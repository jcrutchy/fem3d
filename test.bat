@echo off
setlocal enableextensions

:: Always work from the repository root: the tests find tests\, db\ and
:: examples\ relative to the current folder.
cd /d "%~dp0"

set FAILED=0

echo ==========================================
echo Running unit / patch tests  (bin\*test*.exe)
echo ==========================================
for %%F in (bin\*test*.exe) do (
    echo.
    echo Executing: %%F
    "%%F"
    if errorlevel 1 (
        echo [FAIL] %%F returned a non-zero exit code
        set FAILED=1
    )
)

echo.
echo ==========================================
echo Running geometry fixtures
echo ==========================================
if exist bin\run_geometry_fixtures.exe (
    bin\run_geometry_fixtures.exe
    if errorlevel 1 set FAILED=1
) else (
    echo [FAIL] bin\run_geometry_fixtures.exe not found - run build.bat first
    set FAILED=1
)

echo.
echo ==========================================
echo Running regression suite  (tests\regression)
echo ==========================================
if exist bin\fem_regress.exe (
    bin\fem_regress.exe tests\regression --bin bin
    if errorlevel 1 set FAILED=1
) else (
    echo [FAIL] bin\fem_regress.exe not found - run build.bat first
    set FAILED=1
)

echo.
if "%FAILED%"=="0" (
    echo ALL TEST PROGRAMS PASSED
) else (
    echo [FAILED] one or more test programs reported failures - see above
)

:: "test.bat nopause" is used by run.bat, which does its own pausing
if /i not "%~1"=="nopause" pause
endlocal & exit /b %FAILED%
