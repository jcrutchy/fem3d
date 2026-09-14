program FEM3D_LinStatic;
{$mode objfpc}{$H+}
uses Classes, SysUtils, FEMTypes, FEMModel, FEMElements, FEMMatrix, FEMAnalysisCases, FEMAnalysis, FEMIO, FEM3D_SolverProvenance;

procedure Usage;
begin
  Writeln('FEM3D Linear Static Solver');
  Writeln('Usage: FEM3D_LinStatic.exe [--info] [--validate] [--solve] input.fem3d');
end;

procedure Info;
begin
  Writeln('FEM3D Linear Static Solver');
  Writeln('Version: ',FEM3D_LINSTATIC_VERSION); Writeln('Platform: Windows x64');
  Writeln('Kernel revision: ',FEM3D_LINSTATIC_KERNEL_REVISION); Writeln('Model contract: ',FEM3D_MODEL_CONTRACT); Writeln('Result contract: ',FEM3D_RESULT_CONTRACT);
  Writeln('Analysis: Linear Static'); Writeln('Reference solver: dense LDL^T');
  Writeln('Input: FEM3D ASCII model with persisted analysis case');
end;

var M:TFEMModel; Rg:TElementRegistry; Solver:TDenseLDLTSolver; LS:TLinearStaticSettings; Engine:TAnalysisEngine; R:TAnalysisResult; A:TAnalysisCase; F:string; CaseID:Integer; DoValidate,DoSolve:Boolean; V:TStringList; I,J:Integer; Status:string;
begin
  DoValidate:=False; DoSolve:=False; F:=''; CaseID:=0;
  if ParamCount=0 then begin Usage; Halt(2); end;
  for I:=1 to ParamCount do begin
    if SameText(ParamStr(I),'--info') then begin Info; Halt(0); end
    else if SameText(ParamStr(I),'--validate') then DoValidate:=True
    else if SameText(ParamStr(I),'--solve') then DoSolve:=True
    else if SameText(ParamStr(I),'--case') and (I<ParamCount) then begin Inc(I); CaseID:=StrToIntDef(ParamStr(I),0); end
    else if ParamStr(I)[1]<>'-' then F:=ParamStr(I);
  end;
  if F='' then begin Usage; Halt(2); end;
  M:=TFEMModel.Create; Rg:=TElementRegistry.Create; RegisterBuiltInElements(Rg);
  try
    try TFEMNativeIO.LoadModel(M,F); except on E:Exception do begin Writeln('INPUT ERROR: ',E.Message); Halt(3); end; end;
    if DoValidate then begin V:=TStringList.Create; try if M.Validate(V) then begin Writeln('VALIDATION: PASS'); end else begin Writeln('VALIDATION: FAIL'); Writeln(V.Text); Halt(4); end; finally V.Free end; end;
    if not DoSolve then begin if not DoValidate then Usage; Halt(0); end;
    A:=nil; if CaseID<>0 then A:=M.AnalysisCases.Find(CaseID) else if M.AnalysisCases.Count>0 then A:=M.AnalysisCases.Item(0);
    if A=nil then begin Writeln('ANALYSIS ERROR: no analysis case in input model.'); Halt(5); end;
    if A.AnalysisType<>atLinearStatic then begin Writeln('ANALYSIS ERROR: first analysis case is ',A.TypeName,'.'); Halt(6); end;
    LS:=TLinearStaticSettings(A.Settings); if LS.MatrixStorage<>msDense then begin Writeln('SOLVER ERROR: requested matrix storage ',MatrixStorageToString(LS.MatrixStorage),' is not implemented by this solver.'); Halt(7); end;
    if not SameText(LS.SolverName,'Reference dense LDL^T') then begin Writeln('SOLVER ERROR: requested solver ',LS.SolverName,' is not available in this executable.'); Halt(8); end;
    Solver:=TDenseLDLTSolver.Create; Engine:=TAnalysisEngine.Create(M,Rg,Solver);
    try
      R:=Engine.SolveCase(A);
      try
        if R.Success then Status:='SOLVE: PASS' else Status:='SOLVE: FAIL'; Writeln(Status);
        Writeln(R.MessageText);
        if R.Success then Writeln('RESULTS: ',ChangeFileExt(F,'.fem3dres'));
        if R.Success then begin
          AssignFile(Output,ChangeFileExt(F,'.fem3dres')); Rewrite(Output);
          Writeln(Output,'FEM3D_RESULT 0.7'); Writeln(Output,'SolverVersion=',FEM3D_LINSTATIC_VERSION); Writeln(Output,'SolverKernel=',FEM3D_LINSTATIC_KERNEL); Writeln(Output,'SolverKernelRevision=',FEM3D_LINSTATIC_KERNEL_REVISION); Writeln(Output,'ModelContract=',FEM3D_MODEL_CONTRACT); Writeln(Output,'ResultContract=',FEM3D_RESULT_CONTRACT); Writeln(Output,'AnalysisCase=',A.ID); Writeln(Output,'AnalysisName=',A.Name); Writeln(Output,'AnalysisType=',A.TypeName);
          Writeln(Output,'Solver=',R.SolverName); Writeln(Output,'ModelFingerprint=',R.ModelFingerprint); Writeln(Output,'AnalysisFingerprint=',R.AnalysisFingerprint);
          Writeln(Output,Format('DOFCount=%d',[R.DOFCount])); Writeln(Output,Format('ConstrainedDOF=%d',[R.ConstrainedDOF])); Writeln(Output,Format('ResidualNorm=%.17g',[R.ResidualNorm])); Writeln(Output,Format('MaxReaction=%.17g',[R.MaxReaction])); Writeln(Output,Format('StrainEnergy=%.17g',[R.StrainEnergy])); Writeln(Output,Format('ExternalWork=%.17g',[R.ExternalWork])); Writeln(Output,Format('EnergyBalanceError=%.17g',[R.EnergyBalanceError]));
          Writeln(Output,'[DISPLACEMENTS]'); for J:=0 to High(R.U) do Writeln(Output,Format('%d %.17g',[J+1,R.U[J]]));
          Writeln(Output,'[REACTIONS]'); for J:=0 to High(R.Reactions) do if Abs(R.Reactions[J])>0 then Writeln(Output,Format('%d %.17g',[J+1,R.Reactions[J]]));
          Writeln(Output,'[SOLVER_PROVENANCE]'); Writeln(Output,'Isolation=SOLVER_CORE_SNAPSHOT'); Writeln(Output,'ValidationBoundary=Numerical solver is independent of GUI source tree'); Writeln(Output,'[AUDIT_TRAIL]'); Writeln(Output,R.AuditTrail.Text); CloseFile(Output);
        end;
      finally R.Free end;
    finally Engine.Free; Solver.Free end;
  finally Rg.Free; M.Free end;
end.
