program FEM3D_TestRunner;

{$mode objfpc}{$H+}
{$UNITPATH ../src}

uses
  Classes, SysUtils, Process, Math,
  FEMResults;

const
  EXIT_OK = 0;
  EXIT_TEST_FAILURE = 1;
  EXIT_USAGE = 2;
  PROCESS_TIMEOUT_MS = 600000;


type
  TProcessResult = record
    Started:Boolean;
    ExitCode:Integer;
    OutputText:string;
    ErrorText:string;
  end;

function FNV1a64(const S:string):QWord;
var I:Integer;
begin
  Result:=QWord($CBF29CE484222325);
  for I:=1 to Length(S) do
  begin
    Result:=Result xor Ord(S[I]);
    Result:=Result*QWord($100000001B3);
  end;
end;

function FileFingerprint(const FileName:string):string;
var F:TFileStream; Buffer:array[0..8191] of Byte; N,I:Integer; H:QWord;
begin
  if not FileExists(FileName) then Exit('MISSING');
  H:=QWord($CBF29CE484222325);
  F:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyNone);
  try
    repeat
      N:=F.Read(Buffer,SizeOf(Buffer));
      for I:=0 to N-1 do
      begin
        H:=H xor Buffer[I];
        H:=H*QWord($100000001B3);
      end;
    until N=0;
  finally
    F.Free;
  end;
  Result:=IntToHex(H,16);
end;

function RunProcess(const Exe:string; const Params:array of string; out R:TProcessResult):Boolean;
var P:TProcess; I,N:Integer; S:string;
begin
  FillChar(R,SizeOf(R),0);
  R.ExitCode:=-1;
  Result:=False;
  if not FileExists(Exe) then
  begin
    R.ErrorText:='Executable not found: '+Exe;
    Exit;
  end;
  P:=TProcess.Create(nil);
  try
    P.Executable:=Exe;
    for I:=Low(Params) to High(Params) do P.Parameters.Add(Params[I]);
    P.Options:=[poUsePipes];
    try
      P.Execute;
      R.Started:=True;
      if not P.WaitOnExit(PROCESS_TIMEOUT_MS) then
      begin
        R.ErrorText:='Process timed out after '+IntToStr(PROCESS_TIMEOUT_MS div 1000)+' seconds.';
        try P.Terminate(1); except end;
        try P.WaitOnExit; except end;
        R.ExitCode:=-2;
        Exit;
      end;
      R.ExitCode:=P.ExitStatus;
      N:=P.Output.NumBytesAvailable;
      if N>0 then begin SetLength(S,N); P.Output.ReadBuffer(S[1],N); R.OutputText:=S; end;
      N:=P.Stderr.NumBytesAvailable;
      if N>0 then begin SetLength(S,N); P.Stderr.ReadBuffer(S[1],N); R.ErrorText:=S; end;
      Result:=True;
    except
      on E:Exception do R.ErrorText:=E.Message;
    end;
  finally
    P.Free;
  end;
end;

function ReadKey(const L:TStringList; const Key,Default:string):string;
begin
  Result:=L.Values[Key];
  if Result='' then Result:=Default;
end;

function ParseExpectedResult(const FileName:string; out R:TFEMResultDocument):Boolean;
begin
  R:=TFEMResultDocument.Create;
  try
    try
      R.LoadFromFile(FileName);
      Result:=True;
    except
      R.Free;
      R:=nil;
      Result:=False;
    end;
  end;
end;

function CompareScalar(const LabelText:string; Expected,Actual,Tol:Double):Boolean;
var Diff,Scale,Rel:Double;
begin
  Diff:=Abs(Actual-Expected);
  Scale:=Max(Abs(Expected),1.0);
  Rel:=Diff/Scale;
  Result:=Rel<=Tol;
  if not Result then
    Writeln(Format('  FAIL: %s expected %.17g actual %.17g abs %.6g rel %.6g',[LabelText,Expected,Actual,Diff,Rel]));
end;

function CompareVector(const LabelText:string; const Expected,Actual:array of Double; Tol:Double):Boolean;
var I,N:Integer; E,A:Double; Passed:Boolean;
begin
  Result:=True;
  N:=Length(Expected); if Length(Actual)>N then N:=Length(Actual);
  for I:=0 to N-1 do begin
    if I<Length(Expected) then E:=Expected[I] else E:=0;
    if I<Length(Actual) then A:=Actual[I] else A:=0;
    Passed:=CompareScalar(LabelText+'['+IntToStr(I+1)+']',E,A,Tol);
    Result:=Result and Passed;
  end;
end;

function CompareResult(const CaseName,ExpectedFile,ActualFile:string; Tol:Double):Boolean;
var E,A:TFEMResultDocument; Passed:Boolean;
begin
  Result:=False;
  if not ParseExpectedResult(ExpectedFile,E) then begin Writeln('  ERROR: unable to read expected result.'); Exit; end;
  if not ParseExpectedResult(ActualFile,A) then begin Writeln('  ERROR: unable to read actual result.'); E.Free; Exit; end;
  try
    Passed:=True;
    if not SameText(A.Status,E.Status) then begin Writeln('  FAIL: Status expected ',E.Status,' actual ',A.Status); Passed:=False; end;
    if (E.DOFCount<>0) and (A.DOFCount<>E.DOFCount) then begin Writeln('  FAIL: DOFCount expected ',E.DOFCount,' actual ',A.DOFCount); Passed:=False; end;
    if (E.ConstrainedDOF<>0) and (A.ConstrainedDOF<>E.ConstrainedDOF) then begin Writeln('  FAIL: ConstrainedDOF expected ',E.ConstrainedDOF,' actual ',A.ConstrainedDOF); Passed:=False; end;
    if (E.StrainEnergy<>0) then Passed:=CompareScalar('StrainEnergy',E.StrainEnergy,A.StrainEnergy,Tol) and Passed;
    if (E.ExternalWork<>0) then Passed:=CompareScalar('ExternalWork',E.ExternalWork,A.ExternalWork,Tol) and Passed;
    Passed:=CompareVector('U',E.Displacements,A.Displacements,Tol) and Passed;
    Passed:=CompareVector('R',E.Reactions,A.Reactions,Tol) and Passed;
    if Passed then begin Writeln('  result comparison: PASS'); Result:=True; end;
  finally
    A.Free; E.Free;
  end;
end;

function RunVerifiedCase(const CaseDir,CLI:string):Boolean;
var Manifest:TStringList; CaseName,ModelName,ExpectedName,ModelFile,ExpectedFile,ActualFile:string; Tol:Double; R:TProcessResult; Params:array of string; P:Integer;
begin
  Result:=False;
  Manifest:=TStringList.Create;
  try
    try Manifest.LoadFromFile(CaseDir+DirectorySeparator+'manifest.ini'); except on E:Exception do begin Writeln('  FAIL: unable to read manifest: ',E.Message); Exit; end; end;
    CaseName:=ReadKey(Manifest,'Name',ExtractFileName(CaseDir));
    ModelName:=ReadKey(Manifest,'Model','model.fem3d');
    ExpectedName:=ReadKey(Manifest,'Expected','expected.fem3dres');
    Tol:=StrToFloatDef(ReadKey(Manifest,'Tolerance','1E-8'),1E-8);
    ModelFile:=CaseDir+DirectorySeparator+ModelName;
    ExpectedFile:=CaseDir+DirectorySeparator+ExpectedName;
    ActualFile:=ChangeFileExt(ModelFile,'.fem3dres');
    Writeln('CASE ',CaseName);
    if not FileExists(ModelFile) then begin Writeln('  FAIL: missing model.'); Exit; end;
    if not FileExists(ExpectedFile) then begin Writeln('  FAIL: missing expected result.'); Exit; end;

    SetLength(Params,2); Params[0]:='validate'; Params[1]:=ExpandFileName(ModelFile);
    if not RunProcess(CLI,Params,R) then begin Writeln('  FAIL: validate could not start: ',R.ErrorText); Exit; end;
    if R.ExitCode<>0 then begin Writeln('  FAIL: validate exit ',R.ExitCode); if R.OutputText<>'' then Write(R.OutputText); if R.ErrorText<>'' then Write(R.ErrorText); Exit; end;
    Writeln('  validate: PASS');

    if FileExists(ActualFile) then DeleteFile(ActualFile);
    SetLength(Params,2); Params[0]:='solve'; Params[1]:=ExpandFileName(ModelFile);
    if not RunProcess(CLI,Params,R) then begin Writeln('  FAIL: solve could not start: ',R.ErrorText); Exit; end;
    if R.OutputText<>'' then Write(R.OutputText);
    if R.ErrorText<>'' then Write(R.ErrorText);
    if R.ExitCode<>0 then begin Writeln('  FAIL: solve exit ',R.ExitCode); Exit; end;
    if not FileExists(ActualFile) then begin Writeln('  FAIL: solver produced no result file.'); Exit; end;

    SetLength(Params,2); Params[0]:='results'; Params[1]:=ExpandFileName(ActualFile);
    if not RunProcess(CLI,Params,R) then begin Writeln('  FAIL: results could not start: ',R.ErrorText); Exit; end;
    if R.ExitCode<>0 then begin Writeln('  FAIL: results exit ',R.ExitCode); if R.OutputText<>'' then Write(R.OutputText); if R.ErrorText<>'' then Write(R.ErrorText); Exit; end;
    Writeln('  results: PASS');

    if not CompareResult(CaseName,ExpectedFile,ActualFile,Tol) then Exit;
    Result:=True;
  finally
    if (ActualFile<>'') and FileExists(ActualFile) then DeleteFile(ActualFile);
    Manifest.Free;
  end;
end;

function ContainsTextCI(const S,Needle:string):Boolean;
begin Result:=Pos(UpperCase(Needle),UpperCase(S))>0; end;

function RunInvalidCase(const CaseDir,CLI:string):Boolean;
var Manifest:TStringList; CaseName,ModelName,ExpectedExit,RequiredText,ModelFile:string; R:TProcessResult; Params:array of string; Code:Integer; Combined:string;
begin
  Result:=False; Manifest:=TStringList.Create;
  try
    try Manifest.LoadFromFile(CaseDir+DirectorySeparator+'manifest.ini'); except on E:Exception do begin Writeln('  FAIL: unable to read manifest: ',E.Message); Exit; end; end;
    CaseName:=ReadKey(Manifest,'Name',ExtractFileName(CaseDir));
    ModelName:=ReadKey(Manifest,'Model','model.fem3d');
    ExpectedExit:=ReadKey(Manifest,'ExpectedExitCode','4');
    RequiredText:=ReadKey(Manifest,'RequiredText','');
    ModelFile:=CaseDir+DirectorySeparator+ModelName;
    Writeln('INVALID ',CaseName);
    if not FileExists(ModelFile) then begin Writeln('  FAIL: missing model.'); Exit; end;
    SetLength(Params,2); Params[0]:='validate'; Params[1]:=ExpandFileName(ModelFile);
    if not RunProcess(CLI,Params,R) then begin Writeln('  FAIL: validate could not start: ',R.ErrorText); Exit; end;
    Code:=StrToIntDef(ExpectedExit,-1);
    if R.ExitCode<>Code then begin Writeln('  FAIL: exit expected ',Code,' actual ',R.ExitCode); if R.OutputText<>'' then Write(R.OutputText); Exit; end;
    Combined:=R.OutputText+R.ErrorText;
    if (RequiredText<>'') and not ContainsTextCI(Combined,RequiredText) then begin Writeln('  FAIL: required diagnostic not found: ',RequiredText); Exit; end;
    Writeln('  validation rejection: PASS');
    Result:=True;
  finally Manifest.Free end;
end;

procedure EnumerateCases(const Root:string; List:TStringList);
var SR:TSearchRec;
begin
  if FindFirst(Root+DirectorySeparator+'*',faDirectory,SR)=0 then
  begin
    repeat
      if (SR.Name<>'.') and (SR.Name<>'..') and ((SR.Attr and faDirectory)<>0) then
        if FileExists(Root+DirectorySeparator+SR.Name+DirectorySeparator+'manifest.ini') then List.Add(Root+DirectorySeparator+SR.Name);
    until FindNext(SR)<>0;
    FindClose(SR);
  end;
end;

function FreezeIndex(const Root,IndexName:string):Integer;
var Cases:TStringList; OutF:TextFile; I:Integer; D,Dir,ManifestFile,ModelFile,ExpectedFile:string; L:TStringList;
begin
  Cases:=TStringList.Create; L:=TStringList.Create;
  try
    EnumerateCases(Root,Cases); Cases.Sort;
    AssignFile(OutF,IndexName); Rewrite(OutF);
    try
      Writeln(OutF,'FEM3D VERIFIED CORPUS INDEX 1');
      for I:=0 to Cases.Count-1 do begin
        Dir:=Cases[I]; D:=ExtractFileName(Dir); ManifestFile:=Dir+DirectorySeparator+'manifest.ini';
        L.Clear; L.LoadFromFile(ManifestFile);
        ModelFile:=Dir+DirectorySeparator+ReadKey(L,'Model','model.fem3d');
        ExpectedFile:=Dir+DirectorySeparator+ReadKey(L,'Expected','expected.fem3dres');
        Writeln(OutF,D,'|',FileFingerprint(ManifestFile),'|',FileFingerprint(ModelFile),'|',FileFingerprint(ExpectedFile));
      end;
    finally CloseFile(OutF) end;
    Writeln('Frozen ',Cases.Count,' verified case(s) into ',IndexName);
    Result:=EXIT_OK;
  finally L.Free; Cases.Free end;
end;

function FindIndexEntry(const L:TStringList; const CaseName:string):string;
var I,P:Integer; S:string;
begin
  Result:='';
  for I:=0 to L.Count-1 do
  begin
    S:=Trim(L[I]);
    if (S='') or (S[1]='#') or (Pos('FEM3D VERIFIED',UpperCase(S))=1) then Continue;
    P:=Pos('|',S);
    if (P>0) and SameText(Copy(S,1,P-1),CaseName) then Exit(S);
  end;
end;

function CheckIndex(const Root,IndexName:string):Boolean;
var L,Cases,Manifest:TStringList; I:Integer; S,Dir,Entry,ManifestHash,ModelHash,ExpectedHash,ManifestFile,ModelFile,ExpectedFile:string; Parts:TStringList;
begin
  Result:=False;
  if not FileExists(IndexName) then
  begin
    Writeln('ERROR: verified index is missing. Run --freeze-verified after independently verifying a new/changed case.');
    Exit;
  end;
  L:=TStringList.Create; Cases:=TStringList.Create; Parts:=TStringList.Create; Manifest:=TStringList.Create;
  try
    L.LoadFromFile(IndexName);
    EnumerateCases(Root,Cases); Cases.Sort;
    for I:=0 to Cases.Count-1 do
    begin
      Dir:=Cases[I]; S:=ExtractFileName(Dir); Entry:=FindIndexEntry(L,S);
      if Entry='' then begin Writeln('ERROR: verified case missing from index: ',S); Exit; end;
      Parts.Delimiter:='|'; Parts.StrictDelimiter:=True; Parts.DelimitedText:=Entry;
      if Parts.Count<4 then begin Writeln('ERROR: malformed index entry for ',S); Exit; end;
      ManifestFile:=Dir+DirectorySeparator+'manifest.ini';
      Manifest.Clear; Manifest.LoadFromFile(ManifestFile);
      ModelFile:=Dir+DirectorySeparator+ReadKey(Manifest,'Model','model.fem3d');
      ExpectedFile:=Dir+DirectorySeparator+ReadKey(Manifest,'Expected','expected.fem3dres');
      ManifestHash:=FileFingerprint(ManifestFile); ModelHash:=FileFingerprint(ModelFile); ExpectedHash:=FileFingerprint(ExpectedFile);
      if (Parts[1]<>ManifestHash) or (Parts[2]<>ModelHash) or (Parts[3]<>ExpectedHash) then
      begin
        Writeln('ERROR: verified case has changed: ',S);
        Writeln('       Re-verification is required; index was not updated automatically.');
        Exit;
      end;
    end;
    Result:=True;
  finally Manifest.Free; Parts.Free; Cases.Free; L.Free end;
end;

function RunCommandContractTests(const CLI,Solver:string):Boolean;
var R:TProcessResult; Params:array of string; AllPass:Boolean;
begin
  AllPass:=True;
  Writeln('CLI/SOLVER command contract');

  SetLength(Params,0);
  if not RunProcess(CLI,Params,R) then begin Writeln('  FAIL: CLI no-argument invocation could not start.'); AllPass:=False; end
  else if R.ExitCode<>2 then begin Writeln('  FAIL: CLI no-argument exit expected 2 actual ',R.ExitCode); AllPass:=False; end
  else Writeln('  CLI no-argument rejection: PASS');

  SetLength(Params,3); Params[0]:='solve'; Params[1]:='dummy.fem3d'; Params[2]:='unexpected';
  if not RunProcess(CLI,Params,R) then begin Writeln('  FAIL: CLI extra-argument invocation could not start.'); AllPass:=False; end
  else if R.ExitCode<>2 then begin Writeln('  FAIL: CLI extra-argument exit expected 2 actual ',R.ExitCode); AllPass:=False; end
  else Writeln('  CLI extra-argument rejection: PASS');

  SetLength(Params,1); Params[0]:='not-a-command';
  if not RunProcess(CLI,Params,R) then begin Writeln('  FAIL: CLI unknown-command invocation could not start.'); AllPass:=False; end
  else if R.ExitCode<>2 then begin Writeln('  FAIL: CLI unknown-command exit expected 2 actual ',R.ExitCode); AllPass:=False; end
  else Writeln('  CLI unknown-command rejection: PASS');

  SetLength(Params,0);
  if not RunProcess(Solver,Params,R) then begin Writeln('  FAIL: solver no-argument invocation could not start.'); AllPass:=False; end
  else if R.ExitCode<>2 then begin Writeln('  FAIL: solver no-argument exit expected 2 actual ',R.ExitCode); AllPass:=False; end
  else Writeln('  solver no-argument rejection: PASS');

  SetLength(Params,2); Params[0]:='one.fem3d'; Params[1]:='two.fem3d';
  if not RunProcess(Solver,Params,R) then begin Writeln('  FAIL: solver extra-argument invocation could not start.'); AllPass:=False; end
  else if R.ExitCode<>2 then begin Writeln('  FAIL: solver extra-argument exit expected 2 actual ',R.ExitCode); AllPass:=False; end
  else Writeln('  solver extra-argument rejection: PASS');

  Result:=AllPass;
end;

function RunInvalidResultCase(const CaseDir,CLI:string):Boolean;
var Manifest:TStringList; CaseName,ResultName,ExpectedExit,RequiredText,ResultFile:string; R:TProcessResult; Params:array of string; Code:Integer; Combined:string;
begin
  Result:=False; Manifest:=TStringList.Create;
  try
    try Manifest.LoadFromFile(CaseDir+DirectorySeparator+'manifest.ini'); except on E:Exception do begin Writeln('  FAIL: unable to read manifest: ',E.Message); Exit; end; end;
    CaseName:=ReadKey(Manifest,'Name',ExtractFileName(CaseDir));
    ResultName:=ReadKey(Manifest,'Result','result.fem3dres');
    ExpectedExit:=ReadKey(Manifest,'ExpectedExitCode','3');
    RequiredText:=ReadKey(Manifest,'RequiredText','Result parse error');
    ResultFile:=CaseDir+DirectorySeparator+ResultName;
    Writeln('INVALID RESULT ',CaseName);
    if not FileExists(ResultFile) then begin Writeln('  FAIL: missing result.'); Exit; end;
    SetLength(Params,2); Params[0]:='results'; Params[1]:=ExpandFileName(ResultFile);
    if not RunProcess(CLI,Params,R) then begin Writeln('  FAIL: results command could not start: ',R.ErrorText); Exit; end;
    Code:=StrToIntDef(ExpectedExit,-1);
    if R.ExitCode<>Code then begin Writeln('  FAIL: exit expected ',Code,' actual ',R.ExitCode); if R.OutputText<>'' then Write(R.OutputText); if R.ErrorText<>'' then Write(R.ErrorText); Exit; end;
    Combined:=R.OutputText+R.ErrorText;
    if (RequiredText<>'') and not ContainsTextCI(Combined,RequiredText) then begin Writeln('  FAIL: required diagnostic not found: ',RequiredText); Exit; end;
    Writeln('  result rejection: PASS'); Result:=True;
  finally Manifest.Free end;
end;

function RunAll:Integer;
var CLI,Base:string; Cases:TStringList; I:Integer; AllPass:Boolean;
begin
  Base:=ExtractFilePath(ExpandFileName(ParamStr(0)));
  CLI:=Base+'..'+DirectorySeparator+'FEM3D_CLI.exe';
  if not FileExists(CLI) then CLI:=Base+'FEM3D_CLI.exe';
  if not FileExists(CLI) then begin Writeln('ERROR: FEM3D_CLI.exe not found beside or above test runner.'); Exit(EXIT_TEST_FAILURE); end;
  if not CheckIndex(Base+'verified',Base+'verified'+DirectorySeparator+'VERIFIED.INDEX') then Exit(EXIT_TEST_FAILURE);
  if not RunCommandContractTests(CLI,Base+'..'+DirectorySeparator+'FEM3D_LinStatic.exe') then Exit(EXIT_TEST_FAILURE);
  Cases:=TStringList.Create; try EnumerateCases(Base+'verified',Cases); Cases.Sort; AllPass:=True;
    for I:=0 to Cases.Count-1 do if not RunVerifiedCase(Cases[I],CLI) then AllPass:=False;
    Cases.Clear; EnumerateCases(Base+'invalid',Cases); Cases.Sort;
    for I:=0 to Cases.Count-1 do if not RunInvalidCase(Cases[I],CLI) then AllPass:=False;
    Cases.Clear; EnumerateCases(Base+'invalid_results',Cases); Cases.Sort;
    for I:=0 to Cases.Count-1 do if not RunInvalidResultCase(Cases[I],CLI) then AllPass:=False;
    if AllPass then begin Writeln('ALL REGRESSION TESTS PASSED'); Result:=EXIT_OK; end else begin Writeln('REGRESSION FAILURE'); Result:=EXIT_TEST_FAILURE; end;
  finally Cases.Free end;
end;

var Base,Command:string;
begin
  if ParamCount=1 then begin
    Command:=LowerCase(ParamStr(1));
    if Command='--freeze-verified' then begin
      Base:=ExtractFilePath(ExpandFileName(ParamStr(0)));
      Halt(FreezeIndex(Base+'verified',Base+'verified'+DirectorySeparator+'VERIFIED.INDEX'));
    end;
    if Command='--help' then begin Writeln('FEM3D regression runner'); Writeln('  FEM3D_TestRunner.exe'); Writeln('  FEM3D_TestRunner.exe --freeze-verified'); Halt(EXIT_OK); end;
  end;
  if ParamCount<>0 then begin Writeln('Usage: FEM3D_TestRunner.exe [--freeze-verified]'); Halt(EXIT_USAGE); end;
  try
    Halt(RunAll);
  except
    on E:Exception do begin
      Writeln('REGRESSION HARNESS FATAL ERROR: ',E.Message);
      Halt(EXIT_TEST_FAILURE);
    end;
  end;
end.
