module OndaVision

using Onda

export read_vhdr, parse_amplifier_setup, parse_software_filters, parse_impedances

greet() = print("Hello World!")

include("read_vhdr.jl")

end # module OndaVision
