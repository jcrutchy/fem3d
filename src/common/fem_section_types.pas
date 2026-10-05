unit fem_section_types;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TPoint2D = record
    X, Y: Double;
  end;
  TPoint2DArray = array of TPoint2D;

  // A 2D planar polygon loop: outer boundary (CCW) or internal hole.
  // Holes are conventionally stored CW, but ComputeSectionProperties accepts
  // either winding for a hole (it works on a CCW-normalised private copy).
  // The outer boundary must be CCW.
  TPolygonLoop = record
    IsHole: Boolean;
    Points: TPoint2DArray; // Closed sequence: Points[High] wraps to Points[0]
  end;
  TPolygonLoopArray = array of TPolygonLoop;

  // A section face composed of an outer boundary and zero or more inner holes
  TSectionFace = record
    OuterLoop: TPolygonLoop;
    Holes: TPolygonLoopArray;
  end;
  TSectionFaceArray = array of TSectionFace;

  TSectionProperties = record
    Name: string;
    LengthUnit: string;

    // Geometric
    Area: Double;
    Perimeter: Double;
    CentroidX, CentroidY: Double;
    GlobalCentroidX, GlobalCentroidY, GlobalCentroidZ: Double;
    BBoxXMin, BBoxXMax, BBoxYMin, BBoxYMax: Double;
    CxPos, CxNeg, CyPos, CyNeg: Double;

    // Second moments of area about centroidal axes
    Ixx, Iyy, Ixy: Double;
    I1, I2: Double;              // Principal moments (I1 >= I2)
    ThetaPrincipalRad: Double;   // Radians
    ThetaPrincipalDeg: Double;   // Degrees

    // Radii of gyration
    rx, ry, r1, r2: Double;

    // Section moduli
    ZxPos, ZxNeg, Zx: Double;
    ZyPos, ZyNeg, Zy: Double;
    Sx, Sy: Double;              // Plastic section moduli

    // Torsion
    J: Double;                   // St. Venant torsion constant
    Ip: Double;                  // Polar moment (Ixx + Iyy)
    JThinWalled: Double;         // Analytical thin-walled open estimate

    // Values for the .fem beam PROPERTIES line.  A beam is entered with Iy and
    // Iz about its own local axes and NO product of inertia, so these are
    // taken about the section's principal axes, measured from the centroid.
    // For a section with Ixy = 0 the principal axes are the section x/y axes
    // and BeamThetaDeg = 0.  Otherwise the member must be oriented so that its
    // local axes lie along the directions below.
    //   local y  <->  section direction (BeamYDirX, BeamYDirY)
    //   local z  <->  section direction (BeamZDirX, BeamZDirY)
    BeamIy, BeamIz: Double;      // Iy = integral(z^2 dA), Iz = integral(y^2 dA)
    BeamCy, BeamCz: Double;      // extreme-fibre distance along local y / local z
    BeamRt: Double;              // largest distance from centroid to the boundary
    BeamThetaDeg: Double;        // rotation of local axes from section x/y axes
    BeamYDirX, BeamYDirY: Double;
    BeamZDirX, BeamZDirY: Double;
  end;

function Pt2D(X, Y: Double): TPoint2D;

implementation

function Pt2D(X, Y: Double): TPoint2D;
begin
  Result.X := X;
  Result.Y := Y;
end;

end.
