program adapt_json;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, fem_types, fem_json_model, fem_native_writer;

var
  Model: TModel;
  InPath: string;
  OutStream: THandleStream;
begin
  if ParamCount <> 1 then
  begin
    WriteLn(StdErr, 'Usage: adapt_json <model.json | ->');
    WriteLn(StdErr, '  Converts a JSON model file into the compact native format on stdout.');
    WriteLn(StdErr, '  adapt_json old_model.json > model.fem');
    Halt(1);
  end;
  InPath := ParamStr(1);

  try
    if InPath = '-' then
      Model := LoadModelFromStdin
    else
      Model := LoadModelFromFile(InPath);
  except
    on E: Exception do
    begin
      WriteLn(StdErr, Format('Could not load "%s": %s', [InPath, E.Message]));
      Halt(2);
    end;
  end;

  OutStream := THandleStream.Create(StdOutputHandle);
  try
    WriteModelToStream(Model, OutStream);
  finally
    OutStream.Free;
  end;
  Halt(0);
end.

