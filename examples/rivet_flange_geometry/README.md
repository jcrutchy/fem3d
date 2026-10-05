# Example: a flange strip with a row of rivet holes

A minimal but realistic stand-in for Jared's actual use case (a
stiffened flange around a fuselage access-door opening, a row of
rivets) -- a 200x50mm outline, 5 holes on their own DXF layer, a
filleted corner (ARC), and a TEXT label to demonstrate that an
unsupported entity is flagged, not silently dropped.

Regenerate `flange.fgeo` from `flange.dxf`:

```
dxf2femgeo flange.dxf > flange.fgeo
```

Check it:

```
femgeocheck flange.fgeo
```

Expect `0 error(s)` and a run of `GEO003 WARNING ... is not used by any
loop` for every edge -- correct and expected, not a bug: `dxf2femgeo`
deliberately only emits vertices/curves/edges (a "wireframe soup"), not
loops/faces/bodies -- see the adaptor's own header comment and
`docs/TODO_femgeo.md` for why that reconstruction is a downstream
tool's job. `femgeocheck`'s stderr output during the conversion itself
also reports one `GEO009 WARNING` for the TEXT entity, and a one-line
summary of what was and wasn't converted.
