# Understanding tasks

Feel free to ask questions. 

Do not assume that requested tasks are possible: feel free to inform me that a requested task is not possible in the given form or that there are only tedious workarounds.

# Julia development

For Julia code, use the YAS codestyle (https://github.com/jrevels/YASGuide). 
Explicit `return` statements are required and the use of `import` is forbidden.

When running individual tests in Julia, you need to load the test environment. This can be done with `using TestEnv; TestEnv.activate()`. The entire testsuite can be invoked with `using Pkg; Pkg.test()` without activating the test environment beforehand.

Always invoke Julia with `--startup-file=no` unless explicitly instructed otherwise.

You may invoke a specific Julia version with `+VERSION`, e.g. `+1.10` or `+1.12`. This argument must come immediately after `julia` and before any other flags. 

When checking coverage, you can use LocalCoverage.jl, which writes coverage to `coverage/lcov.info`.
