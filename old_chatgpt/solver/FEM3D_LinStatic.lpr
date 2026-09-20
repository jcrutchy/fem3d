program FEM3D_LinStatic;
{$mode objfpc}{$H+}
{$UNITPATH ../src}
{$UNITPATH common}
uses Classes, SysUtils, FEMTypes, FEMModel, FEMElements, FEMMatrix, FEMAnalysisCases,
  FEMAnalysis, FEMIO, FEM3D_SolverProvenance, FEMHash, FEMSolverContract;

function ResultFileName(const F:string):string; begin Result:=SolverResultFileName(F); end;

procedure WriteResultFailure(const FileName,Status,MessageText:string; A:TAnalysisCase; const Errors,Audit:TStringList);
var O:TextFile; I:Integer; begin
  AssignFile(O,FileName); Rewrite(O); try
    Writeln(O,'FEM3D_RESULT 0.7'); Writeln(O,'Status=',Status); Writeln(O,'SolverVersion=',FEM3D_LINSTATIC_VERSION); Writeln(O,'SolverKernel=',FEM3D_LINSTATIC_KERNEL); Writeln(O,'SolverKernelRevision=',FEM3D_LINSTATIC_KERNEL_REVISION); Writeln(O,'ModelContract=',FEM3D_MODEL_CONTRACT); Writeln(O,'ResultContract=',FEM3D_RESULT_CONTRACT);
    if A<>nil then begin Writeln(O,'AnalysisCase=',A.ID); Writeln(O,'AnalysisName=',A.Name); Writeln(O,'AnalysisType=',A.TypeName); Writeln(O,'AnalysisFingerprint=',AnalysisFingerprint(A)); end;
    Writeln(O,'Message=',MessageText); Writeln(O,'[ERRORS]');
    if Errors<>nil then for I:=0 to Errors.Count-1 do Writeln(O,Errors[I]);
    Writeln(O,'[SOLVER_PROVENANCE]'); Writeln(O,'Isolation=CLI_ONLY_SOLVER'); Writeln(O,'NumericalProcess=Independent executable');
    Writeln(O,'[AUDIT_TRAIL]'); if Audit<>nil then for I:=0 to Audit.Count-1 do Writeln(O,Audit[I]);
  finally CloseFile(O) end;
end;

procedure PublishSuccess(const FileName:string; A:TAnalysisCase; R:TAnalysisResult);
var O:TextFile; Tmp:string; I:Integer; begin
  Tmp:=FileName+'.tmp'; AssignFile(O,Tmp); Rewrite(O); try
    Writeln(O,'FEM3D_RESULT 0.7'); Writeln(O,'Status=OK'); Writeln(O,'SolverVersion=',FEM3D_LINSTATIC_VERSION); Writeln(O,'SolverKernel=',FEM3D_LINSTATIC_KERNEL); Writeln(O,'SolverKernelRevision=',FEM3D_LINSTATIC_KERNEL_REVISION); Writeln(O,'ModelContract=',FEM3D_MODEL_CONTRACT); Writeln(O,'ResultContract=',FEM3D_RESULT_CONTRACT);
    Writeln(O,'AnalysisCase=',A.ID); Writeln(O,'AnalysisName=',A.Name); Writeln(O,'AnalysisType=',A.TypeName); Writeln(O,'Solver=',R.SolverName); Writeln(O,'ModelFingerprint=',R.ModelFingerprint); Writeln(O,'AnalysisFingerprint=',R.AnalysisFingerprint);
    Writeln(O,Format('DOFCount=%d',[R.DOFCount])); Writeln(O,Format('ConstrainedDOF=%d',[R.ConstrainedDOF])); Writeln(O,Format('ResidualNorm=%.17g',[R.ResidualNorm])); Writeln(O,Format('MaxReaction=%.17g',[R.MaxReaction])); Writeln(O,Format('StrainEnergy=%.17g',[R.StrainEnergy])); Writeln(O,Format('ExternalWork=%.17g',[R.ExternalWork])); Writeln(O,Format('EnergyBalanceError=%.17g',[R.EnergyBalanceError]));
    Writeln(O,'[DISPLACEMENTS]'); for I:=0 to High(R.U) do Writeln(O,Format('%d %.17g',[I+1,R.U[I]]));
    Writeln(O,'[REACTIONS]'); for I:=0 to High(R.Reactions) do if Abs(R.Reactions[I])>0 then Writeln(O,Format('%d %.17g',[I+1,R.Reactions[I]]));
    Writeln(O,'[SOLVER_PROVENANCE]'); Writeln(O,'Isolation=CLI_ONLY_SOLVER'); Writeln(O,'NumericalProcess=Independent executable');
    Writeln(O,'[AUDIT_TRAIL]'); Writeln(O,R.AuditTrail.Text);
  finally CloseFile(O) end;
  if FileExists(FileName) then DeleteFile(FileName); if not RenameFile(Tmp,FileName) then begin DeleteFile(Tmp); raise Exception.Create('Unable to publish result file: '+FileName); end;
end;

var
  M:TFEMModel;
  Rg:TElementRegistry;
  Solver:TDenseLDLTSolver;
  Engine:TAnalysisEngine;
  R:TAnalysisResult;
  A:TAnalysisCase;
  F,OutF:string;
  V:TStringList;
  I,ExitCode:Integer;
  LS:TLinearStaticSettings;

begin
  ExitCode:=FEM_SOLVER_SUCCESS;
  M:=nil; Rg:=nil; Solver:=nil; Engine:=nil; R:=nil; A:=nil; V:=TStringList.Create;
  try
    if ParamCount<>1 then
    begin
      Writeln('Usage: FEM3D_LinStatic.exe model.fem3d');
      ExitCode:=FEM_SOLVER_USAGE_ERROR;
      Exit;
    end;

    F:=ParamStr(1);
    OutF:=ResultFileName(F);
    M:=TFEMModel.Create;
    Rg:=TElementRegistry.Create;
    RegisterBuiltInElements(Rg);

    try
      TFEMNativeIO.LoadModel(M,F);
    except
      on E:Exception do
      begin
        V.Add('IO_ERROR='+E.Message);
        WriteResultFailure(OutF,'FAILURE','Unable to load model: '+E.Message,nil,V,nil);
        Writeln('RESULT_FILE=',OutF);
        ExitCode:=FEM_SOLVER_IO_ERROR;
        Exit;
      end;
    end;

    if not M.Validate(V) then
    begin
      WriteResultFailure(OutF,'FAILURE','Model validation failed.',nil,V,nil);
      Writeln('RESULT_FILE=',OutF);
      ExitCode:=FEM_SOLVER_VALIDATION_ERROR;
      Exit;
    end;

    for I:=0 to M.AnalysisCases.Count-1 do
      if M.AnalysisCases.Item(I).AnalysisType=atLinearStatic then
      begin
        if A=nil then
          A:=M.AnalysisCases.Item(I)
        else
        begin
          V.Add('ANALYSIS_AMBIGUOUS=Multiple Linear Static analysis cases are present.');
          WriteResultFailure(OutF,'FAILURE',
            'Multiple applicable Linear Static analysis cases are present.',nil,V,nil);
          Writeln('RESULT_FILE=',OutF);
          ExitCode:=FEM_SOLVER_ANALYSIS_ERROR;
          Exit;
        end;
      end;

    if A=nil then
    begin
      V.Add('ANALYSIS_MISSING=No Linear Static analysis case is present.');
      WriteResultFailure(OutF,'FAILURE',
        'No Linear Static analysis case is present.',nil,V,nil);
      Writeln('RESULT_FILE=',OutF);
      ExitCode:=FEM_SOLVER_ANALYSIS_ERROR;
      Exit;
    end;

    if A.Settings=nil then
    begin
      V.Add('SETTINGS_MISSING=Analysis settings are missing.');
      WriteResultFailure(OutF,'FAILURE',
        'Linear Static analysis settings are missing.',A,V,nil);
      Writeln('RESULT_FILE=',OutF);
      ExitCode:=FEM_SOLVER_CONFIGURATION_ERROR;
      Exit;
    end;

    if not (A.Settings is TLinearStaticSettings) then
    begin
      V.Add('SETTINGS_TYPE=Analysis settings are not Linear Static settings.');
      WriteResultFailure(OutF,'FAILURE',
        'Invalid Linear Static settings object.',A,V,nil);
      Writeln('RESULT_FILE=',OutF);
      ExitCode:=FEM_SOLVER_CONFIGURATION_ERROR;
      Exit;
    end;

    LS:=TLinearStaticSettings(A.Settings);

    if LS.MatrixStorage<>msDense then
    begin
      V.Add('MATRIX_STORAGE_UNSUPPORTED='+MatrixStorageToString(LS.MatrixStorage));
      WriteResultFailure(OutF,'FAILURE',
        'Requested matrix storage is not implemented by this solver.',A,V,nil);
      Writeln('RESULT_FILE=',OutF);
      ExitCode:=FEM_SOLVER_MATRIX_ERROR;
      Exit;
    end;

    if not SameText(LS.SolverName,'Reference dense LDLT') and
       not SameText(LS.SolverName,'Reference dense LDL^T') then
    begin
      V.Add('SOLVER_UNSUPPORTED='+LS.SolverName);
      WriteResultFailure(OutF,'FAILURE',
        'Requested solver implementation is not available.',A,V,nil);
      Writeln('RESULT_FILE=',OutF);
      ExitCode:=FEM_SOLVER_IMPLEMENTATION_ERROR;
      Exit;
    end;

    Solver:=TDenseLDLTSolver.Create;
    Engine:=TAnalysisEngine.Create(M,Rg,Solver);
    R:=Engine.SolveCase(A);

    if R.Success then
    begin
      PublishSuccess(OutF,A,R);
      Writeln('RESULT_FILE=',OutF);
      ExitCode:=FEM_SOLVER_SUCCESS;
    end
    else
    begin
      V.Add('NUMERICAL_ERROR='+R.MessageText);
      WriteResultFailure(OutF,'FAILURE',R.MessageText,A,V,R.AuditTrail);
      Writeln('RESULT_FILE=',OutF);
      ExitCode:=FEM_SOLVER_NUMERICAL_ERROR;
    end;
  finally
    R.Free;
    Engine.Free;
    Solver.Free;
    Rg.Free;
    M.Free;
    V.Free;
  end;

  Halt(ExitCode);
end.
