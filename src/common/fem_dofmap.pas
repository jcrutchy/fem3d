unit fem_dofmap;

{$mode objfpc}{$H+}

interface

uses
  fem_types, fem_index, SysUtils;

type
  // Everything a solver needs to go from (node, dof-name) to a place in
  // its global system, and back. Built once per model; every solver uses
  // the same construction so their DOF numbering never disagrees.
  TDofMap = record
    NumNodes: Integer;
    NDOF: Integer;               // total dofs before constraint elimination
    NEQ: Integer;                // free (unconstrained) dof count
    NodeDofCounts: TIntArray;    // [0..NumNodes-1] -> 3 or 6
    NodeDofStart: TIntArray;     // [0..NumNodes] -> first global dof (1-based) for this node
    GlobalToEq: TIntArray;       // [1..NDOF] -> equation number 1..NEQ, or 0 if constrained
    Prescribed: TDoubleArray;    // [1..NDOF] -> prescribed displacement/rotation (0 for free dofs)
  end;

// Builds the dof map for one freedom case's constraints against this
// model's elements/nodes. Solvers call this once per freedom case (see
// docs/model_format.md on load/freedom cases) -- constraints, not loads,
// determine dof numbering, so this has no load case involved at all.
function BuildDofMap(const Model: TModel; NodeIdx: TIntIntMap;
  const Constraints: TConstraintArray): TDofMap;

function GlobalDof(const Map: TDofMap; NodeIndex, LocalOffset: Integer): Integer; inline;

// 1-based global dof list for an element (6 entries for a truss, 12 for a
// beam), in the same order its local stiffness/mass matrix uses: node1's
// dofs, then node2's.
function ElementGlobalDofs(const Map: TDofMap; NodeIdx: TIntIntMap; const el: TElement): TIntArray;

implementation

function BuildDofMap(const Model: TModel; NodeIdx: TIntIntMap;
  const Constraints: TConstraintArray): TDofMap;
var
  i, gi: Integer;
begin
  Result.NumNodes := Length(Model.Nodes);
  Result.NodeDofCounts := ComputeNodeDofCounts(Model, NodeIdx);

  SetLength(Result.NodeDofStart, Result.NumNodes + 1);
  Result.NodeDofStart[0] := 1;
  for i := 0 to Result.NumNodes - 1 do
    Result.NodeDofStart[i + 1] := Result.NodeDofStart[i] + Result.NodeDofCounts[i];
  Result.NDOF := Result.NodeDofStart[Result.NumNodes] - 1;

  SetLength(Result.GlobalToEq, Result.NDOF + 1);
  SetLength(Result.Prescribed, Result.NDOF + 1);
  for i := 1 to Result.NDOF do
  begin
    Result.GlobalToEq[i] := 1; // placeholder "free" marker, replaced with real eq numbers below
    Result.Prescribed[i] := 0.0;
  end;
  for i := 0 to High(Constraints) do
  begin
    gi := Result.NodeDofStart[NodeIdx[Constraints[i].NodeId]] + DofOffset(Constraints[i].Dof);
    Result.GlobalToEq[gi] := 0;
    Result.Prescribed[gi] := Constraints[i].Value;
  end;

  Result.NEQ := 0;
  for i := 1 to Result.NDOF do
    if Result.GlobalToEq[i] <> 0 then
    begin
      Inc(Result.NEQ);
      Result.GlobalToEq[i] := Result.NEQ;
    end;
end;

function GlobalDof(const Map: TDofMap; NodeIndex, LocalOffset: Integer): Integer; inline;
begin
  Result := Map.NodeDofStart[NodeIndex] + LocalOffset;
end;

function ElementGlobalDofs(const Map: TDofMap; NodeIdx: TIntIntMap; const el: TElement): TIntArray;
var
  dpn, nIdx1, nIdx2, k: Integer;
begin
  dpn := DofsPerNodeForElementType(el.ElementType);
  nIdx1 := NodeIdx[el.NodeIds[0]];
  nIdx2 := NodeIdx[el.NodeIds[1]];
  SetLength(Result, 2 * dpn + 1);
  for k := 0 to dpn - 1 do
  begin
    Result[k + 1]       := GlobalDof(Map, nIdx1, k);
    Result[k + 1 + dpn] := GlobalDof(Map, nIdx2, k);
  end;
end;

end.
