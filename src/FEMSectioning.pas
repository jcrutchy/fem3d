unit FEMSectioning;
{$mode objfpc}{$H+}
interface
type
  TClipPlane = record
    Enabled, ShowPlane, Reverse: Boolean;
    NormalX, NormalY, NormalZ, Offset: Double;
  end;
  TClipState = class
  private FPlanes: array[0..3] of TClipPlane;
  public
    constructor Create;
    procedure Reset;
    function Plane(Index: Integer): TClipPlane;
    procedure SetPlane(Index: Integer; const Value: TClipPlane);
    function PointVisible(X,Y,Z: Double): Boolean;
  end;
implementation

uses SysUtils;
constructor TClipState.Create; begin inherited Create; Reset; end;
procedure TClipState.Reset;
var I: Integer;
begin
  for I:=0 to High(FPlanes) do begin
    FPlanes[I].Enabled:=False; FPlanes[I].ShowPlane:=False; FPlanes[I].Reverse:=False;
    FPlanes[I].NormalX:=1; FPlanes[I].NormalY:=0; FPlanes[I].NormalZ:=0; FPlanes[I].Offset:=0;
  end;
end;
function TClipState.Plane(Index: Integer): TClipPlane;
begin
  if (Index<0) or (Index>High(FPlanes)) then raise ERangeError.Create('Clip plane index out of range');
  Result:=FPlanes[Index];
end;
procedure TClipState.SetPlane(Index: Integer; const Value: TClipPlane);
begin
  if (Index<0) or (Index>High(FPlanes)) then raise ERangeError.Create('Clip plane index out of range');
  FPlanes[Index]:=Value;
end;
function TClipState.PointVisible(X,Y,Z: Double): Boolean;
var I: Integer; D: Double;
begin
  Result:=True;
  for I:=0 to High(FPlanes) do if FPlanes[I].Enabled then begin
    D:=FPlanes[I].NormalX*X+FPlanes[I].NormalY*Y+FPlanes[I].NormalZ*Z-FPlanes[I].Offset;
    if FPlanes[I].Reverse then D:=-D;
    if D<0 then Exit(False);
  end;
end;
end.

