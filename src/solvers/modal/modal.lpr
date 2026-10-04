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

function D2Str(V: Double; const Fmt: TFormatSettings): string;
begin
  Result := FloatToStr(V, Fmt);
end;

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
// translational dofs. Rotational dofs get no mass contribution here (no
// rotary inertia is modeled). A free rotational dof therefore has zero
// mass, which is handled EXACTLY -- not by fixing it -- by statically
// condensing every massless free dof out of the eigenproblem before the
// eigensolve; see the condensation block in the main program below and
// docs/modal.md.
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
  Dsqrt: TDoubleArray; // [1..nT], sqrt(mass) per massed free dof, D in Kmass = D^-1 Kc D^-1
  Kmass: TDenseMatrix; // mass-normalized (condensed) stiffness, nT x nT
  // Static condensation of massless free dofs: the free dofs split into
  // "t" (carry mass) and "r" (zero mass; e.g. beam rotations).
  nT, nR: Integer;
  tOfEq, rOfEq: array of Integer;      // [1..NEQ] -> index within t / r (0 if not in that set)
  eqOfT, eqOfR: array of Integer;      // inverse maps
  Ktt, Kxx, Xr: TDenseMatrix;           // Ktt (nT x nT); Kxx = Krr then its Cholesky factor; Xr = Krr^-1*Krt (nR x nT)
  Krt: TDenseMatrix;                    // nR x nT
  uT, uR: TDoubleArray;
  cholSum, cholMaxDiag: Double;
  kk: Integer;
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
  nTruss, nBeam, nOtherType: Integer;
  otherTypeSuffix: string;

// "dof "ry" at node 3" for a free equation number, for error messages.
function EqLabel(eq: Integer): string;
var
  gi, j, base: Integer;
begin
  Result := Format('equation %d', [eq]);
  for gi := 1 to DofMap.NDOF do
    if DofMap.GlobalToEq[gi] = eq then
      for j := 0 to High(Model.Nodes) do
      begin
        base := fem_dofmap.GlobalDof(DofMap, j, 0);
        if (gi >= base) and (gi < base + DofMap.NodeDofCounts[j]) then
          Result := Format('dof "%s" at node %d', [DofNames[gi - base], Model.Nodes[j].Id]);
      end;
end;

procedure PrintConstraintsBlock(const FC: TFreedomCase; const DMap: TDofMap);
var
  ii, jj, ggi, nConstrained: Integer;
begin
  nConstrained := DMap.NDOF - DMap.NEQ;
  WriteLn(OutF, Format('# Freedom case "%s": %d node(s), %d degree(s) of freedom total, '
    + '%d fixed, %d free -- modal analysis finds one mode per free dof that carries mass.',
    [FC.Id, Length(Model.Nodes), DMap.NDOF, nConstrained, DMap.NEQ]));
  if nConstrained = 0 then Exit;
  WriteLn(OutF, '#   Fixed dof (every constraint here is exactly zero -- modal only supports fixed, not prescribed-nonzero, checked above):');
  for ii := 0 to High(Model.Nodes) do
    for jj := 0 to DMap.NodeDofCounts[ii] - 1 do
    begin
      ggi := fem_dofmap.GlobalDof(DMap, ii, jj);
      if DMap.GlobalToEq[ggi] = 0 then
        WriteLn(OutF, Format('#     node %d, %s', [Model.Nodes[ii].Id, DofNames[jj]]));
    end;
end;

// Mass-orthonormality self-check: EigVecs' columns (from the
// mass-normalized, symmetric-reduced eigenproblem Kmass=D^-1*Kff*D^-1)
// should already be exactly orthonormal in the plain Euclidean sense --
// that's what a correct symmetric eigensolver guarantees, and it's also
// EXACTLY the physical mode-orthogonality condition phi_i^T*M*phi_j =
// delta_ij once mapped back through phi=D^-1*y (D^-1*M*D^-1=I by
// construction, so y_i^T*y_j = phi_i^T*M*phi_j identically). A nonzero
// off-diagonal or a diagonal far from 1 here means a genuine eigensolver
// bug, not a modeling issue -- the direct modal analog of linstatic's
// force-equilibrium check.
procedure PrintOrthonormalityCheck(const CaseLabel: string; const EigVecs: TDenseMatrix; NEQ: Integer);
var
  ii, jj, kk: Integer;
  dot, maxOffDiag, maxDiagErr: Double;
begin
  maxOffDiag := 0; maxDiagErr := 0;
  for ii := 1 to NEQ do
    for jj := ii to NEQ do
    begin
      dot := 0;
      for kk := 1 to NEQ do
        dot := dot + EigVecs[kk][ii] * EigVecs[kk][jj];
      if ii = jj then
      begin
        if Abs(dot - 1.0) > maxDiagErr then maxDiagErr := Abs(dot - 1.0);
      end
      else
        if Abs(dot) > maxOffDiag then maxOffDiag := Abs(dot);
    end;
  WriteLn(OutF, Format('# Mode mass-orthonormality check for %s (should be near-exact regardless of model):', [CaseLabel]));
  if (maxOffDiag <= 1.0E-6) and (maxDiagErr <= 1.0E-6) then
    WriteLn(OutF, Format('#   max |phi_i^T M phi_j|, i<>j = %s; max |phi_i^T M phi_i - 1| = %s -- OK',
      [D2Str(maxOffDiag, FS), D2Str(maxDiagErr, FS)]))
  else
    WriteLn(OutF, Format('#   max |phi_i^T M phi_j|, i<>j = %s; max |phi_i^T M phi_i - 1| = %s -- WARNING: not orthonormal, likely an eigensolver bug',
      [D2Str(maxOffDiag, FS), D2Str(maxDiagErr, FS)]));
end;
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

  WriteLn(OutF, '# FreePascal FEM Suite - modal (lumped-mass Jacobi eigensolver)');
  WriteLn(OutF, Format('# model=%s', [ModelFile]));
  WriteLn(OutF, Format('# nodes=%d elements=%d freedom_cases=%d',
    [Length(Model.Nodes), Length(Model.Elements), Length(Model.FreedomCases)]));
  // Ties these results to the exact model they were computed from; a viewer
  // recomputes it from the model file it is shown and flags any difference.
  // (Printed even with Verbose=0: it is data, not narration.)
  WriteLn(OutF, 'MODEL.FINGERPRINT=' + Model.Fingerprint);

  if Model.SolverParams.Verbose then
  begin
    nTruss := 0; nBeam := 0; nOtherType := 0;
    for i := 0 to High(Model.Elements) do
      if Model.Elements[i].ElementType = 'truss' then Inc(nTruss)
      else if Model.Elements[i].ElementType = 'beam' then Inc(nBeam)
      else Inc(nOtherType);
    if nOtherType > 0 then
      otherTypeSuffix := Format(', %d of a type modal does not support', [nOtherType])
    else
      otherTypeSuffix := '';
    WriteLn(OutF, '#');
    WriteLn(OutF, '# modal extracts natural frequencies and mode shapes: builds a lumped');
    WriteLn(OutF, '# (diagonal, translational-only) mass matrix alongside the usual');
    WriteLn(OutF, '# stiffness matrix, reduces the generalized eigenproblem K*phi=omega^2*M*phi');
    WriteLn(OutF, '# to a standard symmetric one, and solves it with a Jacobi eigensolver --');
    WriteLn(OutF, '# exact for the discretized (lumped-mass) model, not an approximation of');
    WriteLn(OutF, '# the solve itself. Rotary inertia isn''t modeled, so free rotational dof');
    WriteLn(OutF, '# (zero mass) are eliminated exactly by static condensation first; see');
    WriteLn(OutF, '# docs/modal.md.');
    WriteLn(OutF, Format('# %d material(s), %d propert(y/ies). Element types: %d truss, %d beam%s.',
      [Length(Model.Materials), Length(Model.Properties), nTruss, nBeam, otherTypeSuffix]));
    WriteLn(OutF, '# (Verbose=1 is the default; set Verbose=0 in [SOLVERPARAMS] for plain');
    WriteLn(OutF, '# key=value output only.)');
    WriteLn(OutF, '#');
  end;

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

    if Model.SolverParams.Verbose then
      PrintConstraintsBlock(FC, DofMap);

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

    // ---- Split the free dofs: "t" carry mass, "r" are massless ----
    // Lumped mass sits on translations only, so a beam's free rotations have
    // zero mass. They still have stiffness and must NOT be fixed (that would
    // change the structure). Because they carry no inertia, they can be
    // eliminated EXACTLY (no approximation, unlike Guyan reduction of massed
    // dofs): with K = [Ktt Ktr; Krt Krr] and M = [Mtt 0; 0 0],
    //     K*phi = w^2*M*phi   <=>   (Ktt - Ktr*Krr^-1*Krt)*phi_t = w^2*Mtt*phi_t
    // and the massless dofs follow statically: phi_r = -Krr^-1*Krt*phi_t.
    SetLength(tOfEq, DofMap.NEQ + 1);
    SetLength(rOfEq, DofMap.NEQ + 1);
    SetLength(eqOfT, DofMap.NEQ + 1);
    SetLength(eqOfR, DofMap.NEQ + 1);
    nT := 0; nR := 0;
    for eq_i := 1 to DofMap.NEQ do
      if massedDof[eq_i] > 0 then
      begin
        Inc(nT); tOfEq[eq_i] := nT; rOfEq[eq_i] := 0; eqOfT[nT] := eq_i;
      end
      else
      begin
        Inc(nR); rOfEq[eq_i] := nR; tOfEq[eq_i] := 0; eqOfR[nR] := eq_i;
      end;
    if nT = 0 then
      Fail(ExitInvalidModel, Format(
        'Freedom case "%s": no free dof carries any mass, so there is nothing to vibrate -- check that every ' +
        'material has a density (rho) and that the elements are not all fully restrained.', [FC.Id]));

    if (nR > 0) and Model.SolverParams.Verbose then
    begin
      WriteLn(OutF, Format('# %d of the %d free dof carry no mass (rotations -- rotary inertia is not modeled). They are', [nR, DofMap.NEQ]));
      WriteLn(OutF, '# eliminated exactly by static condensation, K_c = K_tt - K_tr*K_rr^-1*K_rt, before the');
      WriteLn(OutF, Format('# eigensolve (%d mode(s) result, one per massed dof); their mode-shape values are then', [nT]));
      WriteLn(OutF, '# recovered as phi_r = -K_rr^-1*K_rt*phi_t. Not an approximation: a dof with no inertia');
      WriteLn(OutF, '# is slaved statically to the others. (Torsion about a beam''s axis has no polar inertia');
      WriteLn(OutF, '# here either, so pure torsional vibration modes do not appear.)');
    end;

    // Partition the dense free-free stiffness.
    Ktt := NewDenseMatrix(nT);
    for i := 1 to nT do
      for j := 1 to nT do
        Ktt[i][j] := Kff[eqOfT[i]][eqOfT[j]];

    if nR > 0 then
    begin
      Kxx := NewDenseMatrix(nR);             // Krr, overwritten by its Cholesky factor
      SetLength(Krt, nR + 1);
      SetLength(Xr, nR + 1);
      for i := 1 to nR do
      begin
        SetLength(Krt[i], nT + 1);
        SetLength(Xr[i], nT + 1);
        for j := 1 to nT do
          Krt[i][j] := Kff[eqOfR[i]][eqOfT[j]];
        for j := 1 to nR do
          Kxx[i][j] := Kff[eqOfR[i]][eqOfR[j]];
      end;

      // Cholesky Krr = L*L^T (lower triangle of Kxx). Krr is symmetric
      // positive definite unless some massless dof is not restrained by
      // stiffness (a mechanism): then a pivot collapses -- reported by name.
      cholMaxDiag := 0.0;
      for i := 1 to nR do
        if Kxx[i][i] > cholMaxDiag then cholMaxDiag := Kxx[i][i];
      for j := 1 to nR do
      begin
        cholSum := Kxx[j][j];
        for kk := 1 to j - 1 do
          cholSum := cholSum - Kxx[j][kk] * Kxx[j][kk];
        if cholSum <= 1.0E-10 * cholMaxDiag then
          Fail(ExitInvalidModel, Format(
            'Freedom case "%s": %s has no mass and is not restrained by any stiffness (a mechanism ' +
            'among the massless dofs, or a node no element stiffens) -- constrain it, or connect it to the structure.',
            [FC.Id, EqLabel(eqOfR[j])]));
        Kxx[j][j] := Sqrt(cholSum);
        for i := j + 1 to nR do
        begin
          cholSum := Kxx[i][j];
          for kk := 1 to j - 1 do
            cholSum := cholSum - Kxx[i][kk] * Kxx[j][kk];
          Kxx[i][j] := cholSum / Kxx[j][j];
        end;
      end;

      // Xr = Krr^-1 * Krt, one column of Krt at a time (forward then back substitution).
      for j := 1 to nT do
      begin
        for i := 1 to nR do
        begin
          cholSum := Krt[i][j];
          for kk := 1 to i - 1 do
            cholSum := cholSum - Kxx[i][kk] * Xr[kk][j];
          Xr[i][j] := cholSum / Kxx[i][i];
        end;
        for i := nR downto 1 do
        begin
          cholSum := Xr[i][j];
          for kk := i + 1 to nR do
            cholSum := cholSum - Kxx[kk][i] * Xr[kk][j];
          Xr[i][j] := cholSum / Kxx[i][i];
        end;
      end;

      // Kc = Ktt - Ktr*Xr  (Ktr = Krt^T), then symmetrize away round-off asymmetry.
      for i := 1 to nT do
        for j := 1 to nT do
        begin
          cholSum := 0.0;
          for kk := 1 to nR do
            cholSum := cholSum + Krt[kk][i] * Xr[kk][j];
          Ktt[i][j] := Ktt[i][j] - cholSum;
        end;
      for i := 1 to nT do
        for j := i + 1 to nT do
        begin
          cholSum := 0.5 * (Ktt[i][j] + Ktt[j][i]);
          Ktt[i][j] := cholSum;
          Ktt[j][i] := cholSum;
        end;
    end;

    // ---- Reduce to a standard symmetric eigenproblem: Kmass = D^-1 Kc D^-1, D=diag(sqrt(M)) ----
    SetLength(Dsqrt, nT + 1);
    for i := 1 to nT do
      Dsqrt[i] := Sqrt(massedDof[eqOfT[i]]);
    Kmass := NewDenseMatrix(nT);
    for i := 1 to nT do
      for j := 1 to nT do
        Kmass[i][j] := Ktt[i][j] / (Dsqrt[i] * Dsqrt[j]);

    try
      JacobiEigenSymmetric(Kmass, nT, EigVals, EigVecs);
    except
      on E: Exception do
        Fail(ExitSolverError, Format('Freedom case "%s": %s', [FC.Id, E.Message]));
    end;

    if Model.SolverParams.Verbose then
      PrintOrthonormalityCheck(Format('freedom case "%s"', [FC.Id]), EigVecs, nT);

    // ---- Output ----
    // omega^2 = eigenvalue of the mass-normalized problem; mode shape in
    // physical (displacement) coordinates is D^-1 * eigenvector, then
    // normalized so phi^T M phi = 1 (mass-normalized, the standard modal
    // convention) -- D^-1*eigenvector is already exactly mass-normalized
    // since the reduction was symmetric (Kmass eigenvectors are orthonormal
    // in the Euclidean sense, and phi = D^-1 y => phi^T M phi = y^T y = 1).
    nModes := nT;
    SetLength(uT, nT + 1);
    SetLength(uR, nR + 1);
    for i := 1 to nModes do
    begin
      if EigVals[i] < 0 then
        Fail(ExitSolverError, Format(
          'Freedom case "%s": mode %d has a negative eigenvalue (omega^2 = %g) -- the free-free stiffness is not ' +
          'positive semi-definite; check the model for an unstable/mechanism sub-structure', [FC.Id, i, EigVals[i]]));
      omega := Sqrt(EigVals[i]);
      freq := omega / (2 * Pi);
      if Model.SolverParams.Verbose then
      begin
        if freq > 0 then
          WriteLn(OutF, Format('# Mode %d: omega=%s rad/s, freq=%s Hz, period=%s s',
            [i, D2Str(omega, FS), D2Str(freq, FS), D2Str(1.0 / freq, FS)]))
        else
          WriteLn(OutF, Format('# Mode %d: omega=%s rad/s, freq=%s Hz -- a rigid-body mode (no period; '
            + 'likely an unrestrained/mechanism direction in this freedom case)',
            [i, D2Str(omega, FS), D2Str(freq, FS)]));
      end;
      WriteLn(OutF, Format('%sMODE.%d.omega=%.17e', [KeyPrefix, i, omega], FS));
      WriteLn(OutF, Format('%sMODE.%d.freq=%.17e', [KeyPrefix, i, freq], FS));
      // Physical mode shape on the massed dofs, then the massless dofs by
      // static recovery phi_r = -Krr^-1*Krt*phi_t (= -Xr*phi_t).
      for kk := 1 to nT do
        uT[kk] := EigVecs[kk][i] / Dsqrt[kk];
      for kk := 1 to nR do
      begin
        cholSum := 0.0;
        for eq_j := 1 to nT do
          cholSum := cholSum + Xr[kk][eq_j] * uT[eq_j];
        uR[kk] := -cholSum;
      end;
      for j := 0 to High(Model.Nodes) do
        for eq_i := 0 to DofMap.NodeDofCounts[j] - 1 do
        begin
          gi := fem_dofmap.GlobalDof(DofMap, j, eq_i);
          eq_j := DofMap.GlobalToEq[gi];
          if eq_j > 0 then
          begin
            if tOfEq[eq_j] > 0 then
              WriteLn(OutF, Format('%sMODE.%d.DISP.%d.%s=%.17e',
                [KeyPrefix, i, Model.Nodes[j].Id, DofNames[eq_i], uT[tOfEq[eq_j]]], FS))
            else
              WriteLn(OutF, Format('%sMODE.%d.DISP.%d.%s=%.17e',
                [KeyPrefix, i, Model.Nodes[j].Id, DofNames[eq_i], uR[rOfEq[eq_j]]], FS));
          end
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
