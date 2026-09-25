unit fem_validate;

{$mode objfpc}{$H+}

interface

uses
  fem_types, fem_index, Classes, SysUtils, Generics.Collections, Math;

// Returns a list of human-readable error strings. Empty list = valid model.
// Pure function: does not mutate Model, does not touch stdout/stderr.
function ValidateModel(const Model: TModel): TStringList;

const
  SupportedElementTypes: array[0..2] of string = ('truss', 'beam', 'shellq4');

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
  else if T = 'shellq4' then Result := 4
  else Result := 0;
end;

function ValidateModel(const Model: TModel): TStringList;
var
  Errs: TStringList;
  NodeIdx, MatIdx, PropIdx, ElemIdx: TIntIntMap;
  NodeDofCounts: TIntArray;
  i, j, expectedNodes, nIdx, dofOff, matI, propI, fc, lc, c: Integer;
  el: TElement;
  prop: TProperty;
  comb: TCombination;
  hasConstraint, usesBeam: Boolean;
  refDx, refDy, refDz, refLen, cosAngle, ax, ay, az, aLen: Double;
  n1, n2: TNode;
  n3, n4: TNode;
  e1x, e1y, e1z, e2x, e2y, e2z, e1Len, e2Len, nx, ny, nz, nLen: Double;
  charLen, d3x, d3y, d3z, outOfPlane: Double;
  FreedomCaseIds, LoadCaseIds: TStringList;
  SeenConstraintKeys: TStringList;
  constraintKey: string;

  // NaN and Infinity both fail every ordered comparison (NaN) or satisfy
  // a plain ">0" test (Infinity) -- so the existing "must be positive"
  // checks below do NOT reliably catch either one on their own (a NaN E
  // silently passes "E<=0" since NaN<=0 is false; an Infinite E silently
  // passes it too, since Infinity>0 is true). Call this alongside those
  // checks, not instead of them.
  procedure CheckFinite(v: Double; const Label_: string);
  begin
    if IsNan(v) then
      Errs.Add(Label_ + ' is NaN')
    else if IsInfinite(v) then
      Errs.Add(Label_ + ' is infinite');
  end;

begin
  Errs := TStringList.Create;

  // --- nodes ---
  if Length(Model.Nodes) = 0 then
    Errs.Add('Model has no nodes');

  NodeIdx := IndexNodes(Model);
  if NodeIdx.Count <> Length(Model.Nodes) then
    Errs.Add('Duplicate node ids found');
  for i := 0 to High(Model.Nodes) do
  begin
    CheckFinite(Model.Nodes[i].X, Format('Node %d: x', [Model.Nodes[i].Id]));
    CheckFinite(Model.Nodes[i].Y, Format('Node %d: y', [Model.Nodes[i].Id]));
    CheckFinite(Model.Nodes[i].Z, Format('Node %d: z', [Model.Nodes[i].Id]));
  end;

  // --- materials ---
  MatIdx := IndexMaterials(Model);
  if MatIdx.Count <> Length(Model.Materials) then
    Errs.Add('Duplicate material ids found');
  for i := 0 to High(Model.Materials) do
  begin
    CheckFinite(Model.Materials[i].E, Format('Material %d: E', [Model.Materials[i].Id]));
    if Model.Materials[i].HasNu then
      CheckFinite(Model.Materials[i].Nu, Format('Material %d: nu', [Model.Materials[i].Id]));
    if Model.Materials[i].HasRho then
      CheckFinite(Model.Materials[i].Rho, Format('Material %d: rho', [Model.Materials[i].Id]));
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
      if prop.ElementType = 'shellq4' then
      begin
        CheckFinite(prop.Thickness, Format('Property %d: thickness', [prop.Id]));
        if prop.Thickness <= 0 then
          Errs.Add(Format('Property %d: thickness must be positive for a shellq4', [prop.Id]));
        if MatIdx.TryGetValue(prop.MaterialId, matI) and not Model.Materials[matI].HasNu then
          Errs.Add(Format('Property %d: shellq4 requires its material (%d) to specify nu (Poisson''s ratio)',
            [prop.Id, prop.MaterialId]));
      end
      else
      begin
        CheckFinite(prop.Area, Format('Property %d: area', [prop.Id]));
        if prop.Area <= 0 then
          Errs.Add(Format('Property %d: area must be positive', [prop.Id]));
        if prop.ElementType = 'beam' then
        begin
          CheckFinite(prop.Iy, Format('Property %d: Iy', [prop.Id]));
          CheckFinite(prop.Iz, Format('Property %d: Iz', [prop.Id]));
          CheckFinite(prop.J, Format('Property %d: J', [prop.Id]));
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
      Errs.Add(Format('Element %d: references unknown property %d', [el.Id, el.PropertyId]))
    else if PropIdx.TryGetValue(el.PropertyId, propI)
       and (Model.Properties[propI].ElementType <> el.ElementType)
       and IsSupportedElementType(el.ElementType) then
      // Both types individually valid (or the "unsupported type" error above
      // already fired) but they don't match -- e.g. a beam element pointing
      // at a shellq4 property. Validating the property alone (area/Iy/Iz/J
      // vs. thickness) is not enough: ElementStiffnessFor dispatches on the
      // ELEMENT's type, so a mismatch here means whichever formulation runs
      // reads fields that were never validated for that formulation (a beam
      // reading an unvalidated, possibly-zero Area from a shellq4 property,
      // for instance) -- silently wrong, not rejected.
      Errs.Add(Format('Element %d: type "%s" does not match its property %d''s type "%s"',
        [el.Id, el.ElementType, el.PropertyId, Model.Properties[propI].ElementType]));

    // Shellq4 flatness: QuadShellStiffness3D builds its local plane from
    // nodes 1, 2, 4 (edges 1-2 and 1-4) and assumes node 3 lies in it --
    // a genuinely warped (non-planar) quad isn't representable by this
    // flat-shell formulation, so catch it here with an actionable message
    // rather than let it silently degrade accuracy or surface later as an
    // opaque assembly-time exception for a badly degenerate case.
    if (el.ElementType = 'shellq4') and (Length(el.NodeIds) = 4)
       and NodeIdx.ContainsKey(el.NodeIds[0]) and NodeIdx.ContainsKey(el.NodeIds[1])
       and NodeIdx.ContainsKey(el.NodeIds[2]) and NodeIdx.ContainsKey(el.NodeIds[3]) then
    begin
      n1 := Model.Nodes[NodeIdx[el.NodeIds[0]]];
      n2 := Model.Nodes[NodeIdx[el.NodeIds[1]]];
      n3 := Model.Nodes[NodeIdx[el.NodeIds[2]]];
      n4 := Model.Nodes[NodeIdx[el.NodeIds[3]]];
      e1x := n2.X-n1.X; e1y := n2.Y-n1.Y; e1z := n2.Z-n1.Z;
      e2x := n4.X-n1.X; e2y := n4.Y-n1.Y; e2z := n4.Z-n1.Z;
      e1Len := Sqrt(e1x*e1x + e1y*e1y + e1z*e1z);
      e2Len := Sqrt(e2x*e2x + e2y*e2y + e2z*e2z);
      if e1Len <= 0 then
        Errs.Add(Format('Element %d: shellq4 nodes 1 and 2 coincide (zero-length edge)', [el.Id]))
      else if e2Len <= 0 then
        Errs.Add(Format('Element %d: shellq4 nodes 1 and 4 coincide (zero-length edge)', [el.Id]))
      else
      begin
        // normal = edge1 x edge2 (unnormalized); zero => nodes 1,2,4 collinear
        nx := e1y*e2z - e1z*e2y;
        ny := e1z*e2x - e1x*e2z;
        nz := e1x*e2y - e1y*e2x;
        nLen := Sqrt(nx*nx + ny*ny + nz*nz);
        if nLen <= 0 then
          Errs.Add(Format('Element %d: shellq4 nodes 1, 2, and 4 are collinear (degenerate quad)', [el.Id]))
        else
        begin
          // signed distance of node 3 from the plane through node1 with
          // normal (nx,ny,nz)/nLen, relative to a characteristic length
          // (the longer of the two edges off node 1) so the tolerance
          // scales with element size rather than being an absolute unit.
          charLen := e1Len;
          if e2Len > charLen then charLen := e2Len;
          d3x := n3.X-n1.X; d3y := n3.Y-n1.Y; d3z := n3.Z-n1.Z;
          outOfPlane := Abs((d3x*nx + d3y*ny + d3z*nz) / nLen);
          if outOfPlane > 0.01 * charLen then
            Errs.Add(Format('Element %d: shellq4 is not flat -- node %d is %.4g%% of the element''s characteristic edge length out of the plane through nodes %d, %d, %d',
              [el.Id, el.NodeIds[2], 100.0*outOfPlane/charLen, el.NodeIds[0], el.NodeIds[1], el.NodeIds[3]]));
        end;
      end;
    end;

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
    SeenConstraintKeys := TStringList.Create;
    SeenConstraintKeys.Sorted := True;
    SeenConstraintKeys.Duplicates := dupIgnore;
    for i := 0 to High(Model.FreedomCases[fc].Constraints) do
    begin
      dofOff := DofOffset(Model.FreedomCases[fc].Constraints[i].Dof);
      CheckFinite(Model.FreedomCases[fc].Constraints[i].Value,
        Format('Freedom case "%s", constraint %d: value', [Model.FreedomCases[fc].Id, i]));
      if not NodeIdx.TryGetValue(Model.FreedomCases[fc].Constraints[i].NodeId, nIdx) then
        Errs.Add(Format('Freedom case "%s", constraint %d: references unknown node %d',
          [Model.FreedomCases[fc].Id, i, Model.FreedomCases[fc].Constraints[i].NodeId]))
      else if dofOff >= 0 then
      begin
        if dofOff >= NodeDofCounts[nIdx] then
          Errs.Add(Format('Freedom case "%s", constraint %d: dof "%s" is rotational, but node %d has no rotational dof (not connected to any beam element)',
            [Model.FreedomCases[fc].Id, i, Model.FreedomCases[fc].Constraints[i].Dof, Model.FreedomCases[fc].Constraints[i].NodeId]));
        // Duplicate (node,dof) constraint within this freedom case: the
        // loader just keeps whichever wins last in fem_dofmap.BuildDofMap,
        // silently -- two constraints on the same dof (even if identical)
        // almost always means a model-generation bug, so this is a hard
        // error, not a "last one wins" convenience.
        constraintKey := Format('%d:%d', [Model.FreedomCases[fc].Constraints[i].NodeId, dofOff]);
        if SeenConstraintKeys.IndexOf(constraintKey) >= 0 then
          Errs.Add(Format('Freedom case "%s": duplicate constraint on node %d, dof "%s"',
            [Model.FreedomCases[fc].Id, Model.FreedomCases[fc].Constraints[i].NodeId,
             Model.FreedomCases[fc].Constraints[i].Dof]))
        else
          SeenConstraintKeys.Add(constraintKey);
      end;
      if dofOff < 0 then
        Errs.Add(Format('Freedom case "%s", constraint %d: dof must be one of x,y,z,rx,ry,rz, got "%s"',
          [Model.FreedomCases[fc].Id, i, Model.FreedomCases[fc].Constraints[i].Dof]));
    end;
    SeenConstraintKeys.Free;
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
      CheckFinite(Model.LoadCases[lc].Loads[i].Value,
        Format('Load case "%s", load %d: value', [Model.LoadCases[lc].Id, i]));
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

  // --- solver params ---
  // The native parser already rejects a Tolerance that fails to parse as
  // a number at all (see fem_native_model's F2D-style strict parsing);
  // this catches the values that parse fine but aren't physically usable
  // -- 0, negative, NaN, or a magnitude so extreme it can only be a typo.
  if IsNan(Model.SolverParams.Tolerance) or IsInfinite(Model.SolverParams.Tolerance) then
    Errs.Add('SolverParams: Tolerance must be a finite number')
  else if Model.SolverParams.Tolerance <= 0 then
    Errs.Add(Format('SolverParams: Tolerance must be positive, got %g', [Model.SolverParams.Tolerance]))
  else if Model.SolverParams.Tolerance > 1.0 then
    Errs.Add(Format('SolverParams: Tolerance %g is implausibly large (expected roughly 1e-12 to 1e-3) -- likely a typo',
      [Model.SolverParams.Tolerance]))
  else if Model.SolverParams.Tolerance < 1.0E-15 then
    Errs.Add(Format('SolverParams: Tolerance %g is implausibly small (tighter than double-precision can resolve) -- likely a typo',
      [Model.SolverParams.Tolerance]));

  Result := Errs;
end;

end.
