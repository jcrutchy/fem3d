program linsparse;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, Generics.Collections, Math,
  fem_types, fem_native_model, fem_validate, fem_index, fem_dofmap, fem_elements, fem_pcg;

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
  NumThreads: Integer;
  UseSpinSync: Boolean;
  SyncModeStr: string;

  NumNodes, NDOF, NEQ: Integer;
  DofMap: TDofMap;
  NodeDofCounts: TIntArray;
  FullU: TDoubleArray;

  ElementData: TElementDataArray;
  ElementGDofsList: array of TIntArray;

  RHS: TDoubleArray;

procedure Fail(Code: Integer; const Msg: string);
begin
  WriteLn(StdErr, Msg);
  Halt(Code);
end;

function GlobalDof(NodeIndex, LocalOffset: Integer): Integer; inline;
begin
  Result := fem_dofmap.GlobalDof(DofMap, NodeIndex, LocalOffset);
end;

var
  i, j, ei, N: Integer;
  el: TElement;
  eq_i, gi: Integer;
  Klocal: TElemMatrix;
  ReactionAccum: TDoubleArray;
  AppliedAtDof: TDoubleArray;

  fcIdx, lcIdx, cIdx, tIdx, termLcIdx, pcgIters: Integer;
  pcgShift: Double;
  FC: TFreedomCase;
  Comb: TCombination;
  CaseFullU: array of TDoubleArray;
  CaseReact: array of TDoubleArray;
  ComboU, ComboR: TDoubleArray;
  RHSPerCase: TDoubleArray;
  UseBareKeys: Boolean;
  KeyPrefix: string;
  OutF: Text;
  nTruss, nBeam, nShellQ4, nShellQ8, nOtherType: Integer;
  otherTypeSuffix: string;

function FindLoadCaseIndex(const Id: string): Integer;
var
  k: Integer;
begin
  Result := -1;
  for k := 0 to High(Model.LoadCases) do
    if Model.LoadCases[k].Id = Id then
    begin
      Result := k;
      Exit;
    end;
end;

procedure EmitCaseResults(const CasePrefix: string; const U, R: TDoubleArray);
var
  ii, jj, ggi: Integer;
begin
  for ii := 0 to High(Model.Nodes) do
    for jj := 0 to NodeDofCounts[ii] - 1 do
      WriteLn(OutF, Format('%sDISP.%d.%s=%.17e',
        [CasePrefix, Model.Nodes[ii].Id, DofNames[jj], U[GlobalDof(ii, jj)]], FS));
  for ii := 0 to High(Model.Nodes) do
    for jj := 0 to NodeDofCounts[ii] - 1 do
    begin
      ggi := GlobalDof(ii, jj);
      if DofMap.GlobalToEq[ggi] = 0 then
        WriteLn(OutF, Format('%sREACT.%d.%s=%.17e', [CasePrefix, Model.Nodes[ii].Id, DofNames[jj], R[ggi]], FS));
    end;
end;

// ---- Verbose-mode narrative helpers, mirroring linstatic's -----------
// (see linstatic.lpr's own copies for the fuller reasoning in comments;
// kept as a second copy rather than a shared unit since each solver
// here is a fully standalone program -- same duplication tradeoff the
// project already accepts for e.g. EmitCaseResults above.) The one
// linsparse-specific addition is PrintPcgConvergence, since this is
// the one solver where "did it actually converge, and how" is a live
// question a direct/exact solver like linstatic never has.

function D2Str(V: Double; const Fmt: TFormatSettings): string;
begin
  Result := FloatToStr(V, Fmt);
end;

procedure PrintConstraintsBlock(const FC: TFreedomCase);
var
  ii, jj, ggi, nConstrained: Integer;
begin
  nConstrained := NDOF - NEQ;
  WriteLn(OutF, Format('# Freedom case "%s": %d node(s), %d degree(s) of freedom total, '
    + '%d constrained, %d free -- the free ones are what this solve is for.',
    [FC.Id, NumNodes, NDOF, nConstrained, NEQ]));
  if nConstrained = 0 then Exit;
  WriteLn(OutF, '#   Constrained dof (node.dof = prescribed value; 0 = fully restrained):');
  for ii := 0 to High(Model.Nodes) do
    for jj := 0 to NodeDofCounts[ii] - 1 do
    begin
      ggi := GlobalDof(ii, jj);
      if DofMap.GlobalToEq[ggi] = 0 then
        WriteLn(OutF, Format('#     node %d, %s = %s',
          [Model.Nodes[ii].Id, DofNames[jj], D2Str(DofMap.Prescribed[ggi], FS)]));
    end;
end;

procedure PrintLoadsBlock(const LC: TLoadCase);
var
  ii: Integer;
begin
  if Length(LC.Loads) = 0 then
  begin
    WriteLn(OutF, Format('# Load case "%s": no applied loads (results below come entirely from '
      + 'the freedom case''s prescribed displacements, if any).', [LC.Id]));
    Exit;
  end;
  WriteLn(OutF, Format('# Load case "%s": %d applied load(s):', [LC.Id, Length(LC.Loads)]));
  for ii := 0 to High(LC.Loads) do
    WriteLn(OutF, Format('#   node %d, %s = %s',
      [LC.Loads[ii].NodeId, LC.Loads[ii].Dof, D2Str(LC.Loads[ii].Value, FS)]));
end;

// PCG-specific: unlike linstatic's exact direct factorization, this
// solve is iterative and only exact up to Tolerance -- worth surfacing
// in the main narrative, not just behind the FEM_DEBUG env var (which
// stays as-is for anyone who wants it on stderr regardless of Verbose).
procedure PrintPcgConvergence(const CaseLabel: string; iters: Integer; shift, tol: Double);
begin
  if shift > 0 then
    WriteLn(OutF, Format('# PCG for %s: converged in %d iteration(s) to tolerance %s (IC(0) preconditioner '
      + 'needed a diagonal shift of %s to avoid breakdown -- see docs/linsparse.md).',
      [CaseLabel, iters, D2Str(tol, FS), D2Str(shift, FS)]))
  else
    WriteLn(OutF, Format('# PCG for %s: converged in %d iteration(s) to tolerance %s.',
      [CaseLabel, iters, D2Str(tol, FS)]));
end;

procedure PrintResultsTable(const CaseLabel: string; const U, R: TDoubleArray);
var
  ii, jj, ggi: Integer;
  line: string;
begin
  WriteLn(OutF, Format('# Results for %s (displacement / rotation, then reaction where restrained):', [CaseLabel]));
  for ii := 0 to High(Model.Nodes) do
  begin
    if NodeDofCounts[ii] = 0 then Continue;
    line := Format('#   node %d: ', [Model.Nodes[ii].Id]);
    for jj := 0 to NodeDofCounts[ii] - 1 do
    begin
      ggi := GlobalDof(ii, jj);
      line := line + Format('%s=%s', [DofNames[jj], D2Str(U[ggi], FS)]);
      if DofMap.GlobalToEq[ggi] = 0 then
        line := line + Format(' (react %s)', [D2Str(R[ggi], FS)]);
      if jj < NodeDofCounts[ii] - 1 then line := line + ', ';
    end;
    WriteLn(OutF, line);
  end;
end;

// Same global force-equilibrium self-check as linstatic -- see that
// file's copy for the full reasoning. Doubly worth having here: a bug
// in the matrix-free PCG element-by-element machinery (as opposed to
// linstatic's conventional assembled-matrix path) is a genuinely
// different code path that could go wrong in its own way, and this
// catches it the same way regardless of which solver produced U/R.
procedure PrintEquilibriumCheck(const CaseLabel: string; const U, R, Applied: TDoubleArray);
var
  ii, jj, ggi: Integer;
  totals: array[0..2] of Double;
  maxMag: Double;
  tol: Double;
  allOk: Boolean;
begin
  totals[0] := 0; totals[1] := 0; totals[2] := 0;
  maxMag := 0;
  for ii := 0 to High(Model.Nodes) do
    for jj := 0 to 2 do
    begin
      if jj >= NodeDofCounts[ii] then Continue;
      ggi := GlobalDof(ii, jj);
      if DofMap.GlobalToEq[ggi] = 0 then
        totals[jj] := totals[jj] + R[ggi]
      else
        totals[jj] := totals[jj] + Applied[ggi];
      if Abs(R[ggi]) > maxMag then maxMag := Abs(R[ggi]);
      if Abs(Applied[ggi]) > maxMag then maxMag := Abs(Applied[ggi]);
    end;
  // PCG only solves to Tolerance, not to floating-point round-off the
  // way the direct solver does, so this check's own tolerance is
  // scaled a little looser (10x) to avoid flagging PCG's own expected
  // convergence-level residual as a false "WARNING".
  tol := 10.0 * Model.SolverParams.Tolerance * (maxMag + 1.0);
  allOk := (Abs(totals[0]) <= tol) and (Abs(totals[1]) <= tol) and (Abs(totals[2]) <= tol);
  WriteLn(OutF, Format('# Equilibrium check for %s (sum of all external forces should be ~0):', [CaseLabel]));
  if allOk then
    WriteLn(OutF, Format('#   sum Fx=%s, sum Fy=%s, sum Fz=%s -- OK',
      [D2Str(totals[0], FS), D2Str(totals[1], FS), D2Str(totals[2], FS)]))
  else
    WriteLn(OutF, Format('#   sum Fx=%s, sum Fy=%s, sum Fz=%s -- WARNING: out of balance beyond tolerance -- '
      + 'possibly PCG not fully converged (see the iteration count above) rather than a solver bug',
      [D2Str(totals[0], FS), D2Str(totals[1], FS), D2Str(totals[2], FS)]));
end;

function CombinationTermsDescription(const Comb: TCombination): string;
var
  ti: Integer;
begin
  Result := '';
  for ti := 0 to High(Comb.Terms) do
  begin
    if ti > 0 then Result := Result + ' + ';
    Result := Result + Format('%s*%s', [D2Str(Comb.Terms[ti].Factor, FS), Comb.Terms[ti].LoadCaseId]);
  end;
end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

  NumThreads := DefaultThreadCount;
  if GetEnvironmentVariable('FEM_THREADS') <> '' then
    NumThreads := StrToIntDef(GetEnvironmentVariable('FEM_THREADS'), DefaultThreadCount);
  if NumThreads < 1 then NumThreads := 1;
  UseSpinSync := LowerCase(GetEnvironmentVariable('FEM_SYNC')) = 'spin';
  if GetEnvironmentVariable('FEM_THREAD_THRESHOLD') <> '' then
    ElementCountThreadThreshold := StrToIntDef(GetEnvironmentVariable('FEM_THREAD_THRESHOLD'), ElementCountThreadThreshold);

  // ---- 1. CLI ----
  if ParamCount <> 1 then
    Fail(ExitUsage, 'Usage: linsparse <model.fem | ->' + LineEnding +
      '  Reads a FEM model file (or "-" for stdin), runs a linear-static solve' + LineEnding +
      '  for every load case (and freedom case) via a matrix-free, multithreaded' + LineEnding +
      '  preconditioned conjugate gradient solver -- no global stiffness matrix' + LineEnding +
      '  is ever assembled or stored, unlike linstatic''s direct skyline solve.' + LineEnding +
      '  See docs/linsparse.md. Set FEM_THREADS to override the thread count' + LineEnding +
      '  (default ' + IntToStr(DefaultThreadCount) + '; only used once a model has enough elements to be worth' + LineEnding +
      '  it -- see FEM_THREAD_THRESHOLD, default ' + IntToStr(ElementCountThreadThreshold) + ' elements).' + LineEnding +
      '  FEM_SYNC=spin uses busy-spin thread signaling instead of RTLEvents (see' + LineEnding +
      '  docs/linsparse.md for the measured comparison between the two).');
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

  // ---- 3. Validate ----
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

  // ---- 4. Indices ----
  NodeIdx := IndexNodes(Model);
  MatIdx := IndexMaterials(Model);
  PropIdx := IndexProperties(Model);
  NumNodes := Length(Model.Nodes);

  UseBareKeys := (Length(Model.FreedomCases) = 1) and (Length(Model.LoadCases) = 1)
             and (Length(Model.Combinations) = 0);

  if Model.SolverParams.HasResultsFile then
  begin
    AssignFile(OutF, Model.SolverParams.ResultsFile);
    Rewrite(OutF);
  end
  else
    OutF := Output;

  WriteLn(OutF, '# FreePascal FEM Suite - linsparse (element-by-element PCG solver)');
  WriteLn(OutF, Format('# model=%s', [ModelFile]));
  if UseSpinSync then SyncModeStr := 'spin' else SyncModeStr := 'event';
  WriteLn(OutF, Format('# nodes=%d elements=%d freedom_cases=%d load_cases=%d combinations=%d threads=%d sync=%s thread_threshold=%d',
    [NumNodes, Length(Model.Elements), Length(Model.FreedomCases), Length(Model.LoadCases), Length(Model.Combinations),
     NumThreads, SyncModeStr, ElementCountThreadThreshold]));

  if Model.SolverParams.Verbose then
  begin
    nTruss := 0; nBeam := 0; nShellQ4 := 0; nShellQ8 := 0; nOtherType := 0;
    for ei := 0 to High(Model.Elements) do
      if Model.Elements[ei].ElementType = 'truss' then Inc(nTruss)
      else if Model.Elements[ei].ElementType = 'beam' then Inc(nBeam)
      else if Model.Elements[ei].ElementType = 'shellq4' then Inc(nShellQ4)
      else if Model.Elements[ei].ElementType = 'shellq8' then Inc(nShellQ8)
      else Inc(nOtherType);
    if nOtherType > 0 then
      otherTypeSuffix := Format(', %d of an unrecognized type', [nOtherType])
    else
      otherTypeSuffix := '';

    WriteLn(OutF, '#');
    WriteLn(OutF, '# linsparse solves the same Ku=F as linstatic, but never assembles or');
    WriteLn(OutF, '# stores a global stiffness matrix: each PCG iteration recomputes Kff*x');
    WriteLn(OutF, '# directly from every element''s own local stiffness (element-by-element,');
    WriteLn(OutF, '# optionally multithreaded), preconditioned with an incomplete Cholesky');
    WriteLn(OutF, '# factor. This trades linstatic''s exact-to-round-off direct solve for one');
    WriteLn(OutF, '# that only needs to be exact to this model''s solver Tolerance, in exchange');
    WriteLn(OutF, '# for never needing the O(NDOF^2)-ish memory a dense/skyline factorization');
    WriteLn(OutF, '# would -- worth it once a model is too big for linstatic, not before.');
    WriteLn(OutF, Format('# %d material(s), %d propert(y/ies), solver tolerance %s.',
      [Length(Model.Materials), Length(Model.Properties), D2Str(Model.SolverParams.Tolerance, FS)]));
    WriteLn(OutF, Format('# Element types in this model: %d truss, %d beam, %d shellq4, %d shellq8%s.',
      [nTruss, nBeam, nShellQ4, nShellQ8, otherTypeSuffix]));
    WriteLn(OutF, '# (Verbose=1 is the default -- every line above and below starting with');
    WriteLn(OutF, '# ''#'' is explanatory narrative, not data; set Verbose=0 in this model''s');
    WriteLn(OutF, '# [SOLVERPARAMS] section for plain key=value output only.)');
    WriteLn(OutF, '#');
  end;

  // ---- 5. One pass per freedom case: build its dof map and precompute every ----
  //         element's local stiffness + equation-number map ONCE (mirrors
  //         linstatic factorizing K once per freedom case) -- no global matrix
  //         is ever assembled; PCG only ever needs Kff*x, computed directly
  //         from these element contributions each iteration.
  for fcIdx := 0 to High(Model.FreedomCases) do
  begin
    FC := Model.FreedomCases[fcIdx];

    DofMap := BuildDofMap(Model, NodeIdx, FC.Constraints);
    NodeDofCounts := DofMap.NodeDofCounts;
    NDOF := DofMap.NDOF;
    NEQ := DofMap.NEQ;

    if NEQ = 0 then
      Fail(ExitInvalidModel, Format('Freedom case "%s": every degree of freedom is constrained -- nothing to solve', [FC.Id]));

    if Model.SolverParams.Verbose then
      PrintConstraintsBlock(FC);

    try
      ElementData := PrecomputeElementData(Model, NodeIdx, MatIdx, PropIdx, DofMap);
    except
      on E: Exception do
        Fail(ExitSolverError, Format('Freedom case "%s": %s', [FC.Id, E.Message]));
    end;
    SetLength(ElementGDofsList, Length(Model.Elements));
    for ei := 0 to High(Model.Elements) do
      ElementGDofsList[ei] := fem_dofmap.ElementGlobalDofs(DofMap, NodeIdx, Model.Elements[ei]);

    // Non-zero prescribed displacements fold into a base RHS contribution,
    // same as linstatic -- computed directly from element data rather than
    // a global matrix, since that's all we have here.
    SetLength(RHS, NEQ + 1);
    for i := 1 to NEQ do RHS[i] := 0.0;
    for ei := 0 to High(Model.Elements) do
    begin
      Klocal := ElementData[ei].Klocal;
      N := Length(ElementData[ei].EqIdx);
      for i := 0 to N - 1 do
      begin
        eq_i := ElementData[ei].EqIdx[i];
        if eq_i = 0 then Continue;
        for j := 0 to N - 1 do
        begin
          if ElementData[ei].EqIdx[j] <> 0 then Continue; // only need the free-x-constrained-y terms
          gi := ElementGDofsList[ei][j + 1];
          if DofMap.Prescribed[gi] <> 0.0 then
            RHS[eq_i] := RHS[eq_i] - Klocal[i + 1][j + 1] * DofMap.Prescribed[gi];
        end;
      end;
    end;

    SetLength(CaseFullU, Length(Model.LoadCases));
    SetLength(CaseReact, Length(Model.LoadCases));

    // ---- 6. Solve every load case via PCG (each is an independent solve -- ----
    //         no factorization to reuse the way the direct solver does, but the
    //         precomputed element data above is reused across all of them)
    for lcIdx := 0 to High(Model.LoadCases) do
    begin
      if Model.SolverParams.Verbose then
        PrintLoadsBlock(Model.LoadCases[lcIdx]);

      SetLength(RHSPerCase, NEQ + 1);
      for i := 1 to NEQ do RHSPerCase[i] := RHS[i];

      for i := 0 to High(Model.LoadCases[lcIdx].Loads) do
      begin
        gi := GlobalDof(NodeIdx[Model.LoadCases[lcIdx].Loads[i].NodeId], DofOffset(Model.LoadCases[lcIdx].Loads[i].Dof));
        eq_i := DofMap.GlobalToEq[gi];
        if eq_i > 0 then
          RHSPerCase[eq_i] := RHSPerCase[eq_i] + Model.LoadCases[lcIdx].Loads[i].Value;
      end;

      try
        RHSPerCase := PCGSolve(ElementData, RHSPerCase, NEQ, Model.SolverParams.Tolerance, NumThreads, pcgIters, pcgShift, UseSpinSync);
      except
        on E: Exception do
          Fail(ExitSolverError, Format('Freedom case "%s", load case "%s": %s', [FC.Id, Model.LoadCases[lcIdx].Id, E.Message]));
      end;

      if GetEnvironmentVariable('FEM_DEBUG') = '1' then
      begin
        WriteLn(StdErr, Format('--- DEBUG: freedom case "%s", load case "%s": PCG converged in %d iterations (tolerance %.3e) ---',
          [FC.Id, Model.LoadCases[lcIdx].Id, pcgIters, Model.SolverParams.Tolerance]));
        if pcgShift > 0 then
          WriteLn(StdErr, Format('  (IC(0) needed a diagonal shift of %.3e to avoid breakdown)', [pcgShift]));
      end;

      if Model.SolverParams.Verbose then
        PrintPcgConvergence(Format('freedom case "%s", load case "%s"', [FC.Id, Model.LoadCases[lcIdx].Id]),
          pcgIters, pcgShift, Model.SolverParams.Tolerance);

      SetLength(FullU, NDOF + 1);
      for i := 1 to NDOF do
        if DofMap.GlobalToEq[i] > 0 then
          FullU[i] := RHSPerCase[DofMap.GlobalToEq[i]]
        else
          FullU[i] := DofMap.Prescribed[i];

      SetLength(ReactionAccum, NDOF + 1);
      SetLength(AppliedAtDof, NDOF + 1);
      for i := 1 to NDOF do
      begin
        ReactionAccum[i] := 0.0;
        AppliedAtDof[i] := 0.0;
      end;
      for i := 0 to High(Model.LoadCases[lcIdx].Loads) do
      begin
        gi := GlobalDof(NodeIdx[Model.LoadCases[lcIdx].Loads[i].NodeId], DofOffset(Model.LoadCases[lcIdx].Loads[i].Dof));
        AppliedAtDof[gi] := AppliedAtDof[gi] + Model.LoadCases[lcIdx].Loads[i].Value;
      end;
      for ei := 0 to High(Model.Elements) do
      begin
        el := Model.Elements[ei];
        Klocal := ElementData[ei].Klocal;
        N := Length(ElementData[ei].EqIdx);
        for i := 0 to N - 1 do
        begin
          gi := ElementGDofsList[ei][i + 1];
          if DofMap.GlobalToEq[gi] = 0 then
            for j := 0 to N - 1 do
            begin
              eq_i := ElementGDofsList[ei][j + 1];
              ReactionAccum[gi] := ReactionAccum[gi] + Klocal[i + 1][j + 1] * FullU[eq_i];
            end;
        end;
      end;
      for i := 1 to NDOF do
        ReactionAccum[i] := ReactionAccum[i] - AppliedAtDof[i];

      CaseFullU[lcIdx] := FullU;
      CaseReact[lcIdx] := ReactionAccum;

      if UseBareKeys then
        KeyPrefix := ''
      else if Length(Model.FreedomCases) > 1 then
        KeyPrefix := FC.Id + '.' + Model.LoadCases[lcIdx].Id + '.'
      else
        KeyPrefix := Model.LoadCases[lcIdx].Id + '.';
      EmitCaseResults(KeyPrefix, CaseFullU[lcIdx], CaseReact[lcIdx]);

      if Model.SolverParams.Verbose then
      begin
        PrintResultsTable(Format('freedom case "%s", load case "%s"', [FC.Id, Model.LoadCases[lcIdx].Id]),
          CaseFullU[lcIdx], CaseReact[lcIdx]);
        PrintEquilibriumCheck(Format('freedom case "%s", load case "%s"', [FC.Id, Model.LoadCases[lcIdx].Id]),
          CaseFullU[lcIdx], CaseReact[lcIdx], AppliedAtDof);
      end;
    end;

    // ---- 7. Combinations: pure superposition, no new solve ----
    for cIdx := 0 to High(Model.Combinations) do
    begin
      Comb := Model.Combinations[cIdx];
      if (Comb.FreedomCaseId <> FC.Id) and not ((Comb.FreedomCaseId = '') and (Length(Model.FreedomCases) = 1)) then
        Continue;

      SetLength(ComboU, NDOF + 1);
      SetLength(ComboR, NDOF + 1);
      for i := 1 to NDOF do begin ComboU[i] := 0.0; ComboR[i] := 0.0; end;

      for tIdx := 0 to High(Comb.Terms) do
      begin
        termLcIdx := FindLoadCaseIndex(Comb.Terms[tIdx].LoadCaseId);
        for i := 1 to NDOF do
        begin
          ComboU[i] := ComboU[i] + Comb.Terms[tIdx].Factor * CaseFullU[termLcIdx][i];
          ComboR[i] := ComboR[i] + Comb.Terms[tIdx].Factor * CaseReact[termLcIdx][i];
        end;
      end;

      if Length(Model.FreedomCases) > 1 then
        KeyPrefix := FC.Id + '.' + Comb.Id + '.'
      else
        KeyPrefix := Comb.Id + '.';
      EmitCaseResults(KeyPrefix, ComboU, ComboR);

      if Model.SolverParams.Verbose then
      begin
        WriteLn(OutF, Format('# Combination "%s" = %s (pure superposition of already-solved load cases -- no new PCG solve, and no separate equilibrium check: a linear combination of individually-balanced cases is automatically balanced too).',
          [Comb.Id, CombinationTermsDescription(Comb)]));
        PrintResultsTable(Format('freedom case "%s", combination "%s"', [FC.Id, Comb.Id]), ComboU, ComboR);
      end;
    end;
  end;

  if Model.SolverParams.HasResultsFile then
  begin
    CloseFile(OutF);
    WriteLn(Format('Results written to %s', [Model.SolverParams.ResultsFile]));
  end
  else
    Flush(OutF);

  NodeIdx.Free;
  MatIdx.Free;
  PropIdx.Free;
  Halt(ExitOk);
end.
