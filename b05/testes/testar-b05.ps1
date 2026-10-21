# testar-b05.ps1 — cenários determinísticos do B-05 no Windows, com executor SIMULADO (sem custo real).
# Cobre N3, N4 (+ PID reutilizado), N5, N1/N2/N6 (com simulado), N7, N8, N9, N10.
# Uso: pwsh -NoProfile -File b05/testes/testar-b05.ps1 -ControladorPath <kits/kit-A/controlador.ps1> -SettingsPath <kits/kit-A/.claude/settings.json>
param([Parameter(Mandatory)][string]$ControladorPath, [Parameter(Mandatory)][string]$SettingsPath)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { 'Os testes do B-05 exigem Windows (Job Object).'; exit 2 }
$Lanc = (Resolve-Path (Join-Path $PSScriptRoot '../lancador.ps1')).Path
$Fake = (Resolve-Path (Join-Path $PSScriptRoot 'fake-executor.ps1')).Path
. (Join-Path $PSScriptRoot '../razao.ps1')
$Pw = (Get-Process -Id $PID).Path
$ControladorPath = (Resolve-Path $ControladorPath).Path; $SettingsPath = (Resolve-Path $SettingsPath).Path
$falhas = 0; $total = 0
function Checar([string]$nome, [bool]$ok, [string]$det = '') { $script:total++; if (-not $ok) { $script:falhas++ }; "  [$(if ($ok) {'ok'} else {'FALHOU'})] $nome$(if (-not $ok -and $det) { " → $det" })" }

function Novo-Ambiente([int]$nTarefas = 1) {
  $b = Join-Path ([IO.Path]::GetTempPath()) ('b05-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
  $repo = "$b\repo"; New-Item -ItemType Directory -Force "$repo\testes", "$repo\.claude", "$b\estado", "$b\razao", "$b\fake" | Out-Null
  Set-Content "$repo\testes\teste-ok.ps1" 'exit 0'; Set-Content "$repo\notas.txt" 'base'
  Copy-Item $SettingsPath "$repo\.claude\settings.json"
  git init -q $repo; git -C $repo config user.email t@t; git -C $repo config user.name t; git -C $repo config core.autocrlf false
  git -C $repo add -A; git -C $repo commit -qm base
  $tarefas = @(1..$nTarefas | ForEach-Object { [ordered]@{ id = "T$_"; titulo = "Tarefa $_"; prompt = "[[T$_]] Acrescente uma linha em notas.txt."; depends_on = @(); status = 'pending'; tentativas = 0; critica = $false } })
  @{ tarefas = $tarefas } | ConvertTo-Json -Depth 5 | Set-Content "$b\TAREFAS.json"
  return @{ Base = $b; Repo = $repo; Estado = "$b\estado"; Razao = "$b\razao"; Fake = "$b\fake"; Tarefas = "$b\TAREFAS.json" }
}

function Args-Lancador($a, [double]$orc, [string[]]$extra = @()) {
  return @('-NoProfile', '-File', $Lanc, '-RepoPath', $a.Repo, '-TarefasPath', $a.Tarefas, '-EstadoDir', $a.Estado, '-RazaoDir', $a.Razao,
           '-ControladorPath', $ControladorPath, '-TestCmd', 'pwsh -NoProfile -File testes/teste-ok.ps1', '-TestPaths', 'testes/*',
           '-OrcamentoUsd', "$orc", '-TetoChamadaUsd', '0.5', '-Folga', '0.25', '-MaxTentativas', '1', '-TimeoutSec', '120',
           '-Executor', $Pw, "-ExecutorPrefixo:-NoProfile|-File|$Fake", '-IgnorarVersao') + $extra
}
function Rodar-Lancador($a, [double]$orc, [string]$modo, [string[]]$extra = @()) {
  $env:B05FAKE_MODO = $modo; $env:B05FAKE_DIR = $a.Fake
  $saida = & $Pw @(Args-Lancador $a $orc $extra) 2>&1
  return @{ Codigo = $LASTEXITCODE; Saida = ($saida -join ' ') }
}
function Iniciar-Lancador($a, [double]$orc, [string]$modo) {
  $env:B05FAKE_MODO = $modo; $env:B05FAKE_DIR = $a.Fake
  $psi = [System.Diagnostics.ProcessStartInfo]::new($Pw); foreach ($x in (Args-Lancador $a $orc)) { $psi.ArgumentList.Add($x) }
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  return [System.Diagnostics.Process]::Start($psi)
}
function Eventos($a) { (Razao-Ler $a.Razao).Eventos }
function Status($a) { @((Get-Content $a.Tarefas -Raw | ConvertFrom-Json).tarefas | ForEach-Object { "$($_.id)=$($_.status)" }) -join ' ' }

"== N7 + N8: chamada normal pelo controlador congelado"
$a = Novo-Ambiente 1; $r = Rodar-Lancador $a 3 'ok:0.30'
$ev = Eventos $a
if (-not (Test-Path "$($a.Fake)\chamada-1.json")) { "  [FALHOU] executor simulado não foi chamado → código $($r.Codigo): $($r.Saida)"; exit 1 }
$ch = Get-Content "$($a.Fake)\chamada-1.json" -Raw | ConvertFrom-Json
$args1 = @($ch.args)
Checar 'controlador terminou (0) e T1 done' ($r.Codigo -eq 0 -and (Status $a) -eq 'T1=done') "código $($r.Codigo); $(Status $a); $($r.Saida)"
Checar 'razão: inicio e fim com custo 0.30' ((@($ev | Where-Object evento -eq 'inicio').Count -eq 1) -and ((@($ev | Where-Object evento -eq 'fim'))[0].custo_usd -eq 0.3))
Checar 'N8: argumentos do controlador preservados + --max-budget-usd 0.5 no fim' (($args1 -join ' ') -match '^-p --output-format json --permission-mode dontAsk --settings .+ --max-budget-usd 0\.5$') ($args1 -join ' ')
Checar 'N8: stdin (prompt da tarefa) chegou ao executor' ("$($ch.stdin)".Contains('[[T1]]'))
Checar 'N8: cwd do executor é o repo' ("$($ch.cwd)" -eq $a.Repo) "$($ch.cwd)"
$est = Get-Content "$($a.Estado)\estado.json" -Raw | ConvertFrom-Json
Checar 'E1: razão (conhecido) = estado.json do controlador' ([math]::Abs((Razao-Contabilizar $ev 0.25).Conhecido - [double]$est.custo_acumulado_usd) -lt 1e-6) "razão $((Razao-Contabilizar $ev 0.25).Conhecido) / estado $($est.custo_acumulado_usd)"
Checar 'P1: membros do job registrados incluem o executor' ((@($ev | Where-Object evento -eq 'membros_job' | ForEach-Object { @($_.pids) }) -contains [int]$ch.pid)) "pid $($ch.pid)"

"== N8: código de saída e JSON de erro preservados"
$a = Novo-Ambiente 1; $r = Rodar-Lancador $a 3 'falha:3'
$log = Get-Content "$($a.Estado)\log.jsonl" -Raw
Checar 'controlador viu código 3 do executor (falhou, T1 failed)' ($log -match '"motivo":"código 3"' -and (Status $a) -eq 'T1=failed') "$(Status $a)"
Checar 'razão: fim com custo 0.02 do JSON de erro' ((@(Eventos $a | Where-Object evento -eq 'fim'))[0].custo_usd -eq 0.02)

"== N9: várias chamadas esgotam o orçamento (0.30 cada; reserva 0.625; orçamento 1.60)"
$a = Novo-Ambiente 5; $r = Rodar-Lancador $a 1.6 'ok:0.30'
$ev = Eventos $a; $cont = Razao-Contabilizar $ev 0.25
Checar 'T1–T4 done, T5 failed' ((Status $a) -eq 'T1=done T2=done T3=done T4=done T5=failed') (Status $a)
Checar '4 inicios, 1 bloqueado, executor chamado 4 vezes' ((@($ev | Where-Object evento -eq 'inicio').Count -eq 4) -and (@($ev | Where-Object evento -eq 'bloqueado').Count -eq 1) -and ([int](Get-Content "$($a.Fake)\chamadas.txt" -Raw) -eq 4))
$est = Get-Content "$($a.Estado)\estado.json" -Raw | ConvertFrom-Json
Checar 'sem dupla cobrança: razão 1.20 = estado.json 1.20' ([math]::Abs($cont.Conhecido - 1.2) -lt 1e-6 -and [math]::Abs([double]$est.custo_acumulado_usd - 1.2) -lt 1e-6) "razão $($cont.Conhecido) estado $($est.custo_acumulado_usd)"

"== N3: saldo insuficiente antes de iniciar"
$a = Novo-Ambiente 1; $r = Rodar-Lancador $a 0.5 'ok:0.30'
Checar 'código 23, controlador não iniciou, executor não chamado' ($r.Codigo -eq 23 -and -not (Test-Path "$($a.Estado)\estado.json") -and -not (Test-Path "$($a.Fake)\chamadas.txt")) "código $($r.Codigo)"

"== N10: falha de associação ao job / handle herdável"
$a = Novo-Ambiente 1; $r = Rodar-Lancador $a 3 'ok:0.30' @('-TesteFalharAssociacao')
Checar 'associação falha → código 24, controlador não iniciou' ($r.Codigo -eq 24 -and -not (@(Eventos $a | Where-Object evento -eq 'controlador').Count) -and -not (Test-Path "$($a.Estado)\estado.json")) "código $($r.Codigo) $($r.Saida)"
$r = Rodar-Lancador $a 3 'ok:0.30' @('-TesteHandleHerdavel')
Checar 'handle herdável → código 24, controlador não iniciou' ($r.Codigo -eq 24 -and -not (Test-Path "$($a.Estado)\estado.json")) "código $($r.Codigo) $($r.Saida)"

"== N4: processo antigo vivo (PID + criação) e PID reutilizado"
$a = Novo-Ambiente 1
$sent = Start-Process $Pw -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 120' -PassThru -WindowStyle Hidden
Start-Sleep 1
Razao-Gravar $a.Razao @{ evento = 'pid'; id = 'antigo'; pid = $sent.Id; criacao = $sent.StartTime.ToUniversalTime().ToString('o') }
Razao-Gravar $a.Razao @{ evento = 'inicio'; id = 'antigo'; teto_usd = 0.1; folga = 0.25 }
Razao-Gravar $a.Razao @{ evento = 'fim'; id = 'antigo'; custo_usd = 0.0; custo_desconhecido = $false }
$r = Rodar-Lancador $a 3 'ok:0.30'
Checar 'processo antigo vivo → código 22' ($r.Codigo -eq 22) "código $($r.Codigo) $($r.Saida)"
Stop-Process -Id $sent.Id -Force; Start-Sleep 1
$a2 = Novo-Ambiente 1; $viz = Start-Process $Pw -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 60' -PassThru -WindowStyle Hidden; Start-Sleep 1
Razao-Gravar $a2.Razao @{ evento = 'pid'; id = 'reuso'; pid = $viz.Id; criacao = '2020-01-01T00:00:00.0000000Z' }
$r = Rodar-Lancador $a2 3 'ok:0.30'
Checar 'mesmo PID com outra criação (reutilizado) → não bloqueia' ($r.Codigo -eq 0) "código $($r.Codigo) $($r.Saida)"
Stop-Process -Id $viz.Id -Force -ErrorAction SilentlyContinue

"== N5 + N1 + N2 + N6: segunda instância, queda do lançador, reserva e retomada (simulado)"
$a = Novo-Ambiente 1
$l1 = Iniciar-Lancador $a 3 'dorme:90'
$lim = (Get-Date).AddSeconds(40); $pidEx = $null
while ((Get-Date) -lt $lim -and -not $pidEx) { Start-Sleep 1; $e = @((Razao-Ler $a.Razao).Eventos | Where-Object evento -eq 'pid'); if ($e.Count) { $pidEx = $e[-1] } }
Start-Sleep 2
$membros = @((Razao-Ler $a.Razao).Eventos | Where-Object evento -eq 'membros_job' | ForEach-Object { @($_.pids) })
Checar 'N1: executor estava no job antes da queda' ($pidEx -and ($membros -contains [int]$pidEx.pid)) "pid $($pidEx.pid) membros $($membros -join ',')"
$r = Rodar-Lancador $a 3 'ok:0.30'
Checar 'N5: segunda instância para o mesmo EstadoDir → código 20' ($r.Codigo -eq 20) "código $($r.Codigo)"
$ctlEv = @((Razao-Ler $a.Razao).Eventos | Where-Object evento -eq 'controlador')[-1]
Stop-Process -Id $l1.Id -Force
Start-Sleep 5
Checar 'N1: executor morto em ≤ 5 s (PID + criação)' (-not (Processo-Vivo ([int]$pidEx.pid) "$($pidEx.criacao)"))
Checar 'N1: controlador morto' (-not (Processo-Vivo ([int]$ctlEv.pid) "$($ctlEv.criacao)"))
Checar 'N1: tarefa ficou in_progress para a retomada' ((Status $a) -eq 'T1=in_progress') (Status $a)
$cont = Razao-Contabilizar (Razao-Ler $a.Razao).Eventos 0.25
Checar 'N2: chamada derrubada reservada (0.625), não zero' ([math]::Abs($cont.Reservado - 0.625) -lt 1e-6 -and $cont.Abertas.Count -eq 1) "reservado $($cont.Reservado)"
$r = Rodar-Lancador $a 3 'ok:0.30'
$cont = Razao-Contabilizar (Razao-Ler $a.Razao).Eventos 0.25
Checar 'N6: retomada concluiu T1 (0)' ($r.Codigo -eq 0 -and (Status $a) -eq 'T1=done') "código $($r.Codigo) $(Status $a) $($r.Saida)"
Checar 'N6: total = 0.625 (derrubada) + 0.30 (nova)' ([math]::Abs($cont.Total - 0.925) -lt 1e-6) "total $($cont.Total)"
Checar 'N6: um único commit da tarefa' (@(git -C $a.Repo log --format=%s | Where-Object { $_ -like 'tarefa T1:*' }).Count -eq 1)

"== E4: razão com linha parcial bloqueia"
$a = Novo-Ambiente 1; [System.IO.File]::WriteAllText("$($a.Razao)\razao.jsonl", '{"evento":"inicio","id":"x"')
$r = Rodar-Lancador $a 3 'ok:0.30'
Checar 'código 21, nada iniciado' ($r.Codigo -eq 21 -and -not (Test-Path "$($a.Estado)\estado.json")) "código $($r.Codigo)"

"TOTAL B05: $($total - $falhas) / $total"
exit $(if ($falhas) { 1 } else { 0 })
