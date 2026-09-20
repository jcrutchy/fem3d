program HeadlessContract;
{$mode objfpc}{$H+}
{$UNITPATH ../src}

uses
  Classes, SysUtils, Math, FEMModel, FEMIO, FEMAnalysisCases, FEMHash;

var
  M, R:TFEMModel;
  A:TAnalysisCase;
  L:TLinearStaticSettings;
  TempFile:string;
  Errors:TStringList;
  Pass:Boolean;

begin
  Pass:=True;
  M:=TFEMModel.Create;
  R:=TFEMModel.Create;
  Errors:=TStringList.Create;
  try
    TFEMNativeIO.LoadModel(M,ExpandFileName('../examples/headless_cantilever.fem3d'));
    if M.AnalysisCases.Count<>1 then begin Writeln('FAIL analysis case count'); Pass:=False; end;
    A:=M.AnalysisCases.Item(0);
    if A.AnalysisType<>atLinearStatic then begin Writeln('FAIL analysis type'); Pass:=False; end;
    if A.LoadCaseID<>1 then begin Writeln('FAIL load case'); Pass:=False; end;
    if not (A.Settings is TLinearStaticSettings) then begin Writeln('FAIL settings type'); Pass:=False; end
    else begin
      L:=TLinearStaticSettings(A.Settings);
      if not SameText(L.SolverName,'Reference dense LDLT') and
         not SameText(L.SolverName,'Reference dense LDL^T') then begin
        Writeln('FAIL solver setting'); Pass:=False;
      end;
      if L.MatrixStorage<>msDense then begin Writeln('FAIL matrix storage'); Pass:=False; end;
      if L.PivotTolerance<=0 then begin Writeln('FAIL pivot tolerance'); Pass:=False; end;
      if L.ResidualTolerance<=0 then begin Writeln('FAIL residual tolerance'); Pass:=False; end;
      if not L.CheckEquilibrium then begin Writeln('FAIL equilibrium setting'); Pass:=False; end;
      if not L.CheckEnergy then begin Writeln('FAIL energy setting'); Pass:=False; end;
    end;

    if not M.Validate(Errors) then begin
      Writeln('FAIL validation:'); Write(Errors.Text); Pass:=False;
    end;

    TempFile:=IncludeTrailingPathDelimiter(GetTempDir(False))+'fem3d_headless_contract.fem3d';
    TFEMNativeIO.SaveModel(M,TempFile);
    TFEMNativeIO.LoadModel(R,TempFile);
    DeleteFile(TempFile);

    if R.AnalysisCases.Count<>M.AnalysisCases.Count then begin Writeln('FAIL roundtrip analysis count'); Pass:=False; end;
    if (Length(R.Nodes)<>Length(M.Nodes)) or
       (Length(R.Elements)<>Length(M.Elements)) or
       (Length(R.Loads)<>Length(M.Loads)) then begin
      Writeln('FAIL roundtrip model counts'); Pass:=False;
    end;

    if Pass then Writeln('HEADLESS MODEL CONTRACT PASSED')
    else Writeln('HEADLESS MODEL CONTRACT FAILED');
  finally
    Errors.Free; R.Free; M.Free;
  end;
  if Pass then Halt(0) else Halt(1);
end.
