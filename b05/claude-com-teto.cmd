@echo off
rem Embrulho B-05 v3.1: usa SEMPRE o pwsh portatil indicado pelo lancador (B05_PWSH), nunca o do PATH.
if not defined B05_PWSH (echo {"type":"result","subtype":"error_b05","is_error":true,"result":"B05: B05_PWSH ausente","total_cost_usd":0}& exit /b 1)
"%B05_PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-com-teto.ps1" %*
