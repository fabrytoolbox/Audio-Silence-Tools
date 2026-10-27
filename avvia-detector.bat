@echo off
REM Launcher per Silence-Detector.ps1
setlocal
cd /d "%~dp0"
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Silence-Detector.ps1" -InputPath "%~1"
) else (
    echo PowerShell 7 non trovato!
    pause
)
endlocal
