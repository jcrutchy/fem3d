@echo off
rem Runs every test in the suite and prints one line per test plus a total:
rem   the regression suite (fem_regress), each self-checking test program, and - if node is
rem   installed - the viewer's tests. Run it from the repository root, after build.bat has put
rem   the .exe files there. The exit code is 0 only if everything passed and nothing is missing.
setlocal
set PASSED=0
set FAILED=0
set MISSING=0

echo Regression suite
call :exe fem_regress
if not errorlevel 1 call :run "fem_regress tests\regression" fem_regress.exe tests\regression --bin .

echo Self-checking test programs
for %%T in (matrix_test results_test shell_results_test skyline_test fingerprint_test run_patch_test run_q8_membrane_test run_q8_plate_test run_q8_shell_test run_q8_shell3d_test run_growthlaw_test) do (
  call :exe %%T
  if not errorlevel 1 call :run %%T %%T.exe
)

where node >nul 2>nul
if errorlevel 1 (
  echo Viewer tests skipped ^(node not installed^)
) else (
  echo Viewer ^(node^)
  call :run "viewer\test\run_tests.js" node viewer\test\run_tests.js
)

echo.
echo %PASSED% passed, %FAILED% failed, %MISSING% missing
if %FAILED% GTR 0 exit /b 1
if %MISSING% GTR 0 exit /b 1
exit /b 0

:exe
rem :exe name  -> errorlevel 0 if name.exe exists, else counts it as missing and returns 1
if exist "%~1.exe" exit /b 0
set /a MISSING+=1
echo   MISSING  %~1   ^(not built: %~1.exe not found^)
exit /b 1

:run
rem :run "label" command args...
set LABEL=%~1
set "OUT=%TEMP%\femtest_%RANDOM%.txt"
shift
%1 %2 %3 %4 %5 %6 %7 >"%OUT%" 2>&1
if errorlevel 1 (
  set /a FAILED+=1
  echo   FAIL     %LABEL%
  type "%OUT%"
) else (
  set /a PASSED+=1
  echo   PASS     %LABEL%
)
del "%OUT%" >nul 2>nul
exit /b 0