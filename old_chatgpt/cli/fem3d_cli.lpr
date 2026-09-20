program fem3d_cli;

{$mode objfpc}{$H+}
{$UNITPATH ../src}
{$UNITPATH ../solver/common}

uses
  Classes, SysUtils,
  FEMModel, FEMIO, FEMValidation, FEMResults, FEMSolverProcess, FEMVerification, FEMSolverContract;

const
  EXIT_OK = FEM_SOLVER_SUCCESS;
  EXIT_USAGE = FEM_SOLVER_USAGE_ERROR;
  EXIT_IO = FEM_SOLVER_IO_ERROR;
  EXIT_VALIDATION = FEM_SOLVER_VALIDATION_ERROR;
  EXIT_PROCESS = FEM_SOLVER_ANALYSIS_ERROR;

procedure Usage;
begin
  Writeln('FEM3D command line client');
  Writeln;
  Writeln('Usage:');
  Writeln('  FEM3D_CLI.exe validate model.fem3d');
  Writeln('  FEM3D_CLI.exe info model.fem3d');
  Writeln('  FEM3D_CLI.exe results result.fem3dres');
  Writeln('  FEM3D_CLI.exe solve model.fem3d');
  Writeln('  FEM3D_CLI.exe verify');
end;

function SolverPath:string;
var
  Base:string;
  Candidate:string;
begin
  Base:=ExtractFilePath(ExpandFileName(ParamStr(0)));
  Candidate:=Base+'FEM3D_LinStatic.exe';
  if FileExists(Candidate) then Exit(Candidate);
  Candidate:=Base+'solver'+DirectorySeparator+'FEM3D_LinStatic.exe';
  if FileExists(Candidate) then Exit(Candidate);
  Result:='';
end;

function ValidateModel(const FileName:string):Integer;
var
  M:TFEMModel;
  Report:TFEMValidationReport;
begin
  M:=TFEMModel.Create;
  Report:=TFEMValidationReport.Create;
  try
    try
      TFEMNativeIO.LoadModel(M,FileName);
    except
      on E:Exception do begin
        Writeln('ERROR [IO] ',E.Message);
        Exit(EXIT_IO);
      end;
    end;
    Report.Validate(M);
    Writeln(Format('Nodes: %d',[Length(M.Nodes)]));
    Writeln(Format('Elements: %d',[Length(M.Elements)]));
    Writeln(Format('Materials: %d',[Length(M.Materials)]));
    Writeln(Format('Sections: %d',[Length(M.Sections)]));
    Writeln(Format('Load cases: %d',[Length(M.LoadCases)]));
    Writeln(Format('Loads: %d',[Length(M.Loads)]));
    Writeln(Format('Analysis cases: %d',[M.AnalysisCases.Count]));
    if Report.Count>0 then Write(Report.AsText);
    if Report.ErrorCount>0 then begin
      Writeln(Format('VALIDATION FAILED: %d error(s), %d warning(s).',[Report.ErrorCount,Report.WarningCount]));
      Exit(EXIT_VALIDATION);
    end;
    Writeln(Format('VALIDATION PASSED: %d warning(s).',[Report.WarningCount]));
    Result:=EXIT_OK;
  finally
    Report.Free;
    M.Free;
  end;
end;

function InfoModel(const FileName:string):Integer;
var
  M:TFEMModel;
  I:Integer;
  A:TAnalysisCase;
begin
  M:=TFEMModel.Create;
  try
    try
      TFEMNativeIO.LoadModel(M,FileName);
    except
      on E:Exception do begin Writeln('ERROR [IO] ',E.Message); Exit(EXIT_IO); end;
    end;
    Writeln('FEM3D model information');
    Writeln('File: ',ExpandFileName(FileName));
    Writeln('Nodes: ',Length(M.Nodes));
    Writeln('Elements: ',Length(M.Elements));
    Writeln('Materials: ',Length(M.Materials));
    Writeln('Sections: ',Length(M.Sections));
    Writeln('Load cases: ',Length(M.LoadCases));
    Writeln('Loads: ',Length(M.Loads));
    Writeln('Analysis cases: ',M.AnalysisCases.Count);
    for I:=0 to M.AnalysisCases.Count-1 do begin
      A:=M.AnalysisCases.Item(I);
      Writeln(Format('  %d: %s [%s], LoadCase=%d, ResultID=%s',[A.ID,A.Name,A.TypeName,A.LoadCaseID,A.ResultID]));
    end;
    Result:=EXIT_OK;
  finally
    M.Free;
  end;
end;

function ShowResults(const FileName:string):Integer;
var R:TFEMResultDocument;
begin
  R:=TFEMResultDocument.Create;
  try
    try R.LoadFromFile(FileName);
    except on E:Exception do begin Writeln('ERROR [IO] ',E.Message); Exit(EXIT_IO); end; end;
    Writeln(R.Summary);
    if R.Errors.Count>0 then begin Writeln('[ERRORS]'); Writeln(R.Errors.Text); end;
    if SameText(R.Status,'OK') then Result:=EXIT_OK else Result:=EXIT_PROCESS;
  finally R.Free end;
end;

function PassText(Passed:Boolean):string;
begin
  if Passed then Result:='PASS: ' else Result:='FAIL: ';
end;

function VerifyCore:Integer;
var
  V:TVerificationResult;
  Pass,AllPass:Boolean;
begin
  AllPass:=True;
  Pass:=TFEMVerification.CantileverTipDisplacement(V); AllPass:=AllPass and Pass;
  Writeln(PassText(Pass),V.Name);
  Pass:=TFEMVerification.CantileverTipDisplacementY(V); AllPass:=AllPass and Pass;
  Writeln(PassText(Pass),V.Name);
  Pass:=TFEMVerification.CantileverAxialDisplacement(V); AllPass:=AllPass and Pass;
  Writeln(PassText(Pass),V.Name);
  Pass:=TFEMVerification.CantileverTorsion(V); AllPass:=AllPass and Pass;
  Writeln(PassText(Pass),V.Name);
  Pass:=TFEMVerification.CantileverReactionEquilibrium(V); AllPass:=AllPass and Pass;
  Writeln(PassText(Pass),V.Name);
  Pass:=TFEMVerification.MechanismDetection(V); AllPass:=AllPass and Pass;
  Writeln(PassText(Pass),V.Name);
  Pass:=TFEMVerification.ModelValidation(V); AllPass:=AllPass and Pass;
  Writeln(PassText(Pass),V.Name);
  Pass:=TFEMVerification.BeamStiffnessSymmetry(V); AllPass:=AllPass and Pass;
  Writeln(PassText(Pass),V.Name);
  Pass:=TFEMVerification.EnergyBalance(V); AllPass:=AllPass and Pass;
  Writeln(PassText(Pass),V.Name);
  Pass:=TFEMVerification.BeamEndForceRecovery(V); AllPass:=AllPass and Pass;
  Writeln(PassText(Pass),V.Name);
  if AllPass then
  begin
    Writeln('ALL VERIFICATIONS PASSED');
    Result:=EXIT_OK;
  end
  else
  begin
    Writeln('VERIFICATION FAILURE');
    Result:=EXIT_PROCESS;
  end;
end;

function SolveModel(const FileName:string):Integer;
var
  Exe:string;
  Params:array of string;
  R:TSolverProcessResult;
  ResultFile:string;
begin
  Exe:=SolverPath;
  if Exe='' then begin Writeln('ERROR: FEM3D_LinStatic.exe was not found beside FEM3D_CLI.exe or in its solver subdirectory.'); Exit(EXIT_PROCESS); end;
  SetLength(Params,1);
  Params[0]:=ExpandFileName(FileName);
  if not TSolverProcessRunner.Run(Exe,Params,R) then begin
    Writeln('ERROR: unable to start solver.');
    Writeln(R.ErrorText);
    Exit(EXIT_PROCESS);
  end;
  if R.OutputText<>'' then Write(R.OutputText);
  if R.ErrorText<>'' then begin Writeln('[SOLVER STDERR]'); Write(R.ErrorText); end;
  ResultFile:=SolverResultFileName(FileName);
  Writeln('RESULT_FILE=',ResultFile);
  if not FileExists(ResultFile) then begin
    Writeln('ERROR: solver exited without producing the required result file.');
    Exit(EXIT_PROCESS);
  end;
  if R.ExitCode=0 then Result:=EXIT_OK else Result:=R.ExitCode;
end;

var
  Command:string;
begin
  try
    if ParamCount<1 then begin Usage; Halt(EXIT_USAGE); end;
    Command:=LowerCase(Trim(ParamStr(1)));
  if Command='validate' then begin
    if ParamCount<>2 then begin Usage; Halt(EXIT_USAGE); end;
    Halt(ValidateModel(ParamStr(2)));
  end
  else if Command='info' then begin
    if ParamCount<>2 then begin Usage; Halt(EXIT_USAGE); end;
    Halt(InfoModel(ParamStr(2)));
  end
  else if Command='results' then begin
    if ParamCount<>2 then begin Usage; Halt(EXIT_USAGE); end;
    Halt(ShowResults(ParamStr(2)));
  end
  else if Command='verify' then begin
    if ParamCount<>1 then begin Usage; Halt(EXIT_USAGE); end;
    Halt(VerifyCore);
  end
  else if Command='solve' then begin
    if ParamCount<>2 then begin Usage; Halt(EXIT_USAGE); end;
    Halt(SolveModel(ParamStr(2)));
  end
    else begin Usage; Halt(EXIT_USAGE); end;
  except
    on E:Exception do begin
      Writeln('FATAL ERROR [UNHANDLED]: ',E.Message);
      Halt(FEM_SOLVER_ANALYSIS_ERROR);
    end;
  end;
end.

