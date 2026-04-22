@testset "identification line" begin
    # v1.0 — old-style identification with space between Brain/Vision
    d = read_vhdr(vhdr("test.vhdr"))
    @test d["identification"] == "Brain Vision Data Exchange Header File Version 1.0"

    # v2.0 identification
    d2 = read_vhdr(vhdr("testv2.vhdr"))
    @test d2["identification"] == "Brain Vision Data Exchange Header File Version 2.0"
end

@testset "Common Infos section" begin
    d = read_vhdr(vhdr("test.vhdr"))
    ci = d["Common Infos"]
    @test ci isa Dict{String,String}
    @test ci["Codepage"] == "UTF-8"
    @test ci["DataFile"] == "test.eeg"
    @test ci["MarkerFile"] == "test.vmrk"
    @test ci["DataFormat"] == "BINARY"
    @test ci["DataOrientation"] == "MULTIPLEXED"
    @test ci["NumberOfChannels"] == "32"
    @test ci["SamplingInterval"] == "1000"
end

@testset "Binary Infos section" begin
    d_int16 = read_vhdr(vhdr("test.vhdr"))
    @test d_int16["Binary Infos"]["BinaryFormat"] == "INT_16"

    d_float32 = @suppress read_vhdr(vhdr("test_old_layout_latin1_software_filter.vhdr"))
    @test d_float32["Binary Infos"]["BinaryFormat"] == "IEEE_FLOAT_32"
end

@testset "Channel Infos section" begin
    d = read_vhdr(vhdr("test.vhdr"))
    ch = d["Channel Infos"]
    @test ch isa Dict{String,String}

    # All 32 channels are present
    @test length(ch) == 32
    for i in 1:32
        @test haskey(ch, "Ch$i")
    end

    # Full four-field entry: name,ref,resolution,unit
    @test ch["Ch1"] == "FP1,,0.5,µV"

    # Trailing comma with empty unit
    @test ch["Ch2"] == "FP2,,0.5,"

    # Missing unit field entirely
    @test ch["Ch3"] == "F3,,0.5"

    # Last channel
    @test ch["Ch32"] == "ReRef,,0.5,C"
end

@testset "channel names with spaces" begin
    d = @suppress read_vhdr(vhdr("test_old_layout_latin1_software_filter_longname.vhdr"))
    @test d["Channel Infos"]["Ch2"] == "F3 3 part,,0.1"
end

@testset "DataOrientation variants" begin
    d_mux = read_vhdr(vhdr("test.vhdr"))
    @test d_mux["Common Infos"]["DataOrientation"] == "MULTIPLEXED"

    d_vec = @suppress read_vhdr(vhdr("test_old_layout_latin1_software_filter.vhdr"))
    @test d_vec["Common Infos"]["DataOrientation"] == "VECTORIZED"
end

@testset "Coordinates section" begin
    d = read_vhdr(vhdr("testv2.vhdr"))
    @test haskey(d, "Coordinates")
    coords = d["Coordinates"]
    @test coords isa Dict{String,String}
    @test length(coords) == 32

    # Standard EEG electrode with non-zero radius
    @test coords["Ch1"] == "1,-90,-72"

    # Non-EEG channel: r=0 indicates invalid/unknown position
    @test coords["Ch29"] == "0,0,0"
end

@testset "Comment section" begin
    d = read_vhdr(vhdr("test.vhdr"))
    @test haskey(d, "Comment")
    @test d["Comment"] isa String
    # Contains amplifier setup and channel listing
    @test occursin("A m p l i f i e r", d["Comment"])
    @test occursin("FP1", d["Comment"])

    # Semicolons inside [Comment] are not treated as INI comments —
    # they must be preserved verbatim in the comment text
    d_semi = read_vhdr(vhdr("test_mixed_lowpass.vhdr"))
    @test occursin("; this is a comment", d_semi["Comment"])
end

@testset "no Comment section" begin
    # testv2.vhdr has no [Comment] section
    d = read_vhdr(vhdr("testv2.vhdr"))
    @test !haskey(d, "Comment")
end

@testset "INI-style comments excluded from sections" begin
    # Lines beginning with ; outside [Comment] must not appear as keys
    d = read_vhdr(vhdr("test.vhdr"))
    for section_value in values(d)
        section_value isa Dict || continue
        for key in keys(section_value)
            @test !startswith(key, ";")
        end
    end
end

@testset "v2 extra sections" begin
    d = read_vhdr(vhdr("testv2.vhdr"))
    # User Infos and Channel User Infos exist but contain only ; comments
    @test haskey(d, "User Infos")
    @test d["User Infos"] isa Dict{String,String}
    @test isempty(d["User Infos"])

    @test haskey(d, "Channel User Infos")
    @test isempty(d["Channel User Infos"])
end

@testset "Latin-1 encoding auto-detected" begin
    # File has no Codepage key — should be treated as Latin-1
    d = @suppress read_vhdr(vhdr("test_old_layout_latin1_software_filter.vhdr"))
    ci = d["Common Infos"]
    @test !haskey(ci, "Codepage")
    @test ci["DataFile"] == "test_old_layout_latin1_software_filter.eeg"
    @test ci["NumberOfChannels"] == "29"
    @test ci["SamplingInterval"] == "4000"
    # All 29 channels parsed correctly
    @test length(d["Channel Infos"]) == 29
    @test d["Channel Infos"]["Ch1"] == "F7,,0.1"
end

@testset "codepage keyword" begin
    # Explicit UTF-8 gives the same result as auto-detection
    d_auto = read_vhdr(vhdr("test.vhdr"))
    d_explicit = read_vhdr(vhdr("test.vhdr"); codepage="UTF-8")
    @test d_auto == d_explicit

    # Explicit Latin-1 on a Latin-1 file gives the same result as auto-detection
    d_auto_latin1 = @suppress read_vhdr(vhdr("test_old_layout_latin1_software_filter.vhdr"))
    d_explicit_latin1 = @suppress read_vhdr(vhdr("test_old_layout_latin1_software_filter.vhdr");
                                            codepage="Latin-1")
    @test d_auto_latin1 == d_explicit_latin1
end

@testset "IO interface" begin
    # read_vhdr(io::IO) works identically to read_vhdr(filename)
    expected = read_vhdr(vhdr("test.vhdr"))
    result = open(vhdr("test.vhdr"), "r") do io
        return read_vhdr(io)
    end
    @test result == expected

    # Also works with an IOBuffer
    bytes = read(vhdr("testv2.vhdr"))
    buf_result = read_vhdr(IOBuffer(bytes))
    file_result = read_vhdr(vhdr("testv2.vhdr"))
    @test buf_result == file_result
end

@testset "varied channel units" begin
    d = read_vhdr(vhdr("test_units.vhdr"))
    ch = d["Channel Infos"]
    @test ch["Ch1"] == "FP1,,500,nV"
    @test ch["Ch2"] == "FP2,,0.0005,mV"
    @test ch["Ch3"] == "F3,,0.0000005,V"
    @test ch["Ch4"] == "F4,,0.5,uV"
    @test ch["Ch5"] == "C3,,0.5,µV"
end

@testset "unsupported codepage keyword" begin
    err = @test_throws ArgumentError read_vhdr(vhdr("test.vhdr"); codepage="Windows-1252")
    @test occursin("unsupported codepage", err.value.msg)
    @test occursin("Windows-1252", err.value.msg)
    @test occursin("UTF-8", err.value.msg)
end

@testset "bad identification line" begin
    bad = "Not a BrainVision file\n[Common Infos]\n"
    err = @test_throws ErrorException OndaVision._parse_vhdr(bad)
    @test occursin("identification", err.value.msg)
    @test occursin("Not a BrainVision file", err.value.msg)
end

@testset "empty file" begin
    err = @test_throws ErrorException OndaVision._parse_vhdr("")
    @test occursin("empty", lowercase(err.value.msg))
end

@testset "missing mandatory section" begin
    # Missing [Binary Infos]
    content = """
Brain Vision Data Exchange Header File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg
DataFormat=BINARY
DataOrientation=MULTIPLEXED
NumberOfChannels=1
SamplingInterval=1000

[Channel Infos]
Ch1=Fp1,,0.5,µV
"""
    err = @test_throws ErrorException OndaVision._parse_vhdr(content)
    @test occursin("Binary Infos", err.value.msg)
    @test occursin("missing", err.value.msg)
end

@testset "missing mandatory Common Infos key" begin
    # Missing SamplingInterval
    content = """
Brain Vision Data Exchange Header File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg
DataFormat=BINARY
DataOrientation=MULTIPLEXED
NumberOfChannels=1

[Binary Infos]
BinaryFormat=INT_16

[Channel Infos]
Ch1=Fp1,,0.5,µV
"""
    err = @test_throws ErrorException OndaVision._parse_vhdr(content)
    @test occursin("SamplingInterval", err.value.msg)
    @test occursin("missing", err.value.msg)
end

@testset "channel count mismatch" begin
    # NumberOfChannels=3 but only 2 entries
    content = """
Brain Vision Data Exchange Header File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg
DataFormat=BINARY
DataOrientation=MULTIPLEXED
NumberOfChannels=3
SamplingInterval=1000

[Binary Infos]
BinaryFormat=INT_16

[Channel Infos]
Ch1=Fp1,,0.5,µV
Ch2=Fp2,,0.5,µV
"""
    err = @test_throws ErrorException OndaVision._parse_vhdr(content)
    @test occursin("NumberOfChannels is 3", err.value.msg)
    @test occursin("2 channel entries were found", err.value.msg)
end

@testset "non-consecutive channel numbers" begin
    # Ch2 is skipped; Ch3 is present instead
    content = """
Brain Vision Data Exchange Header File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg
DataFormat=BINARY
DataOrientation=MULTIPLEXED
NumberOfChannels=2
SamplingInterval=1000

[Binary Infos]
BinaryFormat=INT_16

[Channel Infos]
Ch1=Fp1,,0.5,µV
Ch3=Fp2,,0.5,µV
"""
    err = @test_throws ErrorException OndaVision._parse_vhdr(content)
    @test occursin("Ch2", err.value.msg)
    @test occursin("missing", err.value.msg)
end

@testset "coordinates count mismatch" begin
    # 2 channels but only 1 coordinate entry
    content = """
Brain Vision Data Exchange Header File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg
DataFormat=BINARY
DataOrientation=MULTIPLEXED
NumberOfChannels=2
SamplingInterval=1000

[Binary Infos]
BinaryFormat=INT_16

[Channel Infos]
Ch1=Fp1,,0.5,µV
Ch2=Fp2,,0.5,µV

[Coordinates]
Ch1=1,0,0
"""
    err = @test_throws ErrorException OndaVision._parse_vhdr(content)
    @test occursin("Coordinates", err.value.msg)
    @test occursin("2", err.value.msg)
    @test occursin("1 coordinate entry was found", err.value.msg)
end

@testset "invalid NumberOfChannels value" begin
    content = """
Brain Vision Data Exchange Header File Version 1.0

[Common Infos]
Codepage=UTF-8
DataFile=test.eeg
DataFormat=BINARY
DataOrientation=MULTIPLEXED
NumberOfChannels=abc
SamplingInterval=1000

[Binary Infos]
BinaryFormat=INT_16

[Channel Infos]
Ch1=Fp1,,0.5,µV
"""
    err = @test_throws ErrorException OndaVision._parse_vhdr(content)
    @test occursin("abc", err.value.msg)
    @test occursin("NumberOfChannels", err.value.msg)
end

@testset "parse_amplifier_setup — no amplifier section" begin
    @test parse_amplifier_setup("") === nothing
    @test parse_amplifier_setup("Some free-form comment with no amplifier block") ===
          nothing
    # A file without a Comment section at all
    d = read_vhdr(vhdr("testv2.vhdr"))
    @test !haskey(d, "Comment")
end

@testset "parse_amplifier_setup — info dict (full format)" begin
    d = read_vhdr(vhdr("test.vhdr"))
    result = parse_amplifier_setup(d["Comment"])
    @test result !== nothing
    info, _ = result
    @test info isa Dict{String,String}
    @test info["Number of channels"] == "32"
    @test info["Sampling Rate [Hz]"] == "1000"
    @test info["Sampling Interval [µS]"] == "1000"
end

@testset "parse_amplifier_setup — channel table structure" begin
    d = read_vhdr(vhdr("test.vhdr"))
    _, channels = parse_amplifier_setup(d["Comment"])
    @test channels isa NamedTuple
    @test hasproperty(channels, :number)
    @test hasproperty(channels, :name)
    @test hasproperty(channels, :phys_chn)
    @test hasproperty(channels, :resolution)
    @test hasproperty(channels, :low_cutoff)
    @test hasproperty(channels, :high_cutoff)
    @test hasproperty(channels, :notch)
    # Each column is a Vector{String} with one entry per channel
    @test length(channels.number) == 32
    @test channels.number isa Vector{String}
end

@testset "parse_amplifier_setup — channel table values (full format)" begin
    d = read_vhdr(vhdr("test.vhdr"))
    _, ch = parse_amplifier_setup(d["Comment"])
    # First channel
    @test ch.number[1] == "1"
    @test ch.name[1] == "FP1"
    @test ch.phys_chn[1] == "1"
    @test ch.resolution[1] == "0.5 µV"
    @test ch.low_cutoff[1] == "DC"
    @test ch.high_cutoff[1] == "250"
    @test ch.notch[1] == "Off"
    # Last channel
    @test ch.number[32] == "32"
    @test ch.name[32] == "ReRef"
end

@testset "parse_amplifier_setup — old format (7-column header)" begin
    d = @suppress read_vhdr(vhdr("test_old_layout_latin1_software_filter.vhdr"))
    result = parse_amplifier_setup(d["Comment"])
    @test result !== nothing
    info, ch = result
    @test info["Number of channels"] == "29"
    @test info["Sampling Rate [Hz]"] == "250"
    @test length(ch.number) == 29
    @test ch.name[1] == "F7"
    # Old format resolution column contains only the numeric value, no unit
    @test ch.resolution[1] == "0.1"
    @test ch.low_cutoff[1] == "10"
    @test ch.high_cutoff[1] == "1000"
    @test ch.notch[1] == "Off"
end

@testset "parse_amplifier_setup — channel name with spaces" begin
    # Old-layout file where Ch2 is named "F3 3 part" (internal spaces)
    d = @suppress read_vhdr(vhdr("test_old_layout_latin1_software_filter_longname.vhdr"))
    _, ch = parse_amplifier_setup(d["Comment"])
    @test ch.name[2] == "F3 3 part"

    # Full-format file where Ch28 is named "CP 6" (internal space)
    d2 = read_vhdr(vhdr("test_mixed_lowpass.vhdr"))
    _, ch2 = parse_amplifier_setup(d2["Comment"])
    @test ch2.name[28] == "CP 6"
end

@testset "parse_software_filters — not present / disabled" begin
    @test parse_software_filters("") === nothing
    @test parse_software_filters("Some comment with no software filters") === nothing
    # Sections present but marked Disabled
    d = read_vhdr(vhdr("test.vhdr"))
    @test parse_software_filters(d["Comment"]) === nothing
    d2 = read_vhdr(vhdr("test_units.vhdr"))
    @test parse_software_filters(d2["Comment"]) === nothing
    # No Comment section at all
    d3 = read_vhdr(vhdr("testv2.vhdr"))
    @test !haskey(d3, "Comment")
end

@testset "parse_software_filters — 4-column table (no amplifier setup)" begin
    # Craft a comment with only a Software Filters table and no Amplifier Setup
    comment = """
    S o f t w a r e  F i l t e r s
    ==============================
    #     Low Cutoff [s]   High Cutoff [Hz]   Notch [Hz]
    1      0.9              50                 Off
    2      0.9              50                 Off
    """
    sw = parse_software_filters(comment)
    @test sw !== nothing
    @test sw isa NamedTuple
    @test hasproperty(sw, :number)
    @test !hasproperty(sw, :name)
    @test hasproperty(sw, :low_cutoff)
    @test hasproperty(sw, :high_cutoff)
    @test hasproperty(sw, :notch)
    @test length(sw.number) == 2
    @test sw.number[1] == "1"
    @test sw.low_cutoff[1] == "0.9"
    @test sw.high_cutoff[1] == "50"
    @test sw.notch[1] == "Off"
end

@testset "parse_software_filters — 5-column table (with amplifier names)" begin
    d = @suppress read_vhdr(vhdr("test_old_layout_latin1_software_filter.vhdr"))
    sw = parse_software_filters(d["Comment"])
    @test sw !== nothing
    @test hasproperty(sw, :name)
    @test length(sw.number) == 29
    # First channel: name from Amplifier Setup, filter values from Software Filters
    @test sw.number[1] == "1"
    @test sw.name[1] == "F7"
    @test sw.low_cutoff[1] == "0.9"
    @test sw.high_cutoff[1] == "50"
    @test sw.notch[1] == "50"
    # Last channel
    @test sw.number[29] == "29"
    @test sw.name[29] == "HEOGre"
end

@testset "parse_software_filters — channel name with spaces" begin
    d = @suppress read_vhdr(vhdr("test_old_layout_latin1_software_filter_longname.vhdr"))
    sw = parse_software_filters(d["Comment"])
    @test sw !== nothing
    @test sw.name[2] == "F3 3 part"
end

@testset "parse_impedances — not present" begin
    @test parse_impedances("") === nothing
    @test parse_impedances("Some comment with no impedance block") === nothing
    d = read_vhdr(vhdr("testv2.vhdr"))
    @test !haskey(d, "Comment")
end

@testset "parse_impedances — all unknown (???)" begin
    d = read_vhdr(vhdr("test.vhdr"))
    imp = parse_impedances(d["Comment"])
    @test imp isa Dict{String,Union{Float64,Missing}}
    @test ismissing(imp["FP1"])
    @test ismissing(imp["ReRef"])
    # Ref and Gnd have numeric values even in the all-??? file
    @test imp["Ref"] === 0.0
    @test imp["Gnd"] === 4.0
    @test length(imp) == 34  # 32 channels + Ref + Gnd
end

@testset "parse_impedances — all numeric" begin
    d = @suppress read_vhdr(vhdr("test_old_layout_latin1_software_filter.vhdr"))
    imp = parse_impedances(d["Comment"])
    @test imp isa Dict{String,Union{Float64,Missing}}
    @test imp["F7"] === 0.0
    @test imp["HEOGre"] === 5.0
    @test !any(ismissing, values(imp))
    @test length(imp) == 29
end

@testset "parse_impedances — mixed values and actiCAP preamble" begin
    # test_mixed_lowpass has "Impedances Imported from actiCAP..." before the header
    d = read_vhdr(vhdr("test_mixed_lowpass.vhdr"))
    imp = parse_impedances(d["Comment"])
    @test imp isa Dict{String,Union{Float64,Missing}}
    # Standard channels are unknown
    @test ismissing(imp["FP1"])
    # Non-EEG channels have numeric impedances
    @test imp["ECG+"] === 35.0
    @test imp["ECG-"] === 46.0
    @test imp["Gnd"] === 2.5
end

@testset "parse_impedances — channel name with space" begin
    d = read_vhdr(vhdr("test_mixed_lowpass.vhdr"))
    imp = parse_impedances(d["Comment"])
    @test haskey(imp, "CP 6")
    @test ismissing(imp["CP 6"])

    d2 = @suppress read_vhdr(vhdr("test_old_layout_latin1_software_filter_longname.vhdr"))
    imp2 = parse_impedances(d2["Comment"])
    @test haskey(imp2, "F3 3 part")
    @test imp2["F3 3 part"] === 0.0
end

@testset "missing Codepage warns but does not error" begin
    content = """
Brain Vision Data Exchange Header File Version 1.0

[Common Infos]
DataFile=test.eeg
DataFormat=BINARY
DataOrientation=MULTIPLEXED
NumberOfChannels=1
SamplingInterval=1000

[Binary Infos]
BinaryFormat=INT_16

[Channel Infos]
Ch1=Fp1,,0.5,µV
"""
    result = @test_logs (:warn, r"Codepage") OndaVision._parse_vhdr(content)
    @test haskey(result, "Common Infos")
end
