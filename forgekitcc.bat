@echo off
rem ForgeKitCC launcher. Without arguments it opens the interactive menu.
rem "env" is handled here so the variables stay in the current console.
if /i "%~1"=="env" goto :env
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0forgekitcc.ps1" %*
exit /b %errorlevel%

:env
if defined FORGEKITCC_ENV (
  echo ForgeKitCC is already loaded in this console.
  exit /b 0
)
set "FKCC_SETUP="
set "FKCC_PATHS="
for /f "usebackq tokens=1* delims==" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0forgekitcc.ps1" internal-env`) do set "%%a=%%b"
if not defined FKCC_SETUP (
  echo MSVC is not installed. Run: forgekitcc update
  exit /b 1
)
call "%FKCC_SETUP%" >nul
set "PATH=%FKCC_PATHS%;%PATH%"
set "FKCC_SETUP="
set "FKCC_PATHS="
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0forgekitcc.ps1" internal-notify
echo ForgeKitCC build console: cl, clang-cl, cmake, ninja, python, code (if installed)
exit /b 0
