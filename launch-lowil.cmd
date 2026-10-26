@echo off
rem launch-lowil.cmd - spike de confirmacao do C6-real (C4-F01). Double-click no notebook. pwsh PORTATIL por caminho completo.
setlocal
set "PORTATIL=%~dp0..\ferramentas\pwsh-7.6.7\pwsh.exe"
set "GATE=%~dp0b05\pe\testes\gate-lowil.ps1"
if not exist "%PORTATIL%" (echo [ERRO] pwsh portatil nao encontrado: "%PORTATIL%" & pause & exit /b 3)
if not exist "%GATE%" (echo [ERRO] gate-lowil.ps1 nao encontrado: "%GATE%" & pause & exit /b 3)
echo Rodando o spike low-IL sob o pwsh portatil aprovado...
"%PORTATIL%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%GATE%"
set RC=%ERRORLEVEL%
echo.
echo ===== spike concluido (exit %RC%) - resultado em b05\pe\gate-lowil-*.txt =====
pause
exit /b %RC%
