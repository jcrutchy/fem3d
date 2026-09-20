# V49 — Headless Toolchain

v0.49 shifts the development centre of gravity from the GUI to the executable
model/validate/solve/result pipeline.

## Toolchain

The intended workflow is:

    model.fem3d
        |
        +-- FEM3D_CLI validate
        |
        +-- FEM3D_CLI solve
                  |
                  +-- FEM3D_LinStatic.exe model.fem3d
                              |
                              +-- model.fem3dres
        |
        +-- FEM3D_CLI results

The numerical solver receives exactly one argument: the model filename.
Analysis settings remain in the model.

## Verification

`FEM3D_CLI.exe verify` runs the core native Pascal verification set.

`tests/HeadlessContract.lpr` verifies that the hand-authored example can be
loaded, validated, saved and reloaded while retaining its analysis settings.

`smoke_headless.bat` is intended as a Windows build-and-smoke-test entry point.
It builds the CLI, solver and native verification programs, then exercises
validation, solving and result inspection.

## Numerical work

`src/FEMFastMath.pas` contains small, dependency-free, four-way-unrolled
pointer kernels for dot products and AXPY-style operations. The LDL^T solver
uses the weighted dot-product path for its factorisation.

This is deliberately conservative. The supplied FERRO64 library was reviewed
as a source of ideas rather than dropped wholesale into FEM3D. Useful ideas
include aligned storage, column-major BLAS-style layouts, unrolled Level-1
kernels, CSR triplet assembly, RCM ordering and skyline storage.

AVX2/FMA assembly is not enabled merely because it exists. A future optimized
backend can replace these kernels behind the same interface after benchmark
and regression evidence justify it.
