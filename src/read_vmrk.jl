"""
    read_vmrk(filename)
    read_vmrk(io::IO)

Returns a dictionary of entries from a BrainVision VMRK file.

`filename` may be any entity with an appropriate `open` method.

The BrainVision VMRK format is similar to the Windows INI configuration format, but
has a few additional extensions. 
The most important section is the Marker Infos, 
which contains the sequence of markers. 
This section is extracted as a Tables.jl-compatible table.

# Format notes

- Lines beginning with `;` are comments and are ignored (except inside `[Comment]`).
"""
function read_vmrk(filename; kwargs...)
    return open(filename, "r") do io
        return read_vhdr(io; kwargs...)
    end
end

function read_vmrk(io::IO)
end
