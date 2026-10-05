program femsection;

// Computes engineering section properties from a FEM3DGEO (.fgeo) file
// and emits a canonical .prop file to stdout or a file.
//
// Usage:
//   femsection model.fgeo [output.prop]
//   cat model.fgeo | femsection - > output.prop
//
// Exit codes:
//   0 = Success
//   1 = Geometry / mathematical error (zero area, self-intersection, etc.)
//   2 = CLI usage error
//   3 = File I/O or syntax parse error

{$mode objfpc}{$H+}

uses
  SysUtils, Classes,
  fem_geometry_types, fem_geometry_io,
  fem_section_types, fem_section_calc, fem_section_io;

const
  ExitOk = 0;
  ExitGeomMathError = 1;
  ExitUsage = 2;
  ExitParseError = 3;

var
  inFile, outFile, loadErr, convErr: string;
  inStream, outStream: TStream;
  geoModel: TFEMGeometryModel;
  faces: TSectionFaceArray;
  props: TSectionProperties;
  loaded: Boolean;

begin
  if (ParamCount < 1) or (ParamCount > 2) then
  begin
    WriteLn(StdErr, 'Usage: femsection <model.fgeo | -> [output.prop]');
    WriteLn(StdErr, '  Computes engineering cross-section properties from FEM3DGEO geometry.');
    Halt(ExitUsage);
  end;

  inFile := ParamStr(1);
  if ParamCount = 2 then
    outFile := ParamStr(2)
  else
    outFile := '-';

  if inFile = '-' then
  begin
    inStream := OpenStdInStream;
    try
      loaded := LoadFGeo(inStream, geoModel, loadErr);
    finally
      inStream.Free;
    end;
  end
  else
    loaded := LoadFGeoFile(inFile, geoModel, loadErr);

  if not loaded then
  begin
    WriteLn(StdErr, Format('femsection: could not parse "%s": %s', [inFile, loadErr]));
    Halt(ExitParseError);
  end;

  if not BuildSectionFaces(geoModel, faces, convErr) then
  begin
    WriteLn(StdErr, Format('femsection: geometric conversion error: %s', [convErr]));
    Halt(ExitGeomMathError);
  end;

  try
    FillChar(props, SizeOf(props), 0);
    // Section name: the .fgeo's own SOURCE name if it has one, else the input
    // file name without its extension ("section" when read from stdin).
    if geoModel.Header.HasSource and (geoModel.Header.SourceName <> '') then
      props.Name := geoModel.Header.SourceName
    else if inFile = '-' then
      props.Name := 'section'
    else
      props.Name := ChangeFileExt(ExtractFileName(inFile), '');
    if geoModel.Header.HasUnits and (geoModel.Header.LengthUnit <> '') then
      props.LengthUnit := geoModel.Header.LengthUnit
    else
      props.LengthUnit := 'mm';

    ComputeSectionProperties(faces, props, True);
  except
    on E: Exception do
    begin
      WriteLn(StdErr, Format('femsection: calculation error: %s', [E.Message]));
      Halt(ExitGeomMathError);
    end;
  end;

  if (outFile = '-') or (outFile = '') then
  begin
    outStream := OpenStdOutStream;
    try
      WritePropFile(props, ExtractFileName(inFile), outStream);
    finally
      outStream.Free;
    end;
  end
  else
    SavePropFile(props, ExtractFileName(inFile), outFile);

  Halt(ExitOk);
end.

