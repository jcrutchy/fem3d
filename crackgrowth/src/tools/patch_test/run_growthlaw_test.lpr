program run_growthlaw_test;

// Standalone verification for fem_cg_growthlaws. Three kinds of check,
// same discipline as fem3d's own run_q8_*_test.lpr programs:
//   1. Exact algebraic identities that must hold regardless of any
//      particular reference implementation (Walker with Gamma=1 must
//      equal Paris EXACTLY, for any R -- see WalkerRate's own comment).
//   2. Hand-computable reference values for Paris and Forman (simple
//      enough to verify with a calculator).
//   3. NASGRO values cross-checked against an INDEPENDENT Python
//      implementation of the same documented Newman-closure formula
//      (/tmp/nasgro_ref.py during development) -- this catches a
//      Pascal transcription bug, but does NOT independently confirm
//      the closure formula itself is what real NASGRO material data
//      assumes; see fem_cg_growthlaws.pas's own header comment and
//      crackgrowth/docs/TODO.md.
//
// Run with: ./run_growthlaw_test  (exit code 0 = all checks passed)

{$mode objfpc}{$H+}

uses
  SysUtils, fem_cg_types, fem_cg_growthlaws;

var
  FailCount: Integer;

procedure Check(const Name: string; Cond: Boolean; const Detail: string);
begin
  if Cond then
    WriteLn('PASS  ', Name)
  else
  begin
    WriteLn('FAIL  ', Name, '  -- ', Detail);
    Inc(FailCount);
  end;
end;

function ApproxEqual(A, B, RelTol: Double): Boolean;
begin
  Result := Abs(A - B) <= RelTol * (Abs(B) + 1.0E-300);
end;

var
  mat: TCrackGrowthMaterial;
  rate, rateParis, rateCons: Double;
  lawUsed: TGrowthLaw;
  gotException: Boolean;

begin
  FailCount := 0;

  // --- 1. Paris: hand-computable ---
  // C=1e-11, m=3, DeltaK=10 -> 1e-11 * 1000 = 1e-8
  rate := ParisRate(10.0, 1.0E-11, 3.0);
  Check('Paris: hand value', ApproxEqual(rate, 1.0E-8, 1.0E-12),
    Format('got %g, expected 1e-8', [rate]));

  // --- 2. Walker(Gamma=1) == Paris, exactly, for several R ---
  rateParis := ParisRate(15.0, 3.0E-11, 3.2);
  rate := WalkerRate(15.0, 0.0, 3.0E-11, 3.2, 1.0);
  Check('Walker(Gamma=1, R=0) == Paris', ApproxEqual(rate, rateParis, 1.0E-14),
    Format('walker=%g paris=%g', [rate, rateParis]));
  rate := WalkerRate(15.0, 0.5, 3.0E-11, 3.2, 1.0);
  Check('Walker(Gamma=1, R=0.5) == Paris', ApproxEqual(rate, rateParis, 1.0E-14),
    Format('walker=%g paris=%g', [rate, rateParis]));
  rate := WalkerRate(15.0, -0.4, 3.0E-11, 3.2, 1.0);
  Check('Walker(Gamma=1, R=-0.4) == Paris', ApproxEqual(rate, rateParis, 1.0E-14),
    Format('walker=%g paris=%g', [rate, rateParis]));

  // --- 3. Walker: R>0 with Gamma<1 must grow FASTER than Paris at the
  //        same nominal DeltaK (less closure benefit credited, since
  //        Walker's effective DeltaK inflates for R>0 when Gamma<1) ---
  rate := WalkerRate(15.0, 0.5, 3.0E-11, 3.2, 0.5);
  Check('Walker(Gamma=0.5, R=0.5) > Paris (same DeltaK)', rate > rateParis,
    Format('walker=%g paris=%g', [rate, rateParis]));

  // --- 4. Forman: hand-computable reference values (see /tmp/nasgro_ref.py
  //        companion calc for the exact figures) ---
  rate := FormanRate(20.0, 0.1, 2.0E-10, 3.0, 100.0);
  Check('Forman: hand value #1', ApproxEqual(rate, 2.2857142857142858E-8, 1.0E-10),
    Format('got %g, expected 2.2857142857142858e-8', [rate]));
  rate := FormanRate(50.0, 0.3, 2.0E-10, 3.0, 100.0);
  Check('Forman: hand value #2', ApproxEqual(rate, 1.25E-6, 1.0E-10),
    Format('got %g, expected 1.25e-6', [rate]));

  // --- 5. Forman: at/beyond fracture toughness must raise, not return a number ---
  gotException := False;
  try
    FormanRate(95.0, 0.1, 2.0E-10, 3.0, 100.0); // (1-0.1)*100-95 = -5 <= 0
  except
    on E: Exception do gotException := True;
  end;
  Check('Forman: at/beyond Kc raises an exception', gotException, 'no exception was raised');

  // --- 6. NASGRO: cross-checked against the Python reference implementation ---
  mat.Name := 'Test-Al-NASGRO';
  mat.HasNasgro := True;
  mat.NasgroC := 1.75E-10; mat.NasgroN := 3.0; mat.NasgroP := 0.5; mat.NasgroQ := 1.0;
  mat.NasgroDeltaKth := 2.0; mat.NasgroKc := 60.0; mat.NasgroAlpha := 1.5;
  mat.HasParis := False; mat.HasWalker := False; mat.HasForman := False;

  rate := NasgroRate(10.0, 11.111111111111111, 0.1, mat);
  Check('NASGRO: cross-check #1 (DeltaK=10, R=0.1)', ApproxEqual(rate, 5.3774379003960747E-08, 1.0E-9),
    Format('got %g, expected ~5.3774379003960747e-8', [rate]));
  rate := NasgroRate(10.0, 20.0, 0.5, mat);
  Check('NASGRO: cross-check #2 (DeltaK=10, R=0.5)', ApproxEqual(rate, 1.3474335772486732E-07, 1.0E-9),
    Format('got %g, expected ~1.3474335772486732e-7', [rate]));
  rate := NasgroRate(30.0, 33.333333333333336, 0.1, mat);
  Check('NASGRO: cross-check #3 (DeltaK=30, R=0.1)', ApproxEqual(rate, 2.875106903976265E-06, 1.0E-9),
    Format('got %g, expected ~2.875106903976265e-6', [rate]));
  rate := NasgroRate(5.0, 5.0, -0.3, mat);
  Check('NASGRO: cross-check #4 (DeltaK=5, R=-0.3)', ApproxEqual(rate, 2.123106864012015E-09, 1.0E-9),
    Format('got %g, expected ~2.123106864012015e-9', [rate]));

  // --- 7. NASGRO: below threshold returns exactly 0, not an error ---
  rate := NasgroRate(1.5, 3.0, 0.1, mat); // DeltaK=1.5 <= DeltaKth=2.0
  Check('NASGRO: below threshold -> 0', rate = 0.0, Format('got %g', [rate]));

  // --- 8. NASGRO: at/beyond fracture toughness must raise ---
  gotException := False;
  try
    NasgroRate(30.0, 61.0, 0.1, mat); // Kmax=61 >= Kc=60
  except
    on E: Exception do gotException := True;
  end;
  Check('NASGRO: at/beyond Kc raises an exception', gotException, 'no exception was raised');

  // --- 9. ConservativeRate: with Paris + a Forman that predicts faster
  //        growth at this DeltaK/R, must return the Forman value and
  //        report glForman ---
  mat.HasParis := True; mat.ParisC := 1.0E-12; mat.ParisM := 3.0; // deliberately slow
  mat.HasForman := True; mat.FormanC := 2.0E-10; mat.FormanN := 3.0; mat.FormanKc := 100.0;
  mat.HasWalker := False; mat.HasNasgro := False;
  rateCons := ConservativeRate(20.0, 22.0, 0.1, mat, lawUsed);
  Check('ConservativeRate picks the faster (Forman) law', lawUsed = glForman,
    Format('picked %s', [GrowthLawName(lawUsed)]));
  Check('ConservativeRate value matches FormanRate directly',
    ApproxEqual(rateCons, FormanRate(20.0, 0.1, 2.0E-10, 3.0, 100.0), 1.0E-14),
    Format('got %g', [rateCons]));

  // --- 10. BestAvailableRate: with Paris + Forman only, must prefer Forman ---
  BestAvailableRate(20.0, 22.0, 0.1, mat, lawUsed);
  Check('BestAvailableRate prefers Forman over Paris', lawUsed = glForman,
    Format('picked %s', [GrowthLawName(lawUsed)]));

  // --- 11. BestAvailableRate: with only Paris available, must fall back to it ---
  mat.HasForman := False;
  BestAvailableRate(20.0, 22.0, 0.1, mat, lawUsed);
  Check('BestAvailableRate falls back to Paris when nothing else is available',
    lawUsed = glParis, Format('picked %s', [GrowthLawName(lawUsed)]));

  // --- 12. A material with no usable law at all must raise, not silently return 0 ---
  mat.HasParis := False; mat.HasWalker := False; mat.HasForman := False; mat.HasNasgro := False;
  gotException := False;
  try
    ConservativeRate(20.0, 22.0, 0.1, mat, lawUsed);
  except
    on E: Exception do gotException := True;
  end;
  Check('ConservativeRate on a material with no usable law raises', gotException,
    'no exception was raised');

  // --- 13. Newman closure is only defined below net-section yield ---
  // Smax/sigma0 >= 1 gives cos(pi/2 * S) <= 0, whose fractional power is not
  // real; that used to surface as an obscure floating-point exception.
  Check('Newman closure: a valid Smax/sigma0 (0.3) still evaluates',
    NewmanClosureF(0.1, 0.3, 2.0) > 0.0, 'non-positive closure factor');
  gotException := False;
  try
    NewmanClosureF(0.1, 1.0, 2.0);
  except
    on E: Exception do gotException := (Pos('Smax/sigma0', E.Message) > 0);
  end;
  Check('Newman closure: Smax/sigma0 = 1 raises a clear message', gotException,
    'no (or an unclear) exception');
  gotException := False;
  try
    NewmanClosureF(0.1, 1.3, 2.0);
  except
    on E: Exception do gotException := (Pos('Smax/sigma0', E.Message) > 0);
  end;
  Check('Newman closure: Smax/sigma0 > 1 raises a clear message', gotException,
    'no (or an unclear) exception');

  WriteLn;
  if FailCount = 0 then
    WriteLn('ALL CHECKS PASSED')
  else
  begin
    WriteLn(FailCount, ' CHECK(S) FAILED');
    Halt(1);
  end;
end.
