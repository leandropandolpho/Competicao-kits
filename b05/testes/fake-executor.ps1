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
  'junction' {
    # N18c: planta uma junction na árvore de trabalho (baixa) apontando para uma pasta MÉDIA, para desviar uma escrita
    # média que a atravesse. A varredura de reparse points do embrulho deve fechar a execução.
    $link = Join-Path (Get-Location) 'linkmedio'
    & cmd /c mklink /J "$link" "$env:B05FAKE_ALVO" 2>&1 | Out-Null
    Alterar; [ordered]@{ type = 'result'; is_error = $false; result = 'plantou junction'; total_cost_usd = 0.30 } | ConvertTo-Json -Compress; exit 0 }
  'atacar'   {
    # N18b/N18e: executor (em baixa integridade) tenta subverter E LER registros/credenciais de nível médio.
    # Alvos vêm por B05FAKE_* (o ambiente higienizado da E84-03 removeu B05_DIR). Resultado em .\ataque.txt (repo baixo).
    $rz = $env:B05FAKE_RAZAO; $cred = $env:B05FAKE_CRED
    $o = Join-Path (Get-Location) 'ataque.txt'
    function Tenta($nome, [scriptblock]$b) { try { & $b | Out-Null; "$nome=OK" } catch { "$nome=NEGADO" } }
    $linhas = @(
      Tenta 'razao_ler'      { [IO.File]::ReadAllText((Join-Path $rz 'razao.jsonl')) }
      Tenta 'razao_append'   { [IO.File]::AppendAllText((Join-Path $rz 'razao.jsonl'), '{"evento":"forjado"}' + "`n") }
      Tenta 'liberacao'      { [IO.File]::WriteAllText((Join-Path $rz 'LIBERACAO_HUMANA.txt'), 'forjada') }
      Tenta 'config_apagar'  { Remove-Item (Join-Path $rz ((Get-ChildItem $rz -Filter 'config-*.json')[0].Name)) -ErrorAction Stop }
      Tenta 'credencial_ler' { if ($cred) { [IO.File]::ReadAllText($cred) } else { throw 'sem cred' } }
      Tenta 'git_hook'       { [IO.File]::WriteAllText((Join-Path (Get-Location) '.git\hooks\pre-commit'), 'echo x') }
      Tenta 'git_config'     { [IO.File]::AppendAllText((Join-Path (Get-Location) '.git\config'), '[x]') }
      Tenta 'vars_vazadas'   { if ($env:B05_DIR -or $env:B05_EXECUCAO -or $env:OPENAI_API_KEY) { 'vazou' } else { throw 'limpo' } }
    )
    Set-Content $o ($linhas -join "`n")
    Alterar; [ordered]@{ type = 'result'; is_error = $false; result = 'tarefa feita'; total_cost_usd = 0.30 } | ConvertTo-Json -Compress; exit 0 }
  default    { Write-Output "modo desconhecido: $modo"; exit 9 }
}
