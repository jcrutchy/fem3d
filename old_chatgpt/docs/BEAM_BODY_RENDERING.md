# Beam Body Rendering

## Purpose

v0.22 adds a visual 3D body for `BEAM3D` members. This is a viewport feature only.

## Transparency rule

The current `TBeamSection` record contains area and section inertias, but does not identify a physical section profile (I-section, RHS, CHS, rectangle, etc.). FEM3D therefore must not invent a physical profile from those values.

The renderer instead creates an **area-equivalent circular display radius**:

`R = sqrt(A / pi)`

The radius is bounded relative to member length so extremely small or very large section areas remain visually usable.

This geometry is explicitly presentation-only. It is not used by the solver, stiffness formulation, persistence contract, validation or result recovery.

## Rendering

- Eight-sided faceted body.
- End caps.
- Camera/deformation-aware endpoints.
- Result contour colour is applied to the body when a result field is active.
- Selected members receive an additional centre-line highlight.
- Element edge visibility remains independent of body visibility.

## Future physical sections

When physical section profiles are added to the model, they should become explicit model data with their own validation and persistence rules. The renderer should then use those explicit profiles rather than attempting to infer them from `A`, `Iy`, `Iz` and `J`.
