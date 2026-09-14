unit FEM3D_SolverUI_API;
{$mode objfpc}{$H+}

interface

const
  FEM3D_SOLVER_UI_API_VERSION = 1;

type
  TFEM3DUIGetAPIVersion = function:Integer; cdecl;
  TFEM3DUIGetSolverID = function(Buffer:PAnsiChar; BufferLength:Integer):Integer; cdecl;
  TFEM3DUIGetDisplayName = function(Buffer:PAnsiChar; BufferLength:Integer):Integer; cdecl;
  TFEM3DUIGetVersion = function(Buffer:PAnsiChar; BufferLength:Integer):Integer; cdecl;
  TFEM3DUIGetCapabilities = function(Buffer:PAnsiChar; BufferLength:Integer):Integer; cdecl;
  TFEM3DUIValidateSettings = function(SettingsText:PAnsiChar; ErrorBuffer:PAnsiChar; ErrorBufferLength:Integer):Integer; cdecl;

implementation

end.
