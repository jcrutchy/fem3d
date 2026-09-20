unit FEMAnalysisManagerForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  FEMModel, FEMAnalysisCases;

type
  TAnalysisManagerForm = class(TForm)
    CasesList: TListBox;
    ButtonsPanel: TPanel;
    NewButton: TButton;
    EditButton: TButton;
    DuplicateButton: TButton;
    DeleteButton: TButton;
    UseSelectedButton: TButton;
    CloseButton: TButton;
    SummaryMemo: TMemo;
    procedure FormShow(Sender: TObject);
    procedure CasesListDblClick(Sender: TObject);
    procedure NewButtonClick(Sender: TObject);
    procedure EditButtonClick(Sender: TObject);
    procedure DuplicateButtonClick(Sender: TObject);
    procedure DeleteButtonClick(Sender: TObject);
    procedure UseSelectedButtonClick(Sender: TObject);
    procedure CloseButtonClick(Sender: TObject);
  private
    FModel: TFEMModel;
    FSelectedID: Integer;
    FChanged: Boolean;
    procedure FillList;
    procedure UpdateSummary;
    function SelectedCase: TAnalysisCase;
    procedure CreateCase(AType: TAnalysisType);
  public
    procedure EditModel(AModel: TFEMModel);
    property SelectedID: Integer read FSelectedID;
    property Changed: Boolean read FChanged;
  end;

function RunAnalysisManager(M: TFEMModel; out SelectedID: Integer): Boolean;

implementation

uses
  FEMAnalysisConfigForm;

{$R *.lfm}

procedure TAnalysisManagerForm.EditModel(AModel: TFEMModel);
begin
  FModel := AModel;
  FSelectedID := 0;
  FChanged := False;
end;

procedure TAnalysisManagerForm.FormShow(Sender: TObject);
begin
  FillList;
  UpdateSummary;
end;

procedure TAnalysisManagerForm.FillList;
var
  I: Integer;
  A: TAnalysisCase;
begin
  CasesList.Items.BeginUpdate;
  try
    CasesList.Items.Clear;

    if FModel = nil then
      Exit;

    for I := 0 to FModel.AnalysisCases.Count - 1 do
    begin
      A := FModel.AnalysisCases.Item(I);
      CasesList.Items.AddObject(
        Format('%d  %s  [%s]  LoadCase=%d',
          [A.ID, A.Name, A.TypeName, A.LoadCaseID]), A);
    end;

    if CasesList.Items.Count > 0 then
    begin
      if FSelectedID <> 0 then
      begin
        for I := 0 to CasesList.Items.Count - 1 do
          if TAnalysisCase(CasesList.Items.Objects[I]).ID = FSelectedID then
          begin
            CasesList.ItemIndex := I;
            Break;
          end;
      end;

      if CasesList.ItemIndex < 0 then
        CasesList.ItemIndex := 0;
    end;
  finally
    CasesList.Items.EndUpdate;
  end;
end;

function TAnalysisManagerForm.SelectedCase: TAnalysisCase;
begin
  Result := nil;

  if CasesList.ItemIndex >= 0 then
    Result := TAnalysisCase(CasesList.Items.Objects[CasesList.ItemIndex]);
end;

procedure TAnalysisManagerForm.UpdateSummary;
var
  A: TAnalysisCase;
begin
  SummaryMemo.Clear;

  A := SelectedCase;
  if A = nil then
  begin
    SummaryMemo.Lines.Add('No analysis case selected.');
    SummaryMemo.Lines.Add('');
    SummaryMemo.Lines.Add('Use New to create an analysis case.');
    Exit;
  end;

  FSelectedID := A.ID;

  SummaryMemo.Lines.Add('ID: ' + IntToStr(A.ID));
  SummaryMemo.Lines.Add('Name: ' + A.Name);
  SummaryMemo.Lines.Add('Type: ' + A.TypeName);
  SummaryMemo.Lines.Add('Load case: ' + IntToStr(A.LoadCaseID));

  if A.ResultID <> '' then
    SummaryMemo.Lines.Add('Result: ' + A.ResultID)
  else
    SummaryMemo.Lines.Add('Result: none');

  SummaryMemo.Lines.Add('');
  SummaryMemo.Lines.Add('Double-click the case, or use Edit, to open its');
  SummaryMemo.Lines.Add('designer-managed configuration pages.');
end;

procedure TAnalysisManagerForm.CasesListDblClick(Sender: TObject);
begin
  EditButtonClick(Sender);
end;

procedure TAnalysisManagerForm.NewButtonClick(Sender: TObject);
begin
  CreateCase(atLinearStatic);
end;

procedure TAnalysisManagerForm.CreateCase(AType: TAnalysisType);
var
  A: TAnalysisCase;
  Prefix: string;
begin
  if FModel = nil then
    Exit;

  case AType of
    atLinearStatic:
      Prefix := 'Linear Static ';
    atLinearBuckling:
      Prefix := 'Linear Buckling ';
    atNonlinearStatic:
      Prefix := 'Nonlinear Static ';
  else
    Prefix := AnalysisTypeToString(AType) + ' ';
  end;

  A := FModel.AnalysisCases.Add(
    AType, Prefix + IntToStr(FModel.AnalysisCases.NextID));

  if ConfigureAnalysisCase(A) then
  begin
    FSelectedID := A.ID;
    FChanged := True;
    FillList;
    UpdateSummary;
  end
  else
    FModel.AnalysisCases.Delete(A.ID);
end;

procedure TAnalysisManagerForm.EditButtonClick(Sender: TObject);
var
  A: TAnalysisCase;
begin
  A := SelectedCase;
  if A = nil then
    Exit;

  if ConfigureAnalysisCase(A) then
  begin
    FSelectedID := A.ID;
    FChanged := True;
    FillList;
    UpdateSummary;
  end;
end;

procedure TAnalysisManagerForm.DuplicateButtonClick(Sender: TObject);
var
  A: TAnalysisCase;
  B: TAnalysisCase;
begin
  A := SelectedCase;
  if A = nil then
    Exit;

  B := FModel.AnalysisCases.Add(A.AnalysisType, A.Name + ' copy');
  B.LoadCaseID := A.LoadCaseID;
  B.SetSettings(A.Settings.Clone);
  FSelectedID := B.ID;
  FChanged := True;
  FillList;
  UpdateSummary;
end;

procedure TAnalysisManagerForm.DeleteButtonClick(Sender: TObject);
var
  A: TAnalysisCase;
begin
  A := SelectedCase;
  if A = nil then
    Exit;

  if MessageDlg(
    'Delete analysis',
    'Delete analysis case ' + IntToStr(A.ID) + '?',
    mtWarning, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  FModel.AnalysisCases.Delete(A.ID);
  FSelectedID := 0;
  FChanged := True;
  FillList;
  UpdateSummary;
end;

procedure TAnalysisManagerForm.UseSelectedButtonClick(Sender: TObject);
var
  A: TAnalysisCase;
begin
  A := SelectedCase;
  if A = nil then
    Exit;

  FSelectedID := A.ID;
  ModalResult := mrOK;
end;

procedure TAnalysisManagerForm.CloseButtonClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

function RunAnalysisManager(M: TFEMModel; out SelectedID: Integer): Boolean;
var
  Form: TAnalysisManagerForm;
begin
  Form := TAnalysisManagerForm.Create(nil);
  try
    Form.EditModel(M);
    Result := Form.ShowModal = mrOK;
    SelectedID := Form.SelectedID;
  finally
    Form.Free;
  end;
end;

end.
