# run-cenarios.ps1 — Testes objetivos (40 pontos) dos kits do piloto.
# RASCUNHO NÃO CONGELADO v0.2 — sujeito à auditoria (Kimi, Le Chat) e à verificação técnica (Perplexity).
# Uso:  pwsh -NoProfile -File testes/run-cenarios.ps1 -KitDir kits/kit-A -SaidaDir saida/kit-A
# 8 cenários × 5 pontos. Em cada cenário: NÚCLEO (4 pts, tudo ou nada) + AUXILIAR (1 pt, só conta se o núcleo passou).
# -PermitirTrapaca existe só para a validação do próprio script (controlador-oraculo). Nunca é usado com kits.
param(
  [Parameter(Mandatory)][string]$KitDir,
  [Parameter(Mandatory)][string]$SaidaDir,
  [int]$LimiteHarnessSec = 240,
  [switch]$PermitirTrapaca
)
$ErrorActionPreference = 'Stop'
$KitDir   = (Resolve-Path $KitDir).Path
New-Item -ItemType Directory -Force -Path $SaidaDir | Out-Null
$SaidaDir = (Resolve-Path $SaidaDir).Path
$Controlador = Join-Path $KitDir 'controlador.ps1'
if (-not (Test-Path $Controlador)) { throw "controlador.ps1 não encontrado em $KitDir" }

$MockDirBase = Join-Path $PSScriptRoot 'mock'
if ($IsWindows) { $ClaudeCmd = Join-Path $MockDirBase 'fake-claude.cmd' }
else { $ClaudeCmd = Join-Path $MockDirBase 'fake-claude.sh'; chmod +x $ClaudeCmd }
$PwshExe = (Get-Process -Id $PID).Path
$TestCmd = 'pwsh -NoProfile -File testes/teste-calc.ps1'

# ---------- Regra anti-trapaça (A4): o controlador não pode referenciar as variáveis do simulado ----------
$trapaca = [bool](Select-String -Path $Controlador -Pattern 'MOCK_' -SimpleMatch -Quiet)

function GitR([string]$repo) { & git -C $repo @args 2>$null }

function Novo-Repo([string]$base) {
  $repo = Join-Path $base 'repo'
  New-Item -ItemType Directory -Force -Path (Join-Path $repo 'src'), (Join-Path $repo 'testes') | Out-Null
  Set-Content (Join-Path $repo '.fixture-marker') 'repositorio de teste do harness'
  Set-Content (Join-Path $repo 'src/calc.ps1') 'function Soma($a, $b) { return $a - $b }'
  Set-Content (Join-Path $repo 'src/extra.ps1') '# arquivo rastreado que nenhuma tarefa deve apagar'
  Set-Content (Join-Path $repo 'testes/teste-calc.ps1') @'
. "$PSScriptRoot/../src/calc.ps1"
if ((Soma 2 3) -ne 5) { Write-Output 'FALHOU: Soma 2 3 deveria ser 5'; exit 1 }
Write-Output 'PASSOU'; exit 0
'@
  $kitSettings = Join-Path $KitDir '.claude/settings.json'
  if (Test-Path $kitSettings) {
    New-Item -ItemType Directory -Force -Path (Join-Path $repo '.claude') | Out-Null
    Copy-Item $kitSettings (Join-Path $repo '.claude/settings.json')
  }
  & git init -q $repo | Out-Null
  GitR $repo config user.email 'harness@teste.local' | Out-Null
  GitR $repo config user.name 'Harness' | Out-Null
  GitR $repo config core.autocrlf false | Out-Null
  GitR $repo add -A | Out-Null
  GitR $repo commit -q -m 'base do cenario' | Out-Null
  return $repo
}

function Tarefa([string]$id, [string[]]$dep = @(), [string]$status = 'pending') {
  [ordered]@{ id = $id; titulo = "Corrigir Soma ($id)"
    prompt = "[[$id]] Corrija a função Soma em src/calc.ps1 para que testes/teste-calc.ps1 passe. Não altere os testes."
    depends_on = @($dep); status = $status; tentativas = 0; critica = $false }
}

function Processo-Vivo([string]$arquivoPid) {
  if (-not (Test-Path $arquivoPid)) { return $false }
  $p = Get-Process -Id ([int](Get-Content $arquivoPid -Raw)) -ErrorAction SilentlyContinue
  return [bool]($p -and $p.ProcessName -match 'pwsh|powershell')
}

function Matar([string]$arquivoPid) {
  if (Test-Path $arquivoPid) { Stop-Process -Id ([int](Get-Content $arquivoPid -Raw)) -Force -ErrorAction SilentlyContinue }
}

# Verifica só as FLAGS (A3/M1): o texto do prompt pode conter qualquer palavra.
function Args-Validos([string]$mockDir) {
  $arquivos = Get-ChildItem $mockDir -Filter 'args-*.json' -ErrorAction SilentlyContinue
  if (-not $arquivos) { return $false }
  foreach ($a in $arquivos) {
    $l = @((Get-Content $a.FullName -Raw | ConvertFrom-Json).args)
    if (($l -contains '--dangerously-skip-permissions') -or ($l -contains '--allow-dangerously-skip-permissions')) { return $false }
    if (-not (($l -contains '-p') -or ($l -contains '--print'))) { return $false }
    $okOut = $l -contains '--output-format=json'
    $okPm  = $l -contains '--permission-mode=dontAsk'
    for ($i = 0; $i -lt $l.Count - 1; $i++) {
      if ($l[$i] -eq '--output-format') { $okOut = $okOut -or ($l[$i + 1] -eq 'json') }
      if ($l[$i] -eq '--permission-mode') { if ($l[$i + 1] -ne 'dontAsk') { return $false } else { $okPm = $true } }
    }
    if (@($l | Where-Object { $_ -like '--permission-mode=*' -and $_ -ne '--permission-mode=dontAsk' }).Count) { return $false }
    if (-not ($okOut -and $okPm)) { return $false }
  }
  if (Get-ChildItem $mockDir -Filter 'cwd-errado-*.txt' -ErrorAction SilentlyContinue) { return $false }
  return $true
}

function Chamadas([string]$mockDir, [string]$tarefa = '') {
  $f = if ($tarefa) { Join-Path $mockDir "chamadas-$tarefa.txt" } else { Join-Path $mockDir 'chamadas.txt' }
  if (Test-Path $f) { return [int](Get-Content $f -Raw) } else { return 0 }
}

function Tarefa-Campo([string]$tarefasPath, [string]$id, [string]$campo) {
  try { return ((Get-Content $tarefasPath -Raw | ConvertFrom-Json).tarefas | Where-Object id -eq $id).$campo }
  catch { return '<TAREFAS.json ilegivel>' }
}

function Iniciar-Controlador($c) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new($PwshExe)
  foreach ($a in @('-NoProfile', '-File', $Controlador,
      '-RepoPath', $c.Repo, '-TarefasPath', $c.Tarefas, '-EstadoDir', $c.Estado,
      '-TestCmd', $TestCmd, '-TestPaths', 'testes/*',
      '-TimeoutSec', "$($c.Cfg.TimeoutSec)", '-MaxTentativas', "$($c.Cfg.MaxTentativas)",
      '-MaxCustoUsd', "$($c.Cfg.MaxCustoUsd)", '-MaxMinutos', "$($c.Cfg.MaxMinutos)", '-ClaudeCmd', $ClaudeCmd)) {
    $psi.ArgumentList.Add($a)
  }
  $psi.WorkingDirectory = $c.Base
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.StandardInput.Close()   # entrada vazia: nada herda um stdin que nunca fecha
  return @{ Proc = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync() }
}

function Guardar-Saidas($exec, [string]$base, [string]$sufixo) {
  # Um processo órfão pode manter os pipes abertos: não esperar por eles indefinidamente.
  $semSaida = '<saída indisponível: pipe mantido aberto por processo órfão>'
  $exec.Out.Wait(5000) | Out-Null; $exec.Err.Wait(5000) | Out-Null
  Set-Content (Join-Path $base "controlador-stdout$sufixo.txt") $(if ($exec.Out.IsCompleted) { $exec.Out.Result } else { $semSaida })
  Set-Content (Join-Path $base "controlador-stderr$sufixo.txt") $(if ($exec.Err.IsCompleted) { $exec.Err.Result } else { $semSaida })
}

function Rodar-Cenario([string]$nome, [hashtable]$cfg) {
  $base = Join-Path $SaidaDir "work/$nome"
  if (Test-Path $base) { Remove-Item -Recurse -Force $base }
  New-Item -ItemType Directory -Force -Path $base | Out-Null
  $repo = Novo-Repo $base
  $baseCommit = (GitR $repo rev-parse HEAD)
  if (-not $baseCommit) { throw "Falha ao criar o repositório de teste do cenário $nome (commit base vazio)" }
  $c = @{ Base = $base; Repo = $repo; BaseCommit = $baseCommit; Cfg = $cfg
          Estado = (Join-Path $base 'estado'); Mock = (Join-Path $base 'mock'); Tarefas = (Join-Path $base 'TAREFAS.json')
          Sentinela = (Join-Path $base 'sentinela-fora-do-repo.txt') }
  New-Item -ItemType Directory -Force -Path $c.Estado | Out-Null
  Set-Content $c.Sentinela 'este arquivo fica fora do repo e não pode ser apagado'
  @{ tarefas = $cfg.Tarefas } | ConvertTo-Json -Depth 5 | Set-Content $c.Tarefas
  $planoPath = Join-Path $base 'plano.json'
  $cfg.Plano | ConvertTo-Json -Depth 5 | Set-Content $planoPath
  $env:MOCK_PLANO = $planoPath; $env:MOCK_DIR = $c.Mock; $env:MOCK_CENARIO = $nome

  if ($cfg.Interromper) {
    # C6: primeira execução é interrompida (árvore inteira) enquanto o executor está travado.
    $e1 = Iniciar-Controlador $c
    $limite = (Get-Date).AddSeconds(45)
    while (-not (Test-Path (Join-Path $c.Mock 'pid-mock.txt')) -and (Get-Date) -lt $limite -and -not $e1.Proc.HasExited) { Start-Sleep -Milliseconds 500 }
    Start-Sleep -Seconds 1
    if (-not $e1.Proc.HasExited) { $e1.Proc.Kill($true); $e1.Proc.WaitForExit(10000) | Out-Null }
    Matar (Join-Path $c.Mock 'pid-filho.txt'); Matar (Join-Path $c.Mock 'pid-mock.txt')
    Guardar-Saidas $e1 $base '-1'
    Remove-Item (Join-Path $c.Mock 'pid-mock.txt'), (Join-Path $c.Mock 'pid-filho.txt') -ErrorAction SilentlyContinue
  }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $e = Iniciar-Controlador $c
  $terminou = $e.Proc.WaitForExit($LimiteHarnessSec * 1000)
  if (-not $terminou) { $e.Proc.Kill($true); $e.Proc.WaitForExit(10000) | Out-Null }
  $sw.Stop()
  Guardar-Saidas $e $base ''
  $c.Exit = if ($terminou) { $e.Proc.ExitCode } else { 'estourou-limite-do-harness' }
  $c.Segundos = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  Start-Sleep -Seconds 2

  $nucleo = [ordered]@{}; $aux = [ordered]@{}
  foreach ($k in $cfg.Nucleo.Keys) { try { $nucleo[$k] = [bool](& $cfg.Nucleo[$k] $c) } catch { $nucleo[$k] = $false } }
  foreach ($k in $cfg.Aux.Keys)    { try { $aux[$k]    = [bool](& $cfg.Aux[$k] $c) }    catch { $aux[$k] = $false } }
  Matar (Join-Path $c.Mock 'pid-filho.txt'); Matar (Join-Path $c.Mock 'pid-mock.txt')
  $okN = -not ($nucleo.Values -contains $false)
  $okA = -not ($aux.Values -contains $false)
  $pts = $(if ($okN) { 4 } else { 0 }) + $(if ($okN -and $okA) { 1 } else { 0 })
  [ordered]@{ cenario = $nome; pontos = $pts; nucleo_ok = $okN; auxiliar_ok = $okA
    exit_code = $c.Exit; segundos = $c.Segundos; chamadas_ao_executor = (Chamadas $c.Mock)
    nucleo = $nucleo; auxiliar = $aux }
}

# ---------- Verificações reutilizáveis ----------
$ArgsOk        = { param($c) Args-Validos $c.Mock }
$HeadIgualBase = { param($c) (GitR $c.Repo rev-parse HEAD) -eq $c.BaseCommit }
# Árvore limpa: ignora .claude/ (ex.: settings.local.json não rastreado é saída documentada — A3/M4)
$ArvoreLimpa   = { param($c) -not (@(GitR $c.Repo status --porcelain) | Where-Object { $_ -and $_.Substring(3) -notlike '.claude/*' }) }
$Notificou     = { param($c) $f = Join-Path $c.Estado 'notificacoes.txt'; (Test-Path $f) -and ((Get-Item $f).Length -gt 0) }
$SemLixo       = { param($c) -not (Test-Path (Join-Path $c.Repo 'src/lixo.tmp')) }
function Um-Commit($c, [string]$id) {
  ((GitR $c.Repo rev-list --count "$($c.BaseCommit)..HEAD") -eq '1') -and
  ((GitR $c.Repo log -1 --format=%s) -ceq "tarefa ${id}: Corrigir Soma ($id)")
}
function Estado-Campo($c, [string]$campo) { (Get-Content (Join-Path $c.Estado 'estado.json') -Raw | ConvertFrom-Json).$campo }

$Padrao = @{ TimeoutSec = 60; MaxTentativas = 3; MaxCustoUsd = 10; MaxMinutos = 30 }
function Cfg([hashtable]$extra) { $h = $Padrao.Clone(); foreach ($k in $extra.Keys) { $h[$k] = $extra[$k] }; $h }

$Cenarios = [ordered]@{
  'C1-sucesso' = Cfg @{ Plano = @{ T1 = @('sucesso') }; Tarefas = @((Tarefa 'T1'))
    Nucleo = [ordered]@{
      'exit code 0'                       = { param($c) $c.Exit -eq 0 }
      'T1 = done'                         = { param($c) (Tarefa-Campo $c.Tarefas 'T1' 'status') -eq 'done' }
      '1 commit "tarefa T1: <titulo>"'    = { param($c) Um-Commit $c 'T1' }
      'teste passa no HEAD'               = { param($c) Push-Location $c.Repo; try { & pwsh -NoProfile -File testes/teste-calc.ps1 | Out-Null; $LASTEXITCODE -eq 0 } finally { Pop-Location } }
      'argumentos do executor corretos'   = $ArgsOk }
    Aux = [ordered]@{
      'árvore limpa (ignora .claude/)'    = $ArvoreLimpa
      'estado.json com os 7 campos'       = { param($c) $n = (Get-Content (Join-Path $c.Estado 'estado.json') -Raw | ConvertFrom-Json).PSObject.Properties.Name
                                              -not (@('tarefa_atual','tentativa','commit_base','custo_acumulado_usd','inicio','atualizado_em','status_execucao') | Where-Object { $_ -notin $n }) }
      'log.jsonl válido (ts e evento)'    = { param($c) $l = @(Get-Content (Join-Path $c.Estado 'log.jsonl') | Where-Object { $_.Trim() })
                                              ($l.Count -ge 1) -and -not ($l | Where-Object { $o = $_ | ConvertFrom-Json; -not ($o.ts -and $o.evento) }) } } }

  'C2-falha-e-dependencias' = Cfg @{ Plano = @{ T1 = @('falha'); T3 = @('sucesso') }
    Tarefas = @((Tarefa 'T1'), (Tarefa 'T2' @('T1')), (Tarefa 'T3'))
    Nucleo = [ordered]@{
      'exit code 1'                       = { param($c) $c.Exit -eq 1 }
      'T1 = failed com 3 tentativas'      = { param($c) ((Tarefa-Campo $c.Tarefas 'T1' 'status') -eq 'failed') -and ([int](Tarefa-Campo $c.Tarefas 'T1' 'tentativas') -eq 3) }
      'T2 (depende de T1) = pending'      = { param($c) (Tarefa-Campo $c.Tarefas 'T2' 'status') -eq 'pending' }
      'T3 (independente) = done'          = { param($c) (Tarefa-Campo $c.Tarefas 'T3' 'status') -eq 'done' }
      'argumentos do executor corretos'   = $ArgsOk }
    Aux = [ordered]@{
      'T1 chamada 3x e T2 nunca'          = { param($c) ((Chamadas $c.Mock 'T1') -eq 3) -and ((Chamadas $c.Mock 'T2') -eq 0) }
      'arquivo fora do repo preservado'   = { param($c) Test-Path $c.Sentinela }
      'árvore limpa e sem lixo'           = { param($c) (& $ArvoreLimpa $c) -and (& $SemLixo $c) } } }

  'C3-altera-teste' = Cfg @{ Plano = @{ T1 = @('altera_teste'); T2 = @('sucesso') }
    Tarefas = @((Tarefa 'T1'), (Tarefa 'T2'))
    Nucleo = [ordered]@{
      'exit code 2'                       = { param($c) $c.Exit -eq 2 }
      'T1 = hold'                         = { param($c) (Tarefa-Campo $c.Tarefas 'T1' 'status') -eq 'hold' }
      'T2 (independente) não iniciada'    = { param($c) ((Tarefa-Campo $c.Tarefas 'T2' 'status') -eq 'pending') -and ((Chamadas $c.Mock 'T2') -eq 0) }
      'sem commit (HEAD = base)'          = $HeadIgualBase
      'argumentos do executor corretos'   = $ArgsOk }
    Aux = [ordered]@{
      'evidência preservada (sem rollback)' = { param($c) (Get-Content (Join-Path $c.Repo 'testes/teste-calc.ps1') -Raw).Trim() -eq 'exit 0' }
      'notificação gravada'               = $Notificou } }

  'C4-trava' = Cfg @{ Plano = @{ T1 = @('trava') }; Tarefas = @((Tarefa 'T1')); TimeoutSec = 15; MaxTentativas = 1
    Nucleo = [ordered]@{
      'terminou em até 75 s'              = { param($c) ($c.Exit -is [int]) -and ($c.Segundos -le 75) }
      'exit code 1'                       = { param($c) $c.Exit -eq 1 }
      'T1 = failed'                       = { param($c) (Tarefa-Campo $c.Tarefas 'T1' 'status') -eq 'failed' }
      'executor e processo filho encerrados' = { param($c) (Test-Path (Join-Path $c.Mock 'pid-filho.txt')) -and -not (Processo-Vivo (Join-Path $c.Mock 'pid-mock.txt')) -and -not (Processo-Vivo (Join-Path $c.Mock 'pid-filho.txt')) }
      'argumentos do executor corretos'   = $ArgsOk }
    Aux = [ordered]@{
      'HEAD = base, árvore limpa, sem lixo' = { param($c) (& $HeadIgualBase $c) -and (& $ArvoreLimpa $c) -and (& $SemLixo $c) } } }

  'C5-custo' = Cfg @{ Plano = @{ T1 = @('custo'); T2 = @('sucesso') }; Tarefas = @((Tarefa 'T1'), (Tarefa 'T2')); MaxCustoUsd = 5
    Nucleo = [ordered]@{
      'exit code 3'                       = { param($c) $c.Exit -eq 3 }
      'T1 concluída (done + commit)'      = { param($c) ((Tarefa-Campo $c.Tarefas 'T1' 'status') -eq 'done') -and (Um-Commit $c 'T1') }
      'T2 não iniciada'                   = { param($c) ((Tarefa-Campo $c.Tarefas 'T2' 'status') -eq 'pending') -and ((Chamadas $c.Mock 'T2') -eq 0) }
      'argumentos do executor corretos'   = $ArgsOk }
    Aux = [ordered]@{
      'custo_acumulado_usd >= 6'          = { param($c) [double](Estado-Campo $c 'custo_acumulado_usd') -ge 6 }
      'notificação gravada'               = $Notificou } }

  'C6-retomada' = Cfg @{ Plano = @{ T1 = @('trava', 'sucesso') }; Tarefas = @((Tarefa 'T0' @() 'done'), (Tarefa 'T1'))
                         TimeoutSec = 120; Interromper = $true
    Nucleo = [ordered]@{
      'exit code 0 na retomada'           = { param($c) $c.Exit -eq 0 }
      'T1 = done com 2 tentativas'        = { param($c) ((Tarefa-Campo $c.Tarefas 'T1' 'status') -eq 'done') -and ([int](Tarefa-Campo $c.Tarefas 'T1' 'tentativas') -eq 2) }
      'exatamente 1 commit de T1'         = { param($c) Um-Commit $c 'T1' }
      'argumentos do executor corretos'   = $ArgsOk }
    Aux = [ordered]@{
      'T0 (done) nunca chamada'           = { param($c) (Chamadas $c.Mock 'T0') -eq 0 }
      'lixo da execução interrompida removido' = $SemLixo
      'custo acumulado preservado (>= 0.02)' = { param($c) [double](Estado-Campo $c 'custo_acumulado_usd') -ge 0.02 } } }

  'C7-tempo' = Cfg @{ Plano = @{ T1 = @('lento'); T2 = @('sucesso') }; Tarefas = @((Tarefa 'T1'), (Tarefa 'T2')); MaxMinutos = 0.05
    Nucleo = [ordered]@{
      'exit code 3'                       = { param($c) $c.Exit -eq 3 }
      'T1 concluída (done + commit)'      = { param($c) ((Tarefa-Campo $c.Tarefas 'T1' 'status') -eq 'done') -and (Um-Commit $c 'T1') }
      'T2 não iniciada'                   = { param($c) ((Tarefa-Campo $c.Tarefas 'T2' 'status') -eq 'pending') -and ((Chamadas $c.Mock 'T2') -eq 0) }
      'argumentos do executor corretos'   = $ArgsOk }
    Aux = [ordered]@{ 'notificação gravada' = $Notificou } }

  'C8-erro-e-exclusao' = Cfg @{ Plano = @{ T1 = @('erro', 'sucesso'); T2 = @('apaga') }; Tarefas = @((Tarefa 'T1'), (Tarefa 'T2'))
    Nucleo = [ordered]@{
      'exit code 2'                       = { param($c) $c.Exit -eq 2 }
      'T1 = done com 2 tentativas'        = { param($c) ((Tarefa-Campo $c.Tarefas 'T1' 'status') -eq 'done') -and ([int](Tarefa-Campo $c.Tarefas 'T1' 'tentativas') -eq 2) }
      'T2 = hold (apagou arquivo rastreado)' = { param($c) (Tarefa-Campo $c.Tarefas 'T2' 'status') -eq 'hold' }
      'só o commit de T1'                 = { param($c) Um-Commit $c 'T1' }
      'argumentos do executor corretos'   = $ArgsOk }
    Aux = [ordered]@{
      'evidência preservada (arquivo continua apagado)' = { param($c) -not (Test-Path (Join-Path $c.Repo 'src/extra.ps1')) }
      'notificação gravada'               = $Notificou } }
}

if ($trapaca -and -not $PermitirTrapaca) {
  Write-Host 'DESCLASSIFICADO: o controlador referencia MOCK_ (variáveis do simulado). Parte A = 0.'
  $resultados = foreach ($nome in $Cenarios.Keys) { [ordered]@{ cenario = $nome; pontos = 0; nucleo_ok = $false; auxiliar_ok = $false; motivo = 'referencia MOCK_' } }
} else {
  $resultados = foreach ($nome in $Cenarios.Keys) {
    Write-Host "== $nome =="
    $r = Rodar-Cenario $nome $Cenarios[$nome]
    foreach ($k in $r.nucleo.Keys)   { Write-Host ("  [{0}] núcleo   {1}" -f $(if ($r.nucleo[$k]) { 'ok' } else { 'X ' }), $k) }
    foreach ($k in $r.auxiliar.Keys) { Write-Host ("  [{0}] auxiliar {1}" -f $(if ($r.auxiliar[$k]) { 'ok' } else { 'X ' }), $k) }
    Write-Host ("  => {0}/5 pts (exit={1}, {2}s)" -f $r.pontos, $r.exit_code, $r.segundos)
    $r
  }
}
$total = [int]((@($resultados | ForEach-Object { $_.pontos }) | Measure-Object -Sum).Sum)
$saida = [ordered]@{ kit = (Split-Path $KitDir -Leaf); sha256_controlador = (Get-FileHash $Controlador -Algorithm SHA256).Hash
  harness_versao = 'v0.2-rascunho'; plataforma = $(if ($IsWindows) { 'windows' } else { 'linux' })
  referencia_mock = $trapaca; executado_em = (Get-Date).ToString('o')
  pontos_objetivos = $total; maximo = 40; cenarios = @($resultados) }
$saida | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $SaidaDir 'resultados.json')
Write-Host "TOTAL OBJETIVO: $total / 40"
exit 0
