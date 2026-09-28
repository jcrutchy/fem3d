program dxf2femgeo;
{$mode objfpc}{$H+}
uses SysUtils, Classes, fem_geometry_types, fem_geometry_io;
function NextCode(L:TStringList; var I:Integer; out Code,Value:string):Boolean;
begin Result:=False;Code:='';Value:='';while I+1<L.Count do begin Code:=Trim(L[I]);Value:=Trim(L[I+1]);Inc(I,2);if Code<>'' then exit(True);end;end;
var FN,Err,C,V:string; InS:TFileStream; Lines:TStringList; I,J,VID,CID,EID:Integer; M:TFEMGeometryModel; P1,P2:TVector3;
procedure AddLine(const A,B:TVector3);begin Inc(VID,2);SetLength(M.Vertices,VID);M.Vertices[VID-2].Id:=VID-1;M.Vertices[VID-2].P:=A;M.Vertices[VID-1].Id:=VID;M.Vertices[VID-1].P:=B;Inc(CID);SetLength(M.Curves,CID);M.Curves[CID-1].Id:=CID;M.Curves[CID-1].Kind:=gckLine;M.Curves[CID-1].P1:=A;M.Curves[CID-1].P2:=V3(B.X-A.X,B.Y-A.Y,B.Z-A.Z);Inc(EID);SetLength(M.Edges,EID);M.Edges[EID-1].Id:=EID;M.Edges[EID-1].StartVertex:=VID-1;M.Edges[EID-1].EndVertex:=VID;M.Edges[EID-1].CurveId:=CID;M.Edges[EID-1].T0:=0;M.Edges[EID-1].T1:=1;M.Edges[EID-1].Sense:=1;end;
begin
 if ParamCount<1 then begin WriteLn(StdErr,'usage: dxf2femgeo input.dxf [output.fgeo]');Halt(2);end;
 FN:=ParamStr(1);M:=TFEMGeometryModel.Create;try M.SourceFormat:='DXF';M.SourceName:=ExtractFileName(FN);Lines:=TStringList.Create;InS:=TFileStream.Create(FN,fmOpenRead or fmShareDenyWrite);try Lines.LoadFromStream(InS);finally InS.Free;end;
 I:=0;while NextCode(Lines,I,C,V) do if (C='0') and (UpperCase(V)='LINE') then begin P1:=V3(0,0,0);P2:=P1;while (I+1<Lines.Count) and (Trim(Lines[I])<>'0') do begin C:=Trim(Lines[I]);V:=Trim(Lines[I+1]);Inc(I,2);if C='10' then P1.X:=StrToFloat(V) else if C='20' then P1.Y:=StrToFloat(V) else if C='30' then P1.Z:=StrToFloat(V) else if C='11' then P2.X:=StrToFloat(V) else if C='21' then P2.Y:=StrToFloat(V) else if C='31' then P2.Z:=StrToFloat(V);end;AddLine(P1,P2);end;
 Lines.Free;WriteLn(StdErr,'INFO DXF entities mapped: ',EID,' LINE edges; unsupported DXF entities are currently ignored by this foundation adaptor.');if ParamCount>1 then begin if not SaveFGeoFile(ParamStr(2),M,Err) then begin WriteLn(StdErr,'ERROR ',Err);Halt(2);end;end else WriteFGeo(M,Output);
 finally M.Free;end;
end.
