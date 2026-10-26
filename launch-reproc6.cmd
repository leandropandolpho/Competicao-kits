@echo off
rem launch-reproc6.cmd - repro dirigido do C6-real (diagnostico). Double-click. pwsh PORTATIL por caminho completo.
setlocal
set "PORTATIL=%~dp0..\ferramentas\pwsh-7.6.7\pwsh.exe"
set "GATE=%~dp0b05\pe\testes\repro-c6.ps1"
if not exist "%PORTATIL%" (echo [ERRO] pwsh portatil nao encontrado & pause & exit /b 3)
if not exist "%GATE%" (echo [ERRO] repro-c6.ps1 nao encontrado & pause & exit /b 3)
echo Rodando o repro C6 sob o pwsh portatil...
"%PORTATIL%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%GATE%"
echo.
echo ===== repro concluido - resultado em b05\pe\repro-c6-*.txt =====
pause
