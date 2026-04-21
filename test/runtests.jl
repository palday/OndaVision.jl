include("set_up_tests.jl")

@testset "Aqua" begin
    Aqua.test_all(OndaVision; ambiguities=false)
end

@testset "read_vhdr" include("read_vhdr.jl")
@testset "read_vmrk" include("read_vmrk.jl")
@testset "read_brainvision" include("read_brainvision.jl")
@testset "signal" include("signal.jl")
@testset "annotations" include("annotations.jl")
@testset "full_service" include("full_service.jl")
