const _SUPPORTED_CODEPAGES = ("UTF-8", "Latin-1")

# Scan the raw bytes for "Codepage=" (all ASCII, safe for any encoding).
# Returns the codepage value if found, or "Latin-1" as fallback.
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
