module OndaVision

using Onda

export read_vhdr

greet() = print("Hello World!")

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

const _SUPPORTED_CODEPAGES = ("UTF-8", "Latin-1")

# Matches both the canonical form ("BrainVision") and the legacy form ("Brain Vision").
const _IDENTIFICATION_RE = r"^Brain ?Vision Data Exchange Header File Version \d+\.\d+"

# Keys that the spec marks as mandatory in their respective sections.
const _REQUIRED_COMMON_INFOS_KEYS = ("DataFile", "DataFormat", "DataOrientation",
                                     "NumberOfChannels", "SamplingInterval")
const _REQUIRED_BINARY_INFOS_KEYS = ("BinaryFormat",)

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

# Scan the raw bytes for "Codepage=" (all ASCII, safe for any encoding).
# Returns "UTF-8" if found and that value is present, or "Latin-1" otherwise.
function _detect_codepage(bytes::Vector{UInt8})
    pattern = b"Codepage="
    idx = findfirst(pattern, bytes)
    idx === nothing && return "Latin-1"
    start = last(idx) + 1
    stop = start
    n = length(bytes)
    while stop <= n && bytes[stop] != UInt8('\n') && bytes[stop] != UInt8('\r')
        stop += 1
    end
    value = String(bytes[start:(stop - 1)])
    return strip(value)
end

# Convert Latin-1 (ISO-8859-1) bytes to a UTF-8 Julia String.
function _latin1_to_utf8(bytes::Vector{UInt8})
    buf = IOBuffer()
    for b in bytes
        if b < 0x80
            write(buf, b)
        else
            # Latin-1 supplement maps directly to U+0080..U+00FF,
            # encoded in UTF-8 as two bytes.
            write(buf, 0xC0 | (b >> 6) % UInt8)
            write(buf, 0x80 | (b & 0x3F) % UInt8)
        end
    end
    return String(take!(buf))
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

end # module OndaVision
