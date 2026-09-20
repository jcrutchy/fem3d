unit FEMAnalysisConfigForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls,
  FEMAnalysisCases, FEMMatrix;

type
  TAnalysisConfigForm = class(TForm)
    ButtonsPanel: TPanel;
    CancelButton: TButton;
    SaveButton: TButton;
    Pages: TPageControl;
    AnalysisPage: TTabSheet;
    SolverPage: TTabSheet;
    DiagnosticsPage: TTabSheet;
    AnalysisNameLabel: TLabel;
    AnalysisNameEdit: TEdit;
    LoadCaseLabel: TLabel;
    LoadCaseEdit: TEdit;
    AnalysisTypeLabel: TLabel;
    AnalysisTypeValue: TLabel;
    SolverLabel: TLabel;
    SolverCombo: TComboBox;
    MatrixStorageLabel: TLabel;
    MatrixStorageCombo: TComboBox;
    PivotToleranceLabel: TLabel;
    PivotToleranceEdit: TEdit;
    ResidualToleranceLabel: TLabel;
    ResidualToleranceEdit: TEdit;
    EquilibriumCheck: TCheckBox;
    EnergyCheck: TCheckBox;
    RecoverForcesCheck: TCheckBox;
    StoreDiagnosticsCheck: TCheckBox;
    EigenvalueCountLabel: TLabel;
    EigenvalueCountEdit: TEdit;
    SpectralShiftLabel: TLabel;
    SpectralShiftEdit: TEdit;
    EigenToleranceLabel: TLabel;
    EigenToleranceEdit: TEdit;
    MaximumIterationsLabel: TLabel;
    MaximumIterationsEdit: TEdit;
    NormalizeModesCheck: TCheckBox;
    StoreModesCheck: TCheckBox;
    SymmetryCheck: TCheckBox;
    InitialStepsLabel: TLabel;
    InitialStepsEdit: TEdit;
    MaximumIterationsStepLabel: TLabel;
    MaximumIterationsStepEdit: TEdit;
    ForceToleranceLabel: TLabel;
    ForceToleranceEdit: TEdit;
    DisplacementToleranceLabel: TLabel;
    DisplacementToleranceEdit: TEdit;
    MinimumStepLabel: TLabel;
    MinimumStepEdit: TEdit;
    MaximumStepLabel: TLabel;
    MaximumStepEdit: TEdit;
    MaximumCutbacksLabel: TLabel;
    MaximumCutbacksEdit: TEdit;
    LineSearchCheck: TCheckBox;
    StoreHistoryCheck: TCheckBox;
    DiagnosticText: TMemo;
    procedure FormShow(Sender: TObject);
    procedure SaveButtonClick(Sender: TObject);
  private
    FAnalysisCase: TAnalysisCase;
    procedure LoadFromAnalysisCase;
    procedure SaveToAnalysisCase;
    procedure UpdateSolverPage;
    procedure UpdateDiagnosticText;
  public
    procedure EditAnalysisCase(AAnalysisCase: TAnalysisCase);
  end;

function ConfigureAnalysisCase(AAnalysisCase: TAnalysisCase): Boolean;

implementation

{$R *.lfm}

procedure TAnalysisConfigForm.EditAnalysisCase(AAnalysisCase: TAnalysisCase);
begin
  FAnalysisCase := AAnalysisCase;
end;

procedure TAnalysisConfigForm.FormShow(Sender: TObject);
begin
  LoadFromAnalysisCase;
end;

procedure TAnalysisConfigForm.LoadFromAnalysisCase;
var
  Settings: TAnalysisSettings;
  Linear: TLinearStaticSettings;
  Buckling: TBucklingSettings;
  Nonlinear: TNonlinearStaticSettings;
begin
  if FAnalysisCase = nil then
    Exit;

  AnalysisNameEdit.Text := FAnalysisCase.Name;
  LoadCaseEdit.Text := IntToStr(FAnalysisCase.LoadCaseID);
  AnalysisTypeValue.Caption := FAnalysisCase.TypeName;

  Settings := FAnalysisCase.Settings;

  SolverCombo.Items.Clear;
  MatrixStorageCombo.Items.Clear;
  MatrixStorageCombo.Items.Add('Dense');
  MatrixStorageCombo.Items.Add('Skyline');

  if Settings is TLinearStaticSettings then
  begin
    Linear := TLinearStaticSettings(Settings);
    SolverCombo.Items.Add('Reference dense LDL^T');
    SolverCombo.ItemIndex := 0;
    MatrixStorageCombo.ItemIndex := Ord(Linear.MatrixStorage);
    PivotToleranceEdit.Text := FloatToStr(Linear.PivotTolerance);
    ResidualToleranceEdit.Text := FloatToStr(Linear.ResidualTolerance);
    EquilibriumCheck.Checked := Linear.CheckEquilibrium;
    EnergyCheck.Checked := Linear.CheckEnergy;
    RecoverForcesCheck.Checked := Linear.RecoverElementForces;
    StoreDiagnosticsCheck.Checked := Linear.StoreSolverData;
  end
  else if Settings is TBucklingSettings then
  begin
    Buckling := TBucklingSettings(Settings);
    SolverCombo.Items.Add('Reference dense eigen solver');
    SolverCombo.ItemIndex := 0;
    MatrixStorageCombo.ItemIndex := Ord(Buckling.MatrixStorage);
    EigenvalueCountEdit.Text := IntToStr(Buckling.EigenvalueCount);
    SpectralShiftEdit.Text := FloatToStr(Buckling.Shift);
    EigenToleranceEdit.Text := FloatToStr(Buckling.Tolerance);
    MaximumIterationsEdit.Text := IntToStr(Buckling.MaxIterations);
    NormalizeModesCheck.Checked := Buckling.NormalizeModes;
    StoreModesCheck.Checked := Buckling.StoreModeShapes;
    SymmetryCheck.Checked := Buckling.CheckSymmetry;
  end
  else if Settings is TNonlinearStaticSettings then
  begin
    Nonlinear := TNonlinearStaticSettings(Settings);
    SolverCombo.Items.Add('Newton-Raphson reference');
    SolverCombo.ItemIndex := 0;
    InitialStepsEdit.Text := IntToStr(Nonlinear.InitialLoadSteps);
    MaximumIterationsStepEdit.Text := IntToStr(Nonlinear.MaxIterations);
    ForceToleranceEdit.Text := FloatToStr(Nonlinear.ForceTolerance);
    DisplacementToleranceEdit.Text := FloatToStr(Nonlinear.DisplacementTolerance);
    MinimumStepEdit.Text := FloatToStr(Nonlinear.MinimumStep);
    MaximumStepEdit.Text := FloatToStr(Nonlinear.MaximumStep);
    MaximumCutbacksEdit.Text := IntToStr(Nonlinear.MaxCutbacks);
    LineSearchCheck.Checked := Nonlinear.LineSearch;
    StoreHistoryCheck.Checked := Nonlinear.StoreIterationHistory;
  end;

  UpdateSolverPage;
  UpdateDiagnosticText;
end;

procedure TAnalysisConfigForm.UpdateSolverPage;
var
  IsLinear: Boolean;
  IsBuckling: Boolean;
  IsNonlinear: Boolean;
begin
  IsLinear := FAnalysisCase.AnalysisType = atLinearStatic;
  IsBuckling := FAnalysisCase.AnalysisType = atLinearBuckling;
  IsNonlinear := FAnalysisCase.AnalysisType = atNonlinearStatic;

  PivotToleranceEdit.Visible := IsLinear;
  PivotToleranceLabel.Visible := IsLinear;
  ResidualToleranceEdit.Visible := IsLinear;
  ResidualToleranceLabel.Visible := IsLinear;
  EquilibriumCheck.Visible := IsLinear;
  EnergyCheck.Visible := IsLinear;
  RecoverForcesCheck.Visible := IsLinear;
  StoreDiagnosticsCheck.Visible := IsLinear;

  EigenvalueCountEdit.Visible := IsBuckling;
  EigenvalueCountLabel.Visible := IsBuckling;
  SpectralShiftEdit.Visible := IsBuckling;
  SpectralShiftLabel.Visible := IsBuckling;
  EigenToleranceEdit.Visible := IsBuckling;
  EigenToleranceLabel.Visible := IsBuckling;
  MaximumIterationsEdit.Visible := IsBuckling;
  MaximumIterationsLabel.Visible := IsBuckling;
  NormalizeModesCheck.Visible := IsBuckling;
  StoreModesCheck.Visible := IsBuckling;
  SymmetryCheck.Visible := IsBuckling;

  InitialStepsEdit.Visible := IsNonlinear;
  InitialStepsLabel.Visible := IsNonlinear;
  MaximumIterationsStepEdit.Visible := IsNonlinear;
  MaximumIterationsStepLabel.Visible := IsNonlinear;
  ForceToleranceEdit.Visible := IsNonlinear;
  ForceToleranceLabel.Visible := IsNonlinear;
  DisplacementToleranceEdit.Visible := IsNonlinear;
  DisplacementToleranceLabel.Visible := IsNonlinear;
  MinimumStepEdit.Visible := IsNonlinear;
  MinimumStepLabel.Visible := IsNonlinear;
  MaximumStepEdit.Visible := IsNonlinear;
  MaximumStepLabel.Visible := IsNonlinear;
  MaximumCutbacksEdit.Visible := IsNonlinear;
  MaximumCutbacksLabel.Visible := IsNonlinear;
  LineSearchCheck.Visible := IsNonlinear;
  StoreHistoryCheck.Visible := IsNonlinear;
end;

procedure TAnalysisConfigForm.UpdateDiagnosticText;
begin
  DiagnosticText.Clear;

  if FAnalysisCase = nil then
    Exit;

  DiagnosticText.Lines.Add('Analysis case');
  DiagnosticText.Lines.Add('  ID: ' + IntToStr(FAnalysisCase.ID));
  DiagnosticText.Lines.Add('  Type: ' + FAnalysisCase.TypeName);
  DiagnosticText.Lines.Add('  Load case: ' + IntToStr(FAnalysisCase.LoadCaseID));
  DiagnosticText.Lines.Add('');
  DiagnosticText.Lines.Add('The analysis definition is persisted with the FEM3D model.');
  DiagnosticText.Lines.Add('The numerical solver is a separate process.');
  DiagnosticText.Lines.Add('');
  if FAnalysisCase.AnalysisType = atLinearStatic then
  begin
    DiagnosticText.Lines.Add('Linear Static is the current executable reference workflow.');
    DiagnosticText.Lines.Add('The reference dense LDL^T solver retains the engineering audit trail.');
  end
  else
  begin
    DiagnosticText.Lines.Add('This analysis type is architecturally defined.');
    DiagnosticText.Lines.Add('Numerical execution remains gated pending formulation verification.');
  end;
end;

procedure TAnalysisConfigForm.SaveToAnalysisCase;
var
  Settings: TAnalysisSettings;
  Linear: TLinearStaticSettings;
  Buckling: TBucklingSettings;
  Nonlinear: TNonlinearStaticSettings;
begin
  if FAnalysisCase = nil then
    Exit;

  FAnalysisCase.Name := Trim(AnalysisNameEdit.Text);
  if FAnalysisCase.Name = '' then
    FAnalysisCase.Name := FAnalysisCase.TypeName;

  FAnalysisCase.LoadCaseID := StrToIntDef(LoadCaseEdit.Text, 0);
  Settings := FAnalysisCase.Settings;

  if Settings is TLinearStaticSettings then
  begin
    Linear := TLinearStaticSettings(Settings);
    Linear.MatrixStorage := TMatrixStorageKind(MatrixStorageCombo.ItemIndex);
    Linear.PivotTolerance :=
      StrToFloatDef(PivotToleranceEdit.Text, Linear.PivotTolerance);
    Linear.ResidualTolerance :=
      StrToFloatDef(ResidualToleranceEdit.Text, Linear.ResidualTolerance);
    Linear.CheckEquilibrium := EquilibriumCheck.Checked;
    Linear.CheckEnergy := EnergyCheck.Checked;
    Linear.RecoverElementForces := RecoverForcesCheck.Checked;
    Linear.StoreSolverData := StoreDiagnosticsCheck.Checked;
  end
  else if Settings is TBucklingSettings then
  begin
    Buckling := TBucklingSettings(Settings);
    Buckling.MatrixStorage :=
      TMatrixStorageKind(MatrixStorageCombo.ItemIndex);
    Buckling.EigenvalueCount :=
      StrToIntDef(EigenvalueCountEdit.Text, Buckling.EigenvalueCount);
    Buckling.Shift :=
      StrToFloatDef(SpectralShiftEdit.Text, Buckling.Shift);
    Buckling.Tolerance :=
      StrToFloatDef(EigenToleranceEdit.Text, Buckling.Tolerance);
    Buckling.MaxIterations :=
      StrToIntDef(MaximumIterationsEdit.Text, Buckling.MaxIterations);
    Buckling.NormalizeModes := NormalizeModesCheck.Checked;
    Buckling.StoreModeShapes := StoreModesCheck.Checked;
    Buckling.CheckSymmetry := SymmetryCheck.Checked;
  end
  else if Settings is TNonlinearStaticSettings then
  begin
    Nonlinear := TNonlinearStaticSettings(Settings);
    Nonlinear.InitialLoadSteps :=
      StrToIntDef(InitialStepsEdit.Text, Nonlinear.InitialLoadSteps);
    Nonlinear.MaxIterations :=
      StrToIntDef(MaximumIterationsStepEdit.Text, Nonlinear.MaxIterations);
    Nonlinear.ForceTolerance :=
      StrToFloatDef(ForceToleranceEdit.Text, Nonlinear.ForceTolerance);
    Nonlinear.DisplacementTolerance :=
      StrToFloatDef(DisplacementToleranceEdit.Text,
        Nonlinear.DisplacementTolerance);
    Nonlinear.MinimumStep :=
      StrToFloatDef(MinimumStepEdit.Text, Nonlinear.MinimumStep);
    Nonlinear.MaximumStep :=
      StrToFloatDef(MaximumStepEdit.Text, Nonlinear.MaximumStep);
    Nonlinear.MaxCutbacks :=
      StrToIntDef(MaximumCutbacksEdit.Text, Nonlinear.MaxCutbacks);
    Nonlinear.LineSearch := LineSearchCheck.Checked;
    Nonlinear.StoreIterationHistory := StoreHistoryCheck.Checked;
  end;
end;

procedure TAnalysisConfigForm.SaveButtonClick(Sender: TObject);
begin
  SaveToAnalysisCase;
  ModalResult := mrOK;
end;

function ConfigureAnalysisCase(AAnalysisCase: TAnalysisCase): Boolean;
var
  Form: TAnalysisConfigForm;
begin
  Form := TAnalysisConfigForm.Create(nil);
  try
    Form.EditAnalysisCase(AAnalysisCase);
    Result := Form.ShowModal = mrOK;
  finally
    Form.Free;
  end;
end;

end.
