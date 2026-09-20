unit FEMBeamMesher;
{$mode objfpc}{$H+}

interface

uses SysUtils, Math, FEMTypes, FEMModel, FEMModelEditor;

type
  TBeamMeshOptions = record
    MaximumElementLength: Double;
  end;

  TBeamMeshResult = record
    Success: Boolean;
    Segments: Integer;
    CreatedNodes: Integer;
    CreatedElements: Integer;
  end;

  TBeamMesher = class
  public
    class function MeshBeamByMaximumLength(
      Model: TFEMModel;
      Editor: TModelEditor;
      ElementID: Integer;
      const Options: TBeamMeshOptions
    ): TBeamMeshResult;
  end;

implementation

class function TBeamMesher.MeshBeamByMaximumLength(
  Model: TFEMModel;
  Editor: TModelEditor;
  ElementID: Integer;
  const Options: TBeamMeshOptions
): TBeamMeshResult;
var
  I,A,B: Integer;
  L: Double;
begin
  Result.Success:=False;
  Result.Segments:=0;
  Result.CreatedNodes:=0;
  Result.CreatedElements:=0;

  if (Model=nil) or (Editor=nil) or
     (Options.MaximumElementLength<=0) then
    Exit;

  I:=-1;

  for A:=0 to High(Model.Elements) do
    if Model.Elements[A].ID=ElementID then begin
      I:=A;
      Break;
    end;

  if I<0 then Exit;

  if (Length(Model.Elements[I].NodeIDs)<>2) or
     (not SameText(Model.Elements[I].Kind,'BEAM3D')) then
    Exit;

  A:=Model.FindNode(Model.Elements[I].NodeIDs[0]);
  B:=Model.FindNode(Model.Elements[I].NodeIDs[1]);

  if (A<0) or (B<0) then Exit;

  L:=VNorm(
    VSub(
      Model.Nodes[B].Position,
      Model.Nodes[A].Position
    )
  );

  if L<=1e-12 then Exit;

  Result.Segments:=Max(
    1,
    Ceil(L/Options.MaximumElementLength)
  );

  if Result.Segments=1 then begin
    Result.CreatedElements:=1;
    Result.Success:=True;
    Exit;
  end;

  Result.Success:=Editor.SubdivideElement(
    ElementID,
    Result.Segments,
    Result.CreatedNodes,
    Result.CreatedElements
  );
end;

end.
