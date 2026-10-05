program run_geometry_fixtures;

// Black-box regression runner for femgeo's test fixtures: runs the
// ACTUAL femgeocheck executable (not its internal functions -- this
// checks the real CLI contract, exit codes included) against every
// .fgeo file in tests/geometry/good/ (must exit 0 -- no errors;
// warnings are fine, per spec section 14) and tests/geometry/borked/
// (must exit non-zero -- at least one error). A simpler harness than
// fem3d's own fem_regress (no manifest files, no SHA256 hashes, no
// per-case expected-error-text matching) -- see docs/TODO_femgeo.md
// for upgrading to that same manifest-driven convention, which
// tests/geometry/README.md already anticipates.
//
// Usage: run_geometry_fixtures <path-to-femgeocheck> [fixtures-root]
// (fixtures-root defaults to the directory this is normally run from,
// tests/geometry/)

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Process;

var
  checkerExe, fixturesRoot: string;
  passCount, failCount: Integer;

function RunChecker(const FgeoPath: string; out ExitCode: Integer; out Output: string): Boolean;
var
  Proc: TProcess;
  OutStream: TMemoryStream;
  buf: array[0..4095] of Byte;
  n: Integer;
begin
  Proc := TProcess.Create(nil);
  OutStream := TMemoryStream.Create;
  try
    Proc.Executable := checkerExe;
    Proc.Parameters.Add(FgeoPath);
    Proc.Options := [poUsePipes];
    Proc.Execute;
    repeat
      n := Proc.Output.Read(buf, SizeOf(buf));
      if n > 0 then OutStream.WriteBuffer(buf, n);
    until n <= 0;
    Proc.WaitOnExit;
    ExitCode := Proc.ExitStatus;
    OutStream.Position := 0;
    SetLength(Output, OutStream.Size);
    if OutStream.Size > 0 then OutStream.ReadBuffer(Output[1], OutStream.Size);
    Result := True;
  finally
    OutStream.Free;
    Proc.Free;
  end;
end;

procedure CheckDir(const Dir: string; ExpectClean: Boolean);
var
  sr: TSearchRec;
  full, output: string;
  exitCode: Integer;
begin
  if FindFirst(Dir + '/*.fgeo', faAnyFile, sr) = 0 then
  begin
    repeat
      full := Dir + '/' + sr.Name;
      RunChecker(full, exitCode, output);
      if ExpectClean then
      begin
        if exitCode = 0 then
        begin
          WriteLn('PASS  ', sr.Name, '  (accepted, exit=0)');
          Inc(passCount);
        end
        else
        begin
          WriteLn('FAIL  ', sr.Name, '  -- expected exit=0 (accepted), got exit=', exitCode);
          WriteLn('      ', StringReplace(Trim(output), #10, #10'      ', [rfReplaceAll]));
          Inc(failCount);
        end;
      end
      else
      begin
        if exitCode <> 0 then
        begin
          WriteLn('PASS  ', sr.Name, '  (correctly rejected, exit=', exitCode, ')');
          Inc(passCount);
        end
        else
        begin
          WriteLn('FAIL  ', sr.Name, '  -- expected a non-zero exit (rejected), got exit=0');
          Inc(failCount);
        end;
      end;
    until FindNext(sr) <> 0;
  end;
  FindClose(sr);
end;

begin
  // Usage: run_geometry_fixtures [path-to-femgeocheck [fixtures-root]]
  // With no arguments (as test.bat runs it) it looks for femgeocheck beside this
  // executable and for the fixtures in tests/geometry under the current directory.
  if (ParamCount >= 1) and ((ParamStr(1) = '-h') or (ParamStr(1) = '--help')) then
  begin
    WriteLn('Usage: run_geometry_fixtures [path-to-femgeocheck [fixtures-root]]');
    WriteLn('  defaults: femgeocheck beside this executable; fixtures in tests/geometry');
    Halt(2);
  end;
  if ParamCount >= 1 then
    checkerExe := ParamStr(1)
  else
  begin
    checkerExe := ExtractFilePath(ParamStr(0)) + 'femgeocheck';
{$IFDEF WINDOWS}
    checkerExe := checkerExe + '.exe';
{$ENDIF}
  end;
  if ParamCount >= 2 then
    fixturesRoot := ParamStr(2)
  else
    fixturesRoot := 'tests' + DirectorySeparator + 'geometry';

  if not FileExists(checkerExe) then
  begin
    WriteLn('FAIL  femgeocheck not found at "', checkerExe, '" (build it first, or pass its path)');
    Halt(1);
  end;

  passCount := 0; failCount := 0;

  WriteLn('--- good/ (must be accepted, exit=0) ---');
  CheckDir(fixturesRoot + '/good', True);
  WriteLn;
  WriteLn('--- borked/ (must be rejected, exit<>0) ---');
  CheckDir(fixturesRoot + '/borked', False);

  WriteLn;
  WriteLn(passCount, ' / ', passCount + failCount, ' fixtures passed');
  if passCount + failCount = 0 then
  begin
    WriteLn('FAIL  no fixtures found under "', fixturesRoot, '" (run from the repository root, or pass the fixtures folder)');
    Halt(1);
  end;
  if failCount > 0 then Halt(1);
end.
