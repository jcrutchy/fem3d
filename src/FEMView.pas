unit FEMView;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, Controls, Graphics, FEMTypes, FEMModel, FEMSelection, FEMResultFields, FEMResults;

type
  TViewProjection = (vpPerspective, vpOrthographic);
  TSelectionMode = (smElement, smNode);

  TViewCamera = class
  private
    FYaw,FPitch,FDistance:Double;
    FTarget:TVec3;
    FPanX,FPanY:Double;
    FProjection:TViewProjection;
    FFOV:Double;
    FNearClip:Double;
  public
    constructor Create;
    procedure Reset;
    procedure Orbit(DX,DY:Double);
    procedure Zoom(Factor:Double);
    procedure Pan(DX,DY:Double);
    procedure Fit(const MinP,MaxP:TVec3);
    procedure SetOrientation(AYaw,APitch:Double);
    procedure SetProjection(AProjection:TViewProjection);
    procedure SetFOV(AFOV:Double);
    procedure SetNearClip(ANear:Double);
    procedure Focus(const P:TVec3);
    property Projection:TViewProjection read FProjection;
    property FOV:Double read FFOV;
    property NearClip:Double read FNearClip;
    property Yaw:Double read FYaw;
    property Pitch:Double read FPitch;
    property Distance:Double read FDistance;
    property Target:TVec3 read FTarget;
    property PanX:Double read FPanX;
    property PanY:Double read FPanY;
    function Project(const P:TVec3; W,H:Integer):TPoint;
  end;

  TFEMViewport = class
  private
    FCamera:TViewCamera;
    FModel:TFEMModel;
    FSelection:TSelectionSet;
    FLastX,FLastY:Integer;
    FDragMode:Integer; // 0 none, 1 orbit, 2 pan
    FSelectionMode:TSelectionMode;
    FFields:TResultFieldCollection;
    FActiveField:TResultField;
    FDeformationScale:Double;
    FShowDeformed:Boolean;
    FShowUndeformed:Boolean;
    FContourMin,FContourMax:Double;
    function DisplayPosition(NodeIndex:Integer):TVec3;
    function ValueAtNode(Field:TResultField; NodeIndex:Integer):Double;
    function ContourColor(V:Double):TColor;
  public
    constructor Create(AModel:TFEMModel);
    destructor Destroy; override;
    procedure Paint(C:TCanvas; W,H:Integer);
    procedure FitAll;
    procedure FitSelection;
    procedure FocusSelection;
    procedure StandardView(Index:Integer);
    procedure MouseDown(Button:TMouseButton; X,Y:Integer);
    procedure MouseMove(X,Y:Integer; Shift:TShiftState);
    procedure MouseUp;
    procedure Wheel(Delta:Integer);
    procedure TogglePicked(X,Y,W,H:Integer; Additive:Boolean);
    procedure ClearSelection;
    procedure SelectMode(Mode:TSelectionMode);
    function SelectionMode:TSelectionMode;
    procedure SetResultFields(AFields:TResultFieldCollection);
    procedure SetActiveField(const FieldID:string);
    procedure SetDeformationScale(S:Double);
    procedure SetShowDeformed(Value:Boolean);
    procedure SetShowUndeformed(Value:Boolean);
    procedure AutoContourRange;
    procedure AutoDeformationScale;
    procedure SetContourRange(AMin,AMax:Double);
    function ActiveFieldName:string;
    function ActiveFieldUnits:string;
    function ContourNormalized(V:Double):Double;
    property ActiveField:TResultField read FActiveField;
    property ShowDeformed:Boolean read FShowDeformed;
    property ShowUndeformed:Boolean read FShowUndeformed;
    property DeformationScale:Double read FDeformationScale;
    property ContourMin:Double read FContourMin;
    property ContourMax:Double read FContourMax;
    function PickNode(X,Y,W,H:Integer):Integer;
    function PickElement(X,Y,W,H:Integer):Integer;
    property Camera:TViewCamera read FCamera;
    property Selection:TSelectionSet read FSelection;
  end;

implementation

constructor TViewCamera.Create;
begin inherited Create;Reset;end;

procedure TViewCamera.Reset;
begin FYaw:=0.75;FPitch:=0.45;FDistance:=10;FTarget:=Vec3(0,0,0);FPanX:=0;FPanY:=0;FProjection:=vpPerspective;FFOV:=45; FNearClip:=0.01;end;
procedure TViewCamera.SetOrientation(AYaw,APitch:Double); begin FYaw:=AYaw; FPitch:=Max(-1.5,Min(1.5,APitch)); end;
procedure TViewCamera.SetProjection(AProjection:TViewProjection); begin FProjection:=AProjection; end;
procedure TViewCamera.SetFOV(AFOV:Double); begin FFOV:=Max(10,Min(120,AFOV)); end;
procedure TViewCamera.SetNearClip(ANear:Double); begin FNearClip:=Max(1e-6,Min(1e6,ANear)); end;
procedure TViewCamera.Focus(const P:TVec3); begin FTarget:=P; FPanX:=0; FPanY:=0; end;
procedure TViewCamera.Orbit(DX,DY:Double);begin FYaw:=FYaw+DX;FPitch:=Max(-1.5,Min(1.5,FPitch+DY));end;
procedure TViewCamera.Zoom(Factor:Double);begin FDistance:=Max(1e-6,FDistance*Factor);end;
procedure TViewCamera.Pan(DX,DY:Double);begin FPanX:=FPanX+DX;FPanY:=FPanY+DY;end;

procedure TViewCamera.Fit(const MinP,MaxP:TVec3);
var D:Double;
begin
  FTarget:=Vec3((MinP.X+MaxP.X)/2,(MinP.Y+MaxP.Y)/2,(MinP.Z+MaxP.Z)/2);
  D:=Max(Max(MaxP.X-MinP.X,MaxP.Y-MinP.Y),MaxP.Z-MinP.Z);
  if D<1e-9 then D:=1;
  FDistance:=D*1.5;FPanX:=0;FPanY:=0;
end;

function TViewCamera.Project(const P:TVec3; W,H:Integer):TPoint;
var X,Y,Z,CY,SY,CP,SP,S,Scale:Double;
begin
  X:=P.X-FTarget.X;Y:=P.Y-FTarget.Y;Z:=P.Z-FTarget.Z;
  CY:=Cos(FYaw);SY:=Sin(FYaw);CP:=Cos(FPitch);SP:=Sin(FPitch);
  S:=X*CY+Z*SY; Z:=-X*SY+Z*CY; Y:=Y*CP-Z*SP;
  Scale:=Min(W,H)/(2*Max(FDistance,1e-9));
  Result.X:=Round(W/2+(S+FPanX)*Scale);Result.Y:=Round(H/2-(Y+FPanY)*Scale);
end;

constructor TFEMViewport.Create(AModel:TFEMModel);
begin inherited Create;FModel:=AModel;FCamera:=TViewCamera.Create;FSelection:=TSelectionSet.Create;FFields:=nil;FActiveField:=nil;FDeformationScale:=1;FShowDeformed:=False;FShowUndeformed:=True;FContourMin:=0;FContourMax:=1;FSelectionMode:=smElement;end;
destructor TFEMViewport.Destroy;begin FSelection.Free;FCamera.Free;inherited Destroy;end;

procedure TFEMViewport.FitAll;
var I:Integer; MinP,MaxP,P:TVec3;
begin
  if Length(FModel.Nodes)=0 then Exit;
  MinP:=FModel.Nodes[0].Position;MaxP:=MinP;
  for I:=1 to High(FModel.Nodes) do begin P:=FModel.Nodes[I].Position;
    MinP.X:=Min(MinP.X,P.X);MinP.Y:=Min(MinP.Y,P.Y);MinP.Z:=Min(MinP.Z,P.Z);
    MaxP.X:=Max(MaxP.X,P.X);MaxP.Y:=Max(MaxP.Y,P.Y);MaxP.Z:=Max(MaxP.Z,P.Z);
  end;
  FCamera.Fit(MinP,MaxP);
end;

procedure TFEMViewport.FitSelection;
var I,J,N,K:Integer; MinP,MaxP,P:TVec3; Have:Boolean; E:TElementRecord;
begin
  Have:=False;
  if FSelection.NodeCount>0 then begin
    for I:=0 to FSelection.NodeCount-1 do begin N:=FModel.FindNode(FSelection.NodeID(I)); if N<0 then Continue; P:=FModel.Nodes[N].Position; if not Have then begin MinP:=P; MaxP:=P; Have:=True; end else begin MinP.X:=Min(MinP.X,P.X); MinP.Y:=Min(MinP.Y,P.Y); MinP.Z:=Min(MinP.Z,P.Z); MaxP.X:=Max(MaxP.X,P.X); MaxP.Y:=Max(MaxP.Y,P.Y); MaxP.Z:=Max(MaxP.Z,P.Z); end; end;
  end else if FSelection.ElementCount>0 then begin
    for I:=0 to FSelection.ElementCount-1 do begin
      K:=-1; for N:=0 to High(FModel.Elements) do if FModel.Elements[N].ID=FSelection.ElementID(I) then begin K:=N; Break; end; if K<0 then Continue; E:=FModel.Elements[K];
      for J:=0 to High(E.NodeIDs) do begin N:=FModel.FindNode(E.NodeIDs[J]); if N<0 then Continue; P:=FModel.Nodes[N].Position; if not Have then begin MinP:=P; MaxP:=P; Have:=True; end else begin MinP.X:=Min(MinP.X,P.X); MinP.Y:=Min(MinP.Y,P.Y); MinP.Z:=Min(MinP.Z,P.Z); MaxP.X:=Max(MaxP.X,P.X); MaxP.Y:=Max(MaxP.Y,P.Y); MaxP.Z:=Max(MaxP.Z,P.Z); end; end;
    end;
  end;
  if Have then FCamera.Fit(MinP,MaxP);
end;

procedure TFEMViewport.FocusSelection;
var I,J,N,K:Integer; S:TVec3; Count:Integer; E:TElementRecord;
begin
  S:=Vec3(0,0,0); Count:=0;
  if FSelection.NodeCount>0 then for I:=0 to FSelection.NodeCount-1 do begin N:=FModel.FindNode(FSelection.NodeID(I)); if N>=0 then begin S.X:=S.X+FModel.Nodes[N].Position.X; S.Y:=S.Y+FModel.Nodes[N].Position.Y; S.Z:=S.Z+FModel.Nodes[N].Position.Z; Inc(Count); end; end
  else for I:=0 to FSelection.ElementCount-1 do begin K:=-1; for N:=0 to High(FModel.Elements) do if FModel.Elements[N].ID=FSelection.ElementID(I) then begin K:=N; Break; end; if K<0 then Continue; E:=FModel.Elements[K]; for J:=0 to High(E.NodeIDs) do begin N:=FModel.FindNode(E.NodeIDs[J]); if N>=0 then begin S.X:=S.X+FModel.Nodes[N].Position.X; S.Y:=S.Y+FModel.Nodes[N].Position.Y; S.Z:=S.Z+FModel.Nodes[N].Position.Z; Inc(Count); end; end; end;
  if Count>0 then begin S.X:=S.X/Count; S.Y:=S.Y/Count; S.Z:=S.Z/Count; FCamera.Focus(S); end;
end;

procedure TFEMViewport.StandardView(Index:Integer);
begin
  case Index of
    0: FCamera.SetOrientation(0,0);       // front
    1: FCamera.SetOrientation(Pi,0);      // rear
    2: FCamera.SetOrientation(Pi/2,0);    // right
    3: FCamera.SetOrientation(-Pi/2,0);   // left
    4: FCamera.SetOrientation(0,Pi/2-0.001); // top
    5: FCamera.SetOrientation(0,-Pi/2+0.001); // bottom
    else FCamera.SetOrientation(Pi/4,0.61548); // isometric
  end;
end;

procedure TFEMViewport.Paint(C:TCanvas; W,H:Integer);
var I,A,B:Integer; P1,P2:TPoint; V1,V2,V:Double; Col:TColor;
begin
  C.Brush.Color:=clWhite; C.FillRect(Rect(0,0,W,H));
  if FShowUndeformed then begin
    C.Pen.Width:=1; C.Pen.Color:=clSilver;
    for I:=0 to High(FModel.Elements) do if Length(FModel.Elements[I].NodeIDs)>=2 then begin
      A:=FModel.FindNode(FModel.Elements[I].NodeIDs[0]); B:=FModel.FindNode(FModel.Elements[I].NodeIDs[1]);
      if (A>=0) and (B>=0) then begin
        P1:=FCamera.Project(FModel.Nodes[A].Position,W,H); P2:=FCamera.Project(FModel.Nodes[B].Position,W,H); C.MoveTo(P1.X,P1.Y); C.LineTo(P2.X,P2.Y);
      end;
    end;
  end;
  for I:=0 to High(FModel.Elements) do if Length(FModel.Elements[I].NodeIDs)>=2 then begin
    A:=FModel.FindNode(FModel.Elements[I].NodeIDs[0]); B:=FModel.FindNode(FModel.Elements[I].NodeIDs[1]);
    if (A<0) or (B<0) then Continue;
    P1:=FCamera.Project(DisplayPosition(A),W,H); P2:=FCamera.Project(DisplayPosition(B),W,H);
    if FActiveField<>nil then begin
      if FActiveField.Location=rlElement then V:=FActiveField.ValueForEntity(FModel.Elements[I].ID)
      else begin V1:=ValueAtNode(FActiveField,A); V2:=ValueAtNode(FActiveField,B); V:=(V1+V2)*0.5; end;
      Col:=ContourColor(V); C.Pen.Color:=Col;
    end else C.Pen.Color:=clNavy;
    if FSelection.ElementSelected(FModel.Elements[I].ID) then C.Pen.Width:=3 else C.Pen.Width:=2;
    C.MoveTo(P1.X,P1.Y); C.LineTo(P2.X,P2.Y);
  end;
  C.Pen.Width:=1;
  if FActiveField<>nil then begin
    C.Font.Color:=clBlack; C.Brush.Style:=bsSolid;
    C.Brush.Color:=clWhite; C.FillRect(Rect(W-155,12,W-12,135));
    C.TextOut(W-145,18,FActiveField.Name);
    for I:=0 to 15 do begin C.Brush.Color:=ContourColor(FContourMin+(FContourMax-FContourMin)*(1-I/15)); C.FillRect(Rect(W-45,38+I*5,W-28,43+I*5)); end;
    C.Brush.Color:=clWhite; C.TextOut(W-140,36,Format('%.5g',[FContourMax])); C.TextOut(W-140,111,Format('%.5g',[FContourMin])); C.TextOut(W-140,126,FActiveField.Units);
  end;
  for I:=0 to High(FModel.Nodes) do begin
    P1:=FCamera.Project(DisplayPosition(I),W,H);
    if FSelection.NodeSelected(FModel.Nodes[I].ID) then begin C.Brush.Color:=clRed;C.Ellipse(P1.X-5,P1.Y-5,P1.X+5,P1.Y+5); end
    else begin C.Brush.Color:=clBlack;C.Ellipse(P1.X-3,P1.Y-3,P1.X+3,P1.Y+3); end;
  end;
end;

function TFEMViewport.DisplayPosition(NodeIndex:Integer):TVec3;
var U0,U1,U2:Double;
begin
  Result:=FModel.Nodes[NodeIndex].Position;
  if not FShowDeformed then Exit;
  if FFields=nil then Exit;
  U0:=ValueAtNode(FFields.Find('U0'),NodeIndex); U1:=ValueAtNode(FFields.Find('U1'),NodeIndex); U2:=ValueAtNode(FFields.Find('U2'),NodeIndex);
  Result.X:=Result.X+U0*FDeformationScale; Result.Y:=Result.Y+U1*FDeformationScale; Result.Z:=Result.Z+U2*FDeformationScale;
end;

function TFEMViewport.ValueAtNode(Field:TResultField; NodeIndex:Integer):Double;
begin if (Field=nil) or (NodeIndex<0) or (NodeIndex>=Length(FModel.Nodes)) then Result:=0 else Result:=Field.ValueForEntity(FModel.Nodes[NodeIndex].ID); end;

function TFEMViewport.ContourColor(V:Double):TColor;
var T:Double; R,G,B:Integer;
begin
  if FActiveField=nil then Exit(clNavy);
  if FContourMax<=FContourMin then T:=0.5 else T:=(V-FContourMin)/(FContourMax-FContourMin);
  T:=Max(0,Min(1,T));
  // Blue -> cyan -> green -> yellow -> red engineering contour scale.
  if T<0.25 then begin R:=0;G:=Round(255*(T/0.25));B:=255;end
  else if T<0.5 then begin R:=0;G:=255;B:=Round(255*(1-(T-0.25)/0.25));end
  else if T<0.75 then begin R:=Round(255*((T-0.5)/0.25));G:=255;B:=0;end
  else begin R:=255;G:=Round(255*(1-(T-0.75)/0.25));B:=0;end;
  Result:=RGBToColor(R,G,B);
end;

procedure TFEMViewport.MouseDown(Button:TMouseButton;X,Y:Integer);
begin
  FLastX:=X;FLastY:=Y;
  if Button=mbMiddle then FDragMode:=1 else if Button=mbRight then FDragMode:=2 else FDragMode:=0;
end;

procedure TFEMViewport.MouseMove(X,Y:Integer;Shift:TShiftState);
begin
  if FDragMode=1 then begin FCamera.Orbit((X-FLastX)*0.01,(Y-FLastY)*0.01);FLastX:=X;FLastY:=Y;end
  else if FDragMode=2 then begin FCamera.Pan((X-FLastX)*0.005,(Y-FLastY)*0.005);FLastX:=X;FLastY:=Y;end;
end;

procedure TFEMViewport.MouseUp;begin FDragMode:=0;end;
procedure TFEMViewport.Wheel(Delta:Integer);begin if Delta>0 then FCamera.Zoom(0.9) else FCamera.Zoom(1.1);end;

procedure TFEMViewport.TogglePicked(X,Y,W,H:Integer; Additive:Boolean);
var ID:Integer;
begin
  if FSelectionMode=smNode then begin
    ID:=PickNode(X,Y,W,H);
    if ID<>0 then begin
      if Additive then FSelection.ToggleNode(ID) else begin FSelection.Clear; FSelection.SelectNode(ID,True); end;
    end else if not Additive then FSelection.Clear;
  end else begin
    ID:=PickElement(X,Y,W,H);
    if ID<>0 then begin
      if Additive then FSelection.ToggleElement(ID) else begin FSelection.Clear; FSelection.SelectElement(ID,True); end;
    end else if not Additive then FSelection.Clear;
  end;
end;

procedure TFEMViewport.ClearSelection; begin FSelection.Clear; end;
procedure TFEMViewport.SelectMode(Mode:TSelectionMode); begin FSelectionMode:=Mode; end;
function TFEMViewport.SelectionMode:TSelectionMode; begin Result:=FSelectionMode; end;

procedure TFEMViewport.SetResultFields(AFields:TResultFieldCollection);
begin FFields:=AFields; FActiveField:=nil; end;
procedure TFEMViewport.SetActiveField(const FieldID:string);
begin if FFields=nil then FActiveField:=nil else FActiveField:=FFields.Find(FieldID); AutoContourRange; end;
procedure TFEMViewport.SetDeformationScale(S:Double);begin FDeformationScale:=Max(0,S);end;
procedure TFEMViewport.SetShowDeformed(Value:Boolean);begin FShowDeformed:=Value;end;
procedure TFEMViewport.SetShowUndeformed(Value:Boolean);begin FShowUndeformed:=Value;end;
procedure TFEMViewport.AutoContourRange;
var I:Integer; V:Double;
begin FContourMin:=0;FContourMax:=1;if FActiveField=nil then Exit; if FActiveField.Count=0 then Exit; FContourMin:=FActiveField.Values[0];FContourMax:=FContourMin;for I:=1 to High(FActiveField.Values) do begin V:=FActiveField.Values[I];FContourMin:=Min(FContourMin,V);FContourMax:=Max(FContourMax,V);end; if FContourMax=FContourMin then FContourMax:=FContourMin+1; end;
function TFEMViewport.ActiveFieldName:string;begin if FActiveField=nil then Result:='' else Result:=FActiveField.Name;end;
function TFEMViewport.ActiveFieldUnits:string;begin if FActiveField=nil then Result:='' else Result:=FActiveField.Units;end;
function TFEMViewport.ContourNormalized(V:Double):Double;
begin if FContourMax<=FContourMin then Result:=0.5 else Result:=(V-FContourMin)/(FContourMax-FContourMin); Result:=Max(0,Min(1,Result)); end;
procedure TFEMViewport.AutoDeformationScale;
var I:Integer; MaxU,Span:Double; P:TVec3; F:TResultField;
begin
  if FFields=nil then Exit; F:=FFields.Find('UMAG'); if F=nil then Exit; MaxU:=0; for I:=0 to High(F.Values) do MaxU:=Max(MaxU,Abs(F.Values[I]));
  Span:=0; if Length(FModel.Nodes)>1 then begin P:=FModel.Nodes[0].Position; for I:=1 to High(FModel.Nodes) do begin Span:=Max(Span,VNorm(VSub(FModel.Nodes[I].Position,P))); end; end; if Span<1e-12 then Span:=1;
  if MaxU>1e-20 then FDeformationScale:=0.25*Span/MaxU else FDeformationScale:=1;
end;
procedure TFEMViewport.SetContourRange(AMin,AMax:Double);begin if AMax>AMin then begin FContourMin:=AMin;FContourMax:=AMax;end else AutoContourRange;end;

function TFEMViewport.PickNode(X,Y,W,H:Integer):Integer;
var I:Integer;P:TPoint;D,Best:Double;
begin Result:=0;Best:=9;
  for I:=0 to High(FModel.Nodes) do begin P:=FCamera.Project(DisplayPosition(I),W,H);D:=Hypot(P.X-X,P.Y-Y);
    if D<Best then begin Best:=D;Result:=FModel.Nodes[I].ID;end;
  end;
end;

function TFEMViewport.PickElement(X,Y,W,H:Integer):Integer;
var I,A,B:Integer;P1,P2:TPoint;DX,DY,T,QX,QY,D,Best:Double;
begin Result:=0;Best:=12;
  for I:=0 to High(FModel.Elements) do if Length(FModel.Elements[I].NodeIDs)>=2 then begin
    A:=FModel.FindNode(FModel.Elements[I].NodeIDs[0]);B:=FModel.FindNode(FModel.Elements[I].NodeIDs[1]);
    if (A<0) or (B<0) then Continue;
    P1:=FCamera.Project(DisplayPosition(A),W,H);P2:=FCamera.Project(DisplayPosition(B),W,H);
    DX:=P2.X-P1.X;DY:=P2.Y-P1.Y;
    if Abs(DX)+Abs(DY)<1e-9 then Continue;
    T:=((X-P1.X)*DX+(Y-P1.Y)*DY)/(DX*DX+DY*DY);T:=Max(0,Min(1,T));
    QX:=P1.X+T*DX;QY:=P1.Y+T*DY;D:=Hypot(X-QX,Y-QY);
    if D<Best then begin Best:=D;Result:=FModel.Elements[I].ID;end;
  end;
end;

end.
