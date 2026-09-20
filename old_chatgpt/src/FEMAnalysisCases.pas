unit FEMAnalysisCases;
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, FEMMatrix;

type
  TAnalysisType = (atLinearStatic, atLinearBuckling, atModal, atLinearDynamic,
    atNonlinearStatic, atNonlinearTransient);

  TAnalysisSettings = class
  public
    function AnalysisType:TAnalysisType; virtual; abstract;
    function TypeName:string; virtual; abstract;
    function Clone:TAnalysisSettings; virtual; abstract;
    procedure WriteTo(const L:TStringList); virtual; abstract;
    procedure ReadFrom(const Key,Value:string); virtual; abstract;
  end;

  TGenericAnalysisSettings = class(TAnalysisSettings)
  private FType:TAnalysisType;
  public
    constructor Create(AType:TAnalysisType);
    function AnalysisType:TAnalysisType; override;
    function TypeName:string; override;
    function Clone:TAnalysisSettings; override;
    procedure WriteTo(const L:TStringList); override;
    procedure ReadFrom(const Key,Value:string); override;
  end;

  TLinearStaticSettings = class(TAnalysisSettings)
  public
    SolverName:string;
    MatrixStorage:TMatrixStorageKind;
    PivotTolerance:Double;
    ResidualTolerance:Double;
    CheckEquilibrium:Boolean;
    CheckEnergy:Boolean;
    RecoverElementForces:Boolean;
    StoreSolverData:Boolean;
    function AnalysisType:TAnalysisType; override;
    function TypeName:string; override;
    function Clone:TAnalysisSettings; override;
    procedure WriteTo(const L:TStringList); override;
    procedure ReadFrom(const Key,Value:string); override;
  end;

  TBucklingSettings = class(TAnalysisSettings)
  public
    SolverName:string;
    MatrixStorage:TMatrixStorageKind;
    EigenvalueCount:Integer;
    Shift:Double;
    Tolerance:Double;
    MaxIterations:Integer;
    NormalizeModes:Boolean;
    StoreModeShapes:Boolean;
    CheckSymmetry:Boolean;
    function AnalysisType:TAnalysisType; override;
    function TypeName:string; override;
    function Clone:TAnalysisSettings; override;
    procedure WriteTo(const L:TStringList); override;
    procedure ReadFrom(const Key,Value:string); override;
  end;

  TNonlinearStaticSettings = class(TAnalysisSettings)
  public
    SolverName:string;
    InitialLoadSteps:Integer;
    MaxIterations:Integer;
    ForceTolerance:Double;
    DisplacementTolerance:Double;
    MinimumStep:Double;
    MaximumStep:Double;
    LineSearch:Boolean;
    MaxCutbacks:Integer;
    StoreIterationHistory:Boolean;
    function AnalysisType:TAnalysisType; override;
    function TypeName:string; override;
    function Clone:TAnalysisSettings; override;
    procedure WriteTo(const L:TStringList); override;
    procedure ReadFrom(const Key,Value:string); override;
  end;

  TAnalysisCase = class
  private
    FSettings:TAnalysisSettings;
  public
    ID:Integer;
    Name:string;
    LoadCaseID:Integer;
    ResultID:string;
    constructor Create(AType:TAnalysisType; const AName:string);
    destructor Destroy; override;
    function AnalysisType:TAnalysisType;
    function TypeName:string;
    function Settings:TAnalysisSettings;
    procedure SetSettings(ASettings:TAnalysisSettings);
    procedure WriteTo(const L:TStringList);
  end;

  TAnalysisCaseCollection = class
  private
    FItems:array of TAnalysisCase;
    FNextID:Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Add(AType:TAnalysisType; const AName:string):TAnalysisCase;
    function AddWithID(ID:Integer; AType:TAnalysisType; const AName:string):TAnalysisCase;
    function Find(ID:Integer):TAnalysisCase;
    procedure Delete(ID:Integer);
    function Count:Integer;
    function Item(Index:Integer):TAnalysisCase;
    function NextID:Integer;
  end;

function AnalysisTypeToString(T:TAnalysisType):string;
function StringToAnalysisType(const S:string; out T:TAnalysisType):Boolean;
function MatrixStorageToString(S:TMatrixStorageKind):string;
function StringToMatrixStorage(const S:string; out V:TMatrixStorageKind):Boolean;

implementation

function AnalysisTypeToString(T:TAnalysisType):string;
begin
  case T of
    atLinearStatic:Result:='LinearStatic'; atLinearBuckling:Result:='LinearBuckling';
    atModal:Result:='Modal'; atLinearDynamic:Result:='LinearDynamic';
    atNonlinearStatic:Result:='NonlinearStatic'; atNonlinearTransient:Result:='NonlinearTransient';
  end;
end;

function StringToAnalysisType(const S:string; out T:TAnalysisType):Boolean;
var U:string;
begin
  U:=UpperCase(Trim(S)); U:=StringReplace(U,'_','',[rfReplaceAll]); U:=StringReplace(U,'-','',[rfReplaceAll]); Result:=True;
  if U='LINEARSTATIC' then T:=atLinearStatic else if U='LINEARBUCKLING' then T:=atLinearBuckling
  else if U='MODAL' then T:=atModal else if U='LINEARDYNAMIC' then T:=atLinearDynamic
  else if U='NONLINEARSTATIC' then T:=atNonlinearStatic else if U='NONLINEARTRANSIENT' then T:=atNonlinearTransient
  else Result:=False;
end;

function MatrixStorageToString(S:TMatrixStorageKind):string;
begin if S=msSkyline then Result:='Skyline' else Result:='Dense'; end;
function StringToMatrixStorage(const S:string; out V:TMatrixStorageKind):Boolean;
begin if SameText(Trim(S),'Skyline') then V:=msSkyline else if SameText(Trim(S),'Dense') then V:=msDense else begin Result:=False; Exit; end; Result:=True; end;

function BoolText(V:Boolean):string; begin if V then Result:='1' else Result:='0'; end;
function ParseSettingInt(const S,Key:string):Integer;
begin
  if not TryStrToInt(Trim(S),Result) then raise EConvertError.CreateFmt('Invalid integer setting %s="%s"',[Key,S]);
end;
function ParseSettingFloat(const S,Key:string):Double;
var FS:TFormatSettings;
begin
  FS:=DefaultFormatSettings; FS.DecimalSeparator:='.'; FS.ThousandSeparator:=',';
  if not TryStrToFloat(Trim(S),Result,FS) then raise EConvertError.CreateFmt('Invalid numeric setting %s="%s"',[Key,S]);
  if IsNan(Result) or IsInfinite(Result) then raise EConvertError.CreateFmt('Non-finite numeric setting %s="%s"',[Key,S]);
end;
function ParseSettingBool(const S,Key:string):Boolean;
begin
  if SameText(Trim(S),'1') or SameText(Trim(S),'true') or SameText(Trim(S),'yes') then Result:=True
  else if SameText(Trim(S),'0') or SameText(Trim(S),'false') or SameText(Trim(S),'no') then Result:=False
  else raise EConvertError.CreateFmt('Invalid boolean setting %s="%s"',[Key,S]);
end;
function TextBool(const S:string):Boolean; begin Result:=ParseSettingBool(S,'boolean'); end;

constructor TGenericAnalysisSettings.Create(AType:TAnalysisType); begin inherited Create; FType:=AType; end;
function TGenericAnalysisSettings.AnalysisType:TAnalysisType; begin Result:=FType; end;
function TGenericAnalysisSettings.TypeName:string; begin Result:=AnalysisTypeToString(FType); end;
function TGenericAnalysisSettings.Clone:TAnalysisSettings; begin Result:=TGenericAnalysisSettings.Create(FType); end;
procedure TGenericAnalysisSettings.WriteTo(const L:TStringList); begin end;
procedure TGenericAnalysisSettings.ReadFrom(const Key,Value:string); begin end;

function TLinearStaticSettings.AnalysisType:TAnalysisType; begin Result:=atLinearStatic; end;
function TLinearStaticSettings.TypeName:string; begin Result:='LinearStatic'; end;
function TLinearStaticSettings.Clone:TAnalysisSettings;
var R:TLinearStaticSettings;
begin
  R:=TLinearStaticSettings.Create; R.SolverName:=SolverName; R.MatrixStorage:=MatrixStorage;
  R.PivotTolerance:=PivotTolerance; R.ResidualTolerance:=ResidualTolerance;
  R.CheckEquilibrium:=CheckEquilibrium; R.CheckEnergy:=CheckEnergy;
  R.RecoverElementForces:=RecoverElementForces; R.StoreSolverData:=StoreSolverData; Result:=R;
end;

procedure TLinearStaticSettings.WriteTo(const L:TStringList);
begin
  L.Add('Solver='+SolverName); L.Add('MatrixStorage='+MatrixStorageToString(MatrixStorage));
  L.Add(Format('PivotTolerance=%.17g',[PivotTolerance]));
  L.Add(Format('ResidualTolerance=%.17g',[ResidualTolerance]));
  L.Add('CheckEquilibrium='+BoolText(CheckEquilibrium)); L.Add('CheckEnergy='+BoolText(CheckEnergy));
  L.Add('RecoverElementForces='+BoolText(RecoverElementForces)); L.Add('StoreSolverData='+BoolText(StoreSolverData));
end;

procedure TLinearStaticSettings.ReadFrom(const Key,Value:string);
var V:TMatrixStorageKind;
begin
  if SameText(Key,'Solver') then begin
    SolverName:=Value;
    if SameText(Trim(Value),'ReferenceDenseLDLT') then SolverName:='Reference dense LDL^T';
  end
  else if SameText(Key,'MatrixStorage') then begin
    if not StringToMatrixStorage(Value,V) then raise EConvertError.CreateFmt('Invalid matrix storage setting %s="%s"',[Key,Value]);
    MatrixStorage:=V;
  end
  else if SameText(Key,'PivotTolerance') then PivotTolerance:=ParseSettingFloat(Value,Key)
  else if SameText(Key,'ResidualTolerance') then ResidualTolerance:=ParseSettingFloat(Value,Key)
  else if SameText(Key,'Tolerance') then begin
    PivotTolerance:=ParseSettingFloat(Value,Key);
    ResidualTolerance:=ParseSettingFloat(Value,Key);
  end
  else if SameText(Key,'CheckEquilibrium') then CheckEquilibrium:=ParseSettingBool(Value,Key)
  else if SameText(Key,'CheckEnergy') then CheckEnergy:=ParseSettingBool(Value,Key)
  else if SameText(Key,'RecoverElementForces') then RecoverElementForces:=ParseSettingBool(Value,Key)
  else if SameText(Key,'StoreSolverData') then StoreSolverData:=ParseSettingBool(Value,Key);
end;

function TBucklingSettings.AnalysisType:TAnalysisType; begin Result:=atLinearBuckling; end;
function TBucklingSettings.TypeName:string; begin Result:='LinearBuckling'; end;
function TBucklingSettings.Clone:TAnalysisSettings;
var R:TBucklingSettings;
begin
  R:=TBucklingSettings.Create; R.SolverName:=SolverName; R.MatrixStorage:=MatrixStorage; R.EigenvalueCount:=EigenvalueCount;
  R.Shift:=Shift; R.Tolerance:=Tolerance; R.MaxIterations:=MaxIterations; R.NormalizeModes:=NormalizeModes;
  R.StoreModeShapes:=StoreModeShapes; R.CheckSymmetry:=CheckSymmetry; Result:=R;
end;
procedure TBucklingSettings.WriteTo(const L:TStringList);
begin
  L.Add('Solver='+SolverName); L.Add('MatrixStorage='+MatrixStorageToString(MatrixStorage));
  L.Add(Format('EigenvalueCount=%d',[EigenvalueCount])); L.Add(Format('Shift=%.17g',[Shift]));
  L.Add(Format('Tolerance=%.17g',[Tolerance])); L.Add(Format('MaxIterations=%d',[MaxIterations]));
  L.Add('NormalizeModes='+BoolText(NormalizeModes)); L.Add('StoreModeShapes='+BoolText(StoreModeShapes));
  L.Add('CheckSymmetry='+BoolText(CheckSymmetry));
end;
procedure TBucklingSettings.ReadFrom(const Key,Value:string);
var V:TMatrixStorageKind;
begin
  if SameText(Key,'Solver') then begin
    SolverName:=Value;
    if SameText(Trim(Value),'ReferenceDenseLDLT') then SolverName:='Reference dense LDL^T';
  end
  else if SameText(Key,'MatrixStorage') then begin
    if not StringToMatrixStorage(Value,V) then raise EConvertError.CreateFmt('Invalid matrix storage setting %s="%s"',[Key,Value]);
    MatrixStorage:=V;
  end
  else if SameText(Key,'EigenvalueCount') then EigenvalueCount:=ParseSettingInt(Value,Key)
  else if SameText(Key,'Shift') then Shift:=ParseSettingFloat(Value,Key)
  else if SameText(Key,'Tolerance') then Tolerance:=ParseSettingFloat(Value,Key)
  else if SameText(Key,'MaxIterations') then MaxIterations:=ParseSettingInt(Value,Key)
  else if SameText(Key,'NormalizeModes') then NormalizeModes:=ParseSettingBool(Value,Key)
  else if SameText(Key,'StoreModeShapes') then StoreModeShapes:=ParseSettingBool(Value,Key)
  else if SameText(Key,'CheckSymmetry') then CheckSymmetry:=ParseSettingBool(Value,Key);
end;

function TNonlinearStaticSettings.AnalysisType:TAnalysisType; begin Result:=atNonlinearStatic; end;
function TNonlinearStaticSettings.TypeName:string; begin Result:='NonlinearStatic'; end;
function TNonlinearStaticSettings.Clone:TAnalysisSettings;
var R:TNonlinearStaticSettings;
begin
  R:=TNonlinearStaticSettings.Create; R.SolverName:=SolverName; R.InitialLoadSteps:=InitialLoadSteps;
  R.MaxIterations:=MaxIterations; R.ForceTolerance:=ForceTolerance; R.DisplacementTolerance:=DisplacementTolerance;
  R.MinimumStep:=MinimumStep; R.MaximumStep:=MaximumStep; R.LineSearch:=LineSearch; R.MaxCutbacks:=MaxCutbacks;
  R.StoreIterationHistory:=StoreIterationHistory; Result:=R;
end;
procedure TNonlinearStaticSettings.WriteTo(const L:TStringList);
begin
  L.Add('Solver='+SolverName); L.Add(Format('InitialLoadSteps=%d',[InitialLoadSteps]));
  L.Add(Format('MaxIterations=%d',[MaxIterations])); L.Add(Format('ForceTolerance=%.17g',[ForceTolerance]));
  L.Add(Format('DisplacementTolerance=%.17g',[DisplacementTolerance]));
  L.Add(Format('MinimumStep=%.17g',[MinimumStep])); L.Add(Format('MaximumStep=%.17g',[MaximumStep]));
  L.Add('LineSearch='+BoolText(LineSearch)); L.Add(Format('MaxCutbacks=%d',[MaxCutbacks]));
  L.Add('StoreIterationHistory='+BoolText(StoreIterationHistory));
end;
procedure TNonlinearStaticSettings.ReadFrom(const Key,Value:string);
begin
  if SameText(Key,'Solver') then begin
    SolverName:=Value;
    if SameText(Trim(Value),'ReferenceDenseLDLT') then SolverName:='Reference dense LDL^T';
  end
  else if SameText(Key,'InitialLoadSteps') then InitialLoadSteps:=ParseSettingInt(Value,Key)
  else if SameText(Key,'MaxIterations') then MaxIterations:=ParseSettingInt(Value,Key)
  else if SameText(Key,'ForceTolerance') then ForceTolerance:=ParseSettingFloat(Value,Key)
  else if SameText(Key,'DisplacementTolerance') then DisplacementTolerance:=ParseSettingFloat(Value,Key)
  else if SameText(Key,'MinimumStep') then MinimumStep:=ParseSettingFloat(Value,Key)
  else if SameText(Key,'MaximumStep') then MaximumStep:=ParseSettingFloat(Value,Key)
  else if SameText(Key,'LineSearch') then LineSearch:=ParseSettingBool(Value,Key)
  else if SameText(Key,'MaxCutbacks') then MaxCutbacks:=ParseSettingInt(Value,Key)
  else if SameText(Key,'StoreIterationHistory') then StoreIterationHistory:=ParseSettingBool(Value,Key);
end;

constructor TAnalysisCase.Create(AType:TAnalysisType; const AName:string);
begin
  inherited Create; Name:=AName; LoadCaseID:=0; ResultID:='';
  if AType=atLinearStatic then begin FSettings:=TLinearStaticSettings.Create;
    with TLinearStaticSettings(FSettings) do begin SolverName:='Reference dense LDL^T'; MatrixStorage:=msDense;
      PivotTolerance:=1e-12; ResidualTolerance:=1e-8; CheckEquilibrium:=True; CheckEnergy:=True;
      RecoverElementForces:=True; StoreSolverData:=True; end;
  end else if AType=atLinearBuckling then begin
    FSettings:=TBucklingSettings.Create;
    with TBucklingSettings(FSettings) do begin SolverName:='Reference dense eigen solver'; MatrixStorage:=msDense;
      EigenvalueCount:=5; Shift:=0; Tolerance:=1e-8; MaxIterations:=200; NormalizeModes:=True;
      StoreModeShapes:=True; CheckSymmetry:=True; end;
  end else if AType=atNonlinearStatic then begin
    FSettings:=TNonlinearStaticSettings.Create;
    with TNonlinearStaticSettings(FSettings) do begin SolverName:='Newton-Raphson reference'; InitialLoadSteps:=10;
      MaxIterations:=25; ForceTolerance:=1e-8; DisplacementTolerance:=1e-8; MinimumStep:=1e-3;
      MaximumStep:=0.2; LineSearch:=True; MaxCutbacks:=8; StoreIterationHistory:=True; end;
  end else FSettings:=TGenericAnalysisSettings.Create(AType);
end;

destructor TAnalysisCase.Destroy; begin FSettings.Free; inherited Destroy; end;
function TAnalysisCase.AnalysisType:TAnalysisType; begin if FSettings<>nil then Result:=FSettings.AnalysisType else Result:=atLinearStatic; end;
function TAnalysisCase.TypeName:string; begin Result:=AnalysisTypeToString(AnalysisType); end;
function TAnalysisCase.Settings:TAnalysisSettings; begin Result:=FSettings; end;
procedure TAnalysisCase.SetSettings(ASettings:TAnalysisSettings); begin if FSettings<>ASettings then begin FSettings.Free; FSettings:=ASettings; end; end;
procedure TAnalysisCase.WriteTo(const L:TStringList);
begin
  L.Add(Format('[ANALYSIS_CASE %d]',[ID])); L.Add('Name='+Name); L.Add('Type='+TypeName); L.Add(Format('LoadCase=%d',[LoadCaseID])); L.Add('ResultID='+ResultID);
  if FSettings<>nil then begin L.Add('[SETTINGS]'); FSettings.WriteTo(L); end;
  L.Add('[END_ANALYSIS_CASE]');
end;

constructor TAnalysisCaseCollection.Create; begin inherited Create; Clear; end;
destructor TAnalysisCaseCollection.Destroy; begin Clear; inherited Destroy; end;
procedure TAnalysisCaseCollection.Clear; var I:Integer; begin for I:=0 to High(FItems) do FItems[I].Free; SetLength(FItems,0); FNextID:=1; end;
function TAnalysisCaseCollection.Add(AType:TAnalysisType; const AName:string):TAnalysisCase; begin Result:=AddWithID(FNextID,AType,AName); end;
function TAnalysisCaseCollection.AddWithID(ID:Integer; AType:TAnalysisType; const AName:string):TAnalysisCase;
var I:Integer;
begin
  Result:=TAnalysisCase.Create(AType,AName); Result.ID:=ID; I:=Length(FItems); SetLength(FItems,I+1); FItems[I]:=Result;
  if ID>=FNextID then FNextID:=ID+1;
end;
function TAnalysisCaseCollection.Find(ID:Integer):TAnalysisCase; var I:Integer; begin Result:=nil; for I:=0 to High(FItems) do if FItems[I].ID=ID then Exit(FItems[I]); end;
procedure TAnalysisCaseCollection.Delete(ID:Integer);
var I,J:Integer;
begin
  for I:=0 to High(FItems) do if FItems[I].ID=ID then begin
    FItems[I].Free;
    for J:=I to High(FItems)-1 do FItems[J]:=FItems[J+1];
    SetLength(FItems,Length(FItems)-1); Exit;
  end;
end;

function TAnalysisCaseCollection.Count:Integer; begin Result:=Length(FItems); end;
function TAnalysisCaseCollection.Item(Index:Integer):TAnalysisCase; begin Result:=FItems[Index]; end;
function TAnalysisCaseCollection.NextID:Integer; begin Result:=FNextID; end;

end.
