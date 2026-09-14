## v0.18 — Viewport interaction pass
- Added explicit Element/Node selection mode.
- Added Ctrl-click additive/toggle selection behaviour.
- Added clear-selection and isolate-selection viewport actions.
- Added double-click focus of the current selection.
- Corrected mouse navigation dispatch so middle/right mouse camera navigation is handled independently of left-click selection.
- Kept selection, display state and camera state outside the solver kernel.
- Added docs/VIEWPORT_INTERACTION.md.

# Changelog

## v0.17 — Viewport Controls

- Added perspective and orthographic viewport modes.
- Added adjustable perspective field of view.
- Added independently configurable camera near clipping distance.
- Added Front, Rear, Left, Right, Top, Bottom and Isometric standard views.
- Added Fit all, Fit selected and Focus selection controls.
- Added View menu commands for Fit selection and Focus selection.
- Updated the OpenGL projection setup to use the viewport camera settings.
- Added viewport-control architecture documentation.

## v0.16 — Display Manager Implementation

- Added concrete display manager visibility state.
- Added hide/show/isolate operations by element type, material, section and group.
- Added automatic node visibility based on connected visible elements.
- Connected OpenGL rendering to display-manager visibility.
- Added display-manager GUI controls.

## 0.19.0 — Engineering viewport graphics

- Added renderer-owned engineering symbol layers for loads, restraints, element local axes and coordinate systems.
- Added independent GUI visibility toggles for those layers.
- Added camera-distance-aware glyph sizing.
- Engineering symbols honour display-manager visibility.
- Added `docs/ENGINEERING_SYMBOLS.md`.
