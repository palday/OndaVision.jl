_vmrk(name) = joinpath(@__DIR__, "data", name)

@testset "identification line" begin
    d = read_vmrk(_vmrk("test.vmrk"))
    @test d["identification"] == "Brain Vision Data Exchange Marker File, Version 1.0"

    d2 = read_vmrk(_vmrk("testv2.vmrk"))
    @test d2["identification"] == "Brain Vision Data Exchange Marker File, Version 2.0"

    d3 = @suppress read_vmrk(_vmrk("test_old_layout_latin1_software_filter.vmrk"))
    @test d3["identification"] == "Brain Vision Data Exchange Marker File, Version 1.0"
end

@testset "Common Infos section" begin
    d = read_vmrk(_vmrk("test.vmrk"))
    ci = d["Common Infos"]
    @test ci isa Dict{String,String}
    @test ci["Codepage"] == "UTF-8"
    @test ci["DataFile"] == "test.eeg"
end

@testset "Marker Infos section — structure" begin
    d = read_vmrk(_vmrk("test.vmrk"))
    @test haskey(d, "Marker Infos")
    markers = d["Marker Infos"]
    @test markers isa NamedTuple
    @test hasproperty(markers, :type)
    @test hasproperty(markers, :description)
    @test hasproperty(markers, :position)
    @test hasproperty(markers, :points)
    @test hasproperty(markers, :channel)
    @test hasproperty(markers, :date)
    @test length(markers.type) == 14
end

@testset "Marker Infos section — column types" begin
    d = read_vmrk(_vmrk("test.vmrk"))
    markers = d["Marker Infos"]
    @test markers.type isa Vector{String}
    @test markers.description isa Vector{String}
    @test markers.position isa Vector{Int}
    @test markers.points isa Vector{Int}
    @test markers.channel isa Vector{Int}
    @test markers.date isa Vector{Union{String,Missing}}
end

@testset "Marker Infos section — values" begin
    d = read_vmrk(_vmrk("test.vmrk"))
    markers = d["Marker Infos"]

    # Mk1: New Segment with date, zero-length description
    @test markers.type[1] == "New Segment"
    @test markers.description[1] == ""
    @test markers.position[1] == 1
    @test markers.points[1] == 1
    @test markers.channel[1] == 0
    @test markers.date[1] == "20131113161403794232"

    # Mk2: Stimulus, points=0 (instantaneous), no date
    @test markers.type[2] == "Stimulus"
    @test markers.description[2] == "S253"
    @test markers.position[2] == 487
    @test markers.points[2] == 0
    @test markers.channel[2] == 0
    @test ismissing(markers.date[2])

    # Mk10: Response marker
    @test markers.type[10] == "Response"
    @test markers.description[10] == "R255"
    @test markers.position[10] == 6000

    # Mk13: SyncStatus
    @test markers.type[13] == "SyncStatus"
    @test markers.description[13] == "Sync On"

    # Mk14: Optic with multi-space description
    @test markers.type[14] == "Optic"
    @test markers.description[14] == "O  1"
end

@testset "Marker Infos section — date optional" begin
    d1 = read_vmrk(_vmrk("test.vmrk"))
    markers1 = d1["Marker Infos"]
    # Mk1 has a date, all others do not
    @test !ismissing(markers1.date[1])
    for i in 2:14
        @test ismissing(markers1.date[i])
    end

    # testv2.vmrk: no markers have a date
    d2 = read_vmrk(_vmrk("testv2.vmrk"))
    @test all(ismissing, d2["Marker Infos"].date)

    # old layout: all markers have dates
    d3 = @suppress read_vmrk(_vmrk("test_old_layout_latin1_software_filter.vmrk"))
    @test all(!ismissing, d3["Marker Infos"].date)
end

@testset "Marker Infos section — channel 0 means all channels" begin
    d = read_vmrk(_vmrk("test.vmrk"))
    @test all(==(0), d["Marker Infos"].channel)
end

@testset "v2 extra sections" begin
    d = read_vmrk(_vmrk("testv2.vmrk"))
    @test haskey(d, "Marker User Infos")
    @test d["Marker User Infos"] isa Dict{String,String}
    @test isempty(d["Marker User Infos"])
end

@testset "v2 marker count and special descriptions" begin
    d = read_vmrk(_vmrk("testv2.vmrk"))
    markers = d["Marker Infos"]
    @test length(markers.type) == 16

    # Mk7: description with square brackets
    @test markers.description[7] == "comment using [square] brackets"

    # Mk12: PyCorder-style (no S-prefix)
    @test markers.description[12] == "254"

    # Mk16: dollar-sign type
    @test markers.type[16] == "\$User_Spec"
end

@testset "Latin-1 encoding auto-detected" begin
    d = @suppress read_vmrk(_vmrk("test_old_layout_latin1_software_filter.vmrk"))
    ci = d["Common Infos"]
    @test !haskey(ci, "Codepage")
    @test ci["DataFile"] == "test_old_layout_latin1_software_filter.eeg"
    markers = d["Marker Infos"]
    @test length(markers.type) == 2
    @test markers.type[1] == "New Segment"
    @test markers.position[1] == 1
    @test markers.position[2] == 2
    @test markers.date[1] == "20070716122240937454"
    @test markers.date[2] == "20070716122240937455"
end

@testset "IO interface" begin
    expected = read_vmrk(_vmrk("test.vmrk"))
    result = open(_vmrk("test.vmrk"), "r") do io
        return read_vmrk(io)
    end
    # isequal is used instead of == because the date column contains missing values,
    # and missing == missing returns missing rather than true.
    @test isequal(result, expected)

    bytes = read(_vmrk("testv2.vmrk"))
    buf_result = read_vmrk(IOBuffer(bytes))
    file_result = read_vmrk(_vmrk("testv2.vmrk"))
    @test isequal(buf_result, file_result)
end

@testset "unsupported codepage keyword" begin
    err = @test_throws ArgumentError read_vmrk(_vmrk("test.vmrk"); codepage="Windows-1252")
    @test occursin("unsupported codepage", err.value.msg)
    @test occursin("Windows-1252", err.value.msg)
end

@testset "bad identification line" begin
    bad = "Not a BrainVision marker file\n[Common Infos]\nDataFile=test.eeg\n"
    err = @test_throws ErrorException OndaVision._parse_vmrk(bad)
    @test occursin("identification", err.value.msg)
    @test occursin("Not a BrainVision marker file", err.value.msg)
end

@testset "empty file" begin
    err = @test_throws ErrorException OndaVision._parse_vmrk("")
    @test occursin("empty", lowercase(err.value.msg))
end

@testset "missing Common Infos section" begin
    content = """
BrainVision Data Exchange Marker File Version 1.0

[Marker Infos]
Mk1=New Segment,,1,1,0
"""
    err = @test_throws ErrorException OndaVision._parse_vmrk(content)
    @test occursin("Common Infos", err.value.msg)
    @test occursin("missing", err.value.msg)
end

@testset "missing Marker Infos section" begin
    content = """
BrainVision Data Exchange Marker File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg
"""
    err = @test_throws ErrorException OndaVision._parse_vmrk(content)
    @test occursin("Marker Infos", err.value.msg)
    @test occursin("missing", err.value.msg)
end

@testset "missing DataFile key" begin
    content = """
BrainVision Data Exchange Marker File Version 1.0

[Common Infos]
Codepage=UTF-8

[Marker Infos]
Mk1=New Segment,,1,1,0
"""
    err = @test_throws ErrorException OndaVision._parse_vmrk(content)
    @test occursin("DataFile", err.value.msg)
    @test occursin("missing", err.value.msg)
end

@testset "non-consecutive marker numbers" begin
    content = """
BrainVision Data Exchange Marker File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg

[Marker Infos]
Mk1=New Segment,,1,1,0
Mk3=Stimulus,S1,100,1,0
"""
    err = @test_throws ErrorException OndaVision._parse_vmrk(content)
    @test occursin("Mk2", err.value.msg)
    @test occursin("missing", err.value.msg)
end

@testset "marker with too few fields" begin
    content = """
BrainVision Data Exchange Marker File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg

[Marker Infos]
Mk1=Stimulus,S1,100,1
"""
    err = @test_throws ErrorException OndaVision._parse_vmrk(content)
    @test occursin("Mk1", err.value.msg)
    @test occursin("fewer than 5", err.value.msg)
end

@testset "invalid marker position — non-integer" begin
    content = """
BrainVision Data Exchange Marker File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg

[Marker Infos]
Mk1=Stimulus,S1,abc,1,0
"""
    err = @test_throws ErrorException OndaVision._parse_vmrk(content)
    @test occursin("position", err.value.msg)
    @test occursin("Mk1", err.value.msg)
    @test occursin("abc", err.value.msg)
end

@testset "invalid marker position — not positive" begin
    content = """
BrainVision Data Exchange Marker File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg

[Marker Infos]
Mk1=Stimulus,S1,0,1,0
"""
    err = @test_throws ErrorException OndaVision._parse_vmrk(content)
    @test occursin("position", err.value.msg)
    @test occursin("Mk1", err.value.msg)
end

@testset "invalid marker points — non-integer" begin
    content = """
BrainVision Data Exchange Marker File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg

[Marker Infos]
Mk1=Stimulus,S1,100,xyz,0
"""
    err = @test_throws ErrorException OndaVision._parse_vmrk(content)
    @test occursin("points", err.value.msg)
    @test occursin("Mk1", err.value.msg)
    @test occursin("xyz", err.value.msg)
end

@testset "invalid marker channel — non-integer" begin
    content = """
BrainVision Data Exchange Marker File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg

[Marker Infos]
Mk1=Stimulus,S1,100,1,all
"""
    err = @test_throws ErrorException OndaVision._parse_vmrk(content)
    @test occursin("channel", err.value.msg)
    @test occursin("Mk1", err.value.msg)
    @test occursin("all", err.value.msg)
end

@testset "missing Codepage warns but does not error" begin
    content = """
BrainVision Data Exchange Marker File Version 1.0

[Common Infos]
DataFile=test.eeg

[Marker Infos]
Mk1=New Segment,,1,1,0
"""
    result = @test_logs (:warn, r"Codepage") OndaVision._parse_vmrk(content)
    @test haskey(result, "Common Infos")
    @test length(result["Marker Infos"].type) == 1
end

@testset "empty Marker Infos section" begin
    content = """
BrainVision Data Exchange Marker File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg

[Marker Infos]
"""
    d = read_vmrk(IOBuffer(content))
    markers = d["Marker Infos"]
    @test markers isa NamedTuple
    @test isempty(markers.type)
    @test isempty(markers.position)
end

@testset "get_segments — single segment" begin
    d = read_vmrk(_vmrk("test.vmrk"))
    segs = get_segments(d)
    @test segs isa NamedTuple
    @test hasproperty(segs, :type)
    @test hasproperty(segs, :position)
    @test hasproperty(segs, :date)
    @test length(segs.type) == 1
    @test segs.type[1] == "New Segment"
    @test segs.position[1] == 1
    @test segs.date[1] == "20131113161403794232"
end

@testset "get_segments — multiple segments" begin
    d = @suppress read_vmrk(_vmrk("test_old_layout_latin1_software_filter.vmrk"))
    segs = get_segments(d)
    @test length(segs.type) == 2
    @test all(==("New Segment"), segs.type)
    @test segs.position[1] == 1
    @test segs.position[2] == 2
    @test segs.date[1] == "20070716122240937454"
    @test segs.date[2] == "20070716122240937455"
end

@testset "get_segments — no segments" begin
    content = """
BrainVision Data Exchange Marker File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg

[Marker Infos]
Mk1=Stimulus,S1,100,1,0
Mk2=Response,R1,200,1,0
"""
    d = read_vmrk(IOBuffer(content))
    segs = get_segments(d)
    @test segs isa NamedTuple
    @test isempty(segs.type)
    @test isempty(segs.position)
    @test isempty(segs.date)
end

@testset "get_segments — non-segment markers excluded" begin
    d = read_vmrk(_vmrk("test.vmrk"))
    segs = get_segments(d)
    # test.vmrk has 14 markers total, only 1 is New Segment
    @test length(segs.type) == 1
    @test length(d["Marker Infos"].type) == 14
    @test all(==("New Segment"), segs.type)
end
