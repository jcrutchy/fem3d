# femgeo

CAD geometry interchange for fem3d: a text-based B-rep format
(FEM3DGEO 1.0, `docs/FEM3DGEO.md`) plus a checker and format adaptors,
sitting alongside the main solver suite and the crack-growth module as a
self-contained set of units using the same conventions (native text format,
verbose diagnostics, small composable Unix-philosophy tools).

Rebuilt from scratch 2026-09-29 -- see `docs/TODO_femgeo.md` for exactly
what's built, what's deliberately deferred, and why.

## Layout

```
docs/FEM3DGEO.md                         the format spec
docs/TODO_femgeo.md                      status and what's deferred
src/common/fem_geometry_*.pas            types, IO (reader/canonical writer), validator
src/tools/femgeocheck/                   CLI checker
src/tools/patch_test/run_roundtrip_test.lpr, run_geometry_fixtures.lpr
                                         round-trip + fixture regression tests
src/adaptors/dxf2femgeo/                 DXF -> FEM3DGEO (LINE, CIRCLE, ARC)
(IGES / STEP adaptors)                   not yet written -- the old broken sources were
                                         removed; see docs/TODO_femgeo.md
tests/geometry/                          good/ and borked/ .fgeo fixtures
examples/rivet_flange_geometry/          a worked DXF -> FEM3DGEO example
```

## Building and trying it

From the repository root (`build.bat` does all of this on Windows):

```
fpc -MObjFPC -FE./bin -FU./bin -Fu./src/common src/tools/femgeocheck/femgeocheck.lpr
fpc -MObjFPC -FE./bin -FU./bin -Fu./src/common src/adaptors/dxf2femgeo/dxf2femgeo.lpr

./bin/dxf2femgeo examples/rivet_flange_geometry/flange.dxf > /tmp/flange.fgeo
./bin/femgeocheck /tmp/flange.fgeo
```

## Verifying the build

```
fpc -MObjFPC -FE./bin -FU./bin -Fu./src/common src/tools/patch_test/run_roundtrip_test.lpr
fpc -MObjFPC -FE./bin -FU./bin -Fu./src/common src/tools/patch_test/run_geometry_fixtures.lpr
./bin/run_roundtrip_test        # every good fixture + the rivet-flange example
./bin/run_geometry_fixtures     # uses bin/femgeocheck and tests/geometry
```

Both take optional arguments (file names / checker path and fixtures folder);
with none they use the defaults above, so `test.bat` can run them blind.
