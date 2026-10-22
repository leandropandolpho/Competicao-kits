# fake-executor.ps1 — executor SIMULADO para os testes do B-05 (imita claude -p --output-format json).
# Modo em B05FAKE_MODO: ok:<custo> | dorme:<seg> | semcusto | falha:<codigo> | fuga | cru (imprime B05FAKE_SAIDA literal; N19). Registro em B05FAKE_DIR.
# fuga (N12, violação VERDADEIRA): inicia o pwsh da Microsoft Store (B05FAKE_LOJA) → cmd → ping, a cadeia que a
# sonda 029 mostrou escapar do job; nenhum rótulo artificial — quem decide se está fora do job é o Windows.
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
  'fuga'     {
    $psi = [System.Diagnostics.ProcessStartInfo]::new($env:B05FAKE_LOJA)
    foreach ($x in @('-NoProfile', '-Command', 'cmd /c ping -n 117 127.0.0.1 > nul')) { $psi.ArgumentList.Add($x) }
    $psi.UseShellExecute = $false
    $f = [System.Diagnostics.Process]::Start($psi)
    if ($dir) { Set-Content (Join-Path $dir 'fuga-pid.txt') $f.Id -NoNewline }
    Start-Sleep -Seconds 120; Alterar; [ordered]@{ type = 'result'; is_error = $false; result = 'fuga'; total_cost_usd = 0.01 } | ConvertTo-Json -Compress; exit 0 }
  'cru'      { Alterar; [Console]::Out.Write("$env:B05FAKE_SAIDA"); exit 0 }
  default    { Write-Output "modo desconhecido: $modo"; exit 9 }
}
