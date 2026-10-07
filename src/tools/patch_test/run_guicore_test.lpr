program run_guicore_test;
{$mode objfpc}{$H+}

// Tests the GUI-agnostic units behind the native modules: the 2D view
// transform, the property-row builder and the section document. Run from the
// repository root (test.bat does).

uses
  SysUtils, Classes, Math,
  fem_geometry_validate, fem_section_types, fem_section_io,
  fem_viewport2d, fem_proprows, fem_sectiondoc;

var
  Passed, Failed: Integer;

procedure Check(const Name: string; Cond: Boolean; const Detail: string = '');
begin
  if Cond then
  begin
    Inc(Passed);
    WriteLn('PASS  ', Name);
  end
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', Name, '  ', Detail);
  end;
end;

function Near(A, B: Double; Rel: Double = 1.0E-9): Boolean;
begin
  Result := Abs(A - B) <= Rel * Max(1.0, Max(Abs(A), Abs(B)));
end;

procedure TestViewport;
var
  V: TViewport2D;
  SX, SY, X, Y, X0, Y0, X1, Y1, MaxErr, Step: Double;
  I: Integer;
  Ok: Boolean;
begin
  WriteLn('--- viewport ---');
  V.Init(800, 600);
  V.Scale := 3.7;
  V.OffX := 120.5;
  V.OffY := 410.25;

  MaxErr := 0;
  for I := 0 to 99 do
  begin
    X := (I - 50) * 13.7;
    Y := (I * 7 mod 100 - 50) * 9.1;
    V.WorldToScreen(X, Y, SX, SY);
    V.ScreenToWorld(SX, SY, X0, Y0);
    MaxErr := Max(MaxErr, Max(Abs(X0 - X), Abs(Y0 - Y)));
  end;
  Check('world -> screen -> world round trip', MaxErr < 1.0E-9, FloatToStr(MaxErr));

  V.WorldToScreen(0, 10, SX, SY);
  V.WorldToScreen(0, 20, X, Y);
  Check('world Y points UP on screen (larger y -> smaller pixel row)', Y < SY);

  V.ScreenToWorld(300, 200, X0, Y0);
  V.ZoomAt(300, 200, 1.7);
  V.ScreenToWorld(300, 200, X1, Y1);
  Check('zoom keeps the world point under the cursor fixed',
    Near(X0, X1) and Near(Y0, Y1));
  Check('zoom in increases the scale', Near(V.Scale, 3.7 * 1.7));

  V.ZoomAt(0, 0, 1.0E30);
  Check('scale is clamped at the maximum', V.Scale <= MaxViewScale);
  V.ZoomAt(0, 0, 1.0E-30);
  Check('scale is clamped at the minimum', V.Scale >= MinViewScale);

  V.Init(800, 600);
  V.Pan(25, -40);
  V.ScreenToWorld(400, 300, X, Y);
  Check('pan moves the origin by the given pixels',
    Near(V.OffX, 425) and Near(V.OffY, 260));

  V.Init(800, 600);
  V.Fit(-100, 100, -50, 50, 0.1);
  Ok := True;
  V.WorldToScreen(-100, -50, SX, SY);
  Ok := Ok and (SX >= 0) and (SY <= 600);
  V.WorldToScreen(100, 50, SX, SY);
  Ok := Ok and (SX <= 800) and (SY >= 0);
  Check('fit: the box lies inside the view', Ok);
  V.WorldToScreen(0, 0, SX, SY);
  Check('fit: the box centre is the view centre', Near(SX, 400) and Near(SY, 300));
  V.WorldToScreen(-100, 0, SX, SY);
  V.WorldToScreen(100, 0, X, Y);
  Check('fit: the limiting dimension fills (1 - 2 margin) of the view',
    Near(X - SX, 800 * 0.8, 1.0E-9));

  V.Init(800, 600);
  V.Fit(5, 5, 7, 7);
  Check('fit of a single point does not blow up', (V.Scale > 0) and (V.Scale < 1.0E9));

  V.Init(800, 600);
  V.Fit(-100, 100, -50, 50);
  V.ScreenToWorld(400, 300, X0, Y0);
  V.Resize(1000, 400);
  V.ScreenToWorld(500, 200, X1, Y1);
  Check('resize keeps the centre world point at the centre', Near(X0, X1) and Near(Y0, Y1));

  Ok := True;
  V.Init(800, 600);
  for I := 0 to 40 do
  begin
    V.Scale := Power(10.0, -4 + I * 0.2);
    Step := V.GridStep(50);
    // step is 1, 2 or 5 times a power of ten
    X := Step / Power(10.0, Floor(Log10(Step) + 1.0E-9));
    if not (Near(X, 1) or Near(X, 2) or Near(X, 5)) then Ok := False;
    // and gives at least the requested spacing, but not wastefully more
    if (Step * V.Scale < 50 - 1.0E-6) or (Step * V.Scale > 50 * 2.5 + 1.0E-6) then Ok := False;
  end;
  Check('grid step is 1/2/5 x 10^n and 50..125 pixels apart over 8 decades', Ok);
end;

procedure TestFormat;
begin
  WriteLn('--- value formatting ---');
  Check('format: 3230.9', FormatPropValue(3230.9) = '3230.9', FormatPropValue(3230.9));
  Check('format: 0', FormatPropValue(0) = '0');
  Check('format: tiny numerical noise shows as 0', FormatPropValue(-4.5E-15) = '0');
  Check('format: large values use an exponent (2.35798E7)', FormatPropValue(2.357977894E7) = '2.35798E7',
    FormatPropValue(2.357977894E7));
  Check('format: negative', FormatPropValue(-12.5) = '-12.5');
  Check('unit text: area', DimUnitText(pdArea, 'mm') = 'mm^2');
  Check('unit text: I', DimUnitText(pdLength4, 'in') = 'in^4');
  Check('unit text: angle', DimUnitText(pdAngleDeg, 'mm') = 'deg');
end;

// Parses the numeric "Key=Value" lines of the sections that carry numbers.
procedure ParsePropFile(const Text: string; Keys: TStringList; Values: TList);
var
  SL: TStringList;
  I, P: Integer;
  Line, Sect, K: string;
  V: Double;
  FS: TFormatSettings;
  PV: ^Double;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SL := TStringList.Create;
  try
    SL.Text := Text;
    Sect := '';
    for I := 0 to SL.Count - 1 do
    begin
      Line := Trim(SL[I]);
      if (Line = '') or (Line[1] = '#') then Continue;
      if Line[1] = '[' then
      begin
        Sect := Line;
        Continue;
      end;
      if (Sect = '[HEADER]') or (Sect = '[SECTION]') or (Sect = '[FEM_PROPERTY_SNIPPET]') then Continue;
      P := Pos('=', Line);
      if P < 2 then Continue;
      K := Copy(Line, 1, P - 1);
      if TryStrToFloat(Copy(Line, P + 1, MaxInt), V, FS) then
      begin
        New(PV);
        PV^ := V;
        Keys.Add(K);
        Values.Add(PV);
      end;
    end;
  finally
    SL.Free;
  end;
end;

procedure TestRowsAgainstPropFile(const FgeoPath: string);
var
  Doc: TSectionDoc;
  Rows: TPropRowArray;
  Keys: TStringList;
  Values: TList;
  MS: TMemoryStream;
  Text: string;
  I, J, Found, Missing, Mismatch: Integer;
  Group: string;
  GroupsOk: Boolean;
begin
  WriteLn('--- rows vs the .prop file femsection writes: ', ExtractFileName(FgeoPath), ' ---');
  Doc := TSectionDoc.Create;
  Keys := TStringList.Create;
  Values := TList.Create;
  MS := TMemoryStream.Create;
  try
    if not Doc.Load(FgeoPath) then
    begin
      Check('load ' + FgeoPath, False, Doc.ErrorText);
      Exit;
    end;
    Doc.ComputeFull;
    WritePropFile(Doc.Props, ExtractFileName(FgeoPath), MS);
    SetLength(Text, MS.Size);
    MS.Position := 0;
    if MS.Size > 0 then MS.ReadBuffer(Text[1], MS.Size);
    ParsePropFile(Text, Keys, Values);
    BuildPropRows(Doc.Props, False, Rows);

    Check('the .prop file has numeric keys to compare', Keys.Count >= 30,
      IntToStr(Keys.Count));

    Missing := 0;
    Mismatch := 0;
    for I := 0 to Keys.Count - 1 do
    begin
      Found := -1;
      for J := 0 to High(Rows) do
        if Rows[J].Key = Keys[I] then Found := J;
      if Found < 0 then
      begin
        Inc(Missing);
        WriteLn('      no row for .prop key ', Keys[I]);
      end
      else if not Near(Rows[Found].Value, Double(Values[I]^), 1.0E-12) then
      begin
        Inc(Mismatch);
        WriteLn('      value differs for ', Keys[I], ': row=', Rows[Found].Value, ' file=', Double(Values[I]^));
      end;
    end;
    Check('every numeric key in the .prop file has a displayed row', Missing = 0,
      IntToStr(Missing) + ' missing');
    Check('every displayed row equals the value in the .prop file', Mismatch = 0,
      IntToStr(Mismatch) + ' differ');

    Found := 0;
    for I := 0 to High(Rows) do
      if Rows[I].InPropFile then Inc(Found);
    Check('rows flagged InPropFile match the number of .prop keys', Found = Keys.Count,
      IntToStr(Found) + ' vs ' + IntToStr(Keys.Count));

    GroupsOk := True;
    Group := '';
    for I := 0 to High(Rows) do
      if Rows[I].Group = '' then GroupsOk := False;
    Check('every row belongs to a group', GroupsOk);

    BuildPropRows(Doc.Props, True, Rows);
    Found := 0;
    for I := 0 to High(Rows) do
      if Rows[I].Pending then
      begin
        Inc(Found);
        if Rows[I].Key <> 'J' then Found := 100;
      end;
    Check('JPending marks only the torsion constant J as pending', Found = 1);
  finally
    for I := 0 to Values.Count - 1 do Dispose(PDouble(Values[I]));
    MS.Free;
    Values.Free;
    Keys.Free;
    Doc.Free;
  end;
end;

function SaveRefused(Doc: TSectionDoc): Boolean;
begin
  Result := False;
  try
    if not Doc.FacesOk then Doc.SaveProp(GetTempDir + 'never.prop');
  except
    Result := True;
  end;
end;

procedure TestDoc;
var
  Doc: TSectionDoc;
  QuickJ, XMin, XMax, YMin, YMax: Double;
begin
  WriteLn('--- section document ---');
  Doc := TSectionDoc.Create;
  try
    Check('loads the 200 UB 25.4 example', Doc.Load('examples' + DirectorySeparator + 'prop' +
      DirectorySeparator + '200ub25_4.fgeo'), Doc.ErrorText);
    Check('quick pass: area equals the printed 3230.9 mm^2 within 0.1%',
      Abs(Doc.Props.Area - 3230.9) / 3230.9 < 1.0E-3, FloatToStr(Doc.Props.Area));
    Check('the section name comes from the SOURCE line', Doc.Props.Name = '200UB25.4', Doc.Props.Name);
    Check('length unit is read from the file', Doc.Props.LengthUnit = 'mm');
    Check('no diagnostics on a good file', ErrorCount(Doc.Diags) = 0);
    Check('torsion is not solved until asked', not Doc.FullDone);
    QuickJ := Doc.Props.J;
    Doc.ComputeFull;
    Check('full pass solves J', Doc.FullDone);
    Check('the solved J is larger than the thin-wall lower bound used by the quick pass',
      Doc.Props.J > QuickJ, FloatToStr(QuickJ) + ' -> ' + FloatToStr(Doc.Props.J));
    Check('the solved J is close to the printed 63000 mm^4 (catalogue J is approximate, 5%)',
      Abs(Doc.Props.J - 63000) / 63000 < 0.05, FloatToStr(Doc.Props.J));
    Check('face bounds are found', Doc.FaceBounds(XMin, XMax, YMin, YMax));
    Check('face bounds match the section size', Near(XMax - XMin, 133.0, 1.0E-6) and Near(YMax - YMin, 203.2, 1.0E-6));
    Check('the file is not reported as changed straight after loading', not Doc.FileChanged);

    Check('a plate with a hole loads', Doc.Load('tests' + DirectorySeparator + 'geometry' +
      DirectorySeparator + 'good' + DirectorySeparator + '002_plate_with_hole.fgeo'), Doc.ErrorText);
    Check('the hole is subtracted (one face with one hole)',
      (Length(Doc.Faces) = 1) and (Length(Doc.Faces[0].Holes) = 1));

    Check('a missing file is refused with a message',
      (not Doc.Load('no_such_file.fgeo')) and (Doc.ErrorText <> '') and (not Doc.Loaded));
    Check('a malformed model is refused and its diagnostics are kept',
      (not Doc.Load('tests' + DirectorySeparator + 'geometry' + DirectorySeparator + 'borked' +
        DirectorySeparator + '001_dangling_edge.fgeo')) or (ErrorCount(Doc.Diags) > 0));
    Check('...the diagnostics name a GEO code',
      (Length(Doc.Diags.Items) > 0) and (Copy(Doc.Diags.Items[0].Code, 1, 3) = 'GEO'));
    Check('saving a section that did not load is refused', SaveRefused(Doc));
  finally
    Doc.Free;
  end;
end;

// Architecture rule: nothing in src/common may depend on the LCL, so every
// shared unit stays usable from the command-line tools and testable headlessly.
procedure TestNoLclInCommon;
const
  Forbidden: array[0..11] of string = ('forms', 'controls', 'graphics', 'dialogs',
    'lcltype', 'lclintf', 'interfaces', 'stdctrls', 'extctrls', 'comctrls', 'menus', 'grids');
var
  SR: TSearchRec;
  SL: TStringList;
  Dir, Text, Clause, Tok: string;
  P, Q, I, K, Bad, Files: Integer;
  Words: TStringList;

  function IsIdent(C: Char): Boolean;
  begin
    Result := C in ['a'..'z', 'A'..'Z', '0'..'9', '_'];
  end;

begin
  WriteLn('--- architecture: shared units do not use the LCL ---');
  Dir := 'src' + DirectorySeparator + 'common' + DirectorySeparator;
  Bad := 0;
  Files := 0;
  SL := TStringList.Create;
  Words := TStringList.Create;
  try
    if FindFirst(Dir + '*.pas', faAnyFile, SR) = 0 then
    begin
      repeat
        Inc(Files);
        SL.LoadFromFile(Dir + SR.Name);
        Text := LowerCase(SL.Text);
        P := 1;
        while True do
        begin
          P := Pos('uses', Text);
          if P = 0 then Break;
          // a whole word "uses"
          if ((P > 1) and IsIdent(Text[P - 1])) or ((P + 4 <= Length(Text)) and IsIdent(Text[P + 4])) then
          begin
            Delete(Text, 1, P + 3);
            Continue;
          end;
          Q := Pos(';', Text);
          if Q = 0 then Break;
          Clause := Copy(Text, P + 4, Q - P - 4);
          Delete(Text, 1, Q);
          Words.Clear;
          Tok := '';
          for I := 1 to Length(Clause) do
            if IsIdent(Clause[I]) then Tok := Tok + Clause[I]
            else
            begin
              if Tok <> '' then Words.Add(Tok);
              Tok := '';
            end;
          if Tok <> '' then Words.Add(Tok);
          for I := 0 to Words.Count - 1 do
            for K := 0 to High(Forbidden) do
              if Words[I] = Forbidden[K] then
              begin
                Inc(Bad);
                WriteLn('      ', SR.Name, ' uses ', Words[I]);
              end;
        end;
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
  finally
    Words.Free;
    SL.Free;
  end;
  Check('src/common was scanned', Files > 20, IntToStr(Files) + ' files');
  Check('no unit in src/common uses an LCL unit', Bad = 0, IntToStr(Bad) + ' violations');
end;

begin
  Passed := 0;
  Failed := 0;
  TestNoLclInCommon;
  TestViewport;
  TestFormat;
  TestRowsAgainstPropFile('examples' + DirectorySeparator + 'prop' + DirectorySeparator + '200ub25_4.fgeo');
  TestRowsAgainstPropFile('examples' + DirectorySeparator + 'prop' + DirectorySeparator + '150x100x12ua.fgeo');
  TestDoc;
  WriteLn;
  WriteLn(Passed, ' / ', Passed + Failed, ' checks passed');
  if Failed = 0 then WriteLn('ALL CHECKS PASSED') else Halt(1);
end.
