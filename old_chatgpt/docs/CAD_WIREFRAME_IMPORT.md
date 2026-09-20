# CAD wireframe import

v0.34 adds a conservative engineering import path for structural stick models.

## DXF

ASCII DXF entities currently promoted to FEM geometry:

- `LINE`
- `POINT`
- `LWPOLYLINE` straight segments

Coincident imported endpoints are merged using a small geometric tolerance. Imported lines become BEAM3D elements with clearly named placeholder material/section properties; these properties are presentation/import defaults and must be replaced with engineering values before analysis.

The importer does not interpret arbitrary CAD layers as FEM properties.

## IGES

The wireframe importer follows the IGES Directory/Parameter section relationship and imports Type 110 line entities. This is intentionally conservative: IGES curves and surfaces are **not** silently converted into beam elements.

A dedicated CAD geometry layer is planned for persistent curves, trimmed surfaces and NURBS/parametric surfaces. That layer will feed a future surface mesher rather than being collapsed into the FEM model on import.

## Engineering intent

The import pipeline is deliberately separated from analysis:

```text
CAD file -> imported geometry -> engineering assignment -> FEM model -> solver
```

This keeps imported CAD dimensions and topology distinct from the assumptions used to create an FE idealisation.
