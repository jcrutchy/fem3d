unit FEMFastMath;
{$mode objfpc}{$H+}

interface

function FEMDot(N:Integer; A,B:PDouble):Double;
function FEMDot3(N:Integer; A,B,D:PDouble):Double;
function FEMDot3Strided(N:Integer; A,B,D:PDouble; StrideA,StrideB,StrideD:Integer):Double;

procedure FEMAxpy(N:Integer; Alpha:Double; X,Y:PDouble);

implementation

function FEMDot3Strided(N:Integer; A,B,D:PDouble; StrideA,StrideB,StrideD:Integer):Double;
var
  I:Integer;
  S0,S1,S2,S3:Double;
begin
  if N<=0 then begin Result:=0; Exit; end;
  S0:=0; S1:=0; S2:=0; S3:=0;
  I:=0;
  while I<=N-4 do begin
    S0:=S0+A[I*StrideA]*B[I*StrideB]*D[I*StrideD];
    S1:=S1+A[(I+1)*StrideA]*B[(I+1)*StrideB]*D[(I+1)*StrideD];
    S2:=S2+A[(I+2)*StrideA]*B[(I+2)*StrideB]*D[(I+2)*StrideD];
    S3:=S3+A[(I+3)*StrideA]*B[(I+3)*StrideB]*D[(I+3)*StrideD];
    Inc(I,4);
  end;
  Result:=S0+S1+S2+S3;
  while I<N do begin
    Result:=Result+A[I*StrideA]*B[I*StrideB]*D[I*StrideD];
    Inc(I);
  end;
end;

function FEMDot(N:Integer; A,B:PDouble):Double;
var
  I:Integer;
  S0,S1,S2,S3:Double;
begin
  if N<=0 then begin Result:=0; Exit; end;
  S0:=0; S1:=0; S2:=0; S3:=0;
  I:=0;
  while I<=N-4 do begin
    S0:=S0+A[I]*B[I];
    S1:=S1+A[I+1]*B[I+1];
    S2:=S2+A[I+2]*B[I+2];
    S3:=S3+A[I+3]*B[I+3];
    Inc(I,4);
  end;
  Result:=S0+S1+S2+S3;
  while I<N do begin
    Result:=Result+A[I]*B[I];
    Inc(I);
  end;
end;

function FEMDot3(N:Integer; A,B,D:PDouble):Double;
var
  I:Integer;
  S0,S1,S2,S3:Double;
begin
  if N<=0 then begin Result:=0; Exit; end;
  S0:=0; S1:=0; S2:=0; S3:=0;
  I:=0;
  while I<=N-4 do begin
    S0:=S0+A[I]*B[I]*D[I];
    S1:=S1+A[I+1]*B[I+1]*D[I+1];
    S2:=S2+A[I+2]*B[I+2]*D[I+2];
    S3:=S3+A[I+3]*B[I+3]*D[I+3];
    Inc(I,4);
  end;
  Result:=S0+S1+S2+S3;
  while I<N do begin
    Result:=Result+A[I]*B[I]*D[I];
    Inc(I);
  end;
end;

procedure FEMAxpy(N:Integer; Alpha:Double; X,Y:PDouble);
var
  I:Integer;
begin
  if (N<=0) or (Alpha=0) then Exit;
  I:=0;
  while I<=N-4 do begin
    Y[I]:=Y[I]+Alpha*X[I];
    Y[I+1]:=Y[I+1]+Alpha*X[I+1];
    Y[I+2]:=Y[I+2]+Alpha*X[I+2];
    Y[I+3]:=Y[I+3]+Alpha*X[I+3];
    Inc(I,4);
  end;
  while I<N do begin
    Y[I]:=Y[I]+Alpha*X[I];
    Inc(I);
  end;
end;

end.
