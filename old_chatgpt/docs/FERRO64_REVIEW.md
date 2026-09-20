# FERRO64 review

The attached FERRO64 library is a useful reference for FEM3D's future numerical
backend, but it should not be imported wholesale yet.

## Useful ideas adopted

- small record-based numerical types;
- explicit ownership/views;
- alignment-aware allocation;
- four-way unrolled Level-1 vector kernels;
- sparse triplet -> CSR conversion;
- RCM and skyline storage as future sparse/direct-solver options;
- keeping numerical kernels independent of the GUI.

The first adopted implementation is `FEMFastMath.pas`, using conservative
pure-Pascal pointer kernels.

## Deliberately not adopted yet

The AVX2/FMA assembly has not been copied into the production solver. It should
first have runtime feature dispatch, Windows x64 validation, scalar-vs-vector
regression tests and benchmarks on representative FEM workloads.

FERRO64's CPUID/XGETBV and platform-specific assembly paths also deserve
independent validation before becoming part of the production solver.

Likewise, the sparse/skyline/iterative algorithms should be introduced as
separate solver backends with verification cases rather than replacing the
reference dense solver prematurely.

## Direction

The reference dense solver remains the correctness baseline. Future numerical
backends can be compared against its results on deterministic verification
models and against independently calculated engineering solutions.
