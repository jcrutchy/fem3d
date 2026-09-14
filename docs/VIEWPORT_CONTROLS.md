# FEM3D Viewport Controls

## v0.17 implementation

The viewport camera is presentation state and is deliberately independent of the FEM solver kernel.

### Projection

- **Perspective** provides a conventional engineering 3D camera with adjustable field of view.
- **Orthographic** removes perspective convergence and is useful for inspection and technical drawings.
- **FOV** is available in degrees for perspective mode and is constrained to a sensible 10–120 degree range.
- **Near clip** is independently configurable. This is important when the engineer moves the camera inside a structure and needs to inspect the opposite face or interior.

### Navigation

- Middle mouse drag: orbit.
- Right mouse drag: pan.
- Mouse wheel: dolly/zoom.
- Fit all: frame the complete model.
- Fit selected: frame selected nodes/elements.
- Focus selection: move the camera target to the selection centroid without changing the model.

### Standard views

Front, rear, left, right, top, bottom and isometric views are available. They change orientation only; they do not modify the model or selection.

### Design intent

Camera operations are strictly display operations. They do not modify analysis data, model coordinates, solver settings, or persisted solver provenance.

The next viewport increment can add saved viewpoints, view-normal-to-selected-face/element operations, camera inertia, and a controlled walk/fly mode without coupling any of those features to the numerical kernel.
