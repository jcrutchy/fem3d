unit FEMResults;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math;

type
  TFEMResultDocument = class
  private
    FValues:TStringList;
    FAudit:TStringList;
    FErrors:TStringList;
    FSection:string;
  public
    Status:string;
    MessageText:string;
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
    property Errors:TStringList read FErrors;
  end;

implementation

constructor TFEMResultDocument.Create;
begin inherited Create; FValues:=TStringList.Create; FAudit:=TStringList.Create; FErrors:=TStringList.Create; Clear; end;
destructor TFEMResultDocument.Destroy; begin FErrors.Free; FAudit.Free;FValues.Free;inherited Destroy;end;
procedure TFEMResultDocument.Clear;
begin Status:=''; MessageText:=''; AnalysisCaseID:=0; AnalysisName:=''; AnalysisType:=''; Solver:=''; SolverVersion:=''; SolverKernel:=''; SolverKernelRevision:=''; ModelContract:=''; ResultContract:=''; ModelFingerprint:=''; AnalysisFingerprint:=''; DOFCount:=0; ConstrainedDOF:=0; ResidualNorm:=0; MaxReaction:=0; StrainEnergy:=0; ExternalWork:=0; EnergyBalanceError:=0; SetLength(Displacements,0); SetLength(Reactions,0); FAudit.Clear; FErrors.Clear; FValues.Clear; FSection:=''; end;

procedure TFEMResultDocument.LoadFromFile(const FileName:string);
var
  L:TStringList;
  I,P,Index,LineNo:Integer;
  Key,Val,Line,Section:string;
  D:Double;
  HeaderSeen,StatusSeen:Boolean;
  FS:TFormatSettings;

  procedure Fail(const Msg:string);
  begin
    raise Exception.CreateFmt('Result parse error at line %d: %s',[LineNo,Msg]);
  end;

  function ParseInt(const S,What:string):Integer;
  begin
    if not TryStrToInt(Trim(S),Result) then Fail('invalid integer for '+What+': "'+S+'"');
  end;

  function ParseFloat(const S,What:string):Double;
  begin
    if not TryStrToFloat(Trim(S),Result,FS) then Fail('invalid number for '+What+': "'+S+'"');
    if IsNan(Result) or IsInfinite(Result) then Fail('non-finite number for '+What+': "'+S+'"');
  end;

  procedure StoreVectorValue(const Target:string; const Index:Integer; const Value:Double);
  begin
    if Index<=0 then Fail(Target+' index must be positive');
    if (DOFCount>0) and (Index>DOFCount) then
      Fail(Format('%s index %d exceeds DOFCount %d',[Target,Index,DOFCount]));
    if Target='DISPLACEMENTS' then begin
      if FValues.IndexOf('D:'+IntToStr(Index))>=0 then Fail(Format('duplicate displacement index %d',[Index]));
      FValues.Add('D:'+IntToStr(Index));
      if Length(Displacements)<Index then SetLength(Displacements,Index);
      Displacements[Index-1]:=Value;
    end else begin
      if FValues.IndexOf('R:'+IntToStr(Index))>=0 then Fail(Format('duplicate reaction index %d',[Index]));
      FValues.Add('R:'+IntToStr(Index));
      if Length(Reactions)<Index then SetLength(Reactions,Index);
      Reactions[Index-1]:=Value;
    end;
  end;

begin
  Clear;
  if not FileExists(FileName) then raise Exception.Create('Result file does not exist: '+FileName);
  FS:=DefaultFormatSettings;
  FS.DecimalSeparator:='.';
  FS.ThousandSeparator:=',';
  L:=TStringList.Create;
  try
    try L.LoadFromFile(FileName); except on E:Exception do raise Exception.CreateFmt('Unable to read result file "%s": %s',[FileName,E.Message]); end;
    HeaderSeen:=False; StatusSeen:=False; Section:=''; LineNo:=0;
    for I:=0 to L.Count-1 do begin
      Inc(LineNo);
      Line:=Trim(L[I]);
      if Line='' then Continue;
      if (Line[1]=';') or (Line[1]='#') then Continue;

      if not HeaderSeen then begin
        HeaderSeen:=True;
        P:=Pos(' ',Line);
        if P<=0 then Fail('invalid FEM3D result header. Expected "FEM3D_RESULT <version>"');
        if not SameText(Trim(Copy(Line,1,P-1)),'FEM3D_RESULT') then Fail('invalid FEM3D result header.');
        if not TryStrToFloat(Trim(Copy(Line,P+1,MaxInt)),D,FS) then Fail('invalid FEM3D result format version');
        if D<=0 then Fail('FEM3D result format version must be positive');
        Continue;
      end;

      if (Line[1]='[') and (Line[Length(Line)]=']') then begin
        Section:=UpperCase(Trim(Copy(Line,2,Length(Line)-2)));
        if (Section<>'DISPLACEMENTS') and (Section<>'REACTIONS') and
           (Section<>'ERRORS') and (Section<>'AUDIT_TRAIL') and (Section<>'SOLVER_PROVENANCE') then
          Fail('unknown result section ['+Section+']');
        Continue;
      end;

      if (Section='DISPLACEMENTS') or (Section='REACTIONS') then begin
        P:=Pos(' ',Line);
        if P<=0 then Fail('result vector line must contain index and value');
        Index:=ParseInt(Copy(Line,1,P-1),'result vector index');
        D:=ParseFloat(Copy(Line,P+1,MaxInt),'result vector value');
        StoreVectorValue(Section,Index,D);
        Continue;
      end;

      if (Section='ERRORS') or (Section='AUDIT_TRAIL') or (Section='SOLVER_PROVENANCE') then begin
        if Section='ERRORS' then FErrors.Add(L[I]) else FAudit.Add(L[I]);
        Continue;
      end;

      P:=Pos('=',Line);
      if P<=0 then Fail('result property line must be Key=Value');
      Key:=Trim(Copy(Line,1,P-1)); Val:=Trim(Copy(Line,P+1,MaxInt));
      if Key='' then Fail('result property key is empty');
      if SameText(Key,'Status') then begin Status:=Val; StatusSeen:=True; end
      else if SameText(Key,'Message') then MessageText:=Val
      else if SameText(Key,'SolverVersion') then SolverVersion:=Val
      else if SameText(Key,'SolverKernel') then SolverKernel:=Val
      else if SameText(Key,'SolverKernelRevision') then SolverKernelRevision:=Val
      else if SameText(Key,'ModelContract') then ModelContract:=Val
      else if SameText(Key,'ResultContract') then ResultContract:=Val
      else if SameText(Key,'AnalysisCase') then AnalysisCaseID:=ParseInt(Val,'AnalysisCase')
      else if SameText(Key,'AnalysisName') then AnalysisName:=Val
      else if SameText(Key,'AnalysisType') then AnalysisType:=Val
      else if SameText(Key,'Solver') then Solver:=Val
      else if SameText(Key,'ModelFingerprint') then ModelFingerprint:=Val
      else if SameText(Key,'AnalysisFingerprint') then AnalysisFingerprint:=Val
      else if SameText(Key,'DOFCount') then DOFCount:=ParseInt(Val,'DOFCount')
      else if SameText(Key,'ConstrainedDOF') then ConstrainedDOF:=ParseInt(Val,'ConstrainedDOF')
      else if SameText(Key,'ResidualNorm') then ResidualNorm:=ParseFloat(Val,'ResidualNorm')
      else if SameText(Key,'MaxReaction') then MaxReaction:=ParseFloat(Val,'MaxReaction')
      else if SameText(Key,'StrainEnergy') then StrainEnergy:=ParseFloat(Val,'StrainEnergy')
      else if SameText(Key,'ExternalWork') then ExternalWork:=ParseFloat(Val,'ExternalWork')
      else if SameText(Key,'EnergyBalanceError') then EnergyBalanceError:=ParseFloat(Val,'EnergyBalanceError')
      else Fail('unknown result property "'+Key+'"');
    end;
    if not HeaderSeen then raise Exception.Create('Result parse error: result file is empty; FEM3D_RESULT header is required.');
    if not StatusSeen then raise Exception.Create('Result parse error: Status is required.');
    if not SameText(Status,'OK') and not SameText(Status,'FAILURE') then
      raise Exception.Create('Result parse error: Status must be OK or FAILURE.');
    if DOFCount<0 then raise Exception.Create('Result parse error: DOFCount cannot be negative.');
    if ConstrainedDOF<0 then raise Exception.Create('Result parse error: ConstrainedDOF cannot be negative.');
    if (DOFCount>0) and (ConstrainedDOF>DOFCount) then raise Exception.Create('Result parse error: ConstrainedDOF exceeds DOFCount.');
    if (DOFCount>0) and (Length(Displacements)>DOFCount) then raise Exception.Create('Result parse error: displacement data exceeds DOFCount.');
    if (DOFCount>0) and (Length(Reactions)>DOFCount) then raise Exception.Create('Result parse error: reaction data exceeds DOFCount.');
  finally
    L.Free;
  end;
end;

function TFEMResultDocument.Summary:string;
begin
  Result:=Format('Status: %s'+LineEnding+'Analysis case: %d %s (%s)'+LineEnding+'Solver: %s (v%s, %s)'+LineEnding+'DOF: %d, constrained: %d'+LineEnding+'Residual norm: %.6g'+LineEnding+'Maximum reaction: %.6g'+LineEnding+'Strain energy: %.12g'+LineEnding+'External work: %.12g'+LineEnding+'Energy balance error: %.6g',[Status,AnalysisCaseID,AnalysisName,AnalysisType,Solver,SolverVersion,SolverKernel,DOFCount,ConstrainedDOF,ResidualNorm,MaxReaction,StrainEnergy,ExternalWork,EnergyBalanceError]);
end;

end.
