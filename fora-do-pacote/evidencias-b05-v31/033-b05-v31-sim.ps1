# 033 — (reexecução após correção do conhost) Ato 077: nova candidata B-05 v3.1 — bateria simulada N1–N17 (sem custo) com o pwsh PORTÁTIL.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
if ($env:Path -notlike "*$env:USERPROFILE\.local\bin*") { $env:Path += ";$env:USERPROFILE\.local\bin" }
$base = "$env:USERPROFILE\piloto"; $out = "$base\ponte\saida\033-relatorio.txt"; $h = "$base\harness"
$PwP = "$base\ferramentas\pwsh-7.6.7\pwsh.exe"
& {
  "=== INICIO $(Get-Date -Format s) | $env:USERNAME"
  git -C $h fetch -q origin hibrido 2>&1; git -C $h -c advice.detachedHead=false checkout -q 40def253eda823b4d5266634498b6d710bed15fa 2>&1
  "commit: " + (git -C $h rev-parse HEAD) + " | controlador: " + (Get-FileHash "$h\kits\kit-A\controlador.ps1").Hash
  "pwsh portátil: $PwP | " + (Get-FileHash $PwP).Hash
  Get-FileHash "$h\b05\*.ps1", "$h\b05\*.cmd", "$h\b05\testes\*.ps1" | ForEach-Object { "$($_.Hash) $(Split-Path $_.Path -Leaf)" }
  "--- diagnóstico do 031: violações registradas nos razões temporários"
  Get-ChildItem "$env:TEMP\b05-*\razao*\razao.jsonl" -ErrorAction SilentlyContinue | ForEach-Object { $f = $_; Get-Content $f.FullName | Where-Object { $_ -match 'contencao_violada|externos_encerramento' } | ForEach-Object { "$($f.Directory.Parent.Name): $_" } }
  $env:Path = "$(Split-Path $PwP);$env:Path"
  & $PwP -NoProfile -File "$h\b05\testes\testar-b05.ps1" -ControladorPath "$h\kits\kit-A\controlador.ps1" -SettingsPath "$h\kits\kit-A\.claude\settings.json" 2>&1
  "código: $LASTEXITCODE"
  "=== FIM $(Get-Date -Format s)"
} *>&1 | Out-File -FilePath $out -Encoding utf8
