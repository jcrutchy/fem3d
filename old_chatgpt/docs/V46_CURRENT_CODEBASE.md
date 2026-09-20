FEM3D v0.46 - Current Codebase Snapshot
========================================

This package is a fresh consolidated source tree based on the current FEM3D
snapshot plus the v0.45 result-visualisation adapter work.

Changes in this increment
-------------------------

1. Consolidated the active source modules into one clean tree.
2. Removed obsolete duplicated solver/core copies from the development tree.
3. Kept numerical solver code isolated under solver/.
4. Added the result visualisation scene and OpenGL target adapter.
5. Wired the OpenGL result path through TResultVisualisationAdapter rather
   than calculating result contour colours directly in the viewport loop.
6. Preserved the existing model/result/analysis architecture.
7. Added native visualisation regression coverage.
8. Applied old-school Borland/Delphi VCL-oriented source formatting conventions
   without introducing third-party libraries or changing the numerical model.

Important
---------

This is a source snapshot. It has not been compiled in the target Lazarus/FPC
installation. Compile errors, if any, should be treated as normal integration
issues for the next refinement pass rather than silently assumed to be fixed.

Visualisation direction
-----------------------

The intended pipeline is:

  result document -> result fields -> derived fields -> visualisation scene
                   -> OpenGL / SVG / HTML / DXF targets

The visualisation layer deliberately does not own FEM model or solver logic.
