```@meta
CurrentModule = OndaVision
```

# Guide

## Installation

```julia
using Pkg
Pkg.add("OndaVision")
```

## Tour

### Reading a BrainVision file

[`read_brainvision_onda`](@ref) is the main entry point.  Point it at
the `.vhdr` header file; the data and marker files are resolved
automatically from the header.

```julia
using OndaVision

result = read_brainvision_onda("/path/to/recording.vhdr")
```

The return value is a named tuple with three fields:

```julia
result.signals     # Vector{SignalV2} — one entry per channel group
result.annotations # NamedTuple — onda.annotation@1 column table
result.metadata    # BrainVisionMetadata — BrainVision-specific extras
```

Optional keyword arguments let you control encoding, signal metadata,
and the recording UUID embedded in every row:

```julia
using UUIDs

result = read_brainvision_onda(
    "/path/to/recording.vhdr";
    recording   = uuid4(),        # default: random UUID
    sensor_type = "eeg",          # Onda sensor type
    sensor_label = "eeg",         # Onda sensor label
    codepage    = nothing,        # "UTF-8", "Latin-1", or nothing for auto-detect
)
```

### Working with signals

`result.signals` is a `Vector{SignalV2}`.  For recordings where every
channel shares the same unit and resolution there is a single element;
see [Multi-signal files](@ref) for the case where channels are grouped
into multiple signals.

Each `SignalV2` carries the channel list, sampling rate, unit, and a
path to the underlying binary file.  Load the actual samples with
`Onda.load`:

```julia
using Onda

sig = result.signals[1]
samples = Onda.load(sig)       # returns a SampleV2 (channels × time matrix)
data = samples.data            # Matrix{Int16} or Matrix{Float32} in physical units
```

### Working with annotations

`result.annotations` is a `NamedTuple` that conforms to the
`onda.annotation@1` Legolas schema.  It has the following columns:

| Column | Type | Contents |
|:-------|:-----|:---------|
| `recording` | `Vector{UUID}` | Same UUID as the signals |
| `id` | `Vector{UUID}` | One fresh UUID per annotation |
| `span` | `Vector{TimeSpan}` | Half-open `[start, stop)` interval in nanoseconds |
| `marker_type` | `Vector{String}` | BrainVision marker type (e.g. `"Stimulus"`, `"Response"`) |
| `description` | `Vector{String}` | BrainVision description field (e.g. `"S  1"`) |
| `channel` | `Vector{Union{String,Missing}}` | Channel name, or `missing` for recording-wide markers |

When no marker file is present the table is empty (zero rows) but still
has the correct column schema and passes `Onda.validate_annotations`.

### Writing a BrainVision file

[`write_brainvision`](@ref) is the inverse of
[`read_brainvision_onda`](@ref).  Pass the signals and, optionally,
annotations and metadata:

```julia
vhdr_path = write_brainvision(
    "/path/to/output",          # base path; extension is stripped if present
    result.signals;
    annotations = result.annotations,  # omit to skip writing a .vmrk file
    metadata    = result.metadata,     # omit to use default channel names
)
```

The function writes `output.vhdr`, `output.eeg`, and (when annotations
are provided) `output.vmrk`, returning the path to the `.vhdr` file.

### A complete round-trip

```julia
using OndaVision

# Read
result = read_brainvision_onda("/path/to/input.vhdr")

# Process signals or annotations here …

# Write
write_brainvision(
    "/path/to/output",
    result.signals;
    annotations = result.annotations,
    metadata    = result.metadata,
)
```

### Using lower-level functions

If you only need a subset of the data, or want to integrate BrainVision
parsing into a custom pipeline, the mid- and low-level functions are
available individually:

```julia
# Parse the header dict directly
vhdr = read_vhdr("/path/to/recording.vhdr")

# Convert to Onda signals (reads header, constructs SignalV2 objects)
signals = brainvision_to_signal("/path/to/recording.vhdr")

# Convert markers to annotations (reads VMRK file via the VHDR)
annotations = brainvision_annotations("/path/to/recording.vhdr")

# Read raw sample data as a Matrix{Float64} in physical units
data = read_brainvision("/path/to/recording.vhdr")  # (n_channels × n_samples)
```

## [Multi-signal files](@id Multi-signal files)

The Onda `SignalV2` schema requires every channel in a signal
to share the same `sample_unit` and `sample_resolution_in_unit`.  When a
BrainVision file contains channels with different units or resolutions —
common in mixed-modality recordings that combine EEG with EMG or GSR —
OndaVision groups channels by `(unit, resolution)` and returns one
`SignalV2` per group.

```julia
result = read_brainvision_onda("/path/to/mixed.vhdr")
length(result.signals)  # > 1 when channels differ in unit or resolution
```

Each `SignalV2` in the vector uses a [`ChannelSubsetLPCMFormat`](@ref)-backed format string that encodes
which channels belong to the group, so `Onda.load` can read the correct
slice from the shared binary file.

Do not assume `result.signals` always has exactly one element.

## Metadata beyond Onda: `BrainVisionMetadata`

[`read_brainvision_onda`](@ref) captures BrainVision-specific
information that has no counterpart in the Onda signal or annotation
schemas in a [`BrainVisionMetadata`](@ref) struct.

**Per-channel supplementary** (parallel to the full channel list, same
order as the VHDR):

| Field | Type | Contents |
|:------|:-----|:---------|
| `channel_names` | `Vector{String}` | Original-case channel names (e.g. `"FP1"`, `"Cz"`) |
| `channel_references` | `Vector{String}` | Reference electrode per channel; `""` when not specified |
| `coordinates` | `NamedTuple` | Electrode positions: columns `channel`, `radius`, `theta`, `phi` (spherical) |

**Recording conditions** (parsed from the `[Comment]` block):

| Field | Type | Contents |
|:------|:-----|:---------|
| `amplifier_info` | `Dict{String,String}` | Recording-level hardware key-value pairs |
| `amplifier_channels` | `NamedTuple` | Per-channel hardware filter settings: `number`, `name`, `phys_chn`, `resolution`, `low_cutoff`, `high_cutoff`, `notch` |
| `software_filters` | `NamedTuple` | Per-channel software filter settings: `number`, `low_cutoff`, `high_cutoff`, `notch` (plus optional `name`) |
| `impedances` | `Dict{String,Union{Float64,Missing}}` | Impedance in kΩ; `missing` for unknown values (`???` in file) |

**Free-form metadata**:

| Field | Type | Contents |
|:------|:-----|:---------|
| `comment` | `String` | Raw `[Comment]` section text |
| `user_infos` | `Dict{String,String}` | `[User Infos]` key-value pairs (BrainVision v2.0+) |
| `channel_user_infos` | `Dict{String,String}` | `[Channel User Infos]` key-value pairs (BrainVision v2.0+) |

**Marker supplement**:

| Field | Type | Contents |
|:------|:-----|:---------|
| `marker_dates` | `Vector{Union{String,Missing}}` | VMRK timestamp string per annotation row, format `YYYYMMDDhhmmssμμμμμμ`; `missing` when absent for a given marker |

### Checking for absent fields

Optional fields are represented by **empty containers**, not `nothing`.
Use `isempty` to test for absence:

```julia
meta = result.metadata

isempty(meta.coordinates.channel)   # true when no [Coordinates] section
isempty(meta.amplifier_info)        # true when no Amplifier Setup comment block
isempty(meta.impedances)            # true when no impedance data
isempty(meta.comment)               # true when no [Comment] section
```

## Caveats and Limitations

**Channel ordering after a round-trip.** Channels are grouped by
`(unit, resolution)` when reading.  If the original file has mixed units
or resolutions, the channel order in the round-tripped file may differ
from the original.  When comparing channel lists after a round-trip, use
set equality rather than ordered equality.

**Orientation on write.** All files are always written in MULTIPLEXED
orientation, regardless of the orientation of the source file.

**Character encoding.** BrainVision files can be written in UTF-8 or
Latin-1.  OndaVision auto-detects the encoding on read but always writes
UTF-8.  If auto-detection fails, pass `codepage="Latin-1"` explicitly.

**Segmented recordings.** [`read_brainvision`](@ref) handles
multi-segment files (multiple "New Segment" markers) by returning either
a 3-D array or a vector of matrices.  [`read_brainvision_onda`](@ref)
treats the entire file as a single continuous recording; segmentation
information is preserved only through the "New Segment" annotations in
the annotation table.
