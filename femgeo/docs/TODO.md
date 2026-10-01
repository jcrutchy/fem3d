# femgeo: status and TODO

Rebuilt from scratch 2026-09-29 (Jared: "maybe just rebuild from
scratch?"). The spec (`docs/FEM3DGEO.md`) was kept as-is -- it was
already solid. The previous implementation did not compile (two
separate bugs: a local loop variable shadowing a same-named unit
function, since Pascal identifiers are case-insensitive; and passing
Pascal's Text-typed `Input`/`Output` where a `TStream` was expected,
which are incompatible I/O abstractions) and covered a small fraction
of even the entities it claimed to (STEP: bare points only, no B-rep at
all; IGES/DXF: straight lines only, no circles -- meaning it could not
have read a rivet hole out of anything).

## Done, and verified

- `src/common/fem_geometry_types.pas` -- full FEM3DGEO 1.0 data model:
  header, vertex, curve (line/circle/arc3), edge, loop, surface (plane),
  face, body, set, meta.
- `src/common/fem_geometry_io.pas` -- reader (quote-and-escape-aware
  tokenizer; the previous version's tokenizer only recognised a quoted
  span when it opened right at the start of a field, which broke on
  `name="two words"`) and canonical writer, both over a real `TStream`
  (`THandleStream` for stdin/stdout -- the actual fix for the bug
  above), verified round-trip idempotent
  (`write(read(write(model))) == write(model)` byte for byte --
  `src/tools/patch_test/run_roundtrip_test.lpr`).
- `src/common/fem_geometry_validate.pas` -- all ten GEO001-GEO010
  diagnostics actually implemented (the previous code had partial,
  untested coverage of a few of these under different, non-spec-code
  names), with the spec's error/warning severity distinction (only
  errors fail a check). Every code individually exercised against a
  real fixture during development (see `tests/geometry/`).
- `src/tools/femgeocheck/femgeocheck.lpr` -- CLI checker, file or `-`
  (stdin) input, correct exit codes (0 clean, 1 geometry errors, 2
  usage, 3 parse error).
- `src/adaptors/dxf2femgeo/dxf2femgeo.lpr` -- real DXF group-code
  parsing: LINE, CIRCLE, ARC (the entities a fastener-hole panel
  actually needs -- outline lines, hole circles, filleted corners),
  vertex welding across entities so shared endpoints become one
  VERTEX record, per-layer SET grouping, and GEO009 diagnostics (to
  stderr, one per entity, plus a summary line) for anything else
  rather than silently dropping it (spec rule 6) -- verified against
  `examples/rivet_flange/`, a stand-in for Jared's actual door-cutout/
  rivet-row case, including confirming a TEXT entity is flagged, not
  dropped.
- `tests/geometry/good/`, `tests/geometry/borked/` -- real, individually
  verified fixtures (a plain rectangle; a plate with a circular hole,
  exercising FACE's INNER-loop syntax; one borked fixture per major
  GEO error code), plus `src/tools/patch_test/run_geometry_fixtures.lpr`,
  a black-box runner (drives the actual `femgeocheck` executable, not
  its internal functions) confirming every fixture is accepted or
  rejected as intended. All fixtures currently pass; the previous two
  fixtures (`001_dangling_edge`, `002_broken_loop`) were never actually
  exercised, since nothing compiled -- not reused, since the rebuild
  makes it easy to just verify fresh ones instead of auditing whether
  the old text still matched the new checker's exact wording.

## Not done yet, on purpose

### IGES and STEP adaptors

Not rebuilt this pass -- DXF was prioritized as the format most directly
relevant to Jared's stated use case (a flange panel, most likely
authored or exported as 2D DXF), and doing DXF properly (real parsing,
vertex welding, layer grouping, verified against a realistic example)
was judged better than doing three formats shallowly in the same pass.
The previous IGES adaptor handled entity type 110 (LINE) only, no
circles/arcs; the previous STEP adaptor extracted CARTESIAN_POINT only
-- no topology at all, not usable for anything beyond a point cloud.
Both need the same real-parsing treatment DXF just got:
- **IGES**: fixed-width Start/Global/Directory/Parameter section
  format; at minimum entity types 100 (circular arc) and 110 (line) to
  match DXF's coverage, ideally also 106 (composite curve / polyline)
  and 108 (plane).
  the fixed field-width layout is mechanical but sizeable work, not
  conceptually hard.
- **STEP**: EXPRESS-based, entities cross-reference each other by `#`
  id (e.g. an ADVANCED_FACE references FACE_BOUNDs which reference
  EDGE_LOOPs which reference ORIENTED_EDGEs which reference EDGE_CURVEs
  which reference CARTESIAN_POINTs) -- genuinely a different order of
  complexity from DXF or IGES, since it needs a real (if minimal)
  B-rep graph resolved, not just flat entity records. Recommend
  scoping an initial pass to a specific, named AP (AP203 or AP214,
  the common mechanical-CAD ones) and a specific entity subset
  (CARTESIAN_POINT, LINE, CIRCLE, EDGE_CURVE, ORIENTED_EDGE, EDGE_LOOP,
  PLANE, FACE_BOUND, ADVANCED_FACE) rather than attempting general
  STEP/EXPRESS parsing.

### DXF adaptor: known gaps

- **$INSUNITS not read** -- `UNITS length=UNKNOWN` is always emitted
  regardless of the source file's actual drawing units (DXF header
  variable `$INSUNITS`, group 70 in the HEADER section). Worth reading
  properly before this adaptor is used on real drawings where unit
  correctness matters (all of them).
- **LWPOLYLINE, SPLINE, and block/INSERT references not supported**
  -- flagged via GEO009, not silently dropped, but a real drawing's
  outline is at least as likely to be one LWPOLYLINE as four separate
  LINEs; supporting it (including its bulge-factor arc segments) would
  meaningfully widen what this adaptor can actually read.
- **OCS/extrusion direction not handled** -- a CIRCLE or ARC's group 210/
  220/230 (its Object Coordinate System normal) is ignored; every
  circle/arc is assumed to lie in the world XY plane. Fine for a flat
  2D drawing (most fastener-hole panel drawings), wrong for a DXF with
  entities on a rotated/extruded OCS.

### Topology reconstruction (LOOP/FACE/BODY from a wireframe soup)

`dxf2femgeo` (and any future IGES/STEP adaptor) deliberately stops at
vertices/curves/edges -- see the adaptor's own header comment for why
this is scoped as a downstream tool's job (the streaming pipeline's
`geomclean`/`automesh` stage, per spec section 16), not the format
adaptor's. That downstream tool doesn't exist yet either. Building it
needs real 2D planar-graph reasoning (which edges bound which closed
region) and isn't a small extension of anything here.

### Validator: known gaps

- GEO007 (duplicate/coincident geometry) currently only checks
  vertices. Extending it to flag coincident/duplicate curves or
  surfaces (e.g. two CIRCLE records with the same center/radius) is
  straightforward but not done.
- `angTol` (the TOLERANCE record's `angle` value) is read but not yet
  used by any check -- reserved for a future angle-based degeneracy
  check (e.g. flagging a near-collinear ARC3 by angle rather than by
  the cross-product-magnitude test currently used), not yet needed by
  anything in `good/`/`borked/`.

### Regression harness

`run_geometry_fixtures.lpr` is a simple black-box pass/fail runner --
no manifest files, no SHA256 integrity hashes, no per-case expected-
diagnostic matching. `tests/geometry/README.md` (kept from before the
rebuild) already anticipates a `fem_regress`-style manifest convention
(`Status=VERIFIED|BORKED`, `ExpectedExitCode=`, `ExpectedErrorContains=`)
-- worth building once there are enough fixtures that "does this file
exist and pass/fail" stops being precise enough (e.g. once a single
fixture is meant to exercise a SPECIFIC diagnostic and a change that
silently swaps in a different GEO code should be caught).
