unit FEMModelEditor;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, FEMTypes, FEMModel;

type
  TEditIntArray = array of Integer;

  TModelSnapshot = record
    Nodes: array of TNode;
    Materials: array of TMaterial;
    Sections: array of TBeamSection;
    LoadCases: array of TLoadCase;
    Combinations: array of TLoadCombination;
    Loads: array of TNodalLoad;
    Elements: array of TElementRecord;
    Groups: array of TGroup;
    CoordinateSystems: array of TCoordinateSystem;
  end;

  TModelEditKind = (mekCreateNode, mekCreateElement, mekMoveNode, mekDeleteNode,
    mekDeleteElement, mekSplitElement, mekSubdivideElement, mekAssignElementProperties, mekTransformGeometry, mekCopyGeometry);

  TModelCommand = class
  private
    FEditor: TObject;
    FKind: TModelEditKind;
    FDescription: string;
    FBefore,FAfter:TModelSnapshot;
  public
    constructor Create(AEditor:TObject; AKind:TModelEditKind; const ADescription:string;
      const Before,After:TModelSnapshot);
    procedure Undo;
    procedure Redo;
    property Description:string read FDescription;
  end;

  TModelEditor = class
  private
    FModel:TFEMModel;
    FUndo,FRedo:TList;
    procedure Capture(out S:TModelSnapshot);
    procedure Restore(const S:TModelSnapshot);
    procedure PushCommand(AKind:TModelEditKind; const Description:string;
      const Before,After:TModelSnapshot);
    function SelectedIndexNode(ID:Integer):Integer;
    function SelectedIndexElement(ID:Integer):Integer;
  public
    constructor Create(AModel:TFEMModel);
    destructor Destroy; override;
    function CreateNode(const P:TVec3):Integer;
    function CreateElement(const Kind:string; NodeA,NodeB,MaterialID,SectionID,GroupID:Integer):Integer;
    function MoveNode(NodeID:Integer; const P:TVec3):Boolean;
    function DeleteNode(NodeID:Integer):Boolean;
    function DeleteElement(ElementID:Integer):Boolean;
    function SplitElement(ElementID:Integer; out NewNodeID,NewElementID:Integer):Boolean;
    function SubdivideElement(ElementID,Segments:Integer; out CreatedNodes,CreatedElements:Integer):Boolean;
    function AssignElementProperties(const ElementIDs:array of Integer; MaterialID,SectionID,GroupID:Integer):Integer;
    function TranslateNodes(const NodeIDs:array of Integer; const Delta:TVec3):Integer;
    function TranslateElements(const ElementIDs:array of Integer; const Delta:TVec3):Integer;
    function RotateNodes(const NodeIDs:array of Integer; const Origin:TVec3; Axis:Integer; AngleDeg:Double):Integer;
    function MirrorNodes(const NodeIDs:array of Integer; const Origin:TVec3; Axis:Integer):Integer;
    function CopyElements(const ElementIDs:array of Integer; const Delta:TVec3; out CreatedNodes,CreatedElements:Integer):Boolean;
    function DeleteElements(const ElementIDs:array of Integer):Integer;
    function Undo:Boolean;
    function Redo:Boolean;
    procedure ClearHistory;
    function CanUndo:Boolean;
    function CanRedo:Boolean;
    function UndoDescription:string;
    function RedoDescription:string;
    property Model:TFEMModel read FModel;
  end;

implementation

procedure CopySnapshotArrays(const Src:TModelSnapshot; out Dst:TModelSnapshot);
var I,J:Integer;
begin
  Dst:=Default(TModelSnapshot);
  Dst.Nodes:=Copy(Src.Nodes);
  Dst.Materials:=Copy(Src.Materials);
  Dst.Sections:=Copy(Src.Sections);
  Dst.LoadCases:=Copy(Src.LoadCases);
  SetLength(Dst.Combinations,Length(Src.Combinations));
  for I:=0 to High(Src.Combinations) do begin
    Dst.Combinations[I].ID:=Src.Combinations[I].ID;
    Dst.Combinations[I].Name:=Src.Combinations[I].Name;
    Dst.Combinations[I].Terms:=Copy(Src.Combinations[I].Terms);
  end;
  Dst.Loads:=Copy(Src.Loads);
  SetLength(Dst.Elements,Length(Src.Elements));
  for I:=0 to High(Src.Elements) do begin
    Dst.Elements[I].ID:=Src.Elements[I].ID;
    Dst.Elements[I].Kind:=Src.Elements[I].Kind;
    Dst.Elements[I].NodeIDs:=Copy(Src.Elements[I].NodeIDs);
    Dst.Elements[I].MaterialID:=Src.Elements[I].MaterialID;
    Dst.Elements[I].SectionID:=Src.Elements[I].SectionID;
    Dst.Elements[I].Thickness:=Src.Elements[I].Thickness;
    Dst.Elements[I].CoordinateSystemID:=Src.Elements[I].CoordinateSystemID;
    Dst.Elements[I].GroupID:=Src.Elements[I].GroupID;
  end;
  Dst.Groups:=Copy(Src.Groups);
  Dst.CoordinateSystems:=Copy(Src.CoordinateSystems);
end;

constructor TModelCommand.Create(AEditor:TObject; AKind:TModelEditKind;
  const ADescription:string; const Before,After:TModelSnapshot);
begin
  inherited Create; FEditor:=AEditor; FKind:=AKind; FDescription:=ADescription;
  CopySnapshotArrays(Before,FBefore); CopySnapshotArrays(After,FAfter);
end;

procedure TModelCommand.Undo;
begin TModelEditor(FEditor).Restore(FBefore); end;
procedure TModelCommand.Redo;
begin TModelEditor(FEditor).Restore(FAfter); end;

constructor TModelEditor.Create(AModel:TFEMModel);
begin inherited Create; FModel:=AModel; FUndo:=TList.Create; FRedo:=TList.Create; end;

destructor TModelEditor.Destroy;
var I:Integer;
begin
  for I:=0 to FUndo.Count-1 do TObject(FUndo[I]).Free;
  for I:=0 to FRedo.Count-1 do TObject(FRedo[I]).Free;
  FUndo.Free; FRedo.Free; inherited Destroy;
end;

procedure TModelEditor.Capture(out S:TModelSnapshot);
var T:TModelSnapshot;
begin
  T:=Default(TModelSnapshot);
  T.Nodes:=FModel.Nodes; T.Materials:=FModel.Materials; T.Sections:=FModel.Sections;
  T.LoadCases:=FModel.LoadCases; T.Combinations:=FModel.Combinations; T.Loads:=FModel.Loads;
  T.Elements:=FModel.Elements; T.Groups:=FModel.Groups; T.CoordinateSystems:=FModel.CoordinateSystems;
  CopySnapshotArrays(T,S);
end;

procedure TModelEditor.Restore(const S:TModelSnapshot);
var T:TModelSnapshot;
begin
  CopySnapshotArrays(S,T);
  FModel.Nodes:=T.Nodes; FModel.Materials:=T.Materials; FModel.Sections:=T.Sections;
  FModel.LoadCases:=T.LoadCases; FModel.Combinations:=T.Combinations; FModel.Loads:=T.Loads;
  FModel.Elements:=T.Elements; FModel.Groups:=T.Groups; FModel.CoordinateSystems:=T.CoordinateSystems;
  FModel.RebuildIDCounters;
end;

procedure TModelEditor.PushCommand(AKind:TModelEditKind; const Description:string;
  const Before,After:TModelSnapshot);
var C:TModelCommand; I:Integer;
begin
  C:=TModelCommand.Create(Self,AKind,Description,Before,After); FUndo.Add(C);
  for I:=0 to FRedo.Count-1 do TObject(FRedo[I]).Free; FRedo.Clear;
end;

function TModelEditor.SelectedIndexNode(ID:Integer):Integer; begin Result:=FModel.FindNode(ID); end;
function TModelEditor.SelectedIndexElement(ID:Integer):Integer;
var I:Integer;
begin Result:=-1; for I:=0 to High(FModel.Elements) do if FModel.Elements[I].ID=ID then Exit(I); end;

function TModelEditor.CreateNode(const P:TVec3):Integer;
var B,A:TModelSnapshot;
begin Capture(B); Result:=FModel.AddNode(P); Capture(A); PushCommand(mekCreateNode,Format('Create node %d',[Result]),B,A); end;

function TModelEditor.CreateElement(const Kind:string; NodeA,NodeB,MaterialID,SectionID,GroupID:Integer):Integer;
var B,A:TModelSnapshot; N:array[0..1] of Integer;
begin
  Result:=-1;
  if (FModel.FindNode(NodeA)<0) or (FModel.FindNode(NodeB)<0) or (NodeA=NodeB) then Exit;
  B:=Default(TModelSnapshot); A:=Default(TModelSnapshot); Capture(B);
  N[0]:=NodeA; N[1]:=NodeB;
  Result:=FModel.AddElement(Kind,N,MaterialID,SectionID,0,0,GroupID);
  Capture(A); PushCommand(mekCreateElement,Format('Create %s element %d',[Kind,Result]),B,A);
end;

function TModelEditor.MoveNode(NodeID:Integer; const P:TVec3):Boolean;
var B,A:TModelSnapshot; I:Integer;
begin
  Result:=False; I:=SelectedIndexNode(NodeID); if I<0 then Exit;
  B:=Default(TModelSnapshot); A:=Default(TModelSnapshot); Capture(B);
  FModel.Nodes[I].Position:=P; Capture(A); PushCommand(mekMoveNode,Format('Move node %d',[NodeID]),B,A); Result:=True;
end;

function TModelEditor.DeleteElement(ElementID:Integer):Boolean;
var B,A:TModelSnapshot; I,J:Integer;
begin
  Result:=False; I:=-1; for J:=0 to High(FModel.Elements) do if FModel.Elements[J].ID=ElementID then begin I:=J;Break;end;
  if I<0 then Exit;
  Capture(B);
  for J:=I to High(FModel.Elements)-1 do FModel.Elements[J]:=FModel.Elements[J+1];
  SetLength(FModel.Elements,Length(FModel.Elements)-1); Capture(A);
  PushCommand(mekDeleteElement,Format('Delete element %d',[ElementID]),B,A); Result:=True;
end;

function TModelEditor.DeleteNode(NodeID:Integer):Boolean;
var B,A:TModelSnapshot; I,J,K:Integer; E:TElementRecord;
begin
  Result:=False; I:=FModel.FindNode(NodeID); if I<0 then Exit; Capture(B);
  J:=Length(FModel.Elements)-1;
  while J>=0 do begin
    E:=FModel.Elements[J];
    for K:=0 to High(E.NodeIDs) do if E.NodeIDs[K]=NodeID then begin
      FModel.Elements[J]:=FModel.Elements[High(FModel.Elements)]; SetLength(FModel.Elements,Length(FModel.Elements)-1); Break;
    end;
    Dec(J);
  end;
  J:=Length(FModel.Loads)-1;
  while J>=0 do begin
    if FModel.Loads[J].NodeID=NodeID then begin FModel.Loads[J]:=FModel.Loads[High(FModel.Loads)]; SetLength(FModel.Loads,Length(FModel.Loads)-1); end;
    Dec(J);
  end;
  FModel.Nodes[I]:=FModel.Nodes[High(FModel.Nodes)]; SetLength(FModel.Nodes,Length(FModel.Nodes)-1);
  FModel.RebuildIDCounters; Capture(A); PushCommand(mekDeleteNode,Format('Delete node %d',[NodeID]),B,A); Result:=True;
end;

function TModelEditor.SplitElement(ElementID:Integer; out NewNodeID,NewElementID:Integer):Boolean;
var B,A:TModelSnapshot; I,N1,N2,NewE:Integer; E:TElementRecord; P:TVec3;
begin
  Result:=False; NewNodeID:=-1; NewElementID:=-1; I:=-1;
  for N1:=0 to High(FModel.Elements) do if FModel.Elements[N1].ID=ElementID then begin I:=N1;Break;end;
  if I<0 then Exit;
  E:=FModel.Elements[I]; if (Length(E.NodeIDs)<>2) or (not SameText(E.Kind,'BEAM3D')) then Exit;
  N1:=FModel.FindNode(E.NodeIDs[0]); N2:=FModel.FindNode(E.NodeIDs[1]); if (N1<0) or (N2<0) then Exit;
  Capture(B); P:=VScale(VAdd(FModel.Nodes[N1].Position,FModel.Nodes[N2].Position),0.5);
  NewNodeID:=FModel.AddNode(P);
  FModel.Elements[I].NodeIDs[1]:=NewNodeID;
  NewE:=FModel.AddElement(E.Kind,[NewNodeID,E.NodeIDs[1]],E.MaterialID,E.SectionID,E.Thickness,E.CoordinateSystemID,E.GroupID);
  NewElementID:=NewE; Capture(A); PushCommand(mekSplitElement,Format('Split beam %d at node %d',[ElementID,NewNodeID]),B,A); Result:=True;
end;


function TModelEditor.SubdivideElement(ElementID,Segments:Integer; out CreatedNodes,CreatedElements:Integer):Boolean;
var B,A:TModelSnapshot; I,J,N1,N2,PrevNode,NewID:Integer; E:TElementRecord; P1,P2,P:TVec3; T:Double;
begin
  Result:=False; CreatedNodes:=0; CreatedElements:=0;
  if (Segments<2) or (Segments>100000) then Exit;
  I:=-1;
  for J:=0 to High(FModel.Elements) do
    if FModel.Elements[J].ID=ElementID then begin I:=J; Break; end;
  if I<0 then Exit;
  E:=FModel.Elements[I];
  if (Length(E.NodeIDs)<>2) or (not SameText(E.Kind,'BEAM3D')) then Exit;
  N1:=FModel.FindNode(E.NodeIDs[0]); N2:=FModel.FindNode(E.NodeIDs[1]);
  if (N1<0) or (N2<0) then Exit;
  P1:=FModel.Nodes[N1].Position; P2:=FModel.Nodes[N2].Position;
  if VNorm(VSub(P2,P1))<1e-12 then Exit;
  Capture(B);
  PrevNode:=E.NodeIDs[0];
  for J:=1 to Segments-1 do begin
    T:=J/Segments;
    P:=Vec3(P1.X+(P2.X-P1.X)*T,P1.Y+(P2.Y-P1.Y)*T,P1.Z+(P2.Z-P1.Z)*T);
    NewID:=FModel.AddNode(P); Inc(CreatedNodes);
    if J=1 then
      FModel.Elements[I].NodeIDs[1]:=NewID
    else
      FModel.AddElement(E.Kind,[PrevNode,NewID],E.MaterialID,E.SectionID,E.Thickness,E.CoordinateSystemID,E.GroupID);
    PrevNode:=NewID;
  end;
  FModel.AddElement(E.Kind,[PrevNode,E.NodeIDs[1]],E.MaterialID,E.SectionID,E.Thickness,E.CoordinateSystemID,E.GroupID);
  CreatedElements:=Segments;
  Capture(A);
  PushCommand(mekSubdivideElement,Format('Subdivide beam %d into %d segments',[ElementID,Segments]),B,A);
  Result:=True;
end;


function TModelEditor.TranslateNodes(const NodeIDs:array of Integer; const Delta:TVec3):Integer;
var B,A:TModelSnapshot; I,J:Integer; Changed:Integer; ID:Integer;
begin
  Result:=0;
  if Length(NodeIDs)=0 then Exit;
  Capture(B); Changed:=0;
  for I:=0 to High(NodeIDs) do begin
    ID:=NodeIDs[I];
    J:=FModel.FindNode(ID);
    if J>=0 then begin
      FModel.Nodes[J].Position:=VAdd(FModel.Nodes[J].Position,Delta);
      Inc(Changed);
    end;
  end;
  if Changed=0 then begin Restore(B); Exit; end;
  Capture(A);
  PushCommand(mekMoveNode,Format('Translate %d node(s)',[Changed]),B,A);
  Result:=Changed;
end;

function TModelEditor.TranslateElements(const ElementIDs:array of Integer; const Delta:TVec3):Integer;
var IDs:TEditIntArray; I,J,K,N,NodeID:Integer; E:TElementRecord; Seen:Boolean;
begin
  SetLength(IDs,0);
  for I:=0 to High(ElementIDs) do begin
    for J:=0 to High(FModel.Elements) do
      if FModel.Elements[J].ID=ElementIDs[I] then begin
        E:=FModel.Elements[J];
        for K:=0 to High(E.NodeIDs) do begin
          NodeID:=E.NodeIDs[K]; Seen:=False;
          for N:=0 to High(IDs) do if IDs[N]=NodeID then begin Seen:=True; Break; end;
          if not Seen then begin SetLength(IDs,Length(IDs)+1); IDs[High(IDs)]:=NodeID; end;
        end;
        Break;
      end;
  end;
  Result:=TranslateNodes(IDs,Delta);
end;


function RotateAroundAxis(const P,Origin:TVec3; Axis:Integer; AngleRad:Double):TVec3;
var Q:TVec3; C,S:Double;
begin
  Q:=VSub(P,Origin); C:=Cos(AngleRad); S:=Sin(AngleRad);
  case Axis of
    0: Result:=Vec3(Q.X,Q.Y*C-Q.Z*S,Q.Y*S+Q.Z*C);
    1: Result:=Vec3(Q.X*C+Q.Z*S,Q.Y,-Q.X*S+Q.Z*C);
    else Result:=Vec3(Q.X*C-Q.Y*S,Q.X*S+Q.Y*C,Q.Z);
  end;
  Result:=VAdd(Result,Origin);
end;

function TModelEditor.RotateNodes(const NodeIDs:array of Integer; const Origin:TVec3;
  Axis:Integer; AngleDeg:Double):Integer;
var B,A:TModelSnapshot; I,J:Integer; ID:Integer; Seen:TEditIntArray; K:Integer; P:TVec3;
begin
  Result:=0; if Length(NodeIDs)=0 then Exit;
  if (Axis<0) or (Axis>2) or IsNan(AngleDeg) or IsInfinite(AngleDeg) then Exit;
  SetLength(Seen,0); Capture(B);
  for I:=0 to High(NodeIDs) do begin
    ID:=NodeIDs[I]; J:=FModel.FindNode(ID); if J<0 then Continue;
    K:=0; while K<Length(Seen) do begin if Seen[K]=ID then Break; Inc(K); end;
    if K<Length(Seen) then Continue;
    SetLength(Seen,Length(Seen)+1); Seen[High(Seen)]:=ID;
    P:=RotateAroundAxis(FModel.Nodes[J].Position,Origin,Axis,AngleDeg*Pi/180.0);
    FModel.Nodes[J].Position:=P; Inc(Result);
  end;
  if Result=0 then begin Restore(B); Exit; end;
  Capture(A); PushCommand(mekTransformGeometry,Format('Rotate %d node(s) %.6g deg',[Result,AngleDeg]),B,A);
end;

function TModelEditor.MirrorNodes(const NodeIDs:array of Integer; const Origin:TVec3;
  Axis:Integer):Integer;
var B,A:TModelSnapshot; I,J:Integer; ID:Integer; Seen:TEditIntArray; K:Integer; P:TVec3;
begin
  Result:=0; if Length(NodeIDs)=0 then Exit;
  if (Axis<0) or (Axis>2) then Exit;
  SetLength(Seen,0); Capture(B);
  for I:=0 to High(NodeIDs) do begin
    ID:=NodeIDs[I]; J:=FModel.FindNode(ID); if J<0 then Continue;
    K:=0; while K<Length(Seen) do begin if Seen[K]=ID then Break; Inc(K); end;
    if K<Length(Seen) then Continue;
    SetLength(Seen,Length(Seen)+1); Seen[High(Seen)]:=ID;
    P:=FModel.Nodes[J].Position;
    case Axis of
      0: P.X:=2*Origin.X-P.X;
      1: P.Y:=2*Origin.Y-P.Y;
      else P.Z:=2*Origin.Z-P.Z;
    end;
    FModel.Nodes[J].Position:=P; Inc(Result);
  end;
  if Result=0 then begin Restore(B); Exit; end;
  Capture(A); PushCommand(mekTransformGeometry,Format('Mirror %d node(s)',[Result]),B,A);
end;

function TModelEditor.CopyElements(const ElementIDs:array of Integer; const Delta:TVec3;
  out CreatedNodes,CreatedElements:Integer):Boolean;
var B,A:TModelSnapshot; I,J,K,N,EIdx,OldID,NewID:Integer; E:TElementRecord;
    NodeIDs,NewNodeIDs:TEditIntArray; P:TVec3; Found:Boolean;
begin
  Result:=False; CreatedNodes:=0; CreatedElements:=0;
  if Length(ElementIDs)=0 then Exit;
  SetLength(NodeIDs,0); SetLength(NewNodeIDs,0);
  for I:=0 to High(ElementIDs) do begin
    EIdx:=-1;
    for J:=0 to High(FModel.Elements) do if FModel.Elements[J].ID=ElementIDs[I] then begin EIdx:=J; Break; end;
    if EIdx<0 then Continue;
    E:=FModel.Elements[EIdx];
    for K:=0 to High(E.NodeIDs) do begin
      OldID:=E.NodeIDs[K]; Found:=False;
      for N:=0 to High(NodeIDs) do if NodeIDs[N]=OldID then begin Found:=True; Break; end;
      if not Found then begin SetLength(NodeIDs,Length(NodeIDs)+1); NodeIDs[High(NodeIDs)]:=OldID; end;
    end;
  end;
  if Length(NodeIDs)=0 then Exit;
  Capture(B);
  SetLength(NewNodeIDs,Length(NodeIDs));
  for I:=0 to High(NodeIDs) do begin
    J:=FModel.FindNode(NodeIDs[I]);
    if J<0 then begin Restore(B); Exit; end;
    P:=VAdd(FModel.Nodes[J].Position,Delta);
    NewNodeIDs[I]:=FModel.AddNode(P); Inc(CreatedNodes);
  end;
  for I:=0 to High(ElementIDs) do begin
    EIdx:=-1;
    for J:=0 to High(B.Elements) do if B.Elements[J].ID=ElementIDs[I] then begin EIdx:=J; Break; end;
    if EIdx<0 then Continue;
    E:=B.Elements[EIdx];
    for K:=0 to High(E.NodeIDs) do begin
      OldID:=E.NodeIDs[K]; NewID:=-1;
      for N:=0 to High(NodeIDs) do if NodeIDs[N]=OldID then begin NewID:=NewNodeIDs[N]; Break; end;
      if NewID<0 then begin Restore(B); Exit; end;
      E.NodeIDs[K]:=NewID;
    end;
    FModel.AddElement(E.Kind,E.NodeIDs,E.MaterialID,E.SectionID,E.Thickness,E.CoordinateSystemID,E.GroupID);
    Inc(CreatedElements);
  end;
  if CreatedElements=0 then begin Restore(B); Exit; end;
  Capture(A); PushCommand(mekCopyGeometry,Format('Copy %d element(s)',[CreatedElements]),B,A); Result:=True;
end;

function TModelEditor.DeleteElements(const ElementIDs:array of Integer):Integer;
var B,A:TModelSnapshot; I,J,K:Integer; ID:Integer; Found:Boolean;
begin
  Result:=0;
  if Length(ElementIDs)=0 then Exit;
  Capture(B);
  I:=Length(FModel.Elements)-1;
  while I>=0 do begin
    ID:=FModel.Elements[I].ID; Found:=False;
    for J:=0 to High(ElementIDs) do if ElementIDs[J]=ID then begin Found:=True; Break; end;
    if Found then begin
      FModel.Elements[I]:=FModel.Elements[High(FModel.Elements)];
      SetLength(FModel.Elements,Length(FModel.Elements)-1);
      Inc(Result);
    end;
    Dec(I);
  end;
  if Result=0 then begin Restore(B); Exit; end;
  Capture(A);
  PushCommand(mekDeleteElement,Format('Delete %d element(s)',[Result]),B,A);
end;

function TModelEditor.AssignElementProperties(const ElementIDs:array of Integer; MaterialID,SectionID,GroupID:Integer):Integer;
var B,A:TModelSnapshot; I,J,K,Changed:Integer; EID:Integer;
begin
  Result:=0;
  if (MaterialID<0) and (SectionID<0) and (GroupID<0) then Exit;
  if (MaterialID>0) and (FModel.FindMaterial(MaterialID)<0) then Exit;
  if (SectionID>0) and (FModel.FindSection(SectionID)<0) then Exit;
  if (GroupID>0) and (FModel.FindGroup(GroupID)<0) then Exit;
  Capture(B);
  Changed:=0;
  for I:=0 to High(ElementIDs) do begin
    EID:=ElementIDs[I];
    for J:=0 to High(FModel.Elements) do
      if FModel.Elements[J].ID=EID then begin
        if MaterialID>=0 then FModel.Elements[J].MaterialID:=MaterialID;
        if SectionID>=0 then FModel.Elements[J].SectionID:=SectionID;
        if GroupID>=0 then FModel.Elements[J].GroupID:=GroupID;
        Inc(Changed);
        Break;
      end;
  end;
  if Changed=0 then Exit;
  Capture(A);
  PushCommand(mekAssignElementProperties,
    Format('Assign properties to %d element(s)',[Changed]),B,A);
  Result:=Changed;
end;

function TModelEditor.Undo:Boolean;
var C:TModelCommand;
begin
  Result:=False; if FUndo.Count=0 then Exit; C:=TModelCommand(FUndo[FUndo.Count-1]); FUndo.Delete(FUndo.Count-1); C.Undo; FRedo.Add(C); Result:=True;
end;

function TModelEditor.Redo:Boolean;
var C:TModelCommand;
begin
  Result:=False; if FRedo.Count=0 then Exit; C:=TModelCommand(FRedo[FRedo.Count-1]); FRedo.Delete(FRedo.Count-1); C.Redo; FUndo.Add(C); Result:=True;
end;

procedure TModelEditor.ClearHistory;
var I:Integer;
begin
  for I:=0 to FUndo.Count-1 do TObject(FUndo[I]).Free; FUndo.Clear;
  for I:=0 to FRedo.Count-1 do TObject(FRedo[I]).Free; FRedo.Clear;
end;

function TModelEditor.CanUndo:Boolean; begin Result:=FUndo.Count>0; end;
function TModelEditor.CanRedo:Boolean; begin Result:=FRedo.Count>0; end;
function TModelEditor.UndoDescription:string;
begin if CanUndo then Result:=TModelCommand(FUndo[FUndo.Count-1]).Description else Result:=''; end;
function TModelEditor.RedoDescription:string;
begin if CanRedo then Result:=TModelCommand(FRedo[FRedo.Count-1]).Description else Result:=''; end;

end.
