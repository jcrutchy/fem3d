# femgeo

CAD geometry interchange for fem3d: a text-based B-rep format
(FEM3DGEO 1.0, `docs/FEM3DGEO.md`) plus a checker and format adaptors,
sitting alongside the main solver suite and `crackgrowth/` as a
self-contained module using the same conventions (native text format,
verbose diagnostics, small composable Unix-philosophy tools).

Rebuilt from scratch 2026-09-29 -- see `docs/TODO.md` for exactly
what's built, what's deliberately deferred, and why.

## Layout

```
femgeo/
  docs/FEM3DGEO.md         the format spec
  docs/TODO.md             status and what's deferred
  src/common/               types, IO (reader/canonical writer), validator
  src/tools/femgeocheck/    CLI checker
  src/tools/patch_test/     round-trip + fixture regression tests
  src/adaptors/dxf2femgeo/  DXF -> FEM3DGEO (LINE, CIRCLE, ARC)
  src/adaptors/iges2femgeo/ not yet rebuilt (see docs/TODO.md)
  src/adaptors/step2femgeo/ not yet rebuilt (see docs/TODO.md)
  tests/geometry/           good/borked .fgeo fixtures
  examples/rivet_flange/    a worked DXF -> FEM3DGEO example
```

## Building and trying it

```
cd src/common && fpc fem_geometry_types.pas fem_geometry_io.pas fem_geometry_validate.pas
cd ../tools/femgeocheck && fpc -Fu../../common femgeocheck.lpr
cd ../../adaptors/dxf2femgeo && fpc -Fu../../common dxf2femgeo.lpr

./dxf2femgeo ../../../examples/rivet_flange/flange.dxf > /tmp/flange.fgeo
./femgeocheck /tmp/flange.fgeo
```

## Verifying the build

```
cd src/tools/patch_test
fpc -Fu../../common run_roundtrip_test.lpr
fpc -Fu../../common run_geometry_fixtures.lpr
./run_roundtrip_test ../../../tests/geometry/good/001_rectangle.fgeo
./run_geometry_fixtures ../femgeocheck/femgeocheck ../../../tests/geometry
```
