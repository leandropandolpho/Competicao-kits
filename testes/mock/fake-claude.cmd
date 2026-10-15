@echo off
rem Claude simulado (Windows). Repassa os argumentos ao fake-claude.ps1.
rem Prompts com várias linhas devem ir pela entrada padrão (stdin): o cmd corta quebras de linha em argumentos.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake-claude.ps1" %*
exit /b %ERRORLEVEL%
