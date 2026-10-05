unit fem_resolve;

{$mode objfpc}{$H+}

// femresolve's engine: turns a ".femref" model (a native .fem model that may
// REFER to data kept elsewhere) into a plain native .fem model with every
// referenced value copied in, so the solvers -- which refuse references -- can
// run it, and so the model file's fingerprint covers the numbers actually used.
//
// A .femref is a .fem with one extra section and one extra field form:
//
//   [REFERENCES]
//   # name, kind, source[, designation]
//   col, section, liberty_db.json, 150 UC 30.0
//   brace, section, brace.prop
//
//   [PROPERTIES]
//   1, beam, 1, @col          <- the area/Iy/Iz/J/Cy/Cz/Rt fields come from "col"
//   2, truss, 1, @brace       <- only the area is used
//
// docs/femref.md is the specification.  Everything else in the file is copied
// through unchanged, and what is written for each reference is also described in a
// '#' comment line, which the fingerprint rule ignores.

interface

uses
  SysUtils, Classes, Math,
  fem_sha256, fem_section_types, fem_section_calc, fem_section_db;

type
  EResolveError = class(Exception);

// Input: the lines of the .femref.  BaseDir: folder that relative source paths are
// taken from.  SourceName: shown in the provenance comment.  LengthUnitOverride:
// '' to read the model's length unit from [HEADER] Units=, or one of
// mm, cm, m, in, ft.  Output: the .fem lines.  Warnings: non-fatal notes.
// Raises EResolveError (message starts with the offending line number where one
// applies) and writes nothing useful to Output when anything is wrong.
procedure ResolveFemref(Input: TStrings; const BaseDir, SourceName, LengthUnitOverride: string;
  Output, Warnings: TStrings);

// Length unit named in a "Units=" string such as "SI (N, m, Pa)"; '' if none or
// more than one is named.
function LengthUnitFromUnitsText(const Units: string): string;

function ConvertLengthPower(Value: Double; const FromUnit, ToUnit: string; Power: Integer): Double;

implementation

type
  TRefKind = (rkSection);

  TRefDef = record
    Name: string;
    Kind: TRefKind;
    Source: string;       // as written
    Designation: string;  // '' for a .prop source
    Line: Integer;
    Used: Boolean;
  end;

  // Beam values in the SOURCE's length unit.
  TSectionValues = record
    Area, Iy, Iz, J, Cy, Cz, Rt: Double;
    LengthUnit: string;
    Notes: string;          // one provenance sentence
    Extra: TStringList;     // comment lines copied from a .prop (rotation notes)
  end;

var
  GFS: TFormatSettings;

const
  KnownUnits: array[0..4] of string = ('mm', 'cm', 'm', 'in', 'ft');
  UnitInMm: array[0..4] of Double = (1.0, 10.0, 1000.0, 25.4, 304.8);

function UnitIndex(const U: string): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(KnownUnits) do
    if SameText(KnownUnits[i], U) then Exit(i);
end;

function LengthUnitFromUnitsText(const Units: string): string;
var
  i, j, idx, found: Integer;
  tok: string;
begin
  Result := '';
  found := 0;
  i := 1;
  while i <= Length(Units) do
  begin
    if Units[i] in ['A'..'Z', 'a'..'z'] then
    begin
      j := i;
      while (j <= Length(Units)) and (Units[j] in ['A'..'Z', 'a'..'z']) do Inc(j);
      tok := LowerCase(Copy(Units, i, j - i));
      i := j;
      idx := UnitIndex(tok);
      if idx >= 0 then
      begin
        if (found = 0) or (Result <> tok) then Inc(found);
        Result := tok;
      end;
    end
    else
      Inc(i);
  end;
  if found <> 1 then Result := '';
end;

function ConvertLengthPower(Value: Double; const FromUnit, ToUnit: string; Power: Integer): Double;
var
  a, b: Integer;
  ratio: Double;
begin
  a := UnitIndex(FromUnit);
  b := UnitIndex(ToUnit);
  if (a < 0) or (b < 0) then raise EResolveError.CreateFmt('unknown length unit "%s" or "%s"', [FromUnit, ToUnit]);
  if a = b then Exit(Value);
  // Divide by the (exact where possible) larger-to-smaller ratio rather than
  // multiplying by its reciprocal, so 1 mm -> 0.001 m carries no rounding noise.
  if UnitInMm[b] > UnitInMm[a] then
  begin
    ratio := UnitInMm[b] / UnitInMm[a];
    Result := Value / IntPower(ratio, Power);
  end
  else
  begin
    ratio := UnitInMm[a] / UnitInMm[b];
    Result := Value * IntPower(ratio, Power);
  end;
end;

function Fmt(V: Double): string;
begin
  Result := FloatToStrF(V, ffExponent, 15, 2, GFS);
end;

function SplitFields(const Line: string): TStringList;
var
  p, start: Integer;
begin
  Result := TStringList.Create;
  start := 1;
  for p := 1 to Length(Line) do
    if Line[p] = ',' then
    begin
      Result.Add(Trim(Copy(Line, start, p - start)));
      start := p + 1;
    end;
  Result.Add(Trim(Copy(Line, start, Length(Line) - start + 1)));
end;

function IsCommentOrBlank(const Trimmed: string): Boolean;
begin
  Result := (Trimmed = '') or (Trimmed[1] = '#') or (Trimmed[1] = ';');
end;

// '[NAME]' or '[NAME arg]'  ->  NAME in upper case ('' if the line is not a header)
function SectionNameOf(const Trimmed: string): string;
var
  inner: string;
  p: Integer;
begin
  Result := '';
  if (Length(Trimmed) < 2) or (Trimmed[1] <> '[') or (Trimmed[Length(Trimmed)] <> ']') then Exit;
  inner := Trim(Copy(Trimmed, 2, Length(Trimmed) - 2));
  p := 1;
  while (p <= Length(inner)) and not (inner[p] in [' ', #9]) do Inc(p);
  Result := UpperCase(Copy(inner, 1, p - 1));
end;

function FullPath(const BaseDir, Source: string): string;
begin
  if (Source <> '') and ((Source[1] = '/') or (Source[1] = '\') or
     ((Length(Source) > 1) and (Source[2] = ':'))) then
    Result := Source
  else if BaseDir = '' then
    Result := Source
  else
    Result := IncludeTrailingPathDelimiter(BaseDir) + Source;
end;

procedure ParsePropFile(const Path: string; out V: TSectionValues);
var
  SL: TStringList;
  i: Integer;
  line, sec, key, lowLine: string;
  F: TStringList;
  inSnippet, foundProp: Boolean;
  p: Integer;

  function Num(idx: Integer): Double;
  begin
    if not TryStrToFloat(F[idx], Result, GFS) then
      raise EResolveError.CreateFmt('%s: the Property= line has a field that is not a number ("%s")', [Path, F[idx]]);
  end;

begin
  V.Extra := TStringList.Create;
  V.LengthUnit := '';
  foundProp := False;
  inSnippet := False;
  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(Path);
    except
      on E: Exception do
        raise EResolveError.CreateFmt('cannot read "%s": %s', [Path, E.Message]);
    end;
    sec := '';
    for i := 0 to SL.Count - 1 do
    begin
      line := Trim(SL[i]);
      if line = '' then Continue;
      if line[1] = '[' then
      begin
        sec := UpperCase(line);
        inSnippet := sec = '[FEM_PROPERTY_SNIPPET]';
        Continue;
      end;
      if line[1] = '#' then
      begin
        if inSnippet then
        begin
          lowLine := LowerCase(line);
          if (Pos('ready-to-paste', lowLine) = 0) and (Pos('# id, type', lowLine) = 0) then
            V.Extra.Add(line);
        end;
        Continue;
      end;
      p := Pos('=', line);
      if p = 0 then Continue;
      key := Trim(Copy(line, 1, p - 1));
      if (sec = '[HEADER]') and SameText(key, 'LengthUnit') then
        V.LengthUnit := LowerCase(Trim(Copy(line, p + 1, MaxInt)));
      if inSnippet and SameText(key, 'Property') then
      begin
        if foundProp then
          raise EResolveError.CreateFmt('%s has more than one Property= line', [Path]);
        foundProp := True;
        F := SplitFields(Copy(line, p + 1, MaxInt));
        try
          if F.Count <> 10 then
            raise EResolveError.CreateFmt('%s: the Property= line must have 10 fields (id, type, material, area, Iy, Iz, J, Cy, Cz, Rt), found %d',
              [Path, F.Count]);
          V.Area := Num(3); V.Iy := Num(4); V.Iz := Num(5); V.J := Num(6);
          V.Cy := Num(7); V.Cz := Num(8); V.Rt := Num(9);
        finally
          F.Free;
        end;
      end;
    end;
  finally
    SL.Free;
  end;
  if not foundProp then
    raise EResolveError.CreateFmt('%s has no [FEM_PROPERTY_SNIPPET] Property= line (was it written by femsection?)', [Path]);
  if V.LengthUnit = '' then
    raise EResolveError.CreateFmt('%s has no [HEADER] LengthUnit=', [Path]);
  if UnitIndex(V.LengthUnit) < 0 then
    raise EResolveError.CreateFmt('%s: LengthUnit "%s" is not one of mm, cm, m, in, ft', [Path, V.LengthUnit]);
end;

procedure ResolveFemref(Input: TStrings; const BaseDir, SourceName, LengthUnitOverride: string;
  Output, Warnings: TStrings);
type
  TDbCacheItem = record
    Path: string;
    Db: TSectionDb;
  end;
var
  Refs: array of TRefDef;
  DbCache: array of TDbCacheItem;
  SourcesUsed: TStringList;      // 'path  sha256'
  i, k, n, p: Integer;
  raw, line, sec, secArg: string;
  F: TStringList;
  inRefs, hasRefs: Boolean;
  modelUnit, unitsText: string;
  Body: TStringList;

  procedure Fail(LineNo: Integer; const Msg: string);
  begin
    if LineNo > 0 then
      raise EResolveError.CreateFmt('line %d: %s', [LineNo, Msg])
    else
      raise EResolveError.Create(Msg);
  end;

  function FindRef(const Name: string): Integer;
  var
    j: Integer;
  begin
    Result := -1;
    for j := 0 to High(Refs) do
      if SameText(Refs[j].Name, Name) then Exit(j);
  end;

  function GetDb(const Path: string; LineNo: Integer): Integer;
  var
    j: Integer;
    err: string;
  begin
    for j := 0 to High(DbCache) do
      if DbCache[j].Path = Path then Exit(j);
    SetLength(DbCache, Length(DbCache) + 1);
    j := High(DbCache);
    DbCache[j].Path := Path;
    if not LoadSectionDb(Path, DbCache[j].Db, err) then
    begin
      SetLength(DbCache, Length(DbCache) - 1);
      Fail(LineNo, err);
    end;
    SourcesUsed.Add(Format('%s  sha256 %s', [ExtractFileName(Path), DbCache[j].Db.Sha256]));
    Result := j;
  end;

  procedure ValuesFor(const R: TRefDef; out V: TSectionValues);
  var
    path, err, shapeWhy: string;
    d: Integer;
    entry: TSectionEntry;
    pr: TSectionProperties;
    ext: string;
  begin
    V.Extra := TStringList.Create;
    path := FullPath(BaseDir, R.Source);
    ext := LowerCase(ExtractFileExt(R.Source));
    if ext = '.prop' then
    begin
      if R.Designation <> '' then
        Fail(R.Line, Format('reference "%s": a .prop file holds one section, so no designation may be given', [R.Name]));
      if not FileExists(path) then
        Fail(R.Line, Format('reference "%s": section file "%s" not found', [R.Name, path]));
      V.Extra.Free;
      try
        ParsePropFile(path, V);
      except
        on E1: EResolveError do Fail(R.Line, Format('reference "%s": %s', [R.Name, E1.Message]));
      end;
      SourcesUsed.Add(Format('%s  sha256 %s', [ExtractFileName(path), SHA256FileHex(path)]));
      V.Notes := Format('section file %s (sha256 %s), values as written by femsection (principal axes)',
        [ExtractFileName(path), Copy(SHA256FileHex(path), 1, 16)]);
    end
    else if ext = '.json' then
    begin
      if R.Designation = '' then
        Fail(R.Line, Format('reference "%s": a section database needs a designation as the fourth field', [R.Name]));
      d := GetDb(path, R.Line);
      if not FindSectionEntry(DbCache[d].Db, R.Designation, entry, err) then
        Fail(R.Line, Format('reference "%s": %s', [R.Name, err]));
      if ShapeForCategory(entry.Category, shapeWhy) = ssUnsupported then
        Fail(R.Line, Format('reference "%s": section "%s" (%s) cannot be used: %s',
          [R.Name, entry.Designation, entry.Category, shapeWhy]));
      if not ComputeEntryProperties(entry, pr, err) then
        Fail(R.Line, Format('reference "%s": %s', [R.Name, err]));
      V.Area := pr.Area; V.Iy := pr.BeamIy; V.Iz := pr.BeamIz; V.J := pr.J;
      V.Cy := pr.BeamCy; V.Cz := pr.BeamCz; V.Rt := pr.BeamRt;
      V.LengthUnit := DbCache[d].Db.LengthUnit;
      V.Notes := Format('section "%s" from %s (sha256 %s): outline built from the catalogue d, bf, tf, tw, r1 with depth along local y, properties computed by the section calculator',
        [entry.Designation, ExtractFileName(path), Copy(DbCache[d].Db.Sha256, 1, 16)]);
    end
    else
      Fail(R.Line, Format('reference "%s": source "%s" must be a .prop file or a .json section database', [R.Name, R.Source]));
  end;

  procedure Emit(const S: string);
  begin
    Body.Add(S);
  end;

  procedure ExpandPropertyRow(LineNo: Integer; const Row: string; Fields: TStringList);
  var
    ri, j: Integer;
    V: TSectionValues;
    typ, refName, tail: string;
  begin
    // only  id, beam|truss, material, @name
    for j := 0 to Fields.Count - 1 do
      if (j <> 3) and (Pos('@', Fields[j]) = 1) then
        Fail(LineNo, 'a reference may only be the fourth field of a [PROPERTIES] row (id, type, material, @name)');
    if Fields.Count <> 4 then
      Fail(LineNo, Format('a [PROPERTIES] row that uses a reference must have exactly 4 fields (id, type, material, @name), found %d', [Fields.Count]));
    typ := LowerCase(Fields[1]);
    if (typ <> 'beam') and (typ <> 'truss') then
      Fail(LineNo, Format('a section reference can only fill a beam or truss property, not "%s"', [Fields[1]]));
    refName := Copy(Fields[3], 2, MaxInt);
    ri := FindRef(refName);
    if ri < 0 then Fail(LineNo, Format('reference "@%s" is not defined in [REFERENCES]', [refName]));
    Refs[ri].Used := True;
    ValuesFor(Refs[ri], V);
    try
      if V.LengthUnit = modelUnit then
        Emit(Format('# @%s -> %s; lengths in %s (no conversion)', [Refs[ri].Name, V.Notes, modelUnit]))
      else
        Emit(Format('# @%s -> %s; converted %s -> %s', [Refs[ri].Name, V.Notes, V.LengthUnit, modelUnit]));
      for j := 0 to V.Extra.Count - 1 do
        Emit('#   ' + Copy(V.Extra[j], 2, MaxInt));
      tail := Fmt(ConvertLengthPower(V.Area, V.LengthUnit, modelUnit, 2));
      if typ = 'beam' then
        tail := tail + ', ' + Fmt(ConvertLengthPower(V.Iy, V.LengthUnit, modelUnit, 4))
                     + ', ' + Fmt(ConvertLengthPower(V.Iz, V.LengthUnit, modelUnit, 4))
                     + ', ' + Fmt(ConvertLengthPower(V.J, V.LengthUnit, modelUnit, 4))
                     + ', ' + Fmt(ConvertLengthPower(V.Cy, V.LengthUnit, modelUnit, 1))
                     + ', ' + Fmt(ConvertLengthPower(V.Cz, V.LengthUnit, modelUnit, 1))
                     + ', ' + Fmt(ConvertLengthPower(V.Rt, V.LengthUnit, modelUnit, 1));
      Emit(Format('%s, %s, %s, %s', [Fields[0], Fields[1], Fields[2], tail]));
    finally
      V.Extra.Free;
    end;
  end;

begin
  Output.Clear;
  Warnings.Clear;
  SetLength(Refs, 0);
  SetLength(DbCache, 0);
  SourcesUsed := TStringList.Create;
  Body := TStringList.Create;
  try
    // ---- pass 1: [REFERENCES] and the model's length unit ----
    inRefs := False;
    hasRefs := False;
    unitsText := '';
    sec := '';
    for i := 0 to Input.Count - 1 do
    begin
      raw := Input[i];
      if (i = 0) and (Length(raw) >= 3) and (raw[1] = #$EF) and (raw[2] = #$BB) and (raw[3] = #$BF) then
        Delete(raw, 1, 3);
      line := Trim(raw);
      if IsCommentOrBlank(line) then Continue;
      if line[1] = '[' then
      begin
        sec := SectionNameOf(line);
        if sec = '' then Fail(i + 1, 'malformed section header');
        inRefs := sec = 'REFERENCES';
        if inRefs then
        begin
          if hasRefs then Fail(i + 1, 'more than one [REFERENCES] section');
          hasRefs := True;
        end;
        Continue;
      end;
      if inRefs then
      begin
        F := SplitFields(line);
        try
          if (F.Count < 3) or (F.Count > 4) then
            Fail(i + 1, '[REFERENCES] rows are: name, kind, source[, designation]');
          if F[0] = '' then Fail(i + 1, 'a reference needs a name');
          for k := 1 to Length(F[0]) do
            if not (F[0][k] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) then
              Fail(i + 1, Format('reference name "%s" may only contain letters, digits, _ - and .', [F[0]]));
          if FindRef(F[0]) >= 0 then Fail(i + 1, Format('reference "%s" is defined twice', [F[0]]));
          if SameText(F[1], 'section') then
            n := 0
          else if SameText(F[1], 'material') then
            Fail(i + 1, 'material references are not supported yet (only "section")')
          else
            Fail(i + 1, Format('unknown reference kind "%s" (only "section" is supported)', [F[1]]));
          if F[2] = '' then Fail(i + 1, 'a reference needs a source file');
          SetLength(Refs, Length(Refs) + 1);
          k := High(Refs);
          Refs[k].Name := F[0];
          Refs[k].Kind := rkSection;
          Refs[k].Source := F[2];
          Refs[k].Designation := '';
          if F.Count = 4 then Refs[k].Designation := F[3];
          Refs[k].Line := i + 1;
          Refs[k].Used := False;
        finally
          F.Free;
        end;
      end
      else if sec = 'HEADER' then
      begin
        p := Pos('=', line);
        if (p > 0) and SameText(Trim(Copy(line, 1, p - 1)), 'Units') then
          unitsText := Trim(Copy(line, p + 1, MaxInt));
      end;
    end;

    // ---- model length unit (only needed when something is referenced) ----
    modelUnit := '';
    if Length(Refs) > 0 then
    begin
      if LengthUnitOverride <> '' then
      begin
        if UnitIndex(LengthUnitOverride) < 0 then
          Fail(0, Format('--length-unit "%s" is not one of mm, cm, m, in, ft', [LengthUnitOverride]));
        modelUnit := LowerCase(LengthUnitOverride);
      end
      else
      begin
        modelUnit := LengthUnitFromUnitsText(unitsText);
        if modelUnit = '' then
          Fail(0, Format('cannot tell the model''s length unit from [HEADER] Units="%s" (it must name exactly one of mm, cm, m, in, ft); fix Units= or pass --length-unit', [unitsText]));
      end;
    end;

    // ---- pass 2: copy through, expanding references ----
    inRefs := False;
    sec := '';
    for i := 0 to Input.Count - 1 do
    begin
      raw := Input[i];
      if (i = 0) and (Length(raw) >= 3) and (raw[1] = #$EF) and (raw[2] = #$BB) and (raw[3] = #$BF) then
        Delete(raw, 1, 3);
      line := Trim(raw);
      if (line <> '') and (line[1] = '[') then
      begin
        sec := SectionNameOf(line);
        inRefs := sec = 'REFERENCES';
        if inRefs then Continue;       // the section is consumed here
        Emit(raw);
        Continue;
      end;
      if inRefs then Continue;         // rows and comments inside [REFERENCES]
      if IsCommentOrBlank(line) then
      begin
        Emit(raw);
        Continue;
      end;
      if (sec = 'HEADER') or (sec = 'SOLVERPARAMS') or (sec = 'COMBINATION') then
      begin
        Emit(raw);
        Continue;
      end;
      F := SplitFields(line);
      try
        secArg := '';
        hasRefs := False;
        for k := 0 to F.Count - 1 do
          if (F[k] <> '') and (F[k][1] = '@') then hasRefs := True;
        if not hasRefs then
          Emit(raw)
        else if sec = 'PROPERTIES' then
          ExpandPropertyRow(i + 1, raw, F)
        else if sec = 'MATERIALS' then
          Fail(i + 1, 'material references are not supported yet')
        else
          Fail(i + 1, Format('references are only allowed in [PROPERTIES] rows, not in [%s]', [sec]));
      finally
        F.Free;
      end;
    end;

    for k := 0 to High(Refs) do
      if not Refs[k].Used then
        Warnings.Add(Format('line %d: reference "%s" is defined but never used', [Refs[k].Line, Refs[k].Name]));

    // ---- assemble ----
    Output.Add(Format('# Generated by femresolve from %s -- edit the .femref and run femresolve again, not this file.', [SourceName]));
    if SourcesUsed.Count > 0 then
    begin
      Output.Add('# Referenced data used:');
      for k := 0 to SourcesUsed.Count - 1 do
        Output.Add('#   ' + SourcesUsed[k]);
    end;
    Output.AddStrings(Body);
  finally
    Body.Free;
    SourcesUsed.Free;
  end;
end;

initialization
  GFS := DefaultFormatSettings;
  GFS.DecimalSeparator := '.';
  GFS.ThousandSeparator := #0;

end.
