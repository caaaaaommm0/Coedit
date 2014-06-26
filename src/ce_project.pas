unit ce_project;

{$mode objfpc}{$H+}

interface

// TODO: pre/post compilation shell-script / process
// TODO: run opts, newConsole, catch output, etc
// TODO: configuration templates

uses
  Classes, SysUtils, ce_dmdwrap;

type

(*****************************************************************************
 * Represents a D project.
 *
 * It includes all the options defined in ce_dmdwrap, organized in
 * a collection to allow multiples configurations.
 *
 * Basically it' s designed to provide the options for the dmd process.
 *)
  TCEProject = class(TComponent)
  private
    fOnChange: TNotifyEvent;
    fModified: boolean;
    fFilename: string;
    fBasePath: string;
    fOptsColl: TCollection;
    fSrcs, fSrcsCop: TStringList;
    fConfIx: Integer;
    fChangedCount: NativeInt;
    procedure doChanged;
    procedure subMemberChanged(sender : TObject);
    procedure setOptsColl(const aValue: TCollection);
    procedure setFname(const aValue: string);
    procedure setSrcs(const aValue: TStringList);
    procedure setConfIx(aValue: Integer);
    function getConfig(const ix: integer): TCompilerConfiguration;
    function getCurrConf: TCompilerConfiguration;
  published
    property OptionsCollection: TCollection read fOptsColl write setOptsColl;
    property Sources: TStringList read fSrcs write setSrcs; // 'read' should return a copy to avoid abs/rel errors
    property ConfigurationIndex: Integer read fConfIx write setConfIx;
  public
    constructor create(aOwner: TComponent); override;
    destructor destroy; override;
    procedure beforeChanged;
    procedure afterChanged;
    procedure reset;
    function getAbsoluteSourceName(const aIndex: integer): string;
    function getAbsoluteFilename(const aFilename: string): string;
    procedure addSource(const aFilename: string);
    function addConfiguration: TCompilerConfiguration;
    procedure getOpts(const aList: TStrings);
    procedure saveToFile(const aFilename: string);
    procedure loadFromFile(const aFilename: string);
    //
    property configuration[ix: integer]: TCompilerConfiguration read getConfig;
    property currentConfiguration: TCompilerConfiguration read getCurrConf;
    property fileName: string read fFilename write setFname;
    property onChange: TNotifyEvent read fOnChange write fOnChange;
    property modified: boolean read fModified;
  end;

implementation

uses
  ce_common;

constructor TCEProject.create(aOwner: TComponent);
begin
  inherited create(aOwner);
  fSrcs := TStringList.Create;
  fSrcs.OnChange := @subMemberChanged;
  fSrcsCop := TStringList.Create;
  fOptsColl := TCollection.create(TCompilerConfiguration);
  reset;
  fModified := false;
end;

destructor TCEProject.destroy;
begin
  fOnChange := nil;
  fSrcs.free;
  fSrcsCop.Free;
  fOptsColl.free;
  inherited;
end;

function TCEProject.addConfiguration: TCompilerConfiguration;
begin
  result := TCompilerConfiguration(fOptsColl.Add);
  result.onChanged := @subMemberChanged;
end;

procedure TCEProject.setOptsColl(const aValue: TCollection);
var
  i: nativeInt;
begin
  fOptsColl.Assign(aValue);
  for i:= 0 to self.fOptsColl.Count-1 do
    Configuration[i].onChanged := @subMemberChanged;
end;

procedure TCEProject.addSource(const aFilename: string);
var
  relSrc, absSrc: string;
begin
  for relSrc in fSrcs do
  begin
    absSrc := expandFilenameEx(fBasePath,relsrc);
    if aFilename = absSrc then exit;
  end;
  fSrcs.Add(ExtractRelativepath(fBasePath,aFilename));
end;

procedure TCEProject.setFname(const aValue: string);
var
  oldAbs, newRel, oldBase: string;
  i: NativeInt;
begin
  if fFilename = aValue then exit;
  //
  beforeChanged;

  fFilename := aValue;
  oldBase := fBasePath;
  fBasePath := extractFilePath(fFilename);
  //
  for i:= 0 to fSrcs.Count-1 do
  begin
    oldAbs := expandFilenameEx(oldBase,fSrcs[i]);
    newRel := ExtractRelativepath(fBasePath, oldAbs);
    fSrcs[i] := newRel;
  end;
  //
  afterChanged;
end;

procedure TCEProject.setSrcs(const aValue: TStringList);
begin
  beforeChanged;
  fSrcs.Assign(aValue);
  patchPlateformPaths(fSrcs);
  afterChanged;
end;

procedure TCEProject.setConfIx(aValue: Integer);
begin
  if fConfIx = aValue then exit;
  beforeChanged;
  if aValue < 0 then aValue := 0;
  if aValue > fOptsColl.Count-1 then aValue := fOptsColl.Count-1;
  fConfIx := aValue;
  afterChanged;
end;

procedure TCEProject.subMemberChanged(sender : TObject);
begin
  beforeChanged;
  fModified := true;
  afterChanged;
end;

procedure TCEProject.beforeChanged;
begin
  Inc(fChangedCount);
end;

procedure TCEProject.afterChanged;
begin
  Dec(fChangedCount);
  if fChangedCount > 0 then
  begin
    {$IFDEF DEBUG}
    writeln('project update count > 0');
    {$ENDIF}
    exit;
  end;
  fChangedCount := 0;
  doChanged;
end;

procedure TCEProject.doChanged;
{$IFDEF DEBUG}
var
  lst: TStringList;
{$ENDIF}
begin
  fModified := true;
  if assigned(fOnChange) then fOnChange(Self);
  {$IFDEF DEBUG}
  lst := TStringList.Create;
  try
    lst.Add('---------begin----------');
    getOpts(lst);
    lst.Add('---------end-----------');
    writeln(lst.Text);
  finally
    lst.Free;
  end;
  {$ENDIF}
end;

function TCEProject.getConfig(const ix: integer): TCompilerConfiguration;
begin
  result := TCompilerConfiguration(fOptsColl.Items[ix]);
  result.onChanged := @subMemberChanged;
end;

function TCEProject.getCurrConf: TCompilerConfiguration;
begin
  result := TCompilerConfiguration(fOptsColl.Items[fConfIx]);
end;

procedure TCEProject.reset;
var
  defConf: TCompilerConfiguration;
begin
  beforeChanged;
  fConfIx := 0;
  fOptsColl.Clear;
  defConf := addConfiguration;
  defConf.name := 'default';
  fSrcs.Clear;
  fFilename := '';
  afterChanged;
  fModified := false;
end;

procedure TCEProject.getOpts(const aList: TStrings);
var
  rel, abs: string;
begin
  if fConfIx = -1 then exit;
  for rel in fSrcs do if rel <> '' then
  begin
    abs := expandFilenameEx(fBasePath,rel);
    aList.Add(abs); // process.inc ln 249. double quotes are added anyway if there's a space...
  end;
  TCompilerConfiguration(fOptsColl.Items[fConfIx]).getOpts(aList);
end;

function TCEProject.getAbsoluteSourceName(const aIndex: integer): string;
begin
  if aIndex < 0 then exit('');
  if aIndex > fSrcs.Count-1 then exit('');
  result := expandFileNameEx(fBasePath, fSrcs.Strings[aIndex]);
end;

function TCEProject.getAbsoluteFilename(const aFilename: string): string;
begin
  result := expandFileNameEx(fBasePath, aFilename);
end;

procedure TCEProject.saveToFile(const aFilename: string);
begin
  saveCompToTxtFile(self, aFilename);
  fModified := false;
end;

procedure TCEProject.loadFromFile(const aFilename: string);
begin
  Filename := aFilename;
  loadCompFromTxtFile(self, aFilename);
  patchPlateformPaths(fSrcs);
  doChanged;
  fModified := false;
end;

initialization
  RegisterClasses([TCEProject]);
end.