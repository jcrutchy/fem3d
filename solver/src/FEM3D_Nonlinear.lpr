program FEM3D_Nonlinear;
{$mode objfpc}
uses Classes, SysUtils, FEMModel, FEMElements, FEMAnalysisCases, FEMValidation, FEMIO, FEMHash;

procedure Info;
begin
  Writeln('FEM3D Nonlinear Static Solver'); Writeln('Version: 0.7'); Writeln('Platform: Windows x64');
  Writeln('Input: FEM3D ASCII model with persisted analysis case');
end;

function HasParam(const S:string):Boolean; var K:Integer; begin Result:=False; for K:=1 to ParamCount do if SameText(ParamStr(K),S) then Exit(True); end;

var M:TFEMModel; Rg:TElementRegistry; F,OutF:string; CaseID,I:Integer; A:TAnalysisCase; V:TStringList;
begin
  F:=''; CaseID:=0;
  if ParamCount=0 then begin Writeln('Usage: FEM3D_Nonlinear.exe [--info] [--validate] [--solve] [--case N] input.fem3d'); Halt(2); end;
  I:=1; while I<=ParamCount do begin
    if SameText(ParamStr(I),'--info') then begin Info; Halt(0); end
    else if SameText(ParamStr(I),'--case') and (I<ParamCount) then begin Inc(I); CaseID:=StrToIntDef(ParamStr(I),0); end
    else if ParamStr(I)[1]<>'-' then F:=ParamStr(I); Inc(I);
  end;
  if F='' then begin Writeln('INPUT ERROR: no model file specified.'); Halt(2); end;
  M:=TFEMModel.Create; Rg:=TElementRegistry.Create; RegisterBuiltInElements(Rg);
  try
    try TFEMNativeIO.LoadModel(M,F); except on E:Exception do begin Writeln('INPUT ERROR: ',E.Message); Halt(3); end; end;
    A:=nil; if CaseID<>0 then A:=M.AnalysisCases.Find(CaseID) else if M.AnalysisCases.Count>0 then A:=M.AnalysisCases.Item(0);
    if A=nil then begin Writeln('ANALYSIS ERROR: no requested analysis case.'); Halt(5); end;
    Writeln('ANALYSIS CASE: ',A.ID,' ',A.Name,' [',A.TypeName,']');
    V:=TStringList.Create; try
      if M.Validate(V) then Writeln('VALIDATION: PASS') else begin Writeln('VALIDATION: FAIL'); Writeln(V.Text); Halt(4); end;
    finally V.Free end;
    OutF:=ChangeFileExt(F,'.fem3dres'); AssignFile(Output,OutF); Rewrite(Output);
    Writeln(Output,'FEM3D_RESULT 0.7'); Writeln(Output,'Status=NOT_IMPLEMENTED'); Writeln(Output,'AnalysisCase=',A.ID); Writeln(Output,'AnalysisType=',A.TypeName);
    Writeln(Output,'Message=Numerical solver is intentionally gated pending formulation verification.');
    Writeln(Output,'ModelFingerprint=',ModelFingerprint(M)); Writeln(Output,'AnalysisFingerprint=',AnalysisFingerprint(A)); Writeln(Output,'[AUDIT_TRAIL]'); Writeln(Output,'SOLVER: external process boundary established'); Writeln(Output,'VALIDATION: passed');
    CloseFile(Output);
    if HasParam('--solve') then begin Writeln('SOLVE: NOT IMPLEMENTED'); Writeln('RESULT FILE: ',OutF); Halt(10); end;
    Writeln('VALIDATION: PASS');
  finally Rg.Free; M.Free end;
end.

