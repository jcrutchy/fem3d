program results_test;

// Checks the failure-criterion helpers in fem_results against textbook
// values: von Mises and Tresca for the classic stress states, and the
// plane-stress principal-stress calculation. (Element force recovery itself
// is covered by regression cases 020-024, which compare against hand
// statics.) Exit code 0 = all passed.

{$mode objfpc}{$H+}

uses
  SysUtils, Math, fem_results;

var
  Fails, Checks: Integer;

procedure Near(const Name: string; Actual, Expected: Double; Tol: Double = 1E-9);
begin
  Inc(Checks);
  if Abs(Actual - Expected) <= Tol * (1.0 + Abs(Expected)) then
    WriteLn('PASS  ', Name)
  else
  begin
    Inc(Fails);
    WriteLn('FAIL  ', Name, '  expected ', Expected:0:12, ' got ', Actual:0:12);
  end;
end;

var
  P: TPlaneStress;
begin
  Fails := 0; Checks := 0;

  // sigma-tau (beam fibre) forms
  Near('von Mises, pure tension 100', VonMisesSigmaTau(100, 0), 100);
  Near('von Mises, pure shear 100 = sqrt(3)*100', VonMisesSigmaTau(0, 100), Sqrt(3.0) * 100);
  Near('Tresca, pure shear 100 = 2*100', TrescaSigmaTau(0, 100), 200);
  Near('von Mises, sigma 80 + tau 60 = sqrt(6400+10800)', VonMisesSigmaTau(80, 60), Sqrt(17200.0));
  Near('Tresca, sigma 80 + tau 60 = sqrt(6400+14400)', TrescaSigmaTau(80, 60), Sqrt(20800.0));

  // plane stress
  P := PlaneStressState(100, 0, 0);
  Near('uniaxial: S1', P.S1, 100); Near('uniaxial: S2', P.S2, 0);
  Near('uniaxial: von Mises', P.VonMises, 100); Near('uniaxial: Tresca', P.Tresca, 100);

  P := PlaneStressState(0, 0, 50);
  Near('pure shear: S1 = tau', P.S1, 50); Near('pure shear: S2 = -tau', P.S2, -50);
  Near('pure shear: principal angle 45 deg', P.Angle, Pi / 4);
  Near('pure shear: von Mises = sqrt(3) tau', P.VonMises, Sqrt(3.0) * 50);
  Near('pure shear: Tresca = 2 tau', P.Tresca, 100);

  P := PlaneStressState(100, 100, 0);
  Near('equibiaxial: von Mises = sigma', P.VonMises, 100);
  Near('equibiaxial: Tresca = sigma (third principal stress is 0)', P.Tresca, 100);

  P := PlaneStressState(100, -100, 0);
  Near('tension-compression: von Mises = sqrt(3) sigma', P.VonMises, Sqrt(3.0) * 100);
  Near('tension-compression: Tresca = 2 sigma', P.Tresca, 200);

  P := PlaneStressState(120, 40, 30);
  Near('general: S1+S2 = trace', P.S1 + P.S2, 160);
  Near('general: S1*S2 = determinant', P.S1 * P.S2, 120 * 40 - 30 * 30);
  Near('general: von Mises from principals', P.VonMises, Sqrt(P.S1 * P.S1 - P.S1 * P.S2 + P.S2 * P.S2));

  WriteLn;
  if Fails = 0 then
  begin
    WriteLn('ALL ', Checks, ' CHECKS PASSED');
    Halt(0);
  end
  else
  begin
    WriteLn(Fails, ' of ', Checks, ' CHECKS FAILED');
    Halt(1);
  end;
end.
