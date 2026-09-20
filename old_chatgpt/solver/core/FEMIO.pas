unit FEMIO;
{$mode objfpc}{$H+}

interface
uses Classes, SysUtils, Math, FEMTypes, FEMModel, FEMAnalysisCases;

type
  TFEMNativeIO = class
  public
    class procedure SaveModel(const M:TFEMModel; const FileName:string);
    class procedure LoadModel(const M:TFEMModel; const FileName:string);
  end;
  TGeometryImporter = class
  public
    class procedure ImportDXF(const M:TFEMModel; const FileName:string);
    class procedure ImportOBJ(const M:TFEMModel; const FileName:string);
    class procedure ImportIGES(const M:TFEMModel; const FileName:string);
  end;
implementation

class procedure TFEMNativeIO.SaveModel(const M:TFEMModel; const FileName:string);
var F:TextFile; I,J:Integer; S:string; L:TStringList;
begin
  AssignFile(F,FileName); Rewrite(F); L:=TStringList.Create;
  try
    Writeln(F,'FEM3D 0.7');
    for I:=0 to High(M.Materials) do Writeln(F,Format('MATERIAL %d "%s" %.17g %.17g %.17g',[M.Materials[I].ID,M.Materials[I].Name,M.Materials[I].E,M.Materials[I].Nu,M.Materials[I].Density]));
    for I:=0 to High(M.Sections) do Writeln(F,Format('SECTION %d "%s" %.17g %.17g %.17g %.17g',[M.Sections[I].ID,M.Sections[I].Name,M.Sections[I].Area,M.Sections[I].Iy,M.Sections[I].Iz,M.Sections[I].J]));
    for I:=0 to High(M.Groups) do Writeln(F,Format('GROUP %d "%s"',[M.Groups[I].ID,M.Groups[I].Name]));
    for I:=0 to High(M.LoadCases) do Writeln(F,Format('LOADCASE %d "%s"',[M.LoadCases[I].ID,M.LoadCases[I].Name]));
    for I:=0 to High(M.Nodes) do Writeln(F,Format('NODE %d %.17g %.17g %.17g %d %d %d %d %d %d',[M.Nodes[I].ID,M.Nodes[I].Position.X,M.Nodes[I].Position.Y,M.Nodes[I].Position.Z,Ord(M.Nodes[I].Restraint[0]),Ord(M.Nodes[I].Restraint[1]),Ord(M.Nodes[I].Restraint[2]),Ord(M.Nodes[I].Restraint[3]),Ord(M.Nodes[I].Restraint[4]),Ord(M.Nodes[I].Restraint[5])]));
    for I:=0 to High(M.Elements) do begin S:='ELEMENT '+IntToStr(M.Elements[I].ID)+' '+M.Elements[I].Kind+' '+IntToStr(M.Elements[I].MaterialID)+' '+IntToStr(M.Elements[I].SectionID)+' '+FloatToStr(M.Elements[I].Thickness)+' '+IntToStr(M.Elements[I].GroupID); for J:=0 to High(M.Elements[I].NodeIDs) do S:=S+' '+IntToStr(M.Elements[I].NodeIDs[J]); Writeln(F,S); end;
    for I:=0 to High(M.Loads) do Writeln(F,Format('LOAD %d %d %d %.17g %.17g %.17g %.17g %.17g %.17g',[M.Loads[I].ID,M.Loads[I].NodeID,M.Loads[I].LoadCaseID,M.Loads[I].Value[0],M.Loads[I].Value[1],M.Loads[I].Value[2],M.Loads[I].Value[3],M.Loads[I].Value[4],M.Loads[I].Value[5]]));
    for I:=0 to M.AnalysisCases.Count-1 do begin L.Clear; M.AnalysisCases.Item(I).WriteTo(L); Writeln(F,L.Text); end;
  finally L.Free; CloseFile(F); end;
end;

class procedure TFEMNativeIO.LoadModel(const M:TFEMModel; const FileName:string);
var F:TextFile; Line,Cmd,Section,Key,Val:string; P:TStringList; I,J,N,ID,LC:Integer; V:TDofVector; IDs:array of Integer; T:TAnalysisType; AC:TAnalysisCase; Vals:TStringList; Eq:Integer;
begin
  M.Clear; P:=TStringList.Create; P.Delimiter:=' '; P.StrictDelimiter:=True; Vals:=TStringList.Create; Vals.NameValueSeparator:='=';
  AssignFile(F,FileName); Reset(F);
  try
    AC:=nil; Section:='';
    while not Eof(F) do begin
      ReadLn(F,Line); Line:=Trim(Line); if Line='' then Continue;
      if (Copy(Line,1,1)='[') and (Copy(Line,Length(Line),1)=']') then begin
        Section:=Copy(Line,2,Length(Line)-2);
        if SameText(Section,'END_ANALYSIS_CASE') then begin AC:=nil; Section:=''; end
        else if Pos('ANALYSIS_CASE ',UpperCase(Section))=1 then begin ID:=StrToInt(Copy(Section,15,MaxInt)); AC:=M.AnalysisCases.AddWithID(ID,atLinearStatic,'Analysis '+IntToStr(ID)); end;
        Continue;
      end;
      if AC<>nil and SameText(Section,'SETTINGS') then begin
        I:=Pos('=',Line); if I>0 then begin Key:=Trim(Copy(Line,1,I-1)); Val:=Trim(Copy(Line,I+1,MaxInt)); if AC.Settings<>nil then AC.Settings.ReadFrom(Key,Val); end; Continue;
      end;
      if AC<>nil and Pos('ANALYSIS_CASE ',UpperCase(Section))=1 then begin
        I:=Pos('=',Line); if I>0 then begin Key:=Trim(Copy(Line,1,I-1)); Val:=Trim(Copy(Line,I+1,MaxInt));
          if SameText(Key,'Name') then AC.Name:=Val else if SameText(Key,'LoadCase') then AC.LoadCaseID:=StrToInt(Val) else if SameText(Key,'ResultID') then AC.ResultID:=Val
          else if SameText(Key,'Type') and StringToAnalysisType(Val,T) then begin
            if T<>AC.AnalysisType then begin
              if T=atLinearStatic then AC.SetSettings(TLinearStaticSettings.Create) else if T=atLinearBuckling then AC.SetSettings(TBucklingSettings.Create) else if T=atNonlinearStatic then AC.SetSettings(TNonlinearStaticSettings.Create) else AC.SetSettings(TGenericAnalysisSettings.Create(T));
            end;
          end;
        end; Continue;
      end;
      P.DelimitedText:=Line; if P.Count=0 then Continue; Cmd:=UpperCase(P[0]);
      if Cmd='NODE' then begin N:=M.AddNode(Vec3(StrToFloat(P[2]),StrToFloat(P[3]),StrToFloat(P[4]))); for J:=0 to 5 do M.Nodes[High(M.Nodes)].Restraint[J]:=StrToInt(P[5+J])<>0; M.Nodes[High(M.Nodes)].ID:=StrToInt(P[1]);
      end else if Cmd='MATERIAL' then begin ID:=M.AddMaterial(P[2],StrToFloat(P[3]),StrToFloat(P[4]),StrToFloat(P[5])); M.Materials[High(M.Materials)].ID:=StrToInt(P[1]);
      end else if Cmd='SECTION' then begin ID:=M.AddSection(P[2],StrToFloat(P[3]),StrToFloat(P[4]),StrToFloat(P[5]),StrToFloat(P[6])); M.Sections[High(M.Sections)].ID:=StrToInt(P[1]);
      end else if Cmd='GROUP' then begin ID:=M.AddGroup(P[2]); M.Groups[High(M.Groups)].ID:=StrToInt(P[1]);
      end else if Cmd='LOADCASE' then begin ID:=M.AddLoadCase(P[2]); M.LoadCases[High(M.LoadCases)].ID:=StrToInt(P[1]);
      end else if Cmd='LOAD' then begin for J:=0 to 5 do V[J]:=StrToFloat(P[4+J]); M.AddNodalLoad(StrToInt(P[2]),StrToInt(P[3]),V);
      end else if Cmd='ELEMENT' then begin N:=StrToInt(P[1]); SetLength(IDs,P.Count-7); for I:=0 to High(IDs) do IDs[I]:=StrToInt(P[7+I]); M.AddElement(P[2],IDs,StrToInt(P[3]),StrToInt(P[4]),StrToFloat(P[5]),0,StrToInt(P[6])); M.Elements[High(M.Elements)].ID:=N;
      end;
    end;
    M.RebuildIDCounters;
  finally CloseFile(F); P.Free; Vals.Free; end;
end;

class procedure TGeometryImporter.ImportDXF(const M:TFEMModel; const FileName:string);
var F:TextFile; Code:Integer; S,S2:string; X1,Y1,Z1,X2,Y2,Z2:Double; N1,N2,Mat,Sec:Integer;
begin Mat:=0; Sec:=0; AssignFile(F,FileName); Reset(F); try while not Eof(F) do begin ReadLn(F,S); if not TryStrToInt(Trim(S),Code) then Continue; if Eof(F) then Break; ReadLn(F,S2); if (Code=0) and SameText(Trim(S2),'POINT') then begin ReadLn(F,S);ReadLn(F,S2);X1:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);Y1:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);Z1:=StrToFloat(Trim(S2));M.AddNode(Vec3(X1,Y1,Z1)); end else if (Code=0) and SameText(Trim(S2),'LINE') then begin ReadLn(F,S);ReadLn(F,S2);X1:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);Y1:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);Z1:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);X2:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);Y2:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);Z2:=StrToFloat(Trim(S2));N1:=M.AddNode(Vec3(X1,Y1,Z1));N2:=M.AddNode(Vec3(X2,Y2,Z2));if Mat=0 then Mat:=M.AddMaterial('Imported',1,0.3,0);if Sec=0 then Sec:=M.AddSection('Imported',1,1,1,1);M.AddElement('BEAM3D',[N1,N2],Mat,Sec,0,0,0);end; end; finally CloseFile(F);end;end;
class procedure TGeometryImporter.ImportOBJ(const M:TFEMModel; const FileName:string);var F:TextFile;S:string;P:TStringList;X,Y,Z:Double;begin P:=TStringList.Create;P.Delimiter:=' ';P.StrictDelimiter:=True;AssignFile(F,FileName);Reset(F);try while not Eof(F) do begin ReadLn(F,S);S:=Trim(S);if (Length(S)>2) and (Copy(S,1,2)='v ') then begin P.DelimitedText:=S;if P.Count>=4 then begin X:=StrToFloat(P[1]);Y:=StrToFloat(P[2]);Z:=StrToFloat(P[3]);M.AddNode(Vec3(X,Y,Z));end;end;end;finally CloseFile(F);P.Free;end;end;
class procedure TGeometryImporter.ImportIGES(const M:TFEMModel; const FileName:string);var F:TextFile;S,T:string;X,Y,Z:Double;begin AssignFile(F,FileName);Reset(F);try while not Eof(F) do begin ReadLn(F,S);if Length(S)<72 then Continue;T:=Trim(Copy(S,73,8));if T='116' then begin X:=StrToFloatDef(Trim(Copy(S,10,8)),0);Y:=StrToFloatDef(Trim(Copy(S,18,8)),0);Z:=StrToFloatDef(Trim(Copy(S,26,8)),0);M.AddNode(Vec3(X,Y,Z));end;end;finally CloseFile(F);end;end;
end.
