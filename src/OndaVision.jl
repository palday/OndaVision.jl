module OndaVision

using Onda

export read_vhdr, parse_amplifier_setup, parse_software_filters, parse_impedances
export read_vmrk

include("utils.jl")
include("read_vhdr.jl")
include("read_vmrk.jl")

end # module OndaVision
