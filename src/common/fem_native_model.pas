unit fem_native_model;

{$mode objfpc}{$H+}

interface

uses
  fem_types, SysUtils, Classes;

// Loads and parses a model from any stream (file, stdin, ...) in the
// compact native format (see docs/native_format.md) into a TModel.
// Same three-function shape as fem_json_model, so a solver can switch
// between them by changing one line in its uses clause.
function LoadModelFromStream(Stream: TStream): TModel;
function LoadModelFromFile(const FileName: string): TModel;
function LoadModelFromStdin: TModel;

implementation

type
  TFieldArray = array of string;

var
  GFS: TFormatSettings;

function SplitFields(const Line: string): TFieldArray;
var
  Parts: TStringList;
  i: Integer;
begin
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := ',';
    Parts.DelimitedText := Line;
    SetLength(Result, Parts.Count);
    for i := 0 to Parts.Count - 1 do
      Result[i] := Trim(Parts[i]);
  finally
    Parts.Free;
  end;
end;

function F2S(const F: TFieldArray; Idx: Integer; const Default: string = ''): string;
begin
  if (Idx >= 0) and (Idx < Length(F)) then Result := F[Idx] else Result := Default;
end;

function F2I(const F: TFieldArray; Idx: Integer; Default: Integer = 0): Integer;
var
  s: string;
begin
  s := F2S(F, Idx);
  if (s = '') or (s = '-') then Result := Default
  else if not TryStrToInt(s, Result) then Result := Default;
end;

function F2D(const F: TFieldArray; Idx: Integer; Default: Double = 0.0): Double;
var
  s: string;
begin
  s := F2S(F, Idx);
  if (s = '') or (s = '-') then Result := Default
  else if not TryStrToFloat(s, Result, GFS) then Result := Default;
end;

function F2HasVal(const F: TFieldArray; Idx: Integer): Boolean;
var
  s: string;
begin
  s := F2S(F, Idx);
  Result := (s <> '') and (s <> '-');
end;

// Parses a "[NAME]" or "[NAME arg]" section header line. Returns False if
// Line isn't a section header at all (blank/comment/data lines fall through).
function ParseSectionHeader(const Line: string; out Name, Arg: string): Boolean;
var
  inner: string;
  sp: Integer;
begin
  Result := False;
  if (Length(Line) < 2) or (Line[1] <> '[') or (Line[Length(Line)] <> ']') then Exit;
  inner := Trim(Copy(Line, 2, Length(Line) - 2));
  sp := Pos(' ', inner);
  if sp > 0 then
  begin
    Name := UpperCase(Trim(Copy(inner, 1, sp - 1)));
    Arg := Trim(Copy(inner, sp + 1, Length(inner)));
  end
  else
  begin
    Name := UpperCase(inner);
    Arg := '';
  end;
  Result := True;
end;

function LoadModelFromStream(Stream: TStream): TModel;
var
  SL: TStringList;
  raw, line, secName, secArg, key, valStr: string;
  hdrName, hdrArg: string; // separate from secName/secArg: ParseSectionHeader's `out` params
                            // get cleared on every call, even a False (non-header-line) one --
                            // must not let that clobber the persistent "current section" state.
  eqPos, i: Integer;
  F: TFieldArray;

  NodeCount, MatCount, PropCount, ElemCount: Integer;
  fcIdx, lcIdx, combIdx: Integer;
  curFcConstraints, curLcLoads: Integer; // running count within the current [FREEDOMCASE x]/[LOADCASE x] section
  MemStream: TMemoryStream;
  sbuf: array[0..4095] of Byte;
  n: LongInt;

  procedure GrowNodes; begin Inc(NodeCount); SetLength(Result.Nodes, NodeCount); end;
  procedure GrowMats;  begin Inc(MatCount);  SetLength(Result.Materials, MatCount); end;
  procedure GrowProps; begin Inc(PropCount); SetLength(Result.Properties, PropCount); end;
  procedure GrowElems; begin Inc(ElemCount); SetLength(Result.Elements, ElemCount); end;

begin
  GFS := DefaultFormatSettings;
  GFS.DecimalSeparator := '.';

  NodeCount := 0; MatCount := 0; PropCount := 0; ElemCount := 0;
  SetLength(Result.FreedomCases, 0);
  SetLength(Result.LoadCases, 0);
  SetLength(Result.Combinations, 0);
  Result.SolverParams.Tolerance := 1e-9;
  Result.SolverParams.HasResultsFile := False;

  secName := '';
  fcIdx := -1; lcIdx := -1; combIdx := -1;
  curFcConstraints := 0; curLcLoads := 0;

  SL := TStringList.Create;
  try
    // TStringList.LoadFromStream (like fpjson's GetJSON) doesn't reliably
    // handle a stream that can't report .Size, which a raw pipe (stdin)
    // can't -- slurp into memory first, same fix as fem_json_model.
    begin
      MemStream := TMemoryStream.Create;
      try
        repeat
          n := Stream.Read(sbuf, SizeOf(sbuf));
          if n > 0 then MemStream.WriteBuffer(sbuf, n);
        until n <= 0;
        MemStream.Position := 0;
        SL.LoadFromStream(MemStream);
      finally
        MemStream.Free;
      end;
    end;

    for i := 0 to SL.Count - 1 do
    begin
      raw := SL[i];
      line := Trim(raw);
      if (line = '') or (line[1] = '#') or (line[1] = ';') then Continue;

      if ParseSectionHeader(line, hdrName, hdrArg) then
      begin
        secName := hdrName;
        secArg := hdrArg;
        if secName = 'FREEDOMCASE' then
        begin
          fcIdx := Length(Result.FreedomCases);
          SetLength(Result.FreedomCases, fcIdx + 1);
          Result.FreedomCases[fcIdx].Id := secArg;
          Result.FreedomCases[fcIdx].Name := secArg;
          curFcConstraints := 0;
        end
        else if secName = 'LOADCASE' then
        begin
          lcIdx := Length(Result.LoadCases);
          SetLength(Result.LoadCases, lcIdx + 1);
          Result.LoadCases[lcIdx].Id := secArg;
          Result.LoadCases[lcIdx].Name := secArg;
          curLcLoads := 0;
        end
        else if secName = 'COMBINATION' then
        begin
          combIdx := Length(Result.Combinations);
          SetLength(Result.Combinations, combIdx + 1);
          Result.Combinations[combIdx].Id := secArg;
          Result.Combinations[combIdx].Name := secArg;
          Result.Combinations[combIdx].FreedomCaseId := '';
        end;
        Continue;
      end;

      // --- data line: dispatch on current section ---
      if secName = 'HEADER' then
      begin
        eqPos := Pos('=', line);
        if eqPos > 0 then
        begin
          key := UpperCase(Trim(Copy(line, 1, eqPos - 1)));
          valStr := Trim(Copy(line, eqPos + 1, Length(line)));
          if key = 'SOLVER' then Result.SolverName := valStr
          else if key = 'UNITS' then Result.Units := valStr;
        end;
      end

      else if secName = 'NODES' then
      begin
        F := SplitFields(line);
        GrowNodes;
        Result.Nodes[NodeCount - 1].Id := F2I(F, 0);
        Result.Nodes[NodeCount - 1].X := F2D(F, 1);
        Result.Nodes[NodeCount - 1].Y := F2D(F, 2);
        Result.Nodes[NodeCount - 1].Z := F2D(F, 3);
      end

      else if secName = 'MATERIALS' then
      begin
        F := SplitFields(line);
        GrowMats;
        Result.Materials[MatCount - 1].Id := F2I(F, 0);
        Result.Materials[MatCount - 1].E := F2D(F, 1);
        Result.Materials[MatCount - 1].HasNu := F2HasVal(F, 2);
        Result.Materials[MatCount - 1].Nu := F2D(F, 2);
        Result.Materials[MatCount - 1].HasRho := F2HasVal(F, 3);
        Result.Materials[MatCount - 1].Rho := F2D(F, 3);
      end

      else if secName = 'PROPERTIES' then
      begin
        // id, type, material, area[, Iy, Iz, J]
        F := SplitFields(line);
        GrowProps;
        Result.Properties[PropCount - 1].Id := F2I(F, 0);
        Result.Properties[PropCount - 1].ElementType := LowerCase(F2S(F, 1));
        Result.Properties[PropCount - 1].MaterialId := F2I(F, 2);
        Result.Properties[PropCount - 1].Area := F2D(F, 3);
        Result.Properties[PropCount - 1].Iy := F2D(F, 4);
        Result.Properties[PropCount - 1].Iz := F2D(F, 5);
        Result.Properties[PropCount - 1].J := F2D(F, 6);
      end

      else if secName = 'ELEMENTS' then
      begin
        // id, type, node1, node2, property[, refX, refY, refZ]
        F := SplitFields(line);
        GrowElems;
        Result.Elements[ElemCount - 1].Id := F2I(F, 0);
        Result.Elements[ElemCount - 1].ElementType := LowerCase(F2S(F, 1));
        SetLength(Result.Elements[ElemCount - 1].NodeIds, 2);
        Result.Elements[ElemCount - 1].NodeIds[0] := F2I(F, 2);
        Result.Elements[ElemCount - 1].NodeIds[1] := F2I(F, 3);
        Result.Elements[ElemCount - 1].PropertyId := F2I(F, 4);
        Result.Elements[ElemCount - 1].HasRefVec := F2HasVal(F, 5) or F2HasVal(F, 6) or F2HasVal(F, 7);
        Result.Elements[ElemCount - 1].RefVec[0] := F2D(F, 5);
        Result.Elements[ElemCount - 1].RefVec[1] := F2D(F, 6);
        Result.Elements[ElemCount - 1].RefVec[2] := F2D(F, 7);
      end

      else if secName = 'FREEDOMCASE' then
      begin
        if fcIdx < 0 then Continue; // malformed file; fem_validate will catch the fallout
        F := SplitFields(line);
        Inc(curFcConstraints);
        SetLength(Result.FreedomCases[fcIdx].Constraints, curFcConstraints);
        Result.FreedomCases[fcIdx].Constraints[curFcConstraints - 1].NodeId := F2I(F, 0);
        Result.FreedomCases[fcIdx].Constraints[curFcConstraints - 1].Dof := LowerCase(F2S(F, 1));
        Result.FreedomCases[fcIdx].Constraints[curFcConstraints - 1].Value := F2D(F, 2);
      end

      else if secName = 'LOADCASE' then
      begin
        if lcIdx < 0 then Continue;
        F := SplitFields(line);
        Inc(curLcLoads);
        SetLength(Result.LoadCases[lcIdx].Loads, curLcLoads);
        Result.LoadCases[lcIdx].Loads[curLcLoads - 1].NodeId := F2I(F, 0);
        Result.LoadCases[lcIdx].Loads[curLcLoads - 1].Dof := LowerCase(F2S(F, 1));
        Result.LoadCases[lcIdx].Loads[curLcLoads - 1].Value := F2D(F, 2);
      end

      else if secName = 'COMBINATION' then
      begin
        if combIdx < 0 then Continue;
        eqPos := Pos('=', line);
        if eqPos > 0 then
        begin
          key := UpperCase(Trim(Copy(line, 1, eqPos - 1)));
          valStr := Trim(Copy(line, eqPos + 1, Length(line)));
          if key = 'FREEDOMCASE' then
            Result.Combinations[combIdx].FreedomCaseId := valStr
          else if key = 'TERMS' then
          begin
            // Terms=DL:1.2,LL:1.6
            F := SplitFields(valStr);
            SetLength(Result.Combinations[combIdx].Terms, Length(F));
            for eqPos := 0 to High(F) do
            begin
              key := Trim(Copy(F[eqPos], 1, Pos(':', F[eqPos]) - 1));
              valStr := Trim(Copy(F[eqPos], Pos(':', F[eqPos]) + 1, Length(F[eqPos])));
              Result.Combinations[combIdx].Terms[eqPos].LoadCaseId := key;
              if not TryStrToFloat(valStr, Result.Combinations[combIdx].Terms[eqPos].Factor, GFS) then
                Result.Combinations[combIdx].Terms[eqPos].Factor := 0.0;
            end;
          end;
        end;
      end

      else if secName = 'SOLVERPARAMS' then
      begin
        eqPos := Pos('=', line);
        if eqPos > 0 then
        begin
          key := UpperCase(Trim(Copy(line, 1, eqPos - 1)));
          valStr := Trim(Copy(line, eqPos + 1, Length(line)));
          if key = 'TOLERANCE' then
            Result.SolverParams.Tolerance := StrToFloatDef(valStr, 1e-9, GFS)
          else if key = 'RESULTSFILE' then
          begin
            Result.SolverParams.HasResultsFile := True;
            Result.SolverParams.ResultsFile := valStr;
          end;
        end;
      end;
    end;
  finally
    SL.Free;
  end;

  // Legacy-format compatibility: a file with no [FREEDOMCASE ...] / [LOADCASE
  // ...] sections at all still needs at least one of each (empty), same as
  // the JSON loader's normalization -- fem_validate treats "no freedom
  // cases" as a bug, not "zero constraints", so this keeps that invariant.
  if Length(Result.FreedomCases) = 0 then
  begin
    SetLength(Result.FreedomCases, 1);
    Result.FreedomCases[0].Id := 'default';
    Result.FreedomCases[0].Name := 'default';
  end;
  if Length(Result.LoadCases) = 0 then
  begin
    SetLength(Result.LoadCases, 1);
    Result.LoadCases[0].Id := 'default';
    Result.LoadCases[0].Name := 'default';
  end;
end;

function LoadModelFromFile(const FileName: string): TModel;
var
  FS: TFileStream;
begin
  if not FileExists(FileName) then
    raise Exception.CreateFmt('Model file not found: %s', [FileName]);
  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    try
      Result := LoadModelFromStream(FS);
    except
      on E: Exception do
        raise Exception.CreateFmt('%s (in %s)', [E.Message, FileName]);
    end;
  finally
    FS.Free;
  end;
end;

function LoadModelFromStdin: TModel;
var
  HS: THandleStream;
begin
  HS := THandleStream.Create(StdInputHandle);
  try
    Result := LoadModelFromStream(HS);
  finally
    HS.Free;
  end;
end;

end.
