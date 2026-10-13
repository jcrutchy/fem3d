program run_gui_script_test;
{$mode objfpc}{$H+}

// End-to-end test of the native section editor: runs femsecedit on each script
// in tests/gui (which drive the real tool, snap, undo and drag code paths and
// carry their own "expect" assertions), checks the exit code, and checks that
// the files a script saves are accepted by femgeocheck and carry the expected
// area according to femsection.
//
// It opens a window briefly for each script. On Linux it needs a display (and
// a window manager); without DISPLAY it reports SKIPPED rather than passing.
// Run from the repository root (test.bat does).

uses
  SysUtils, Classes, Process;

var
  Passed, Failed: Integer;
  BinDir, Exe, CheckExe, SectionExe, TmpDir: string;

procedure Check(const Name: string; Cond: Boolean; const Detail: string = '');
begin
  if Cond then
  begin
    Inc(Passed);
    WriteLn('PASS  ', Name);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', Name, '  ', Detail);
  end;
end;

// Runs a program, returns its exit code (or -1) and captured stdout+stderr.
function RunProg(const AExe: string; const Args: array of string; const Env: array of string;
  out Output: string; TimeoutMs: Integer = 90000): Integer;
var
  P: TProcess;
  I: Integer;
  Buf: array[0..4095] of Byte;
  N: Integer;
  T0: QWord;
begin
  Output := '';
  Result := -1;
  P := TProcess.Create(nil);
  try
    P.Executable := AExe;
    for I := 0 to High(Args) do P.Parameters.Add(Args[I]);
    for I := 0 to GetEnvironmentVariableCount - 1 do P.Environment.Add(GetEnvironmentString(I + 1));
    for I := 0 to High(Env) do P.Environment.Add(Env[I]);
    P.Options := [poUsePipes, poStderrToOutPut];
    P.Execute;
    T0 := GetTickCount64;
    while P.Running do
    begin
      while P.Output.NumBytesAvailable > 0 do
      begin
        N := P.Output.Read(Buf[0], SizeOf(Buf));
        if N > 0 then
        begin
          SetLength(Output, Length(Output) + N);
          Move(Buf[0], Output[Length(Output) - N + 1], N);
        end;
      end;
      if Int64(GetTickCount64 - T0) > TimeoutMs then
      begin
        P.Terminate(1);
        Output := Output + '[timed out]';
        Exit(-2);
      end;
      Sleep(20);
    end;
    while P.Output.NumBytesAvailable > 0 do
    begin
      N := P.Output.Read(Buf[0], SizeOf(Buf));
      if N <= 0 then Break;
      SetLength(Output, Length(Output) + N);
      Move(Buf[0], Output[Length(Output) - N + 1], N);
    end;
    Result := P.ExitCode;
  finally
    P.Free;
  end;
end;

function ReadAll(const Path: string): string;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.LoadFromFile(Path);
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

// "Area=1.88E+04" from a .prop / femsection output
function AreaFrom(const Text: string): Double;
var
  SL: TStringList;
  I: Integer;
  FS: TFormatSettings;
begin
  Result := -1;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SL := TStringList.Create;
  try
    SL.Text := Text;
    for I := 0 to SL.Count - 1 do
      if Copy(Trim(SL[I]), 1, 5) = 'Area=' then
        Exit(StrToFloatDef(Copy(Trim(SL[I]), 6, MaxInt), -1, FS));
  finally
    SL.Free;
  end;
end;

function FileBytes(const AName: string): Int64;
var
  SR: TSearchRec;
begin
  Result := -1;
  if FindFirst(AName, faAnyFile, SR) = 0 then
  begin
    Result := SR.Size;
    FindClose(SR);
  end;
end;

// Runs a script expected to succeed; returns True if it did.
function RunGood(const Name: string): Boolean;
var
  Out_, Fgeo, Prop: string;
  RC: Integer;
begin
  Fgeo := TmpDir + Name + '.fgeo';
  Prop := TmpDir + Name + '.prop';
  DeleteFile(Fgeo);
  DeleteFile(Prop);
  RC := RunProg(Exe, ['--script', 'tests' + DirectorySeparator + 'gui' + DirectorySeparator + Name + '.script',
    '--screenshot', TmpDir + Name + '.png'], ['OUT=' + Fgeo, 'OUT_PROP=' + Prop], Out_);
  Check(Name + ': script runs to the end with every expectation met', RC = 0,
    'exit=' + IntToStr(RC) + ' ' + Trim(Out_));
  Check(Name + ': a screenshot of the window was written', FileExists(TmpDir + Name + '.png') and
    (FileBytes(TmpDir + Name + '.png') > 5000) or (RC <> 0));
  Result := RC = 0;
end;

procedure TestSavedFile(const Name: string; ExpectedArea, RelTol: Double);
var
  Fgeo, Prop, Out_: string;
  RC: Integer;
  A: Double;
begin
  Fgeo := TmpDir + Name + '.fgeo';
  Prop := TmpDir + Name + '.prop';
  Check(Name + ': the saved .fgeo exists', FileExists(Fgeo));
  if not FileExists(Fgeo) then Exit;
  RC := RunProg(CheckExe, [Fgeo], [], Out_);
  Check(Name + ': femgeocheck accepts the saved file', RC = 0, Trim(Out_));
  RC := RunProg(SectionExe, [Fgeo], [], Out_);
  A := AreaFrom(Out_);
  Check(Name + ': femsection computes the expected area from the saved file',
    (RC = 0) and (Abs(A - ExpectedArea) <= RelTol * ExpectedArea),
    Format('exit=%d area=%g expected=%g', [RC, A, ExpectedArea]));
  if FileExists(Prop) then
    Check(Name + ': the exported .prop has the same area as femsection',
      Abs(AreaFrom(ReadAll(Prop)) - A) <= 1.0E-9 * Abs(A));
end;

procedure TestBad(const Name, Expected: string);
var
  Out_: string;
  RC: Integer;
begin
  RC := RunProg(Exe, ['--script', 'tests' + DirectorySeparator + 'gui' + DirectorySeparator + Name + '.script'],
    ['OUT=' + TmpDir + 'unused.fgeo'], Out_);
  Check(Name + ': a faulty script fails with exit code 3', RC = 3, 'exit=' + IntToStr(RC));
  Check(Name + ': ...and says why', Pos(Expected, Out_) > 0, Trim(Out_));
end;

begin
  Passed := 0;
  Failed := 0;
  BinDir := ExtractFilePath(ParamStr(0));
{$IFDEF WINDOWS}
  Exe := BinDir + 'femsecedit.exe';
  CheckExe := BinDir + 'femgeocheck.exe';
  SectionExe := BinDir + 'femsection.exe';
{$ELSE}
  Exe := BinDir + 'femsecedit';
  CheckExe := BinDir + 'femgeocheck';
  SectionExe := BinDir + 'femsection';
{$ENDIF}
  TmpDir := IncludeTrailingPathDelimiter(GetTempDir) + 'femsecedit_gui_test' + DirectorySeparator;
  ForceDirectories(TmpDir);

  if not FileExists(Exe) then
  begin
    WriteLn('SKIPPED  femsecedit is not built (', Exe, ')');
    Halt(0);
  end;
{$IFDEF UNIX}
  if GetEnvironmentVariable('DISPLAY') = '' then
  begin
    WriteLn('SKIPPED  no DISPLAY: the GUI end-to-end test needs an X display and a window manager');
    Halt(0);
  end;
{$ENDIF}
  if not FileExists(CheckExe) or not FileExists(SectionExe) then
  begin
    WriteLn('FAIL  femgeocheck and femsection must be built');
    Halt(1);
  end;

  if RunGood('draw_plate_with_hole') then TestSavedFile('draw_plate_with_hole', 18800, 1.0E-9);
  if RunGood('preset_ibeam') then TestSavedFile('preset_ibeam', 3230.9, 1.0E-3);
  RunGood('edit_drag');
  RunGood('presets_all');
  TestBad('bad_command', 'unknown command');
  TestBad('bad_expectation', 'expected area');

  WriteLn;
  WriteLn(Passed, ' / ', Passed + Failed, ' checks passed');
  if Failed = 0 then WriteLn('ALL CHECKS PASSED') else Halt(1);
end.
