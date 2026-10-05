# FEMSECTION 1.0 — Section Properties Specification & Tool

## 1. Purpose

`femsection` calculates the full suite of cross-sectional engineering properties
from a `FEM3DGEO` (`.fgeo`) planar cross-section file and writes a `.prop` file.
It requires zero third-party libraries and follows the standard Unix streaming
pipeline conventions of `fem3d`.

## 2. Properties Computed

1. **Geometric & Area Properties:**
   - Total Gross Area ($A$)
   - Perimeter ($P$)
   - Centroid coordinates ($\bar{x}, \bar{y}$, and global 3D centroid)
   - Section bounding box ($x_{min}, x_{max}, y_{min}, y_{max}$)
   - Distance from centroid to extreme fibres ($c_x^+, c_x^-, c_y^+, c_y^-$)

2. **Second Moments of Area (Moments of Inertia):**
   - Centroidal second moments ($I_{xx}, I_{yy}, I_{xy}$) via exact Green's theorem contour integrals
   - Principal second moments ($I_1, I_2$ where $I_1 \ge I_2$)
   - Principal axis orientation angle ($\theta_p$)
   - Radii of gyration ($r_x, r_y, r_1, r_2$)

3. **Section Moduli:**
   - Elastic section moduli:
     $Z_{xx}^+ = I_{xx}/c_y^+$, $Z_{xx}^- = I_{xx}/c_y^-$, $Z_{xx} = \min(Z_{xx}^+, Z_{xx}^-)$
     $Z_{yy}^+ = I_{yy}/c_x^+$, $Z_{yy}^- = I_{yy}/c_x^-$, $Z_{yy} = \min(Z_{yy}^+, Z_{yy}^-)$
   - Plastic section moduli ($S_{xx}, S_{yy}$):
     Determined by locating the exact Plastic Neutral Axis (PNA) splitting the section
     into equal areas ($A/2$) via monotonic Sutherland-Hodgman polygon clipping,
     followed by centroidal integration of each half.

4. **Torsional Properties:**
   - Polar moment of inertia: $I_p = I_{xx} + I_{yy}$
   - St. Venant torsion constant ($J$), computed by solving the Prandtl stress
     function problem $\nabla^2 \phi = -2$ on a regular grid embedded in the
     section's bounding box (150 nodes across the width), with $J = 2 \iint \phi \, dA$.
     - **Solver:** Conjugate Gradient on the symmetric positive definite
       finite-difference system, stopped on a relative residual of $10^{-10}$
       (not on a fixed iteration count).
     - **Boundary position:** a grid link that crosses the section boundary is
       weighted by the fraction $\theta$ of the link that lies inside the
       section (found by bisection on the polygon), rather than snapping the
       boundary to the nearest node. This removes the "one cell too thick"
       bias of a plain staircase classification.
     - **Solid sections:** $\phi = 0$ on the boundary.
     - **Hollow (closed) sections:** $\phi$ is a constant $c_k$ on each hole,
       determined by the circulation condition. This is implemented with the
       membrane-analogy "lid": every grid node inside hole $k$ shares one
       unknown $c_k$, and $J$ includes the volume under the lid. Multi-cell
       sections get one unknown per cell. A hole smaller than one grid cell
       owns no node and is ignored.
     - **Thin-walled floor:** the result is never allowed below
       $J_{tw} = \tfrac{4}{3} A^3 / P^2$, the asymptotic value for an open
       thin-walled profile (for a closed section this is the J of the same tube
       with a slit cut in it, so it is only a lower bound there).

     Measured accuracy against closed-form values (checked by `run_section_test`): square,
     rectangle and ribbon within 0.25%; solid circle 0.01%; circular tubes
     (3 mm to 20 mm wall) within 0.05%. Walls thinner than about one grid cell
     (roughly width/150) are not resolved; the thin-wall floor applies there.

## 3. `.prop` File Format Specification

Sectioned and key=value syntax (matching `.fem` and `.fgeo` conventions). The
example below is the actual output of `femsection examples/200ub25_4.fgeo`.

```ini
# FEM3D Section Properties File (.prop)
[HEADER]
Source=200ub25_4.fgeo
LengthUnit=mm
GeneratedBy=femsection

[SECTION]
Name=200UB25.4
Type=beam

[GEOMETRY]
Area=3.230900137526791E+03
Perimeter=9.115181722939844E+02
CentroidX=0.000000000000000E+00
CentroidY=-4.503981741604103E-15
BBoxXMin=-6.650000000000000E+01
BBoxXMax=6.650000000000000E+01
BBoxYMin=-1.016000000000000E+02
BBoxYMax=1.016000000000000E+02
CxPos=6.650000000000000E+01
CxNeg=6.650000000000000E+01
CyPos=1.016000000000000E+02
CyNeg=1.016000000000000E+02

[SECOND_MOMENTS]
Ixx=2.357977894315745E+07
Iyy=3.063293335138907E+06
Ixy=0.000000000000000E+00
I1=2.357977894315745E+07
I2=3.063293335138906E+06
ThetaPrincipalDeg=0.000000000000000E+00

[RADII_OF_GYRATION]
rx=8.542954577848445E+01
ry=3.079161908672171E+01
r1=8.542954577848445E+01
r2=3.079161908672170E+01

[SECTION_MODULI]
ZxPos=2.320844384169040E+05
ZxNeg=2.320844384169040E+05
Zx=2.320844384169040E+05
ZyPos=4.606456143066026E+04
ZyNeg=4.606456143066026E+04
Zy=4.606456143066026E+04
Sx=2.599839498646148E+05
Sy=7.089732543422622E+04

[TORSION]
J=6.300276549075908E+04
Ip=2.664307227829636E+07

[FEM_PROPERTY_SNIPPET]
# Ready-to-paste line for .fem [PROPERTIES] section:
# id, type, material, area, Iy, Iz, J, Cy, Cz, Rt
Property=1, beam, 1, 3.230900137526791E+03, 3.063293335138906E+06, 2.357977894315745E+07, 6.300276549075908E+04, 1.016000000000000E+02, 6.650000000000000E+01, 1.214282092431573E+02
```

Notes on the fields:

- `Source` is the input file name as given on the command line (without any
  directory), or `-` when reading from stdin. `Name` is the `SOURCE name="..."`
  from the `.fgeo` header when it has one, otherwise the file name without its
  extension (`section` for stdin).
- `Perimeter` includes hole perimeters.
- `Cx*/Cy*` are distances from the centroid to the extreme fibres.
- `Sx`, `Sy` are plastic moduli about the centroidal x and y axes.
- The `Property=` line is the beam line for the `.fem` `[PROPERTIES]` section.
  Its values are about the section's **principal axes** (see section 5), and
  are:
  - `Iy`, `Iz`: the principal second moments. `Iz` is the moment about the
    axis along local z, i.e. the one paired with distances measured along local
    y (the section's y direction when there is no rotation); for a section that
    is symmetric about its x and y axes this is `Iz = Ixx`, `Iy = Iyy`.
  - `Cy`, `Cz`: the largest distance from the centroid to the outline along
    local y and local z, taken over **both** sides, so an unsymmetric section
    gets the worse side (the `.fem` stress corners are symmetric, ±Cy, ±Cz).
  - `Rt`: the largest distance from the centroid to any boundary point. This
    is the outer-fibre radius for `TAU = T·Rt/J`: exact for a circle, and an
    upper-bound estimate for other shapes (a rectangle's corner, an I-section's
    flange tip).
- When the section is not symmetric (`Ixy` not zero) the snippet is preceded by
  comment lines giving the rotation and the section directions the member's
  local y and z axes must be oriented along.

## 4. Exit Codes

  - 0: Clean success
  - 1: Mathematical or geometry error (zero/negative area, open loop,
    self-intersection, etc.)
  - 2: CLI usage error
  - 3: File open or syntax parse error

## 5. Geometry Conventions and Known Limitations

- **Supported edges.** `LINE`, `ARC3` and `CIRCLE` curves. A curved edge is
  flattened to a polygon with no more than 1 degree per segment (a full circle's
  area is then 0.005% low, and the polygon is inscribed). For `ARC3` the edge
  covers the curve between its `t0` and `t1`, where `t` runs 0..1 over the whole
  three-point arc; for `CIRCLE`, `t` is the angle in radians from +X
  (counter-clockwise for a +Z normal, clockwise for -Z). Edge and loop senses
  are honoured, so an edge stored against its curve direction is handled.
  Circles must lie in a plane parallel to XY.
- **Loop winding.** The outer boundary of a face is normalised to
  counter-clockwise on load. Hole loops may be given in either winding;
  `ComputeSectionProperties` works on a private counter-clockwise copy and
  never modifies the caller's data. Holes may sit anywhere relative to the
  origin.
- **Beam line and principal axes.** A `.fem` beam property has `Iy` and `Iz`
  but no product of inertia, so `femsection` writes the values about the
  section's principal axes, rotated from the section x/y axes by the smallest
  angle (never more than 45 degrees). Orient the member so that its local y and
  z axes lie along the directions given in the comment lines above the
  `Property=` line. If the member is oriented along the section's x/y axes
  instead, the product of inertia is lost and the bending of an unsymmetric
  section is not modelled correctly.
- **Grid-based J.** J is a numerical solution on a 150-node-wide grid (up to
  300 nodes tall). It is accurate for compact and moderately thin sections
  (section 2.4); features thinner than about one grid cell are not resolved.
  Calling `ComputeSectionProperties` with `SolveNumericalJ = False` leaves J at
  the thin-wall lower bound only, which is far too low for compact sections;
  `femsection` always solves.
- **Catalogue sections.** `fem_section_db` rebuilds a standard section from the
  dimensions printed in a JSON catalogue (`db/liberty_db.json`) and passes it
  through the same calculator, so a catalogue designation can supply a beam
  property (see `docs/femref.md`). Universal beams/columns/bearing piles and
  parallel flange channels are supported; tapered flange beams and angles are
  refused because the catalogue lacks the flange slope / root and toe radii.
  Computed values agree with the printed catalogue to about 1% (J: 2.5% for
  I-sections, 6% for channels).
- **Self-test.** `run_section_test` (in `src/tools/patch_test`, run by
  `test.bat`) holds the closed-form checks for areas,
  inertias, plastic moduli, hole placement and winding, J (solid, hollow and
  multi-cell), curved edges read from FEM3DGEO text, and the beam-line values.
