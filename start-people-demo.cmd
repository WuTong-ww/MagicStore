@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\dev\run-people-demo.ps1"
if errorlevel 1 pause
