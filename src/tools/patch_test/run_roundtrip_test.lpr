program run_roundtrip_test;
{$mode objfpc}{$H+}
uses SysUtils, Classes, fem_geometry_types, fem_geometry_io, fem_geometry_validate;
var
  m1, m2: TFEMGeometryModel;
  err: string;
  ms1, ms2: TMemoryStream;
  s1, s2: string;
  d: TGeoDiagnostics;
  fail: Integer;
begin
  fail := 0;
  if not LoadFGeoFile(ParamStr(1), m1, err) then
  begin
    WriteLn('LOAD FAILED: ', err); Halt(1);
  end;
  ms1 := TMemoryStream.Create;
  WriteFGeo(m1, ms1);
  ms1.Position := 0;
  SetLength(s1, ms1.Size);
  if ms1.Size > 0 then ms1.ReadBuffer(s1[1], ms1.Size);

  ms1.Position := 0;
  if not LoadFGeo(ms1, m2, err) then
  begin
    WriteLn('RE-LOAD FAILED: ', err); Halt(1);
  end;
  ms2 := TMemoryStream.Create;
  WriteFGeo(m2, ms2);
  ms2.Position := 0;
  SetLength(s2, ms2.Size);
  if ms2.Size > 0 then ms2.ReadBuffer(s2[1], ms2.Size);

  if s1 = s2 then
    WriteLn('PASS  canonical write is idempotent (write == write(read(write)))')
  else
  begin
    WriteLn('FAIL  canonical write is NOT idempotent'); Inc(fail);
  end;

  InitDiagnostics(d);
  CheckGeometry(m2, d);
  if not HasErrors(d) then
    WriteLn('PASS  round-tripped model still validates with no errors')
  else
  begin
    WriteLn('FAIL  round-tripped model has validation errors'); Inc(fail);
  end;

  if fail = 0 then WriteLn('ALL CHECKS PASSED') else Halt(1);
end.
