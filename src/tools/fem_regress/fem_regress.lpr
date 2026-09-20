program fem_regress;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, IniFiles, Process, Generics.Collections, fem_sha256;

type
  TKVMap = specialize TDictionary<string, string>;
  TValMap = specialize TDictionary<string, Double>;

var
  FS: TFormatSettings;
  TargetPath, BinDir: string;
  UpdateHashesMode: Boolean;
  TotalCases, PassedCases: Integer;

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
begin
  Result := DigestToHex(SHA256Bytes(TEncoding.UTF8.GetBytes(
    CanonicalManifestText(ManifestPath, True))));
end;

// --- solver KV output parsing ----------------------------------------------
function RunSolver(const Exe, ModelPath: string; out ExitCode: Integer;
  out StdOutText, StdErrText: string): Boolean;
var
  Proc: TProcess;
  OutStream, ErrStream: TMemoryStream;
  buf: array[0..4095] of Byte;

  procedure DrainAll;
  var
    n1, n2, toRead: LongInt;
  begin
    // Drain both pipes non-blockingly while the process is actively executing
    while Proc.Running do
    begin
      n1 := Proc.Output.NumBytesAvailable;
      if n1 > 0 then
      begin
        toRead := n1;
        if toRead > SizeOf(buf) then toRead := SizeOf(buf);
        n1 := Proc.Output.Read(buf[0], toRead);
        if n1 > 0 then OutStream.WriteBuffer(buf[0], n1);
      end
      else
        n1 := 0;

      n2 := Proc.Stderr.NumBytesAvailable;
      if n2 > 0 then
      begin
        toRead := n2;
        if toRead > SizeOf(buf) then toRead := SizeOf(buf);
        n2 := Proc.Stderr.Read(buf[0], toRead);
        if n2 > 0 then ErrStream.WriteBuffer(buf[0], n2);
      end
      else
        n2 := 0;

      if (n1 = 0) and (n2 = 0) then
        Sleep(5);
    end;

    // Process has exited; write handles are closed so reading cannot block.
    // Drain any remaining buffered bytes until EOF.
    repeat
      n1 := Proc.Output.Read(buf[0], SizeOf(buf));
      if n1 > 0 then OutStream.WriteBuffer(buf[0], n1);
    until n1 <= 0;

    repeat
      n2 := Proc.Stderr.Read(buf[0], SizeOf(buf));
      if n2 > 0 then ErrStream.WriteBuffer(buf[0], n2);
    until n2 <= 0;
  end;

begin
  Result := True;
  Proc := TProcess.Create(nil);
  OutStream := TMemoryStream.Create;
  ErrStream := TMemoryStream.Create;
  try
    Proc.Executable := Exe;
    Proc.Parameters.Add(ModelPath);
    Proc.Options := [poUsePipes];
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
    DrainAll;
    Proc.WaitOnExit;
    ExitCode := Proc.ExitStatus;
    SetString(StdOutText, PAnsiChar(OutStream.Memory), OutStream.Size);
    SetString(StdErrText, PAnsiChar(ErrStream.Memory), ErrStream.Size);
  finally
    OutStream.Free;
    ErrStream.Free;
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
  ExpectModelHash, ActualModelHash, ExpectManifestHash, ActualManifestHash: string;
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

    ModelRel := Ini.ReadString('FILES', 'Model', 'model.json');
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
procedure UpdateHashes(const ManifestPath: string);
var
  CaseDir, ModelRel, ModelPath, modelHash, manifestHashHex: string;
  Ini: TMemIniFile;
  SL: TStringList;
  i, eqPos: Integer;
  key: string;
  found: Boolean;
begin
  CaseDir := ExtractFilePath(ExpandFileName(ManifestPath));
  Ini := TMemIniFile.Create(ManifestPath);
  try
    ModelRel := Ini.ReadString('FILES', 'Model', 'model.json');
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
    found := False;
    for i := 0 to SL.Count - 1 do
    begin
      eqPos := Pos('=', SL[i]);
      if eqPos > 0 then
      begin
        key := Trim(Copy(SL[i], 1, eqPos - 1));
        if CompareText(key, 'ModelSHA256') = 0 then
        begin
          SL[i] := 'ModelSHA256=' + modelHash;
          found := True;
        end;
      end;
    end;
    if not found then
      SL.Add('ModelSHA256=' + modelHash);
    SL.LineBreak := #10;
    SL.SaveToFile(ManifestPath);
  finally
    SL.Free;
  end;

  manifestHashHex := ManifestHash(ManifestPath); // computed with ManifestSHA256 line blanked

  SL := TStringList.Create;
  try
    SL.LoadFromFile(ManifestPath);
    found := False;
    for i := 0 to SL.Count - 1 do
    begin
      eqPos := Pos('=', SL[i]);
      if eqPos > 0 then
      begin
        key := Trim(Copy(SL[i], 1, eqPos - 1));
        if CompareText(key, 'ManifestSHA256') = 0 then
        begin
          SL[i] := 'ManifestSHA256=' + manifestHashHex;
          found := True;
        end;
      end;
    end;
    if not found then
      SL.Add('ManifestSHA256=' + manifestHashHex);
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
    if FindFirst(IncludeTrailingPathDelimiter(Path) + '*', faDirectory, Info) = 0 then
    begin
      try
        repeat
          if (Info.Name = '.') or (Info.Name = '..') then Continue;
          if (Info.Attr and faDirectory) = 0 then Continue;
          sub := IncludeTrailingPathDelimiter(Path) + Info.Name;
          if FileExists(sub + PathDelim + 'manifest.ini') then
            ProcessTarget(sub + PathDelim + 'manifest.ini');
        until FindNext(Info) <> 0;
      finally
        FindClose(Info);
      end;
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
  ProcessTarget(TargetPath);

  if not UpdateHashesMode then
  begin
    WriteLn;
    WriteLn(Format('%d / %d cases passed', [PassedCases, TotalCases]));
    if PassedCases <> TotalCases then
      Halt(1);
  end;
  Halt(0);
end.
