unit fem_geometry_types;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes;

type
  TVector3 = record X,Y,Z: Double; end;
  TGeoCurveKind = (gckLine,gckCircle,gckArc3);
  TGeoSurfaceKind = (gskPlane);
  TGeoEntityKind = (gekVertex,gekEdge,gekLoop,gekFace,gekBody);
  TGeoDiagnosticSeverity = (gdsInfo,gdsWarning,gdsError);

  TGeoTolerance = record
    Coincidence, EdgeMatch, SurfaceMatch, Feature, Angle: Double;
  end;

  TGeoVertex = record Id: Integer; P: TVector3; end;
  TGeoCurve = record
    Id: Integer; Kind: TGeoCurveKind;
    P1,P2,P3: TVector3; Radius: Double;
  end;
  TGeoEdge = record
    Id,StartVertex,EndVertex,CurveId: Integer;
    T0,T1: Double; Sense: Integer;
  end;
  TGeoLoop = record Id: Integer; EdgeIds: array of Integer; Senses: array of Integer; end;
  TGeoSurface = record
    Id: Integer; Kind: TGeoSurfaceKind; Origin,Normal: TVector3;
  end;
  TGeoFace = record
    Id,SurfaceId,OuterLoopId: Integer; InnerLoopIds: array of Integer;
    Orientation: Integer;
  end;
  TGeoBody = record Id: Integer; FaceIds: array of Integer; end;
  TGeoSet = record Id: Integer; Name,EntityType: string; EntityIds: array of Integer; end;
  TGeoMeta = record Key,Value: string; end;
  TGeoDiagnostic = record Severity: TGeoDiagnosticSeverity; Code,Message: string; EntityKind: TGeoEntityKind; EntityId: Integer; end;

  TVertexArray = array of TGeoVertex;
  TCurveArray = array of TGeoCurve;
  TEdgeArray = array of TGeoEdge;
  TLoopArray = array of TGeoLoop;
  TSurfaceArray = array of TGeoSurface;
  TFaceArray = array of TGeoFace;
  TBodyArray = array of TGeoBody;
  TSetArray = array of TGeoSet;
  TMetaArray = array of TGeoMeta;
  TDiagnosticArray = array of TGeoDiagnostic;

  TFEMGeometryModel = class
  public
    Version: string;
    LengthUnit,ForceUnit,StressUnit: string;
    CoordSys: string;
    Tolerance: TGeoTolerance;
    SourceFormat,SourceName: string;
    Vertices: TVertexArray; Curves: TCurveArray; Edges: TEdgeArray;
    Loops: TLoopArray; Surfaces: TSurfaceArray; Faces: TFaceArray;
    Bodies: TBodyArray; Sets: TSetArray; Meta: TMetaArray;
    constructor Create;
    procedure Clear;
  end;

function V3(AX,AY,AZ: Double): TVector3;
function CurveKindName(K: TGeoCurveKind): string;
function SurfaceKindName(K: TGeoSurfaceKind): string;
function EntityKindName(K: TGeoEntityKind): string;

implementation
function V3(AX,AY,AZ: Double): TVector3; begin Result.X:=AX; Result.Y:=AY; Result.Z:=AZ; end;
function CurveKindName(K:TGeoCurveKind):string; begin case K of gckLine:Result:='LINE'; gckCircle:Result:='CIRCLE'; gckArc3:Result:='ARC3'; end; end;
function SurfaceKindName(K:TGeoSurfaceKind):string; begin case K of gskPlane:Result:='PLANE'; end; end;
function EntityKindName(K:TGeoEntityKind):string; begin case K of gekVertex:Result:='VERTEX'; gekEdge:Result:='EDGE'; gekLoop:Result:='LOOP'; gekFace:Result:='FACE'; gekBody:Result:='BODY'; end; end;
constructor TFEMGeometryModel.Create; begin inherited Create; Version:='1.0'; CoordSys:='CARTESIAN'; LengthUnit:='UNKNOWN'; ForceUnit:='UNKNOWN'; StressUnit:='UNKNOWN'; Tolerance.Coincidence:=0.001; Tolerance.EdgeMatch:=0.005; Tolerance.SurfaceMatch:=0.010; Tolerance.Feature:=0.010; Tolerance.Angle:=1E-8; end;
procedure TFEMGeometryModel.Clear; begin SetLength(Vertices,0);SetLength(Curves,0);SetLength(Edges,0);SetLength(Loops,0);SetLength(Surfaces,0);SetLength(Faces,0);SetLength(Bodies,0);SetLength(Sets,0);SetLength(Meta,0); end;
end.
