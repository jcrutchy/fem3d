# Engineering Viewport Symbols

FEM3D v0.19 introduces a renderer-owned engineering symbol layer. Symbols are presentation only and never alter the FEM model or solver state.

## Layers

- Loads â€” translational load arrows and a compact moment glyph.
- Restraints â€” translational restraint markers and rotational restraint glyphs.
- Local axes â€” element local triads for supported line elements.
- Coordinate systems â€” model coordinate-system triads.

Each layer can be independently enabled from the viewport UI.

## Design rules

1. Symbols are derived from model data; they are not copied into the model as graphics.
2. Symbol size is tied to camera distance so glyphs remain useful while zooming.
3. Hidden elements/nodes are not given engineering glyphs.
4. Selection and visibility remain independent.
5. The renderer is not part of the numerical solver boundary.

Future work includes screen-space sizing, load-case filtering, prescribed-displacement symbols, labels, adjustable glyph density and higher-quality arrowheads.
