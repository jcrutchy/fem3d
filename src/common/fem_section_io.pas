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

const
  // Maximum angle covered by one polygon segment when a curved edge is
  // flattened.  1 degree keeps the area of a full circle within 0.005% and the
  // extreme-fibre distance within 0.002%.
  MaxSegmentAngle = Pi / 180.0;
  MinCurveSegments = 8;

// Circle through 3 non-collinear points (x,y only): centre, radius, the angle
// of the first point and the signed sweep from first to last THROUGH the middle.
function ArcFromThreePoints(const StartPt, MidPt, EndPt: TGeoVec3;
  out Cx, Cy, Rad, AStart, Sweep: Double): Boolean;
var
  p1, pm, p2: TPoint2D;
  D, numT, t: Double;
  aMid, aEnd, d1, d2: Double;
begin
  p1.X := StartPt.X; p1.Y := StartPt.Y;
  pm.X := MidPt.X;   pm.Y := MidPt.Y;
  p2.X := EndPt.X;   p2.Y := EndPt.Y;

  // Cross product of chord vectors (V_1m x V_m2)
  D := (pm.X - p1.X) * (p2.Y - pm.Y) - (pm.Y - p1.Y) * (p2.X - pm.X);
  if Abs(D) < 1.0E-10 then Exit(False);

  // Intersection of perpendicular bisectors
  numT := (p2.X - p1.X) * (p2.X - pm.X) + (p2.Y - p1.Y) * (p2.Y - pm.Y);
  t := numT / (2.0 * D);
  Cx := 0.5 * (p1.X + pm.X) - t * (pm.Y - p1.Y);
  Cy := 0.5 * (p1.Y + pm.Y) + t * (pm.X - p1.X);
  Rad := Sqrt(Sqr(p1.X - Cx) + Sqr(p1.Y - Cy));

  AStart := ArcTan2(p1.Y - Cy, p1.X - Cx);
  aMid   := ArcTan2(pm.Y - Cy, pm.X - Cx);
  aEnd   := ArcTan2(p2.Y - Cy, p2.X - Cx);

  // Normalize relative angles into (-pi, pi]
  d1 := aMid - AStart;
  while d1 <= -Pi do d1 := d1 + 2.0 * Pi;
  while d1 >   Pi do d1 := d1 - 2.0 * Pi;
  d2 := aEnd - aMid;
  while d2 <= -Pi do d2 := d2 + 2.0 * Pi;
  while d2 >   Pi do d2 := d2 - 2.0 * Pi;
  Sweep := d1 + d2;
  Result := True;
end;

// Points along a curved edge from curve parameter T0 to T1 (increasing t is
// the curve's positive direction).  ARC3: t runs 0..1 over the whole
// three-point arc.  CIRCLE: t is the angle in radians from +X, counter-clockwise
// when the normal points to +Z (clockwise for -Z).  Returns False for a curve
// kind that cannot be flattened here.
function SampleCurvedEdge(const Cv: TGeoCurve; T0, T1: Double;
  out Pts: TPoint2DArray): Boolean;
var
  cx, cy, rad, a0, sweep, ang, extent, dir: Double;
  n, k: Integer;
begin
  Result := False;
  SetLength(Pts, 0);
  case Cv.Kind of
    gcArc3:
      begin
        if not ArcFromThreePoints(Cv.Arc3Start, Cv.Arc3Mid, Cv.Arc3End,
                                  cx, cy, rad, a0, sweep) then Exit;
        extent := Abs(sweep * (T1 - T0));
        n := Ceil(extent / MaxSegmentAngle);
        if n < MinCurveSegments then n := MinCurveSegments;
        SetLength(Pts, n + 1);
        for k := 0 to n do
        begin
          ang := a0 + sweep * (T0 + (T1 - T0) * k / n);
          Pts[k].X := cx + rad * Cos(ang);
          Pts[k].Y := cy + rad * Sin(ang);
        end;
        Result := True;
      end;
    gcCircle:
      begin
        // Only circles in (or parallel to) the XY plane can be sections
        if Abs(Cv.CircleNormal.Z) < 1.0E-9 * (Abs(Cv.CircleNormal.X) + Abs(Cv.CircleNormal.Y)) then
          Exit;
        if Cv.CircleNormal.Z >= 0.0 then dir := 1.0 else dir := -1.0;
        extent := Abs(T1 - T0);
        n := Ceil(extent / MaxSegmentAngle);
        if n < MinCurveSegments then n := MinCurveSegments;
        SetLength(Pts, n + 1);
        for k := 0 to n do
        begin
          ang := dir * (T0 + (T1 - T0) * k / n);
          Pts[k].X := Cv.CircleCenter.X + Cv.CircleRadius * Cos(ang);
          Pts[k].Y := Cv.CircleCenter.Y + Cv.CircleRadius * Sin(ang);
        end;
        Result := True;
      end;
  end;
end;

function BuildSectionFaces(const Geo: TFEMGeometryModel;
  out Faces: TSectionFaceArray; out Err: string): Boolean;
var
  i, j, k, vStart, vEnd: Integer;
  pts: TPoint2DArray;
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
    u, vi, nUses, nPts: Integer;
    ed: TGeoEdge;
    cv: TGeoCurve;
    vA, vB, vS, vE: TGeoVertex;
    samples, tmp: TPoint2DArray;
    dFwd, dRev: Double;
    closedEdge: Boolean;

    procedure AddPoint(const P: TPoint2D);
    begin
      SetLength(OutPoly.Points, Length(OutPoly.Points) + 1);
      OutPoly.Points[High(OutPoly.Points)] := P;
    end;

    function Dist2(const P: TPoint2D; const V: TGeoVertex): Double;
    begin
      Result := Sqr(P.X - V.P.X) + Sqr(P.Y - V.P.Y);
    end;

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

      if FindCurve(ed.CurveId, cv) and (cv.Kind in [gcArc3, gcCircle]) then
      begin
        // Flatten the part of the curve the edge actually covers (t0..t1).
        if not SampleCurvedEdge(cv, ed.T0, ed.T1, samples) then Exit(False);
        nPts := Length(samples);

        // Put the points in the edge's STORED direction (start vertex first).
        // The vertices decide this where they can; for a self-closing edge
        // (start = end) the edge's own sense relative to the curve decides.
        if not FindVertex(ed.StartVertexId, vS) or not FindVertex(ed.EndVertexId, vE) then Exit(False);
        closedEdge := ed.StartVertexId = ed.EndVertexId;
        dFwd := 0.0;
        dRev := 0.0;
        if not closedEdge then
        begin
          dFwd := Dist2(samples[0], vS) + Dist2(samples[nPts - 1], vE);
          dRev := Dist2(samples[nPts - 1], vS) + Dist2(samples[0], vE);
        end;
        if (closedEdge and (ed.Sense < 0)) or ((not closedEdge) and (dRev < dFwd)) then
        begin
          SetLength(tmp, nPts);
          for vi := 0 to nPts - 1 do tmp[vi] := samples[nPts - 1 - vi];
          samples := tmp;
        end;

        // Then into the LOOP's traversal direction
        if L.EdgeUses[u].Sense < 0 then
        begin
          SetLength(tmp, nPts);
          for vi := 0 to nPts - 1 do tmp[vi] := samples[nPts - 1 - vi];
          samples := tmp;
        end;

        // All but the last point (it is the next edge's first point)
        for vi := 0 to nPts - 2 do AddPoint(samples[vi]);
      end
      else
        AddPoint(p0);
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
    if Abs(Props.BeamThetaDeg) > 1.0E-6 then
    begin
      // A beam property has no product of inertia, so the values below are
      // about the section's PRINCIPAL axes, not the x/y axes of the .fgeo.
      SL.Add('# NOT symmetric about its x/y axes (Ixy <> 0): Iy, Iz, Cy, Cz are about the principal axes,');
      SL.Add(Format('# rotated %s deg from the section x/y axes. Orient the member so that its local y axis',
        [FmtE(Props.BeamThetaDeg)]));
      SL.Add(Format('# lies along section direction (%s, %s) and its local z axis along (%s, %s).',
        [FmtE(Props.BeamYDirX), FmtE(Props.BeamYDirY), FmtE(Props.BeamZDirX), FmtE(Props.BeamZDirY)]));
    end;
    SL.Add(Format('Property=1, beam, 1, %s, %s, %s, %s, %s, %s, %s',
      [FmtE(Props.Area), FmtE(Props.BeamIy), FmtE(Props.BeamIz), FmtE(Props.J),
       FmtE(Props.BeamCy), FmtE(Props.BeamCz), FmtE(Props.BeamRt)]));

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
