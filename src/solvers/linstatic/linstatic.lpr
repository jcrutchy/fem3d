program linstatic;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Generics.Collections, Math,
  fem_types, fem_native_model, fem_validate, fem_index, fem_dofmap, fem_skyline, fem_elements, fem_results_out;

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
  FS: TFormatSettings; // locale-independent '.' decimal separator, for both %e output and StrToFloat

  NumNodes, NDOF, NEQ: Integer;
  DofMap: TDofMap;
  NodeDofCounts: TIntArray;   // [0..NumNodes-1] -> 3 or 6 (alias of DofMap.NodeDofCounts)
  FullU: TDoubleArray;        // [1..NDOF] -> final displacement/rotation, filled after solve

  ElementEqLists: array of TIntArray;  // per element, the (possibly 0) eq numbers touched, for profile calc
  ElementGDofs: array of TIntArray;    // per element, global dof numbers, 1-based (index 0 unused)

  K: TSkylineMatrix;
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

function ElementGlobalDofs(const el: TElement): TIntArray;
begin
  Result := fem_dofmap.ElementGlobalDofs(DofMap, NodeIdx, el);
end;

var
  i, j, ei, N: Integer;
  gd: TIntArray;
  el: TElement;
  eq_i, eq_j, gi, gj: Integer;
  Klocal: TElemMatrix;
  ReactionAccum: TDoubleArray; // [1..NDOF]
  AppliedAtDof: TDoubleArray;  // [1..NDOF]

  fcIdx, lcIdx, cIdx, tIdx, termLcIdx: Integer;
  FC: TFreedomCase;
  Comb: TCombination;
  CaseFullU: array of TDoubleArray;    // [0..NumLoadCases-1] of [1..NDOF]
  CaseReact: array of TDoubleArray;    // [0..NumLoadCases-1] of [1..NDOF] (net: accumulated - applied)
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

// Short, human-readable number formatting for the verbose narrative
// output (vs. EmitCaseResults' %.17e machine-precision format) -- plain
// FloatToStr, same locale-independent settings (FS) used everywhere
// else in this program.
function D2Str(V: Double; const Fmt: TFormatSettings): string;
begin
  Result := FloatToStr(V, Fmt);
end;

// "1.5*dead + 1.2*live"-style description of a combination's terms, for
// the verbose narrative line printed alongside a combination's results.
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

// ---- Verbose-mode narrative helpers -----------------------------------
// Every line these print is '#'-prefixed, same convention as the 3
// existing header comment lines -- so nothing here changes what
// fem_regress (or any other key=value scraper) sees: ParseKV already
// skips blank lines, '#' lines, and anything that doesn't parse as
// key=number. These are purely additive.

// Freedom case FC's constraint set, AFTER BuildDofMap has resolved it --
// read back from DofMap/NodeDofCounts (the actually-applied result)
// rather than re-interpreting FC.Constraints, so this can't drift from
// what the solver actually did with e.g. a wildcard or range spec.
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

// A load case's inputs, printed BEFORE the solve -- restating the
// "given" in a hand-calc sense, before showing the "find".
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

// Human-readable results, one line per node with every active dof
// together (vs. EmitCaseResults' one-line-per-dof machine format) --
// reactions shown only where that dof was actually constrained (an
// em-dash elsewhere, since "reaction" is meaningless at a free dof:
// the solved equilibrium already makes the net force there exactly the
// applied load, not some separate restraint force).
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

// Global force equilibrium: sum, over every node, of whichever force
// actually acts at each translational dof in the solved system --
// the reaction where that dof was constrained, the applied load where
// it was free (a solved free dof's net force is the applied load, by
// construction of the equilibrium equations solved for it) -- must sum
// to (near) zero in x, y, and z. This isn't a hand-wavy sanity check:
// it's the same global force balance every statics course opens with
// (sum of all external forces on a body in equilibrium is zero), and
// it holds for ANY linear-static solve regardless of how the model
// mixes prescribed-displacement and applied-load boundary conditions --
// internal element forces are self-cancelling across the assembly, so
// only this external interface can be out of balance. A nonzero result
// here would mean a genuine bug (an assembly, dofmap, or solve error),
// not model error -- which is exactly why it's worth printing always,
// not just for a tutorial audience. Rotational (moment) equilibrium
// isn't checked here -- that needs a reference point and moment arms,
// a follow-up if it turns out to be worth the complexity.
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
    for jj := 0 to 2 do // x, y, z translational only -- see comment above
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
  tol := Model.SolverParams.Tolerance * (maxMag + 1.0);
  allOk := (Abs(totals[0]) <= tol) and (Abs(totals[1]) <= tol) and (Abs(totals[2]) <= tol);
  WriteLn(OutF, Format('# Equilibrium check for %s (sum of all external forces should be ~0):', [CaseLabel]));
  if allOk then
    WriteLn(OutF, Format('#   sum Fx=%s, sum Fy=%s, sum Fz=%s -- OK',
      [D2Str(totals[0], FS), D2Str(totals[1], FS), D2Str(totals[2], FS)]))
  else
    WriteLn(OutF, Format('#   sum Fx=%s, sum Fy=%s, sum Fz=%s -- WARNING: out of balance beyond tolerance -- likely a solver bug, not a model issue',
      [D2Str(totals[0], FS), D2Str(totals[1], FS), D2Str(totals[2], FS)]));
end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

  // ---- 1. CLI ----
  if ParamCount <> 1 then
    Fail(ExitUsage, 'Usage: linstatic <model.fem | ->' + LineEnding +
      '  Reads a FEM model file (or "-" for stdin), runs a linear-static skyline' + LineEnding +
      '  solve for every load case (and freedom case) in the model, and writes' + LineEnding +
      '  results to stdout. Composes with adaptors: e.g. adapt_strand7 in.txt | linstatic -   (or adapt_json old.json | linstatic -)');
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

  // ---- 4. Indices (element/material/property/node data -- same for every case) ----
  NodeIdx := IndexNodes(Model);
  MatIdx := IndexMaterials(Model);
  PropIdx := IndexProperties(Model);
  NumNodes := Length(Model.Nodes);

  // Bare (unprefixed) DISP./REACT. keys iff there's exactly one freedom
  // case, one load case, and no combinations -- i.e. this model is
  // equivalent to the old single-case format, so its output is byte-for-
  // byte identical to what this solver produced before multi-case support
  // existed. Anything more gets "<freedomCaseId(if >1 fc)>.<caseId>." prefixed.
  UseBareKeys := (Length(Model.FreedomCases) = 1) and (Length(Model.LoadCases) = 1)
             and (Length(Model.Combinations) = 0);

  if Model.SolverParams.HasResultsFile then
  begin
    AssignFile(OutF, Model.SolverParams.ResultsFile);
    Rewrite(OutF);
  end
  else
    OutF := Output;

  WriteLn(OutF, '# FreePascal FEM Suite - linstatic (skyline linear-static solver)');
  WriteLn(OutF, Format('# model=%s', [ModelFile]));
  WriteLn(OutF, Format('# nodes=%d elements=%d freedom_cases=%d load_cases=%d combinations=%d',
    [NumNodes, Length(Model.Elements), Length(Model.FreedomCases), Length(Model.LoadCases), Length(Model.Combinations)]));

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
    WriteLn(OutF, '# linstatic solves Ku=F for one or more static load cases: assembles the');
    WriteLn(OutF, '# global stiffness matrix K from every element, applies each freedom');
    WriteLn(OutF, '# case''s constraints (removing restrained dof, folding any prescribed');
    WriteLn(OutF, '# nonzero displacement into the right-hand side), and solves the resulting');
    WriteLn(OutF, '# reduced system directly (skyline Cholesky/LDL, no iteration -- exact up');
    WriteLn(OutF, '# to floating-point round-off, not an approximate/converged solution).');
    WriteLn(OutF, Format('# %d material(s), %d propert(y/ies), solver tolerance %s.',
      [Length(Model.Materials), Length(Model.Properties), D2Str(Model.SolverParams.Tolerance, FS)]));
    WriteLn(OutF, Format('# Element types in this model: %d truss, %d beam, %d shellq4, %d shellq8%s.',
      [nTruss, nBeam, nShellQ4, nShellQ8, otherTypeSuffix]));
    WriteLn(OutF, '# (Verbose=1 is the default -- every line above and below starting with');
    WriteLn(OutF, '# ''#'' is explanatory narrative, not data; set Verbose=0 in this model''s');
    WriteLn(OutF, '# [SOLVERPARAMS] section for plain key=value output only.)');
    WriteLn(OutF, '#');
  end;

  // ---- 5. One pass per freedom case: build its dof map, assemble+factorize K ONCE, ----
  //         then solve every load case against it as a separate RHS (cheap: forward/
  //         back substitution only, no re-factorization), then evaluate any
  //         combinations that target this freedom case as a pure linear combination
  //         of already-solved load case results (no extra solve at all).
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

    try
      K := TSkylineMatrix.Create(NEQ, ComputeSkylineHeight(NEQ, ElementEqLists));
    except
      on E: Exception do
        Fail(ExitSolverError, Format('Freedom case "%s": failed to allocate skyline matrix: %s', [FC.Id, E.Message]));
    end;

    // Stiffness assembly depends only on constraints (via DofMap), not on
    // any load case, so it happens once per freedom case. Non-zero
    // prescribed displacements still fold into a base RHS contribution
    // here; each load case's own RHS starts from a copy of it.
    SetLength(RHS, NEQ + 1);
    for i := 1 to NEQ do RHS[i] := 0.0;
    try
      for ei := 0 to High(Model.Elements) do
      begin
        el := Model.Elements[ei];
        Klocal := ElementStiffnessFor(Model, NodeIdx, MatIdx, PropIdx, el);
        gd := ElementGDofs[ei];
        N := High(gd);
        for i := 1 to N do
          for j := i to N do
          begin
            if Klocal[i][j] = 0.0 then Continue;
            gi := gd[i]; gj := gd[j];
            eq_i := DofMap.GlobalToEq[gi]; eq_j := DofMap.GlobalToEq[gj];
            if (eq_i > 0) and (eq_j > 0) then
              K.AddToK(eq_i, eq_j, Klocal[i][j])
            else if (eq_i > 0) and (eq_j = 0) then
            begin
              if DofMap.Prescribed[gj] <> 0.0 then
                RHS[eq_i] := RHS[eq_i] - Klocal[i][j] * DofMap.Prescribed[gj];
            end
            else if (eq_j > 0) and (eq_i = 0) then
            begin
              if DofMap.Prescribed[gi] <> 0.0 then
                RHS[eq_j] := RHS[eq_j] - Klocal[i][j] * DofMap.Prescribed[gi];
            end;
          end;
      end;
    except
      on E: Exception do
        Fail(ExitSolverError, Format('Freedom case "%s": assembly error: %s', [FC.Id, E.Message]));
    end;

    try
      K.Factorize(Model.SolverParams.PivotTolerance);
    except
      on E: Exception do
        Fail(ExitSolverError, Format('Freedom case "%s": %s', [FC.Id, E.Message]));
    end;

    SetLength(CaseFullU, Length(Model.LoadCases));
    SetLength(CaseReact, Length(Model.LoadCases));

    // ---- 6. Solve every load case against this freedom case's factorized K ----
    for lcIdx := 0 to High(Model.LoadCases) do
    begin
      if Model.SolverParams.Verbose then
        PrintLoadsBlock(Model.LoadCases[lcIdx]);

      SetLength(RHSPerCase, NEQ + 1);
      for i := 1 to NEQ do RHSPerCase[i] := RHS[i]; // start from the prescribed-displacement contribution

      for i := 0 to High(Model.LoadCases[lcIdx].Loads) do
      begin
        gi := GlobalDof(NodeIdx[Model.LoadCases[lcIdx].Loads[i].NodeId], DofOffset(Model.LoadCases[lcIdx].Loads[i].Dof));
        eq_i := DofMap.GlobalToEq[gi];
        if eq_i > 0 then
          RHSPerCase[eq_i] := RHSPerCase[eq_i] + Model.LoadCases[lcIdx].Loads[i].Value;
      end;

      if GetEnvironmentVariable('FEM_DEBUG') = '1' then
      begin
        WriteLn(StdErr, Format('--- DEBUG: freedom case "%s", load case "%s" ---', [FC.Id, Model.LoadCases[lcIdx].Id]));
        WriteLn(StdErr, '  GlobalToEq:');
        for i := 1 to NDOF do
          WriteLn(StdErr, Format('    gdof %d -> eq %d', [i, DofMap.GlobalToEq[i]]));
        WriteLn(StdErr, '  Kff dense:');
        for i := 1 to NEQ do
        begin
          Write(StdErr, '    ');
          for j := 1 to NEQ do
            Write(StdErr, Format('%14.4e', [K.GetEntry(i, j)]));
          WriteLn(StdErr);
        end;
        WriteLn(StdErr, '  RHS:');
        for i := 1 to NEQ do
          WriteLn(StdErr, Format('    eq %d -> %14.6e', [i, RHSPerCase[i]]));
      end;

      try
        RHSPerCase := K.Solve(RHSPerCase);
      except
        on E: Exception do
          Fail(ExitSolverError, Format('Freedom case "%s", load case "%s": %s', [FC.Id, Model.LoadCases[lcIdx].Id, E.Message]));
      end;

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
        Klocal := ElementStiffnessFor(Model, NodeIdx, MatIdx, PropIdx, el);
        gd := ElementGDofs[ei];
        N := High(gd);
        for i := 1 to N do
          if DofMap.GlobalToEq[gd[i]] = 0 then
            for j := 1 to N do
              ReactionAccum[gd[i]] := ReactionAccum[gd[i]] + Klocal[i][j] * FullU[gd[j]];
      end;
      for i := 1 to NDOF do
        ReactionAccum[i] := ReactionAccum[i] - AppliedAtDof[i]; // net reaction, stored ready-to-emit

      CaseFullU[lcIdx] := FullU;
      CaseReact[lcIdx] := ReactionAccum;

      if UseBareKeys then
        KeyPrefix := ''
      else if Length(Model.FreedomCases) > 1 then
        KeyPrefix := FC.Id + '.' + Model.LoadCases[lcIdx].Id + '.'
      else
        KeyPrefix := Model.LoadCases[lcIdx].Id + '.';
      EmitCaseResults(KeyPrefix, CaseFullU[lcIdx], CaseReact[lcIdx]);
      if Model.SolverParams.ElementResults then
        EmitElementResults(OutF, KeyPrefix,
          Format('freedom case "%s", load case "%s"', [FC.Id, Model.LoadCases[lcIdx].Id]),
          Model, NodeIdx, MatIdx, PropIdx, DofMap, CaseFullU[lcIdx], FS);

      if Model.SolverParams.Verbose then
      begin
        PrintResultsTable(Format('freedom case "%s", load case "%s"', [FC.Id, Model.LoadCases[lcIdx].Id]),
          CaseFullU[lcIdx], CaseReact[lcIdx]);
        PrintEquilibriumCheck(Format('freedom case "%s", load case "%s"', [FC.Id, Model.LoadCases[lcIdx].Id]),
          CaseFullU[lcIdx], CaseReact[lcIdx], AppliedAtDof);
      end;
    end;

    // ---- 7. Combinations targeting this freedom case: pure superposition, no new solve ----
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
      if Model.SolverParams.ElementResults then
        EmitElementResults(OutF, KeyPrefix,
          Format('freedom case "%s", combination "%s"', [FC.Id, Comb.Id]),
          Model, NodeIdx, MatIdx, PropIdx, DofMap, ComboU, FS);

      if Model.SolverParams.Verbose then
      begin
        WriteLn(OutF, Format('# Combination "%s" = %s (pure superposition of already-solved load cases -- no new solve, and no separate equilibrium check: a linear combination of individually-balanced cases is automatically balanced too).',
          [Comb.Id, CombinationTermsDescription(Comb)]));
        PrintResultsTable(Format('freedom case "%s", combination "%s"', [FC.Id, Comb.Id]), ComboU, ComboR);
      end;
    end;

    K.Free;
  end;

  if Model.SolverParams.HasResultsFile then
  begin
    CloseFile(OutF);
    WriteLn(Format('Results written to %s', [Model.SolverParams.ResultsFile]));
  end
  else
    Flush(OutF); // Halt() below can otherwise skip the buffer flush a normal exit would do

  NodeIdx.Free;
  MatIdx.Free;
  PropIdx.Free;
  Halt(ExitOk);
end.
