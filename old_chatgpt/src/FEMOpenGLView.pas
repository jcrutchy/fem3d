unit FEMOpenGLView;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, OpenGLContext, GL,
  FEMTypes, FEMModel, FEMView, FEMSelection, FEMResultFields, FEMDisplayManager,
  FEMResultVisualisation, FEMResultVisualisationGL;

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
    FShowClipPlane: Boolean;
    FShowLoads: Boolean;
    FShowRestraints: Boolean;
    FShowLocalAxes: Boolean;
    FShowCoordinateSystems: Boolean;
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
    function GlyphScale: Double;
    procedure DrawArrow(const Origin,Direction: TVec3; Length,HeadSize: Double);
    procedure DrawLoads;
    procedure DrawRestraints;
    procedure DrawLocalAxes;
    procedure DrawCoordinateSystems;
  public
    constructor Create(AControl: TOpenGLControl; AModel: TFEMModel; AView: TFEMViewport);
    procedure SetDisplayManager(ADisplay:TDisplayManager);
    procedure Paint;
    procedure SetResultFields(AFields: TResultFieldCollection);
    procedure SetClipEnabled(Value: Boolean);
    procedure SetClipAxis(Axis: TClipAxis);
    procedure SetClipFraction(Value: Double);
    procedure SetShowAxes(Value: Boolean);
    procedure SetShowGrid(Value: Boolean);
    procedure SetShowNodes(Value: Boolean);
    procedure SetShowElementEdges(Value: Boolean);
    procedure SetShowClipPlane(Value: Boolean);
    procedure SetShowLoads(Value: Boolean);
    procedure SetShowRestraints(Value: Boolean);
    procedure SetShowLocalAxes(Value: Boolean);
    procedure SetShowCoordinateSystems(Value: Boolean);
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
  FShowAxes:=True; FShowGrid:=True; FShowNodes:=True; FShowElementEdges:=True; FShowClipPlane:=True;
  FShowLoads:=True; FShowRestraints:=True; FShowLocalAxes:=False; FShowCoordinateSystems:=True;
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

procedure TOpenGLFEMRenderer.ApplyClipPlane;
var Eq: array[0..3] of GLdouble; C: Double;
    MinP,MaxP: TVec3;
begin
  if not FClipEnabled then Exit;
  GetBounds(MinP,MaxP);
  case FClipAxis of
    caX: begin C:=MinP.X+(MaxP.X-MinP.X)*FClipFraction; Eq[0]:=1;Eq[1]:=0;Eq[2]:=0;Eq[3]:=-C; end;
    caY: begin C:=MinP.Y+(MaxP.Y-MinP.Y)*FClipFraction; Eq[0]:=0;Eq[1]:=1;Eq[2]:=0;Eq[3]:=-C; end;
    else begin C:=MinP.Z+(MaxP.Z-MinP.Z)*FClipFraction; Eq[0]:=0;Eq[1]:=0;Eq[2]:=1;Eq[3]:=-C; end;
  end;
  glClipPlane(GL_CLIP_PLANE0,@Eq); glEnable(GL_CLIP_PLANE0);
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
var MinP,MaxP: TVec3; C: Double;
begin
  if (not FClipEnabled) or (not FShowClipPlane) then Exit;
  GetBounds(MinP,MaxP);
  case FClipAxis of
    caX: begin C:=MinP.X+(MaxP.X-MinP.X)*FClipFraction; glBegin(GL_QUADS); glColor4f(0.2,0.65,1,0.10); glVertex3d(C,MinP.Y,MinP.Z); glVertex3d(C,MaxP.Y,MinP.Z); glVertex3d(C,MaxP.Y,MaxP.Z); glVertex3d(C,MinP.Y,MaxP.Z); glEnd; end;
    caY: begin C:=MinP.Y+(MaxP.Y-MinP.Y)*FClipFraction; glBegin(GL_QUADS); glColor4f(0.2,0.65,1,0.10); glVertex3d(MinP.X,C,MinP.Z); glVertex3d(MaxP.X,C,MinP.Z); glVertex3d(MaxP.X,C,MaxP.Z); glVertex3d(MinP.X,C,MaxP.Z); glEnd; end;
    else begin C:=MinP.Z+(MaxP.Z-MinP.Z)*FClipFraction; glBegin(GL_QUADS); glColor4f(0.2,0.65,1,0.10); glVertex3d(MinP.X,MinP.Y,C); glVertex3d(MaxP.X,MinP.Y,C); glVertex3d(MaxP.X,MaxP.Y,C); glVertex3d(MinP.X,MaxP.Y,C); glEnd; end;
  end;
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

procedure TOpenGLFEMRenderer.Paint;
var I,A,B: Integer; P1,P2: TVec3; V,V1,V2: Double; F:TResultField; Col: TSelectionSet; Scene:TResultVisualisationScene;
begin
  if not FControl.MakeCurrent then Exit;
  glViewport(0,0,FControl.Width,FControl.Height);
  glClearColor(0.055,0.065,0.08,1); glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT);
  glEnable(GL_DEPTH_TEST); glDepthFunc(GL_LEQUAL); glEnable(GL_BLEND); glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);
  SetupProjection(FControl.Width,FControl.Height); SetupCamera; ApplyClipPlane;
  if FShowGrid then DrawGrid; if FShowAxes then DrawAxes;
  F:=FView.ActiveField;
  if F<>nil then begin
    Scene:=TResultVisualisationAdapter.BuildElementContourScene(
      FModel, FFields, F, FView.ShowDeformed, FView.DeformationScale,
      FView.ContourMin, FView.ContourMax);
    try
      TGLResultVisualisationAdapter.DrawContourScene(Scene, -1);
    finally
      Scene.Free;
    end;
  end else begin
    glDisable(GL_LIGHTING);
    glLineWidth(2);
    for I:=0 to High(FModel.Elements) do
      if (FDisplay=nil) or FDisplay.IsElementVisible(FModel.Elements[I]) then
        if Length(FModel.Elements[I].NodeIDs)>=2 then begin
          A:=FModel.FindNode(FModel.Elements[I].NodeIDs[0]);
          B:=FModel.FindNode(FModel.Elements[I].NodeIDs[1]);
          if (A<0) or (B<0) then Continue;
          glColor3f(0.72,0.76,0.84);
          if FView.Selection.ElementSelected(FModel.Elements[I].ID) then
            glLineWidth(5)
          else
            glLineWidth(2);
          P1:=NodePosition(A);
          P2:=NodePosition(B);
          glBegin(GL_LINES);
          glVertex3d(P1.X,P1.Y,P1.Z);
          glVertex3d(P2.X,P2.Y,P2.Z);
          glEnd;
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
  if FShowNodes then begin glPointSize(6); glBegin(GL_POINTS); for I:=0 to High(FModel.Nodes) do begin if (FDisplay=nil) or FDisplay.IsNodeVisible(FModel,FModel.Nodes[I].ID) then begin if FView.Selection.NodeSelected(FModel.Nodes[I].ID) then glColor3f(1,0.2,0.2) else glColor3f(0.95,0.95,0.95); P1:=NodePosition(I); glVertex3d(P1.X,P1.Y,P1.Z); end; end; glEnd; end;
  FControl.SwapBuffers;
end;

procedure TOpenGLFEMRenderer.SetResultFields(AFields:TResultFieldCollection); begin FFields:=AFields; end;
procedure TOpenGLFEMRenderer.SetDisplayManager(ADisplay:TDisplayManager); begin FDisplay:=ADisplay; end;
procedure TOpenGLFEMRenderer.SetClipEnabled(Value:Boolean); begin FClipEnabled:=Value; end;
procedure TOpenGLFEMRenderer.SetClipAxis(Axis:TClipAxis); begin FClipAxis:=Axis; end;
procedure TOpenGLFEMRenderer.SetClipFraction(Value:Double); begin FClipFraction:=Max(0,Min(1,Value)); end;
procedure TOpenGLFEMRenderer.SetShowAxes(Value:Boolean); begin FShowAxes:=Value; end;
procedure TOpenGLFEMRenderer.SetShowGrid(Value:Boolean); begin FShowGrid:=Value; end;
procedure TOpenGLFEMRenderer.SetShowNodes(Value:Boolean); begin FShowNodes:=Value; end;
procedure TOpenGLFEMRenderer.SetShowElementEdges(Value:Boolean); begin FShowElementEdges:=Value; end;
procedure TOpenGLFEMRenderer.SetShowClipPlane(Value:Boolean); begin FShowClipPlane:=Value; end;
procedure TOpenGLFEMRenderer.SetShowLoads(Value:Boolean); begin FShowLoads:=Value; end;
procedure TOpenGLFEMRenderer.SetShowRestraints(Value:Boolean); begin FShowRestraints:=Value; end;
procedure TOpenGLFEMRenderer.SetShowLocalAxes(Value:Boolean); begin FShowLocalAxes:=Value; end;
procedure TOpenGLFEMRenderer.SetShowCoordinateSystems(Value:Boolean); begin FShowCoordinateSystems:=Value; end;

end.
