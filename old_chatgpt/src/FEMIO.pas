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
var
  F:TextFile;
  I,J:Integer;
  S:string;
  L:TStringList;
  OldDecimal,OldThousand:Char;
  Opened:Boolean;
  TempFile,BackupFile:string;
begin
  OldDecimal:=DecimalSeparator;
  OldThousand:=ThousandSeparator;
  DecimalSeparator:='.';
  ThousandSeparator:=',';
  TempFile:=FileName+'.tmp';
  BackupFile:=FileName+'.bak';
  Opened:=False;
  AssignFile(F,TempFile);
  L:=TStringList.Create;
  try
    try
      Rewrite(F);
      Opened:=True;
      Writeln(F,'FEM3D 0.7');
      for I:=0 to High(M.Materials) do Writeln(F,Format('MATERIAL %d "%s" %.17g %.17g %.17g',[M.Materials[I].ID,M.Materials[I].Name,M.Materials[I].E,M.Materials[I].Nu,M.Materials[I].Density]));
      for I:=0 to High(M.Sections) do Writeln(F,Format('SECTION %d "%s" %.17g %.17g %.17g %.17g',[M.Sections[I].ID,M.Sections[I].Name,M.Sections[I].Area,M.Sections[I].Iy,M.Sections[I].Iz,M.Sections[I].J]));
      for I:=0 to High(M.Groups) do Writeln(F,Format('GROUP %d "%s"',[M.Groups[I].ID,M.Groups[I].Name]));
      for I:=0 to High(M.LoadCases) do Writeln(F,Format('LOADCASE %d "%s"',[M.LoadCases[I].ID,M.LoadCases[I].Name]));
      for I:=0 to High(M.Nodes) do Writeln(F,Format('NODE %d %.17g %.17g %.17g %d %d %d %d %d %d',[M.Nodes[I].ID,M.Nodes[I].Position.X,M.Nodes[I].Position.Y,M.Nodes[I].Position.Z,Ord(M.Nodes[I].Restraint[0]),Ord(M.Nodes[I].Restraint[1]),Ord(M.Nodes[I].Restraint[2]),Ord(M.Nodes[I].Restraint[3]),Ord(M.Nodes[I].Restraint[4]),Ord(M.Nodes[I].Restraint[5])]));
      for I:=0 to High(M.Elements) do begin S:='ELEMENT '+IntToStr(M.Elements[I].ID)+' '+M.Elements[I].Kind+' '+IntToStr(M.Elements[I].MaterialID)+' '+IntToStr(M.Elements[I].SectionID)+' '+FloatToStr(M.Elements[I].Thickness)+' '+IntToStr(M.Elements[I].GroupID); for J:=0 to High(M.Elements[I].NodeIDs) do S:=S+' '+IntToStr(M.Elements[I].NodeIDs[J]); Writeln(F,S); end;
      for I:=0 to High(M.Loads) do Writeln(F,Format('LOAD %d %d %d %.17g %.17g %.17g %.17g %.17g %.17g',[M.Loads[I].ID,M.Loads[I].NodeID,M.Loads[I].LoadCaseID,M.Loads[I].Value[0],M.Loads[I].Value[1],M.Loads[I].Value[2],M.Loads[I].Value[3],M.Loads[I].Value[4],M.Loads[I].Value[5]]));
      for I:=0 to M.AnalysisCases.Count-1 do begin L.Clear; M.AnalysisCases.Item(I).WriteTo(L); Writeln(F,L.Text); end;
      CloseFile(F);
      Opened:=False;
      if FileExists(FileName) then begin
        if FileExists(BackupFile) and not DeleteFile(BackupFile) then raise Exception.Create('Unable to prepare model backup file: '+BackupFile);
        if not RenameFile(FileName,BackupFile) then raise Exception.Create('Unable to protect existing model file before replacement: '+FileName);
      end;
      if not RenameFile(TempFile,FileName) then begin
        if FileExists(BackupFile) then RenameFile(BackupFile,FileName);
        raise Exception.Create('Unable to publish model file: '+FileName);
      end;
      if FileExists(BackupFile) then DeleteFile(BackupFile);
    except
      on E:Exception do begin
        if Opened then CloseFile(F);
        if FileExists(TempFile) then DeleteFile(TempFile);
        raise Exception.CreateFmt('Unable to save FEM3D model "%s": %s',[FileName,E.Message]);
      end;
    end;
  finally
    L.Free;
    DecimalSeparator:=OldDecimal;
    ThousandSeparator:=OldThousand;
  end;
end;

class procedure TFEMNativeIO.LoadModel(const M:TFEMModel; const FileName:string);
var
  F:TextFile;
  Line,Cmd,Section,Key,Val:string;
  P:TStringList;
  I,J,N,ID,LineNo:Integer;
  V:TDofVector;
  IDs:array of Integer;
  D:Double;
  T:TAnalysisType;
  Pending:TStringList;
  PendingID:Integer;
  InAnalysis:Boolean;
  HeaderSeen:Boolean;
  FS:TFormatSettings;
  Opened:Boolean;

  procedure Fail(const Msg:string);
  begin
    raise Exception.CreateFmt('Model parse error at line %d: %s',[LineNo,Msg]);
  end;

  function ParseInt(const S,What:string):Integer;
  begin
    if not TryStrToInt(Trim(S),Result) then Fail('invalid integer for '+What+': "'+S+'"');
  end;

  function ParseFloat(const S,What:string):Double;
  begin
    if not TryStrToFloat(Trim(S),Result,FS) then Fail('invalid number for '+What+': "'+S+'"');
    if IsNan(Result) or IsInfinite(Result) then Fail('non-finite number for '+What+': "'+S+'"');
  end;

  procedure RequireCount(Actual,Minimum:Integer; const What:string);
  begin
    if Actual<Minimum then Fail(Format('%s requires at least %d fields, found %d',[What,Minimum,Actual]));
  end;

  procedure FinishAnalysis;
  var
    A:TAnalysisCase;
    SName,SType,SLC,SResult:string;
    K:Integer;
  begin
    if not InAnalysis then Exit;
    if PendingID<=0 then Fail('analysis case ID must be positive');
    if M.AnalysisCases.Find(PendingID)<>nil then Fail(Format('duplicate analysis case ID %d',[PendingID]));
    SType:=Pending.Values['__TYPE__'];
    if SType='' then Fail('analysis case is missing Type');
    if not StringToAnalysisType(SType,T) then Fail('unknown analysis Type "'+SType+'"');
    SName:=Pending.Values['__NAME__'];
    if SName='' then SName:='Analysis '+IntToStr(PendingID);
    A:=M.AnalysisCases.AddWithID(PendingID,T,SName);
    SLC:=Pending.Values['__LOADCASE__'];
    if SLC<>'' then A.LoadCaseID:=ParseInt(SLC,'analysis LoadCase');
    SResult:=Pending.Values['__RESULTID__'];
    if SResult<>'' then A.ResultID:=SResult;
    for K:=0 to Pending.Count-1 do
      if (Pos('__',Pending.Names[K])<>1) then begin
        if (T=atLinearStatic) and
           not (SameText(Pending.Names[K],'Solver') or SameText(Pending.Names[K],'MatrixStorage') or
                SameText(Pending.Names[K],'PivotTolerance') or SameText(Pending.Names[K],'ResidualTolerance') or
                SameText(Pending.Names[K],'Tolerance') or SameText(Pending.Names[K],'CheckEquilibrium') or
                SameText(Pending.Names[K],'CheckEnergy') or SameText(Pending.Names[K],'RecoverElementForces') or
                SameText(Pending.Names[K],'StoreSolverData')) then
          Fail('unknown linear-static setting "'+Pending.Names[K]+'"');
        A.Settings.ReadFrom(Pending.Names[K],Pending.ValueFromIndex[K]);
      end;
    InAnalysis:=False;
    Pending.Clear;
  end;

begin
  if not FileExists(FileName) then raise Exception.Create('Model file does not exist: '+FileName);
  M.Clear;
  FS:=DefaultFormatSettings;
  FS.DecimalSeparator:='.';
  FS.ThousandSeparator:=',';
  P:=TStringList.Create;
  Pending:=TStringList.Create;
  P.Delimiter:=' ';
  P.StrictDelimiter:=True;
  P.QuoteChar:='"';
  HeaderSeen:=False;
  InAnalysis:=False;
  PendingID:=0;
  Section:='';
  LineNo:=0;
  Opened:=False;
  AssignFile(F,FileName);
  try
    try
      Reset(F);
      Opened:=True;
    except
      on E:Exception do raise Exception.CreateFmt('Unable to open model file "%s": %s',[FileName,E.Message]);
    end;
    try
      while not Eof(F) do begin
        Inc(LineNo);
        ReadLn(F,Line);
        Line:=Trim(Line);
        if Line='' then Continue;
        if (Line[1]=';') or (Line[1]='#') then Continue;

        if not HeaderSeen then begin
          HeaderSeen:=True;
          P.DelimitedText:=Line;
          if (P.Count<>2) or not SameText(P[0],'FEM3D') then
            Fail('invalid FEM3D model header. Expected "FEM3D <version>".');
          if not TryStrToFloat(P[1],D,FS) then
            Fail('invalid FEM3D format version "'+P[1]+'"');
          if D<=0 then Fail('FEM3D format version must be positive');
          Continue;
        end;

        if (Line[1]='[') and (Line[Length(Line)]=']') then begin
          Section:=Trim(Copy(Line,2,Length(Line)-2));
          if SameText(Section,'END_ANALYSIS_CASE') then begin
            if not InAnalysis then Fail('END_ANALYSIS_CASE without an open analysis case');
            FinishAnalysis;
            Section:='';
          end else if Pos('ANALYSIS_CASE ',UpperCase(Section))=1 then begin
            if InAnalysis then Fail('nested analysis case is not permitted');
            Pending.Clear;
            PendingID:=ParseInt(Trim(Copy(Section,15,MaxInt)),'analysis case ID');
            InAnalysis:=True;
            Section:='ANALYSIS_CASE';
          end else if SameText(Section,'SETTINGS') then begin
            if not InAnalysis then Fail('[SETTINGS] requires an open analysis case');
            Section:='SETTINGS';
          end else begin
            Fail('unknown section ['+Section+']');
          end;
          Continue;
        end;

        if InAnalysis then begin
          I:=Pos('=',Line);
          if I<=0 then Fail('analysis case line must be Key=Value');
          Key:=Trim(Copy(Line,1,I-1));
          Val:=Trim(Copy(Line,I+1,MaxInt));
          if (Key='') then Fail('analysis case key is empty');
          if Pending.IndexOfName(Key)>=0 then Fail('duplicate analysis-case key "'+Key+'"');
          if SameText(Key,'Name') then Pending.Values['__NAME__']:=Val
          else if SameText(Key,'Type') then Pending.Values['__TYPE__']:=Val
          else if SameText(Key,'LoadCase') then begin ParseInt(Val,'analysis LoadCase'); Pending.Values['__LOADCASE__']:=Val; end
          else if SameText(Key,'ResultID') then Pending.Values['__RESULTID__']:=Val
          else if SameText(Section,'SETTINGS') then Pending.Values[Key]:=Val
          else Fail('unknown analysis-case key "'+Key+'"');
          Continue;
        end;

        P.DelimitedText:=Line;
        if P.Count=0 then Continue;
        Cmd:=UpperCase(P[0]);
        if Cmd='FEM3D' then Fail('FEM3D header may only appear as the first non-comment line')
        else if Cmd='NODE' then begin
          RequireCount(P.Count,11,'NODE');
          ID:=ParseInt(P[1],'node ID');
          if ID<=0 then Fail('node ID must be positive');
          if M.FindNode(ID)>=0 then Fail(Format('duplicate node ID %d',[ID]));
          N:=M.AddNode(Vec3(ParseFloat(P[2],'node X'),ParseFloat(P[3],'node Y'),ParseFloat(P[4],'node Z')));
          M.Nodes[High(M.Nodes)].ID:=ID;
          for J:=0 to 5 do begin
            I:=ParseInt(P[5+J],Format('node restraint %d',[J]));
            if (I<>0) and (I<>1) then Fail('node restraint values must be 0 or 1');
            M.Nodes[High(M.Nodes)].Restraint[J]:=I<>0;
          end;
        end
        else if Cmd='MATERIAL' then begin
          RequireCount(P.Count,6,'MATERIAL');
          ID:=ParseInt(P[1],'material ID');
          if ID<=0 then Fail('material ID must be positive');
          if M.FindMaterial(ID)>=0 then Fail(Format('duplicate material ID %d',[ID]));
          N:=M.AddMaterial(P[2],ParseFloat(P[3],'material E'),ParseFloat(P[4],'material Nu'),ParseFloat(P[5],'material density'));
          M.Materials[High(M.Materials)].ID:=ID;
        end
        else if Cmd='SECTION' then begin
          RequireCount(P.Count,7,'SECTION');
          ID:=ParseInt(P[1],'section ID');
          if ID<=0 then Fail('section ID must be positive');
          if M.FindSection(ID)>=0 then Fail(Format('duplicate section ID %d',[ID]));
          N:=M.AddSection(P[2],ParseFloat(P[3],'section area'),ParseFloat(P[4],'section Iy'),ParseFloat(P[5],'section Iz'),ParseFloat(P[6],'section J'));
          M.Sections[High(M.Sections)].ID:=ID;
        end
        else if Cmd='GROUP' then begin
          RequireCount(P.Count,3,'GROUP');
          ID:=ParseInt(P[1],'group ID');
          if ID<=0 then Fail('group ID must be positive');
          if M.FindGroup(ID)>=0 then Fail(Format('duplicate group ID %d',[ID]));
          N:=M.AddGroup(P[2]); M.Groups[High(M.Groups)].ID:=ID;
        end
        else if Cmd='LOADCASE' then begin
          RequireCount(P.Count,3,'LOADCASE');
          ID:=ParseInt(P[1],'load case ID');
          if ID<=0 then Fail('load case ID must be positive');
          if M.FindLoadCase(ID)>=0 then Fail(Format('duplicate load case ID %d',[ID]));
          N:=M.AddLoadCase(P[2]); M.LoadCases[High(M.LoadCases)].ID:=ID;
        end
        else if Cmd='LOAD' then begin
          RequireCount(P.Count,10,'LOAD');
          ID:=ParseInt(P[1],'load ID');
          if ID<=0 then Fail('load ID must be positive');
          for J:=0 to 5 do V[J]:=ParseFloat(P[4+J],Format('load DOF %d',[J]));
          for J:=0 to High(M.Loads) do if M.Loads[J].ID=ID then Fail(Format('duplicate load ID %d',[ID]));
          M.AddNodalLoad(ParseInt(P[2],'load node ID'),ParseInt(P[3],'load case ID'),V);
          M.Loads[High(M.Loads)].ID:=ID;
        end
        else if Cmd='ELEMENT' then begin
          RequireCount(P.Count,8,'ELEMENT');
          ID:=ParseInt(P[1],'element ID');
          if ID<=0 then Fail('element ID must be positive');
          for J:=0 to High(M.Elements) do if M.Elements[J].ID=ID then Fail(Format('duplicate element ID %d',[ID]));
          N:=ParseInt(P[3],'element material ID');
          J:=ParseInt(P[4],'element section ID');
          SetLength(IDs,P.Count-7);
          for I:=0 to High(IDs) do IDs[I]:=ParseInt(P[7+I],Format('element node %d',[I+1]));
          M.AddElement(P[2],IDs,N,J,ParseFloat(P[5],'element thickness'),0,ParseInt(P[6],'element group ID'));
          M.Elements[High(M.Elements)].ID:=ID;
        end
        else Fail('unknown model record "'+P[0]+'"');
      end;
      if not HeaderSeen then raise Exception.Create('Model parse error: model file is empty; FEM3D header is required.');
      if InAnalysis then Fail('unterminated analysis case; expected [END_ANALYSIS_CASE]');
    except
      on E:Exception do begin
        if Pos('Model parse error',E.Message)=1 then raise;
        raise Exception.CreateFmt('Model parse error at line %d: %s',[LineNo,E.Message]);
      end;
    end;
  finally
    if Opened then CloseFile(F);
    Pending.Free;
    P.Free;
  end;
end;

class procedure TGeometryImporter.ImportDXF(const M:TFEMModel; const FileName:string);
var F:TextFile; Code:Integer; S,S2:string; X1,Y1,Z1,X2,Y2,Z2:Double; N1,N2,Mat,Sec:Integer;
begin Mat:=0; Sec:=0; AssignFile(F,FileName); Reset(F); try while not Eof(F) do begin ReadLn(F,S); if not TryStrToInt(Trim(S),Code) then Continue; if Eof(F) then Break; ReadLn(F,S2); if (Code=0) and SameText(Trim(S2),'POINT') then begin ReadLn(F,S);ReadLn(F,S2);X1:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);Y1:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);Z1:=StrToFloat(Trim(S2));M.AddNode(Vec3(X1,Y1,Z1)); end else if (Code=0) and SameText(Trim(S2),'LINE') then begin ReadLn(F,S);ReadLn(F,S2);X1:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);Y1:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);Z1:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);X2:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);Y2:=StrToFloat(Trim(S2));ReadLn(F,S);ReadLn(F,S2);Z2:=StrToFloat(Trim(S2));N1:=M.AddNode(Vec3(X1,Y1,Z1));N2:=M.AddNode(Vec3(X2,Y2,Z2));if Mat=0 then Mat:=M.AddMaterial('Imported',1,0.3,0);if Sec=0 then Sec:=M.AddSection('Imported',1,1,1,1);M.AddElement('BEAM3D',[N1,N2],Mat,Sec,0,0,0);end; end; finally CloseFile(F);end;end;
class procedure TGeometryImporter.ImportOBJ(const M:TFEMModel; const FileName:string);var F:TextFile;S:string;P:TStringList;X,Y,Z:Double;begin P:=TStringList.Create;P.Delimiter:=' ';P.StrictDelimiter:=True;AssignFile(F,FileName);Reset(F);try while not Eof(F) do begin ReadLn(F,S);S:=Trim(S);if (Length(S)>2) and (Copy(S,1,2)='v ') then begin P.DelimitedText:=S;if P.Count>=4 then begin X:=StrToFloat(P[1]);Y:=StrToFloat(P[2]);Z:=StrToFloat(P[3]);M.AddNode(Vec3(X,Y,Z));end;end;end;finally CloseFile(F);P.Free;end;end;
class procedure TGeometryImporter.ImportIGES(const M:TFEMModel; const FileName:string);var F:TextFile;S,T:string;X,Y,Z:Double;begin AssignFile(F,FileName);Reset(F);try while not Eof(F) do begin ReadLn(F,S);if Length(S)<72 then Continue;T:=Trim(Copy(S,73,8));if T='116' then begin X:=StrToFloatDef(Trim(Copy(S,10,8)),0);Y:=StrToFloatDef(Trim(Copy(S,18,8)),0);Z:=StrToFloatDef(Trim(Copy(S,26,8)),0);M.AddNode(Vec3(X,Y,Z));end;end;finally CloseFile(F);end;end;
end.
