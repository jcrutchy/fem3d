unit secedit_view;

// The drawing surface of the native section editor: a custom-painted control
// that shows the section faces with a grid, the centroid and the principal
// axes, with wheel zoom and drag pan. All view maths lives in fem_viewport2d
// (unit-tested); this unit only paints and forwards mouse input.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Types,
  fem_section_types, fem_viewport2d;

type
  TCursorEvent = procedure(Sender: TObject; WorldX, WorldY: Double) of object;

  TSectionView = class(TCustomControl)
  private
    FVp: TViewport2D;
    FFaces: TSectionFaceArray;
    FProps: TSectionProperties;
    FHasProps: Boolean;
    FMessage: string;
    FLengthUnit: string;
    FShowGrid, FShowPrincipal, FShowBBox, FShowCentroid: Boolean;
    FDragging: Boolean;
    FDragX, FDragY: Integer;
    FOnCursor: TCursorEvent;
    FOnViewChange: TNotifyEvent;
    procedure SetShowGrid(V: Boolean);
    procedure SetShowPrincipal(V: Boolean);
    procedure SetShowBBox(V: Boolean);
    procedure DrawGrid;
    procedure DrawFaces;
    procedure DrawOverlays;
    procedure DrawCentred(const S: string; Dy: Integer);
    function PX(X: Double): Integer;
    function PY(Y: Double): Integer;
    procedure FaceBounds(out XMin, XMax, YMin, YMax: Double; out Any: Boolean);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    // Shows these faces. Props supplies the centroid and principal axes.
    procedure SetSection(const AFaces: TSectionFaceArray; const AProps: TSectionProperties;
      AHasProps: Boolean);
    // Shows a message instead of a section (a file that cannot be used).
    procedure SetMessage(const AMessage: string);
    // Props changed (e.g. the full torsion solve finished) but the shape did not.
    procedure UpdateProps(const AProps: TSectionProperties);
    procedure FitView;
    property ShowGrid: Boolean read FShowGrid write SetShowGrid;
    property ShowPrincipal: Boolean read FShowPrincipal write SetShowPrincipal;
    property ShowBBox: Boolean read FShowBBox write SetShowBBox;
    property Viewport: TViewport2D read FVp;
    property OnCursor: TCursorEvent read FOnCursor write FOnCursor;
    property OnViewChange: TNotifyEvent read FOnViewChange write FOnViewChange;
  end;

implementation

uses
  Math;

const
  ColBackground = $2A1E16;   // BGR: dark slate
  ColGrid       = $4A3A2C;
  ColGridMajor  = $6B5642;
  ColAxis       = $9C8468;
  ColFill       = $8C6238;
  ColOutline    = $FFC47D;
  ColText       = $D8CFC4;
  ColCentroid   = $2F9CF5;   // orange
  ColPrincipal  = $38C0F5;   // amber
  ColBBox       = $8A7A6A;
  ColError      = $5050F0;

constructor TSectionView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  FShowGrid := True;
  FShowPrincipal := True;
  FShowBBox := False;
  FShowCentroid := True;
  FLengthUnit := 'mm';
  FVp.Init(Max(ClientWidth, 1), Max(ClientHeight, 1));
  FVp.Scale := 1.0;
end;

function TSectionView.PX(X: Double): Integer;
var
  SX, SY: Double;
begin
  FVp.WorldToScreen(X, 0, SX, SY);
  Result := Round(Max(-1.0E6, Min(1.0E6, SX)));
end;

function TSectionView.PY(Y: Double): Integer;
var
  SX, SY: Double;
begin
  FVp.WorldToScreen(0, Y, SX, SY);
  Result := Round(Max(-1.0E6, Min(1.0E6, SY)));
end;

procedure TSectionView.SetShowGrid(V: Boolean);
begin
  if FShowGrid = V then Exit;
  FShowGrid := V;
  Invalidate;
end;

procedure TSectionView.SetShowPrincipal(V: Boolean);
begin
  if FShowPrincipal = V then Exit;
  FShowPrincipal := V;
  Invalidate;
end;

procedure TSectionView.SetShowBBox(V: Boolean);
begin
  if FShowBBox = V then Exit;
  FShowBBox := V;
  Invalidate;
end;

procedure TSectionView.FaceBounds(out XMin, XMax, YMin, YMax: Double; out Any: Boolean);
var
  F, K: Integer;
  P: TPoint2D;
begin
  Any := False;
  XMin := 0; XMax := 0; YMin := 0; YMax := 0;
  for F := 0 to High(FFaces) do
    for K := 0 to High(FFaces[F].OuterLoop.Points) do
    begin
      P := FFaces[F].OuterLoop.Points[K];
      if not Any then
      begin
        XMin := P.X; XMax := P.X; YMin := P.Y; YMax := P.Y;
        Any := True;
      end
      else
      begin
        if P.X < XMin then XMin := P.X;
        if P.X > XMax then XMax := P.X;
        if P.Y < YMin then YMin := P.Y;
        if P.Y > YMax then YMax := P.Y;
      end;
    end;
end;

procedure TSectionView.SetSection(const AFaces: TSectionFaceArray;
  const AProps: TSectionProperties; AHasProps: Boolean);
begin
  FFaces := AFaces;
  FProps := AProps;
  FHasProps := AHasProps;
  FMessage := '';
  if AProps.LengthUnit <> '' then FLengthUnit := AProps.LengthUnit;
  Invalidate;
end;

procedure TSectionView.SetMessage(const AMessage: string);
begin
  FFaces := nil;
  FHasProps := False;
  FMessage := AMessage;
  Invalidate;
end;

procedure TSectionView.UpdateProps(const AProps: TSectionProperties);
begin
  FProps := AProps;
  Invalidate;
end;

procedure TSectionView.FitView;
var
  XMin, XMax, YMin, YMax: Double;
  Any: Boolean;
begin
  FVp.Resize(Max(ClientWidth, 1), Max(ClientHeight, 1));
  FaceBounds(XMin, XMax, YMin, YMax, Any);
  if Any then
    FVp.Fit(XMin, XMax, YMin, YMax, 0.12)
  else
  begin
    FVp.Init(Max(ClientWidth, 1), Max(ClientHeight, 1));
    FVp.Scale := 1.0;
  end;
  Invalidate;
  if Assigned(FOnViewChange) then FOnViewChange(Self);
end;

procedure TSectionView.Resize;
begin
  inherited Resize;
  FVp.Resize(Max(ClientWidth, 1), Max(ClientHeight, 1));
end;

procedure TSectionView.DrawGrid;
var
  Step, X0, Y0, X1, Y1, V: Double;
  I, I0, I1, Lines: Integer;
begin
  Step := FVp.GridStep(48);
  FVp.ScreenToWorld(0, ClientHeight, X0, Y0);
  FVp.ScreenToWorld(ClientWidth, 0, X1, Y1);

  if FShowGrid then
  begin
    I0 := Floor(X0 / Step);
    I1 := Ceil(X1 / Step);
    Lines := 0;
    for I := I0 to I1 do
    begin
      Inc(Lines);
      if Lines > 400 then Break;
      V := I * Step;
      if I mod 5 = 0 then Canvas.Pen.Color := ColGridMajor else Canvas.Pen.Color := ColGrid;
      Canvas.Line(PX(V), 0, PX(V), ClientHeight);
    end;
    I0 := Floor(Y0 / Step);
    I1 := Ceil(Y1 / Step);
    Lines := 0;
    for I := I0 to I1 do
    begin
      Inc(Lines);
      if Lines > 400 then Break;
      V := I * Step;
      if I mod 5 = 0 then Canvas.Pen.Color := ColGridMajor else Canvas.Pen.Color := ColGrid;
      Canvas.Line(0, PY(V), ClientWidth, PY(V));
    end;
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := ColText;
    Canvas.TextOut(8, ClientHeight - Canvas.TextHeight('Ag') - 6,
      'grid ' + FloatToStr(Step) + ' ' + FLengthUnit);
  end;

  // world axes through the origin
  Canvas.Pen.Color := ColAxis;
  Canvas.Line(PX(0), 0, PX(0), ClientHeight);
  Canvas.Line(0, PY(0), ClientWidth, PY(0));
end;

procedure TSectionView.DrawFaces;
var
  F, H, N: Integer;
  Pts: array of TPoint;
  L: TPolygonLoop;

  procedure LoopToPoints(const Lp: TPolygonLoop);
  var
    Q: Integer;
  begin
    N := Length(Lp.Points);
    SetLength(Pts, N);
    for Q := 0 to N - 1 do
    begin
      Pts[Q].X := PX(Lp.Points[Q].X);
      Pts[Q].Y := PY(Lp.Points[Q].Y);
    end;
  end;

begin
  Canvas.Pen.Width := 1;
  for F := 0 to High(FFaces) do
  begin
    L := FFaces[F].OuterLoop;
    if Length(L.Points) >= 3 then
    begin
      LoopToPoints(L);
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ColFill;
      Canvas.Pen.Color := ColOutline;
      Canvas.Polygon(Pts);
    end;
    for H := 0 to High(FFaces[F].Holes) do
    begin
      L := FFaces[F].Holes[H];
      if Length(L.Points) >= 3 then
      begin
        LoopToPoints(L);
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := ColBackground;
        Canvas.Pen.Color := ColOutline;
        Canvas.Polygon(Pts);
      end;
    end;
  end;
  Canvas.Brush.Style := bsClear;
end;

procedure TSectionView.DrawOverlays;
var
  CX, CY, Th, DX, DY, Len, XMin, XMax, YMin, YMax: Double;
  Any: Boolean;
  R: Integer;
begin
  if (Length(FFaces) = 0) then Exit;

  if FShowBBox then
  begin
    FaceBounds(XMin, XMax, YMin, YMax, Any);
    if Any then
    begin
      Canvas.Pen.Color := ColBBox;
      Canvas.Pen.Style := psDash;
      Canvas.Brush.Style := bsClear;
      Canvas.Rectangle(PX(XMin), PY(YMax), PX(XMax), PY(YMin));
      Canvas.Pen.Style := psSolid;
    end;
  end;

  if not FHasProps then Exit;
  CX := FProps.CentroidX;
  CY := FProps.CentroidY;

  if FShowPrincipal then
  begin
    Th := FProps.ThetaPrincipalRad;
    Len := (ClientWidth + ClientHeight) / Max(FVp.Scale, 1.0E-12);
    Canvas.Pen.Color := ColPrincipal;
    Canvas.Pen.Style := psDash;
    DX := Cos(Th) * Len;
    DY := Sin(Th) * Len;
    Canvas.Line(PX(CX - DX), PY(CY - DY), PX(CX + DX), PY(CY + DY));
    Canvas.Line(PX(CX + DY), PY(CY - DX), PX(CX - DY), PY(CY + DX));
    Canvas.Pen.Style := psSolid;
  end;

  if FShowCentroid then
  begin
    R := 7;
    Canvas.Pen.Color := ColCentroid;
    Canvas.Pen.Width := 2;
    Canvas.Line(PX(CX) - R, PY(CY), PX(CX) + R, PY(CY));
    Canvas.Line(PX(CX), PY(CY) - R, PX(CX), PY(CY) + R);
    Canvas.Brush.Style := bsClear;
    Canvas.Ellipse(PX(CX) - R, PY(CY) - R, PX(CX) + R, PY(CY) + R);
    Canvas.Pen.Width := 1;
  end;
end;

procedure TSectionView.DrawCentred(const S: string; Dy: Integer);
begin
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut((ClientWidth - Canvas.TextWidth(S)) div 2,
    ClientHeight div 2 + Dy, S);
end;

procedure TSectionView.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ColBackground;
  Canvas.Pen.Style := psSolid;
  Canvas.FillRect(0, 0, ClientWidth, ClientHeight);
  DrawGrid;
  DrawFaces;
  DrawOverlays;
  if FMessage <> '' then
  begin
    Canvas.Font.Color := ColError;
    DrawCentred(FMessage, -8);
  end
  else if Length(FFaces) = 0 then
  begin
    Canvas.Font.Color := ColText;
    DrawCentred('Open a .fgeo section file (File > Open)', -8);
  end;
end;

procedure TSectionView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FDragging := True;     // every button pans in this first version
  FDragX := X;
  FDragY := Y;
  Cursor := crSizeAll;
end;

procedure TSectionView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  WX, WY: Double;
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then
  begin
    FVp.Pan(X - FDragX, Y - FDragY);
    FDragX := X;
    FDragY := Y;
    Invalidate;
    if Assigned(FOnViewChange) then FOnViewChange(Self);
  end;
  if Assigned(FOnCursor) then
  begin
    FVp.ScreenToWorld(X, Y, WX, WY);
    FOnCursor(Self, WX, WY);
  end;
end;

procedure TSectionView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
  Cursor := crDefault;
end;

function TSectionView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  FVp.ZoomAt(MousePos.X, MousePos.Y, Power(1.15, WheelDelta / 120.0));
  Invalidate;
  if Assigned(FOnViewChange) then FOnViewChange(Self);
  Result := True;
end;

end.
