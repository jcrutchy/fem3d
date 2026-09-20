program TestResultVisualisation;

{$mode objfpc}{$H+}

uses
  SysUtils, Math, FEMTypes, FEMModel, FEMResultFields, FEMResultVisualisation;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then begin Writeln('FAIL: ',MessageText); Halt(1); end;
end;

var Mapper: TResultContourMapper; C:TResultRGB; M:TFEMModel; F:TResultField;
    Scene:TResultVisualisationScene; D:TResultDiagram;
begin
  Mapper:=TResultContourMapper.Create(-10,10);
  try
    Check(Abs(Mapper.Normalize(-10))<1E-12,'minimum normalises to zero');
    Check(Abs(Mapper.Normalize(0)-0.5)<1E-12,'midpoint normalises to one half');
    Check(Abs(Mapper.Normalize(10)-1)<1E-12,'maximum normalises to one');
    C:=Mapper.Color(0);
    Check((C.R>=0) and (C.R<=1) and (C.G>=0) and (C.G<=1) and (C.B>=0) and (C.B<=1),'colour remains in range');
  finally Mapper.Free end;

  M:=TFEMModel.Create;
  try
    M.AddNode(Vec3(0,0,0));
    M.AddNode(Vec3(1,0,0));
    M.AddElement('BEAM3D',[1,2],0,0,0,0,0);
    F:=TResultField.Create('TEST','Test field','unit',rlNode);
    try
      SetLength(F.EntityIDs,2); SetLength(F.Values,2);
      F.EntityIDs[0]:=1; F.Values[0]:=0;
      F.EntityIDs[1]:=2; F.Values[1]:=100;
      Scene:=TResultVisualisationAdapter.BuildElementContourScene(M,nil,F,False,1,0,100);
      try
        Check(Scene.SegmentCount=1,'one beam produces one contour segment');
        Check(Abs(Scene.Segment(0).V1-0)<1E-12,'first nodal value preserved');
        Check(Abs(Scene.Segment(0).V2-100)<1E-12,'second nodal value preserved');
        Check(Scene.LegendCount=9,'default legend contains nine bands');
      finally Scene.Free end;
      D:=TResultVisualisationAdapter.BuildBeamDiagram(M,nil,F,1);
      try
        Check(D.Count=2,'beam diagram contains two endpoints');
        Check(Abs(D.Point(1).Value-100)<1E-12,'beam diagram endpoint value preserved');
      finally D.Free end;
    finally F.Free end;
  finally M.Free end;
  Writeln('PASS: result visualisation adapter tests');
end.
