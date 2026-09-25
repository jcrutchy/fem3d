program modal;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Generics.Collections, Math,
  fem_types, fem_native_model, fem_validate, fem_index, fem_dofmap, fem_eigen, fem_elements;

const
  ExitOk           = 0;
  ExitUsage        = 1;
  ExitLoadError    = 2;
  ExitInvalidModel = 3;
  ExitSolverError  = 4;
  DofNames: array[0..5] of string = ('x', 'y', 'z', 'rx', 'ry', 'rz');

var
  ModelFile: string;
  Model: TModel;
  Errors: TStringList;
  NodeIdx, MatIdx, PropIdx: TIntIntMap;
  FS: TFormatSettings;

  DofMap: TDofMap;
  ElementEqLists: array of TIntArray;
  ElementGDofs: array of TIntArray;

  MassLumped: TDoubleArray; // [1..NDOF], lumped translational mass per global dof (0 for rotational -- see below)

procedure Fail(Code: Integer; const Msg: string);
begin
  WriteLn(StdErr, Msg);
  Halt(Code);
end;

function ElementGlobalDofs(const el: TElement): TIntArray;
begin
  Result := fem_dofmap.ElementGlobalDofs(DofMap, NodeIdx, el);
end;

// Lumped mass: half the element's total mass to each end node's 3
// translational dofs. Rotational dofs get no mass contribution here --
// proper rotary-inertia lumping for beams isn't implemented yet (it needs
// section data this suite doesn't model), so a beam model only works with
// this solver if its rotational dofs end up fixed rather than free; see
// the check after assembly below, and docs/model_format.md.
procedure AddElementMass(const el: TElement);
var
  prop: TProperty;
  mat: TMaterial;
  n1, n2: TNode;
  L, halfMass: Double;
  nIdx1, nIdx2, k: Integer;
begin
  if (el.ElementType <> 'truss') and (el.ElementType <> 'beam') then
    raise Exception.CreateFmt(
      'modal does not yet support element type "%s" (element %d) -- no mass matrix ' +
      'is implemented for it (this solver''s lumped-mass formula assumes a 2-node line ' +
      'element''s length and cross-sectional area). Avoid modal analysis on models ' +
      'containing this element type for now.', [el.ElementType, el.Id]);
  prop := Model.Properties[PropIdx[el.PropertyId]];
  mat := Model.Materials[MatIdx[prop.MaterialId]];
  n1 := Model.Nodes[NodeIdx[el.NodeIds[0]]];
  n2 := Model.Nodes[NodeIdx[el.NodeIds[1]]];
  L := Sqrt(Sqr(n2.X - n1.X) + Sqr(n2.Y - n1.Y) + Sqr(n2.Z - n1.Z));
  halfMass := 0.5 * mat.Rho * prop.Area * L;
  nIdx1 := NodeIdx[el.NodeIds[0]];
  nIdx2 := NodeIdx[el.NodeIds[1]];
  for k := 0 to 2 do // translational dofs only
  begin
    MassLumped[fem_dofmap.GlobalDof(DofMap, nIdx1, k)] := MassLumped[fem_dofmap.GlobalDof(DofMap, nIdx1, k)] + halfMass;
    MassLumped[fem_dofmap.GlobalDof(DofMap, nIdx2, k)] := MassLumped[fem_dofmap.GlobalDof(DofMap, nIdx2, k)] + halfMass;
  end;
end;

var
  i, j, ei, N, nModes: Integer;
  gd: TIntArray;
  el: TElement;
  eq_i, eq_j, gi, gj: Integer;
  Klocal: TElemMatrix;
  Kff: TDenseMatrix;
  Dsqrt: TDoubleArray; // [1..NEQ], sqrt(mass) per free dof, D in Kmass = D^-1 Kff D^-1
  Kmass: TDenseMatrix; // mass-normalized stiffness
  EigVals: TDoubleArray;
  EigVecs: TDenseMatrix;
  omega, freq: Double;
  massedDof: TDoubleArray; // [1..NEQ] free-dof mass, from MassLumped
  usedMaterialIds: TIntIntMap;
  matI: Integer;
  fcIdx: Integer;
  FC: TFreedomCase;
  UseBareKeys: Boolean;
  KeyPrefix: string;
  OutF: Text;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

  // ---- 1. CLI ----
  if ParamCount <> 1 then
    Fail(ExitUsage, 'Usage: modal <model.fem | ->' + LineEnding +
      '  Reads a FEM model file (or "-" for stdin), runs a lumped-mass modal' + LineEnding +
      '  analysis (Jacobi eigensolve), and writes natural frequencies and mode' + LineEnding +
      '  shapes to stdout.');
  ModelFile := ParamStr(1);

  // ---- 2. Load ----
  try
    if ModelFile = '-' then
      Model := LoadModelFromStdin
    else
      Model := LoadModelFromFile(ModelFile);
  except
    on E: Exception do
      Fail(ExitLoadError, Format('Could not load model file "%s": %s', [ModelFile, E.Message]));
  end;

  // ---- 3. Shared validation ----
  Errors := ValidateModel(Model);
  if Errors.Count > 0 then
  begin
    WriteLn(StdErr, Format('Model "%s" failed validation (%d error(s)):', [ModelFile, Errors.Count]));
    for i := 0 to Errors.Count - 1 do
      WriteLn(StdErr, '  - ' + Errors[i]);
    Errors.Free;
    Halt(ExitInvalidModel);
  end;
  Errors.Free;

  NodeIdx := IndexNodes(Model);
  MatIdx := IndexMaterials(Model);
  PropIdx := IndexProperties(Model);

  // ---- 4. modal-specific checks (not universal model validity, so not in fem_validate) ----
  // (a) every material actually used by an element must specify rho --
  //     mass is only meaningful to a solver that needs it, so this isn't
  //     a blanket requirement on every model, just on models run through
  //     this solver.
  usedMaterialIds := TIntIntMap.Create;
  try
    for i := 0 to High(Model.Elements) do
    begin
      matI := MatIdx[Model.Properties[PropIdx[Model.Elements[i].PropertyId]].MaterialId];
      usedMaterialIds.TryAdd(Model.Materials[matI].Id, matI);
    end;
    for matI in usedMaterialIds.Values do
      if not Model.Materials[matI].HasRho then
        Fail(ExitInvalidModel, Format(
          'Material %d is used by an element but has no rho (density) -- modal analysis needs mass, which linstatic never required, so this is checked here rather than by the shared validator',
          [Model.Materials[matI].Id]));
  finally
    usedMaterialIds.Free;
  end;

  // (b) a non-zero prescribed constraint doesn't mean anything for an
  //     eigenvalue extraction (there's no "applied displacement" concept
  //     here, only fixed vs free) -- check every freedom case
  for fcIdx := 0 to High(Model.FreedomCases) do
    for i := 0 to High(Model.FreedomCases[fcIdx].Constraints) do
      if Model.FreedomCases[fcIdx].Constraints[i].Value <> 0.0 then
        Fail(ExitInvalidModel, Format(
          'Freedom case "%s": constraint on node %d, dof "%s" has a non-zero prescribed value (%g) -- modal analysis only supports fixed (zero) constraints',
          [Model.FreedomCases[fcIdx].Id, Model.FreedomCases[fcIdx].Constraints[i].NodeId,
           Model.FreedomCases[fcIdx].Constraints[i].Dof, Model.FreedomCases[fcIdx].Constraints[i].Value]));

  UseBareKeys := Length(Model.FreedomCases) = 1;

  if Model.SolverParams.HasResultsFile then
  begin
    AssignFile(OutF, Model.SolverParams.ResultsFile);
    Rewrite(OutF);
  end
  else
    OutF := Output;

  // ---- 5-9. One pass per freedom case: dof map, mass+stiffness, eigensolve, output ----
  // Modal analysis has no load cases (the eigenproblem is homogeneous), so
  // unlike linstatic this only loops over freedom cases, not load cases too.
  for fcIdx := 0 to High(Model.FreedomCases) do
  begin
    FC := Model.FreedomCases[fcIdx];
    if UseBareKeys then KeyPrefix := '' else KeyPrefix := FC.Id + '.';

    DofMap := BuildDofMap(Model, NodeIdx, FC.Constraints);
    if DofMap.NEQ = 0 then
      Fail(ExitInvalidModel, Format('Freedom case "%s": every degree of freedom is constrained -- nothing to solve', [FC.Id]));

    SetLength(ElementEqLists, Length(Model.Elements));
    SetLength(ElementGDofs, Length(Model.Elements));
    for ei := 0 to High(Model.Elements) do
    begin
      el := Model.Elements[ei];
      gd := ElementGlobalDofs(el);
      ElementGDofs[ei] := gd;
      N := High(gd);
      SetLength(ElementEqLists[ei], N);
      for j := 1 to N do
        ElementEqLists[ei][j - 1] := DofMap.GlobalToEq[gd[j]];
    end;

    // ---- Assemble dense free-free stiffness (Jacobi needs a dense matrix; no skyline sparsity exploited here) ----
    Kff := NewDenseMatrix(DofMap.NEQ);
    try
      for ei := 0 to High(Model.Elements) do
      begin
        el := Model.Elements[ei];
        Klocal := ElementStiffnessFor(Model, NodeIdx, MatIdx, PropIdx, el);
        gd := ElementGDofs[ei];
        N := High(gd);
        for i := 1 to N do
          for j := 1 to N do
          begin
            if Klocal[i][j] = 0.0 then Continue;
            gi := gd[i]; gj := gd[j];
            eq_i := DofMap.GlobalToEq[gi]; eq_j := DofMap.GlobalToEq[gj];
            if (eq_i > 0) and (eq_j > 0) then
              Kff[eq_i][eq_j] := Kff[eq_i][eq_j] + Klocal[i][j];
            // constrained rows/cols simply don't enter Kff -- consistent with
            // requiring all constraints to be zero (checked above), so there's
            // no RHS-folding needed the way linstatic needs it for non-zero
            // prescribed displacements.
          end;
      end;
    except
      on E: Exception do
        Fail(ExitSolverError, Format('Freedom case "%s": assembly error: %s', [FC.Id, E.Message]));
    end;

    // ---- Lumped mass ----
    SetLength(MassLumped, DofMap.NDOF + 1);
    for i := 1 to DofMap.NDOF do MassLumped[i] := 0.0;
    try
      for ei := 0 to High(Model.Elements) do
        AddElementMass(Model.Elements[ei]);
    except
      on E: Exception do
        Fail(ExitInvalidModel, Format('Freedom case "%s": %s', [FC.Id, E.Message]));
    end;

    SetLength(massedDof, DofMap.NEQ + 1);
    for i := 1 to DofMap.NDOF do
      if DofMap.GlobalToEq[i] > 0 then
        massedDof[DofMap.GlobalToEq[i]] := MassLumped[i];

    for eq_i := 1 to DofMap.NEQ do
      if massedDof[eq_i] <= 0 then
      begin
        // find which (node, dof) this free equation corresponds to, for an actionable error
        for i := 1 to DofMap.NDOF do
          if DofMap.GlobalToEq[i] = eq_i then
          begin
            for j := 0 to High(Model.Nodes) do
              if fem_dofmap.GlobalDof(DofMap, j, 0) <= i then
                if i < fem_dofmap.GlobalDof(DofMap, j, 0) + DofMap.NodeDofCounts[j] then
                begin
                  Fail(ExitInvalidModel, Format(
                    'Freedom case "%s": free dof "%s" at node %d has zero lumped mass -- likely a rotational dof of a beam element ' +
                    '(rotary inertia lumping for beams isn''t implemented yet). Either constrain that dof or ' +
                    'avoid modal analysis on this model for now.',
                    [FC.Id, DofNames[i - fem_dofmap.GlobalDof(DofMap, j, 0)], Model.Nodes[j].Id]));
                end;
            Break;
          end;
      end;

    // ---- Reduce to a standard symmetric eigenproblem: Kmass = D^-1 Kff D^-1, D=diag(sqrt(M)) ----
    SetLength(Dsqrt, DofMap.NEQ + 1);
    for i := 1 to DofMap.NEQ do
      Dsqrt[i] := Sqrt(massedDof[i]);
    Kmass := NewDenseMatrix(DofMap.NEQ);
    for i := 1 to DofMap.NEQ do
      for j := 1 to DofMap.NEQ do
        Kmass[i][j] := Kff[i][j] / (Dsqrt[i] * Dsqrt[j]);

    try
      JacobiEigenSymmetric(Kmass, DofMap.NEQ, EigVals, EigVecs);
    except
      on E: Exception do
        Fail(ExitSolverError, Format('Freedom case "%s": %s', [FC.Id, E.Message]));
    end;

    // ---- Output ----
    // omega^2 = eigenvalue of the mass-normalized problem; mode shape in
    // physical (displacement) coordinates is D^-1 * eigenvector, then
    // normalized so phi^T M phi = 1 (mass-normalized, the standard modal
    // convention) -- D^-1*eigenvector is already exactly mass-normalized
    // since the reduction was symmetric (Kmass eigenvectors are orthonormal
    // in the Euclidean sense, and phi = D^-1 y => phi^T M phi = y^T y = 1).
    if fcIdx = 0 then
    begin
      WriteLn(OutF, '# FreePascal FEM Suite - modal (lumped-mass Jacobi eigensolver)');
      WriteLn(OutF, Format('# model=%s', [ModelFile]));
      WriteLn(OutF, Format('# nodes=%d elements=%d freedom_cases=%d',
        [Length(Model.Nodes), Length(Model.Elements), Length(Model.FreedomCases)]));
    end;
    nModes := DofMap.NEQ;
    for i := 1 to nModes do
    begin
      if EigVals[i] < 0 then
        Fail(ExitSolverError, Format(
          'Freedom case "%s": mode %d has a negative eigenvalue (omega^2 = %g) -- the free-free stiffness is not ' +
          'positive semi-definite; check the model for an unstable/mechanism sub-structure', [FC.Id, i, EigVals[i]]));
      omega := Sqrt(EigVals[i]);
      freq := omega / (2 * Pi);
      WriteLn(OutF, Format('%sMODE.%d.omega=%.17e', [KeyPrefix, i, omega], FS));
      WriteLn(OutF, Format('%sMODE.%d.freq=%.17e', [KeyPrefix, i, freq], FS));
      for j := 0 to High(Model.Nodes) do
        for eq_i := 0 to DofMap.NodeDofCounts[j] - 1 do
        begin
          gi := fem_dofmap.GlobalDof(DofMap, j, eq_i);
          eq_j := DofMap.GlobalToEq[gi];
          if eq_j > 0 then
            WriteLn(OutF, Format('%sMODE.%d.DISP.%d.%s=%.17e',
              [KeyPrefix, i, Model.Nodes[j].Id, DofNames[eq_i], EigVecs[eq_j][i] / Dsqrt[eq_j]], FS))
          else
            WriteLn(OutF, Format('%sMODE.%d.DISP.%d.%s=%.17e', [KeyPrefix, i, Model.Nodes[j].Id, DofNames[eq_i], 0.0], FS));
        end;
    end;
  end;

  NodeIdx.Free;
  MatIdx.Free;
  PropIdx.Free;
  if Model.SolverParams.HasResultsFile then
  begin
    CloseFile(OutF);
    WriteLn(Format('Results written to %s', [Model.SolverParams.ResultsFile]));
  end
  else
    Flush(OutF); // Halt() below can otherwise skip the buffer flush a normal exit would do
  Halt(ExitOk);
end.
