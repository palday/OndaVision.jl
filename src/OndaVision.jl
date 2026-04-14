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

function read_vhdr(io::IO; codepage::Union{AbstractString, Nothing}=nothing)
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

# Parse a decoded (UTF-8) VHDR string into a nested Dict.
function _parse_vhdr(content::String)
    result = Dict{String, Any}()

    # Split on any line ending (CRLF or LF)
    lines = split(content, r"\r?\n")
    isempty(lines) && error("Empty VHDR file")

    # The very first line must be the identification line.
    identification = rstrip(lines[1])
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
                    result[current_section] = Dict{String, String}()
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

    return result
end

end # module OndaVision
