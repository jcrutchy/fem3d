@echo off
setlocal
if not exist "tests\FEM3D_TestRunner.exe" call build_headless.bat
if errorlevel 1 exit /b 1

tests\FEM3D_TestRunner.exe --freeze-verified
exit /b %errorlevel%
