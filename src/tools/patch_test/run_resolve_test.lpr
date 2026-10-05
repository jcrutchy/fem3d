program run_resolve_test;

{$mode objfpc}{$H+}

// Two groups of checks:
//
//  1. CATALOGUE.  Every catalogue section that can be built is rebuilt from its
//     printed dimensions, run through the section calculator, and compared with
//     the catalogue's own printed values.  tests/liberty/manifest.ini pins
//     the SHA-256 of liberty_db.json (and of itself), so editing the database --
//     or loosening a tolerance -- is noticed instead of quietly passing.
//
//  2. RESOLVER.  femresolve's engine (fem_resolve): references expand to the right
//     numbers in the right units, bad references are refused with a clear message,
//     and nothing is guessed.
//
//   run_resolve_test [manifest.ini] [--update-hashes]
//
// --update-hashes rewrites DatabaseSHA256 and ManifestSHA256 in the manifest after a
// deliberate change to the database or the manifest; it does not run any check.

uses
  SysUtils, Classes, IniFiles, Math,
  fem_types, fem_native_model, fem_fingerprint, fem_sha256,
  fem_section_types, fem_section_calc, fem_section_db, fem_resolve;

var
  Checks, Fails: Integer;
  GFmt: TFormatSettings;

procedure Check(const Name: string; Ok: Boolean; const Detail: string = '');
begin
  Inc(Checks);
  if Ok then
    WriteLn('PASS  ', Name)
  else
  begin
    Inc(Fails);
    if Detail <> '' then WriteLn('FAIL  ', Name, '  -- ', Detail) else WriteLn('FAIL  ', Name);
  end;
end;

function RelPct(Got, Want: Double): Double;
begin
  if Want = 0 then Result := 0 else Result := 100.0 * (Got - Want) / Want;
end;

// ---------------------------------------------------------------------------
// manifest hashing -- the same rule as fem_regress (docs/regression_testing.md):
// ManifestSHA256 hashes the manifest with its own value blanked, lines joined by LF.
// ---------------------------------------------------------------------------

function ManifestHashOf(const Path: string): string;
var
  SL: TStringList;
  i, eq: Integer;
  txt: RawByteString;
  Bytes: TBytes;
begin
  SL := TStringList.Create;
  try
    SL.LoadFromFile(Path);
    for i := 0 to SL.Count - 1 do
    begin
      eq := Pos('=', SL[i]);
      if (eq > 0) and SameText(Trim(Copy(SL[i], 1, eq - 1)), 'ManifestSHA256') then
        SL[i] := 'ManifestSHA256=';
    end;
    txt := '';
    for i := 0 to SL.Count - 1 do txt := txt + RawByteString(SL[i]) + #10;
  finally
    SL.Free;
  end;
  SetLength(Bytes, Length(txt));
  if Length(txt) > 0 then Move(txt[1], Bytes[0], Length(txt));
  Result := DigestToHex(SHA256Bytes(Bytes));
end;

procedure SetKeyInFiles(SL: TStringList; const Key, Value: string);
var
  i, eq: Integer;
  line: string;
  inFiles: Boolean;
begin
  inFiles := False;
  for i := 0 to SL.Count - 1 do
  begin
    line := Trim(SL[i]);
    if (Length(line) > 1) and (line[1] = '[') then
      inFiles := SameText(line, '[FILES]')
    else if inFiles then
    begin
      eq := Pos('=', line);
      if (eq > 0) and SameText(Trim(Copy(line, 1, eq - 1)), Key) then
      begin
        SL[i] := Key + '=' + Value;
        Exit;
      end;
    end;
  end;
  raise Exception.CreateFmt('manifest has no %s= line in [FILES]', [Key]);
end;

procedure UpdateManifestHashes(const ManifestPath: string);
var
  Ini: TMemIniFile;
  SL: TStringList;
  dbPath: string;
begin
  Ini := TMemIniFile.Create(ManifestPath);
  try
    dbPath := ExtractFilePath(ExpandFileName(ManifestPath)) + Ini.ReadString('FILES', 'Database', '');
  finally
    Ini.Free;
  end;
  if not FileExists(dbPath) then raise Exception.CreateFmt('database not found: %s', [dbPath]);
  SL := TStringList.Create;
  try
    SL.LoadFromFile(ManifestPath);
    SetKeyInFiles(SL, 'DatabaseSHA256', SHA256FileHex(dbPath));
    SetKeyInFiles(SL, 'ManifestSHA256', '');
    SL.LineBreak := #10;
    SL.SaveToFile(ManifestPath);
  finally
    SL.Free;
  end;
  SL := TStringList.Create;
  try
    SL.LoadFromFile(ManifestPath);
    SetKeyInFiles(SL, 'ManifestSHA256', ManifestHashOf(ManifestPath));
    SL.LineBreak := #10;
    SL.SaveToFile(ManifestPath);
  finally
    SL.Free;
  end;
  WriteLn('DatabaseSHA256=', SHA256FileHex(dbPath));
  WriteLn('ManifestSHA256=', ManifestHashOf(ManifestPath));
end;

function FindManifest(const Given: string): string;
var
  exeDir: string;
  cand: array[0..3] of string;
  i: Integer;
begin
  if Given <> '' then Exit(Given);
  exeDir := ExtractFilePath(ParamStr(0));
  cand[0] := 'tests' + DirectorySeparator + 'liberty' + DirectorySeparator + 'manifest.ini';
  cand[1] := '..' + DirectorySeparator + cand[0];
  cand[2] := exeDir + cand[0];
  cand[3] := exeDir + '..' + DirectorySeparator + cand[0];
  for i := 0 to High(cand) do
    if FileExists(cand[i]) then Exit(cand[i]);
  Result := cand[0];
end;

// ---------------------------------------------------------------------------
// 1. catalogue
// ---------------------------------------------------------------------------

var
  Worst: array[0..9] of Double;
  WorstName: array[0..9] of string;
const
  PropNames: array[0..9] of string = ('Ag', 'Ix', 'Iy', 'Zx', 'Sx', 'Zy', 'Sy', 'J', 'XL', '-');

procedure Note(Idx: Integer; const Sec: string; Pct: Double);
begin
  if Abs(Pct) > Abs(Worst[Idx]) then
  begin
    Worst[Idx] := Pct;
    WorstName[Idx] := Sec;
  end;
end;

procedure TestCatalogue(const ManifestPath: string);
var
  Ini: TMemIniFile;
  dbPath, wantDbHash, wantManHash, why, err, bad: string;
  geomTol, jTolI, jTolC, jTol, pct: Double;
  expSections, expBuildable: Integer;
  Db: TSectionDb;
  i, built, refused, wrongRefusals: Integer;
  E: TSectionEntry;
  Props: TSectionProperties;
  shape: TSectionShape;
  Faces: TSectionFaceArray;
  zyWant: Double;

  procedure Cmp(Idx: Integer; Got, Want, Tolerance: Double);
  begin
    if IsNaN(Want) or (Want = 0) then Exit;
    pct := RelPct(Got, Want);
    Note(Idx, E.Designation, pct);
    if Abs(pct) > Tolerance then
      bad := bad + Format(' %s %.2f%% (limit %.1f%%);', [PropNames[Idx], pct, Tolerance]);
  end;

begin
  WriteLn('=== 1. LIBERTY CATALOGUE: COMPUTED vs PRINTED ===');
  if not FileExists(ManifestPath) then
  begin
    Check('catalogue manifest found', False,
      ManifestPath + ' not found (run from the repository root, or pass the manifest path)');
    Exit;
  end;
  Ini := TMemIniFile.Create(ManifestPath);
  try
    dbPath := ExtractFilePath(ExpandFileName(ManifestPath)) + Ini.ReadString('FILES', 'Database', '');
    wantDbHash := LowerCase(Ini.ReadString('FILES', 'DatabaseSHA256', ''));
    wantManHash := LowerCase(Ini.ReadString('FILES', 'ManifestSHA256', ''));
    geomTol := StrToFloatDef(Ini.ReadString('EXPECTATIONS', 'GeometryTolerancePercent', ''), -1, GFmt);
    jTolI := StrToFloatDef(Ini.ReadString('EXPECTATIONS', 'JTolerancePercent.IBeam', ''), -1, GFmt);
    jTolC := StrToFloatDef(Ini.ReadString('EXPECTATIONS', 'JTolerancePercent.Channel', ''), -1, GFmt);
    expSections := StrToIntDef(Ini.ReadString('EXPECTATIONS', 'Sections', ''), -1);
    expBuildable := StrToIntDef(Ini.ReadString('EXPECTATIONS', 'Buildable', ''), -1);
  finally
    Ini.Free;
  end;

  Check('manifest integrity (ManifestSHA256)',
    (wantManHash <> '') and (ManifestHashOf(ManifestPath) = wantManHash),
    'the manifest was edited without --update-hashes; if the edit was intended run: run_resolve_test --update-hashes');
  Check('database present', FileExists(dbPath), dbPath + ' not found');
  if not FileExists(dbPath) then Exit;
  Check('database integrity (DatabaseSHA256)',
    (wantDbHash <> '') and (SHA256FileHex(dbPath) = wantDbHash),
    'liberty_db.json differs from the version these tests were verified against; check the change, then run: run_resolve_test --update-hashes');
  Check('tolerances present in manifest', (geomTol > 0) and (jTolI > 0) and (jTolC > 0));
  if not (geomTol > 0) then Exit;

  if not LoadSectionDb(dbPath, Db, err) then
  begin
    Check('database loads', False, err);
    Exit;
  end;
  Check('database loads; every designation is unique', True);
  Check('section count matches manifest', Length(Db.Entries) = expSections,
    Format('database has %d sections, manifest expects %d', [Length(Db.Entries), expSections]));

  built := 0;
  refused := 0;
  wrongRefusals := 0;
  for i := 0 to High(Worst) do begin Worst[i] := 0; WorstName[i] := ''; end;

  for i := 0 to High(Db.Entries) do
  begin
    E := Db.Entries[i];
    shape := ShapeForCategory(E.Category, why);
    if shape = ssUnsupported then
    begin
      Inc(refused);
      // must be refused with a reason, never guessed
      if BuildEntryFaces(E, Faces, err) or (err = '') then Inc(wrongRefusals);
      Continue;
    end;

    if not ComputeEntryProperties(E, Props, err) then
    begin
      Check('catalogue ' + E.Designation, False, err);
      Continue;
    end;
    Inc(built);
    bad := '';
    if shape = ssIBeam then jTol := jTolI else jTol := jTolC;
    Cmp(0, Props.Area, E.Ag, geomTol);
    Cmp(1, Props.Ixx, E.Ix * CatalogueMomentScale, geomTol);
    Cmp(2, Props.Iyy, E.Iy * CatalogueMomentScale, geomTol);
    Cmp(3, Props.Zx, E.Zx * CatalogueModulusScale, geomTol);
    Cmp(4, Props.Sx, E.Sx * CatalogueModulusScale, geomTol);
    if shape = ssChannel then
    begin
      // the catalogue gives the two Zy values; the calculator's Zy is the smaller
      zyWant := Min(E.ZyR, E.ZyL);
      Cmp(8, Props.CentroidX, E.XL, geomTol);
    end
    else
      zyWant := E.Zy;
    Cmp(5, Props.Zy, zyWant * CatalogueModulusScale, geomTol);
    Cmp(6, Props.Sy, E.Sy * CatalogueModulusScale, geomTol);
    Cmp(7, Props.J, E.J * CatalogueTorsionScale, jTol);
    Check('catalogue ' + E.Designation, bad = '', bad);
  end;

  Check('buildable section count matches manifest', built = expBuildable,
    Format('%d sections built, manifest expects %d', [built, expBuildable]));
  Check('unbuildable sections (tapered flange, angles) are refused with a reason', wrongRefusals = 0,
    Format('%d of %d were built or refused without an explanation', [wrongRefusals, refused]));
  Check('every catalogue entry is either computed or refused (none skipped)', built + refused = Length(Db.Entries),
    Format('%d built + %d refused <> %d', [built, refused, Length(Db.Entries)]));

  WriteLn;
  WriteLn('  worst agreement with the printed catalogue over ', built, ' sections:');
  for i := 0 to 8 do
    if WorstName[i] <> '' then
      WriteLn(Format('    %-3s %7.2f%%   (%s)', [PropNames[i], Worst[i], WorstName[i]]));
  WriteLn;
end;

// ---------------------------------------------------------------------------
// 2. resolver
// ---------------------------------------------------------------------------

var
  DbDir: string;

function Lines(const Text: string): TStringList;
begin
  Result := TStringList.Create;
  Result.Text := Text;
end;

// Resolve text; returns True and the output, or False and the error message.
function Resolve(const Text, LenUnit: string; out OutText, Err: string; Warn: TStringList = nil): Boolean;
var
  Inp, Outp, W: TStringList;
begin
  Result := False;
  OutText := '';
  Err := '';
  Inp := Lines(Text);
  Outp := TStringList.Create;
  if Warn <> nil then W := Warn else W := TStringList.Create;
  try
    try
      ResolveFemref(Inp, DbDir, 'test.femref', LenUnit, Outp, W);
      OutText := Outp.Text;
      Result := True;
    except
      on E: EResolveError do Err := E.Message;
    end;
  finally
    if Warn = nil then W.Free;
    Outp.Free;
    Inp.Free;
  end;
end;

function Model(const Units, Refs, PropRows: string): string;
begin
  Result :=
    '[HEADER]'#10'Solver=linstatic'#10'Units=' + Units + #10#10 +
    Refs +
    '[NODES]'#10'1, 0, 0, 0'#10'2, 3, 0, 0'#10#10 +
    '[MATERIALS]'#10'1, 200000000000, 0.3, -'#10#10 +
    '[PROPERTIES]'#10 + PropRows + #10 +
    '[ELEMENTS]'#10'1, beam, 1, 2, 1'#10;
end;

const
  RefCol = '[REFERENCES]'#10'col, section, liberty_db.json, 200 UB 25.4'#10#10;

function LoadFromText(const Text: string): TModel;
var
  MS: TMemoryStream;
begin
  MS := TMemoryStream.Create;
  try
    if Length(Text) > 0 then MS.WriteBuffer(Text[1], Length(Text));
    MS.Position := 0;
    Result := LoadModelFromStream(MS);
  finally
    MS.Free;
  end;
end;

function ByteFingerprint(const Text: string): string;
var
  B: TBytes;
begin
  SetLength(B, Length(Text));
  if Length(Text) > 0 then Move(Text[1], B[0], Length(Text));
  Result := ModelFingerprint(B);
end;

procedure ExpectFail(const Name, Text, LenUnit, Contains: string);
var
  o, e: string;
begin
  if Resolve(Text, LenUnit, o, e) then
    Check(Name, False, 'was accepted but should be refused')
  else
    Check(Name, Pos(LowerCase(Contains), LowerCase(e)) > 0,
      Format('refused, but the message "%s" lacks "%s"', [e, Contains]));
end;

procedure TestResolver(const ManifestPath: string);
var
  o, e, plain, tmpProp: string;
  M: TModel;
  Db: TSectionDb;
  Entry: TSectionEntry;
  Pr: TSectionProperties;
  W: TStringList;
  Fh: TextFile;
  dbPath: string;
begin
  WriteLn('=== 2. FEMRESOLVE: REFERENCES -> PLAIN .fem ===');
  dbPath := DbDir + 'liberty_db.json';
  if not FileExists(dbPath) then
  begin
    Check('resolver tests need liberty_db.json next to the manifest tree', False, dbPath);
    Exit;
  end;
  LoadSectionDb(dbPath, Db, e);
  FindSectionEntry(Db, '200 UB 25.4', Entry, e);
  ComputeEntryProperties(Entry, Pr, e);

  // -- a model with no references passes through; the fingerprint is unchanged
  plain := Model('SI (N, m, Pa, rad)', '', '1, beam, 1, 0.005, 0.00004, 0.00008, 0.00002'#10);
  Check('no references: accepted', Resolve(plain, '', o, e), e);
  Check('no references: same fingerprint as the input', ByteFingerprint(o) = ByteFingerprint(plain));

  // -- beam section from the catalogue, SI model
  Check('beam reference: accepted', Resolve(Model('SI (N, m, Pa, rad)', RefCol, '1, beam, 1, @col'#10), '', o, e), e);
  Check('output has no references left', (Pos('@', StringReplace(o, '# @col', '', [rfReplaceAll])) = 0)
    and (Pos('[REFERENCES]', o) = 0));
  M := LoadFromText(o);
  Check('beam reference: the solver''s own loader accepts the output', Length(M.Properties) = 1);
  if Length(M.Properties) = 1 then
  begin
    Check('beam reference: area in m^2', Abs(M.Properties[0].Area / (Pr.Area * 1.0E-6) - 1) < 1.0E-12,
      Format('got %g', [M.Properties[0].Area]));
    Check('beam reference: Iz = strong axis (catalogue Ix) in m^4',
      Abs(M.Properties[0].Iz / (Pr.BeamIz * 1.0E-12) - 1) < 1.0E-12, Format('got %g', [M.Properties[0].Iz]));
    Check('beam reference: Iy = weak axis in m^4',
      Abs(M.Properties[0].Iy / (Pr.BeamIy * 1.0E-12) - 1) < 1.0E-12);
    Check('beam reference: J in m^4', Abs(M.Properties[0].J / (Pr.J * 1.0E-12) - 1) < 1.0E-12);
    Check('beam reference: Cy = half depth in m (0.1016)', Abs(M.Properties[0].Cy - 0.1016) < 1.0E-12,
      Format('got %g', [M.Properties[0].Cy]));
    Check('beam reference: Cz = half flange width in m (0.0665)', Abs(M.Properties[0].Cz - 0.0665) < 1.0E-12,
      Format('got %g', [M.Properties[0].Cz]));
    Check('beam reference: Rt positive and >= Cy', M.Properties[0].Rt >= M.Properties[0].Cy);
    Check('beam reference: the id, type and material fields are kept',
      (M.Properties[0].Id = 1) and (M.Properties[0].ElementType = 'beam') and (M.Properties[0].MaterialId = 1));
    Check('beam reference: Iz within 1% of the printed catalogue Ix (23.4e6 mm^4)',
      Abs(M.Properties[0].Iz / 23.4E-6 - 1) < 0.01);
  end;

  // -- provenance is in comments only, and the output is deterministic
  Check('provenance names the database hash', Pos(Db.Sha256, o) > 0);
  Check('provenance is comment text only (fingerprint ignores it)',
    ByteFingerprint(o) = ByteFingerprint(StringReplace(o, 'Generated by femresolve', 'Changed words', [rfReplaceAll])));
  Resolve(Model('SI (N, m, Pa, rad)', RefCol, '1, beam, 1, @col'#10), '', e, plain);
  Check('deterministic: the same input resolves to identical text', e = o);

  // -- truss takes only the area
  Check('truss reference: accepted', Resolve(
    Model('SI (N, m, Pa, rad)', RefCol, '1, truss, 1, @col'#10), '', o, e), e);
  Check('truss reference: only the area is written', Pos('1, truss, 1, 3.2308', o) > 0);

  // -- millimetre model: values are the catalogue's own mm numbers, no scaling
  Check('mm model: accepted', Resolve(
    Model('N, mm, MPa', RefCol, '1, beam, 1, @col'#10), '', o, e), e);
  M := LoadFromText(o);
  Check('mm model: area stays in mm^2', Abs(M.Properties[0].Area / Pr.Area - 1) < 1.0E-12);
  Check('mm model: Iz stays in mm^4', Abs(M.Properties[0].Iz / Pr.BeamIz - 1) < 1.0E-12);

  // -- explicit unit overrides the (unreadable) Units text
  Check('--length-unit overrides Units=', Resolve(
    Model('consistent units', RefCol, '1, beam, 1, @col'#10), 'm', o, e), e);

  // -- designation matching
  Check('designation: case and spaces ignored', Resolve(
    Model('SI (N, m, Pa)', '[REFERENCES]'#10'c, section, liberty_db.json, 200ub25.4'#10#10, '1, beam, 1, @c'#10), '', o, e), e);
  Check('designation: trailing .0 optional ("150 UC 30" = "150 UC 30.0")', Resolve(
    Model('SI (N, m, Pa)', '[REFERENCES]'#10'c, section, liberty_db.json, 150 UC 30'#10#10, '1, beam, 1, @c'#10), '', o, e), e);

  // -- section files written by femsection
  tmpProp := IncludeTrailingPathDelimiter(GetTempDir) + 'femresolve_test_' + IntToStr(GetProcessID) + '.prop';
  AssignFile(Fh, tmpProp);
  Rewrite(Fh);
  WriteLn(Fh, '# FEM3D Section Properties File (.prop)');
  WriteLn(Fh, '[HEADER]'); WriteLn(Fh, 'Source=angle.fgeo'); WriteLn(Fh, 'LengthUnit=mm');
  WriteLn(Fh, '[FEM_PROPERTY_SNIPPET]');
  WriteLn(Fh, '# Ready-to-paste line for .fem [PROPERTIES] section:');
  WriteLn(Fh, '# id, type, material, area, Iy, Iz, J, Cy, Cz, Rt');
  WriteLn(Fh, '# NOT symmetric about its x/y axes (Ixy <> 0): rotated 10 deg');
  WriteLn(Fh, 'Property=1, beam, 1, 2.0E+03, 1.0E+06, 5.0E+06, 7.0E+04, 100, 50, 110');
  CloseFile(Fh);
  try
    Check('.prop source: accepted', Resolve(
      Model('SI (N, m, Pa)', '[REFERENCES]'#10'a, section, ' + tmpProp + #10#10, '1, beam, 1, @a'#10), '', o, e), e);
    M := LoadFromText(o);
    Check('.prop source: converted mm -> m (area 2000 mm^2 = 0.002 m^2)', Abs(M.Properties[0].Area - 0.002) < 1.0E-15);
    Check('.prop source: Iz 5e6 mm^4 = 5e-6 m^4', Abs(M.Properties[0].Iz - 5.0E-6) < 1.0E-18);
    Check('.prop source: Cy 100 mm = 0.1 m', Abs(M.Properties[0].Cy - 0.1) < 1.0E-15);
    Check('.prop source: the rotation note is carried into the output', Pos('rotated 10 deg', o) > 0);
    Check('.prop source with a designation is refused', not Resolve(
      Model('SI (N, m, Pa)', '[REFERENCES]'#10'a, section, ' + tmpProp + ', X'#10#10, '1, beam, 1, @a'#10), '', o, e)
      and (Pos('no designation', e) > 0), e);
  finally
    DeleteFile(tmpProp);
  end;

  // -- things that must be refused, with a clear reason
  ExpectFail('refuse: undefined reference', Model('SI (N, m, Pa)', RefCol, '1, beam, 1, @nope'#10), '', 'not defined');
  ExpectFail('refuse: unknown designation (suggests neighbours)',
    Model('SI (N, m, Pa)', '[REFERENCES]'#10'c, section, liberty_db.json, 200 UB 99'#10#10, '1, beam, 1, @c'#10), '', 'not found');
  ExpectFail('refuse: angle (catalogue has no radii)',
    Model('SI (N, m, Pa)', '[REFERENCES]'#10'c, section, liberty_db.json, 150 x 100 x 12 UA'#10#10, '1, beam, 1, @c'#10), '', 'no root or toe radii');
  ExpectFail('refuse: tapered flange beam (slope not recorded)',
    Model('SI (N, m, Pa)', '[REFERENCES]'#10'c, section, liberty_db.json, 125 TFB'#10#10, '1, beam, 1, @c'#10), '', 'flange slope');
  ExpectFail('refuse: database reference without a designation',
    Model('SI (N, m, Pa)', '[REFERENCES]'#10'c, section, liberty_db.json'#10#10, '1, beam, 1, @c'#10), '', 'needs a designation');
  ExpectFail('refuse: material references (not supported yet)',
    Model('SI (N, m, Pa)', '[REFERENCES]'#10'm, material, steels.json, S355'#10#10, '1, beam, 1, 0.005, 1, 1, 1'#10), '', 'not supported yet');
  ExpectFail('refuse: unknown reference kind',
    Model('SI (N, m, Pa)', '[REFERENCES]'#10'm, thing, x.json, y'#10#10, '1, beam, 1, 0.005, 1, 1, 1'#10), '', 'unknown reference kind');
  ExpectFail('refuse: duplicate reference name',
    Model('SI (N, m, Pa)', RefCol + '[REFERENCES]'#10'col, section, liberty_db.json, 150 UC 30'#10#10, '1, beam, 1, @col'#10), '', 'more than one');
  ExpectFail('refuse: same name defined twice in one section',
    Model('SI (N, m, Pa)', '[REFERENCES]'#10'c, section, liberty_db.json, 200 UB 25.4'#10'C, section, liberty_db.json, 150 UC 30'#10#10, '1, beam, 1, @c'#10), '', 'defined twice');
  ExpectFail('refuse: missing database file',
    Model('SI (N, m, Pa)', '[REFERENCES]'#10'c, section, no_such_db.json, 200 UB 25.4'#10#10, '1, beam, 1, @c'#10), '', 'not found');
  ExpectFail('refuse: source that is neither .prop nor .json',
    Model('SI (N, m, Pa)', '[REFERENCES]'#10'c, section, data.txt, X'#10#10, '1, beam, 1, @c'#10), '', 'must be a .prop');
  ExpectFail('refuse: reference outside [PROPERTIES]',
    Model('SI (N, m, Pa)', RefCol, '1, beam, 1, 0.005, 1, 1, 1'#10) + '[LOADCASE a]'#10'@col, y, 1'#10, '', 'only allowed in [PROPERTIES]');
  ExpectFail('refuse: reference in the wrong field',
    Model('SI (N, m, Pa)', RefCol, '1, beam, 1, 0.005, @col, 1, 1'#10), '', 'fourth field');
  ExpectFail('refuse: extra fields after a reference',
    Model('SI (N, m, Pa)', RefCol, '1, beam, 1, @col, 5'#10), '', 'exactly 4 fields');
  ExpectFail('refuse: a shell cannot take a section',
    Model('SI (N, m, Pa)', RefCol, '1, shellq4, 1, @col'#10), '', 'beam or truss');
  ExpectFail('refuse: model length unit unreadable',
    Model('consistent units', RefCol, '1, beam, 1, @col'#10), '', 'length unit');
  ExpectFail('refuse: two length units named',
    Model('N, m, mm', RefCol, '1, beam, 1, @col'#10), '', 'length unit');
  ExpectFail('refuse: bad --length-unit', Model('SI (N, m, Pa)', RefCol, '1, beam, 1, @col'#10), 'parsec', 'not one of');
  ExpectFail('refuse: bad reference name',
    Model('SI (N, m, Pa)', '[REFERENCES]'#10'a b, section, liberty_db.json, 200 UB 25.4'#10#10, '1, beam, 1, 0.005, 1, 1, 1'#10), '', 'may only contain');
  ExpectFail('refuse: wrong field count in [REFERENCES]',
    Model('SI (N, m, Pa)', '[REFERENCES]'#10'a, section'#10#10, '1, beam, 1, 0.005, 1, 1, 1'#10), '', 'name, kind, source');

  // -- unused reference is only a warning
  W := TStringList.Create;
  try
    Check('unused reference: still resolves', Resolve(
      Model('SI (N, m, Pa)', RefCol, '1, beam, 1, 0.005, 0.00004, 0.00008, 0.00002'#10), '', o, e, W), e);
    Check('unused reference: warned about', (W.Count = 1) and (Pos('never used', W[0]) > 0));
  finally
    W.Free;
  end;

  // -- the solvers refuse the unresolved model
  try
    LoadFromText(Model('SI (N, m, Pa)', RefCol, '1, beam, 1, @col'#10));
    Check('the native loader refuses an unresolved .femref', False, 'it was accepted');
  except
    on Ex: Exception do Check('the native loader refuses an unresolved .femref', True);
  end;
  WriteLn;
end;

// ---------------------------------------------------------------------------
// 3. committed regression model is what the resolver now produces
// ---------------------------------------------------------------------------

procedure TestRegressionCase(const ManifestPath: string);
var
  caseDir, refPath, femPath: string;
  Inp, Outp, W: TStringList;
  Fem: TStringList;
  e: string;
begin
  WriteLn('=== 3. COMMITTED MODEL vs ITS .femref ===');
  caseDir := ExtractFilePath(ExpandFileName(ManifestPath)) + '..' + DirectorySeparator + '..' + DirectorySeparator
    + '..' + DirectorySeparator + 'tests' + DirectorySeparator + 'regression' + DirectorySeparator
    + '036_beam_liberty_section' + DirectorySeparator;
  refPath := caseDir + 'model.femref';
  femPath := caseDir + 'model.fem';
  if not (FileExists(refPath) and FileExists(femPath)) then
  begin
    Check('regression case 036 present', False, caseDir);
    Exit;
  end;
  Inp := TStringList.Create; Outp := TStringList.Create; W := TStringList.Create; Fem := TStringList.Create;
  try
    Inp.LoadFromFile(refPath);
    Fem.LoadFromFile(femPath);
    try
      ResolveFemref(Inp, caseDir, 'model.femref', '', Outp, W);
      e := '';
    except
      on Ex: EResolveError do e := Ex.Message;
    end;
    Check('036: model.femref resolves', e = '', e);
    Check('036: resolving model.femref reproduces model.fem (same fingerprint)',
      ByteFingerprint(Outp.Text) = ByteFingerprint(Fem.Text),
      'model.fem is out of date: run  femresolve model.femref > model.fem  and update the regression manifest hashes');
  finally
    Fem.Free; W.Free; Outp.Free; Inp.Free;
  end;
  WriteLn;
end;

var
  manifest: string;
  update: Boolean;
  i: Integer;
begin
  Checks := 0;
  Fails := 0;
  GFmt := DefaultFormatSettings;
  GFmt.DecimalSeparator := '.';
  manifest := '';
  update := False;
  for i := 1 to ParamCount do
    if ParamStr(i) = '--update-hashes' then update := True
    else manifest := ParamStr(i);
  manifest := FindManifest(manifest);

  if update then
  begin
    try
      UpdateManifestHashes(manifest);
    except
      on E: Exception do
      begin
        WriteLn('could not update hashes: ', E.Message);
        Halt(1);
      end;
    end;
    Halt(0);
  end;

  DbDir := ExtractFilePath(ExpandFileName(manifest)) + '..' + DirectorySeparator + '..' + DirectorySeparator + 'db' + DirectorySeparator;
  TestCatalogue(manifest);
  TestResolver(manifest);
  TestRegressionCase(manifest);

  if Fails = 0 then
    WriteLn('ALL ', Checks, ' CHECKS PASSED')
  else
    WriteLn(Fails, ' OF ', Checks, ' CHECKS FAILED');
  if Fails > 0 then Halt(1);
end.
