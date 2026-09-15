unit FEMHash;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, FEMModel, FEMAnalysisCases;
function ModelFingerprint(const M:TFEMModel):string;
function AnalysisFingerprint(const A:TAnalysisCase):string;
implementation
function FNV1a64(const S:string):QWord;
var I:Integer;
begin Result:=QWord($CBF29CE484222325); for I:=1 to Length(S) do begin Result:=Result xor Ord(S[I]); Result:=Result*QWord($100000001B3); end; end;
function CanonicalModel(const M:TFEMModel):string;
var I,J:Integer; S:string;
begin S:='FEM3D-FINGERPRINT-1'; for I:=0 to High(M.Nodes) do begin S+=Format('|N%d|%.17g|%.17g|%.17g',[M.Nodes[I].ID,M.Nodes[I].Position.X,M.Nodes[I].Position.Y,M.Nodes[I].Position.Z]); for J:=0 to 5 do if M.Nodes[I].Restraint[J] then S+='|R'+IntToStr(J)+'=1'; end;
for I:=0 to High(M.Materials) do S+=Format('|M%d|%s|%.17g|%.17g|%.17g',[M.Materials[I].ID,M.Materials[I].Name,M.Materials[I].E,M.Materials[I].Nu,M.Materials[I].Density]);
for I:=0 to High(M.Sections) do S+=Format('|S%d|%s|%.17g|%.17g|%.17g|%.17g',[M.Sections[I].ID,M.Sections[I].Name,M.Sections[I].Area,M.Sections[I].Iy,M.Sections[I].Iz,M.Sections[I].J]);
for I:=0 to High(M.LoadCases) do S+=Format('|LC%d|%s',[M.LoadCases[I].ID,M.LoadCases[I].Name]);
for I:=0 to High(M.Groups) do S+=Format('|G%d|%s',[M.Groups[I].ID,M.Groups[I].Name]);
for I:=0 to High(M.CoordinateSystems) do S+=Format('|CS%d|%s|%.17g|%.17g|%.17g|%.17g|%.17g|%.17g|%.17g|%.17g|%.17g|%.17g|%.17g',[M.CoordinateSystems[I].ID,M.CoordinateSystems[I].Name,M.CoordinateSystems[I].Origin.X,M.CoordinateSystems[I].Origin.Y,M.CoordinateSystems[I].Origin.Z,M.CoordinateSystems[I].XAxis.X,M.CoordinateSystems[I].XAxis.Y,M.CoordinateSystems[I].XAxis.Z,M.CoordinateSystems[I].YAxis.X,M.CoordinateSystems[I].YAxis.Y,M.CoordinateSystems[I].YAxis.Z,M.CoordinateSystems[I].ZAxis.X,M.CoordinateSystems[I].ZAxis.Y,M.CoordinateSystems[I].ZAxis.Z]);
for I:=0 to High(M.Combinations) do begin S+=Format('|C%d|%s',[M.Combinations[I].ID,M.Combinations[I].Name]); for J:=0 to High(M.Combinations[I].Terms) do S+=Format('|%d|%.17g',[M.Combinations[I].Terms[J].LoadCaseID,M.Combinations[I].Terms[J].Factor]); end;
for I:=0 to High(M.Elements) do begin S+=Format('|E%d|%s|%d|%d|%.17g|%d',[M.Elements[I].ID,M.Elements[I].Kind,M.Elements[I].MaterialID,M.Elements[I].SectionID,M.Elements[I].Thickness,M.Elements[I].CoordinateSystemID,M.Elements[I].GroupID]); for J:=0 to High(M.Elements[I].NodeIDs) do S+='|'+IntToStr(M.Elements[I].NodeIDs[J]); end;
for I:=0 to High(M.Loads) do begin S+=Format('|L%d|%d|%d',[M.Loads[I].ID,M.Loads[I].NodeID,M.Loads[I].LoadCaseID]); for J:=0 to 5 do S+=Format('|%.17g',[M.Loads[I].Value[J]]); end; Result:=S; end;
function ModelFingerprint(const M:TFEMModel):string; begin Result:=IntToHex(FNV1a64(CanonicalModel(M)),16); end;
function AnalysisFingerprint(const A:TAnalysisCase):string; var L:TStringList; S:string; begin L:=TStringList.Create; try A.WriteTo(L); S:='FEM3D-ANALYSIS-FINGERPRINT-1|'+L.Text; Result:=IntToHex(FNV1a64(S),16); finally L.Free end; end;
end.

