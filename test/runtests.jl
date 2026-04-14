include("set_up_tests.jl")

@testset "Aqua" begin
    Aqua.test_all(OndaVision; ambiguities=false)
end

@testset "read_vhdr" include("read_vhdr.jl")
