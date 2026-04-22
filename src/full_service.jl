"""
    BrainVisionMetadata

BrainVision-specific recording and channel metadata that has no counterpart in
the Onda signal or annotation schemas.

Fields are grouped into four categories:

**Per-channel supplementary** (parallel to the full `[Channel Infos]` list,
VHDR order, 1-based):
- `channel_names::Vector{String}`: original-case channel names from VHDR.
- `channel_references::Vector{String}`: reference-channel field from
  `[Channel Infos]`; `""` when absent.
- `coordinates::NamedTuple`: column table `(; channel, radius, theta, phi)`
  from the `[Coordinates]` section.  Zero-length vectors when the section is
  absent; use `isempty(metadata.coordinates.channel)` to check.

**Recording conditions** (parsed from the `[Comment]` free-text block):
- `amplifier_info::Dict{String,String}`: recording-level key-value pairs from
  the "Amplifier Setup" sub-section (e.g. `"Sampling Rate [Hz]"`); empty when
  absent.
- `amplifier_channels::NamedTuple`: per-channel hardware configuration table
  with columns `number`, `name`, `phys_chn`, `resolution`, `low_cutoff`,
  `high_cutoff`, `notch`; zero-length rows when absent.
- `software_filters::NamedTuple`: per-channel software filter table; columns
  are `number`, `low_cutoff`, `high_cutoff`, `notch` (optionally with `name`
  inserted after `number` when amplifier channel names are available);
  zero-length rows when absent or disabled.
- `impedances::Dict{String,Union{Float64,Missing}}`: per-channel/electrode
  impedance measurements in kOhm; `missing` for unknown values (`???` in
  file); empty when absent.

**Free-form / generic metadata**:
- `comment::String`: raw `[Comment]` section text; `""` when absent.
- `user_infos::Dict{String,String}`: `[User Infos]` key-value pairs
  (BrainVision v2.0+); empty otherwise.
- `channel_user_infos::Dict{String,String}`: `[Channel User Infos]` key-value
  pairs (BrainVision v2.0+); empty otherwise.

**Marker supplement**:
- `marker_dates::Vector{Union{String,Missing}}`: the `date` column from the
  VMRK `[Marker Infos]` table, in the same order as the `annotations` table
  returned by [`read_brainvision_onda`](@ref).  Empty when no marker file is
  present.  Dates are strings of the form `YYYYMMDDhhmmssμμμμμμ`; `missing`
  when the field is absent for a given marker.
"""
struct BrainVisionMetadata
    channel_names::Vector{String}
    # TODO: use channel references when creating the Onda names for the relevant channels
    channel_references::Vector{String}
    coordinates::NamedTuple
    amplifier_info::Dict{String,String}
    amplifier_channels::NamedTuple
    software_filters::NamedTuple
    impedances::Dict{String,Union{Float64,Missing}}
    comment::String
    user_infos::Dict{String,String}
    channel_user_infos::Dict{String,String}
    marker_dates::Vector{Union{String,Missing}}
end

# TODO handle oddity around BV specifying high-pass filters in seconds, see https://github.com/mne-tools/mne-python/issues/4998

"""
    read_brainvision_onda(vhdr_filename; codepage=nothing, recording=uuid4(),
                          sensor_type="eeg", sensor_label=sensor_type)

Read a BrainVision recording from a VHDR header file and return a named tuple
`(; signals, annotations, metadata)` containing:

- `signals::Vector{SignalV2}`: Onda signal descriptors (see
  [`brainvision_to_signal`](@ref)).
- `annotations::NamedTuple`: Onda-compliant annotation table (see
  [`brainvision_annotations`](@ref)); passes `Onda.validate_annotations`.
  Empty (zero-row) when no marker file is found.
- `metadata::`[`BrainVisionMetadata`](@ref): all BrainVision-specific
  information that has no counterpart in the Onda schemas, including electrode
  coordinates, hardware/software filter settings, impedances, and recording
  comments.

The VHDR file is read once; the VMRK is read at most once.  All keyword
arguments are forwarded as documented below.

# Keyword arguments

- `codepage`: character encoding passed to `read_vhdr`/`read_vmrk`.
  Accepted values are `"UTF-8"` and `"Latin-1"`.
- `recording`: a `UUID` identifying the recording (default: random).
  The same UUID is embedded in every `SignalV2` and in every annotation row.
- `sensor_type`: Onda sensor type string (default: `"eeg"`).
- `sensor_label`: Onda sensor label string (default: same as `sensor_type`).
"""
function read_brainvision_onda(vhdr_filename;
                               codepage=nothing,
                               recording=uuid4(),
                               sensor_type="eeg",
                               sensor_label=sensor_type)
    vhdr = read_vhdr(vhdr_filename; codepage)
    ci = vhdr["Common Infos"]
    ch = vhdr["Channel Infos"]
    n_channels = parse(Int, ci["NumberOfChannels"])
    sample_rate = 1e6 / parse(Float64, ci["SamplingInterval"])

    # --- Read marker file (optional) ---
    vmrk = nothing
    if haskey(ci, "MarkerFile") && !isempty(ci["MarkerFile"])
        vhdr_dir = dirname(abspath(vhdr_filename))
        vmrk_file = joinpath(vhdr_dir, ci["MarkerFile"])
        if isfile(vmrk_file)
            vmrk = read_vmrk(vmrk_file; codepage)
        end
    end

    # --- Signals ---
    vhdr_dir = dirname(abspath(vhdr_filename))
    signals = brainvision_to_signal(vhdr; vhdr_dir, recording, sensor_type, sensor_label)

    # --- Annotations and marker dates ---
    channel_names_orig, _, _ = _parse_channel_info(ch, n_channels)
    resolved_names = lowercase.(channel_names_orig)

    annotations, marker_dates = if !isnothing(vmrk)
        ann = brainvision_annotations(vmrk, sample_rate; recording,
                                      channel_names=resolved_names)
        dates = copy(vmrk["Marker Infos"].date)
        (ann, dates)
    else
        empty_ann = (; recording=UUID[], id=UUID[], span=TimeSpan[],
                     marker_type=String[], description=String[],
                     channel=Union{String,Missing}[])
        (empty_ann, Union{String,Missing}[])
    end

    # --- Metadata ---
    comment = get(vhdr, "Comment", "")::String
    amp_result = parse_amplifier_setup(comment)
    amp_info, amp_channels = if isnothing(amp_result)
        (Dict{String,String}(),
         _empty_column_table(_AMP_CHANNEL_COLS))
    else
        info, chans = amp_result
        ch_nt = @something(chans, _empty_column_table(_AMP_CHANNEL_COLS))
        (info, ch_nt)
    end

    sw_result = parse_software_filters(comment)
    sw_filters = @something(sw_result,
                            _empty_column_table(_SW_FILTER_COLS_BASE))

    imp_result = parse_impedances(comment)
    impedances = @something(imp_result, Dict{String,Union{Float64,Missing}}())

    metadata = BrainVisionMetadata(channel_names_orig,
                                   _parse_channel_references(ch, n_channels),
                                   _parse_coordinates(get(vhdr, "Coordinates", nothing),
                                                      ch, n_channels),
                                   amp_info,
                                   amp_channels,
                                   sw_filters,
                                   impedances,
                                   comment,
                                   get(vhdr, "User Infos", Dict{String,String}()),
                                   get(vhdr, "Channel User Infos", Dict{String,String}()),
                                   marker_dates)

    return (; signals, annotations, metadata)
end
