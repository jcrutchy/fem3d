program femgeocheck;

// Checks an FEM3DGEO file against the GEO001-GEO010 diagnostics (spec
// section 14) and reports them. Exit code is 0 if no errors (warnings
// alone don't fail a check, per spec section 14), 3 if the file itself
// doesn't parse as valid FEM3DGEO syntax (a format error, not a
// geometry error), 1 if the geometry has one or more GEO-code errors.
//
// Usage:
//   femgeocheck model.fgeo        (file -> stdout)
//   femgeocheck -                 (stdin -> stdout)
//   cat model.fgeo | femgeocheck -
//
// Diagnostics go to stdout, one per line, "<CODE> <SEVERITY> <message>"
// -- deliberately NOT the geometry data itself: femgeocheck's role in
// the streaming pipeline (spec section 16:
// "step2femgeo model.step | femgeocheck - | geomclean - | automesh -")
// is to check and report, not to transform, so it does not re-emit the
// model. A tool further down a pipe that needs the model too should
// read it directly, or femgeocheck should gain a pass-through option
// if that turns out to be needed in practice (see femgeo/docs/TODO.md).

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, fem_geometry_types, fem_geometry_io, fem_geometry_validate;

const
  ExitOk = 0;
  ExitGeometryErrors = 1;
  ExitUsage = 2;
  ExitParseError = 3;

var
  fileArg: string;
  model: TFEMGeometryModel;
  diags: TGeoDiagnostics;
  loadErr: string;
  loaded: Boolean;
  i: Integer;
  sevStr: string;
  stdinStream: TStream;

begin
  if ParamCount <> 1 then
  begin
    WriteLn(StdErr, 'Usage: femgeocheck <file.fgeo | ->');
    Halt(ExitUsage);
  end;
  fileArg := ParamStr(1);

  if fileArg = '-' then
  begin
    stdinStream := OpenStdInStream;
    try
      loaded := LoadFGeo(stdinStream, model, loadErr);
    finally
      stdinStream.Free;
    end;
  end
  else
    loaded := LoadFGeoFile(fileArg, model, loadErr);

  if not loaded then
  begin
    WriteLn(StdErr, Format('femgeocheck: %s: %s', [fileArg, loadErr]));
    Halt(ExitParseError);
  end;

  InitDiagnostics(diags);
  CheckGeometry(model, diags);

  for i := 0 to High(diags.Items) do
  begin
    if diags.Items[i].Severity = gsError then sevStr := 'ERROR' else sevStr := 'WARNING';
    WriteLn(Format('%s %s %s', [diags.Items[i].Code, sevStr, diags.Items[i].Msg]));
  end;

  WriteLn(Format('# %s: %d error(s), %d warning(s)',
    [fileArg, ErrorCount(diags), WarningCount(diags)]));

  if HasErrors(diags) then
    Halt(ExitGeometryErrors)
  else
    Halt(ExitOk);
end.
