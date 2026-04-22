# OndaVision.jl Documentation

```@meta
CurrentModule = OndaVision
```

*OndaVision.jl* is a Julia package for reading and writing
[BrainVision](https://www.brainproducts.com/support-resources/brainvision-core-data-format-1-0/)
files as [Onda](https://github.com/beacon-biosignals/Onda.jl?tab=readme-ov-file#the-onda-format-specification)
data.  It converts the three-file BrainVision format (`.vhdr` header,
`.eeg` binary, `.vmrk` markers) to and from Onda's Arrow-based signal
and annotation tables, preserving BrainVision-specific metadata such as
electrode coordinates, hardware and software filter settings, and
impedance measurements that have no direct Onda counterpart.

```@contents
Pages = [
        "background.md",
        "guide.md",
        "api.md",
]
Depth = 1
```
