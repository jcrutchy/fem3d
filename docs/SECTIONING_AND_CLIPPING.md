# Sectioning and Clipping â€” FEM3D v0.20

Sectioning is viewport/presentation state only. It never modifies the FEM model,
mesh connectivity, solver input, or engineering data.

## Foundation
- Four independent clipping planes.
- Enable/disable and show/hide plane state.
- Arbitrary plane normal and offset.
- Reverse clipping side.
- Combined clipping predicate.
- Display visibility, selection and camera clipping remain independent.

## Future
- Interactive plane manipulators
- Section boxes and boolean clipping volumes
- Solid clipped-face caps
- Saved section states
- Result-aware section inspection

