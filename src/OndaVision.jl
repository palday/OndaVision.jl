module OndaVision

using Onda

greet() = print("Hello World!")

"""
    read_vhdr(filename)
    read_vhdr(io::IO)

Returns a nested dictionary of configuration entries from a BrainVision VHDR file.

`filename` may be any entity with an appropriate `open` method.

The BrainVision VHDR format is similar to the Windows INI configuration format, but
has a few additional extensions.
"""
function read_vhdr(filename; kwargs...)
    return open(filename, "r") do io
        return read_vhdr(io, kwargs...)
    end
end


function read_vhdr(io::IO)
end

end # module OndaVision
