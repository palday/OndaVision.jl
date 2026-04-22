"""
    _VMRK_IDENTIFICATION_RE

Regular expression that matches the mandatory first line of a VMRK file.
Accepts the canonical spelling `"BrainVision"`, the legacy form `"Brain Vision"`,
and variants with or without a comma before `"Version"`.
"""
const _VMRK_IDENTIFICATION_RE = r"^Brain ?Vision Data Exchange Marker File,? Version \d+\.\d+"

"""
    _REQUIRED_VMRK_COMMON_INFOS_KEYS

Keys that the BVCDF 1.0 specification marks as mandatory in the `[Common Infos]`
section of a VMRK file.
"""
const _REQUIRED_VMRK_COMMON_INFOS_KEYS = ("DataFile",)

"""
    _MARKER_COLS

Column names for the `[Marker Infos]` table parsed by `read_vmrk` and
filtered by [`get_segments`](@ref):
`type`, `description`, `position`, `points`, `channel`, `date`.
"""
const _MARKER_COLS = (:type, :description, :position, :points, :channel, :date)

"""
    read_vmrk(filename)
    read_vmrk(io::IO)

Returns a dictionary of entries from a BrainVision VMRK marker file.

`filename` may be any entity with an appropriate `open` method.

The BrainVision VMRK format is similar to the Windows INI configuration format.
The `[Marker Infos]` section is parsed into a Tables.jl-compatible `NamedTuple`
column table with columns `type`, `description`, `position`, `points`, `channel`,
and `date`.

# Return value

Returns a `Dict{String, Any}` with the following structure:
- `"identification"`: the identification line string
- `"Common Infos"`: a `Dict{String, String}` of key-value pairs
- `"Marker Infos"`: a `NamedTuple` column table (see below)
- Any additional sections map to `Dict{String, String}`

The `"Marker Infos"` table has columns:
- `type::Vector{String}`: marker type (e.g. `"Stimulus"`, `"Response"`)
- `description::Vector{String}`: marker description (may be empty)
- `position::Vector{Int}`: 1-based sample position
- `points::Vector{Int}`: duration in samples (0 = instantaneous)
- `channel::Vector{Int}`: channel number (0 = applies to all channels)
- `date::Vector{Union{String,Missing}}`: optional recording timestamp; `missing` when absent

# Format notes

- Lines beginning with `;` are comments and are ignored.
- Files without a `Codepage` key are assumed to be Latin-1 encoded.
"""
function read_vmrk(filename; kwargs...)
    return open(filename, "r") do io
        return read_vmrk(io; kwargs...)
    end
end

function read_vmrk(io::IO; codepage::Union{AbstractString,Nothing}=nothing)
    if !isnothing(codepage) && codepage ∉ _SUPPORTED_CODEPAGES
        throw(ArgumentError("unsupported codepage \"$codepage\"; " *
                            "supported values are: " *
                            join(repr.(_SUPPORTED_CODEPAGES), ", ")))
    end
    bytes = read(io)
    cp = @something(codepage, _detect_codepage(bytes))
    content = cp == "UTF-8" ? String(copy(bytes)) : _latin1_to_utf8(bytes)
    return _parse_vmrk(content)
end

"""
    _parse_vmrk(content) -> Dict{String,Any}

Parse a decoded (UTF-8) VMRK string into a nested `Dict`, validating
structural requirements from the BVCDF 1.0 specification along the way.

The identification line is stored under `"identification"`.  `[Common Infos]`
becomes a `Dict{String,String}`.  `[Marker Infos]` is parsed into a typed
`NamedTuple` column table via [`_parse_marker_infos`](@ref).  Any additional
sections are passed through as `Dict{String,String}`.
"""
function _parse_vmrk(content::String)
    result = Dict{String,Any}()

    lines = split(content, r"\r?\n")

    # The very first line must be the identification line.
    identification = rstrip(lines[1])
    isempty(identification) && error("VMRK file is empty")
    if !occursin(_VMRK_IDENTIFICATION_RE, identification)
        error("unrecognised VMRK identification line: \"$identification\"\n" *
              "expected a line matching: $_VMRK_IDENTIFICATION_RE")
    end
    result["identification"] = identification

    current_section = nothing
    raw_sections = Dict{String,Dict{String,String}}()

    for line in @view lines[2:end]
        line = rstrip(line)

        # Skip INI-style comment lines and blank lines.
        (startswith(line, ";") || isempty(line)) && continue

        # Section header?
        if startswith(line, "[")
            close_idx = findfirst(']', line)
            if close_idx !== nothing
                current_section = line[2:(close_idx - 1)]
                raw_sections[current_section] = Dict{String,String}()
            end
            continue
        end

        # Key=value pair.
        if current_section !== nothing
            eq_idx = findfirst('=', line)
            if eq_idx !== nothing
                key = line[1:(eq_idx - 1)]
                value = line[(eq_idx + 1):end]
                raw_sections[current_section][key] = value
            end
        end
    end

    _validate_vmrk(raw_sections)

    result["Common Infos"] = raw_sections["Common Infos"]
    result["Marker Infos"] = _parse_marker_infos(raw_sections["Marker Infos"])

    # Pass through any additional sections as-is.
    for (section, entries) in raw_sections
        section in ("Common Infos", "Marker Infos") && continue
        result[section] = entries
    end

    return result
end

"""
    _validate_vmrk(raw_sections)

Post-parse structural validation for a parsed VMRK file.  Checks that
`[Common Infos]` and `[Marker Infos]` sections are present and that all
mandatory `[Common Infos]` keys exist.  Warns (rather than errors) if
`Codepage` is absent.
"""
function _validate_vmrk(raw_sections::Dict{String,Dict{String,String}})
    # --- Mandatory sections ---
    for section in ("Common Infos", "Marker Infos")
        haskey(raw_sections, section) ||
            error("mandatory section [$section] is missing from the VMRK file")
    end

    ci = raw_sections["Common Infos"]

    # --- Mandatory Common Infos keys ---
    for key in _REQUIRED_VMRK_COMMON_INFOS_KEYS
        # TODO: use setdiff to validate all keys at once and give a comprehensive error message
        haskey(ci, key) ||
            error("mandatory key \"$key\" is missing from [Common Infos]")
    end

    # Codepage is mandatory per spec but absent in old-style files; warn rather than error.
    if !haskey(ci, "Codepage")
        @warn "\"Codepage\" key is missing from [Common Infos]; assuming Latin-1 encoding"
    end

    return nothing
end

"""
    _parse_marker_infos(entries) -> NamedTuple

Parse the raw `Dict{String,String}` of `[Marker Infos]` key-value pairs
into a typed `NamedTuple` column table with columns matching `_MARKER_COLS`.

Each entry has the form `Mk<N>=<type>,<description>,<position>,<points>,<channel>[,<date>]`.
Validates that keys form the consecutive sequence `Mk1`…`MkN` and that all
integer fields are valid; the optional `date` field becomes `missing` when absent.
"""
function _parse_marker_infos(entries::Dict{String,String})
    n = length(entries)

    # Validate that all keys match Mk<N> and are the consecutive sequence Mk1..MkN.
    for key in keys(entries)
        occursin(r"^Mk\d+$", key) ||
            error("unexpected key \"$key\" in [Marker Infos]; expected only Mk<N> entries")
    end
    for i in 1:n
        haskey(entries, "Mk$i") ||
            error("marker entry \"Mk$i\" is missing from [Marker Infos] " *
                  "(found $n markers, expected consecutive numbering from Mk1)")
    end

    types = String[]
    descriptions = String[]
    positions = Int[]
    points_list = Int[]
    channels = Int[]
    dates = Union{String,Missing}[]

    for i in 1:n
        value = entries["Mk$i"]
        parts = split(value, ',')
        length(parts) < 5 &&
            error("marker Mk$i has fewer than 5 comma-separated fields: \"$value\"")

        push!(types, String(parts[1]))
        push!(descriptions, String(parts[2]))

        pos_str = strip(parts[3])
        pos = tryparse(Int, pos_str)
        isnothing(pos) &&
            error("position in Mk$i is not a valid integer: \"$pos_str\"")
        pos > 0 ||
            error("position in Mk$i must be > 0, got $pos")
        push!(positions, pos)

        pts_str = strip(parts[4])
        pts = tryparse(Int, pts_str)
        isnothing(pts) &&
            error("points in Mk$i is not a valid integer: \"$pts_str\"")
        pts >= 0 ||
            error("points in Mk$i must be >= 0, got $pts")
        push!(points_list, pts)

        ch_str = strip(parts[5])
        ch = tryparse(Int, ch_str)
        isnothing(ch) &&
            error("channel number in Mk$i is not a valid integer: \"$ch_str\"")
        push!(channels, ch)

        date_val = length(parts) >= 6 ? strip(parts[6]) : ""
        push!(dates, isempty(date_val) ? missing : String(date_val))
    end

    return NamedTuple{_MARKER_COLS}((types, descriptions, positions, points_list,
                                     channels, dates))
end

"""
    get_segments(vmrk::Dict{String,Any}) -> NamedTuple

Extract the "New Segment" markers from the return value of [`read_vmrk`](@ref).

Each "New Segment" marker records the start of a new continuous recording
block.  The `date` field, when present, contains the recording timestamp in
the format `YYYYMMDDhhmmssμμμμμμ` (year, month, day, hour, minute, second,
microsecond).

Returns a Tables.jl-compatible `NamedTuple` column table with the same
columns as `"Marker Infos"` (`type`, `description`, `position`, `points`,
`channel`, `date`), containing only the rows where `type == "New Segment"`.
"""
function get_segments(vmrk::Dict{String,Any})
    markers = vmrk["Marker Infos"]
    idx = findall(==("New Segment"), markers.type)
    return NamedTuple{_MARKER_COLS}((markers.type[idx], markers.description[idx],
                                     markers.position[idx], markers.points[idx],
                                     markers.channel[idx], markers.date[idx]))
end
