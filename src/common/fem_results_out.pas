unit fem_results_out;

{$mode objfpc}{$H+}

// Writes element forces/stresses for one solved case, in the same two
// styles every solver output uses:
//   * machine-readable  <prefix>ELEM.<id>.<name>=<%.17e>   (always)
//   * '#'-prefixed readable tables                         (Verbose only)
// Shared by linstatic and linsparse so their element output is identical
// and cannot drift apart.
//
// Key names (all within one case's prefix):
//   truss  ELEM.<id>.N  .SIGMA  .VM  .TRESCA
//   beam   ELEM.<id>.S<k>.POS                       station position along member
//                          .N .VY .VZ .T .MY .MZ    member-local (principal) axes
//                          .GFX .GFY .GFZ .GMX .GMY .GMZ   same, global axes
//                          .SIGAX .SIGMAX .SIGMIN .TAU .VM .TRESCA
//          k = 0..BeamDivisions (0 = node 1, BeamDivisions = node 2)
// See fem_results.pas for the sign conventions.

interface

uses
  fem_types, fem_index, fem_dofmap, fem_results, SysUtils, StrUtils, Math;

procedure EmitElementResults(var OutF: Text; const CasePrefix, CaseLabel: string;
  const Model: TModel; NodeIdx, MatIdx, PropIdx: TIntIntMap;
  const DofMap: TDofMap; const U: TDoubleArray; const FS: TFormatSettings);

implementation

// Largest magnitude in the table being printed. Values smaller than 1E-10 of
// it are shown as 0: they are floating-point round-off (e.g. a bending
// moment of 1E-12 at a free end), and printing them is noise. The
// ELEM.* key=value lines are not touched -- they always carry the raw value.
var
  TableScale: Double = 0.0;

function G(V: Double; const FS: TFormatSettings; W: Integer = 12): string;
begin
  // 6 significant digits, general format, right-aligned in W columns.
  if Abs(V) <= 1.0E-10 * TableScale then V := 0.0; // also avoids printing -0
  Result := FloatToStrF(V, ffGeneral, 6, 0, FS);
  while Length(Result) < W do Result := ' ' + Result;
end;

procedure Emit(var OutF: Text; const Key: string; V: Double; const FS: TFormatSettings);
begin
  WriteLn(OutF, Format('%s=%.17e', [Key, V], FS));
end;

procedure EmitTruss(var OutF: Text; const P: string; const el: TElement;
  const R: TTrussResult; const FS: TFormatSettings);
begin
  Emit(OutF, Format('%sELEM.%d.N', [P, el.Id]), R.N, FS);
  Emit(OutF, Format('%sELEM.%d.SIGMA', [P, el.Id]), R.Sigma, FS);
  Emit(OutF, Format('%sELEM.%d.VM', [P, el.Id]), Abs(R.Sigma), FS);
  Emit(OutF, Format('%sELEM.%d.TRESCA', [P, el.Id]), Abs(R.Sigma), FS);
end;

procedure EmitBeam(var OutF: Text; const P: string; const el: TElement;
  const R: TBeamResult; const FS: TFormatSettings);
var
  k: Integer;
  B: string;
begin
  for k := 0 to High(R.Stations) do
  begin
    B := Format('%sELEM.%d.S%d.', [P, el.Id, k]);
    with R.Stations[k] do
    begin
      Emit(OutF, B + 'POS', S, FS);
      Emit(OutF, B + 'N', N, FS);   Emit(OutF, B + 'VY', Vy, FS); Emit(OutF, B + 'VZ', Vz, FS);
      Emit(OutF, B + 'T', T, FS);   Emit(OutF, B + 'MY', My, FS); Emit(OutF, B + 'MZ', Mz, FS);
      Emit(OutF, B + 'GFX', GFx, FS); Emit(OutF, B + 'GFY', GFy, FS); Emit(OutF, B + 'GFZ', GFz, FS);
      Emit(OutF, B + 'GMX', GMx, FS); Emit(OutF, B + 'GMY', GMy, FS); Emit(OutF, B + 'GMZ', GMz, FS);
      Emit(OutF, B + 'SIGAX', SigAxial, FS);
      Emit(OutF, B + 'SIGMAX', SigMax, FS);
      Emit(OutF, B + 'SIGMIN', SigMin, FS);
      Emit(OutF, B + 'TAU', Tau, FS);
      Emit(OutF, B + 'VM', VonMises, FS);
      Emit(OutF, B + 'TRESCA', Tresca, FS);
    end;
  end;
end;

procedure NarrateTruss(var OutF: Text; const el: TElement; const R: TTrussResult;
  const FS: TFormatSettings);
begin
  TableScale := 0.0;
  WriteLn(OutF, Format('#   truss %d (nodes %d-%d): axial force N = %s (%s), stress = %s (von Mises = Tresca = |stress| for a one-dimensional member)',
    [el.Id, el.NodeIds[0], el.NodeIds[1], Trim(G(R.N, FS)),
     IfThen(R.N > 0, 'tension', IfThen(R.N < 0, 'compression', 'unloaded')),
     Trim(G(R.Sigma, FS))]));
end;

procedure NarrateBeam(var OutF: Text; const el: TElement; const R: TBeamResult;
  const FS: TFormatSettings);
var
  k: Integer;
begin
  TableScale := 0.0;
  for k := 0 to High(R.Stations) do
    with R.Stations[k] do
    begin
      TableScale := Max(TableScale, Max(Abs(N), Max(Abs(Vy), Max(Abs(Vz), Max(Abs(T), Max(Abs(My), Abs(Mz)))))));
      TableScale := Max(TableScale, Max(Abs(SigMax), Max(Abs(SigMin), Max(Abs(Tau), Max(Abs(VonMises), Abs(Tresca))))));
    end;
  WriteLn(OutF, Format('#   beam %d (nodes %d-%d), length %s, %d division(s) = %d stations:',
    [el.Id, el.NodeIds[0], el.NodeIds[1], Trim(G(R.Length, FS)),
     Length(R.Stations) - 1, Length(R.Stations)]));
  WriteLn(OutF, '#     forces on the +x face of the section, member-local (principal) axes:');
  WriteLn(OutF, '#          s           N          Vy          Vz           T          My          Mz');
  for k := 0 to High(R.Stations) do
    with R.Stations[k] do
      WriteLn(OutF, '#   ' + G(S, FS, 10) + G(N, FS) + G(Vy, FS) + G(Vz, FS) + G(T, FS) + G(My, FS) + G(Mz, FS));
  WriteLn(OutF, '#     the same resultants on global axes:');
  WriteLn(OutF, '#          s         Fx          Fy          Fz          Mx          My          Mz');
  for k := 0 to High(R.Stations) do
    with R.Stations[k] do
      WriteLn(OutF, '#   ' + G(S, FS, 10) + G(GFx, FS) + G(GFy, FS) + G(GFz, FS) + G(GMx, FS) + G(GMy, FS) + G(GMz, FS));
  if R.HasBendingStress then
    WriteLn(OutF, '#     stresses at the four section corners (axial + bending' +
      IfThen(R.HasTorsionStress, ' + torsional shear', '') + '; transverse shear stress is not included):')
  else
    WriteLn(OutF, '#     stresses (axial N/A only -- give Cy and Cz in the beam''s property line for bending stress' +
      IfThen(R.HasTorsionStress, '; torsional shear included', '') + '):');
  WriteLn(OutF, '#          s      sig_axial     sig_max     sig_min         tau   von Mises      Tresca');
  for k := 0 to High(R.Stations) do
    with R.Stations[k] do
      WriteLn(OutF, '#   ' + G(S, FS, 10) + G(SigAxial, FS) + G(SigMax, FS) + G(SigMin, FS) + G(Tau, FS) +
        G(VonMises, FS, 12) + G(Tresca, FS, 12));
end;

procedure EmitElementResults(var OutF: Text; const CasePrefix, CaseLabel: string;
  const Model: TModel; NodeIdx, MatIdx, PropIdx: TIntIntMap;
  const DofMap: TDofMap; const U: TDoubleArray; const FS: TFormatSettings);
var
  ei, i, nT, nB: Integer;
  el: TElement;
  gd: TIntArray;
  Ue: TDoubleArray;
  TR: TTrussResult;
  BR: TBeamResult;
begin
  nT := 0; nB := 0;
  for ei := 0 to High(Model.Elements) do
  begin
    if Model.Elements[ei].ElementType = 'truss' then Inc(nT)
    else if Model.Elements[ei].ElementType = 'beam' then Inc(nB);
  end;
  if (nT + nB) = 0 then Exit;

  if Model.SolverParams.Verbose then
  begin
    WriteLn(OutF, Format('# Element forces and stresses for %s:', [CaseLabel]));
    WriteLn(OutF, '#   (internal forces are recovered from the solved displacements, element by element;');
    WriteLn(OutF, '#    N is tension-positive. Set ElementResults=0 in [SOLVERPARAMS] to skip this section.)');
  end;

  for ei := 0 to High(Model.Elements) do
  begin
    el := Model.Elements[ei];
    if (el.ElementType <> 'truss') and (el.ElementType <> 'beam') then Continue;
    gd := ElementGlobalDofs(DofMap, NodeIdx, el);
    SetLength(Ue, High(gd) + 1);
    Ue[0] := 0.0;
    for i := 1 to High(gd) do Ue[i] := U[gd[i]];

    if el.ElementType = 'truss' then
    begin
      TR := TrussResultFor(Model, NodeIdx, MatIdx, PropIdx, el, Ue);
      EmitTruss(OutF, CasePrefix, el, TR, FS);
      if Model.SolverParams.Verbose then NarrateTruss(OutF, el, TR, FS);
    end
    else
    begin
      BR := BeamResultFor(Model, NodeIdx, MatIdx, PropIdx, el, Ue, Model.SolverParams.BeamDivisions);
      EmitBeam(OutF, CasePrefix, el, BR, FS);
      if Model.SolverParams.Verbose then NarrateBeam(OutF, el, BR, FS);
    end;
  end;
end;

end.
