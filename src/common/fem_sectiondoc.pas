unit fem_sectiondoc;

// The document model behind the native section editor/viewer: one .fgeo file
// loaded, validated and analysed exactly the way the femsection command-line
// tool does it (same units, same calls), so the GUI and the CLI cannot
// disagree. No LCL dependency.
//
// Properties are computed in two passes: Load runs the fast pass (everything
// except the numerical torsion constant J, which is only the thin-wall lower
// bound at that point); ComputeFull then runs the full pass including the J
// solve. A GUI shows the quick values at once and fills in J afterwards.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes,
  fem_geometry_types, fem_geometry_io, fem_geometry_validate,
  fem_section_types, fem_section_calc, fem_section_io;

type
  TSectionDoc = class
  public
    FileName: string;
    FileTime: LongInt;          // file age when loaded
    Geo: TFEMGeometryModel;
    Faces: TSectionFaceArray;
    Props: TSectionProperties;
    Diags: TGeoDiagnostics;
    Loaded: Boolean;            // the file parsed
    FacesOk: Boolean;           // section faces built and Props computed (quick pass)
    FullDone: Boolean;          // J solved
    ErrorText: string;          // the first fatal problem, '' if none
    constructor Create;
    // Returns True if the file parsed AND produced a computable section.
    function Load(const AFileName: string): Boolean;
    procedure ComputeFull;
    function FileChanged: Boolean;
    // Saves the .prop file exactly as femsection would write it.
    procedure SaveProp(const OutFile: string);
    // Bounding box of the polygon faces (False if there are none).
    function FaceBounds(out XMin, XMax, YMin, YMax: Double): Boolean;
  end;

implementation

constructor TSectionDoc.Create;
begin
  inherited Create;
  Loaded := False;
  FacesOk := False;
  FullDone := False;
  InitDiagnostics(Diags);
end;

function TSectionDoc.Load(const AFileName: string): Boolean;
var
  LoadErr, ConvErr: string;
begin
  FileName := AFileName;
  Loaded := False;
  FacesOk := False;
  FullDone := False;
  ErrorText := '';
  Faces := nil;
  InitDiagnostics(Diags);
  FillChar(Props, SizeOf(Props), 0);
  FileTime := FileAge(AFileName);

  if not LoadFGeoFile(AFileName, Geo, LoadErr) then
  begin
    ErrorText := 'Could not read "' + ExtractFileName(AFileName) + '": ' + LoadErr;
    Exit(False);
  end;
  Loaded := True;

  CheckGeometry(Geo, Diags);

  if not BuildSectionFaces(Geo, Faces, ConvErr) then
  begin
    Faces := nil;
    ErrorText := 'Not a usable section: ' + ConvErr;
    Exit(False);
  end;

  // Name and units exactly as femsection chooses them.
  if Geo.Header.HasSource and (Geo.Header.SourceName <> '') then
    Props.Name := Geo.Header.SourceName
  else
    Props.Name := ChangeFileExt(ExtractFileName(AFileName), '');
  if Geo.Header.HasUnits and (Geo.Header.LengthUnit <> '') then
    Props.LengthUnit := Geo.Header.LengthUnit
  else
    Props.LengthUnit := 'mm';

  try
    ComputeSectionProperties(Faces, Props, False);
  except
    on E: Exception do
    begin
      ErrorText := 'Calculation error: ' + E.Message;
      Exit(False);
    end;
  end;
  FacesOk := True;
  Result := True;
end;

procedure TSectionDoc.ComputeFull;
begin
  if not FacesOk then Exit;
  try
    ComputeSectionProperties(Faces, Props, True);
    FullDone := True;
  except
    on E: Exception do
    begin
      ErrorText := 'Torsion solve failed: ' + E.Message;
    end;
  end;
end;

function TSectionDoc.FileChanged: Boolean;
var
  A: LongInt;
begin
  A := FileAge(FileName);
  Result := (A <> -1) and (A <> FileTime);
end;

procedure TSectionDoc.SaveProp(const OutFile: string);
begin
  if not FacesOk then
    raise Exception.Create('There is no valid section to save');
  if not FullDone then ComputeFull;
  SavePropFile(Props, ExtractFileName(FileName), OutFile);
end;

function TSectionDoc.FaceBounds(out XMin, XMax, YMin, YMax: Double): Boolean;
var
  F, K: Integer;
  First: Boolean;

  procedure Take(const P: TPoint2D);
  begin
    if First then
    begin
      XMin := P.X; XMax := P.X; YMin := P.Y; YMax := P.Y;
      First := False;
    end
    else
    begin
      if P.X < XMin then XMin := P.X;
      if P.X > XMax then XMax := P.X;
      if P.Y < YMin then YMin := P.Y;
      if P.Y > YMax then YMax := P.Y;
    end;
  end;

begin
  First := True;
  XMin := 0; XMax := 0; YMin := 0; YMax := 0;
  for F := 0 to High(Faces) do
    for K := 0 to High(Faces[F].OuterLoop.Points) do
      Take(Faces[F].OuterLoop.Points[K]);
  Result := not First;
end;

end.
