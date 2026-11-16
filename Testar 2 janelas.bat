@echo off
rem Abre duas janelas do jogo para testar Host + Client no mesmo PC.
cd /d "%~dp0"
start "" "FPSArenaLAN.exe"
timeout /t 1 /nobreak >nul
start "" "FPSArenaLAN.exe"
