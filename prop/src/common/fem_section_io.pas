unit fem_section_io;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math,
  fem_geometry_types, fem_geometry_io, fem_geometry_validate,
  fem_section_types, fem_section_calc;

function BuildSectionFaces(const Geo: TFEMGeometryModel;
  out Faces: TSectionFaceArray; out Err: string): Boolean;
procedure WritePropFile(const Props: TSectionProperties; const SourceName: string; Stream: TStream);
procedure SavePropFile(const Props: TSectionProperties; const SourceName, FileName: string);

implementation

var
  GFS: TFormatSettings;

function FmtE(V: Double): string;
begin
  Result := FloatToStrF(V, ffExponent, 16, 2, GFS);
end;

// Circumcircle discretization through 3 non-collinear points
function DiscretizeArc(const StartPt, MidPt, EndPt: TGeoVec3; Segments: Integer = 16): TPoint2DArray;
var
  p1, pm, p2: TPoint2D;
  D, numT, t, cx, cy, rad: Double;
  aStart, aMid, aEnd, d1, d2, sweep, a: Double;
  k: Integer;
begin
  p1.X := StartPt.X; p1.Y := StartPt.Y;
  pm.X := MidPt.X;   pm.Y := MidPt.Y;
  p2.X := EndPt.X;   p2.Y := EndPt.Y;

  // Cross product of chord vectors (V_1m x V_m2)
  D := (pm.X - p1.X) * (p2.Y - pm.Y) - (pm.Y - p1.Y) * (p2.X - pm.X);
  if Abs(D) < 1.0E-10 then
  begin
    SetLength(Result, 2);
    Result[0] := p1; Result[1] := p2;
    Exit;
  end;

  // Intersection of perpendicular bisectors
  numT := (p2.X - p1.X) * (p2.X - pm.X) + (p2.Y - p1.Y) * (p2.Y - pm.Y);
  t := numT / (2.0 * D);
  cx := 0.5 * (p1.X + pm.X) - t * (pm.Y - p1.Y);
  cy := 0.5 * (p1.Y + pm.Y) + t * (pm.X - p1.X);
  rad := Sqrt(Sqr(p1.X - cx) + Sqr(p1.Y - cy));

  aStart := ArcTan2(p1.Y - cy, p1.X - cx);
  aMid   := ArcTan2(pm.Y - cy, pm.X - cx);
  aEnd   := ArcTan2(p2.Y - cy, p2.X - cx);

  // Normalize relative angles into (-pi, pi]
  d1 := aMid - aStart;
  while d1 <= -Pi do d1 := d1 + 2.0 * Pi;
  while d1 >   Pi do d1 := d1 - 2.0 * Pi;

  d2 := aEnd - aMid;
  while d2 <= -Pi do d2 := d2 + 2.0 * Pi;
  while d2 >   Pi do d2 := d2 - 2.0 * Pi;

  sweep := d1 + d2;

  SetLength(Result, Segments + 1);
  for k := 0 to Segments do
  begin
    a := aStart + sweep * (k / Segments);
    Result[k].X := cx + rad * Cos(a);
    Result[k].Y := cy + rad * Sin(a);
  end;
end;

function BuildSectionFaces(const Geo: TFEMGeometryModel;
  out Faces: TSectionFaceArray; out Err: string): Boolean;
var
  i, j, k, vStart, vEnd: Integer;
  pts, arcPts: TPoint2DArray;
  p0: TPoint2D;
  diags: TGeoDiagnostics;

  function FindVertex(Id: Integer; out V: TGeoVertex): Boolean;
  var vi: Integer;
  begin
    for vi := 0 to High(Geo.Vertices) do
      if Geo.Vertices[vi].Id = Id then begin V := Geo.Vertices[vi]; Exit(True); end;
    Result := False;
  end;

  function FindCurve(Id: Integer; out C: TGeoCurve): Boolean;
  var ci: Integer;
  begin
    for ci := 0 to High(Geo.Curves) do
      if Geo.Curves[ci].Id = Id then begin C := Geo.Curves[ci]; Exit(True); end;
    Result := False;
  end;

  function FindEdge(Id: Integer; out E: TGeoEdge): Boolean;
  var ei: Integer;
  begin
    for ei := 0 to High(Geo.Edges) do
      if Geo.Edges[ei].Id = Id then begin E := Geo.Edges[ei]; Exit(True); end;
    Result := False;
  end;

  function FindLoop(Id: Integer; out L: TGeoLoop): Boolean;
  var li: Integer;
  begin
    for li := 0 to High(Geo.Loops) do
      if Geo.Loops[li].Id = Id then begin L := Geo.Loops[li]; Exit(True); end;
    Result := False;
  end;

  function LoopToPolygon(const L: TGeoLoop; out OutPoly: TPolygonLoop): Boolean;
  var
    u, vi, nUses: Integer;
    ed: TGeoEdge;
    cv: TGeoCurve;
    vA, vB: TGeoVertex;
  begin
    OutPoly.IsHole := False;
    SetLength(OutPoly.Points, 0);
    nUses := Length(L.EdgeUses);
    if nUses = 0 then Exit(False);

    for u := 0 to nUses - 1 do
    begin
      if not FindEdge(L.EdgeUses[u].EdgeId, ed) then Exit(False);
      if L.EdgeUses[u].Sense >= 0 then
      begin
        vStart := ed.StartVertexId;
        vEnd := ed.EndVertexId;
      end
      else
      begin
        vStart := ed.EndVertexId;
        vEnd := ed.StartVertexId;
      end;

      if not FindVertex(vStart, vA) or not FindVertex(vEnd, vB) then Exit(False);
      p0.X := vA.P.X; p0.Y := vA.P.Y;

      if FindCurve(ed.CurveId, cv) and (cv.Kind = gcArc3) then
      begin
        arcPts := DiscretizeArc(cv.Arc3Start, cv.Arc3Mid, cv.Arc3End, 16);
        if L.EdgeUses[u].Sense < 0 then
        begin
          for vi := High(arcPts) downto 1 do
          begin
            SetLength(OutPoly.Points, Length(OutPoly.Points) + 1);
            OutPoly.Points[High(OutPoly.Points)] := arcPts[vi];
          end;
        end
        else
        begin
          for vi := 0 to High(arcPts) - 1 do
          begin
            SetLength(OutPoly.Points, Length(OutPoly.Points) + 1);
            OutPoly.Points[High(OutPoly.Points)] := arcPts[vi];
          end;
        end;
      end
      else
      begin
        SetLength(OutPoly.Points, Length(OutPoly.Points) + 1);
        OutPoly.Points[High(OutPoly.Points)] := p0;
      end;
    end;

    if Length(OutPoly.Points) < 3 then Exit(False);
    Result := True;
  end;

var
  fc: TGeoFace;
  lp: TGeoLoop;
begin
  Result := False;
  SetLength(Faces, 0);

  InitDiagnostics(diags);
  CheckGeometry(Geo, diags);
  if HasErrors(diags) then
  begin
    Err := 'Input .fgeo failed geometric validation';
    Exit;
  end;

  if Length(Geo.Faces) > 0 then
  begin
    SetLength(Faces, Length(Geo.Faces));
    for i := 0 to High(Geo.Faces) do
    begin
      fc := Geo.Faces[i];
      if not FindLoop(fc.OuterLoopId, lp) then
      begin
        Err := Format('Face %d references nonexistent outer loop %d', [fc.Id, fc.OuterLoopId]);
        Exit;
      end;
      if not LoopToPolygon(lp, Faces[i].OuterLoop) then
      begin
        Err := Format('Failed to convert loop %d to polygon for face %d', [lp.Id, fc.Id]);
        Exit;
      end;
      if PolygonArea2D(Faces[i].OuterLoop.Points) < 0 then
      begin
        pts := Copy(Faces[i].OuterLoop.Points);
        for j := 0 to High(pts) do
          Faces[i].OuterLoop.Points[j] := pts[High(pts) - j];
      end;

      SetLength(Faces[i].Holes, Length(fc.InnerLoopIds));
      for k := 0 to High(fc.InnerLoopIds) do
      begin
        if not FindLoop(fc.InnerLoopIds[k], lp) then
        begin
          Err := Format('Face %d references nonexistent inner loop %d', [fc.Id, fc.InnerLoopIds[k]]);
          Exit;
        end;
        if not LoopToPolygon(lp, Faces[i].Holes[k]) then
        begin
          Err := Format('Failed to convert inner loop %d to polygon', [lp.Id]);
          Exit;
        end;
        Faces[i].Holes[k].IsHole := True;
      end;
    end;
    Result := True;
  end
  else if Length(Geo.Loops) > 0 then
  begin
    SetLength(Faces, 1);
    if not LoopToPolygon(Geo.Loops[0], Faces[0].OuterLoop) then
    begin
      Err := 'Failed to convert loop 1 to polygon';
      Exit;
    end;
    if PolygonArea2D(Faces[0].OuterLoop.Points) < 0 then
    begin
      pts := Copy(Faces[0].OuterLoop.Points);
      for j := 0 to High(pts) do
        Faces[0].OuterLoop.Points[j] := pts[High(pts) - j];
    end;
    Result := True;
  end
  else
    Err := 'Input .fgeo contains no FACE or LOOP records';
end;

procedure WritePropFile(const Props: TSectionProperties; const SourceName: string; Stream: TStream);
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('# FEM3D Section Properties File (.prop)');
    SL.Add('[HEADER]');
    SL.Add('Source=' + SourceName);
    SL.Add('LengthUnit=' + Props.LengthUnit);
    SL.Add('GeneratedBy=femsection');
    SL.Add('');

    SL.Add('[SECTION]');
    SL.Add('Name=' + Props.Name);
    SL.Add('Type=beam');
    SL.Add('');

    SL.Add('[GEOMETRY]');
    SL.Add('Area=' + FmtE(Props.Area));
    SL.Add('Perimeter=' + FmtE(Props.Perimeter));
    SL.Add('CentroidX=' + FmtE(Props.CentroidX));
    SL.Add('CentroidY=' + FmtE(Props.CentroidY));
    SL.Add('BBoxXMin=' + FmtE(Props.BBoxXMin));
    SL.Add('BBoxXMax=' + FmtE(Props.BBoxXMax));
    SL.Add('BBoxYMin=' + FmtE(Props.BBoxYMin));
    SL.Add('BBoxYMax=' + FmtE(Props.BBoxYMax));
    SL.Add('CxPos=' + FmtE(Props.CxPos));
    SL.Add('CxNeg=' + FmtE(Props.CxNeg));
    SL.Add('CyPos=' + FmtE(Props.CyPos));
    SL.Add('CyNeg=' + FmtE(Props.CyNeg));
    SL.Add('');

    SL.Add('[SECOND_MOMENTS]');
    SL.Add('Ixx=' + FmtE(Props.Ixx));
    SL.Add('Iyy=' + FmtE(Props.Iyy));
    SL.Add('Ixy=' + FmtE(Props.Ixy));
    SL.Add('I1=' + FmtE(Props.I1));
    SL.Add('I2=' + FmtE(Props.I2));
    SL.Add('ThetaPrincipalDeg=' + FmtE(Props.ThetaPrincipalDeg));
    SL.Add('');

    SL.Add('[RADII_OF_GYRATION]');
    SL.Add('rx=' + FmtE(Props.rx));
    SL.Add('ry=' + FmtE(Props.ry));
    SL.Add('r1=' + FmtE(Props.r1));
    SL.Add('r2=' + FmtE(Props.r2));
    SL.Add('');

    SL.Add('[SECTION_MODULI]');
    SL.Add('ZxPos=' + FmtE(Props.ZxPos));
    SL.Add('ZxNeg=' + FmtE(Props.ZxNeg));
    SL.Add('Zx=' + FmtE(Props.Zx));
    SL.Add('ZyPos=' + FmtE(Props.ZyPos));
    SL.Add('ZyNeg=' + FmtE(Props.ZyNeg));
    SL.Add('Zy=' + FmtE(Props.Zy));
    SL.Add('Sx=' + FmtE(Props.Sx));
    SL.Add('Sy=' + FmtE(Props.Sy));
    SL.Add('');

    SL.Add('[TORSION]');
    SL.Add('J=' + FmtE(Props.J));
    SL.Add('Ip=' + FmtE(Props.Ip));
    SL.Add('');

    SL.Add('[FEM_PROPERTY_SNIPPET]');
    SL.Add('# Ready-to-paste line for .fem [PROPERTIES] section:');
    SL.Add('# id, type, material, area, Iy, Iz, J, Cy, Cz, Rt');
    SL.Add(Format('Property=1, beam, 1, %s, %s, %s, %s, %s, %s, %s',
      [FmtE(Props.Area), FmtE(Props.Iyy), FmtE(Props.Ixx), FmtE(Props.J),
       FmtE(Props.CyPos), FmtE(Props.CxPos), FmtE(Max(Props.CxPos, Props.CyPos))]));

    SL.LineBreak := #10;
    SL.SaveToStream(Stream);
  finally
    SL.Free;
  end;
end;

procedure SavePropFile(const Props: TSectionProperties; const SourceName, FileName: string);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(FileName, fmCreate);
  try
    WritePropFile(Props, SourceName, FS);
  finally
    FS.Free;
  end;
end;

initialization
  GFS := DefaultFormatSettings;
  GFS.DecimalSeparator := '.';
  GFS.ThousandSeparator := #0;

end.
