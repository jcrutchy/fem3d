unit secedit_presetdlg;

// The dialog that asks for the dimensions of a parametric shape. It is built in
// code because the number of fields depends on the shape.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Dialogs,
  fem_sketch, fem_sectionpresets;

// Shows the dialog for the preset; on OK returns the built sketch.
function AskPreset(const Def: TPresetDef; const LengthUnit: string;
  out S: TSketch): Boolean;

implementation

type
  TPresetDialog = class(TForm)
  private
    FDef: TPresetDef;
    FUnit: string;
    FEdits: array of TEdit;
    FMessage: TLabel;
    procedure DlgCloseQuery(Sender: TObject; var CanClose: Boolean);
  public
    Built: TSketch;
    constructor CreateFor(AOwner: TComponent; const ADef: TPresetDef; const AUnit: string);
  end;

constructor TPresetDialog.CreateFor(AOwner: TComponent; const ADef: TPresetDef;
  const AUnit: string);
var
  I: Integer;
  Lbl: TLabel;
  Ed: TEdit;
  Scale, V: Double;
  Btn: TButton;
  FS: TFormatSettings;
begin
  inherited CreateNew(AOwner);
  FDef := ADef;
  FUnit := AUnit;
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Caption := ADef.Caption;
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  ClientWidth := 360;
  ClientHeight := 40 + Length(ADef.Params) * 32 + 90;
  Scale := DefaultScaleForUnit(AUnit);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.SetBounds(16, 12, 330, 20);
  Lbl.Caption := 'Dimensions in ' + AUnit;

  SetLength(FEdits, Length(ADef.Params));
  for I := 0 to High(ADef.Params) do
  begin
    Lbl := TLabel.Create(Self);
    Lbl.Parent := Self;
    Lbl.SetBounds(16, 44 + I * 32, 190, 20);
    Lbl.Caption := ADef.Params[I].Caption;
    Ed := TEdit.Create(Self);
    Ed.Parent := Self;
    Ed.SetBounds(214, 40 + I * 32, 130, 24);
    V := ADef.Params[I].DefaultValue * Scale;
    Ed.Text := FloatToStrF(V, ffGeneral, 6, 0, FS);
    FEdits[I] := Ed;
  end;

  FMessage := TLabel.Create(Self);
  FMessage.Parent := Self;
  FMessage.SetBounds(16, 48 + Length(ADef.Params) * 32, 328, 36);
  FMessage.AutoSize := False;
  FMessage.WordWrap := True;
  FMessage.Font.Color := clRed;

  Btn := TButton.Create(Self);
  Btn.Parent := Self;
  Btn.Caption := 'OK';
  Btn.ModalResult := mrOk;
  Btn.Default := True;
  Btn.SetBounds(184, ClientHeight - 40, 76, 28);
  Btn := TButton.Create(Self);
  Btn.Parent := Self;
  Btn.Caption := 'Cancel';
  Btn.ModalResult := mrCancel;
  Btn.Cancel := True;
  Btn.SetBounds(268, ClientHeight - 40, 76, 28);

  OnCloseQuery := @DlgCloseQuery;
  if Length(FEdits) > 0 then ActiveControl := FEdits[0];
end;

procedure TPresetDialog.DlgCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  I: Integer;
  Vals: array of Double;
  FS: TFormatSettings;
  Txt, Err: string;
begin
  if ModalResult <> mrOk then Exit;     // Cancel / close box: always allowed
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  SetLength(Vals, Length(FEdits));
  for I := 0 to High(FEdits) do
  begin
    Txt := StringReplace(Trim(FEdits[I].Text), ',', '.', [rfReplaceAll]);
    if not TryStrToFloat(Txt, Vals[I], FS) then
    begin
      FMessage.Caption := FDef.Params[I].Caption + ' is not a number.';
      FEdits[I].SetFocus;
      CanClose := False;
      Exit;
    end;
  end;
  if not BuildPreset(FDef.Id, Vals, FUnit, Built, Err) then
  begin
    FMessage.Caption := Err;
    CanClose := False;
    Exit;
  end;
end;

function AskPreset(const Def: TPresetDef; const LengthUnit: string;
  out S: TSketch): Boolean;
var
  Dlg: TPresetDialog;
begin
  SketchInit(S, '', LengthUnit);
  Dlg := TPresetDialog.CreateFor(Application, Def, LengthUnit);
  try
    Result := Dlg.ShowModal = mrOk;
    if Result then SketchCopy(Dlg.Built, S);
  finally
    Dlg.Free;
  end;
end;

end.
