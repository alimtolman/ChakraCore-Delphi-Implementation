unit ChakraCoreEngine;

interface

uses
  Classes, SysUtils,
  ChakraCore, ChakraCommon, ChakraCoreClasses, ChakraCoreUtils;

type
  TJsValueRef = JsValueRef;

  TArgs = PJsValueRefArray;

  TNativeFunction = function(callee: TJsValueRef; isConstructCall: Boolean; arguments: TArgs; argumentCount: Word; callbackState: Pointer): TJsValueRef;

  TChakraCoreEngine = class
  private
    FContext: TChakraCoreContext;
    FDefineGlobalThis: Boolean;
    FDocumentName: string;
    FRuntime: TChakraCoreRuntime;
    FScript: TStringList;
    (* functions *)
    function FindPath(const path: TArray<string>): JsValueRef;
  public
    constructor Create();
    destructor Destroy(); override;
    procedure Execute(const script: string = '');
    function GetVarAsString(const varName: string): string;
    function GetVarFromEvaluate(const script: string = ''): string;
    procedure SetNewObject(const varName: string);
    procedure SetVarBoolean(const varName: string; const varValue: Boolean);
    procedure SetVarFromEvaluate(const varName: string; const script: string);
    procedure SetVarFromScript(const varName, definedVarName: string);
    procedure SetVarInteger(const varName: string; const varValue: Integer);
    procedure SetVarLong(const varName: string; const varValue: Int64);
    procedure SetVarNull(const varName: string);
    procedure SetVarString(const varName, varValue: string);
    procedure SetNativeFunction(const ContextPath: string; const FunctionName: string; FunctionPtr: TNativeFunction);
    (* properties *)
    property DefineGlobalThis: Boolean read FDefineGlobalThis write FDefineGlobalThis;
    property DocumentName: string read FDocumentName write FDocumentName;
    property Script: TStringList read FScript write FScript;
  end;

(* Helpers *)

function JsStringToString(Value: TJsValueRef): string;

function GetUndefined(): TJsValueRef;

implementation

function JsStringToString(Value: TJsValueRef): string;
var
  StringValue: JsValueRef;
  StringLength: size_t;
  ResultString: UTF8String;
begin
  ResultString := '';
  StringValue := JsValueAsJsString(Value);
  StringLength := 0;
  ChakraCoreCheck(JsCopyString(StringValue, nil, 0, @StringLength));

  if StringLength > 0 then
  begin
    SetLength(ResultString, StringLength);
    ChakraCoreCheck(JsCopyString(StringValue, PAnsiChar(ResultString), StringLength, nil));
  end;

  Result := string(ResultString);
end;

function GetUndefined(): TJsValueRef;
begin
  Result := JsUndefinedValue();
end;

{---------- TChakraCoreEngine ----------}

constructor TChakraCoreEngine.Create();
begin
  inherited Create();

  FDefineGlobalThis := True;
  FDocumentName := '<anonymous>';
  FRuntime := TChakraCoreRuntime.Create();
  FContext := TChakraCoreContext.Create(FRuntime);
  FScript := TStringList.Create();

  FContext.Activate();
end;

destructor TChakraCoreEngine.Destroy();
begin
  FContext.Destroy();
  FRuntime.Destroy();
  FScript.Destroy();

  inherited Destroy();
end;

(* private *)

function TChakraCoreEngine.FindPath(const path: TArray<string>): JsValueRef;
var
  i: Integer;
  obj: JsValueRef;
begin
  if Length(path) = 1 then
    obj := FContext.Global
  else
  begin
    obj := JsGetProperty(FContext.Global, path[0]);

    for i := 1 to Length(path) - 2 do
      obj := JsGetProperty(obj, path[i]);
  end;

  Result := obj;
end;

(* public *)

procedure TChakraCoreEngine.Execute(const script: string = '');
begin
  if FDefineGlobalThis then
    JsSetProperty(FContext.Global, 'globalThis', FContext.RunScript('this;', FDocumentName), True);

  if script = '' then
    FContext.RunScript(FScript.Text, FDocumentName)
  else
    FContext.RunScript(script, FDocumentName);
end;

function TChakraCoreEngine.GetVarAsString(const varName: string): string;
var
  path: TArray<string>;
  r: JsValueRef;
begin
  path := varName.Split(['.']);
  r := JsGetProperty(FindPath(path), path[Length(path) - 1]);

  Result := JsStringToUnicodeString(r);
end;

function TChakraCoreEngine.GetVarFromEvaluate(const script: string = ''): string;
var
  r: JsValueRef;
begin
  r := FContext.RunScript(script, FDocumentName);

  Result := JsStringToUnicodeString(r);
end;

procedure TChakraCoreEngine.SetNewObject(const varName: string);
var
  obj: JsValueRef;
  path: TArray<string>;
  i: Integer;
begin
  path := varName.Split(['.']);

  if not JsHasProperty(FContext.Global, path[0]) then
    JsSetProperty(FContext.Global, path[0], JsCreateObject(), True);

  obj := JsGetProperty(FContext.Global, path[0]);

  for i := 1 to Length(path) - 1 do
  begin
    if not JsHasProperty(obj, path[i]) then
      JsSetProperty(obj, path[i], JsCreateObject(), True);

    obj := JsGetProperty(obj, path[i]);
  end;
end;

procedure TChakraCoreEngine.SetVarBoolean(const varName: string; const varValue: Boolean);
var
  path: TArray<string>;
begin
  path := varName.Split(['.']);

  JsSetProperty(FindPath(path), path[Length(path) - 1], BooleanToJsBoolean(varValue), True);
end;

procedure TChakraCoreEngine.SetVarFromEvaluate(const varName: string; const script: string);
var
  path: TArray<string>;
begin
  path := varName.Split(['.']);

  JsSetProperty(FindPath(path), path[Length(path) - 1], FContext.RunScript(script, FDocumentName), True);
end;

procedure TChakraCoreEngine.SetVarFromScript(const varName, definedVarName: string);
var
  path, path2: TArray<string>;
begin
  path := varName.Split(['.']);
  path2 := definedVarName.Split(['.']);

  JsSetProperty(FindPath(path), path[Length(path) - 1], JsGetProperty(FindPath(path2), path2[Length(path2) - 1]), True);
end;

procedure TChakraCoreEngine.SetVarInteger(const varName: string; const varValue: Integer);
var
  path: TArray<string>;
begin
  path := varName.Split(['.']);

  JsSetProperty(FindPath(path), path[Length(path) - 1], IntToJsNumber(varValue), True);
end;

procedure TChakraCoreEngine.SetVarLong(const varName: string; const varValue: Int64);
var
  path: TArray<string>;
  longValue: JsValueRef;
begin
  path := varName.Split(['.']);

  JsConvertValueToNumber(StringToJsString(IntToStr(varValue)), longValue);
  JsSetProperty(FindPath(path), path[Length(path) - 1], longValue, True);
end;

procedure TChakraCoreEngine.SetVarNull(const varName: string);
var
  path: TArray<string>;
begin
  path := varName.Split(['.']);

  JsSetProperty(FindPath(path), path[Length(path) - 1], JsNullValue, True);
end;

procedure TChakraCoreEngine.SetVarString(const varName, varValue: string);
var
  path: TArray<string>;
begin
  path := varName.Split(['.']);

  JsSetProperty(FindPath(path), path[Length(path) - 1], StringToJsString(varValue), True);
end;

procedure TChakraCoreEngine.SetNativeFunction(const ContextPath: string; const FunctionName: string; FunctionPtr: TNativeFunction);
var
  path: TArray<string>;
begin
  path := ContextPath.Split(['.']);

  JsSetCallback(FindPath(path), FunctionName, @FunctionPtr, nil);
end;

end.
