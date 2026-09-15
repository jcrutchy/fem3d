unit FEMOpenGLView;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, OpenGLContext, GL,
  FEMTypes, FEMModel, FEMView, FEMSelection, FEMResultFields, FEMDisplayManager, FEMSectioning;

type
  TClipAxis = (caX, caY, caZ);

  { TOpenGLFEMRenderer }
  TOpenGLFEMRenderer = class
  private
    FControl: TOpenGLControl;
    FModel: TFEMModel;
    FView: TFEMViewport;
    FFields: TResultFieldCollection;
    FDisplay: TDisplayManager;
    FClipEnabled: Boolean;
    FClipAxis: TClipAxis;
    FClipFraction: Double;
    FShowAxes: Boolean;
    FShowGrid: Boolean;
    FShowNodes: Boolean;
    FShowElementEdges: Boolean;
    FShowSolidMembers: Boolean;
    FShowClipPlane: Boolean;
    FShowLoads: Boolean;
    FShowRestraints: Boolean;
    FShowLocalAxes: Boolean;
    FShowCoordinateSystems: Boolean;
    FEditPreviewActive: Boolean; FEditPreviewNodeID: Integer; FEditPreviewPoint: TVec3;
    FEditPreviewBeamActive: Boolean; FEditPreviewBeamStart,FEditPreviewBeamEnd: TVec3;
    FSelectionBoxActive:Boolean; FSelectionBoxX1,FSelectionBoxY1,FSelectionBoxX2,FSelectionBoxY2:Integer;
    FClipState: TClipState;
    function NodePosition(NodeIndex: Integer): TVec3;
    function FieldValue(Field: TResultField; EntityID: Integer): Double;
    function ContourT(V: Double): Double;
    procedure SetMaterialColor(T: Double);
    procedure DrawGrid;
    procedure DrawAxes;
    procedure DrawClipPlane;
    procedure GetBounds(out MinP,MaxP:TVec3);
    procedure SetupProjection(W,H: Integer);
    procedure SetupCamera;
    procedure ApplyClipPlane;
    procedure SetPrimaryClipPlane;
    function GlyphScale: Double;
    procedure DrawArrow(const Origin,Direction: TVec3; Length,HeadSize: Double);
    procedure DrawLoads;
    procedure DrawRestraints;
    procedure DrawLocalAxes;
    procedure DrawCoordinateSystems;
    procedure DrawSelectionBox;
    procedure DrawBeamBody(const P1,P2: TVec3; Radius: Double; Selected,Hover: Boolean);
    function BeamDisplayRadius(const E: TElementRecord; const P1,P2: TVec3): Double;
  public
    constructor Create(AControl: TOpenGLControl; AModel: TFEMModel; AView: TFEMViewport);
    destructor Destroy; override;
    procedure SetDisplayManager(ADisplay:TDisplayManager);
    procedure Paint;
    procedure SetResultFields(AFields: TResultFieldCollection);
    procedure SetClipEnabled(Value: Boolean);
    procedure SetClipAxis(Axis: TClipAxis);
    procedure SetClipFraction(Value: Double);
    procedure SetClipReverse(Value: Boolean);
    procedure SetShowAxes(Value: Boolean);
    procedure SetShowGrid(Value: Boolean);
    procedure SetShowNodes(Value: Boolean);
    procedure SetShowElementEdges(Value: Boolean);
    procedure SetShowSolidMembers(Value: Boolean);
    procedure SetShowClipPlane(Value: Boolean);
    procedure SetShowLoads(Value: Boolean);
    procedure SetShowRestraints(Value: Boolean);
    procedure SetShowLocalAxes(Value: Boolean);
    procedure SetShowCoordinateSystems(Value: Boolean);
    procedure SetEditPreviewNode(Active:Boolean; NodeID:Integer; const P:TVec3);
    procedure SetEditPreviewBeam(Active:Boolean; const P1,P2:TVec3);
    procedure SetSelectionBox(AActive: Boolean; X1,Y1,X2,Y2: Integer);
    property ClipEnabled: Boolean read FClipEnabled;
    property ClipAxis: TClipAxis read FClipAxis;
    property ClipFraction: Double read FClipFraction;
  end;

implementation

constructor TOpenGLFEMRenderer.Create(AControl: TOpenGLControl; AModel: TFEMModel; AView: TFEMViewport);
begin
  inherited Create;
  FControl:=AControl; FModel:=AModel; FView:=AView; FFields:=nil; FDisplay:=nil;
  FClipEnabled:=False; FClipAxis:=caX; FClipFraction:=0.5;
  FShowAxes:=True; FShowGrid:=True; FShowNodes:=True; FShowElementEdges:=True; FShowSolidMembers:=True; FShowClipPlane:=True;
  FShowLoads:=True; FShowRestraints:=True; FShowLocalAxes:=False; FShowCoordinateSystems:=True;
  FEditPreviewActive:=False; FEditPreviewNodeID:=0; FEditPreviewPoint:=Vec3(0,0,0);
  FEditPreviewBeamActive:=False; FEditPreviewBeamStart:=Vec3(0,0,0); FEditPreviewBeamEnd:=Vec3(0,0,0);
  FSelectionBoxActive:=False; FSelectionBoxX1:=0; FSelectionBoxY1:=0; FSelectionBoxX2:=0; FSelectionBoxY2:=0;
  FClipState:=TClipState.Create;
end;

destructor TOpenGLFEMRenderer.Destroy;
begin
  FClipState.Free;
  inherited Destroy;
end;

function TOpenGLFEMRenderer.NodePosition(NodeIndex: Integer): TVec3;
var U0,U1,U2: Double; F: TResultField;
begin
  Result:=FModel.Nodes[NodeIndex].Position;
  if not FView.ShowDeformed then Exit;
  if FFields=nil then Exit;
  F:=FFields.Find('U0'); if F<>nil then U0:=FieldValue(F,FModel.Nodes[NodeIndex].ID) else U0:=0;
  F:=FFields.Find('U1'); if F<>nil then U1:=FieldValue(F,FModel.Nodes[NodeIndex].ID) else U1:=0;
  F:=FFields.Find('U2'); if F<>nil then U2:=FieldValue(F,FModel.Nodes[NodeIndex].ID) else U2:=0;
  Result.X:=Result.X+U0*FView.DeformationScale;
  Result.Y:=Result.Y+U1*FView.DeformationScale;
  Result.Z:=Result.Z+U2*FView.DeformationScale;
end;

function TOpenGLFEMRenderer.FieldValue(Field: TResultField; EntityID: Integer): Double;
begin
  if Field=nil then Result:=0 else Result:=Field.ValueForEntity(EntityID);
end;

function TOpenGLFEMRenderer.ContourT(V: Double): Double;
begin
  Result:=FView.ContourNormalized(V);
end;

procedure TOpenGLFEMRenderer.SetMaterialColor(T: Double);
var R,G,B: Double;
begin
  T:=Max(0,Min(1,T));
  if T<0.25 then begin R:=0; G:=T/0.25; B:=1; end
  else if T<0.5 then begin R:=0; G:=1; B:=1-(T-0.25)/0.25; end
  else if T<0.75 then begin R:=(T-0.5)/0.25; G:=1; B:=0; end
  else begin R:=1; G:=1-(T-0.75)/0.25; B:=0; end;
  glColor3f(R,G,B);
end;

procedure TOpenGLFEMRenderer.GetBounds(out MinP,MaxP:TVec3);
var I:Integer; P:TVec3;
begin
  if Length(FModel.Nodes)=0 then begin MinP:=Vec3(0,0,0); MaxP:=Vec3(1,1,1); Exit; end;
  MinP:=FModel.Nodes[0].Position; MaxP:=MinP;
  for I:=1 to High(FModel.Nodes) do begin P:=FModel.Nodes[I].Position; MinP.X:=Min(MinP.X,P.X); MinP.Y:=Min(MinP.Y,P.Y); MinP.Z:=Min(MinP.Z,P.Z); MaxP.X:=Max(MaxP.X,P.X); MaxP.Y:=Max(MaxP.Y,P.Y); MaxP.Z:=Max(MaxP.Z,P.Z); end;
end;

procedure TOpenGLFEMRenderer.SetupProjection(W,H: Integer);
var Aspect,NearZ,FarZ,Fov,TopV,RightV,HalfSize: Double;
begin
  if H<1 then H:=1;
  Aspect:=W/H; NearZ:=FView.Camera.NearClip; FarZ:=Max(NearZ*1000,FView.Camera.Distance*100);
  glMatrixMode(GL_PROJECTION); glLoadIdentity;
  if FView.Camera.Projection=vpOrthographic then begin
    HalfSize:=Max(FView.Camera.Distance*0.6,NearZ*10);
    glOrtho(-HalfSize*Aspect,HalfSize*Aspect,-HalfSize,HalfSize,-FarZ,FarZ);
  end else begin
    Fov:=FView.Camera.FOV*Pi/180; TopV:=Tan(Fov/2)*NearZ; RightV:=TopV*Aspect;
    glFrustum(-RightV,RightV,-TopV,TopV,NearZ,FarZ);
  end;
  glMatrixMode(GL_MODELVIEW);
end;

procedure TOpenGLFEMRenderer.SetupCamera;
begin
  glLoadIdentity;
  glTranslated(FView.Camera.PanX,FView.Camera.PanY,-FView.Camera.Distance);
  glRotated(-FView.Camera.Pitch*180/Pi,1,0,0);
  glRotated(-FView.Camera.Yaw*180/Pi,0,1,0);
  glTranslated(-FView.Camera.Target.X,-FView.Camera.Target.Y,-FView.Camera.Target.Z);
end;

procedure TOpenGLFEMRenderer.SetPrimaryClipPlane;
var P:TClipPlane; MinP,MaxP:TVec3; C:Double;
begin
  P:=FClipState.Plane(0); P.Enabled:=FClipEnabled; P.ShowPlane:=FShowClipPlane;
  GetBounds(MinP,MaxP);
  case FClipAxis of
    caX: begin P.NormalX:=1; P.NormalY:=0; P.NormalZ:=0; C:=MinP.X+(MaxP.X-MinP.X)*FClipFraction; end;
    caY: begin P.NormalX:=0; P.NormalY:=1; P.NormalZ:=0; C:=MinP.Y+(MaxP.Y-MinP.Y)*FClipFraction; end;
    else begin P.NormalX:=0; P.NormalY:=0; P.NormalZ:=1; C:=MinP.Z+(MaxP.Z-MinP.Z)*FClipFraction; end;
  end;
  P.Offset:=C; FClipState.SetPlane(0,P);
end;

procedure TOpenGLFEMRenderer.ApplyClipPlane;
var I:Integer; P:TClipPlane; Eq:array[0..3] of GLdouble;
begin
  SetPrimaryClipPlane;
  for I:=0 to 3 do begin
    P:=FClipState.Plane(I); glDisable(GL_CLIP_PLANE0+I);
    if P.Enabled then begin
      Eq[0]:=P.NormalX; Eq[1]:=P.NormalY; Eq[2]:=P.NormalZ; Eq[3]:=-P.Offset;
      if P.Reverse then begin Eq[0]:=-Eq[0]; Eq[1]:=-Eq[1]; Eq[2]:=-Eq[2]; Eq[3]:=-Eq[3]; end;
      glClipPlane(GL_CLIP_PLANE0+I,@Eq); glEnable(GL_CLIP_PLANE0+I);
    end;
  end;
end;

procedure TOpenGLFEMRenderer.DrawGrid;
var MinP,MaxP: TVec3; I: Integer; Step,X,Y: Double; Span: Double;
begin
  GetBounds(MinP,MaxP); Span:=Max(Max(MaxP.X-MinP.X,MaxP.Y-MinP.Y),MaxP.Z-MinP.Z);
  if Span<1e-9 then Span:=1; Step:=Span/10;
  glDisable(GL_LIGHTING); glColor3f(0.16,0.18,0.22); glLineWidth(1);
  glBegin(GL_LINES);
  for I:=-10 to 10 do begin
    X:=FView.Camera.Target.X+I*Step; glVertex3d(X,MinP.Y,FView.Camera.Target.Z-10*Step); glVertex3d(X,MinP.Y,FView.Camera.Target.Z+10*Step);
    Y:=FView.Camera.Target.Z+I*Step; glVertex3d(FView.Camera.Target.X-10*Step,MinP.Y,Y); glVertex3d(FView.Camera.Target.X+10*Step,MinP.Y,Y);
  end;
  glEnd;
end;

procedure TOpenGLFEMRenderer.DrawAxes;
var L: Double; P: TVec3;
begin
  L:=Max(1,FView.Camera.Distance*0.15); P:=FView.Camera.Target;
  glDisable(GL_LIGHTING); glLineWidth(3); glBegin(GL_LINES);
  glColor3f(1,0.2,0.2); glVertex3d(P.X,P.Y,P.Z); glVertex3d(P.X+L,P.Y,P.Z);
  glColor3f(0.2,1,0.2); glVertex3d(P.X,P.Y,P.Z); glVertex3d(P.X,P.Y+L,P.Z);
  glColor3f(0.2,0.5,1); glVertex3d(P.X,P.Y,P.Z); glVertex3d(P.X,P.Y,P.Z+L); glEnd;
end;

procedure TOpenGLFEMRenderer.DrawClipPlane;
var MinP,MaxP:TVec3; C:Double; P:TClipPlane;
begin
  P:=FClipState.Plane(0); if (not P.Enabled) or (not P.ShowPlane) then Exit;
  GetBounds(MinP,MaxP); C:=P.Offset; glDisable(GL_LIGHTING); glDepthMask(GL_FALSE);
  glBegin(GL_QUADS); glColor4f(0.2,0.65,1,0.10);
  case FClipAxis of
    caX: begin glVertex3d(C,MinP.Y,MinP.Z); glVertex3d(C,MaxP.Y,MinP.Z); glVertex3d(C,MaxP.Y,MaxP.Z); glVertex3d(C,MinP.Y,MaxP.Z); end;
    caY: begin glVertex3d(MinP.X,C,MinP.Z); glVertex3d(MaxP.X,C,MinP.Z); glVertex3d(MaxP.X,C,MaxP.Z); glVertex3d(MinP.X,C,MaxP.Z); end;
    else begin glVertex3d(MinP.X,MinP.Y,C); glVertex3d(MaxP.X,MinP.Y,C); glVertex3d(MaxP.X,MaxP.Y,C); glVertex3d(MinP.X,MaxP.Y,C); end;
  end; glEnd; glDepthMask(GL_TRUE);
end;


function TOpenGLFEMRenderer.GlyphScale: Double;
begin
  Result:=Max(0.05,FView.Camera.Distance*0.035);
end;

procedure TOpenGLFEMRenderer.DrawArrow(const Origin,Direction: TVec3; Length,HeadSize: Double);
var D,U,V,P,Tip: TVec3;
begin
  D:=VUnit(Direction);
  if VNorm(D)<1e-12 then Exit;
  if Abs(D.Z)<0.9 then U:=VUnit(Vec3(-D.Y,D.X,0)) else U:=VUnit(Vec3(1,0,0));
  V:=VUnit(Vec3(D.Y*U.Z-D.Z*U.Y,D.Z*U.X-D.X*U.Z,D.X*U.Y-D.Y*U.X));
  Tip:=Vec3(Origin.X+D.X*Length,Origin.Y+D.Y*Length,Origin.Z+D.Z*Length);
  P:=Vec3(Tip.X-D.X*HeadSize,Tip.Y-D.Y*HeadSize,Tip.Z-D.Z*HeadSize);
  glBegin(GL_LINES); glVertex3d(Origin.X,Origin.Y,Origin.Z); glVertex3d(Tip.X,Tip.Y,Tip.Z); glEnd;
  glBegin(GL_TRIANGLES);
  glVertex3d(Tip.X,Tip.Y,Tip.Z); glVertex3d(P.X+U.X*HeadSize*0.45,P.Y+U.Y*HeadSize*0.45,P.Z+U.Z*HeadSize*0.45); glVertex3d(P.X+V.X*HeadSize*0.45,P.Y+V.Y*HeadSize*0.45,P.Z+V.Z*HeadSize*0.45);
  glVertex3d(Tip.X,Tip.Y,Tip.Z); glVertex3d(P.X+V.X*HeadSize*0.45,P.Y+V.Y*HeadSize*0.45,P.Z+V.Z*HeadSize*0.45); glVertex3d(P.X-U.X*HeadSize*0.45,P.Y-U.Y*HeadSize*0.45,P.Z-U.Z*HeadSize*0.45);
  glEnd;
end;

procedure TOpenGLFEMRenderer.DrawLoads;
var I,J:Integer; N:Integer; V:TDofVector; D:TVec3; Mag,Scale:Double; P:TVec3; LC:Integer;
begin
  if Length(FModel.Loads)=0 then Exit;
  Scale:=GlyphScale; glDisable(GL_LIGHTING); glLineWidth(2.5); glColor3f(1.0,0.65,0.10);
  for I:=0 to High(FModel.Loads) do begin
    N:=FModel.FindNode(FModel.Loads[I].NodeID); if N<0 then Continue;
    if (FDisplay<>nil) and (not FDisplay.IsNodeVisible(FModel,FModel.Nodes[N].ID)) then Continue;
    V:=FModel.Loads[I].Value; Mag:=Sqrt(Sqr(V[0])+Sqr(V[1])+Sqr(V[2]));
    if Mag>1e-12 then begin D:=Vec3(V[0]/Mag,V[1]/Mag,V[2]/Mag); P:=NodePosition(N); DrawArrow(P,D,Scale*2.2,Scale*0.55); end;
    if (Abs(V[3])+Abs(V[4])+Abs(V[5]))>1e-12 then begin
      P:=NodePosition(N); glBegin(GL_LINE_STRIP);
      glVertex3d(P.X+Scale*0.7,P.Y,P.Z); glVertex3d(P.X,P.Y+Scale*0.7,P.Z); glVertex3d(P.X-Scale*0.7,P.Y,P.Z); glVertex3d(P.X,P.Y-Scale*0.7,P.Z); glVertex3d(P.X+Scale*0.7,P.Y,P.Z); glEnd;
    end;
  end;
end;

procedure TOpenGLFEMRenderer.DrawRestraints;
var I,J:Integer; P,Q:TVec3; S:Double; R:TDofMask;
begin
  S:=GlyphScale*0.75; glDisable(GL_LIGHTING); glLineWidth(2); glColor3f(0.95,0.30,0.30);
  for I:=0 to High(FModel.Nodes) do begin
    if (FDisplay<>nil) and (not FDisplay.IsNodeVisible(FModel,FModel.Nodes[I].ID)) then Continue;
    R:=FModel.Nodes[I].Restraint; P:=NodePosition(I);
    for J:=0 to 2 do if R[J] then begin
      case J of 0: Q:=Vec3(P.X+S,P.Y,P.Z); 1: Q:=Vec3(P.X,P.Y+S,P.Z); else Q:=Vec3(P.X,P.Y,P.Z+S); end;
      glBegin(GL_LINES); glVertex3d(P.X,P.Y,P.Z); glVertex3d(Q.X,Q.Y,Q.Z); glEnd;
      glBegin(GL_LINE_STRIP); glVertex3d(Q.X-S*0.35,Q.Y-S*0.35,Q.Z); glVertex3d(Q.X+S*0.35,Q.Y-S*0.35,Q.Z); glVertex3d(Q.X+S*0.35,Q.Y+S*0.35,Q.Z); glVertex3d(Q.X-S*0.35,Q.Y+S*0.35,Q.Z); glVertex3d(Q.X-S*0.35,Q.Y-S*0.35,Q.Z); glEnd;
    end;
    for J:=3 to 5 do if R[J] then begin
      glBegin(GL_LINE_STRIP); glVertex3d(P.X-S*0.45,P.Y,P.Z); glVertex3d(P.X,P.Y+S*0.45,P.Z); glVertex3d(P.X+S*0.45,P.Y,P.Z); glVertex3d(P.X,P.Y-S*0.45,P.Z); glVertex3d(P.X-S*0.45,P.Y,P.Z); glEnd;
    end;
  end;
end;

procedure TOpenGLFEMRenderer.DrawLocalAxes;
var I,A,B:Integer; P,Q,D1,D2:TVec3; S:Double;
begin
  S:=GlyphScale*1.2; glDisable(GL_LIGHTING); glLineWidth(2);
  for I:=0 to High(FModel.Elements) do begin
    if (FDisplay<>nil) and (not FDisplay.IsElementVisible(FModel.Elements[I])) then Continue;
    if Length(FModel.Elements[I].NodeIDs)<2 then Continue;
    A:=FModel.FindNode(FModel.Elements[I].NodeIDs[0]); B:=FModel.FindNode(FModel.Elements[I].NodeIDs[1]); if (A<0) or (B<0) then Continue;
    P:=NodePosition(A); Q:=NodePosition(B); D1:=VUnit(Vec3(Q.X-P.X,Q.Y-P.Y,Q.Z-P.Z));
    if VNorm(D1)<1e-12 then Continue;
    if Abs(D1.Z)<0.9 then D2:=VUnit(Vec3(-D1.Y,D1.X,0)) else D2:=VUnit(Vec3(1,0,0));
    glColor3f(0.95,0.30,0.30); DrawArrow(P,D1,S,S*0.18);
    glColor3f(0.30,0.95,0.30); DrawArrow(P,D2,S,S*0.18);
    glColor3f(0.30,0.55,1.00); DrawArrow(P,VUnit(Vec3(D1.Y*D2.Z-D1.Z*D2.Y,D1.Z*D2.X-D1.X*D2.Z,D1.X*D2.Y-D1.Y*D2.X)),S,S*0.18);
  end;
end;

procedure TOpenGLFEMRenderer.DrawCoordinateSystems;
var I:Integer; C:TCoordinateSystem; S:Double; P:TVec3;
begin
  S:=GlyphScale*1.5; glDisable(GL_LIGHTING); glLineWidth(2);
  for I:=0 to High(FModel.CoordinateSystems) do begin C:=FModel.CoordinateSystems[I]; P:=C.Origin;
    glColor3f(1,0.3,0.3); DrawArrow(P,C.XAxis,S,S*0.18);
    glColor3f(0.3,1,0.3); DrawArrow(P,C.YAxis,S,S*0.18);
    glColor3f(0.3,0.55,1); DrawArrow(P,C.ZAxis,S,S*0.18);
  end;
end;


function TOpenGLFEMRenderer.BeamDisplayRadius(const E: TElementRecord; const P1,P2: TVec3): Double;
var SI: Integer; L,A,R,MinR,MaxR: Double;
begin
  L:=VNorm(VSub(P2,P1));
  if L<1e-12 then Exit(0);
  A:=0;
  SI:=FModel.FindSection(E.SectionID);
  if SI>=0 then A:=Abs(FModel.Sections[SI].Area);
  if A>1e-18 then R:=Sqrt(A/Pi) else R:=L*0.006;
  { The renderer intentionally uses an area-equivalent display radius. It is
    presentation geometry only; it is not a claim about the real section shape. }
  MinR:=L*0.003;
  MaxR:=L*0.05;
  Result:=Max(MinR,Min(MaxR,R));
end;

procedure TOpenGLFEMRenderer.DrawBeamBody(const P1,P2: TVec3; Radius: Double; Selected,Hover: Boolean);
const Segments=8;
var D,U,V,Q1,Q2: TVec3; I: Integer; A1,A2,C,S: Double;
begin
  D:=VUnit(VSub(P2,P1));
  if VNorm(D)<1e-12 then Exit;
  if Abs(D.Z)<0.9 then U:=VUnit(Vec3(-D.Y,D.X,0)) else U:=VUnit(Vec3(1,0,0));
  V:=VUnit(VCross(D,U));
  glDisable(GL_LIGHTING);
  glBegin(GL_QUADS);
  for I:=0 to Segments-1 do begin
    A1:=2*Pi*I/Segments; A2:=2*Pi*(I+1)/Segments;
    C:=Cos(A1); S:=Sin(A1);
    Q1:=Vec3(P1.X+Radius*(U.X*C+V.X*S),P1.Y+Radius*(U.Y*C+V.Y*S),P1.Z+Radius*(U.Z*C+V.Z*S));
    C:=Cos(A2); S:=Sin(A2);
    Q2:=Vec3(P1.X+Radius*(U.X*C+V.X*S),P1.Y+Radius*(U.Y*C+V.Y*S),P1.Z+Radius*(U.Z*C+V.Z*S));
    glVertex3d(Q1.X,Q1.Y,Q1.Z); glVertex3d(Q2.X,Q2.Y,Q2.Z);
    C:=Cos(A2); S:=Sin(A2);
    Q2:=Vec3(P2.X+Radius*(U.X*C+V.X*S),P2.Y+Radius*(U.Y*C+V.Y*S),P2.Z+Radius*(U.Z*C+V.Z*S));
    glVertex3d(Q2.X,Q2.Y,Q2.Z);
    C:=Cos(A1); S:=Sin(A1);
    Q1:=Vec3(P2.X+Radius*(U.X*C+V.X*S),P2.Y+Radius*(U.Y*C+V.Y*S),P2.Z+Radius*(U.Z*C+V.Z*S));
    glVertex3d(Q1.X,Q1.Y,Q1.Z);
  end;
  glEnd;

  { End caps make the member read as a real 3D body when viewed obliquely. }
  glBegin(GL_TRIANGLE_FAN);
  glVertex3d(P1.X,P1.Y,P1.Z);
  for I:=0 to Segments do begin
    A1:=2*Pi*(I mod Segments)/Segments; C:=Cos(A1); S:=Sin(A1);
    Q1:=Vec3(P1.X+Radius*(U.X*C+V.X*S),P1.Y+Radius*(U.Y*C+V.Y*S),P1.Z+Radius*(U.Z*C+V.Z*S));
    glVertex3d(Q1.X,Q1.Y,Q1.Z);
  end;
  glEnd;
  glBegin(GL_TRIANGLE_FAN);
  glVertex3d(P2.X,P2.Y,P2.Z);
  for I:=Segments downto 0 do begin
    A1:=2*Pi*(I mod Segments)/Segments; C:=Cos(A1); S:=Sin(A1);
    Q1:=Vec3(P2.X+Radius*(U.X*C+V.X*S),P2.Y+Radius*(U.Y*C+V.Y*S),P2.Z+Radius*(U.Z*C+V.Z*S));
    glVertex3d(Q1.X,Q1.Y,Q1.Z);
  end;
  glEnd;

  if FShowElementEdges or Selected or Hover then begin
    if Selected then begin glLineWidth(4); glColor3f(1,0.2,0.2); end
    else if Hover then begin glLineWidth(3); glColor3f(1,0.85,0.2); end
    else begin glLineWidth(1); glColor4f(0.08,0.10,0.13,0.85); end;
    glBegin(GL_LINES);
    for I:=0 to Segments-1 do begin
      A1:=2*Pi*I/Segments; C:=Cos(A1); S:=Sin(A1);
      Q1:=Vec3(P1.X+Radius*(U.X*C+V.X*S),P1.Y+Radius*(U.Y*C+V.Y*S),P1.Z+Radius*(U.Z*C+V.Z*S));
      Q2:=Vec3(P2.X+Radius*(U.X*C+V.X*S),P2.Y+Radius*(U.Y*C+V.Y*S),P2.Z+Radius*(U.Z*C+V.Z*S));
      glVertex3d(Q1.X,Q1.Y,Q1.Z); glVertex3d(Q2.X,Q2.Y,Q2.Z);
    end;
    glEnd;
  end;
  if Selected then begin
    glColor3f(1,0.2,0.2); glLineWidth(2);
    glBegin(GL_LINES); glVertex3d(P1.X,P1.Y,P1.Z); glVertex3d(P2.X,P2.Y,P2.Z); glEnd;
  end;
end;

procedure TOpenGLFEMRenderer.Paint;
var I,A,B: Integer; P1,P2: TVec3; V,V1,V2: Double; F:TResultField; Col: TSelectionSet;
begin
  if not FControl.MakeCurrent then Exit;
  glViewport(0,0,FControl.Width,FControl.Height);
  glClearColor(0.055,0.065,0.08,1); glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT);
  glEnable(GL_DEPTH_TEST); glDepthFunc(GL_LEQUAL); glEnable(GL_BLEND); glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);
  SetupProjection(FControl.Width,FControl.Height); SetupCamera; ApplyClipPlane;
  if FShowGrid then DrawGrid; if FShowAxes then DrawAxes;
  F:=FView.ActiveField;
  glDisable(GL_LIGHTING); glLineWidth(2);
  for I:=0 to High(FModel.Elements) do if (FDisplay=nil) or FDisplay.IsElementVisible(FModel.Elements[I]) then if Length(FModel.Elements[I].NodeIDs)>=2 then begin
    A:=FModel.FindNode(FModel.Elements[I].NodeIDs[0]); B:=FModel.FindNode(FModel.Elements[I].NodeIDs[1]); if (A<0) or (B<0) then Continue;
    if F<>nil then begin
      if F.Location=rlElement then V:=FieldValue(F,FModel.Elements[I].ID) else begin V1:=FieldValue(F,FModel.Nodes[A].ID); V2:=FieldValue(F,FModel.Nodes[B].ID); V:=(V1+V2)*0.5; end;
      SetMaterialColor(ContourT(V));
    end else glColor3f(0.72,0.76,0.84);
    P1:=NodePosition(A); P2:=NodePosition(B);
    if FShowSolidMembers and SameText(FModel.Elements[I].Kind,'BEAM3D') then
      DrawBeamBody(P1,P2,BeamDisplayRadius(FModel.Elements[I],P1,P2),FView.Selection.ElementSelected(FModel.Elements[I].ID),FView.HoverElementID=FModel.Elements[I].ID)
    else begin
      if FView.Selection.ElementSelected(FModel.Elements[I].ID) then begin glLineWidth(5); glColor3f(1,0.2,0.2); end else if FView.HoverElementID=FModel.Elements[I].ID then begin glLineWidth(4); glColor3f(1,0.85,0.2); end else glLineWidth(2);
      glBegin(GL_LINES); glVertex3d(P1.X,P1.Y,P1.Z); glVertex3d(P2.X,P2.Y,P2.Z); glEnd;
    end;
  end;
  glDisable(GL_CLIP_PLANE0);
  if FView.ShowUndeformed then begin
    glColor4f(0.5,0.55,0.65,0.35); glLineWidth(1); glEnable(GL_LINE_STIPPLE); glLineStipple(1,$AAAA);
    for I:=0 to High(FModel.Elements) do if (FDisplay=nil) or FDisplay.IsElementVisible(FModel.Elements[I]) then if Length(FModel.Elements[I].NodeIDs)>=2 then begin A:=FModel.FindNode(FModel.Elements[I].NodeIDs[0]);B:=FModel.FindNode(FModel.Elements[I].NodeIDs[1]);if(A>=0)and(B>=0)then begin P1:=FModel.Nodes[A].Position;P2:=FModel.Nodes[B].Position;glBegin(GL_LINES);glVertex3d(P1.X,P1.Y,P1.Z);glVertex3d(P2.X,P2.Y,P2.Z);glEnd;end;end;
    glDisable(GL_LINE_STIPPLE);
  end;
  DrawClipPlane;
  if FShowCoordinateSystems then DrawCoordinateSystems;
  if FShowLocalAxes then DrawLocalAxes;
  if FShowLoads then DrawLoads;
  if FShowRestraints then DrawRestraints;
  if FShowNodes then begin glPointSize(6); glBegin(GL_POINTS); for I:=0 to High(FModel.Nodes) do begin if (FDisplay=nil) or FDisplay.IsNodeVisible(FModel,FModel.Nodes[I].ID) then begin if FView.Selection.NodeSelected(FModel.Nodes[I].ID) then glColor3f(1,0.2,0.2) else if FView.HoverNodeID=FModel.Nodes[I].ID then begin glColor3f(1,0.85,0.2); glPointSize(10); end else begin glColor3f(0.95,0.95,0.95); glPointSize(6); end; P1:=NodePosition(I); glVertex3d(P1.X,P1.Y,P1.Z); end; end; glEnd; end;
  if FEditPreviewBeamActive then begin
    { Beam creation preview is graphical only; no model state is changed. }
    glDisable(GL_DEPTH_TEST); glLineWidth(5); glColor3f(0.35,0.95,1.0);
    glBegin(GL_LINES);
    glVertex3d(FEditPreviewBeamStart.X,FEditPreviewBeamStart.Y,FEditPreviewBeamStart.Z);
    glVertex3d(FEditPreviewBeamEnd.X,FEditPreviewBeamEnd.Y,FEditPreviewBeamEnd.Z);
    glEnd;
    glPointSize(12); glColor3f(0.35,0.95,1.0);
    glBegin(GL_POINTS);
    glVertex3d(FEditPreviewBeamEnd.X,FEditPreviewBeamEnd.Y,FEditPreviewBeamEnd.Z);
    glEnd;
    glEnable(GL_DEPTH_TEST);
  end;
  DrawSelectionBox;
  if FEditPreviewActive then begin
    { Drag preview is deliberately graphical only: the model is not modified until mouse release. }
    glDisable(GL_DEPTH_TEST); glLineWidth(4); glColor3f(1,0.85,0.2);
    glBegin(GL_LINES);
    for I:=0 to High(FModel.Elements) do if Length(FModel.Elements[I].NodeIDs)>=2 then begin
      if (FModel.Elements[I].NodeIDs[0]=FEditPreviewNodeID) or (FModel.Elements[I].NodeIDs[1]=FEditPreviewNodeID) then begin
        A:=FModel.FindNode(FModel.Elements[I].NodeIDs[0]); B:=FModel.FindNode(FModel.Elements[I].NodeIDs[1]);
        if (A>=0) and (B>=0) then begin
          if FModel.Elements[I].NodeIDs[0]=FEditPreviewNodeID then P1:=FEditPreviewPoint else P1:=NodePosition(A);
          if FModel.Elements[I].NodeIDs[1]=FEditPreviewNodeID then P2:=FEditPreviewPoint else P2:=NodePosition(B);
          glVertex3d(P1.X,P1.Y,P1.Z); glVertex3d(P2.X,P2.Y,P2.Z);
        end;
      end;
    end;
    glEnd;
    glPointSize(13); glColor3f(1,0.85,0.2); glBegin(GL_POINTS); glVertex3d(FEditPreviewPoint.X,FEditPreviewPoint.Y,FEditPreviewPoint.Z); glEnd;
    glEnable(GL_DEPTH_TEST);
  end;
  FControl.SwapBuffers;
end;

procedure TOpenGLFEMRenderer.SetResultFields(AFields:TResultFieldCollection); begin FFields:=AFields; end;
procedure TOpenGLFEMRenderer.SetDisplayManager(ADisplay:TDisplayManager); begin FDisplay:=ADisplay; end;
procedure TOpenGLFEMRenderer.SetClipEnabled(Value:Boolean); begin FClipEnabled:=Value; end;
procedure TOpenGLFEMRenderer.SetClipAxis(Axis:TClipAxis); begin FClipAxis:=Axis; end;
procedure TOpenGLFEMRenderer.SetClipFraction(Value:Double); begin FClipFraction:=Max(0,Min(1,Value)); end;
procedure TOpenGLFEMRenderer.SetClipReverse(Value:Boolean); var P:TClipPlane; begin P:=FClipState.Plane(0); P.Reverse:=Value; FClipState.SetPlane(0,P); end;
procedure TOpenGLFEMRenderer.SetShowAxes(Value:Boolean); begin FShowAxes:=Value; end;
procedure TOpenGLFEMRenderer.SetShowGrid(Value:Boolean); begin FShowGrid:=Value; end;
procedure TOpenGLFEMRenderer.SetShowNodes(Value:Boolean); begin FShowNodes:=Value; end;
procedure TOpenGLFEMRenderer.SetShowElementEdges(Value:Boolean); begin FShowElementEdges:=Value; end;
procedure TOpenGLFEMRenderer.SetShowSolidMembers(Value:Boolean); begin FShowSolidMembers:=Value; end;
procedure TOpenGLFEMRenderer.SetShowClipPlane(Value:Boolean); begin FShowClipPlane:=Value; end;
procedure TOpenGLFEMRenderer.SetShowLoads(Value:Boolean); begin FShowLoads:=Value; end;
procedure TOpenGLFEMRenderer.SetShowRestraints(Value:Boolean); begin FShowRestraints:=Value; end;
procedure TOpenGLFEMRenderer.SetShowLocalAxes(Value:Boolean); begin FShowLocalAxes:=Value; end;
procedure TOpenGLFEMRenderer.SetShowCoordinateSystems(Value:Boolean); begin FShowCoordinateSystems:=Value; end;
procedure TOpenGLFEMRenderer.SetEditPreviewNode(Active:Boolean; NodeID:Integer; const P:TVec3); begin FEditPreviewActive:=Active; FEditPreviewNodeID:=NodeID; FEditPreviewPoint:=P; end;
procedure TOpenGLFEMRenderer.SetEditPreviewBeam(Active:Boolean; const P1,P2:TVec3); begin FEditPreviewBeamActive:=Active; FEditPreviewBeamStart:=P1; FEditPreviewBeamEnd:=P2; end;




procedure TOpenGLFEMRenderer.DrawSelectionBox;
var L,R,T,B:Integer; W,H:Integer;
begin
  if not FSelectionBoxActive then Exit;
  W:=FControl.Width; H:=FControl.Height; if (W<=0) or (H<=0) then Exit;
  L:=Min(FSelectionBoxX1,FSelectionBoxX2); R:=Max(FSelectionBoxX1,FSelectionBoxX2);
  T:=Min(FSelectionBoxY1,FSelectionBoxY2); B:=Max(FSelectionBoxY1,FSelectionBoxY2);
  glDisable(GL_DEPTH_TEST); glDisable(GL_CLIP_PLANE0); glDisable(GL_LIGHTING);
  glMatrixMode(GL_PROJECTION); glPushMatrix; glLoadIdentity; glOrtho(0,W,H,0,-1,1);
  glMatrixMode(GL_MODELVIEW); glPushMatrix; glLoadIdentity;
  glLineWidth(2); glColor4f(0.35,0.85,1.0,0.9);
  glBegin(GL_LINE_LOOP); glVertex2i(L,T); glVertex2i(R,T); glVertex2i(R,B); glVertex2i(L,B); glEnd;
  glMatrixMode(GL_MODELVIEW); glPopMatrix; glMatrixMode(GL_PROJECTION); glPopMatrix;
  glMatrixMode(GL_MODELVIEW); glEnable(GL_DEPTH_TEST);
end;

procedure TOpenGLFEMRenderer.SetSelectionBox(AActive: Boolean; X1, Y1, X2,
  Y2: Integer);
begin FSelectionBoxActive:=AActive; FSelectionBoxX1:=X1; FSelectionBoxY1:=Y1; FSelectionBoxX2:=X2; FSelectionBoxY2:=Y2; end;

end.
