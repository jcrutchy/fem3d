unit FEMAnalysisUI;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, Dialogs,
  FEMModel, FEMAnalysisCases, FEMMatrix;

function ConfigureAnalysisCase(A:TAnalysisCase):Boolean;
function RunAnalysisManager(M:TFEMModel; out SelectedID:Integer):Boolean;

implementation

function AddLabel(P:TWinControl; const S:string; X,Y:Integer):TLabel;
begin Result:=TLabel.Create(P); Result.Parent:=P; Result.Caption:=S; Result.Left:=X; Result.Top:=Y; end;

function AddEdit(P:TWinControl; const S:string; X,Y,W:Integer):TEdit;
begin Result:=TEdit.Create(P); Result.Parent:=P; Result.Left:=X; Result.Top:=Y; Result.Width:=W; end;

function AddCheck(P:TWinControl; const S:string; X,Y:Integer; V:Boolean):TCheckBox;
begin Result:=TCheckBox.Create(P); Result.Parent:=P; Result.Caption:=S; Result.Left:=X; Result.Top:=Y; Result.Checked:=V; end;

function ConfigureAnalysisCase(A:TAnalysisCase):Boolean;
var D:TForm; Pages:TPageControl; P1,P2,P3:TTabSheet; EName,ELoad,EPivot,ERes:TEdit;
    CStorage,CSolver:TComboBox; BEquil,BEnergy,BForces,BData:TCheckBox;
    ECount,EShift,ETol,EMaxIt:TEdit; BNorm,BModes,BSym:TCheckBox;
    ENSteps,ENIt,EForce,EDisp,EMin,EMax,ECut:TEdit; BLine,BHist:TCheckBox;
    OK,Cancel:TButton; R:Integer; S:TAnalysisSettings; LS:TLinearStaticSettings; BK:TBucklingSettings; NL:TNonlinearStaticSettings;
begin
  Result:=False;
  D:=TForm.CreateNew(nil); try
    D.Caption:=A.TypeName+' Analysis'; D.Width:=700; D.Height:=540; D.Position:=poScreenCenter; D.BorderStyle:=bsDialog;
    Pages:=TPageControl.Create(D); Pages.Parent:=D; Pages.Align:=alClient;
    P1:=TTabSheet.Create(Pages); P1.PageControl:=Pages; P1.Caption:='Analysis';
    P2:=TTabSheet.Create(Pages); P2.PageControl:=Pages; P2.Caption:='Solver / Numerical';
    P3:=TTabSheet.Create(Pages); P3.PageControl:=Pages; P3.Caption:='Output / Diagnostics';

    AddLabel(P1,'Analysis name',20,28); EName:=AddEdit(P1,A.Name,180,25,430);
    AddLabel(P1,'Load case ID',20,66); ELoad:=AddEdit(P1,IntToStr(A.LoadCaseID),180,63,120);
    AddLabel(P1,'Analysis type',20,104); AddLabel(P1,A.TypeName,180,101);
    AddLabel(P1,'The analysis definition is stored in the FEM3D model file.',20,150);
    AddLabel(P1,'The GUI is only a front end; the selected solver receives an ASCII input deck.',20,174);

    if A.AnalysisType=atLinearStatic then begin
      LS:=TLinearStaticSettings(A.Settings);
      AddLabel(P2,'Solver',20,28); CSolver:=TComboBox.Create(P2); CSolver.Parent:=P2; CSolver.Left:=180; CSolver.Top:=25; CSolver.Width:=430; CSolver.Items.Add('Reference dense LDL^T'); CSolver.ItemIndex:=0;
      AddLabel(P2,'Matrix storage',20,66); CStorage:=TComboBox.Create(P2); CStorage.Parent:=P2; CStorage.Left:=180; CStorage.Top:=63; CStorage.Width:=180; CStorage.Items.Add('Dense'); CStorage.Items.Add('Skyline'); CStorage.ItemIndex:=Ord(LS.MatrixStorage);
      AddLabel(P2,'Pivot tolerance',20,104); EPivot:=AddEdit(P2,FloatToStr(LS.PivotTolerance),180,101,180);
      AddLabel(P2,'Residual tolerance',20,142); ERes:=AddEdit(P2,FloatToStr(LS.ResidualTolerance),180,139,180);
      AddLabel(P2,'Reference solver options',20,190); BEquil:=AddCheck(P2,'Equilibrium check',40,220,LS.CheckEquilibrium); BEnergy:=AddCheck(P2,'Energy balance check',40,248,LS.CheckEnergy);
      BForces:=AddCheck(P2,'Recover element forces',40,276,LS.RecoverElementForces); BData:=AddCheck(P2,'Store solver diagnostics',40,304,LS.StoreSolverData);
      CSolver.Enabled:=True;
      AddLabel(P3,'Linear static output',20,28); AddLabel(P3,'Displacements, reactions, residuals, energy balance and audit trail are retained.',20,56);
      AddLabel(P3,'Element force recovery is controlled by the analysis case.',20,84);
    end else if A.AnalysisType=atLinearBuckling then begin
      BK:=TBucklingSettings(A.Settings);
      AddLabel(P2,'Eigenvalue solver',20,28); CSolver:=TComboBox.Create(P2); CSolver.Parent:=P2; CSolver.Left:=180; CSolver.Top:=25; CSolver.Width:=430; CSolver.Items.Add('Reference dense eigen solver'); CSolver.ItemIndex:=0;
      AddLabel(P2,'Matrix storage',20,66); CStorage:=TComboBox.Create(P2); CStorage.Parent:=P2; CStorage.Left:=180; CStorage.Top:=63; CStorage.Width:=180; CStorage.Items.Add('Dense'); CStorage.Items.Add('Skyline'); CStorage.ItemIndex:=Ord(BK.MatrixStorage);
      AddLabel(P2,'Eigenvalues requested',20,104); ECount:=AddEdit(P2,IntToStr(BK.EigenvalueCount),180,101,120);
      AddLabel(P2,'Spectral shift',20,142); EShift:=AddEdit(P2,FloatToStr(BK.Shift),180,139,180);
      AddLabel(P2,'Eigen tolerance',20,180); ETol:=AddEdit(P2,FloatToStr(BK.Tolerance),180,177,180);
      AddLabel(P2,'Maximum iterations',20,218); EMaxIt:=AddEdit(P2,IntToStr(BK.MaxIterations),180,215,120);
      BNorm:=AddCheck(P2,'Normalize mode shapes',40,253,BK.NormalizeModes); BModes:=AddCheck(P2,'Store mode shapes',40,281,BK.StoreModeShapes); BSym:=AddCheck(P2,'Check matrix symmetry',40,309,BK.CheckSymmetry);
      AddLabel(P3,'Buckling output',20,28); AddLabel(P3,'Future result files will contain critical load factors, eigenvectors and mode provenance.',20,56);
      AddLabel(P3,'The reference buckling solver is intentionally gated until the geometric stiffness formulation is verified.',20,84);
    end else if A.AnalysisType=atNonlinearStatic then begin
      NL:=TNonlinearStaticSettings(A.Settings);
      AddLabel(P2,'Nonlinear solver',20,28); CSolver:=TComboBox.Create(P2); CSolver.Parent:=P2; CSolver.Left:=180; CSolver.Top:=25; CSolver.Width:=430; CSolver.Items.Add('Newton-Raphson reference'); CSolver.ItemIndex:=0;
      AddLabel(P2,'Initial load steps',20,66); ENSteps:=AddEdit(P2,IntToStr(NL.InitialLoadSteps),180,63,120);
      AddLabel(P2,'Maximum iterations / step',20,104); ENIt:=AddEdit(P2,IntToStr(NL.MaxIterations),180,101,120);
      AddLabel(P2,'Force tolerance',20,142); EForce:=AddEdit(P2,FloatToStr(NL.ForceTolerance),180,139,180);
      AddLabel(P2,'Displacement tolerance',20,180); EDisp:=AddEdit(P2,FloatToStr(NL.DisplacementTolerance),180,177,180);
      AddLabel(P2,'Minimum load step',20,218); EMin:=AddEdit(P2,FloatToStr(NL.MinimumStep),180,215,180);
      AddLabel(P2,'Maximum load step',20,256); EMax:=AddEdit(P2,FloatToStr(NL.MaximumStep),180,253,180);
      AddLabel(P2,'Maximum cutbacks',20,294); ECut:=AddEdit(P2,IntToStr(NL.MaxCutbacks),180,291,120);
      BLine:=AddCheck(P2,'Line search',40,327,NL.LineSearch); BHist:=AddCheck(P2,'Store iteration history',40,355,NL.StoreIterationHistory);
      AddLabel(P3,'Nonlinear output',20,28); AddLabel(P3,'Each converged load step will eventually have its own convergence and cutback history.',20,56);
      AddLabel(P3,'The nonlinear solver is gated until nonlinear element formulations and tangent consistency are verified.',20,84);
    end else begin
      AddLabel(P2,'No solver-specific settings are available yet for this analysis type.',20,28);
      AddLabel(P3,'This analysis type is reserved in the model format but not numerically implemented.',20,28);
    end;

    OK:=TButton.Create(D); OK.Parent:=D; OK.Caption:='Save'; OK.Left:=500; OK.Top:=465; OK.Width:=80; OK.ModalResult:=mrOK;
    Cancel:=TButton.Create(D); Cancel.Parent:=D; Cancel.Caption:='Cancel'; Cancel.Left:=590; Cancel.Top:=465; Cancel.Width:=80; Cancel.ModalResult:=mrCancel;
    R:=D.ShowModal; if R<>mrOK then Exit;
    A.Name:=EName.Text; A.LoadCaseID:=StrToIntDef(ELoad.Text,0); S:=A.Settings;
    if S is TLinearStaticSettings then begin
      LS:=TLinearStaticSettings(S); LS.MatrixStorage:=TMatrixStorageKind(CStorage.ItemIndex); LS.PivotTolerance:=StrToFloatDef(EPivot.Text,LS.PivotTolerance); LS.ResidualTolerance:=StrToFloatDef(ERes.Text,LS.ResidualTolerance); LS.CheckEquilibrium:=BEquil.Checked; LS.CheckEnergy:=BEnergy.Checked; LS.RecoverElementForces:=BForces.Checked; LS.StoreSolverData:=BData.Checked;
    end else if S is TBucklingSettings then begin
      BK:=TBucklingSettings(S); BK.MatrixStorage:=TMatrixStorageKind(CStorage.ItemIndex); BK.EigenvalueCount:=StrToIntDef(ECount.Text,BK.EigenvalueCount); BK.Shift:=StrToFloatDef(EShift.Text,BK.Shift); BK.Tolerance:=StrToFloatDef(ETol.Text,BK.Tolerance); BK.MaxIterations:=StrToIntDef(EMaxIt.Text,BK.MaxIterations); BK.NormalizeModes:=BNorm.Checked; BK.StoreModeShapes:=BModes.Checked; BK.CheckSymmetry:=BSym.Checked;
    end else if S is TNonlinearStaticSettings then begin
      NL:=TNonlinearStaticSettings(S); NL.InitialLoadSteps:=StrToIntDef(ENSteps.Text,NL.InitialLoadSteps); NL.MaxIterations:=StrToIntDef(ENIt.Text,NL.MaxIterations); NL.ForceTolerance:=StrToFloatDef(EForce.Text,NL.ForceTolerance); NL.DisplacementTolerance:=StrToFloatDef(EDisp.Text,NL.DisplacementTolerance); NL.MinimumStep:=StrToFloatDef(EMin.Text,NL.MinimumStep); NL.MaximumStep:=StrToFloatDef(EMax.Text,NL.MaximumStep); NL.MaxCutbacks:=StrToIntDef(ECut.Text,NL.MaxCutbacks); NL.LineSearch:=BLine.Checked; NL.StoreIterationHistory:=BHist.Checked;
    end;
    Result:=True;
  finally D.Free end;
end;

type
  TAnalysisManagerForm=class(TForm)
  private
    FModel:TFEMModel; FList:TListBox; FChanged:Boolean; FSelectedID:Integer;
    procedure NewCase(Sender:TObject); procedure EditCase(Sender:TObject); procedure DuplicateCase(Sender:TObject); procedure DeleteCase(Sender:TObject); procedure SelectCase(Sender:TObject);
    procedure FillList;
  public
    constructor CreateManager(AOwner:TComponent; M:TFEMModel);
    property SelectedID:Integer read FSelectedID;
    property Changed:Boolean read FChanged;
  end;

constructor TAnalysisManagerForm.CreateManager(AOwner:TComponent; M:TFEMModel);
var B:TButton;
begin
  inherited CreateNew(AOwner); FModel:=M; FSelectedID:=0; FChanged:=False;
  Caption:='Analysis Manager'; Width:=780; Height:=520; Position:=poScreenCenter; BorderStyle:=bsDialog;
  FList:=TListBox.Create(Self); FList.Parent:=Self; FList.Left:=12; FList.Top:=12; FList.Width:=750; FList.Height:=390; FList.Anchors:=[akLeft,akTop,akRight,akBottom]; FList.OnDblClick:=@EditCase;
  B:=TButton.Create(Self); B.Parent:=Self; B.Caption:='New'; B.Left:=12; B.Top:=420; B.Width:=80; B.OnClick:=@NewCase;
  B:=TButton.Create(Self); B.Parent:=Self; B.Caption:='Edit'; B.Left:=100; B.Top:=420; B.Width:=80; B.OnClick:=@EditCase;
  B:=TButton.Create(Self); B.Parent:=Self; B.Caption:='Duplicate'; B.Left:=188; B.Top:=420; B.Width:=90; B.OnClick:=@DuplicateCase;
  B:=TButton.Create(Self); B.Parent:=Self; B.Caption:='Delete'; B.Left:=286; B.Top:=420; B.Width:=80; B.OnClick:=@DeleteCase;
  B:=TButton.Create(Self); B.Parent:=Self; B.Caption:='Use selected'; B.Left:=650; B.Top:=420; B.Width:=110; B.OnClick:=@SelectCase;
  FillList;
end;

procedure TAnalysisManagerForm.FillList;
var I:Integer; A:TAnalysisCase;
begin FList.Items.Clear; for I:=0 to FModel.AnalysisCases.Count-1 do begin A:=FModel.AnalysisCases.Item(I); FList.Items.AddObject(Format('%d  %s  [%s]  LoadCase=%d',[A.ID,A.Name,A.TypeName,A.LoadCaseID]),A); end; end;

procedure TAnalysisManagerForm.NewCase(Sender:TObject);
var D:TForm; C:TComboBox; BOK,BCancel:TButton; T:TAnalysisType; A:TAnalysisCase; N:string; R:Integer;
begin
  D:=TForm.CreateNew(Self); try D.Caption:='New Analysis Case'; D.Width:=380; D.Height:=180; D.Position:=poScreenCenter; D.BorderStyle:=bsDialog;
    AddLabel(D,'Analysis type',20,25); C:=TComboBox.Create(D); C.Parent:=D; C.Left:=130; C.Top:=22; C.Width:=210; C.Items.Add('Linear Static'); C.Items.Add('Linear Buckling'); C.Items.Add('Nonlinear Static'); C.ItemIndex:=0;
    BOK:=TButton.Create(D); BOK.Parent:=D; BOK.Caption:='Continue'; BOK.Left:=170; BOK.Top:=95; BOK.Width:=80; BOK.ModalResult:=mrOK;
    BCancel:=TButton.Create(D); BCancel.Parent:=D; BCancel.Caption:='Cancel'; BCancel.Left:=260; BCancel.Top:=95; BCancel.Width:=80; BCancel.ModalResult:=mrCancel;
    R:=D.ShowModal; if R<>mrOK then Exit;
    case C.ItemIndex of 0:T:=atLinearStatic; 1:T:=atLinearBuckling; else T:=atNonlinearStatic; end;
    case T of atLinearStatic:N:='Linear Static '; atLinearBuckling:N:='Linear Buckling '; else N:='Nonlinear Static '; end; N:=N+IntToStr(FModel.AnalysisCases.NextID);
    A:=FModel.AnalysisCases.Add(T,N); if ConfigureAnalysisCase(A) then begin FChanged:=True; FillList; end else FModel.AnalysisCases.Delete(A.ID);
  finally D.Free end;
end;

procedure TAnalysisManagerForm.EditCase(Sender:TObject);
var A:TAnalysisCase;
begin if FList.ItemIndex<0 then Exit; A:=TAnalysisCase(FList.Items.Objects[FList.ItemIndex]); if ConfigureAnalysisCase(A) then begin FChanged:=True; FillList; end; end;

procedure TAnalysisManagerForm.DuplicateCase(Sender:TObject);
var A,B:TAnalysisCase;
begin if FList.ItemIndex<0 then Exit; A:=TAnalysisCase(FList.Items.Objects[FList.ItemIndex]); B:=FModel.AnalysisCases.Add(A.AnalysisType,A.Name+' copy'); B.LoadCaseID:=A.LoadCaseID; B.SetSettings(A.Settings.Clone); FChanged:=True; FillList; end;

procedure TAnalysisManagerForm.DeleteCase(Sender:TObject);
var A:TAnalysisCase;
begin
  if FList.ItemIndex<0 then Exit; A:=TAnalysisCase(FList.Items.Objects[FList.ItemIndex]);
  if MessageDlg('Delete analysis','Delete analysis case '+IntToStr(A.ID)+'?',mtWarning,[mbYes,mbNo],0)<>mrYes then Exit;
  FModel.AnalysisCases.Delete(A.ID); FSelectedID:=0; FChanged:=True; FillList;
end;

procedure TAnalysisManagerForm.SelectCase(Sender:TObject);
var A:TAnalysisCase;
begin if FList.ItemIndex>=0 then begin A:=TAnalysisCase(FList.Items.Objects[FList.ItemIndex]); FSelectedID:=A.ID; end; ModalResult:=mrOK; end;

function RunAnalysisManager(M:TFEMModel; out SelectedID:Integer):Boolean;
var D:TAnalysisManagerForm;
begin D:=TAnalysisManagerForm.CreateManager(nil,M); try Result:=D.ShowModal=mrOK; SelectedID:=D.SelectedID; finally D.Free end; end;

end.
