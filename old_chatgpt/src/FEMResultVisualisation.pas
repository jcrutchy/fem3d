unit FEMResultVisualisation;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  FEMTypes, FEMModel, FEMResultFields;

type
  TResultRGB = record
    R, G, B: Double;
  end;

  TResultContourMapper = class
  private
    FMinimum, FMaximum: Double;
    FConstant: Boolean;
  public
    constructor Create(AMinimum, AMaximum: Double);
    function Normalize(V: Double): Double;
    function Color(V: Double): TResultRGB;
    property Minimum: Double read FMinimum;
    property Maximum: Double read FMaximum;
    property IsConstant: Boolean read FConstant;
  end;

  TResultContourSegment = record
    ElementID: Integer;
    P1, P2: TVec3;
    V1, V2: Double;
  end;

  TResultLegendBand = record
    Minimum, Maximum: Double;
    Color: TResultRGB;
  end;

  TResultDiagramPoint = record
    Position: Double;
    Value: Double;
  end;

  TResultDiagram = class
  private
    FElementID: Integer;
    FFieldID: string;
    FPoints: array of TResultDiagramPoint;
  public
    procedure Clear;
    procedure AddPoint(const APosition, AValue: Double);
    property ElementID: Integer read FElementID write FElementID;
    property FieldID: string read FFieldID write FFieldID;
    function Count: Integer;
    function Point(I: Integer): TResultDiagramPoint;
  end;

  TResultVisualisationScene = class
  private
    FMapper: TResultContourMapper;
    FSegments: array of TResultContourSegment;
    FLegend: array of TResultLegendBand;
  public
    constructor Create(AMinimum, AMaximum: Double);
    destructor Destroy; override;
    procedure Clear;
    procedure AddSegment(const S: TResultContourSegment);
    procedure BuildLegend(BandCount: Integer = 9);
    function SegmentCount: Integer;
    function Segment(I: Integer): TResultContourSegment;
    function LegendCount: Integer;
    function LegendBand(I: Integer): TResultLegendBand;
    property Mapper: TResultContourMapper read FMapper;
  end;

  TResultVisualisationAdapter = class
  private
    class function NodeResultPosition(const M: TFEMModel; NodeIndex: Integer;
      Fields: TResultFieldCollection; Deformed: Boolean; DeformationScale: Double): TVec3; static;
    class function NodeFieldValue(Field: TResultField; NodeID: Integer): Double; static;
  public
    class function BuildElementContourScene(const M: TFEMModel;
      Fields: TResultFieldCollection; ActiveField: TResultField;
      Deformed: Boolean; DeformationScale, Minimum, Maximum: Double): TResultVisualisationScene; static;
    class function BuildBeamDiagram(const M: TFEMModel;
      Fields: TResultFieldCollection; Field: TResultField; ElementID: Integer): TResultDiagram; static;
  end;

implementation

constructor TResultContourMapper.Create(AMinimum, AMaximum: Double);
begin
  inherited Create;
  FMinimum:=AMinimum;
  FMaximum:=AMaximum;
  FConstant:=Abs(FMaximum-FMinimum)<=1E-30;
end;

function TResultContourMapper.Normalize(V: Double): Double;
begin
  if FConstant then Exit(0.5);
  Result:=(V-FMinimum)/(FMaximum-FMinimum);
  Result:=Max(0,Min(1,Result));
end;

function TResultContourMapper.Color(V: Double): TResultRGB;
var T: Double;
begin
  T:=Normalize(V);
  if T<0.25 then begin Result.R:=0; Result.G:=T/0.25; Result.B:=1; end
  else if T<0.5 then begin Result.R:=0; Result.G:=1; Result.B:=1-(T-0.25)/0.25; end
  else if T<0.75 then begin Result.R:=(T-0.5)/0.25; Result.G:=1; Result.B:=0; end
  else begin Result.R:=1; Result.G:=1-(T-0.75)/0.25; Result.B:=0; end;
end;

procedure TResultDiagram.Clear;
begin
  SetLength(FPoints,0);
  FElementID:=-1;
  FFieldID:='';
end;

procedure TResultDiagram.AddPoint(const APosition, AValue: Double);
var I: Integer;
begin
  I:=Length(FPoints);
  SetLength(FPoints,I+1);
  FPoints[I].Position:=APosition;
  FPoints[I].Value:=AValue;
end;

function TResultDiagram.Count: Integer;
begin Result:=Length(FPoints); end;

function TResultDiagram.Point(I: Integer): TResultDiagramPoint;
begin
  Result:=FPoints[I];
end;

constructor TResultVisualisationScene.Create(AMinimum, AMaximum: Double);
begin
  inherited Create;
  FMapper:=TResultContourMapper.Create(AMinimum,AMaximum);
  Clear;
end;

destructor TResultVisualisationScene.Destroy;
begin
  FMapper.Free;
  inherited Destroy;
end;

procedure TResultVisualisationScene.Clear;
begin
  SetLength(FSegments,0);
  SetLength(FLegend,0);
end;

procedure TResultVisualisationScene.AddSegment(const S: TResultContourSegment);
var I: Integer;
begin
  I:=Length(FSegments);
  SetLength(FSegments,I+1);
  FSegments[I]:=S;
end;

procedure TResultVisualisationScene.BuildLegend(BandCount: Integer);
var I: Integer; A,B,T: Double;
begin
  if BandCount<2 then BandCount:=2;
  SetLength(FLegend,BandCount);
  for I:=0 to BandCount-1 do begin
    T:=I/(BandCount-1);
    A:=FMapper.Minimum+(FMapper.Maximum-FMapper.Minimum)*(I/BandCount);
    B:=FMapper.Minimum+(FMapper.Maximum-FMapper.Minimum)*((I+1)/BandCount);
    FLegend[I].Minimum:=A;
    FLegend[I].Maximum:=B;
    FLegend[I].Color:=FMapper.Color(FMapper.Minimum+(FMapper.Maximum-FMapper.Minimum)*(T+0.5/BandCount));
  end;
end;

function TResultVisualisationScene.SegmentCount: Integer;
begin Result:=Length(FSegments); end;

function TResultVisualisationScene.Segment(I: Integer): TResultContourSegment;
begin Result:=FSegments[I]; end;

function TResultVisualisationScene.LegendCount: Integer;
begin Result:=Length(FLegend); end;

function TResultVisualisationScene.LegendBand(I: Integer): TResultLegendBand;
begin Result:=FLegend[I]; end;

class function TResultVisualisationAdapter.NodeFieldValue(Field: TResultField; NodeID: Integer): Double;
begin
  if Field=nil then Result:=0 else Result:=Field.ValueForEntity(NodeID);
end;

class function TResultVisualisationAdapter.NodeResultPosition(const M: TFEMModel;
  NodeIndex: Integer; Fields: TResultFieldCollection; Deformed: Boolean;
  DeformationScale: Double): TVec3;
var F: TResultField;
begin
  Result:=M.Nodes[NodeIndex].Position;
  if not Deformed then Exit;
  if Fields=nil then Exit;
  F:=Fields.Find('U0'); Result.X:=Result.X+NodeFieldValue(F,M.Nodes[NodeIndex].ID)*DeformationScale;
  F:=Fields.Find('U1'); Result.Y:=Result.Y+NodeFieldValue(F,M.Nodes[NodeIndex].ID)*DeformationScale;
  F:=Fields.Find('U2'); Result.Z:=Result.Z+NodeFieldValue(F,M.Nodes[NodeIndex].ID)*DeformationScale;
end;

class function TResultVisualisationAdapter.BuildElementContourScene(const M: TFEMModel;
  Fields: TResultFieldCollection; ActiveField: TResultField; Deformed: Boolean;
  DeformationScale, Minimum, Maximum: Double): TResultVisualisationScene;
var I,A,B: Integer; S: TResultContourSegment;
begin
  Result:=TResultVisualisationScene.Create(Minimum,Maximum);
  if ActiveField=nil then begin Result.BuildLegend; Exit; end;
  for I:=0 to High(M.Elements) do begin
    if Length(M.Elements[I].NodeIDs)<2 then Continue;
    A:=M.FindNode(M.Elements[I].NodeIDs[0]);
    B:=M.FindNode(M.Elements[I].NodeIDs[1]);
    if (A<0) or (B<0) then Continue;
    S.ElementID:=M.Elements[I].ID;
    S.P1:=NodeResultPosition(M,A,Fields,Deformed,DeformationScale);
    S.P2:=NodeResultPosition(M,B,Fields,Deformed,DeformationScale);
    if ActiveField.Location=rlElement then begin
      S.V1:=ActiveField.ValueForEntity(M.Elements[I].ID);
      S.V2:=S.V1;
    end else begin
      S.V1:=ActiveField.ValueForEntity(M.Nodes[A].ID);
      S.V2:=ActiveField.ValueForEntity(M.Nodes[B].ID);
    end;
    Result.AddSegment(S);
  end;
  Result.BuildLegend;
end;

class function TResultVisualisationAdapter.BuildBeamDiagram(const M: TFEMModel;
  Fields: TResultFieldCollection; Field: TResultField; ElementID: Integer): TResultDiagram;
var E,N1,N2: Integer;
begin
  Result:=TResultDiagram.Create;
  Result.ElementID:=ElementID;
  if Field<>nil then Result.FieldID:=Field.ID;
  E:=-1;
  for N1:=0 to High(M.Elements) do if M.Elements[N1].ID=ElementID then begin E:=N1; Break; end;
  if (E<0) or (Length(M.Elements[E].NodeIDs)<2) or (Field=nil) then Exit;
  N1:=M.Elements[E].NodeIDs[0];
  N2:=M.Elements[E].NodeIDs[1];
  if Field.Location=rlElement then begin
    Result.AddPoint(0,Field.ValueForEntity(ElementID));
    Result.AddPoint(1,Field.ValueForEntity(ElementID));
  end else begin
    Result.AddPoint(0,Field.ValueForEntity(N1));
    Result.AddPoint(1,Field.ValueForEntity(N2));
  end;
end;

end.
