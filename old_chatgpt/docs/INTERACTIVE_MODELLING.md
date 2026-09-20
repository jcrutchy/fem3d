# Interactive Modelling — v0.25

FEM3D now has a first viewport-driven construction workflow above the model-editing layer.

## Construction modes

### Add node

Choose **Add node**, then click in the viewport. The screen ray is intersected with the selected construction plane:

- XY — constant Z
- XZ — constant Y
- YZ — constant X

The plane offset is editable. Optional grid snapping is applied after the ray/plane intersection.

If the click is close enough to an existing node for the normal FEM3D picker to find it, that node is reused instead of creating a duplicate.

### Add beam

Choose **Add beam**, then click two points/nodes in sequence. Existing nodes are reused; otherwise a node is created at the construction-plane intersection. A BEAM3D is then created between the two nodes using the first available material and beam section.

After each beam, the second node remains the pending start node, allowing a beam chain to be drawn efficiently.

### Cancel

Cancel leaves interactive construction mode without changing the model.

## Engineering boundaries

The interactive workflow does not bypass `TModelEditor`. Every actual model mutation still goes through the model editing command layer and therefore participates in undo/redo.

The construction plane is a modelling aid only. It does not alter the model coordinate system or analysis formulation.

The solver executables and solver-core snapshot are unchanged by this increment.

## v0.26 — graphical node movement

The Move Node tool is now viewport-driven. Select **Move node**, click a node, drag it on the active construction plane, and release to commit the edit.

During the drag the model is not modified. The renderer shows a temporary node/connected-member preview. The edit is committed as one `TModelEditor.MoveNode` command on mouse release, so undo restores the original position in a single operation.

The construction plane and grid snap settings used by Add Node/Add Beam also govern Move Node. Middle-drag orbit and right-drag pan remain available outside the left-button modelling gesture.


## v0.27 — beam creation feedback and construction-plane snapping

During Add Beam, the first node remains anchored while a cyan construction preview follows the cursor. The preview is graphical only and does not modify the FEM model. Existing nodes are preferred over grid-generated points when the cursor is close enough to a node.

Grid snapping is construction-plane aware: XY keeps Z at the plane offset, XZ keeps Y at the offset, and YZ keeps X at the offset. This avoids accidentally moving a point off the selected drawing plane due to snapping the normal coordinate.

Beam creation remains chain-oriented: after a segment is committed, its second node becomes the next pending start node.

## v0.28 — beam assignment controls

Interactive BEAM3D creation now exposes material, section and group assignment in the MODEL EDITING panel. The selected assignments are applied to each newly committed beam segment, including chained creation. This removes the previous dependence on the first material and first section in the model.

## v0.29 — direct beam meshing

The MODEL EDITING panel and Model menu now provide **Mesh beam**. Select a two-node BEAM3D and enter a maximum element length. FEM3D determines the required number of equal segments and inserts the intermediate nodes. This is intentionally the first simple mesher, not yet a general shell/solid mesh engine.
