"""
    brainvision_annotations(vmrk, sample_rate; recording, channel_names)
    brainvision_annotations(vmrk_filename, sample_rate; recording, codepage, channel_names)
    brainvision_annotations(vhdr_filename; recording, codepage, channel_names)

Convert BrainVision marker data to an Onda-compatible annotation table.

The lowest-level method accepts a pre-parsed VMRK dictionary (as returned by
[`read_vmrk`](@ref)) and an explicit `sample_rate` in Hz.  The file-based
method reads the VMRK file from disk.  The convenience method reads the VHDR
file and automatically locates the VMRK file and derives `sample_rate` from the
`SamplingInterval` key.

# Return value

A `NamedTuple` column table that complies with the `onda.annotation@1` Legolas
schema (i.e. passes `Onda.validate_annotations`).  Columns:

- `recording::Vector{UUID}`: the supplied recording UUID, repeated for every row
- `id::Vector{UUID}`: a fresh random UUID per annotation
- `span::Vector{TimeSpan}`: half-open `[start, stop)` time interval in nanoseconds,
  derived from the marker's 1-based sample position and duration in samples.
  Instantaneous markers (`points == 0`) are given a one-sample span.
- `marker_type::Vector{String}`: raw BrainVision type string (e.g. `"Stimulus"`,
  `"Response"`, `"New Segment"`)
- `description::Vector{String}`: raw description field (e.g. `"S255"`, `""`)
- `channel`: `Vector{Int}` when `channel_names === nothing` (0 means all channels);
  `Vector{Union{String,Missing}}` otherwise (`missing` for channel 0)

# Keyword arguments

- `recording`: a `UUID` for the recording (default: random).
- `codepage`: character encoding forwarded to `read_vhdr` / `read_vmrk`.
- `channel_names`: controls the type of the `channel` output column.
  - `nothing` (default for the low-level methods): keep raw integer channel numbers.
  - `true` (default for the VHDR convenience method): resolve channel numbers to
    lowercase names using the `[Channel Infos]` from the VHDR file.
  - An `AbstractVector{String}` or `AbstractDict{Int,String}`: explicit 1-based
    mapping from channel index to name.
"""
function brainvision_annotations(vmrk::Dict{String,Any}, sample_rate::Real;
                                  recording::UUID=uuid4(),
                                  channel_names=nothing)
    markers = vmrk["Marker Infos"]
    n = length(markers.type)
    ids = [uuid4() for _ in 1:n]
    spans = map(markers.position, markers.points) do pos, pts
        n_pts = max(pts, 1)
        return TimeSpans.time_from_index(sample_rate, pos:(pos + n_pts - 1))
    end
    channel_col = _resolve_channels(markers.channel, channel_names)
    return (recording=fill(recording, n),
            id=ids,
            span=spans,
            marker_type=copy(markers.type),
            description=copy(markers.description),
            channel=channel_col)
end

function brainvision_annotations(vmrk_filename, sample_rate::Real;
                                  recording::UUID=uuid4(),
                                  codepage=nothing,
                                  channel_names=nothing)
    vmrk = read_vmrk(vmrk_filename; codepage)
    return brainvision_annotations(vmrk, sample_rate; recording, channel_names)
end

function brainvision_annotations(vhdr_filename;
                                  recording::UUID=uuid4(),
                                  codepage=nothing,
                                  channel_names=true)
    vhdr = read_vhdr(vhdr_filename; codepage)
    ci = vhdr["Common Infos"]
    sample_rate = 1e6 / parse(Float64, ci["SamplingInterval"])
    vhdr_dir = dirname(abspath(vhdr_filename))
    haskey(ci, "MarkerFile") && !isempty(ci["MarkerFile"]) ||
        error("no MarkerFile key in VHDR [Common Infos]; cannot locate marker file")
    vmrk_file = joinpath(vhdr_dir, ci["MarkerFile"])
    isfile(vmrk_file) ||
        error("marker file \"$(ci["MarkerFile"])\" not found at \"$vmrk_file\"")
    vmrk = read_vmrk(vmrk_file; codepage)
    resolved_names = if channel_names === true
        n_ch = parse(Int, ci["NumberOfChannels"])
        names, _, _ = _parse_channel_info(vhdr["Channel Infos"], n_ch)
        lowercase.(names)
    else
        channel_names
    end
    return brainvision_annotations(vmrk, sample_rate; recording, channel_names=resolved_names)
end

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

"""
    _resolve_channels(channels, channel_names) -> Vector

Return the `channel` output column.  When `channel_names` is `nothing`, return
a copy of the raw integer `channels` vector.  Otherwise map each integer to a
name (or `missing` for channel 0, which denotes "all channels").
"""
function _resolve_channels(channels::Vector{Int}, ::Nothing)
    return copy(channels)
end

function _resolve_channels(channels::Vector{Int}, names::AbstractVector{<:AbstractString})
    return Union{String,Missing}[ch == 0 ? missing : String(names[ch]) for ch in channels]
end

function _resolve_channels(channels::Vector{Int}, names::AbstractDict)
    return Union{String,Missing}[ch == 0 ? missing : String(names[ch]) for ch in channels]
end
