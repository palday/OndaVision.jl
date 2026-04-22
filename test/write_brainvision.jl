@testset "write_brainvision" begin
    # --- Test 1: Roundtrip INT_16 MULTIPLEXED with annotations and metadata ---
    @testset "roundtrip INT_16 MULTIPLEXED with metadata and annotations" begin
        vhdr_in = "data/test.vhdr"
        isfile(vhdr_in) || error("test data not found: $vhdr_in")

        # Read original
        (signals_in, annotations_in, metadata_in) = @suppress read_brainvision_onda(vhdr_in)

        mktempdir() do tempdir
            out_path = joinpath(tempdir, "roundtrip")
            vhdr_out = @suppress write_brainvision(out_path, signals_in;
                                                   annotations=annotations_in,
                                                   metadata=metadata_in)

            # Verify file was created
            @test isfile(vhdr_out)
            @test isfile(replace(vhdr_out, ".vhdr" => ".eeg"))
            @test isfile(replace(vhdr_out, ".vhdr" => ".vmrk"))

            # Read back
            (signals_out, annotations_out, metadata_out) = @suppress read_brainvision_onda(vhdr_out)

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

            return nothing
        end
    end

    # --- Test 2: Roundtrip IEEE_FLOAT_32 (was VECTORIZED on read, becomes MULTIPLEXED on write) ---
    @testset "roundtrip IEEE_FLOAT_32 VECTORIZED" begin
        vhdr_in = "data/test_float32_vectorized.vhdr"
        isfile(vhdr_in) || error("test data not found: $vhdr_in")

        # Read original
        (signals_in, annotations_in, metadata_in) = @suppress read_brainvision_onda(vhdr_in)

        mktempdir() do tempdir
            out_path = joinpath(tempdir, "roundtrip_float")
            vhdr_out = @suppress write_brainvision(out_path, signals_in;
                                                   annotations=annotations_in,
                                                   metadata=metadata_in)

            # Verify file was created
            @test isfile(vhdr_out)
            @test isfile(replace(vhdr_out, ".vhdr" => ".eeg"))
            @test isfile(replace(vhdr_out, ".vhdr" => ".vmrk"))

            # Read back
            (signals_out, annotations_out, metadata_out) = @suppress read_brainvision_onda(vhdr_out)

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

            return nothing
        end
    end

    # --- Test 3: Write without annotations (no VMRK file) ---
    @testset "write without annotations" begin
        vhdr_in = "data/test.vhdr"
        (signals_in, _, metadata_in) = @suppress read_brainvision_onda(vhdr_in)

        mktempdir() do tempdir
            out_path = joinpath(tempdir, "no_markers")
            vhdr_out = @suppress write_brainvision(out_path, signals_in;
                                                   metadata=metadata_in)

            # Verify VMRK file was NOT created
            @test !isfile(replace(vhdr_out, ".vhdr" => ".vmrk"))

            # Verify VHDR contains no MarkerFile key
            vhdr = @suppress read_vhdr(vhdr_out)
            @test !haskey(vhdr["Common Infos"], "MarkerFile") ||
                  isempty(vhdr["Common Infos"]["MarkerFile"])

            return nothing
        end
    end

    # --- Test 4: Write without metadata (use lowercase channel names) ---
    @testset "write without metadata" begin
        vhdr_in = "data/test.vhdr"
        (signals_in, annotations_in, _) = @suppress read_brainvision_onda(vhdr_in)

        mktempdir() do tempdir
            out_path = joinpath(tempdir, "no_metadata")
            vhdr_out = @suppress write_brainvision(out_path, signals_in;
                                                   annotations=annotations_in)

            # Read back and verify
            (signals_out, _, metadata_out) = @suppress read_brainvision_onda(vhdr_out)
            @test length(signals_out) == length(signals_in)

            return nothing
        end
    end

    # --- Test 5: Extension stripping ---
    @testset "extension stripping" begin
        vhdr_in = "data/test.vhdr"
        (signals_in, annotations_in, metadata_in) = @suppress read_brainvision_onda(vhdr_in)

        mktempdir() do tempdir
            # Pass path with .vhdr extension
            out_path_1 = joinpath(tempdir, "with_ext.vhdr")
            vhdr_out_1 = @suppress write_brainvision(out_path_1, signals_in;
                                                     annotations=annotations_in,
                                                     metadata=metadata_in)
            @test vhdr_out_1 == joinpath(tempdir, "with_ext.vhdr")

            # Pass path with .eeg extension
            out_path_2 = joinpath(tempdir, "with_ext2.eeg")
            vhdr_out_2 = @suppress write_brainvision(out_path_2, signals_in;
                                                     annotations=annotations_in,
                                                     metadata=metadata_in)
            @test vhdr_out_2 == joinpath(tempdir, "with_ext2.vhdr")

            # Pass path without extension
            out_path_3 = joinpath(tempdir, "no_ext")
            vhdr_out_3 = @suppress write_brainvision(out_path_3, signals_in;
                                                     annotations=annotations_in,
                                                     metadata=metadata_in)
            @test vhdr_out_3 == joinpath(tempdir, "no_ext.vhdr")

            return nothing
        end
    end

    # --- Test 6: _julia_sample_type error on unsupported type ---
    @testset "_julia_sample_type error" begin
        @test_throws ErrorException OndaVision._julia_sample_type("float64")
    end

    # --- Test 7: Roundtrip preserves electrode coordinates ---
    @testset "roundtrip preserves coordinates" begin
        vhdr_in = "data/testv2.vhdr"
        (signals_in, annotations_in, metadata_in) = @suppress read_brainvision_onda(vhdr_in)
        @test !isempty(metadata_in.coordinates.channel)  # sanity: testv2 has coordinates

        mktempdir() do tempdir
            out_path = joinpath(tempdir, "roundtrip_coords")
            vhdr_out = @suppress write_brainvision(out_path, signals_in;
                                                   annotations=annotations_in,
                                                   metadata=metadata_in)

            (_, _, metadata_out) = @suppress read_brainvision_onda(vhdr_out)
            @test !isempty(metadata_out.coordinates.channel)
            @test length(metadata_out.coordinates.channel) ==
                  length(metadata_in.coordinates.channel)
            @test metadata_out.coordinates.radius == metadata_in.coordinates.radius
            @test metadata_out.coordinates.theta == metadata_in.coordinates.theta
            @test metadata_out.coordinates.phi == metadata_in.coordinates.phi

            return nothing
        end
    end

    # --- Test 8: Write [User Infos] and [Channel User Infos] sections ---
    @testset "write user_infos and channel_user_infos" begin
        vhdr_in = "data/test.vhdr"
        (signals_in, _, meta_base) = @suppress read_brainvision_onda(vhdr_in)

        meta = BrainVisionMetadata(meta_base.channel_names,
                                   meta_base.channel_references,
                                   meta_base.coordinates,
                                   meta_base.amplifier_info,
                                   meta_base.amplifier_channels,
                                   meta_base.software_filters,
                                   meta_base.impedances,
                                   meta_base.comment,
                                   Dict("Source" => "TestData"),
                                   Dict("FP1" => "FrontalLeft"),
                                   meta_base.marker_dates)

        mktempdir() do tempdir
            out_path = joinpath(tempdir, "with_infos")
            vhdr_out = @suppress write_brainvision(out_path, signals_in; metadata=meta)

            vhdr_dict = @suppress read_vhdr(vhdr_out)
            @test haskey(vhdr_dict, "User Infos")
            @test vhdr_dict["User Infos"]["Source"] == "TestData"
            @test haskey(vhdr_dict, "Channel User Infos")
            @test vhdr_dict["Channel User Infos"]["FP1"] == "FrontalLeft"

            return nothing
        end
    end

    # --- Test 9: Annotations without initial New Segment, string channel, marker_dates ---
    @testset "write annotations without initial New Segment" begin
        vhdr_in = "data/test_highpass.vhdr"
        (signals_in, _, meta_base) = @suppress read_brainvision_onda(vhdr_in)
        sample_rate = signals_in[1].sample_rate
        ch_names_lower = lowercase.(meta_base.channel_names)

        # Annotations starting with Stimulus (not New Segment), string channel
        ann = (; recording=fill(signals_in[1].recording, 1),
               id=[uuid4()],
               span=[TimeSpans.time_from_index(sample_rate, 100:100)],
               marker_type=["Stimulus"],
               description=["S1"],
               channel=Union{String,Missing}[ch_names_lower[1]])

        # marker_dates: index 1 for the synthetic New Segment, index 2 for the annotation
        meta = BrainVisionMetadata(meta_base.channel_names,
                                   meta_base.channel_references,
                                   meta_base.coordinates,
                                   meta_base.amplifier_info,
                                   meta_base.amplifier_channels,
                                   meta_base.software_filters,
                                   meta_base.impedances,
                                   meta_base.comment,
                                   meta_base.user_infos,
                                   meta_base.channel_user_infos,
                                   Union{String,Missing}["20230101120000000000",
                                                         "20230101120001000000"])

        mktempdir() do tempdir
            out_path = joinpath(tempdir, "no_seg")
            vhdr_out = @suppress write_brainvision(out_path, signals_in;
                                                   annotations=ann,
                                                   metadata=meta)

            vmrk = @suppress read_vmrk(replace(vhdr_out, ".vhdr" => ".vmrk"))
            markers = vmrk["Marker Infos"]

            # A synthetic New Segment is prepended with date from marker_dates[1]
            @test markers.type[1] == "New Segment"
            @test markers.date[1] == "20230101120000000000"

            # Our Stimulus annotation follows with date from marker_dates[2]
            @test markers.type[2] == "Stimulus"
            @test markers.description[2] == "S1"
            @test markers.date[2] == "20230101120001000000"

            return nothing
        end
    end
end
