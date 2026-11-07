@echo off
rem Double-click to open a console with the ForgeKitCC build environment.
title ForgeKitCC build console
call "%~dp0forgekitcc.bat" env
if errorlevel 1 (
  pause
  exit /b 1
)
cmd /k
