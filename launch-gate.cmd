@echo off
rem launch-gate.cmd - GATE EMPIRICO de topologia de Jobs (C4-F01, Ato 164). Double-click no notebook.
rem Chama o pwsh PORTATIL aprovado pelo CAMINHO COMPLETO (evita o alias MSIX da Store - causa-raiz do Ato 151).
rem Fica no RAIZ do repo (gate-pe-083); o pwsh portatil esta em ..\ferramentas\pwsh-7.6.7\pwsh.exe.
setlocal
set "PORTATIL=%~dp0..\ferramentas\pwsh-7.6.7\pwsh.exe"
set "GATE=%~dp0b05\pe\testes\gate-jobtopo.ps1"
if not exist "%PORTATIL%" (echo [ERRO] pwsh portatil nao encontrado: "%PORTATIL%" & echo Ajuste o caminho ou rode de dentro do gate-pe-083. & pause & exit /b 3)
if not exist "%GATE%" (echo [ERRO] gate-jobtopo.ps1 nao encontrado: "%GATE%" & pause & exit /b 3)
echo Rodando o gate sob o pwsh portatil aprovado...
"%PORTATIL%" -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%GATE%"
set RC=%ERRORLEVEL%
echo.
echo ===== gate concluido (exit %RC%) - resultado em b05\pe\gate-jobtopo-*.txt =====
echo (exit 0 = TODAS VERDES / PASSA ; 1 = ha falha ; 3 = pwsh nao aprovado ou ambiente invalido)
pause
exit /b %RC%
