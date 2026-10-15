@echo off
rem Claude simulado (Windows). Repassa todos os argumentos ao fake-claude.ps1.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-claude.ps1" %*
exit /b %ERRORLEVEL%
