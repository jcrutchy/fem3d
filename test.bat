@echo off
setlocal enableextensions

:: Change working directory to the folder containing this batch file
cd /d "%~dp0"

echo Searching for *test*.exe files...
echo.

:: Loop recursively through current directory and subdirectories
for /r "%~dp0" %%F in (*test*.exe) do (
    if exist "%%F" (
        echo Executing: "%%F"
        
        :: Sequential Execution (waits for each program to close before opening the next):
        "%%F"
        
        :: Parallel Execution (launches all programs simultaneously without waiting):
        :: start "" "%%F"
    )
)

echo.
echo All matching executables have been processed.
pause