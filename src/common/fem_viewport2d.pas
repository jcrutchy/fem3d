unit fem_viewport2d;

// 2D view transform shared by the native GUI modules (section editor, geometry
// editor ...). No LCL dependency, so it is unit-tested headlessly.
//
// World space has Y pointing UP (as in engineering drawings); screen space has
// Y pointing DOWN (pixels). Scale is pixels per world unit.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

type
  TViewport2D = record
    Scale: Double;       // pixels per world unit
    OffX, OffY: Double;  // screen position (pixels) of the world origin
    Width, Height: Integer;
    procedure Init(AWidth, AHeight: Integer);
    procedure WorldToScreen(X, Y: Double; out SX, SY: Double);
    procedure ScreenToWorld(SX, SY: Double; out X, Y: Double);
    // Drag the view by (DX, DY) screen pixels.
    procedure Pan(DX, DY: Double);
    // Zoom by Factor (>1 zooms in) keeping the world point under (SX, SY) fixed.
    procedure ZoomAt(SX, SY, Factor: Double);
    // Fit the world box into the view, leaving Margin (fraction of each side).
    procedure Fit(XMin, XMax, YMin, YMax: Double; Margin: Double = 0.08);
    // Change the view size, keeping the world point at the centre fixed.
    procedure Resize(NewWidth, NewHeight: Integer);
    // A "nice" grid spacing (1, 2 or 5 x 10^n world units) that is at least
    // MinPixels apart on screen.
    function GridStep(MinPixels: Double): Double;
  end;

const
  MinViewScale = 1.0E-9;
  MaxViewScale = 1.0E9;

implementation

uses
  Math;

procedure TViewport2D.Init(AWidth, AHeight: Integer);
begin
  Width := AWidth;
  Height := AHeight;
  Scale := 1.0;
  OffX := AWidth / 2.0;
  OffY := AHeight / 2.0;
end;

procedure TViewport2D.WorldToScreen(X, Y: Double; out SX, SY: Double);
begin
  SX := OffX + X * Scale;
  SY := OffY - Y * Scale;
end;

procedure TViewport2D.ScreenToWorld(SX, SY: Double; out X, Y: Double);
begin
  X := (SX - OffX) / Scale;
  Y := (OffY - SY) / Scale;
end;

procedure TViewport2D.Pan(DX, DY: Double);
begin
  OffX := OffX + DX;
  OffY := OffY + DY;
end;

procedure TViewport2D.ZoomAt(SX, SY, Factor: Double);
var
  WX, WY, NewScale: Double;
begin
  if Factor <= 0 then Exit;
  ScreenToWorld(SX, SY, WX, WY);
  NewScale := Scale * Factor;
  if NewScale < MinViewScale then NewScale := MinViewScale;
  if NewScale > MaxViewScale then NewScale := MaxViewScale;
  Scale := NewScale;
  OffX := SX - WX * Scale;
  OffY := SY + WY * Scale;
end;

procedure TViewport2D.Fit(XMin, XMax, YMin, YMax: Double; Margin: Double);
var
  W, H, AvailW, AvailH, S, CX, CY: Double;
begin
  if XMax < XMin then begin S := XMin; XMin := XMax; XMax := S; end;
  if YMax < YMin then begin S := YMin; YMin := YMax; YMax := S; end;
  W := XMax - XMin;
  H := YMax - YMin;
  CX := 0.5 * (XMin + XMax);
  CY := 0.5 * (YMin + YMax);
  AvailW := Width * (1.0 - 2.0 * Margin);
  AvailH := Height * (1.0 - 2.0 * Margin);
  if AvailW < 1 then AvailW := 1;
  if AvailH < 1 then AvailH := 1;
  if (W <= 0) and (H <= 0) then
    S := 1.0
  else if W <= 0 then
    S := AvailH / H
  else if H <= 0 then
    S := AvailW / W
  else
    S := Min(AvailW / W, AvailH / H);
  if S < MinViewScale then S := MinViewScale;
  if S > MaxViewScale then S := MaxViewScale;
  Scale := S;
  OffX := Width / 2.0 - CX * Scale;
  OffY := Height / 2.0 + CY * Scale;
end;

procedure TViewport2D.Resize(NewWidth, NewHeight: Integer);
var
  CX, CY: Double;
begin
  if (NewWidth <= 0) or (NewHeight <= 0) then Exit;
  ScreenToWorld(Width / 2.0, Height / 2.0, CX, CY);
  Width := NewWidth;
  Height := NewHeight;
  OffX := Width / 2.0 - CX * Scale;
  OffY := Height / 2.0 + CY * Scale;
end;

function TViewport2D.GridStep(MinPixels: Double): Double;
var
  Raw, Pow10, Frac: Double;
begin
  Raw := MinPixels / Scale;
  if Raw <= 0 then Exit(1.0);
  Pow10 := Power(10.0, Floor(Log10(Raw)));
  Frac := Raw / Pow10;
  if Frac <= 1.0 then Result := 1.0 * Pow10
  else if Frac <= 2.0 then Result := 2.0 * Pow10
  else if Frac <= 5.0 then Result := 5.0 * Pow10
  else Result := 10.0 * Pow10;
end;

end.
