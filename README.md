# OndaVision.jl

Onda and BrainVision, together.

[![Project Status: WIP – Initial development is in progress, but there has not yet been a stable, usable release suitable for the public.](https://www.repostatus.org/badges/latest/wip.svg)](https://www.repostatus.org/#wip)
[![Stable Docs][docs-stable-img]][docs-stable-url]
[![Dev Docs][docs-dev-img]][docs-dev-url]
[![codecov](https://codecov.io/gh/palday/OndaVision.jl/graph/badge.svg?token=91EQd4krJi)](https://codecov.io/gh/palday/OndaVision.jl)
[![Code Style: YAS](https://img.shields.io/badge/code%20style-yas-1fdcb2.svg)](https://github.com/jrevels/YASGuide)
<!-- [![DOI](https://zenodo.org/badge/337082120.svg)](https://zenodo.org/badge/latestdoi/337082120) -->

[docs-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg
[docs-dev-url]: https://palday.github.io/OndaVision.jl/dev

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://palday.github.io/OndaVision.jl/stable


**OndaVision.jl** is a Julia package for reading and writing [BrainVision Core Data Format](https://www.brainproducts.com/support-resources/brainvision-core-data-format-1-0/) files as [Onda](https://github.com/beacon-biosignals/Onda.jl) data.

BrainVision is a widely used format for electrophysiological recordings (EEG, EMG, and related signals), stored as a trio of files: a text header (`.vhdr`), a binary data file (`.eeg`), and a marker file (`.vmrk`). Onda is a lightweight format defined atop Apache Arrow for storing and manipulating sets of multi-sensor, multi-channel, LPCM-encodable, annotated, time-series recordings.

OndaVision bridges the two: one call reads a BrainVision recording into Onda's typed signal and annotation tables, and one call writes them back out.

```julia
using OndaVision

# Read a BrainVision recording
result = read_brainvision_onda("recording.vhdr")
result.signals     # Vector{SignalV2} — load samples with Onda.load(signal)
result.annotations # NamedTuple — onda.annotation@1-compliant marker table
result.metadata    # BrainVisionMetadata — coordinates, filters, impedances, …

# Write back out (lossless round-trip)
write_brainvision("output", result.signals;
                  annotations = result.annotations,
                  metadata    = result.metadata)
```

BrainVision-specific metadata that has no Onda counterpart — electrode coordinates, hardware and software filter settings, impedance measurements, and recording comments — is preserved in a `BrainVisionMetadata` struct and round-tripped faithfully.

For full documentation, including format background, the complete API reference, and guidance on multi-signal files and encoding edge cases, see the [documentation][docs-stable-url].
