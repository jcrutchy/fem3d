unit FEMTypes;
{$mode objfpc}{$H+}

interface

uses Math;

type
  TVec3 = record
    X, Y, Z: Double;
  end;

  TMat3 = array[0..2,0..2] of Double;

  TDofVector = array[0..5] of Double;
  TDofMask = array[0..5] of Boolean;

  TElementKind = (ekUnknown, ekBeam3D, ekTri3Membrane);

function Vec3(AX,AY,AZ:Double):TVec3; inline;
function VAdd(const A,B:TVec3):TVec3; inline;
function VSub(const A,B:TVec3):TVec3; inline;
function VScale(const A:TVec3; S:Double):TVec3; inline;
function VDot(const A,B:TVec3):Double; inline;
function VCross(const A,B:TVec3):TVec3; inline;
function VNorm(const A:TVec3):Double; inline;
function VUnit(const A:TVec3):TVec3; inline;

function Identity3:TMat3;
function Mat3Vec(const A:TMat3; const V:TVec3):TVec3;
function Mat3Transpose(const A:TMat3):TMat3;

implementation

function Vec3(AX,AY,AZ:Double):TVec3;
begin Result.X:=AX; Result.Y:=AY; Result.Z:=AZ; end;

function VAdd(const A,B:TVec3):TVec3;
begin Result.X:=A.X+B.X; Result.Y:=A.Y+B.Y; Result.Z:=A.Z+B.Z; end;

function VSub(const A,B:TVec3):TVec3;
begin Result.X:=A.X-B.X; Result.Y:=A.Y-B.Y; Result.Z:=A.Z-B.Z; end;

function VScale(const A:TVec3; S:Double):TVec3;
begin Result.X:=A.X*S; Result.Y:=A.Y*S; Result.Z:=A.Z*S; end;

function VDot(const A,B:TVec3):Double;
begin
  {$IF Defined(CPUX86_64)}
  asm
    movsd xmm0,[A]
    mulsd xmm0,[B]
    movsd xmm1,[A+8]
    mulsd xmm1,[B+8]
    addsd xmm0,xmm1
    movsd xmm1,[A+16]
    mulsd xmm1,[B+16]
    addsd xmm0,xmm1
    movsd Result,xmm0
  end;
  {$ELSE}
  Result:=A.X*B.X+A.Y*B.Y+A.Z*B.Z;
  {$ENDIF}
end;

function VCross(const A,B:TVec3):TVec3;
begin
  Result.X:=A.Y*B.Z-A.Z*B.Y;
  Result.Y:=A.Z*B.X-A.X*B.Z;
  Result.Z:=A.X*B.Y-A.Y*B.X;
end;

function VNorm(const A:TVec3):Double;
begin Result:=Sqrt(VDot(A,A)); end;

function VUnit(const A:TVec3):TVec3;
var N:Double;
begin
  N:=VNorm(A);
  if N>1e-30 then Result:=VScale(A,1/N)
  else Result:=Vec3(1,0,0);
end;

function Identity3:TMat3;
var I:Integer;
begin
  FillChar(Result,SizeOf(Result),0);
  for I:=0 to 2 do Result[I,I]:=1;
end;

function Mat3Vec(const A:TMat3; const V:TVec3):TVec3;
begin
  Result.X:=A[0,0]*V.X+A[0,1]*V.Y+A[0,2]*V.Z;
  Result.Y:=A[1,0]*V.X+A[1,1]*V.Y+A[1,2]*V.Z;
  Result.Z:=A[2,0]*V.X+A[2,1]*V.Y+A[2,2]*V.Z;
end;

function Mat3Transpose(const A:TMat3):TMat3;
var I,J:Integer;
begin for I:=0 to 2 do for J:=0 to 2 do Result[I,J]:=A[J,I]; end;

end.
