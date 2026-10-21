@echo off
rem Embrulho do executor (B-05): o controlador congelado chama este .cmd como se fosse o claude.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-com-teto.ps1" %*
exit /b %ERRORLEVEL%
