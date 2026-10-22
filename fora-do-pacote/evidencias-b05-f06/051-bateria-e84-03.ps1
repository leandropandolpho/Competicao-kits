# 051 — Ato 089: bateria B-05 no commit db398a7 (E84-03 NO_READ_UP + ambiente higienizado). N18b/N18e.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
if ($env:Path -notlike "*$env:USERPROFILE\.local\bin*") { $env:Path += ";$env:USERPROFILE\.local\bin" }
$base = "$env:USERPROFILE\piloto"; $out = "$base\ponte\saida\051-relatorio.txt"
$PwP = "$base\ferramentas\pwsh-7.6.7\pwsh.exe"
& {
  "=== INICIO $(Get-Date -Format s) | $env:USERNAME"
  $h = "$base\harness"
  git -C $h fetch -q origin hibrido 2>&1; git -C $h -c advice.detachedHead=false checkout -q db398a7f06204815ba69818372b007660c2cd3da 2>&1
  "commit: " + (git -C $h rev-parse HEAD) + " | controlador: " + (Get-FileHash "$h\kits\kit-A\controlador.ps1").Hash
  Get-FileHash "$h\b05\*.ps1", "$h\b05\*.cmd", "$h\b05\testes\*.ps1" | ForEach-Object { "$($_.Hash) $(Split-Path $_.Path -Leaf)" }
  $env:Path = "$(Split-Path $PwP);$env:Path"
  "##### 1 — bateria simulada"
  & $PwP -NoProfile -File "$h\b05\testes\testar-b05.ps1" -ControladorPath "$h\kits\kit-A\controlador.ps1" -SettingsPath "$h\kits\kit-A\.claude\settings.json" 2>&1
  "código: $LASTEXITCODE"
  "=== FIM $(Get-Date -Format s)"
} *>&1 | Out-File -FilePath $out -Encoding utf8
