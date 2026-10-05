program run_roundtrip_test;
{$mode objfpc}{$H+}
uses SysUtils, Classes, fem_geometry_types, fem_geometry_io, fem_geometry_validate;
var
  Fail, Checked: Integer;

// Round-trips one .fgeo file: write(read(f)) must equal write(read(write(read(f)))),
// and the re-read model must still validate with no errors.
procedure CheckFile(const Path: string);
var
  m1, m2: TFEMGeometryModel;
  err: string;
  ms1, ms2: TMemoryStream;
  s1, s2: string;
  d: TGeoDiagnostics;
begin
  WriteLn('--- ', Path);
  Inc(Checked);
  if not LoadFGeoFile(Path, m1, err) then
  begin
    WriteLn('FAIL  could not load: ', err);
    Inc(Fail);
    Exit;
  end;
  ms1 := TMemoryStream.Create;
  ms2 := TMemoryStream.Create;
  try
    WriteFGeo(m1, ms1);
    ms1.Position := 0;
    SetLength(s1, ms1.Size);
    if ms1.Size > 0 then ms1.ReadBuffer(s1[1], ms1.Size);

    ms1.Position := 0;
    if not LoadFGeo(ms1, m2, err) then
    begin
      WriteLn('FAIL  re-load of the written file failed: ', err);
      Inc(Fail);
      Exit;
    end;
    WriteFGeo(m2, ms2);
    ms2.Position := 0;
    SetLength(s2, ms2.Size);
    if ms2.Size > 0 then ms2.ReadBuffer(s2[1], ms2.Size);

    if s1 = s2 then
      WriteLn('PASS  canonical write is idempotent (write == write(read(write)))')
    else
    begin
      WriteLn('FAIL  canonical write is NOT idempotent');
      Inc(Fail);
    end;

    InitDiagnostics(d);
    CheckGeometry(m2, d);
    if not HasErrors(d) then
      WriteLn('PASS  round-tripped model still validates with no errors')
    else
    begin
      WriteLn('FAIL  round-tripped model has validation errors');
      Inc(Fail);
    end;
  finally
    ms2.Free;
    ms1.Free;
  end;
end;

procedure CheckDirectory(const Dir: string);
var
  sr: TSearchRec;
begin
  if FindFirst(Dir + DirectorySeparator + '*.fgeo', faAnyFile, sr) = 0 then
  begin
    repeat
      CheckFile(Dir + DirectorySeparator + sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
end;

var
  i: Integer;
begin
  // Usage: run_roundtrip_test [file.fgeo ...]
  // With no arguments (as test.bat runs it) every .fgeo under tests/geometry/good and
  // examples/rivet_flange_geometry is checked, relative to the current directory.
  Fail := 0;
  Checked := 0;
  if ParamCount >= 1 then
    for i := 1 to ParamCount do CheckFile(ParamStr(i))
  else
  begin
    CheckDirectory('tests' + DirectorySeparator + 'geometry' + DirectorySeparator + 'good');
    CheckDirectory('examples' + DirectorySeparator + 'rivet_flange_geometry');
  end;
  if Checked = 0 then
  begin
    WriteLn('FAIL  no .fgeo files found (run from the repository root, or pass file names)');
    Halt(1);
  end;
  if Fail = 0 then WriteLn('ALL CHECKS PASSED') else Halt(1);
end.
