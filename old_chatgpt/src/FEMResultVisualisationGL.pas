unit FEMResultVisualisationGL;

{$mode objfpc}{$H+}

interface

uses
  OpenGL, FEMResultVisualisation;

type
  { Target adapter for the native OpenGL viewport.  It deliberately knows
    nothing about FEM models or result files; it consumes a visualisation
    scene produced by FEMResultVisualisation. }
  TGLResultVisualisationAdapter = class
  public
    class procedure DrawContourScene(Scene: TResultVisualisationScene;
      SelectedElementID: Integer = -1); static;
  end;

implementation

class procedure TGLResultVisualisationAdapter.DrawContourScene(
  Scene: TResultVisualisationScene; SelectedElementID: Integer);
var I: Integer; S: TResultContourSegment; C1,C2: TResultRGB;
begin
  if Scene=nil then Exit;
  glDisable(GL_LIGHTING);
  for I:=0 to Scene.SegmentCount-1 do begin
    S:=Scene.Segment(I);
    C1:=Scene.Mapper.Color(S.V1);
    C2:=Scene.Mapper.Color(S.V2);
    if S.ElementID=SelectedElementID then glLineWidth(5) else glLineWidth(2);
    glBegin(GL_LINES);
      glColor3d(C1.R,C1.G,C1.B);
      glVertex3d(S.P1.X,S.P1.Y,S.P1.Z);
      glColor3d(C2.R,C2.G,C2.B);
      glVertex3d(S.P2.X,S.P2.Y,S.P2.Z);
    glEnd;
  end;
end;

end.
