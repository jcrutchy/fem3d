@echo off
setlocal
if not exist "FEM3D_CLI.exe" call build_headless.bat
if errorlevel 1 exit /b 1
if not exist "FEM3D_LinStatic.exe" call build_headless.bat
if errorlevel 1 exit /b 1
if not exist "verify.exe" call build_headless.bat
if errorlevel 1 exit /b 1
if not exist "HeadlessContract.exe" call build_headless.bat
if errorlevel 1 exit /b 1
if not exist "tests\FEM3D_TestRunner.exe" call build_headless.bat
if errorlevel 1 exit /b 1

verify.exe
if errorlevel 1 exit /b 1
HeadlessContract.exe
if errorlevel 1 exit /b 1
FEM3D_CLI.exe validate examples\headless_cantilever.fem3d
if errorlevel 1 exit /b 1
FEM3D_CLI.exe solve examples\headless_cantilever.fem3d
if errorlevel 1 exit /b 1
FEM3D_CLI.exe results examples\headless_cantilever.fem3dres
if errorlevel 1 exit /b 1

tests\FEM3D_TestRunner.exe
if errorlevel 1 exit /b 1

echo HEADLESS SMOKE TEST PASSED
