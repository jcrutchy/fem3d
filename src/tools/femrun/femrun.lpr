program femrun;
{$mode objfpc}{$H+}

// femrun -- a tiny, locked-down "run a whitelisted CLI tool" gateway.
//
// Written to be the target of a vdrx bus-protocol route (cli_bridges with
// "protocol": "bus"), so a browser page can run the suite's command-line
// tools without a browser ever being able to launch anything it likes:
//
//   stdin  : ONE line of JSON, vdrx's request object
//            {"method","path","prefix","sub_path","query","headers","body"}
//   stdout : ONE line of JSON   {"status":200,"body":"<a JSON document, as a string>"}
//
// Nothing else is ever written to stdout. See docs/femrun.md.
//
// Routes (sub_path = whatever follows the vdrx route prefix):
//   GET  /ping            health check
//   GET  /tools           the whitelist (names, allowed flags, limits)
//   POST /run/<tool>?a=<flag>&a=<flag>...   body -> the tool's stdin
//
// Safety rules (all enforced here, none delegated to the caller):
//   * tools come only from the config file; the request supplies a NAME that
//     is looked up, never a path
//   * no shell; arguments are an array, each must exactly match the tool's
//     whitelist ("Args"); the config's "Fixed" arguments are always appended
//   * Host header must be in AllowedHosts (defeats DNS rebinding); an Origin
//     header, if present, must be in AllowedOrigins
//   * POST needs a matching Origin, or the configured token (X-Femrun-Token)
//   * input size, output size and run time are capped per tool

uses
{$IFDEF UNIX}
  cthreads, BaseUnix,
{$ENDIF}
  SysUtils, Classes, Process, Pipes, IniFiles, fpjson, jsonparser;

type
  TTool = record
    Name: string;
    Exe: string;
    Args: TStringList;       // client-selectable flags (exact match)
    Fixed: TStringList;      // always appended (e.g. "-" to read stdin)
    TimeoutMs: Integer;
    MaxInput: Int64;
    MaxOutput: Int64;
    Cwd: string;
  end;

  // Feeds a tool's stdin from its own thread. The main thread must never
  // block writing to the tool: a tool that writes output before it has read
  // its input (or whose pipes are small, as on Windows) would then deadlock
  // against us, each side waiting for the other to make room.
  TFeeder = class(TThread)
  private
    FProc: TProcess;
    FData: string;
  protected
    procedure Execute; override;
  public
    constructor Create(AProc: TProcess; const AData: string);
  end;

  // Reads one of the tool's output pipes with blocking reads on its own
  // thread (polling with Sleep() is far too slow on Windows, whose timer tick
  // is ~15 ms and whose pipe buffers are only a few KB). Keeps at most FCap
  // bytes; the rest is still read, so the tool never blocks on a full pipe.
  TReader = class(TThread)
  private
    FStream: TStream;
    FCap: Int64;
  protected
    procedure Execute; override;
  public
    Data: string;
    Truncated: Boolean;
    constructor Create(AStream: TStream; ACap: Int64);
  end;

var
  Cfg: TMemIniFile;
  BaseDir: string;
  AllowedHosts, AllowedOrigins: TStringList;
  Token: string;

constructor TFeeder.Create(AProc: TProcess; const AData: string);
begin
  FProc := AProc;
  FData := AData;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TFeeder.Execute;
var
  Pos, N, W: Integer;
begin
  try
    Pos := 0;
    while (Pos < Length(FData)) and not Terminated do
    begin
      N := Length(FData) - Pos;
      if N > 32768 then N := 32768;
      W := FProc.Input.Write(FData[Pos + 1], N);
      if W <= 0 then Break;
      Inc(Pos, W);
    end;
  except
    // the tool closed its stdin or exited early: nothing more to feed
  end;
  try
    FProc.CloseInput;
  except
  end;
end;

constructor TReader.Create(AStream: TStream; ACap: Int64);
begin
  FStream := AStream;
  FCap := ACap;
  Data := '';
  Truncated := False;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TReader.Execute;
var
  Tmp: array[0..16383] of Byte;
  N: Integer;
  Take, Len: Int64;
begin
  Len := 0;
  try
    while True do
    begin
      N := FStream.Read(Tmp[0], SizeOf(Tmp));
      if N <= 0 then Break;
      Take := N;
      if Len + Take > FCap then
      begin
        Truncated := True;
        Take := FCap - Len;
        if Take < 0 then Take := 0;
      end;
      if Take > 0 then
      begin
        if Len + Take > Length(Data) then
          SetLength(Data, (Len + Take) * 2 + 4096);
        Move(Tmp[0], Data[Len + 1], Take);
        Inc(Len, Take);
      end;
    end;
  except
    // pipe closed under us (tool killed): keep what we have
  end;
  SetLength(Data, Len);
end;

// ------------------------------------------------------------ JSON output

// Escape a byte string as a JSON string body. Valid UTF-8 passes through;
// invalid bytes become '?', so the reply line is always valid JSON.
function JsonEscape(const S: string): string;
var
  Buf: string;
  Len: Integer;

  procedure Put(const Piece: string);
  begin
    if Len + Length(Piece) > Length(Buf) then
      SetLength(Buf, (Len + Length(Piece)) * 2 + 64);
    Move(Piece[1], Buf[Len + 1], Length(Piece));
    Inc(Len, Length(Piece));
  end;

  procedure PutC(C: Char);
  begin
    if Len + 1 > Length(Buf) then SetLength(Buf, Length(Buf) * 2 + 64);
    Inc(Len);
    Buf[Len] := C;
  end;

var
  i, n, k: Integer;
  c: Byte;
  Need: Integer;
  Ok: Boolean;
begin
  Buf := '';
  Len := 0;
  SetLength(Buf, Length(S) + 64);
  i := 1;
  n := Length(S);
  while i <= n do
  begin
    c := Byte(S[i]);
    if c < 128 then
    begin
      case c of
        34: Put('\"');
        92: Put('\\');
        8:  Put('\b');
        9:  Put('\t');
        10: Put('\n');
        12: Put('\f');
        13: Put('\r');
      else
        if c < 32 then Put('\u00' + IntToHex(c, 2))
        else PutC(Char(c));
      end;
      Inc(i);
    end
    else
    begin
      if (c >= $C2) and (c <= $DF) then Need := 1
      else if (c >= $E0) and (c <= $EF) then Need := 2
      else if (c >= $F0) and (c <= $F4) then Need := 3
      else Need := -1;
      Ok := (Need > 0) and (i + Need <= n);
      if Ok then
        for k := 1 to Need do
          if (Byte(S[i + k]) and $C0) <> $80 then Ok := False;
      if Ok then
      begin
        Put(Copy(S, i, Need + 1));
        Inc(i, Need + 1);
      end
      else
      begin
        PutC('?');
        Inc(i);
      end;
    end;
  end;
  SetLength(Buf, Len);
  Result := Buf;
end;

function Q(const S: string): string;
begin
  Result := '"' + JsonEscape(S) + '"';
end;

procedure Reply(Status: Integer; const InnerJson: string);
begin
  Write(StdOut, '{"status":', Status, ',"body":', Q(InnerJson), '}', #10);
  Flush(StdOut);
  Halt(0);
end;

procedure Fail(Status: Integer; const Msg: string);
begin
  Reply(Status, '{"error":' + Q(Msg) + '}');
end;

// ------------------------------------------------------------ helpers

function UrlDecode(const S: string): string;
var
  i: Integer;
  h: string;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = '%') and (i + 2 <= Length(S)) then
    begin
      h := Copy(S, i + 1, 2);
      if StrToIntDef('$' + h, -1) >= 0 then
      begin
        Result := Result + Char(StrToInt('$' + h));
        Inc(i, 3);
        Continue;
      end;
    end;
    if S[i] = '+' then Result := Result + ' ' else Result := Result + S[i];
    Inc(i);
  end;
end;

procedure SplitList(const S: string; Dest: TStringList; Sep: Char);
var
  i, st: Integer;
  Item: string;
begin
  st := 1;
  for i := 1 to Length(S) + 1 do
    if (i > Length(S)) or (S[i] = Sep) then
    begin
      Item := Trim(Copy(S, st, i - st));
      if Item <> '' then Dest.Add(Item);
      st := i + 1;
    end;
end;

function HeaderValue(Headers: TJSONObject; const Name: string): string;
var
  i: Integer;
begin
  Result := '';
  if Headers = nil then Exit;
  for i := 0 to Headers.Count - 1 do
    if SameText(Headers.Names[i], Name) then
      Exit(Headers.Items[i].AsString);
end;

function InList(L: TStringList; const S: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to L.Count - 1 do
    if SameText(L[i], S) then Exit(True);
end;

function ValidName(const S: string): Boolean;
var
  i: Integer;
begin
  Result := (S <> '') and (Length(S) <= 64);
  for i := 1 to Length(S) do
    if not (S[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then Exit(False);
end;

function IsAbs(const P: string): Boolean;
begin
  Result := (P <> '') and ((P[1] = '/') or (P[1] = '\') or
    ((Length(P) >= 2) and (P[2] = ':')));
end;

function ResolvePath(const P: string): string;
begin
  if (P = '') then Exit('');
  if IsAbs(P) then Result := P
  else Result := ExpandFileName(IncludeTrailingPathDelimiter(BaseDir) + P);
end;

function LoadTool(const Name: string; out T: TTool): Boolean;
var
  Sec: string;
begin
  Result := False;
  Sec := 'TOOL ' + Name;
  if not Cfg.SectionExists(Sec) then Exit;
  T.Name := Name;
  T.Exe := ResolvePath(Cfg.ReadString(Sec, 'Exe', ''));
  T.Args := TStringList.Create;
  T.Args.CaseSensitive := True;      // the flag whitelist is an EXACT match
  T.Fixed := TStringList.Create;
  SplitList(Cfg.ReadString(Sec, 'Args', ''), T.Args, ' ');
  SplitList(Cfg.ReadString(Sec, 'Fixed', ''), T.Fixed, ' ');
  T.TimeoutMs := Cfg.ReadInteger(Sec, 'TimeoutMs', 10000);
  T.MaxInput := StrToInt64Def(Cfg.ReadString(Sec, 'MaxInputBytes', '8000000'), 8000000);
  T.MaxOutput := StrToInt64Def(Cfg.ReadString(Sec, 'MaxOutputBytes', '16000000'), 16000000);
  T.Cwd := ResolvePath(Cfg.ReadString(Sec, 'Cwd', ''));
  if T.Cwd = '' then T.Cwd := BaseDir;
  Result := True;
end;

// ------------------------------------------------------------ authorisation

procedure Authorise(const Method: string; Headers: TJSONObject);
var
  Host, Origin, Tok: string;
begin
  Host := HeaderValue(Headers, 'Host');
  if (AllowedHosts.Count = 0) or not InList(AllowedHosts, Host) then
    Fail(403, 'Host not allowed');
  Origin := HeaderValue(Headers, 'Origin');
  if (Origin <> '') and not InList(AllowedOrigins, Origin) then
    Fail(403, 'Origin not allowed');
  if not SameText(Method, 'GET') then
  begin
    if Token <> '' then
    begin
      Tok := HeaderValue(Headers, 'X-Femrun-Token');
      if Tok <> Token then Fail(403, 'Missing or wrong token');
    end
    else if Origin = '' then
      Fail(403, 'POST needs an allowed Origin or a token');
  end;
end;

// ------------------------------------------------------------ running a tool

procedure RunTool(const T: TTool; const Query, Body: string);
var
  Proc: TProcess;
  Params: TStringList;
  i, p: Integer;
  Pair, Key, Val: string;
  OutBuf, ErrBuf: string;
  OutTrunc, ErrTrunc, TimedOut: Boolean;
  Feeder: TFeeder;
  OutReader, ErrReader: TReader;
  Start, GraceStart: QWord;
  ExitCode: Integer;
begin
  if Int64(Length(Body)) > T.MaxInput then Fail(413, 'Input too large for this tool');
  if not FileExists(T.Exe) then Fail(500, 'Tool executable not found on this machine');

  // query: only "a=<flag>" is understood
  Params := TStringList.Create;
  try
    p := 1;
    while p <= Length(Query) + 1 do
    begin
      i := p;
      while (i <= Length(Query)) and (Query[i] <> '&') do Inc(i);
      Pair := Copy(Query, p, i - p);
      p := i + 1;
      if Pair = '' then Continue;
      Key := Pair;
      Val := '';
      if Pos('=', Pair) > 0 then
      begin
        Key := Copy(Pair, 1, Pos('=', Pair) - 1);
        Val := UrlDecode(Copy(Pair, Pos('=', Pair) + 1, MaxInt));
      end;
      if Key <> 'a' then Fail(400, 'Unknown query parameter: ' + Key);
      if T.Args.IndexOf(Val) < 0 then
        Fail(400, 'Argument not allowed for this tool: ' + Val);
      Params.Add(Val);
    end;

    Proc := TProcess.Create(nil);
    try
      Proc.Executable := T.Exe;
      for i := 0 to Params.Count - 1 do Proc.Parameters.Add(Params[i]);
      for i := 0 to T.Fixed.Count - 1 do Proc.Parameters.Add(T.Fixed[i]);
      Proc.CurrentDirectory := T.Cwd;
      Proc.Options := [poUsePipes, poNoConsole];
      Proc.ShowWindow := swoHide;

      TimedOut := False;
      Feeder := nil;
      Start := GetTickCount64;
      try
        Proc.Execute;
      except
        on E: Exception do Fail(500, 'Could not start tool: ' + E.Message);
      end;

      // One thread per pipe, each doing blocking I/O: stdin is fed, stdout and
      // stderr are drained, all at once, so no pipe can fill up and stall the
      // tool (or us).
      OutReader := TReader.Create(Proc.Output, T.MaxOutput);
      ErrReader := TReader.Create(Proc.Stderr, T.MaxOutput);
      if Length(Body) = 0 then
      begin
        try Proc.CloseInput; except end;
      end
      else
        Feeder := TFeeder.Create(Proc, Body);

      // wait for the tool to finish (or the time limit)
      while Proc.Running do
      begin
        if Int64(GetTickCount64 - Start) > T.TimeoutMs then
        begin
          TimedOut := True;
          Proc.Terminate(1);
          Break;
        end;
        Sleep(2);
      end;

      // The tool is gone: its pipes close, the readers reach end-of-file and a
      // blocked stdin write fails. Give them a moment; a grandchild that kept
      // a pipe open must not be able to hold us here forever.
      GraceStart := GetTickCount64;
      while not (OutReader.Finished and ErrReader.Finished) and
            (Int64(GetTickCount64 - GraceStart) < 3000) do
        Sleep(2);
      if Feeder <> nil then
      begin
        Feeder.Terminate;
        if Feeder.Finished or (Int64(GetTickCount64 - GraceStart) < 3000) then
          Feeder.WaitFor;
      end;
      try Proc.WaitOnExit; except end;
      ExitCode := Proc.ExitCode;   // decoded exit code (ExitStatus is the raw wait status on Unix)

      OutBuf := OutReader.Data;   OutTrunc := OutReader.Truncated;
      ErrBuf := ErrReader.Data;   ErrTrunc := ErrReader.Truncated;
      if OutReader.Finished then OutReader.Free;
      if ErrReader.Finished then ErrReader.Free;
      if (Feeder <> nil) and Feeder.Finished then Feeder.Free;
    finally
      Proc.Free;
    end;

    if TimedOut then
      Reply(504, '{"error":"Tool timed out","tool":' + Q(T.Name) + ',"timeout_ms":' +
        IntToStr(T.TimeoutMs) + '}');

    Reply(200, '{"tool":' + Q(T.Name) + ',"exit":' + IntToStr(ExitCode) +
      ',"stdout":' + Q(OutBuf) + ',"stderr":' + Q(ErrBuf) +
      ',"truncated":' + LowerCase(BoolToStr(OutTrunc or ErrTrunc, True)) +
      ',"ms":' + IntToStr(Int64(GetTickCount64 - Start)) + '}');
  finally
    Params.Free;
  end;
end;

// ------------------------------------------------------------ routing

procedure ListTools;
var
  Secs: TStringList;
  i, j, n: Integer;
  T: TTool;
  S, A: string;
begin
  Secs := TStringList.Create;
  try
    Cfg.ReadSections(Secs);
    Secs.Sort;
    S := '';
    n := 0;
    for i := 0 to Secs.Count - 1 do
      if Copy(Secs[i], 1, 5) = 'TOOL ' then
        if LoadTool(Copy(Secs[i], 6, MaxInt), T) then
        begin
          A := '';
          for j := 0 to T.Args.Count - 1 do
          begin
            if A <> '' then A := A + ',';
            A := A + Q(T.Args[j]);
          end;
          if n > 0 then S := S + ',';
          S := S + '{"name":' + Q(T.Name) + ',"args":[' + A + '],"timeout_ms":' +
            IntToStr(T.TimeoutMs) + ',"max_input_bytes":' + IntToStr(T.MaxInput) + '}';
          Inc(n);
        end;
    Reply(200, '{"tools":[' + S + ']}');
  finally
    Secs.Free;
  end;
end;

var
  StdinBuf: array[0..65535] of Byte;

procedure Main;
var
  Line, CfgPath, Method, SubPath, Query, Body, ToolName: string;
  Data: TJSONData;
  Req, Headers: TJSONObject;
  T: TTool;
begin
  if ParamCount >= 1 then CfgPath := ParamStr(1)
  else CfgPath := ExtractFilePath(ParamStr(0)) + 'femrun.ini';
  if not FileExists(CfgPath) then Fail(500, 'femrun config not found');
  CfgPath := ExpandFileName(CfgPath);
  BaseDir := ExtractFilePath(CfgPath);
  Cfg := TMemIniFile.Create(CfgPath);
  AllowedHosts := TStringList.Create;
  AllowedOrigins := TStringList.Create;
  SplitList(Cfg.ReadString('FEMRUN', 'AllowedHosts', ''), AllowedHosts, ',');
  SplitList(Cfg.ReadString('FEMRUN', 'AllowedOrigins', ''), AllowedOrigins, ',');
  Token := Cfg.ReadString('FEMRUN', 'Token', '');
  if Cfg.ReadString('FEMRUN', 'BaseDir', '') <> '' then
    BaseDir := IncludeTrailingPathDelimiter(ResolvePath(Cfg.ReadString('FEMRUN', 'BaseDir', '')));

  SetTextBuf(Input, StdinBuf, SizeOf(StdinBuf));
  Line := '';
  ReadLn(Line);
  try
    Data := GetJSON(Line);
  except
    Fail(400, 'Request is not valid JSON');
  end;
  if not (Data is TJSONObject) then Fail(400, 'Request is not a JSON object');
  Req := TJSONObject(Data);

  Method := Req.Get('method', '');
  SubPath := Req.Get('sub_path', '');
  Query := Req.Get('query', '');
  Body := Req.Get('body', '');
  Headers := nil;
  if Req.Find('headers') is TJSONObject then Headers := TJSONObject(Req.Find('headers'));

  Authorise(Method, Headers);

  if (SameText(Method, 'GET')) and (SubPath = '/ping') then
    Reply(200, '{"ok":true,"femrun":1}');
  if (SameText(Method, 'GET')) and (SubPath = '/tools') then
    ListTools;
  if SameText(Method, 'POST') and (Copy(SubPath, 1, 5) = '/run/') then
  begin
    ToolName := Copy(SubPath, 6, MaxInt);
    if not ValidName(ToolName) then Fail(404, 'No such tool');
    if not LoadTool(ToolName, T) then Fail(404, 'No such tool');
    RunTool(T, Query, Body);
  end;
  Fail(404, 'No such route');
end;

begin
{$IFDEF UNIX}
  // a tool that exits before reading all its input must not kill us with SIGPIPE
  FpSignal(SIGPIPE, SignalHandler(SIG_IGN));
{$ENDIF}
  try
    Main;
  except
    on E: Exception do
      Reply(500, '{"error":' + Q('Internal error: ' + E.Message) + '}');
  end;
end.
