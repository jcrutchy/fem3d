unit fem_geometry_io;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes, StrUtils, fem_geometry_types;
procedure WriteFGeo(M: TFEMGeometryModel; S: TStream);
function LoadFGeo(S: TStream; M: TFEMGeometryModel; out Err: string): Boolean;
function SaveFGeoFile(const FN: string; M: TFEMGeometryModel; out Err: string): Boolean;
function LoadFGeoFile(const FN: string; M: TFEMGeometryModel; out Err: string): Boolean;
implementation
function F(X:Double):string; var FS:TFormatSettings; begin FS:=DefaultFormatSettings; FS.DecimalSeparator:='.'; FS.ThousandSeparator:=#0; Result:=FloatToStr(X,FS); end;
function Q(const S:string):string; begin Result:='"'+StringReplace(StringReplace(StringReplace(StringReplace(S,'\\','\\\\',[rfReplaceAll]),'"','\\"',[rfReplaceAll]),#13,'\\r',[rfReplaceAll]),#10,'\\n',[rfReplaceAll])+'"'; end;
procedure W(S:TStream; const X:string); var B:AnsiString; Ch:AnsiChar; begin B:=X; if Length(B)>0 then S.WriteBuffer(B[1],Length(B)); Ch:=#10; S.WriteBuffer(Ch,1); end;
procedure WriteFGeo(M:TFEMGeometryModel;S:TStream); var i,j:Integer; L:string;
begin
 W(S,'FEM3DGEO '+M.Version); W(S,'UNITS length='+M.LengthUnit+' force='+M.ForceUnit+' stress='+M.StressUnit); W(S,'COORDSYS '+M.CoordSys);
 W(S,'TOLERANCE coincidence='+F(M.Tolerance.Coincidence)+' edge='+F(M.Tolerance.EdgeMatch)+' surface='+F(M.Tolerance.SurfaceMatch)+' feature='+F(M.Tolerance.Feature)+' angle='+F(M.Tolerance.Angle));
 if M.SourceFormat<>'' then W(S,'SOURCE format='+M.SourceFormat+' name='+Q(M.SourceName));
 for i:=0 to High(M.Vertices) do with M.Vertices[i] do W(S,Format('VERTEX %d %s %s %s',[Id,F(P.X),F(P.Y),F(P.Z)]));
 for i:=0 to High(M.Curves) do with M.Curves[i] do begin case Kind of gckLine: L:=Format('CURVE %d LINE %s %s %s %s %s %s',[Id,F(P1.X),F(P1.Y),F(P1.Z),F(P2.X),F(P2.Y),F(P2.Z)]); gckCircle:L:=Format('CURVE %d CIRCLE %s %s %s %s %s %s %s',[Id,F(P1.X),F(P1.Y),F(P1.Z),F(P2.X),F(P2.Y),F(P2.Z),F(Radius)]); gckArc3:L:=Format('CURVE %d ARC3 %s %s %s %s %s %s %s %s %s',[Id,F(P1.X),F(P1.Y),F(P1.Z),F(P2.X),F(P2.Y),F(P2.Z),F(P3.X),F(P3.Y),F(P3.Z)]); end; W(S,L); end;
 for i:=0 to High(M.Edges) do with M.Edges[i] do W(S,Format('EDGE %d %d %d %d %s %s %d',[Id,StartVertex,EndVertex,CurveId,F(T0),F(T1),Sense]));
 for i:=0 to High(M.Loops) do begin L:=Format('LOOP %d',[M.Loops[i].Id]); for j:=0 to High(M.Loops[i].EdgeIds) do L:=L+Format(' EDGE %d %d',[M.Loops[i].EdgeIds[j],M.Loops[i].Senses[j]]); W(S,L); end;
 for i:=0 to High(M.Surfaces) do with M.Surfaces[i] do W(S,Format('SURFACE %d PLANE %s %s %s %s %s %s',[Id,F(Origin.X),F(Origin.Y),F(Origin.Z),F(Normal.X),F(Normal.Y),F(Normal.Z)]));
 for i:=0 to High(M.Faces) do begin L:=Format('FACE %d %d OUTER %d',[M.Faces[i].Id,M.Faces[i].SurfaceId,M.Faces[i].OuterLoopId]); for j:=0 to High(M.Faces[i].InnerLoopIds) do L:=L+Format(' INNER %d',[M.Faces[i].InnerLoopIds[j]]); W(S,L); end;
 for i:=0 to High(M.Bodies) do begin L:=Format('BODY %d',[M.Bodies[i].Id]); for j:=0 to High(M.Bodies[i].FaceIds) do L:=L+Format(' FACE %d',[M.Bodies[i].FaceIds[j]]); W(S,L); end;
 for i:=0 to High(M.Sets) do begin L:=Format('SET %d %s %s',[M.Sets[i].Id,Q(M.Sets[i].Name),M.Sets[i].EntityType]); for j:=0 to High(M.Sets[i].EntityIds) do L:=L+Format(' %d',[M.Sets[i].EntityIds[j]]); W(S,L); end;
 for i:=0 to High(M.Meta) do W(S,'META '+M.Meta[i].Key+'='+Q(M.Meta[i].Value));
end;
function Tok(const L:string):TStringList; begin Result:=TStringList.Create; Result.Delimiter:=' '; Result.StrictDelimiter:=False; Result.DelimitedText:=Trim(L); end;
function D(const S:string):Double; begin Result:=StrToFloat(S,FormatSettings); end;
function I(const S:string):Integer; begin Result:=StrToInt(S); end;
function LoadFGeo(S:TStream;M:TFEMGeometryModel;out Err:string):Boolean;
var SS,T:TStringList; L:string; i,j,n:Integer; C:TGeoCurve; E:TGeoEdge; LP:TGeoLoop; SF:TGeoSurface; FC:TGeoFace; B:TGeoBody; V:TGeoVertex; Z:TGeoSet;
begin
 Result:=False; Err:=''; M.Clear; SS:=TStringList.Create;
 try
  SS.LoadFromStream(S);
  try
   for i:=0 to SS.Count-1 do begin
    L:=Trim(SS[i]); if (L='') or (L[1]='#') then Continue;
    T:=Tok(L);
    try
     if T.Count=0 then Continue
     else if T[0]='FEM3DGEO' then begin if T.Count<2 then raise Exception.Create('missing format version'); M.Version:=T[1]; end
     else if T[0]='UNITS' then begin
      for j:=1 to T.Count-1 do begin
       if Pos('length=',T[j])=1 then M.LengthUnit:=Copy(T[j],8,MaxInt)
       else if Pos('force=',T[j])=1 then M.ForceUnit:=Copy(T[j],7,MaxInt)
       else if Pos('stress=',T[j])=1 then M.StressUnit:=Copy(T[j],8,MaxInt);
      end;
     end
     else if T[0]='COORDSYS' then M.CoordSys:=T[1]
     else if T[0]='TOLERANCE' then begin
      for j:=1 to T.Count-1 do begin
       if Pos('coincidence=',T[j])=1 then M.Tolerance.Coincidence:=D(Copy(T[j],13,MaxInt))
       else if Pos('edge=',T[j])=1 then M.Tolerance.EdgeMatch:=D(Copy(T[j],6,MaxInt))
       else if Pos('surface=',T[j])=1 then M.Tolerance.SurfaceMatch:=D(Copy(T[j],9,MaxInt))
       else if Pos('feature=',T[j])=1 then M.Tolerance.Feature:=D(Copy(T[j],9,MaxInt))
       else if Pos('angle=',T[j])=1 then M.Tolerance.Angle:=D(Copy(T[j],7,MaxInt));
      end;
     end
     else if T[0]='SOURCE' then begin M.SourceFormat:=Copy(T[1],8,MaxInt); if T.Count>2 then M.SourceName:=StringReplace(Copy(T[2],6,MaxInt),'"','',[rfReplaceAll]); end
     else if T[0]='VERTEX' then begin
      V.Id:=I(T[1]); V.P:=V3(D(T[2]),D(T[3]),D(T[4])); n:=Length(M.Vertices); SetLength(M.Vertices,n+1); M.Vertices[n]:=V;
     end
     else if T[0]='CURVE' then begin
      C.Id:=I(T[1]);
      if T[2]='LINE' then begin C.Kind:=gckLine; C.P1:=V3(D(T[3]),D(T[4]),D(T[5])); C.P2:=V3(D(T[6]),D(T[7]),D(T[8])); end
      else if T[2]='CIRCLE' then begin C.Kind:=gckCircle; C.P1:=V3(D(T[3]),D(T[4]),D(T[5])); C.P2:=V3(D(T[6]),D(T[7]),D(T[8])); C.Radius:=D(T[9]); end
      else if T[2]='ARC3' then begin C.Kind:=gckArc3; C.P1:=V3(D(T[3]),D(T[4]),D(T[5])); C.P2:=V3(D(T[6]),D(T[7]),D(T[8])); C.P3:=V3(D(T[9]),D(T[10]),D(T[11])); end
      else raise Exception.Create('unsupported curve '+T[2]);
      n:=Length(M.Curves); SetLength(M.Curves,n+1); M.Curves[n]:=C;
     end
     else if T[0]='EDGE' then begin E.Id:=I(T[1]); E.StartVertex:=I(T[2]); E.EndVertex:=I(T[3]); E.CurveId:=I(T[4]); E.T0:=D(T[5]); E.T1:=D(T[6]); E.Sense:=I(T[7]); n:=Length(M.Edges); SetLength(M.Edges,n+1); M.Edges[n]:=E; end
     else if T[0]='LOOP' then begin LP.Id:=I(T[1]); SetLength(LP.EdgeIds,0); SetLength(LP.Senses,0); j:=2; while j<T.Count do begin if (j+2>=T.Count) or (T[j]<>'EDGE') then raise Exception.Create('expected EDGE in LOOP'); n:=Length(LP.EdgeIds); SetLength(LP.EdgeIds,n+1); SetLength(LP.Senses,n+1); LP.EdgeIds[n]:=I(T[j+1]); LP.Senses[n]:=I(T[j+2]); Inc(j,3); end; n:=Length(M.Loops); SetLength(M.Loops,n+1); M.Loops[n]:=LP; end
     else if T[0]='SURFACE' then begin SF.Id:=I(T[1]); if T[2]<>'PLANE' then raise Exception.Create('unsupported surface '+T[2]); SF.Kind:=gskPlane; SF.Origin:=V3(D(T[3]),D(T[4]),D(T[5])); SF.Normal:=V3(D(T[6]),D(T[7]),D(T[8])); n:=Length(M.Surfaces); SetLength(M.Surfaces,n+1); M.Surfaces[n]:=SF; end
     else if T[0]='FACE' then begin FC.Id:=I(T[1]); FC.SurfaceId:=I(T[2]); if T[3]<>'OUTER' then raise Exception.Create('FACE missing OUTER'); FC.OuterLoopId:=I(T[4]); FC.Orientation:=1; SetLength(FC.InnerLoopIds,0); j:=5; while j<T.Count do begin if T[j]='INNER' then begin n:=Length(FC.InnerLoopIds); SetLength(FC.InnerLoopIds,n+1); FC.InnerLoopIds[n]:=I(T[j+1]); Inc(j,2); end else Inc(j); end; n:=Length(M.Faces); SetLength(M.Faces,n+1); M.Faces[n]:=FC; end
     else if T[0]='BODY' then begin B.Id:=I(T[1]); SetLength(B.FaceIds,0); j:=2; while j<T.Count do begin if T[j]='FACE' then begin n:=Length(B.FaceIds); SetLength(B.FaceIds,n+1); B.FaceIds[n]:=I(T[j+1]); Inc(j,2); end else Inc(j); end; n:=Length(M.Bodies); SetLength(M.Bodies,n+1); M.Bodies[n]:=B; end
     else if T[0]='SET' then begin Z.Id:=I(T[1]); Z.Name:=StringReplace(T[2],'"','',[rfReplaceAll]); Z.EntityType:=UpperCase(T[3]); if T.Count>4 then begin SetLength(Z.EntityIds,T.Count-4); for j:=4 to T.Count-1 do Z.EntityIds[j-4]:=I(T[j]); end else SetLength(Z.EntityIds,0); n:=Length(M.Sets); SetLength(M.Sets,n+1); M.Sets[n]:=Z; end
     else if T[0]='META' then begin if T.Count<2 then raise Exception.Create('META missing key'); n:=Length(M.Meta); SetLength(M.Meta,n+1); M.Meta[n].Key:=T[1]; M.Meta[n].Value:=''; end
     else if (T[0]='INFO') or (T[0]='WARNING') or (T[0]='ERROR') then ;
    finally T.Free; end;
   end;
   Result:=True;
  except on X:Exception do begin Err:=Format('line %d: %s',[i+1,X.Message]); Result:=False; end; end;
 finally SS.Free; end;
end;
function SaveFGeoFile(const FN:string;M:TFEMGeometryModel;out Err:string):Boolean;var FS:TFileStream;begin Result:=False;Err:='';try FS:=TFileStream.Create(FN,fmCreate);try WriteFGeo(M,FS);Result:=True;finally FS.Free;end;except on X:Exception do Err:=X.Message;end;end;
function LoadFGeoFile(const FN:string;M:TFEMGeometryModel;out Err:string):Boolean;var FS:TFileStream;begin Result:=False;Err:='';try FS:=TFileStream.Create(FN,fmOpenRead or fmShareDenyWrite);try Result:=LoadFGeo(FS,M,Err);finally FS.Free;end;except on X:Exception do Err:=X.Message;end;end;
end.
