@echo off
rem Despachante P-B da fase teste (D-2): o controlador congelado recebe este .cmd como $TestCmd. Usa SEMPRE o pwsh
rem portatil (B05_PWSH). O teste real roda sob o PE em Low IL, Job novo, via ponte (modo somente-teste).
if not defined B05_PWSH (echo despachante-teste: B05_PWSH ausente 1>&2& exit /b 1)
"%B05_PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0despachante-teste.ps1" %*
