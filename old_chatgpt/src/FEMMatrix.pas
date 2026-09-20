unit FEMMatrix;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, FEMFastMath;

type
  TMatrixStorageKind = (msDense, msSkyline);

  TGlobalSystem = class
  private
    FOriginalK, FOriginalF:array of Double;
    FOriginalCaptured:Boolean;
    FConstrained:array of Boolean;
    procedure CaptureOriginal;
  public
    N:Integer;
    K,F:array of Double;
    constructor Create(AN:Integer);
    procedure Clear;
    procedure Add(I,J:Integer; Value:Double); inline;
    procedure ApplyZeroConstraint(Equation:Integer);
    function Get(I,J:Integer):Double; inline;
    function OriginalGet(I,J:Integer):Double; inline;
    function OriginalForce(I:Integer):Double; inline;
    function IsConstrained(I:Integer):Boolean; inline;
    function ConstrainedCount:Integer;
    function ResidualNorm(const U:array of Double):Double;
    function EquilibriumResidual(const U:array of Double; Equation:Integer):Double;
    function StrainEnergy(const U:array of Double):Double;
    function ExternalWork(const U:array of Double):Double;
  end;

  TSolverOptions = record
    PivotTolerance:Double;
    ComputeResidual:Boolean;
  end;

  TAnalysisResult = class
  public
    Success:Boolean;
    MessageText:string;
    DOFCount,ConstrainedDOF:Integer;
    ResidualNorm:Double;
    MaxFreeEquationResidual,MaxReaction:Double;
    StrainEnergy,ExternalWork,EnergyBalanceError:Double;
    U:array of Double;
    Reactions:array of Double;
    SolverName:string;
    AnalysisCaseID:Integer;
    AnalysisType:string;
    ModelFingerprint:string;
    AnalysisFingerprint:string;
    AuditTrail:TStringList;
    constructor Create;
    destructor Destroy; override;
  end;

  TFEMSolver = class
  public
    function Name:string; virtual; abstract;
    function StorageKind:TMatrixStorageKind; virtual;
    function Solve(const G:TGlobalSystem; const Options:TSolverOptions):TAnalysisResult; virtual; abstract;
  end;

  TDenseLDLTSolver = class(TFEMSolver)
  public
    function Name:string; override;
    function StorageKind:TMatrixStorageKind; override;
    function Solve(const G:TGlobalSystem; const Options:TSolverOptions):TAnalysisResult; override;
  end;

implementation

constructor TAnalysisResult.Create;
begin
  inherited Create; AuditTrail:=TStringList.Create;
end;

destructor TAnalysisResult.Destroy;
begin
  AuditTrail.Free; inherited Destroy;
end;

constructor TGlobalSystem.Create(AN:Integer);
begin
  inherited Create; N:=AN; SetLength(K,N*N); SetLength(F,N); SetLength(FConstrained,N); Clear;
end;

procedure TGlobalSystem.Clear;
begin
  if Length(K)>0 then FillChar(K[0],Length(K)*SizeOf(Double),0);
  if Length(F)>0 then FillChar(F[0],Length(F)*SizeOf(Double),0);
  if Length(FConstrained)>0 then FillChar(FConstrained[0],Length(FConstrained)*SizeOf(Boolean),0);
  SetLength(FOriginalK,0); SetLength(FOriginalF,0); FOriginalCaptured:=False;
end;

procedure TGlobalSystem.CaptureOriginal;
begin
  if FOriginalCaptured then Exit;
  FOriginalK:=Copy(K); FOriginalF:=Copy(F); FOriginalCaptured:=True;
end;

procedure TGlobalSystem.Add(I,J:Integer; Value:Double); inline;
begin if (I>=0) and (J>=0) and (I<N) and (J<N) then K[I*N+J]:=K[I*N+J]+Value; end;

procedure TGlobalSystem.ApplyZeroConstraint(Equation:Integer);
var J:Integer;
begin
  if (Equation<0) or (Equation>=N) then Exit;
  CaptureOriginal;
  FConstrained[Equation]:=True;
  for J:=0 to N-1 do begin K[Equation*N+J]:=0; K[J*N+Equation]:=0; end;
  K[Equation*N+Equation]:=1; F[Equation]:=0;
end;

function TGlobalSystem.Get(I,J:Integer):Double; inline;
begin Result:=K[I*N+J]; end;
function TGlobalSystem.OriginalGet(I,J:Integer):Double; inline;
begin if FOriginalCaptured then Result:=FOriginalK[I*N+J] else Result:=K[I*N+J]; end;
function TGlobalSystem.OriginalForce(I:Integer):Double; inline;
begin if FOriginalCaptured then Result:=FOriginalF[I] else Result:=F[I]; end;
function TGlobalSystem.IsConstrained(I:Integer):Boolean; inline;
begin Result:=(I>=0) and (I<N) and FConstrained[I]; end;

function TGlobalSystem.ConstrainedCount:Integer;
var I:Integer;
begin Result:=0; for I:=0 to N-1 do if FConstrained[I] then Inc(Result); end;

function TGlobalSystem.ResidualNorm(const U:array of Double):Double;
var I,J:Integer; S,RR,FF:Double;
begin
  RR:=0; FF:=0;
  for I:=0 to N-1 do if not IsConstrained(I) then begin
    S:=0; for J:=0 to N-1 do S:=S+OriginalGet(I,J)*U[J];
    S:=S-OriginalForce(I); RR:=RR+S*S; FF:=FF+Sqr(OriginalForce(I));
  end;
  if FF>0 then Result:=Sqrt(RR/FF) else Result:=Sqrt(RR);
end;

function TGlobalSystem.EquilibriumResidual(const U:array of Double; Equation:Integer):Double;
var J:Integer; S:Double;
begin
  S:=0; if (Equation<0) or (Equation>=N) then Exit(0);
  for J:=0 to N-1 do S:=S+OriginalGet(Equation,J)*U[J];
  Result:=S-OriginalForce(Equation);
end;

function TGlobalSystem.StrainEnergy(const U:array of Double):Double;
var I,J:Integer; S:Double;
begin
  Result:=0;
  for I:=0 to N-1 do begin
    S:=0;
    for J:=0 to N-1 do S:=S+OriginalGet(I,J)*U[J];
    Result:=Result+0.5*U[I]*S;
  end;
end;

function TGlobalSystem.ExternalWork(const U:array of Double):Double;
var I:Integer;
begin
  Result:=0;
  for I:=0 to N-1 do Result:=Result+U[I]*OriginalForce(I);
end;

function TFEMSolver.StorageKind:TMatrixStorageKind; begin Result:=msDense; end;
function TDenseLDLTSolver.Name:string; begin Result:='Reference dense LDL^T'; end;
function TDenseLDLTSolver.StorageKind:TMatrixStorageKind; begin Result:=msDense; end;

function TDenseLDLTSolver.Solve(const G:TGlobalSystem; const Options:TSolverOptions):TAnalysisResult;
var
  A,Y,X:array of Double;
  I,J,K,N:Integer;
  S,RR,NormF,MaxEq,MatrixScale,PivotLimit:Double;
begin
  Result:=TAnalysisResult.Create; Result.SolverName:=Name;
  N:=G.N; Result.DOFCount:=N; Result.ConstrainedDOF:=G.ConstrainedCount;
  SetLength(Result.U,N); SetLength(Result.Reactions,N);
  if N=0 then begin Result.Success:=False; Result.MessageText:='Empty global system.'; Exit; end;
  A:=Copy(G.K); SetLength(Y,N); SetLength(X,N);
  MatrixScale:=0; for I:=0 to N-1 do if Abs(A[I*N+I])>MatrixScale then MatrixScale:=Abs(A[I*N+I]);
  if MatrixScale<=0 then begin Result.Success:=False; Result.MessageText:='Zero global stiffness matrix.'; Exit; end;
  PivotLimit:=Options.PivotTolerance*MatrixScale;

  for I:=0 to N-1 do begin
    for J:=0 to I do begin
      S:=A[I*N+J];
      S:=S-FEMDot3Strided(J,@A[I*N],@A[J*N],@A[0],1,1,N);
      if I=J then begin
        if (IsNan(S) or IsInfinite(S)) or (Abs(S)<PivotLimit) then begin
          Result.Success:=False;
          Result.MessageText:=Format('Singular or ill-conditioned matrix near equation %d; pivot %.6g.',[I+1,S]);
          Exit;
        end;
        A[I*N+I]:=S;
      end else A[I*N+J]:=S/A[J*N+J];
    end;
  end;

  for I:=0 to N-1 do begin
    S:=G.F[I]-FEMDot(I,@A[I*N],@Y[0]); Y[I]:=S;
  end;
  for I:=N-1 downto 0 do begin
    S:=Y[I]; for K:=I+1 to N-1 do S:=S-A[K*N+I]*X[K]; X[I]:=S/A[I*N+I];
  end;

  Result.U:=X;
  for I:=0 to N-1 do Result.Reactions[I]:=0;
  MaxEq:=0; Result.MaxReaction:=0;
  for I:=0 to N-1 do begin
    S:=G.EquilibriumResidual(X,I);
    if G.IsConstrained(I) then begin
      Result.Reactions[I]:=S;
      if Abs(S)>Result.MaxReaction then Result.MaxReaction:=Abs(S);
    end else if Abs(S)>MaxEq then MaxEq:=Abs(S);
  end;
  Result.MaxFreeEquationResidual:=MaxEq;
  Result.StrainEnergy:=G.StrainEnergy(X);
  Result.ExternalWork:=G.ExternalWork(X);
  Result.EnergyBalanceError:=Abs(2*Result.StrainEnergy-Result.ExternalWork)/Max(Abs(Result.ExternalWork),1e-300);
  if Options.ComputeResidual then Result.ResidualNorm:=G.ResidualNorm(X);
  Result.Success:=True;
  Result.MessageText:=Format('Solved successfully; %d DOF, %d constrained DOF.',[N,Result.ConstrainedDOF]);
end;

end.
