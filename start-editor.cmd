@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\dev\run.ps1" -Editor
if errorlevel 1 pause
