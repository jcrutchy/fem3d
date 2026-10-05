unit fem_section_db;

{$mode objfpc}{$H+}

// A catalogue of standard steel sections stored as JSON (today: prop/liberty_db.json,
// the Liberty Steel hot-rolled catalogue), and the code that turns one catalogue
// entry into a real cross-section outline -- so its properties can be COMPUTED by
// the same fem_section_calc code that handles any other section, instead of
// being copied from the catalogue's printed (3 significant figure) values.
//
// Used by both femresolve (to fill in a beam property from a designation such as
// "150 UC 30.0") and the catalogue test (run_liberty_test), so the two can never
// disagree about what a catalogue section looks like.
//
// WHAT CAN BE BUILT.  An outline is built from the catalogue's overall depth d,
// flange width bf, flange thickness tf, web thickness tw and root radius r1:
//   universal_beams, universal_columns, universal_bearing_piles  -> I-section
//   parallel_flange_channels                                       -> channel
// These categories are refused, with the reason, rather than guessed:
//   tapered_flange_beams  the catalogue does not record the flange slope
//   equal_angles, unequal_angles  the catalogue gives no root or toe radii
//
// Orientation: depth runs along the section's Y axis, so Ix in the catalogue is
// the section's Ixx.  A channel has its web on the LEFT (x = 0 is the back of the
// web).  Dimensions are in mm.

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  fem_sha256, fem_section_types, fem_section_calc;

type
  TSectionShape = (ssUnsupported, ssIBeam, ssChannel);

  TSectionEntry = record
    Category: string;            // name of the JSON array the entry came from
    Designation: string;         // as printed, e.g. '150 UC 30.0'
    D, Bf, Tf, Tw, R1: Double;   // mm; NaN if the category has no such column
    // Catalogue values exactly as stored (see the scale constants below);
    // NaN where the category has no such column.
    Ag, Ix, Iy, Zx, Sx, Zy, ZyR, ZyL, Sy, J, XL: Double;
  end;
  TSectionEntryArray = array of TSectionEntry;

  TSectionDb = record
    FileName: string;
    Sha256: string;              // of the file's bytes, lowercase hex
    Title: string;
    LengthUnit: string;          // always 'mm' (anything else is refused on load)
    Entries: TSectionEntryArray;
  end;

const
  // Scales that turn the stored catalogue columns into mm / mm^2 / mm^4 / mm^3.
  // LoadSectionDb checks the file's own "units" block says exactly this.
  CatalogueMomentScale = 1.0E6;   // Ix, Iy      stored in 10^6 mm^4
  CatalogueModulusScale = 1.0E3;  // Zx Sx Zy Sy stored in 10^3 mm^3
  CatalogueTorsionScale = 1.0E3;  // J           stored in 10^3 mm^4

function LoadSectionDb(const FileName: string; out Db: TSectionDb; out Err: string): Boolean;

// 'ignore case, spaces and a trailing .0': '150 UC 30.0', '150uc30', '150 UC 30'
// all normalise to the same text.
function NormalizeDesignation(const S: string): string;

function FindSectionEntry(const Db: TSectionDb; const Designation: string;
  out Entry: TSectionEntry; out Err: string): Boolean;

function ShapeForCategory(const Category: string; out WhyNot: string): TSectionShape;

// Outline of a catalogue entry (one face, no holes).
function BuildEntryFaces(const E: TSectionEntry; out Faces: TSectionFaceArray;
  out Err: string): Boolean;

// Outline plus the full set of computed section properties (J solved).
function ComputeEntryProperties(const E: TSectionEntry; out Props: TSectionProperties;
  out Err: string): Boolean;

implementation

const
  ArcStepDeg = 1.0;   // fillet polygon step, as for curved edges read from a .fgeo

var
  GFS: TFormatSettings;

function NumOrNaN(Obj: TJSONObject; const Key: string): Double;
var
  Item: TJSONData;
begin
  Item := Obj.Find(Key);
  if (Item = nil) or not (Item.JSONType = jtNumber) then
    Result := NaN
  else
    Result := Item.AsFloat;
end;

function NormalizeDesignation(const S: string): string;
var
  i, j: Integer;
  tok: string;
  ch: Char;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    ch := S[i];
    if ch in ['0'..'9'] then
    begin
      // a number: take digits and an optional decimal part, drop trailing zeros
      j := i;
      while (j <= Length(S)) and (S[j] in ['0'..'9', '.']) do Inc(j);
      tok := Copy(S, i, j - i);
      if Pos('.', tok) > 0 then
      begin
        while (Length(tok) > 0) and (tok[Length(tok)] = '0') do Delete(tok, Length(tok), 1);
        if (Length(tok) > 0) and (tok[Length(tok)] = '.') then Delete(tok, Length(tok), 1);
      end;
      Result := Result + tok;
      i := j;
    end
    else
    begin
      if not (ch in [' ', #9]) then Result := Result + LowerCase(ch);
      Inc(i);
    end;
  end;
end;

function LoadSectionDb(const FileName: string; out Db: TSectionDb; out Err: string): Boolean;
var
  FS: TFileStream;
  Root: TJSONData;
  RootObj, UnitsObj, SecObj: TJSONObject;
  Arr: TJSONArray;
  Item: TJSONObject;
  Names: TStringList;
  i, k, n: Integer;
  cat, norm: string;

  function UnitIs(const Key, Expected: string): Boolean;
  var
    U: TJSONData;
  begin
    U := UnitsObj.Find(Key);
    Result := (U <> nil) and (U.JSONType = jtString) and (U.AsString = Expected);
  end;

begin
  Result := False;
  Err := '';
  Db.FileName := FileName;
  Db.Sha256 := '';
  Db.Title := '';
  Db.LengthUnit := 'mm';
  SetLength(Db.Entries, 0);

  if not FileExists(FileName) then
  begin
    Err := Format('section database "%s" not found', [FileName]);
    Exit;
  end;
  Db.Sha256 := SHA256FileHex(FileName);

  Root := nil;
  try
    FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      try
        Root := GetJSON(FS);
      except
        on E: Exception do
        begin
          Err := Format('section database "%s" is not valid JSON: %s', [FileName, E.Message]);
          Exit;
        end;
      end;
    finally
      FS.Free;
    end;

    if not (Root is TJSONObject) then
    begin
      Err := Format('section database "%s": top level must be a JSON object', [FileName]);
      Exit;
    end;
    RootObj := TJSONObject(Root);
    if RootObj.Find('title') <> nil then Db.Title := RootObj.Get('title', '');

    // A wrong unit would silently scale every property, so insist on the exact units
    // this reader is written for.
    if not (RootObj.Find('units') is TJSONObject) then
    begin
      Err := Format('section database "%s": no "units" block', [FileName]);
      Exit;
    end;
    UnitsObj := TJSONObject(RootObj.Find('units'));
    if not (UnitIs('dimensions', 'mm') and UnitIs('area', 'mm^2')
      and UnitIs('second_moment_of_area', '10^6 mm^4')
      and UnitIs('section_modulus', '10^3 mm^3')
      and UnitIs('torsion_constant_J', '10^3 mm^4')) then
    begin
      Err := Format('section database "%s": unsupported "units" block (expected mm, mm^2, 10^6 mm^4, 10^3 mm^3, 10^3 mm^4)', [FileName]);
      Exit;
    end;

    if not (RootObj.Find('sections') is TJSONObject) then
    begin
      Err := Format('section database "%s": no "sections" object', [FileName]);
      Exit;
    end;
    SecObj := TJSONObject(RootObj.Find('sections'));

    Names := TStringList.Create;
    try
      Names.Sorted := True;
      Names.Duplicates := dupError;
      n := 0;
      for k := 0 to SecObj.Count - 1 do
      begin
        cat := SecObj.Names[k];
        if not (SecObj.Items[k] is TJSONArray) then
        begin
          Err := Format('section database "%s": "%s" is not an array', [FileName, cat]);
          Exit;
        end;
        Arr := TJSONArray(SecObj.Items[k]);
        SetLength(Db.Entries, n + Arr.Count);
        for i := 0 to Arr.Count - 1 do
        begin
          if not (Arr.Items[i] is TJSONObject) then
          begin
            Err := Format('section database "%s": "%s"[%d] is not an object', [FileName, cat, i]);
            Exit;
          end;
          Item := TJSONObject(Arr.Items[i]);
          if (Item.Find('designation') = nil) or (Item.Find('designation').JSONType <> jtString) then
          begin
            Err := Format('section database "%s": "%s"[%d] has no designation', [FileName, cat, i]);
            Exit;
          end;
          Db.Entries[n].Category := cat;
          Db.Entries[n].Designation := Item.Get('designation', '');
          Db.Entries[n].D := NumOrNaN(Item, 'd');
          Db.Entries[n].Bf := NumOrNaN(Item, 'bf');
          Db.Entries[n].Tf := NumOrNaN(Item, 'tf');
          Db.Entries[n].Tw := NumOrNaN(Item, 'tw');
          Db.Entries[n].R1 := NumOrNaN(Item, 'r1');
          Db.Entries[n].Ag := NumOrNaN(Item, 'Ag');
          Db.Entries[n].Ix := NumOrNaN(Item, 'Ix');
          Db.Entries[n].Iy := NumOrNaN(Item, 'Iy');
          Db.Entries[n].Zx := NumOrNaN(Item, 'Zx');
          Db.Entries[n].Sx := NumOrNaN(Item, 'Sx');
          Db.Entries[n].Zy := NumOrNaN(Item, 'Zy');
          Db.Entries[n].ZyR := NumOrNaN(Item, 'ZyR');
          Db.Entries[n].ZyL := NumOrNaN(Item, 'ZyL');
          Db.Entries[n].Sy := NumOrNaN(Item, 'Sy');
          Db.Entries[n].J := NumOrNaN(Item, 'J');
          Db.Entries[n].XL := NumOrNaN(Item, 'XL');

          norm := NormalizeDesignation(Db.Entries[n].Designation);
          try
            Names.Add(norm);
          except
            on EStringListError do
            begin
              Err := Format('section database "%s": designation "%s" is ambiguous (two entries normalise to "%s")',
                [FileName, Db.Entries[n].Designation, norm]);
              Exit;
            end;
          end;
          Inc(n);
        end;
      end;
    finally
      Names.Free;
    end;
    Result := True;
  finally
    Root.Free;
  end;
end;

function FindSectionEntry(const Db: TSectionDb; const Designation: string;
  out Entry: TSectionEntry; out Err: string): Boolean;
var
  want, firstNum, hints: string;
  i, p, hintCount: Integer;
begin
  Result := False;
  Err := '';
  want := NormalizeDesignation(Designation);
  if want = '' then
  begin
    Err := 'empty section designation';
    Exit;
  end;
  for i := 0 to High(Db.Entries) do
    if NormalizeDesignation(Db.Entries[i].Designation) = want then
    begin
      Entry := Db.Entries[i];
      Exit(True);
    end;

  // not found: suggest entries that start with the same leading number
  p := 1;
  while (p <= Length(want)) and (want[p] in ['0'..'9']) do Inc(p);
  firstNum := Copy(want, 1, p - 1);
  hints := '';
  hintCount := 0;
  if firstNum <> '' then
    for i := 0 to High(Db.Entries) do
    begin
      if (Pos(firstNum, NormalizeDesignation(Db.Entries[i].Designation)) = 1) and (hintCount < 6) then
      begin
        if hints <> '' then hints := hints + ', ';
        hints := hints + '"' + Db.Entries[i].Designation + '"';
        Inc(hintCount);
      end;
    end;
  Err := Format('section "%s" not found in %s', [Designation, ExtractFileName(Db.FileName)]);
  if hints <> '' then Err := Err + ' (entries starting with ' + firstNum + ': ' + hints + ')';
end;

function ShapeForCategory(const Category: string; out WhyNot: string): TSectionShape;
begin
  WhyNot := '';
  if (Category = 'universal_beams') or (Category = 'universal_columns')
    or (Category = 'universal_bearing_piles') then
    Result := ssIBeam
  else if Category = 'parallel_flange_channels' then
    Result := ssChannel
  else
  begin
    Result := ssUnsupported;
    if Category = 'tapered_flange_beams' then
      WhyNot := 'the catalogue does not record the flange slope of a tapered-flange beam'
    else if (Category = 'equal_angles') or (Category = 'unequal_angles') then
      WhyNot := 'the catalogue gives no root or toe radii for an angle'
    else
      WhyNot := 'no outline generator for this category';
  end;
end;

// Append the points of a circular arc, from angle A0 to A1 (degrees, either
// direction), both ends included.  A zero radius adds the single corner point.
procedure AddArc(var Pts: TPoint2DArray; Cx, Cy, R, A0, A1: Double);
var
  n, k: Integer;
  a: Double;
begin
  if R <= 1.0E-12 then
  begin
    SetLength(Pts, Length(Pts) + 1);
    Pts[High(Pts)] := Pt2D(Cx, Cy);
    Exit;
  end;
  n := Ceil(Abs(A1 - A0) / ArcStepDeg);
  if n < 1 then n := 1;
  for k := 0 to n do
  begin
    a := (A0 + (A1 - A0) * k / n) * Pi / 180.0;
    SetLength(Pts, Length(Pts) + 1);
    Pts[High(Pts)] := Pt2D(Cx + R * Cos(a), Cy + R * Sin(a));
  end;
end;

procedure AddPt(var Pts: TPoint2DArray; X, Y: Double);
begin
  SetLength(Pts, Length(Pts) + 1);
  Pts[High(Pts)] := Pt2D(X, Y);
end;

function BuildEntryFaces(const E: TSectionEntry; out Faces: TSectionFaceArray;
  out Err: string): Boolean;
var
  shape: TSectionShape;
  why: string;
  Dh, B, T, tf, r: Double;
  pts: TPoint2DArray;
begin
  Result := False;
  Err := '';
  SetLength(Faces, 0);
  shape := ShapeForCategory(E.Category, why);
  if shape = ssUnsupported then
  begin
    Err := Format('section "%s" (%s) cannot be built from its catalogue entry: %s',
      [E.Designation, E.Category, why]);
    Exit;
  end;
  if IsNaN(E.D) or IsNaN(E.Bf) or IsNaN(E.Tf) or IsNaN(E.Tw) or IsNaN(E.R1) then
  begin
    Err := Format('section "%s": catalogue entry is missing d, bf, tf, tw or r1', [E.Designation]);
    Exit;
  end;
  if (E.D <= 0) or (E.Bf <= 0) or (E.Tf <= 0) or (E.Tw <= 0) or (E.R1 < 0)
    or (2.0 * E.Tf >= E.D) or (E.Tw >= E.Bf) then
  begin
    Err := Format('section "%s": catalogue dimensions are not a valid section (d=%g bf=%g tf=%g tw=%g r1=%g)',
      [E.Designation, E.D, E.Bf, E.Tf, E.Tw, E.R1]);
    Exit;
  end;

  Dh := E.D / 2.0;
  tf := E.Tf;
  r := E.R1;
  SetLength(pts, 0);

  if shape = ssIBeam then
  begin
    B := E.Bf / 2.0;
    T := E.Tw / 2.0;
    if (r > B - T) or (r > Dh - tf) then
    begin
      Err := Format('section "%s": root radius %g does not fit between web and flange', [E.Designation, r]);
      Exit;
    end;
    // counter-clockwise, starting at the bottom-left corner of the bottom flange
    AddPt(pts, -B, -Dh);
    AddPt(pts, B, -Dh);
    AddPt(pts, B, -Dh + tf);
    AddArc(pts, T + r, -Dh + tf + r, r, -90.0, -180.0);   // lower right root
    AddArc(pts, T + r, Dh - tf - r, r, 180.0, 90.0);      // upper right root
    AddPt(pts, B, Dh - tf);
    AddPt(pts, B, Dh);
    AddPt(pts, -B, Dh);
    AddPt(pts, -B, Dh - tf);
    AddArc(pts, -T - r, Dh - tf - r, r, 90.0, 0.0);       // upper left root
    AddArc(pts, -T - r, -Dh + tf + r, r, 0.0, -90.0);     // lower left root
    AddPt(pts, -B, -Dh + tf);
  end
  else
  begin
    // channel: web on the left (x = 0 .. tw), flanges extend to x = bf
    B := E.Bf;
    T := E.Tw;
    if (r > B - T) or (r > Dh - tf) then
    begin
      Err := Format('section "%s": root radius %g does not fit between web and flange', [E.Designation, r]);
      Exit;
    end;
    AddPt(pts, 0.0, -Dh);
    AddPt(pts, B, -Dh);
    AddPt(pts, B, -Dh + tf);
    AddArc(pts, T + r, -Dh + tf + r, r, -90.0, -180.0);   // lower root
    AddArc(pts, T + r, Dh - tf - r, r, 180.0, 90.0);      // upper root
    AddPt(pts, B, Dh - tf);
    AddPt(pts, B, Dh);
    AddPt(pts, 0.0, Dh);
  end;

  SetLength(Faces, 1);
  Faces[0].OuterLoop.IsHole := False;
  Faces[0].OuterLoop.Points := pts;
  SetLength(Faces[0].Holes, 0);
  Result := True;
end;

function ComputeEntryProperties(const E: TSectionEntry; out Props: TSectionProperties;
  out Err: string): Boolean;
var
  faces: TSectionFaceArray;
begin
  Result := False;
  FillChar(Props, SizeOf(Props), 0);
  if not BuildEntryFaces(E, faces, Err) then Exit;
  try
    ComputeSectionProperties(faces, Props, True);
  except
    on Ex: Exception do
    begin
      Err := Format('section "%s": %s', [E.Designation, Ex.Message]);
      Exit;
    end;
  end;
  Props.Name := E.Designation;
  Props.LengthUnit := 'mm';
  Result := True;
end;

initialization
  GFS := DefaultFormatSettings;
  GFS.DecimalSeparator := '.';
  GFS.ThousandSeparator := #0;

end.
