{
 /***************************************************************************
                          componentpalette.pas
                          --------------------


 ***************************************************************************/

 ***************************************************************************
 *                                                                         *
 *   This source is free software; you can redistribute it and/or modify   *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This code is distributed in the hope that it will be useful, but      *
 *   WITHOUT ANY WARRANTY; without even the implied warranty of            *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU     *
 *   General Public License for more details.                              *
 *                                                                         *
 *   A copy of the GNU General Public License is available on the World    *
 *   Wide Web at <http://www.gnu.org/copyleft/gpl.html>. You can also      *
 *   obtain it by writing to the Free Software Foundation,                 *
 *   Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.        *
 *                                                                         *
 ***************************************************************************

  Author: Mattias Gaertner, Juha Manninen

  Abstract:
   The implementation of the component palette.
   Supports reordering of pages and components by user settings in environment options.
}
unit ComponentPalette;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, AVL_Tree, fgl,
  Controls, Forms, Graphics, ComCtrls, Buttons, Menus, ExtCtrls,
  FileUtil, LazFileCache, PropEdits, LCLProc, FormEditingIntf, LazIDEIntf,
  {$IFDEF CustomIDEComps}
  CustomIDEComps,
  {$ENDIF}
  MainBase, LazarusIDEStrConsts, ComponentReg, DesignerProcs, PackageDefs, EnvironmentOpts;

const
  CompPalSelectionToolBtnPrefix = 'PaletteSelectBtn';
  CompPaletteCompBtnPrefix = 'PaletteBtn';
type
  TComponentSelectionMode = (
    csmSingle, // reset selection on component add
    csmMulty   // don't reset selection on component add
  );

  { TComponentPage }

  TComponentPage = class(TBaseComponentPage)
  private
    fPageComponent: TCustomPage;
    fSelectButton: TComponent;
    fBtnIndex: integer;
    fCompNames: TStringList;   // Reference to component names.
    fGuiCreated: Boolean;
    procedure ReAlignButtons;
    procedure RemoveSheet;
    procedure InsertVisiblePage(aCompNames: TStringList);
    procedure CreateSelectionButton(aButtonUniqueName: string; aScrollBox: TScrollBox);
    procedure CreateOrDelButton(aComp: TPkgComponent; aButtonUniqueName: string;
      aScrollBox: TScrollBox);
    procedure CreateButtons;
  protected
  public
    constructor Create(const ThePageName: string);
    destructor Destroy; override;
    function GetScrollBox: TScrollBox;
  public
    property PageComponent: TCustomPage read fPageComponent write fPageComponent;
    property SelectButton: TComponent read fSelectButton write fSelectButton;
  end;

  TComponentButtonMap = specialize TFPGMap<String,TSpeedButton>;

  { TComponentPalette }

  TComponentPalette = class(TBaseComponentPalette)
    PalettePopupMenu: TPopupMenu;
    PopupMenu: TPopupMenu;
    OpenPackageMenuItem: TMenuItem;
    OpenUnitMenuItem: TMenuItem;
    procedure ActivePageChanged(Sender: TObject);
    procedure OnScrollBoxResize(Sender: TObject);
    procedure OpenPackageClicked(Sender: TObject);
    procedure OpenUnitClicked(Sender: TObject);
    procedure ComponentListClicked(Sender: TObject);
    procedure PalettePopupMenuPopup(Sender: TObject);
    procedure PopupMenuPopup(Sender: TObject);
  private
    fComponentButtons: TComponentButtonMap;
    // Visual container for tabs
    FPageControl: TPageControl;
    FOnOpenPackage: TNotifyEvent;
    FOnOpenUnit: TNotifyEvent;
    FOnClassSelected: TNotifyEvent;
    FSelected: TRegisteredComponent;
    FSelectionMode: TComponentSelectionMode;
    fUnregisteredIcon: TCustomBitmap;
    fSelectButtonIcon: TCustomBitmap;
    fUpdatingPageControl: boolean;
    // Used by UpdateNoteBookButtons
    fOldActivePage: TTabSheet;
    fVisiblePageIndex: integer;
    procedure ClearButtons;
    function FindCompByButton(Button: TSpeedButton): TRegisteredComponent;
    function FindPkgCompByButton(Button: TComponent): TPkgComponent;
    function IndexOfPageComponent(AComponent: TComponent): integer;
    // Component layout :
    procedure ReAlignButtons(aSheet: TCustomPage);
    procedure UpdateNoteBookButtons(ForceUpdateAll: Boolean);

    procedure RemoveUnneededPage(aSheet: TCustomPage);
    procedure SetPageControl(const AValue: TPageControl);
    procedure SelectionToolClick(Sender: TObject);
    procedure ComponentBtnMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; {%H-}X, {%H-}Y: Integer);
    procedure ComponentBtnMouseUp(Sender: TObject; {%H-}Button: TMouseButton;
      {%H-}Shift: TShiftState; {%H-}X, {%H-}Y: Integer);
    procedure ComponentBtnDblClick(Sender: TObject);
    procedure OnPageMouseWheel(Sender: TObject; {%H-}Shift: TShiftState;
      WheelDelta: Integer; {%H-}MousePos: TPoint; var Handled: Boolean);
    procedure CreatePopupMenu;
    procedure UnselectAllButtons;
    function GetUnregisteredIcon: TCustomBitmap;
    function GetSelectButtonIcon: TCustomBitmap;
    function SelectAButton(Button: TSpeedButton): boolean;
  protected
    procedure OnPageAddedComponent(Component: TRegisteredComponent); override;
    procedure OnPageRemovedComponent(Page: TBaseComponentPage;
                                     Component: TRegisteredComponent); override;
    procedure CheckComponentDesignerVisible(AComponent: TComponent;
                                            var Invisible: boolean);
    procedure SetSelected(const AValue: TRegisteredComponent); override;
    function GetSelected: TRegisteredComponent; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure DoAfterComponentAdded; override;
    procedure OnGetNonVisualCompIcon(Sender: TObject;
                                     AComponent: TComponent; var Icon: TCustomBitmap);
    {$IFDEF CustomIDEComps}
    procedure RegisterCustomIDEComponents(
                       const RegisterProc: RegisterUnitComponentProc); override;
    {$ENDIF}
    procedure Update(ForceUpdateAll: Boolean); override;
  public
    property PageControl: TPageControl read FPageControl write SetPageControl;
    property SelectionMode: TComponentSelectionMode read FSelectionMode write FSelectionMode;
    property OnOpenPackage: TNotifyEvent read FOnOpenPackage write FOnOpenPackage;
    property OnOpenUnit: TNotifyEvent read FOnOpenUnit write FOnOpenUnit;
    property OnClassSelected: TNotifyEvent read FOnClassSelected write FOnClassSelected;
  end;

function CompareControlsWithTag(Control1, Control2: Pointer): integer;

implementation

{$R ../images/components_images.res}
{$DEFINE USE_PageIndex}

const
  OVERVIEW_PANEL_WIDTH = 20;

function CompareControlsWithTag(Control1, Control2: Pointer): integer;
var
  Ctrl1: TControl absolute Control1;
  Ctrl2: TControl absolute Control2;
begin
  if Ctrl1.Tag>Ctrl2.Tag then
    Result:=1
  else if Ctrl1.Tag<Ctrl2.Tag then
    Result:=-1
  else
    Result:=0;
end;

{ TComponentPage }

constructor TComponentPage.Create(const ThePageName: string);
begin
  inherited Create(ThePageName);
end;

destructor TComponentPage.Destroy;
begin
  FreeAndNil(fSelectButton);
  FreeAndNil(fPageComponent);
  inherited Destroy;
end;

function TComponentPage.GetScrollBox: TScrollBox;
begin
  if Assigned(PageComponent) and (PageComponent.ComponentCount > 0)
  and (PageComponent.Components[0] is TScrollBox) then
    Result := TScrollBox(PageComponent.Components[0])
  else
    Result := Nil;
end;

function IsSelectionToolBtn(aControl: TControl): boolean;
begin
  Result:=(aControl is TSpeedButton)
    and (LeftStr(aControl.Name,length(CompPalSelectionToolBtnPrefix))=CompPalSelectionToolBtnPrefix);
end;

procedure TComponentPage.ReAlignButtons;
var
  Pal: TComponentPalette;
  CurButton: TSpeedButton;
  ButtonTree: TAVLTree;
  Node: TAVLTreeNode;
  ScrollBox: TScrollBox;
  buttonx, MaxBtnPerRow, i: integer;
begin
  if (PageComponent=Nil) or (PageComponent.ComponentCount=0)
  or not (PageComponent.Components[0] is TScrollBox) then
    exit;
  if not fGuiCreated then begin
    {$IFDEF VerboseComponentPalette}
    DebugLn(['TComponentPage.ReAlignButtons, ', PageName, ', calling CreateButtons']);
    {$ENDIF}
    CreateButtons;         // Delayed creation of buttons at startup.
  end;
  Pal := TComponentPalette(Palette);
  if Pal.PageControl<>nil then
    Pal.PageControl.DisableAutoSizing{$IFDEF DebugDisableAutoSizing}('TComponentPage.ReAlignButtons'){$ENDIF};
  ButtonTree:=nil;
  try
    ScrollBox:=TScrollBox(PageComponent.Components[0]);
    ButtonTree:=TAVLTree.Create(@CompareControlsWithTag);
    for i:=0 to ScrollBox.ControlCount-1 do begin
      CurButton:=TSpeedbutton(ScrollBox.Controls[i]);
      if IsSelectionToolBtn(CurButton) then continue;
      if (CurButton is TSpeedButton) and CurButton.Visible then
        ButtonTree.Add(CurButton);
    end;
    if ButtonTree.Count=0 then exit;

    ButtonX:= ((ComponentPaletteBtnWidth*3) div 2) + 2;

    {$IFDEF VerboseComponentPalette}
    if PageComponent.Caption = CompPalVerbPgName then
      DebugLn(['TComponentPage.ReAlignButtons',
        ' ButtonTree.Count=',ButtonTree.Count,
        ' ScrollBox.ControlCount=',ScrollBox.ControlCount,
        ' ScrollBox.Bounds=',dbgs(ScrollBox.BoundsRect),
        ' VertScrollBar.Size=',ScrollBox.VertScrollBar.Size,
        ' ClientSizeWithoutBar=',ScrollBox.VertScrollBar.ClientSizeWithoutBar,
        ' IsScrollBarVisible=',ScrollBox.VertScrollBar.IsScrollBarVisible,
        ' HorzScrollBar.Size=',ScrollBox.HorzScrollBar.Size,
        ' Page=',ScrollBox.HorzScrollBar.Page,
        ' Range=',ScrollBox.HorzScrollBar.Range,
        ' IsScrollBarVisible=',ScrollBox.HorzScrollBar.IsScrollBarVisible
        ]);
    {$ENDIF}
    MaxBtnPerRow:=ButtonTree.Count;
    {$IFnDEF LCLCarbon}
    // This condition prevents a mysterious repagination on Windows during startup.
    if MainIDE.IDEStarted then
      MaxBtnPerRow:=((ScrollBox.VertScrollBar.ClientSizeWithoutBar - ButtonX) div ComponentPaletteBtnWidth);
    {$ENDIF}
    // If we need to wrap, make sure we have space for the scrollbar
    if MaxBtnPerRow < ButtonTree.Count then
      MaxBtnPerRow:=((ScrollBox.VertScrollBar.ClientSizeWithBar - ButtonX) div ComponentPaletteBtnWidth);
    //debugln(['TComponentPage.ReAlignButtons MaxBtnPerRow=',MaxBtnPerRow,' ButtonTree.Count=',ButtonTree.Count,' ',ButtonX + MaxBtnPerRow * ComponentPaletteBtnWidth]);
    if MaxBtnPerRow<1 then MaxBtnPerRow:=1;

    i:=0;
    Node:=ButtonTree.FindLowest;
    while Node<>nil do begin
      CurButton:=TSpeedbutton(Node.Data);
      CurButton.SetBounds(ButtonX + (i mod MaxBtnPerRow) * ComponentPaletteBtnWidth,
                          (i div MaxBtnPerRow) * ComponentPaletteBtnHeight,
                          CurButton.Width, CurButton.Height);
      {$IFDEF VerboseComponentPalette}
      if PageComponent.Caption = CompPalVerbPgName then
        DebugLn(['TComponentPage.ReAlignButtons ',CurButton.Name,' ',dbgs(CurButton.BoundsRect)]);
      {$ENDIF}
      inc(i);
      Node:=ButtonTree.FindSuccessor(Node);
    end;
    PageComponent.Invalidate;
  finally
    if Pal.PageControl<>nil then
      Pal.PageControl.EnableAutoSizing{$IFDEF DebugDisableAutoSizing}('TComponentPage.ReAlignButtons'){$ENDIF};
    FreeAndNil(ButtonTree);
  end;
end;

procedure TComponentPage.RemoveSheet;
var
  Btn: TSpeedButton;
begin
  Btn:=TSpeedButton(SelectButton);
  if Btn<>nil then begin
    SelectButton:=nil;
    Application.ReleaseComponent(Btn);
    Btn.Visible:=false;
  end;
  PageComponent:=nil;
end;

procedure TComponentPage.InsertVisiblePage(aCompNames: TStringList);
var
  Pal: TComponentPalette;
  TabIndex: Integer;
  PanelRight: TPanel;
  BtnRight: TSpeedButton;
  TabControl: TCustomTabControl;
begin
  if not Visible then begin
    {$IFDEF VerboseComponentPalette}
    DebugLn(['TComponentPalette.InsertVisiblePage: Not inserting Page=', PageName]);
    {$ENDIF}
    exit;
  end;
  fCompNames := aCompNames;
  Pal := TComponentPalette(Palette);
  TabControl := TCustomTabControl(Pal.FPageControl);
  if PageComponent=nil then
  begin
    // insert a new PageControl page
    {$IFDEF VerboseComponentPalette}
    DebugLn(['TComponentPalette.InsertVisiblePage: Inserting Page=', PageName,
             ', at index=', Pal.fVisiblePageIndex]);
    {$ENDIF}
    {$IFDEF USE_PageIndex}
    TabIndex:= TabControl.Pages.Add(PageName);
    PageComponent := Pal.FPageControl.Page[TabIndex];
    PageComponent.PageIndex := Pal.fVisiblePageIndex;
    {$ELSE}
    TabControl.Pages.Insert(Pal.fVisiblePageIndex, PageName);
    PageComponent := Pal.FPageControl.Page[Pal.fVisiblePageIndex];
    {$ENDIF}
    with TScrollBox.Create(PageComponent) do begin
      Align := alClient;
      BorderStyle := bsNone;
      BorderWidth := 0;
      HorzScrollBar.Visible := false;
      {$IFDEF LCLCarbon}
      // carbon has not implemented turning scrollbars on and off
      VertScrollBar.Visible := false;
      AutoScroll:=false;
      {$ENDIF}
      VertScrollBar.Increment := ComponentPaletteBtnHeight;
      Parent := PageComponent;
    end;
    PanelRight := TPanel.Create(PageComponent);
    with PanelRight do
    begin
      Align := alRight;
      Caption := '';
      BevelOuter := bvNone;
      Width := OVERVIEW_PANEL_WIDTH;
      Visible := True; // EnvironmentOptions.IDESpeedButtonsVisible;
      Parent := PageComponent;
      OnMouseWheel := @Pal.OnPageMouseWheel;
    end;
    BtnRight:=TSpeedButton.Create(PageComponent);
    with BtnRight do
    begin
      LoadGlyphFromResourceName(HInstance, 'SelCompPage');
      Flat := True;
      SetBounds(2,1,16,16);
      Hint := 'Click to Select Palette Page';
      ShowHint := True;
      OnClick := @MainIDE.SelComponentPageButtonClick;
      OnMouseWheel := @Pal.OnPageMouseWheel;
      Parent := PanelRight;
    end;
  end
  else begin
    // move to the right position
    {$IFDEF USE_PageIndex}
      {$IFDEF VerboseComponentPalette}
      DebugLn(['TComponentPalette.InsertVisiblePage: Page=', PageName,
               ' setting PageIndex from ', PageComponent.PageIndex , ' to ', Pal.fVisiblePageIndex]);
      {$ENDIF}
    PageComponent.PageIndex := Pal.fVisiblePageIndex;
    {$ELSE}
    TabIndex := PageComponent.PageIndex;
    {$IFDEF VerboseComponentPalette}
    DebugLn(['TComponentPalette.InsertVisiblePage: Start moving Page=', PageName,
             ' from ', TabIndex, ' to ', Pal.fVisiblePageIndex]);
    {$ENDIF}
    if (TabIndex<>Pal.fVisiblePageIndex)
    and (Pal.fVisiblePageIndex < TabControl.Pages.Count) then
    begin
      {$IFDEF VerboseComponentPalette}
      if {PageName = CompPalVerbPgName} true then
        DebugLn(['TComponentPalette.InsertVisiblePage: Moving Page=', PageName,
                 ' from ', TabIndex, ' to ', Pal.fVisiblePageIndex]);
      {$ENDIF}
      TabControl.Pages.Move(TabIndex, Pal.fVisiblePageIndex);
    end;
    {$ENDIF}
  end;
  inc(Pal.fVisiblePageIndex);
end;

procedure TComponentPage.CreateSelectionButton(aButtonUniqueName: string; aScrollBox: TScrollBox);
var
  {%H-}Pal: TComponentPalette;
  Btn: TSpeedButton;
begin
  if Assigned(SelectButton) then Exit;
  Pal := TComponentPalette(Palette);
  Btn := TSpeedButton.Create(nil);
  SelectButton:=Btn;
  with Btn do begin
    Name := CompPalSelectionToolBtnPrefix + aButtonUniqueName;
    OnClick := @Pal.SelectionToolClick;
    OnMouseWheel := @Pal.OnPageMouseWheel;
    LoadGlyphFromResourceName(hInstance, 'tmouse');
    Flat := True;
    GroupIndex:= 1;
    Down := True;
    Hint := lisSelectionTool;
    ShowHint := EnvironmentOptions.ShowHintsForComponentPalette;
    SetBounds(0,0,ComponentPaletteBtnWidth,ComponentPaletteBtnHeight);
    Parent := aScrollBox;
  end;
end;

procedure TComponentPage.CreateOrDelButton(aComp: TPkgComponent; aButtonUniqueName: string;
  aScrollBox: TScrollBox);
var
  Pal: TComponentPalette;
  Btn: TSpeedButton;
  CompCN: String;      // Component ClassName
  i: Integer;
begin
  Pal := TComponentPalette(Palette);
  CompCN := aComp.ComponentClass.ClassName;
  if Pal.fComponentButtons.Find(CompCN, i) then
    Btn := Pal.fComponentButtons.Data[i]
  else
    Btn := nil;
  if aComp.Visible then
  begin
    inc(fBtnIndex);
    if Btn=nil then
    begin
      Btn := TSpeedButton.Create(nil);
      Pal.fComponentButtons[CompCN] := Btn;
      Btn.Name := CompPaletteCompBtnPrefix + aButtonUniqueName + CompCN;
      // Left and Top will be set in ReAlignButtons.
      Btn.SetBounds(Btn.Left,Btn.Top,ComponentPaletteBtnWidth,ComponentPaletteBtnHeight);
      Btn.Glyph.Assign(aComp.Icon);
      Btn.GroupIndex := 1;
      Btn.Flat := true;
      Btn.OnMouseDown := @Pal.ComponentBtnMouseDown;
      Btn.OnMouseUp := @Pal.ComponentBtnMouseUp;
      Btn.OnDblClick := @Pal.ComponentBtnDblClick;
      Btn.OnMouseWheel := @Pal.OnPageMouseWheel;
      Btn.ShowHint := EnvironmentOptions.ShowHintsForComponentPalette;
      Btn.Hint := CompCN + sLineBreak + '(' + aComp.ComponentClass.UnitName + ')';
      Btn.PopupMenu:=Pal.PopupMenu;
      {$IFDEF VerboseComponentPalette}
      if aComp.RealPage.PageName = CompPalVerbPgName then
        DebugLn(['TComponentPalette.CreateOrDelButton Created Button: ',CompCN,' ',Btn.Name]);
      {$ENDIF}
    end else
    begin
      {$IFDEF VerboseComponentPalette}
      if aComp.RealPage.PageName = CompPalVerbPgName then
        DebugLn(['TComponentPalette.CreateOrDelButton Keep Button: ',CompCN,' ',Btn.Name,' ',DbgSName(Btn.Parent)]);
      {$ENDIF}
    end;
    Btn.Parent := aScrollBox;
    Btn.Tag:=fBtnIndex;
  end
  else if Btn<>nil then
  begin
    {$IFDEF VerboseComponentPalette}
    if aComp.RealPage.PageName = CompPalVerbPgName then
      DebugLn(['TComponentPalette.CreateOrDelButton Destroy Button: ',CompCN,' ',Btn.Name]);
    {$ENDIF}
    Application.ReleaseComponent(Btn);
    Pal.fComponentButtons.Remove(CompCN);
    Btn.Visible:=false;
  end;
end;

procedure TComponentPage.CreateButtons;
// Create speedbuttons for every visible component
var
  Pal: TComponentPalette;
  ScrollBox: TScrollBox;
  Comp: TPkgComponent;
  i: Integer;
begin
  if not Visible then Exit;
  Pal := TComponentPalette(Palette);
  ScrollBox := GetScrollBox;
  Assert(Assigned(ScrollBox), 'CreateButtons: ScrollBox not assigned.');
  ScrollBox.OnResize := @Pal.OnScrollBoxResize;
  ScrollBox.OnMouseWheel := @Pal.OnPageMouseWheel;
  {$IFDEF VerboseComponentPalette}
  if PageName = CompPalVerbPgName then
    DebugLn(['TComponentPalette.CreateButtons PAGE="',PageName,'", PageIndex=',PageComponent.PageIndex]);
  {$ENDIF}
  // create selection button
  CreateSelectionButton(IntToStr(FIndex), ScrollBox);
  // create component buttons and delete unneeded ones
  fBtnIndex := 0;
  Assert(Assigned(fCompNames), 'TComponentPage.CreateButtons: fCompNames is not assigned.');
  for i := 0 to fCompNames.Count-1 do begin
    Comp := Pal.FindComponent(fCompNames[i]) as TPkgComponent;
    if Assigned(Comp) then
      CreateOrDelButton(Comp, Format('%d_%d_',[FIndex,i]), ScrollBox);
  end;
  fGuiCreated := True;
end;

{ TComponentPalette }

procedure TComponentPalette.ActivePageChanged(Sender: TObject);
begin
  if FPageControl=nil then exit;
  if (FSelected<>nil)
  and ((FSelected.RealPage as TComponentPage).PageComponent=FPageControl.ActivePage) then exit;
  if fUpdatingPageControl then exit;
  {$IFDEF VerboseComponentPalette}
  DebugLn('TComponentPalette.ActivePageChanged: Calling ReAlignButtons, setting Selected:=nil.');
  {$ENDIF}
  ReAlignButtons(FPageControl.ActivePage);
  Selected:=nil;
end;

procedure TComponentPalette.OnScrollBoxResize(Sender: TObject);
begin
  if MainIDE.IDEStarted and (TControl(Sender).Parent is TCustomPage) then
  begin
    {$IFDEF VerboseComponentPalette}
    DebugLn(['TComponentPalette.OnScrollBoxResize Calling ReAlignButtons, IDEStarted=', MainIDE.IDEStarted]);
    {$ENDIF}
    ReAlignButtons(TCustomPage(TControl(Sender).Parent));
  end;
end;

procedure TComponentPalette.OpenPackageClicked(Sender: TObject);
var
  PkgComponent: TPkgComponent;
begin
  PkgComponent:=FindPkgCompByButton(PopupMenu.PopupComponent);
  if (PkgComponent=nil) or (PkgComponent.PkgFile=nil)
  or (PkgComponent.PkgFile.LazPackage=nil) then exit;
  if Assigned(OnOpenPackage) then
    OnOpenPackage(PkgComponent.PkgFile.LazPackage);
end;

procedure TComponentPalette.OpenUnitClicked(Sender: TObject);
var
  PkgComponent: TPkgComponent;
begin
  PkgComponent:=FindPkgCompByButton(PopupMenu.PopupComponent);
  if (PkgComponent=nil) or (PkgComponent.PkgFile=nil)
  or (PkgComponent.PkgFile.LazPackage=nil) then exit;
  if Assigned(OnOpenUnit) then
    OnOpenUnit(PkgComponent);
end;

procedure TComponentPalette.ComponentListClicked(Sender: TObject);
begin
  MainIDE.DoShowComponentList;
end;

procedure TComponentPalette.PalettePopupMenuPopup(Sender: TObject);
begin
  ;
end;

procedure TComponentPalette.PopupMenuPopup(Sender: TObject);
var
  PkgComponent: TPkgComponent;
  APackage: TLazPackage;
  UnitFilename: String;
  ShownFilename: String;
begin
  PkgComponent:=FindPkgCompByButton(PopupMenu.PopupComponent);
  APackage:=nil;
  if (PkgComponent<>nil) and (PkgComponent.PkgFile<>nil) then
    APackage:=PkgComponent.PkgFile.LazPackage;
  if APackage=nil then begin
    OpenPackageMenuItem.Visible:=false;
    OpenUnitMenuItem.Visible:=false;
  end else begin
    OpenPackageMenuItem.Caption:=Format(lisCPOpenPackage, [APackage.IDAsString]);
    OpenPackageMenuItem.Visible:=true;
    ShownFilename:=PkgComponent.PkgFile.Filename;
    UnitFilename:=PkgComponent.PkgFile.GetFullFilename;
    if not FileExistsCached(UnitFilename) then begin
      UnitFilename:=LazarusIDE.FindSourceFile(ExtractFilename(UnitFilename),
                                              APackage.Directory,[]);
      if FileExistsUTF8(UnitFilename) then
        UnitFilename:=ShownFilename;
    end;
    OpenUnitMenuItem.Caption:=Format(lisCPOpenUnit, [ShownFilename]);
    OpenUnitMenuItem.Visible:=true;
    OpenUnitMenuItem.Enabled:=FileExistsCached(UnitFilename);
  end;
end;

procedure TComponentPalette.SetPageControl(const AValue: TPageControl);
var
  MenuItem: TMenuItem;
begin
  if FPageControl=AValue then exit;
  ClearButtons;
  FPageControl:=AValue;
  if FPageControl<>nil then begin
    FPageControl.OnChange:=@ActivePageChanged;
    if PalettePopupMenu=nil then begin
      PalettePopupMenu:=TPopupMenu.Create(nil);
      PalettePopupMenu.OnPopup:=@PalettePopupMenuPopup;
      PalettePopupMenu.Name:='PalettePopupMenu';
      // Component List
      MenuItem:=TMenuItem.Create(PalettePopupMenu);
      with MenuItem do begin
        Name:='ComponentListMenuItem';
        Caption:=lisCompPalComponentList;
        OnClick:=@ComponentListClicked;
      end;
      PalettePopupMenu.Items.Add(MenuItem);
    end;
    FPageControl.PopupMenu:=PalettePopupMenu;
  end;
  {$IFDEF VerboseComponentPalette}
  DebugLn(['TComponentPalette.SetPageControl, calling UpdateNoteBookButtons, ', AValue]);
  {$ENDIF}
end;

procedure TComponentPalette.SelectionToolClick(Sender: TObject);
begin
  SelectAButton(TSpeedButton(Sender));
end;

procedure TComponentPalette.ComponentBtnMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button=mbLeft then
  begin
    if ssShift in Shift then
      SelectionMode := csmMulty
    else
      SelectionMode := csmSingle;
    SelectAButton(TSpeedButton(Sender));
    if Assigned(OnClassSelected) then
      OnClassSelected(Self);
  end;
end;

procedure TComponentPalette.ComponentBtnMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
   { If the visual state is down, but internal "no selection" then
    just do visual unselection of all buttons
    This trick is for double-click handling (to unselect the button visually ). }
  if ((Sender as TCustomSpeedButton).Down) and (Selected = Nil) then
    UnselectAllButtons;
end;

procedure TComponentPalette.ComponentBtnDblClick(Sender: TObject);
var
  TypeClass: TComponentClass;
  ParentComp: TComponent;
  X, Y: integer;
  AComponent: TComponent;
  DisableAutoSize: Boolean;
begin
  //debugln('TComponentPalette.ComponentBtnDblClick ',TComponent(Sender).Name);
  if SelectAButton(TSpeedButton(Sender)) and (FSelected<>nil) then begin
    if FormEditingHook<>nil then begin
      TypeClass:=FSelected.ComponentClass;
      if assigned(FSelected.OnGetCreationClass) then
        FSelected.OnGetCreationClass(Self,TypeClass);
      if TypeClass=nil then exit;
      ParentComp:=FormEditingHook.GetDefaultComponentParent(TypeClass);
      if ParentComp=nil then exit;
      if not FormEditingHook.GetDefaultComponentPosition(TypeClass,ParentComp,X,Y)
      then exit;
      //debugln('TComponentPalette.ComponentBtnDblClick ',dbgsName(Sender),' ',dbgs(X),',',dbgs(Y));
      DisableAutoSize:=true;
      AComponent:=FormEditingHook.CreateComponent(ParentComp,TypeClass,'',X,Y,0,0,
        DisableAutoSize);
      if AComponent<>nil then begin
        if DisableAutoSize and (AComponent is TControl) then
          TControl(AComponent).EnableAutoSizing;
        GlobalDesignHook.PersistentAdded(AComponent,true);
      end;
    end;
  end;
  Selected:=nil;
  if Assigned(OnClassSelected) then
    OnClassSelected(Self);
end;

// unselect all other buttons on all other PageControl pages
procedure TComponentPalette.UnselectAllButtons;
var
  i: Integer;
  CurPage: TBaseComponentPage;
  SelectButtonOnPage: TSpeedButton;
begin
  for i:=0 to Pages.Count-1 do begin
    CurPage:=Pages[i];
    if (FSelected=nil) or (FSelected.RealPage<>CurPage) then begin
      SelectButtonOnPage:=TSpeedButton(TComponentPage(CurPage).SelectButton);
      if SelectButtonOnPage<>nil then
        SelectButtonOnPage.Down:=true;
    end;
  end;
end;

procedure TComponentPalette.SetSelected(const AValue: TRegisteredComponent);
var
  Sheet: TTabSheet;
  i: Integer;
begin
  if FSelected=AValue then exit;
  FSelected:=AValue;
  if FSelected<>nil then begin
    if (FSelected.RealPage=nil) or (FSelected.RealPage.Palette<>Self)
    or (not FSelected.Visible)
    or (not FSelected.CanBeCreatedInDesigner) then
      FSelected:=nil;
  end;
  if FPageControl=nil then exit;
  UnselectAllButtons;
  if FSelected=nil then exit;
  Assert(Assigned(FSelected.RealPage), 'TComponentPalette.SetSelected: FSelected.RealPage = Nil.');
  Sheet:=(FSelected.RealPage as TComponentPage).PageComponent as TTabSheet;
  {$IFDEF VerboseComponentPalette}
  DebugLn(['TComponentPalette.SetSelected: Setting FPageControl.ActivePage index ',Sheet.PageIndex]);
  {$ENDIF}
  // Switch to the new page
  FPageControl.ActivePage:=Sheet;
  // Build the GUI layout for this page if not done yet.
  if not fComponentButtons.Find(FSelected.ComponentClass.ClassName, i) then
    ReAlignButtons(FPageControl.ActivePage);
  // Select button
  fComponentButtons[FSelected.ComponentClass.ClassName].Down := true;
end;

function TComponentPalette.GetSelected: TRegisteredComponent;
begin
  Result:=FSelected;
end;

procedure TComponentPalette.CreatePopupMenu;
var
  MenuItem: TMenuItem;
begin
  if PopupMenu<>nil then exit;
  PopupMenu:=TPopupMenu.Create(nil);
  PopupMenu.OnPopup:=@PopupMenuPopup;
  PopupMenu.Name:='ComponentPopupMenu';
  
  OpenPackageMenuItem:=TMenuItem.Create(PopupMenu);
  with OpenPackageMenuItem do begin
    Name:='OpenPackageMenuItem';
    Caption:=lisCompPalOpenPackage;
    OnClick:=@OpenPackageClicked;
  end;
  PopupMenu.Items.Add(OpenPackageMenuItem);

  OpenUnitMenuItem:=TMenuItem.Create(PopupMenu);
  with OpenUnitMenuItem do begin
    Name:='OpenUnitMenuItem';
    Caption:=lisCompPalOpenUnit;
    OnClick:=@OpenUnitClicked;
  end;
  PopupMenu.Items.Add(OpenUnitMenuItem);

  PopupMenu.Items.AddSeparator;

  MenuItem:=TMenuItem.Create(PopupMenu);
  with MenuItem do begin
    Name:='ComponentListMenuItem';
    Caption:=lisCompPalComponentList;
    OnClick:=@ComponentListClicked;
  end;
  PopupMenu.Items.Add(MenuItem);
end;

procedure TComponentPalette.OnPageMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  if (WheelDelta > 0) then
  begin
    if (PageControl.ActivePageIndex > 0) then
      PageControl.ActivePageIndex := PageControl.ActivePageIndex - 1;
  end else begin
    if (PageControl.ActivePageIndex < PageControl.PageCount-1) then
      PageControl.ActivePageIndex := PageControl.ActivePageIndex + 1;
  end;
  Handled := True;
end;

procedure TComponentPalette.OnPageAddedComponent(Component: TRegisteredComponent);
begin
  fComponentCache.Add(Component);
  inherited OnPageAddedComponent(Component);
end;

procedure TComponentPalette.OnPageRemovedComponent(Page: TBaseComponentPage;
  Component: TRegisteredComponent);
begin
  fComponentCache.Remove(Component);
  inherited OnPageRemovedComponent(Page, Component);
end;

procedure TComponentPalette.Update(ForceUpdateAll: Boolean);
begin
  {$IFDEF VerboseComponentPalette}
  DebugLn(['TComponentPalette.Update, calling UpdateNoteBookButtons, fUpdatingPageControl=', fUpdatingPageControl]);
  {$ENDIF}
  UpdateNoteBookButtons(ForceUpdateAll);
end;

procedure TComponentPalette.CheckComponentDesignerVisible(
  AComponent: TComponent; var Invisible: boolean);
var
  RegComp: TRegisteredComponent;
  AControl: TControl;
begin
  if (AComponent is TControl) then begin
    AControl:=TControl(AComponent);
    Invisible:=(csNoDesignVisible in AControl.ControlStyle)
  end else begin
    RegComp:=FindComponent(AComponent.ClassName);
    Invisible:=(RegComp=nil) or (RegComp.OrigPageName='');
  end;
end;

constructor TComponentPalette.Create;
begin
  inherited Create(EnvironmentOptions.ComponentPaletteOptions);
  FSelectionMode:=csmSingle;
  fComponentButtons:=TComponentButtonMap.Create;
  fComponentButtons.Sorted:=True;
  OnComponentIsInvisible:=@CheckComponentDesignerVisible;
end;

destructor TComponentPalette.Destroy;
var
  i: Integer;
begin
  if OnComponentIsInvisible=@CheckComponentDesignerVisible then
    OnComponentIsInvisible:=nil;
  PageControl:=nil;
  for i := 0 to fComponentButtons.Count-1 do
    fComponentButtons.Data[i].Free;
  FreeAndNil(fComponentButtons);
  FreeAndNil(fUnregisteredIcon);
  FreeAndNil(fSelectButtonIcon);
  FreeAndNil(PopupMenu);
  FreeAndNil(PalettePopupMenu);
  inherited Destroy;
end;

procedure TComponentPalette.ClearButtons;
begin
  if FPageControl<>nil then
    FPageControl.DisableAlign;
  Selected:=nil;
  if PopupMenu<>nil then begin
    PopupMenu.Free;
    PopupMenu:=nil;
    OpenPackageMenuItem:=nil;
  end;
  if FPageControl<>nil then
    FPageControl.EnableAlign;
end;

procedure TComponentPalette.DoAfterComponentAdded;
begin
  inherited DoAfterComponentAdded;
  if not (ssShift in GetKeyShiftState) and (SelectionMode = csmSingle) then
    Selected := nil;
end;

function TComponentPalette.GetUnregisteredIcon: TCustomBitmap;
begin
  if fUnregisteredIcon = nil then 
  begin
    fUnregisteredIcon := CreateBitmapFromResourceName(hInstance, 'unregisteredcomponent');
    if fUnregisteredIcon = nil then
      fUnregisteredIcon := CreateBitmapFromResourceName(hInstance, 'default');
  end;
  Result := fUnregisteredIcon;
end;

function TComponentPalette.GetSelectButtonIcon: TCustomBitmap;
begin
  if fSelectButtonIcon=nil then 
    fSelectButtonIcon := CreateBitmapFromResourceName(hInstance, 'tmouse');
  Result:=fSelectButtonIcon;
end;

function TComponentPalette.SelectAButton(Button: TSpeedButton): boolean;
var
  NewComponent: TRegisteredComponent;
begin
  NewComponent := FindCompByButton(Button);
  Selected := NewComponent;
  Result := (Selected = NewComponent);
end;

procedure TComponentPalette.ReAlignButtons(aSheet: TCustomPage);
var
  PageInd: Integer;
begin
  if (aSheet=Nil) or not aSheet.Visible then
    exit;
  {$IFDEF VerboseComponentPalette}
  DebugLn(['TComponentPalette.ReAlignButtons Visible="',aSheet.Caption,'", ClientWidth=',aSheet.ClientWidth]);
  {$ENDIF}
  PageInd:=IndexOfPageComponent(aSheet);
  if PageInd>=0 then
    TComponentPage(Pages[PageInd]).ReAlignButtons;
end;

procedure TComponentPalette.RemoveUnneededPage(aSheet: TCustomPage);
var
  PageInd: Integer;
begin
  PageInd:=IndexOfPageComponent(aSheet);
  if (PageInd>=0) and Pages[PageInd].Visible then
    Exit;
  // page is not needed anymore => delete
  if PageInd>=0 then
    TComponentPage(Pages[PageInd]).RemoveSheet;
  if aSheet=fOldActivePage then
    fOldActivePage:=nil;
  aSheet.Visible:=false;
  {$IFDEF VerboseComponentPalette}
  if aSheet.Caption = CompPalVerbPgName then
    DebugLn(['TComponentPalette.RemoveUnneededPage: Removing Page=', aSheet.Caption, ', index=', PageInd]);
  {$ENDIF}
  Application.ReleaseComponent(aSheet);
end;

procedure TComponentPalette.UpdateNoteBookButtons(ForceUpdateAll: Boolean);
var
  i: Integer;
  Pg: TComponentPage;
begin
  if fUpdatingPageControl then exit;
  Assert(not IsUpdateLocked, 'TComponentPalette.UpdateNoteBookButtons: IsUpdateLocked');
  if FPageControl=Nil then exit;
  // lock
  fUpdatingPageControl:=true;
  FPageControl.DisableAlign;
  try
    fOldActivePage:=FPageControl.ActivePage;
    fUserOrder.SortPagesAndCompsUserOrder;
    ComponentPageClass := TComponentPage;   // Used by CreatePagesFromUserOrder
    CreatePagesFromUserOrder;
    CreatePopupMenu;

    {$IFDEF VerboseComponentPalette}
    DebugLn(['TComponentPalette.UpdateNoteBookButtons: FPageCount before=', FPageControl.PageCount]);
    {$ENDIF}
    // remove every page in the PageControl without a visible page
    for i:=FPageControl.PageCount-1 downto 0 do
      RemoveUnneededPage(FPageControl.Pages[i]);
    Application.ProcessMessages; // PageIndex of tabs are not updated without this.
    {$IFDEF VerboseComponentPalette}
    DebugLn(['TComponentPalette.UpdateNoteBookButtons: FPageCount after=', FPageControl.PageCount,
    ' PageCount=', Pages.count]);
    {$ENDIF}

    // Mark GUIs as not created. They will be created later when page gets selected.
    for i := 0 to Pages.Count-1 do
      TComponentPage(Pages[i]).fGuiCreated := False;

    // insert a PageControl page for every visible palette page
    fVisiblePageIndex := 0;
    for i := 0 to Pages.Count-1 do
    begin
      // fPages and fUserOrder.ComponentPages are now synchronized, same index applies.
      Assert(Pages[i].PageName=fUserOrder.ComponentPages[i],
             'UpdateNoteBookButtons: Page names do not match.');
      Pg := TComponentPage(Pages[i]);
      {$IFDEF LCLQt}   // Qt has some problems in moving existing tabs!
      if Assigned(Pg.PageComponent) then begin
        Pg.PageComponent.Free;
        Pg.RemoveSheet;
      end;
      {$ENDIF}
      Pg.InsertVisiblePage(TStringList(fUserOrder.ComponentPages.Objects[i]));
      {$IFDEF VerboseComponentPalette}
      DebugLn(['TComponentPalette.UpdateNoteBookButtons: PageIndex=', i, ' PageName=',Pages[i].PageName]);
      {$ENDIF}
    end;

    // OldActivePage can be invalid if a user defined page is just deleted.
    if Assigned(fOldActivePage) and (FPageControl.IndexOf(fOldActivePage) = -1) then
      fOldActivePage := Nil;
    for i := Pages.Count-1 downto 0 do
    begin
      Pg := TComponentPage(Pages[i]);
      // During IDE start create GUI only for the active page.
      if ((fOldActivePage=Nil) and (i=0))  // First page is activated by default.
      or (Pg.PageComponent=fOldActivePage) // Previous active page will be restored.
      or (ForceUpdateAll) then             // Forced after changing configuration.
        Pg.ReAlignButtons;
    end;
    // restore active page
    if Assigned(fOldActivePage) then
      FPageControl.ActivePage:=fOldActivePage
    else if FPageControl.PageCount>0 then
      FPageControl.PageIndex:=0;
  finally
    // unlock
    fUpdatingPageControl:=false;
    FPageControl.EnableAlign;
  end;
end;

procedure TComponentPalette.OnGetNonVisualCompIcon(Sender: TObject;
  AComponent: TComponent; var Icon: TCustomBitmap);
var
  ARegComp: TRegisteredComponent;
begin
  if AComponent<>nil then
    ARegComp:=FindComponent(AComponent.ClassName)
  else
    ARegComp:=nil;
  if ARegComp<>nil then
    Icon:=TPkgComponent(ARegComp).Icon
  else
    Icon:=GetUnregisteredIcon;
end;

function TComponentPalette.IndexOfPageComponent(AComponent: TComponent): integer;
begin
  if AComponent<>nil then begin
    Result:=Pages.Count-1;
    while (Result>=0) and ((Pages[Result] as TComponentPage).PageComponent<>AComponent) do
      dec(Result);
  end else
    Result:=-1;
end;

function TComponentPalette.FindCompByButton(Button: TSpeedButton): TRegisteredComponent;
var
  i: Integer;
  CompName: String;
begin
  i := fComponentButtons.IndexOfData(Button);
  if i >= 0 then
    Result := FindComponent(fComponentButtons.Keys[i])
  else
    Result := nil;
end;

function TComponentPalette.FindPkgCompByButton(Button: TComponent): TPkgComponent;
begin
  Result := FindCompByButton(Button as TSpeedButton) as TPkgComponent;
end;

{$IFDEF CustomIDEComps}
procedure TComponentPalette.RegisterCustomIDEComponents(
  const RegisterProc: RegisterUnitComponentProc);
begin
  CustomIDEComps.RegisterCustomComponents(RegisterProc);
end;
{$ENDIF}

end.

