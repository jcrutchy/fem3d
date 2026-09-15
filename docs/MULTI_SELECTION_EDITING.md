# Multi-selection Editing

FEM3D v0.32 extends the model editor with topology-aware bulk geometry operations.

## Translation

Nodes can be translated by an explicit `(DX,DY,DZ)` vector. When elements are selected instead, FEM3D gathers the unique nodes referenced by those elements and translates those nodes once. This preserves shared-node topology rather than duplicating or disconnecting the model.

The operation is recorded as a single undoable command. The current implementation deliberately uses explicit Cartesian offsets rather than silently interpreting them in a local element coordinate system.

## Multi-element deletion

Multiple selected elements can be deleted in one operation. Element IDs are matched against the model and removed without changing node IDs. The operation is recorded as one undoable command.

## Engineering behaviour

Geometry edits invalidate loaded analysis results because the previous result document no longer describes the current model geometry. The numerical solver is not modified by these modelling features.

Future operations such as rotate, mirror, copy/pattern and align should build on the same command infrastructure.
