# testar-b05.ps1 — cenários determinísticos do B-05 (contrato v3.1) no Windows, com executor SIMULADO (sem custo real).
# Cobre N1–N17, N19 e N20 (N1r e N18 usam processos reais do Claude/Windows e rodam à parte), E4.
# Uso (com o pwsh PORTÁTIL): <pwsh portátil> -NoProfile -File b05/testes/testar-b05.ps1 -ControladorPath <kits/kit-A/controlador.ps1> -SettingsPath <kits/kit-A/.claude/settings.json>
param([Parameter(Mandatory)][string]$ControladorPath, [Parameter(Mandatory)][string]$SettingsPath,
      [string]$PwshLoja = "$env:LOCALAPPDATA\Microsoft\WindowsApps\Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.exe")
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { 'Os testes do B-05 exigem Windows (Job Object).'; exit 2 }
if ((Get-Process -Id $PID).Path -match '\\WindowsApps\\') { 'Rode os testes com o pwsh PORTÁTIL.'; exit 2 }
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

function Args-Lancador($a, [double]$orc, [string[]]$extra = @(), [int]$tent = 1) {
  return @('-NoProfile', '-File', $Lanc, '-RepoPath', $a.Repo, '-TarefasPath', $a.Tarefas, '-EstadoDir', $a.Estado, '-RazaoDir', $a.Razao,
           '-ControladorPath', $ControladorPath, '-TestCmd', 'pwsh -NoProfile -File testes/teste-ok.ps1', '-TestPaths', 'testes/*',
           '-OrcamentoUsd', "$orc", '-TetoChamadaUsd', '0.5', '-Folga', '0.25', '-MaxTentativas', "$tent", '-TimeoutSec', '120',
           '-Executor', $Pw, "-ExecutorPrefixo:-NoProfile|-File|$Fake", '-IgnorarVersao') + $extra
}
function Rodar-Lancador($a, [double]$orc, [string]$modo, [string[]]$extra = @(), [int]$tent = 1) {
  $env:B05FAKE_MODO = $modo; $env:B05FAKE_DIR = $a.Fake
  $saida = & $Pw @(Args-Lancador $a $orc $extra $tent) 2>&1
  return @{ Codigo = $LASTEXITCODE; Saida = ($saida -join ' ') }
}
function Iniciar-Lancador($a, [double]$orc, [string]$modo, [int]$tent = 1) {
  $env:B05FAKE_MODO = $modo; $env:B05FAKE_DIR = $a.Fake
  $psi = [System.Diagnostics.ProcessStartInfo]::new($Pw); foreach ($x in (Args-Lancador $a $orc @() $tent)) { $psi.ArgumentList.Add($x) }
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  return [System.Diagnostics.Process]::Start($psi)
}
function Eventos($a) { (Razao-Ler $a.Razao).Eventos }
function Canon([string]$p) { [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $p).ProviderPath).TrimEnd('\') }
function Vincular($a) {
  # Cria o vínculo como o lançador faria (para cenários que precisam de razão pré-preenchido).
  $id = [guid]::NewGuid().ToString('N'); $ts = (Get-Date).ToString('o')
  Razao-Gravar $a.Razao @{ evento = 'base_historica'; valor_usd = 0.0; vinculo = $id }
  [IO.File]::WriteAllText("$($a.Razao)\vinculo.json", ([ordered]@{ id = $id; estado_dir = (Canon $a.Estado); criado_em = $ts } | ConvertTo-Json))
  [IO.File]::WriteAllText("$($a.Estado)\b05-vinculo.json", ([ordered]@{ id = $id; razao_dir = (Canon $a.Razao); criado_em = $ts } | ConvertTo-Json))
}
function Hash-Pasta([string]$d) { (@(Get-ChildItem -LiteralPath $d -File | Sort-Object Name | ForEach-Object { "$($_.Name)=$((Get-FileHash $_.FullName).Hash)" }) -join ';') }
function Vivos-Ping117 { @(Get-CimInstance Win32_Process -Filter "Name='PING.EXE'" | Where-Object { $_.CommandLine -match '-n 117' }) }
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
Checar 'P1: executor registrado dentro de um Job Object (IsProcessInJob)' ((@($ev | Where-Object evento -eq 'pid'))[0].em_job -eq $true) "em_job $((@($ev | Where-Object evento -eq 'pid'))[0].em_job)"

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
$a = Novo-Ambiente 1; Vincular $a
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
$l1 = Iniciar-Lancador $a 3 'dorme:90' 2   # 2 tentativas: a retomada (N6) usa a segunda
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
Checar 'N1: executor morto em ≤ 5 s (PID + criação)' (-not (Processo-Vivo ([int]$pidEx.pid) $pidEx.criacao))
Checar 'N1: controlador morto' (-not (Processo-Vivo ([int]$ctlEv.pid) $ctlEv.criacao))
Checar 'N1: varredura só verifica (nenhum evento de associação nem violação)' (-not @((Razao-Ler $a.Razao).Eventos | Where-Object { $_.evento -in @('erro_job', 'associado', 'contencao_violada') }).Count)
Checar 'N1: tarefa ficou in_progress para a retomada' ((Status $a) -eq 'T1=in_progress') (Status $a)
$cont = Razao-Contabilizar (Razao-Ler $a.Razao).Eventos 0.25
Checar 'N2: chamada derrubada reservada (0.625), não zero' ([math]::Abs($cont.Reservado - 0.625) -lt 1e-6 -and $cont.Abertas.Count -eq 1) "reservado $($cont.Reservado)"
$r = Rodar-Lancador $a 3 'ok:0.30' @() 2
$cont = Razao-Contabilizar (Razao-Ler $a.Razao).Eventos 0.25
Checar 'N6: retomada concluiu T1 (0)' ($r.Codigo -eq 0 -and (Status $a) -eq 'T1=done') "código $($r.Codigo) $(Status $a) $($r.Saida)"
Checar 'N6: total = 0.625 (derrubada) + 0.30 (nova)' ([math]::Abs($cont.Total - 0.925) -lt 1e-6) "total $($cont.Total)"
Checar 'N6: um único commit da tarefa' (@(git -C $a.Repo log --format=%s | Where-Object { $_ -like 'tarefa T1:*' }).Count -eq 1)

"== E4: razão com linha parcial bloqueia"
$a = Novo-Ambiente 1; [System.IO.File]::WriteAllText("$($a.Razao)\razao.jsonl", '{"evento":"inicio","id":"x"')
$r = Rodar-Lancador $a 3 'ok:0.30'
Checar 'código 21, nada iniciado' ($r.Codigo -eq 21 -and -not (Test-Path "$($a.Estado)\estado.json")) "código $($r.Codigo)"

"== N11: pwsh empacotado (Microsoft Store) ou hash diferente → 27"
$a = Novo-Ambiente 1
if (Test-Path -LiteralPath $PwshLoja) {
  $env:B05FAKE_MODO = 'ok:0.30'; $env:B05FAKE_DIR = $a.Fake
  $null = & $PwshLoja @(Args-Lancador $a 3) 2>&1; $cod = $LASTEXITCODE
  Checar 'lançador no pwsh da Store → código 27, nada iniciado' ($cod -eq 27 -and -not (Test-Path "$($a.Estado)\estado.json") -and -not (Test-Path "$($a.Razao)\razao.jsonl")) "código $cod"
} else { Checar 'pwsh da Store presente para N11' $false $PwshLoja }
$r = Rodar-Lancador $a 3 'ok:0.30' @('-PwshSha256', ('0' * 64))
Checar 'hash do pwsh diferente do fixado → código 27, nada iniciado' ($r.Codigo -eq 27 -and -not (Test-Path "$($a.Estado)\estado.json") -and -not (Test-Path "$($a.Razao)\razao.jsonl")) "código $($r.Codigo)"

"== N12: violação VERDADEIRA (executor → pwsh da Store → cmd → ping) → 29, externos mortos, próxima partida recusada"
$a = Novo-Ambiente 1; $env:B05FAKE_LOJA = $PwshLoja
$t0 = Get-Date; $r = Rodar-Lancador $a 3 'fuga' @() 2; $dur = ((Get-Date) - $t0).TotalSeconds
Start-Sleep 3
$ev = Eventos $a
$cv = @($ev | Where-Object evento -eq 'contencao_violada'); $ee = @($ev | Where-Object evento -eq 'externos_encerramento')
$execV = if ($cv.Count) { "$($cv[0].execucao)" } else { '' }
$txtV = ($cv | ForEach-Object { @($_.violacoes) }) -join ' ; '
Checar 'lançador saiu com 29 antes do fim natural do executor' ($r.Codigo -eq 29 -and $dur -lt 100) "código $($r.Codigo) em $([int]$dur) s: $($r.Saida)"
Checar 'contencao_violada durável com processo real fora do job' ($cv.Count -ge 1 -and $txtV -match 'fora do job|não verificável') $txtV
Checar 'externos_encerramento gravado' ($ee.Count -ge 1) (($ee | ForEach-Object { @($_.resultados) }) -join ' ; ')
Checar 'conferência externa: nenhum ping da cadeia vivo' ((Vivos-Ping117).Count -eq 0) "vivos: $(@(Vivos-Ping117 | ForEach-Object ProcessId) -join ',')"
$fpid = if (Test-Path "$($a.Fake)\fuga-pid.txt") { [int](Get-Content "$($a.Fake)\fuga-pid.txt" -Raw) } else { 0 }
Checar 'conferência externa: pwsh da Store da cadeia morto' ($fpid -and -not (Get-Process -Id $fpid -ErrorAction SilentlyContinue)) "pid $fpid"
$ex1 = Get-Content "$($a.Fake)\chamada-1.json" -Raw | ConvertFrom-Json
Checar 'conferência externa: executor morto' (-not (Get-Process -Id $ex1.pid -ErrorAction SilentlyContinue))
$antes = Hash-Pasta $a.Fake
$r = Rodar-Lancador $a 3 'ok:0.30' @() 2
Checar 'partida seguinte recusada (29) sem LIBERACAO_HUMANA, executor não chamado' ($r.Codigo -eq 29 -and (Hash-Pasta $a.Fake) -eq $antes) "código $($r.Codigo)"
Set-Content "$($a.Razao)\LIBERACAO_HUMANA.txt" "Liberado por Leandro: execução $execV analisada."
$r = Rodar-Lancador $a 3 'ok:0.30' @() 2
Checar 'com LIBERACAO_HUMANA (id da execução) → retoma e conclui T1' ($r.Codigo -eq 0 -and (Status $a) -eq 'T1=done' -and @(Eventos $a | Where-Object evento -eq 'liberacao_humana').Count -eq 1) "código $($r.Codigo) $(Status $a) $($r.Saida)"
Get-Process -Id $fpid -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Vivos-Ping117 | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

"== N13: dois EstadoDir com o mesmo RazaoDir em paralelo → 20"
$a = Novo-Ambiente 1; $b = Novo-Ambiente 1; $b.Razao = $a.Razao
$l1 = Iniciar-Lancador $a 3 'dorme:40'
$lim = (Get-Date).AddSeconds(40); while ((Get-Date) -lt $lim -and -not @(Eventos $a | Where-Object evento -eq 'pid').Count) { Start-Sleep 1 }
$cfgA = @(Get-ChildItem "$($a.Razao)\config-*.json"); $hA = Hash-Pasta $a.Razao
$hCfg = ($cfgA | ForEach-Object { (Get-FileHash $_.FullName).Hash }) -join ','
$r = Rodar-Lancador $b 3 'ok:0.30'
Checar 'segunda execução recusada com 20' ($r.Codigo -eq 20 -and -not (Test-Path "$($b.Estado)\estado.json")) "código $($r.Codigo) $($r.Saida)"
Checar 'configuração da primeira intacta e somente-leitura' ($cfgA.Count -eq 1 -and ((Get-ChildItem "$($a.Razao)\config-*.json" | ForEach-Object { (Get-FileHash $_.FullName).Hash }) -join ',') -eq $hCfg -and (Get-Item $cfgA[0].FullName).IsReadOnly)
Stop-Process -Id $l1.Id -Force; Start-Sleep 3

"== N14: estado.json divergente do razão → 28 antes de iniciar"
$a = Novo-Ambiente 2; $r = Rodar-Lancador $a 3 'ok:0.30'
$est = Get-Content "$($a.Estado)\estado.json" -Raw | ConvertFrom-Json
Checar 'primeira execução ok e reconciliada (estado 0.60 = base 0 + conhecido 0.60)' ($r.Codigo -eq 0 -and [math]::Abs([double]$est.custo_acumulado_usd - 0.6) -lt 1e-6) "código $($r.Codigo) custo $($est.custo_acumulado_usd)"
$est.custo_acumulado_usd = [double]$est.custo_acumulado_usd + 1
$est | ConvertTo-Json -Depth 8 | Set-Content "$($a.Estado)\estado.json"
$n0 = [int](Get-Content "$($a.Fake)\chamadas.txt" -Raw)
$r = Rodar-Lancador $a 3 'ok:0.30'
Checar 'divergência → 28, executor não chamado' ($r.Codigo -eq 28 -and [int](Get-Content "$($a.Fake)\chamadas.txt" -Raw) -eq $n0) "código $($r.Codigo) $($r.Saida)"

"== N15: falha forçada na gravação do pid → executor encerrado, reserva mantida, erro"
$a = Novo-Ambiente 1; $env:B05_TESTE_FALHAR_PID = '1'
$t0 = Get-Date; $r = Rodar-Lancador $a 3 'dorme:60'; $dur = ((Get-Date) - $t0).TotalSeconds
Remove-Item Env:B05_TESTE_FALHAR_PID
$ev = Eventos $a; $cont = Razao-Contabilizar $ev 0.25
Checar 'chamada falhou rápido (executor encerrado, sem esperar 60 s)' ($dur -lt 45 -and (Status $a) -eq 'T1=failed') "$([int]$dur) s, $(Status $a), código $($r.Codigo)"
Checar 'sem evento pid nem fim; reserva 0.625 mantida' (-not @($ev | Where-Object evento -eq 'pid').Count -and -not @($ev | Where-Object evento -eq 'fim').Count -and [math]::Abs($cont.Reservado - 0.625) -lt 1e-6) "reservado $($cont.Reservado)"
Checar 'notas.txt intacto (executor não alterou nada)' ((Get-Content "$($a.Repo)\notas.txt" -Raw).Trim() -eq 'base')

"== N16: reutilização sequencial do razão por outro estado → 30, razão inalterado"
$a = Novo-Ambiente 1; $r = Rodar-Lancador $a 3 'ok:0.30'
$b = Novo-Ambiente 1; $b.Razao = $a.Razao
$h0 = Hash-Pasta $a.Razao
$r = Rodar-Lancador $b 3 'ok:0.30'
Checar 'outro estado com razão vinculado → 30' ($r.Codigo -eq 30 -and -not (Test-Path "$($b.Estado)\estado.json")) "código $($r.Codigo) $($r.Saida)"
Checar 'RazaoDir byte a byte inalterado' ((Hash-Pasta $a.Razao) -eq $h0)
$c = Novo-Ambiente 1; $c.Estado = $a.Estado; $c.Tarefas = $a.Tarefas; $c.Repo = $a.Repo
$r = Rodar-Lancador $c 3 'ok:0.30'
Checar 'estado vinculado apontado para outro razão → 30, novo razão vazio' ($r.Codigo -eq 30 -and -not @(Get-ChildItem -LiteralPath $c.Razao).Count) "código $($r.Codigo)"

"== N17 + H8: custo histórico entra no orçamento e na reconciliação"
$a = Novo-Ambiente 1; Set-Content "$($a.Estado)\estado.json" '{"custo_acumulado_usd": 2.6}'
$r = Rodar-Lancador $a 3 'ok:0.30'
$ev = Eventos $a
Checar 'base 2.60 + reserva 0.625 > 3 → código 23, executor não chamado' ($r.Codigo -eq 23 -and -not (Test-Path "$($a.Fake)\chamadas.txt")) "código $($r.Codigo) $($r.Saida)"
Checar 'base_historica gravada uma vez com 2.60' (@($ev | Where-Object evento -eq 'base_historica').Count -eq 1 -and [double](@($ev | Where-Object evento -eq 'base_historica'))[0].valor_usd -eq 2.6)
$r = Rodar-Lancador $a 3 'ok:0.30'
Checar 'segunda tentativa: ainda 23 e base não regravada' ($r.Codigo -eq 23 -and @(Eventos $a | Where-Object evento -eq 'base_historica').Count -eq 1) "código $($r.Codigo)"
# Positivo: estado de antes do B-05 (custo 0.30) adotado por um razão novo → base 0.30; nova tarefa → estado 0.60 = 0.30 + 0.30.
$a = Novo-Ambiente 1; $r = Rodar-Lancador $a 3 'ok:0.30'
$t = Get-Content $a.Tarefas -Raw | ConvertFrom-Json
$t.tarefas += [pscustomobject][ordered]@{ id = 'T2'; titulo = 'Tarefa 2'; prompt = '[[T2]] Acrescente uma linha em notas.txt.'; depends_on = @(); status = 'pending'; tentativas = 0; critica = $false }
$t | ConvertTo-Json -Depth 6 | Set-Content $a.Tarefas
Remove-Item "$($a.Estado)\b05-vinculo.json"; $a.Razao = "$($a.Base)\razao2"
$r = Rodar-Lancador $a 3 'ok:0.30'
$cont = Razao-Contabilizar (Eventos $a) 0.25; $est = Get-Content "$($a.Estado)\estado.json" -Raw | ConvertFrom-Json
Checar 'H8: base 0.30 + conhecido 0.30 = estado 0.60, T2 done' ($r.Codigo -eq 0 -and $cont.Base -eq 0.3 -and [math]::Abs([double]$est.custo_acumulado_usd - 0.6) -lt 1e-6 -and (Status $a) -eq 'T1=done T2=done') "código $($r.Codigo) base $($cont.Base) estado $($est.custo_acumulado_usd) $(Status $a) $($r.Saida)"

"== N19: custo inválido do executor (negativo, texto, não finito) → desconhecido, reserva conservada"
foreach ($caso in @(@('negativo', '{"type":"result","is_error":false,"result":"x","total_cost_usd":-5}'),
                    @('texto', '{"type":"result","is_error":false,"result":"x","total_cost_usd":"0.3"}'),
                    @('nao_finito', '{"type":"result","is_error":false,"result":"x","total_cost_usd":1e999}'))) {
  $a = Novo-Ambiente 1; $env:B05FAKE_SAIDA = $caso[1]
  $r = Rodar-Lancador $a 3 'cru'
  $ev = Eventos $a; $f = @($ev | Where-Object evento -eq 'fim'); $cont = Razao-Contabilizar $ev 0.25
  Checar "$($caso[0]): fim com custo desconhecido, reserva 0.625 conservada, conhecido 0" ($f.Count -eq 1 -and $f[0].custo_desconhecido -eq $true -and [math]::Abs($cont.Reservado - 0.625) -lt 1e-6 -and $cont.Conhecido -eq 0) "fim $($f | ConvertTo-Json -Compress) reservado $($cont.Reservado) conhecido $($cont.Conhecido)"
  $n0 = [int](Get-Content "$($a.Fake)\chamadas.txt" -Raw)
  if ($r.Codigo -eq 28) {
    $r2 = Rodar-Lancador $a 3 'ok:0.30'
    Checar "$($caso[0]): controlador contabilizou outro valor → 28 (fecha), partida seguinte também 28 sem chamar o executor" ($r2.Codigo -eq 28 -and [int](Get-Content "$($a.Fake)\chamadas.txt" -Raw) -eq $n0) "segunda: $($r2.Codigo)"
  } else {
    $est = Get-Content "$($a.Estado)\estado.json" -Raw | ConvertFrom-Json
    Checar "$($caso[0]): lançador $($r.Codigo) e estado reconciliado (estado = B + K)" ([math]::Abs([double]$est.custo_acumulado_usd - ($cont.Base + $cont.Conhecido)) -lt 1e-6) "estado $($est.custo_acumulado_usd)"
  }
}
Remove-Item Env:B05FAKE_SAIDA

"== N20: processo não legítimo tenta enquadrar-se na exceção do conhost.exe"
. (Join-Path $PSScriptRoot '../b05job.ps1'); . (Join-Path $PSScriptRoot '../dispensa.ps1')
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class B05Pai {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct SI { public int cb; public string r, d, t; public int x, y, xs, ys, xc, yc, fill, flags; public short show, r2; public IntPtr r3, i, o, e; }
  [StructLayout(LayoutKind.Sequential)] struct SIX { public SI si; public IntPtr lista; }
  [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr hp, ht; public int pid, tid; }
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool InitializeProcThreadAttributeList(IntPtr l, int n, int f, ref IntPtr tam);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool UpdateProcThreadAttribute(IntPtr l, uint f, IntPtr attr, IntPtr val, IntPtr tam, IntPtr a, IntPtr b);
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool CreateProcessW(string app, System.Text.StringBuilder cmd, IntPtr pa, IntPtr ta, bool herda, uint flags, IntPtr env, string dir, ref SIX si, out PI pi);
  [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint a, bool h, int pid);
  // Cria um processo com PAI FALSIFICADO (PROC_THREAD_ATTRIBUTE_PARENT_PROCESS). Devolve o PID ou -erro.
  public static int Criar(string exe, string linha, int pai) {
    IntPtr hp = OpenProcess(0x0080, false, pai);   // PROCESS_CREATE_PROCESS
    if (hp == IntPtr.Zero) return -Marshal.GetLastWin32Error();
    IntPtr tam = IntPtr.Zero; InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref tam);
    IntPtr l = Marshal.AllocHGlobal(tam); IntPtr val = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(val, hp);
    if (!InitializeProcThreadAttributeList(l, 1, 0, ref tam)) return -Marshal.GetLastWin32Error();
    if (!UpdateProcThreadAttribute(l, 0, (IntPtr)0x00020000, val, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero)) return -Marshal.GetLastWin32Error();
    SIX s = new SIX(); s.si.cb = Marshal.SizeOf(typeof(SIX)); s.lista = l; PI pi;
    if (!CreateProcessW(exe, new System.Text.StringBuilder(linha), IntPtr.Zero, IntPtr.Zero, false, 0x00080000 | 0x08000000, IntPtr.Zero, null, ref s, out pi)) return -Marshal.GetLastWin32Error();
    return pi.pid;
  }
}
'@
$falso = Join-Path ([IO.Path]::GetTempPath()) ('b05-falso-' + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory $falso | Out-Null
Copy-Item "$env:SystemRoot\System32\PING.EXE" "$falso\conhost.exe"
$eu = [uint32]$PID; $criEu = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToFileTimeUtc()
# (a) cópia renomeada (conhost.exe fora do System32), filho deste processo
$p1 = Start-Process "$falso\conhost.exe" -ArgumentList '-n 30 127.0.0.1' -PassThru -WindowStyle Hidden; Start-Sleep 1
$d = Testar-Dispensa ([uint32]$p1.Id) $eu $eu $criEu ([DateTime]::UtcNow.ToFileTimeUtc())
Checar 'N20a: conhost.exe falso (caminho fora do System32) → não dispensado' (-not $d.Ok -and $d.Motivo -match 'caminho') $d.Motivo
# (b) conhost.exe legítimo do System32, mas criado DEPOIS da "associação"
$inst = [DateTime]::UtcNow.ToFileTimeUtc(); Start-Sleep -Milliseconds 200
$p2 = Start-Process "$env:SystemRoot\System32\conhost.exe" -ArgumentList '--headless', 'ping -n 30 127.0.0.1' -PassThru -WindowStyle Hidden; Start-Sleep 1
$d = Testar-Dispensa ([uint32]$p2.Id) $eu $eu $criEu $inst
Checar 'N20b: conhost.exe verdadeiro criado após a associação → não dispensado' (-not $d.Ok -and $d.Motivo -match 'depois da associa') $d.Motivo
# (c) controle: o mesmo processo, com o instante de associação posterior à criação → aceito (a regra não é cega)
$d = Testar-Dispensa ([uint32]$p2.Id) $eu $eu $criEu ([DateTime]::UtcNow.ToFileTimeUtc())
Checar 'N20c (controle): conhost.exe verdadeiro, pai certo, criado antes → dispensável' ($d.Ok) $d.Motivo
# (d) pai diferente / (e) PID "reutilizado" (criação anterior ao lançador)
$d = Testar-Dispensa ([uint32]$p2.Id) $eu ([uint32]4) $criEu ([DateTime]::UtcNow.ToFileTimeUtc())
Checar 'N20d: pai diferente do lançador → não dispensado' (-not $d.Ok -and $d.Motivo -match 'pai') $d.Motivo
$d = Testar-Dispensa ([uint32]$p2.Id) $eu $eu ([DateTime]::UtcNow.AddMinutes(5).ToFileTimeUtc()) ([DateTime]::UtcNow.AddMinutes(6).ToFileTimeUtc())
Checar 'N20e: criado antes do lançador (PID reutilizado) → não dispensado' (-not $d.Ok -and $d.Motivo -match 'antes do lan') $d.Motivo
Stop-Process -Id $p1.Id, $p2.Id -Force -ErrorAction SilentlyContinue
# (f) integração: conhost.exe falso com PAI FALSIFICADO = lançador em execução
$a = Novo-Ambiente 1; $l1 = Iniciar-Lancador $a 3 'dorme:25'
$lim = (Get-Date).AddSeconds(40); while ((Get-Date) -lt $lim -and -not @(Eventos $a | Where-Object evento -eq 'pid').Count) { Start-Sleep 1 }
$pf = [B05Pai]::Criar("$falso\conhost.exe", 'conhost.exe -n 60 127.0.0.1', $l1.Id)
Start-Sleep 2
$ctl = @(Eventos $a | Where-Object evento -eq 'controlador')[0]
$preTxt = (@($ctl.preexistentes) | ForEach-Object { "$($_.pid) $($_.caminho)" }) -join '; '
Checar 'N20f: processo com pai falsificado criado (teste válido)' ($pf -gt 0) "retorno $pf"
Checar 'N20f: não consta como pré-existente dispensado' (-not (@($ctl.preexistentes) | Where-Object { [int]$_.pid -eq $pf })) $preTxt
$l1.WaitForExit(90000) | Out-Null; Start-Sleep 2
$cv = @(Eventos $a | Where-Object evento -eq 'contencao_violada')
$vivo = [bool](Get-Process -Id $pf -ErrorAction SilentlyContinue)
Checar 'N20f: tratado como qualquer descendente (contido pelo job e morto no fim, ou violação 29) — nunca sobrevive' (-not $vivo -and ($l1.ExitCode -eq 0 -or ($l1.ExitCode -eq 29 -and $cv.Count))) "código $($l1.ExitCode) vivo $vivo violações $($cv.Count) $(($cv | ForEach-Object { @($_.violacoes) }) -join ' ; ')"
if ($vivo) { Stop-Process -Id $pf -Force -ErrorAction SilentlyContinue }
Remove-Item -Recurse -Force $falso -ErrorAction SilentlyContinue

"TOTAL B05: $($total - $falhas) / $total"
exit $(if ($falhas) { 1 } else { 0 })
