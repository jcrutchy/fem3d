program verify;
{$mode objfpc}{$H+}
uses SysUtils, FEMVerification;
var V:TVerificationResult; Pass,AllPass:Boolean; I:Integer;
procedure Run(const B:Boolean; const V:TVerificationResult);
begin
  if B then Writeln('PASS: ',V.Name) else Writeln('FAIL: ',V.Name);
  Writeln('  ',V.MessageText);
end;
begin
  AllPass:=True;
  Pass:=TFEMVerification.CantileverTipDisplacement(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.CantileverTipDisplacementY(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.CantileverAxialDisplacement(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.CantileverTorsion(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.CantileverReactionEquilibrium(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.MechanismDetection(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.ModelValidation(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.BeamStiffnessSymmetry(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.EnergyBalance(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.BeamEndForceRecovery(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.AuditTrailRetention(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.AnalysisCasePersistence(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.FingerprintSensitivity(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.ResultExpression(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Pass:=TFEMVerification.DisplayManagerVisibility(V); Run(Pass,V); AllPass:=AllPass and Pass;
  Writeln;
  if AllPass then begin Writeln('ALL VERIFICATIONS PASSED'); Halt(0); end
  else begin Writeln('VERIFICATION FAILURE'); Halt(1); end;
end.
