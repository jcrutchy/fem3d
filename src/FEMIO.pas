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
      if (AC <> nil) and (Pos('ANALYSIS_CASE ',UpperCase(Section)) = 1) then begin
        I:=Pos('=',Line); if I>0 then begin Key:=Trim(Copy(Line,1,I-1)); Val:=Trim(Copy(Line,I+1,MaxInt)); if AC.Settings<>nil then AC.Settings.ReadFrom(Key,Val); end; Continue;
      end;
      if (AC<>nil) and (Pos('ANALYSIS_CASE ',UpperCase(Section))=1) then begin
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
type TPair=record Code:Integer; Value:string; end;
var
  F:TextFile; Lines:TStringList; I,J,Code:Integer; Ent:string;
  P:TStringList; X1,Y1,Z1,X2,Y2,Z2,Elev:Double;
  N1,N2,Mat,Sec:Integer; Layer:string;
  VX,VY,VZ:Double; LastNode:Integer;
  function NodeAt(const X,Y,Z,Tol:Double):Integer;
  var K:Integer; D2:Double;
  begin
    for K:=0 to High(M.Nodes) do begin
      D2:=Sqr(M.Nodes[K].Position.X-X)+Sqr(M.Nodes[K].Position.Y-Y)+Sqr(M.Nodes[K].Position.Z-Z);
      if D2<=Tol*Tol then Exit(M.Nodes[K].ID);
    end;
    Result:=M.AddNode(Vec3(X,Y,Z));
  end;
  function ValAt(const A:TStringList; C:Integer; const Default:string=''):string;
  var K:Integer;
  begin
    Result:=Default;
    for K:=0 to A.Count-1 do if StrToIntDef(A.Names[K],-99999)=C then Exit(A.ValueFromIndex[K]);
  end;
  procedure AddLine(const AX1,AY1,AZ1,AX2,AY2,AZ2:Double);
  begin
    N1:=NodeAt(AX1,AY1,AZ1,1E-8); N2:=NodeAt(AX2,AY2,AZ2,1E-8);
    if N1=N2 then Exit;
    if Mat=0 then Mat:=M.AddMaterial('Imported DXF',1.0,0.3,0.0);
    if Sec=0 then Sec:=M.AddSection('Imported DXF section',1.0,1.0,1.0,1.0);
    M.AddElement('BEAM3D',[N1,N2],Mat,Sec,0.0,0,0);
  end;
begin
  Lines:=TStringList.Create; P:=TStringList.Create; P.NameValueSeparator:='=';
  AssignFile(F,FileName); Reset(F);
  try
    while not Eof(F) do begin ReadLn(F,Ent); Lines.Add(Trim(Ent)); if Eof(F) then Break; ReadLn(F,Ent); Lines.Add(Trim(Ent)); end;
  finally CloseFile(F); end;
  try
    Mat:=0; Sec:=0; I:=0; LastNode:=-1; Layer:='';
    while I<Lines.Count-1 do begin
      Code:=StrToIntDef(Lines[I],-1);
      if (Code=0) and SameText(Lines[I+1],'ENDSEC') then Break;
      if (Code<>0) or not SameText(Lines[I+1],'ENTITIES') then begin Inc(I,2); Continue; end;
      Inc(I,2);
      while I<Lines.Count-1 do begin
        if (StrToIntDef(Lines[I],-1)=0) and SameText(Lines[I+1],'ENDSEC') then Break;
        if StrToIntDef(Lines[I],-1)<>0 then begin Inc(I,2); Continue; end;
        Ent:=UpperCase(Lines[I+1]); Inc(I,2); P.Clear;
        while I<Lines.Count-1 do begin
          Code:=StrToIntDef(Lines[I],-1); if Code=0 then Break;
          if P.Count=0 then P.Add(IntToStr(Code)+'='+Lines[I+1]) else P.Add(IntToStr(Code)+'='+Lines[I+1]); Inc(I,2);
        end;
        if Ent='LINE' then begin
          X1:=StrToFloatDef(ValAt(P,10,'0'),0); Y1:=StrToFloatDef(ValAt(P,20,'0'),0); Z1:=StrToFloatDef(ValAt(P,30,'0'),0);
          X2:=StrToFloatDef(ValAt(P,11,'0'),0); Y2:=StrToFloatDef(ValAt(P,21,'0'),0); Z2:=StrToFloatDef(ValAt(P,31,'0'),0); AddLine(X1,Y1,Z1,X2,Y2,Z2);
        end else if Ent='POINT' then begin
          X1:=StrToFloatDef(ValAt(P,10,'0'),0); Y1:=StrToFloatDef(ValAt(P,20,'0'),0); Z1:=StrToFloatDef(ValAt(P,30,'0'),0); NodeAt(X1,Y1,Z1,1E-8);
        end else if Ent='LWPOLYLINE' then begin
          Elev:=StrToFloatDef(ValAt(P,38,'0'),0); X1:=0;Y1:=0;Z1:=Elev; LastNode:=-1;
          for J:=0 to P.Count-1 do if StrToIntDef(P.Names[J],-1)=10 then begin
            X1:=StrToFloatDef(P.ValueFromIndex[J],0); Y1:=0; if (J+1<P.Count) and (StrToIntDef(P.Names[J+1],-1)=20) then Y1:=StrToFloatDef(P.ValueFromIndex[J+1],0);
            if LastNode<0 then LastNode:=NodeAt(X1,Y1,Z1,1E-8) else begin N2:=NodeAt(X1,Y1,Z1,1E-8); if N2<>LastNode then AddLine(M.Nodes[M.FindNode(LastNode)].Position.X,M.Nodes[M.FindNode(LastNode)].Position.Y,M.Nodes[M.FindNode(LastNode)].Position.Z,X1,Y1,Z1); LastNode:=N2; end;
          end;
        end;
        if (I<Lines.Count-1) and (StrToIntDef(Lines[I],-1)=0) then Continue;
      end;
      Break;
    end;
  finally Lines.Free; P.Free; end;
end;

class procedure TGeometryImporter.ImportOBJ(const M:TFEMModel; const FileName:string);
var F:TextFile;S:string;P:TStringList;X,Y,Z:Double;
begin P:=TStringList.Create;P.Delimiter:=' ';P.StrictDelimiter:=True;AssignFile(F,FileName);Reset(F);try while not Eof(F) do begin ReadLn(F,S);S:=Trim(S);if (Length(S)>2) and (Copy(S,1,2)='v ') then begin P.DelimitedText:=S;if P.Count>=4 then begin X:=StrToFloat(P[1]);Y:=StrToFloat(P[2]);Z:=StrToFloat(P[3]);M.AddNode(Vec3(X,Y,Z));end;end;end;finally CloseFile(F);P.Free;end;end;

class procedure TGeometryImporter.ImportIGES(const M:TFEMModel; const FileName:string);
var
  F:TextFile; S,Data,Tok:string; Section:string; I,K,Typ,Ptr,Seq:Integer;
  DMap,PMap:TStringList; Fields:TStringList;
  X1,Y1,Z1,X2,Y2,Z2:Double; N1,N2,Mat,Sec:Integer;
  function DField(const S:string; A,B:Integer):string;
  begin Result:=Trim(Copy(S,A,B)); end;
  function ParseReal(const S:string):Double;
  begin Result:=StrToFloatDef(Trim(S),0); end;
  function ParamData(const PointerID:Integer):string;
  var R,Posn:Integer; L:string;
  begin
    Result:='';
    Posn:=PMap.IndexOfName(IntToStr(PointerID));
    if Posn<0 then Exit;
    R:=Posn;
    while R<PMap.Count do begin
      L:=PMap.ValueFromIndex[R];
      if Result='' then Result:=L else Result:=Result+L;
      if Pos(';',L)>0 then Break;
      Inc(R);
    end;
  end;
  procedure AddLineFromParams(const S:string);
  var A:TStringList; J:Integer;
  begin
    A:=TStringList.Create; A.StrictDelimiter:=True; A.Delimiter:=',';
    try
      A.DelimitedText:=StringReplace(S,';',',',[rfReplaceAll]);
      if A.Count<7 then Exit;
      if StrToIntDef(Trim(A[0]),0)<>110 then Exit;
      { 110 line: entity type, x1,y1,z1,x2,y2,z2 }
      X1:=ParseReal(A[1]); Y1:=ParseReal(A[2]); Z1:=ParseReal(A[3]);
      X2:=ParseReal(A[4]); Y2:=ParseReal(A[5]); Z2:=ParseReal(A[6]);
      N1:=M.AddNode(Vec3(X1,Y1,Z1)); N2:=M.AddNode(Vec3(X2,Y2,Z2));
      if N1=N2 then Exit;
      if Mat=0 then Mat:=M.AddMaterial('Imported IGES',1.0,0.3,0.0);
      if Sec=0 then Sec:=M.AddSection('Imported IGES section',1.0,1.0,1.0,1.0);
      M.AddElement('BEAM3D',[N1,N2],Mat,Sec,0.0,0,0);
    finally A.Free; end;
  end;
begin
  { Conservative IGES wireframe importer. It follows the standard D/P section
    relationship and imports Type 110 lines. Curves/surfaces are not silently
    converted to FEM elements until a dedicated CAD-geometry layer exists. }
  DMap:=TStringList.Create; PMap:=TStringList.Create; Fields:=TStringList.Create;
  DMap.NameValueSeparator:='='; PMap.NameValueSeparator:='=';
  AssignFile(F,FileName); Reset(F);
  try
    Section:='';
    while not Eof(F) do begin
      ReadLn(F,S);
      if Length(S)<8 then Continue;
      Section:=UpperCase(Copy(S,73,1));
      if Section='D' then begin
        Typ:=StrToIntDef(DField(S,1,8),0); Ptr:=StrToIntDef(DField(S,9,8),0); Seq:=StrToIntDef(DField(S,73,8),0);
        if Typ<>0 then DMap.Add(IntToStr(Seq)+'='+IntToStr(Typ)+','+IntToStr(Ptr));
      end else if Section='P' then begin
        Seq:=StrToIntDef(DField(S,73,8),0);
        PMap.Add(IntToStr(Seq)+'='+Copy(S,1,64));
      end;
    end;
  finally CloseFile(F); end;
  try
    Mat:=0; Sec:=0;
    for I:=0 to DMap.Count-1 do begin
      Fields.Clear; Fields.Delimiter:=','; Fields.StrictDelimiter:=True; Fields.DelimitedText:=DMap.ValueFromIndex[I];
      if Fields.Count<2 then Continue;
      Typ:=StrToIntDef(Fields[0],0); Ptr:=StrToIntDef(Fields[1],0);
      if Typ=110 then begin Data:=ParamData(Ptr); if Data<>'' then AddLineFromParams(Data); end;
    end;
  finally DMap.Free; PMap.Free; Fields.Free; end;
end;
end.
