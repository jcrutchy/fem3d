unit MainUnit;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, ComCtrls, Menus,
  StdCtrls, Dialogs, Grids, Math, Process, FEMTypes, FEMModel, FEMElements, FEMMatrix,
  FEMAnalysis, FEMAnalysisCases, FEMIO, FEMView, FEMOpenGLView, FEMVerification, FEMAnalysisUI, FEMSolverProcess, FEMResults, FEMResultFields, FEMValidation, FEMHash, FEMDisplayManager, FEMModelEditor, FEMBeamMesher, OpenGLContext;

type
  TInteractiveEditMode = (iemNone, iemCreateNode, iemCreateBeam, iemMoveNode);

  TMainForm = class(TForm)
  private
    Model:TFEMModel;
    Registry:TElementRegistry;
    View:TFEMViewport;
    Tree:TTreeView;
    CanvasBox:TOpenGLControl;
    GLView:TOpenGLFEMRenderer;
    Display:TDisplayManager;
    Editor:TModelEditor;
    Inspector:TMemo;
    Log:TMemo;
    Status:TStatusBar;
    SplitLeft,SplitRight:TPanel;
    OpenDlg:TOpenDialog;
    SaveDlg:TSaveDialog;
    ActiveAnalysisID:Integer;
    LastResult:TFEMResultDocument;
    ResultFields:TResultFieldCollection;
    DisplayPanel:TPanel;
    DisplayKind,DisplayMaterial,DisplaySection,DisplayGroup:TComboBox;
    DisplayHide,DisplayShow,DisplayIsolate,DisplayRestore,DisplayAll:TButton;
    DisplayInfo:TLabel;
    SymbolPanel:TPanel;
    ShowLoads,ShowRestraints,ShowLocalAxes,ShowCoordinateSystems:TCheckBox;
    ViewPanel:TPanel;
    ProjectionCombo:TComboBox;
    FOVEdit,NearClipEdit:TEdit;
    ViewFront,ViewRear,ViewLeft,ViewRight,ViewTop,ViewBottom,ViewIso,ViewFit,ViewFocus,ViewFitSel:TButton;
    SelectionModeCombo:TComboBox; SelectionClear,SelectionIsolate:TButton;
    ShowSolidMembers:TCheckBox;
    EditPanel:TPanel;
    EditCreateNode,EditCreateBeam,EditMoveNode,EditSplit,EditSubdivide,EditMeshBeam,EditAssign,EditTranslate,EditDelete,EditUndo,EditRedo,EditRotate,EditMirror,EditCopy:TButton;
    EditModeLabel:TLabel;
    EditPlaneCombo:TComboBox; EditPlaneOffset,EditGridStep:TEdit; EditSnapGrid:TCheckBox; EditMaterialCombo,EditSectionCombo,EditGroupCombo:TComboBox; EditCancel:TButton;
    InteractiveMode:TInteractiveEditMode; PendingBeamNodeID:Integer;
    PendingMoveNodeID:Integer;
    MovePreviewActive:Boolean; MovePreviewPoint:TVec3;
    BeamPreviewActive:Boolean; BeamPreviewStart:TVec3; BeamPreviewEnd:TVec3;
    LastViewX,LastViewY:Integer;
    SelectionBoxActive:Boolean; SelectionBoxX1,SelectionBoxY1:Integer;
    ResultPanel:TPanel;
    ResultQuantity:TComboBox;
    DeformationScale:TEdit;
    ShowDeformed:TCheckBox;
    ShowUndeformed:TCheckBox;
    ResultInfo:TLabel;
    ResultExpression:TButton;
    AutoScaleButton:TButton;
    AutoRangeButton:TButton;
    ContourMinEdit,ContourMaxEdit:TEdit;
    NodeTableButton,ElementTableButton,ResultStatsButton:TButton;
    ClipEnable:TCheckBox; ClipAxis:TComboBox; ClipPlane,ClipReverse:TCheckBox; ClipSlider:TTrackBar;
    ControlScroll: TScrollBox;
    procedure SelectionModeChange(Sender:TObject);
    procedure SelectionClearClick(Sender:TObject);
    procedure SelectionIsolateClick(Sender:TObject);
    procedure ViewDblClick(Sender:TObject);
    procedure ViewControlAction(Sender:TObject);
    procedure CameraSettingChange(Sender:TObject);
    procedure ClipChanged(Sender:TObject);
    procedure DisplayAction(Sender:TObject);
    procedure ResultQuantityChange(Sender:TObject);
    procedure DeformationScaleChange(Sender:TObject);
    procedure ResultVisibilityChange(Sender:TObject);
    procedure ResultExpressionClick(Sender:TObject);
    procedure AutoScaleClick(Sender:TObject);
    procedure AutoRangeClick(Sender:TObject);
    procedure ContourRangeChange(Sender:TObject);
    procedure NodeTableClick(Sender:TObject);
    procedure ElementTableClick(Sender:TObject);
    procedure ResultStatsClick(Sender:TObject);
    procedure LoadResultFile(const FileName:string);
    procedure ClearResults;
    procedure UpdateSelectionInspector;
    procedure ShowResultTable(ALocation:TResultLocation);
    procedure ShowResultStatistics;
    procedure BuildUI;
    procedure SeedExample;
    procedure Refresh;
    procedure PaintView(Sender:TObject);
    procedure MouseDownView(Sender:TObject; Button:TMouseButton; Shift:TShiftState; X,Y:Integer);
    procedure MouseMoveView(Sender:TObject; Shift:TShiftState; X,Y:Integer);
    procedure MouseUpView(Sender:TObject; Button:TMouseButton; Shift:TShiftState; X,Y:Integer);
    procedure MouseWheelView(Sender:TObject; Shift:TShiftState; WheelDelta:Integer; MousePos:TPoint; var Handled:Boolean);
    procedure ValidateClick(Sender:TObject);
    procedure SolveClick(Sender:TObject);
    procedure LinearStaticClick(Sender:TObject);
    procedure LinearBucklingClick(Sender:TObject);
    procedure NonlinearStaticClick(Sender:TObject);
    procedure ViewResultsClick(Sender:TObject);
    procedure AnalysisManagerClick(Sender:TObject);
    procedure UnimplementedAnalysisClick(Sender:TObject);
    procedure NewClick(Sender:TObject);
    procedure OpenClick(Sender:TObject);
    procedure SaveClick(Sender:TObject);
    procedure DXFClick(Sender:TObject);
    procedure IGESClick(Sender:TObject);
    procedure FitClick(Sender:TObject);
    procedure VerifyClick(Sender:TObject);
    procedure ExitClick(Sender:TObject);
    procedure EditCreateNodeClick(Sender:TObject);
    procedure EditCreateBeamClick(Sender:TObject);
    procedure EditMoveNodeClick(Sender:TObject);
    procedure EditSplitClick(Sender:TObject);
    procedure EditSubdivideClick(Sender:TObject);
    procedure EditMeshBeamClick(Sender:TObject);
    procedure EditAssignClick(Sender:TObject);
    procedure EditTranslateClick(Sender:TObject);
    procedure EditRotateClick(Sender:TObject);
    procedure EditMirrorClick(Sender:TObject);
    procedure EditCopyClick(Sender:TObject);
    procedure EditDeleteClick(Sender:TObject);
    procedure EditUndoClick(Sender:TObject);
    procedure EditRedoClick(Sender:TObject);
    procedure ModelEdited(AResetView:Boolean=True);
    procedure SetInteractiveMode(Mode:TInteractiveEditMode);
    function InteractivePoint(X,Y:Integer; out P:TVec3):Boolean;
    function SnapPointToGrid(const P:TVec3):TVec3;
    function PickOrCreateInteractiveNode(X,Y:Integer; out NodeID:Integer):Boolean;
    procedure UpdateEditModeUI;
    procedure EditCancelClick(Sender:TObject);
  public
    constructor Create(AOwner:TComponent); override;
    destructor Destroy; override;
  end;

var MainForm:TMainForm;

implementation

constructor TMainForm.Create(AOwner:TComponent);
begin
  inherited Create(AOwner);

  Caption := 'FEM3D â€” transparent engineering FEA';
  Width := 1400;
  Height := 850;
  Position := poScreenCenter;

  Model := TFEMModel.Create;
  Registry := TElementRegistry.Create;
  RegisterBuiltInElements(Registry);

  View := TFEMViewport.Create(Model);
  Display := TDisplayManager.Create;
  Editor := TModelEditor.Create(Model);

  ActiveAnalysisID := 0;
  LastResult := nil;
  ResultFields := nil;
  InteractiveMode:=iemNone;
  PendingBeamNodeID:=-1; BeamPreviewActive:=False; BeamPreviewStart:=Vec3(0,0,0); BeamPreviewEnd:=Vec3(0,0,0);
  PendingMoveNodeID:=-1; MovePreviewActive:=False; MovePreviewPoint:=Vec3(0,0,0);

  BuildUI;

  GLView := TOpenGLFEMRenderer.Create(CanvasBox, Model, View);
  GLView.SetDisplayManager(Display);

  SeedExample;
  Refresh;
  View.FitAll;
  CanvasBox.Invalidate;
end;

destructor TMainForm.Destroy;
begin
  ClearResults;

  FreeAndNil(GLView);
  FreeAndNil(Editor);
  FreeAndNil(Display);
  FreeAndNil(View);
  FreeAndNil(Registry);
  FreeAndNil(Model);

  inherited Destroy;
end;

procedure TMainForm.BuildUI;
var FM,AM,VM,Item:TMenuItem;
begin
  Menu:=TMainMenu.Create(Self);
  FM:=TMenuItem.Create(Menu);FM.Caption:='File';Menu.Items.Add(FM);
  Item:=TMenuItem.Create(Menu);Item.Caption:='New';Item.OnClick:=@NewClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Open FEM3D...';Item.OnClick:=@OpenClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Save FEM3D...';Item.OnClick:=@SaveClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Import DXF...';Item.OnClick:=@DXFClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Import IGES wireframe...';Item.OnClick:=@IGESClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Exit';Item.OnClick:=@ExitClick;FM.Add(Item);
  FM:=TMenuItem.Create(Menu);FM.Caption:='Model';Menu.Items.Add(FM);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Create node...';Item.OnClick:=@EditCreateNodeClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Create beam from selected nodes';Item.OnClick:=@EditCreateBeamClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Move selected node...';Item.OnClick:=@EditMoveNodeClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Split selected beam';Item.OnClick:=@EditSplitClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Subdivide selected beam...';Item.OnClick:=@EditSubdivideClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Mesh selected beam by maximum length...';Item.OnClick:=@EditMeshBeamClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Assign properties to selected elements';Item.OnClick:=@EditAssignClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Translate selected geometry...';Item.OnClick:=@EditTranslateClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Delete selected';Item.OnClick:=@EditDeleteClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Undo';Item.OnClick:=@EditUndoClick;FM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Redo';Item.OnClick:=@EditRedoClick;FM.Add(Item);
  AM:=TMenuItem.Create(Menu);AM.Caption:='Solve';Menu.Items.Add(AM);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Linear Static...';Item.OnClick:=@LinearStaticClick;AM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Linear Buckling...';Item.OnClick:=@LinearBucklingClick;AM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Modal...';Item.OnClick:=@UnimplementedAnalysisClick;Item.Enabled:=False;AM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Linear Dynamic...';Item.OnClick:=@UnimplementedAnalysisClick;Item.Enabled:=False;AM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Nonlinear Static...';Item.OnClick:=@NonlinearStaticClick;AM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Nonlinear Transient...';Item.OnClick:=@UnimplementedAnalysisClick;Item.Enabled:=False;AM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='-';AM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Analysis Manager...';Item.OnClick:=@AnalysisManagerClick;AM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='View Last Results...';Item.OnClick:=@ViewResultsClick;AM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Validate model';Item.OnClick:=@ValidateClick;AM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Run verification benchmark';Item.OnClick:=@VerifyClick;AM.Add(Item);

  VM:=TMenuItem.Create(Menu);VM.Caption:='View';Menu.Items.Add(VM);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Fit model';Item.OnClick:=@FitClick;VM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Fit selection';Item.OnClick:=@ViewControlAction;Item.Tag:=10;VM.Add(Item);
  Item:=TMenuItem.Create(Menu);Item.Caption:='Focus selection';Item.OnClick:=@ViewControlAction;Item.Tag:=11;VM.Add(Item);

  Tree:=TTreeView.Create(Self);Tree.Parent:=Self;Tree.Align:=alLeft;Tree.Width:=230;
  SplitLeft:=TPanel.Create(Self);SplitLeft.Parent:=Self;SplitLeft.Align:=alLeft;SplitLeft.Width:=1;SplitLeft.BevelOuter:=bvNone;
  CanvasBox:=TOpenGLControl.Create(Self);CanvasBox.Parent:=Self;CanvasBox.Align:=alClient;CanvasBox.AutoResizeViewport:=True;CanvasBox.DoubleBuffered:=True;CanvasBox.MultiSampling:=4;CanvasBox.OnPaint:=@PaintView;
  CanvasBox.OnMouseDown:=@MouseDownView;CanvasBox.OnMouseMove:=@MouseMoveView;CanvasBox.OnMouseUp:=@MouseUpView;
  CanvasBox.OnMouseWheel:=@MouseWheelView;CanvasBox.OnDblClick:=@ViewDblClick;
  SplitRight:=TPanel.Create(Self);SplitRight.Parent:=Self;SplitRight.Align:=alRight;SplitRight.Width:=340;SplitRight.BevelOuter:=bvNone;
  ControlScroll:=TScrollBox.Create(Self);ControlScroll.Parent:=SplitRight;ControlScroll.Align:=alClient;ControlScroll.BorderStyle:=bsNone;ControlScroll.AutoScroll:=True;
  ControlScroll.VertScrollBar.Visible:=True;ControlScroll.HorzScrollBar.Visible:=False;
  DisplayPanel:=TPanel.Create(Self);DisplayPanel.Parent:=ControlScroll;DisplayPanel.Align:=alTop;DisplayPanel.Height:=210;DisplayPanel.BevelOuter:=bvNone;
  with TLabel.Create(Self) do begin Parent:=DisplayPanel;Left:=8;Top:=7;Caption:='DISPLAY MANAGER';Font.Style:=[fsBold];end;
  with TLabel.Create(Self) do begin Parent:=DisplayPanel;Left:=8;Top:=31;Caption:='Element type';end;
  DisplayKind:=TComboBox.Create(Self);DisplayKind.Parent:=DisplayPanel;DisplayKind.Left:=90;DisplayKind.Top:=27;DisplayKind.Width:=225;DisplayKind.Style:=csDropDownList;
  with TLabel.Create(Self) do begin Parent:=DisplayPanel;Left:=8;Top:=61;Caption:='Material';end;
  DisplayMaterial:=TComboBox.Create(Self);DisplayMaterial.Parent:=DisplayPanel;DisplayMaterial.Left:=90;DisplayMaterial.Top:=57;DisplayMaterial.Width:=225;DisplayMaterial.Style:=csDropDownList;
  with TLabel.Create(Self) do begin Parent:=DisplayPanel;Left:=8;Top:=91;Caption:='Section';end;
  DisplaySection:=TComboBox.Create(Self);DisplaySection.Parent:=DisplayPanel;DisplaySection.Left:=90;DisplaySection.Top:=87;DisplaySection.Width:=225;DisplaySection.Style:=csDropDownList;
  with TLabel.Create(Self) do begin Parent:=DisplayPanel;Left:=8;Top:=121;Caption:='Group';end;
  DisplayGroup:=TComboBox.Create(Self);DisplayGroup.Parent:=DisplayPanel;DisplayGroup.Left:=90;DisplayGroup.Top:=117;DisplayGroup.Width:=225;DisplayGroup.Style:=csDropDownList;
  DisplayHide:=TButton.Create(Self);DisplayHide.Parent:=DisplayPanel;DisplayHide.Left:=8;DisplayHide.Top:=150;DisplayHide.Width:=58;DisplayHide.Caption:='Hide';DisplayHide.Tag:=1;DisplayHide.OnClick:=@DisplayAction;
  DisplayShow:=TButton.Create(Self);DisplayShow.Parent:=DisplayPanel;DisplayShow.Left:=70;DisplayShow.Top:=150;DisplayShow.Width:=58;DisplayShow.Caption:='Show';DisplayShow.Tag:=2;DisplayShow.OnClick:=@DisplayAction;
  DisplayIsolate:=TButton.Create(Self);DisplayIsolate.Parent:=DisplayPanel;DisplayIsolate.Left:=132;DisplayIsolate.Top:=150;DisplayIsolate.Width:=75;DisplayIsolate.Caption:='Isolate';DisplayIsolate.Tag:=3;DisplayIsolate.OnClick:=@DisplayAction;
  DisplayRestore:=TButton.Create(Self);DisplayRestore.Parent:=DisplayPanel;DisplayRestore.Left:=211;DisplayRestore.Top:=150;DisplayRestore.Width:=65;DisplayRestore.Caption:='Restore';DisplayRestore.Tag:=4;DisplayRestore.OnClick:=@DisplayAction;
  DisplayAll:=TButton.Create(Self);DisplayAll.Parent:=DisplayPanel;DisplayAll.Left:=280;DisplayAll.Top:=150;DisplayAll.Width:=35;DisplayAll.Caption:='All';DisplayAll.Tag:=5;DisplayAll.OnClick:=@DisplayAction;
  DisplayInfo:=TLabel.Create(Self);DisplayInfo.Parent:=DisplayPanel;DisplayInfo.Left:=8;DisplayInfo.Top:=181;DisplayInfo.Caption:='All geometry visible';
  SymbolPanel:=TPanel.Create(Self);SymbolPanel.Parent:=ControlScroll;SymbolPanel.Align:=alTop;SymbolPanel.Height:=105;SymbolPanel.BevelOuter:=bvNone;
  with TLabel.Create(Self) do begin Parent:=SymbolPanel;Left:=8;Top:=7;Caption:='ENGINEERING SYMBOLS';Font.Style:=[fsBold];end;
  ShowLoads:=TCheckBox.Create(Self);ShowLoads.Parent:=SymbolPanel;ShowLoads.Left:=8;ShowLoads.Top:=31;ShowLoads.Caption:='Loads';ShowLoads.Checked:=True;ShowLoads.OnChange:=@CameraSettingChange;
  ShowRestraints:=TCheckBox.Create(Self);ShowRestraints.Parent:=SymbolPanel;ShowRestraints.Left:=95;ShowRestraints.Top:=31;ShowRestraints.Caption:='Restraints';ShowRestraints.Checked:=True;ShowRestraints.OnChange:=@CameraSettingChange;
  ShowLocalAxes:=TCheckBox.Create(Self);ShowLocalAxes.Parent:=SymbolPanel;ShowLocalAxes.Left:=190;ShowLocalAxes.Top:=31;ShowLocalAxes.Caption:='Local axes';ShowLocalAxes.Checked:=False;ShowLocalAxes.OnChange:=@CameraSettingChange;
  ShowCoordinateSystems:=TCheckBox.Create(Self);ShowCoordinateSystems.Parent:=SymbolPanel;ShowCoordinateSystems.Left:=8;ShowCoordinateSystems.Top:=60;ShowCoordinateSystems.Caption:='Coordinate systems';ShowCoordinateSystems.Checked:=True;ShowCoordinateSystems.OnChange:=@CameraSettingChange;
  ViewPanel:=TPanel.Create(Self);ViewPanel.Parent:=ControlScroll;ViewPanel.Align:=alTop;ViewPanel.Height:=165;ViewPanel.BevelOuter:=bvNone;
  with TLabel.Create(Self) do begin Parent:=ViewPanel;Left:=8;Top:=7;Caption:='VIEWPORT';Font.Style:=[fsBold];end;
  with TLabel.Create(Self) do begin Parent:=ViewPanel;Left:=8;Top:=31;Caption:='Projection';end;
  ProjectionCombo:=TComboBox.Create(Self);ProjectionCombo.Parent:=ViewPanel;ProjectionCombo.Left:=75;ProjectionCombo.Top:=27;ProjectionCombo.Width:=105;ProjectionCombo.Style:=csDropDownList;ProjectionCombo.Items.Add('Perspective');ProjectionCombo.Items.Add('Orthographic');ProjectionCombo.ItemIndex:=0;ProjectionCombo.OnChange:=@CameraSettingChange;
  with TLabel.Create(Self) do begin Parent:=ViewPanel;Left:=190;Top:=31;Caption:='FOV';end;
  FOVEdit:=TEdit.Create(Self);FOVEdit.Parent:=ViewPanel;FOVEdit.Left:=220;FOVEdit.Top:=27;FOVEdit.Width:=45;FOVEdit.Text:='45';FOVEdit.OnChange:=@CameraSettingChange;
  with TLabel.Create(Self) do begin Parent:=ViewPanel;Left:=272;Top:=31;Caption:='Near';end;
  NearClipEdit:=TEdit.Create(Self);NearClipEdit.Parent:=ViewPanel;NearClipEdit.Left:=303;NearClipEdit.Top:=27;NearClipEdit.Width:=30;NearClipEdit.Text:='0.01';NearClipEdit.OnChange:=@CameraSettingChange;
  ViewFront:=TButton.Create(Self);ViewFront.Parent:=ViewPanel;ViewFront.Left:=8;ViewFront.Top:=60;ViewFront.Width:=48;ViewFront.Caption:='Front';ViewFront.Tag:=1;ViewFront.OnClick:=@ViewControlAction;
  ViewRear:=TButton.Create(Self);ViewRear.Parent:=ViewPanel;ViewRear.Left:=58;ViewRear.Top:=60;ViewRear.Width:=48;ViewRear.Caption:='Rear';ViewRear.Tag:=2;ViewRear.OnClick:=@ViewControlAction;
  ViewLeft:=TButton.Create(Self);ViewLeft.Parent:=ViewPanel;ViewLeft.Left:=108;ViewLeft.Top:=60;ViewLeft.Width:=48;ViewLeft.Caption:='Left';ViewLeft.Tag:=3;ViewLeft.OnClick:=@ViewControlAction;
  ViewRight:=TButton.Create(Self);ViewRight.Parent:=ViewPanel;ViewRight.Left:=158;ViewRight.Top:=60;ViewRight.Width:=48;ViewRight.Caption:='Right';ViewRight.Tag:=4;ViewRight.OnClick:=@ViewControlAction;
  ViewTop:=TButton.Create(Self);ViewTop.Parent:=ViewPanel;ViewTop.Left:=208;ViewTop.Top:=60;ViewTop.Width:=48;ViewTop.Caption:='Top';ViewTop.Tag:=5;ViewTop.OnClick:=@ViewControlAction;
  ViewBottom:=TButton.Create(Self);ViewBottom.Parent:=ViewPanel;ViewBottom.Left:=258;ViewBottom.Top:=60;ViewBottom.Width:=48;ViewBottom.Caption:='Bottom';ViewBottom.Tag:=6;ViewBottom.OnClick:=@ViewControlAction;
  ViewIso:=TButton.Create(Self);ViewIso.Parent:=ViewPanel;ViewIso.Left:=308;ViewIso.Top:=60;ViewIso.Width:=25;ViewIso.Caption:='Iso';ViewIso.Tag:=7;ViewIso.OnClick:=@ViewControlAction;
  ViewFit:=TButton.Create(Self);ViewFit.Parent:=ViewPanel;ViewFit.Left:=8;ViewFit.Top:=94;ViewFit.Width:=75;ViewFit.Caption:='Fit all';ViewFit.Tag:=8;ViewFit.OnClick:=@ViewControlAction;
  ViewFitSel:=TButton.Create(Self);ViewFitSel.Parent:=ViewPanel;ViewFitSel.Left:=87;ViewFitSel.Top:=94;ViewFitSel.Width:=85;ViewFitSel.Caption:='Fit selected';ViewFitSel.Tag:=9;ViewFitSel.OnClick:=@ViewControlAction;
  ViewFocus:=TButton.Create(Self);ViewFocus.Parent:=ViewPanel;ViewFocus.Left:=176;ViewFocus.Top:=94;ViewFocus.Width:=82;ViewFocus.Caption:='Focus sel.';ViewFocus.Tag:=11;ViewFocus.OnClick:=@ViewControlAction;
  with TLabel.Create(Self) do begin Parent:=ViewPanel;Left:=8;Top:=130;Caption:='Orbit: middle drag   Pan: right drag   Zoom: wheel';end;
  ShowSolidMembers:=TCheckBox.Create(Self);ShowSolidMembers.Parent:=ViewPanel;ShowSolidMembers.Left:=190;ShowSolidMembers.Top:=127;ShowSolidMembers.Caption:='Solid members';ShowSolidMembers.Checked:=True;ShowSolidMembers.OnChange:=@CameraSettingChange;
  with TLabel.Create(Self) do begin Parent:=ViewPanel;Left:=8;Top:=151;Caption:='Select';end;
  SelectionModeCombo:=TComboBox.Create(Self);SelectionModeCombo.Parent:=ViewPanel;SelectionModeCombo.Left:=55;SelectionModeCombo.Top:=147;SelectionModeCombo.Width:=90;SelectionModeCombo.Style:=csDropDownList;SelectionModeCombo.Items.Add('Element');SelectionModeCombo.Items.Add('Node');SelectionModeCombo.ItemIndex:=0;SelectionModeCombo.OnChange:=@SelectionModeChange;
  SelectionClear:=TButton.Create(Self);SelectionClear.Parent:=ViewPanel;SelectionClear.Left:=150;SelectionClear.Top:=146;SelectionClear.Width:=75;SelectionClear.Caption:='Clear';SelectionClear.OnClick:=@SelectionClearClick;
  SelectionIsolate:=TButton.Create(Self);SelectionIsolate.Parent:=ViewPanel;SelectionIsolate.Left:=230;SelectionIsolate.Top:=146;SelectionIsolate.Width:=95;SelectionIsolate.Caption:='Isolate sel.';SelectionIsolate.OnClick:=@SelectionIsolateClick;
  ViewPanel.Height:=195;
  EditPanel:=TPanel.Create(Self);EditPanel.Parent:=ControlScroll;EditPanel.Align:=alTop;EditPanel.Height:=205;EditPanel.BevelOuter:=bvNone;
  with TLabel.Create(Self) do begin Parent:=EditPanel;Left:=8;Top:=6;Caption:='MODEL EDITING';Font.Style:=[fsBold];end;
  EditCreateNode:=TButton.Create(Self);EditCreateNode.Parent:=EditPanel;EditCreateNode.Left:=8;EditCreateNode.Top:=29;EditCreateNode.Width:=60;EditCreateNode.Caption:='Add node';EditCreateNode.OnClick:=@EditCreateNodeClick;
  EditCreateBeam:=TButton.Create(Self);EditCreateBeam.Parent:=EditPanel;EditCreateBeam.Left:=72;EditCreateBeam.Top:=29;EditCreateBeam.Width:=70;EditCreateBeam.Caption:='Add beam';EditCreateBeam.OnClick:=@EditCreateBeamClick;
  EditMoveNode:=TButton.Create(Self);EditMoveNode.Parent:=EditPanel;EditMoveNode.Left:=146;EditMoveNode.Top:=29;EditMoveNode.Width:=62;EditMoveNode.Caption:='Move node';EditMoveNode.OnClick:=@EditMoveNodeClick;
  EditSplit:=TButton.Create(Self);EditSplit.Parent:=EditPanel;EditSplit.Left:=212;EditSplit.Top:=29;EditSplit.Width:=52;EditSplit.Caption:='Split';EditSplit.OnClick:=@EditSplitClick;
  EditSubdivide:=TButton.Create(Self);EditSubdivide.Parent:=EditPanel;EditSubdivide.Left:=268;EditSubdivide.Top:=29;EditSubdivide.Width:=64;EditSubdivide.Caption:='Subdivide';EditSubdivide.OnClick:=@EditSubdivideClick;
  EditMeshBeam:=TButton.Create(Self);EditMeshBeam.Parent:=EditPanel;EditMeshBeam.Left:=8;EditMeshBeam.Top:=57;EditMeshBeam.Width:=70;EditMeshBeam.Caption:='Mesh beam';EditMeshBeam.OnClick:=@EditMeshBeamClick;
  EditAssign:=TButton.Create(Self);EditAssign.Parent:=EditPanel;EditAssign.Left:=84;EditAssign.Top:=57;EditAssign.Width:=58;EditAssign.Caption:='Assign';EditAssign.OnClick:=@EditAssignClick;
  EditTranslate:=TButton.Create(Self);EditTranslate.Parent:=EditPanel;EditTranslate.Left:=146;EditTranslate.Top:=57;EditTranslate.Width:=70;EditTranslate.Caption:='Translate';EditTranslate.OnClick:=@EditTranslateClick;
  EditDelete:=TButton.Create(Self);EditDelete.Parent:=EditPanel;EditDelete.Left:=220;EditDelete.Top:=57;EditDelete.Width:=55;EditDelete.Caption:='Delete';EditDelete.OnClick:=@EditDeleteClick;
  EditUndo:=TButton.Create(Self);EditUndo.Parent:=EditPanel;EditUndo.Left:=8;EditUndo.Top:=85;EditUndo.Width:=55;EditUndo.Caption:='Undo';EditUndo.OnClick:=@EditUndoClick;
  EditRedo:=TButton.Create(Self);EditRedo.Parent:=EditPanel;EditRedo.Left:=67;EditRedo.Top:=85;EditRedo.Width:=55;EditRedo.Caption:='Redo';EditRedo.OnClick:=@EditRedoClick;
  EditRotate:=TButton.Create(Self);EditRotate.Parent:=EditPanel;EditRotate.Left:=128;EditRotate.Top:=85;EditRotate.Width:=65;EditRotate.Caption:='Rotate';EditRotate.OnClick:=@EditRotateClick;
  EditMirror:=TButton.Create(Self);EditMirror.Parent:=EditPanel;EditMirror.Left:=198;EditMirror.Top:=85;EditMirror.Width:=65;EditMirror.Caption:='Mirror';EditMirror.OnClick:=@EditMirrorClick;
  EditCopy:=TButton.Create(Self);EditCopy.Parent:=EditPanel;EditCopy.Left:=268;EditCopy.Top:=85;EditCopy.Width:=55;EditCopy.Caption:='Copy';EditCopy.OnClick:=@EditCopyClick;
  with TLabel.Create(Self) do begin Parent:=EditPanel;Left:=8;Top:=89;Caption:='Plane';end;
  EditPlaneCombo:=TComboBox.Create(Self);EditPlaneCombo.Parent:=EditPanel;EditPlaneCombo.Left:=43;EditPlaneCombo.Top:=113;EditPlaneCombo.Width:=45;EditPlaneCombo.Style:=csDropDownList;EditPlaneCombo.Items.Add('XY');EditPlaneCombo.Items.Add('XZ');EditPlaneCombo.Items.Add('YZ');EditPlaneCombo.ItemIndex:=0;
  with TLabel.Create(Self) do begin Parent:=EditPanel;Left:=92;Top:=117;Caption:='Offset';end;
  EditPlaneOffset:=TEdit.Create(Self);EditPlaneOffset.Parent:=EditPanel;EditPlaneOffset.Left:=132;EditPlaneOffset.Top:=113;EditPlaneOffset.Width:=48;EditPlaneOffset.Text:='0';
  EditSnapGrid:=TCheckBox.Create(Self);EditSnapGrid.Parent:=EditPanel;EditSnapGrid.Left:=190;EditSnapGrid.Top:=114;EditSnapGrid.Caption:='Grid snap';EditSnapGrid.Checked:=True;
  with TLabel.Create(Self) do begin Parent:=EditPanel;Left:=270;Top:=117;Caption:='Step';end;
  EditGridStep:=TEdit.Create(Self);EditGridStep.Parent:=EditPanel;EditGridStep.Left:=300;EditGridStep.Top:=113;EditGridStep.Width:=32;EditGridStep.Text:='0.25';
  with TLabel.Create(Self) do begin Parent:=EditPanel;Left:=8;Top:=145;Caption:='Material';end;
  EditMaterialCombo:=TComboBox.Create(Self);EditMaterialCombo.Parent:=EditPanel;EditMaterialCombo.Left:=55;EditMaterialCombo.Top:=141;EditMaterialCombo.Width:=95;EditMaterialCombo.Style:=csDropDownList;
  with TLabel.Create(Self) do begin Parent:=EditPanel;Left:=157;Top:=145;Caption:='Section';end;
  EditSectionCombo:=TComboBox.Create(Self);EditSectionCombo.Parent:=EditPanel;EditSectionCombo.Left:=205;EditSectionCombo.Top:=141;EditSectionCombo.Width:=125;EditSectionCombo.Style:=csDropDownList;
  with TLabel.Create(Self) do begin Parent:=EditPanel;Left:=8;Top:=173;Caption:='Group';end;
  EditGroupCombo:=TComboBox.Create(Self);EditGroupCombo.Parent:=EditPanel;EditGroupCombo.Left:=55;EditGroupCombo.Top:=169;EditGroupCombo.Width:=145;EditGroupCombo.Style:=csDropDownList;
  EditModeLabel:=TLabel.Create(Self);EditModeLabel.Parent:=EditPanel;EditModeLabel.Left:=8;EditModeLabel.Top:=199;EditModeLabel.Caption:='Click Add node or Add beam, then draw in the viewport.';
  EditCancel:=TButton.Create(Self);EditCancel.Parent:=EditPanel;EditCancel.Left:=268;EditCancel.Top:=199;EditCancel.Width:=60;EditCancel.Caption:='Cancel';EditCancel.OnClick:=@EditCancelClick;
  ResultPanel:=TPanel.Create(Self);ResultPanel.Parent:=ControlScroll;ResultPanel.Align:=alTop;ResultPanel.Height:=335;ResultPanel.BevelOuter:=bvNone;
  ResultInfo:=TLabel.Create(Self);ResultInfo.Parent:=ResultPanel;ResultInfo.Left:=8;ResultInfo.Top:=8;ResultInfo.Caption:='No results loaded';
  ResultQuantity:=TComboBox.Create(Self);ResultQuantity.Parent:=ResultPanel;ResultQuantity.Left:=8;ResultQuantity.Top:=32;ResultQuantity.Width:=315;ResultQuantity.Style:=csDropDownList;ResultQuantity.OnChange:=@ResultQuantityChange;
  ResultExpression:=TButton.Create(Self);ResultExpression.Parent:=ResultPanel;ResultExpression.Left:=8;ResultExpression.Top:=65;ResultExpression.Width:=120;ResultExpression.Caption:='Expression...';ResultExpression.OnClick:=@ResultExpressionClick;
  AutoScaleButton:=TButton.Create(Self);AutoScaleButton.Parent:=ResultPanel;AutoScaleButton.Left:=230;AutoScaleButton.Top:=65;AutoScaleButton.Width:=85;AutoScaleButton.Caption:='Auto scale';AutoScaleButton.OnClick:=@AutoScaleClick;
  DeformationScale:=TEdit.Create(Self);DeformationScale.Parent:=ResultPanel;DeformationScale.Left:=145;DeformationScale.Top:=65;DeformationScale.Width:=80;DeformationScale.Text:='1';DeformationScale.OnChange:=@DeformationScaleChange;
  ShowDeformed:=TCheckBox.Create(Self);ShowDeformed.Parent:=ResultPanel;ShowDeformed.Left:=8;ShowDeformed.Top:=98;ShowDeformed.Caption:='Deformed shape';ShowDeformed.Checked:=False;ShowDeformed.OnChange:=@ResultVisibilityChange;
  ShowUndeformed:=TCheckBox.Create(Self);ShowUndeformed.Parent:=ResultPanel;ShowUndeformed.Left:=150;ShowUndeformed.Top:=98;ShowUndeformed.Caption:='Show original';ShowUndeformed.Checked:=True;ShowUndeformed.OnChange:=@ResultVisibilityChange;
  ContourMinEdit:=TEdit.Create(Self);ContourMinEdit.Parent:=ResultPanel;ContourMinEdit.Left:=8;ContourMinEdit.Top:=130;ContourMinEdit.Width:=95;ContourMinEdit.Text:='auto';ContourMinEdit.OnChange:=@ContourRangeChange;
  ContourMaxEdit:=TEdit.Create(Self);ContourMaxEdit.Parent:=ResultPanel;ContourMaxEdit.Left:=110;ContourMaxEdit.Top:=130;ContourMaxEdit.Width:=95;ContourMaxEdit.Text:='auto';ContourMaxEdit.OnChange:=@ContourRangeChange;
  AutoRangeButton:=TButton.Create(Self);AutoRangeButton.Parent:=ResultPanel;AutoRangeButton.Left:=230;AutoRangeButton.Top:=128;AutoRangeButton.Width:=85;AutoRangeButton.Caption:='Auto range';AutoRangeButton.OnClick:=@AutoRangeClick;
  NodeTableButton:=TButton.Create(Self);NodeTableButton.Parent:=ResultPanel;NodeTableButton.Left:=8;NodeTableButton.Top:=165;NodeTableButton.Width:=100;NodeTableButton.Caption:='Node results...';NodeTableButton.OnClick:=@NodeTableClick;
  ElementTableButton:=TButton.Create(Self);ElementTableButton.Parent:=ResultPanel;ElementTableButton.Left:=113;ElementTableButton.Top:=165;ElementTableButton.Width:=105;ElementTableButton.Caption:='Element results...';ElementTableButton.OnClick:=@ElementTableClick;
  ResultStatsButton:=TButton.Create(Self);ResultStatsButton.Parent:=ResultPanel;ResultStatsButton.Left:=223;ResultStatsButton.Top:=165;ResultStatsButton.Width:=92;ResultStatsButton.Caption:='Statistics...';ResultStatsButton.OnClick:=@ResultStatsClick;
  ClipEnable:=TCheckBox.Create(Self);ClipEnable.Parent:=ResultPanel;ClipEnable.Left:=8;ClipEnable.Top:=202;ClipEnable.Caption:='3D clipping plane';ClipEnable.OnChange:=@ClipChanged;
  ClipAxis:=TComboBox.Create(Self);ClipAxis.Parent:=ResultPanel;ClipAxis.Left:=150;ClipAxis.Top:=198;ClipAxis.Width:=70;ClipAxis.Style:=csDropDownList;ClipAxis.Items.Add('X');ClipAxis.Items.Add('Y');ClipAxis.Items.Add('Z');ClipAxis.ItemIndex:=0;ClipAxis.OnChange:=@ClipChanged;
  ClipPlane:=TCheckBox.Create(Self);ClipPlane.Parent:=ResultPanel;ClipPlane.Left:=230;ClipPlane.Top:=202;ClipPlane.Caption:='Show plane';ClipPlane.Checked:=True;ClipPlane.OnChange:=@ClipChanged;
  ClipReverse:=TCheckBox.Create(Self);ClipReverse.Parent:=ResultPanel;ClipReverse.Left:=8;ClipReverse.Top:=260;ClipReverse.Caption:='Reverse side';ClipReverse.OnChange:=@ClipChanged;
  ClipSlider:=TTrackBar.Create(Self);ClipSlider.Parent:=ResultPanel;ClipSlider.Left:=8;ClipSlider.Top:=235;ClipSlider.Width:=307;ClipSlider.Min:=0;ClipSlider.Max:=100;ClipSlider.Position:=50;ClipSlider.Frequency:=10;ClipSlider.OnChange:=@ClipChanged;
  with TLabel.Create(Self) do begin Parent:=ResultPanel;Left:=8;Top:=285;Caption:='Graphics: OpenGL | middle-drag orbit | right-drag pan | wheel zoom';end;
  with TLabel.Create(Self) do begin Parent:=ResultPanel;Left:=8;Top:=305;Caption:='Clipping keeps the positive side of the selected plane.';end;
  Inspector:=TMemo.Create(Self);Inspector.Parent:=SplitRight;Inspector.Align:=alBottom;Inspector.Height:=150;Inspector.ReadOnly:=True;Inspector.ScrollBars:=ssAutoBoth;
  Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alBottom;Log.Height:=50;Log.ReadOnly:=True;
  Status:=TStatusBar.Create(Self);Status.Parent:=Self;Status.Align:=alBottom;
  OpenDlg:=TOpenDialog.Create(Self);SaveDlg:=TSaveDialog.Create(Self);
end;

procedure TMainForm.SeedExample;
var N1,N2,Mat,Sec,LC,Grp:Integer; V:TDofVector;
begin
  Model.Clear;
  Mat:=Model.AddMaterial('Structural steel',200e9,0.3,7850);
  Sec:=Model.AddSection('Demo section',0.01,8e-6,3e-6,1e-6);
  LC:=Model.AddLoadCase('LC1 â€” tip load');
  Grp:=Model.AddGroup('Demo beam');
  N1:=Model.AddNode(Vec3(0,0,0));N2:=Model.AddNode(Vec3(5,0,0));
  FillChar(Model.Nodes[0].Restraint,SizeOf(TDofMask),1);
  FillChar(V,SizeOf(V),0);V[2]:=-10000;
  Model.AddNodalLoad(N2,LC,V);
  with Model.AnalysisCases.Add(atLinearStatic,'Linear Static â€” LC1') do begin LoadCaseID:=LC; ActiveAnalysisID:=ID; end;
  Model.AddElement('BEAM3D',[N1,N2],Mat,Sec,0,0,Grp);
end;

procedure TMainForm.Refresh;
var I:Integer; A:TAnalysisCase; S:TAnalysisSettings;
begin
  Tree.Items.Clear;
  DisplayKind.Items.Clear; DisplayKind.Items.Add('â€” any type â€”');
  DisplayMaterial.Items.Clear; DisplayMaterial.Items.Add('â€” any material â€”');
  DisplaySection.Items.Clear; DisplaySection.Items.Add('â€” any section â€”');
  DisplayGroup.Items.Clear; DisplayGroup.Items.Add('â€” any group â€”');
  for I:=0 to High(Model.Elements) do if DisplayKind.Items.IndexOf(Model.Elements[I].Kind)<0 then DisplayKind.Items.Add(Model.Elements[I].Kind);
  for I:=0 to High(Model.Materials) do DisplayMaterial.Items.AddObject(Model.Materials[I].Name,TObject(PtrInt(Model.Materials[I].ID)));
  for I:=0 to High(Model.Sections) do DisplaySection.Items.AddObject(Model.Sections[I].Name,TObject(PtrInt(Model.Sections[I].ID)));
  for I:=0 to High(Model.Groups) do DisplayGroup.Items.AddObject(Model.Groups[I].Name,TObject(PtrInt(Model.Groups[I].ID)));
  DisplayKind.ItemIndex:=0; DisplayMaterial.ItemIndex:=0; DisplaySection.ItemIndex:=0; DisplayGroup.ItemIndex:=0;
  if Assigned(EditMaterialCombo) then begin
    EditMaterialCombo.Items.Clear; EditSectionCombo.Items.Clear; EditGroupCombo.Items.Clear;
    for I:=0 to High(Model.Materials) do EditMaterialCombo.Items.AddObject(Model.Materials[I].Name,TObject(PtrInt(Model.Materials[I].ID)));
    for I:=0 to High(Model.Sections) do EditSectionCombo.Items.AddObject(Model.Sections[I].Name,TObject(PtrInt(Model.Sections[I].ID)));
    EditGroupCombo.Items.AddObject('(none)',TObject(PtrInt(0)));
    for I:=0 to High(Model.Groups) do EditGroupCombo.Items.AddObject(Model.Groups[I].Name,TObject(PtrInt(Model.Groups[I].ID)));
    if EditMaterialCombo.Items.Count>0 then EditMaterialCombo.ItemIndex:=0;
    if EditSectionCombo.Items.Count>0 then EditSectionCombo.ItemIndex:=0;
    EditGroupCombo.ItemIndex:=0;
  end;
  Tree.Items.Add(nil,Format('Nodes (%d)',[Length(Model.Nodes)]));
  Tree.Items.Add(nil,Format('Elements (%d)',[Length(Model.Elements)]));
  Tree.Items.Add(nil,Format('Materials (%d)',[Length(Model.Materials)]));
  Tree.Items.Add(nil,Format('Sections (%d)',[Length(Model.Sections)]));
  Tree.Items.Add(nil,Format('Load cases (%d)',[Length(Model.LoadCases)]));
  Tree.Items.Add(nil,Format('Combinations (%d)',[Length(Model.Combinations)]));
  Tree.Items.Add(nil,Format('Groups (%d)',[Length(Model.Groups)]));
  Tree.Items.Add(nil,Format('Analysis cases (%d)',[Model.AnalysisCases.Count]));
  Inspector.Clear;
  Inspector.Lines.Add('MODEL');
  Inspector.Lines.Add('--------------------------------');
  Inspector.Lines.Add(Format('Nodes              %d',[Length(Model.Nodes)]));
  Inspector.Lines.Add(Format('Elements           %d',[Length(Model.Elements)]));
  Inspector.Lines.Add(Format('Materials          %d',[Length(Model.Materials)]));
  Inspector.Lines.Add(Format('Sections           %d',[Length(Model.Sections)]));
  Inspector.Lines.Add(Format('Load cases         %d',[Length(Model.LoadCases)]));
  Inspector.Lines.Add(Format('Analysis cases     %d',[Model.AnalysisCases.Count]));
  Inspector.Lines.Add('');
  Inspector.Lines.Add('ANALYSIS CASES');
  Inspector.Lines.Add('--------------------------------');
  for I:=0 to Model.AnalysisCases.Count-1 do begin
    A:=Model.AnalysisCases.Item(I);
    Inspector.Lines.Add(Format('%d  %s  [%s]  LC=%d',[A.ID,A.Name,A.TypeName,A.LoadCaseID]));
    if A.ID=ActiveAnalysisID then Inspector.Lines.Add('  * active');
    S:=A.Settings;
    if S is TLinearStaticSettings then begin
      Inspector.Lines.Add('  Solver: '+TLinearStaticSettings(S).SolverName);
      Inspector.Lines.Add('  Storage: '+MatrixStorageToString(TLinearStaticSettings(S).MatrixStorage));
    end else if S is TBucklingSettings then begin
      Inspector.Lines.Add('  Solver: '+TBucklingSettings(S).SolverName);
      Inspector.Lines.Add(Format('  Modes: %d',[TBucklingSettings(S).EigenvalueCount]));
    end else if S is TNonlinearStaticSettings then begin
      Inspector.Lines.Add('  Solver: '+TNonlinearStaticSettings(S).SolverName);
      Inspector.Lines.Add(Format('  Initial steps: %d',[TNonlinearStaticSettings(S).InitialLoadSteps]));
    end;
  end;
  Inspector.Lines.Add('');
  Inspector.Lines.Add('ELEMENT REGISTRY');
  for I:=0 to Registry.Count-1 do Inspector.Lines.Add('  '+Registry.Item(I).Kind+' â€” '+Registry.Item(I).Description);
  CanvasBox.Invalidate;
  Status.SimpleText:=Format('%d nodes | %d elements | %d DOF | active analysis %d',[Length(Model.Nodes),Length(Model.Elements),Model.TotalDOF,ActiveAnalysisID]);
end;

procedure TMainForm.PaintView(Sender:TObject);
begin
  if GLView<>nil then begin
    GLView.SetResultFields(ResultFields);
    GLView.SetShowLoads(ShowLoads.Checked);
    GLView.SetShowRestraints(ShowRestraints.Checked);
    GLView.SetShowLocalAxes(ShowLocalAxes.Checked);
    GLView.SetShowCoordinateSystems(ShowCoordinateSystems.Checked);
    GLView.SetShowSolidMembers(ShowSolidMembers.Checked);
    GLView.Paint;
  end;
end;

procedure TMainForm.DisplayAction(Sender:TObject);
var I,ID:Integer; K:string;
begin
  if Display=nil then Exit;
  case TButton(Sender).Tag of
    1: begin
      if DisplayKind.ItemIndex>0 then begin K:=DisplayKind.Text; Display.HideByKind(Model,K); end
      else if DisplayMaterial.ItemIndex>0 then begin ID:=Integer(PtrInt(DisplayMaterial.Items.Objects[DisplayMaterial.ItemIndex])); Display.HideByMaterial(Model,ID); end
      else if DisplaySection.ItemIndex>0 then begin ID:=Integer(PtrInt(DisplaySection.Items.Objects[DisplaySection.ItemIndex])); Display.HideBySection(Model,ID); end
      else if DisplayGroup.ItemIndex>0 then begin ID:=Integer(PtrInt(DisplayGroup.Items.Objects[DisplayGroup.ItemIndex])); Display.HideByGroup(Model,ID); end;
    end;
    2: begin
      if DisplayKind.ItemIndex>0 then Display.ShowByKind(Model,DisplayKind.Text)
      else if DisplayMaterial.ItemIndex>0 then begin ID:=Integer(PtrInt(DisplayMaterial.Items.Objects[DisplayMaterial.ItemIndex])); Display.ShowByMaterial(Model,ID); end
      else if DisplaySection.ItemIndex>0 then begin ID:=Integer(PtrInt(DisplaySection.Items.Objects[DisplaySection.ItemIndex])); Display.ShowBySection(Model,ID); end
      else if DisplayGroup.ItemIndex>0 then begin ID:=Integer(PtrInt(DisplayGroup.Items.Objects[DisplayGroup.ItemIndex])); Display.ShowByGroup(Model,ID); end
      else Display.ShowAll;
    end;
    3: begin
      if DisplayKind.ItemIndex>0 then Display.IsolateByKind(Model,DisplayKind.Text)
      else if DisplayMaterial.ItemIndex>0 then begin ID:=Integer(PtrInt(DisplayMaterial.Items.Objects[DisplayMaterial.ItemIndex])); Display.IsolateByMaterial(Model,ID); end
      else if DisplaySection.ItemIndex>0 then begin ID:=Integer(PtrInt(DisplaySection.Items.Objects[DisplaySection.ItemIndex])); Display.IsolateBySection(Model,ID); end
      else if DisplayGroup.ItemIndex>0 then begin ID:=Integer(PtrInt(DisplayGroup.Items.Objects[DisplayGroup.ItemIndex])); Display.IsolateByGroup(Model,ID); end
      else begin Display.RestoreIsolation; end;
    end;
    4: Display.RestoreIsolation;
    5: Display.ShowAll;
  end;
  if Display.IsolationActive then DisplayInfo.Caption:=Format('Isolation active | %d hidden elements',[Display.HiddenElementCount])
  else if Display.HiddenElementCount>0 then DisplayInfo.Caption:=Format('%d elements hidden',[Display.HiddenElementCount])
  else DisplayInfo.Caption:='All geometry visible';
  CanvasBox.Invalidate;
end;

procedure TMainForm.ClipChanged(Sender:TObject);
begin
  if GLView=nil then Exit;
  GLView.SetClipEnabled(ClipEnable.Checked);
  if ClipAxis.ItemIndex=1 then GLView.SetClipAxis(caY) else if ClipAxis.ItemIndex=2 then GLView.SetClipAxis(caZ) else GLView.SetClipAxis(caX);
  GLView.SetClipFraction(ClipSlider.Position/100); GLView.SetShowClipPlane(ClipPlane.Checked); GLView.SetClipReverse(ClipReverse.Checked); CanvasBox.Invalidate;
end;

procedure TMainForm.MouseDownView(Sender:TObject; Button:TMouseButton; Shift:TShiftState; X,Y:Integer);
var ID,ID2,NewE,N:Integer; P:TVec3;
begin
  LastViewX:=X; LastViewY:=Y;
  if (Button=mbLeft) and (InteractiveMode=iemMoveNode) then begin
    ID:=View.PickNode(X,Y,CanvasBox.Width,CanvasBox.Height);
    if ID<=0 then begin Status.SimpleText:='Move node: click a node.'; Exit; end;
    PendingMoveNodeID:=ID;
    if InteractivePoint(X,Y,P) then begin MovePreviewPoint:=P; MovePreviewActive:=True; GLView.SetEditPreviewNode(True,ID,P); end;
    Status.SimpleText:=Format('MOVE NODE %d: drag to new position; release to commit.',[ID]);
    CanvasBox.Invalidate;
    Exit;
  end;
  if (Button=mbLeft) and (InteractiveMode=iemCreateNode) then begin
    if PickOrCreateInteractiveNode(X,Y,ID) then begin
      ModelEdited(False);
      View.Selection.Clear; View.Selection.SelectNode(ID,False);
      SetInteractiveMode(iemCreateNode);
    end;
    Exit;
  end;
  if (Button=mbLeft) and (InteractiveMode=iemCreateBeam) then begin
    if not PickOrCreateInteractiveNode(X,Y,ID) then Exit;
    if PendingBeamNodeID<0 then begin
      PendingBeamNodeID:=ID;
      N:=Model.FindNode(ID);
      if N>=0 then begin
        BeamPreviewStart:=Model.Nodes[N].Position;
        BeamPreviewEnd:=BeamPreviewStart;
        BeamPreviewActive:=True;
        GLView.SetEditPreviewBeam(True,BeamPreviewStart,BeamPreviewEnd);
      end;
      View.Selection.Clear; View.Selection.SelectNode(ID,False);
      UpdateEditModeUI; CanvasBox.Invalidate;
    end else begin
      ID2:=ID;
      if ID2=PendingBeamNodeID then begin Status.SimpleText:='Second beam point must differ from the first.'; Exit; end;
      if (EditMaterialCombo.ItemIndex<0) or (EditSectionCombo.ItemIndex<0) then begin Status.SimpleText:='Choose a material and section before creating a beam.'; Exit; end;
      NewE:=Editor.CreateElement('BEAM3D',
        PendingBeamNodeID,
        ID2,
        Integer(PtrInt(EditMaterialCombo.Items.Objects[EditMaterialCombo.ItemIndex])),
        Integer(PtrInt(EditSectionCombo.Items.Objects[EditSectionCombo.ItemIndex])),
        Integer(PtrInt(EditGroupCombo.Items.Objects[EditGroupCombo.ItemIndex])));
      if NewE<0 then begin Status.SimpleText:='Could not create beam.'; Exit; end;
      Log.Lines.Add(Format('Interactive BEAM3D %d: nodes %d -> %d.',[NewE,PendingBeamNodeID,ID2]));
      PendingBeamNodeID:=ID2;
      N:=Model.FindNode(ID2);
      if N>=0 then begin
        BeamPreviewStart:=Model.Nodes[N].Position;
        BeamPreviewEnd:=BeamPreviewStart;
        BeamPreviewActive:=True;
        GLView.SetEditPreviewBeam(True,BeamPreviewStart,BeamPreviewEnd);
      end;
      ModelEdited(False);
      View.Selection.Clear; View.Selection.SelectElement(NewE,False);
      SetInteractiveMode(iemCreateBeam);
    end;
    Exit;
  end;
  if Button=mbLeft then begin
    SelectionBoxActive:=True; SelectionBoxX1:=X; SelectionBoxY1:=Y;
    GLView.SetSelectionBox(True,X,Y,X,Y);
    CanvasBox.Invalidate;
    Exit;
  end;
  View.MouseDown(Button,X,Y);
end;

procedure TMainForm.MouseMoveView(Sender:TObject; Shift:TShiftState; X,Y:Integer);
var P:TVec3; N:Integer;
begin
  View.MouseMove(X,Y,Shift);
  if (InteractiveMode=iemMoveNode) and MovePreviewActive and (PendingMoveNodeID>0) then begin
    if InteractivePoint(X,Y,P) then begin
      MovePreviewPoint:=P;
      GLView.SetEditPreviewNode(True,PendingMoveNodeID,P);
      Status.SimpleText:=Format('MOVE NODE %d: preview (%.6g, %.6g, %.6g)',[PendingMoveNodeID,P.X,P.Y,P.Z]);
    end;
  end else if (InteractiveMode=iemCreateBeam) and BeamPreviewActive and (PendingBeamNodeID>0) then begin
    if InteractivePoint(X,Y,P) then begin
      N:=View.PickNode(X,Y,CanvasBox.Width,CanvasBox.Height);
      if N>0 then begin
        N:=Model.FindNode(N);
        if N>=0 then P:=Model.Nodes[N].Position;
      end;
      BeamPreviewEnd:=P;
      GLView.SetEditPreviewBeam(True,BeamPreviewStart,BeamPreviewEnd);
      Status.SimpleText:=Format('ADD BEAM: node %d -> (%.6g, %.6g, %.6g)',[PendingBeamNodeID,P.X,P.Y,P.Z]);
    end;
  end else if SelectionBoxActive then begin
    GLView.SetSelectionBox(True,SelectionBoxX1,SelectionBoxY1,X,Y);
  end else
    View.UpdateHover(X,Y,CanvasBox.Width,CanvasBox.Height);
  CanvasBox.Invalidate;
end;
procedure TMainForm.MouseUpView(Sender:TObject; Button:TMouseButton; Shift:TShiftState; X,Y:Integer);
var Crossing,Additive:Boolean;
begin
  if (Button=mbLeft) and SelectionBoxActive then begin
    SelectionBoxActive:=False;
    GLView.SetSelectionBox(False,0,0,0,0);
    if (Abs(X-SelectionBoxX1)>=4) or (Abs(Y-SelectionBoxY1)>=4) then begin
      Crossing:=X<SelectionBoxX1; Additive:=ssCtrl in Shift;
      View.SelectBox(SelectionBoxX1,SelectionBoxY1,X,Y,CanvasBox.Width,CanvasBox.Height,Crossing,Additive);
      UpdateSelectionInspector;
    end else begin
      View.TogglePicked(X,Y,CanvasBox.Width,CanvasBox.Height,ssCtrl in Shift);
      UpdateSelectionInspector;
    end;
    CanvasBox.Invalidate;
  end;
  if (Button=mbLeft) and (InteractiveMode=iemMoveNode) and MovePreviewActive and (PendingMoveNodeID>0) then begin
    if Editor.MoveNode(PendingMoveNodeID,MovePreviewPoint) then begin
      Log.Lines.Add(Format('Moved node %d to (%.6g, %.6g, %.6g).',[PendingMoveNodeID,MovePreviewPoint.X,MovePreviewPoint.Y,MovePreviewPoint.Z]));
      GLView.SetEditPreviewNode(False,0,Vec3(0,0,0));
      PendingMoveNodeID:=-1; MovePreviewActive:=False;
      ModelEdited(False);
      SetInteractiveMode(iemMoveNode);
    end;
  end;
  View.MouseUp;
end;
procedure TMainForm.ViewDblClick(Sender:TObject);begin View.FocusSelection; CanvasBox.Invalidate;end;
procedure TMainForm.SelectionModeChange(Sender:TObject);
begin
  if SelectionModeCombo.ItemIndex=1 then View.SelectMode(smNode) else View.SelectMode(smElement);
  View.ClearHover;
  CanvasBox.Invalidate;
end;
procedure TMainForm.SelectionClearClick(Sender:TObject);
begin View.ClearSelection; UpdateSelectionInspector; CanvasBox.Invalidate; end;
procedure TMainForm.SelectionIsolateClick(Sender:TObject);
var I:Integer; A:array of Integer;
begin
  if View.Selection.ElementCount=0 then Exit;
  SetLength(A,View.Selection.ElementCount);
  for I:=0 to View.Selection.ElementCount-1 do A[I]:=View.Selection.ElementID(I);
  Display.IsolateSelected(Model,A);
  DisplayInfo.Caption:=Format('Selection isolated | %d elements',[View.Selection.ElementCount]);
  CanvasBox.Invalidate;
end;
procedure TMainForm.MouseWheelView(Sender:TObject; Shift:TShiftState; WheelDelta:Integer; MousePos:TPoint; var Handled:Boolean);begin View.Wheel(WheelDelta);CanvasBox.Invalidate;Handled:=True;end;

procedure TMainForm.UpdateSelectionInspector;
var I,J:Integer; ID,N:Integer; F:TResultField; V:Double;
begin
  if View.Selection.NodeCount>0 then begin
    ID:=View.Selection.NodeID(0); N:=Model.FindNode(ID); Inspector.Lines.Add(''); Inspector.Lines.Add('SELECTED NODE '+IntToStr(ID)); Inspector.Lines.Add('--------------------------------');
    if N>=0 then begin
      Inspector.Lines.Add(Format('Position: %.6g, %.6g, %.6g',[Model.Nodes[N].Position.X,Model.Nodes[N].Position.Y,Model.Nodes[N].Position.Z]));
      Inspector.Lines.Add(Format('Restraints: %d %d %d %d %d %d',[Ord(Model.Nodes[N].Restraint[0]),Ord(Model.Nodes[N].Restraint[1]),Ord(Model.Nodes[N].Restraint[2]),Ord(Model.Nodes[N].Restraint[3]),Ord(Model.Nodes[N].Restraint[4]),Ord(Model.Nodes[N].Restraint[5])]));
    end;
    if ResultFields<>nil then for I:=0 to ResultFields.Count-1 do begin F:=ResultFields.Item(I); if F.Location=rlNode then begin V:=F.ValueForEntity(ID); Inspector.Lines.Add(Format('%-22s % .8g %s',[F.Name,V,F.Units])); end; end;
  end else if View.Selection.ElementCount>0 then begin
    ID:=View.Selection.ElementID(0); Inspector.Lines.Add(''); Inspector.Lines.Add('SELECTED ELEMENT '+IntToStr(ID)); Inspector.Lines.Add('--------------------------------');
    N:= -1; for I:=0 to High(Model.Elements) do if Model.Elements[I].ID=ID then begin N:=I; Break; end;
    if N>=0 then begin
      Inspector.Lines.Add('Kind: '+Model.Elements[N].Kind);
      if Length(Model.Elements[N].NodeIDs)>=2 then Inspector.Lines.Add(Format('Nodes: %d -> %d',[Model.Elements[N].NodeIDs[0],Model.Elements[N].NodeIDs[1]]));
      I:=Model.FindMaterial(Model.Elements[N].MaterialID); if I>=0 then Inspector.Lines.Add('Material: '+Model.Materials[I].Name);
      I:=Model.FindSection(Model.Elements[N].SectionID); if I>=0 then Inspector.Lines.Add('Section: '+Model.Sections[I].Name);
      I:=Model.FindGroup(Model.Elements[N].GroupID); if I>=0 then Inspector.Lines.Add('Group: '+Model.Groups[I].Name);
    end;
    if ResultFields<>nil then for I:=0 to ResultFields.Count-1 do begin F:=ResultFields.Item(I); if F.Location=rlElement then begin V:=F.ValueForEntity(ID); Inspector.Lines.Add(Format('%-22s % .8g %s',[F.Name,V,F.Units])); end; end;
  end;
end;

procedure TMainForm.ClearResults;
begin
  if Assigned(View) then
    View.SetResultFields(nil);

  if Assigned(ResultQuantity) then
    ResultQuantity.Items.Clear;

  if Assigned(ResultInfo) then
    ResultInfo.Caption := 'No results loaded';

  FreeAndNil(ResultFields);
  FreeAndNil(LastResult);

  if Assigned(CanvasBox) then
    CanvasBox.Invalidate;
end;

procedure TMainForm.LoadResultFile(const FileName:string);
var I:Integer; F:TResultField;
begin
  ClearResults;
  LastResult:=TFEMResultDocument.Create; LastResult.LoadFromFile(FileName);
  if (LastResult.ModelFingerprint<>'') and (not SameText(LastResult.ModelFingerprint,ModelFingerprint(Model))) then Log.Lines.Add('WARNING: result model fingerprint does not match the current model. Results may be stale.');
  if not SameText(LastResult.Status,'OK') then begin ResultInfo.Caption:='Result status: '+LastResult.Status; Exit; end;
  ResultFields:=BuildResultFields(Model,LastResult); View.SetResultFields(ResultFields);
  ResultQuantity.Items.Clear;
  for I:=0 to ResultFields.Count-1 do begin F:=ResultFields.Item(I); ResultQuantity.Items.AddObject(F.Name+' ['+F.Units+']',F); end;
  if ResultQuantity.Items.Count>0 then begin ResultQuantity.ItemIndex:=0; for I:=0 to ResultFields.Count-1 do if SameText(ResultFields.Item(I).ID,'UMAG') then begin ResultQuantity.ItemIndex:=I; Break; end; View.SetActiveField(TResultField(ResultQuantity.Items.Objects[ResultQuantity.ItemIndex]).ID); end;
  ResultInfo.Caption:=Format('Case %d: %s',[LastResult.AnalysisCaseID,LastResult.AnalysisName]);
  Inspector.Lines.Add(''); Inspector.Lines.Add('RESULT VIEW'); Inspector.Lines.Add('--------------------------------'); Inspector.Lines.Add(LastResult.Summary);
  Inspector.Lines.Add(''); Inspector.Lines.Add('RESULT FIELDS');
  for I:=0 to ResultFields.Count-1 do begin F:=ResultFields.Item(I); Inspector.Lines.Add(Format('  %s  (%s, %s)',[F.ID,F.Name,F.Units])); end;
  Inspector.Lines.Add(''); Inspector.Lines.Add('PROVENANCE'); Inspector.Lines.Add('  Model fingerprint: '+LastResult.ModelFingerprint); Inspector.Lines.Add('  Analysis fingerprint: '+LastResult.AnalysisFingerprint);
  Inspector.Lines.Add(''); Inspector.Lines.Add('AUDIT TRAIL'); Inspector.Lines.AddStrings(LastResult.AuditTrail);
  CanvasBox.Invalidate;
end;


procedure TMainForm.ShowResultTable(ALocation:TResultLocation);
var D:TForm; G:TStringGrid; I,J,RowCount:Integer; F:TResultField; ID:Integer; V:Double; TitleText:string;
begin
  if ResultFields=nil then begin ShowMessage('Load a solver result first.'); Exit; end;
  D:=TForm.CreateNew(Self); try
    if ALocation=rlNode then TitleText:='Node result table' else TitleText:='Element result table';
    D.Caption:='FEM3D â€” '+TitleText; D.Width:=760; D.Height:=560; D.Position:=poScreenCenter;
    G:=TStringGrid.Create(D); G.Parent:=D; G.Align:=alClient; G.FixedRows:=1; G.ColCount:=2; G.Cells[0,0]:='ID'; G.Cells[1,0]:='Result';
    if ResultQuantity.ItemIndex>=0 then begin
      F:=TResultField(ResultQuantity.Items.Objects[ResultQuantity.ItemIndex]); G.Cells[1,0]:=F.Name+' ['+F.Units+']';
      if ALocation=rlNode then RowCount:=Length(Model.Nodes) else RowCount:=Length(Model.Elements);
      G.RowCount:=Max(2,RowCount+1);
      for I:=0 to RowCount-1 do begin
        if ALocation=rlNode then ID:=Model.Nodes[I].ID else ID:=Model.Elements[I].ID;
        G.Cells[0,I+1]:=IntToStr(ID); V:=F.ValueForEntity(ID); G.Cells[1,I+1]:=Format('%.12g',[V]);
      end;
    end else G.RowCount:=2;
    D.ShowModal;
  finally D.Free end;
end;

procedure TMainForm.ShowResultStatistics;
var D:TForm; M:TMemo; I:Integer; F:TResultField; MaxF,MinF:Double;
begin
  if ResultFields=nil then begin ShowMessage('Load a solver result first.'); Exit; end;
  D:=TForm.CreateNew(Self); try
    D.Caption:='FEM3D â€” Result statistics'; D.Width:=620; D.Height:=520; D.Position:=poScreenCenter;
    M:=TMemo.Create(D); M.Parent:=D; M.Align:=alClient; M.ReadOnly:=True; M.ScrollBars:=ssAutoBoth;
    M.Lines.Add('RESULT FIELD STATISTICS'); M.Lines.Add('================================');
    for I:=0 to ResultFields.Count-1 do begin
      F:=ResultFields.Item(I); MinF:=F.MinValue; MaxF:=F.MaxValue;
      M.Lines.Add(Format('%-24s  min=% .8g  max=% .8g  absmax=% .8g %s',[F.Name,MinF,MaxF,F.AbsMaxValue,F.Units]));
    end;
    M.Lines.Add(''); M.Lines.Add('Result provenance:');
    M.Lines.Add('  Case: '+IntToStr(LastResult.AnalysisCaseID)+' â€” '+LastResult.AnalysisName);
    M.Lines.Add('  Solver: '+LastResult.Solver);
    M.Lines.Add('  Model fingerprint: '+LastResult.ModelFingerprint);
    M.Lines.Add('  Analysis fingerprint: '+LastResult.AnalysisFingerprint);
    D.ShowModal;
  finally D.Free end;
end;

procedure TMainForm.NodeTableClick(Sender:TObject); begin ShowResultTable(rlNode); end;
procedure TMainForm.ElementTableClick(Sender:TObject); begin ShowResultTable(rlElement); end;
procedure TMainForm.ResultStatsClick(Sender:TObject); begin ShowResultStatistics; end;

procedure TMainForm.ResultQuantityChange(Sender:TObject);
var F:TResultField;
begin if ResultQuantity.ItemIndex<0 then Exit; F:=TResultField(ResultQuantity.Items.Objects[ResultQuantity.ItemIndex]); View.SetActiveField(F.ID); CanvasBox.Invalidate; ResultInfo.Caption:=Format('%s [%s]  min=%g  max=%g  absmax=%g',[F.Name,F.Units,F.MinValue,F.MaxValue,F.AbsMaxValue]); end;

procedure TMainForm.DeformationScaleChange(Sender:TObject);
var V:Double;
begin if SameText(Trim(DeformationScale.Text),'auto') then begin View.AutoDeformationScale; end else if TryStrToFloat(Trim(DeformationScale.Text),V) then View.SetDeformationScale(V); CanvasBox.Invalidate; end;

procedure TMainForm.ResultVisibilityChange(Sender:TObject);
begin View.SetShowDeformed(ShowDeformed.Checked); View.SetShowUndeformed(ShowUndeformed.Checked); CanvasBox.Invalidate; end;

procedure TMainForm.ResultExpressionClick(Sender:TObject);
var NameText,Expr,LocText,UnitsText,Err:string; Loc:Integer; F:TResultField; Eval:TResultExpressionEvaluator; I:Integer; V:Double;
begin
  if ResultFields=nil then begin ShowMessage('Load a solver result before creating a result expression.'); Exit; end;
  NameText:='User expression'; Expr:='UMAG'; LocText:='Node'; UnitsText:='derived';
  if not InputQuery('Result expression','Display name:',NameText) then Exit;
  if not InputQuery('Result expression','Equation (for example: ABS(U2) or SQRT(U0*U0+U1*U1)):',Expr) then Exit;
  if not InputQuery('Result expression','Location: Node or Element',LocText) then Exit;
  if not InputQuery('Result expression','Units:',UnitsText) then Exit;
  if SameText(Trim(LocText),'Element') then Loc:=Ord(rlElement) else Loc:=Ord(rlNode);
  F:=TResultField.Create('USER_'+IntToStr(ResultFields.Count+1),NameText,UnitsText,TResultLocation(Loc));
  if Loc=Ord(rlNode) then begin SetLength(F.EntityIDs,Length(Model.Nodes));SetLength(F.Values,Length(Model.Nodes));for I:=0 to High(Model.Nodes) do F.EntityIDs[I]:=Model.Nodes[I].ID;end
  else begin SetLength(F.EntityIDs,Length(Model.Elements));SetLength(F.Values,Length(Model.Elements));for I:=0 to High(Model.Elements) do F.EntityIDs[I]:=Model.Elements[I].ID;end;
  Eval:=TResultExpressionEvaluator.Create(ResultFields); try
    if Loc=Ord(rlNode) then for I:=0 to High(F.EntityIDs) do if not Eval.Evaluate(Expr,rlNode,F.EntityIDs[I],V,Err) then begin ShowMessage(Err);F.Free;Exit;end else F.Values[I]:=V
    else for I:=0 to High(F.EntityIDs) do if not Eval.Evaluate(Expr,rlElement,F.EntityIDs[I],V,Err) then begin ShowMessage(Err);F.Free;Exit;end else F.Values[I]:=V;
  finally Eval.Free end;
  ResultFields.Add(F); ResultQuantity.Items.AddObject(F.Name+' ['+F.Units+']',F);ResultQuantity.ItemIndex:=ResultQuantity.Items.Count-1;View.SetActiveField(F.ID);CanvasBox.Invalidate;
  Log.Lines.Add('Added derived result field: '+NameText+' = '+Expr);
end;

procedure TMainForm.AutoScaleClick(Sender:TObject);
begin View.AutoDeformationScale; DeformationScale.Text:='auto'; Log.Lines.Add('Deformation scale set automatically.'); CanvasBox.Invalidate; end;

procedure TMainForm.AutoRangeClick(Sender:TObject);
begin if ResultQuantity.ItemIndex>=0 then begin View.SetActiveField(TResultField(ResultQuantity.Items.Objects[ResultQuantity.ItemIndex]).ID); ContourMinEdit.Text:='auto'; ContourMaxEdit.Text:='auto'; CanvasBox.Invalidate; end; end;

procedure TMainForm.ContourRangeChange(Sender:TObject);
var A,B:Double;
begin if (LowerCase(Trim(ContourMinEdit.Text))='auto') or (LowerCase(Trim(ContourMaxEdit.Text))='auto') then Exit; if TryStrToFloat(ContourMinEdit.Text,A) and TryStrToFloat(ContourMaxEdit.Text,B) then View.SetContourRange(A,B); CanvasBox.Invalidate; end;

procedure TMainForm.ValidateClick(Sender:TObject);
var Report:TFEMValidationReport;
begin
  Report:=TFEMValidationReport.Create; try
    if Report.Validate(Model) then Log.Lines.Add(Format('VALIDATION: OK (%d warnings)',[Report.WarningCount]))
    else Log.Lines.Add(Format('VALIDATION: FAILED (%d errors, %d warnings)',[Report.ErrorCount,Report.WarningCount]));
    Inspector.Lines.Add(''); Inspector.Lines.Add('MODEL VALIDATION'); Inspector.Lines.Add('--------------------------------'); Inspector.Lines.Add(Report.AsText);
  finally Report.Free end;
end;

procedure TMainForm.SolveClick(Sender:TObject);
var InputFile,SolverFile,OutFile:string; A:TAnalysisCase; PR:TSolverProcessResult; Params:array of string;
begin
  A:=Model.AnalysisCases.Find(ActiveAnalysisID);
  if A=nil then begin Log.Lines.Add('No active analysis case. Use Solve -> Analysis Manager...'); Exit; end;
  if A.AnalysisType<>atLinearStatic then begin Log.Lines.Add('The selected analysis is '+A.TypeName+'. Use its dedicated Solve menu item.'); Exit; end;
  InputFile:=IncludeTrailingPathDelimiter(GetTempDir)+'fem3d_gui_run.fem3d'; OutFile:=ChangeFileExt(InputFile,'.fem3dres');
  SolverFile:=ExtractFilePath(Application.ExeName)+'FEM3D_LinStatic.exe';
  if not FileExists(SolverFile) then begin Log.Lines.Add('Solver executable not found: '+SolverFile); Log.Lines.Add('Build FEM3D_LinStatic.exe and place it beside FEM3D.exe.'); Exit; end;
  try
    TFEMNativeIO.SaveModel(Model,InputFile); SetLength(Params,4); Params[0]:='--solve'; Params[1]:='--case'; Params[2]:=IntToStr(A.ID); Params[3]:=InputFile;
    if not TSolverProcessRunner.Run(SolverFile,Params,PR) then begin Log.Lines.Add(PR.ErrorText); Exit; end;
    if PR.OutputText<>'' then Log.Lines.Add(Trim(PR.OutputText)); if PR.ErrorText<>'' then Log.Lines.Add('Solver stderr: '+Trim(PR.ErrorText));
    if PR.ExitCode<>0 then begin Log.Lines.Add(Format('Solver process failed with exit code %d.',[PR.ExitCode])); Exit; end;
    if FileExists(OutFile) then begin LoadResultFile(OutFile); end;
    A.ResultID:=ExtractFileName(OutFile); Log.Lines.Add('Solver process completed successfully. Results: '+OutFile);
  except on E:Exception do Log.Lines.Add('Solver launch failed: '+E.Message); end;
end;

procedure TMainForm.LinearStaticClick(Sender:TObject);
var A:TAnalysisCase; I:Integer;
begin
  A:=nil;
  for I:=0 to Model.AnalysisCases.Count-1 do if Model.AnalysisCases.Item(I).AnalysisType=atLinearStatic then begin A:=Model.AnalysisCases.Item(I); Break; end;
  if A=nil then A:=Model.AnalysisCases.Add(atLinearStatic,'Linear Static '+IntToStr(Model.AnalysisCases.NextID));
  ActiveAnalysisID:=A.ID;
  if ConfigureAnalysisCase(A) then begin Log.Lines.Add(Format('Saved Linear Static case %d (%s).',[A.ID,A.Name])); Refresh; SolveClick(nil); end;
end;

procedure TMainForm.LinearBucklingClick(Sender:TObject);
var A:TAnalysisCase; I:Integer;
begin
  A:=nil; for I:=0 to Model.AnalysisCases.Count-1 do if Model.AnalysisCases.Item(I).AnalysisType=atLinearBuckling then begin A:=Model.AnalysisCases.Item(I); Break; end;
  if A=nil then A:=Model.AnalysisCases.Add(atLinearBuckling,'Linear Buckling '+IntToStr(Model.AnalysisCases.NextID));
  ActiveAnalysisID:=A.ID;
  if ConfigureAnalysisCase(A) then begin Log.Lines.Add(Format('Saved Linear Buckling case %d (%s).',[A.ID,A.Name])); Refresh; Log.Lines.Add('Buckling solver is present as an external-process boundary but remains gated pending geometric-stiffness verification.'); end;
end;

procedure TMainForm.NonlinearStaticClick(Sender:TObject);
var A:TAnalysisCase; I:Integer;
begin
  A:=nil; for I:=0 to Model.AnalysisCases.Count-1 do if Model.AnalysisCases.Item(I).AnalysisType=atNonlinearStatic then begin A:=Model.AnalysisCases.Item(I); Break; end;
  if A=nil then A:=Model.AnalysisCases.Add(atNonlinearStatic,'Nonlinear Static '+IntToStr(Model.AnalysisCases.NextID));
  ActiveAnalysisID:=A.ID;
  if ConfigureAnalysisCase(A) then begin Log.Lines.Add(Format('Saved Nonlinear Static case %d (%s).',[A.ID,A.Name])); Refresh; Log.Lines.Add('Nonlinear solver is present as an external-process boundary but remains gated pending nonlinear element/tangent verification.'); end;
end;

procedure TMainForm.ViewResultsClick(Sender:TObject);
var F:string;
begin
  F:=ChangeFileExt(IncludeTrailingPathDelimiter(GetTempDir)+'fem3d_gui_run.fem3d','.fem3dres');
  if not FileExists(F) then begin Log.Lines.Add('No result file found: '+F); Exit; end;
  LoadResultFile(F);
end;

procedure TMainForm.AnalysisManagerClick(Sender:TObject);
var ID:Integer;
begin
  if RunAnalysisManager(Model,ID) then begin if ID<>0 then ActiveAnalysisID:=ID; Refresh; Log.Lines.Add('Analysis Manager: active case '+IntToStr(ActiveAnalysisID)); end;
end;

procedure TMainForm.UnimplementedAnalysisClick(Sender:TObject);
begin ShowMessage('This analysis type is defined in the FEM3D architecture but its numerical solver is not implemented yet.'); end;

procedure TMainForm.NewClick(Sender:TObject);begin ClearResults;Editor.ClearHistory;Model.Clear;Display.ShowAll;View.Selection.Clear;ActiveAnalysisID:=0;Refresh;CanvasBox.Invalidate;end;

procedure TMainForm.OpenClick(Sender:TObject);
begin
  OpenDlg.Filter:='FEM3D model|*.fem3d|All files|*.*';
  if OpenDlg.Execute then begin try ClearResults; Display.ShowAll; TFEMNativeIO.LoadModel(Model,OpenDlg.FileName); if Model.AnalysisCases.Count>0 then ActiveAnalysisID:=Model.AnalysisCases.Item(0).ID else ActiveAnalysisID:=0; Log.Lines.Add('Opened '+OpenDlg.FileName);Refresh;except on E:Exception do Log.Lines.Add('Open failed: '+E.Message);end;end;
end;

procedure TMainForm.SaveClick(Sender:TObject);
begin
  SaveDlg.Filter:='FEM3D model|*.fem3d|All files|*.*';
  if SaveDlg.Execute then begin try TFEMNativeIO.SaveModel(Model,SaveDlg.FileName);Log.Lines.Add('Saved '+SaveDlg.FileName);except on E:Exception do Log.Lines.Add('Save failed: '+E.Message);end;end;
end;

procedure TMainForm.DXFClick(Sender:TObject);
begin
  Display.ShowAll;
  OpenDlg.Filter:='DXF ASCII|*.dxf|All files|*.*';
  if OpenDlg.Execute then begin try TGeometryImporter.ImportDXF(Model,OpenDlg.FileName);Log.Lines.Add('Imported DXF geometry.');Refresh;except on E:Exception do Log.Lines.Add('DXF import failed: '+E.Message);end;end;
end;

procedure TMainForm.IGESClick(Sender:TObject);
begin
  Display.ShowAll;
  OpenDlg.Filter:='IGES files|*.igs;*.iges|All files|*.*';
  if OpenDlg.Execute then begin
    try
      TGeometryImporter.ImportIGES(Model,OpenDlg.FileName);
      Log.Lines.Add('Imported IGES wireframe: '+ExtractFileName(OpenDlg.FileName));
      Refresh; View.FitAll;
    except on E:Exception do Log.Lines.Add('IGES import failed: '+E.Message); end;
  end;
end;

procedure TMainForm.ViewControlAction(Sender:TObject);
var T:Integer;
begin
  T:=TButton(Sender).Tag;
  case T of
    1: View.StandardView(0);
    2: View.StandardView(1);
    3: View.StandardView(3);
    4: View.StandardView(2);
    5: View.StandardView(4);
    6: View.StandardView(5);
    7: View.StandardView(6);
    8: View.FitAll;
    9,10: View.FitSelection;
    11: View.FocusSelection;
  end;
  CanvasBox.Invalidate;
end;


procedure TMainForm.CameraSettingChange(Sender:TObject);
var V:Double;
begin
  if ProjectionCombo.ItemIndex=1 then View.Camera.SetProjection(vpOrthographic) else View.Camera.SetProjection(vpPerspective);
  if TryStrToFloat(FOVEdit.Text,V) then View.Camera.SetFOV(V);
  if TryStrToFloat(NearClipEdit.Text,V) then View.Camera.SetNearClip(V);
  if GLView<>nil then GLView.SetShowSolidMembers(ShowSolidMembers.Checked);
  CanvasBox.Invalidate;
end;

procedure TMainForm.FitClick(Sender:TObject);begin View.FitAll;CanvasBox.Invalidate;end;

procedure TMainForm.VerifyClick(Sender:TObject);
var V:TVerificationResult;
begin
  if TFEMVerification.CantileverTipDisplacement(V) then
    Log.Lines.Add('VERIFY PASS: '+V.MessageText)
  else
    Log.Lines.Add('VERIFY FAIL: '+V.MessageText);
end;

procedure TMainForm.ModelEdited(AResetView:Boolean);
begin
  ClearResults; View.Selection.Clear; View.ClearHover; Refresh;
  if AResetView then View.FitAll;
  CanvasBox.Invalidate;
  Status.SimpleText:=Format('Model changed. Undo=%s  Redo=%s',[BoolToStr(Editor.CanUndo,True),BoolToStr(Editor.CanRedo,True)]);
end;

procedure TMainForm.UpdateEditModeUI;
begin
  case InteractiveMode of
    iemCreateNode: EditModeLabel.Caption:='ADD NODE: click in viewport';
    iemCreateBeam:
      if PendingBeamNodeID<0 then EditModeLabel.Caption:='ADD BEAM: click first node/point'
      else EditModeLabel.Caption:=Format('ADD BEAM: first node %d set; click second point',[PendingBeamNodeID]);
    iemMoveNode: EditModeLabel.Caption:='MOVE NODE: select a node, then drag it in the viewport';
    else EditModeLabel.Caption:='Click Add node or Add beam, then draw in the viewport.';
  end;
  Status.SimpleText:=EditModeLabel.Caption;
end;

procedure TMainForm.SetInteractiveMode(Mode:TInteractiveEditMode);
begin
  InteractiveMode:=Mode;
  if Mode<>iemCreateBeam then begin
    PendingBeamNodeID:=-1; BeamPreviewActive:=False;
    if GLView<>nil then GLView.SetEditPreviewBeam(False,Vec3(0,0,0),Vec3(0,0,0));
  end;
  if Mode<>iemMoveNode then begin PendingMoveNodeID:=-1; MovePreviewActive:=False; if GLView<>nil then GLView.SetEditPreviewNode(False,0,Vec3(0,0,0)); end;
  View.ClearHover;
  UpdateEditModeUI;
  CanvasBox.Invalidate;
end;

function TMainForm.SnapPointToGrid(const P:TVec3):TVec3;
var S,Offset:Double; Plane:Integer;
begin
  Result:=P;
  if not EditSnapGrid.Checked then Exit;
  if (not TryStrToFloat(EditGridStep.Text,S)) or (S<=0) then Exit;
  Plane:=EditPlaneCombo.ItemIndex;
  if not TryStrToFloat(EditPlaneOffset.Text,Offset) then Offset:=0;
  case Plane of
    0: begin { XY: Z is the construction-plane offset. }
      Result.X:=Round(Result.X/S)*S; Result.Y:=Round(Result.Y/S)*S; Result.Z:=Offset;
    end;
    1: begin { XZ: Y is the construction-plane offset. }
      Result.X:=Round(Result.X/S)*S; Result.Y:=Offset; Result.Z:=Round(Result.Z/S)*S;
    end;
    else begin { YZ: X is the construction-plane offset. }
      Result.X:=Offset; Result.Y:=Round(Result.Y/S)*S; Result.Z:=Round(Result.Z/S)*S;
    end;
  end;
end;

function TMainForm.InteractivePoint(X,Y:Integer; out P:TVec3):Boolean;
var Plane:Integer; Offset:Double;
begin
  Result:=False; P:=Vec3(0,0,0);
  Plane:=EditPlaneCombo.ItemIndex;
  if not TryStrToFloat(EditPlaneOffset.Text,Offset) then begin
    Status.SimpleText:='Invalid drawing-plane offset.'; Exit;
  end;
  if not View.Camera.ScreenPointOnPlane(X,Y,CanvasBox.Width,CanvasBox.Height,Plane,Offset,P) then begin
    Status.SimpleText:='View ray is parallel to the drawing plane.'; Exit;
  end;
  P:=SnapPointToGrid(P);
  Result:=True;
end;

function TMainForm.PickOrCreateInteractiveNode(X,Y:Integer; out NodeID:Integer):Boolean;
var ID:Integer; P:TVec3;
begin
  Result:=False; NodeID:=-1;
  ID:=View.PickNode(X,Y,CanvasBox.Width,CanvasBox.Height);
  if ID>=0 then begin NodeID:=ID; Result:=True; Exit; end;
  if not InteractivePoint(X,Y,P) then Exit;
  NodeID:=Editor.CreateNode(P);
  Result:=NodeID>=0;
  if Result then Log.Lines.Add(Format('Interactive node %d at (%.6g, %.6g, %.6g).',[NodeID,P.X,P.Y,P.Z]));
end;

procedure TMainForm.EditCancelClick(Sender:TObject);
begin
  SetInteractiveMode(iemNone);
end;

procedure TMainForm.EditCreateNodeClick(Sender:TObject);
begin
  SetInteractiveMode(iemCreateNode);
end;

procedure TMainForm.EditCreateBeamClick(Sender:TObject);
begin
  if Length(Model.Materials)=0 then begin ShowMessage('No material is defined.'); Exit; end;
  if Length(Model.Sections)=0 then begin ShowMessage('No beam section is defined.'); Exit; end;
  SetInteractiveMode(iemCreateBeam);
end;

procedure TMainForm.EditMoveNodeClick(Sender:TObject);
begin
  SetInteractiveMode(iemMoveNode);
end;

procedure TMainForm.EditSubdivideClick(Sender:TObject);
var I,Segments,CN,CE:Integer; S:string;
begin
  if View.Selection.ElementCount<>1 then begin ShowMessage('Select exactly one beam element first.'); Exit; end;
  I:=View.Selection.ElementID(0); S:='4';
  if not InputQuery('Subdivide beam','Number of segments (2..1000):',S) then Exit;
  if (not TryStrToInt(Trim(S),Segments)) or (Segments<2) or (Segments>1000) then begin ShowMessage('Enter an integer from 2 to 1000.'); Exit; end;
  if Editor.SubdivideElement(I,Segments,CN,CE) then begin
    Log.Lines.Add(Format('Subdivided beam %d into %d segments (%d new nodes).',[I,Segments,CN]));
    ModelEdited(False);
  end else ShowMessage('Only two-node BEAM3D elements can currently be subdivided.');
end;

procedure TMainForm.EditMeshBeamClick(Sender:TObject);
var
  I,Segments,CN,CE:Integer;
  S:string;
  Opt:TBeamMeshOptions;
  MeshResult:TBeamMeshResult;
begin
  ShowMessage('Beam meshing temporarily disabled while the compiler issue is investigated.');
  {if View.Selection.ElementCount<>1 then begin ShowMessage('Select exactly one beam element first.'); Exit; end;
  I:=View.Selection.ElementID(0); S:='1.0';
  if not InputQuery('Mesh beam','Maximum element length:',S) then Exit;
  if (not TryStrToFloat(Trim(S),Opt.MaximumElementLength)) or (Opt.MaximumElementLength<=0) then begin ShowMessage('Enter a positive maximum element length.'); Exit; end;

  MeshResult:=TBeamMesher.MeshBeamByMaximumLength(Model,Editor,I,Opt);
  if not MeshResult.Success then
  begin
    ShowMessage('Only straight two-node BEAM3D elements can currently be meshed.');
    Exit;
  end;

  Segments:=MeshResult.Segments;
  CN:=MeshResult.CreatedNodes;
  CE:=MeshResult.CreatedElements;

  if Segments=1 then Log.Lines.Add(Format('Beam %d already satisfies maximum length %.6g.',[I,Opt.MaximumElementLength]))
  else begin Log.Lines.Add(Format('Meshed beam %d into %d equal segments (%d new nodes).',[I,Segments,CN])); ModelEdited(False); end;}
end;

procedure TMainForm.EditSplitClick(Sender:TObject);
var ID,NN,NE:Integer;
begin
  if View.Selection.ElementCount<>1 then begin ShowMessage('Select exactly one beam element first.'); Exit; end;
  ID:=View.Selection.ElementID(0);
  if not Editor.SplitElement(ID,NN,NE) then begin ShowMessage('Only two-node BEAM3D elements can currently be split.'); Exit; end;
  Log.Lines.Add(Format('Split beam %d: new node %d, new element %d.',[ID,NN,NE])); ModelEdited;
end;

procedure TMainForm.EditAssignClick(Sender:TObject);
var IDs:array of Integer; I,M,S,G,N:Integer;
begin
  if View.Selection.ElementCount=0 then begin ShowMessage('Select one or more elements first.'); Exit; end;
  M:=-1; S:=-1; G:=-1;
  if EditMaterialCombo.ItemIndex>=0 then M:=Integer(PtrInt(EditMaterialCombo.Items.Objects[EditMaterialCombo.ItemIndex]));
  if EditSectionCombo.ItemIndex>=0 then S:=Integer(PtrInt(EditSectionCombo.Items.Objects[EditSectionCombo.ItemIndex]));
  if EditGroupCombo.ItemIndex>=0 then G:=Integer(PtrInt(EditGroupCombo.Items.Objects[EditGroupCombo.ItemIndex]));
  N:=View.Selection.ElementCount; SetLength(IDs,N);
  for I:=0 to N-1 do IDs[I]:=View.Selection.ElementID(I);
  if Editor.AssignElementProperties(IDs,M,S,G)>0 then begin
    Log.Lines.Add(Format('Assigned material=%d section=%d group=%d to %d selected element(s).',[M,S,G,N]));
    ModelEdited(False);
  end else ShowMessage('No selected elements were changed.');
end;

procedure TMainForm.EditTranslateClick(Sender:TObject);
var I,N:Integer; SX,SY,SZ:string; DX,DY,DZ:Double; IDs:array of Integer; TranslatedCount:Integer;
begin
  if (View.Selection.NodeCount=0) and (View.Selection.ElementCount=0) then begin
    ShowMessage('Select nodes or elements to translate.'); Exit;
  end;
  SX:='0'; SY:='0'; SZ:='0';
  if not InputQuery('Translate geometry','DX:',SX) then Exit;
  if not InputQuery('Translate geometry','DY:',SY) then Exit;
  if not InputQuery('Translate geometry','DZ:',SZ) then Exit;
  if (not TryStrToFloat(Trim(SX),DX)) or (not TryStrToFloat(Trim(SY),DY)) or
     (not TryStrToFloat(Trim(SZ),DZ)) then begin
    ShowMessage('Enter valid numeric offsets.'); Exit;
  end;
  if View.Selection.NodeCount>0 then begin
    N:=View.Selection.NodeCount; SetLength(IDs,N);
    for I:=0 to N-1 do IDs[I]:=View.Selection.NodeID(I);
    TranslatedCount:=Editor.TranslateNodes(IDs,Vec3(DX,DY,DZ));
  end else begin
    N:=View.Selection.ElementCount; SetLength(IDs,N);
    for I:=0 to N-1 do IDs[I]:=View.Selection.ElementID(I);
    TranslatedCount:=Editor.TranslateElements(IDs,Vec3(DX,DY,DZ));
  end;
  if TranslatedCount>0 then begin
    Log.Lines.Add(Format('Translated %d node(s) by (%.6g, %.6g, %.6g).',[TranslatedCount,DX,DY,DZ]));
    ModelEdited(False);
  end else ShowMessage('No valid geometry was translated.');
end;


procedure TMainForm.EditRotateClick(Sender:TObject);
var IDs:array of Integer; I,Axis:Integer; S,SO,SX,SY,SZ:string; Angle,OX,OY,OZ:Double; Origin:TVec3; Changed_:Integer;
  J:Integer; K:Integer; EI: Integer; N:Integer; Found: Boolean;
begin
  if View.Selection.NodeCount>0 then begin SetLength(IDs,View.Selection.NodeCount); for I:=0 to High(IDs) do IDs[I]:=View.Selection.NodeID(I); end
  else if View.Selection.ElementCount>0 then begin SetLength(IDs,View.Selection.ElementCount); for I:=0 to High(IDs) do IDs[I]:=View.Selection.ElementID(I); end
  else begin ShowMessage('Select nodes or elements to rotate.'); Exit; end;
  S:='90'; if not InputQuery('Rotate geometry','Angle (degrees):',S) then Exit;
  SO:='0'; if not InputQuery('Rotate geometry','Axis (X=0, Y=1, Z=2):',SO) then Exit;
  SX:='0'; SY:='0'; SZ:='0';
  if not InputQuery('Rotate geometry','Origin X:',SX) then Exit;
  if not InputQuery('Rotate geometry','Origin Y:',SY) then Exit;
  if not InputQuery('Rotate geometry','Origin Z:',SZ) then Exit;
  if (not TryStrToFloat(Trim(S),Angle)) or (not TryStrToInt(Trim(SO),Axis)) or
     (not TryStrToFloat(Trim(SX),OX)) or (not TryStrToFloat(Trim(SY),OY)) or (not TryStrToFloat(Trim(SZ),OZ)) or
     (Axis<0) or (Axis>2) then begin ShowMessage('Invalid rotation parameters.'); Exit; end;
  Origin:=Vec3(OX,OY,OZ);
  { Element selections are converted to their unique nodes by the editor. }
  if View.Selection.NodeCount=0 then begin
    { build unique node list from selected elements }
    SetLength(IDs,0);
    for I:=0 to View.Selection.ElementCount-1 do begin
      EI:=View.Selection.ElementID(I);
      for J:=0 to High(Model.Elements) do if Model.Elements[J].ID=EI then begin
        for K:=0 to High(Model.Elements[J].NodeIDs) do begin
          Found:=False;
          for N:=0 to High(IDs) do if IDs[N]=Model.Elements[J].NodeIDs[K] then Found:=True;
          if not Found then begin SetLength(IDs,Length(IDs)+1); IDs[High(IDs)]:=Model.Elements[J].NodeIDs[K]; end;
        end; Break;
      end;
    end;
  end;
  Changed_:=Editor.RotateNodes(IDs,Origin,Axis,Angle);
  if Changed_>0 then begin Log.Lines.Add(Format('Rotated %d node(s) by %.6g degrees about axis %d.',[Changed_,Angle,Axis])); ModelEdited(False); end;
end;

procedure TMainForm.EditMirrorClick(Sender:TObject);
var IDs:array of Integer; I,J,K,N,EI,Axis,NodeID:Integer; Found:Boolean; S,SX,SY,SZ:string; OX,OY,OZ:Double; Origin:TVec3; Changed_:Integer;
begin
  if View.Selection.NodeCount>0 then begin SetLength(IDs,View.Selection.NodeCount); for I:=0 to High(IDs) do IDs[I]:=View.Selection.NodeID(I); end
  else if View.Selection.ElementCount>0 then begin
    SetLength(IDs,0);
    for I:=0 to View.Selection.ElementCount-1 do begin EI:=View.Selection.ElementID(I); for J:=0 to High(Model.Elements) do if Model.Elements[J].ID=EI then begin
      for K:=0 to High(Model.Elements[J].NodeIDs) do begin NodeID:=Model.Elements[J].NodeIDs[K]; Found:=False; for N:=0 to High(IDs) do if IDs[N]=NodeID then Found:=True; if not Found then begin SetLength(IDs,Length(IDs)+1); IDs[High(IDs)]:=NodeID; end; end; Break; end;
    end;
  end else begin ShowMessage('Select nodes or elements to mirror.'); Exit; end;
  S:='0'; if not InputQuery('Mirror geometry','Plane normal axis (X=0, Y=1, Z=2):',S) then Exit;
  SX:='0'; SY:='0'; SZ:='0'; if not InputQuery('Mirror geometry','Plane origin X:',SX) then Exit; if not InputQuery('Mirror geometry','Plane origin Y:',SY) then Exit; if not InputQuery('Mirror geometry','Plane origin Z:',SZ) then Exit;
  if (not TryStrToInt(Trim(S),Axis)) or (not TryStrToFloat(Trim(SX),OX)) or (not TryStrToFloat(Trim(SY),OY)) or (not TryStrToFloat(Trim(SZ),OZ)) or (Axis<0) or (Axis>2) then begin ShowMessage('Invalid mirror parameters.'); Exit; end;
  Origin:=Vec3(OX,OY,OZ); Changed_:=Editor.MirrorNodes(IDs,Origin,Axis);
  if Changed_>0 then begin Log.Lines.Add(Format('Mirrored %d node(s) about axis-%d plane.',[Changed_,Axis])); ModelEdited(False); end;
end;

procedure TMainForm.EditCopyClick(Sender:TObject);
var IDs:array of Integer; I:Integer; SX,SY,SZ:string; DX,DY,DZ:Double; CN,CE:Integer;
begin
  if View.Selection.ElementCount=0 then begin ShowMessage('Select one or more elements to copy.'); Exit; end;
  SetLength(IDs,View.Selection.ElementCount); for I:=0 to High(IDs) do IDs[I]:=View.Selection.ElementID(I);
  SX:='0'; SY:='0'; SZ:='1'; if not InputQuery('Copy geometry','DX:',SX) then Exit; if not InputQuery('Copy geometry','DY:',SY) then Exit; if not InputQuery('Copy geometry','DZ:',SZ) then Exit;
  if (not TryStrToFloat(Trim(SX),DX)) or (not TryStrToFloat(Trim(SY),DY)) or (not TryStrToFloat(Trim(SZ),DZ)) then begin ShowMessage('Enter valid numeric offsets.'); Exit; end;
  if Editor.CopyElements(IDs,Vec3(DX,DY,DZ),CN,CE) then begin Log.Lines.Add(Format('Copied %d element(s), creating %d node(s).',[CE,CN])); ModelEdited(False); end;
end;

procedure TMainForm.EditDeleteClick(Sender:TObject);
var ID,Choice,I,N,Deleted:Integer; IDs:array of Integer;
begin
  if View.Selection.NodeCount=1 then begin
    ID:=View.Selection.NodeID(0); Choice:=MessageDlg(Format('Delete node %d? Connected elements and nodal loads will also be deleted.',[ID]),mtWarning,[mbYes,mbNo],0);
    if Choice=mrYes then if Editor.DeleteNode(ID) then begin Log.Lines.Add(Format('Deleted node %d and its dependent geometry/loads.',[ID])); ModelEdited; end;
  end else if View.Selection.ElementCount>0 then begin
    N:=View.Selection.ElementCount; SetLength(IDs,N);
    for I:=0 to N-1 do IDs[I]:=View.Selection.ElementID(I);
    Choice:=MessageDlg(Format('Delete %d selected element(s)?',[N]),mtWarning,[mbYes,mbNo],0);
    if Choice=mrYes then begin
      Deleted:=Editor.DeleteElements(IDs);
      if Deleted>0 then begin Log.Lines.Add(Format('Deleted %d selected element(s).',[Deleted])); ModelEdited; end;
    end;
  end else ShowMessage('Select a node or one or more elements.');
end;

procedure TMainForm.EditUndoClick(Sender:TObject);
begin
  if Editor.Undo then begin Log.Lines.Add('Undo completed.'); ModelEdited; end else Log.Lines.Add('Nothing to undo.');
end;

procedure TMainForm.EditRedoClick(Sender:TObject);
begin
  if Editor.Redo then begin Log.Lines.Add('Redo: '+Editor.RedoDescription); ModelEdited; end else Log.Lines.Add('Nothing to redo.');
end;

procedure TMainForm.ExitClick(Sender:TObject);begin Close;end;

end.
