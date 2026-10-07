program run_femrun_test;
{$mode objfpc}{$H+}

// Tests femrun (src/tools/femrun) as vdrx would drive it: one JSON request
// line in, one JSON reply line out. Covers the gateway's security rules
// (Host/Origin/token, whitelist, tool names), its limits (input size, output
// size, timeout), exit-code/stderr handling, a real fgeo fixture through the
// real femgeocheck, and a large stdin round trip (pipe deadlock check).
//
// Run from the repository root (test.bat does). femrun and femgeocheck are
// expected next to this executable (bin/).
//
// This executable also doubles as a helper "tool" for those tests, so the
// limits can be exercised portably: run_femrun_test --echo | --sleep |
// --noisy | --exit3 | --stderr.

uses
{$IFDEF UNIX}
  cthreads,
{$ENDIF}
  SysUtils, Classes, Process, fpjson, jsonparser;

var
  Passed, Failed: Integer;
  ExeExt: string;
  BinDir, FemrunExe, CheckExe, ConfigPath, TokenConfigPath: string;

// ---------------------------------------------------------------- helper modes

procedure HelperMode(const Mode: string);
var
  Inp, Outp: THandleStream;
  Buf: array[0..8191] of Byte;
  n, i: Integer;
  Junk: string;
begin
  if Mode = '--echo' then
  begin
    Inp := THandleStream.Create(StdInputHandle);
    Outp := THandleStream.Create(StdOutputHandle);
    repeat
      n := Inp.Read(Buf[0], SizeOf(Buf));
      if n > 0 then Outp.WriteBuffer(Buf[0], n);
    until n <= 0;
    Halt(0);
  end
  else if Mode = '--greedy' then
  begin
    // writes ~1 MB of output BEFORE reading any input, then echoes its input:
    // deadlocks a gateway that feeds stdin and drains stdout from one thread
    Inp := THandleStream.Create(StdInputHandle);
    Outp := THandleStream.Create(StdOutputHandle);
    SetLength(Junk, 10000);
    FillChar(Junk[1], 10000, Ord('g'));
    Outp.WriteBuffer(Junk[1], 1000);
    Sleep(300);      // long enough for the gateway to have filled our stdin pipe
    for i := 1 to 100 do Outp.WriteBuffer(Junk[1], 10000);
    repeat
      n := Inp.Read(Buf[0], SizeOf(Buf));
      if n > 0 then Outp.WriteBuffer(Buf[0], n);
    until n <= 0;
    Halt(0);
  end
  else if Mode = '--sleep' then
  begin
    Sleep(8000);
    Halt(0);
  end
  else if Mode = '--noisy' then
  begin
    // interleaved large output on both pipes: deadlocks a naive reader
    SetLength(Junk, 4000);
    FillChar(Junk[1], 4000, Ord('x'));
    for i := 1 to 100 do
    begin
      Write(StdOut, Junk);
      Write(StdErr, Junk);
    end;
    Flush(StdOut);
    Halt(0);
  end
  else if Mode = '--exit3' then
    Halt(3)
  else if Mode = '--stderr' then
  begin
    WriteLn(StdErr, 'oops');
    WriteLn('out');
    Halt(0);
  end;
end;

// ---------------------------------------------------------------- harness

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

function ReadFile(const Path: string): string;
var
  S: TFileStream;
begin
  S := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, S.Size);
    if S.Size > 0 then S.ReadBuffer(Result[1], S.Size);
  finally
    S.Free;
  end;
end;

procedure WriteFile(const Path, Text: string);
var
  S: TFileStream;
begin
  S := TFileStream.Create(Path, fmCreate);
  try
    if Length(Text) > 0 then S.WriteBuffer(Text[1], Length(Text));
  finally
    S.Free;
  end;
end;

function MakeReq(const Method, SubPath, Query, Host, Origin, Tok, Body: string): string;
var
  O, H: TJSONObject;
begin
  O := TJSONObject.Create;
  H := TJSONObject.Create;
  try
    if Host <> '' then H.Add('Host', Host);
    if Origin <> '' then H.Add('Origin', Origin);
    if Tok <> '' then H.Add('X-Femrun-Token', Tok);
    O.Add('method', Method);
    O.Add('path', '/fem' + SubPath);
    O.Add('prefix', '/fem');
    O.Add('sub_path', SubPath);
    O.Add('query', Query);
    O.Add('headers', H);
    O.Add('body', Body);
    Result := O.AsJSON;
  finally
    O.Free;   // owns H
  end;
end;

type
  // Kills femrun if it has not finished by the deadline, so a hang in femrun
  // shows up as a FAIL instead of freezing the whole test run.
  TKiller = class(TThread)
  private
    FProc: TProcess;
    FDeadlineMs: Integer;
  protected
    procedure Execute; override;
  public
    Fired: Boolean;
    constructor Create(AProc: TProcess; ADeadlineMs: Integer);
  end;

constructor TKiller.Create(AProc: TProcess; ADeadlineMs: Integer);
begin
  FProc := AProc;
  FDeadlineMs := ADeadlineMs;
  Fired := False;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TKiller.Execute;
var
  T0: QWord;
begin
  T0 := GetTickCount64;
  while not Terminated do
  begin
    if Int64(GetTickCount64 - T0) > FDeadlineMs then
    begin
      Fired := True;
      try FProc.Terminate(1); except end;
      Exit;
    end;
    Sleep(25);
  end;
end;

// Runs femrun with the given config and request line; returns its raw stdout
// ('' if femrun had to be killed for exceeding DeadlineMs).
function CallFemrun(const Cfg, ReqLine: string; DeadlineMs: Integer = 60000): string;
var
  Proc: TProcess;
  Buf: array[0..65535] of Byte;
  n: Integer;
  Line: string;
  Killer: TKiller;
  Len: Int64;
begin
  Result := '';
  Len := 0;
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := FemrunExe;
    Proc.Parameters.Add(Cfg);
    Proc.Options := [poUsePipes, poNoConsole];
    Proc.Execute;
    Killer := TKiller.Create(Proc, DeadlineMs);
    try
      try
        Line := ReqLine + #10;
        Proc.Input.WriteBuffer(Line[1], Length(Line));
        Proc.CloseInput;
        // blocking reads: full pipe speed, no polling
        repeat
          n := Proc.Output.Read(Buf[0], SizeOf(Buf));
          if n > 0 then
          begin
            if Len + n > Length(Result) then SetLength(Result, (Len + n) * 2 + 4096);
            Move(Buf[0], Result[Len + 1], n);
            Inc(Len, n);
          end;
        until n <= 0;
      except
        // femrun killed while we were writing to it
      end;
      SetLength(Result, Len);
      Killer.Terminate;
      Killer.WaitFor;
      if Killer.Fired then Result := '';
    finally
      Killer.Free;
    end;
    try Proc.WaitOnExit; except end;
  finally
    Proc.Free;
  end;
end;

// Parses a femrun reply line. Status = -1 if it is not the promised shape.
procedure ParseReply(const Raw: string; out Status: Integer; out Inner: TJSONObject);
var
  D: TJSONData;
  Line: string;
begin
  Status := -1;
  Inner := nil;
  Line := Trim(Raw);
  if (Line = '') or (Pos(#10, Line) > 0) then Exit;   // must be exactly one line
  try
    D := GetJSON(Line);
  except
    Exit;
  end;
  if not (D is TJSONObject) then Exit;
  Status := TJSONObject(D).Get('status', -1);
  try
    D := GetJSON(TJSONObject(D).Get('body', ''));
    if D is TJSONObject then Inner := TJSONObject(D);
  except
    Status := -1;
  end;
end;

function Call(const Cfg, Method, SubPath, Query, Host, Origin, Tok, Body: string;
  out Inner: TJSONObject): Integer;
begin
  ParseReply(CallFemrun(Cfg, MakeReq(Method, SubPath, Query, Host, Origin, Tok, Body)),
    Result, Inner);
end;

const
  GoodHost = '127.0.0.1:9080';
  GoodOrigin = 'http://127.0.0.1:9080';

// ---------------------------------------------------------------- config

procedure WriteConfigs;
var
  Me, Common: string;
begin
  Me := ParamStr(0);
  Common :=
    '[FEMRUN]' + LineEnding +
    'AllowedHosts=127.0.0.1:9080,localhost:9080' + LineEnding +
    'AllowedOrigins=http://127.0.0.1:9080,http://localhost:9080' + LineEnding +
    LineEnding +
    '[TOOL echo]' + LineEnding + 'Exe=' + Me + LineEnding + 'Args=--echo' + LineEnding +
    'TimeoutMs=20000' + LineEnding + LineEnding +
    '[TOOL tinyin]' + LineEnding + 'Exe=' + Me + LineEnding + 'Args=--echo' + LineEnding +
    'MaxInputBytes=10' + LineEnding + LineEnding +
    '[TOOL sleeper]' + LineEnding + 'Exe=' + Me + LineEnding + 'Args=--sleep' + LineEnding +
    'TimeoutMs=400' + LineEnding + LineEnding +
    '[TOOL noisy]' + LineEnding + 'Exe=' + Me + LineEnding + 'Args=--noisy' + LineEnding +
    'MaxOutputBytes=1000' + LineEnding + 'TimeoutMs=20000' + LineEnding + LineEnding +
    '[TOOL greedy]' + LineEnding + 'Exe=' + Me + LineEnding + 'Args=--greedy' + LineEnding +
    'TimeoutMs=20000' + LineEnding + LineEnding +
    '[TOOL exit3]' + LineEnding + 'Exe=' + Me + LineEnding + 'Args=--exit3' + LineEnding + LineEnding +
    '[TOOL errout]' + LineEnding + 'Exe=' + Me + LineEnding + 'Args=--stderr' + LineEnding + LineEnding +
    '[TOOL fixedarg]' + LineEnding + 'Exe=' + Me + LineEnding + 'Fixed=--exit3' + LineEnding + LineEnding +
    '[TOOL missing]' + LineEnding + 'Exe=' + BinDir + 'no_such_tool_xyz' + LineEnding + LineEnding +
    '[TOOL femgeocheck]' + LineEnding + 'Exe=' + CheckExe + LineEnding + 'Fixed=-' + LineEnding +
    'TimeoutMs=20000' + LineEnding;
  WriteFile(ConfigPath, Common);
  // the same config with a token, inserted under [FEMRUN] (not at the end of the file)
  WriteFile(TokenConfigPath, StringReplace(Common, '[FEMRUN]' + LineEnding,
    '[FEMRUN]' + LineEnding + 'Token=s3cret-token' + LineEnding, []));
end;

function ConfigWithToken: string;
begin
  Result := TokenConfigPath;
end;

// ---------------------------------------------------------------- tests

var
  Inner: TJSONObject;
  St, i: Integer;
  Big, Raw, S: string;
  HasToolsBadName: Boolean;
  Arr: TJSONArray;

begin
  if (ParamCount >= 1) and (Copy(ParamStr(1), 1, 2) = '--') then
  begin
    HelperMode(ParamStr(1));
    Halt(0);
  end;

  Passed := 0;
  Failed := 0;
  BinDir := ExtractFilePath(ParamStr(0));
  ExeExt := '';
{$IFDEF WINDOWS}
  ExeExt := '.exe';
{$ENDIF}
  FemrunExe := BinDir + 'femrun' + ExeExt;
  CheckExe := BinDir + 'femgeocheck' + ExeExt;
  ConfigPath := IncludeTrailingPathDelimiter(GetTempDir) + 'femrun_test_a.ini';
  TokenConfigPath := IncludeTrailingPathDelimiter(GetTempDir) + 'femrun_test_b.ini';

  if not FileExists(FemrunExe) then
  begin
    WriteLn('FAIL  femrun not found at "', FemrunExe, '" (build it first)');
    Halt(1);
  end;
  if not FileExists(CheckExe) then
  begin
    WriteLn('FAIL  femgeocheck not found at "', CheckExe, '" (build it first)');
    Halt(1);
  end;
  WriteConfigs;

  WriteLn('--- routes and authorisation ---');
  St := Call(ConfigPath, 'GET', '/ping', '', GoodHost, '', '', '', Inner);
  Check('ping with an allowed Host', (St = 200) and (Inner <> nil) and Inner.Get('ok', False));

  St := Call(ConfigPath, 'GET', '/ping', '', 'evil.example.com', '', '', '', Inner);
  Check('wrong Host rejected (DNS-rebinding defence)', St = 403);

  St := Call(ConfigPath, 'GET', '/ping', '', '', '', '', '', Inner);
  Check('missing Host rejected', St = 403);

  St := Call(ConfigPath, 'GET', '/ping', '', GoodHost, 'http://evil.example.com', '', '', Inner);
  Check('foreign Origin rejected even on GET', St = 403);

  St := Call(ConfigPath, 'GET', '/tools', '', GoodHost, '', '', '', Inner);
  HasToolsBadName := False;
  if (St = 200) and (Inner <> nil) and (Inner.Find('tools') is TJSONArray) then
  begin
    Arr := TJSONArray(Inner.Find('tools'));
    for i := 0 to Arr.Count - 1 do
      if Arr.Objects[i].Get('name', '') = 'femgeocheck' then HasToolsBadName := True;
  end;
  Check('GET /tools lists the whitelist', HasToolsBadName);

  St := Call(ConfigPath, 'GET', '/nonsense', '', GoodHost, '', '', '', Inner);
  Check('unknown route -> 404', St = 404);

  St := Call(ConfigPath, 'POST', '/run/echo', 'a=--echo', GoodHost, '', '', 'hi', Inner);
  Check('POST with neither Origin nor token rejected', St = 403);

  St := Call(ConfigPath, 'POST', '/run/echo', 'a=--echo', GoodHost, GoodOrigin, '', 'hi', Inner);
  Check('POST with allowed Origin accepted', (St = 200) and (Inner <> nil) and (Inner.Get('stdout', '') = 'hi'));

  St := Call(ConfigWithToken, 'POST', '/run/echo', 'a=--echo', GoodHost, GoodOrigin, '', 'hi', Inner);
  Check('token configured: Origin alone is not enough', St = 403);
  St := Call(ConfigWithToken, 'POST', '/run/echo', 'a=--echo', GoodHost, GoodOrigin, 'wrong', 'hi', Inner);
  Check('token configured: wrong token rejected', St = 403);
  St := Call(ConfigWithToken, 'POST', '/run/echo', 'a=--echo', GoodHost, GoodOrigin, 's3cret-token', 'hi', Inner);
  Check('token configured: right token accepted', (St = 200) and (Inner <> nil) and (Inner.Get('stdout', '') = 'hi'));

  WriteLn('--- whitelist ---');
  St := Call(ConfigPath, 'POST', '/run/nope', '', GoodHost, GoodOrigin, '', '', Inner);
  Check('unknown tool -> 404', St = 404);
  St := Call(ConfigPath, 'POST', '/run/..%2Fecho', '', GoodHost, GoodOrigin, '', '', Inner);
  Check('tool name with path characters -> 404', St = 404);
  St := Call(ConfigPath, 'POST', '/run/../echo', '', GoodHost, GoodOrigin, '', '', Inner);
  Check('tool name with ".." -> 404', St = 404);
  St := Call(ConfigPath, 'POST', '/run/echo', 'a=--sleep', GoodHost, GoodOrigin, '', '', Inner);
  Check('flag not in the tool''s list -> 400', St = 400);
  St := Call(ConfigPath, 'POST', '/run/echo', 'a=--ECHO', GoodHost, GoodOrigin, '', 'x', Inner);
  Check('flag match is case-sensitive -> 400', St = 400);
  St := Call(ConfigPath, 'POST', '/run/echo', 'b=--echo', GoodHost, GoodOrigin, '', '', Inner);
  Check('unknown query parameter -> 400', St = 400);
  St := Call(ConfigPath, 'POST', '/run/echo', 'a=--echo%20--sleep', GoodHost, GoodOrigin, '', '', Inner);
  Check('flags cannot be smuggled in one value -> 400', St = 400);
  St := Call(ConfigPath, 'POST', '/run/missing', '', GoodHost, GoodOrigin, '', '', Inner);
  Check('configured but not installed -> 500', St = 500);

  WriteLn('--- request handling ---');
  Raw := CallFemrun(ConfigPath, 'this is not json');
  ParseReply(Raw, St, Inner);
  Check('malformed request -> 400', St = 400);

  WriteLn('--- limits and results ---');
  St := Call(ConfigPath, 'POST', '/run/tinyin', 'a=--echo', GoodHost, GoodOrigin, '', 'this is more than ten bytes', Inner);
  Check('input over MaxInputBytes -> 413', St = 413);

  St := Call(ConfigPath, 'POST', '/run/sleeper', 'a=--sleep', GoodHost, GoodOrigin, '', '', Inner);
  Check('runaway tool killed at TimeoutMs -> 504', St = 504);

  St := Call(ConfigPath, 'POST', '/run/noisy', 'a=--noisy', GoodHost, GoodOrigin, '', '', Inner);
  Check('output over MaxOutputBytes is truncated, not a hang',
    (St = 200) and (Inner <> nil) and Inner.Get('truncated', False) and
    (Length(Inner.Get('stdout', '')) <= 1000) and (Length(Inner.Get('stderr', '')) <= 1000));

  St := Call(ConfigPath, 'POST', '/run/exit3', 'a=--exit3', GoodHost, GoodOrigin, '', '', Inner);
  Check('tool exit code is reported', (St = 200) and (Inner <> nil) and (Inner.Get('exit', -1) = 3));

  St := Call(ConfigPath, 'POST', '/run/fixedarg', '', GoodHost, GoodOrigin, '', '', Inner);
  Check('Fixed arguments are always appended', (St = 200) and (Inner <> nil) and (Inner.Get('exit', -1) = 3));

  St := Call(ConfigPath, 'POST', '/run/errout', 'a=--stderr', GoodHost, GoodOrigin, '', '', Inner);
  Check('stdout and stderr are kept separate',
    (St = 200) and (Inner <> nil) and (Trim(Inner.Get('stdout', '')) = 'out') and
    (Trim(Inner.Get('stderr', '')) = 'oops'));

  // large stdin through the tool and back: must not deadlock, must be exact
  S := 'abcdefghij"\\ line' + #10;
  SetLength(Big, 120000 * Length(S));
  for i := 0 to 119999 do Move(S[1], Big[i * Length(S) + 1], Length(S));
  St := Call(ConfigPath, 'POST', '/run/echo', 'a=--echo', GoodHost, GoodOrigin, '', Big, Inner);
  Check('2 MB round trip through a tool is exact',
    (St = 200) and (Inner <> nil) and (Inner.Get('stdout', '') = Big),
    'status=' + IntToStr(St));

  // a tool that talks before it listens (Windows pipes are small: this is the
  // case that froze the first Windows run)
  Big := '';
  SetLength(Big, 300000);
  FillChar(Big[1], 300000, Ord('b'));
  St := Call(ConfigPath, 'POST', '/run/greedy', 'a=--greedy', GoodHost, GoodOrigin, '', Big, Inner);
  Check('tool that writes before reading does not deadlock the gateway',
    (St = 200) and (Inner <> nil) and (Length(Inner.Get('stdout', '')) = 1301000) and
    (Copy(Inner.Get('stdout', ''), 1, 5) = 'ggggg') and
    (Copy(Inner.Get('stdout', ''), 1001001, 5) = 'bbbbb'),
    'status=' + IntToStr(St));

  // a tool that exits without reading its (large) input must not wedge or crash femrun
  St := Call(ConfigPath, 'POST', '/run/exit3', 'a=--exit3', GoodHost, GoodOrigin, '', Big, Inner);
  Check('tool exiting without reading its input: exit code still reported',
    (St = 200) and (Inner <> nil) and (Inner.Get('exit', -1) = 3), 'status=' + IntToStr(St));

  WriteLn('--- a real tool: femgeocheck ---');
  Raw := ReadFile('tests' + DirectorySeparator + 'geometry' + DirectorySeparator + 'good' +
    DirectorySeparator + '001_rectangle.fgeo');
  St := Call(ConfigPath, 'POST', '/run/femgeocheck', '', GoodHost, GoodOrigin, '', Raw, Inner);
  Check('good .fgeo accepted (exit 0)', (St = 200) and (Inner <> nil) and (Inner.Get('exit', -1) = 0),
    'status=' + IntToStr(St));

  Raw := ReadFile('tests' + DirectorySeparator + 'geometry' + DirectorySeparator + 'borked' +
    DirectorySeparator + '001_dangling_edge.fgeo');
  St := Call(ConfigPath, 'POST', '/run/femgeocheck', '', GoodHost, GoodOrigin, '', Raw, Inner);
  Check('borked .fgeo rejected with a GEO diagnostic',
    (St = 200) and (Inner <> nil) and (Inner.Get('exit', 0) <> 0) and
    (Pos('GEO', Inner.Get('stdout', '') + Inner.Get('stderr', '')) > 0),
    'status=' + IntToStr(St));

  DeleteFile(ConfigPath);
  DeleteFile(TokenConfigPath);

  WriteLn;
  WriteLn(Passed, ' / ', Passed + Failed, ' checks passed');
  if Failed = 0 then WriteLn('ALL CHECKS PASSED') else Halt(1);
end.
