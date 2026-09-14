unit FEMVerification;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, FEMTypes, FEMModel, FEMElements, FEMMatrix, FEMAnalysis, FEMValidation, FEMAnalysisCases, FEMIO, FEMHash, FEMResults, FEMResultFields, FEMDisplayManager;

type
  TVerificationResult = record
    Name:string;
    Passed:Boolean;
    Expected,Actual,RelativeError,Tolerance:Double;
    MessageText:string;
  end;

  TFEMVerification = class
  private
    class function BuildCantilever(out M:TFEMModel; out R:TElementRegistry; out S:TFEMSolver;
      out Engine:TAnalysisEngine; out Node1,Node2,LC:Integer):Boolean;
    class function RunScalar(const Name:string; Expected,Actual,Tol:Double; out V:TVerificationResult):Boolean;
  public
    class function CantileverTipDisplacement(out V:TVerificationResult):Boolean;
    class function CantileverTipDisplacementY(out V:TVerificationResult):Boolean;
    class function CantileverAxialDisplacement(out V:TVerificationResult):Boolean;
    class function CantileverTorsion(out V:TVerificationResult):Boolean;
    class function CantileverReactionEquilibrium(out V:TVerificationResult):Boolean;
    class function MechanismDetection(out V:TVerificationResult):Boolean;
    class function ModelValidation(out V:TVerificationResult):Boolean;
    class function BeamStiffnessSymmetry(out V:TVerificationResult):Boolean;
    class function EnergyBalance(out V:TVerificationResult):Boolean;
    class function BeamEndForceRecovery(out V:TVerificationResult):Boolean;
    class function AuditTrailRetention(out V:TVerificationResult):Boolean;
    class function AnalysisCasePersistence(out V:TVerificationResult):Boolean;
    class function FingerprintSensitivity(out V:TVerificationResult):Boolean;
    class function ResultExpression(out V:TVerificationResult):Boolean;
    class function DisplayManagerVisibility(out V:TVerificationResult):Boolean;
  end;

implementation

class function TFEMVerification.ResultExpression(out V:TVerificationResult):Boolean;
var Fields:TResultFieldCollection; F:TResultField; E:TResultExpressionEvaluator; X,Expected:Double; Err:string;
begin
  Fields:=TResultFieldCollection.Create; try
    F:=TResultField.Create('UX','UX','m',rlNode); SetLength(F.EntityIDs,2);SetLength(F.Values,2);F.EntityIDs[0]:=10;F.EntityIDs[1]:=20;F.Values[0]:=0.002;F.Values[1]:=-0.003;Fields.Add(F);
    F:=TResultField.Create('UY','UY','m',rlNode); SetLength(F.EntityIDs,2);SetLength(F.Values,2);F.EntityIDs[0]:=10;F.EntityIDs[1]:=20;F.Values[0]:=0.004;F.Values[1]:=0.000;Fields.Add(F);
    E:=TResultExpressionEvaluator.Create(Fields); try
      Expected:=Sqrt(Sqr(0.002)+Sqr(0.004)); if not E.Evaluate('SQRT(UX*UX+UY*UY)',rlNode,10,X,Err) then begin V.Name:='Result expression evaluator';V.MessageText:=Err;Exit(False);end; Result:=RunScalar('Result expression evaluator',Expected,X,1e-12,V);
    finally E.Free end;
  finally Fields.Free end;
end;


class function TFEMVerification.DisplayManagerVisibility(out V:TVerificationResult):Boolean;
var M:TFEMModel; D:TDisplayManager; Mat1,Mat2,Sec,G1,G2,N1,N2,N3:Integer; I1,I2:Integer;
begin
  M:=TFEMModel.Create; D:=TDisplayManager.Create;
  try
    Mat1:=M.AddMaterial('Steel A',200e9,0.3,7850); Mat2:=M.AddMaterial('Steel B',210e9,0.3,7850);
    Sec:=M.AddSection('Section',0.01,8e-6,3e-6,1e-6); G1:=M.AddGroup('Group A'); G2:=M.AddGroup('Group B');
    N1:=M.AddNode(Vec3(0,0,0)); N2:=M.AddNode(Vec3(1,0,0)); N3:=M.AddNode(Vec3(2,0,0));
    I1:=M.AddElement('BEAM3D',[N1,N2],Mat1,Sec,0,0,G1); I2:=M.AddElement('BEAM3D',[N2,N3],Mat2,Sec,0,0,G2);
    V.Name:='Display manager visibility, hide/show and isolation'; V.Expected:=0; V.Actual:=0; V.Tolerance:=0; V.RelativeError:=0;
    if not D.IsElementVisible(M.Elements[0]) or not D.IsElementVisible(M.Elements[1]) then begin V.Passed:=False; V.MessageText:='Initial visibility failed.'; Exit(False); end;
    D.HideByGroup(M,G1); if D.IsElementVisible(M.Elements[0]) or not D.IsElementVisible(M.Elements[1]) then begin V.Passed:=False; V.MessageText:='Hide by group failed.'; Exit(False); end;
    D.ShowByGroup(M,G1); if not D.IsElementVisible(M.Elements[0]) then begin V.Passed:=False; V.MessageText:='Show by group failed.'; Exit(False); end;
    D.IsolateByMaterial(M,Mat2); if D.IsElementVisible(M.Elements[0]) or not D.IsElementVisible(M.Elements[1]) then begin V.Passed:=False; V.MessageText:='Material isolation failed.'; Exit(False); end;
    D.RestoreIsolation; if not D.IsElementVisible(M.Elements[0]) or not D.IsElementVisible(M.Elements[1]) then begin V.Passed:=False; V.MessageText:='Isolation restore failed.'; Exit(False); end;
    D.HideElement(I1); if D.IsNodeVisible(M,N1) or not D.IsNodeVisible(M,N3) then begin V.Passed:=False; V.MessageText:='Node visibility propagation failed.'; Exit(False); end;
    D.ShowElement(I1); V.Passed:=D.IsElementVisible(M.Elements[0]) and D.IsElementVisible(M.Elements[1]);
    V.MessageText:='Hide/show, property isolation and node visibility propagation verified.'; Result:=V.Passed;
  finally D.Free; M.Free; end;
end;

class function TFEMVerification.RunScalar(const Name:string; Expected,Actual,Tol:Double; out V:TVerificationResult):Boolean;
begin
  V.Name:=Name; V.Expected:=Expected; V.Actual:=Actual; V.Tolerance:=Tol; V.RelativeError:=Abs(Actual-Expected)/Max(Abs(Expected),1e-300);
  V.Passed:=V.RelativeError<=Tol;
  V.MessageText:=Format('expected %.12g, actual %.12g, relative error %.6g, tolerance %.6g',[Expected,Actual,V.RelativeError,Tol]);
  Result:=V.Passed;
end;

class function TFEMVerification.BuildCantilever(out M:TFEMModel; out R:TElementRegistry; out S:TFEMSolver;
  out Engine:TAnalysisEngine; out Node1,Node2,LC:Integer):Boolean;
var Mat,Sec:Integer;
begin
  M:=TFEMModel.Create; R:=TElementRegistry.Create; S:=TDenseLDLTSolver.Create; Engine:=nil;
  RegisterBuiltInElements(R);
  Mat:=M.AddMaterial('Steel',200e9,0.3,7850);
  Sec:=M.AddSection('Section',0.01,8e-6,3e-6,1e-6);
  LC:=M.AddLoadCase('Verification'); Node1:=M.AddNode(Vec3(0,0,0)); Node2:=M.AddNode(Vec3(5,0,0));
  FillChar(M.Nodes[0].Restraint,SizeOf(TDofMask),1);
  M.AddElement('BEAM3D',[Node1,Node2],Mat,Sec,0,0,0);
  Engine:=TAnalysisEngine.Create(M,R,S); Result:=True;
end;

class function TFEMVerification.CantileverTipDisplacement(out V:TVerificationResult):Boolean;
var M:TFEMModel;R:TElementRegistry;S:TFEMSolver;E:TAnalysisEngine;N1,N2,LC:Integer;L,P,Expected:Double;Load:TDofVector;X:TAnalysisResult;Setup:TAnalysisSetup;
begin
  Result:=False; if not BuildCantilever(M,R,S,E,N1,N2,LC) then Exit;
  try
    FillChar(Load,SizeOf(Load),0); Load[2]:=-10000; M.AddNodalLoad(N2,LC,Load);
    Setup.LoadCaseID:=LC; Setup.SolverName:=S.Name; Setup.Options.PivotTolerance:=1e-12; Setup.Options.ComputeResidual:=True;
    X:=E.Solve(Setup); try
      if not X.Success then begin V.Name:='3D beam cantilever — tip Z displacement'; V.MessageText:=X.MessageText; Exit; end;
      L:=5;P:=10000;Expected:=-P*L*L*L/(3*200e9*8e-6);
      V.Name:='3D beam cantilever — tip Z displacement'; Result:=RunScalar(V.Name,Expected,X.U[(M.FindNode(N2))*6+2],1e-8,V);
      if X.ResidualNorm>1e-10 then begin V.Passed:=False; V.MessageText:=V.MessageText+Format('; residual %.6g',[X.ResidualNorm]); Result:=False; end;
    finally X.Free; end;
  finally E.Free;S.Free;R.Free;M.Free;end;
end;

class function TFEMVerification.CantileverTipDisplacementY(out V:TVerificationResult):Boolean;
var M:TFEMModel;R:TElementRegistry;S:TFEMSolver;E:TAnalysisEngine;N1,N2,LC:Integer;Expected:Double;Load:TDofVector;X:TAnalysisResult;Setup:TAnalysisSetup;
begin
  Result:=False; BuildCantilever(M,R,S,E,N1,N2,LC); try
    FillChar(Load,SizeOf(Load),0); Load[1]:=-10000; M.AddNodalLoad(N2,LC,Load);
    Setup.LoadCaseID:=LC; Setup.SolverName:=S.Name; Setup.Options.PivotTolerance:=1e-12; Setup.Options.ComputeResidual:=True; X:=E.Solve(Setup);
    try if not X.Success then begin V.Name:='Cantilever Y bending'; V.MessageText:=X.MessageText; Exit; end;
      Expected:=-10000*Sqr(5)*5/(3*200e9*3e-6); Result:=RunScalar('3D beam cantilever — tip Y displacement',Expected,X.U[M.FindNode(N2)*6+1],1e-8,V);
    finally X.Free; end;
  finally E.Free;S.Free;R.Free;M.Free;end;
end;

class function TFEMVerification.CantileverAxialDisplacement(out V:TVerificationResult):Boolean;
var M:TFEMModel;R:TElementRegistry;S:TFEMSolver;E:TAnalysisEngine;N1,N2,LC:Integer;Expected:Double;Load:TDofVector;X:TAnalysisResult;Setup:TAnalysisSetup;
begin
  Result:=False; BuildCantilever(M,R,S,E,N1,N2,LC); try
    FillChar(Load,SizeOf(Load),0); Load[0]:=10000; M.AddNodalLoad(N2,LC,Load);
    Setup.LoadCaseID:=LC; Setup.SolverName:=S.Name; Setup.Options.PivotTolerance:=1e-12; Setup.Options.ComputeResidual:=True; X:=E.Solve(Setup);
    try if not X.Success then begin V.Name:='Cantilever axial'; V.MessageText:=X.MessageText; Exit; end;
      Expected:=10000*5/(200e9*0.01); Result:=RunScalar('3D beam cantilever — axial displacement',Expected,X.U[M.FindNode(N2)*6],1e-9,V);
    finally X.Free; end;
  finally E.Free;S.Free;R.Free;M.Free;end;
end;

class function TFEMVerification.CantileverTorsion(out V:TVerificationResult):Boolean;
var M:TFEMModel;R:TElementRegistry;S:TFEMSolver;E:TAnalysisEngine;N1,N2,LC:Integer;G,J,L,T,Expected:Double;Load:TDofVector;X:TAnalysisResult;Setup:TAnalysisSetup;
begin
  Result:=False; BuildCantilever(M,R,S,E,N1,N2,LC); try
    FillChar(Load,SizeOf(Load),0); Load[3]:=10000; M.AddNodalLoad(N2,LC,Load);
    Setup.LoadCaseID:=LC; Setup.SolverName:=S.Name; Setup.Options.PivotTolerance:=1e-12; Setup.Options.ComputeResidual:=True; X:=E.Solve(Setup);
    try if not X.Success then begin V.Name:='Cantilever torsion'; V.MessageText:=X.MessageText; Exit; end;
      G:=200e9/(2*(1+0.3)); J:=1e-6; L:=5; T:=10000; Expected:=T*L/(G*J);
      Result:=RunScalar('3D beam cantilever — torsional rotation',Expected,X.U[M.FindNode(N2)*6+3],1e-8,V);
    finally X.Free; end;
  finally E.Free;S.Free;R.Free;M.Free;end;
end;

class function TFEMVerification.CantileverReactionEquilibrium(out V:TVerificationResult):Boolean;
var M:TFEMModel;R:TElementRegistry;S:TFEMSolver;E:TAnalysisEngine;N1,N2,LC:Integer;Load:TDofVector;X:TAnalysisResult;Setup:TAnalysisSetup;Eq:Double;
begin
  Result:=False; BuildCantilever(M,R,S,E,N1,N2,LC); try
    FillChar(Load,SizeOf(Load),0); Load[2]:=-10000; M.AddNodalLoad(N2,LC,Load);
    Setup.LoadCaseID:=LC; Setup.SolverName:=S.Name; Setup.Options.PivotTolerance:=1e-12; Setup.Options.ComputeResidual:=True; X:=E.Solve(Setup);
    try
      if not X.Success then begin V.Name:='Reaction equilibrium'; V.MessageText:=X.MessageText; Exit; end;
      Eq:=X.Reactions[0*6+2]; Result:=RunScalar('Fixed support Z reaction — global equilibrium',10000,Eq,1e-10,V);
      if X.ResidualNorm>1e-10 then begin V.Passed:=False; V.MessageText:=V.MessageText+Format('; free-equation residual %.6g',[X.ResidualNorm]); Result:=False; end;
    finally X.Free; end;
  finally E.Free;S.Free;R.Free;M.Free;end;
end;

class function TFEMVerification.MechanismDetection(out V:TVerificationResult):Boolean;
var M:TFEMModel;R:TElementRegistry;S:TFEMSolver;E:TAnalysisEngine;N1,N2,LC,Mat,Sec:Integer;Load:TDofVector;X:TAnalysisResult;Setup:TAnalysisSetup;
begin
  M:=TFEMModel.Create; R:=TElementRegistry.Create; S:=TDenseLDLTSolver.Create; E:=nil;
  try
    RegisterBuiltInElements(R); Mat:=M.AddMaterial('Steel',200e9,0.3,7850); Sec:=M.AddSection('Section',0.01,8e-6,3e-6,1e-6);
    LC:=M.AddLoadCase('Mechanism'); N1:=M.AddNode(Vec3(0,0,0)); N2:=M.AddNode(Vec3(5,0,0)); M.AddElement('BEAM3D',[N1,N2],Mat,Sec,0,0,0);
    FillChar(Load,SizeOf(Load),0); Load[0]:=1; M.AddNodalLoad(N2,LC,Load); E:=TAnalysisEngine.Create(M,R,S);
    Setup.LoadCaseID:=LC; Setup.SolverName:=S.Name; Setup.Options.PivotTolerance:=1e-12; Setup.Options.ComputeResidual:=True; X:=E.Solve(Setup);
    V.Name:='Rigid-body mechanism detection'; V.Expected:=0; V.Actual:=0; V.Tolerance:=0; V.RelativeError:=0;
    V.Passed:=not X.Success; if X.Success then V.MessageText:='Solver unexpectedly accepted an unconstrained rigid-body model.' else V.MessageText:='Correctly rejected singular system: '+X.MessageText; Result:=V.Passed;
    X.Free;
  finally E.Free;S.Free;R.Free;M.Free;end;
end;

class function TFEMVerification.ModelValidation(out V:TVerificationResult):Boolean;
var M:TFEMModel;Mat,Sec,N1,N2:Integer; Rep:TFEMValidationReport;
begin
  M:=TFEMModel.Create; Rep:=TFEMValidationReport.Create; try
    Mat:=M.AddMaterial('Bad',-1,0.3,7850); Sec:=M.AddSection('Bad',0,1,1,1); N1:=M.AddNode(Vec3(0,0,0)); N2:=M.AddNode(Vec3(0,0,0)); M.AddElement('BEAM3D',[N1,N2],Mat,Sec,0,0,0);
    V.Name:='Model validation catches invalid properties and geometry'; V.Expected:=0; V.Actual:=Rep.ErrorCount; V.Tolerance:=0; V.RelativeError:=0; Rep.Validate(M);
    V.Actual:=Rep.ErrorCount; V.Passed:=V.Actual>=3; V.MessageText:=Format('validation returned %d errors and %d warnings',[Rep.ErrorCount,Rep.WarningCount]); Result:=V.Passed;
  finally Rep.Free;M.Free;end;
end;

class function TFEMVerification.BeamStiffnessSymmetry(out V:TVerificationResult):Boolean;
var M:TFEMModel;R:TElementRegistry;N:TDOFNumbering;C:TElementContext;ER:TElementRecord;B:TFEMElement;Ke:array of Double;I,J:Integer;Diff,Scale,Ener,S:Double;U:array of Double;
begin
  M:=TFEMModel.Create; R:=TElementRegistry.Create; N:=nil;
  try
    RegisterBuiltInElements(R);
    M.AddMaterial('Steel',200e9,0.3,7850); M.AddSection('Section',0.01,8e-6,3e-6,1e-6);
    M.AddNode(Vec3(0,0,0)); M.AddNode(Vec3(5,1,0.5)); M.AddElement('BEAM3D',[1,2],1,1,0,0,0);
    N:=M.CreateDOFNumbering; C.Model:=M; C.Numbering:=N; ER:=M.Elements[0]; B:=R.Find('BEAM3D'); SetLength(Ke,144); B.Stiffness(C,ER,Ke);
    Diff:=0; Scale:=0; for I:=0 to 11 do for J:=0 to 11 do begin if Abs(Ke[I*12+J])>Scale then Scale:=Abs(Ke[I*12+J]); if Abs(Ke[I*12+J]-Ke[J*12+I])>Diff then Diff:=Abs(Ke[I*12+J]-Ke[J*12+I]); end;
    SetLength(U,12); for I:=0 to 11 do U[I]:=0.01*(I+1); Ener:=0; for I:=0 to 11 do begin S:=0; for J:=0 to 11 do S:=S+Ke[I*12+J]*U[J]; Ener:=Ener+U[I]*S; end;
    V.Name:='BEAM3D stiffness symmetry and positive energy'; V.Expected:=0; V.Actual:=Diff/Max(Scale,1); V.Tolerance:=1e-12; V.RelativeError:=V.Actual; V.Passed:=(V.Actual<=V.Tolerance) and (Ener>0);
    V.MessageText:=Format('relative symmetry error %.6g; strain-energy quadratic form %.12g',[V.Actual,Ener]); Result:=V.Passed;
  finally N.Free;R.Free;M.Free;end;
end;

class function TFEMVerification.EnergyBalance(out V:TVerificationResult):Boolean;
var M:TFEMModel;R:TElementRegistry;S:TFEMSolver;E:TAnalysisEngine;N1,N2,LC:Integer;Load:TDofVector;X:TAnalysisResult;Setup:TAnalysisSetup;
begin
  Result:=False; if not BuildCantilever(M,R,S,E,N1,N2,LC) then Exit;
  try
    FillChar(Load,SizeOf(Load),0); Load[2]:=-10000; M.AddNodalLoad(N2,LC,Load);
    Setup.LoadCaseID:=LC; Setup.SolverName:=S.Name; Setup.Options.PivotTolerance:=1e-12; Setup.Options.ComputeResidual:=True; X:=E.Solve(Setup);
    try
      V.Name:='Global energy balance'; V.Expected:=0; V.Actual:=X.EnergyBalanceError; V.Tolerance:=1e-10; V.RelativeError:=X.EnergyBalanceError; V.Passed:=X.Success and (V.Actual<=V.Tolerance);
      V.MessageText:=Format('strain energy %.12g; external work %.12g; relative energy error %.6g',[X.StrainEnergy,X.ExternalWork,V.Actual]); Result:=V.Passed;
    finally X.Free end;
  finally E.Free;S.Free;R.Free;M.Free end;
end;

class function TFEMVerification.BeamEndForceRecovery(out V:TVerificationResult):Boolean;
var M:TFEMModel;R:TElementRegistry;S:TFEMSolver;E:TAnalysisEngine;N1,N2,LC:Integer;Load:TDofVector;X:TAnalysisResult;Setup:TAnalysisSetup;C:TElementContext;N:TDOFNumbering;F:TBeamEndForces;B:TBeam3D;ER:TElementRecord;Err:Double;
begin
  Result:=False; if not BuildCantilever(M,R,S,E,N1,N2,LC) then Exit;
  try
    FillChar(Load,SizeOf(Load),0); Load[2]:=-10000; M.AddNodalLoad(N2,LC,Load); Setup.LoadCaseID:=LC; Setup.SolverName:=S.Name; Setup.Options.PivotTolerance:=1e-12; Setup.Options.ComputeResidual:=True; X:=E.Solve(Setup);
    try
      N:=M.CreateDOFNumbering; try C.Model:=M; C.Numbering:=N; ER:=M.Elements[0]; B:=TBeam3D(R.Find('BEAM3D'));
        if not B.RecoverEndForces(C,ER,X.U,F) then begin V.Name:='Beam local end-force recovery'; V.Passed:=False; V.MessageText:='Recovery routine failed.'; Exit; end;
        Err:=Max(Abs(F.Node2[2]+10000),Abs(F.Node1[2]-10000));
        V.Name:='Beam local end-force recovery'; V.Expected:=0; V.Actual:=Err/10000; V.Tolerance:=1e-10; V.RelativeError:=V.Actual; V.Passed:=X.Success and (V.Actual<=V.Tolerance);
        V.MessageText:=Format('tip local/global force component %.12g; fixed-end component %.12g; relative error %.6g',[F.Node2[2],F.Node1[2],V.Actual]); Result:=V.Passed;
      finally N.Free end;
    finally X.Free end;
  finally E.Free;S.Free;R.Free;M.Free end;
end;

class function TFEMVerification.AuditTrailRetention(out V:TVerificationResult):Boolean;
var M:TFEMModel;R:TElementRegistry;S:TFEMSolver;E:TAnalysisEngine;N1,N2,LC:Integer;Load:TDofVector;X:TAnalysisResult;Setup:TAnalysisSetup;
begin
  Result:=False; if not BuildCantilever(M,R,S,E,N1,N2,LC) then Exit;
  try
    FillChar(Load,SizeOf(Load),0); Load[2]:=-10000; M.AddNodalLoad(N2,LC,Load); Setup.LoadCaseID:=LC; Setup.SolverName:=S.Name; Setup.Options.PivotTolerance:=1e-12; Setup.Options.ComputeResidual:=True; X:=E.Solve(Setup);
    try
      V.Name:='Structured analysis audit trail retention'; V.Expected:=1; V.Actual:=X.AuditTrail.Count; V.Tolerance:=0; V.RelativeError:=0;
      V.Passed:=X.Success and (X.AuditTrail.Count>=5); V.MessageText:=Format('retained %d audit records',[X.AuditTrail.Count]); Result:=V.Passed;
    finally X.Free end;
  finally E.Free;S.Free;R.Free;M.Free end;
end;

class function TFEMVerification.AnalysisCasePersistence(out V:TVerificationResult):Boolean;
var M,NM:TFEMModel; A,B:TAnalysisCase; F:string; S1,S2:TStringList;
begin
  Result:=False; M:=TFEMModel.Create; NM:=TFEMModel.Create; S1:=TStringList.Create; S2:=TStringList.Create;
  try
    A:=M.AnalysisCases.Add(atLinearStatic,'Persistent Static'); A.LoadCaseID:=7;
    with TLinearStaticSettings(A.Settings) do begin MatrixStorage:=msSkyline; PivotTolerance:=2e-11; ResidualTolerance:=3e-9; CheckEquilibrium:=False; end;
    B:=M.AnalysisCases.Add(atLinearBuckling,'Persistent Buckling'); B.LoadCaseID:=8;
    with TBucklingSettings(B.Settings) do begin EigenvalueCount:=12; Shift:=0.25; Tolerance:=2e-7; MaxIterations:=321; NormalizeModes:=False; end;
    F:=IncludeTrailingPathDelimiter(GetTempDir)+'fem3d_analysis_persistence.fem3d';
    TFEMNativeIO.SaveModel(M,F); TFEMNativeIO.LoadModel(NM,F);
    V.Name:='Persistent analysis cases and solver settings'; V.Expected:=0; V.Actual:=0; V.Tolerance:=0; V.RelativeError:=0;
    if NM.AnalysisCases.Count<>2 then begin V.Passed:=False; V.MessageText:='Expected two analysis cases after reload.'; Exit; end;
    A:=NM.AnalysisCases.Find(1); B:=NM.AnalysisCases.Find(2);
    V.Passed:=(A<>nil) and (B<>nil) and (A.Name='Persistent Static') and (A.LoadCaseID=7) and
      (TLinearStaticSettings(A.Settings).MatrixStorage=msSkyline) and
      SameValue(TLinearStaticSettings(A.Settings).PivotTolerance,2e-11,1e-20) and
      (not TLinearStaticSettings(A.Settings).CheckEquilibrium) and
      (B.AnalysisType=atLinearBuckling) and (TBucklingSettings(B.Settings).EigenvalueCount=12) and
      SameValue(TBucklingSettings(B.Settings).Shift,0.25,1e-14) and (not TBucklingSettings(B.Settings).NormalizeModes);
    if V.Passed then V.MessageText:='Linear Static and Linear Buckling definitions survived native save/load with solver settings intact.'
    else V.MessageText:='Analysis case settings changed during native save/load.'; Result:=V.Passed;
    DeleteFile(F);
  finally S2.Free;S1.Free;NM.Free;M.Free end;
end;

class function TFEMVerification.FingerprintSensitivity(out V:TVerificationResult):Boolean;
var M:TFEMModel; A,B:string; L:TDofVector; N,LC:Integer;
begin
  M:=TFEMModel.Create; try
    N:=M.AddNode(Vec3(0,0,0)); LC:=M.AddLoadCase('LC1'); A:=ModelFingerprint(M);
    FillChar(M.Nodes[0].Restraint,SizeOf(TDofMask),0); M.Nodes[0].Restraint[0]:=True; B:=ModelFingerprint(M);
    if A=B then begin V.Name:='Model fingerprint includes restraints and loads'; V.Passed:=False; V.MessageText:='Fingerprint did not change after restraint modification.'; Exit(False); end;
    FillChar(L,SizeOf(L),0); L[0]:=123.456; M.AddNodalLoad(N,LC,L); A:=ModelFingerprint(M);
    if A=B then begin V.Name:='Model fingerprint includes restraints and loads'; V.Passed:=False; V.MessageText:='Fingerprint did not change after load modification.'; Exit(False); end;
    V.Name:='Model fingerprint includes restraints and loads'; V.Passed:=True; V.Expected:=1; V.Actual:=1; V.Tolerance:=0; V.RelativeError:=0; V.MessageText:='Fingerprint changed for both boundary-condition and load changes.'; Result:=True;
  finally M.Free end;
end;

end.
