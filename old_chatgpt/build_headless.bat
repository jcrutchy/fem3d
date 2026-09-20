@echo off
setlocal
set FPC=C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe

%FPC% -O3 -Fu"src" -Fu"solver\common" -Fu"tests" "cli\FEM3D_CLI.lpr" -o"FEM3D_CLI.exe"
if errorlevel 1 exit /b 1
%FPC% -O3 -Fu"src" -Fu"solver\common" "solver\FEM3D_LinStatic.lpr" -o"FEM3D_LinStatic.exe"
if errorlevel 1 exit /b 1
%FPC% -O3 -Fu"src" "tests\verify.lpr" -o"verify.exe"
if errorlevel 1 exit /b 1
%FPC% -O3 -Fu"src" "tests\HeadlessContract.lpr" -o"HeadlessContract.exe"
if errorlevel 1 exit /b 1
%FPC% -O3 -Fu"src" "tests\FEM3D_TestRunner.lpr" -o"tests\FEM3D_TestRunner.exe"
if errorlevel 1 exit /b 1

echo Headless build completed.
