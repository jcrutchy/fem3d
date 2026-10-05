unit fem_geometry_types;

// Data model for FEM3DGEO 1.0 (see femgeo/docs/FEM3DGEO.md) -- a
// text-based B-rep geometry interchange format, kept deliberately
// separate from fem3d's own solver-native .fem model (this describes
// shapes; .fem describes a mesh and boundary conditions). One record
// type per spec section, field names matching the spec's own record
// syntax as closely as Pascal identifiers allow, so reading this
// alongside FEM3DGEO.md needs no translation.
//
// IDs throughout are the file's own explicit integer IDs (spec rule 1:
// "IDs are explicit and stable within a file"), NOT array indices --
// every array here is stored in file order, and anything that needs to
// resolve an ID to an array position (fem_geometry_io's parser,
// fem_geometry_validate's checks) builds its own id->index map rather
// than assuming id=index+1. Never assume otherwise when adding code
// that walks these arrays.

{$mode objfpc}{$H+}

interface

type
  TGeoCurveKind = (gcLine, gcCircle, gcArc3);
  TGeoSurfaceKind = (gsPlane);
  TGeoSetEntityKind = (geVertex, geEdge, geLoop, geFace, geBody);

  TGeoVec3 = record
    X, Y, Z: Double;
  end;

  // FEM3DGEO header records (spec section 4). All optional except the
  // version line itself, which fem_geometry_io checks separately
  // before populating any of this.
  TFEMGeoHeader = record
    HasUnits: Boolean;
    LengthUnit: string;       // e.g. 'mm', 'm', 'in', or 'UNKNOWN'
    ForceUnit: string;        // optional, '' if not given
    StressUnit: string;       // optional, '' if not given
    HasCoordSys: Boolean;
    CoordSys: string;         // version 1.0: 'CARTESIAN' only
    HasTolerance: Boolean;
    TolCoincidence, TolEdge, TolSurface, TolFeature, TolAngle: Double;
    HasSource: Boolean;
    SourceFormat: string;
    SourceName: string;       // '' if not given
  end;

  // VERTEX <id> <x> <y> <z>  -- spec section 5
  TGeoVertex = record
    Id: Integer;
    P: TGeoVec3;
  end;
  TGeoVertexArray = array of TGeoVertex;

  // CURVE <id> LINE <x> <y> <z> <dx> <dy> <dz>
  // CURVE <id> CIRCLE <cx> <cy> <cz> <nx> <ny> <nz> <r>
  // CURVE <id> ARC3 <x1> <y1> <z1> <xm> <ym> <zm> <x2> <y2> <z2>
  // -- spec section 6. Only the fields the curve's own Kind uses are
  // meaningful; the others are left at their zero value. A future
  // curve kind (the spec names rational B-splines and conics as
  // planned extensions) needs a new TGeoCurveKind value and its own
  // field group here, NOT a reuse of an existing field for a different
  // meaning -- that's exactly the kind of silent reinterpretation the
  // spec's "unknown curve kinds must be rejected... not guessed" rule
  // (section 6) is guarding against.
  TGeoCurve = record
    Id: Integer;
    Kind: TGeoCurveKind;
    // LINE: Origin + Direction (Direction need not be unit length; the
    // edge's t0/t1 parameter range is in units of Direction's own
    // length, per spec section 7's separation of curve and edge).
    LineOrigin, LineDirection: TGeoVec3;
    // CIRCLE: Center, plane Normal, Radius.
    CircleCenter, CircleNormal: TGeoVec3;
    CircleRadius: Double;
    // ARC3: three non-collinear points the arc passes through
    // (start, mid, end) -- the arc's own center/radius are DERIVED
    // from these three points, not stored redundantly (avoids a file
    // where the stored center/radius disagree with the three points,
    // which ARC3's own three-point definition can't express as an
    // inconsistency in the first place).
    Arc3Start, Arc3Mid, Arc3End: TGeoVec3;
  end;
  TGeoCurveArray = array of TGeoCurve;

  // EDGE <id> <startVertex> <endVertex> <curveId> <t0> <t1> <sense>
  // -- spec section 7
  TGeoEdge = record
    Id: Integer;
    StartVertexId, EndVertexId: Integer;
    CurveId: Integer;
    T0, T1: Double;
    Sense: Integer; // +1 or -1
  end;
  TGeoEdgeArray = array of TGeoEdge;

  // One EDGE <id> <sense> use inside a LOOP record -- spec section 8.
  TGeoLoopEdgeUse = record
    EdgeId: Integer;
    Sense: Integer; // +1 or -1
  end;

  // LOOP <id> EDGE <edgeId> <sense> EDGE <edgeId> <sense> ...
  TGeoLoop = record
    Id: Integer;
    EdgeUses: array of TGeoLoopEdgeUse;
  end;
  TGeoLoopArray = array of TGeoLoop;

  // SURFACE <id> PLANE <ox> <oy> <oz> <nx> <ny> <nz>  -- spec section 9
  TGeoSurface = record
    Id: Integer;
    Kind: TGeoSurfaceKind;
    PlaneOrigin, PlaneNormal: TGeoVec3; // Normal need not be unit length
  end;
  TGeoSurfaceArray = array of TGeoSurface;

  // FACE <id> <surfaceId> OUTER <loopId> [INNER <loopId> ...]
  // -- spec section 10
  TGeoFace = record
    Id: Integer;
    SurfaceId: Integer;
    OuterLoopId: Integer;
    InnerLoopIds: array of Integer;
  end;
  TGeoFaceArray = array of TGeoFace;

  // BODY <id> FACE <faceId> [FACE <faceId> ...]  -- spec section 11
  TGeoBody = record
    Id: Integer;
    FaceIds: array of Integer;
  end;
  TGeoBodyArray = array of TGeoBody;

  // SET <id> "name" <entityType> <entityId> [<entityId> ...]
  // -- spec section 12
  TGeoSet = record
    Id: Integer;
    Name: string;
    EntityKind: TGeoSetEntityKind;
    EntityIds: array of Integer;
  end;
  TGeoSetArray = array of TGeoSet;

  // MTA source_format="STEP" source_entity="#4172"  -- spec section 13.
  // Free-form key=value provenance/attribute pairs, preserved verbatim
  // on round-trip even by tools that don't interpret them (spec: "must
  // preserve unknown attribute records when round-tripping").
  TGeoMetaPair = record
    Key, Value: string;
  end;
  TGeoMetaRecord = record
    Pairs: array of TGeoMetaPair;
  end;
  TGeoMetaArray = array of TGeoMetaRecord;

  TFEMGeometryModel = record
    Header: TFEMGeoHeader;
    Vertices: TGeoVertexArray;
    Curves: TGeoCurveArray;
    Edges: TGeoEdgeArray;
    Loops: TGeoLoopArray;
    Surfaces: TGeoSurfaceArray;
    Faces: TGeoFaceArray;
    Bodies: TGeoBodyArray;
    Sets: TGeoSetArray;
    Meta: TGeoMetaArray;
  end;

function V3(X, Y, Z: Double): TGeoVec3;
function CurveKindName(K: TGeoCurveKind): string;
function SurfaceKindName(K: TGeoSurfaceKind): string;
function SetEntityKindName(K: TGeoSetEntityKind): string;

implementation

function V3(X, Y, Z: Double): TGeoVec3;
begin
  Result.X := X; Result.Y := Y; Result.Z := Z;
end;

function CurveKindName(K: TGeoCurveKind): string;
begin
  case K of
    gcLine:   Result := 'LINE';
    gcCircle: Result := 'CIRCLE';
    gcArc3:   Result := 'ARC3';
  else
    Result := '?';
  end;
end;

function SurfaceKindName(K: TGeoSurfaceKind): string;
begin
  case K of
    gsPlane: Result := 'PLANE';
  else
    Result := '?';
  end;
end;

function SetEntityKindName(K: TGeoSetEntityKind): string;
begin
  case K of
    geVertex: Result := 'VERTEX';
    geEdge:   Result := 'EDGE';
    geLoop:   Result := 'LOOP';
    geFace:   Result := 'FACE';
    geBody:   Result := 'BODY';
  else
    Result := '?';
  end;
end;

end.
