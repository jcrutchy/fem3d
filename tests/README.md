# FEM3D verification suite

This is a native FreePascal verification runner. It deliberately avoids Python and external numerical libraries.

The suite currently checks:

1. 3D Euler-Bernoulli cantilever tip displacement in global Z against the closed-form \(PL^3/(3EI_y)\) result.
2. Cantilever tip displacement in global Y against the corresponding \(I_z\) closed-form result.
3. Cantilever axial extension against \(PL/(EA)\).
4. Cantilever torsional rotation against \(TL/(GJ)\).
5. Fixed-support reaction equilibrium.
6. Detection of an unconstrained rigid-body mechanism through singular-system rejection.
7. Model validation for invalid material/section properties and zero-length geometry.

The important distinction is between **verification** and **validation**:

- Verification asks whether the implemented numerical formulation reproduces known mathematical/analytical results.
- Validation asks whether the formulation is an appropriate representation of the physical behaviour. Shell/plate bending validation is intentionally not claimed yet.

Every future element/solver should add analytical benchmarks, patch tests, symmetry checks, equilibrium checks and convergence studies before being treated as engineering-ready.


The verification project now also compiles the analysis-case, hashing and native I/O units so persistence/provenance tests can be added without changing the solver boundary. Native execution remains unverified in this environment because FPC/Lazarus is unavailable.

## v0.7 primary-analysis verification

`sample_primary_analyses.fem3d` contains one each of Linear Static, Linear Buckling and Nonlinear Static analysis definitions so the Analysis Manager and persistence path can be exercised manually.

The native verification runner now also checks that analysis cases and solver settings survive save/load, and that the model fingerprint changes when restraints or nodal loads change.

v0.9 adds result-expression coverage targets for arithmetic, comparisons and IF(). Native execution still requires a Lazarus/FreePascal environment; this archive has not been compiled in the generation environment.

### v0.16

Added `DisplayManagerVisibility` verification. This checks that presentation-only hide/show operations, material isolation and node visibility propagation behave deterministically without modifying solver data.
