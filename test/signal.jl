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

@testset "brainvision_to_signal - mixed units" begin
    # test.vhdr has 32 channels, all resolution 0.5, but mixed units:
    # Ch1-26: microvolt, Ch27: BS, Ch28: µS, Ch29: ARU, Ch30: uS, Ch31: S, Ch32: C
    vhdr_file = joinpath(DATA_DIR, "test.vhdr")
    signals = @suppress brainvision_to_signal(vhdr_file)
    @test length(signals) == 6

    # Groups are sorted by (unit, resolution):
    # aru, bs, celsius, microsiemens, microvolt, siemens
    @test signals[1].sample_unit == "aru"
    @test signals[1].channels == ["hl"]
    @test signals[1].sensor_label == "eeg_aru"

    @test signals[2].sample_unit == "bs"
    @test signals[2].channels == ["cp5"]
    @test signals[2].sensor_label == "eeg_bs"

    @test signals[3].sample_unit == "celsius"
    @test signals[3].channels == ["reref"]

    @test signals[4].sample_unit == "microsiemens"
    @test signals[4].channels == ["cp6", "hr"]

    @test signals[5].sample_unit == "microvolt"
    @test length(signals[5].channels) == 26
    @test signals[5].channels[1] == "fp1"

    @test signals[6].sample_unit == "siemens"
    @test signals[6].channels == ["vb"]

    # All signals share the same resolution, sample_rate, span, and file_path
    @test all(s -> s.sample_resolution_in_unit == 0.5, signals)
    @test all(s -> s.sample_rate == 1000.0, signals)
    @test all(s -> s.span == signals[1].span, signals)
    @test all(s -> s.file_path == signals[1].file_path, signals)

    # Subset signals use the subset file format
    @test startswith(signals[1].file_format, "lpcm.subset.")
    # The microvolt group is a subset too (26 of 32 channels)
    @test startswith(signals[5].file_format, "lpcm.subset.")

    # Round-trip: each signal loads the correct channel subset
    expected_all = @suppress read_brainvision(vhdr_file)
    for signal in signals
        samples = Onda.load(signal)
        @test !samples.encoded
    end

    # Verify the microvolt group matches the first 26 channels
    mv_samples = Onda.load(signals[5])
    @test mv_samples.data ≈ expected_all[1:26, :]

    # Verify the microsiemens group matches channels 28, 30
    ms_samples = Onda.load(signals[4])
    @test ms_samples.data ≈ expected_all[[28, 30], :]
end

@testset "brainvision_to_signal - mixed resolutions" begin
    # test_units.vhdr has channels with different resolutions AND units
    vhdr_file = joinpath(DATA_DIR, "test_units.vhdr")
    signals = @suppress brainvision_to_signal(vhdr_file)

    # Should produce multiple signals grouped by (unit, resolution)
    @test length(signals) > 1

    # All signals share the same file
    @test all(s -> s.file_path == signals[1].file_path, signals)
    @test all(s -> s.sample_rate == 1000.0, signals)

    # Each signal should be loadable
    for signal in signals
        samples = Onda.load(signal)
        @test !samples.encoded
    end

    # Find the microvolt group (0.5 resolution, channels 4-26)
    mv_signals = filter(s -> s.sample_unit == "microvolt" &&
                             s.sample_resolution_in_unit == 0.5, signals)
    @test length(mv_signals) == 1
    @test length(mv_signals[1].channels) == 23

    # Verify round-trip for the microvolt group
    expected_all = @suppress read_brainvision(vhdr_file)
    mv_samples = Onda.load(mv_signals[1])
    @test mv_samples.data ≈ expected_all[4:26, :]

    # Check the nanovolt group (Ch1, resolution 500)
    nv_signals = filter(s -> s.sample_unit == "nanovolt", signals)
    @test length(nv_signals) == 1
    @test nv_signals[1].sample_resolution_in_unit == 500.0
    @test nv_signals[1].channels == ["fp1"]
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

@testset "ChannelSubsetLPCMFormat round-trip" begin
    n_channels = 4
    n_samples = 100
    data = Int16.(rand(-1000:1000, n_channels, n_samples))

    # MULTIPLEXED subset
    inner = LPCMFormat(n_channels, Int16)
    fmt = ChannelSubsetLPCMFormat(inner, [2, 4])
    bytes = Onda.serialize_lpcm(inner, data)
    recovered = Onda.deserialize_lpcm(fmt, bytes)
    @test recovered == data[[2, 4], :]

    # Partial deserialization
    recovered_partial = Onda.deserialize_lpcm(fmt, bytes, 10, 50)
    @test recovered_partial == data[[2, 4], 11:60]

    # VECTORIZED subset
    inner_v = VectorizedLPCMFormat(LPCMFormat(n_channels, Int16))
    fmt_v = ChannelSubsetLPCMFormat(inner_v, [1, 3])
    bytes_v = Onda.serialize_lpcm(inner_v, data)
    recovered_v = Onda.deserialize_lpcm(fmt_v, bytes_v)
    @test recovered_v == data[[1, 3], :]

    # file_format_string round-trip
    @test Onda.file_format_string(fmt) == "lpcm.subset.4.2,4"
    @test Onda.file_format_string(fmt_v) == "lpcm.vectorized.subset.4.1,3"

    # serialize errors
    @test_throws ErrorException Onda.serialize_lpcm(fmt, data[[2, 4], :])
end
