unit FEMResults;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math;

type
  TFEMResultDocument = class
  private
    FValues:TStringList;
    FAudit:TStringList;
    FSection:string;
  public
    Status:string;
    AnalysisCaseID:Integer;
    AnalysisName:string;
    AnalysisType:string;
    Solver:string;
    SolverVersion:string;
    SolverKernel:string;
    SolverKernelRevision:string;
    ModelContract:string;
    ResultContract:string;
    ModelFingerprint:string;
    AnalysisFingerprint:string;
    DOFCount:Integer;
    ConstrainedDOF:Integer;
    ResidualNorm:Double;
    MaxReaction:Double;
    StrainEnergy:Double;
    ExternalWork:Double;
    EnergyBalanceError:Double;
    Displacements:array of Double;
    Reactions:array of Double;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure LoadFromFile(const FileName:string);
    function Summary:string;
    property AuditTrail:TStringList read FAudit;
  end;

implementation

constructor TFEMResultDocument.Create;
begin inherited Create; FValues:=TStringList.Create; FAudit:=TStringList.Create; Clear; end;
destructor TFEMResultDocument.Destroy; begin FAudit.Free;FValues.Free;inherited Destroy;end;
procedure TFEMResultDocument.Clear;
begin Status:=''; AnalysisCaseID:=0; AnalysisName:=''; AnalysisType:=''; Solver:=''; SolverVersion:=''; SolverKernel:=''; SolverKernelRevision:=''; ModelContract:=''; ResultContract:=''; ModelFingerprint:=''; AnalysisFingerprint:=''; DOFCount:=0; ConstrainedDOF:=0; ResidualNorm:=0; MaxReaction:=0; StrainEnergy:=0; ExternalWork:=0; EnergyBalanceError:=0; SetLength(Displacements,0); SetLength(Reactions,0); FAudit.Clear; FValues.Clear; FSection:=''; end;

procedure TFEMResultDocument.LoadFromFile(const FileName:string);
var L:TStringList; I,P:Integer; Key,Val:string; Index:Integer; D:Double;
begin
  Clear; L:=TStringList.Create; try L.LoadFromFile(FileName);
    for I:=0 to L.Count-1 do begin
      if Trim(L[I])='' then Continue;
      if (Copy(Trim(L[I]),1,1)='[') and (Copy(Trim(L[I]),Length(Trim(L[I])),1)=']') then begin FSection:=UpperCase(Copy(Trim(L[I]),2,Length(Trim(L[I]))-2)); Continue; end;
      if (FSection='AUDIT_TRAIL') or (FSection='SOLVER_PROVENANCE') then begin FAudit.Add(L[I]); Continue; end;
      if (FSection='DISPLACEMENTS') or (FSection='REACTIONS') then begin
        P:=Pos(' ',Trim(L[I])); if P<=0 then Continue; Key:=Trim(Copy(Trim(L[I]),1,P-1)); Val:=Trim(Copy(Trim(L[I]),P+1,MaxInt));
        Index:=StrToIntDef(Key,0); D:=StrToFloatDef(Val,0);
        if Index>0 then begin
          if FSection='DISPLACEMENTS' then begin if Length(Displacements)<Index then SetLength(Displacements,Index); Displacements[Index-1]:=D; end
          else begin if Length(Reactions)<Index then SetLength(Reactions,Index); Reactions[Index-1]:=D; end;
        end;
        Continue;
      end;
      P:=Pos('=',L[I]); if P<=0 then Continue; Key:=Trim(Copy(L[I],1,P-1)); Val:=Trim(Copy(L[I],P+1,MaxInt));
      if SameText(Key,'Status') then Status:=Val else if SameText(Key,'AnalysisCase') then AnalysisCaseID:=StrToIntDef(Val,0)
      else if SameText(Key,'AnalysisName') then AnalysisName:=Val else if SameText(Key,'AnalysisType') then AnalysisType:=Val else if SameText(Key,'Solver') then Solver:=Val
      else if SameText(Key,'ModelFingerprint') then ModelFingerprint:=Val else if SameText(Key,'AnalysisFingerprint') then AnalysisFingerprint:=Val
      else if SameText(Key,'DOFCount') then DOFCount:=StrToIntDef(Val,0) else if SameText(Key,'ConstrainedDOF') then ConstrainedDOF:=StrToIntDef(Val,0)
      else if SameText(Key,'ResidualNorm') then ResidualNorm:=StrToFloatDef(Val,0) else if SameText(Key,'MaxReaction') then MaxReaction:=StrToFloatDef(Val,0)
      else if SameText(Key,'StrainEnergy') then StrainEnergy:=StrToFloatDef(Val,0) else if SameText(Key,'ExternalWork') then ExternalWork:=StrToFloatDef(Val,0)
      else if SameText(Key,'EnergyBalanceError') then EnergyBalanceError:=StrToFloatDef(Val,0);
    end;
  finally L.Free end;
end;

function TFEMResultDocument.Summary:string;
begin
  Result:=Format('Status: %s'+LineEnding+'Analysis case: %d %s (%s)'+LineEnding+'Solver: %s (v%s, %s)'+LineEnding+'DOF: %d, constrained: %d'+LineEnding+'Residual norm: %.6g'+LineEnding+'Maximum reaction: %.6g'+LineEnding+'Strain energy: %.12g'+LineEnding+'External work: %.12g'+LineEnding+'Energy balance error: %.6g',[Status,AnalysisCaseID,AnalysisName,AnalysisType,Solver,SolverVersion,SolverKernel,DOFCount,ConstrainedDOF,ResidualNorm,MaxReaction,StrainEnergy,ExternalWork,EnergyBalanceError]);
end;

end.

