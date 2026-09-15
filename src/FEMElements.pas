unit FEMElements;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, FEMTypes, FEMModel;

type
  TBeamEndForces = record
    Node1,Node2:array[0..5] of Double;
  end;

  TElementContext = record
    Model: TFEMModel;
    Numbering: TDOFNumbering;
  end;

  TFEMElement = class
  public
    function Kind:string; virtual; abstract;
    function NodeCount:Integer; virtual; abstract;
    function DofCount:Integer; virtual;
    procedure GetDofMap(const C:TElementContext; const R:TElementRecord; var Map:array of Integer); virtual; abstract;
    procedure Stiffness(const C:TElementContext; const R:TElementRecord; var Ke:array of Double); virtual; abstract;
    function Description:string; virtual;
  end;

  TElementRegistry = class
  private
    FItems:array of TFEMElement;
  public
    destructor Destroy; override;
    procedure RegisterElement(E:TFEMElement);
    function Find(const KindName:string):TFEMElement;
    function Count:Integer;
    function Item(I:Integer):TFEMElement;
  end;

  TBeam3D = class(TFEMElement)
  public
    function Kind:string; override;
    function NodeCount:Integer; override;
    procedure GetDofMap(const C:TElementContext; const R:TElementRecord; var Map:array of Integer); override;
    procedure Stiffness(const C:TElementContext; const R:TElementRecord; var Ke:array of Double); override;
    function Description:string; override;
    function RecoverEndForces(const C:TElementContext; const R:TElementRecord;
      const GlobalDisplacement:array of Double; out Forces:TBeamEndForces):Boolean;
  end;

  TTri3Membrane = class(TFEMElement)
  public
    function Kind:string; override;
    function NodeCount:Integer; override;
    procedure GetDofMap(const C:TElementContext; const R:TElementRecord; var Map:array of Integer); override;
    procedure Stiffness(const C:TElementContext; const R:TElementRecord; var Ke:array of Double); override;
    function Description:string; override;
  end;

procedure RegisterBuiltInElements(R:TElementRegistry);

implementation

function TFEMElement.DofCount:Integer; begin Result:=NodeCount*6; end;
function TFEMElement.Description:string; begin Result:=Kind; end;

destructor TElementRegistry.Destroy;
var I:Integer;
begin for I:=0 to High(FItems) do FItems[I].Free; inherited Destroy; end;

procedure TElementRegistry.RegisterElement(E:TFEMElement);
begin SetLength(FItems,Length(FItems)+1); FItems[High(FItems)]:=E; end;

function TElementRegistry.Find(const KindName:string):TFEMElement;
var I:Integer;
begin
  Result:=nil;
  for I:=0 to High(FItems) do if SameText(FItems[I].Kind,KindName) then Exit(FItems[I]);
end;

function TElementRegistry.Count:Integer; begin Result:=Length(FItems); end;
function TElementRegistry.Item(I:Integer):TFEMElement; begin Result:=FItems[I]; end;

function TBeam3D.Kind:string; begin Result:='BEAM3D'; end;
function TBeam3D.NodeCount:Integer; begin Result:=2; end;
function TBeam3D.Description:string; begin Result:='3D Euler-Bernoulli frame beam; 6 DOF/node'; end;

function TBeam3D.RecoverEndForces(const C:TElementContext; const R:TElementRecord;
  const GlobalDisplacement:array of Double; out Forces:TBeamEndForces):Boolean;
var N1,N2,MI,SI,I,J,K,L:Integer; P1,P2,Ex,Ref,Ey,Ez:TVec3; Len,E,Nu,G,A,Iy,Iz,Jt,S,V:Double;
    Kloc,T:array[0..11,0..11] of Double; Ug,Ul,Fl:array[0..11] of Double; Eq:Integer;
begin
  Result:=False; FillChar(Forces,SizeOf(Forces),0);
  if Length(GlobalDisplacement)<C.Numbering.Count then Exit;
  N1:=C.Model.FindNode(R.NodeIDs[0]); N2:=C.Model.FindNode(R.NodeIDs[1]); MI:=C.Model.FindMaterial(R.MaterialID); SI:=C.Model.FindSection(R.SectionID);
  if (N1<0) or (N2<0) or (MI<0) or (SI<0) then Exit;
  P1:=C.Model.Nodes[N1].Position; P2:=C.Model.Nodes[N2].Position; Len:=VNorm(VSub(P2,P1)); if Len<1e-12 then Exit;
  Ex:=VUnit(VSub(P2,P1)); Ref:=Vec3(0,0,1); if Abs(VDot(Ex,Ref))>0.9 then Ref:=Vec3(0,1,0); Ey:=VUnit(VCross(Ref,Ex)); Ez:=VCross(Ex,Ey);
  E:=C.Model.Materials[MI].E; Nu:=C.Model.Materials[MI].Nu; G:=E/(2*(1+Nu)); A:=C.Model.Sections[SI].Area; Iy:=C.Model.Sections[SI].Iy; Iz:=C.Model.Sections[SI].Iz; Jt:=C.Model.Sections[SI].J;
  FillChar(Kloc,SizeOf(Kloc),0);
  Kloc[0,0]:=E*A/Len; Kloc[0,6]:=-Kloc[0,0]; Kloc[6,0]:=Kloc[0,6]; Kloc[6,6]:=Kloc[0,0];
  Kloc[3,3]:=G*Jt/Len; Kloc[3,9]:=-Kloc[3,3]; Kloc[9,3]:=Kloc[3,9]; Kloc[9,9]:=Kloc[3,3];
  V:=12*E*Iz/(Len*Sqr(Len)); S:=6*E*Iz/Sqr(Len);
  Kloc[1,1]:=V; Kloc[1,5]:=S; Kloc[1,7]:=-V; Kloc[1,11]:=S; Kloc[5,1]:=S; Kloc[5,5]:=4*E*Iz/Len; Kloc[5,7]:=-S; Kloc[5,11]:=2*E*Iz/Len;
  Kloc[7,1]:=-V; Kloc[7,5]:=-S; Kloc[7,7]:=V; Kloc[7,11]:=-S; Kloc[11,1]:=S; Kloc[11,5]:=2*E*Iz/Len; Kloc[11,7]:=-S; Kloc[11,11]:=4*E*Iz/Len;
  V:=12*E*Iy/(Len*Sqr(Len)); S:=-6*E*Iy/Sqr(Len);
  Kloc[2,2]:=V; Kloc[2,4]:=S; Kloc[2,8]:=-V; Kloc[2,10]:=S; Kloc[4,2]:=S; Kloc[4,4]:=4*E*Iy/Len; Kloc[4,8]:=-S; Kloc[4,10]:=2*E*Iy/Len;
  Kloc[8,2]:=-V; Kloc[8,4]:=-S; Kloc[8,8]:=V; Kloc[8,10]:=-S; Kloc[10,2]:=S; Kloc[10,4]:=2*E*Iy/Len; Kloc[10,8]:=-S; Kloc[10,10]:=4*E*Iy/Len;
  FillChar(T,SizeOf(T),0);
  for I:=0 to 3 do begin
    T[I*3+0,I*3+0]:=Ex.X; T[I*3+0,I*3+1]:=Ex.Y; T[I*3+0,I*3+2]:=Ex.Z;
    T[I*3+1,I*3+0]:=Ey.X; T[I*3+1,I*3+1]:=Ey.Y; T[I*3+1,I*3+2]:=Ey.Z;
    T[I*3+2,I*3+0]:=Ez.X; T[I*3+2,I*3+1]:=Ez.Y; T[I*3+2,I*3+2]:=Ez.Z;
  end;
  for I:=0 to 1 do for J:=0 to 5 do begin Eq:=C.Numbering.DOF(R.NodeIDs[I],J); if (Eq<0) or (Eq>=Length(GlobalDisplacement)) then Exit; Ug[I*6+J]:=GlobalDisplacement[Eq]; end;
  for I:=0 to 11 do begin Ul[I]:=0; for K:=0 to 11 do Ul[I]:=Ul[I]+T[I,K]*Ug[K]; end;
  for I:=0 to 11 do begin Fl[I]:=0; for J:=0 to 11 do Fl[I]:=Fl[I]+Kloc[I,J]*Ul[J]; end;
  for I:=0 to 5 do begin Forces.Node1[I]:=Fl[I]; Forces.Node2[I]:=Fl[I+6]; end;
  Result:=True;
end;

procedure TBeam3D.GetDofMap(const C:TElementContext; const R:TElementRecord; var Map:array of Integer);
var I,J,N:Integer;
begin
  for I:=0 to 1 do begin
    for J:=0 to 5 do Map[I*6+J]:=C.Numbering.DOF(R.NodeIDs[I],J);
  end;
end;

procedure TBeam3D.Stiffness(const C:TElementContext; const R:TElementRecord; var Ke:array of Double);
var
  N1,N2,MI,SI,I,J,K,L:Integer;
  P1,P2,Ex,Ref,Ey,Ez:TVec3;
  Len,E,Nu,G,A,Iy,Iz,Jt,S,V:Double;
  Kloc,T:array[0..11,0..11] of Double;
begin
  FillChar(Ke[0],Length(Ke)*SizeOf(Double),0);
  if Length(Ke)<144 then Exit;
  N1:=C.Model.FindNode(R.NodeIDs[0]); N2:=C.Model.FindNode(R.NodeIDs[1]);
  MI:=C.Model.FindMaterial(R.MaterialID); SI:=C.Model.FindSection(R.SectionID);
  if (N1<0) or (N2<0) or (MI<0) or (SI<0) then Exit;
  P1:=C.Model.Nodes[N1].Position; P2:=C.Model.Nodes[N2].Position;
  Len:=VNorm(VSub(P2,P1)); if Len<1e-12 then Exit;
  Ex:=VUnit(VSub(P2,P1));
  Ref:=Vec3(0,0,1);
  if Abs(VDot(Ex,Ref))>0.9 then Ref:=Vec3(0,1,0);
  Ey:=VUnit(VCross(Ref,Ex)); Ez:=VCross(Ex,Ey);
  E:=C.Model.Materials[MI].E; Nu:=C.Model.Materials[MI].Nu; G:=E/(2*(1+Nu));
  A:=C.Model.Sections[SI].Area; Iy:=C.Model.Sections[SI].Iy; Iz:=C.Model.Sections[SI].Iz; Jt:=C.Model.Sections[SI].J;

  FillChar(Kloc,SizeOf(Kloc),0);
  Kloc[0,0]:=E*A/Len; Kloc[0,6]:=-Kloc[0,0]; Kloc[6,0]:=Kloc[0,6]; Kloc[6,6]:=Kloc[0,0];
  Kloc[3,3]:=G*Jt/Len; Kloc[3,9]:=-Kloc[3,3]; Kloc[9,3]:=Kloc[3,9]; Kloc[9,9]:=Kloc[3,3];

  V:=12*E*Iz/(Len*Sqr(Len)); S:=6*E*Iz/Sqr(Len);
  Kloc[1,1]:=V; Kloc[1,5]:=S; Kloc[1,7]:=-V; Kloc[1,11]:=S;
  Kloc[5,1]:=S; Kloc[5,5]:=4*E*Iz/Len; Kloc[5,7]:=-S; Kloc[5,11]:=2*E*Iz/Len;
  Kloc[7,1]:=-V; Kloc[7,5]:=-S; Kloc[7,7]:=V; Kloc[7,11]:=-S;
  Kloc[11,1]:=S; Kloc[11,5]:=2*E*Iz/Len; Kloc[11,7]:=-S; Kloc[11,11]:=4*E*Iz/Len;

  V:=12*E*Iy/(Len*Sqr(Len)); S:=-6*E*Iy/Sqr(Len);
  Kloc[2,2]:=V; Kloc[2,4]:=S; Kloc[2,8]:=-V; Kloc[2,10]:=S;
  Kloc[4,2]:=S; Kloc[4,4]:=4*E*Iy/Len; Kloc[4,8]:=-S; Kloc[4,10]:=2*E*Iy/Len;
  Kloc[8,2]:=-V; Kloc[8,4]:=-S; Kloc[8,8]:=V; Kloc[8,10]:=-S;
  Kloc[10,2]:=S; Kloc[10,4]:=2*E*Iy/Len; Kloc[10,8]:=-S; Kloc[10,10]:=4*E*Iy/Len;

  FillChar(T,SizeOf(T),0);
  for I:=0 to 3 do begin
    T[I*3+0,I*3+0]:=Ex.X; T[I*3+0,I*3+1]:=Ex.Y; T[I*3+0,I*3+2]:=Ex.Z;
    T[I*3+1,I*3+0]:=Ey.X; T[I*3+1,I*3+1]:=Ey.Y; T[I*3+1,I*3+2]:=Ey.Z;
    T[I*3+2,I*3+0]:=Ez.X; T[I*3+2,I*3+1]:=Ez.Y; T[I*3+2,I*3+2]:=Ez.Z;
  end;
  for I:=0 to 11 do for J:=0 to 11 do begin
    V:=0;
    for K:=0 to 11 do for L:=0 to 11 do V:=V+T[K,I]*Kloc[K,L]*T[L,J];
    Ke[I*12+J]:=V;
  end;
end;

function TTri3Membrane.Kind:string; begin Result:='TRI3_MEMBRANE'; end;
function TTri3Membrane.NodeCount:Integer; begin Result:=3; end;
function TTri3Membrane.Description:string; begin Result:='3-node constant-strain membrane only; no bending DOF formulation'; end;

procedure TTri3Membrane.GetDofMap(const C:TElementContext; const R:TElementRecord; var Map:array of Integer);
var I,J,N:Integer;
begin
  for I:=0 to 2 do begin
    for J:=0 to 5 do Map[I*6+J]:=C.Numbering.DOF(R.NodeIDs[I],J);
  end;
end;

procedure TTri3Membrane.Stiffness(const C:TElementContext; const R:TElementRecord; var Ke:array of Double);
begin
  // Placeholder by design. This element is retained only as an extension example.
  // A future membrane implementation should use a reduced in-plane DOF space
  // rather than pretending to provide plate/shell behaviour.
  FillChar(Ke[0],Length(Ke)*SizeOf(Double),0);
end;

procedure RegisterBuiltInElements(R:TElementRegistry);
begin
  R.RegisterElement(TBeam3D.Create);
  R.RegisterElement(TTri3Membrane.Create);
end;

end.

