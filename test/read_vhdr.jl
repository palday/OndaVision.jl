const DATA_DIR = joinpath(@__DIR__, "data")
vhdr(name) = joinpath(DATA_DIR, name)

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
        @test ci isa Dict{String, String}
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

        d_float32 = read_vhdr(vhdr("test_old_layout_latin1_software_filter.vhdr"))
        @test d_float32["Binary Infos"]["BinaryFormat"] == "IEEE_FLOAT_32"
    end

    @testset "Channel Infos section" begin
        d = read_vhdr(vhdr("test.vhdr"))
        ch = d["Channel Infos"]
        @test ch isa Dict{String, String}

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
        d = read_vhdr(vhdr("test_old_layout_latin1_software_filter_longname.vhdr"))
        @test d["Channel Infos"]["Ch2"] == "F3 3 part,,0.1"
    end

    @testset "DataOrientation variants" begin
        d_mux = read_vhdr(vhdr("test.vhdr"))
        @test d_mux["Common Infos"]["DataOrientation"] == "MULTIPLEXED"

        d_vec = read_vhdr(vhdr("test_old_layout_latin1_software_filter.vhdr"))
        @test d_vec["Common Infos"]["DataOrientation"] == "VECTORIZED"
    end

    @testset "Coordinates section" begin
        d = read_vhdr(vhdr("testv2.vhdr"))
        @test haskey(d, "Coordinates")
        coords = d["Coordinates"]
        @test coords isa Dict{String, String}
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
        @test d["User Infos"] isa Dict{String, String}
        @test isempty(d["User Infos"])

        @test haskey(d, "Channel User Infos")
        @test isempty(d["Channel User Infos"])
    end

    @testset "Latin-1 encoding auto-detected" begin
        # File has no Codepage key — should be treated as Latin-1
        d = read_vhdr(vhdr("test_old_layout_latin1_software_filter.vhdr"))
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
        d_auto_latin1 = read_vhdr(vhdr("test_old_layout_latin1_software_filter.vhdr"))
        d_explicit_latin1 = read_vhdr(vhdr("test_old_layout_latin1_software_filter.vhdr");
                                       codepage="Latin-1")
        @test d_auto_latin1 == d_explicit_latin1
    end

    @testset "IO interface" begin
        # read_vhdr(io::IO) works identically to read_vhdr(filename)
        expected = read_vhdr(vhdr("test.vhdr"))
        result = open(vhdr("test.vhdr"), "r") do io
            read_vhdr(io)
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
