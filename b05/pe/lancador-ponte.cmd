@echo off
rem lancador-ponte.cmd - ponto de entrada estavel do lancador do modo PRINCIPAL-ISOLADO (R-01). gate-pe. Ato 150.
rem EXTERNO e ADITIVO: nao toca controlador/claude-com-teto/supervisora/lancador.ps1/nucleo B-05.
rem Usa o pwsh aprovado (B05_PWSH) para rodar lancador-ponte.ps1; repassa todos os argumentos.
setlocal
if "%B05_PWSH%"=="" (echo lancador-ponte: B05_PWSH ausente 1>&2 & exit /b 1)
rem C4-F02 (Ato 153): recusa de cara um B05_PWSH do MSIX da Store (WindowsApps); o .ps1 faz o gate completo por SHA.
echo %B05_PWSH%| find /i "WindowsApps" >nul && (echo C4-F02: B05_PWSH MSIX/WindowsApps recusado 1>&2 & exit /b 31)
"%B05_PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0lancador-ponte.ps1" %*
exit /b %ERRORLEVEL%
