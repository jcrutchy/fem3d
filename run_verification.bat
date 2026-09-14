@echo off
setlocal
if exist tests\verify.exe (
  tests\verify.exe
  exit /b %errorlevel%
)
echo tests\verify.exe not found. Build with build_win64.bat first.
exit /b 2
