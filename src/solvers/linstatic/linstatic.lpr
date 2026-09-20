program linstatic;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Generics.Collections, Math,
  fem_types, fem_json_model, fem_validate, fem_index, fem_dofmap, fem_skyline, fem_elements;

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

function ElementStiffness(const el: TElement): TElemMatrix;
var
  prop: TProperty;
  mat: TMaterial;
  n1, n2: TNode;
  G: Double;
  refVec: array[0..2] of Double;
begin
  prop := Model.Properties[PropIdx[el.PropertyId]];
  mat := Model.Materials[MatIdx[prop.MaterialId]];
  n1 := Model.Nodes[NodeIdx[el.NodeIds[0]]];
  n2 := Model.Nodes[NodeIdx[el.NodeIds[1]]];
  if el.ElementType = 'truss' then
    Result := TrussStiffness3D(mat.E, prop.Area, n1.X, n1.Y, n1.Z, n2.X, n2.Y, n2.Z)
  else // 'beam' -- fem_validate guarantees no other type reaches here
  begin
    G := mat.E / (2.0 * (1.0 + mat.Nu));
    if el.HasRefVec then
    begin
      refVec[0] := el.RefVec[0]; refVec[1] := el.RefVec[1]; refVec[2] := el.RefVec[2];
    end
    else
    begin
      refVec[0] := 0; refVec[1] := 0; refVec[2] := 0;
    end;
    Result := BeamStiffness3D(mat.E, G, prop.Area, prop.Iy, prop.Iz, prop.J,
      n1.X, n1.Y, n1.Z, n2.X, n2.Y, n2.Z, refVec);
  end;
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
      WriteLn(Format('%sDISP.%d.%s=%.17e',
        [CasePrefix, Model.Nodes[ii].Id, DofNames[jj], U[GlobalDof(ii, jj)]], FS));
  for ii := 0 to High(Model.Nodes) do
    for jj := 0 to NodeDofCounts[ii] - 1 do
    begin
      ggi := GlobalDof(ii, jj);
      if DofMap.GlobalToEq[ggi] = 0 then
        WriteLn(Format('%sREACT.%d.%s=%.17e', [CasePrefix, Model.Nodes[ii].Id, DofNames[jj], R[ggi]], FS));
    end;
end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

  // ---- 1. CLI ----
  if ParamCount <> 1 then
    Fail(ExitUsage, 'Usage: linstatic <model.json | ->' + LineEnding +
      '  Reads a FEM model file (or "-" for stdin), runs a linear-static skyline' + LineEnding +
      '  solve for every load case (and freedom case) in the model, and writes' + LineEnding +
      '  results to stdout. Composes with adaptors: e.g. adapt_strand7 in.txt | linstatic -');
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

  WriteLn('# FreePascal FEM Suite - linstatic (skyline linear-static solver)');
  WriteLn(Format('# model=%s', [ModelFile]));
  WriteLn(Format('# nodes=%d elements=%d freedom_cases=%d load_cases=%d combinations=%d',
    [NumNodes, Length(Model.Elements), Length(Model.FreedomCases), Length(Model.LoadCases), Length(Model.Combinations)]));

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
        Klocal := ElementStiffness(el);
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
      K.Factorize;
    except
      on E: Exception do
        Fail(ExitSolverError, Format('Freedom case "%s": %s', [FC.Id, E.Message]));
    end;

    SetLength(CaseFullU, Length(Model.LoadCases));
    SetLength(CaseReact, Length(Model.LoadCases));

    // ---- 6. Solve every load case against this freedom case's factorized K ----
    for lcIdx := 0 to High(Model.LoadCases) do
    begin
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
        Klocal := ElementStiffness(el);
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
    end;

    K.Free;
  end;

  NodeIdx.Free;
  MatIdx.Free;
  PropIdx.Free;
  Halt(ExitOk);
end.
