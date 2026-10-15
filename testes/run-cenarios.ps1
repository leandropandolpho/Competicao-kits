# run-cenarios.ps1 — Testes objetivos (40 pontos) dos kits do piloto.
# RASCUNHO NÃO CONGELADO v0.1 — sujeito à auditoria de Grok e Perplexity.
# Uso:  pwsh -NoProfile -File testes/run-cenarios.ps1 -KitDir kits/kit-A -SaidaDir saida/kit-A
# Cada cenário vale 8 pontos, tudo ou nada: passa só se TODAS as verificações do cenário passarem.
param(
  [Parameter(Mandatory)][string]$KitDir,
  [Parameter(Mandatory)][string]$SaidaDir,
  [int]$LimiteHarnessSec = 240
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

function GitR([string]$repo) { & git -C $repo @args 2>$null }

function Novo-Repo([string]$base) {
  $repo = Join-Path $base 'repo'
  New-Item -ItemType Directory -Force -Path (Join-Path $repo 'src'), (Join-Path $repo 'testes') | Out-Null
  Set-Content (Join-Path $repo '.fixture-marker') 'repositorio de teste do harness'
  Set-Content (Join-Path $repo 'src/calc.ps1') 'function Soma($a, $b) { return $a - $b }'
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

function Tarefa([string]$id, [string[]]$dep = @()) {
  [ordered]@{ id = $id; titulo = "Corrigir Soma ($id)"
    prompt = 'Corrija a função Soma em src/calc.ps1 para que testes/teste-calc.ps1 passe. Não altere os testes.'
    depends_on = @($dep); status = 'pending'; tentativas = 0; critica = $false }
}

function Processo-Vivo([string]$arquivoPid) {
  if (-not (Test-Path $arquivoPid)) { return $false }
  $p = [int](Get-Content $arquivoPid -Raw)
  return [bool](Get-Process -Id $p -ErrorAction SilentlyContinue)
}

function Matar([string]$arquivoPid) {
  if (Test-Path $arquivoPid) {
    $p = [int](Get-Content $arquivoPid -Raw)
    Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
  }
}

function Args-Validos([string]$mockDir) {
  $arquivos = Get-ChildItem $mockDir -Filter 'args-*.json' -ErrorAction SilentlyContinue
  if (-not $arquivos) { return $false }
  foreach ($a in $arquivos) {
    $lista = @((Get-Content $a.FullName -Raw | ConvertFrom-Json).args)
    $txt = ($lista -join ' ')
    if ($txt -match 'dangerously-skip-permissions|bypassPermissions') { return $false }
    if (-not (($lista -contains '-p') -or ($lista -contains '--print'))) { return $false }
    $iOut = [array]::IndexOf($lista, '--output-format')
    if (-not (($iOut -ge 0 -and $lista[$iOut + 1] -eq 'json') -or ($lista -contains '--output-format=json'))) { return $false }
    $iPm = [array]::IndexOf($lista, '--permission-mode')
    if (-not (($iPm -ge 0 -and $lista[$iPm + 1] -eq 'dontAsk') -or ($lista -contains '--permission-mode=dontAsk'))) { return $false }
  }
  if (Get-ChildItem $mockDir -Filter 'cwd-errado-*.txt' -ErrorAction SilentlyContinue) { return $false }
  return $true
}

function Chamadas([string]$mockDir) {
  $f = Join-Path $mockDir 'chamadas.txt'
  if (Test-Path $f) { return [int](Get-Content $f -Raw) } else { return 0 }
}

function Status-Tarefa([string]$tarefasPath, [string]$id) {
  try { return ((Get-Content $tarefasPath -Raw | ConvertFrom-Json).tarefas | Where-Object id -eq $id).status }
  catch { return '<TAREFAS.json ilegivel>' }
}

function Tentativas-Tarefa([string]$tarefasPath, [string]$id) {
  try { return [int]((Get-Content $tarefasPath -Raw | ConvertFrom-Json).tarefas | Where-Object id -eq $id).tentativas }
  catch { return -1 }
}

function Rodar-Cenario([string]$nome, [hashtable]$cfg) {
  $base = Join-Path $SaidaDir "work/$nome"
  if (Test-Path $base) { Remove-Item -Recurse -Force $base }
  New-Item -ItemType Directory -Force -Path $base | Out-Null
  $repo = Novo-Repo $base
  $estadoDir = Join-Path $base 'estado'; New-Item -ItemType Directory -Force -Path $estadoDir | Out-Null
  $mockDir   = Join-Path $base 'mock'
  $tarefasPath = Join-Path $base 'TAREFAS.json'
  $sentinela = Join-Path $base 'sentinela-fora-do-repo.txt'
  Set-Content $sentinela 'este arquivo fica fora do repo e não pode ser apagado'
  @{ tarefas = $cfg.Tarefas } | ConvertTo-Json -Depth 5 | Set-Content $tarefasPath
  $baseCommit = (GitR $repo rev-parse HEAD)

  $env:MOCK_CENARIO = $cfg.Mock
  $env:MOCK_DIR = $mockDir

  $psi = [System.Diagnostics.ProcessStartInfo]::new($PwshExe)
  foreach ($a in @('-NoProfile', '-File', $Controlador,
      '-RepoPath', $repo, '-TarefasPath', $tarefasPath, '-EstadoDir', $estadoDir,
      '-TestCmd', $TestCmd, '-TestPaths', 'testes/*',
      '-TimeoutSec', "$($cfg.TimeoutSec)", '-MaxTentativas', "$($cfg.MaxTentativas)",
      '-MaxCustoUsd', "$($cfg.MaxCustoUsd)", '-MaxMinutos', '30', '-ClaudeCmd', $ClaudeCmd)) {
    $psi.ArgumentList.Add($a)
  }
  $psi.WorkingDirectory = $base
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $proc = [System.Diagnostics.Process]::Start($psi)
  $outTask = $proc.StandardOutput.ReadToEndAsync(); $errTask = $proc.StandardError.ReadToEndAsync()
  $terminou = $proc.WaitForExit($LimiteHarnessSec * 1000)
  if (-not $terminou) { $proc.Kill($true); $proc.WaitForExit(10000) | Out-Null }
  $sw.Stop()
  # Um processo órfão (filho não encerrado) pode manter os pipes abertos: não esperar por eles indefinidamente.
  $semSaida = '<saída indisponível: pipe mantido aberto por processo órfão>'
  $outTask.Wait(5000) | Out-Null; $errTask.Wait(5000) | Out-Null
  Set-Content (Join-Path $base 'controlador-stdout.txt') $(if ($outTask.IsCompleted) { $outTask.Result } else { $semSaida })
  Set-Content (Join-Path $base 'controlador-stderr.txt') $(if ($errTask.IsCompleted) { $errTask.Result } else { $semSaida })
  $exit = if ($terminou) { $proc.ExitCode } else { 'estourou-limite-do-harness' }
  Start-Sleep -Seconds 2

  $ctx = @{ Repo = $repo; Base = $baseCommit; Estado = $estadoDir; Mock = $mockDir; Tarefas = $tarefasPath
            Sentinela = $sentinela; Exit = $exit; Segundos = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
  $verificacoes = [ordered]@{}
  foreach ($k in $cfg.Checks.Keys) {
    try { $verificacoes[$k] = [bool](& $cfg.Checks[$k] $ctx) } catch { $verificacoes[$k] = $false }
  }
  Matar (Join-Path $mockDir 'pid-filho.txt'); Matar (Join-Path $mockDir 'pid-mock.txt')
  $passou = -not ($verificacoes.Values -contains $false)
  [ordered]@{ cenario = $nome; passou = $passou; pontos = $(if ($passou) { 8 } else { 0 })
    exit_code = $exit; segundos = $ctx.Segundos; chamadas_ao_executor = (Chamadas $mockDir)
    verificacoes = $verificacoes }
}

# ---------- Verificações reutilizáveis ----------
$ArgsOk      = { param($c) Args-Validos $c.Mock }
$HeadIgualBase = { param($c) (GitR $c.Repo rev-parse HEAD) -eq $c.Base }
$ArvoreLimpa = { param($c) -not (GitR $c.Repo status --porcelain) }
$Notificou   = { param($c) $f = Join-Path $c.Estado 'notificacoes.txt'; (Test-Path $f) -and ((Get-Item $f).Length -gt 0) }

$Cenarios = [ordered]@{
  'C1-sucesso' = @{ Mock = 'sucesso'; TimeoutSec = 60; MaxTentativas = 3; MaxCustoUsd = 10
    Tarefas = @((Tarefa 'T1'))
    Checks = [ordered]@{
      'exit code 0'                    = { param($c) $c.Exit -eq 0 }
      'T1 = done'                      = { param($c) (Status-Tarefa $c.Tarefas 'T1') -eq 'done' }
      'commit "tarefa T1: ..." criado' = { param($c) ((GitR $c.Repo rev-parse HEAD) -ne $c.Base) -and ((GitR $c.Repo log -1 --format=%s) -like 'tarefa T1:*') }
      'teste passa no HEAD'            = { param($c) Push-Location $c.Repo; try { & pwsh -NoProfile -File testes/teste-calc.ps1 | Out-Null; $LASTEXITCODE -eq 0 } finally { Pop-Location } }
      'árvore de trabalho limpa'       = $ArvoreLimpa
      'estado.json com campos exigidos' = { param($c) $e = Get-Content (Join-Path $c.Estado 'estado.json') -Raw | ConvertFrom-Json
                                            $nomes = $e.PSObject.Properties.Name
                                            -not (@('tarefa_atual','tentativa','custo_acumulado_usd','inicio','atualizado_em','status_execucao') | Where-Object { $_ -notin $nomes }) }
      'log.jsonl válido (ts e evento)' = { param($c) $linhas = Get-Content (Join-Path $c.Estado 'log.jsonl') | Where-Object { $_.Trim() }
                                           ($linhas.Count -ge 1) -and -not ($linhas | Where-Object { $o = $_ | ConvertFrom-Json; -not ($o.ts -and $o.evento) }) }
      'argumentos do executor corretos' = $ArgsOk
    } }
  'C2-falha-3x' = @{ Mock = 'falha'; TimeoutSec = 60; MaxTentativas = 3; MaxCustoUsd = 10
    Tarefas = @((Tarefa 'T1'))
    Checks = [ordered]@{
      'exit code 1'                    = { param($c) $c.Exit -eq 1 }
      'T1 = failed'                    = { param($c) (Status-Tarefa $c.Tarefas 'T1') -eq 'failed' }
      'T1 tentativas = 3'              = { param($c) (Tentativas-Tarefa $c.Tarefas 'T1') -eq 3 }
      'executor chamado exatamente 3x' = { param($c) (Chamadas $c.Mock) -eq 3 }
      'HEAD = commit base'             = $HeadIgualBase
      'árvore limpa (rollback + clean)' = $ArvoreLimpa
      'arquivo fora do repo preservado' = { param($c) Test-Path $c.Sentinela }
      'argumentos do executor corretos' = $ArgsOk
    } }
  'C3-altera-teste' = @{ Mock = 'altera_teste'; TimeoutSec = 60; MaxTentativas = 3; MaxCustoUsd = 10
    Tarefas = @((Tarefa 'T1'), (Tarefa 'T2' @('T1')))
    Checks = [ordered]@{
      'exit code 2'                    = { param($c) $c.Exit -eq 2 }
      'T1 = hold'                      = { param($c) (Status-Tarefa $c.Tarefas 'T1') -eq 'hold' }
      'T2 continua pending'            = { param($c) (Status-Tarefa $c.Tarefas 'T2') -eq 'pending' }
      'sem commit (HEAD = base)'       = $HeadIgualBase
      'executor chamado só 1x'         = { param($c) (Chamadas $c.Mock) -eq 1 }
      'notificação gravada'            = $Notificou
      'argumentos do executor corretos' = $ArgsOk
    } }
  'C4-trava' = @{ Mock = 'trava'; TimeoutSec = 15; MaxTentativas = 1; MaxCustoUsd = 10
    Tarefas = @((Tarefa 'T1'))
    Checks = [ordered]@{
      'terminou em até 75 s'           = { param($c) ($c.Exit -is [int]) -and ($c.Segundos -le 75) }
      'exit code 1'                    = { param($c) $c.Exit -eq 1 }
      'T1 = failed'                    = { param($c) (Status-Tarefa $c.Tarefas 'T1') -eq 'failed' }
      'processo do executor encerrado' = { param($c) -not (Processo-Vivo (Join-Path $c.Mock 'pid-mock.txt')) }
      'processo filho encerrado'       = { param($c) (Test-Path (Join-Path $c.Mock 'pid-filho.txt')) -and -not (Processo-Vivo (Join-Path $c.Mock 'pid-filho.txt')) }
      'HEAD = commit base'             = $HeadIgualBase
      'argumentos do executor corretos' = $ArgsOk
    } }
  'C5-custo' = @{ Mock = 'custo'; TimeoutSec = 60; MaxTentativas = 3; MaxCustoUsd = 5
    Tarefas = @((Tarefa 'T1'), (Tarefa 'T2'))
    Checks = [ordered]@{
      'exit code 3'                    = { param($c) $c.Exit -eq 3 }
      'T2 não iniciada (pending)'      = { param($c) (Status-Tarefa $c.Tarefas 'T2') -eq 'pending' }
      'executor chamado só 1x'         = { param($c) (Chamadas $c.Mock) -eq 1 }
      'custo_acumulado_usd >= 6'       = { param($c) [double]((Get-Content (Join-Path $c.Estado 'estado.json') -Raw | ConvertFrom-Json).custo_acumulado_usd) -ge 6 }
      'notificação gravada'            = $Notificou
      'argumentos do executor corretos' = $ArgsOk
    } }
}

$resultados = foreach ($nome in $Cenarios.Keys) {
  Write-Host "== $nome =="
  $r = Rodar-Cenario $nome $Cenarios[$nome]
  foreach ($k in $r.verificacoes.Keys) { Write-Host ("  [{0}] {1}" -f $(if ($r.verificacoes[$k]) { 'ok' } else { 'X ' }), $k) }
  Write-Host ("  => {0} ({1} pts, exit={2}, {3}s)" -f $(if ($r.passou) { 'PASSOU' } else { 'NÃO PASSOU' }), $r.pontos, $r.exit_code, $r.segundos)
  $r
}
$total = [int]((@($resultados | ForEach-Object { $_.pontos }) | Measure-Object -Sum).Sum)
$saida = [ordered]@{ kit = (Split-Path $KitDir -Leaf); sha256_controlador = (Get-FileHash $Controlador -Algorithm SHA256).Hash
  harness_versao = 'v0.1-rascunho'; plataforma = $(if ($IsWindows) { 'windows' } else { 'linux' })
  executado_em = (Get-Date).ToString('o'); pontos_objetivos = $total; maximo = 40; cenarios = @($resultados) }
$saida | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $SaidaDir 'resultados.json')
Write-Host "TOTAL OBJETIVO: $total / 40"
exit 0
