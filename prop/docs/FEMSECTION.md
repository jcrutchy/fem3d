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
   - St. Venant torsion constant ($J$):
     Computed by solving the Prandtl stress function Poisson boundary value problem:
     $\nabla^2 \phi = -2$ with $\phi = 0$ on the boundary, using an embedded grid Preconditioned Conjugate Gradient (PCG) solver, where $J = 2 \iint \phi \, dA$.
     An analytical thin-walled approximation $J_{tw} = \sum \frac{1}{3} b_i t_i^3$ is also provided for open thin-walled profiles.

## 3. `.prop` File Format Specification

Sectioned and key=value syntax (matching `.fem` and `.fgeo` conventions):

```ini
# FEM3D Section Properties File (.prop)
[HEADER]
Source=310UB40.4.fgeo
SourceUnits=length=mm
LengthUnit=mm
GeneratedBy=femsection

[SECTION]
Name=310UB40.4
Type=beam

[GEOMETRY]
Area=5.2100000000000000E+003
Perimeter=1.2360000000000000E+003
CentroidX=8.2500000000000000E+001
CentroidY=1.5200000000000000E+002
BBoxXMin=0.0000000000000000E+000
BBoxXMax=1.6500000000000000E+002
BBoxYMin=0.0000000000000000E+000
BBoxYMax=3.0400000000000000E+002
CxPos=8.2500000000000000E+001
CxNeg=8.2500000000000000E+001
CyPos=1.5200000000000000E+002
CyNeg=1.5200000000000000E+002

[SECOND_MOMENTS]
Ixx=8.6400000000000000E+007
Iyy=7.6500000000000000E+006
Ixy=0.0000000000000000E+000
I1=8.6400000000000000E+007
I2=7.6500000000000000E+006
ThetaPrincipalDeg=0.0000000000000000E+000

[RADII_OF_GYRATION]
rx=1.2877395000000000E+002
ry=3.8318800000000000E+001
r1=1.2877395000000000E+002
r2=3.8318800000000000E+001

[SECTION_MODULI]
ZxPos=5.6842105263157895E+005
ZxNeg=5.6842105263157895E+005
Zx=5.6842105263157895E+005
ZyPos=9.2727272727272727E+004
ZyNeg=9.2727272727272727E+004
Zy=9.2727272727272727E+004
Sx=6.3300000000000000E+005
Sy=1.4200000000000000E+005

[TORSION]
J=1.5700000000000000E+005
Ip=9.4050000000000000E+007

[FEM_PROPERTY_SNIPPET]
# id, type, material, area, Iy, Iz, J, Cy, Cz, Rt
Property=1, beam, 1, 5.2100000000000000E+003, 7.6500000000000000E+006, 8.6400000000000000E+007, 1.5700000000000000E+005, 1.5200000000000000E+002, 8.2500000000000000E+001, 1.5200000000000000E+002

4. Exit Codes

  - 0: Clean success
  - 1: Mathematical or geometry error (zero/negative area, open loop,
    self-intersection, etc.)
  - 2: CLI usage error
  - 3: File open or syntax parse error
