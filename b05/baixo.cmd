@echo off
rem baixo.cmd (E84-05/G3): roda o comando recebido em BAIXA integridade, via o pwsh portatil (B05_PWSH).
if not defined B05_PWSH (echo {"erro":"B05_PWSH ausente"}& exit /b 97)
"%B05_PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0baixo-exec.ps1" %*
