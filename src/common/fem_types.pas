unit fem_types;

{$mode objfpc}{$H+}

interface

type
  TNode = record
    Id: Integer;
    X, Y, Z: Double;
  end;

  TMaterial = record
    Id: Integer;
    E: Double;             // Young's modulus
    HasNu: Boolean;        // Poisson's ratio given? (only required for beam elements, used to derive G)
    Nu: Double;
    HasRho: Boolean;       // density given? (only required by solvers that need mass, e.g. modal)
    Rho: Double;
  end;

  TProperty = record
    Id: Integer;
    ElementType: string;   // 'truss' | 'beam' | 'shellq4'
    MaterialId: Integer;
    Area: Double;          // cross-sectional area (truss, beam)
    Iy, Iz: Double;        // second moment of area about local y / local z axis (beam)
    J: Double;             // torsion constant (beam)
    Thickness: Double;     // shell thickness (shellq4)
  end;

  TElement = record
    Id: Integer;
    ElementType: string;
    NodeIds: array of Integer;
    PropertyId: Integer;
    HasRefVec: Boolean;    // beam only: explicit orientation reference vector given?
    RefVec: array[0..2] of Double;
  end;

  TConstraint = record
    NodeId: Integer;
    Dof: string;           // 'x' | 'y' | 'z' | 'rx' | 'ry' | 'rz'
    Value: Double;         // prescribed displacement/rotation (0 = fixed)
  end;

  TLoad = record
    NodeId: Integer;
    Dof: string;           // 'x' | 'y' | 'z' | 'rx' | 'ry' | 'rz'
    Value: Double;         // applied force/moment
  end;

  TSolverParams = record
    Tolerance: Double;
    HasResultsFile: Boolean;
    ResultsFile: string; // if set, solver writes results here instead of stdout
  end;

  TNodeArray       = array of TNode;
  TMaterialArray   = array of TMaterial;
  TPropertyArray   = array of TProperty;
  TElementArray    = array of TElement;
  TConstraintArray = array of TConstraint;
  TLoadArray       = array of TLoad;

  // A freedom case is a named set of constraints -- Strand7's term for
  // "one particular set of supports", since the same structure is
  // sometimes analyzed under different support conditions (construction
  // stage vs. final, say). Most models have exactly one, named "default"
  // whether the JSON used the new "freedomCases" array or just a flat
  // legacy "constraints" array -- fem_json_model normalizes either way,
  // so nothing downstream of the loader ever sees the old flat form.
  TFreedomCase = record
    Id: string;
    Name: string;
    Constraints: TConstraintArray;
  end;
  TFreedomCaseArray = array of TFreedomCase;

  // A load case is a named set of loads, same idea. Also always at least
  // one ("default") after loading, legacy "loads" array included.
  TLoadCase = record
    Id: string;
    Name: string;
    Loads: TLoadArray;
  end;
  TLoadCaseArray = array of TLoadCase;

  // A combination is a linear combination of load case RESULTS (valid
  // because linear-static analysis is linear: superposition holds), all
  // evaluated within one freedom case (different freedom cases have
  // different constraints and so aren't combinable -- they're not even
  // the same set of free dofs in general).
  TCombinationTerm = record
    LoadCaseId: string;
    Factor: Double;
  end;
  TCombination = record
    Id: string;
    Name: string;
    FreedomCaseId: string; // resolved by the loader if omitted and there's exactly one freedom case
    Terms: array of TCombinationTerm;
  end;
  TCombinationArray = array of TCombination;

  TModel = record
    SolverName: string;
    Units: string;
    Nodes: TNodeArray;
    Materials: TMaterialArray;
    Properties: TPropertyArray;
    Elements: TElementArray;
    FreedomCases: TFreedomCaseArray;
    LoadCases: TLoadCaseArray;
    Combinations: TCombinationArray;
    SolverParams: TSolverParams;
  end;

  TDoubleArray = array of Double;
  TIntArray    = array of Integer;

  // Generic dense NxN matrix, 1-based (index 0 unused, so callers can use
  // natural 1..N loops). Shared by element stiffness matrices (fem_elements)
  // and the eigensolver (fem_eigen) -- both are "just a dense matrix" once
  // you're past assembling them.
  TDenseMatrix = array of array of Double;

function NewDenseMatrix(N: Integer): TDenseMatrix;

// DOF helpers. Offsets 0..2 are translations (x,y,z); 3..5 are rotations
// (rx,ry,rz) and only meaningful at nodes that carry rotational dofs
// (i.e. touched by at least one beam element).
function DofOffset(const Dof: string): Integer; // 0..5, or -1 if invalid
function IsRotationalDof(Offset: Integer): Boolean;

// How many dofs/node an element type needs: 3 for a truss (translations
// only), 6 for a beam or shellq4 (translations + rotations). 0 =
// unrecognized type.
function DofsPerNodeForElementType(const ElementType: string): Integer;

implementation

function NewDenseMatrix(N: Integer): TDenseMatrix;
var
  i: Integer;
begin
  SetLength(Result, N + 1, N + 1);
  for i := 0 to N do
    FillChar(Result[i][0], (N + 1) * SizeOf(Double), 0);
end;

function DofOffset(const Dof: string): Integer;
begin
  if Dof = 'x' then Result := 0
  else if Dof = 'y' then Result := 1
  else if Dof = 'z' then Result := 2
  else if Dof = 'rx' then Result := 3
  else if Dof = 'ry' then Result := 4
  else if Dof = 'rz' then Result := 5
  else Result := -1;
end;

function IsRotationalDof(Offset: Integer): Boolean;
begin
  Result := (Offset >= 3) and (Offset <= 5);
end;

function DofsPerNodeForElementType(const ElementType: string): Integer;
begin
  if ElementType = 'truss' then Result := 3
  else if ElementType = 'beam' then Result := 6
  else if ElementType = 'shellq4' then Result := 6
  else Result := 0;
end;

end.
