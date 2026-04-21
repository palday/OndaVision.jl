module OndaVision

using Dates
using Onda
using TimeSpans
using UUIDs

export read_vhdr, parse_amplifier_setup, parse_software_filters, parse_impedances
export read_vmrk, get_segments
export read_brainvision
export brainvision_to_signal
export VectorizedLPCMFormat

include("utils.jl")
include("read_vhdr.jl")
include("read_vmrk.jl")
include("read_brainvision.jl")
include("vectorized_lpcm.jl")
include("signal.jl")

function __init__()
    _register_vectorized_lpcm_format!()
    return nothing
end

end # module OndaVision
