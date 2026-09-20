unit FEMSolverContract;
{$mode objfpc}{$H+}

interface

uses SysUtils;

const
  FEM_SOLVER_SUCCESS = 0;
  FEM_SOLVER_USAGE_ERROR = 2;
  FEM_SOLVER_IO_ERROR = 3;
  FEM_SOLVER_VALIDATION_ERROR = 4;
  FEM_SOLVER_ANALYSIS_ERROR = 5;
  FEM_SOLVER_CONFIGURATION_ERROR = 6;
  FEM_SOLVER_MATRIX_ERROR = 7;
  FEM_SOLVER_IMPLEMENTATION_ERROR = 8;
  FEM_SOLVER_NUMERICAL_ERROR = 9;

function SolverResultFileName(const ModelFileName: string): string;
function SolverTemporaryResultFileName(const ModelFileName: string): string;

implementation

function SolverResultFileName(const ModelFileName: string): string;
begin
  Result := ChangeFileExt(ExpandFileName(ModelFileName), '.fem3dres');
end;

function SolverTemporaryResultFileName(const ModelFileName: string): string;
begin
  Result := SolverResultFileName(ModelFileName) + '.tmp';
end;

end.
