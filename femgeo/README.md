# FEM3D geometry foundation

This package adds the first geometry/intermediate-model layer proposed for FEM3D.

It is intentionally independent of the solver `.fem` model.  CAD adaptors map
source geometry into the common `FEM3DGEO` model (`.fgeo`), and subsequent
recipe modules can consume that representation through stdin/stdout or files.

The initial implementation is deliberately conservative: it establishes the
format, topology model, parser/writer, checker, regression fixtures and thin
adaptor entry points.  STEP/IGES/DXF readers report unsupported source entities
rather than silently approximating them.
