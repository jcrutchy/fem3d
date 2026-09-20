# FEM3D Viewport Interaction

## v0.18 interaction pass

The viewport now treats selection as an explicit interaction mode rather than implicitly choosing nodes first.

### Selection

- Element and Node selection modes are selectable in the viewport panel.
- Left click selects the current pick target.
- Ctrl+left click adds/removes the picked target from the current selection.
- Clicking empty space clears the selection unless Ctrl is held.
- Clear selection is an explicit viewport command.
- Selection is presentation state and is independent of model visibility and solver state.

### Camera workflow

- Middle mouse drag: orbit.
- Right mouse drag: pan.
- Wheel: dolly/zoom.
- Double-click: focus the current selection.
- Fit selected and Focus selection remain separate operations: fit changes camera distance and target, while focus changes only the target.

### Isolation workflow

A selected set of elements can be isolated directly from the viewport. Isolation is implemented by the display manager and therefore does not modify the FEM model or solver input.

### Design intent

The interaction layer is intentionally kept outside the numerical solver. The solver consumes model/analysis data; the viewport consumes model, selection, display and result data.

Future interaction work should build on this layer with window selection, connected selection, selection filters, cursor-centred zoom, view-normal commands, saved viewpoints and more sophisticated clipping/manipulators.
