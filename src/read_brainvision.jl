"""
    read_brainvision(filename; codepage=nothing)

Read a BrainVision recording from a VHDR header file, returning the sample data
as a numeric array after applying per-channel resolution scaling.

`filename` must be a path to a `.vhdr` header file.  The EEG data file and
(optionally) the marker file are resolved relative to the directory containing
the VHDR file.

# Keyword arguments

- `codepage`: character encoding passed through to `read_vhdr` and `read_vmrk`.
  Accepted values are `"UTF-8"` and `"Latin-1"`.  When `nothing` (the default),
  the encoding is auto-detected from each file.

# Return value

The return type depends on the number and lengths of "New Segment" markers found
in the marker file:

- **No marker file, or a single "New Segment" marker**: returns a
  `Matrix{Float64}` of shape `(n_channels, n_samples)`.
- **Multiple "New Segment" markers with equal segment lengths**: returns an
  `Array{Float64, 3}` of shape `(n_channels, segment_length, n_segments)`.
- **Multiple "New Segment" markers with unequal segment lengths**: returns a
  `Vector{Matrix{Float64}}`, one matrix per segment, each of shape
  `(n_channels, segment_samples)`.

All values are in the physical unit specified by the channel info (typically µV),
with the per-channel resolution factor from the VHDR `[Channel Infos]` section
applied.

# Supported formats

- `DataFormat`: `BINARY`
- `DataOrientation`: `MULTIPLEXED` or `VECTORIZED`
- `BinaryFormat`: `INT_16` or `IEEE_FLOAT_32`
- `DataType`: `TIMEDOMAIN` (default when key is absent)
"""
function read_brainvision(vhdr_filename; codepage=nothing)
    vhdr = read_vhdr(vhdr_filename; codepage)
    ci   = vhdr["Common Infos"]
    bi   = vhdr["Binary Infos"]
    ch   = vhdr["Channel Infos"]

    # --- Validate supported format fields ---
    data_format = ci["DataFormat"]
    data_format == "BINARY" ||
        error("unsupported DataFormat \"$data_format\"; only \"BINARY\" is supported")

    data_orientation = ci["DataOrientation"]
    data_orientation in ("MULTIPLEXED", "VECTORIZED") ||
        error("unsupported DataOrientation \"$data_orientation\"; " *
              "expected \"MULTIPLEXED\" or \"VECTORIZED\"")

    binary_format = bi["BinaryFormat"]
    binary_format in ("INT_16", "IEEE_FLOAT_32") ||
        error("unsupported BinaryFormat \"$binary_format\"; " *
              "expected \"INT_16\" or \"IEEE_FLOAT_32\"")

    if haskey(ci, "DataType")
        data_type = ci["DataType"]
        data_type == "TIMEDOMAIN" ||
            error("unsupported DataType \"$data_type\"; only \"TIMEDOMAIN\" is supported")
    end

    n_channels = parse(Int, ci["NumberOfChannels"])

    # --- Resolve file paths ---
    vhdr_dir = dirname(abspath(vhdr_filename))
    eeg_file = joinpath(vhdr_dir, ci["DataFile"])
    isfile(eeg_file) ||
        error("EEG data file not found: \"$eeg_file\"")

    # --- Read and validate marker file ---
    vmrk = nothing
    if haskey(ci, "MarkerFile") && !isempty(ci["MarkerFile"])
        vmrk_file = joinpath(vhdr_dir, ci["MarkerFile"])
        if isfile(vmrk_file)
            vmrk = read_vmrk(vmrk_file; codepage)
            _check_vhdr_vmrk_consistency(ci, vmrk["Common Infos"])
        else
            @warn "marker file \"$(ci["MarkerFile"])\" referenced in VHDR not found at " *
                  "\"$vmrk_file\"; proceeding without marker information"
        end
    end

    # --- Parse per-channel resolution factors ---
    resolutions = _parse_resolutions(ch, n_channels)

    # --- Read binary sample data ---
    T = binary_format == "INT_16" ? Int16 : Float32
    bytes = read(eeg_file)
    nb    = length(bytes)
    nb % sizeof(T) == 0 ||
        error("EEG data file size ($nb bytes) is not a multiple of the sample " *
              "size ($(sizeof(T)) bytes for BinaryFormat \"$binary_format\")")
    raw = ltoh.(reinterpret(T, bytes))

    n_total, rem = divrem(length(raw), n_channels)
    rem == 0 ||
        error("total number of values ($(length(raw))) in EEG data file is not " *
              "divisible by NumberOfChannels ($n_channels)")

    # --- Reshape to (n_channels × n_samples) ---
    if data_orientation == "MULTIPLEXED"
        # Binary layout: ch1_t1, ch2_t1, …, chN_t1, ch1_t2, …
        # Julia column-major reshape reads columns first → correct directly.
        data = reshape(Float64.(raw), n_channels, n_total)
    else  # VECTORIZED
        # Binary layout: ch1_t1, ch1_t2, …, ch1_tN, ch2_t1, …
        # reshape to (n_samples, n_channels) then permute dims.
        data = permutedims(reshape(Float64.(raw), n_total, n_channels))
    end

    # --- Apply per-channel resolution scaling ---
    # resolutions is a (n_channels,) vector; broadcasting multiplies row i by resolutions[i].
    data .*= resolutions

    # --- Segment dispatch ---
    if vmrk === nothing
        return data   # 2D, no marker file
    end

    segments = get_segments(vmrk)
    n_segs   = length(segments.position)

    n_segs <= 1 && return data   # 0 or 1 segment → 2D

    # Compute per-segment boundaries (1-based sample indices).
    positions = segments.position
    starts = positions
    ends   = vcat(positions[2:end] .- 1, [n_total])
    lengths = ends .- starts .+ 1

    if allequal(lengths)
        return _make_3d(data, starts, ends, lengths[1], n_segs)
    else
        return _split_segments(data, starts, ends, n_segs)
    end
end

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

# Parse the resolution factor from each Ch<N> entry in [Channel Infos].
# Format: <name>,<ref>,<resolution>[,<unit>][,...]
# Missing or empty resolution → defaults to 1.0.
function _parse_resolutions(ch_info::Dict{String,String}, n_channels::Int)
    resolutions = Vector{Float64}(undef, n_channels)
    for i in 1:n_channels
        entry  = ch_info["Ch$i"]
        parts  = split(entry, ',')
        res_str = length(parts) >= 3 ? strip(parts[3]) : ""
        resolutions[i] = isempty(res_str) ? 1.0 : parse(Float64, res_str)
    end
    return resolutions
end

# Cross-check shared fields between the VHDR and VMRK Common Infos sections.
# Inconsistencies trigger a @warn; VHDR values take precedence.
function _check_vhdr_vmrk_consistency(vhdr_ci::Dict{String,String},
                                      vmrk_ci::Dict{String,String})
    vhdr_df = vhdr_ci["DataFile"]
    vmrk_df = get(vmrk_ci, "DataFile", nothing)
    if vmrk_df !== nothing && vmrk_df != vhdr_df
        @warn "DataFile in VMRK (\"$vmrk_df\") differs from VHDR (\"$vhdr_df\"); " *
              "using the value from the VHDR file"
    end

    vhdr_cp = get(vhdr_ci, "Codepage", nothing)
    vmrk_cp = get(vmrk_ci, "Codepage", nothing)
    if vhdr_cp !== nothing && vmrk_cp !== nothing && vhdr_cp != vmrk_cp
        @warn "Codepage in VMRK (\"$vmrk_cp\") differs from VHDR (\"$vhdr_cp\"); " *
              "using the value from the VHDR file"
    end

    return nothing
end

# Build an (n_channels × seg_len × n_segs) 3-D array from contiguous slices of data.
# Assumes all segment lengths are equal (caller must verify).
function _make_3d(data::Matrix{Float64},
                  starts::Vector{Int}, ends::Vector{Int},
                  seg_len::Int, n_segs::Int)
    n_channels = size(data, 1)
    result = Array{Float64,3}(undef, n_channels, seg_len, n_segs)
    for s in 1:n_segs
        result[:, :, s] = data[:, starts[s]:ends[s]]
    end
    return result
end

# Return a Vector of 2-D matrices, one per segment (for unequal-length segments).
function _split_segments(data::Matrix{Float64},
                         starts::Vector{Int}, ends::Vector{Int},
                         n_segs::Int)
    return [data[:, starts[s]:ends[s]] for s in 1:n_segs]
end
