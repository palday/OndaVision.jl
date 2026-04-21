"""
    _BRAINVISION_UNIT_MAP

Map of BrainVision unit strings to Onda-compatible lowercase snake_case unit names.
Handles both U+00B5 (MICRO SIGN) and U+03BC (GREEK SMALL LETTER MU).
"""
const _BRAINVISION_UNIT_MAP = Dict{String,String}("" => "microvolt",
                                                  "µV" => "microvolt",       # U+00B5
                                                  "μV" => "microvolt",       # U+03BC
                                                  "uV" => "microvolt",
                                                  "nV" => "nanovolt",
                                                  "mV" => "millivolt",
                                                  "V" => "volt",
                                                  "µS" => "microsiemens",    # U+00B5
                                                  "μS" => "microsiemens",    # U+03BC
                                                  "uS" => "microsiemens",
                                                  "S" => "siemens",
                                                  "C" => "celsius",
                                                  "µV/Hz" => "microvolt_per_hertz",
                                                  "μV/Hz" => "microvolt_per_hertz")

"""
    _normalize_bv_unit(unit::AbstractString) -> String

Convert a BrainVision unit string to an Onda-compatible lowercase snake_case
alphanumeric unit name.

Known units (µV, µS, nV, mV, V, S, C, etc.) are mapped to their full names.
Unknown units are lowercased with non-alphanumeric characters replaced by `_`,
and a warning is emitted.
"""
function _normalize_bv_unit(unit::AbstractString)
    normalized = get(_BRAINVISION_UNIT_MAP, unit, nothing)
    if normalized !== nothing
        return normalized
    end
    # Fallback: lowercase + replace non-alphanumeric with underscore
    result = replace(lowercase(unit), r"[^a-z0-9]" => "_")
    result = replace(result, r"_+" => "_")  # collapse multiple underscores
    result = strip(result, '_')             # strip leading/trailing
    @warn "unknown BrainVision unit \"$unit\"; normalized to \"$result\""
    return result
end

"""
    brainvision_to_signal(vhdr_filename; codepage=nothing, recording=uuid4(),
                          sensor_type="eeg", sensor_label=sensor_type)

Read a BrainVision VHDR header file and return a `Vector{SignalV2}` pointing
to the associated EEG binary data file.

When all channels share the same unit and resolution, a single `SignalV2` is
returned with a standard `"lpcm"` or `"lpcm.vectorized"` file format.

When channels differ in unit or resolution, they are grouped by
`(unit, resolution)` and one `SignalV2` is returned per group.  Each group
uses a [`ChannelSubsetLPCMFormat`](@ref)-backed file format string that
encodes the total channel count and 1-based channel indices so that
`Onda.load` can read the correct channels from the shared binary file.

# Keyword arguments

- `codepage`: character encoding passed through to `read_vhdr`.
  Accepted values are `"UTF-8"` and `"Latin-1"`.
- `recording`: a `UUID` identifying the recording (default: random).
- `sensor_type`: Onda sensor type string (default: `"eeg"`).
- `sensor_label`: Onda sensor label string (default: same as `sensor_type`).
  When multiple groups are produced, `"_\$(unit)"` is appended to
  distinguish them.
"""
function brainvision_to_signal(vhdr_filename;
                               codepage=nothing,
                               recording=uuid4(),
                               sensor_type="eeg",
                               sensor_label=sensor_type)
    vhdr = read_vhdr(vhdr_filename; codepage)
    vhdr_dir = dirname(abspath(vhdr_filename))
    return brainvision_to_signal(vhdr; vhdr_dir, recording, sensor_type, sensor_label)
end

function brainvision_to_signal(vhdr::Dict{String,Any};
                               vhdr_dir::String=".",
                               recording=uuid4(),
                               sensor_type="eeg",
                               sensor_label=sensor_type)
    ci = vhdr["Common Infos"]
    bi = vhdr["Binary Infos"]
    ch = vhdr["Channel Infos"]

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

    # --- Parse channel info ---
    names, resolutions, units = _parse_channel_info(ch, n_channels)

    # Normalize units up front
    normalized_units = [_normalize_bv_unit(u) for u in units]

    # --- Compute sample rate and file info ---
    sampling_interval_us = parse(Float64, ci["SamplingInterval"])
    sample_rate = 1e6 / sampling_interval_us

    # Resolve EEG data file path
    eeg_file = joinpath(vhdr_dir, ci["DataFile"])
    isfile(eeg_file) ||
        error("EEG data file not found: \"$eeg_file\"")

    # Compute total sample count from file size
    T = binary_format == "INT_16" ? Int16 : Float32
    eeg_size = filesize(eeg_file)
    n_values, rem = divrem(eeg_size, sizeof(T))
    rem == 0 ||
        error("EEG data file size ($eeg_size bytes) is not a multiple of the " *
              "sample size ($(sizeof(T)) bytes for BinaryFormat \"$binary_format\")")
    n_total_samples, rem = divrem(n_values, n_channels)
    rem == 0 ||
        error("total number of values ($n_values) in EEG data file is not " *
              "divisible by NumberOfChannels ($n_channels)")

    # --- Group channels by (normalized_unit, resolution) ---
    groups = Dict{Tuple{String,Float64},Vector{Int}}()
    for i in 1:n_channels
        key = (normalized_units[i], resolutions[i])
        push!(get!(Vector{Int}, groups, key), i)
    end

    # --- Determine base file format ---
    base_fmt = data_orientation == "MULTIPLEXED" ? "lpcm" : "lpcm.vectorized"

    # --- Build one SignalV2 per group ---
    onda_sample_type = binary_format == "INT_16" ? "int16" : "float32"
    span = TimeSpan(Nanosecond(0),
                    TimeSpans.time_from_index(sample_rate, n_total_samples + 1))
    multi_group = length(groups) > 1

    signals = SignalV2[]
    for ((unit, resolution), indices) in sort!(collect(groups))
        channel_names = lowercase.(names[indices])

        file_fmt = if length(indices) == n_channels
            base_fmt
        else
            idx_str = join(indices, ',')
            "$(base_fmt).subset.$(n_channels).$(idx_str)"
        end

        label = multi_group ? "$(sensor_label)_$(unit)" : sensor_label

        signal = SignalV2(; recording,
                          file_path=eeg_file,
                          file_format=file_fmt,
                          span,
                          sensor_label=label,
                          sensor_type,
                          channels=channel_names,
                          sample_unit=unit,
                          sample_resolution_in_unit=resolution,
                          sample_offset_in_unit=0.0,
                          sample_type=onda_sample_type,
                          sample_rate)
        push!(signals, signal)
    end

    return signals
end
