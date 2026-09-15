unit FEMModel;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, FEMTypes, FEMAnalysisCases;

type
  TFEMModel = class;

  TNode = record
    ID: Integer;
    Position: TVec3;
    Restraint: TDofMask;
  end;

  TMaterial = record
    ID: Integer;
    Name: string;
    E, Nu, Density: Double;
  end;

  TBeamSection = record
    ID: Integer;
    Name: string;
    Area, Iy, Iz, J: Double;
  end;

  TLoadCase = record
    ID: Integer;
    Name: string;
  end;

  TLoadCombinationTerm = record
    LoadCaseID: Integer;
    Factor: Double;
  end;

  TLoadCombination = record
    ID: Integer;
    Name: string;
    Terms: array of TLoadCombinationTerm;
  end;

  TNodalLoad = record
    ID: Integer;
    NodeID: Integer;
    LoadCaseID: Integer;
    Value: TDofVector;
  end;

  TCoordinateSystem = record
    ID: Integer;
    Name: string;
    Origin: TVec3;
    XAxis, YAxis, ZAxis: TVec3;
  end;

  TElementRecord = record
    ID: Integer;
    Kind: string;
    NodeIDs: array of Integer;
    MaterialID: Integer;
    SectionID: Integer;
    Thickness: Double;
    CoordinateSystemID: Integer;
    GroupID: Integer;
  end;

  TGroup = record
    ID: Integer;
    Name: string;
  end;

  TDOFNumbering = class
  private
    FNodeIDs:array of Integer;
    FBase:array of Integer;
  public
    constructor Create(const M:TFEMModel);
    function NodeEquation(NodeID:Integer):Integer;
    function DOF(NodeID,LocalDOF:Integer):Integer;
    function Count:Integer;
  end;

  TFEMModel = class
  private
    FNextNodeID, FNextElementID, FNextMaterialID, FNextSectionID: Integer;
    FNextLoadCaseID, FNextLoadID, FNextGroupID, FNextCSID, FNextComboID: Integer;
  public
    Nodes: array of TNode;
    Materials: array of TMaterial;
    Sections: array of TBeamSection;
    LoadCases: array of TLoadCase;
    Combinations: array of TLoadCombination;
    Loads: array of TNodalLoad;
    Elements: array of TElementRecord;
    Groups: array of TGroup;
    CoordinateSystems: array of TCoordinateSystem;
    AnalysisCases: TAnalysisCaseCollection;

    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure RebuildIDCounters;

    function AddNode(const P:TVec3):Integer;
    function AddMaterial(const Name:string; E,Nu,Density:Double):Integer;
    function AddSection(const Name:string; A,Iy,Iz,J:Double):Integer;
    function AddLoadCase(const Name:string):Integer;
    function AddCombination(const Name:string):Integer;
    procedure AddCombinationTerm(CombinationID,LoadCaseID:Integer; Factor:Double);
    function AddNodalLoad(NodeID,LoadCaseID:Integer; const V:TDofVector):Integer;
    function AddGroup(const Name:string):Integer;
    function AddCoordinateSystem(const Name:string; const Origin,XAxis,YAxis,ZAxis:TVec3):Integer;
    function AddElement(const Kind:string; const NodeIDs:array of Integer;
      MaterialID,SectionID:Integer; Thickness:Double; CoordinateSystemID,GroupID:Integer):Integer;

    function FindNode(ID:Integer):Integer;
    function FindMaterial(ID:Integer):Integer;
    function FindSection(ID:Integer):Integer;
    function FindLoadCase(ID:Integer):Integer;
    function FindCombination(ID:Integer):Integer;
    function FindGroup(ID:Integer):Integer;

    function TotalDOF:Integer;
    function CreateDOFNumbering:TDOFNumbering;
    function Validate(out Errors:TStringList):Boolean;
  end;

implementation

constructor TDOFNumbering.Create(const M:TFEMModel);
var I:Integer;
begin
  inherited Create;
  SetLength(FNodeIDs,Length(M.Nodes)); SetLength(FBase,Length(M.Nodes));
  for I:=0 to High(M.Nodes) do begin FNodeIDs[I]:=M.Nodes[I].ID; FBase[I]:=I*6; end;
end;

function TDOFNumbering.NodeEquation(NodeID:Integer):Integer;
var I:Integer;
begin Result:=-1; for I:=0 to High(FNodeIDs) do if FNodeIDs[I]=NodeID then Exit(FBase[I]); end;

function TDOFNumbering.DOF(NodeID,LocalDOF:Integer):Integer;
var B:Integer;
begin B:=NodeEquation(NodeID); if (B<0) or (LocalDOF<0) or (LocalDOF>5) then Result:=-1 else Result:=B+LocalDOF; end;
function TDOFNumbering.Count:Integer; begin Result:=Length(FNodeIDs)*6; end;

constructor TFEMModel.Create;
begin inherited Create; AnalysisCases:=TAnalysisCaseCollection.Create; Clear; end;

destructor TFEMModel.Destroy;
begin AnalysisCases.Free; inherited Destroy; end;


procedure TFEMModel.Clear;
begin
  SetLength(Nodes,0); SetLength(Materials,0); SetLength(Sections,0);
  SetLength(LoadCases,0); SetLength(Combinations,0); SetLength(Loads,0);
  SetLength(Elements,0); SetLength(Groups,0); SetLength(CoordinateSystems,0);
  AnalysisCases.Clear;
  FNextNodeID:=1; FNextElementID:=1; FNextMaterialID:=1; FNextSectionID:=1;
  FNextLoadCaseID:=1; FNextLoadID:=1; FNextGroupID:=1; FNextCSID:=1; FNextComboID:=1;
end;

procedure TFEMModel.RebuildIDCounters;
var I:Integer;
begin
  FNextNodeID:=1; for I:=0 to High(Nodes) do if Nodes[I].ID>=FNextNodeID then FNextNodeID:=Nodes[I].ID+1;
  FNextElementID:=1; for I:=0 to High(Elements) do if Elements[I].ID>=FNextElementID then FNextElementID:=Elements[I].ID+1;
  FNextMaterialID:=1; for I:=0 to High(Materials) do if Materials[I].ID>=FNextMaterialID then FNextMaterialID:=Materials[I].ID+1;
  FNextSectionID:=1; for I:=0 to High(Sections) do if Sections[I].ID>=FNextSectionID then FNextSectionID:=Sections[I].ID+1;
  FNextLoadCaseID:=1; for I:=0 to High(LoadCases) do if LoadCases[I].ID>=FNextLoadCaseID then FNextLoadCaseID:=LoadCases[I].ID+1;
  FNextLoadID:=1; for I:=0 to High(Loads) do if Loads[I].ID>=FNextLoadID then FNextLoadID:=Loads[I].ID+1;
  FNextGroupID:=1; for I:=0 to High(Groups) do if Groups[I].ID>=FNextGroupID then FNextGroupID:=Groups[I].ID+1;
  FNextCSID:=1; for I:=0 to High(CoordinateSystems) do if CoordinateSystems[I].ID>=FNextCSID then FNextCSID:=CoordinateSystems[I].ID+1;
  FNextComboID:=1; for I:=0 to High(Combinations) do if Combinations[I].ID>=FNextComboID then FNextComboID:=Combinations[I].ID+1;
end;

function TFEMModel.AddNode(const P:TVec3):Integer;
var I:Integer;
begin
  I:=Length(Nodes); SetLength(Nodes,I+1);
  Nodes[I].ID:=FNextNodeID; Inc(FNextNodeID); Nodes[I].Position:=P;
  FillChar(Nodes[I].Restraint,SizeOf(TDofMask),0); Result:=Nodes[I].ID;
end;

function TFEMModel.AddMaterial(const Name:string; E,Nu,Density:Double):Integer;
var I:Integer;
begin
  I:=Length(Materials); SetLength(Materials,I+1); Materials[I].ID:=FNextMaterialID; Inc(FNextMaterialID);
  Materials[I].Name:=Name; Materials[I].E:=E; Materials[I].Nu:=Nu; Materials[I].Density:=Density;
  Result:=Materials[I].ID;
end;

function TFEMModel.AddSection(const Name:string; A,Iy,Iz,J:Double):Integer;
var I:Integer;
begin
  I:=Length(Sections); SetLength(Sections,I+1); Sections[I].ID:=FNextSectionID; Inc(FNextSectionID);
  Sections[I].Name:=Name; Sections[I].Area:=A; Sections[I].Iy:=Iy; Sections[I].Iz:=Iz; Sections[I].J:=J;
  Result:=Sections[I].ID;
end;

function TFEMModel.AddLoadCase(const Name:string):Integer;
var I:Integer;
begin
  I:=Length(LoadCases); SetLength(LoadCases,I+1); LoadCases[I].ID:=FNextLoadCaseID; Inc(FNextLoadCaseID);
  LoadCases[I].Name:=Name; Result:=LoadCases[I].ID;
end;

function TFEMModel.AddCombination(const Name:string):Integer;
var I:Integer;
begin
  I:=Length(Combinations); SetLength(Combinations,I+1); Combinations[I].ID:=FNextComboID; Inc(FNextComboID);
  Combinations[I].Name:=Name; SetLength(Combinations[I].Terms,0); Result:=Combinations[I].ID;
end;

procedure TFEMModel.AddCombinationTerm(CombinationID,LoadCaseID:Integer; Factor:Double);
var I,J:Integer;
begin
  I:=FindCombination(CombinationID); if I<0 then Exit;
  J:=Length(Combinations[I].Terms); SetLength(Combinations[I].Terms,J+1);
  Combinations[I].Terms[J].LoadCaseID:=LoadCaseID; Combinations[I].Terms[J].Factor:=Factor;
end;

function TFEMModel.AddNodalLoad(NodeID,LoadCaseID:Integer; const V:TDofVector):Integer;
var I:Integer;
begin
  I:=Length(Loads); SetLength(Loads,I+1); Loads[I].ID:=FNextLoadID; Inc(FNextLoadID);
  Loads[I].NodeID:=NodeID; Loads[I].LoadCaseID:=LoadCaseID; Loads[I].Value:=V; Result:=Loads[I].ID;
end;

function TFEMModel.AddGroup(const Name:string):Integer;
var I:Integer;
begin
  I:=Length(Groups); SetLength(Groups,I+1); Groups[I].ID:=FNextGroupID; Inc(FNextGroupID);
  Groups[I].Name:=Name; Result:=Groups[I].ID;
end;

function TFEMModel.AddCoordinateSystem(const Name:string; const Origin,XAxis,YAxis,ZAxis:TVec3):Integer;
var I:Integer;
begin
  I:=Length(CoordinateSystems); SetLength(CoordinateSystems,I+1);
  CoordinateSystems[I].ID:=FNextCSID; Inc(FNextCSID); CoordinateSystems[I].Name:=Name;
  CoordinateSystems[I].Origin:=Origin; CoordinateSystems[I].XAxis:=VUnit(XAxis);
  CoordinateSystems[I].YAxis:=VUnit(YAxis); CoordinateSystems[I].ZAxis:=VUnit(ZAxis);
  Result:=CoordinateSystems[I].ID;
end;

function TFEMModel.AddElement(const Kind:string; const NodeIDs:array of Integer;
  MaterialID,SectionID:Integer; Thickness:Double; CoordinateSystemID,GroupID:Integer):Integer;
var I,J:Integer;
begin
  I:=Length(Elements); SetLength(Elements,I+1); Elements[I].ID:=FNextElementID; Inc(FNextElementID);
  Elements[I].Kind:=Kind; SetLength(Elements[I].NodeIDs,Length(NodeIDs));
  for J:=0 to High(NodeIDs) do Elements[I].NodeIDs[J]:=NodeIDs[J];
  Elements[I].MaterialID:=MaterialID; Elements[I].SectionID:=SectionID; Elements[I].Thickness:=Thickness;
  Elements[I].CoordinateSystemID:=CoordinateSystemID; Elements[I].GroupID:=GroupID;
  Result:=Elements[I].ID;
end;

function TFEMModel.FindNode(ID:Integer):Integer;
var I:Integer;
begin Result:=-1; for I:=0 to High(Nodes) do if Nodes[I].ID=ID then Exit(I); end;

function TFEMModel.FindMaterial(ID:Integer):Integer;
var I:Integer;
begin Result:=-1; for I:=0 to High(Materials) do if Materials[I].ID=ID then Exit(I); end;

function TFEMModel.FindSection(ID:Integer):Integer;
var I:Integer;
begin Result:=-1; for I:=0 to High(Sections) do if Sections[I].ID=ID then Exit(I); end;

function TFEMModel.FindLoadCase(ID:Integer):Integer;
var I:Integer;
begin Result:=-1; for I:=0 to High(LoadCases) do if LoadCases[I].ID=ID then Exit(I); end;

function TFEMModel.FindCombination(ID:Integer):Integer;
var I:Integer;
begin Result:=-1; for I:=0 to High(Combinations) do if Combinations[I].ID=ID then Exit(I); end;

function TFEMModel.FindGroup(ID:Integer):Integer;
var I:Integer;
begin Result:=-1; for I:=0 to High(Groups) do if Groups[I].ID=ID then Exit(I); end;

function TFEMModel.TotalDOF:Integer; begin Result:=Length(Nodes)*6; end;
function TFEMModel.CreateDOFNumbering:TDOFNumbering; begin Result:=TDOFNumbering.Create(Self); end;

function TFEMModel.Validate(out Errors:TStringList):Boolean;
var I,J,N,M,S,L,CS:Integer;
begin
  Errors:=TStringList.Create;
  if Length(Nodes)=0 then Errors.Add('Model contains no nodes.');
  for I:=0 to High(Elements) do begin
    if Length(Elements[I].NodeIDs)=0 then Errors.Add(Format('Element %d has no nodes.',[Elements[I].ID]));
    for J:=0 to High(Elements[I].NodeIDs) do begin
      N:=FindNode(Elements[I].NodeIDs[J]);
      if N<0 then Errors.Add(Format('Element %d references missing node %d.',[Elements[I].ID,Elements[I].NodeIDs[J]]));
    end;
    M:=FindMaterial(Elements[I].MaterialID);
    if M<0 then Errors.Add(Format('Element %d references missing material %d.',[Elements[I].ID,Elements[I].MaterialID]));
    if Elements[I].SectionID<>0 then begin
      S:=FindSection(Elements[I].SectionID);
      if S<0 then Errors.Add(Format('Element %d references missing section %d.',[Elements[I].ID,Elements[I].SectionID]));
    end;
    if Elements[I].CoordinateSystemID<>0 then begin
      CS:=-1;
      for J:=0 to High(CoordinateSystems) do if CoordinateSystems[J].ID=Elements[I].CoordinateSystemID then begin CS:=J; Break; end;
      if CS<0 then Errors.Add(Format('Element %d references missing coordinate system %d.',[Elements[I].ID,Elements[I].CoordinateSystemID]));
    end;
    if Elements[I].GroupID<>0 then begin
      if FindGroup(Elements[I].GroupID)<0 then Errors.Add(Format('Element %d references missing group %d.',[Elements[I].ID,Elements[I].GroupID]));
    end;
  end;
  for I:=0 to High(Loads) do begin
    if FindNode(Loads[I].NodeID)<0 then Errors.Add(Format('Load %d references missing node %d.',[Loads[I].ID,Loads[I].NodeID]));
    if FindLoadCase(Loads[I].LoadCaseID)<0 then Errors.Add(Format('Load %d references missing load case %d.',[Loads[I].ID,Loads[I].LoadCaseID]));
  end;
  Result:=Errors.Count=0;
end;

end.

