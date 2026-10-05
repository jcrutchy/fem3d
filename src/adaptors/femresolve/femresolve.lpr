program femresolve;

{$mode objfpc}{$H+}

// Reads a .femref model (a .fem that may refer to a section file or a section
// catalogue) and writes the plain .fem model, with every referenced value copied
// in, to stdout.  Solvers never read references; this is where they are resolved.
//
//   femresolve model.femref > model.fem
//   femresolve model.femref | linstatic -
//
// See docs/femref.md.

uses
  SysUtils, Classes, fem_resolve;

procedure Usage;
begin
  WriteLn(StdErr, 'Usage: femresolve <model.femref | -> [--base DIR] [--length-unit mm|cm|m|in|ft]');
  WriteLn(StdErr, '  Writes the model with all references resolved (a plain .fem) to stdout.');
  WriteLn(StdErr, '  --base DIR         folder that relative source paths are taken from');
  WriteLn(StdErr, '                     (default: the folder of the input file, or the current folder for stdin)');
  WriteLn(StdErr, '  --length-unit U    the model''s length unit, instead of reading it from [HEADER] Units=');
  WriteLn(StdErr, 'Exit codes: 0 ok, 1 a reference could not be resolved, 2 usage error, 3 input could not be read.');
end;

var
  InPath, BaseDir, LenUnit, SourceName: string;
  i: Integer;
  Input, Output, Warnings: TStringList;
  Raw: string;
  Bytes: TBytes;
  Stream: TStream;
  OutStream: THandleStream;
  Text: string;
begin
  InPath := '';
  BaseDir := '';
  LenUnit := '';
  i := 1;
  while i <= ParamCount do
  begin
    if ParamStr(i) = '--base' then
    begin
      if i = ParamCount then begin Usage; Halt(2); end;
      BaseDir := ParamStr(i + 1);
      Inc(i, 2);
    end
    else if ParamStr(i) = '--length-unit' then
    begin
      if i = ParamCount then begin Usage; Halt(2); end;
      LenUnit := ParamStr(i + 1);
      Inc(i, 2);
    end
    else if (Length(ParamStr(i)) > 1) and (ParamStr(i)[1] = '-') then
    begin
      WriteLn(StdErr, 'Unknown option: ', ParamStr(i));
      Usage;
      Halt(2);
    end
    else if InPath = '' then
    begin
      InPath := ParamStr(i);
      Inc(i);
    end
    else
    begin
      Usage;
      Halt(2);
    end;
  end;
  if InPath = '' then begin Usage; Halt(2); end;

  Input := TStringList.Create;
  Output := TStringList.Create;
  Warnings := TStringList.Create;
  try
    try
      if InPath = '-' then
      begin
        Stream := THandleStream.Create(StdInputHandle);
        try
          SetLength(Raw, 0);
          SetLength(Bytes, 0);
          Input.LoadFromStream(Stream);
        finally
          Stream.Free;
        end;
        SourceName := 'stdin';
        if BaseDir = '' then BaseDir := GetCurrentDir;
      end
      else
      begin
        Input.LoadFromFile(InPath);
        SourceName := ExtractFileName(InPath);
        if BaseDir = '' then BaseDir := ExtractFilePath(ExpandFileName(InPath));
      end;
    except
      on E: Exception do
      begin
        WriteLn(StdErr, Format('Could not read "%s": %s', [InPath, E.Message]));
        Halt(3);
      end;
    end;

    try
      ResolveFemref(Input, BaseDir, SourceName, LenUnit, Output, Warnings);
    except
      on E: EResolveError do
      begin
        WriteLn(StdErr, Format('femresolve: %s: %s', [SourceName, E.Message]));
        Halt(1);
      end;
    end;

    for i := 0 to Warnings.Count - 1 do
      WriteLn(StdErr, 'femresolve: warning: ', Warnings[i]);

    Output.LineBreak := #10;
    Text := Output.Text;
    OutStream := THandleStream.Create(StdOutputHandle);
    try
      if Length(Text) > 0 then OutStream.WriteBuffer(Text[1], Length(Text));
    finally
      OutStream.Free;
    end;
  finally
    Warnings.Free;
    Output.Free;
    Input.Free;
  end;
  Halt(0);
end.
