unit FEMDisplayManager;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, FEMModel;

type
  TDisplayManager = class
  private
    FHiddenElements: TStringList;
    FHiddenNodes: TStringList;
    FIsolatedElements: TStringList;
      FMaterialVisible: TStringList;
    FSectionVisible: TStringList;
    FGroupVisible: TStringList;
    FHasIsolation: Boolean;
    function HasID(const L:TStringList; ID:Integer):Boolean;
    procedure AddID(L:TStringList; ID:Integer);
    procedure RemoveID(L:TStringList; ID:Integer);
    function GetCategoryVisible(L:TStringList; ID:Integer):Boolean;
    procedure SetCategoryVisible(L:TStringList; ID:Integer; Value:Boolean);
    procedure BuildIsolation(const M:TFEMModel; const ElementIDs:array of Integer);
    function ElementCategoryVisible(const E:TElementRecord):Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    procedure ShowAll;
    procedure HideElement(ID:Integer);
    procedure ShowElement(ID:Integer);
    procedure HideNode(ID:Integer);
    procedure ShowNode(ID:Integer);
    procedure IsolateElements(const ElementIDs:array of Integer);
    procedure IsolateByKind(const M:TFEMModel; const Kind:string);
    procedure IsolateByMaterial(const M:TFEMModel; MaterialID:Integer);
    procedure IsolateBySection(const M:TFEMModel; SectionID:Integer);
    procedure IsolateByGroup(const M:TFEMModel; GroupID:Integer);
    procedure ShowByKind(const M:TFEMModel; const Kind:string);
    procedure ShowByMaterial(const M:TFEMModel; MaterialID:Integer);
    procedure ShowBySection(const M:TFEMModel; SectionID:Integer);
    procedure ShowByGroup(const M:TFEMModel; GroupID:Integer);
    procedure HideByKind(const M:TFEMModel; const Kind:string);
    procedure HideByMaterial(const M:TFEMModel; MaterialID:Integer);
    procedure HideBySection(const M:TFEMModel; SectionID:Integer);
    procedure HideByGroup(const M:TFEMModel; GroupID:Integer);
    procedure RestoreIsolation;
    procedure IsolateSelected(const M:TFEMModel; const SelectionIDs:array of Integer);
    function IsElementVisible(const E:TElementRecord):Boolean;
    function IsNodeVisible(const M:TFEMModel; NodeID:Integer):Boolean;
    function HiddenElementCount:Integer;
    function IsolationActive:Boolean;
  end;

implementation

constructor TDisplayManager.Create;
begin
  inherited Create;
  FHiddenElements:=TStringList.Create; FHiddenNodes:=TStringList.Create;
  FIsolatedElements:=TStringList.Create;
  FMaterialVisible:=TStringList.Create;
  FSectionVisible:=TStringList.Create; FGroupVisible:=TStringList.Create;
  Reset;
end;

destructor TDisplayManager.Destroy;
begin
  FGroupVisible.Free; FSectionVisible.Free; FMaterialVisible.Free;
  FIsolatedElements.Free; FHiddenNodes.Free; FHiddenElements.Free; inherited Destroy;
end;

procedure TDisplayManager.Reset;
begin
  FHiddenElements.Clear; FHiddenNodes.Clear; FIsolatedElements.Clear;
  FMaterialVisible.Clear; FSectionVisible.Clear; FGroupVisible.Clear;
  FHasIsolation:=False;
end;

function TDisplayManager.HasID(const L:TStringList; ID:Integer):Boolean;
begin Result:=L.IndexOf(IntToStr(ID))>=0; end;
procedure TDisplayManager.AddID(L:TStringList; ID:Integer); begin if not HasID(L,ID) then L.Add(IntToStr(ID)); end;
procedure TDisplayManager.RemoveID(L:TStringList; ID:Integer); begin L.Delete(L.IndexOf(IntToStr(ID))); end;

function TDisplayManager.GetCategoryVisible(L:TStringList; ID:Integer):Boolean;
var I:Integer;
begin
  I:=L.IndexOfName(IntToStr(ID));
  if I<0 then Result:=True else Result:=L.ValueFromIndex[I]='1';
end;

procedure TDisplayManager.SetCategoryVisible(L:TStringList; ID:Integer; Value:Boolean);
var S:string; I:Integer;
begin
  S:=IntToStr(ID); I:=L.IndexOfName(S);
  if Value then S:=S+'=1' else S:=S+'=0';
  if I<0 then L.Add(S) else L.ValueFromIndex[I]:=Copy(S,Pos('=',S)+1,MaxInt);
end;

function TDisplayManager.ElementCategoryVisible(const E:TElementRecord):Boolean;
begin
  Result:=GetCategoryVisible(FMaterialVisible,E.MaterialID) and
          GetCategoryVisible(FSectionVisible,E.SectionID) and
          GetCategoryVisible(FGroupVisible,E.GroupID);
end;

function TDisplayManager.IsElementVisible(const E:TElementRecord):Boolean;
begin
  Result:=ElementCategoryVisible(E);
  if Result then Result:=not HasID(FHiddenElements,E.ID);
  if Result and FHasIsolation then Result:=HasID(FIsolatedElements,E.ID);
end;

function TDisplayManager.IsNodeVisible(const M:TFEMModel; NodeID:Integer):Boolean;
var I,J:Integer; Connected:Boolean;
begin
  if HasID(FHiddenNodes,NodeID) then Exit(False);
  Connected:=False; Result:=False;
  for I:=0 to High(M.Elements) do begin
    for J:=0 to High(M.Elements[I].NodeIDs) do if M.Elements[I].NodeIDs[J]=NodeID then begin
      Connected:=True;
      if IsElementVisible(M.Elements[I]) then Exit(True);
      Break;
    end;
  end;
  if not Connected then Result:=True;
end;

procedure TDisplayManager.ShowAll;
begin Reset; end;
procedure TDisplayManager.HideElement(ID:Integer); begin AddID(FHiddenElements,ID); end;
procedure TDisplayManager.ShowElement(ID:Integer); begin if HasID(FHiddenElements,ID) then RemoveID(FHiddenElements,ID); end;
procedure TDisplayManager.HideNode(ID:Integer); begin AddID(FHiddenNodes,ID); end;
procedure TDisplayManager.ShowNode(ID:Integer); begin if HasID(FHiddenNodes,ID) then RemoveID(FHiddenNodes,ID); end;

procedure TDisplayManager.IsolateElements(const ElementIDs:array of Integer);
var I:Integer;
begin
  FIsolatedElements.Clear;
  for I:=0 to High(ElementIDs) do AddID(FIsolatedElements,ElementIDs[I]);
  FHasIsolation:=Length(ElementIDs)>0;
end;

procedure TDisplayManager.BuildIsolation(const M:TFEMModel; const ElementIDs:array of Integer);
begin IsolateElements(ElementIDs); end;

procedure TDisplayManager.IsolateByKind(const M:TFEMModel; const Kind:string);
var I,N:Integer; A:array of Integer;
begin SetLength(A,Length(M.Elements));N:=0;for I:=0 to High(M.Elements) do if SameText(M.Elements[I].Kind,Kind) then begin A[N]:=M.Elements[I].ID;Inc(N);end;SetLength(A,N);BuildIsolation(M,A);end;
procedure TDisplayManager.IsolateByMaterial(const M:TFEMModel; MaterialID:Integer);
var I,N:Integer; A:array of Integer;
begin SetLength(A,Length(M.Elements));N:=0;for I:=0 to High(M.Elements) do if M.Elements[I].MaterialID=MaterialID then begin A[N]:=M.Elements[I].ID;Inc(N);end;SetLength(A,N);BuildIsolation(M,A);end;
procedure TDisplayManager.IsolateBySection(const M:TFEMModel; SectionID:Integer);
var I,N:Integer; A:array of Integer;
begin SetLength(A,Length(M.Elements));N:=0;for I:=0 to High(M.Elements) do if M.Elements[I].SectionID=SectionID then begin A[N]:=M.Elements[I].ID;Inc(N);end;SetLength(A,N);BuildIsolation(M,A);end;
procedure TDisplayManager.IsolateByGroup(const M:TFEMModel; GroupID:Integer);
var I,N:Integer; A:array of Integer;
begin SetLength(A,Length(M.Elements));N:=0;for I:=0 to High(M.Elements) do if M.Elements[I].GroupID=GroupID then begin A[N]:=M.Elements[I].ID;Inc(N);end;SetLength(A,N);BuildIsolation(M,A);end;

procedure TDisplayManager.ShowByKind(const M:TFEMModel; const Kind:string);
var I:Integer; begin for I:=0 to High(M.Elements) do if SameText(M.Elements[I].Kind,Kind) then ShowElement(M.Elements[I].ID); end;
procedure TDisplayManager.ShowByMaterial(const M:TFEMModel; MaterialID:Integer);
var I:Integer; begin SetCategoryVisible(FMaterialVisible,MaterialID,True); for I:=0 to High(M.Elements) do if M.Elements[I].MaterialID=MaterialID then ShowElement(M.Elements[I].ID); end;
procedure TDisplayManager.ShowBySection(const M:TFEMModel; SectionID:Integer);
var I:Integer; begin SetCategoryVisible(FSectionVisible,SectionID,True); for I:=0 to High(M.Elements) do if M.Elements[I].SectionID=SectionID then ShowElement(M.Elements[I].ID); end;
procedure TDisplayManager.ShowByGroup(const M:TFEMModel; GroupID:Integer);
var I:Integer; begin SetCategoryVisible(FGroupVisible,GroupID,True); for I:=0 to High(M.Elements) do if M.Elements[I].GroupID=GroupID then ShowElement(M.Elements[I].ID); end;

procedure TDisplayManager.HideByKind(const M:TFEMModel; const Kind:string);
var I:Integer; begin for I:=0 to High(M.Elements) do if SameText(M.Elements[I].Kind,Kind) then HideElement(M.Elements[I].ID); end;
procedure TDisplayManager.HideByMaterial(const M:TFEMModel; MaterialID:Integer);
var I:Integer; begin SetCategoryVisible(FMaterialVisible,MaterialID,False); for I:=0 to High(M.Elements) do if M.Elements[I].MaterialID=MaterialID then HideElement(M.Elements[I].ID); end;
procedure TDisplayManager.HideBySection(const M:TFEMModel; SectionID:Integer);
var I:Integer; begin SetCategoryVisible(FSectionVisible,SectionID,False); for I:=0 to High(M.Elements) do if M.Elements[I].SectionID=SectionID then HideElement(M.Elements[I].ID); end;
procedure TDisplayManager.HideByGroup(const M:TFEMModel; GroupID:Integer);
var I:Integer; begin SetCategoryVisible(FGroupVisible,GroupID,False); for I:=0 to High(M.Elements) do if M.Elements[I].GroupID=GroupID then HideElement(M.Elements[I].ID); end;

procedure TDisplayManager.RestoreIsolation;
begin FIsolatedElements.Clear; FHasIsolation:=False; end;

procedure TDisplayManager.IsolateSelected(const M:TFEMModel; const SelectionIDs:array of Integer);
begin
  IsolateElements(SelectionIDs);
end;
function TDisplayManager.HiddenElementCount:Integer; begin Result:=FHiddenElements.Count; end;
function TDisplayManager.IsolationActive:Boolean; begin Result:=FHasIsolation; end;

end.
