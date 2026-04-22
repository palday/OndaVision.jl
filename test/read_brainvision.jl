# ---------------------------------------------------------------------------
# PyMNE correctness comparisons
# ---------------------------------------------------------------------------
# All three files contain a single "New Segment" marker and produce a 2-D result.
# MNE and OndaVision must agree element-wise.

@testset "PyMNE comparison — $name" for name in
                                        ["testv2.vhdr", "test_float32_vectorized.vhdr"]
    path = vhdr(name)
    ov = read_brainvision(path)
    mne = _mne_load(path)
    @test size(ov) == size(mne)
    @test all(ov .≈ mne)
end

@testset "PyMNE comparison — test.vhdr (µV channels only)" begin
    # Channels 27–32 have non-µV units (BS, µS, ARU, uS, S, C).
    # MNE applies different per-unit scaling for unknown units (no ×1e-6),
    # so comparing raw MNE output ×1e6 is only valid for the 26 µV channels.
    path = vhdr("test.vhdr")
    ov = read_brainvision(path)
    mne = _mne_load(path)
    @test size(ov) == size(mne)
    @test all(@view(ov[1:26, :]) .≈ @view(mne[1:26, :]))
end

# ---------------------------------------------------------------------------
# Shape and type tests (no PyMNE required)
# ---------------------------------------------------------------------------

@testset "INT_16 MULTIPLEXED single segment" begin
    result = read_brainvision(vhdr("test.vhdr"))
    @test result isa Matrix{Float64}
    # 32 channels, 505600 bytes / (32 ch × 2 bytes) = 7900 samples
    @test size(result) == (32, 7900)
end

@testset "FLOAT32 VECTORIZED single segment" begin
    result = read_brainvision(vhdr("test_float32_vectorized.vhdr"))
    @test result isa Matrix{Float64}
    @test size(result) == (2, 4)
    # ch1 samples [1,2,3,4] and ch2 samples [5,6,7,8], resolution=1.0
    @test result[1, :] == Float64[1, 2, 3, 4]
    @test result[2, :] == Float64[5, 6, 7, 8]
end

@testset "resolution factor is applied" begin
    result = read_brainvision(vhdr("test.vhdr"))
    # INT_16 raw values are up to ±32767; with resolution 0.5 µV, scaled max ≈ ±16383 µV.
    # Without resolution the values would stay as raw Int16 counts.
    @test maximum(abs, result) <= 16384.0
end

@testset "FLOAT32 VECTORIZED multi-segment unequal lengths" begin
    # test_old_layout_latin1_software_filter has two New Segment markers:
    # position 1 (1 sample) and position 2 (250 samples) → unequal lengths.
    # The file also lacks a Codepage key → codepage warning; suppress output.
    result = @suppress read_brainvision(vhdr("test_old_layout_latin1_software_filter.vhdr"))
    @test result isa Vector{Matrix{Float64}}
    @test length(result) == 2
    @test size(result[1]) == (29, 1)
    @test size(result[2]) == (29, 250)
end

@testset "multi-segment equal lengths → 3-D array" begin
    mktempdir() do dir
        # 2 channels, INT_16, MULTIPLEXED, 6 samples, resolution=1.0
        # ch1: [1,2,3,4,5,6], ch2: [11,12,13,14,15,16]
        # MULTIPLEXED binary: ch1_t1,ch2_t1, ch1_t2,ch2_t2, …
        raw = Int16[1, 11, 2, 12, 3, 13, 4, 14, 5, 15, 6, 16]
        open(joinpath(dir, "multiseg.eeg"), "w") do io
            return write(io, htol.(raw))
        end

        write(joinpath(dir, "multiseg.vhdr"), """
            BrainVision Data Exchange Header File Version 1.0
            [Common Infos]
            Codepage=UTF-8
            DataFile=multiseg.eeg
            MarkerFile=multiseg.vmrk
            DataFormat=BINARY
            DataOrientation=MULTIPLEXED
            NumberOfChannels=2
            SamplingInterval=1000
            [Binary Infos]
            BinaryFormat=INT_16
            [Channel Infos]
            Ch1=Ch1,,1.0,µV
            Ch2=Ch2,,1.0,µV
            """)

        write(joinpath(dir, "multiseg.vmrk"), """
            BrainVision Data Exchange Marker File Version 1.0
            [Common Infos]
            Codepage=UTF-8
            DataFile=multiseg.eeg
            [Marker Infos]
            Mk1=New Segment,,1,1,0
            Mk2=New Segment,,4,1,0
            """)

        result = read_brainvision(joinpath(dir, "multiseg.vhdr"))
        @test result isa Array{Float64,3}
        @test size(result) == (2, 3, 2)
        # Segment 1: samples 1–3
        @test result[:, :, 1] == Float64[1 2 3; 11 12 13]
        # Segment 2: samples 4–6
        @test result[:, :, 2] == Float64[4 5 6; 14 15 16]
    end
end

@testset "VMRK DataFile mismatch → warning" begin
    mktempdir() do dir
        cp(vhdr("test.eeg"), joinpath(dir, "test.eeg"))

        write(joinpath(dir, "mismatch.vmrk"), """
            BrainVision Data Exchange Marker File Version 1.0
            [Common Infos]
            Codepage=UTF-8
            DataFile=wrong.eeg
            [Marker Infos]
            Mk1=New Segment,,1,1,0
            """)

        write(joinpath(dir, "test.vhdr"),
              """
BrainVision Data Exchange Header File Version 1.0
[Common Infos]
Codepage=UTF-8
DataFile=test.eeg
MarkerFile=mismatch.vmrk
DataFormat=BINARY
DataOrientation=MULTIPLEXED
NumberOfChannels=32
SamplingInterval=1000
[Binary Infos]
BinaryFormat=INT_16
[Channel Infos]
""" * join(["Ch$i=Ch$i,,0.5,µV" for i in 1:32], "\n") * "\n")

        @suppress @test_logs (:warn, r"DataFile.*differs|differs.*DataFile") begin
            result = read_brainvision(joinpath(dir, "test.vhdr"))
            @test result isa Matrix{Float64}
        end
    end
end

@testset "missing VMRK file → warning, returns 2-D" begin
    mktempdir() do dir
        cp(vhdr("test.eeg"), joinpath(dir, "test.eeg"))

        write(joinpath(dir, "test.vhdr"),
              """
BrainVision Data Exchange Header File Version 1.0
[Common Infos]
Codepage=UTF-8
DataFile=test.eeg
MarkerFile=nonexistent.vmrk
DataFormat=BINARY
DataOrientation=MULTIPLEXED
NumberOfChannels=32
SamplingInterval=1000
[Binary Infos]
BinaryFormat=INT_16
[Channel Infos]
""" * join(["Ch$i=Ch$i,,0.5,µV" for i in 1:32], "\n") * "\n")

        @suppress @test_logs (:warn, r"marker file.*not found") begin
            result = read_brainvision(joinpath(dir, "test.vhdr"))
            @test result isa Matrix{Float64}
            @test size(result) == (32, 7900)
        end
    end
end

@testset "missing EEG file → error" begin
    mktempdir() do dir
        write(joinpath(dir, "empty.vhdr"), """
            BrainVision Data Exchange Header File Version 1.0
            [Common Infos]
            Codepage=UTF-8
            DataFile=nonexistent.eeg
            DataFormat=BINARY
            DataOrientation=MULTIPLEXED
            NumberOfChannels=1
            SamplingInterval=1000
            [Binary Infos]
            BinaryFormat=INT_16
            [Channel Infos]
            Ch1=Ch1,,1.0,µV
            """)

        @test_throws ErrorException read_brainvision(joinpath(dir, "empty.vhdr"))
    end
end

@testset "unsupported BinaryFormat → error" begin
    mktempdir() do dir
        write(joinpath(dir, "bad.vhdr"), """
            BrainVision Data Exchange Header File Version 1.0
            [Common Infos]
            Codepage=UTF-8
            DataFile=bad.eeg
            DataFormat=BINARY
            DataOrientation=MULTIPLEXED
            NumberOfChannels=1
            SamplingInterval=1000
            [Binary Infos]
            BinaryFormat=UINT_8
            [Channel Infos]
            Ch1=Ch1,,1.0,µV
            """)

        @test_throws ErrorException read_brainvision(joinpath(dir, "bad.vhdr"))
    end
end

@testset "unsupported DataOrientation → error" begin
    mktempdir() do dir
        write(joinpath(dir, "bad.vhdr"), """
            BrainVision Data Exchange Header File Version 1.0
            [Common Infos]
            Codepage=UTF-8
            DataFile=bad.eeg
            DataFormat=BINARY
            DataOrientation=ROWMAJOR
            NumberOfChannels=1
            SamplingInterval=1000
            [Binary Infos]
            BinaryFormat=INT_16
            [Channel Infos]
            Ch1=Ch1,,1.0,µV
            """)

        @test_throws ErrorException read_brainvision(joinpath(dir, "bad.vhdr"))
    end
end

@testset "unsupported DataType → error" begin
    mktempdir() do dir
        write(joinpath(dir, "bad.vhdr"), """
            BrainVision Data Exchange Header File Version 1.0
            [Common Infos]
            Codepage=UTF-8
            DataFile=bad.eeg
            DataFormat=BINARY
            DataOrientation=MULTIPLEXED
            DataType=FREQUENCYDOMAIN
            NumberOfChannels=1
            SamplingInterval=1000
            [Binary Infos]
            BinaryFormat=INT_16
            [Channel Infos]
            Ch1=Ch1,,1.0,µV
            """)

        @test_throws ErrorException read_brainvision(joinpath(dir, "bad.vhdr"))
    end
end

@testset "EEG data size not divisible by sample size → error" begin
    mktempdir() do dir
        # Write 3 bytes — not divisible by sizeof(Int16)=2
        write(joinpath(dir, "odd.eeg"), UInt8[0x01, 0x02, 0x03])

        write(joinpath(dir, "odd.vhdr"), """
            BrainVision Data Exchange Header File Version 1.0
            [Common Infos]
            Codepage=UTF-8
            DataFile=odd.eeg
            DataFormat=BINARY
            DataOrientation=MULTIPLEXED
            NumberOfChannels=1
            SamplingInterval=1000
            [Binary Infos]
            BinaryFormat=INT_16
            [Channel Infos]
            Ch1=Ch1,,1.0,µV
            """)

        @test_throws ErrorException read_brainvision(joinpath(dir, "odd.vhdr"))
    end
end
