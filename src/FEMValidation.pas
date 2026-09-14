unit FEMValidation;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, FEMModel, FEMTypes;

type
  TValidationSeverity = (vsInfo, vsWarning, vsError);
  TValidationItem = record
    Severity:TValidationSeverity;
    Code:string;
    MessageText:string;
    EntityKind:string;
    EntityID:Integer;
  end;

  TFEMValidationReport = class
  private
    FItems:array of TValidationItem;
    procedure Add(Severity:TValidationSeverity; const Code,Msg:string; const EntityKind:string=''; EntityID:Integer=0);
  public
    procedure Clear;
    procedure Info(const Code,Msg:string);
    procedure Warning(const Code,Msg:string);
    procedure Error(const Code,Msg:string);
    procedure InfoEntity(const Code,Msg,EntityKind:string; EntityID:Integer);
    procedure WarningEntity(const Code,Msg,EntityKind:string; EntityID:Integer);
    procedure ErrorEntity(const Code,Msg,EntityKind:string; EntityID:Integer);
    function Count:Integer;
    function ErrorCount:Integer;
    function WarningCount:Integer;
    function Item(I:Integer):TValidationItem;
    function AsText:string;
    function Validate(const M:TFEMModel):Boolean;
  end;

implementation

procedure TFEMValidationReport.Add(Severity:TValidationSeverity; const Code,Msg:string; const EntityKind:string; EntityID:Integer);
var I:Integer;
begin
  I:=Length(FItems); SetLength(FItems,I+1);
  FItems[I].Severity:=Severity; FItems[I].Code:=Code; FItems[I].MessageText:=Msg;
  FItems[I].EntityKind:=EntityKind; FItems[I].EntityID:=EntityID;
end;

procedure TFEMValidationReport.Clear; begin SetLength(FItems,0); end;
procedure TFEMValidationReport.Info(const Code,Msg:string); begin Add(vsInfo,Code,Msg); end;
procedure TFEMValidationReport.Warning(const Code,Msg:string); begin Add(vsWarning,Code,Msg); end;
procedure TFEMValidationReport.Error(const Code,Msg:string); begin Add(vsError,Code,Msg); end;
procedure TFEMValidationReport.InfoEntity(const Code,Msg,EntityKind:string; EntityID:Integer); begin Add(vsInfo,Code,Msg,EntityKind,EntityID); end;
procedure TFEMValidationReport.WarningEntity(const Code,Msg,EntityKind:string; EntityID:Integer); begin Add(vsWarning,Code,Msg,EntityKind,EntityID); end;
procedure TFEMValidationReport.ErrorEntity(const Code,Msg,EntityKind:string; EntityID:Integer); begin Add(vsError,Code,Msg,EntityKind,EntityID); end;
function TFEMValidationReport.Count:Integer; begin Result:=Length(FItems); end;
function TFEMValidationReport.ErrorCount:Integer;
var I:Integer;
begin Result:=0; for I:=0 to High(FItems) do if FItems[I].Severity=vsError then Inc(Result); end;
function TFEMValidationReport.WarningCount:Integer;
var I:Integer;
begin Result:=0; for I:=0 to High(FItems) do if FItems[I].Severity=vsWarning then Inc(Result); end;
function TFEMValidationReport.Item(I:Integer):TValidationItem; begin Result:=FItems[I]; end;

function TFEMValidationReport.AsText:string;
var I:Integer; P:string;
begin
  Result:='';
  for I:=0 to High(FItems) do begin
    case FItems[I].Severity of
      vsInfo:P:='INFO'; vsWarning:P:='WARN'; else P:='ERROR';
    end;
    if FItems[I].EntityKind<>'' then Result:=Result+Format('%s [%s] %s (%s %d)',[P,FItems[I].Code,FItems[I].MessageText,FItems[I].EntityKind,FItems[I].EntityID])+LineEnding
    else Result:=Result+Format('%s [%s] %s',[P,FItems[I].Code,FItems[I].MessageText])+LineEnding;
  end;
end;

function NodeVec(const M:TFEMModel; NodeID:Integer):TVec3;
var I:Integer;
begin I:=M.FindNode(NodeID); if I<0 then Result:=Vec3(0,0,0) else Result:=M.Nodes[I].Position; end;

function AngleBetween(const A,B:TVec3):Double;
var D:Double;
begin D:=VNorm(A)*VNorm(B); if D<1e-20 then Exit(Pi); Result:=ArcCos(Max(-1,Min(1,VDot(A,B)/D))); end;

function FaceNormal(const A,B,C:TVec3):TVec3;
begin Result:=VCross(VSub(B,A),VSub(C,A)); end;

function TFEMValidationReport.Validate(const M:TFEMModel):Boolean;
var I,J,K,N,MI,SI,LC:Integer; UsedNode:array of Boolean; V,MinEdge,MaxEdge,EL:Double;
begin
  Clear; SetLength(UsedNode,Length(M.Nodes));
  if Length(M.Nodes)=0 then Error('MODEL_EMPTY','Model contains no nodes.');
  if Length(M.Elements)=0 then Warning('NO_ELEMENTS','Model contains no elements.');

  for I:=0 to High(M.Nodes) do begin
    for J:=0 to I-1 do if M.Nodes[J].ID=M.Nodes[I].ID then Error('DUP_NODE_ID',Format('Duplicate node ID %d.',[M.Nodes[I].ID]));
    if IsNan(M.Nodes[I].Position.X) or IsInfinite(M.Nodes[I].Position.X) or IsNan(M.Nodes[I].Position.Y) or IsInfinite(M.Nodes[I].Position.Y) or IsNan(M.Nodes[I].Position.Z) or IsInfinite(M.Nodes[I].Position.Z) then Error('BAD_NODE_COORD',Format('Node %d has invalid coordinates.',[M.Nodes[I].ID]));
  end;

  for I:=0 to High(M.Nodes) do for J:=0 to I-1 do
    if VNorm(VSub(M.Nodes[I].Position,M.Nodes[J].Position))<1e-12 then
      WarningEntity('COINCIDENT_NODES',Format('Nodes %d and %d occupy the same coordinates.',[M.Nodes[I].ID,M.Nodes[J].ID]),'Node',M.Nodes[I].ID);
  if Length(M.Nodes)>0 then begin
    K:=0; for I:=0 to High(M.Nodes) do for J:=0 to 5 do if M.Nodes[I].Restraint[J] then Inc(K);
    if K=0 then Warning('NO_RESTRAINTS','No degrees of freedom are restrained; a static structural model will normally contain rigid-body mechanisms.');
  end;

  for I:=0 to High(M.Materials) do begin
    for J:=0 to I-1 do if M.Materials[J].ID=M.Materials[I].ID then Error('DUP_MATERIAL_ID',Format('Duplicate material ID %d.',[M.Materials[I].ID]));
    if M.Materials[I].E<=0 then Error('BAD_MATERIAL_E',Format('Material %d has non-positive Young''s modulus.',[M.Materials[I].ID]));
    if (M.Materials[I].Nu<=-1) or (M.Materials[I].Nu>=0.5) then Error('BAD_MATERIAL_NU',Format('Material %d has invalid Poisson ratio %.6g.',[M.Materials[I].ID,M.Materials[I].Nu]));
  end;
  for I:=0 to High(M.Sections) do begin
    for J:=0 to I-1 do if M.Sections[J].ID=M.Sections[I].ID then Error('DUP_SECTION_ID',Format('Duplicate section ID %d.',[M.Sections[I].ID]));
    if M.Sections[I].Area<=0 then Error('BAD_SECTION_A',Format('Section %d has non-positive area.',[M.Sections[I].ID]));
    if M.Sections[I].Iy<=0 then Error('BAD_SECTION_IY',Format('Section %d has non-positive Iy.',[M.Sections[I].ID]));
    if M.Sections[I].Iz<=0 then Error('BAD_SECTION_IZ',Format('Section %d has non-positive Iz.',[M.Sections[I].ID]));
    if M.Sections[I].J<=0 then Error('BAD_SECTION_J',Format('Section %d has non-positive torsional constant J.',[M.Sections[I].ID]));
  end;
  for I:=0 to High(M.LoadCases) do for J:=0 to I-1 do if M.LoadCases[J].ID=M.LoadCases[I].ID then Error('DUP_LOADCASE_ID',Format('Duplicate load case ID %d.',[M.LoadCases[I].ID]));

  for I:=0 to High(M.Elements) do begin
    for J:=0 to I-1 do if M.Elements[J].ID=M.Elements[I].ID then Error('DUP_ELEMENT_ID',Format('Duplicate element ID %d.',[M.Elements[I].ID]));
    if Length(M.Elements[I].NodeIDs)=0 then Error('ELEMENT_NO_NODES',Format('Element %d has no nodes.',[M.Elements[I].ID]));
    for J:=0 to High(M.Elements[I].NodeIDs) do begin
      N:=M.FindNode(M.Elements[I].NodeIDs[J]);
      if N<0 then Error('MISSING_NODE',Format('Element %d references missing node %d.',[M.Elements[I].ID,M.Elements[I].NodeIDs[J]]))
      else begin
        UsedNode[N]:=True;
      end;
      for K:=0 to J-1 do if M.Elements[I].NodeIDs[K]=M.Elements[I].NodeIDs[J] then Error('DUP_ELEMENT_NODE',Format('Element %d repeats node %d.',[M.Elements[I].ID,M.Elements[I].NodeIDs[J]]));
    end;
    MI:=M.FindMaterial(M.Elements[I].MaterialID); if MI<0 then Error('MISSING_MATERIAL',Format('Element %d references missing material %d.',[M.Elements[I].ID,M.Elements[I].MaterialID]));
    if M.Elements[I].SectionID<>0 then begin SI:=M.FindSection(M.Elements[I].SectionID); if SI<0 then Error('MISSING_SECTION',Format('Element %d references missing section %d.',[M.Elements[I].ID,M.Elements[I].SectionID])); end;
    if Length(M.Elements[I].NodeIDs)>=2 then begin
      N:=M.FindNode(M.Elements[I].NodeIDs[0]); K:=M.FindNode(M.Elements[I].NodeIDs[1]);
      if (N>=0) and (K>=0) then begin
        V:=Sqr(M.Nodes[K].Position.X-M.Nodes[N].Position.X)+Sqr(M.Nodes[K].Position.Y-M.Nodes[N].Position.Y)+Sqr(M.Nodes[K].Position.Z-M.Nodes[N].Position.Z);
        if V<1e-24 then ErrorEntity('ZERO_LENGTH_ELEMENT',Format('Element %d has zero length between its first two nodes.',[M.Elements[I].ID]),'Element',M.Elements[I].ID);
        if SameText(M.Elements[I].Kind,'BEAM3D') and (V>=1e-24) then begin
          SI:=M.FindSection(M.Elements[I].SectionID);
          if SI>=0 then begin
            if Sqrt(V)/Sqrt(Max(M.Sections[SI].Area,1e-30))>200 then WarningEntity('BEAM_SLENDERNESS',Format('Beam %d is very slender (L/sqrt(A) > 200); verify formulation and mesh density.',[M.Elements[I].ID]),'Element',M.Elements[I].ID);
          end;
        end;
      end;
    end;
    // Generic polygon edge-ratio check. It is intentionally conservative and is
    // applicable to future plate/shell elements as well as current surface prototypes.
    if Length(M.Elements[I].NodeIDs)>=3 then begin
      MinEdge:=1e300; MaxEdge:=0;
      for J:=0 to High(M.Elements[I].NodeIDs) do begin
        K:=M.FindNode(M.Elements[I].NodeIDs[J]); N:=M.FindNode(M.Elements[I].NodeIDs[(J+1) mod Length(M.Elements[I].NodeIDs)]);
        if (K>=0) and (N>=0) then begin EL:=Sqrt(Sqr(M.Nodes[K].Position.X-M.Nodes[N].Position.X)+Sqr(M.Nodes[K].Position.Y-M.Nodes[N].Position.Y)+Sqr(M.Nodes[K].Position.Z-M.Nodes[N].Position.Z)); MinEdge:=Min(MinEdge,EL);MaxEdge:=Max(MaxEdge,EL);end;
      end;
      if (MinEdge<1e299) and (MinEdge>1e-12) and (MaxEdge/MinEdge>10) then WarningEntity('ELEMENT_ASPECT_RATIO',Format('Element %d has edge aspect ratio %.3g (>10); review mesh quality.',[M.Elements[I].ID,MaxEdge/MinEdge]),'Element',M.Elements[I].ID);
      if Length(M.Elements[I].NodeIDs)>=3 then begin
        for J:=0 to High(M.Elements[I].NodeIDs) do begin
          K:=M.FindNode(M.Elements[I].NodeIDs[(J-1+Length(M.Elements[I].NodeIDs)) mod Length(M.Elements[I].NodeIDs)]);
          N:=M.FindNode(M.Elements[I].NodeIDs[J]);
          SI:=M.FindNode(M.Elements[I].NodeIDs[(J+1) mod Length(M.Elements[I].NodeIDs)]);
          if (K>=0) and (N>=0) and (SI>=0) then
            if AngleBetween(VSub(M.Nodes[K].Position,M.Nodes[N].Position),VSub(M.Nodes[SI].Position,M.Nodes[N].Position)) < DegToRad(15) then
              WarningEntity('SMALL_ELEMENT_ANGLE',Format('Element %d has an internal angle below 15 degrees.',[M.Elements[I].ID]),'Element',M.Elements[I].ID);
        end;
      end;
      if Length(M.Elements[I].NodeIDs)=4 then begin
        N:=M.FindNode(M.Elements[I].NodeIDs[0]); K:=M.FindNode(M.Elements[I].NodeIDs[1]); SI:=M.FindNode(M.Elements[I].NodeIDs[2]); LC:=M.FindNode(M.Elements[I].NodeIDs[3]);
        if (N>=0) and (K>=0) and (SI>=0) and (LC>=0) then begin
          V:=VNorm(FaceNormal(M.Nodes[N].Position,M.Nodes[K].Position,M.Nodes[SI].Position))*VNorm(FaceNormal(M.Nodes[N].Position,M.Nodes[SI].Position,M.Nodes[LC].Position));
          if V>1e-24 then begin
            EL:=RadToDeg(AngleBetween(FaceNormal(M.Nodes[N].Position,M.Nodes[K].Position,M.Nodes[SI].Position),FaceNormal(M.Nodes[N].Position,M.Nodes[SI].Position,M.Nodes[LC].Position)));
            if EL>10 then WarningEntity('QUAD_WARP',Format('Element %d has quad face warpage of %.3g degrees (>10).',[M.Elements[I].ID,EL]),'Element',M.Elements[I].ID);
          end;
        end;
      end;
    end;
  end;
  for I:=0 to High(UsedNode) do if not UsedNode[I] then Warning('ORPHAN_NODE',Format('Node %d is not referenced by any element.',[M.Nodes[I].ID]));

  for I:=0 to High(M.Loads) do begin
    if M.FindNode(M.Loads[I].NodeID)<0 then Error('LOAD_NODE_MISSING',Format('Load %d references missing node %d.',[M.Loads[I].ID,M.Loads[I].NodeID]));
    LC:=M.FindLoadCase(M.Loads[I].LoadCaseID); if LC<0 then Error('LOADCASE_MISSING',Format('Load %d references missing load case %d.',[M.Loads[I].ID,M.Loads[I].LoadCaseID]));
  end;
  Result:=ErrorCount=0;
end;

end.
