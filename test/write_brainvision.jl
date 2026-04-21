@testset "write_brainvision" begin
    # --- Test 1: Roundtrip INT_16 MULTIPLEXED with annotations and metadata ---
    @testset "roundtrip INT_16 MULTIPLEXED with metadata and annotations" begin
        vhdr_in = "data/test.vhdr"
        isfile(vhdr_in) || error("test data not found: $vhdr_in")

        # Read original
        (signals_in, annotations_in, metadata_in) = read_brainvision_onda(vhdr_in)

        # Write to temporary location
        tmpdir = mktempdir()
        out_path = joinpath(tmpdir, "roundtrip")
        vhdr_out = write_brainvision(out_path, signals_in; annotations=annotations_in,
                                     metadata=metadata_in)

        # Verify file was created
        @test isfile(vhdr_out)
        @test isfile(replace(vhdr_out, ".vhdr" => ".eeg"))
        @test isfile(replace(vhdr_out, ".vhdr" => ".vmrk"))

        # Read back
        (signals_out, annotations_out, metadata_out) = read_brainvision_onda(vhdr_out)

        # --- Verify signals ---
        @test length(signals_out) == length(signals_in)
        # Channels may be reordered due to unit/resolution grouping, so check set equality
        all_channels_in = vcat([s.channels for s in signals_in]...)
        all_channels_out = vcat([s.channels for s in signals_out]...)
        @test Set(all_channels_out) == Set(all_channels_in)

        # Check sample rates and types match
        for i in eachindex(signals_in)
            sig_in = signals_in[i]
            sig_out = signals_out[i]
            @test sig_out.sample_rate == sig_in.sample_rate
            @test sig_out.sample_type == sig_in.sample_type
        end

        # Verify sample data roundtrip (load all samples from both sets)
        for i in eachindex(signals_in)
            samples_in = Onda.load(signals_in[i]).data
            samples_out = Onda.load(signals_out[i]).data
            # Data should match (allowing small numeric tolerance)
            @test samples_in ≈ samples_out atol = 1e-6
        end

        # --- Verify annotations ---
        @test length(annotations_out.span) == length(annotations_in.span)
        @test annotations_out.marker_type == annotations_in.marker_type
        @test annotations_out.description == annotations_in.description

        # Verify span roundtrip (allow small rounding errors in TimeSpans arithmetic)
        for i in eachindex(annotations_in.span)
            span_in = annotations_in.span[i]
            span_out = annotations_out.span[i]
            # Check sample ranges are same length (guards against off-by-one errors)
            rng_in = TimeSpans.index_from_time(signals_in[1].sample_rate, span_in)
            rng_out = TimeSpans.index_from_time(signals_out[1].sample_rate, span_out)
            @test length(rng_in) == length(rng_out)
            # Allow small rounding error in start position (within 1 sample)
            @test abs(first(rng_in) - first(rng_out)) <= 1
        end

        # --- Verify metadata ---
        @test metadata_out.channel_names == metadata_in.channel_names
        @test metadata_out.channel_references == metadata_in.channel_references

        # Cleanup
        rm(tmpdir; recursive=true)
    end

    # --- Test 2: Roundtrip IEEE_FLOAT_32 (was VECTORIZED on read, becomes MULTIPLEXED on write) ---
    @testset "roundtrip IEEE_FLOAT_32 VECTORIZED" begin
        vhdr_in = "data/test_float32_vectorized.vhdr"
        isfile(vhdr_in) || error("test data not found: $vhdr_in")

        # Read original
        (signals_in, annotations_in, metadata_in) = read_brainvision_onda(vhdr_in)

        # Write to temporary location
        tmpdir = mktempdir()
        out_path = joinpath(tmpdir, "roundtrip_float")
        vhdr_out = write_brainvision(out_path, signals_in; annotations=annotations_in,
                                     metadata=metadata_in)

        # Verify file was created
        @test isfile(vhdr_out)
        @test isfile(replace(vhdr_out, ".vhdr" => ".eeg"))
        @test isfile(replace(vhdr_out, ".vhdr" => ".vmrk"))

        # Read back
        (signals_out, annotations_out, metadata_out) = read_brainvision_onda(vhdr_out)

        # Verify signals
        @test length(signals_out) == length(signals_in)
        for i in eachindex(signals_in)
            sig_in = signals_in[i]
            sig_out = signals_out[i]

            @test sig_out.channels == sig_in.channels
            @test sig_out.sample_rate == sig_in.sample_rate
            @test sig_out.sample_unit == sig_in.sample_unit
            @test sig_out.sample_type == sig_in.sample_type

            # Sample data should match
            samples_in = Onda.load(sig_in).data
            samples_out = Onda.load(sig_out).data
            @test samples_in ≈ samples_out atol = 1e-6
        end

        # Cleanup
        rm(tmpdir; recursive=true)
    end

    # --- Test 3: Write without annotations (no VMRK file) ---
    @testset "write without annotations" begin
        vhdr_in = "data/test.vhdr"
        (signals_in, _, metadata_in) = read_brainvision_onda(vhdr_in)

        tmpdir = mktempdir()
        out_path = joinpath(tmpdir, "no_markers")
        vhdr_out = write_brainvision(out_path, signals_in; metadata=metadata_in)

        # Verify VMRK file was NOT created
        @test !isfile(replace(vhdr_out, ".vhdr" => ".vmrk"))

        # Verify VHDR contains no MarkerFile key
        vhdr = read_vhdr(vhdr_out)
        @test !haskey(vhdr["Common Infos"], "MarkerFile") ||
              isempty(vhdr["Common Infos"]["MarkerFile"])

        # Cleanup
        rm(tmpdir; recursive=true)
    end

    # --- Test 4: Write without metadata (use lowercase channel names) ---
    @testset "write without metadata" begin
        vhdr_in = "data/test.vhdr"
        (signals_in, annotations_in, _) = read_brainvision_onda(vhdr_in)

        tmpdir = mktempdir()
        out_path = joinpath(tmpdir, "no_metadata")
        vhdr_out = write_brainvision(out_path, signals_in; annotations=annotations_in)

        # Read back and verify
        (signals_out, _, metadata_out) = read_brainvision_onda(vhdr_out)
        @test length(signals_out) == length(signals_in)

        # Cleanup
        rm(tmpdir; recursive=true)
    end

    # --- Test 5: Extension stripping ---
    @testset "extension stripping" begin
        vhdr_in = "data/test.vhdr"
        (signals_in, annotations_in, metadata_in) = read_brainvision_onda(vhdr_in)

        tmpdir = mktempdir()

        # Pass path with .vhdr extension
        out_path_1 = joinpath(tmpdir, "with_ext.vhdr")
        vhdr_out_1 = write_brainvision(out_path_1, signals_in;
                                       annotations=annotations_in,
                                       metadata=metadata_in)
        @test vhdr_out_1 == joinpath(tmpdir, "with_ext.vhdr")

        # Pass path with .eeg extension
        out_path_2 = joinpath(tmpdir, "with_ext2.eeg")
        vhdr_out_2 = write_brainvision(out_path_2, signals_in;
                                       annotations=annotations_in,
                                       metadata=metadata_in)
        @test vhdr_out_2 == joinpath(tmpdir, "with_ext2.vhdr")

        # Pass path without extension
        out_path_3 = joinpath(tmpdir, "no_ext")
        vhdr_out_3 = write_brainvision(out_path_3, signals_in;
                                       annotations=annotations_in,
                                       metadata=metadata_in)
        @test vhdr_out_3 == joinpath(tmpdir, "no_ext.vhdr")

        rm(tmpdir; recursive=true)
    end
end
