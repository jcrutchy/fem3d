program fem_regress;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, IniFiles, Process, Generics.Collections, fem_sha256;

type
  TKVMap = specialize TDictionary<string, string>;
  TValMap = specialize TDictionary<string, Double>;

  // Reads one pipe stream to EOF on its own thread. Two of these running
  // concurrently (one per pipe) is the standard fix for the classic
  // dual-pipe problem: alternating blocking reads between stdout and
  // stderr can deadlock (stuck reading one while the child blocks writing
  // a full buffer to the other), but polling via Proc.Running to avoid
  // that blocking is its own hazard -- on at least this FPC/platform
  // combination, querying Running on an already-exited process appears to
  // reap it in a way that leaves Proc.ExitStatus holding the raw,
  // unshifted wait() status (observed as exit codes like 768 instead of
  // 3). Two independent blocking readers sidestep both problems: no
  // alternation to deadlock on, and Running/WaitOnExit are only ever
  // touched once, after both pipes have hit EOF on their own.
  TPipeReaderThread = class(TThread)
  private
    FSource: TStream;
    FResult: TMemoryStream;
  protected
    procedure Execute; override;
  public
    constructor Create(ASource: TStream);
    destructor Destroy; override;
    property ResultStream: TMemoryStream read FResult;
  end;

constructor TPipeReaderThread.Create(ASource: TStream);
begin
  inherited Create(True);
  FSource := ASource;
  FResult := TMemoryStream.Create;
  FreeOnTerminate := False;
end;

destructor TPipeReaderThread.Destroy;
begin
  FResult.Free;
  inherited Destroy;
end;

procedure TPipeReaderThread.Execute;
var
  buf: array[0..4095] of Byte;
  n: LongInt;
begin
  repeat
    n := FSource.Read(buf[0], SizeOf(buf));
    if n > 0 then FResult.WriteBuffer(buf[0], n);
  until n <= 0;
end;

var
  FS: TFormatSettings;
  TargetPath, BinDir: string;
  UpdateHashesMode: Boolean;
  TotalCases, PassedCases, UnhashedCases: Integer;

procedure PrintUsage;
begin
  WriteLn('Usage: fem_regress <regression-dir-or-manifest.ini> [--bin <dir>] [--update-hashes]');
  WriteLn('  <regression-dir-or-manifest.ini>  a directory containing */manifest.ini cases,');
  WriteLn('                                     or a path to a single manifest.ini');
  WriteLn('  --bin <dir>                       directory containing solver executables (default: ./bin)');
  WriteLn('  --update-hashes                   (re)compute ModelSHA256/ManifestSHA256 and write them');
  WriteLn('                                     into the manifest, instead of running the case');
end;

// --- canonical manifest hashing -------------------------------------------
// The ManifestSHA256 field is self-referential: it hashes the manifest''s
// own content with its own value blanked out. Lines are joined with a fixed
// LF regardless of the file''s on-disk line-ending style, so the hash is
// stable across platforms/editors.
function CanonicalManifestText(const ManifestPath: string; BlankManifestHash: Boolean): string;
var
  SL: TStringList;
  i, eqPos: Integer;
  key: string;
begin
  SL := TStringList.Create;
  try
    SL.LoadFromFile(ManifestPath);
    if BlankManifestHash then
      for i := 0 to SL.Count - 1 do
      begin
        eqPos := Pos('=', SL[i]);
        if eqPos > 0 then
        begin
          key := Trim(Copy(SL[i], 1, eqPos - 1));
          if CompareText(key, 'ManifestSHA256') = 0 then
            SL[i] := 'ManifestSHA256=';
        end;
      end;
    Result := '';
    for i := 0 to SL.Count - 1 do
      Result := Result + SL[i] + #10;
  finally
    SL.Free;
  end;
end;

function ManifestHash(const ManifestPath: string): string;
var
  Raw: RawByteString;
  Bytes: TBytes;
begin
  // Hash the text's bytes exactly as they are. Going through TEncoding.UTF8.GetBytes
  // first converts the AnsiString to UTF-16 using the machine's ANSI code page, so a
  // manifest holding a non-ASCII character would hash differently on Windows (code page
  // 1252, say) than on Linux (UTF-8). For pure-ASCII manifests -- all of them today --
  // the bytes, and so every existing hash, are unchanged.
  Raw := RawByteString(CanonicalManifestText(ManifestPath, True));
  SetLength(Bytes, Length(Raw));
  if Length(Raw) > 0 then Move(Raw[1], Bytes[0], Length(Raw));
  Result := DigestToHex(SHA256Bytes(Bytes));
end;

// Names of ModelSHA256 / ManifestSHA256 lines found in any section other than [FILES].
// Only [FILES] is ever read for the integrity checks, so a hash sitting anywhere else
// (appended to the end of the file lands in whatever section comes last) is silently
// ignored -- the case LOOKS protected and is not.
function StrayHashKeys(const ManifestPath: string): string;
var
  SL: TStringList;
  i, eq: Integer;
  line, k: string;
  inFiles: Boolean;
begin
  Result := '';
  SL := TStringList.Create;
  try
    SL.LoadFromFile(ManifestPath);
    inFiles := False;
    for i := 0 to SL.Count - 1 do
    begin
      line := Trim(SL[i]);
      if (Length(line) > 1) and (line[1] = '[') then
      begin
        inFiles := SameText(line, '[FILES]');
        Continue;
      end;
      eq := Pos('=', line);
      if (eq > 0) and (not inFiles) then
      begin
        k := Trim(Copy(line, 1, eq - 1));
        if SameText(k, 'ModelSHA256') or SameText(k, 'ManifestSHA256') then
        begin
          if Result <> '' then Result := Result + ', ';
          Result := Result + k;
        end;
      end;
    end;
  finally
    SL.Free;
  end;
end;

// --- solver KV output parsing ----------------------------------------------
function RunSolver(const Exe, ModelPath: string; out ExitCode: Integer;
  out StdOutText, StdErrText: string): Boolean;
var
  Proc: TProcess;
  OutThread, ErrThread: TPipeReaderThread;
begin
  Result := True;
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := Exe;
    Proc.Parameters.Add(ModelPath);
    Proc.Options := [poUsePipes]; // keep stdout/stderr separate so BORKED cases can check stderr text
    try
      Proc.Execute;
    except
      on E: Exception do
      begin
        Result := False;
        StdErrText := 'Could not execute solver "' + Exe + '": ' + E.Message;
        ExitCode := -1;
        Exit;
      end;
    end;

    OutThread := TPipeReaderThread.Create(Proc.Output);
    ErrThread := TPipeReaderThread.Create(Proc.Stderr);
    try
      OutThread.Start;
      ErrThread.Start;
      OutThread.WaitFor;
      ErrThread.WaitFor;

      Proc.WaitOnExit;
      ExitCode := Proc.ExitStatus;

      SetString(StdOutText, PAnsiChar(OutThread.ResultStream.Memory), OutThread.ResultStream.Size);
      SetString(StdErrText, PAnsiChar(ErrThread.ResultStream.Memory), ErrThread.ResultStream.Size);
    finally
      OutThread.Free;
      ErrThread.Free;
    end;
  finally
    Proc.Free;
  end;
end;

function ParseKV(const Text: string): TValMap;
var
  Lines: TStringList;
  i, eqPos: Integer;
  line, key, valStr: string;
  val: Double;
begin
  Result := TValMap.Create;
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    for i := 0 to Lines.Count - 1 do
    begin
      line := Trim(Lines[i]);
      if (line = '') or (line[1] = '#') then Continue;
      eqPos := Pos('=', line);
      if eqPos <= 0 then Continue;
      key := Copy(line, 1, eqPos - 1);
      valStr := Copy(line, eqPos + 1, Length(line));
      if TryStrToFloat(valStr, val, FS) then
        Result.AddOrSetValue(key, val);
    end;
  finally
    Lines.Free;
  end;
end;

// --- one case ---------------------------------------------------------------
procedure RunCase(const ManifestPath: string);
var
  Ini: TMemIniFile;
  CaseDir, Status, SolverName, ModelRel, ModelPath, Exe: string;
  ExpectModelHash, ActualModelHash, ExpectManifestHash, ActualManifestHash, StrayKeys: string;
  ExitCode: Integer;
  StdOutText, StdErrText: string;
  ranOk: Boolean;
  CaseId, CaseName: string;
  CasePassed: Boolean;
  ExpKeys, MapKeys: TStringList;
  i: Integer;
  Tolerance: Double;
  key, mappedKey, expStr: string;
  expVal, actVal, diff: Double;
  actuals: TValMap;
  expectedExitCode: Integer;
  expectedErrSub: string;
begin
  CaseDir := ExtractFilePath(ExpandFileName(ManifestPath));
  Ini := TMemIniFile.Create(ManifestPath);
  actuals := nil;
  try
    CaseId := Ini.ReadString('CASE', 'ID', '?');
    CaseName := Ini.ReadString('CASE', 'Name', '(unnamed)');
    Status := UpperCase(Ini.ReadString('CASE', 'Status', 'VERIFIED'));
    SolverName := Ini.ReadString('CASE', 'Solver', 'linstatic');

    ModelRel := Ini.ReadString('FILES', 'Model', 'model.fem');
    ModelPath := CaseDir + ModelRel;
    ExpectModelHash := LowerCase(Ini.ReadString('FILES', 'ModelSHA256', ''));
    ExpectManifestHash := LowerCase(Ini.ReadString('FILES', 'ManifestSHA256', ''));

    Inc(TotalCases);
    Write(Format('[%s] %-32s ', [CaseId, CaseName]));
    CasePassed := True;

    if not FileExists(ModelPath) then
    begin
      WriteLn('FAIL  (model file not found: ' + ModelPath + ')');
      Exit;
    end;

    // --- integrity checks ---
    StrayKeys := StrayHashKeys(ManifestPath);
    if StrayKeys <> '' then
    begin
      WriteLn('FAIL  (' + StrayKeys + ' found outside [FILES]: that integrity check is NOT being applied; run --update-hashes to move it)');
      Exit;
    end;
    if (ExpectModelHash = '') or (ExpectManifestHash = '') then Inc(UnhashedCases);
    if ExpectModelHash <> '' then
    begin
      ActualModelHash := SHA256FileHex(ModelPath);
      if not SameText(ActualModelHash, ExpectModelHash) then
      begin
        WriteLn('FAIL  (model file integrity check failed -- ModelSHA256 mismatch)');
        WriteLn('        expected: ' + ExpectModelHash);
        WriteLn('        actual:   ' + ActualModelHash);
        Exit;
      end;
    end;
    if ExpectManifestHash <> '' then
    begin
      ActualManifestHash := ManifestHash(ManifestPath);
      if not SameText(ActualManifestHash, ExpectManifestHash) then
      begin
        WriteLn('FAIL  (manifest integrity check failed -- ManifestSHA256 mismatch; run --update-hashes if this edit was intentional)');
        Exit;
      end;
    end;

    // --- run the solver ---
    Exe := IncludeTrailingPathDelimiter(BinDir) + SolverName;
    ranOk := RunSolver(Exe, ModelPath, ExitCode, StdOutText, StdErrText);
    if not ranOk then
    begin
      WriteLn('FAIL  (' + StdErrText + ')');
      Exit;
    end;

    if Status = 'BORKED' then
    begin
      expectedExitCode := Ini.ReadInteger('EXPECTATIONS', 'ExpectedExitCode', -999);
      expectedErrSub := Ini.ReadString('EXPECTATIONS', 'ExpectedErrorContains', '');
      if ExitCode = 0 then
      begin
        WriteLn('FAIL  ** CRITICAL ** solver reported SUCCESS on a model that should have been rejected');
        Exit;
      end;
      if (expectedExitCode <> -999) and (ExitCode <> expectedExitCode) then
      begin
        WriteLn(Format('FAIL  (expected exit code %d, got %d)', [expectedExitCode, ExitCode]));
        Exit;
      end;
      if (expectedErrSub <> '') and (Pos(expectedErrSub, StdErrText) = 0) then
      begin
        WriteLn('FAIL  (stderr did not contain expected text: "' + expectedErrSub + '")');
        Exit;
      end;
      WriteLn(Format('PASS  (correctly rejected, exit=%d)', [ExitCode]));
      Inc(PassedCases);
      Exit;
    end;

    // Status = VERIFIED
    if ExitCode <> 0 then
    begin
      WriteLn(Format('FAIL  (solver exited %d, expected success; stderr: %s)', [ExitCode, Trim(StdErrText)]));
      Exit;
    end;

    actuals := ParseKV(StdOutText);
    Tolerance := Ini.ReadFloat('EXPECTATIONS', 'Tolerance', 1e-9);

    ExpKeys := TStringList.Create;
    MapKeys := TStringList.Create;
    try
      Ini.ReadSection('EXPECTATIONS', ExpKeys);
      Ini.ReadSection('MAP', MapKeys);
      WriteLn; // move detail lines to their own lines under the case header
      for i := 0 to ExpKeys.Count - 1 do
      begin
        key := ExpKeys[i];
        if SameText(key, 'Tolerance') then Continue;
        expStr := Ini.ReadString('EXPECTATIONS', key, '');
        if not TryStrToFloat(expStr, expVal, FS) then Continue;

        if MapKeys.IndexOf(key) >= 0 then
          mappedKey := Ini.ReadString('MAP', key, key)
        else
          mappedKey := key; // no [MAP] entry: assume the expectation key IS the solver's KV key

        if not actuals.TryGetValue(mappedKey, actVal) then
        begin
          WriteLn(Format('    %-20s FAIL  (solver output has no key "%s")', [key, mappedKey]));
          CasePassed := False;
          Continue;
        end;
        diff := Abs(actVal - expVal);
        if diff <= Tolerance then
          WriteLn(Format('    %-20s ok    (%.10e)', [key, actVal], FS))
        else
        begin
          WriteLn(Format('    %-20s FAIL  expected=%.10e actual=%.10e diff=%.3e > tol=%.3e',
            [key, expVal, actVal, diff, Tolerance], FS));
          CasePassed := False;
        end;
      end;
    finally
      ExpKeys.Free;
      MapKeys.Free;
    end;

    if CasePassed then
    begin
      WriteLn('  => PASS');
      Inc(PassedCases);
    end
    else
      WriteLn('  => FAIL');
  finally
    if Assigned(actuals) then actuals.Free;
    Ini.Free;
  end;
end;

// --- --update-hashes mode ---------------------------------------------------
// Sets Key=Value inside the [FILES] section of a manifest held in SL -- the only place
// the runner reads the integrity hashes from. An existing line there is replaced in
// place; if there is none, one is inserted at the end of [FILES] (the section is created
// if absent). Any copy of the key left in another section is removed.
procedure SetFilesKey(SL: TStringList; const Key, Value: string);
var
  i, eq, lastInFiles, filesStart: Integer;
  line, k: string;
  inFiles, placed: Boolean;
begin
  // pass 1: remove copies outside [FILES]
  inFiles := False;
  i := 0;
  while i < SL.Count do
  begin
    line := Trim(SL[i]);
    if (Length(line) > 1) and (line[1] = '[') then
      inFiles := SameText(line, '[FILES]')
    else if not inFiles then
    begin
      eq := Pos('=', line);
      if eq > 0 then
      begin
        k := Trim(Copy(line, 1, eq - 1));
        if SameText(k, Key) then
        begin
          SL.Delete(i);
          Continue;
        end;
      end;
    end;
    Inc(i);
  end;

  // pass 2: replace within [FILES], remembering where the section's last entry is
  placed := False; filesStart := -1; lastInFiles := -1; inFiles := False;
  for i := 0 to SL.Count - 1 do
  begin
    line := Trim(SL[i]);
    if (Length(line) > 1) and (line[1] = '[') then
    begin
      inFiles := SameText(line, '[FILES]');
      if inFiles then begin filesStart := i; lastInFiles := i; end;
    end
    else if inFiles then
    begin
      if line <> '' then lastInFiles := i;
      eq := Pos('=', line);
      if eq > 0 then
      begin
        k := Trim(Copy(line, 1, eq - 1));
        if SameText(k, Key) then begin SL[i] := Key + '=' + Value; placed := True; end;
      end;
    end;
  end;
  if placed then Exit;
  if filesStart >= 0 then
    SL.Insert(lastInFiles + 1, Key + '=' + Value)
  else
  begin
    if (SL.Count > 0) and (Trim(SL[SL.Count - 1]) <> '') then SL.Add('');
    SL.Add('[FILES]');
    SL.Add(Key + '=' + Value);
  end;
end;

procedure UpdateHashes(const ManifestPath: string);
var
  CaseDir, ModelRel, ModelPath, modelHash, manifestHashHex: string;
  Ini: TMemIniFile;
  SL: TStringList;
begin
  CaseDir := ExtractFilePath(ExpandFileName(ManifestPath));
  Ini := TMemIniFile.Create(ManifestPath);
  try
    ModelRel := Ini.ReadString('FILES', 'Model', 'model.fem');
    ModelPath := CaseDir + ModelRel;
  finally
    Ini.Free;
  end;

  if not FileExists(ModelPath) then
  begin
    WriteLn('  SKIP (model not found: ' + ModelPath + ')');
    Exit;
  end;
  modelHash := SHA256FileHex(ModelPath);

  SL := TStringList.Create;
  try
    SL.LoadFromFile(ManifestPath);
    SetFilesKey(SL, 'ModelSHA256', modelHash);
    // Put the manifest hash's line in its final place (empty for now) BEFORE hashing:
    // the hash is taken over the whole file with that line's value blanked, so the line
    // has to be where it will end up -- hashing first and moving it afterwards would
    // produce a hash that the runner, reading the finished file, can never reproduce.
    SetFilesKey(SL, 'ManifestSHA256', '');
    SL.LineBreak := #10;
    SL.SaveToFile(ManifestPath);
  finally
    SL.Free;
  end;

  manifestHashHex := ManifestHash(ManifestPath); // computed with ManifestSHA256 line blanked

  SL := TStringList.Create;
  try
    SL.LoadFromFile(ManifestPath);
    SetFilesKey(SL, 'ManifestSHA256', manifestHashHex);
    SL.LineBreak := #10;
    SL.SaveToFile(ManifestPath);
  finally
    SL.Free;
  end;

  WriteLn('  ModelSHA256=' + modelHash);
  WriteLn('  ManifestSHA256=' + manifestHashHex);
end;

// --- driver ------------------------------------------------------------------
procedure ProcessTarget(const Path: string);
var
  Info: TSearchRec;
  sub: string;
  Names: TStringList;
  k: Integer;
begin
  if (ExtractFileName(Path) = 'manifest.ini') or
     (not DirectoryExists(Path) and FileExists(Path)) then
  begin
    if UpdateHashesMode then
    begin
      WriteLn(Path + ':');
      UpdateHashes(Path);
    end
    else
      RunCase(Path);
    Exit;
  end;

  if DirectoryExists(Path) then
  begin
    // Collect the case folders and run them in name order. Directory enumeration order
    // is up to the file system (NTFS returns names sorted, ext4 does not), and a test
    // report whose order differs from machine to machine cannot be compared with a diff.
    Names := TStringList.Create;
    try
      if FindFirst(IncludeTrailingPathDelimiter(Path) + '*', faDirectory, Info) = 0 then
      begin
        try
          repeat
            if (Info.Name = '.') or (Info.Name = '..') then Continue;
            if (Info.Attr and faDirectory) = 0 then Continue;
            Names.Add(Info.Name);
          until FindNext(Info) <> 0;
        finally
          FindClose(Info);
        end;
      end;
      Names.Sort;
      for k := 0 to Names.Count - 1 do
      begin
        sub := IncludeTrailingPathDelimiter(Path) + Names[k];
        if FileExists(sub + PathDelim + 'manifest.ini') then
          ProcessTarget(sub + PathDelim + 'manifest.ini');
      end;
    finally
      Names.Free;
    end;
  end;
end;

var
  i: Integer;
  arg: string;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  BinDir := 'bin';
  UpdateHashesMode := False;
  TargetPath := '';

  i := 1;
  while i <= ParamCount do
  begin
    arg := ParamStr(i);
    if arg = '--bin' then
    begin
      Inc(i);
      if i > ParamCount then begin PrintUsage; Halt(1); end;
      BinDir := ParamStr(i);
    end
    else if arg = '--update-hashes' then
      UpdateHashesMode := True
    else if TargetPath = '' then
      TargetPath := arg
    else
    begin
      PrintUsage;
      Halt(1);
    end;
    Inc(i);
  end;

  if TargetPath = '' then
  begin
    PrintUsage;
    Halt(1);
  end;

  TotalCases := 0;
  PassedCases := 0;
  UnhashedCases := 0;
  ProcessTarget(TargetPath);

  if not UpdateHashesMode then
  begin
    WriteLn;
    if UnhashedCases > 0 then
      WriteLn(Format('note: %d case(s) have no integrity hashes (ModelSHA256 / ManifestSHA256 in [FILES]) and are not tamper-checked', [UnhashedCases]));
    WriteLn(Format('%d / %d cases passed', [PassedCases, TotalCases]));
    if PassedCases <> TotalCases then
      Halt(1);
  end;
  Halt(0);
end.
