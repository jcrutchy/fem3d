# FEM3D Changelog

## v0.35 - Viewport Box Selection
- Added left-to-right window selection and right-to-left crossing selection.
- Added Ctrl-additive box selection.
- Added screen-space selection rectangle overlay.
- Node selection uses projected node positions.
- Element window selection requires both endpoints inside; crossing selection accepts rectangle/segment intersection.
- Small drags retain normal click selection behaviour.

## v0.32 — Multi-selection geometry editing

- Added undoable translation of selected nodes or selected elements.
- Element translation operates on the unique nodes referenced by the selected elements, preserving shared topology.
- Added multi-element deletion as one undoable operation.
- Added Translate command/button to the model editing UI.
- Existing results are invalidated after geometry edits.
- Numerical solver sources remain unchanged.

## v0.30 — Dedicated beam meshing and assignment UI polish

- Added `FEMBeamMesher` as a separate modelling/meshing layer.
- Added maximum-element-length beam meshing with equal-length subdivision.
- Added material, section and group assignment controls for interactive BEAM3D creation.
- Kept all topology mutation behind `TModelEditor` for atomic undo/redo.
- Improved selection inspection so model properties remain available without solver results.
- No solver-core changes.

## v0.29 — First dedicated beam mesher

- Added `FEMBeamMesher.pas` as a modelling/meshing layer above the model editor.
- Added maximum-element-length meshing for straight two-node BEAM3D members.
- Uses `ceil(L / Lmax)` equal segments and delegates topology changes to `TModelEditor`.
- Added Mesh beam controls to the Model menu and MODEL EDITING panel.
- No solver-core changes.

## v0.28 — Engineering assignment and selection inspection

- Added interactive material, section and group assignment controls for new BEAM3D members.
- Interactive beam creation no longer assumes the first material/section in the model.
- Extended the selection inspector to show model properties without requiring loaded results.
- Node inspection now includes coordinates and six restraint flags.
- Element inspection now includes kind, connectivity, material, section and group references.
- No solver-core changes.

## v0.27 — Interactive construction feedback and beam subdivision

- Added graphical rubber-band preview for interactive BEAM3D creation.
- Existing nodes are preferred during beam preview and commit.
- Made grid snapping construction-plane aware so the plane offset is preserved.
- Added `TModelEditor.SubdivideElement` for equal-length two-node BEAM3D subdivision with one-command undo/redo.
- Original element ID is retained for the first generated segment; additional elements receive new IDs.
- Added verification coverage for subdivision topology, attribute preservation and undo/redo.

# FEM3D v0.23 — Engineering Selection Feedback

- Added viewport hover/preselection state for nodes and elements.
- Added camera-aware hover feedback using the existing perspective/orthographic screen-ray picker.
- Added visual hover highlighting for solid BEAM3D bodies and line-mode elements.
- Added larger hover node markers while preserving selected-node highlighting.
- Hover state is cleared when selection mode changes.
- No solver or numerical-kernel changes.

## v0.21 — Engineering viewport picking and clipping integration

- Replaced the viewport's 2D screen-distance picking approximation with camera-ray picking for nodes and line elements.
- Added `TViewCamera.ScreenRay`, using the actual perspective/orthographic camera state, FOV, pan, target and orientation.
- Node and element picking now works in perspective mode without depending on the legacy orthographic projection helper.
- Added protection against degenerate zero-length pick segments.
- Connected the existing `TClipState` foundation to the OpenGL renderer.
- OpenGL now consumes up to four independent clipping-plane states instead of maintaining a separate renderer-only single-plane implementation.
- Added a reverse-side control for the primary clipping plane.
- Kept sectioning/clipping as presentation state only; model connectivity and solver input remain untouched.
- Added viewport picking documentation.

## v0.18 â€” Viewport interaction pass
- Added explicit Element/Node selection mode.
- Added Ctrl-click additive/toggle selection behaviour.
- Added clear-selection and isolate-selection viewport actions.
- Added double-click focus of the current selection.
- Corrected mouse navigation dispatch so middle/right mouse camera navigation is handled independently of left-click selection.
- Kept selection, display state and camera state outside the solver kernel.
- Added docs/VIEWPORT_INTERACTION.md.

# Changelog

## v0.17 â€” Viewport Controls

- Added perspective and orthographic viewport modes.
- Added adjustable perspective field of view.
- Added independently configurable camera near clipping distance.
- Added Front, Rear, Left, Right, Top, Bottom and Isometric standard views.
- Added Fit all, Fit selected and Focus selection controls.
- Added View menu commands for Fit selection and Focus selection.
- Updated the OpenGL projection setup to use the viewport camera settings.
- Added viewport-control architecture documentation.

## v0.16 â€” Display Manager Implementation

- Added concrete display manager visibility state.
- Added hide/show/isolate operations by element type, material, section and group.
- Added automatic node visibility based on connected visible elements.
- Connected OpenGL rendering to display-manager visibility.
- Added display-manager GUI controls.

## 0.19.0 â€” Engineering viewport graphics

- Added renderer-owned engineering symbol layers for loads, restraints, element local axes and coordinate systems.
- Added independent GUI visibility toggles for those layers.
- Added camera-distance-aware glyph sizing.
- Engineering symbols honour display-manager visibility.
- Added `docs/ENGINEERING_SYMBOLS.md`.


## v0.22 — 3D member body rendering

- Added optional solid-body rendering for `BEAM3D` members in the OpenGL viewport.
- Members are rendered as faceted 8-sided bodies with end caps so oblique/perspective inspection reads as 3D structure rather than centre-lines only.
- Display radius is derived from the section area as an explicitly presentation-only area-equivalent proxy and is bounded relative to member length.
- Added a `Solid members` viewport toggle; the underlying `TBeam3D` formulation and section data are unchanged.
- Element edge visibility remains independent of solid-body visibility.
- Selected members retain a clear engineering selection highlight.
- No solver-core, analysis, persistence or model-contract changes were made.

## v0.24 — Model Editing Foundation
- Added `FEMModelEditor.pas` as the first explicit modelling/edit-command layer.
- Added create node, create beam, move node, delete node, delete element and beam split operations.
- Added conservative snapshot-based undo/redo.
- Beam splitting preserves material, section, thickness, coordinate-system and group attributes.
- Added GUI Model menu and MODEL EDITING controls.
- Editing invalidates displayed solver results and clears selection/hover state.
- Numerical solver core remains untouched.

## v0.25 — Interactive Viewport Modelling
- Added viewport-driven Add Node mode.
- Added viewport-driven Add Beam mode with chained beam creation.
- Added XY/XZ/YZ construction plane selection and editable plane offset.
- Added optional construction grid snapping.
- Existing nodes are reused when picked instead of creating coincident duplicates.
- Added construction-mode status/cancel controls.
- Added camera ray to construction-plane intersection API.
- Kept all model mutations routed through `TModelEditor` undo/redo commands.
- Added interactive modelling documentation.
- Solver core and validated numerical kernel remain untouched.

## v0.26 — Interactive node movement
- Added viewport-driven Move Node mode.
- Node movement uses the active XY/XZ/YZ construction plane and existing grid snap settings.
- Added graphical drag preview without modifying the FEM model until mouse release.
- Connected members follow the preview node graphically during the drag.
- Committed movement remains a single `TModelEditor` command for clean undo/redo.
- Kept numerical solver code and solver contracts unchanged.

## v0.31.0 — Multi-element engineering property assignment
- Added `TModelEditor.AssignElementProperties` as a single undoable model-edit command.
- Material, beam section and group assignments can now be applied to multiple selected elements.
- Added Assign button to the model editing panel and corresponding Model menu command.
- Property assignment validates referenced material/section/group IDs before committing.
- Analysis results are invalidated after assignment through the existing model-edit pathway.
- Numerical solver sources remain unchanged.

## v0.33 — Geometry Transforms and Copy
- Added undoable rotate and mirror operations for selected nodes/element geometry.
- Added topology-aware element copying with shared-node preservation within the copied set.
- Added Rotate, Mirror and Copy model-editing controls.
- Transform operations invalidate prior analysis results through the existing model-edit path.
- Numerical solver sources remain unchanged.

## v0.34 — CAD wireframe import foundation

- Improved ASCII DXF import with entity scanning and coincident endpoint merging.
- Supports DXF LINE, POINT and straight LWPOLYLINE segments.
- Added IGES wireframe import for Type 110 lines using the IGES Directory/Parameter relationship.
- Added File -> Import IGES wireframe.
- Added CAD wireframe import documentation.
- IGES surface entities remain geometry-layer work and are not silently converted into FEM elements.
