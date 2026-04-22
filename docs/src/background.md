```@meta
CurrentModule = OndaVision
```

# Background

## The BrainVision Core Data Format

[BrainVision](https://www.brainproducts.com/support-resources/brainvision-core-data-format-1-0/)
is a widely used file format for electrophysiological time-series data
(EEG, EMG, EOG, and similar biosignals).  A complete recording consists
of three files that share the same base name:

| File | Extension | Contents |
|:-----|:----------|:---------|
| Header file | `.vhdr` | INI-style text file; describes channel count, sampling rate, binary format, and links to the other two files |
| Data file | `.eeg` | Raw binary samples (INT\_16 or IEEE\_FLOAT\_32) |
| Marker file | `.vmrk` | INI-style text file; contains a timestamped event list |

The data file stores samples in one of two orientations:

- **MULTIPLEXED** — samples are interleaved across channels: `ch1[t0], ch2[t0], …, ch1[t1], ch2[t1], …`
- **VECTORIZED** — all samples for each channel are contiguous: `ch1[t0], ch1[t1], …, ch2[t0], ch2[t1], …`

Each channel has an independent `resolution` scale factor stored in the
header.  The physical value (in the channel's unit, e.g. µV) is obtained
by multiplying the raw integer sample by this factor.

The marker file records discrete events such as stimulus presentations,
responses, and recording-segment boundaries.  Each marker has a type, a
description, a sample-position, an optional channel index, and an
optional date/time stamp.

For the full format specification see the
[BrainVision Core Data Format documentation](https://www.brainproducts.com/support-resources/brainvision-core-data-format-1-0/).

## The Onda Format

[Onda](https://github.com/beacon-biosignals/Onda.jl?tab=readme-ov-file#the-onda-format-specification)
is an open, Arrow-based format for multi-channel biosignal data.  It
separates *signal metadata* from the raw binary samples, making it easy
to work with large datasets without loading all data into memory.

The two main Onda data structures are:

**`SignalV2`** — a row in an Arrow table that describes one group of
channels from a single recording.  Key fields include:

| Field | Meaning |
|:------|:--------|
| `recording` | UUID identifying the recording |
| `channels` | ordered list of channel names |
| `sample_unit` | physical unit as a lowercase snake\_case string (e.g. `"microvolt"`) |
| `sample_resolution_in_unit` | scale factor from raw integer to physical unit |
| `sample_type` | Julia numeric type as a string (`"int16"` or `"float32"`) |
| `sample_rate` | samples per second |
| `span` | half-open `[start, stop)` time interval in nanoseconds |
| `file_path` | path to the binary data file |
| `file_format` | string describing the binary layout |

**`onda.annotation@1`** — a row in an Arrow table representing a
discrete event associated with a recording.  Required columns are
`recording` (UUID), `id` (UUID), and `span` (`TimeSpan`).

Use `Onda.load(signal)` to load the sample data described by a
`SignalV2` into memory as a `SampleV2` (a `channels × samples` matrix
paired with its signal descriptor).

## Package Structure and API Layers

OndaVision exposes three layers of abstraction, from lowest to highest
level:

| Layer | Functions | Use when |
|:------|:----------|:---------|
| **Raw parsers** | [`read_vhdr`](@ref), [`read_vmrk`](@ref), [`read_brainvision`](@ref) | You need raw `Dict` or `Matrix` access to BrainVision data, or you are building a custom pipeline |
| **Mid-level converters** | [`brainvision_to_signal`](@ref), [`brainvision_annotations`](@ref) | You need Onda objects but want control over how the files are read |
| **High-level integrated** | [`read_brainvision_onda`](@ref), [`write_brainvision`](@ref) | Standard BrainVision ↔ Onda round-trip |

Most users should start with [`read_brainvision_onda`](@ref) and
[`write_brainvision`](@ref).

## Supported BrainVision Format Combinations

| Feature | Read | Write |
|:--------|:-----|:------|
| `DataFormat: BINARY` | ✓ | ✓ |
| `BinaryFormat: INT_16` | ✓ | ✓ |
| `BinaryFormat: IEEE_FLOAT_32` | ✓ | ✓ |
| `DataOrientation: MULTIPLEXED` | ✓ | ✓ |
| `DataOrientation: VECTORIZED` | ✓ | converted to MULTIPLEXED on write |
| `DataType: TIMEDOMAIN` | ✓ | ✓ |
| Character encoding: UTF-8 | ✓ | ✓ |
| Character encoding: Latin-1 | ✓ | — (always written as UTF-8) |
