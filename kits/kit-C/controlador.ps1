# controlador.ps1 — Controlador determinístico de execução headless (Claude Code)
param(
  [Parameter(Mandatory)][string]$RepoPath,     # pasta do repositório git onde o executor trabalha
  [Parameter(Mandatory)][string]$TarefasPath,  # caminho do TAREFAS.json (FORA do repositório)
  [Parameter(Mandatory)][string]$EstadoDir,    # pasta de estado/log/notificações (FORA do repositório)
  [Parameter(Mandatory)][string]$TestCmd,      # comando de teste; código de saída 0 = passou
  [Parameter(Mandatory)][string[]]$TestPaths,  # padrões dos arquivos de teste (seção 3.4)
  [int]$TimeoutSec     = 900,                  # tempo máximo por chamada ao executor
  [int]$MaxTentativas  = 3,                    # tentativas por tarefa
  [double]$MaxCustoUsd = 10,                   # teto de custo acumulado da execução
  [double]$MaxMinutos  = 240,                  # teto de tempo total da execução (aceita fração: 0.05 = 3 s)
  [string]$ClaudeCmd   = 'claude'              # executável do executor (o teste troca por um simulado)
)

$ErrorActionPreference = 'Stop'

# ---------- Inicialização e validação de isolamento de caminhos ----------
if (-not (Test-Path -LiteralPath $RepoPath)) { throw "Repositório não encontrado: $RepoPath" }
if (-not (Test-Path -LiteralPath $TarefasPath)) { throw "Arquivo de tarefas não encontrado: $TarefasPath" }
New-Item -ItemType Directory -Force -Path $EstadoDir | Out-Null

$RepoPath    = (Resolve-Path -LiteralPath $RepoPath).Path
$TarefasPath = (Resolve-Path -LiteralPath $TarefasPath).Path
$EstadoDir   = (Resolve-Path -LiteralPath $EstadoDir).Path
$PwshExe     = (Get-Process -Id $PID).Path

$EstadoFile       = Join-Path $EstadoDir 'estado.json'
$LogFile          = Join-Path $EstadoDir 'log.jsonl'
$NotificacoesFile = Join-Path $EstadoDir 'notificacoes.txt'

# Garante que git reset/clean nunca atinjam estado ou tarefas fora do repositório
$repoPrefix = $RepoPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
if ($TarefasPath.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
    $EstadoDir.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Violação de segurança: TarefasPath e EstadoDir devem ficar fora de RepoPath."
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
  throw "RepoPath não contém um repositório git válido: $RepoPath"
}

# ---------- Persistência atômica, log e notificações ----------
function Gravar-JsonAtomico([string]$Caminho, [object]$Dados) {
  # Escrita atômica via arquivo temporário + substituição para evitar corrupção em interrupções
  $dir = Split-Path -Parent $Caminho
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $tmp = "$Caminho.tmp.$PID.$([guid]::NewGuid().ToString('N').Substring(0, 8))"
  $json = $Dados | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
  for ($tent = 1; $tent -le 5; $tent++) {
    try {
      [System.IO.File]::Move($tmp, $Caminho, $true)
      break
    } catch {
      if ($tent -eq 5) { throw }
      Start-Sleep -Milliseconds 25
    }
  }
}

function Limpar-Temporarios([string]$Pasta) {
  Get-ChildItem -LiteralPath $Pasta -Filter '*.tmp.*' -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

function Registrar-Log([string]$Evento, [hashtable]$Detalhes = @{}) {
  $entrada = [ordered]@{
    ts     = (Get-Date).ToString('o')
    evento = $Evento
  }
  foreach ($k in $Detalhes.Keys) { $entrada[$k] = $Detalhes[$k] }
  $linha = $entrada | ConvertTo-Json -Compress -Depth 6
  Add-Content -LiteralPath $LogFile -Value $linha -Encoding utf8
}

function Notificar([string]$Mensagem) {
  # Função isolada de notificação: grava em notificacoes.txt no diretório de estado
  $ts = (Get-Date).ToString('o')
  Add-Content -LiteralPath $NotificacoesFile -Value "[$ts] $Mensagem" -Encoding utf8
}

function Ler-Tarefas() {
  return (Get-Content -LiteralPath $TarefasPath -Raw -Encoding utf8 | ConvertFrom-Json)
}

function Salvar-Tarefas([object]$DocTarefas) {
  Gravar-JsonAtomico -Caminho $TarefasPath -Dados $DocTarefas
}

function Atualizar-Estado([AllowNull()]$TarefaAtual, [int]$Tentativa, [string]$CommitBase, [string]$StatusExecucao) {
  $agora = (Get-Date).ToString('o')
  $estado = [ordered]@{
    tarefa_atual        = $TarefaAtual
    tentativa           = [int]$Tentativa
    commit_base         = [string]$CommitBase
    custo_acumulado_usd = [double]([math]::Round($script:CustoAcumulado, 6))
    inicio              = [string]$script:InicioExecucaoIso
    atualizado_em       = $agora
    status_execucao     = $StatusExecucao
  }
  Gravar-JsonAtomico -Caminho $EstadoFile -Dados $estado
}

# ---------- Operações Git restritas a $RepoPath ----------
function Invoke-Git([string[]]$GitArgs) {
  $saida = & git -C $RepoPath @GitArgs 2>$null
  return $saida
}

function Obter-HeadAtual() {
  return ("$(Invoke-Git @('rev-parse', 'HEAD'))").Trim()
}

function Invoke-GitRollback([string]$CommitBase) {
  # Rollback estritamente confinado a $RepoPath; preserva .claude/settings.local.json se existir
  & git -C $RepoPath reset -q --hard $CommitBase 2>$null | Out-Null
  & git -C $RepoPath clean -qfd -e '.claude/settings.local.json' 2>$null | Out-Null
}

function Invoke-GitCommit([string]$IdTarefa, [string]$TituloTarefa) {
  & git -C $RepoPath add -A 2>$null | Out-Null
  # Evita comitar .claude/settings.local.json caso tenha sido criado como não rastreado
  $localSettings = Join-Path $RepoPath '.claude/settings.local.json'
  if (Test-Path -LiteralPath $localSettings) {
    $eraRastreado = & git -C $RepoPath ls-files --error-unmatch '.claude/settings.local.json' 2>$null
    if ($LASTEXITCODE -ne 0) {
      & git -C $RepoPath reset -q HEAD -- '.claude/settings.local.json' 2>$null | Out-Null
    }
  }
  $msg = "tarefa ${IdTarefa}: ${TituloTarefa}"
  & git -C $RepoPath commit -q --allow-empty -m $msg 2>$null | Out-Null
}

# ---------- Padrões de teste ($TestPaths) e verificação de gatilhos R1 ----------
function Expandir-PadroesTeste([string[]]$Brutos) {
  return @(
    $Brutos | ForEach-Object { $_ -split ',' } |
      ForEach-Object { $_.Trim().Replace('\', '/').TrimStart('/') } |
      Where-Object { $_ -ne '' }
  )
}

function Caminho-EhTeste([string]$RelPath, [string[]]$Padroes) {
  $norm = $RelPath.Replace('\', '/').TrimStart('/')
  foreach ($p in $Padroes) {
    if ($norm -like $p) { return $true }
  }
  return $false
}

function Obter-ArquivosRepositorio() {
  # Lista todos os arquivos presentes na árvore de trabalho (rastreados e não rastreados), exceto .git e .claude
  $raizNorm = $RepoPath.TrimEnd('\', '/')
  $todos = Get-ChildItem -LiteralPath $RepoPath -Recurse -File -Force -ErrorAction SilentlyContinue
  $relativos = [System.Collections.Generic.List[string]]::new()
  foreach ($arq in $todos) {
    $rel = $arq.FullName.Substring($raizNorm.Length).TrimStart('\', '/').Replace('\', '/')
    if ($rel -like '.git/*' -or $rel -eq '.git' -or $rel -like '.claude/*' -or $rel -eq '.claude') {
      continue
    }
    $relativos.Add($rel)
  }
  return $relativos
}

function Obter-HashesTestes([string[]]$Padroes) {
  # Calcula o SHA-256 real de todos os arquivos que casam com $TestPaths (não confia apenas em deny)
  $mapa = [ordered]@{}
  foreach ($rel in (Obter-ArquivosRepositorio)) {
    if (Caminho-EhTeste -RelPath $rel -Padroes $Padroes) {
      $full = Join-Path $RepoPath $rel
      if (Test-Path -LiteralPath $full) {
        $mapa[$rel] = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
      }
    }
  }
  return $mapa
}

function Obter-RastreadosCommit([string]$Commit) {
  $linhas = @(& git -C $RepoPath ls-tree -r --name-only $Commit 2>$null)
  return @(
    $linhas | ForEach-Object { "$_".Trim().Replace('\', '/') } |
      Where-Object { $_ -ne '' -and $_ -notlike '.claude/*' }
  )
}

function Verificar-GatilhosR1([string]$CommitBase, [hashtable]$HashesTestesBase, [string[]]$RastreadosBase, [string[]]$PadroesTeste) {
  $motivos = [System.Collections.Generic.List[string]]::new()

  # 1) Verificação por hash SHA-256 dos arquivos de teste (alterado, criado ou removido)
  $hashesAtuais = Obter-HashesTestes -Padroes $PadroesTeste
  foreach ($arq in $HashesTestesBase.Keys) {
    if (-not $hashesAtuais.Contains($arq)) {
      $motivos.Add("Arquivo de teste removido: $arq")
    } elseif ($hashesAtuais[$arq] -ne $HashesTestesBase[$arq]) {
      $motivos.Add("Arquivo de teste alterado (SHA-256 divergente): $arq")
    }
  }
  foreach ($arq in $hashesAtuais.Keys) {
    if (-not $HashesTestesBase.Contains($arq)) {
      $motivos.Add("Arquivo de teste criado: $arq")
    }
  }

  # 2) Exclusão de qualquer arquivo rastreado que existia no commit base
  foreach ($arqRastreado in $RastreadosBase) {
    $caminhoFisico = Join-Path $RepoPath $arqRastreado
    if (-not (Test-Path -LiteralPath $caminhoFisico)) {
      $motivos.Add("Arquivo rastreado excluído: $arqRastreado")
    }
  }

  # 3) Caminhos tocados desde o commit base (diff + não rastreados): testes, migrations e manifestos
  $diffPaths = @(& git -C $RepoPath diff --name-only $CommitBase 2>$null)
  $untrackedPaths = @(& git -C $RepoPath ls-files --others --exclude-standard 2>$null)
  $tocados = @(
    ($diffPaths + $untrackedPaths) |
      ForEach-Object { "$_".Trim().Replace('\', '/') } |
      Where-Object { $_ -ne '' -and $_ -notlike '.claude/*' } |
      Select-Object -Unique
  )

  $manifestosProtegidos = @('package.json', 'package-lock.json', 'requirements.txt', 'pyproject.toml')
  foreach ($caminho in $tocados) {
    if ((Caminho-EhTeste -RelPath $caminho -Padroes $PadroesTeste) -and ($motivos.Count -eq 0)) {
      $motivos.Add("Arquivo de teste tocado: $caminho")
    }
    if ($caminho -match '(?i)migration') {
      $motivos.Add("Caminho de migration tocado: $caminho")
    }
    $nomeArquivo = Split-Path -Leaf $caminho
    if ($manifestosProtegidos -contains $nomeArquivo.ToLowerInvariant()) {
      $motivos.Add("Manifesto de dependências tocado: $caminho")
    }
  }

  return $motivos
}

# ---------- Execução do comando de teste e do executor headless ----------
function Executar-TesteRepositorio() {
  Push-Location -LiteralPath $RepoPath
  try {
    & $PwshExe -NoProfile -Command $TestCmd *> $null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  } finally {
    Pop-Location
  }
}

function Encerrar-ArvoreProcesso([System.Diagnostics.Process]$Proc) {
  if ($null -eq $Proc) { return }
  try {
    if ($IsWindows -and -not $Proc.HasExited) {
      & taskkill /T /F /PID $Proc.Id 2>$null | Out-Null
    }
  } catch {}
  try {
    if (-not $Proc.HasExited) {
      $Proc.Kill($true)
    }
  } catch {}
  try { $Proc.WaitForExit(5000) | Out-Null } catch {}
}

function Invocar-Executor([string]$PromptTexto) {
  $executavel = $ClaudeCmd
  if (-not [System.IO.Path]::IsPathRooted($ClaudeCmd) -and -not (Test-Path -LiteralPath $ClaudeCmd)) {
    $cmdInfo = Get-Command $ClaudeCmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmdInfo -and $cmdInfo.Source) { $executavel = $cmdInfo.Source }
  }

  $psi = [System.Diagnostics.ProcessStartInfo]::new($executavel)
  # Argumentos obrigatórios do modo headless seguro (sem qualquer flag de bypass)
  foreach ($arg in @('-p', '--output-format', 'json', '--permission-mode', 'dontAsk')) {
    $psi.ArgumentList.Add($arg)
  }

  # Resolve a confiança da pasta em claude -p passando explicitamente --settings quando disponível
  $settingsRepo = Join-Path $RepoPath '.claude/settings.json'
  $settingsKit  = Join-Path $PSScriptRoot '.claude/settings.json'
  if (Test-Path -LiteralPath $settingsRepo) {
    $psi.ArgumentList.Add('--settings')
    $psi.ArgumentList.Add($settingsRepo)
  } elseif (Test-Path -LiteralPath $settingsKit) {
    $psi.ArgumentList.Add('--settings')
    $psi.ArgumentList.Add($settingsKit)
  }

  $psi.WorkingDirectory       = $RepoPath
  $psi.RedirectStandardInput  = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute        = $false

  $proc = [System.Diagnostics.Process]::Start($psi)
  # Envia o prompt integral por stdin para suportar múltiplas linhas em lançadores .cmd no Windows
  try {
    $proc.StandardInput.Write($PromptTexto)
    $proc.StandardInput.Close()
  } catch {}

  $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
  $stderrTask = $proc.StandardError.ReadToEndAsync()

  $terminouNoPrazo = $proc.WaitForExit($TimeoutSec * 1000)
  if (-not $terminouNoPrazo) {
    Encerrar-ArvoreProcesso -Proc $proc
    $stdoutTask.Wait(2000) | Out-Null
    $stderrTask.Wait(2000) | Out-Null
    return [ordered]@{
      falhou    = $true
      motivo    = 'timeout'
      exit_code = -1
      custo_usd = 0.0
      resultado = ''
    }
  }

  $stdoutTask.Wait(5000) | Out-Null
  $stderrTask.Wait(5000) | Out-Null
  $textoOut = if ($stdoutTask.IsCompleted) { $stdoutTask.Result } else { '' }
  $exitCode = $proc.ExitCode

  $dadosJson = $null
  $jsonValido = $false
  if (-not [string]::IsNullOrWhiteSpace($textoOut)) {
    try {
      $dadosJson = $textoOut | ConvertFrom-Json -ErrorAction Stop
      if ($null -ne $dadosJson) { $jsonValido = $true }
    } catch {
      $jsonValido = $false
    }
  }

  $custoChamada = 0.0
  if ($jsonValido -and ($dadosJson.PSObject.Properties.Name -contains 'total_cost_usd') -and ($null -ne $dadosJson.total_cost_usd)) {
    try { $custoChamada = [double]$dadosJson.total_cost_usd } catch { $custoChamada = 0.0 }
  } else {
    Registrar-Log -Evento 'executor_saida_sem_custo_json' -Detalhes @{ exit_code = $exitCode }
  }

  $isError = $false
  if ($jsonValido -and ($dadosJson.PSObject.Properties.Name -contains 'is_error')) {
    $isError = [bool]$dadosJson.is_error
  }

  $falhou = ($exitCode -ne 0) -or (-not $jsonValido) -or $isError
  $motivo = if (-not $jsonValido) { 'saida_nao_json' } elseif ($isError) { 'is_error_true' } elseif ($exitCode -ne 0) { "exit_code_$exitCode" } else { 'ok' }

  return [ordered]@{
    falhou    = $falhou
    motivo    = $motivo
    exit_code = $exitCode
    custo_usd = $custoChamada
    resultado = $(if ($jsonValido -and ($dadosJson.PSObject.Properties.Name -contains 'result')) { "$($dadosJson.result)" } else { '' })
  }
}

# ---------- Retomada e inicialização do ciclo ----------
Limpar-Temporarios -Pasta $EstadoDir
Limpar-Temporarios -Pasta (Split-Path -Parent $TarefasPath)

$PadroesTeste = Expandir-PadroesTeste -Brutos $TestPaths
$CronometroExecucao = [System.Diagnostics.Stopwatch]::StartNew()
$script:InicioExecucaoIso = (Get-Date).ToString('o')
$script:CustoAcumulado = 0.0

$estadoAnterior = $null
if (Test-Path -LiteralPath $EstadoFile) {
  try {
    $estadoAnterior = Get-Content -LiteralPath $EstadoFile -Raw -Encoding utf8 | ConvertFrom-Json
    if ($null -ne $estadoAnterior -and ($estadoAnterior.PSObject.Properties.Name -contains 'custo_acumulado_usd')) {
      $script:CustoAcumulado = [double]$estadoAnterior.custo_acumulado_usd
    }
  } catch {}
}

$docTarefas = Ler-Tarefas
foreach ($t in $docTarefas.tarefas) {
  if ($t.status -eq 'in_progress') {
    $commitRetomada = if ($estadoAnterior -and $estadoAnterior.commit_base) { "$($estadoAnterior.commit_base)" } else { Obter-HeadAtual }
    Invoke-GitRollback -CommitBase $commitRetomada
    if ([int]$t.tentativas -ge $MaxTentativas) {
      $t.status = 'failed'
    } else {
      $t.status = 'pending'
    }
    Salvar-Tarefas -DocTarefas $docTarefas
    Registrar-Log -Evento 'retomada_tarefa_interrompida' -Detalhes @{
      tarefa      = $t.id
      tentativas  = [int]$t.tentativas
      commit_base = $commitRetomada
      custo_prev  = $script:CustoAcumulado
    }
  }
}

$headInicial = Obter-HeadAtual
Atualizar-Estado -TarefaAtual $null -Tentativa 0 -CommitBase $headInicial -StatusExecucao 'rodando'
Registrar-Log -Evento 'inicio_execucao' -Detalhes @{ commit_inicial = $headInicial; custo_inicial = $script:CustoAcumulado }

# ---------- Seleção da próxima tarefa elegível ----------
function Obter-ProximaTarefa([object]$Doc) {
  $concluidas = @($Doc.tarefas | Where-Object { $_.status -eq 'done' } | ForEach-Object { $_.id })
  foreach ($item in $Doc.tarefas) {
    if ($item.status -ne 'pending') { continue }
    $deps = @($item.depends_on | Where-Object { $_ -ne $null -and "$_".Trim() -ne '' })
    $depsOk = $true
    foreach ($d in $deps) {
      if ($concluidas -notcontains $d) { $depsOk = $false; break }
    }
    if ($depsOk) { return $item }
  }
  return $null
}

# ---------- Loop principal de tarefas ----------
while ($true) {
  $docTarefas = Ler-Tarefas
  $tarefa = Obter-ProximaTarefa -Doc $docTarefas
  if ($null -eq $tarefa) { break }

  if ([int]$tarefa.tentativas -ge $MaxTentativas) {
    $tarefa.status = 'failed'
    Salvar-Tarefas -DocTarefas $docTarefas
    Atualizar-Estado -TarefaAtual $tarefa.id -Tentativa ([int]$tarefa.tentativas) -CommitBase (Obter-HeadAtual) -StatusExecucao 'rodando'
    continue
  }

  $atingiuTeto = $false
  $motivoTeto  = ''

  while ($tarefa.status -in @('pending', 'in_progress') -and ([int]$tarefa.tentativas -lt $MaxTentativas)) {
    # Passo 2: Registrar commit base e SHA-256 dos arquivos de teste
    $commitBase       = Obter-HeadAtual
    $hashesTestesBase = Obter-HashesTestes -Padroes $PadroesTeste
    $rastreadosBase   = Obter-RastreadosCommit -Commit $commitBase

    # Passo 3: Incrementar tentativas e gravar TAREFAS.json ANTES de chamar o executor
    $tarefa.tentativas = [int]$tarefa.tentativas + 1
    $tarefa.status     = 'in_progress'
    Salvar-Tarefas -DocTarefas $docTarefas
    Atualizar-Estado -TarefaAtual $tarefa.id -Tentativa ([int]$tarefa.tentativas) -CommitBase $commitBase -StatusExecucao 'rodando'
    Registrar-Log -Evento 'inicio_tentativa' -Detalhes @{
      tarefa         = $tarefa.id
      tentativa      = [int]$tarefa.tentativas
      commit_base    = $commitBase
      arquivos_teste = $hashesTestesBase.Count
    }

    # Passo 4: Chamar o executor
    $resp = Invocar-Executor -PromptTexto ([string]$tarefa.prompt)
    $script:CustoAcumulado += [double]$resp.custo_usd
    Atualizar-Estado -TarefaAtual $tarefa.id -Tentativa ([int]$tarefa.tentativas) -CommitBase $commitBase -StatusExecucao 'rodando'

    # Passo 5 e Passo 7: Gatilhos críticos R1 têm precedência sobre falha do executor e sobre o resultado do teste
    $gatilhosR1 = Verificar-GatilhosR1 -CommitBase $commitBase -HashesTestesBase $hashesTestesBase -RastreadosBase $rastreadosBase -PadroesTeste $PadroesTeste
    if ($gatilhosR1.Count -gt 0) {
      $resumoR1 = ($gatilhosR1 -join '; ')
      $tarefa.status = 'hold'
      Salvar-Tarefas -DocTarefas $docTarefas
      Notificar -Mensagem "HOLD na tarefa $($tarefa.id): gatilho crítico R1 acionado ($resumoR1)."
      Atualizar-Estado -TarefaAtual $tarefa.id -Tentativa ([int]$tarefa.tentativas) -CommitBase $commitBase -StatusExecucao 'hold'
      Registrar-Log -Evento 'hold_gatilho_r1' -Detalhes @{ tarefa = $tarefa.id; tentativa = [int]$tarefa.tentativas; motivos = @($gatilhosR1) }
      exit 2
    }

    if ($resp.falhou) {
      # Passo 5: Executor falhou sem gatilho R1 -> rollback e nova tentativa
      Invoke-GitRollback -CommitBase $commitBase
      Registrar-Log -Evento 'falha_executor_rollback' -Detalhes @{
        tarefa    = $tarefa.id
        tentativa = [int]$tarefa.tentativas
        motivo    = $resp.motivo
      }
      if ([int]$tarefa.tentativas -ge $MaxTentativas) {
        $tarefa.status = 'failed'
      } else {
        $tarefa.status = 'pending'
      }
      Salvar-Tarefas -DocTarefas $docTarefas
    } else {
      # Passo 6: O próprio controlador roda o comando de teste no repositório
      $testePassou = Executar-TesteRepositorio

      # Reconfere gatilhos R1 após a execução do teste por segurança
      $gatilhosPosTeste = Verificar-GatilhosR1 -CommitBase $commitBase -HashesTestesBase $hashesTestesBase -RastreadosBase $rastreadosBase -PadroesTeste $PadroesTeste
      if ($gatilhosPosTeste.Count -gt 0) {
        $resumoR1 = ($gatilhosPosTeste -join '; ')
        $tarefa.status = 'hold'
        Salvar-Tarefas -DocTarefas $docTarefas
        Notificar -Mensagem "HOLD na tarefa $($tarefa.id): gatilho crítico R1 acionado ($resumoR1)."
        Atualizar-Estado -TarefaAtual $tarefa.id -Tentativa ([int]$tarefa.tentativas) -CommitBase $commitBase -StatusExecucao 'hold'
        Registrar-Log -Evento 'hold_gatilho_r1' -Detalhes @{ tarefa = $tarefa.id; tentativa = [int]$tarefa.tentativas; motivos = @($gatilhosPosTeste) }
        exit 2
      }

      if ($testePassou) {
        # Passo 8: Teste passou -> commit exato e status done
        Invoke-GitCommit -IdTarefa $tarefa.id -TituloTarefa $tarefa.titulo
        $tarefa.status = 'done'
        Salvar-Tarefas -DocTarefas $docTarefas
        $novoHead = Obter-HeadAtual
        Atualizar-Estado -TarefaAtual $tarefa.id -Tentativa ([int]$tarefa.tentativas) -CommitBase $novoHead -StatusExecucao 'rodando'
        Registrar-Log -Evento 'tarefa_concluida' -Detalhes @{ tarefa = $tarefa.id; tentativa = [int]$tarefa.tentativas; commit = $novoHead }
      } else {
        # Passo 9: Teste falhou -> rollback somente em $RepoPath e nova tentativa
        Invoke-GitRollback -CommitBase $commitBase
        Registrar-Log -Evento 'teste_falhou_rollback' -Detalhes @{ tarefa = $tarefa.id; tentativa = [int]$tarefa.tentativas }
        if ([int]$tarefa.tentativas -ge $MaxTentativas) {
          $tarefa.status = 'failed'
        } else {
          $tarefa.status = 'pending'
        }
        Salvar-Tarefas -DocTarefas $docTarefas
      }
    }

    # Passo 10: Verificar tetos de custo acumulado e tempo total após concluir a etapa da chamada
    $minutosDecorridos = $CronometroExecucao.Elapsed.TotalMinutes
    if ($script:CustoAcumulado -gt $MaxCustoUsd) {
      $atingiuTeto = $true
      $motivoTeto  = "teto de custo ultrapassado (US$ $([math]::Round($script:CustoAcumulado, 4)) > US$ $MaxCustoUsd)"
      break
    }
    if ($minutosDecorridos -gt $MaxMinutos) {
      $atingiuTeto = $true
      $motivoTeto  = "teto de tempo ultrapassado ($([math]::Round($minutosDecorridos, 3)) min > $MaxMinutos min)"
      break
    }
  }

  if ($atingiuTeto) {
    Notificar -Mensagem "PAUSA após tarefa $($tarefa.id): $motivoTeto."
    Atualizar-Estado -TarefaAtual $tarefa.id -Tentativa ([int]$tarefa.tentativas) -CommitBase (Obter-HeadAtual) -StatusExecucao 'pausado'
    Registrar-Log -Evento 'pausa_limite' -Detalhes @{ tarefa = $tarefa.id; motivo = $motivoTeto; custo_acumulado_usd = $script:CustoAcumulado }
    exit 3
  }
}

# ---------- Consolidação do código de saída (3.7) ----------
$docFinal = Ler-Tarefas
$ultimaTarefaId = if ($docFinal.tarefas.Count -gt 0) { $docFinal.tarefas[-1].id } else { $null }
$ultimaTentativa = if ($docFinal.tarefas.Count -gt 0) { [int]$docFinal.tarefas[-1].tentativas } else { 0 }
$temFalha = [bool]($docFinal.tarefas | Where-Object { $_.status -eq 'failed' })

if ($temFalha) {
  Atualizar-Estado -TarefaAtual $ultimaTarefaId -Tentativa $ultimaTentativa -CommitBase (Obter-HeadAtual) -StatusExecucao 'falhou'
  Registrar-Log -Evento 'fim_execucao' -Detalhes @{ status = 'falhou'; exit_code = 1 }
  exit 1
}

Atualizar-Estado -TarefaAtual $ultimaTarefaId -Tentativa $ultimaTentativa -CommitBase (Obter-HeadAtual) -StatusExecucao 'concluido'
Registrar-Log -Evento 'fim_execucao' -Detalhes @{ status = 'concluido'; exit_code = 0 }
exit 0
