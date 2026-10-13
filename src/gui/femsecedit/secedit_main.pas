unit secedit_main;

// Main window of the native section editor (femsecedit).
//
// The layout lives in secedit_main.lfm, so it can be adjusted visually in the
// Lazarus designer. The drawing surface (secedit_view.TSectionView) is not a
// registered component, so the form has a placeholder panel (PanelView) and
// the view is created inside it at start-up; the Shapes menu is filled from the
// preset list at start-up too.
//
// Two documents are kept in step:
//   FSk  - the editable sketch with its undo history (fem_sketch)
//   FDoc - the same section validated and analysed exactly as the femsection
//          command-line tool does it (fem_sectiondoc)
// Every edit rebuilds the FEM3DGEO model from the sketch and recomputes; the
// numerical torsion constant J is solved a moment after the last edit.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ExtCtrls,
  ComCtrls, StdCtrls, Grids, Clipbrd, LCLType,
  fem_geometry_types, fem_geometry_io, fem_geometry_validate, fem_proprows,
  fem_sectiondoc, fem_sketch, fem_sectionpresets,
  secedit_view, secedit_presetdlg, secedit_trace;

type
  TSecEditForm = class(TForm)
    MainMenu1: TMainMenu;
    miFile: TMenuItem;
    miNew: TMenuItem;
    miOpen: TMenuItem;
    miReload: TMenuItem;
    miSave: TMenuItem;
    miSaveAs: TMenuItem;
    miExport: TMenuItem;
    miSep1: TMenuItem;
    miExit: TMenuItem;
    miEdit: TMenuItem;
    miUndo: TMenuItem;
    miRedo: TMenuItem;
    miSep3: TMenuItem;
    miDelete: TMenuItem;
    miHole: TMenuItem;
    miDraw: TMenuItem;
    miToolSelect: TMenuItem;
    miToolRect: TMenuItem;
    miToolPolygon: TMenuItem;
    miToolCircle: TMenuItem;
    miShapes: TMenuItem;
    miView: TMenuItem;
    miFit: TMenuItem;
    miSep2: TMenuItem;
    miGrid: TMenuItem;
    miPrincipal: TMenuItem;
    miBBox: TMenuItem;
    miSep4: TMenuItem;
    miSnapObjects: TMenuItem;
    miSnapGrid: TMenuItem;
    miOrtho: TMenuItem;
    miSep5: TMenuItem;
    miAutoReload: TMenuItem;
    miUnits: TMenuItem;
    miUnitMm: TMenuItem;
    miUnitCm: TMenuItem;
    miUnitM: TMenuItem;
    miUnitIn: TMenuItem;
    miHelp: TMenuItem;
    miAbout: TMenuItem;
    ToolBar1: TToolBar;
    tbSelect: TToolButton;
    tbRect: TToolButton;
    tbPolygon: TToolButton;
    tbCircle: TToolButton;
    tbSep1: TToolButton;
    tbUndo: TToolButton;
    tbRedo: TToolButton;
    tbSep2: TToolButton;
    tbDelete: TToolButton;
    tbHole: TToolButton;
    tbSep3: TToolButton;
    tbFit: TToolButton;
    PanelRight: TPanel;
    LabelSection: TLabel;
    ListProfiles: TListBox;
    Splitter3: TSplitter;
    GridProps: TStringGrid;
    Splitter1: TSplitter;
    PanelBottom: TPanel;
    ListDiag: TListBox;
    Splitter2: TSplitter;
    PanelView: TPanel;
    StatusBar1: TStatusBar;
    OpenDialog1: TOpenDialog;
    SaveDialog1: TSaveDialog;
    SaveGeoDialog: TSaveDialog;
    TimerReload: TTimer;
    TimerCalc: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure miNewClick(Sender: TObject);
    procedure miOpenClick(Sender: TObject);
    procedure miReloadClick(Sender: TObject);
    procedure miSaveClick(Sender: TObject);
    procedure miSaveAsClick(Sender: TObject);
    procedure miExportClick(Sender: TObject);
    procedure miExitClick(Sender: TObject);
    procedure miUndoClick(Sender: TObject);
    procedure miRedoClick(Sender: TObject);
    procedure miDeleteClick(Sender: TObject);
    procedure miHoleClick(Sender: TObject);
    procedure miToolClick(Sender: TObject);
    procedure tbToolClick(Sender: TObject);
    procedure miShapeClick(Sender: TObject);
    procedure miFitClick(Sender: TObject);
    procedure miViewOptionClick(Sender: TObject);
    procedure miUnitClick(Sender: TObject);
    procedure miAboutClick(Sender: TObject);
    procedure ListProfilesSelectionChange(Sender: TObject; User: Boolean);
    procedure GridPropsDrawCell(Sender: TObject; aCol, aRow: Integer;
      aRect: TRect; aState: TGridDrawState);
    procedure GridPropsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListDiagDrawItem(Control: TWinControl; Index: Integer;
      ARect: TRect; State: TOwnerDrawState);
    procedure TimerReloadTimer(Sender: TObject);
    procedure TimerCalcTimer(Sender: TObject);
  private
    FSk: TSketchDoc;
    FDoc: TSectionDoc;
    FView: TSectionView;
    FRowIsGroup: array of Boolean;
    FFilePath: string;
    FPendingAge: LongInt;
    FReadOnly: Boolean;
    FReadOnlyReason: string;
    FUnassigned: Integer;
    FUpdatingList: Boolean;
    FAutomation: Boolean;
    FScreenshotFile, FScriptFile: string;
    procedure ParseCommandLine(out FileToOpen: string);
    procedure BuildShapesMenu;
    procedure SetEditTool(T: TEditTool);
    procedure NewDocument(const AUnit: string);
    procedure LoadFile(const AFileName: string; KeepView: Boolean);
    function SaveTo(const APath: string): Boolean;
    function ConfirmDiscard: Boolean;
    procedure Recompute;
    procedure RefreshProps(JPending: Boolean);
    procedure RefreshDiagnostics;
    procedure RefreshProfileList;
    procedure UpdateMenus;
    procedure UpdateTitle;
    procedure UpdateStatus;
    procedure ViewCursor(Sender: TObject; WorldX, WorldY: Double);
    procedure ViewChanged(Sender: TObject);
    procedure ViewSketchChanged(Sender: TObject);
    procedure ViewSelectionChanged(Sender: TObject);
    procedure ViewHint(Sender: TObject; const AText: string);
    procedure SyncViewOptions;
    procedure ApplyUnit(const AUnit: string);
    procedure AddShape(const S: TSketch; Interactive: Boolean);
    procedure DoAutomation(Data: PtrInt);
    procedure RunScript(const AFileName: string);
    procedure ScriptCommand(const Line: string; LineNo: Integer);
    procedure ScriptFail(LineNo: Integer; const Msg: string);
    function DisplayName: string;
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

// ---------------------------------------------------------------- start-up

procedure TSecEditForm.FormCreate(Sender: TObject);
var
  FileToOpen: string;
begin
  FSk := TSketchDoc.Create;
  FDoc := TSectionDoc.Create;
  FPendingAge := -1;

  FView := TSectionView.Create(Self);
  FView.Parent := PanelView;
  FView.Align := alClient;
  FView.OnCursor := @ViewCursor;
  FView.OnViewChange := @ViewChanged;
  FView.OnSketchChanged := @ViewSketchChanged;
  FView.OnSelectionChanged := @ViewSelectionChanged;
  FView.OnHint := @ViewHint;

  BuildShapesMenu;
  ParseCommandLine(FileToOpen);
  FAutomation := (FScreenshotFile <> '') or (FScriptFile <> '');
  SyncViewOptions;

  if FileToOpen <> '' then
    LoadFile(FileToOpen, False)
  else
    NewDocument('mm');

  if FAutomation then
  begin
    TimerReload.Enabled := False;
    Application.QueueAsyncCall(@DoAutomation, 0);
  end;
end;

procedure TSecEditForm.FormDestroy(Sender: TObject);
begin
  FDoc.Free;
  FSk.Free;
end;

// femsecedit [file.fgeo] [--script file] [--screenshot out.png] [--size WxH]
procedure TSecEditForm.ParseCommandLine(out FileToOpen: string);
var
  I, P, W, H: Integer;
  A, S: string;
begin
  FileToOpen := '';
  FScreenshotFile := '';
  FScriptFile := '';
  I := 1;
  while I <= ParamCount do
  begin
    A := ParamStr(I);
    if A = '--screenshot' then
    begin
      Inc(I);
      if I <= ParamCount then FScreenshotFile := ParamStr(I);
    end
    else if A = '--script' then
    begin
      Inc(I);
      if I <= ParamCount then FScriptFile := ParamStr(I);
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
          if (W >= 600) and (H >= 400) then
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

procedure TSecEditForm.BuildShapesMenu;
var
  I: Integer;
  Item: TMenuItem;
begin
  for I := 0 to PresetCount - 1 do
  begin
    Item := TMenuItem.Create(Self);
    Item.Caption := PresetDefAt(I).Caption + '...';
    Item.Tag := I;
    Item.OnClick := @miShapeClick;
    miShapes.Add(Item);
  end;
end;

// ---------------------------------------------------------------- documents

function TSecEditForm.DisplayName: string;
begin
  if FFilePath <> '' then Result := ExtractFileName(FFilePath)
  else Result := FSk.Sketch.Name + '.fgeo';
end;

procedure TSecEditForm.NewDocument(const AUnit: string);
begin
  FSk.NewSketch('Section', AUnit);
  FFilePath := '';
  FReadOnly := False;
  FReadOnlyReason := '';
  FDoc.FileName := '';
  FView.SetDoc(FSk);
  Recompute;
  FView.FitView;
end;

procedure TSecEditForm.LoadFile(const AFileName: string; KeepView: Boolean);
var
  S: TSketch;
  Err: string;
begin
  FPendingAge := -1;
  TimerCalc.Enabled := False;
  FDoc.Load(AFileName);
  FFilePath := AFileName;

  if FDoc.Loaded and FDoc.FacesOk and GeoToSketch(FDoc.Geo, ChangeFileExt(ExtractFileName(AFileName), ''), S, Err) then
  begin
    FReadOnly := False;
    FReadOnlyReason := '';
    FSk.Replace(S);
    FView.SetDoc(FSk);
    Recompute;
    // Recompute replaced the model with the sketch's; keep the file's age
    FDoc.FileName := AFileName;
    FDoc.FileTime := FileAge(AFileName);
  end
  else
  begin
    // shown but not editable
    FReadOnly := True;
    if FDoc.FacesOk then FReadOnlyReason := Err else FReadOnlyReason := FDoc.ErrorText;
    FSk.NewSketch('Section', 'mm');
    if FDoc.FacesOk then
    begin
      FView.SetReadOnlyFaces(FDoc.Faces);
      FView.SetProps(FDoc.Props, True);
      RefreshProps(True);
      TimerCalc.Enabled := True;
    end
    else
    begin
      FView.SetReadOnlyFaces(nil);
      FView.SetMessage(FDoc.ErrorText);
      GridProps.RowCount := 1;
      SetLength(FRowIsGroup, 1);
    end;
    RefreshDiagnostics;
    RefreshProfileList;
  end;
  if not KeepView then FView.FitView;
  UpdateMenus;
  UpdateTitle;
  UpdateStatus;
end;

function TSecEditForm.SaveTo(const APath: string): Boolean;
var
  Geo: TFEMGeometryModel;
  U: Integer;
begin
  Result := False;
  if FReadOnly then
  begin
    ShowMessage('This file is open read-only: ' + FReadOnlyReason);
    Exit;
  end;
  if Length(FSk.Sketch.Profiles) = 0 then
  begin
    if not FAutomation then ShowMessage('There is nothing to save yet.');
    Exit;
  end;
  SketchToGeo(FSk.Sketch, Geo, U);
  if (U > 0) and not FAutomation then
    if MessageDlg('Save', Format('%d hole(s) lie outside every solid shape and will not be saved. Save anyway?', [U]),
         mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  WriteFGeoFile(Geo, APath);
  FFilePath := APath;
  FDoc.FileName := APath;
  FDoc.FileTime := FileAge(APath);
  FPendingAge := -1;
  FSk.Dirty := False;
  UpdateTitle;
  Result := True;
end;

// True if it is fine to throw the current document away.
function TSecEditForm.ConfirmDiscard: Boolean;
var
  R: TModalResult;
begin
  Result := True;
  if FAutomation or not FSk.Dirty then Exit;
  R := MessageDlg('Unsaved changes', 'Save the changes to ' + DisplayName + ' first?',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0);
  case R of
    mrYes:
      begin
        if FFilePath = '' then
        begin
          SaveGeoDialog.FileName := FSk.Sketch.Name + '.fgeo';
          if SaveGeoDialog.Execute then Result := SaveTo(SaveGeoDialog.FileName) else Result := False;
        end
        else
          Result := SaveTo(FFilePath);
      end;
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

procedure TSecEditForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := ConfirmDiscard;
end;

// Rebuilds the model from the sketch and refreshes everything that depends on it.
procedure TSecEditForm.Recompute;
var
  Geo: TFEMGeometryModel;
begin
  if FReadOnly then Exit;
  SketchToGeo(FSk.Sketch, Geo, FUnassigned);
  if Length(FSk.Sketch.Profiles) = 0 then
  begin
    FDoc.SetModel(Geo, DisplayName);
    FDoc.ErrorText := '';
    FView.SetProps(FDoc.Props, False);
    GridProps.RowCount := 1;
    SetLength(FRowIsGroup, 1);
    LabelSection.Caption := 'Nothing drawn yet';
  end
  else
  begin
    FDoc.SetModel(Geo, DisplayName);
    FView.SetProps(FDoc.Props, FDoc.FacesOk);
    if FDoc.FacesOk then
    begin
      RefreshProps(True);
      LabelSection.Caption := FDoc.Props.Name + '  (' + FDoc.Props.LengthUnit + ')';
      TimerCalc.Enabled := False;    // restart the debounce
      TimerCalc.Enabled := True;
    end
    else
    begin
      GridProps.RowCount := 1;
      SetLength(FRowIsGroup, 1);
      LabelSection.Caption := FSk.Sketch.Name;
    end;
  end;
  RefreshDiagnostics;
  RefreshProfileList;
  UpdateMenus;
  UpdateTitle;
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
    GridProps.RowCount := 1;
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
    if FReadOnly then
      ListDiag.Items.AddObject('READ-ONLY  ' + FReadOnlyReason, TObject(PtrInt(SevWarning)));
    if (Length(FSk.Sketch.Profiles) = 0) and not FReadOnly then
      ListDiag.Items.AddObject('Nothing drawn yet.', TObject(PtrInt(SevInfo)))
    else
    begin
      if FDoc.ErrorText <> '' then
        ListDiag.Items.AddObject('ERROR  ' + FDoc.ErrorText, TObject(PtrInt(SevError)));
      if FUnassigned > 0 then
        ListDiag.Items.AddObject(Format('WARNING  %d hole(s) lie outside every solid shape and are ignored.', [FUnassigned]),
          TObject(PtrInt(SevWarning)));
      for I := 0 to High(FDoc.Diags.Items) do
      begin
        D := FDoc.Diags.Items[I];
        if D.Severity = gsError then Sev := SevError else Sev := SevWarning;
        ListDiag.Items.AddObject(D.Code + '  ' + D.Msg, TObject(PtrInt(Sev)));
      end;
      if ListDiag.Items.Count = 0 then
        ListDiag.Items.AddObject('No geometry problems found.', TObject(PtrInt(SevInfo)));
    end;
  finally
    ListDiag.Items.EndUpdate;
  end;
end;

procedure TSecEditForm.RefreshProfileList;
var
  I, K, Arcs: Integer;
  P: TSketchProfile;
  S: string;
begin
  FUpdatingList := True;
  try
    ListProfiles.Items.BeginUpdate;
    try
      ListProfiles.Items.Clear;
      for I := 0 to High(FSk.Sketch.Profiles) do
      begin
        P := FSk.Sketch.Profiles[I];
        if P.IsHole then S := 'hole   ' else S := 'solid  ';
        if P.Kind = pkCircle then
          S := S + Format('circle  r = %.5g', [P.Radius])
        else
        begin
          Arcs := 0;
          for K := 0 to High(P.Segs) do
            if P.Segs[K].Kind = skArc then Inc(Arcs);
          S := S + Format('%d segments', [Length(P.Segs)]);
          if Arcs > 0 then S := S + Format(' (%d arcs)', [Arcs]);
        end;
        ListProfiles.Items.Add(Format('%d  %s', [I + 1, S]));
      end;
    finally
      ListProfiles.Items.EndUpdate;
    end;
    if (FView.Selected >= 0) and (FView.Selected < ListProfiles.Items.Count) then
      ListProfiles.ItemIndex := FView.Selected
    else
      ListProfiles.ItemIndex := -1;
  finally
    FUpdatingList := False;
  end;
end;

procedure TSecEditForm.UpdateMenus;
var
  Edit, HasSel: Boolean;
begin
  Edit := FView.Editable;
  HasSel := Edit and (FView.Selected >= 0);
  miUndo.Enabled := Edit and FSk.CanUndo;
  miRedo.Enabled := Edit and FSk.CanRedo;
  tbUndo.Enabled := miUndo.Enabled;
  tbRedo.Enabled := miRedo.Enabled;
  if FSk.CanUndo then miUndo.Caption := '&Undo ' + FSk.UndoName else miUndo.Caption := '&Undo';
  if FSk.CanRedo then miRedo.Caption := '&Redo ' + FSk.RedoName else miRedo.Caption := '&Redo';
  miDelete.Enabled := HasSel;
  tbDelete.Enabled := HasSel;
  miHole.Enabled := HasSel;
  tbHole.Enabled := HasSel;
  miShapes.Enabled := Edit;
  miToolRect.Enabled := Edit;
  miToolPolygon.Enabled := Edit;
  miToolCircle.Enabled := Edit;
  tbRect.Enabled := Edit;
  tbPolygon.Enabled := Edit;
  tbCircle.Enabled := Edit;
  miUnits.Enabled := Edit;
  miSave.Enabled := Edit;
  miSaveAs.Enabled := Edit;
end;

procedure TSecEditForm.UpdateTitle;
var
  S: string;
begin
  S := 'FEM3D Section Editor - ' + DisplayName;
  if FSk.Dirty then S := S + ' *';
  if FReadOnly then S := S + ' (read-only)';
  Caption := S;
end;

procedure TSecEditForm.UpdateStatus;
var
  U: string;
begin
  if FFilePath <> '' then StatusBar1.Panels[0].Text := FFilePath
  else StatusBar1.Panels[0].Text := '(unsaved)';
  U := FSk.Sketch.LengthUnit;
  if FReadOnly then U := FDoc.Props.LengthUnit;
  if U = '' then U := 'mm';
  StatusBar1.Panels[3].Text := Format('zoom %.4g px/%s', [FView.Viewport.Scale, U]);
end;

// ---------------------------------------------------------------- view events

procedure TSecEditForm.ViewCursor(Sender: TObject; WorldX, WorldY: Double);
begin
  StatusBar1.Panels[2].Text := Format('x %.4g   y %.4g', [WorldX, WorldY]);
end;

procedure TSecEditForm.ViewChanged(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TSecEditForm.ViewSketchChanged(Sender: TObject);
begin
  Recompute;
end;

procedure TSecEditForm.ViewSelectionChanged(Sender: TObject);
begin
  if not FUpdatingList then
  begin
    FUpdatingList := True;
    try
      if (FView.Selected >= 0) and (FView.Selected < ListProfiles.Items.Count) then
        ListProfiles.ItemIndex := FView.Selected
      else
        ListProfiles.ItemIndex := -1;
    finally
      FUpdatingList := False;
    end;
  end;
  UpdateMenus;
end;

procedure TSecEditForm.ViewHint(Sender: TObject; const AText: string);
begin
  StatusBar1.Panels[1].Text := AText;
end;

procedure TSecEditForm.ListProfilesSelectionChange(Sender: TObject; User: Boolean);
begin
  if FUpdatingList or not User then Exit;
  FView.SelectProfile(ListProfiles.ItemIndex);
end;

procedure TSecEditForm.SyncViewOptions;
begin
  FView.ShowGrid := miGrid.Checked;
  FView.ShowPrincipal := miPrincipal.Checked;
  FView.ShowBBox := miBBox.Checked;
  FView.SnapObjects := miSnapObjects.Checked;
  FView.SnapGrid := miSnapGrid.Checked;
  FView.Ortho := miOrtho.Checked;
  TimerReload.Enabled := miAutoReload.Checked;
end;

// ---------------------------------------------------------------- tools

procedure TSecEditForm.SetEditTool(T: TEditTool);
begin
  FView.Tool := T;
  case FView.Tool of
    etSelect: begin tbSelect.Down := True; miToolSelect.Checked := True; end;
    etRect: begin tbRect.Down := True; miToolRect.Checked := True; end;
    etPolygon: begin tbPolygon.Down := True; miToolPolygon.Checked := True; end;
    etCircle: begin tbCircle.Down := True; miToolCircle.Checked := True; end;
  end;
end;

procedure TSecEditForm.miToolClick(Sender: TObject);
begin
  SetEditTool(TEditTool((Sender as TMenuItem).Tag));
end;

procedure TSecEditForm.tbToolClick(Sender: TObject);
begin
  SetEditTool(TEditTool((Sender as TToolButton).Tag));
end;

procedure TSecEditForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Shift <> [] then Exit;
  case Key of
    VK_ESCAPE:
      begin
        FView.CancelTool;
        SetEditTool(FView.Tool);
        Key := 0;
      end;
    VK_RETURN:
      if FView.Tool = etPolygon then
      begin
        FView.FinishPolygon;
        Key := 0;
      end;
    VK_BACK:
      if (FView.Tool <> etSelect) and (ActiveControl = nil) or (ActiveControl is TPanel) then
      begin
        FView.UndoLastPoint;
        Key := 0;
      end;
  end;
end;

procedure TSecEditForm.miUndoClick(Sender: TObject);
begin
  if not FSk.CanUndo then Exit;
  FSk.Undo;
  FView.SketchReplaced;
  Recompute;
end;

procedure TSecEditForm.miRedoClick(Sender: TObject);
begin
  if not FSk.CanRedo then Exit;
  FSk.Redo;
  FView.SketchReplaced;
  Recompute;
end;

procedure TSecEditForm.miDeleteClick(Sender: TObject);
begin
  FView.DeleteSelected;
end;

procedure TSecEditForm.miHoleClick(Sender: TObject);
begin
  FView.ToggleHoleSelected;
end;

procedure TSecEditForm.miFitClick(Sender: TObject);
begin
  FView.FitView;
end;

procedure TSecEditForm.miViewOptionClick(Sender: TObject);
begin
  SyncViewOptions;
end;

// ---------------------------------------------------------------- shapes and units

procedure TSecEditForm.AddShape(const S: TSketch; Interactive: Boolean);
var
  B1, B2: TSketchBox;
  R: TModalResult;
  Offset: Double;
begin
  if Length(FSk.Sketch.Profiles) = 0 then
  begin
    FSk.Checkpoint('Add ' + S.Name);
    SkAppend(FSk.Sketch, S, 0, 0);
    FSk.Sketch.Name := S.Name;
  end
  else
  begin
    if Interactive then
      R := MessageDlg('Shape', 'Replace the current drawing with this shape?' + LineEnding +
        '(No adds it next to what is there.)', mtConfirmation, [mbYes, mbNo, mbCancel], 0)
    else
      R := mrYes;
    if R = mrCancel then Exit;
    if R = mrYes then
    begin
      FSk.Checkpoint('Replace with ' + S.Name);
      FSk.Sketch.Profiles := nil;
      SkAppend(FSk.Sketch, S, 0, 0);
      FSk.Sketch.Name := S.Name;
    end
    else
    begin
      FSk.Checkpoint('Add ' + S.Name);
      B1 := SketchBounds(FSk.Sketch);
      B2 := SketchBounds(S);
      Offset := B1.XMax - B2.XMin + 0.1 * (B1.XMax - B1.XMin);
      SkAppend(FSk.Sketch, S, Offset, 0);
    end;
  end;
  FView.SetDoc(FSk);
  Recompute;
  FView.FitView;
end;

procedure TSecEditForm.miShapeClick(Sender: TObject);
var
  S: TSketch;
begin
  if not FView.Editable then Exit;
  if AskPreset(PresetDefAt((Sender as TMenuItem).Tag), FSk.Sketch.LengthUnit, S) then
    AddShape(S, True);
end;

procedure TSecEditForm.ApplyUnit(const AUnit: string);
begin
  if FSk.Sketch.LengthUnit = AUnit then Exit;
  FSk.Checkpoint('Change units');
  FSk.Sketch.LengthUnit := AUnit;
  if FSk.Sketch.HasHeader then FSk.Sketch.Header.LengthUnit := AUnit;
  FView.SketchReplaced;
  Recompute;
end;

procedure TSecEditForm.miUnitClick(Sender: TObject);
begin
  case (Sender as TMenuItem).Tag of
    0: ApplyUnit('mm');
    1: ApplyUnit('cm');
    2: ApplyUnit('m');
    3: ApplyUnit('in');
  end;
end;

// ---------------------------------------------------------------- file menu

procedure TSecEditForm.miNewClick(Sender: TObject);
begin
  if ConfirmDiscard then NewDocument(FSk.Sketch.LengthUnit);
end;

procedure TSecEditForm.miOpenClick(Sender: TObject);
begin
  if not ConfirmDiscard then Exit;
  if OpenDialog1.Execute then LoadFile(OpenDialog1.FileName, False);
end;

procedure TSecEditForm.miReloadClick(Sender: TObject);
begin
  if FFilePath = '' then Exit;
  if ConfirmDiscard then LoadFile(FFilePath, True);
end;

procedure TSecEditForm.miSaveClick(Sender: TObject);
begin
  if FFilePath = '' then miSaveAsClick(Sender) else SaveTo(FFilePath);
end;

procedure TSecEditForm.miSaveAsClick(Sender: TObject);
begin
  if FFilePath <> '' then SaveGeoDialog.FileName := FFilePath
  else SaveGeoDialog.FileName := FSk.Sketch.Name + '.fgeo';
  if SaveGeoDialog.Execute then SaveTo(SaveGeoDialog.FileName);
end;

procedure TSecEditForm.miExportClick(Sender: TObject);
begin
  if not FDoc.FacesOk then
  begin
    ShowMessage('There is no valid section to export.');
    Exit;
  end;
  SaveDialog1.FileName := ChangeFileExt(DisplayName, '.prop');
  if SaveDialog1.Execute then
  begin
    Screen.Cursor := crHourGlass;
    try
      FDoc.SaveProp(SaveDialog1.FileName, DisplayName);
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

procedure TSecEditForm.miAboutClick(Sender: TObject);
begin
  ShowMessage('FEM3D section editor' + LineEnding + LineEnding +
    'Draw or load a section; every property updates as you edit, computed by' + LineEnding +
    'the same code as the femsection command-line tool.' + LineEnding + LineEnding +
    'Draw: R rectangle, P polygon, C circle (Enter closes a polygon, Esc cancels).' + LineEnding +
    'A shape drawn inside a solid becomes a hole; H toggles hole/solid.' + LineEnding +
    'Select: click a shape, drag it, or drag a square handle to move a corner.' + LineEnding +
    'Mouse: wheel zooms, right/middle drag pans.  F fits, G toggles the grid.' + LineEnding +
    'Shapes menu: standard sections.  Ctrl+Z / Ctrl+Y undo and redo.');
end;

// ---------------------------------------------------------------- grids and lists

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
    OffsetX := 0;
    for C := 0 to aCol - 1 do Inc(OffsetX, G.ColWidths[C]);
    G.Canvas.Font.Style := [fsBold];
    G.Canvas.Font.Color := clWindowText;
    TS := G.Canvas.TextStyle;
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

procedure TSecEditForm.GridPropsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
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

// ---------------------------------------------------------------- timers

// Auto-reload: reload when the file changed on disk and has stayed unchanged for
// one more tick (so a half-written file is not read). Not while there are unsaved edits.
procedure TSecEditForm.TimerReloadTimer(Sender: TObject);
var
  A: LongInt;
begin
  if (FFilePath = '') or FSk.Dirty then Exit;
  A := FileAge(FFilePath);
  if (A = -1) or (A = FDoc.FileTime) then
  begin
    FPendingAge := -1;
    Exit;
  end;
  if A = FPendingAge then
    LoadFile(FFilePath, True)
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
  FView.SetProps(FDoc.Props, True);
  RefreshDiagnostics;
end;

// ---------------------------------------------------------------- automation

procedure TSecEditForm.ScriptFail(LineNo: Integer; const Msg: string);
begin
  raise Exception.Create(Format('script line %d: %s', [LineNo, Msg]));
end;

// One script line. Commands (see docs/femsecedit.md):
//   new [unit] | open PATH | save PATH | export PATH | unit U | fit
//   tool select|rect|polygon|circle | click X Y | move X Y | drag X0 Y0 X1 Y1
//   finish | cancel
//   undo | redo | delete | hole | select N
//   snap objects|grid|none | ortho on|off | preset ID v1 v2 ...
//   expect profiles N | expect area VALUE [REL] | expect dirty yes|no | expect selected N
// A token that starts with $ is replaced by that environment variable.
procedure TSecEditForm.ScriptCommand(const Line: string; LineNo: Integer);
var
  Tok: TStringList;
  Cmd, A: string;
  I: Integer;
  X, Y, V, Rel: Double;
  FS: TFormatSettings;
  Vals: array of Double;
  S: TSketch;
  Err: string;

  function Arg(N: Integer): string;
  begin
    if N >= Tok.Count then ScriptFail(LineNo, 'missing argument for ' + Cmd);
    Result := Tok[N];
    if (Length(Result) > 1) and (Result[1] = '$') then
      Result := GetEnvironmentVariable(Copy(Result, 2, MaxInt));
  end;

  function Num(N: Integer): Double;
  begin
    if not TryStrToFloat(Arg(N), Result, FS) then
      ScriptFail(LineNo, 'not a number: ' + Arg(N));
  end;

begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Tok := TStringList.Create;
  try
    Tok.Delimiter := ' ';
    Tok.StrictDelimiter := True;
    Tok.DelimitedText := Trim(Line);
    for I := Tok.Count - 1 downto 0 do
      if Tok[I] = '' then Tok.Delete(I);
    if Tok.Count = 0 then Exit;
    Cmd := LowerCase(Tok[0]);

    if Cmd = 'new' then
    begin
      if Tok.Count > 1 then A := Arg(1) else A := 'mm';
      NewDocument(A);
    end
    else if Cmd = 'open' then LoadFile(Arg(1), False)
    else if Cmd = 'save' then
    begin
      if not SaveTo(Arg(1)) then ScriptFail(LineNo, 'save failed');
    end
    else if Cmd = 'export' then
    begin
      if not FDoc.FacesOk then ScriptFail(LineNo, 'no valid section to export');
      FDoc.SaveProp(Arg(1), DisplayName);
    end
    else if Cmd = 'unit' then ApplyUnit(Arg(1))
    else if Cmd = 'fit' then FView.FitView
    else if Cmd = 'tool' then
    begin
      A := LowerCase(Arg(1));
      if A = 'select' then SetEditTool(etSelect)
      else if A = 'rect' then SetEditTool(etRect)
      else if A = 'polygon' then SetEditTool(etPolygon)
      else if A = 'circle' then SetEditTool(etCircle)
      else ScriptFail(LineNo, 'unknown tool ' + A);
    end
    else if Cmd = 'click' then
    begin
      X := Num(1); Y := Num(2);
      FView.ClickAt(X, Y);
    end
    else if Cmd = 'move' then
    begin
      X := Num(1); Y := Num(2);
      FView.MoveCursorTo(X, Y);
    end
    else if Cmd = 'drag' then
    begin
      X := Num(1); Y := Num(2);
      FView.ScriptDrag(X, Y, Num(3), Num(4));
    end
    else if Cmd = 'finish' then FView.FinishPolygon
    else if Cmd = 'cancel' then begin FView.CancelTool; SetEditTool(FView.Tool); end
    else if Cmd = 'undo' then miUndoClick(nil)
    else if Cmd = 'redo' then miRedoClick(nil)
    else if Cmd = 'delete' then FView.DeleteSelected
    else if Cmd = 'hole' then FView.ToggleHoleSelected
    else if Cmd = 'select' then FView.SelectProfile(Round(Num(1)) - 1)
    else if Cmd = 'snap' then
    begin
      A := LowerCase(Arg(1));
      miSnapObjects.Checked := (A = 'objects') or (A = 'both');
      miSnapGrid.Checked := (A = 'grid') or (A = 'both');
      SyncViewOptions;
    end
    else if Cmd = 'ortho' then
    begin
      miOrtho.Checked := LowerCase(Arg(1)) = 'on';
      SyncViewOptions;
    end
    else if Cmd = 'preset' then
    begin
      SetLength(Vals, Tok.Count - 2);
      for I := 2 to Tok.Count - 1 do Vals[I - 2] := Num(I);
      if not BuildPreset(Arg(1), Vals, FSk.Sketch.LengthUnit, S, Err) then
        ScriptFail(LineNo, Err);
      AddShape(S, False);
    end
    else if Cmd = 'expect' then
    begin
      A := LowerCase(Arg(1));
      if A = 'profiles' then
      begin
        if Length(FSk.Sketch.Profiles) <> Round(Num(2)) then
          ScriptFail(LineNo, Format('expected %d profile(s), found %d', [Round(Num(2)), Length(FSk.Sketch.Profiles)]));
      end
      else if A = 'area' then
      begin
        if not FDoc.FacesOk then ScriptFail(LineNo, 'there is no valid section');
        V := Num(2);
        if Tok.Count > 3 then Rel := Num(3) else Rel := 1.0E-6;
        if Abs(FDoc.Props.Area - V) > Rel * Abs(V) then
          ScriptFail(LineNo, Format('expected area %.8g, found %.8g', [V, FDoc.Props.Area]));
      end
      else if A = 'dirty' then
      begin
        if FSk.Dirty <> (LowerCase(Arg(2)) = 'yes') then
          ScriptFail(LineNo, 'unexpected modified state');
      end
      else if A = 'selected' then
      begin
        if FView.Selected <> Round(Num(2)) - 1 then
          ScriptFail(LineNo, Format('expected profile %d selected, found %d', [Round(Num(2)), FView.Selected + 1]));
      end
      else ScriptFail(LineNo, 'unknown expectation ' + A);
    end
    else
      ScriptFail(LineNo, 'unknown command ' + Cmd);
  finally
    Tok.Free;
  end;
end;

procedure TSecEditForm.RunScript(const AFileName: string);
var
  SL: TStringList;
  I: Integer;
  L: string;
begin
  SL := TStringList.Create;
  try
    SL.LoadFromFile(AFileName);
    for I := 0 to SL.Count - 1 do
    begin
      L := Trim(SL[I]);
      if (L = '') or (L[1] = '#') then Continue;
      ScriptCommand(L, I + 1);
    end;
  finally
    SL.Free;
  end;
end;

procedure TSecEditForm.DoAutomation(Data: PtrInt);
var
  Bmp: TBitmap;
  Png: TPortableNetworkGraphic;
begin
  Trace('DoAutomation');
  try
    if FScriptFile <> '' then RunScript(FScriptFile);
    Application.ProcessMessages;
    // finish the numerical torsion solve so the picture shows final values
    TimerCalc.Enabled := False;
    if FDoc.FacesOk and not FDoc.FullDone then
    begin
      FDoc.ComputeFull;
      RefreshProps(False);
      FView.SetProps(FDoc.Props, True);
    end;
    if FScreenshotFile <> '' then
    begin
      if FDoc.FacesOk or (Length(FSk.Sketch.Profiles) > 0) then FView.FitView;
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
    end;
  except
    on E: Exception do
    begin
      try
        WriteLn(StdErr, 'femsecedit: ', E.Message);
      except
      end;
      ExitCode := 3;
    end;
  end;
  Application.Terminate;
end;

end.
