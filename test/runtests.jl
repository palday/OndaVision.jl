include("set_up_tests.jl")

@testset "Aqua" begin
    Aqua.test_all(OndaVision; ambiguities=false)
end
