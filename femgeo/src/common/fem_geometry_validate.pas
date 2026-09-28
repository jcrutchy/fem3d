unit fem_geometry_validate;
{$mode objfpc}{$H+}
interface
uses SysUtils, fem_geometry_types;
function ValidateGeometry(M:TFEMGeometryModel; out D:TDiagnosticArray):Boolean;
implementation
procedure Add(var A:TDiagnosticArray; Sev:TGeoDiagnosticSeverity; const Code,Msg:string; K:TGeoEntityKind; Id:Integer);var N:Integer;begin N:=Length(A);SetLength(A,N+1);A[N].Severity:=Sev;A[N].Code:=Code;A[N].Message:=Msg;A[N].EntityKind:=K;A[N].EntityId:=Id;end;
function HasV(M:TFEMGeometryModel;Id:Integer):Boolean;var i:Integer;begin Result:=False;for i:=0 to High(M.Vertices) do if M.Vertices[i].Id=Id then exit(True);end;
function HasC(M:TFEMGeometryModel;Id:Integer):Boolean;var i:Integer;begin Result:=False;for i:=0 to High(M.Curves) do if M.Curves[i].Id=Id then exit(True);end;
function HasE(M:TFEMGeometryModel;Id:Integer):Boolean;var i:Integer;begin Result:=False;for i:=0 to High(M.Edges) do if M.Edges[i].Id=Id then exit(True);end;
function HasL(M:TFEMGeometryModel;Id:Integer):Boolean;var i:Integer;begin Result:=False;for i:=0 to High(M.Loops) do if M.Loops[i].Id=Id then exit(True);end;
function HasS(M:TFEMGeometryModel;Id:Integer):Boolean;var i:Integer;begin Result:=False;for i:=0 to High(M.Surfaces) do if M.Surfaces[i].Id=Id then exit(True);end;
function HasF(M:TFEMGeometryModel;Id:Integer):Boolean;var i:Integer;begin Result:=False;for i:=0 to High(M.Faces) do if M.Faces[i].Id=Id then exit(True);end;
function EdgeEnds(M:TFEMGeometryModel; EdgeId,Sense:Integer; out A,B:Integer):Boolean;var i:Integer;begin Result:=False;A:=0;B:=0;for i:=0 to High(M.Edges) do if M.Edges[i].Id=EdgeId then begin if Sense=1 then begin A:=M.Edges[i].StartVertex;B:=M.Edges[i].EndVertex;end else begin A:=M.Edges[i].EndVertex;B:=M.Edges[i].StartVertex;end;Exit(True);end;end;
function ValidateGeometry(M:TFEMGeometryModel;out D:TDiagnosticArray):Boolean;
var i,j,A,B,NA,NB:Integer;E:TGeoEdge;L:TGeoLoop;F:TGeoFace;S:TGeoSurface;N2:Double;
begin
 SetLength(D,0); if M.Version<>'1.0' then Add(D,gdsError,'GEO010','unsupported FEM3DGEO version '+M.Version,gekBody,0);
 for i:=0 to High(M.Vertices) do begin if M.Vertices[i].Id<=0 then Add(D,gdsError,'GEO002','vertex id must be positive',gekVertex,M.Vertices[i].Id);for j:=i+1 to High(M.Vertices) do if M.Vertices[i].Id=M.Vertices[j].Id then Add(D,gdsError,'GEO002','duplicate vertex id',gekVertex,M.Vertices[i].Id);end;
 for i:=0 to High(M.Curves) do for j:=i+1 to High(M.Curves) do if M.Curves[i].Id=M.Curves[j].Id then Add(D,gdsError,'GEO002','duplicate curve id',gekEdge,M.Curves[i].Id);
 for i:=0 to High(M.Edges) do begin E:=M.Edges[i];for j:=i+1 to High(M.Edges) do if E.Id=M.Edges[j].Id then Add(D,gdsError,'GEO002','duplicate edge id',gekEdge,E.Id);if not HasV(M,E.StartVertex) then Add(D,gdsError,'GEO001','missing start vertex',gekEdge,E.Id);if not HasV(M,E.EndVertex) then Add(D,gdsError,'GEO001','missing end vertex',gekEdge,E.Id);if not HasC(M,E.CurveId) then Add(D,gdsError,'GEO001','missing curve',gekEdge,E.Id);if (E.Sense<>1) and (E.Sense<>-1) then Add(D,gdsError,'GEO005','edge sense must be +1 or -1',gekEdge,E.Id);if E.StartVertex=E.EndVertex then Add(D,gdsError,'GEO008','edge has identical endpoints',gekEdge,E.Id);end;
 for i:=0 to High(M.Loops) do begin L:=M.Loops[i];for j:=i+1 to High(M.Loops) do if L.Id=M.Loops[j].Id then Add(D,gdsError,'GEO002','duplicate loop id',gekLoop,L.Id);if Length(L.EdgeIds)=0 then Add(D,gdsError,'GEO004','empty loop',gekLoop,L.Id);if Length(L.EdgeIds)<>Length(L.Senses) then Add(D,gdsError,'GEO004','loop edge/sense count mismatch',gekLoop,L.Id);for j:=0 to High(L.EdgeIds) do if not HasE(M,L.EdgeIds[j]) then Add(D,gdsError,'GEO001','loop references missing edge',gekLoop,L.Id);if Length(L.EdgeIds)>0 then if EdgeEnds(M,L.EdgeIds[0],L.Senses[0],A,B) then begin for j:=1 to High(L.EdgeIds) do if EdgeEnds(M,L.EdgeIds[j],L.Senses[j],NA,NB) then begin if B<>NA then Add(D,gdsError,'GEO004','loop is not topologically continuous',gekLoop,L.Id);B:=NB;end;if B<>A then Add(D,gdsError,'GEO004','loop is not closed',gekLoop,L.Id);end;end;
 for i:=0 to High(M.Surfaces) do begin S:=M.Surfaces[i];for j:=i+1 to High(M.Surfaces) do if S.Id=M.Surfaces[j].Id then Add(D,gdsError,'GEO002','duplicate surface id',gekFace,S.Id);N2:=S.Normal.X*S.Normal.X+S.Normal.Y*S.Normal.Y+S.Normal.Z*S.Normal.Z;if N2<=0 then Add(D,gdsError,'GEO005','surface normal is zero',gekFace,S.Id);end;
 for i:=0 to High(M.Faces) do begin F:=M.Faces[i];for j:=i+1 to High(M.Faces) do if F.Id=M.Faces[j].Id then Add(D,gdsError,'GEO002','duplicate face id',gekFace,F.Id);if not HasS(M,F.SurfaceId) then Add(D,gdsError,'GEO001','face references missing surface',gekFace,F.Id);if not HasL(M,F.OuterLoopId) then Add(D,gdsError,'GEO001','face references missing outer loop',gekFace,F.Id);for j:=0 to High(F.InnerLoopIds) do if not HasL(M,F.InnerLoopIds[j]) then Add(D,gdsError,'GEO001','face references missing inner loop',gekFace,F.Id);end;
 for i:=0 to High(M.Bodies) do begin for j:=i+1 to High(M.Bodies) do if M.Bodies[i].Id=M.Bodies[j].Id then Add(D,gdsError,'GEO002','duplicate body id',gekBody,M.Bodies[i].Id);for j:=0 to High(M.Bodies[i].FaceIds) do if not HasF(M,M.Bodies[i].FaceIds[j]) then Add(D,gdsError,'GEO001','body references missing face',gekBody,M.Bodies[i].Id);end;
 Result:=True;for i:=0 to High(D) do if D[i].Severity=gdsError then Exit(False);
end;
end.
