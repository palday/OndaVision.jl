"""
    _SUPPORTED_CODEPAGES

Character encodings accepted by the `codepage` keyword argument of `read_vhdr`
and `read_vmrk`.  Currently `("UTF-8", "Latin-1")`.
"""
const _SUPPORTED_CODEPAGES = ("UTF-8", "Latin-1")

"""
    _detect_codepage(bytes) -> String

Scan raw file bytes for a `Codepage=` key (all-ASCII, safe for any encoding)
and return its value.  Falls back to `"Latin-1"` when the key is absent.
"""
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

"""
    _parse_channel_info(ch_info::Dict{String,String}, n_channels::Int)

Parse channel names, resolutions, and units from the `[Channel Infos]` section.
Returns `(names::Vector{String}, resolutions::Vector{Float64}, units::Vector{String})`.
"""
function _parse_channel_info(ch_info::Dict{String,String}, n_channels::Int)
    names = Vector{String}(undef, n_channels)
    resolutions = Vector{Float64}(undef, n_channels)
    units = Vector{String}(undef, n_channels)
    for i in 1:n_channels
        entry = ch_info["Ch$i"]
        parts = split(entry, ',')
        names[i] = String(strip(parts[1]))
        res_str = length(parts) >= 3 ? strip(parts[3]) : ""
        resolutions[i] = isempty(res_str) ? 1.0 : parse(Float64, res_str)
        units[i] = length(parts) >= 4 ? String(strip(parts[4])) : ""
    end
    return names, resolutions, units
end

"""
    _latin1_to_utf8(bytes) -> String

Convert a Latin-1 (ISO-8859-1) encoded byte vector to a UTF-8 `String`.

Each byte value in `0x80..0xFF` is mapped to the corresponding Unicode code
point `U+0080..U+00FF` (the Latin-1 Supplement block) and encoded as two
UTF-8 bytes.  Bytes below `0x80` are passed through unchanged.
"""
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
