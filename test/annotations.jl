const _VMRK_FILE = joinpath(DATA_DIR, "test.vmrk")
const _VHDR_FILE = joinpath(DATA_DIR, "test_highpass.vhdr")
const _SAMPLE_RATE = 1000.0  # Hz (SamplingInterval=1000 µs)

@testset "structure" begin
    result = @suppress brainvision_annotations(@suppress(read_vmrk(_VMRK_FILE)),
                                               _SAMPLE_RATE)
    @test result isa NamedTuple
    @test hasproperty(result, :recording)
    @test hasproperty(result, :id)
    @test hasproperty(result, :span)
    @test hasproperty(result, :marker_type)
    @test hasproperty(result, :description)
    @test hasproperty(result, :channel)
    @test length(result.recording) == 14
    @test length(result.id) == 14
    @test length(result.span) == 14
end

@testset "schema compliance" begin
    result = @suppress brainvision_annotations(@suppress(read_vmrk(_VMRK_FILE)),
                                               _SAMPLE_RATE)
    @test_nowarn Onda.validate_annotations(result)
end

@testset "span - instantaneous (points == 0)" begin
    # Mk2: position=487, points=0 → single-sample span
    result = @suppress brainvision_annotations(@suppress(read_vmrk(_VMRK_FILE)),
                                               _SAMPLE_RATE)
    @test result.marker_type[2] == "Stimulus"
    expected = TimeSpans.time_from_index(_SAMPLE_RATE, 487:487)
    @test result.span[2] == expected
end

@testset "span - nonzero duration (points > 0)" begin
    # Mk3: position=497, points=1
    result = @suppress brainvision_annotations(@suppress(read_vmrk(_VMRK_FILE)),
                                               _SAMPLE_RATE)
    expected = TimeSpans.time_from_index(_SAMPLE_RATE, 497:497)
    @test result.span[3] == expected
    # Mk1: position=1, points=1
    expected1 = TimeSpans.time_from_index(_SAMPLE_RATE, 1:1)
    @test result.span[1] == expected1
end

@testset "column values" begin
    result = @suppress brainvision_annotations(@suppress(read_vmrk(_VMRK_FILE)),
                                               _SAMPLE_RATE)
    @test result.marker_type[1] == "New Segment"
    @test result.marker_type[2] == "Stimulus"
    @test result.marker_type[10] == "Response"
    @test result.description[2] == "S253"
    @test result.description[10] == "R255"
    @test result.channel[2] == 0
    # all channels are 0 in test.vmrk
    @test all(==(0), result.channel)
end

@testset "recording kwarg" begin
    rec = uuid4()
    result = @suppress brainvision_annotations(@suppress(read_vmrk(_VMRK_FILE)),
                                               _SAMPLE_RATE; recording=rec)
    @test all(==(rec), result.recording)
end

@testset "unique annotation ids" begin
    result = @suppress brainvision_annotations(@suppress(read_vmrk(_VMRK_FILE)),
                                               _SAMPLE_RATE)
    @test length(unique(result.id)) == 14
end

@testset "channel_names=nothing returns Vector{Int}" begin
    result = @suppress brainvision_annotations(@suppress(read_vmrk(_VMRK_FILE)),
                                               _SAMPLE_RATE; channel_names=nothing)
    @test result.channel isa Vector{Int}
end

@testset "channel_names vector: channel 0 → missing, nonzero → name" begin
    # Fabricate a vmrk with a nonzero channel entry
    content = """
Brain Vision Data Exchange Marker File, Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg

[Marker Infos]
Mk1=New Segment,,1,1,0
Mk2=Stimulus,S1,100,1,3
"""
    vmrk = @suppress read_vmrk(IOBuffer(content))
    ch_names = ["fp1", "fp2", "fz"]
    result = @suppress brainvision_annotations(vmrk, _SAMPLE_RATE; channel_names=ch_names)
    @test result.channel isa Vector{Union{String,Missing}}
    @test ismissing(result.channel[1])   # channel 0 → missing
    @test result.channel[2] == "fz"     # channel 3 → ch_names[3]
end

@testset "channel_names dict: channel 0 → missing, nonzero → name" begin
    content = """
Brain Vision Data Exchange Marker File, Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg

[Marker Infos]
Mk1=Stimulus,S1,100,1,2
Mk2=Response,R1,200,1,0
"""
    vmrk = @suppress read_vmrk(IOBuffer(content))
    ch_dict = Dict(1 => "fp1", 2 => "fp2")
    result = @suppress brainvision_annotations(vmrk, _SAMPLE_RATE; channel_names=ch_dict)
    @test result.channel isa Vector{Union{String,Missing}}
    @test result.channel[1] == "fp2"
    @test ismissing(result.channel[2])
end

@testset "method 2 (file-based) equals method 1 (dict-based)" begin
    vmrk = @suppress read_vmrk(_VMRK_FILE)
    rec = uuid4()
    from_dict = @suppress brainvision_annotations(vmrk, _SAMPLE_RATE; recording=rec)
    from_file = @suppress brainvision_annotations(_VMRK_FILE, _SAMPLE_RATE; recording=rec)
    # ids are random so exclude from comparison; check everything else
    @test from_dict.recording == from_file.recording
    @test from_dict.span == from_file.span
    @test from_dict.marker_type == from_file.marker_type
    @test from_dict.description == from_file.description
    @test from_dict.channel == from_file.channel
end

@testset "method 3 (vhdr-based)" begin
    rec = uuid4()
    result = @suppress brainvision_annotations(_VHDR_FILE; recording=rec)
    @test result isa NamedTuple
    @test length(result.span) == 14
    @test all(==(rec), result.recording)
    # channel column is Union{String,Missing} because channel_names=true
    @test result.channel isa Vector{Union{String,Missing}}
    # channel 0 rows → missing
    @test all(ismissing, result.channel)
    # marker_type and spans match what method 2 would give
    from_file = @suppress brainvision_annotations(_VMRK_FILE, _SAMPLE_RATE; recording=rec)
    @test result.span == from_file.span
    @test result.marker_type == from_file.marker_type
    @test result.description == from_file.description
end

@testset "method 3 - schema compliance" begin
    result = @suppress brainvision_annotations(_VHDR_FILE)
    @test_nowarn Onda.validate_annotations(result)
end

@testset "method 3 - missing MarkerFile errors" begin
    # test.vhdr references test.vmrk; rename-based test is fragile, so we use
    # a real VHDR that has a MarkerFile key but point to a nonexistent directory.
    # Instead, write a minimal VHDR to a tempfile that lacks a MarkerFile key.
    mktempdir() do dir
        vhdr_path = joinpath(dir, "no_marker.vhdr")
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
        err = @test_throws ErrorException brainvision_annotations(vhdr_path)
        @test occursin("MarkerFile", err.value.msg)
    end
end
