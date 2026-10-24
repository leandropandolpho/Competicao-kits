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
  'neto'     {
    # PE-R4 (determinístico, Ato 122/ChatGPT): executor LEGÍTIMO que gera um processo filho (neto do PE), DENTRO do job
    # (sem escape artificial). Formato neto:<netoSeg>:<selfSeg>:<exit>. Grava ".\neto-pid.txt" = "<pid>|<ticksUtc>"
    # (identidade PID+criação). Prova de contenção: após o fim do executor/acao-pe nenhum descendente pode sobreviver
    # (KILL_ON_JOB_CLOSE em encerramento normal/falha; TerminateJobObject em timeout).
    $netoSeg, $selfSeg, $rc = ($valor -split ':', 3)
    if (-not $netoSeg) { $netoSeg = 60 }; if (-not $selfSeg) { $selfSeg = 0 }; if (-not $rc) { $rc = 0 }
    $psi = [System.Diagnostics.ProcessStartInfo]::new($env:ComSpec)
    foreach ($x in @('/c', "ping -n $([int]$netoSeg + 1) 127.0.0.1 > nul")) { $psi.ArgumentList.Add($x) }
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $f = [System.Diagnostics.Process]::Start($psi)
    Set-Content (Join-Path (Get-Location) 'neto-pid.txt') ("$($f.Id)|$($f.StartTime.ToUniversalTime().Ticks)") -NoNewline
    if ([int]$selfSeg -gt 0) { Start-Sleep -Seconds ([int]$selfSeg) }
    Alterar; [ordered]@{ type = 'result'; is_error = ([int]$rc -ne 0); result = 'neto'; total_cost_usd = 0.05 } | ConvertTo-Json -Compress
    exit ([int]$rc) }
  'junction' {
    # N18c: planta uma junction na árvore de trabalho (baixa) apontando para uma pasta MÉDIA, para desviar uma escrita
    # média que a atravesse. A varredura de reparse points do embrulho deve fechar a execução.
    $link = Join-Path (Get-Location) 'linkmedio'
    $mk = (& cmd /c mklink /J "$link" "$env:B05FAKE_ALVO" 2>&1) -join ' '
    Set-Content (Join-Path (Get-Location) 'juncao.txt') ("mklink=$mk | criado=" + (Test-Path $link))
    Alterar; [ordered]@{ type = 'result'; is_error = $false; result = 'tentou junction'; total_cost_usd = 0.30 } | ConvertTo-Json -Compress; exit 0 }
  'atacar'   {
    # N18b/N18e: executor (em baixa integridade) tenta subverter E LER registros/credenciais de nível médio.
    # Alvos vêm por B05FAKE_* (o ambiente higienizado da E84-03 removeu B05_DIR). Resultado em .\ataque.txt (repo baixo).
    $rz = $env:B05FAKE_RAZAO; $cred = $env:B05FAKE_CRED; $est = $env:B05FAKE_ESTADO
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
      # N18f (condição do ChatGPT no Ato 094): o EstadoDir é legível (settings), mas o executor baixo NÃO pode ESCREVER nele.
      Tenta 'estado_escrever'   { if ($est) { [IO.File]::AppendAllText((Join-Path $est 'estado.json'), 'x') } else { throw 'sem est' } }
      Tenta 'settings_escrever' { if ($est) { [IO.File]::AppendAllText((Join-Path $est 'settings-executor.json'), 'x') } else { throw 'sem est' } }
      Tenta 'settings_ler'      { if ($est) { [IO.File]::ReadAllText((Join-Path $est 'settings-executor.json')) } else { throw 'sem est' } }
    )
    Set-Content $o ($linhas -join "`n")
    Alterar; [ordered]@{ type = 'result'; is_error = $false; result = 'tarefa feita'; total_cost_usd = 0.30 } | ConvertTo-Json -Compress; exit 0 }
  default    { Write-Output "modo desconhecido: $modo"; exit 9 }
}
