# FEM3D v0.45 — Result visualisation adapter architecture

## Purpose

v0.45 introduces a target-independent result visualisation layer. Numerical
results remain in `TResultFieldCollection`; visualisation converts those fields
into a simple scene representation which a target renderer can consume.

The first target is OpenGL, but the scene is deliberately free of LCL, OpenGL,
Forms and file-format code.

## Data flow

    .fem3dres
        |
        v
    TResultFieldCollection
        |
        v
    TResultVisualisationAdapter
        |
        v
    TResultVisualisationScene
        |
        +--> OpenGL viewport
        +--> future SVG exporter
        +--> future HTML/CSS/HTMX exporter
        +--> future DXF exporter

This prevents the GUI renderer from becoming the owner of result semantics.

## Current scene primitives

`TResultContourSegment` contains:

* element ID;
* two 3D positions;
* scalar value at each end.

`TResultLegendBand` contains a scalar range and display colour.

`TResultDiagram` contains ordered position/value pairs for result diagrams.
The first implementation provides the two beam endpoints; it is intentionally
small enough to evolve into richer beam diagrams later.

## Contour mapping

`TResultContourMapper` owns the normalisation and blue/cyan/green/yellow/red
mapping currently used by the OpenGL renderer. The mapping is no longer
conceptually tied to OpenGL.

The mapper treats a constant result range explicitly, avoiding a divide by
zero when a field has identical minimum and maximum values.

## Important design rule

The visualisation layer must not alter solver results. It may derive display
quantities, interpolate values for presentation, transform positions by a
user-selected deformation scale, and construct diagrams/legends, but it must
never write back into `TFEMResultDocument` or the model.

## Future targets

Likely target adapters include:

* `TGLResultVisualisationAdapter` — interactive desktop viewport;
* `TSVGResultVisualisationAdapter` — vector contour/diagram export;
* `THTMLResultVisualisationAdapter` — self-contained report output;
* `THTMXResultVisualisationAdapter` — interactive web-oriented presentation;
* `TDXFResultVisualisationAdapter` — engineering drawing/export of selected
  result geometry and diagrams.

The target adapters should consume the same scene/primitives rather than
reimplementing result extraction.

## Future diagram types

The scene model should eventually support separate primitives for:

* beam axial-force diagrams;
* shear-force diagrams;
* bending-moment diagrams;
* torsion diagrams;
* reaction vectors;
* displacement vectors;
* principal-stress directions;
* contour bands;
* min/max markers;
* probe labels;
* undeformed/deformed geometry;
* section/result annotations.

These are display products, not solver products.

## Current integration status

The adapter units are source-only in this increment. The existing OpenGL
renderer remains functional and is not replaced wholesale. Wiring the viewport
to consume the scene object is deliberately the next surgical integration step,
so existing display/selection/clip behaviour can be retained while result
rendering moves behind the adapter boundary.
