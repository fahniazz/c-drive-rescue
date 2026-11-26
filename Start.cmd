@echo off
rem Double-click to open the C Drive Rescue menu. ExecutionPolicy Bypass only applies to this one window.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0cdr.ps1" menu
