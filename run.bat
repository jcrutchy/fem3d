@echo off
:: Build everything, then run every test. "call" is essential: without it
:: Windows never returns from build.bat, so the tests silently never run.
cd /d "%~dp0"
call build.bat nopause
if errorlevel 1 (
    echo.
    echo [FAILED] Build failed - tests not run.
    pause
    exit /b 1
)
call test.bat nopause
set TESTRESULT=%errorlevel%
pause
exit /b %TESTRESULT%
