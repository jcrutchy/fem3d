# Geometry regression extension

The existing FEM3D regression harness already protects solver models with
SHA-256 manifests and deliberately BORKED cases. Geometry tests should reuse
that philosophy rather than creating a second testing framework.

Suggested manifest extension:

```ini
[CASE]
ID=G001
Name=Simple rectangle geometry
Status=VERIFIED
Tool=femgeocheck

[FILES]
Input=001_rectangle.fgeo
InputSHA256=<sha256>
ManifestSHA256=<sha256>

[EXPECTATIONS]
ExpectedExitCode=0
```

A BORKED case uses the same fields with a non-zero expected exit code and,
optionally, `ExpectedErrorContains=GEO001`.

For importer integration cases:

```ini
Tool=step2femgeo
Source=bracket.step
ExpectedExitCode=0
Output=bracket.fgeo
```

The harness should capture stdout/stderr exactly as it already does for
solvers, and a later checker step can validate the generated `.fgeo`.
