# Box Selection

FEM3D v0.35 adds viewport box selection. Drag left-to-right for window selection: elements are selected when both end nodes are inside the rectangle. Drag right-to-left for crossing selection: an element is selected when its projected segment intersects the rectangle. In node mode, nodes inside the rectangle are selected. Hold Ctrl to add to the existing selection. A short drag below the selection threshold behaves as ordinary click selection.

Selection is performed against the current camera projection, so perspective and orthographic views use the same screen-space interaction. The selection rectangle is graphical only and does not alter model state.
