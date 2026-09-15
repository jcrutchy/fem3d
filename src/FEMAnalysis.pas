unit FEMAnalysis;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, FEMModel, FEMElements, FEMMatrix, FEMValidation, FEMAnalysisCases, FEMHash;

type
  TAnalysisSetup = record
    LoadCaseID:Integer;
    SolverName:string;
    Options:TSolverOptions;
    AnalysisCaseID:Integer;
    AnalysisType:string;
  end;

  TAnalysisAudit = class
  private
    FLines:TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const Stage,MessageText:string);
    function AsText:string;
  end;

  TFEMAssembler = class
  public
    class procedure Assemble(const M:TFEMModel; const R:TElementRegistry;
      const Setup:TAnalysisSetup; G:TGlobalSystem; Numbering:TDOFNumbering;
      out Diagnostics:TStringList);
  end;

  TAnalysisEngine = class
  private
    FModel:TFEMModel;
    FRegistry:TElementRegistry;
    FSolver:TFEMSolver;
  public
    constructor Create(AModel:TFEMModel; ARegistry:TElementRegistry; ASolver:TFEMSolver);
    function Solve(const Setup:TAnalysisSetup):TAnalysisResult;
    function SolveCase(const A:TAnalysisCase):TAnalysisResult;
    property Solver:TFEMSolver read FSolver;
  end;

implementation

class procedure TFEMAssembler.Assemble(const M:TFEMModel; const R:TElementRegistry;
  const Setup:TAnalysisSetup; G:TGlobalSystem; Numbering:TDOFNumbering; out Diagnostics:TStringList);
var
  I,J,K,Cnt:Integer;
  E:TFEMElement;
  C:TElementContext;
  ER:TElementRecord;
  Ke: array of Double;
  Map: array of LongInt;
  NI:Integer;
begin
  Diagnostics:=TStringList.Create;
  C.Model:=M; C.Numbering:=Numbering;
  for I:=0 to High(M.Elements) do begin
    ER:=M.Elements[I]; E:=R.Find(ER.Kind);
    if E=nil then begin Diagnostics.Add(Format('Element %d: unsupported type "%s".',[ER.ID,ER.Kind])); Continue; end;
    Cnt:=E.DofCount;
    SetLength(Ke,Cnt*Cnt); SetLength(Map,Cnt);
    E.GetDofMap(C,ER,Map);
    E.Stiffness(C,ER,Ke);
    for J:=0 to Cnt-1 do for K:=0 to Cnt-1 do G.Add(Map[J],Map[K],Ke[J*Cnt+K]);
  end;

  for I:=0 to High(M.Loads) do if M.Loads[I].LoadCaseID=Setup.LoadCaseID then begin
    NI:=M.FindNode(M.Loads[I].NodeID);
    if NI>=0 then for J:=0 to 5 do begin K:=Numbering.DOF(M.Loads[I].NodeID,J); if K>=0 then G.F[K]:=G.F[K]+M.Loads[I].Value[J]; end;
  end;

  for I:=0 to High(M.Nodes) do for J:=0 to 5 do
    if M.Nodes[I].Restraint[J] then begin K:=Numbering.DOF(M.Nodes[I].ID,J); if K>=0 then G.ApplyZeroConstraint(K); end;

end;

constructor TAnalysisEngine.Create(AModel:TFEMModel; ARegistry:TElementRegistry; ASolver:TFEMSolver);
begin inherited Create; FModel:=AModel; FRegistry:=ARegistry; FSolver:=ASolver; end;

constructor TAnalysisAudit.Create;
begin inherited Create; FLines:=TStringList.Create; end;
destructor TAnalysisAudit.Destroy; begin FLines.Free; inherited Destroy; end;
procedure TAnalysisAudit.Add(const Stage,MessageText:string); begin FLines.Add(Format('%s: %s',[Stage,MessageText])); end;
function TAnalysisAudit.AsText:string; begin Result:=FLines.Text; end;

function TAnalysisEngine.Solve(const Setup:TAnalysisSetup):TAnalysisResult;
var G:TGlobalSystem; D,AuditLines:TStringList; N:TDOFNumbering; V:TFEMValidationReport; Audit:TAnalysisAudit; I:Integer; SolverResult:TAnalysisResult;
begin
  Result:=TAnalysisResult.Create;
  Audit:=TAnalysisAudit.Create; V:=TFEMValidationReport.Create; N:=FModel.CreateDOFNumbering;
  try
    Result.AnalysisCaseID:=Setup.AnalysisCaseID; Result.AnalysisType:=Setup.AnalysisType;
    Result.ModelFingerprint:=ModelFingerprint(FModel);
    Audit.Add('MODEL',Format('%d nodes, %d elements, %d DOF',[Length(FModel.Nodes),Length(FModel.Elements),N.Count]));
    if Setup.AnalysisCaseID<>0 then Audit.Add('ANALYSIS',Format('case %d; type=%s',[Setup.AnalysisCaseID,Setup.AnalysisType]));
    Audit.Add('PROVENANCE','Model fingerprint='+Result.ModelFingerprint);
    if FModel.FindLoadCase(Setup.LoadCaseID)<0 then begin Result.Success:=False; Result.MessageText:=Format('Load case %d does not exist.',[Setup.LoadCaseID]); AuditLines:=TStringList.Create; try AuditLines.Text:=Audit.AsText; Result.AuditTrail.AddStrings(AuditLines); finally AuditLines.Free end; Exit; end;
    if not V.Validate(FModel) then begin
      Result.Success:=False; Result.MessageText:='Model validation failed.'+LineEnding+V.AsText;
      Result.AuditTrail.Add('MODEL: '+Format('%d nodes, %d elements, %d DOF',[Length(FModel.Nodes),Length(FModel.Elements),N.Count])); Result.AuditTrail.Add('VALIDATION: failed'); Exit;
    end;
    Audit.Add('VALIDATION',Format('passed; %d warnings',[V.WarningCount]));
    G:=TGlobalSystem.Create(N.Count);
    try
      TFEMAssembler.Assemble(FModel,FRegistry,Setup,G,N,D);
      try
        for I:=0 to D.Count-1 do Audit.Add('ASSEMBLY',D[I]);
        if D.Count>0 then begin
          Result.Success:=False;
          Result.MessageText:='Assembly failed; unsupported or invalid element definitions were not silently ignored.'+LineEnding+Audit.AsText;
          Exit;
        end;
      finally D.Free; end;
      Audit.Add('CONSTRAINTS',Format('%d constrained DOF',[G.ConstrainedCount]));
      SolverResult:=FSolver.Solve(G,Setup.Options);
      SolverResult.AnalysisCaseID:=Setup.AnalysisCaseID; SolverResult.AnalysisType:=Setup.AnalysisType; SolverResult.ModelFingerprint:=ModelFingerprint(FModel);
      AuditLines:=TStringList.Create; try AuditLines.Text:=Audit.AsText; SolverResult.AuditTrail.AddStrings(AuditLines); finally AuditLines.Free end;
      SolverResult.MessageText:=SolverResult.MessageText+LineEnding+Format('Energy balance relative error %.6g.',[SolverResult.EnergyBalanceError])+LineEnding+'Audit trail:'+LineEnding+Audit.AsText;
      Result.Free; Result:=SolverResult;
    finally G.Free; end;
  finally Audit.Free; V.Free; N.Free; end;
end;

function TAnalysisEngine.SolveCase(const A:TAnalysisCase):TAnalysisResult;
var Setup:TAnalysisSetup; LS:TLinearStaticSettings;
begin
  FillChar(Setup,SizeOf(Setup),0); Setup.AnalysisCaseID:=A.ID; Setup.AnalysisType:=A.TypeName; Setup.LoadCaseID:=A.LoadCaseID;
  if A.Settings is TLinearStaticSettings then begin LS:=TLinearStaticSettings(A.Settings); Setup.SolverName:=LS.SolverName; Setup.Options.PivotTolerance:=LS.PivotTolerance; Setup.Options.ComputeResidual:=True; end;
  if A.AnalysisType<>atLinearStatic then begin
    Result:=TAnalysisResult.Create; Result.Success:=False; Result.AnalysisCaseID:=A.ID; Result.AnalysisType:=A.TypeName; Result.ModelFingerprint:=ModelFingerprint(FModel); Result.AnalysisFingerprint:=AnalysisFingerprint(A); Result.MessageText:='Analysis type '+A.TypeName+' is defined but its numerical solver is not implemented yet.'; Result.AuditTrail.Add('ANALYSIS: case '+IntToStr(A.ID)+'; type='+A.TypeName); Result.AuditTrail.Add('PROVENANCE: Model fingerprint='+Result.ModelFingerprint); Result.AuditTrail.Add('PROVENANCE: Analysis fingerprint='+Result.AnalysisFingerprint); Exit;
  end;
  Result:=Solve(Setup); Result.AnalysisFingerprint:=AnalysisFingerprint(A); Result.AuditTrail.Add('PROVENANCE: Analysis fingerprint='+Result.AnalysisFingerprint);
end;

end.

