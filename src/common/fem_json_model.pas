unit fem_json_model;

{$mode objfpc}{$H+}

interface

uses
  fem_types, SysUtils, Classes, fpjson, jsonparser;

// Loads and parses a model from any stream (file, stdin, ...) into a TModel.
// Raises Exception with a human-readable message on malformed JSON or
// structurally invalid input (wrong root type, array entries that aren't
// objects, etc). Semantic validation (dangling references, missing fields,
// bad values) is NOT done here -- that's fem_validate's job.
function LoadModelFromStream(Stream: TStream): TModel;

// Convenience wrapper for a named file on disk.
function LoadModelFromFile(const FileName: string): TModel;

// Convenience wrapper for stdin -- lets a solver accept "-" as its model
// argument, so an adaptor can feed it directly: `adapt_x in.txt | linstatic -`
function LoadModelFromStdin: TModel;

implementation

function GetArr(Obj: TJSONObject; const Name: string): TJSONArray;
var
  idx: Integer;
begin
  Result := nil;
  if Obj = nil then Exit;
  idx := Obj.IndexOfName(Name);
  if (idx >= 0) and (Obj.Items[idx] is TJSONArray) then
    Result := TJSONArray(Obj.Items[idx]);
end;

function GetObj(Obj: TJSONObject; const Name: string): TJSONObject;
var
  idx: Integer;
begin
  Result := nil;
  if Obj = nil then Exit;
  idx := Obj.IndexOfName(Name);
  if (idx >= 0) and (Obj.Items[idx] is TJSONObject) then
    Result := TJSONObject(Obj.Items[idx]);
end;

function ItemObj(Arr: TJSONArray; i: Integer; const Context: string): TJSONObject;
begin
  if not (Arr.Items[i] is TJSONObject) then
    raise Exception.CreateFmt('%s[%d] must be a JSON object', [Context, i]);
  Result := TJSONObject(Arr.Items[i]);
end;

function LoadModelFromStream(Stream: TStream): TModel;
var
  JData: TJSONData;
  JObj, JItem, JSolverParams: TJSONObject;
  JArr, JNodeIds, JRefVec, JConstraints, JLoads, JTerms: TJSONArray;
  JCItem, JLItem, JTItem: TJSONObject;
  i, j: Integer;
  MemStream: TMemoryStream;
  buf: array[0..4095] of Byte;
  n: LongInt;
begin
  // GetJSON() wants a stream it can size/seek, which a raw pipe (stdin)
  // doesn't support -- slurp into memory first so this works for any
  // source stream, file or pipe alike.
  MemStream := TMemoryStream.Create;
  try
    repeat
      n := Stream.Read(buf, SizeOf(buf));
      if n > 0 then MemStream.WriteBuffer(buf, n);
    until n <= 0;
    MemStream.Position := 0;

    try
      JData := GetJSON(MemStream);
    except
      on E: Exception do
        raise Exception.CreateFmt('Malformed JSON: %s', [E.Message]);
    end;
  finally
    MemStream.Free;
  end;

  try
    if not (JData is TJSONObject) then
      raise Exception.Create('Model file root must be a JSON object');
    JObj := TJSONObject(JData);

    Result.SolverName := JObj.Get('solver', '');
    Result.Units := JObj.Get('units', '');
    Result.SolverParams.Tolerance := 1e-9;

    JSolverParams := GetObj(JObj, 'solverParams');
    if Assigned(JSolverParams) then
      Result.SolverParams.Tolerance := JSolverParams.Get('tolerance', 1e-9);

    // nodes
    JArr := GetArr(JObj, 'nodes');
    if Assigned(JArr) then
    begin
      SetLength(Result.Nodes, JArr.Count);
      for i := 0 to JArr.Count - 1 do
      begin
        JItem := ItemObj(JArr, i, 'nodes');
        Result.Nodes[i].Id := JItem.Get('id', 0);
        Result.Nodes[i].X := JItem.Get('x', 0.0);
        Result.Nodes[i].Y := JItem.Get('y', 0.0);
        Result.Nodes[i].Z := JItem.Get('z', 0.0);
      end;
    end;

    // materials
    JArr := GetArr(JObj, 'materials');
    if Assigned(JArr) then
    begin
      SetLength(Result.Materials, JArr.Count);
      for i := 0 to JArr.Count - 1 do
      begin
        JItem := ItemObj(JArr, i, 'materials');
        Result.Materials[i].Id := JItem.Get('id', 0);
        Result.Materials[i].E := JItem.Get('E', 0.0);
        Result.Materials[i].HasNu := JItem.IndexOfName('nu') >= 0;
        Result.Materials[i].Nu := JItem.Get('nu', 0.0);
        Result.Materials[i].HasRho := JItem.IndexOfName('rho') >= 0;
        Result.Materials[i].Rho := JItem.Get('rho', 0.0);
      end;
    end;

    // properties
    JArr := GetArr(JObj, 'properties');
    if Assigned(JArr) then
    begin
      SetLength(Result.Properties, JArr.Count);
      for i := 0 to JArr.Count - 1 do
      begin
        JItem := ItemObj(JArr, i, 'properties');
        Result.Properties[i].Id := JItem.Get('id', 0);
        Result.Properties[i].ElementType := JItem.Get('type', '');
        Result.Properties[i].MaterialId := JItem.Get('material', 0);
        Result.Properties[i].Area := JItem.Get('area', 0.0);
        Result.Properties[i].Iy := JItem.Get('Iy', 0.0);
        Result.Properties[i].Iz := JItem.Get('Iz', 0.0);
        Result.Properties[i].J := JItem.Get('J', 0.0);
        Result.Properties[i].Thickness := JItem.Get('thickness', 0.0);
      end;
    end;

    // elements
    JArr := GetArr(JObj, 'elements');
    if Assigned(JArr) then
    begin
      SetLength(Result.Elements, JArr.Count);
      for i := 0 to JArr.Count - 1 do
      begin
        JItem := ItemObj(JArr, i, 'elements');
        Result.Elements[i].Id := JItem.Get('id', 0);
        Result.Elements[i].ElementType := JItem.Get('type', '');
        Result.Elements[i].PropertyId := JItem.Get('property', 0);
        JNodeIds := GetArr(JItem, 'nodes');
        if Assigned(JNodeIds) then
        begin
          SetLength(Result.Elements[i].NodeIds, JNodeIds.Count);
          for j := 0 to JNodeIds.Count - 1 do
            Result.Elements[i].NodeIds[j] := JNodeIds.Integers[j];
        end;
        Result.Elements[i].RefVec[0] := 0; Result.Elements[i].RefVec[1] := 0; Result.Elements[i].RefVec[2] := 0;
        JRefVec := GetArr(JItem, 'refVec');
        Result.Elements[i].HasRefVec := Assigned(JRefVec) and (JRefVec.Count = 3);
        if Result.Elements[i].HasRefVec then
        begin
          Result.Elements[i].RefVec[0] := JRefVec.Floats[0];
          Result.Elements[i].RefVec[1] := JRefVec.Floats[1];
          Result.Elements[i].RefVec[2] := JRefVec.Floats[2];
        end;
      end;
    end;

    // constraints / freedomCases -- "freedomCases" (array of named
    // {id,name,constraints}) is the new form; a flat legacy "constraints"
    // array is normalized into a single freedom case named "default".
    // Everything downstream only ever sees Result.FreedomCases.
    JArr := GetArr(JObj, 'freedomCases');
    if Assigned(JArr) then
    begin
      SetLength(Result.FreedomCases, JArr.Count);
      for i := 0 to JArr.Count - 1 do
      begin
        JItem := ItemObj(JArr, i, 'freedomCases');
        Result.FreedomCases[i].Id := JItem.Get('id', '');
        Result.FreedomCases[i].Name := JItem.Get('name', '');
        JConstraints := GetArr(JItem, 'constraints');
        if Assigned(JConstraints) then
        begin
          SetLength(Result.FreedomCases[i].Constraints, JConstraints.Count);
          for j := 0 to JConstraints.Count - 1 do
          begin
            JCItem := ItemObj(JConstraints, j, 'constraints');
            Result.FreedomCases[i].Constraints[j].NodeId := JCItem.Get('node', 0);
            Result.FreedomCases[i].Constraints[j].Dof := JCItem.Get('dof', '');
            Result.FreedomCases[i].Constraints[j].Value := JCItem.Get('value', 0.0);
          end;
        end;
      end;
    end
    else
    begin
      JArr := GetArr(JObj, 'constraints');
      SetLength(Result.FreedomCases, 1);
      Result.FreedomCases[0].Id := 'default';
      Result.FreedomCases[0].Name := 'default';
      if Assigned(JArr) then
      begin
        SetLength(Result.FreedomCases[0].Constraints, JArr.Count);
        for i := 0 to JArr.Count - 1 do
        begin
          JItem := ItemObj(JArr, i, 'constraints');
          Result.FreedomCases[0].Constraints[i].NodeId := JItem.Get('node', 0);
          Result.FreedomCases[0].Constraints[i].Dof := JItem.Get('dof', '');
          Result.FreedomCases[0].Constraints[i].Value := JItem.Get('value', 0.0);
        end;
      end;
    end;

    // loads / loadCases -- same normalization pattern as freedomCases above.
    JArr := GetArr(JObj, 'loadCases');
    if Assigned(JArr) then
    begin
      SetLength(Result.LoadCases, JArr.Count);
      for i := 0 to JArr.Count - 1 do
      begin
        JItem := ItemObj(JArr, i, 'loadCases');
        Result.LoadCases[i].Id := JItem.Get('id', '');
        Result.LoadCases[i].Name := JItem.Get('name', '');
        JLoads := GetArr(JItem, 'loads');
        if Assigned(JLoads) then
        begin
          SetLength(Result.LoadCases[i].Loads, JLoads.Count);
          for j := 0 to JLoads.Count - 1 do
          begin
            JLItem := ItemObj(JLoads, j, 'loads');
            Result.LoadCases[i].Loads[j].NodeId := JLItem.Get('node', 0);
            Result.LoadCases[i].Loads[j].Dof := JLItem.Get('dof', '');
            Result.LoadCases[i].Loads[j].Value := JLItem.Get('value', 0.0);
          end;
        end;
      end;
    end
    else
    begin
      JArr := GetArr(JObj, 'loads');
      SetLength(Result.LoadCases, 1);
      Result.LoadCases[0].Id := 'default';
      Result.LoadCases[0].Name := 'default';
      if Assigned(JArr) then
      begin
        SetLength(Result.LoadCases[0].Loads, JArr.Count);
        for i := 0 to JArr.Count - 1 do
        begin
          JItem := ItemObj(JArr, i, 'loads');
          Result.LoadCases[0].Loads[i].NodeId := JItem.Get('node', 0);
          Result.LoadCases[0].Loads[i].Dof := JItem.Get('dof', '');
          Result.LoadCases[0].Loads[i].Value := JItem.Get('value', 0.0);
        end;
      end;
    end;

    // combinations: a named linear combination of load case results,
    // evaluated within one freedom case. FreedomCaseId is left blank if
    // omitted in the JSON -- fem_validate resolves a blank to the model's
    // sole freedom case if there's exactly one, and rejects it as
    // ambiguous otherwise, rather than the loader silently guessing.
    JArr := GetArr(JObj, 'combinations');
    if Assigned(JArr) then
    begin
      SetLength(Result.Combinations, JArr.Count);
      for i := 0 to JArr.Count - 1 do
      begin
        JItem := ItemObj(JArr, i, 'combinations');
        Result.Combinations[i].Id := JItem.Get('id', '');
        Result.Combinations[i].Name := JItem.Get('name', '');
        Result.Combinations[i].FreedomCaseId := JItem.Get('freedomCase', '');
        JTerms := GetArr(JItem, 'terms');
        if Assigned(JTerms) then
        begin
          SetLength(Result.Combinations[i].Terms, JTerms.Count);
          for j := 0 to JTerms.Count - 1 do
          begin
            JTItem := ItemObj(JTerms, j, 'terms');
            Result.Combinations[i].Terms[j].LoadCaseId := JTItem.Get('loadCase', '');
            Result.Combinations[i].Terms[j].Factor := JTItem.Get('factor', 0.0);
          end;
        end;
      end;
    end;

  finally
    JData.Free;
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
