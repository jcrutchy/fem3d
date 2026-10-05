# FEM3DGEO 1.0 — geometry interchange specification

## 1. Purpose

`FEM3DGEO` (`.fgeo`) is the canonical, text-based interchange representation
for FEM3D geometric preprocessing. It is deliberately separate from the
solver-native `.fem` model.

A format adaptor (STEP, IGES, DXF, or a future source) converts source geometry
into this representation. Geometry checking, healing, defeaturing, sizing,
meshing and FE-model generation operate on FEM3DGEO rather than directly on a
CAD format.

The format is designed for:

* deterministic regression testing;
* human inspection and diffing;
* streaming through stdin/stdout;
* explicit topology;
* source provenance;
* non-destructive preprocessing recipes;
* future extension without coupling downstream modules to CAD formats.

## 2. Design rules

1. IDs are explicit and stable within a file.
2. References always refer to IDs, never array positions.
3. Geometry and topology are separate concepts.
4. A curve is a geometric definition; an edge is a bounded/topological use of
   that curve.
5. A surface is a geometric definition; a face is a bounded/topological use of
   that surface.
6. No importer may silently discard an unsupported source entity.
7. Units and tolerances are explicit metadata.
8. Entity ordering is canonical for files written by FEM3D: ascending numeric
   IDs within each entity class.
9. Text is UTF-8. Decimal numbers use `.` regardless of locale.
10. Comments begin with `#` and are ignored by parsers.

## 3. File structure

A file consists of a header followed by records. Whitespace separates fields;
quoted strings use double quotes and support `\\`, `\"`, `\n`, `\r`, and `\t`.

```text
FEM3DGEO 1.0
UNITS length=mm force=N stress=MPa
COORDSYS CARTESIAN
TOLERANCE coincidence=0.001 edge=0.005 surface=0.010 feature=0.010 angle=1e-8
SOURCE format=STEP name="bracket.step"

VERTEX 1 0 0 0
VERTEX 2 100 0 0
CURVE 1 LINE 1 0 0 0 1 0 0
EDGE 1 1 2 1 0 100 1
LOOP 1 EDGE 1 +
SURFACE 1 PLANE 0 0 0 0 0 1
FACE 1 1 OUTER 1
BODY 1 FACE 1
SET 1 "FIXED" VERTEX 1 2
```

The canonical writer may emit blank lines between sections, but readers must
not depend on them.

## 4. Header records

### `FEM3DGEO 1.0`

Required first non-comment record.

### `UNITS`

Optional. Values are descriptive strings; `length` is required when units are
known. Examples: `mm`, `m`, `in`. A source with unknown units uses
`length=UNKNOWN` and must not invent a scale.

### `COORDSYS`

Optional. Version 1.0 defines `CARTESIAN` only.

### `TOLERANCE`

Optional. Values are in the declared length/angular units. Names are:
`coincidence`, `edge`, `surface`, `feature`, `angle`.

### `SOURCE`

Optional provenance. At minimum `format=` is recommended. Additional key/value
pairs are allowed.

## 5. Vertices

```text
VERTEX <id> <x> <y> <z>
```

A vertex is a topological point. Coordinates are in the declared length unit.

## 6. Curves

Version 1.0 defines these initial curve forms:

```text
CURVE <id> LINE <x> <y> <z> <dx> <dy> <dz>
CURVE <id> CIRCLE <cx> <cy> <cz> <nx> <ny> <nz> <r>
CURVE <id> ARC3 <x1> <y1> <z1> <xm> <ym> <zm> <x2> <y2> <z2>
```

`LINE` is an infinite parametric line; the edge supplies its finite parameter
range. `CIRCLE` is a circle in a plane. `ARC3` defines a circular arc through
three non-collinear points.

Future curve kinds include rational B-splines and conics. Unknown curve kinds
must be rejected by strict consumers, not guessed.

## 7. Edges

```text
EDGE <id> <startVertex> <endVertex> <curveId> <t0> <t1> <sense>
```

`sense` is `+1` or `-1` and describes the edge traversal relative to the curve's
positive parameter direction.

An edge's topological endpoints must agree with its traversal. The geometric
curve and its edge parameter range remain separate.

## 8. Loops

A loop is an ordered closed or open sequence of oriented edge uses.

```text
LOOP <id> EDGE <edgeId> <sense> EDGE <edgeId> <sense> ...
```

For a face boundary the loop must be closed. `sense` is `+1` or `-1` relative
to the stored edge direction.

## 9. Surfaces

Initial form:

```text
SURFACE <id> PLANE <ox> <oy> <oz> <nx> <ny> <nz>
```

The origin and normal define the plane. The normal need not be unit length on
input; a strict geometry checker reports a zero normal.

Future versions will add cylinders, cones, spheres, tori and NURBS surfaces.

## 10. Faces

```text
FACE <id> <surfaceId> OUTER <loopId> [INNER <loopId> ...]
```

A face is a bounded region of a surface. `OUTER` identifies the exterior
boundary; `INNER` identifies holes.

Face orientation is the direction of the surface normal after applying the
face's optional orientation attribute. Version 1.0 uses the surface normal
unless an explicit `ORIENTATION` record is supplied.

## 11. Bodies

```text
BODY <id> FACE <faceId> [FACE <faceId> ...]
```

A body is a grouping of faces. It may be a closed solid or an open shell.
Version 1.0 does not require every body to be watertight.

## 12. Sets

Sets are named groups used later by geometry recipes and attribute inheritance.

```text
SET <id> "name" <entityType> <entityId> [<entityId> ...]
```

`entityType` is one of `VERTEX`, `EDGE`, `LOOP`, `FACE`, `BODY` in version 1.0.

## 13. Attributes and provenance

Version 1.0 reserves free-form records for later engineering/meshing
attributes. Implementations should preserve unknown attribute records when
round-tripping, but are not required to interpret them.

Recommended source metadata:

```text
META source_format="STEP" source_entity="#4172"
META source_name="BRACKET"
```

A geometry operation may append provenance records rather than replacing the
source information.

## 14. Diagnostics

Diagnostics are not geometry records and may be emitted by tools to stdout or
stderr. Stable codes are recommended:

* `GEO001` invalid reference
* `GEO002` duplicate ID
* `GEO003` dangling topology
* `GEO004` open/non-contiguous face loop
* `GEO005` invalid orientation/normal
* `GEO006` non-manifold topology
* `GEO007` duplicate/coincident geometry
* `GEO008` zero-length/degenerate geometry
* `GEO009` unsupported geometry
* `GEO010` unit/tolerance problem

A checker exits non-zero if errors exist. Warnings do not by themselves fail a
check.

## 15. Canonicalisation

The canonical writer:

* writes the header records in the order shown above;
* emits entity records in ascending numeric ID order within each type;
* uses a deterministic floating-point representation;
* writes `+1`/`-1` explicitly;
* writes quoted names using the defined escape rules;
* does not emit volatile timestamps.

Canonicalisation is what makes `.fgeo` fixtures suitable for regression tests.

## 16. Streaming contract

Every FEM3D geometry tool should support:

```text
input file -> stdout
stdin      -> stdout
input file -> output file
```

Errors and diagnostics go to stderr unless a tool explicitly documents another
mode. Thus a recipe can be written as:

```text
step2femgeo model.step | femgeocheck - | geomclean - | automesh -
```

## 17. Compatibility

Readers must reject a major version they do not understand. A reader may accept
future minor versions if it can safely ignore records it does not interpret.
Writers must emit the version they actually implement.
