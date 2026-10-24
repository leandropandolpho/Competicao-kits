@echo off
rem Modo principal-isolado (REQ-08): usa SEMPRE o pwsh portatil indicado pelo lancador (B05_PWSH), nunca o do PATH.
rem O controlador congelado recebe ESTE .cmd como ClaudeCmd quando a config seleciona a ponte (claude-com-teto intocado).
if not defined B05_PWSH (echo {"type":"result","subtype":"error_ponte","is_error":true,"result":"ponte: B05_PWSH ausente","total_cost_usd":0}& exit /b 1)
"%B05_PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-ponte.ps1" %*
