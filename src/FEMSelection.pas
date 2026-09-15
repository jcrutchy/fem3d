unit FEMSelection;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, FEMModel;

type
  TIntArray = array of Integer;
  TSelectionSet = class
  private
    FNodes, FElements: TIntArray;
    function Contains(const A:TIntArray; ID:Integer):Boolean;
    procedure Toggle(var A:TIntArray; ID:Integer);
    procedure Remove(var A:TIntArray; ID:Integer);
  public
    procedure Clear;
    procedure SelectNode(ID:Integer; Additive:Boolean);
    procedure SelectElement(ID:Integer; Additive:Boolean);
    procedure DeselectNode(ID:Integer);
    procedure DeselectElement(ID:Integer);
    function NodeSelected(ID:Integer):Boolean;
    function ElementSelected(ID:Integer):Boolean;
    function NodeCount:Integer;
    function ElementCount:Integer;
    function NodeID(I:Integer):Integer;
    function ElementID(I:Integer):Integer;
    procedure ToggleNode(ID:Integer);
    procedure ToggleElement(ID:Integer);
  end;

implementation

function TSelectionSet.Contains(const A:TIntArray; ID:Integer):Boolean;
var I:Integer;
begin Result:=False; for I:=0 to High(A) do if A[I]=ID then Exit(True); end;

procedure TSelectionSet.Toggle(var A:TIntArray; ID:Integer);
var I,N:Integer;
begin
  if Contains(A,ID) then begin Remove(A,ID); Exit; end;
  N:=Length(A);
  SetLength(A,N+1);
  A[N]:=ID;
end;

procedure TSelectionSet.Remove(var A:TIntArray; ID:Integer);
var I,J:Integer;
begin
  for I:=0 to High(A) do if A[I]=ID then begin
    for J:=I to High(A)-1 do A[J]:=A[J+1];
    SetLength(A,Length(A)-1);Exit;
  end;
end;

procedure TSelectionSet.Clear;
begin SetLength(FNodes,0);SetLength(FElements,0);end;

procedure TSelectionSet.SelectNode(ID:Integer; Additive:Boolean);
begin if not Additive then begin SetLength(FNodes,0);SetLength(FElements,0);end; if not Contains(FNodes,ID) then begin SetLength(FNodes,Length(FNodes)+1);FNodes[High(FNodes)]:=ID;end;end;

procedure TSelectionSet.SelectElement(ID:Integer; Additive:Boolean);
begin if not Additive then begin SetLength(FNodes,0);SetLength(FElements,0);end; if not Contains(FElements,ID) then begin SetLength(FElements,Length(FElements)+1);FElements[High(FElements)]:=ID;end;end;

procedure TSelectionSet.ToggleNode(ID:Integer); begin Toggle(FNodes,ID); end;
procedure TSelectionSet.ToggleElement(ID:Integer); begin Toggle(FElements,ID); end;
procedure TSelectionSet.DeselectNode(ID:Integer);begin Remove(FNodes,ID);end;
procedure TSelectionSet.DeselectElement(ID:Integer);begin Remove(FElements,ID);end;
function TSelectionSet.NodeSelected(ID:Integer):Boolean;begin Result:=Contains(FNodes,ID);end;
function TSelectionSet.ElementSelected(ID:Integer):Boolean;begin Result:=Contains(FElements,ID);end;
function TSelectionSet.NodeCount:Integer;begin Result:=Length(FNodes);end;
function TSelectionSet.ElementCount:Integer;begin Result:=Length(FElements);end;
function TSelectionSet.NodeID(I:Integer):Integer;begin Result:=FNodes[I];end;
function TSelectionSet.ElementID(I:Integer):Integer;begin Result:=FElements[I];end;

end.

