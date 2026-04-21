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
    _parse_channel_references(ch_info::Dict{String,String}, n_channels::Int) -> Vector{String}

Extract the reference-channel field (field 2) from each `Ch<N>` entry in the
`[Channel Infos]` dictionary.  Returns an empty string for any channel whose
reference field is absent or blank.
"""
function _parse_channel_references(ch_info::Dict{String,String}, n_channels::Int)
    refs = Vector{String}(undef, n_channels)
    for i in 1:n_channels
        entry = ch_info["Ch$i"]
        parts = split(entry, ',')
        refs[i] = length(parts) >= 2 ? String(strip(parts[2])) : ""
    end
    return refs
end

"""
    _parse_coordinates(coords, ch_info, n_channels) -> NamedTuple

Parse the `[Coordinates]` section into a column table with fields
`channel`, `radius`, `theta`, `phi`.  `coords` is the raw
`Dict{String,String}` stored under `"Coordinates"` in the VHDR dict, or
`nothing` when the section is absent.

Returns a NamedTuple with zero-length vectors when the section is absent
or empty, so callers can use `isempty(result.channel)` to detect absence
without a `nothing` check.
"""
function _parse_coordinates(coords::Union{Nothing,Dict{String,String}},
                            ch_info::Dict{String,String}, n_channels::Int)
    if coords === nothing || isempty(coords)
        return (; channel=String[], radius=Float64[], theta=Float64[], phi=Float64[])
    end
    names, _, _ = _parse_channel_info(ch_info, n_channels)
    radii = Vector{Float64}(undef, n_channels)
    thetas = Vector{Float64}(undef, n_channels)
    phis = Vector{Float64}(undef, n_channels)
    for i in 1:n_channels
        parts = split(coords["Ch$i"], ',')
        radii[i] = parse(Float64, strip(parts[1]))
        thetas[i] = parse(Float64, strip(parts[2]))
        phis[i] = parse(Float64, strip(parts[3]))
    end
    return (; channel=names, radius=radii, theta=thetas, phi=phis)
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
