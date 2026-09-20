unit fem_native_writer;

{$mode objfpc}{$H+}

interface

uses
  fem_types, SysUtils, Classes;

// Writes Model in the compact native format (see docs/native_format.md)
// to Stream.
procedure WriteModelToStream(const Model: TModel; Stream: TStream);
procedure WriteModelToFile(const Model: TModel; const FileName: string);

implementation

var
  GFS: TFormatSettings;

function D2S(V: Double): string;
begin
  Result := FloatToStr(V, GFS);
end;

function OptD(HasIt: Boolean; V: Double): string;
begin
  if HasIt then Result := D2S(V) else Result := '-';
end;

procedure WriteModelToStream(const Model: TModel; Stream: TStream);
var
  SL: TStringList;
  i, j: Integer;
  el: TElement;
  fc: TFreedomCase;
  lc: TLoadCase;
  comb: TCombination;
  termsStr: string;
begin
  GFS := DefaultFormatSettings;
  GFS.DecimalSeparator := '.';

  SL := TStringList.Create;
  try
    SL.Add('# FreePascal FEM Suite - native model format');
    SL.Add('[HEADER]');
    if Model.SolverName <> '' then SL.Add('Solver=' + Model.SolverName);
    if Model.Units <> '' then SL.Add('Units=' + Model.Units);
    SL.Add('');

    SL.Add('[NODES]');
    SL.Add('# id, x, y, z');
    for i := 0 to High(Model.Nodes) do
      SL.Add(Format('%d, %s, %s, %s',
        [Model.Nodes[i].Id, D2S(Model.Nodes[i].X), D2S(Model.Nodes[i].Y), D2S(Model.Nodes[i].Z)]));
    SL.Add('');

    SL.Add('[MATERIALS]');
    SL.Add('# id, E, nu, rho');
    for i := 0 to High(Model.Materials) do
      SL.Add(Format('%d, %s, %s, %s',
        [Model.Materials[i].Id, D2S(Model.Materials[i].E),
         OptD(Model.Materials[i].HasNu, Model.Materials[i].Nu),
         OptD(Model.Materials[i].HasRho, Model.Materials[i].Rho)]));
    SL.Add('');

    SL.Add('[PROPERTIES]');
    SL.Add('# id, type, material, area[, Iy, Iz, J]');
    for i := 0 to High(Model.Properties) do
    begin
      if Model.Properties[i].ElementType = 'beam' then
        SL.Add(Format('%d, %s, %d, %s, %s, %s, %s',
          [Model.Properties[i].Id, Model.Properties[i].ElementType, Model.Properties[i].MaterialId,
           D2S(Model.Properties[i].Area), D2S(Model.Properties[i].Iy),
           D2S(Model.Properties[i].Iz), D2S(Model.Properties[i].J)]))
      else
        SL.Add(Format('%d, %s, %d, %s',
          [Model.Properties[i].Id, Model.Properties[i].ElementType, Model.Properties[i].MaterialId,
           D2S(Model.Properties[i].Area)]));
    end;
    SL.Add('');

    SL.Add('[ELEMENTS]');
    SL.Add('# id, type, node1, node2, property[, refX, refY, refZ]');
    for i := 0 to High(Model.Elements) do
    begin
      el := Model.Elements[i];
      if el.HasRefVec then
        SL.Add(Format('%d, %s, %d, %d, %d, %s, %s, %s',
          [el.Id, el.ElementType, el.NodeIds[0], el.NodeIds[1], el.PropertyId,
           D2S(el.RefVec[0]), D2S(el.RefVec[1]), D2S(el.RefVec[2])]))
      else
        SL.Add(Format('%d, %s, %d, %d, %d',
          [el.Id, el.ElementType, el.NodeIds[0], el.NodeIds[1], el.PropertyId]));
    end;
    SL.Add('');

    for i := 0 to High(Model.FreedomCases) do
    begin
      fc := Model.FreedomCases[i];
      SL.Add(Format('[FREEDOMCASE %s]', [fc.Id]));
      SL.Add('# node, dof, value');
      for j := 0 to High(fc.Constraints) do
        SL.Add(Format('%d, %s, %s',
          [fc.Constraints[j].NodeId, fc.Constraints[j].Dof, D2S(fc.Constraints[j].Value)]));
      SL.Add('');
    end;

    for i := 0 to High(Model.LoadCases) do
    begin
      lc := Model.LoadCases[i];
      SL.Add(Format('[LOADCASE %s]', [lc.Id]));
      SL.Add('# node, dof, value');
      for j := 0 to High(lc.Loads) do
        SL.Add(Format('%d, %s, %s',
          [lc.Loads[j].NodeId, lc.Loads[j].Dof, D2S(lc.Loads[j].Value)]));
      SL.Add('');
    end;

    for i := 0 to High(Model.Combinations) do
    begin
      comb := Model.Combinations[i];
      SL.Add(Format('[COMBINATION %s]', [comb.Id]));
      if comb.FreedomCaseId <> '' then
        SL.Add('FreedomCase=' + comb.FreedomCaseId);
      termsStr := '';
      for j := 0 to High(comb.Terms) do
      begin
        if j > 0 then termsStr := termsStr + ',';
        termsStr := termsStr + comb.Terms[j].LoadCaseId + ':' + D2S(comb.Terms[j].Factor);
      end;
      SL.Add('Terms=' + termsStr);
      SL.Add('');
    end;

    if (Model.SolverParams.Tolerance <> 1e-9) or Model.SolverParams.HasResultsFile then
    begin
      SL.Add('[SOLVERPARAMS]');
      SL.Add('Tolerance=' + D2S(Model.SolverParams.Tolerance));
      if Model.SolverParams.HasResultsFile then
        SL.Add('ResultsFile=' + Model.SolverParams.ResultsFile);
    end;

    SL.LineBreak := #10;
    SL.SaveToStream(Stream);
  finally
    SL.Free;
  end;
end;

procedure WriteModelToFile(const Model: TModel; const FileName: string);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(FileName, fmCreate);
  try
    WriteModelToStream(Model, FS);
  finally
    FS.Free;
  end;
end;

end.
