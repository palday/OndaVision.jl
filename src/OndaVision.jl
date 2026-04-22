module OndaVision

using Dates
using Onda
using TimeSpans
using UUIDs

include("utils.jl")

include("read_vhdr.jl")
export read_vhdr, parse_amplifier_setup, parse_software_filters, parse_impedances

include("read_vmrk.jl")
export read_vmrk, get_segments

include("read_brainvision.jl")
export read_brainvision

include("vectorized_lpcm.jl")
export VectorizedLPCMFormat

include("channel_subset_lpcm.jl")
export ChannelSubsetLPCMFormat

include("signal.jl")
export brainvision_to_signal

include("annotations.jl")
export brainvision_annotations

include("full_service.jl")
export read_brainvision_onda, BrainVisionMetadata

include("write_brainvision.jl")
export write_brainvision

function __init__()
    _register_vectorized_lpcm_format!()
    _register_channel_subset_lpcm_format!()
    return nothing
end

end # module OndaVision
