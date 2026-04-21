"""
    _ONDA_TO_BV_UNIT_MAP

Map of Onda-compatible lowercase snake_case unit names to BrainVision unit strings.
This reverses the mapping in `_BRAINVISION_UNIT_MAP` from signal.jl.
"""
const _ONDA_TO_BV_UNIT_MAP = Dict{String,String}("microvolt" => "µV",
                                                 "nanovolt" => "nV",
                                                 "millivolt" => "mV",
                                                 "volt" => "V",
                                                 "microsiemens" => "µS",
                                                 "siemens" => "S",
                                                 "celsius" => "C",
                                                 "microvolt_per_hertz" => "µV/Hz")

"""
    _bv_unit_from_onda(unit::String) -> String

Convert an Onda unit string to a BrainVision unit string.
Known units are mapped; unknown units are returned as-is.
"""
function _bv_unit_from_onda(unit::AbstractString)
    return get(_ONDA_TO_BV_UNIT_MAP, unit, unit)
end

"""
    _julia_sample_type(sample_type::AbstractString) -> DataType

Convert an Onda sample_type string to the corresponding Julia numeric type.
"""
function _julia_sample_type(sample_type::AbstractString)
    sample_type == "int16" && return Int16
    sample_type == "float32" && return Float32
    return error("unsupported sample_type: \"$sample_type\"")
end

"""
    _format_resolution(r::Float64) -> String

Format resolution for VHDR [Channel Infos] section.
Drops trailing .0 for integer values.
"""
function _format_resolution(r::Float64)
    return isinteger(r) ? string(Int(r)) : string(r)
end

# ---------------------------------------------------------------------------
# EEG file writing
# ---------------------------------------------------------------------------

"""
    _write_eeg(io, signals)

Read samples from all signals and write them as a combined MULTIPLEXED binary file.
"""
function _write_eeg(io::IO, signals::AbstractVector)
    T = _julia_sample_type(signals[1].sample_type)
    n_total = sum(length(s.channels) for s in signals)
    n_samp = length(TimeSpans.index_from_time(signals[1].sample_rate, signals[1].span))

    combined = Matrix{T}(undef, n_total, n_samp)
    row = 1
    for signal in signals
        block = Onda.load(signal; encoded=true).data
        nch = size(block, 1)
        combined[row:(row + nch - 1), :] = block
        row += nch
    end

    return write(io, combined)
end

# ---------------------------------------------------------------------------
# VHDR file writing
# ---------------------------------------------------------------------------

"""
    _write_vhdr(io, base_name, signals, metadata, annotations)

Write a BrainVision VHDR header file.
"""
function _write_vhdr(io::IO, base_name::AbstractString, signals::AbstractVector,
                     metadata::Union{BrainVisionMetadata,Nothing},
                     annotations)
    # --- Reconstruct channel info ---
    all_channels = vcat([s.channels for s in signals]...)
    all_units = vcat([fill(s.sample_unit, length(s.channels)) for s in signals]...)
    all_resols = vcat([fill(s.sample_resolution_in_unit, length(s.channels))
                       for s in signals]...)

    # Original-case names and references
    if metadata !== nothing
        channel_names = metadata.channel_names
        channel_refs = metadata.channel_references
    else
        # Use lowercase names from signals (guaranteed unique) and empty references
        channel_names = collect(all_channels)
        channel_refs = fill("", length(all_channels))
    end

    n_channels = length(all_channels)
    sample_rate = signals[1].sample_rate
    sample_type = signals[1].sample_type

    # --- Write header ---
    println(io, "Brain Vision Data Exchange Header File Version 1.0")
    println(io, "; Written by OndaVision.jl")
    println(io)

    println(io, "[Common Infos]")
    println(io, "DataFile=$(base_name).eeg")
    if annotations !== nothing
        println(io, "MarkerFile=$(base_name).vmrk")
    end
    println(io, "DataFormat=BINARY")
    println(io, "DataOrientation=MULTIPLEXED")
    println(io, "NumberOfChannels=$n_channels")
    sampling_interval_us = round(Int, 1e6 / sample_rate)
    println(io, "SamplingInterval=$sampling_interval_us")
    println(io, "Codepage=UTF-8")
    println(io)

    println(io, "[Binary Infos]")
    binary_fmt = sample_type == "int16" ? "INT_16" : "IEEE_FLOAT_32"
    println(io, "BinaryFormat=$binary_fmt")
    println(io)

    println(io, "[Channel Infos]")
    for i in 1:n_channels
        ch_name = channel_names[i]
        ch_ref = channel_refs[i]
        ch_resol = _format_resolution(all_resols[i])
        ch_unit = _bv_unit_from_onda(all_units[i])
        println(io, "Ch$i=$ch_name,$ch_ref,$ch_resol,$ch_unit")
    end
    println(io)

    # --- Write optional [Coordinates] section ---
    if metadata !== nothing && !isempty(metadata.coordinates.channel)
        println(io, "[Coordinates]")
        coords = metadata.coordinates
        for i in 1:length(coords.channel)
            println(io, "Ch$i=$(coords.radius[i]),$(coords.theta[i]),$(coords.phi[i])")
        end
        println(io)
    end

    # --- Write optional [Comment] section ---
    if metadata !== nothing && !isempty(metadata.comment)
        println(io, "[Comment]")
        println(io, metadata.comment)
        println(io)
    end

    # --- Write optional [User Infos] section ---
    if metadata !== nothing && !isempty(metadata.user_infos)
        println(io, "[User Infos]")
        for (key, value) in metadata.user_infos
            println(io, "$key=$value")
        end
        println(io)
    end

    # --- Write optional [Channel User Infos] section ---
    if metadata !== nothing && !isempty(metadata.channel_user_infos)
        println(io, "[Channel User Infos]")
        for (key, value) in metadata.channel_user_infos
            println(io, "$key=$value")
        end
        println(io)
    end

    return nothing
end

# ---------------------------------------------------------------------------
# VMRK file writing
# ---------------------------------------------------------------------------

"""
    _write_vmrk(io, base_name, annotations, metadata, sample_rate, channel_names)

Write a BrainVision VMRK marker file.
"""
function _write_vmrk(io::IO, base_name::AbstractString, annotations, metadata,
                     sample_rate::Real, channel_names::AbstractVector{<:AbstractString})
    # --- Write header ---
    println(io, "Brain Vision Data Exchange Marker File, Version 1.0")
    println(io, "; Written by OndaVision.jl")
    println(io)

    println(io, "[Common Infos]")
    println(io, "DataFile=$(base_name).eeg")
    println(io, "Codepage=UTF-8")
    println(io)

    println(io, "[Marker Infos]")

    # Determine if first annotation is already "New Segment"
    has_initial_segment = !isempty(annotations.marker_type) &&
                          annotations.marker_type[1] == "New Segment"

    mk_num = 1

    # Write "New Segment" marker at position 1 if not already present
    if !has_initial_segment
        date_str = ""
        if metadata !== nothing && !isempty(metadata.marker_dates)
            first_date = metadata.marker_dates[1]
            if first_date !== missing
                date_str = ",$first_date"
            end
        end
        println(io, "Mk$mk_num=New Segment,,1,1,0$date_str")
        mk_num += 1
    end

    # Write user annotations
    if length(annotations.marker_type) > 0
        for i in eachindex(annotations.marker_type)
            marker_type = annotations.marker_type[i]
            description = annotations.description[i]

            # Compute position and points from span
            rng = TimeSpans.index_from_time(sample_rate, annotations.span[i])
            position = first(rng)
            n_samp = length(rng)
            points = n_samp == 1 ? 0 : n_samp

            # Resolve channel
            ch = annotations.channel[i]
            ch_num = if ch isa Missing || ch == 0
                0
            elseif ch isa AbstractString
                idx = findfirst(==(ch), channel_names)
                idx !== nothing ? idx : 0
            else
                Int(ch)
            end

            # Date field (optional)
            date_str = ""
            # Only use marker_dates if we didn't add a synthetic "New Segment"
            if !has_initial_segment && metadata !== nothing &&
               length(metadata.marker_dates) > i
                marker_date = metadata.marker_dates[i + 1]  # +1 because synthetic segment is at index 1
                if marker_date !== missing
                    date_str = ",$marker_date"
                end
            elseif has_initial_segment && metadata !== nothing &&
                   length(metadata.marker_dates) >= i
                marker_date = metadata.marker_dates[i]
                if marker_date !== missing
                    date_str = ",$marker_date"
                end
            end

            println(io,
                    "Mk$mk_num=$marker_type,$description,$position,$points,$ch_num$date_str")
            mk_num += 1
        end
    end

    return nothing
end

# ---------------------------------------------------------------------------
# Top-level API
# ---------------------------------------------------------------------------

"""
    write_brainvision(base_path, signals; annotations=nothing, metadata=nothing)

Write Onda signals and optional annotations to a BrainVision recording.

# Arguments

- `base_path::AbstractString`: path prefix (e.g. `"/tmp/subj01"` or `"/tmp/subj01.vhdr"`).
  The extension is stripped if present. Three files are written:
  `<base>.vhdr`, `<base>.eeg`, and optionally `<base>.vmrk`.
- `signals::AbstractVector{SignalV2}`: one or more signal descriptors. All signals must
  share the same `sample_rate` and `sample_type`.
- `annotations::Union{NamedTuple,Nothing}`: optional Onda annotation table as returned
  by [`brainvision_annotations`](@ref). When provided, a VMRK file is written.
  Default: `nothing` (no markers).
- `metadata::Union{BrainVisionMetadata,Nothing}`: optional metadata struct as returned
  by [`read_brainvision_onda`](@ref). Used to recover original-case channel names,
  references, coordinates, and comment blocks. Default: `nothing`.

# Returns

The path to the written `.vhdr` file as a `String`.

# Validation

- All signals must have the same `sample_rate` and `sample_type`.
- All signals must describe the same time span.
"""
function write_brainvision(base_path, signals::AbstractVector;
                                annotations=nothing,
                                metadata::Union{BrainVisionMetadata,Nothing}=nothing)
    # --- Validate early ---
    isempty(signals) && error("signals vector cannot be empty")
    sample_rate = signals[1].sample_rate
    sample_type = signals[1].sample_type
    span = signals[1].span

    for sig in signals[2:end]
        sig.sample_rate == sample_rate ||
            error("all signals must have the same sample_rate")
        sig.sample_type == sample_type ||
            error("all signals must have the same sample_type")
        sig.span == span ||
            error("all signals must describe the same time span")
    end

    # --- Normalize base path ---
    base_str = string(base_path)
    base = if endswith(base_str, ".vhdr")
        base_str[1:(end - 5)]
    elseif endswith(base_str, ".vmrk") || endswith(base_str, ".eeg")
        base_str[1:(end - 4)]
    else
        base_str
    end
    base_name = basename(base)

    # --- Reconstruct channel names for VMRK ---
    all_channels = vcat([s.channels for s in signals]...)
    if metadata !== nothing
        channel_names = metadata.channel_names
    else
        # Use lowercase names from signals (guaranteed unique)
        channel_names = collect(all_channels)
    end

    # --- Write EEG file ---
    eeg_path = base * ".eeg"
    open(eeg_path, "w") do io
        return _write_eeg(io, signals)
    end

    # --- Write VHDR file ---
    vhdr_path = base * ".vhdr"
    open(vhdr_path, "w") do io
        return _write_vhdr(io, base_name, signals, metadata, annotations)
    end

    # --- Write VMRK file (optional) ---
    if annotations !== nothing
        vmrk_path = base * ".vmrk"
        open(vmrk_path, "w") do io
            return _write_vmrk(io, base_name, annotations, metadata, sample_rate,
                               channel_names)
        end
    end

    return vhdr_path
end
