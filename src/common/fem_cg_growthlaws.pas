unit fem_cg_growthlaws;

// Fatigue crack growth RATE laws: da/dN as a function of the stress-
// intensity range at a crack tip, for one load cycle. This unit knows
// nothing about crack geometry, K-solutions, or how a crack actually
// grows over many cycles -- that's the next layer up (not yet built;
// see crackgrowth/docs/TODO.md), which will call these once per cycle
// (or once per block of a spectrum) and integrate the resulting da/dN
// into a crack-length history. Keeping this layer free of geometry
// concerns means it's fully unit-testable against hand/textbook
// values on its own, the same reasoning fem3d's own element-formulation
// units (fem_elements.pas) are kept free of dofmap/assembly concerns.
//
// All four laws take DeltaK = Kmax - Kmin and R = Kmin/Kmax explicitly
// rather than raw Kmax/Kmin, since that's how growth-law constants are
// conventionally reported and fit in the literature -- but Kmax itself
// is also needed by Forman and NASGRO (both have a Kmax-vs-Kc term), so
// it's passed alongside DeltaK/R rather than re-derived, avoiding a
// silent assumption about which of DeltaK/R/Kmax/Kmin the caller
// computed most precisely.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, fem_cg_types;

type
  TGrowthLaw = (glParis, glWalker, glForman, glNasgro);

function GrowthLawName(Law: TGrowthLaw): string;

// da/dN = C * DeltaK^m. DeltaK must be > 0.
function ParisRate(DeltaK, C, M: Double): Double;

// da/dN = C * (DeltaK / (1-R)^(1-Gamma))^M
// Gamma=1 makes the (1-R)^(1-Gamma) term equal (1-R)^0=1 for any R, so
// WalkerRate(DeltaK, R, C, M, 1.0) = ParisRate(DeltaK, C, M) EXACTLY for
// every R -- checked directly in run_growthlaw_test.lpr. R must be < 1
// (a physically necessary condition: R=Kmin/Kmax=1 means no cyclic
// range at all, DeltaK=0, which ParisRate already rejects, and R>1
// isn't a meaningful cycle).
function WalkerRate(DeltaK, R, C, M, Gamma: Double): Double;

// da/dN = C * DeltaK^N / ((1-R)*Kc - DeltaK)
// Raises an exception if the denominator is <= 0 -- that means
// (1-R)*Kc <= DeltaK, i.e. Kmax has reached or passed the material's
// fracture toughness: this is "already failed," not "grows very fast,"
// and a silently huge or negative da/dN would be actively misleading
// rather than conservative.
function FormanRate(DeltaK, R, C, N, Kc: Double): Double;

// Newman's crack-opening-stress ratio f = Sop/Smax, used by NasgroRate.
// SmaxOverSigma0 is the ratio of the cycle's maximum REMOTE (applied)
// stress to the material's flow stress (conventionally
// (SigmaYield+SigmaUltimate)/2) -- NOT Kmax/Kc. Computing it requires
// the crack geometry (to relate Kmax back to a remote stress), which
// this unit deliberately doesn't know about -- it's the K-solution
// layer's job to supply it. Alpha is the constraint factor: 1.0 plane
// stress, 3.0 plane strain (NASGRO analyses commonly use an
// intermediate effective value for real sheet/plate thicknesses; this
// unit takes whatever Alpha it's given without judging it).
//
// Reference form (Newman 1984; same form documented in the NASGRO
// manual) -- cross-checked against an independently written Python
// reference during development (see this unit's own header comment
// and crackgrowth/docs/TODO.md), but treat the FORM ITSELF as worth an
// independent check against the actual NASGRO documentation before
// relying on it for real work:
//   A0 = (0.825 - 0.34*Alpha + 0.05*Alpha^2) * cos(pi/2 * S)^(1/Alpha)
//   A1 = (0.415 - 0.071*Alpha) * S
//   A3 = 2*A0 + A1 - 1
//   A2 = 1 - A0 - A1 - A3
//   f = max(R, A0 + A1*R + A2*R^2 + A3*R^3)   for R >= 0
//   f = A0 + A1*R                              for -2 <= R < 0
//   f = A0 - 2*A1                              for R < -2
// where S = SmaxOverSigma0. Below R = -2 the opening ratio is held at its
// R = -2 value (the NASGRO truncation) rather than extrapolated or
// rejected: R < -2 happens routinely in flight spectra (ground-air-ground
// cycles, gust and landing loads), and an exception there would abort a
// cycle-by-cycle integration. NOTE this R < -2 branch is from memory of
// the NASGRO documentation -- confirm against the manual with the rest of
// the closure form (see crackgrowth/docs/TODO.md).
function NewmanClosureF(R, SmaxOverSigma0, Alpha: Double): Double;

// da/dN = C * (((1-f)/(1-R)) * DeltaK)^N * (1-DeltaKth/DeltaK)^P
//           / (1-Kmax/Kc)^Q
// Returns 0 (no growth, not an error) when DeltaK <= DeltaKth -- below
// threshold is a normal, expected physical state, not a failure.
// Also returns 0 when Kmax <= 0: a fully compressive cycle never opens
// the crack, so it cannot grow it (linear elastic fracture mechanics has
// no tensile stress intensity to drive growth).
// Raises an exception if Kmax >= Kc -- at or beyond fracture toughness,
// same "already failed, don't report a number" reasoning as Forman.
function NasgroRate(DeltaK, Kmax, R: Double; const Mat: TCrackGrowthMaterial): Double;

// Evaluates every growth law the material has constants for for this
// cycle, and returns the LARGEST predicted da/dN -- the fastest growth,
// i.e. the shortest predicted remaining life: the conservative choice
// for a damage-tolerance life estimate, in the sense that no law the
// material actually has data for would predict a shorter life than
// this. LawUsed reports which law produced the returned value, so the
// choice is auditable rather than opaque -- if two laws tie closely
// cycle to cycle, LawUsed can visibly switch between them as R or
// DeltaK shift, which is expected and worth being able to see, not a
// bug to hide. Raises an exception if the material has no usable law
// at all (every HasXxx flag false).
function ConservativeRate(DeltaK, Kmax, R: Double; const Mat: TCrackGrowthMaterial;
  out LawUsed: TGrowthLaw): Double;

// Picks the SINGLE most physically complete law the material has full
// constants for, preferring NASGRO (closure + threshold + toughness,
// the most complete physical model) > Forman (toughness-aware) >
// Walker (R-aware) > Paris (the fallback every material with any
// fatigue data at all is expected to have) -- NOT the fastest-growth
// law the way ConservativeRate is. Raises an exception if the material
// has no usable law at all.
function BestAvailableRate(DeltaK, Kmax, R: Double; const Mat: TCrackGrowthMaterial;
  out LawUsed: TGrowthLaw): Double;

implementation

function GrowthLawName(Law: TGrowthLaw): string;
begin
  case Law of
    glParis:  Result := 'Paris';
    glWalker: Result := 'Walker';
    glForman: Result := 'Forman';
    glNasgro: Result := 'NASGRO';
  else
    Result := '?';
  end;
end;

function ParisRate(DeltaK, C, M: Double): Double;
begin
  if DeltaK <= 0 then
    raise Exception.CreateFmt('ParisRate: DeltaK must be positive, got %g', [DeltaK]);
  Result := C * Power(DeltaK, M);
end;

function WalkerRate(DeltaK, R, C, M, Gamma: Double): Double;
var
  effectiveDeltaK: Double;
begin
  if DeltaK <= 0 then
    raise Exception.CreateFmt('WalkerRate: DeltaK must be positive, got %g', [DeltaK]);
  if R >= 1 then
    raise Exception.CreateFmt('WalkerRate: R must be less than 1, got %g', [R]);
  effectiveDeltaK := DeltaK / Power(1 - R, 1 - Gamma);
  Result := C * Power(effectiveDeltaK, M);
end;

function FormanRate(DeltaK, R, C, N, Kc: Double): Double;
var
  denom: Double;
begin
  if DeltaK <= 0 then
    raise Exception.CreateFmt('FormanRate: DeltaK must be positive, got %g', [DeltaK]);
  denom := (1 - R) * Kc - DeltaK;
  if denom <= 0 then
    raise Exception.CreateFmt(
      'FormanRate: (1-R)*Kc - DeltaK = %g is not positive -- Kmax has reached or ' +
      'passed the material''s fracture toughness (Kc=%g); this cycle represents ' +
      'immediate failure, not a finite growth rate', [denom, Kc]);
  Result := C * Power(DeltaK, N) / denom;
end;

function NewmanClosureF(R, SmaxOverSigma0, Alpha: Double): Double;
var
  S, A0, A1, A2, A3: Double;
begin
  S := SmaxOverSigma0;
  // Smax/sigma0 >= 1 means the net section has yielded (plastic collapse): the
  // closure model is not defined there (cos(pi/2 * S) <= 0 and a fractional power
  // of it is not real). Without this guard that surfaced as an obscure floating-
  // point exception.
  if (S < 0.0) or (S >= 1.0) then
    raise Exception.CreateFmt('NewmanClosureF: Smax/sigma0 must be in [0, 1) -- got %g ' +
      '(at or above 1 the net section has yielded and crack closure is not defined)', [S]);
  A0 := (0.825 - 0.34 * Alpha + 0.05 * Alpha * Alpha) * Power(Cos(Pi / 2 * S), 1.0 / Alpha);
  A1 := (0.415 - 0.071 * Alpha) * S;
  A3 := 2 * A0 + A1 - 1;
  A2 := 1 - A0 - A1 - A3;
  if R >= 0 then
  begin
    Result := A0 + A1 * R + A2 * R * R + A3 * R * R * R;
    if R > Result then Result := R;
  end
  else if R >= -2 then
    Result := A0 + A1 * R
  else
    Result := A0 - 2 * A1; // R < -2: truncate at the R = -2 value (continuous there)
end;

function NasgroRate(DeltaK, Kmax, R: Double; const Mat: TCrackGrowthMaterial): Double;
var
  f, U, bracket, threshTerm, toughnessDenom: Double;
begin
  if not Mat.HasNasgro then
    raise Exception.CreateFmt('NasgroRate: material "%s" has no NASGRO constants', [Mat.Name]);
  if Kmax <= 0 then
  begin
    Result := 0.0; // fully compressive cycle: crack stays closed, no growth
    Exit;
  end;
  if DeltaK <= 0 then
    raise Exception.CreateFmt('NasgroRate: DeltaK must be positive, got %g', [DeltaK]);
  if Kmax >= Mat.NasgroKc then
    raise Exception.CreateFmt(
      'NasgroRate: Kmax=%g has reached or passed the material''s fracture toughness ' +
      '(Kc=%g); this cycle represents immediate failure, not a finite growth rate',
      [Kmax, Mat.NasgroKc]);
  if DeltaK <= Mat.NasgroDeltaKth then
  begin
    Result := 0.0; // below threshold: no growth, not an error
    Exit;
  end;

  // NewmanClosureF needs Smax/sigma0, which this function does not take
  // as a parameter -- NASGRO material records in this unit don't carry
  // a flow stress or a remote-stress value (see fem_cg_types' comment:
  // that conversion needs the crack geometry, which belongs to the
  // not-yet-built K-solution layer). For now this uses Mat.NasgroAlpha
  // together with a fixed placeholder S=0.3 -- WRONG for anything but
  // illustration, and flagged loudly rather than silently: see
  // crackgrowth/docs/TODO.md. Once the K-solution layer exists, this
  // parameter list needs SmaxOverSigma0 added explicitly, the same way
  // DeltaK/Kmax/R already are, rather than buried inside Mat.
  f := NewmanClosureF(R, 0.3, Mat.NasgroAlpha);

  U := (1 - f) / (1 - R);
  bracket := U * DeltaK;
  threshTerm := 1 - Mat.NasgroDeltaKth / DeltaK;
  toughnessDenom := 1 - Kmax / Mat.NasgroKc;
  Result := Mat.NasgroC * Power(bracket, Mat.NasgroN) * Power(threshTerm, Mat.NasgroP)
    / Power(toughnessDenom, Mat.NasgroQ);
end;

// Law BestAvailableRate would pick (NASGRO > Forman > Walker > Paris);
// used to give LawUsed a meaningful value on a zero-growth cycle.
function PreferredLaw(const Mat: TCrackGrowthMaterial; const Caller: string): TGrowthLaw;
begin
  if Mat.HasNasgro then Result := glNasgro
  else if Mat.HasForman then Result := glForman
  else if Mat.HasWalker then Result := glWalker
  else if Mat.HasParis then Result := glParis
  else
    raise Exception.CreateFmt('%s: material "%s" has no usable growth law', [Caller, Mat.Name]);
end;

function ConservativeRate(DeltaK, Kmax, R: Double; const Mat: TCrackGrowthMaterial;
  out LawUsed: TGrowthLaw): Double;
var
  rate: Double;
  haveAny: Boolean;
begin
  Result := 0;
  haveAny := False;

  // Fully compressive cycle (Kmax <= 0): no law grows a closed crack.
  if Kmax <= 0 then
  begin
    LawUsed := PreferredLaw(Mat, 'ConservativeRate');
    Exit;
  end;

  if Mat.HasParis then
  begin
    rate := ParisRate(DeltaK, Mat.ParisC, Mat.ParisM);
    if (not haveAny) or (rate > Result) then begin Result := rate; LawUsed := glParis; end;
    haveAny := True;
  end;
  if Mat.HasWalker then
  begin
    rate := WalkerRate(DeltaK, R, Mat.WalkerC, Mat.WalkerM, Mat.WalkerGamma);
    if (not haveAny) or (rate > Result) then begin Result := rate; LawUsed := glWalker; end;
    haveAny := True;
  end;
  if Mat.HasForman then
  begin
    rate := FormanRate(DeltaK, R, Mat.FormanC, Mat.FormanN, Mat.FormanKc);
    if (not haveAny) or (rate > Result) then begin Result := rate; LawUsed := glForman; end;
    haveAny := True;
  end;
  if Mat.HasNasgro then
  begin
    rate := NasgroRate(DeltaK, Kmax, R, Mat);
    if (not haveAny) or (rate > Result) then begin Result := rate; LawUsed := glNasgro; end;
    haveAny := True;
  end;

  if not haveAny then
    raise Exception.CreateFmt('ConservativeRate: material "%s" has no usable growth law', [Mat.Name]);
end;

function BestAvailableRate(DeltaK, Kmax, R: Double; const Mat: TCrackGrowthMaterial;
  out LawUsed: TGrowthLaw): Double;
begin
  // Fully compressive cycle (Kmax <= 0): no law grows a closed crack.
  if Kmax <= 0 then
  begin
    LawUsed := PreferredLaw(Mat, 'BestAvailableRate');
    Result := 0.0;
    Exit;
  end;
  if Mat.HasNasgro then
  begin
    LawUsed := glNasgro;
    Result := NasgroRate(DeltaK, Kmax, R, Mat);
  end
  else if Mat.HasForman then
  begin
    LawUsed := glForman;
    Result := FormanRate(DeltaK, R, Mat.FormanC, Mat.FormanN, Mat.FormanKc);
  end
  else if Mat.HasWalker then
  begin
    LawUsed := glWalker;
    Result := WalkerRate(DeltaK, R, Mat.WalkerC, Mat.WalkerM, Mat.WalkerGamma);
  end
  else if Mat.HasParis then
  begin
    LawUsed := glParis;
    Result := ParisRate(DeltaK, Mat.ParisC, Mat.ParisM);
  end
  else
    raise Exception.CreateFmt('BestAvailableRate: material "%s" has no usable growth law', [Mat.Name]);
end;

end.
