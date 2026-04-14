# Matches both the canonical form ("BrainVision") and the legacy form ("Brain Vision").
const _IDENTIFICATION_RE = r"^Brain ?Vision Data Exchange Header File Version \d+\.\d+"

# Keys that the spec marks as mandatory in their respective sections.
const _REQUIRED_COMMON_INFOS_KEYS = ("DataFile", "DataFormat", "DataOrientation",
                                     "NumberOfChannels", "SamplingInterval")
const _REQUIRED_BINARY_INFOS_KEYS = ("BinaryFormat",)

# Column names for the Amplifier Setup channel table (fixed, position-based).
const _AMP_CHANNEL_COLS = (:number, :name, :phys_chn, :resolution, :low_cutoff,
                           :high_cutoff, :notch)

# Column names for the Software Filters table, without and with channel names.
const _SW_FILTER_COLS_BASE = (:number, :low_cutoff, :high_cutoff, :notch)
const _SW_FILTER_COLS_WITH_NAMES = (:number, :name, :low_cutoff, :high_cutoff, :notch)

"""
    read_vhdr(filename; codepage=nothing)
    read_vhdr(io::IO; codepage=nothing)

Returns a nested dictionary of configuration entries from a BrainVision VHDR file.

`filename` may be any entity with an appropriate `open` method.

The BrainVision VHDR format is similar to the Windows INI configuration format, but
has a few additional extensions.

# Keyword arguments

- `codepage`: the character encoding to use when decoding the file. Accepted values are
  `"UTF-8"` and `"Latin-1"`. When `nothing` (the default), the encoding is determined
  automatically from the `Codepage` key in the file, falling back to `"Latin-1"` if the
  key is absent.

# Return value

Returns a `Dict{String, Any}` with the following structure:
- `"identification"`: the identification line string (e.g. `"BrainVision Data Exchange Header File Version 1.0"`)
- Each section name maps to a `Dict{String, String}` of key-value pairs, except the
  `"Comment"` section which maps to a raw `String` of arbitrary text.

# Format notes

- Lines beginning with `;` are comments and are ignored (except inside `[Comment]`).
- The `[Comment]` section contains arbitrary free-form text.
- Files without a `Codepage` key are assumed to be Latin-1 encoded.
"""
function read_vhdr(filename; kwargs...)
    return open(filename, "r") do io
        return read_vhdr(io; kwargs...)
    end
end

function read_vhdr(io::IO; codepage::Union{AbstractString,Nothing}=nothing)
    if codepage !== nothing && codepage ∉ _SUPPORTED_CODEPAGES
        throw(ArgumentError("unsupported codepage \"$codepage\"; " *
                            "supported values are: " *
                            join(repr.(_SUPPORTED_CODEPAGES), ", ")))
    end
    bytes = read(io)
    cp = codepage === nothing ? _detect_codepage(bytes) : codepage
    content = cp == "UTF-8" ? String(copy(bytes)) : _latin1_to_utf8(bytes)
    return _parse_vhdr(content)
end

# Parse a decoded (UTF-8) VHDR string into a nested Dict, validating structural
# requirements from the BVCDF 1.0 specification along the way.
function _parse_vhdr(content::String)
    result = Dict{String,Any}()

    # Split on any line ending (CRLF or LF)
    lines = split(content, r"\r?\n")

    # The very first line must be the identification line.
    identification = rstrip(lines[1])
    isempty(identification) && error("VHDR file is empty")
    if !occursin(_IDENTIFICATION_RE, identification)
        error("unrecognised VHDR identification line: \"$identification\"\n" *
              "expected a line matching: $_IDENTIFICATION_RE")
    end
    result["identification"] = identification

    current_section = nothing
    comment_lines = String[]
    in_comment = false

    for line in @view lines[2:end]
        line = rstrip(line)

        if in_comment
            # In [Comment], everything is free-form text — no special handling.
            push!(comment_lines, line)
            continue
        end

        # Outside [Comment]: skip INI-style comment lines and blank lines.
        (startswith(line, ";") || isempty(line)) && continue

        # Section header?
        if startswith(line, "[")
            close_idx = findfirst(']', line)
            if close_idx !== nothing
                current_section = line[2:(close_idx - 1)]
                if current_section == "Comment"
                    in_comment = true
                else
                    result[current_section] = Dict{String,String}()
                end
            end
            continue
        end

        # Key=value pair (only meaningful outside [Comment]).
        if current_section !== nothing
            eq_idx = findfirst('=', line)
            if eq_idx !== nothing
                key = line[1:(eq_idx - 1)]
                value = line[(eq_idx + 1):end]
                result[current_section][key] = value
            end
        end
    end

    if in_comment
        result["Comment"] = join(comment_lines, "\n")
    end

    _validate_vhdr(result)

    return result
end

# Post-parse structural validation: checks the requirements stated in the BVCDF 1.0 spec.
function _validate_vhdr(result::Dict{String,Any})
    # --- Mandatory sections ---
    for section in ("Common Infos", "Binary Infos", "Channel Infos")
        haskey(result, section) ||
            error("mandatory section [$section] is missing from the VHDR file")
    end

    ci = result["Common Infos"]
    bi = result["Binary Infos"]
    ch = result["Channel Infos"]

    # --- Mandatory Common Infos keys ---
    for key in _REQUIRED_COMMON_INFOS_KEYS
        haskey(ci, key) ||
            error("mandatory key \"$key\" is missing from [Common Infos]")
    end

    # Codepage is mandatory per spec but absent in old-style files; warn rather than error.
    if !haskey(ci, "Codepage")
        @warn "\"Codepage\" key is missing from [Common Infos]; assuming Latin-1 encoding"
    end

    # --- Mandatory Binary Infos keys ---
    for key in _REQUIRED_BINARY_INFOS_KEYS
        haskey(bi, key) ||
            error("mandatory key \"$key\" is missing from [Binary Infos]")
    end

    # --- Channel count consistency ---
    n_channels_str = ci["NumberOfChannels"]
    n_channels = tryparse(Int, n_channels_str)
    if n_channels === nothing
        error("NumberOfChannels value \"$n_channels_str\" is not a valid integer")
    end
    if n_channels <= 0
        error("NumberOfChannels must be > 0, got $n_channels")
    end

    n_parsed = length(ch)
    if n_parsed != n_channels
        error("NumberOfChannels is $n_channels but $n_parsed channel " *
              "$(n_parsed == 1 ? "entry was" : "entries were") found in [Channel Infos]")
    end

    # Channel numbers must be the consecutive sequence Ch1..ChN.
    for i in 1:n_channels
        haskey(ch, "Ch$i") ||
            error("channel entry \"Ch$i\" is missing from [Channel Infos] " *
                  "(NumberOfChannels = $n_channels)")
    end

    # --- Coordinates count (if section is present) ---
    if haskey(result, "Coordinates")
        coords = result["Coordinates"]
        n_coords = length(coords)
        if n_coords != n_channels
            error("NumberOfChannels is $n_channels but $n_coords coordinate " *
                  "$(n_coords == 1 ? "entry was" : "entries were") found in [Coordinates]")
        end
        for i in 1:n_channels
            haskey(coords, "Ch$i") ||
                error("coordinate entry \"Ch$i\" is missing from [Coordinates] " *
                      "(NumberOfChannels = $n_channels)")
        end
    end

    return nothing
end

"""
    parse_amplifier_setup(comment::String) -> (info, channels) or nothing

Parse the "Amplifier Setup" sub-section from a VHDR `[Comment]` string.

Returns `nothing` if no amplifier setup section is found in `comment`.

Otherwise returns a 2-tuple `(info, channels)` where:

- `info` is a `Dict{String,String}` containing the three header key-value pairs,
  typically `"Number of channels"`, `"Sampling Rate [Hz]"`, and
  `"Sampling Interval [µS]"`.

- `channels` is a Tables.jl-compatible `NamedTuple` column table whose columns
  are `Vector{String}` with names `number`, `name`, `phys_chn`, `resolution`,
  `low_cutoff`, `high_cutoff`, `notch`.  Each row corresponds to one channel
  in the amplifier channel table.
"""
function parse_amplifier_setup(comment::String)
    lines = split(comment, r"\r?\n")

    # Locate the "A m p l i f i e r  S e t u p" banner line.
    amp_idx = findfirst(l -> startswith(strip(l), "A m p l i f i e r"), lines)
    amp_idx === nothing && return nothing

    # Parse the three info key-value lines.  They follow the "====" separator.
    info = Dict{String,String}()
    i = amp_idx + 2  # skip the banner line and the "====" separator
    while i <= length(lines)
        l = strip(lines[i])
        isempty(l) && break
        m = match(r"^(.+?)\s*:\s*(.+)$", l)
        m !== nothing && (info[String(m[1])] = String(m[2]))
        i += 1
    end

    # Find the channel-table header line (first line starting with "#").
    hash_idx = findnext(l -> startswith(strip(l), "#"), lines, amp_idx + 1)
    hash_idx === nothing && return (info, nothing)

    # Parse channel data rows.  Each row starts with a digit (the channel number).
    # Columns are separated by 2+ spaces in both the header and data rows; splitting
    # on that pattern gives the first 7 semantically stable columns regardless of
    # whether the file uses the 7-column or the extended 10-column header variant.
    cols = ntuple(_ -> String[], 7)
    row_idx = hash_idx + 1
    while row_idx <= length(lines)
        l = strip(lines[row_idx])
        row_idx += 1
        (isempty(l) || !isdigit(first(l))) && break
        tokens = split(l, r"  +")
        for col in 1:7
            push!(cols[col], col <= length(tokens) ? String(strip(tokens[col])) : "")
        end
    end

    channels = NamedTuple{_AMP_CHANNEL_COLS}(cols)
    return (info, channels)
end

"""
    parse_software_filters(comment::String) -> NamedTuple or nothing

Parse the "Software Filters" sub-section from a VHDR `[Comment]` string.

Returns `nothing` if the section is absent or marked as "Disabled".

Otherwise returns a Tables.jl-compatible `NamedTuple` column table.  When an
"Amplifier Setup" section is also present in `comment` and its channel count
matches, a `name` column (channel names from the amplifier table) is inserted
after `number`, giving 5 columns total:

    number  name  low_cutoff  high_cutoff  notch

Without matching amplifier data the table has 4 columns:

    number  low_cutoff  high_cutoff  notch

Each column is a `Vector{String}` with one entry per channel row.
"""
function parse_software_filters(comment::String)
    lines = split(comment, r"\r?\n")

    # Locate the "S o f t w a r e  F i l t e r s" banner line.
    sw_idx = findfirst(l -> startswith(strip(l), "S o f t w a r e"), lines)
    sw_idx === nothing && return nothing

    # Find the channel-table header line (starts with "#") after the banner.
    # If not present the section contains prose (e.g. "Disabled") — return nothing.
    hash_idx = findnext(l -> startswith(strip(l), "#"), lines, sw_idx + 1)
    hash_idx === nothing && return nothing

    # Parse 4-column data rows.  Each row starts with a digit (the channel number).
    cols = ntuple(_ -> String[], 4)
    row_idx = hash_idx + 1
    while row_idx <= length(lines)
        l = strip(lines[row_idx])
        row_idx += 1
        (isempty(l) || !isdigit(first(l))) && break
        tokens = split(l, r"  +")
        for col in 1:4
            push!(cols[col], col <= length(tokens) ? String(strip(tokens[col])) : "")
        end
    end

    isempty(cols[1]) && return nothing

    # Augment with channel names from the Amplifier Setup section when available
    # and the row counts agree.
    amp_result = parse_amplifier_setup(comment)
    if amp_result !== nothing
        _, amp_ch = amp_result
        if amp_ch !== nothing && length(amp_ch.name) == length(cols[1])
            return NamedTuple{_SW_FILTER_COLS_WITH_NAMES}((cols[1], amp_ch.name,
                                                           cols[2], cols[3], cols[4]))
        end
    end

    return NamedTuple{_SW_FILTER_COLS_BASE}(cols)
end

"""
    parse_impedances(comment::String) -> Dict{String, Union{Float64, Missing}} or nothing

Parse the impedance table from a VHDR `[Comment]` string.

Returns `nothing` if no `Impedance [kOhm] at ...` header line is found.

Otherwise returns a `Dict{String, Union{Float64, Missing}}` mapping each
channel name to its measured impedance in kOhm.  Unknown impedances (recorded
as `???` in the file) are represented as `missing`.

Channel names may contain spaces (e.g. `"CP 6"`, `"F3 3 part"`) or special
characters such as `+` and `-`.  The section may be preceded by optional prose
lines (e.g. `"Impedances Imported from actiCAP Control Software:"`) which are
ignored.
"""
function parse_impedances(comment::String)
    lines = split(comment, r"\r?\n")

    # Find the "Impedance [kOhm] at HH:MM:SS :" header line.
    imp_idx = findfirst(l -> occursin("Impedance [kOhm] at", l), lines)
    imp_idx === nothing && return nothing

    # Parse entries from the next line onwards.
    # Each entry has the form "Name:   value" where value is a number or "???".
    # Blank lines and lines beginning with ";" are skipped.
    # The first non-blank, non-comment line that does not match the entry pattern
    # terminates the section.
    result = Dict{String,Union{Float64,Missing}}()
    for line in @view lines[(imp_idx + 1):end]
        l = strip(line)
        isempty(l) && continue
        startswith(l, ";") && continue
        m = match(r"^(.+?):\s+(.+)$", l)
        m === nothing && break
        name = String(strip(m[1]))
        val_str = String(strip(m[2]))
        result[name] = val_str == "???" ? missing : parse(Float64, val_str)
    end

    isempty(result) && return nothing
    return result
end
