"""
    VectorizedLPCMFormat{S} <: Onda.AbstractLPCMFormat

An `AbstractLPCMFormat` for non-interleaved (vectorized) LPCM binary data, where
all samples for channel 1 are stored contiguously, followed by all samples for
channel 2, and so on.

This is the layout used by BrainVision's `DataOrientation=VECTORIZED` format,
as opposed to Onda's default interleaved (multiplexed) layout.

The total number of time points is inferred dynamically from the byte count
during deserialization, so this format can be constructed from just a
`SamplesInfoV2` (or anything with `channels` and `sample_type` fields).

See also: [`LPCMFormat`](@ref)
"""
struct VectorizedLPCMFormat{S<:Onda.LPCM_SAMPLE_TYPE_UNION} <: Onda.AbstractLPCMFormat
    lpcm::LPCMFormat{S}
end

VectorizedLPCMFormat(info) = VectorizedLPCMFormat(LPCMFormat(info))

Onda.file_format_string(::VectorizedLPCMFormat) = "lpcm.vectorized"

function Onda.deserialize_lpcm(format::VectorizedLPCMFormat{S}, bytes,
                               sample_offset::Integer=0,
                               sample_count::Integer=typemax(Int)) where {S}
    n_channels = format.lpcm.channel_count
    raw = reinterpret(S, bytes)
    n_total, rem = divrem(length(raw), n_channels)
    rem == 0 ||
        throw(ArgumentError("byte count ($(length(bytes))) does not divide evenly " *
                            "into $n_channels channels of $(sizeof(S))-byte samples"))
    # Vectorized layout: all samples for ch1, then ch2, etc.
    # reshape to (n_total, n_channels) then permutedims to (n_channels, n_total)
    interleaved = permutedims(reshape(raw, n_total, n_channels))
    # Apply offset and count
    sample_start = min(sample_offset + 1, size(interleaved, 2))
    sample_end = min(sample_offset + sample_count, size(interleaved, 2))
    return interleaved[:, sample_start:sample_end]
end

function Onda.serialize_lpcm(format::VectorizedLPCMFormat{S},
                             samples::AbstractMatrix) where {S}
    n_channels = format.lpcm.channel_count
    if size(samples, 1) != n_channels
        throw(ArgumentError("`samples` row count ($(size(samples, 1))) does not " *
                            "match expected channel count ($n_channels)"))
    end
    if !(eltype(samples) <: S)
        throw(ArgumentError("`samples` eltype ($(eltype(samples))) does not " *
                            "match expected eltype ($S)"))
    end
    # Permute from (n_channels, n_samples) to (n_samples, n_channels) then flatten
    return reinterpret(UInt8, vec(permutedims(samples)))
end

function _register_vectorized_lpcm_format!()
    return Onda.register_lpcm_format!() do file_format
        return file_format == "lpcm.vectorized" ? VectorizedLPCMFormat : nothing
    end
end
