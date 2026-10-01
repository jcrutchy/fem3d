unit fem_geometry_io;

// Reader/writer for the FEM3DGEO 1.0 text format (femgeo/docs/FEM3DGEO.md).
// Both LoadFGeo and WriteFGeo take a plain TStream -- for a file, wrap a
// TFileStream; for stdin/stdout (the streaming contract in spec section
// 16), wrap THandleStream.Create(StdInputHandle) /
// THandleStream.Create(StdOutputHandle) (both from the Classes/System
// units) -- NOT Pascal's Text-typed Input/Output, which are a
// completely different I/O abstraction and cannot be passed to
// anything expecting a TStream. (This is corrected from an earlier
// draft of this module that tried exactly that and could not compile;
// see femgeo/docs/TODO.md.)

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fem_geometry_types;

function LoadFGeo(Stream: TStream; out Model: TFEMGeometryModel; out Err: string): Boolean;
function LoadFGeoFile(const FileName: string; out Model: TFEMGeometryModel; out Err: string): Boolean;

// Writes in CANONICAL form (spec section 15): header records in the
// order the spec lists them, entities in ascending ID order within
// each type, explicit +1/-1 signs, no volatile timestamps -- what
// makes .fgeo fixtures suitable for regression tests (femgeo/tests/).
procedure WriteFGeo(const Model: TFEMGeometryModel; Stream: TStream);
procedure WriteFGeoFile(const Model: TFEMGeometryModel; const FileName: string);

// Opens stdin/stdout as proper streams for the "-" filename convention
// used throughout femgeo's CLI tools (spec section 16: "stdin -> stdout").
function OpenStdInStream: TStream;
function OpenStdOutStream: TStream;

implementation

var
  GFS: TFormatSettings; // '.' decimal point regardless of locale (spec rule 9)

function OpenStdInStream: TStream;
begin
  Result := THandleStream.Create(StdInputHandle);
end;

function OpenStdOutStream: TStream;
begin
  Result := THandleStream.Create(StdOutputHandle);
end;

// ---- Tokenizer -----------------------------------------------------
// Whitespace-separated fields; a double-quoted SPAN within a field may
// itself contain whitespace and the escapes \\ \" \n \r \t (spec
// section 3) -- e.g. name="tutorial rectangle" is ONE field, with the
// quotes and escapes resolved and removed, not two fields split on the
// space inside the quotes. A field ends at the first whitespace that
// is outside any quoted span, not at the first whitespace regardless
// of position -- this rewrite fixes an earlier version of this
// function that only recognised quoting when a field started with a
// quote character, which broke on exactly this key="value with
// spaces" form (see femgeo/docs/TODO.md).
function Tokenize(const Line: string): TStringArray;
var
  i, n: Integer;
  cur: string;
  inQuotes: Boolean;
  c: Char;
begin
  SetLength(Result, 0);
  n := Length(Line);
  i := 1;
  while i <= n do
  begin
    while (i <= n) and (Line[i] in [' ', #9]) do Inc(i);
    if i > n then Break;
    cur := '';
    inQuotes := False;
    while (i <= n) and (inQuotes or not (Line[i] in [' ', #9])) do
    begin
      c := Line[i];
      if inQuotes then
      begin
        if c = '\' then
        begin
          Inc(i);
          if i > n then
            raise Exception.Create('unterminated escape at end of quoted string');
          case Line[i] of
            '\': cur := cur + '\';
            '"': cur := cur + '"';
            'n': cur := cur + #10;
            'r': cur := cur + #13;
            't': cur := cur + #9;
          else
            raise Exception.CreateFmt('unknown escape "\%s" in quoted string', [Line[i]]);
          end;
          Inc(i);
        end
        else if c = '"' then
        begin
          inQuotes := False;
          Inc(i);
        end
        else
        begin
          cur := cur + c;
          Inc(i);
        end;
      end
      else if c = '"' then
      begin
        inQuotes := True;
        Inc(i);
      end
      else
      begin
        cur := cur + c;
        Inc(i);
      end;
    end;
    if inQuotes then
      raise Exception.Create('unterminated quoted string');
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := cur;
  end;
end;

function TD(const T: TStringArray; Idx: Integer; const What: string): Double;
begin
  if (Idx < 0) or (Idx >= Length(T)) then
    raise Exception.CreateFmt('missing field (%s)', [What]);
  if not TryStrToFloat(T[Idx], Result, GFS) then
    raise Exception.CreateFmt('%s must be a number, got "%s"', [What, T[Idx]]);
end;

function TI(const T: TStringArray; Idx: Integer; const What: string): Integer;
begin
  if (Idx < 0) or (Idx >= Length(T)) then
    raise Exception.CreateFmt('missing field (%s)', [What]);
  if not TryStrToInt(T[Idx], Result) then
    raise Exception.CreateFmt('%s must be an integer, got "%s"', [What, T[Idx]]);
end;

function TS(const T: TStringArray; Idx: Integer; const What: string): string;
begin
  if (Idx < 0) or (Idx >= Length(T)) then
    raise Exception.CreateFmt('missing field (%s)', [What]);
  Result := T[Idx];
end;

function TSense(const T: TStringArray; Idx: Integer; const What: string): Integer;
begin
  Result := TI(T, Idx, What);
  if (Result <> 1) and (Result <> -1) then
    raise Exception.CreateFmt('%s must be +1 or -1, got %d', [What, Result]);
end;

function ReadV3(const T: TStringArray; Idx: Integer; const What: string): TGeoVec3;
begin
  Result.X := TD(T, Idx,     What + '.x');
  Result.Y := TD(T, Idx + 1, What + '.y');
  Result.Z := TD(T, Idx + 2, What + '.z');
end;

// ---- Reader ----------------------------------------------------------

function LoadFGeo(Stream: TStream; out Model: TFEMGeometryModel; out Err: string): Boolean;
var
  lines: TStringList;
  lineNo, n: Integer;
  raw, kv, key, val: string;
  tok: TStringArray;
  sawVersion: Boolean;
  eqPos, i: Integer;

  procedure GrowV;  begin n := Length(Model.Vertices); SetLength(Model.Vertices, n+1); end;
  procedure GrowC;  begin n := Length(Model.Curves);   SetLength(Model.Curves,   n+1); end;
  procedure GrowE;  begin n := Length(Model.Edges);    SetLength(Model.Edges,    n+1); end;
  procedure GrowLP; begin n := Length(Model.Loops);    SetLength(Model.Loops,    n+1); end;
  procedure GrowSF; begin n := Length(Model.Surfaces); SetLength(Model.Surfaces, n+1); end;
  procedure GrowFC; begin n := Length(Model.Faces);    SetLength(Model.Faces,    n+1); end;
  procedure GrowB;  begin n := Length(Model.Bodies);   SetLength(Model.Bodies,   n+1); end;
  procedure GrowSet;begin n := Length(Model.Sets);     SetLength(Model.Sets,     n+1); end;
  procedure GrowM;  begin n := Length(Model.Meta);     SetLength(Model.Meta,     n+1); end;

begin
  Result := False;
  Model.Header.HasUnits := False;
  Model.Header.HasCoordSys := False;
  Model.Header.HasTolerance := False;
  Model.Header.HasSource := False;
  SetLength(Model.Vertices, 0); SetLength(Model.Curves, 0); SetLength(Model.Edges, 0);
  SetLength(Model.Loops, 0); SetLength(Model.Surfaces, 0); SetLength(Model.Faces, 0);
  SetLength(Model.Bodies, 0); SetLength(Model.Sets, 0); SetLength(Model.Meta, 0);
  sawVersion := False;

  lines := TStringList.Create;
  try
    lines.LoadFromStream(Stream);
    try
      for lineNo := 0 to lines.Count - 1 do
      begin
        raw := Trim(lines[lineNo]);
        if (raw = '') or (raw[1] = '#') then Continue;

        tok := Tokenize(raw);
        if Length(tok) = 0 then Continue;

        if not sawVersion then
        begin
          if (tok[0] <> 'FEM3DGEO') or (Length(tok) < 2) or (tok[1] <> '1.0') then
            raise Exception.Create('first non-comment record must be "FEM3DGEO 1.0"');
          sawVersion := True;
          Continue;
        end;

        if tok[0] = 'UNITS' then
        begin
          Model.Header.HasUnits := True;
          Model.Header.ForceUnit := ''; Model.Header.StressUnit := '';
          for i := 1 to High(tok) do
          begin
            kv := tok[i];
            eqPos := Pos('=', kv);
            if eqPos = 0 then
              raise Exception.CreateFmt('UNITS: expected key=value, got "%s"', [kv]);
            key := Copy(kv, 1, eqPos - 1);
            val := Copy(kv, eqPos + 1, MaxInt);
            if key = 'length' then Model.Header.LengthUnit := val
            else if key = 'force' then Model.Header.ForceUnit := val
            else if key = 'stress' then Model.Header.StressUnit := val;
          end;
        end

        else if tok[0] = 'COORDSYS' then
        begin
          Model.Header.HasCoordSys := True;
          Model.Header.CoordSys := TS(tok, 1, 'COORDSYS');
          if Model.Header.CoordSys <> 'CARTESIAN' then
            raise Exception.CreateFmt('COORDSYS "%s" not recognized (version 1.0 defines CARTESIAN only)',
              [Model.Header.CoordSys]);
        end

        else if tok[0] = 'TOLERANCE' then
        begin
          Model.Header.HasTolerance := True;
          for i := 1 to High(tok) do
          begin
            kv := tok[i];
            eqPos := Pos('=', kv);
            if eqPos = 0 then
              raise Exception.CreateFmt('TOLERANCE: expected key=value, got "%s"', [kv]);
            key := Copy(kv, 1, eqPos - 1);
            val := Copy(kv, eqPos + 1, MaxInt);
            if key = 'coincidence' then Model.Header.TolCoincidence := StrToFloat(val, GFS)
            else if key = 'edge' then Model.Header.TolEdge := StrToFloat(val, GFS)
            else if key = 'surface' then Model.Header.TolSurface := StrToFloat(val, GFS)
            else if key = 'feature' then Model.Header.TolFeature := StrToFloat(val, GFS)
            else if key = 'angle' then Model.Header.TolAngle := StrToFloat(val, GFS);
          end;
        end

        else if tok[0] = 'SOURCE' then
        begin
          Model.Header.HasSource := True;
          Model.Header.SourceName := '';
          for i := 1 to High(tok) do
          begin
            kv := tok[i];
            eqPos := Pos('=', kv);
            if eqPos = 0 then
              raise Exception.CreateFmt('SOURCE: expected key=value, got "%s"', [kv]);
            key := Copy(kv, 1, eqPos - 1);
            val := Copy(kv, eqPos + 1, MaxInt);
            if key = 'format' then Model.Header.SourceFormat := val
            else if key = 'name' then Model.Header.SourceName := val;
          end;
        end

        else if tok[0] = 'VERTEX' then
        begin
          GrowV;
          Model.Vertices[n].Id := TI(tok, 1, 'VERTEX id');
          Model.Vertices[n].P := ReadV3(tok, 2, 'VERTEX');
        end

        else if tok[0] = 'CURVE' then
        begin
          GrowC;
          Model.Curves[n].Id := TI(tok, 1, 'CURVE id');
          if TS(tok, 2, 'CURVE kind') = 'LINE' then
          begin
            Model.Curves[n].Kind := gcLine;
            Model.Curves[n].LineOrigin := ReadV3(tok, 3, 'CURVE LINE origin');
            Model.Curves[n].LineDirection := ReadV3(tok, 6, 'CURVE LINE direction');
          end
          else if TS(tok, 2, 'CURVE kind') = 'CIRCLE' then
          begin
            Model.Curves[n].Kind := gcCircle;
            Model.Curves[n].CircleCenter := ReadV3(tok, 3, 'CURVE CIRCLE center');
            Model.Curves[n].CircleNormal := ReadV3(tok, 6, 'CURVE CIRCLE normal');
            Model.Curves[n].CircleRadius := TD(tok, 9, 'CURVE CIRCLE radius');
          end
          else if TS(tok, 2, 'CURVE kind') = 'ARC3' then
          begin
            Model.Curves[n].Kind := gcArc3;
            Model.Curves[n].Arc3Start := ReadV3(tok, 3, 'CURVE ARC3 start');
            Model.Curves[n].Arc3Mid   := ReadV3(tok, 6, 'CURVE ARC3 mid');
            Model.Curves[n].Arc3End   := ReadV3(tok, 9, 'CURVE ARC3 end');
          end
          else
            raise Exception.CreateFmt(
              'CURVE kind "%s" not recognized -- unknown curve kinds must be rejected, not guessed (spec section 6)',
              [tok[2]]);
        end

        else if tok[0] = 'EDGE' then
        begin
          GrowE;
          Model.Edges[n].Id := TI(tok, 1, 'EDGE id');
          Model.Edges[n].StartVertexId := TI(tok, 2, 'EDGE startVertex');
          Model.Edges[n].EndVertexId := TI(tok, 3, 'EDGE endVertex');
          Model.Edges[n].CurveId := TI(tok, 4, 'EDGE curveId');
          Model.Edges[n].T0 := TD(tok, 5, 'EDGE t0');
          Model.Edges[n].T1 := TD(tok, 6, 'EDGE t1');
          Model.Edges[n].Sense := TSense(tok, 7, 'EDGE sense');
        end

        else if tok[0] = 'LOOP' then
        begin
          GrowLP;
          Model.Loops[n].Id := TI(tok, 1, 'LOOP id');
          SetLength(Model.Loops[n].EdgeUses, 0);
          i := 2;
          while i <= High(tok) do
          begin
            if TS(tok, i, 'LOOP') <> 'EDGE' then
              raise Exception.CreateFmt('LOOP: expected "EDGE", got "%s"', [tok[i]]);
            SetLength(Model.Loops[n].EdgeUses, Length(Model.Loops[n].EdgeUses) + 1);
            Model.Loops[n].EdgeUses[High(Model.Loops[n].EdgeUses)].EdgeId := TI(tok, i + 1, 'LOOP edgeId');
            Model.Loops[n].EdgeUses[High(Model.Loops[n].EdgeUses)].Sense := TSense(tok, i + 2, 'LOOP sense');
            Inc(i, 3);
          end;
        end

        else if tok[0] = 'SURFACE' then
        begin
          GrowSF;
          Model.Surfaces[n].Id := TI(tok, 1, 'SURFACE id');
          if TS(tok, 2, 'SURFACE kind') <> 'PLANE' then
            raise Exception.CreateFmt(
              'SURFACE kind "%s" not recognized (version 1.0 defines PLANE only) -- ' +
              'unknown surface kinds must be rejected, not guessed', [tok[2]]);
          Model.Surfaces[n].Kind := gsPlane;
          Model.Surfaces[n].PlaneOrigin := ReadV3(tok, 3, 'SURFACE PLANE origin');
          Model.Surfaces[n].PlaneNormal := ReadV3(tok, 6, 'SURFACE PLANE normal');
        end

        else if tok[0] = 'FACE' then
        begin
          GrowFC;
          Model.Faces[n].Id := TI(tok, 1, 'FACE id');
          Model.Faces[n].SurfaceId := TI(tok, 2, 'FACE surfaceId');
          if TS(tok, 3, 'FACE') <> 'OUTER' then
            raise Exception.CreateFmt('FACE: expected "OUTER", got "%s"', [tok[3]]);
          Model.Faces[n].OuterLoopId := TI(tok, 4, 'FACE outer loopId');
          SetLength(Model.Faces[n].InnerLoopIds, 0);
          i := 5;
          while i <= High(tok) do
          begin
            if TS(tok, i, 'FACE') <> 'INNER' then
              raise Exception.CreateFmt('FACE: expected "INNER", got "%s"', [tok[i]]);
            SetLength(Model.Faces[n].InnerLoopIds, Length(Model.Faces[n].InnerLoopIds) + 1);
            Model.Faces[n].InnerLoopIds[High(Model.Faces[n].InnerLoopIds)] := TI(tok, i + 1, 'FACE inner loopId');
            Inc(i, 2);
          end;
        end

        else if tok[0] = 'BODY' then
        begin
          GrowB;
          Model.Bodies[n].Id := TI(tok, 1, 'BODY id');
          SetLength(Model.Bodies[n].FaceIds, 0);
          i := 2;
          while i <= High(tok) do
          begin
            if TS(tok, i, 'BODY') <> 'FACE' then
              raise Exception.CreateFmt('BODY: expected "FACE", got "%s"', [tok[i]]);
            SetLength(Model.Bodies[n].FaceIds, Length(Model.Bodies[n].FaceIds) + 1);
            Model.Bodies[n].FaceIds[High(Model.Bodies[n].FaceIds)] := TI(tok, i + 1, 'BODY faceId');
            Inc(i, 2);
          end;
        end

        else if tok[0] = 'SET' then
        begin
          GrowSet;
          Model.Sets[n].Id := TI(tok, 1, 'SET id');
          Model.Sets[n].Name := TS(tok, 2, 'SET name');
          key := TS(tok, 3, 'SET entityType');
          if key = 'VERTEX' then Model.Sets[n].EntityKind := geVertex
          else if key = 'EDGE' then Model.Sets[n].EntityKind := geEdge
          else if key = 'LOOP' then Model.Sets[n].EntityKind := geLoop
          else if key = 'FACE' then Model.Sets[n].EntityKind := geFace
          else if key = 'BODY' then Model.Sets[n].EntityKind := geBody
          else
            raise Exception.CreateFmt(
              'SET entityType "%s" not recognized (version 1.0: VERTEX, EDGE, LOOP, FACE, BODY)', [key]);
          SetLength(Model.Sets[n].EntityIds, 0);
          for i := 4 to High(tok) do
          begin
            SetLength(Model.Sets[n].EntityIds, Length(Model.Sets[n].EntityIds) + 1);
            Model.Sets[n].EntityIds[High(Model.Sets[n].EntityIds)] := TI(tok, i, 'SET entityId');
          end;
        end

        else if tok[0] = 'META' then
        begin
          GrowM;
          SetLength(Model.Meta[n].Pairs, 0);
          for i := 1 to High(tok) do
          begin
            kv := tok[i];
            eqPos := Pos('=', kv);
            if eqPos = 0 then
              raise Exception.CreateFmt('META: expected key=value, got "%s"', [kv]);
            SetLength(Model.Meta[n].Pairs, Length(Model.Meta[n].Pairs) + 1);
            Model.Meta[n].Pairs[High(Model.Meta[n].Pairs)].Key := Copy(kv, 1, eqPos - 1);
            Model.Meta[n].Pairs[High(Model.Meta[n].Pairs)].Value := Copy(kv, eqPos + 1, MaxInt);
          end;
        end

        else
          raise Exception.CreateFmt('unrecognized record type "%s"', [tok[0]]);
      end;

      if not sawVersion then
        raise Exception.Create('file is empty or has no records -- expected "FEM3DGEO 1.0" as the first non-comment line');

      Result := True;
    except
      on E: Exception do
        Err := Format('line %d: %s', [lineNo + 1, E.Message]);
    end;
  finally
    lines.Free;
  end;
end;

function LoadFGeoFile(const FileName: string; out Model: TFEMGeometryModel; out Err: string): Boolean;
var
  fs: TFileStream;
begin
  try
    fs := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  except
    on E: Exception do
    begin
      Err := Format('could not open "%s": %s', [FileName, E.Message]);
      Result := False;
      Exit;
    end;
  end;
  try
    Result := LoadFGeo(fs, Model, Err);
  finally
    fs.Free;
  end;
end;

// ---- Writer ------------------------------------------------------------

function FmtD(V: Double): string;
begin
  // Deterministic, locale-independent representation (spec rule 9 and
  // section 15's canonicalisation requirement) -- 'g' format, 15
  // significant digits (round-trips a double exactly), '.' decimal
  // point unconditionally via GFS.
  Result := FloatToStrF(V, ffGeneral, 15, 0, GFS);
end;

function FmtV3(const V: TGeoVec3): string;
begin
  Result := FmtD(V.X) + ' ' + FmtD(V.Y) + ' ' + FmtD(V.Z);
end;

function QuoteStr(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '"';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      '\': Result := Result + '\\';
      '"': Result := Result + '\"';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
      #9:  Result := Result + '\t';
    else
      Result := Result + c;
    end;
  end;
  Result := Result + '"';
end;

function SenseStr(S: Integer): string;
begin
  if S >= 0 then Result := '+1' else Result := '-1';
end;

// Ascending-ID sort index for an array of records exposing an Id
// field, via a simple index-array insertion sort (these arrays are
// geometry entity counts, not mesh-scale -- not worth a fancier
// algorithm or FPC's generic-function machinery for 8 short arrays).

procedure SortIdx(var Idx: array of Integer; const GetId: array of Integer);
var
  i, j, key, keyId: Integer;
begin
  for i := 1 to High(Idx) do
  begin
    key := Idx[i];
    keyId := GetId[key];
    j := i - 1;
    while (j >= 0) and (GetId[Idx[j]] > keyId) do
    begin
      Idx[j+1] := Idx[j];
      Dec(j);
    end;
    Idx[j+1] := key;
  end;
end;

procedure WriteFGeo(const Model: TFEMGeometryModel; Stream: TStream);
var
  SL: TStringList;
  idx: array of Integer;
  ids: array of Integer;
  i, j, k: Integer;
  ln: string;

  procedure MakeIdx(count: Integer; const getIds: array of Integer);
  var
    ii: Integer;
  begin
    SetLength(idx, count);
    SetLength(ids, count);
    for ii := 0 to count - 1 do
    begin
      idx[ii] := ii;
      ids[ii] := getIds[ii];
    end;
    if count > 1 then SortIdx(idx, ids);
  end;

begin
  SL := TStringList.Create;
  try
    SL.Add('FEM3DGEO 1.0');
    if Model.Header.HasUnits then
    begin
      ln := 'UNITS length=' + Model.Header.LengthUnit;
      if Model.Header.ForceUnit <> '' then ln := ln + ' force=' + Model.Header.ForceUnit;
      if Model.Header.StressUnit <> '' then ln := ln + ' stress=' + Model.Header.StressUnit;
      SL.Add(ln);
    end;
    if Model.Header.HasCoordSys then
      SL.Add('COORDSYS ' + Model.Header.CoordSys);
    if Model.Header.HasTolerance then
      SL.Add(Format('TOLERANCE coincidence=%s edge=%s surface=%s feature=%s angle=%s',
        [FmtD(Model.Header.TolCoincidence), FmtD(Model.Header.TolEdge),
         FmtD(Model.Header.TolSurface), FmtD(Model.Header.TolFeature), FmtD(Model.Header.TolAngle)]));
    if Model.Header.HasSource then
    begin
      ln := 'SOURCE format=' + Model.Header.SourceFormat;
      if Model.Header.SourceName <> '' then ln := ln + ' name=' + QuoteStr(Model.Header.SourceName);
      SL.Add(ln);
    end;
    SL.Add('');

    if Length(Model.Vertices) > 0 then
    begin
      SetLength(ids, Length(Model.Vertices));
      for i := 0 to High(Model.Vertices) do ids[i] := Model.Vertices[i].Id;
      MakeIdx(Length(Model.Vertices), ids);
      for i := 0 to High(idx) do
        with Model.Vertices[idx[i]] do
          SL.Add(Format('VERTEX %d %s', [Id, FmtV3(P)]));
      SL.Add('');
    end;

    if Length(Model.Curves) > 0 then
    begin
      SetLength(ids, Length(Model.Curves));
      for i := 0 to High(Model.Curves) do ids[i] := Model.Curves[i].Id;
      MakeIdx(Length(Model.Curves), ids);
      for i := 0 to High(idx) do
        with Model.Curves[idx[i]] do
          case Kind of
            gcLine:   SL.Add(Format('CURVE %d LINE %s %s', [Id, FmtV3(LineOrigin), FmtV3(LineDirection)]));
            gcCircle: SL.Add(Format('CURVE %d CIRCLE %s %s %s',
                        [Id, FmtV3(CircleCenter), FmtV3(CircleNormal), FmtD(CircleRadius)]));
            gcArc3:   SL.Add(Format('CURVE %d ARC3 %s %s %s', [Id, FmtV3(Arc3Start), FmtV3(Arc3Mid), FmtV3(Arc3End)]));
          end;
      SL.Add('');
    end;

    if Length(Model.Edges) > 0 then
    begin
      SetLength(ids, Length(Model.Edges));
      for i := 0 to High(Model.Edges) do ids[i] := Model.Edges[i].Id;
      MakeIdx(Length(Model.Edges), ids);
      for i := 0 to High(idx) do
        with Model.Edges[idx[i]] do
          SL.Add(Format('EDGE %d %d %d %d %s %s %s',
            [Id, StartVertexId, EndVertexId, CurveId, FmtD(T0), FmtD(T1), SenseStr(Sense)]));
      SL.Add('');
    end;

    if Length(Model.Loops) > 0 then
    begin
      SetLength(ids, Length(Model.Loops));
      for i := 0 to High(Model.Loops) do ids[i] := Model.Loops[i].Id;
      MakeIdx(Length(Model.Loops), ids);
      for i := 0 to High(idx) do
      begin
        ln := Format('LOOP %d', [Model.Loops[idx[i]].Id]);
        for j := 0 to High(Model.Loops[idx[i]].EdgeUses) do
          ln := ln + Format(' EDGE %d %s',
            [Model.Loops[idx[i]].EdgeUses[j].EdgeId, SenseStr(Model.Loops[idx[i]].EdgeUses[j].Sense)]);
        SL.Add(ln);
      end;
      SL.Add('');
    end;

    if Length(Model.Surfaces) > 0 then
    begin
      SetLength(ids, Length(Model.Surfaces));
      for i := 0 to High(Model.Surfaces) do ids[i] := Model.Surfaces[i].Id;
      MakeIdx(Length(Model.Surfaces), ids);
      for i := 0 to High(idx) do
        with Model.Surfaces[idx[i]] do
          SL.Add(Format('SURFACE %d PLANE %s %s', [Id, FmtV3(PlaneOrigin), FmtV3(PlaneNormal)]));
      SL.Add('');
    end;

    if Length(Model.Faces) > 0 then
    begin
      SetLength(ids, Length(Model.Faces));
      for i := 0 to High(Model.Faces) do ids[i] := Model.Faces[i].Id;
      MakeIdx(Length(Model.Faces), ids);
      for i := 0 to High(idx) do
      begin
        ln := Format('FACE %d %d OUTER %d',
          [Model.Faces[idx[i]].Id, Model.Faces[idx[i]].SurfaceId, Model.Faces[idx[i]].OuterLoopId]);
        for j := 0 to High(Model.Faces[idx[i]].InnerLoopIds) do
          ln := ln + Format(' INNER %d', [Model.Faces[idx[i]].InnerLoopIds[j]]);
        SL.Add(ln);
      end;
      SL.Add('');
    end;

    if Length(Model.Bodies) > 0 then
    begin
      SetLength(ids, Length(Model.Bodies));
      for i := 0 to High(Model.Bodies) do ids[i] := Model.Bodies[i].Id;
      MakeIdx(Length(Model.Bodies), ids);
      for i := 0 to High(idx) do
      begin
        ln := Format('BODY %d', [Model.Bodies[idx[i]].Id]);
        for j := 0 to High(Model.Bodies[idx[i]].FaceIds) do
          ln := ln + Format(' FACE %d', [Model.Bodies[idx[i]].FaceIds[j]]);
        SL.Add(ln);
      end;
      SL.Add('');
    end;

    if Length(Model.Sets) > 0 then
    begin
      SetLength(ids, Length(Model.Sets));
      for i := 0 to High(Model.Sets) do ids[i] := Model.Sets[i].Id;
      MakeIdx(Length(Model.Sets), ids);
      for i := 0 to High(idx) do
      begin
        ln := Format('SET %d %s %s', [Model.Sets[idx[i]].Id, QuoteStr(Model.Sets[idx[i]].Name),
          SetEntityKindName(Model.Sets[idx[i]].EntityKind)]);
        for j := 0 to High(Model.Sets[idx[i]].EntityIds) do
          ln := ln + Format(' %d', [Model.Sets[idx[i]].EntityIds[j]]);
        SL.Add(ln);
      end;
      SL.Add('');
    end;

    for k := 0 to High(Model.Meta) do
    begin
      ln := 'META';
      for j := 0 to High(Model.Meta[k].Pairs) do
        ln := ln + ' ' + Model.Meta[k].Pairs[j].Key + '=' + QuoteStr(Model.Meta[k].Pairs[j].Value);
      SL.Add(ln);
    end;

    while (SL.Count > 0) and (SL[SL.Count - 1] = '') do
      SL.Delete(SL.Count - 1);

    SL.LineBreak := #10;
    SL.SaveToStream(Stream);
  finally
    SL.Free;
  end;
end;

procedure WriteFGeoFile(const Model: TFEMGeometryModel; const FileName: string);
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(FileName, fmCreate);
  try
    WriteFGeo(Model, fs);
  finally
    fs.Free;
  end;
end;

initialization
  GFS := DefaultFormatSettings;
  GFS.DecimalSeparator := '.';
  GFS.ThousandSeparator := #0;

end.
