# Model Editing Foundation

FEM3D v0.24 introduces a small model-editing layer in `FEMModelEditor.pas`.

## Design

The editor sits above `TFEMModel` and below the GUI. Editing operations are explicit:

- Create node
- Create two-node `BEAM3D`
- Move node
- Delete node
- Delete element
- Split two-node `BEAM3D`
- Undo
- Redo

Each edit is recorded as a command with before/after model snapshots. Undo and redo therefore restore the model state rather than attempting to reverse individual array operations. This is deliberately conservative while the modelling kernel is being established.

The numerical solver core is not changed by this increment.

## Split behaviour

Splitting a beam creates a midpoint node, changes the original beam to run from its first node to the midpoint, and creates a second beam from the midpoint to the original second node. Material, section, thickness, coordinate-system and group attributes are preserved.

The current implementation is intentionally limited to two-node `BEAM3D` elements. Shell and solid topology editing will be added only when those element kernels exist.

## GUI

The Model menu and MODEL EDITING panel expose the current operations. Beam creation uses the first material and first section in the model; a dedicated property/assignment workflow will replace this later.

Any model edit clears loaded results because existing result data no longer describes the edited model.


## Beam subdivision — v0.27

A two-node `BEAM3D` can be subdivided into an arbitrary number of equal-length segments (currently guarded to a practical UI range of 2..1000). The original element ID is retained for the first segment; additional segments receive new IDs. Internal nodes are inserted linearly between the original end nodes.

All generated beam segments inherit the original material, section, thickness, coordinate-system and group attributes. The entire subdivision is one undo/redo command rather than a sequence of visible edits.

## Selection inspection — v0.28

The selection inspector now reports model properties even when no solver result is loaded. Node selections show coordinates and restraint flags. Element selections show kind, connectivity and referenced material, section and group, followed by result values when a result document is available.

## Beam meshing by maximum length — v0.29

`FEMBeamMesher` provides the first dedicated meshing layer. For a straight two-node `BEAM3D`, the requested maximum element length is converted to an integer number of equal segments using `ceil(L / Lmax)`. The actual topology change is still committed through `TModelEditor`, preserving the single-command undo/redo and model-edit/result invalidation behaviour.
