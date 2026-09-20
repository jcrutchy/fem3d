unit fem_validate;

{$mode objfpc}{$H+}

interface

uses
  fem_types, fem_index, Classes, SysUtils, Generics.Collections;

// Returns a list of human-readable error strings. Empty list = valid model.
// Pure function: does not mutate Model, does not touch stdout/stderr.
function ValidateModel(const Model: TModel): TStringList;

const
  SupportedElementTypes: array[0..1] of string = ('truss', 'beam');

implementation

function IsSupportedElementType(const T: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(SupportedElementTypes) do
    if SupportedElementTypes[i] = T then
    begin
      Result := True;
      Exit;
    end;
end;

function NodesPerElementType(const T: string): Integer;
begin
  if (T = 'truss') or (T = 'beam') then Result := 2
  else Result := 0;
end;

function ValidateModel(const Model: TModel): TStringList;
var
  Errs: TStringList;
  NodeIdx, MatIdx, PropIdx, ElemIdx: TIntIntMap;
  NodeDofCounts: TIntArray;
  i, j, expectedNodes, nIdx, dofOff, matI, fc, lc, c: Integer;
  el: TElement;
  prop: TProperty;
  comb: TCombination;
  hasConstraint, usesBeam: Boolean;
  refDx, refDy, refDz, refLen, cosAngle, ax, ay, az, aLen: Double;
  n1, n2: TNode;
  FreedomCaseIds, LoadCaseIds: TStringList;
begin
  Errs := TStringList.Create;

  // --- nodes ---
  if Length(Model.Nodes) = 0 then
    Errs.Add('Model has no nodes');

  NodeIdx := IndexNodes(Model);
  if NodeIdx.Count <> Length(Model.Nodes) then
    Errs.Add('Duplicate node ids found');

  // --- materials ---
  MatIdx := IndexMaterials(Model);
  if MatIdx.Count <> Length(Model.Materials) then
    Errs.Add('Duplicate material ids found');
  for i := 0 to High(Model.Materials) do
  begin
    if Model.Materials[i].E <= 0 then
      Errs.Add(Format('Material %d: E must be positive', [Model.Materials[i].Id]));
    if Model.Materials[i].HasNu and ((Model.Materials[i].Nu <= -1.0) or (Model.Materials[i].Nu >= 0.5)) then
      Errs.Add(Format('Material %d: nu (Poisson''s ratio) must be in (-1, 0.5), got %g',
        [Model.Materials[i].Id, Model.Materials[i].Nu]));
    if Model.Materials[i].HasRho and (Model.Materials[i].Rho <= 0) then
      Errs.Add(Format('Material %d: rho (density) must be positive, got %g',
        [Model.Materials[i].Id, Model.Materials[i].Rho]));
  end;

  // --- properties ---
  PropIdx := IndexProperties(Model);
  if PropIdx.Count <> Length(Model.Properties) then
    Errs.Add('Duplicate property ids found');
  for i := 0 to High(Model.Properties) do
  begin
    prop := Model.Properties[i];
    if not IsSupportedElementType(prop.ElementType) then
      Errs.Add(Format('Property %d: unsupported element type "%s"', [prop.Id, prop.ElementType]))
    else
    begin
      if prop.Area <= 0 then
        Errs.Add(Format('Property %d: area must be positive', [prop.Id]));
      if prop.ElementType = 'beam' then
      begin
        if prop.Iy <= 0 then
          Errs.Add(Format('Property %d: Iy must be positive for a beam', [prop.Id]));
        if prop.Iz <= 0 then
          Errs.Add(Format('Property %d: Iz must be positive for a beam', [prop.Id]));
        if prop.J <= 0 then
          Errs.Add(Format('Property %d: J (torsion constant) must be positive for a beam', [prop.Id]));
        if MatIdx.TryGetValue(prop.MaterialId, matI) and not Model.Materials[matI].HasNu then
          Errs.Add(Format('Property %d: beam requires its material (%d) to specify nu (Poisson''s ratio), used to derive the shear modulus G',
            [prop.Id, prop.MaterialId]));
      end;
    end;
    if not MatIdx.ContainsKey(prop.MaterialId) then
      Errs.Add(Format('Property %d: references unknown material %d', [prop.Id, prop.MaterialId]));
  end;

  // --- elements ---
  ElemIdx := IndexElements(Model);
  if ElemIdx.Count <> Length(Model.Elements) then
    Errs.Add('Duplicate element ids found');
  usesBeam := False;
  for i := 0 to High(Model.Elements) do
  begin
    el := Model.Elements[i];
    if not IsSupportedElementType(el.ElementType) then
      Errs.Add(Format('Element %d: unsupported element type "%s"', [el.Id, el.ElementType]))
    else
    begin
      expectedNodes := NodesPerElementType(el.ElementType);
      if Length(el.NodeIds) <> expectedNodes then
        Errs.Add(Format('Element %d: type "%s" requires %d node(s), got %d',
          [el.Id, el.ElementType, expectedNodes, Length(el.NodeIds)]));
      if el.ElementType = 'beam' then usesBeam := True;
    end;
    for j := 0 to High(el.NodeIds) do
      if not NodeIdx.ContainsKey(el.NodeIds[j]) then
        Errs.Add(Format('Element %d: references unknown node %d', [el.Id, el.NodeIds[j]]));
    if not PropIdx.ContainsKey(el.PropertyId) then
      Errs.Add(Format('Element %d: references unknown property %d', [el.Id, el.PropertyId]));

    // Beam orientation: an explicit refVec (or, if none given, global Z /
    // falling back to X) must not be (near-)parallel to the beam axis --
    // that's degenerate, there'd be no way to fix the beam's roll.
    if (el.ElementType = 'beam') and (Length(el.NodeIds) = 2)
       and NodeIdx.ContainsKey(el.NodeIds[0]) and NodeIdx.ContainsKey(el.NodeIds[1]) then
    begin
      n1 := Model.Nodes[NodeIdx[el.NodeIds[0]]];
      n2 := Model.Nodes[NodeIdx[el.NodeIds[1]]];
      ax := n2.X - n1.X; ay := n2.Y - n1.Y; az := n2.Z - n1.Z;
      aLen := Sqrt(ax * ax + ay * ay + az * az);
      if aLen > 0 then
      begin
        if el.HasRefVec then
        begin
          refDx := el.RefVec[0]; refDy := el.RefVec[1]; refDz := el.RefVec[2];
          if (refDx = 0) and (refDy = 0) and (refDz = 0) then
            Errs.Add(Format('Element %d: refVec must not be the zero vector', [el.Id]))
          else
          begin
            refLen := Sqrt(refDx * refDx + refDy * refDy + refDz * refDz);
            cosAngle := Abs((ax * refDx + ay * refDy + az * refDz) / (aLen * refLen));
            if cosAngle > 0.999 then
              Errs.Add(Format('Element %d: refVec is (near-)parallel to the beam axis -- cannot fix its roll orientation', [el.Id]));
          end;
        end;
      end;
    end;
  end;

  // --- per-node dof counts (needs element types/refs above, but tolerates errors) ---
  NodeDofCounts := ComputeNodeDofCounts(Model, NodeIdx);

  // --- freedom cases ---
  if Length(Model.FreedomCases) = 0 then
    Errs.Add('Model has no freedom cases'); // the loader always produces at least one; this would mean a bug upstream
  FreedomCaseIds := TStringList.Create;
  FreedomCaseIds.Sorted := True;
  FreedomCaseIds.Duplicates := dupIgnore;
  for fc := 0 to High(Model.FreedomCases) do
  begin
    if Model.FreedomCases[fc].Id = '' then
      Errs.Add(Format('Freedom case %d: missing "id"', [fc]));
    if FreedomCaseIds.IndexOf(Model.FreedomCases[fc].Id) >= 0 then
      Errs.Add(Format('Duplicate freedom case id "%s"', [Model.FreedomCases[fc].Id]))
    else
      FreedomCaseIds.Add(Model.FreedomCases[fc].Id);

    hasConstraint := Length(Model.FreedomCases[fc].Constraints) > 0;
    for i := 0 to High(Model.FreedomCases[fc].Constraints) do
    begin
      dofOff := DofOffset(Model.FreedomCases[fc].Constraints[i].Dof);
      if not NodeIdx.TryGetValue(Model.FreedomCases[fc].Constraints[i].NodeId, nIdx) then
        Errs.Add(Format('Freedom case "%s", constraint %d: references unknown node %d',
          [Model.FreedomCases[fc].Id, i, Model.FreedomCases[fc].Constraints[i].NodeId]))
      else if dofOff >= 0 then
      begin
        if dofOff >= NodeDofCounts[nIdx] then
          Errs.Add(Format('Freedom case "%s", constraint %d: dof "%s" is rotational, but node %d has no rotational dof (not connected to any beam element)',
            [Model.FreedomCases[fc].Id, i, Model.FreedomCases[fc].Constraints[i].Dof, Model.FreedomCases[fc].Constraints[i].NodeId]));
      end;
      if dofOff < 0 then
        Errs.Add(Format('Freedom case "%s", constraint %d: dof must be one of x,y,z,rx,ry,rz, got "%s"',
          [Model.FreedomCases[fc].Id, i, Model.FreedomCases[fc].Constraints[i].Dof]));
    end;
    if not hasConstraint then
      Errs.Add(Format('Freedom case "%s" has no constraints -- system would be singular (unconstrained rigid-body motion)',
        [Model.FreedomCases[fc].Id]));
  end;

  // --- load cases ---
  LoadCaseIds := TStringList.Create;
  LoadCaseIds.Sorted := True;
  LoadCaseIds.Duplicates := dupIgnore;
  for lc := 0 to High(Model.LoadCases) do
  begin
    if Model.LoadCases[lc].Id = '' then
      Errs.Add(Format('Load case %d: missing "id"', [lc]));
    if LoadCaseIds.IndexOf(Model.LoadCases[lc].Id) >= 0 then
      Errs.Add(Format('Duplicate load case id "%s"', [Model.LoadCases[lc].Id]))
    else
      LoadCaseIds.Add(Model.LoadCases[lc].Id);

    for i := 0 to High(Model.LoadCases[lc].Loads) do
    begin
      dofOff := DofOffset(Model.LoadCases[lc].Loads[i].Dof);
      if not NodeIdx.TryGetValue(Model.LoadCases[lc].Loads[i].NodeId, nIdx) then
        Errs.Add(Format('Load case "%s", load %d: references unknown node %d',
          [Model.LoadCases[lc].Id, i, Model.LoadCases[lc].Loads[i].NodeId]))
      else if dofOff >= 0 then
      begin
        if dofOff >= NodeDofCounts[nIdx] then
          Errs.Add(Format('Load case "%s", load %d: dof "%s" is rotational, but node %d has no rotational dof (not connected to any beam element)',
            [Model.LoadCases[lc].Id, i, Model.LoadCases[lc].Loads[i].Dof, Model.LoadCases[lc].Loads[i].NodeId]));
      end;
      if dofOff < 0 then
        Errs.Add(Format('Load case "%s", load %d: dof must be one of x,y,z,rx,ry,rz, got "%s"',
          [Model.LoadCases[lc].Id, i, Model.LoadCases[lc].Loads[i].Dof]));
    end;
  end;

  // --- combinations ---
  for c := 0 to High(Model.Combinations) do
  begin
    comb := Model.Combinations[c];
    if comb.Id = '' then
      Errs.Add(Format('Combination %d: missing "id"', [c]));
    if comb.FreedomCaseId = '' then
    begin
      if Length(Model.FreedomCases) <> 1 then
        Errs.Add(Format('Combination "%s": "freedomCase" is required when the model has more than one freedom case',
          [comb.Id]));
      // else: resolved to the model's sole freedom case by whichever solver runs it
    end
    else if FreedomCaseIds.IndexOf(comb.FreedomCaseId) < 0 then
      Errs.Add(Format('Combination "%s": references unknown freedom case "%s"', [comb.Id, comb.FreedomCaseId]));

    if Length(comb.Terms) = 0 then
      Errs.Add(Format('Combination "%s" has no terms', [comb.Id]));
    for i := 0 to High(comb.Terms) do
      if LoadCaseIds.IndexOf(comb.Terms[i].LoadCaseId) < 0 then
        Errs.Add(Format('Combination "%s": term %d references unknown load case "%s"',
          [comb.Id, i, comb.Terms[i].LoadCaseId]));
  end;

  FreedomCaseIds.Free;
  LoadCaseIds.Free;
  NodeIdx.Free;
  MatIdx.Free;
  PropIdx.Free;
  ElemIdx.Free;

  Result := Errs;
end;

end.
