"""
    ChannelSubsetLPCMFormat{F} <: Onda.AbstractLPCMFormat

An `AbstractLPCMFormat` wrapper that deserializes a full multi-channel LPCM
binary file but returns only a subset of channels.

This is used when a BrainVision file contains channels with different units or
resolutions, requiring multiple Onda `SignalV2` records that each point to the
same `.eeg` data file but cover different channel subsets.

The `file_format` string encodes the base format, total channel count, and
1-based channel indices so that `Onda.load` can reconstruct the format
automatically.  For example:

    "lpcm.subset.32.1,2,3"               # MULTIPLEXED, 32 total channels, indices 1-3
    "lpcm.vectorized.subset.32.27,28"     # VECTORIZED, 32 total channels, indices 27-28

See also: [`VectorizedLPCMFormat`](@ref), [`LPCMFormat`](@ref)
"""
struct ChannelSubsetLPCMFormat{F<:Onda.AbstractLPCMFormat} <: Onda.AbstractLPCMFormat
    inner::F
    indices::Vector{Int}
end

function Onda.file_format_string(fmt::ChannelSubsetLPCMFormat)
    base = Onda.file_format_string(fmt.inner)
    total = _inner_channel_count(fmt.inner)
    idx_str = join(fmt.indices, ',')
    return "$(base).subset.$(total).$(idx_str)"
end

_inner_channel_count(f::LPCMFormat) = f.channel_count
_inner_channel_count(f::VectorizedLPCMFormat) = f.lpcm.channel_count

function Onda.deserialize_lpcm(fmt::ChannelSubsetLPCMFormat, bytes,
                               sample_offset::Integer=0,
                               sample_count::Integer=typemax(Int))
    full = Onda.deserialize_lpcm(fmt.inner, bytes, sample_offset, sample_count)
    return full[fmt.indices, :]
end

function Onda.serialize_lpcm(::ChannelSubsetLPCMFormat, ::AbstractMatrix)
    return error("serialization is not supported for ChannelSubsetLPCMFormat")
end

const _SUBSET_FORMAT_RE = r"^(lpcm(?:\.vectorized)?)\.subset\.(\d+)\.([\d,]+)$"

function _register_channel_subset_lpcm_format!()
    return Onda.register_lpcm_format!() do file_format
        m = match(_SUBSET_FORMAT_RE, file_format)
        m === nothing && return nothing
        base_format = m.captures[1]
        total_channels = parse(Int, m.captures[2])
        indices = parse.(Int, split(m.captures[3], ','))
        return function(info; kwargs...)
            S = Onda.sample_type(info)
            inner = if base_format == "lpcm"
                LPCMFormat(total_channels, S)
            else
                VectorizedLPCMFormat(LPCMFormat(total_channels, S))
            end
            return ChannelSubsetLPCMFormat(inner, indices)
        end
    end
end
