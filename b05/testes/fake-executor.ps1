# fake-executor.ps1 — executor SIMULADO para os testes do B-05 (imita claude -p --output-format json).
# Modo em B05FAKE_MODO: ok:<custo> | dorme:<seg> | semcusto | falha:<codigo>. Registro em B05FAKE_DIR.
$stdin = if ([Console]::IsInputRedirected) { [Console]::In.ReadToEnd() } else { '' }
$dir = $env:B05FAKE_DIR; $modo = "$env:B05FAKE_MODO"
if ($dir) {
  New-Item -ItemType Directory -Force $dir | Out-Null
  $n = 1; $cf = Join-Path $dir 'chamadas.txt'; if (Test-Path $cf) { $n = [int](Get-Content $cf -Raw) + 1 }; Set-Content $cf $n -NoNewline
  [ordered]@{ args = @($args); stdin = $stdin; pid = $PID; cwd = (Get-Location).Path } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dir "chamada-$n.json")
}
# Toda chamada bem-sucedida altera um arquivo do repo (o controlador exige alteração real).
function Alterar { Add-Content -Path (Join-Path (Get-Location) 'notas.txt') -Value "chamada $PID $(Get-Date -Format o)" }
$tipo, $valor = $modo -split ':', 2
switch ($tipo) {
  'ok'       { Alterar; [ordered]@{ type = 'result'; is_error = $false; result = 'feito'; total_cost_usd = [double]$valor } | ConvertTo-Json -Compress; exit 0 }
  'semcusto' { Alterar; [ordered]@{ type = 'result'; is_error = $false; result = 'feito' } | ConvertTo-Json -Compress; exit 0 }
  'dorme'    { Start-Sleep -Seconds ([int]$valor); Alterar; [ordered]@{ type = 'result'; is_error = $false; result = 'acordei'; total_cost_usd = 0.01 } | ConvertTo-Json -Compress; exit 0 }
  'falha'    { [ordered]@{ type = 'result'; is_error = $true; result = 'falhei'; total_cost_usd = 0.02 } | ConvertTo-Json -Compress; exit ([int]$valor) }
  default    { Write-Output "modo desconhecido: $modo"; exit 9 }
}
