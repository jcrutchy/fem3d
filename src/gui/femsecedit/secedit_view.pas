unit secedit_view;

// The drawing surface of the native section editor: a custom-painted control
// that shows the sketch (solids and holes) with grid, snapping, the centroid
// and the principal axes, and implements the drawing/selection tools.
//
// All geometry, snapping and undo logic lives in common units
// (fem_viewport2d, fem_sketch, fem_snap2d), which are unit-tested without a
// GUI. This unit paints, turns mouse input into world coordinates, and drives
// those units. The tool actions are also public methods (ClickAt, MoveCursorTo
// ...) so the same code path can be driven by a script in the automated tests.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Types,
  fem_section_types, fem_viewport2d, fem_sketch, fem_snap2d;

type
  TEditTool = (etSelect, etRect, etPolygon, etCircle);

  TCursorEvent = procedure(Sender: TObject; WorldX, WorldY: Double) of object;
  TStringEvent = procedure(Sender: TObject; const AText: string) of object;

  TDragMode = (dmNone, dmPan, dmMove, dmVertex);

  TSectionView = class(TCustomControl)
  private
    FVp: TViewport2D;
    FDoc: TSketchDoc;
    FFaces: TSectionFaceArray;       // read-only display (a file that cannot be edited)
    FProps: TSectionProperties;
    FHasProps: Boolean;
    FMessage: string;
    FLengthUnit: string;
    FShowGrid, FShowPrincipal, FShowBBox, FShowCentroid: Boolean;
    FSnapObjects, FSnapGrid, FOrtho: Boolean;
    FEditable: Boolean;
    FTool: TEditTool;
    FSel: Integer;
    FPts: array of TPoint2D;         // points placed so far by the current tool
    FCursorW: TPoint2D;              // raw cursor position (world)
    FSnap: TSnapResult;              // snapped cursor
    FDrag: TDragMode;
    FDragProfile, FDragVertex: Integer;
    FDragLast: TPoint2D;
    FDragPX, FDragPY: Integer;
    FDragChanged: Boolean;
    FOnCursor: TCursorEvent;
    FOnViewChange: TNotifyEvent;
    FOnSketchChanged: TNotifyEvent;
    FOnSelectionChanged: TNotifyEvent;
    FOnHint: TStringEvent;
    procedure SetShowGrid(V: Boolean);
    procedure SetShowPrincipal(V: Boolean);
    procedure SetShowBBox(V: Boolean);
    procedure SetOrtho(V: Boolean);
    procedure SetTool(V: TEditTool);
    procedure DrawGrid;
    procedure DrawSketch;
    procedure DrawFacesReadOnly;
    procedure DrawPreview;
    procedure DrawOverlays;
    procedure DrawSnapMarker;
    procedure DrawCentred(const S: string; Dy: Integer);
    function PX(X: Double): Integer;
    function PY(Y: Double): Integer;
    function PixelsToWorld(Pixels: Double): Double;
    function SnapWorld(WX, WY: Double; ExProfile, ExVertex: Integer): TSnapResult;
    function Anchor(out A: TPoint2D): Boolean;
    function HitProfile(WX, WY: Double): Integer;
    function HitVertex(WX, WY: Double): Integer;
    procedure Changed;
    procedure SetSelection(I: Integer);
    procedure UpdateHint;
    procedure CommitRect(const A, B: TPoint2D);
    procedure CommitCircle(const C, R: TPoint2D);
    procedure CommitPolygon;
    procedure AddProfileUndoable(const AName: string; const P: TSketchProfile);
    procedure BeginDragChange(const AName: string);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    // The sketch being edited (owned by the form). Setting it makes the view editable.
    procedure SetDoc(ADoc: TSketchDoc);
    // Read-only display of faces (a file that could not be turned into a sketch).
    procedure SetReadOnlyFaces(const AFaces: TSectionFaceArray);
    procedure SetMessage(const AMessage: string);
    procedure SetProps(const AProps: TSectionProperties; AHas: Boolean);
    procedure FitView;
    procedure SketchReplaced;          // the document was replaced or undone/redone
    // tool actions
    procedure ClickAt(WX, WY: Double);
    procedure MoveCursorTo(WX, WY: Double);
    procedure FinishPolygon;
    procedure UndoLastPoint;
    procedure CancelTool;              // Esc: abandon what is being drawn, back to Select
    procedure DeleteSelected;
    procedure ToggleHoleSelected;
    procedure SelectProfile(I: Integer);
    // Presses the left button at (X0, Y0), drags to (X1, Y1) in several steps and
    // releases -- the real mouse handlers, driven by world coordinates (for scripts).
    procedure ScriptDrag(X0, Y0, X1, Y1: Double);
    property Selected: Integer read FSel;
    property Tool: TEditTool read FTool write SetTool;
    property ShowGrid: Boolean read FShowGrid write SetShowGrid;
    property ShowPrincipal: Boolean read FShowPrincipal write SetShowPrincipal;
    property ShowBBox: Boolean read FShowBBox write SetShowBBox;
    property SnapObjects: Boolean read FSnapObjects write FSnapObjects;
    property SnapGrid: Boolean read FSnapGrid write FSnapGrid;
    property Ortho: Boolean read FOrtho write SetOrtho;
    property Editable: Boolean read FEditable;
    property Viewport: TViewport2D read FVp;
    property OnCursor: TCursorEvent read FOnCursor write FOnCursor;
    property OnViewChange: TNotifyEvent read FOnViewChange write FOnViewChange;
    property OnSketchChanged: TNotifyEvent read FOnSketchChanged write FOnSketchChanged;
    property OnSelectionChanged: TNotifyEvent read FOnSelectionChanged write FOnSelectionChanged;
    property OnHint: TStringEvent read FOnHint write FOnHint;
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
  ColSelected   = $30B0FF;   // bright orange outline
  ColPreview    = $60E0A0;   // green-ish
  ColSnap       = $50E0FF;
  ColHandle     = $FFFFFF;

  SnapPixels   = 10;
  HandlePixels = 8;
  HitPixels    = 6;

constructor TSectionView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  FShowGrid := True;
  FShowPrincipal := True;
  FShowBBox := False;
  FShowCentroid := True;
  FSnapObjects := True;
  FSnapGrid := False;
  FOrtho := False;
  FLengthUnit := 'mm';
  FSel := -1;
  FTool := etSelect;
  FDrag := dmNone;
  FSnap.Kind := snNone;
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

function TSectionView.PixelsToWorld(Pixels: Double): Double;
begin
  Result := Pixels / Max(FVp.Scale, 1.0E-12);
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

procedure TSectionView.SetOrtho(V: Boolean);
begin
  FOrtho := V;
  Invalidate;
end;

procedure TSectionView.SetTool(V: TEditTool);
begin
  if (V <> etSelect) and not FEditable then V := etSelect;
  FTool := V;
  SetLength(FPts, 0);
  FDrag := dmNone;
  if V <> etSelect then SetSelection(-1);
  UpdateHint;
  Invalidate;
end;

procedure TSectionView.SetDoc(ADoc: TSketchDoc);
begin
  FDoc := ADoc;
  FEditable := ADoc <> nil;
  FFaces := nil;
  FMessage := '';
  SetLength(FPts, 0);
  SetSelection(-1);
  if (FDoc <> nil) and (FDoc.Sketch.LengthUnit <> '') then FLengthUnit := FDoc.Sketch.LengthUnit;
  UpdateHint;
  Invalidate;
end;

procedure TSectionView.SetReadOnlyFaces(const AFaces: TSectionFaceArray);
begin
  FDoc := nil;
  FEditable := False;
  FFaces := AFaces;
  FMessage := '';
  FTool := etSelect;
  SetLength(FPts, 0);
  SetSelection(-1);
  UpdateHint;
  Invalidate;
end;

procedure TSectionView.SetMessage(const AMessage: string);
begin
  FFaces := nil;
  FMessage := AMessage;
  FHasProps := False;
  Invalidate;
end;

procedure TSectionView.SetProps(const AProps: TSectionProperties; AHas: Boolean);
begin
  FProps := AProps;
  FHasProps := AHas;
  if AProps.LengthUnit <> '' then FLengthUnit := AProps.LengthUnit;
  Invalidate;
end;

procedure TSectionView.SketchReplaced;
begin
  SetLength(FPts, 0);
  if FDoc <> nil then
    if FSel > High(FDoc.Sketch.Profiles) then SetSelection(-1);
  if (FDoc <> nil) and (FDoc.Sketch.LengthUnit <> '') then FLengthUnit := FDoc.Sketch.LengthUnit;
  Invalidate;
end;

procedure TSectionView.FitView;
var
  B: TSketchBox;
  XMin, XMax, YMin, YMax: Double;
  Any: Boolean;
  F, K: Integer;
  P: TPoint2D;
begin
  FVp.Resize(Max(ClientWidth, 1), Max(ClientHeight, 1));
  Any := False;
  XMin := 0; XMax := 0; YMin := 0; YMax := 0;
  if FDoc <> nil then
  begin
    B := SketchBounds(FDoc.Sketch);
    if B.Valid then
    begin
      Any := True;
      XMin := B.XMin; XMax := B.XMax; YMin := B.YMin; YMax := B.YMax;
    end;
  end
  else
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
          XMin := Min(XMin, P.X); XMax := Max(XMax, P.X);
          YMin := Min(YMin, P.Y); YMax := Max(YMax, P.Y);
        end;
      end;
  if Any then
    FVp.Fit(XMin, XMax, YMin, YMax, 0.12)
  else
  begin
    FVp.Init(Max(ClientWidth, 1), Max(ClientHeight, 1));
    FVp.Scale := 2.0;
  end;
  Invalidate;
  if Assigned(FOnViewChange) then FOnViewChange(Self);
end;

procedure TSectionView.Resize;
begin
  inherited Resize;
  FVp.Resize(Max(ClientWidth, 1), Max(ClientHeight, 1));
end;

// ---------------------------------------------------------------- painting

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

  Canvas.Pen.Color := ColAxis;
  Canvas.Line(PX(0), 0, PX(0), ClientHeight);
  Canvas.Line(0, PY(0), ClientWidth, PY(0));
end;

procedure TSectionView.DrawSketch;
var
  I, K, N: Integer;
  Flat: TPoint2DArray;
  Pts: array of TPoint;
  Pass: Integer;
  Sk: TSketch;

  procedure ToScreen(const P: TSketchProfile);
  var
    Q: Integer;
  begin
    ProfileFlatten(P, Flat, 0.1);
    N := Length(Flat);
    SetLength(Pts, N);
    for Q := 0 to N - 1 do
    begin
      Pts[Q].X := PX(Flat[Q].X);
      Pts[Q].Y := PY(Flat[Q].Y);
    end;
  end;

begin
  Sk := FDoc.Sketch;
  // solids first, then holes cut back to the background, then outlines
  for Pass := 0 to 1 do
    for I := 0 to High(Sk.Profiles) do
    begin
      if (Pass = 0) and Sk.Profiles[I].IsHole then Continue;
      if (Pass = 1) and not Sk.Profiles[I].IsHole then Continue;
      ToScreen(Sk.Profiles[I]);
      if N < 3 then Continue;
      Canvas.Brush.Style := bsSolid;
      if Pass = 0 then Canvas.Brush.Color := ColFill else Canvas.Brush.Color := ColBackground;
      Canvas.Pen.Color := ColOutline;
      Canvas.Pen.Width := 1;
      Canvas.Polygon(Pts);
    end;
  Canvas.Brush.Style := bsClear;

  // the selected profile on top, with its vertex handles
  if (FSel >= 0) and (FSel <= High(Sk.Profiles)) then
  begin
    ToScreen(Sk.Profiles[FSel]);
    Canvas.Pen.Color := ColSelected;
    Canvas.Pen.Width := 2;
    if N >= 3 then Canvas.Polygon(Pts);
    Canvas.Pen.Width := 1;
    if Sk.Profiles[FSel].Kind = pkChain then
      for K := 0 to High(Sk.Profiles[FSel].Segs) do
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := ColHandle;
        Canvas.Pen.Color := ColSelected;
        Canvas.Rectangle(PX(Sk.Profiles[FSel].Segs[K].P0.X) - 3, PY(Sk.Profiles[FSel].Segs[K].P0.Y) - 3,
                         PX(Sk.Profiles[FSel].Segs[K].P0.X) + 4, PY(Sk.Profiles[FSel].Segs[K].P0.Y) + 4);
      end;
    Canvas.Brush.Style := bsClear;
  end;
end;

procedure TSectionView.DrawFacesReadOnly;
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

procedure TSectionView.DrawPreview;
var
  I: Integer;
  R: Double;
  Cur: TPoint2D;
begin
  if (FTool = etSelect) or (Length(FPts) = 0) then Exit;
  Cur.X := FSnap.X;
  Cur.Y := FSnap.Y;
  Canvas.Pen.Color := ColPreview;
  Canvas.Pen.Style := psDash;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  case FTool of
    etRect:
      Canvas.Rectangle(PX(FPts[0].X), PY(FPts[0].Y), PX(Cur.X), PY(Cur.Y));
    etCircle:
      begin
        R := Sqrt(Sqr(Cur.X - FPts[0].X) + Sqr(Cur.Y - FPts[0].Y));
        Canvas.Ellipse(PX(FPts[0].X - R), PY(FPts[0].Y + R), PX(FPts[0].X + R), PY(FPts[0].Y - R));
        Canvas.Line(PX(FPts[0].X), PY(FPts[0].Y), PX(Cur.X), PY(Cur.Y));
      end;
    etPolygon:
      begin
        for I := 0 to High(FPts) - 1 do
          Canvas.Line(PX(FPts[I].X), PY(FPts[I].Y), PX(FPts[I + 1].X), PY(FPts[I + 1].Y));
        Canvas.Line(PX(FPts[High(FPts)].X), PY(FPts[High(FPts)].Y), PX(Cur.X), PY(Cur.Y));
        if Length(FPts) >= 3 then
          Canvas.Line(PX(Cur.X), PY(Cur.Y), PX(FPts[0].X), PY(FPts[0].Y));
      end;
  end;
  Canvas.Pen.Style := psSolid;
  // placed points
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ColPreview;
  for I := 0 to High(FPts) do
    Canvas.Rectangle(PX(FPts[I].X) - 3, PY(FPts[I].Y) - 3, PX(FPts[I].X) + 4, PY(FPts[I].Y) + 4);
  Canvas.Brush.Style := bsClear;
end;

procedure TSectionView.DrawOverlays;
var
  CX, CY, Th, DX, DY, Len: Double;
  B: TSketchBox;
  R: Integer;
begin
  if FShowBBox and (FDoc <> nil) then
  begin
    B := SketchBounds(FDoc.Sketch);
    if B.Valid then
    begin
      Canvas.Pen.Color := ColBBox;
      Canvas.Pen.Style := psDash;
      Canvas.Brush.Style := bsClear;
      Canvas.Rectangle(PX(B.XMin), PY(B.YMax), PX(B.XMax), PY(B.YMin));
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

procedure TSectionView.DrawSnapMarker;
var
  X, Y: Integer;
begin
  if FSnap.Kind = snNone then Exit;
  X := PX(FSnap.X);
  Y := PY(FSnap.Y);
  Canvas.Pen.Color := ColSnap;
  Canvas.Pen.Width := 2;
  Canvas.Brush.Style := bsClear;
  case FSnap.Kind of
    snVertex:   Canvas.Rectangle(X - 6, Y - 6, X + 7, Y + 7);
    snMidpoint: Canvas.Polygon([Point(X, Y - 7), Point(X + 7, Y + 6), Point(X - 7, Y + 6)]);
    snCenter, snQuadrant: Canvas.Ellipse(X - 6, Y - 6, X + 7, Y + 7);
    snGrid:     begin Canvas.Line(X - 6, Y, X + 7, Y); Canvas.Line(X, Y - 6, X, Y + 7); end;
  end;
  Canvas.Pen.Width := 1;
  if FSnap.Kind <> snGrid then
  begin
    Canvas.Font.Color := ColSnap;
    Canvas.TextOut(X + 10, Y - 20, SnapKindName(FSnap.Kind));
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
  if FDoc <> nil then DrawSketch else DrawFacesReadOnly;
  DrawOverlays;
  DrawPreview;
  DrawSnapMarker;
  if FMessage <> '' then
  begin
    Canvas.Font.Color := ColError;
    DrawCentred(FMessage, -8);
  end
  else if (FDoc <> nil) and (Length(FDoc.Sketch.Profiles) = 0) and (Length(FPts) = 0) then
  begin
    Canvas.Font.Color := ColText;
    DrawCentred('Empty. Draw a shape (Rectangle, Polygon, Circle) or pick one from the Shapes menu.', -8);
  end;
end;

// ---------------------------------------------------------------- snapping and picking

function TSectionView.SnapWorld(WX, WY: Double; ExProfile, ExVertex: Integer): TSnapResult;
var
  Sk: TSketch;
begin
  if FDoc <> nil then Sk := FDoc.Sketch else SketchInit(Sk, '', 'mm');
  Result := SnapPoint(Sk, WX, WY, PixelsToWorld(SnapPixels), FVp.GridStep(48),
    FSnapObjects, FSnapGrid, ExProfile, ExVertex);
end;

function TSectionView.Anchor(out A: TPoint2D): Boolean;
begin
  Result := (FTool <> etSelect) and (Length(FPts) > 0);
  if Result then A := FPts[High(FPts)];
end;

function TSectionView.HitProfile(WX, WY: Double): Integer;
var
  I: Integer;
  Tol, D, BestD, A, BestA: Double;
begin
  Result := -1;
  if FDoc = nil then Exit;
  Tol := PixelsToWorld(HitPixels);
  BestD := 1.0E300;
  for I := 0 to High(FDoc.Sketch.Profiles) do
  begin
    D := ProfileEdgeDistance(FDoc.Sketch.Profiles[I], WX, WY);
    if (D <= Tol) and (D < BestD) then
    begin
      BestD := D;
      Result := I;
    end;
  end;
  if Result >= 0 then Exit;
  BestA := 1.0E300;
  for I := 0 to High(FDoc.Sketch.Profiles) do
    if ProfileContains(FDoc.Sketch.Profiles[I], WX, WY) then
    begin
      A := ProfileArea(FDoc.Sketch.Profiles[I]);
      if A < BestA then
      begin
        BestA := A;
        Result := I;
      end;
    end;
end;

function TSectionView.HitVertex(WX, WY: Double): Integer;
var
  K: Integer;
  Tol: Double;
begin
  Result := -1;
  if (FDoc = nil) or (FSel < 0) or (FSel > High(FDoc.Sketch.Profiles)) then Exit;
  if FDoc.Sketch.Profiles[FSel].Kind <> pkChain then Exit;
  Tol := PixelsToWorld(HandlePixels);
  for K := 0 to High(FDoc.Sketch.Profiles[FSel].Segs) do
    if Sqrt(Sqr(FDoc.Sketch.Profiles[FSel].Segs[K].P0.X - WX) +
            Sqr(FDoc.Sketch.Profiles[FSel].Segs[K].P0.Y - WY)) <= Tol then
      Exit(K);
end;

procedure TSectionView.Changed;
begin
  Invalidate;
  if Assigned(FOnSketchChanged) then FOnSketchChanged(Self);
end;

procedure TSectionView.SetSelection(I: Integer);
begin
  if FSel = I then Exit;
  FSel := I;
  Invalidate;
  if Assigned(FOnSelectionChanged) then FOnSelectionChanged(Self);
end;

procedure TSectionView.SelectProfile(I: Integer);
begin
  if (FDoc <> nil) and ((I < 0) or (I > High(FDoc.Sketch.Profiles))) then I := -1;
  SetSelection(I);
end;

procedure TSectionView.UpdateHint;
var
  S: string;
begin
  if not FEditable then
    S := 'Read-only: this file cannot be edited here.'
  else
    case FTool of
      etSelect:
        if FSel >= 0 then
          S := 'Drag to move, drag a square handle to move a corner, H toggles hole, Del deletes. Esc deselects.'
        else
          S := 'Click a shape to select it. Wheel zooms, right/middle drag pans.';
      etRect:
        if Length(FPts) = 0 then S := 'Rectangle: click the first corner (Esc cancels)'
        else S := 'Rectangle: click the opposite corner';
      etPolygon:
        if Length(FPts) = 0 then S := 'Polygon: click the first corner (Esc cancels)'
        else if Length(FPts) < 3 then S := 'Polygon: click the next corner (Backspace undoes a point)'
        else S := 'Polygon: next corner, or click the first point / press Enter to close';
      etCircle:
        if Length(FPts) = 0 then S := 'Circle: click the centre (Esc cancels)'
        else S := 'Circle: click a point on the circle';
    end;
  if Assigned(FOnHint) then FOnHint(Self, S);
end;

// ---------------------------------------------------------------- committing shapes

procedure TSectionView.AddProfileUndoable(const AName: string; const P: TSketchProfile);
var
  Hole: Boolean;
  Q: TSketchProfile;
  IP: TPoint2D;
begin
  if FDoc = nil then Exit;
  Q := P;
  IP := ProfileInteriorPoint(Q);
  Hole := DefaultHoleAt(FDoc.Sketch, IP.X, IP.Y);
  Q.IsHole := Hole;
  FDoc.Checkpoint(AName);
  SetSelection(SkAddProfile(FDoc.Sketch, Q));
  Changed;
end;

procedure TSectionView.CommitRect(const A, B: TPoint2D);
begin
  if (Abs(A.X - B.X) < 1.0E-9) or (Abs(A.Y - B.Y) < 1.0E-9) then Exit;
  AddProfileUndoable('Add rectangle', MakeRectProfile(A.X, A.Y, B.X, B.Y, False));
end;

procedure TSectionView.CommitCircle(const C, R: TPoint2D);
var
  Rad: Double;
begin
  Rad := Sqrt(Sqr(R.X - C.X) + Sqr(R.Y - C.Y));
  if Rad < 1.0E-9 then Exit;
  AddProfileUndoable('Add circle', MakeCircleProfile(C.X, C.Y, Rad, False));
end;

procedure TSectionView.CommitPolygon;
var
  P: TSketchProfile;
begin
  if Length(FPts) < 3 then Exit;
  P := MakePolygonProfile(FPts, False);
  if ProfileArea(P) < 1.0E-12 then Exit;
  AddProfileUndoable('Add polygon', P);
end;

// ---------------------------------------------------------------- tool actions

procedure TSectionView.MoveCursorTo(WX, WY: Double);
var
  A: TPoint2D;
  Raw: TPoint2D;
begin
  FCursorW.X := WX;
  FCursorW.Y := WY;
  Raw := FCursorW;
  if FOrtho and Anchor(A) then
  begin
    Raw := OrthoPoint(A, WX, WY);
    FSnap.Kind := snNone;
    if FSnapGrid then
    begin
      // grid-snap only along the free direction so the line stays orthogonal
      if Raw.Y = A.Y then Raw.X := Round(Raw.X / FVp.GridStep(48)) * FVp.GridStep(48)
      else Raw.Y := Round(Raw.Y / FVp.GridStep(48)) * FVp.GridStep(48);
      FSnap.Kind := snGrid;
    end;
    FSnap.X := Raw.X;
    FSnap.Y := Raw.Y;
  end
  else if FDrag = dmMove then
    FSnap := SnapWorld(WX, WY, FDragProfile, -1)
  else if FDrag = dmVertex then
    FSnap := SnapWorld(WX, WY, FDragProfile, FDragVertex)
  else
    FSnap := SnapWorld(WX, WY, -1, -1);
  if FSnap.Kind = snNone then
  begin
    FSnap.X := Raw.X;
    FSnap.Y := Raw.Y;
  end;
  if Assigned(FOnCursor) then FOnCursor(Self, FSnap.X, FSnap.Y);
  Invalidate;
end;

procedure TSectionView.BeginDragChange(const AName: string);
begin
  if not FDragChanged then
  begin
    FDoc.Checkpoint(AName);
    FDragChanged := True;
  end;
end;

procedure TSectionView.ClickAt(WX, WY: Double);
var
  P: TPoint2D;
  Tol: Double;
  Hit: Integer;
begin
  if FDoc = nil then Exit;
  MoveCursorTo(WX, WY);
  P.X := FSnap.X;
  P.Y := FSnap.Y;
  case FTool of
    etSelect:
      begin
        Hit := HitProfile(WX, WY);
        SetSelection(Hit);
      end;
    etRect:
      if Length(FPts) = 0 then
      begin
        SetLength(FPts, 1);
        FPts[0] := P;
      end
      else
      begin
        CommitRect(FPts[0], P);
        SetLength(FPts, 0);
      end;
    etCircle:
      if Length(FPts) = 0 then
      begin
        SetLength(FPts, 1);
        FPts[0] := P;
      end
      else
      begin
        CommitCircle(FPts[0], P);
        SetLength(FPts, 0);
      end;
    etPolygon:
      begin
        Tol := PixelsToWorld(SnapPixels);
        if (Length(FPts) >= 3) and (Sqrt(Sqr(P.X - FPts[0].X) + Sqr(P.Y - FPts[0].Y)) <= Tol) then
        begin
          CommitPolygon;
          SetLength(FPts, 0);
        end
        else if (Length(FPts) = 0) or
                (Sqrt(Sqr(P.X - FPts[High(FPts)].X) + Sqr(P.Y - FPts[High(FPts)].Y)) > 1.0E-9) then
        begin
          SetLength(FPts, Length(FPts) + 1);
          FPts[High(FPts)] := P;
        end;
      end;
  end;
  UpdateHint;
  Invalidate;
end;

procedure TSectionView.FinishPolygon;
begin
  if (FTool = etPolygon) and (Length(FPts) >= 3) then
  begin
    CommitPolygon;
    SetLength(FPts, 0);
    UpdateHint;
    Invalidate;
  end;
end;

procedure TSectionView.UndoLastPoint;
begin
  if Length(FPts) > 0 then
  begin
    SetLength(FPts, Length(FPts) - 1);
    UpdateHint;
    Invalidate;
  end;
end;

procedure TSectionView.CancelTool;
begin
  if Length(FPts) > 0 then
  begin
    SetLength(FPts, 0);
    UpdateHint;
    Invalidate;
  end
  else if FTool <> etSelect then
    SetTool(etSelect)
  else
    SetSelection(-1);
end;

procedure TSectionView.DeleteSelected;
begin
  if (FDoc = nil) or (FSel < 0) or (FSel > High(FDoc.Sketch.Profiles)) then Exit;
  FDoc.Checkpoint('Delete shape');
  SkDeleteProfile(FDoc.Sketch, FSel);
  SetSelection(-1);
  Changed;
  UpdateHint;
end;

procedure TSectionView.ToggleHoleSelected;
begin
  if (FDoc = nil) or (FSel < 0) or (FSel > High(FDoc.Sketch.Profiles)) then Exit;
  FDoc.Checkpoint('Toggle hole');
  SkSetHole(FDoc.Sketch, FSel, not FDoc.Sketch.Profiles[FSel].IsHole);
  Changed;
end;

// ---------------------------------------------------------------- mouse

procedure TSectionView.ScriptDrag(X0, Y0, X1, Y1: Double);
var
  SX0, SY0, SX1, SY1: Double;
  I, Steps: Integer;
begin
  FVp.WorldToScreen(X0, Y0, SX0, SY0);
  FVp.WorldToScreen(X1, Y1, SX1, SY1);
  MouseDown(mbLeft, [ssLeft], Round(SX0), Round(SY0));
  Steps := 8;
  for I := 1 to Steps do
    MouseMove([ssLeft], Round(SX0 + (SX1 - SX0) * I / Steps), Round(SY0 + (SY1 - SY0) * I / Steps));
  MouseUp(mbLeft, [], Round(SX1), Round(SY1));
end;

procedure TSectionView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  WX, WY: Double;
  V: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button in [mbMiddle, mbRight] then
  begin
    FDrag := dmPan;
    FDragPX := X;
    FDragPY := Y;
    Cursor := crSizeAll;
    Exit;
  end;
  if Button <> mbLeft then Exit;
  FVp.ScreenToWorld(X, Y, WX, WY);

  if not FEditable then
  begin
    FDrag := dmPan;     // read-only files can still be panned with the left button
    FDragPX := X;
    FDragPY := Y;
    Exit;
  end;

  if FTool = etSelect then
  begin
    V := HitVertex(WX, WY);
    if V >= 0 then
    begin
      FDrag := dmVertex;
      FDragProfile := FSel;
      FDragVertex := V;
      FDragChanged := False;
      Exit;
    end;
    ClickAt(WX, WY);
    if FSel >= 0 then
    begin
      FDrag := dmMove;
      FDragProfile := FSel;
      FDragChanged := False;
      FDragLast.X := FSnap.X;
      FDragLast.Y := FSnap.Y;
    end;
  end
  else
    ClickAt(WX, WY);
end;

procedure TSectionView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  WX, WY: Double;
begin
  inherited MouseMove(Shift, X, Y);
  if FDrag = dmPan then
  begin
    FVp.Pan(X - FDragPX, Y - FDragPY);
    FDragPX := X;
    FDragPY := Y;
    Invalidate;
    if Assigned(FOnViewChange) then FOnViewChange(Self);
    Exit;
  end;
  FVp.ScreenToWorld(X, Y, WX, WY);
  MoveCursorTo(WX, WY);
  if FDoc = nil then Exit;
  case FDrag of
    dmMove:
      begin
        if (Abs(FSnap.X - FDragLast.X) > 0) or (Abs(FSnap.Y - FDragLast.Y) > 0) then
        begin
          BeginDragChange('Move shape');
          SkMoveProfile(FDoc.Sketch, FDragProfile, FSnap.X - FDragLast.X, FSnap.Y - FDragLast.Y);
          FDragLast.X := FSnap.X;
          FDragLast.Y := FSnap.Y;
          Changed;
        end;
      end;
    dmVertex:
      begin
        BeginDragChange('Move corner');
        SkMoveVertex(FDoc.Sketch, FDragProfile, FDragVertex, FSnap.X, FSnap.Y);
        Changed;
      end;
  end;
end;

procedure TSectionView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDrag := dmNone;
  Cursor := crDefault;
  Invalidate;
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
