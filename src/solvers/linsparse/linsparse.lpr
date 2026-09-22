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

