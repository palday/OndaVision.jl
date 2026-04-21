using Dates
using Onda
using TimeSpans
using UUIDs

@testset "return shape" begin
    result = @suppress read_brainvision_onda(joinpath(DATA_DIR, "test.vhdr"))
    @test result isa NamedTuple
    @test hasproperty(result, :signals)
    @test hasproperty(result, :annotations)
    @test hasproperty(result, :metadata)
    @test result.metadata isa BrainVisionMetadata
end

@testset "signals match brainvision_to_signal" begin
    rec = uuid4()
    result = @suppress read_brainvision_onda(joinpath(DATA_DIR, "test.vhdr"); recording=rec)
    expected = @suppress brainvision_to_signal(joinpath(DATA_DIR, "test.vhdr"); recording=rec)
    @test length(result.signals) == length(expected)
    for (s, e) in zip(result.signals, expected)
        @test s.file_path == e.file_path
        @test s.file_format == e.file_format
        @test s.channels == e.channels
        @test s.sample_unit == e.sample_unit
        @test s.sample_resolution_in_unit == e.sample_resolution_in_unit
        @test s.sample_rate == e.sample_rate
        @test s.span == e.span
        @test s.recording == rec
    end
end

@testset "annotations match brainvision_annotations" begin
    rec = uuid4()
    result = read_brainvision_onda(joinpath(DATA_DIR, "test_highpass.vhdr"); recording=rec)
    expected = brainvision_annotations(joinpath(DATA_DIR, "test_highpass.vhdr"); recording=rec)
    @test result.annotations.recording == expected.recording
    @test result.annotations.span == expected.span
    @test result.annotations.marker_type == expected.marker_type
    @test result.annotations.description == expected.description
    @test isequal(result.annotations.channel, expected.channel)
    @test_nowarn Onda.validate_annotations(result.annotations)
end

@testset "recording kwarg propagates to both signals and annotations" begin
    rec = uuid4()
    result = read_brainvision_onda(joinpath(DATA_DIR, "test_highpass.vhdr"); recording=rec)
    @test all(==(rec), result.annotations.recording)
    @test all(s -> s.recording == rec, result.signals)
end

@testset "channel names and references" begin
    result = @suppress read_brainvision_onda(joinpath(DATA_DIR, "test.vhdr"))
    @test result.metadata.channel_names isa Vector{String}
    @test length(result.metadata.channel_names) == 32
    @test result.metadata.channel_names[1] == "FP1"
    @test result.metadata.channel_names[17] == "Cz"
    # test.vhdr has no reference channels specified
    @test result.metadata.channel_references isa Vector{String}
    @test length(result.metadata.channel_references) == 32
    @test all(==(""), result.metadata.channel_references)
end

@testset "coordinates absent" begin
    result = @suppress read_brainvision_onda(joinpath(DATA_DIR, "test.vhdr"))
    @test result.metadata.coordinates isa NamedTuple
    @test isempty(result.metadata.coordinates.channel)
    @test isempty(result.metadata.coordinates.radius)
end

@testset "coordinates present" begin
    result = @suppress read_brainvision_onda(joinpath(DATA_DIR, "testv2.vhdr"))
    coords = result.metadata.coordinates
    @test coords isa NamedTuple
    @test length(coords.channel) == 32
    @test length(coords.radius) == 32
    @test length(coords.theta) == 32
    @test length(coords.phi) == 32
    # Ch17=1,0,0 in testv2.vhdr (Cz)
    @test coords.channel[17] == "Cz"
    @test coords.radius[17] == 1.0
    @test coords.theta[17] == 0.0
    @test coords.phi[17] == 0.0
    # Ch1=1,-90,-72 (FP1)
    @test coords.radius[1] == 1.0
    @test coords.theta[1] == -90.0
    @test coords.phi[1] == -72.0
end

@testset "impedances present" begin
    result = @suppress read_brainvision_onda(joinpath(DATA_DIR, "test.vhdr"))
    @test result.metadata.impedances isa Dict{String,Union{Float64,Missing}}
    # Named electrodes stored as ??? → missing; reference/ground are numeric
    @test ismissing(result.metadata.impedances["FP1"])
    @test result.metadata.impedances["Ref"] === 0.0
    @test result.metadata.impedances["Gnd"] === 4.0
end

@testset "impedances absent" begin
    result = @suppress read_brainvision_onda(joinpath(DATA_DIR, "testv2.vhdr"))
    @test isempty(result.metadata.impedances)
end

@testset "amplifier channels present" begin
    result = @suppress read_brainvision_onda(joinpath(DATA_DIR, "test.vhdr"))
    amp = result.metadata.amplifier_channels
    @test amp isa NamedTuple
    @test length(amp.number) == 32
    @test amp.low_cutoff[1] == "DC"
    @test amp.high_cutoff[1] == "250"
    @test amp.notch[1] == "Off"
    @test amp.name[1] == "FP1"
    @test result.metadata.amplifier_info["Sampling Rate [Hz]"] == "1000"
end

@testset "amplifier channels absent" begin
    result = @suppress read_brainvision_onda(joinpath(DATA_DIR, "testv2.vhdr"))
    @test isempty(result.metadata.amplifier_channels.number)
    @test isempty(result.metadata.amplifier_info)
end

@testset "software filters disabled" begin
    result = @suppress read_brainvision_onda(joinpath(DATA_DIR, "test.vhdr"))
    @test isempty(result.metadata.software_filters.number)
end

@testset "software filters active" begin
    result = @suppress read_brainvision_onda(
        joinpath(DATA_DIR, "test_old_layout_latin1_software_filter.vhdr"))
    sw = result.metadata.software_filters
    @test sw isa NamedTuple
    @test !isempty(sw.number)
end

@testset "marker dates" begin
    result = read_brainvision_onda(joinpath(DATA_DIR, "test_highpass.vhdr"))
    @test result.metadata.marker_dates isa Vector{Union{String,Missing}}
    @test length(result.metadata.marker_dates) == length(result.annotations.recording)
end

@testset "no marker file — empty annotations" begin
    mktempdir() do dir
        vhdr_path = joinpath(dir, "no_marker.vhdr")
        eeg_path = joinpath(dir, "no_marker.eeg")
        write(eeg_path, zeros(Int16, 2 * 10))  # 2 channels × 10 samples
        write(vhdr_path, """
Brain Vision Data Exchange Header File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=no_marker.eeg
DataFormat=BINARY
DataOrientation=MULTIPLEXED
NumberOfChannels=2
SamplingInterval=1000

[Binary Infos]
BinaryFormat=INT_16

[Channel Infos]
Ch1=Cz,,1,µV
Ch2=Pz,,1,µV
""")
        result = read_brainvision_onda(vhdr_path)
        @test isempty(result.metadata.marker_dates)
        @test length(result.annotations.recording) == 0
        @test_nowarn Onda.validate_annotations(result.annotations)
    end
end

@testset "user_infos and channel_user_infos empty for v2 file" begin
    result = @suppress read_brainvision_onda(joinpath(DATA_DIR, "testv2.vhdr"))
    @test result.metadata.user_infos isa Dict{String,String}
    @test isempty(result.metadata.user_infos)
    @test result.metadata.channel_user_infos isa Dict{String,String}
    @test isempty(result.metadata.channel_user_infos)
end

@testset "comment present" begin
    result = @suppress read_brainvision_onda(joinpath(DATA_DIR, "test.vhdr"))
    @test result.metadata.comment isa String
    # Banner uses spaced lettering: "A m p l i f i e r  S e t u p"
    @test occursin("A m p l i f i e r", result.metadata.comment)
end

@testset "comment absent" begin
    result = @suppress read_brainvision_onda(joinpath(DATA_DIR, "testv2.vhdr"))
    @test result.metadata.comment == ""
end
