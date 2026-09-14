unit MainUnit;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, ComCtrls, Menus,
  StdCtrls, Dialogs, Grids, Math, Process, FEMTypes, FEMModel, FEMElements, FEMMatrix,
  FEMAnalysis, FEMAnalysisCases, FEMIO, FEMView, FEMOpenGLView, FEMVerification, FEMAnalysisUI, FEMSolverProcess, FEMResults, FEMResultFields, FEMValidation, FEMHash, FEMDisplayManager, OpenGLContext;

type
  TMainForm = class(TForm)
  private
    Model:TFEMModel;
    Registry:TElementRegistry;
    View:TFEMViewport;
    Tree:TTreeView;
    CanvasBox:TOpenGLControl;
    GLView:TOpenGLFEMRenderer;
    Display:TDisplayManager;
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
    LastViewX,LastViewY:Integer;
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
    ClipEnable:TCheckBox; ClipAxis:TComboBox; ClipPlane:TCheckBox; ClipSlider:TTrackBar;
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
    procedure FitClick(Sender:TObject);
    procedure VerifyClick(Sender:TObject);
    procedure ExitClick(Sender:TObject);
  public
    constructor Create(AOwner:TComponent); override;
    destructor Destroy; override;
  end;

var MainForm:TMainForm;

implementation

constructor TMainForm.Create(AOwner:TComponent);
begin
  inherited Create(AOwner);

  Caption := 'FEM3D — transparent engineering FEA';
  Width := 1400;
  Height := 850;
  Position := poScreenCenter;

  Model := TFEMModel.Create;
  Registry := TElementRegistry.Create;
  RegisterBuiltInElements(Registry);

  View := TFEMViewport.Create(Model);
  Display := TDisplayManager.Create;

  ActiveAnalysisID := 0;
  LastResult := nil;
  ResultFields := nil;

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
  Item:=TMenuItem.Create(Menu);Item.Caption:='Exit';Item.OnClick:=@ExitClick;FM.Add(Item);
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
  DisplayPanel:=TPanel.Create(Self);DisplayPanel.Parent:=SplitRight;DisplayPanel.Align:=alTop;DisplayPanel.Height:=210;DisplayPanel.BevelOuter:=bvNone;
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
  SymbolPanel:=TPanel.Create(Self);SymbolPanel.Parent:=SplitRight;SymbolPanel.Align:=alTop;SymbolPanel.Height:=105;SymbolPanel.BevelOuter:=bvNone;
  with TLabel.Create(Self) do begin Parent:=SymbolPanel;Left:=8;Top:=7;Caption:='ENGINEERING SYMBOLS';Font.Style:=[fsBold];end;
  ShowLoads:=TCheckBox.Create(Self);ShowLoads.Parent:=SymbolPanel;ShowLoads.Left:=8;ShowLoads.Top:=31;ShowLoads.Caption:='Loads';ShowLoads.Checked:=True;ShowLoads.OnChange:=@CameraSettingChange;
  ShowRestraints:=TCheckBox.Create(Self);ShowRestraints.Parent:=SymbolPanel;ShowRestraints.Left:=95;ShowRestraints.Top:=31;ShowRestraints.Caption:='Restraints';ShowRestraints.Checked:=True;ShowRestraints.OnChange:=@CameraSettingChange;
  ShowLocalAxes:=TCheckBox.Create(Self);ShowLocalAxes.Parent:=SymbolPanel;ShowLocalAxes.Left:=190;ShowLocalAxes.Top:=31;ShowLocalAxes.Caption:='Local axes';ShowLocalAxes.Checked:=False;ShowLocalAxes.OnChange:=@CameraSettingChange;
  ShowCoordinateSystems:=TCheckBox.Create(Self);ShowCoordinateSystems.Parent:=SymbolPanel;ShowCoordinateSystems.Left:=8;ShowCoordinateSystems.Top:=60;ShowCoordinateSystems.Caption:='Coordinate systems';ShowCoordinateSystems.Checked:=True;ShowCoordinateSystems.OnChange:=@CameraSettingChange;
  ViewPanel:=TPanel.Create(Self);ViewPanel.Parent:=SplitRight;ViewPanel.Align:=alTop;ViewPanel.Height:=165;ViewPanel.BevelOuter:=bvNone;
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
  with TLabel.Create(Self) do begin Parent:=ViewPanel;Left:=8;Top:=151;Caption:='Select';end;
  SelectionModeCombo:=TComboBox.Create(Self);SelectionModeCombo.Parent:=ViewPanel;SelectionModeCombo.Left:=55;SelectionModeCombo.Top:=147;SelectionModeCombo.Width:=90;SelectionModeCombo.Style:=csDropDownList;SelectionModeCombo.Items.Add('Element');SelectionModeCombo.Items.Add('Node');SelectionModeCombo.ItemIndex:=0;SelectionModeCombo.OnChange:=@SelectionModeChange;
  SelectionClear:=TButton.Create(Self);SelectionClear.Parent:=ViewPanel;SelectionClear.Left:=150;SelectionClear.Top:=146;SelectionClear.Width:=75;SelectionClear.Caption:='Clear';SelectionClear.OnClick:=@SelectionClearClick;
  SelectionIsolate:=TButton.Create(Self);SelectionIsolate.Parent:=ViewPanel;SelectionIsolate.Left:=230;SelectionIsolate.Top:=146;SelectionIsolate.Width:=95;SelectionIsolate.Caption:='Isolate sel.';SelectionIsolate.OnClick:=@SelectionIsolateClick;
  ViewPanel.Height:=195;
  ResultPanel:=TPanel.Create(Self);ResultPanel.Parent:=SplitRight;ResultPanel.Align:=alTop;ResultPanel.Height:=335;ResultPanel.BevelOuter:=bvNone;
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
  ClipSlider:=TTrackBar.Create(Self);ClipSlider.Parent:=ResultPanel;ClipSlider.Left:=8;ClipSlider.Top:=235;ClipSlider.Width:=307;ClipSlider.Min:=0;ClipSlider.Max:=100;ClipSlider.Position:=50;ClipSlider.Frequency:=10;ClipSlider.OnChange:=@ClipChanged;
  with TLabel.Create(Self) do begin Parent:=ResultPanel;Left:=8;Top:=270;Caption:='Graphics: OpenGL | middle-drag orbit | right-drag pan | wheel zoom';end;
  with TLabel.Create(Self) do begin Parent:=ResultPanel;Left:=8;Top:=290;Caption:='Clipping keeps the positive side of the selected plane.';end;
  Inspector:=TMemo.Create(Self);Inspector.Parent:=SplitRight;Inspector.Align:=alClient;Inspector.ReadOnly:=True;
  Log:=TMemo.Create(Self);Log.Parent:=Self;Log.Align:=alBottom;Log.Height:=150;Log.ReadOnly:=True;
  Status:=TStatusBar.Create(Self);Status.Parent:=Self;Status.Align:=alBottom;
  OpenDlg:=TOpenDialog.Create(Self);SaveDlg:=TSaveDialog.Create(Self);
end;

procedure TMainForm.SeedExample;
var N1,N2,Mat,Sec,LC,Grp:Integer; V:TDofVector;
begin
  Model.Clear;
  Mat:=Model.AddMaterial('Structural steel',200e9,0.3,7850);
  Sec:=Model.AddSection('Demo section',0.01,8e-6,3e-6,1e-6);
  LC:=Model.AddLoadCase('LC1 — tip load');
  Grp:=Model.AddGroup('Demo beam');
  N1:=Model.AddNode(Vec3(0,0,0));N2:=Model.AddNode(Vec3(5,0,0));
  FillChar(Model.Nodes[0].Restraint,SizeOf(TDofMask),1);
  FillChar(V,SizeOf(V),0);V[2]:=-10000;
  Model.AddNodalLoad(N2,LC,V);
  with Model.AnalysisCases.Add(atLinearStatic,'Linear Static — LC1') do begin LoadCaseID:=LC; ActiveAnalysisID:=ID; end;
  Model.AddElement('BEAM3D',[N1,N2],Mat,Sec,0,0,Grp);
end;

procedure TMainForm.Refresh;
var I:Integer; A:TAnalysisCase; S:TAnalysisSettings;
begin
  Tree.Items.Clear;
  DisplayKind.Items.Clear; DisplayKind.Items.Add('— any type —');
  DisplayMaterial.Items.Clear; DisplayMaterial.Items.Add('— any material —');
  DisplaySection.Items.Clear; DisplaySection.Items.Add('— any section —');
  DisplayGroup.Items.Clear; DisplayGroup.Items.Add('— any group —');
  for I:=0 to High(Model.Elements) do if DisplayKind.Items.IndexOf(Model.Elements[I].Kind)<0 then DisplayKind.Items.Add(Model.Elements[I].Kind);
  for I:=0 to High(Model.Materials) do DisplayMaterial.Items.AddObject(Model.Materials[I].Name,TObject(PtrInt(Model.Materials[I].ID)));
  for I:=0 to High(Model.Sections) do DisplaySection.Items.AddObject(Model.Sections[I].Name,TObject(PtrInt(Model.Sections[I].ID)));
  for I:=0 to High(Model.Groups) do DisplayGroup.Items.AddObject(Model.Groups[I].Name,TObject(PtrInt(Model.Groups[I].ID)));
  DisplayKind.ItemIndex:=0; DisplayMaterial.ItemIndex:=0; DisplaySection.ItemIndex:=0; DisplayGroup.ItemIndex:=0;
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
  for I:=0 to Registry.Count-1 do Inspector.Lines.Add('  '+Registry.Item(I).Kind+' — '+Registry.Item(I).Description);
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
  GLView.SetClipFraction(ClipSlider.Position/100); GLView.SetShowClipPlane(ClipPlane.Checked); CanvasBox.Invalidate;
end;

procedure TMainForm.MouseDownView(Sender:TObject; Button:TMouseButton; Shift:TShiftState; X,Y:Integer);
begin
  LastViewX:=X; LastViewY:=Y;
  if Button=mbLeft then begin
    View.TogglePicked(X,Y,CanvasBox.Width,CanvasBox.Height,ssCtrl in Shift);
    UpdateSelectionInspector;
    CanvasBox.Invalidate;
  end;
  View.MouseDown(Button,X,Y);
end;

procedure TMainForm.MouseMoveView(Sender:TObject; Shift:TShiftState; X,Y:Integer);
begin View.MouseMove(X,Y,Shift);CanvasBox.Invalidate;end;
procedure TMainForm.MouseUpView(Sender:TObject; Button:TMouseButton; Shift:TShiftState; X,Y:Integer);begin View.MouseUp;end;
procedure TMainForm.ViewDblClick(Sender:TObject);begin View.FocusSelection; CanvasBox.Invalidate;end;
procedure TMainForm.SelectionModeChange(Sender:TObject);
begin
  if SelectionModeCombo.ItemIndex=1 then View.SelectMode(smNode) else View.SelectMode(smElement);
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
  if LastResult=nil then Exit;
  if View.Selection.NodeCount>0 then begin
    ID:=View.Selection.NodeID(0); N:=Model.FindNode(ID); Inspector.Lines.Add(''); Inspector.Lines.Add('SELECTED NODE '+IntToStr(ID)); Inspector.Lines.Add('--------------------------------');
    if N>=0 then Inspector.Lines.Add(Format('Position: %.6g, %.6g, %.6g',[Model.Nodes[N].Position.X,Model.Nodes[N].Position.Y,Model.Nodes[N].Position.Z]));
    for I:=0 to ResultFields.Count-1 do begin F:=ResultFields.Item(I); if F.Location=rlNode then begin V:=F.ValueForEntity(ID); Inspector.Lines.Add(Format('%-22s % .8g %s',[F.Name,V,F.Units])); end; end;
  end else if View.Selection.ElementCount>0 then begin
    ID:=View.Selection.ElementID(0); Inspector.Lines.Add(''); Inspector.Lines.Add('SELECTED ELEMENT '+IntToStr(ID)); Inspector.Lines.Add('--------------------------------');
    for I:=0 to ResultFields.Count-1 do begin F:=ResultFields.Item(I); if F.Location=rlElement then begin V:=F.ValueForEntity(ID); Inspector.Lines.Add(Format('%-22s % .8g %s',[F.Name,V,F.Units])); end; end;
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
    D.Caption:='FEM3D — '+TitleText; D.Width:=760; D.Height:=560; D.Position:=poScreenCenter;
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
    D.Caption:='FEM3D — Result statistics'; D.Width:=620; D.Height:=520; D.Position:=poScreenCenter;
    M:=TMemo.Create(D); M.Parent:=D; M.Align:=alClient; M.ReadOnly:=True; M.ScrollBars:=ssAutoBoth;
    M.Lines.Add('RESULT FIELD STATISTICS'); M.Lines.Add('================================');
    for I:=0 to ResultFields.Count-1 do begin
      F:=ResultFields.Item(I); MinF:=F.MinValue; MaxF:=F.MaxValue;
      M.Lines.Add(Format('%-24s  min=% .8g  max=% .8g  absmax=% .8g %s',[F.Name,MinF,MaxF,F.AbsMaxValue,F.Units]));
    end;
    M.Lines.Add(''); M.Lines.Add('Result provenance:');
    M.Lines.Add('  Case: '+IntToStr(LastResult.AnalysisCaseID)+' — '+LastResult.AnalysisName);
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

procedure TMainForm.NewClick(Sender:TObject);begin ClearResults;Model.Clear;Display.ShowAll;ActiveAnalysisID:=0;Refresh;end;

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

procedure TMainForm.ExitClick(Sender:TObject);begin Close;end;

end.
