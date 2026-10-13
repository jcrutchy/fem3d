unit fem_snap2d;

// Snapping for the native sketch tools: picks the nearest vertex, circle
// centre/quadrant, segment midpoint or grid point to a cursor position. No LCL
// dependency, so it is unit-tested headlessly.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, fem_section_types, fem_sketch;

type
  TSnapKind = (snNone, snVertex, snCenter, snQuadrant, snMidpoint, snGrid);

  TSnapResult = record
    Kind: TSnapKind;
    X, Y: Double;
  end;

function SnapKindName(K: TSnapKind): string;

// Nearest snap point within Tol (world units) of (X, Y). Object snaps win over
// the grid. With ExcludeProfile >= 0 that profile is ignored (it is being
// dragged); with ExcludeVertex >= 0 as well, only that vertex and the midpoints
// of its two segments are ignored (a vertex being moved).
function SnapPoint(const S: TSketch; X, Y, Tol, GridStep: Double;
  UseObjects, UseGrid: Boolean; ExcludeProfile: Integer = -1;
  ExcludeVertex: Integer = -1): TSnapResult;

// Constrains (X, Y) to the horizontal or vertical line through Anchor,
// whichever is nearer.
function OrthoPoint(const Anchor: TPoint2D; X, Y: Double): TPoint2D;

implementation

function SnapKindName(K: TSnapKind): string;
begin
  case K of
    snVertex:   Result := 'vertex';
    snCenter:   Result := 'centre';
    snQuadrant: Result := 'quadrant';
    snMidpoint: Result := 'midpoint';
    snGrid:     Result := 'grid';
  else
    Result := '';
  end;
end;

function SnapPoint(const S: TSketch; X, Y, Tol, GridStep: Double;
  UseObjects, UseGrid: Boolean; ExcludeProfile: Integer;
  ExcludeVertex: Integer): TSnapResult;
var
  BestD: Double;
  BestKind: TSnapKind;

  procedure Offer(AKind: TSnapKind; PX, PY: Double);
  var
    D: Double;
  begin
    D := Sqrt(Sqr(PX - X) + Sqr(PY - Y));
    if D > Tol then Exit;
    // nearest wins; on a tie the more specific kind (lower ordinal) wins
    if (D < BestD - 1.0E-12) or ((Abs(D - BestD) <= 1.0E-12) and (Ord(AKind) < Ord(BestKind))) then
    begin
      BestD := D;
      BestKind := AKind;
      Result.Kind := AKind;
      Result.X := PX;
      Result.Y := PY;
    end;
  end;

var
  I, K, N, Prev: Integer;
  P: TSketchProfile;
begin
  Result.Kind := snNone;
  Result.X := X;
  Result.Y := Y;
  BestD := 1.0E300;
  BestKind := snGrid;

  if UseObjects then
    for I := 0 to High(S.Profiles) do
    begin
      if (I = ExcludeProfile) and (ExcludeVertex < 0) then Continue;
      P := S.Profiles[I];
      if P.Kind = pkCircle then
      begin
        Offer(snCenter, P.Center.X, P.Center.Y);
        Offer(snQuadrant, P.Center.X + P.Radius, P.Center.Y);
        Offer(snQuadrant, P.Center.X - P.Radius, P.Center.Y);
        Offer(snQuadrant, P.Center.X, P.Center.Y + P.Radius);
        Offer(snQuadrant, P.Center.X, P.Center.Y - P.Radius);
      end
      else
      begin
        N := Length(P.Segs);
        for K := 0 to N - 1 do
        begin
          Prev := (K + N - 1) mod N;
          if (I = ExcludeProfile) and (K = ExcludeVertex) then Continue;
          Offer(snVertex, P.Segs[K].P0.X, P.Segs[K].P0.Y);
          // a segment next to the vertex being moved has no fixed midpoint
          if (I = ExcludeProfile) and ((K = ExcludeVertex) or ((K + 1) mod N = ExcludeVertex)) then Continue;
          if P.Segs[K].Kind = skArc then
            Offer(snMidpoint, P.Segs[K].PM.X, P.Segs[K].PM.Y)
          else
            Offer(snMidpoint, 0.5 * (P.Segs[K].P0.X + P.Segs[K].P1.X),
                              0.5 * (P.Segs[K].P0.Y + P.Segs[K].P1.Y));
          if Prev < 0 then Continue;
        end;
      end;
    end;

  if (Result.Kind = snNone) and UseGrid and (GridStep > 0) then
  begin
    Result.Kind := snGrid;
    Result.X := Round(X / GridStep) * GridStep;
    Result.Y := Round(Y / GridStep) * GridStep;
  end;
end;

function OrthoPoint(const Anchor: TPoint2D; X, Y: Double): TPoint2D;
begin
  if Abs(X - Anchor.X) >= Abs(Y - Anchor.Y) then
  begin
    Result.X := X;
    Result.Y := Anchor.Y;
  end
  else
  begin
    Result.X := Anchor.X;
    Result.Y := Y;
  end;
end;

end.
