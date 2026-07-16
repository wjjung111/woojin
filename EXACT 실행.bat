@echo off
cd /d "%~dp0"
if exist "arap_index_data.js" (
  start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "arap_launch.ps1"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "arap_launch.ps1"
)
