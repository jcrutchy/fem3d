@echo off
setlocal

:: Define paths
set "LAZ_DIR=C:\lazarus"
set "LAZBUILD=%LAZ_DIR%\lazbuild.exe"

echo ==========================================
echo Starting Lazarus/FPC Project Compilation
echo ==========================================

:: Check if lazbuild exists
if not exist "%LAZBUILD%" (
    echo [ERROR] Could not find lazbuild.exe at %LAZBUILD%
    goto :error
)

echo.
echo [INFO] Scanning for Lazarus projects (.lpi)...

:: Automatically loop through all .lpi files in this directory and subdirectories
for /R %%p in (*.lpi) do (
    echo.
    echo ------------------------------------------
    echo Building: %%p
    echo ------------------------------------------
    
    :: Remove --build-mode=Release if you haven't set up specific build modes
    "%LAZBUILD%" "%%p"
    
    if errorlevel 1 (
        echo [ERROR] Failed to compile: %%p
        goto :error
    )
)

echo.
echo ==========================================
echo All projects compiled successfully!
echo ==========================================
goto :end

:error
echo.
echo [FAILED] Compilation stopped due to errors.
exit /b 1

:end
endlocal
pause