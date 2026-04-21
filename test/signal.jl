using Onda
using Dates
using TimeSpans
using UUIDs

const DATA_DIR = joinpath(@__DIR__, "data")

@testset "unit normalization" begin
    @test OndaVision._normalize_bv_unit("") == "microvolt"
    @test OndaVision._normalize_bv_unit("µV") == "microvolt"    # U+00B5
    @test OndaVision._normalize_bv_unit("μV") == "microvolt"    # U+03BC
    @test OndaVision._normalize_bv_unit("uV") == "microvolt"
    @test OndaVision._normalize_bv_unit("nV") == "nanovolt"
    @test OndaVision._normalize_bv_unit("mV") == "millivolt"
    @test OndaVision._normalize_bv_unit("V") == "volt"
    @test OndaVision._normalize_bv_unit("µS") == "microsiemens" # U+00B5
    @test OndaVision._normalize_bv_unit("μS") == "microsiemens" # U+03BC
    @test OndaVision._normalize_bv_unit("uS") == "microsiemens"
    @test OndaVision._normalize_bv_unit("S") == "siemens"
    @test OndaVision._normalize_bv_unit("C") == "celsius"
    @test @test_logs((:warn, r"unknown BrainVision unit"),
                     OndaVision._normalize_bv_unit("ARU")) == "aru"
    @test @test_logs((:warn, r"unknown BrainVision unit"),
                     OndaVision._normalize_bv_unit("BS")) == "bs"
end

@testset "brainvision_to_signal - MULTIPLEXED INT_16" begin
    vhdr_file = joinpath(DATA_DIR, "test_highpass.vhdr")
    signals = brainvision_to_signal(vhdr_file; sensor_type="eeg")
    @test length(signals) == 1
    signal = signals[1]

    @test signal.sensor_type == "eeg"
    @test signal.sensor_label == "eeg"
    @test signal.file_format == "lpcm"
    @test signal.sample_type == "int16"
    @test signal.sample_rate == 1000.0
    @test signal.sample_resolution_in_unit == 0.5
    @test signal.sample_offset_in_unit == 0.0
    @test signal.sample_unit == "microvolt"
    @test length(signal.channels) == 32
    @test signal.channels[1] == "fp1"
    @test signal.channels[end] == "reref"
    @test all(c -> c == lowercase(c), signal.channels)
    @test signal.file_path == abspath(joinpath(DATA_DIR, "test.eeg"))

    # Round-trip: load via Onda and compare to read_brainvision
    samples = Onda.load(signal)
    expected = read_brainvision(vhdr_file)
    @test samples.data ≈ expected
    @test !samples.encoded
end

@testset "brainvision_to_signal - VECTORIZED FLOAT32" begin
    vhdr_file = joinpath(DATA_DIR, "test_float32_vectorized.vhdr")
    signals = brainvision_to_signal(vhdr_file; sensor_type="eeg")
    @test length(signals) == 1
    signal = signals[1]

    @test signal.file_format == "lpcm.vectorized"
    @test signal.sample_type == "float32"
    @test signal.sample_rate == 1000.0
    @test signal.sample_resolution_in_unit == 1.0
    @test signal.sample_unit == "microvolt"
    @test length(signal.channels) == 2
    @test signal.channels == ["cz", "pz"]

    # Round-trip: load via Onda and compare to read_brainvision
    samples = Onda.load(signal)
    expected = read_brainvision(vhdr_file)
    @test samples.data ≈ expected
    @test !samples.encoded
end

@testset "brainvision_to_signal - custom keyword args" begin
    vhdr_file = joinpath(DATA_DIR, "test_float32_vectorized.vhdr")
    rec_uuid = uuid4()
    signals = brainvision_to_signal(vhdr_file;
                                    recording=rec_uuid,
                                    sensor_type="ecog",
                                    sensor_label="grid_a")
    signal = signals[1]
    @test signal.recording == rec_uuid
    @test signal.sensor_type == "ecog"
    @test signal.sensor_label == "grid_a"
end

@testset "brainvision_to_signal - mixed units error" begin
    vhdr_file = joinpath(DATA_DIR, "test.vhdr")
    @test_throws ErrorException brainvision_to_signal(vhdr_file)
end

@testset "brainvision_to_signal - mixed resolution error" begin
    vhdr_file = joinpath(DATA_DIR, "test_units.vhdr")
    @test_throws ErrorException brainvision_to_signal(vhdr_file)
end

@testset "VectorizedLPCMFormat round-trip" begin
    # Create some test data and verify serialize/deserialize round-trip
    n_channels = 3
    n_samples = 100
    data = Int16.(rand(-1000:1000, n_channels, n_samples))
    lpcm = LPCMFormat(n_channels, Int16)
    fmt = VectorizedLPCMFormat(lpcm)

    bytes = Onda.serialize_lpcm(fmt, data)
    recovered = Onda.deserialize_lpcm(fmt, bytes)
    @test recovered == data

    # Test partial deserialization
    recovered_partial = Onda.deserialize_lpcm(fmt, bytes, 10, 50)
    @test recovered_partial == data[:, 11:60]
end
