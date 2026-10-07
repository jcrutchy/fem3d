unit secedit_main;

// Main window of the native section editor / analyser (femsecedit).
//
// The layout lives in secedit_main.lfm, so it can be adjusted visually in the
// Lazarus designer. The drawing surface (secedit_view.TSectionView) is not a
// registered component, so the form has a placeholder panel (PanelView) and
// the view is created inside it at start-up.
//
// All calculation is done by the same units the femsection command-line tool
// uses (through fem_sectiondoc), so the numbers cannot differ from the CLI's.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ExtCtrls,
  ComCtrls, StdCtrls, Grids, Clipbrd, LCLType,
  fem_geometry_validate, fem_proprows, fem_sectiondoc, secedit_view;

type
  TSecEditForm = class(TForm)
    MainMenu1: TMainMenu;
    miFile: TMenuItem;
    miOpen: TMenuItem;
    miReload: TMenuItem;
    miExport: TMenuItem;
    miSep1: TMenuItem;
    miExit: TMenuItem;
    miView: TMenuItem;
    miFit: TMenuItem;
    miSep2: TMenuItem;
    miGrid: TMenuItem;
    miPrincipal: TMenuItem;
    miBBox: TMenuItem;
    miAutoReload: TMenuItem;
    miHelp: TMenuItem;
    miAbout: TMenuItem;
    PanelRight: TPanel;
    LabelSection: TLabel;
    GridProps: TStringGrid;
    Splitter1: TSplitter;
    PanelBottom: TPanel;
    ListDiag: TListBox;
    Splitter2: TSplitter;
    PanelView: TPanel;
    StatusBar1: TStatusBar;
    OpenDialog1: TOpenDialog;
    SaveDialog1: TSaveDialog;
    TimerReload: TTimer;
    TimerCalc: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure miOpenClick(Sender: TObject);
    procedure miReloadClick(Sender: TObject);
    procedure miExportClick(Sender: TObject);
    procedure miExitClick(Sender: TObject);
    procedure miFitClick(Sender: TObject);
    procedure miViewOptionClick(Sender: TObject);
    procedure miAboutClick(Sender: TObject);
    procedure GridPropsDrawCell(Sender: TObject; aCol, aRow: Integer;
      aRect: TRect; aState: TGridDrawState);
    procedure GridPropsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListDiagDrawItem(Control: TWinControl; Index: Integer;
      ARect: TRect; State: TOwnerDrawState);
    procedure TimerReloadTimer(Sender: TObject);
    procedure TimerCalcTimer(Sender: TObject);
  private
    FDoc: TSectionDoc;
    FView: TSectionView;
    FRowIsGroup: array of Boolean;
    FPendingAge: LongInt;
    FScreenshotFile: string;
    procedure ParseCommandLine(out FileToOpen: string);
    procedure LoadFile(const AFileName: string; KeepView: Boolean);
    procedure RefreshProps(JPending: Boolean);
    procedure RefreshDiagnostics;
    procedure UpdateStatus;
    procedure ViewCursor(Sender: TObject; WorldX, WorldY: Double);
    procedure ViewChanged(Sender: TObject);
    procedure SyncViewOptions;
    procedure DoScreenshot(Data: PtrInt);
  public
    constructor Create(TheOwner: TComponent); override;
  end;

var
  SecEditForm: TSecEditForm;

implementation

{$R *.lfm}

const
  SevError = 0;
  SevWarning = 1;
  SevInfo = 2;

constructor TSecEditForm.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
end;

procedure TSecEditForm.FormCreate(Sender: TObject);
var
  FileToOpen: string;
begin
  FDoc := TSectionDoc.Create;
  FPendingAge := -1;

  FView := TSectionView.Create(Self);
  FView.Parent := PanelView;
  FView.Align := alClient;
  FView.OnCursor := @ViewCursor;
  FView.OnViewChange := @ViewChanged;

  ParseCommandLine(FileToOpen);
  SyncViewOptions;
  RefreshDiagnostics;
  UpdateStatus;

  if FileToOpen <> '' then LoadFile(FileToOpen, False);

  if FScreenshotFile <> '' then
  begin
    TimerReload.Enabled := False;
    Application.QueueAsyncCall(@DoScreenshot, 0);
  end;
end;

procedure TSecEditForm.FormDestroy(Sender: TObject);
begin
  FDoc.Free;
end;

// femsecedit [file.fgeo] [--screenshot out.png] [--size WxH]
// The screenshot mode loads the file, draws the window and saves it as a PNG
// (used for documentation and for automated checks), then exits.
procedure TSecEditForm.ParseCommandLine(out FileToOpen: string);
var
  I, P, W, H: Integer;
  A, S: string;
begin
  FileToOpen := '';
  FScreenshotFile := '';
  I := 1;
  while I <= ParamCount do
  begin
    A := ParamStr(I);
    if A = '--screenshot' then
    begin
      Inc(I);
      if I <= ParamCount then FScreenshotFile := ParamStr(I);
    end
    else if A = '--size' then
    begin
      Inc(I);
      if I <= ParamCount then
      begin
        S := LowerCase(ParamStr(I));
        P := Pos('x', S);
        if P > 1 then
        begin
          W := StrToIntDef(Copy(S, 1, P - 1), 0);
          H := StrToIntDef(Copy(S, P + 1, MaxInt), 0);
          if (W >= 400) and (H >= 300) then
          begin
            Width := W;
            Height := H;
          end;
        end;
      end;
    end
    else if (Length(A) > 0) and (A[1] <> '-') then
      FileToOpen := A;
    Inc(I);
  end;
end;

procedure TSecEditForm.LoadFile(const AFileName: string; KeepView: Boolean);
begin
  FDoc.Load(AFileName);
  FPendingAge := -1;
  TimerCalc.Enabled := False;
  RefreshDiagnostics;
  if FDoc.FacesOk then
  begin
    FView.SetSection(FDoc.Faces, FDoc.Props, True);
    RefreshProps(True);
    LabelSection.Caption := FDoc.Props.Name + '  (' + FDoc.Props.LengthUnit + ')';
    if FScreenshotFile <> '' then
    begin
      FDoc.ComputeFull;           // no waiting in screenshot mode
      RefreshProps(False);
      FView.UpdateProps(FDoc.Props);
    end
    else
      TimerCalc.Enabled := True;  // solve J after the window has repainted
  end
  else
  begin
    FView.SetMessage(FDoc.ErrorText);
    GridProps.RowCount := 1;
    SetLength(FRowIsGroup, 1);
    LabelSection.Caption := ExtractFileName(AFileName);
  end;
  if not KeepView then FView.FitView;
  Caption := 'FEM3D Section Editor - ' + ExtractFileName(AFileName);
  UpdateStatus;
end;

procedure TSecEditForm.RefreshProps(JPending: Boolean);
var
  Rows: TPropRowArray;
  I, R: Integer;
  LastGroup: string;
begin
  BuildPropRows(FDoc.Props, JPending, Rows);
  GridProps.BeginUpdate;
  try
    GridProps.RowCount := 1;   // header row only
    SetLength(FRowIsGroup, 1);
    LastGroup := #0;
    for I := 0 to High(Rows) do
    begin
      if Rows[I].Group <> LastGroup then
      begin
        GridProps.RowCount := GridProps.RowCount + 1;
        R := GridProps.RowCount - 1;
        SetLength(FRowIsGroup, R + 1);
        FRowIsGroup[R] := True;
        GridProps.Cells[0, R] := Rows[I].Group;
        GridProps.Cells[1, R] := '';
        GridProps.Cells[2, R] := '';
        LastGroup := Rows[I].Group;
      end;
      GridProps.RowCount := GridProps.RowCount + 1;
      R := GridProps.RowCount - 1;
      SetLength(FRowIsGroup, R + 1);
      FRowIsGroup[R] := False;
      GridProps.Cells[0, R] := Rows[I].Caption;
      if Rows[I].Pending then
        GridProps.Cells[1, R] := 'solving...'
      else
        GridProps.Cells[1, R] := FormatPropValue(Rows[I].Value);
      GridProps.Cells[2, R] := Rows[I].UnitText;
    end;
  finally
    GridProps.EndUpdate;
  end;
end;

procedure TSecEditForm.RefreshDiagnostics;
var
  I: Integer;
  D: TGeoDiagnostic;
  Sev: Integer;
begin
  ListDiag.Items.BeginUpdate;
  try
    ListDiag.Items.Clear;
    if FDoc.ErrorText <> '' then
      ListDiag.Items.AddObject('ERROR  ' + FDoc.ErrorText, TObject(PtrInt(SevError)));
    for I := 0 to High(FDoc.Diags.Items) do
    begin
      D := FDoc.Diags.Items[I];
      if D.Severity = gsError then Sev := SevError else Sev := SevWarning;
      ListDiag.Items.AddObject(D.Code + '  ' + D.Msg, TObject(PtrInt(Sev)));
    end;
    if ListDiag.Items.Count = 0 then
    begin
      if FDoc.FacesOk then
        ListDiag.Items.AddObject('No geometry problems found.', TObject(PtrInt(SevInfo)))
      else
        ListDiag.Items.AddObject('No file loaded.', TObject(PtrInt(SevInfo)));
    end;
  finally
    ListDiag.Items.EndUpdate;
  end;
end;

procedure TSecEditForm.UpdateStatus;
var
  U: string;
begin
  if FDoc.Loaded then
    StatusBar1.Panels[0].Text := FDoc.FileName
  else
    StatusBar1.Panels[0].Text := 'No file';
  U := FDoc.Props.LengthUnit;
  if U = '' then U := 'mm';
  StatusBar1.Panels[2].Text := Format('zoom %.4g px/%s', [FView.Viewport.Scale, U]);
end;

procedure TSecEditForm.ViewCursor(Sender: TObject; WorldX, WorldY: Double);
begin
  StatusBar1.Panels[1].Text := Format('x %.4g   y %.4g', [WorldX, WorldY]);
end;

procedure TSecEditForm.ViewChanged(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TSecEditForm.SyncViewOptions;
begin
  FView.ShowGrid := miGrid.Checked;
  FView.ShowPrincipal := miPrincipal.Checked;
  FView.ShowBBox := miBBox.Checked;
  TimerReload.Enabled := miAutoReload.Checked;
end;

procedure TSecEditForm.miOpenClick(Sender: TObject);
begin
  if OpenDialog1.Execute then LoadFile(OpenDialog1.FileName, False);
end;

procedure TSecEditForm.miReloadClick(Sender: TObject);
begin
  if FDoc.FileName <> '' then LoadFile(FDoc.FileName, True);
end;

procedure TSecEditForm.miExportClick(Sender: TObject);
begin
  if not FDoc.FacesOk then
  begin
    ShowMessage('There is no valid section to export.');
    Exit;
  end;
  SaveDialog1.FileName := ChangeFileExt(ExtractFileName(FDoc.FileName), '.prop');
  if SaveDialog1.Execute then
  begin
    Screen.Cursor := crHourGlass;
    try
      FDoc.SaveProp(SaveDialog1.FileName);
    finally
      Screen.Cursor := crDefault;
    end;
    RefreshProps(False);
    StatusBar1.Panels[1].Text := 'Saved ' + ExtractFileName(SaveDialog1.FileName);
  end;
end;

procedure TSecEditForm.miExitClick(Sender: TObject);
begin
  Close;
end;

procedure TSecEditForm.miFitClick(Sender: TObject);
begin
  FView.FitView;
end;

procedure TSecEditForm.miViewOptionClick(Sender: TObject);
begin
  SyncViewOptions;
end;

procedure TSecEditForm.miAboutClick(Sender: TObject);
begin
  ShowMessage('FEM3D section editor' + LineEnding + LineEnding +
    'Shows a .fgeo section and its properties, using the same code as the' + LineEnding +
    'femsection command-line tool. Edits made to the file elsewhere (for' + LineEnding +
    'example saved from the web section editor) are picked up automatically' + LineEnding +
    'while View > Auto-reload is on.' + LineEnding + LineEnding +
    'Mouse: wheel zooms, drag pans.  F fits the view, G toggles the grid.');
end;

procedure TSecEditForm.GridPropsDrawCell(Sender: TObject; aCol, aRow: Integer;
  aRect: TRect; aState: TGridDrawState);
var
  G: TStringGrid;
  S: string;
  C, OffsetX: Integer;
  TS: TTextStyle;
begin
  G := GridProps;
  if (aRow <= 0) or (aRow > High(FRowIsGroup)) then
  begin
    G.DefaultDrawCell(aCol, aRow, aRect, aState);
    Exit;
  end;
  if FRowIsGroup[aRow] then
  begin
    G.Canvas.Brush.Color := clBtnFace;
    G.Canvas.FillRect(aRect);
    // draw the heading across all three columns: each cell paints the same
    // text, offset so it lines up, clipped to its own rectangle
    OffsetX := 0;
    for C := 0 to aCol - 1 do Inc(OffsetX, G.ColWidths[C]);
    G.Canvas.Font.Style := [fsBold];
    G.Canvas.Font.Color := clWindowText;
    TS := G.Canvas.TextStyle;       // the grid leaves the column's alignment set
    TS.Alignment := taLeftJustify;
    TS.Layout := tlTop;
    TS.Clipping := True;
    G.Canvas.TextRect(aRect, aRect.Left - OffsetX + 4, aRect.Top + 2, G.Cells[0, aRow], TS);
    G.Canvas.Font.Style := [];
    Exit;
  end;
  S := G.Cells[aCol, aRow];
  if (aCol = 1) and (S = 'solving...') then
  begin
    G.Canvas.Font.Color := clGrayText;
    G.Canvas.Font.Style := [fsItalic];
  end;
  G.DefaultDrawCell(aCol, aRow, aRect, aState);
  G.Canvas.Font.Style := [];
end;

// Ctrl+C copies the selected row as "name<TAB>value<TAB>unit".
procedure TSecEditForm.GridPropsKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
var
  R: Integer;
begin
  if (Key = VK_C) and (ssCtrl in Shift) then
  begin
    R := GridProps.Row;
    if (R > 0) and (R <= High(FRowIsGroup)) and (not FRowIsGroup[R]) then
      Clipboard.AsText := GridProps.Cells[0, R] + #9 + GridProps.Cells[1, R] +
        #9 + GridProps.Cells[2, R];
    Key := 0;
  end;
end;

procedure TSecEditForm.ListDiagDrawItem(Control: TWinControl; Index: Integer;
  ARect: TRect; State: TOwnerDrawState);
var
  LB: TListBox;
begin
  LB := ListDiag;
  if odSelected in State then
  begin
    LB.Canvas.Brush.Color := clHighlight;
    LB.Canvas.Font.Color := clHighlightText;
  end
  else
  begin
    LB.Canvas.Brush.Color := clWindow;
    case PtrInt(LB.Items.Objects[Index]) of
      SevError: LB.Canvas.Font.Color := clRed;
      SevWarning: LB.Canvas.Font.Color := $0060B0;
    else
      LB.Canvas.Font.Color := clGrayText;
    end;
  end;
  LB.Canvas.FillRect(ARect);
  LB.Canvas.TextOut(ARect.Left + 4, ARect.Top + 1, LB.Items[Index]);
end;

// Auto-reload: reload when the file's timestamp changed and has stayed the same
// for one more tick (so a file that is still being written is not read half way).
procedure TSecEditForm.TimerReloadTimer(Sender: TObject);
var
  A: LongInt;
begin
  if (not FDoc.Loaded) or (FDoc.FileName = '') then Exit;
  A := FileAge(FDoc.FileName);
  if (A = -1) or (A = FDoc.FileTime) then
  begin
    FPendingAge := -1;
    Exit;
  end;
  if A = FPendingAge then
    LoadFile(FDoc.FileName, True)
  else
    FPendingAge := A;
end;

procedure TSecEditForm.TimerCalcTimer(Sender: TObject);
begin
  TimerCalc.Enabled := False;
  if not FDoc.FacesOk then Exit;
  Screen.Cursor := crHourGlass;
  try
    FDoc.ComputeFull;
  finally
    Screen.Cursor := crDefault;
  end;
  RefreshProps(False);
  FView.UpdateProps(FDoc.Props);
  RefreshDiagnostics;
end;

procedure TSecEditForm.DoScreenshot(Data: PtrInt);
var
  Bmp: TBitmap;
  Png: TPortableNetworkGraphic;
begin
  Application.ProcessMessages;
  if FDoc.FacesOk then FView.FitView;
  Application.ProcessMessages;
  Bmp := GetFormImage;
  try
    Png := TPortableNetworkGraphic.Create;
    try
      Png.Assign(Bmp);
      Png.SaveToFile(FScreenshotFile);
    finally
      Png.Free;
    end;
  finally
    Bmp.Free;
  end;
  Application.Terminate;
end;

end.
