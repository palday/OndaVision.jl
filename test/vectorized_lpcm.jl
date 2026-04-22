@testset "file_format_string" begin
    fmt = VectorizedLPCMFormat(Onda.LPCMFormat(2, Int16))
    @test Onda.file_format_string(fmt) == "lpcm.vectorized"
end

@testset "serialize_lpcm errors" begin
    fmt = VectorizedLPCMFormat(Onda.LPCMFormat(2, Int16))
    # Wrong channel count: format expects 2 rows, matrix has 3
    @test_throws ArgumentError Onda.serialize_lpcm(fmt, Matrix{Int16}(undef, 3, 10))
    # Wrong element type: format is Int16, matrix is Float32
    @test_throws ArgumentError Onda.serialize_lpcm(fmt, Matrix{Float32}(undef, 2, 10))
end
