unit fem_index;

{$mode objfpc}{$H+}

interface

uses
  fem_types, Generics.Collections;

type
  TIntIntMap = specialize TDictionary<Integer, Integer>;

// Each returns a map of Id -> array index. If the same Id appears more than
// once, the map will contain fewer entries than the array length; callers
// (chiefly fem_validate) use that mismatch to detect duplicate ids.
function IndexNodes(const Model: TModel): TIntIntMap;
function IndexMaterials(const Model: TModel): TIntIntMap;
function IndexProperties(const Model: TModel): TIntIntMap;
function IndexElements(const Model: TModel): TIntIntMap;

// Per-node dof count: 3 (translations only) unless the node is touched by
// at least one element that needs rotational dofs (currently: beam), in
// which case it's 6. Shared by fem_validate and every solver's DOF
// numbering so the two never disagree about what a node has.
function ComputeNodeDofCounts(const Model: TModel; NodeIdx: TIntIntMap): TIntArray;

implementation

function IndexNodes(const Model: TModel): TIntIntMap;
var
  i: Integer;
begin
  Result := TIntIntMap.Create;
  for i := 0 to High(Model.Nodes) do
    Result.TryAdd(Model.Nodes[i].Id, i);
end;

function IndexMaterials(const Model: TModel): TIntIntMap;
var
  i: Integer;
begin
  Result := TIntIntMap.Create;
  for i := 0 to High(Model.Materials) do
    Result.TryAdd(Model.Materials[i].Id, i);
end;

function IndexProperties(const Model: TModel): TIntIntMap;
var
  i: Integer;
begin
  Result := TIntIntMap.Create;
  for i := 0 to High(Model.Properties) do
    Result.TryAdd(Model.Properties[i].Id, i);
end;

function IndexElements(const Model: TModel): TIntIntMap;
var
  i: Integer;
begin
  Result := TIntIntMap.Create;
  for i := 0 to High(Model.Elements) do
    Result.TryAdd(Model.Elements[i].Id, i);
end;

// Per-node dof count: 3 (translations only) unless the node is touched by
// at least one element that needs rotational dofs (currently: beam), in
// which case it's 6. Shared by fem_validate and every solver's DOF
// numbering so the two never disagree about what a node has.
function ComputeNodeDofCounts(const Model: TModel; NodeIdx: TIntIntMap): TIntArray;
var
  i, j, nIdx: Integer;
  needed: Integer;
begin
  SetLength(Result, Length(Model.Nodes));
  for i := 0 to High(Result) do
    Result[i] := 3;
  for i := 0 to High(Model.Elements) do
  begin
    needed := DofsPerNodeForElementType(Model.Elements[i].ElementType);
    if needed <= 3 then Continue; // 0 (unrecognized -- validate will flag it) or 3: no widening needed
    for j := 0 to High(Model.Elements[i].NodeIds) do
      if NodeIdx.TryGetValue(Model.Elements[i].NodeIds[j], nIdx) then
        if needed > Result[nIdx] then
          Result[nIdx] := needed;
  end;
end;

end.
