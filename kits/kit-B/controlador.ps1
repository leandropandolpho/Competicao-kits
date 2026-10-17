# controlador.ps1
# controlador.ps1 — Controlador determinístico do piloto (Claude Code headless como executor).
# Requer só pwsh 7+ e git. Interface fixa: ESPECIFICACAO.md, seção 3.
# Princípio: o controlador não confia no executor. Ele mesmo roda o teste, confere os arquivos de
# teste por SHA-256 e decide commit, rollback ou hold. As regras do settings.json são uma camada a mais,
# não a barreira.
param(
  [Parameter(Mandatory)][string]$RepoPath,
  [Parameter(Mandatory)][string]$TarefasPath,
  [Parameter(Mandatory)][string]$EstadoDir,
  [Parameter(Mandatory)][string]$TestCmd,
  [Parameter(Mandatory)][string[]]$TestPaths,
  [int]$TimeoutSec     = 900,
  [int]$MaxTentativas  = 3,
  [double]$MaxCustoUsd = 10,
  [double]$MaxMinutos  = 240,
  [string]$ClaudeCmd   = 'claude'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$Utf8 = [System.Text.UTF8Encoding]::new($false)

# Gatilhos R1 por nome de arquivo (além dos testes, migrations e exclusões).
$ArquivosCriticos = @('package.json', 'package-lock.json', 'requirements.txt', 'pyproject.toml')

# ======================= Registro: estado, log, notificações =======================

function Agora { (Get-Date).ToString('o') }

function Gravar-Atomico([string]$caminho, [string]$texto) {
  # Grava num temporário ao lado e troca de uma vez: uma interrupção no meio nunca deixa o arquivo pela metade.
  $tmp = "$caminho.tmp"
  [System.IO.File]::WriteAllText($tmp, $texto, $Utf8)
  for ($i = 1; ; $i++) {
    try { [System.IO.File]::Move($tmp, $caminho, $true); return }
    catch { if ($i -ge 5) { throw }; Start-Sleep -Milliseconds (100 * $i) }   # antivírus pode segurar o arquivo
  }
}

function Log([string]$evento, [hashtable]$dados = @{}) {
  $linha = [ordered]@{ ts = (Agora); evento = $evento }
  foreach ($k in $dados.Keys) { $linha[$k] = $dados[$k] }
  [System.IO.File]::AppendAllText($script:ArqLog, (($linha | ConvertTo-Json -Compress -Depth 5) + "`n"), $Utf8)
}

function Notificar([string]$mensagem) {
  # Isolada de propósito: hoje só grava texto; amanhã pode enviar e-mail/WhatsApp sem mexer no resto.
  [System.IO.File]::AppendAllText($script:ArqNotif, "[$(Agora)] $mensagem`n", $Utf8)
  Log 'notificacao' @{ mensagem = $mensagem }
}

function Salvar-Estado([string]$status) {
  # Heartbeat: regravado a cada etapa.
  $script:Estado.status_execucao     = $status
  $script:Estado.custo_acumulado_usd = [math]::Round($script:Custo, 6)
  $script:Estado.atualizado_em       = Agora
  Gravar-Atomico $script:ArqEstado ($script:Estado | ConvertTo-Json -Depth 6)
}

function Ler-Tarefas { Get-Content -LiteralPath $TarefasPath -Raw -Encoding utf8 | ConvertFrom-Json }

function Normalizar-Tarefas {
  # Campos ausentes recebem o padrão da especificação (evita erro com um TAREFAS.json escrito à mão).
  foreach ($t in @($script:Doc.tarefas)) {
    $padrao = [ordered]@{ depends_on = @(); status = 'pending'; tentativas = 0; critica = $false }
    foreach ($k in $padrao.Keys) { if (-not $t.PSObject.Properties[$k]) { $t | Add-Member -NotePropertyName $k -NotePropertyValue $padrao[$k] } }
  }
}

function Salvar-Tarefas { Gravar-Atomico $TarefasPath ($script:Doc | ConvertTo-Json -Depth 10) }

function Definir-Status($tarefa, [string]$status) {
  $tarefa.status = $status
  Salvar-Tarefas
  Log 'status_tarefa' @{ tarefa = $tarefa.id; status = $status; tentativas = $tarefa.tentativas }
}

# ======================= Git (única via de escrita no repositório) =======================

function Invoke-Git([string[]]$argumentos) {
  # Argumentos sempre como lista: nada de "-A" ou "--" ser interpretado pelo PowerShell.
  $saida = & git -C $script:Repo -c core.quotepath=off @argumentos 2>$null
  if ($LASTEXITCODE -ne 0) { throw "git $($argumentos -join ' ') falhou (código $LASTEXITCODE)" }
  return $saida
}

function Invoke-GitLista([string[]]$argumentos) {
  # Saída separada por NUL (-z): nomes com espaço ou acento chegam intactos.
  $bruto = Invoke-Git $argumentos
  return @(("$bruto" -split "`0") | Where-Object { $_ })
}

function Rollback([string]$base) {
  # Só dentro do repositório (git -C). settings.local.json não rastreado é do usuário: preservado.
  Invoke-Git @('reset', '-q', '--hard', $base) | Out-Null
  Invoke-Git @('clean', '-fdq', '-e', '.claude/settings.local.json') | Out-Null
  Log 'rollback' @{ para = $base }
}

function Commitar($tarefa, [string]$base) {
  # Se o executor fez commits por conta própria, eles são fundidos: sempre 1 commit por tarefa.
  if ((Invoke-Git @('rev-parse', 'HEAD')) -ne $base) { Invoke-Git @('reset', '-q', '--soft', $base) | Out-Null }
  Invoke-Git @('add', '-A', '--', '.', ':(exclude).claude/settings.local.json') | Out-Null
  Invoke-Git @('commit', '-q', '--allow-empty', '-m', "tarefa $($tarefa.id): $($tarefa.titulo)") | Out-Null
  Log 'commit' @{ tarefa = $tarefa.id; hash = (Invoke-Git @('rev-parse', 'HEAD')) }
}

function Arvore-Suja {
  # Ignora .claude/ (settings.local.json não rastreado é permitido pela especificação).
  return @(Invoke-Git @('status', '--porcelain') | Where-Object { $_ -and $_.Substring(3) -notlike '.claude/*' }).Count -gt 0
}

# ======================= Gatilhos críticos (R1) =======================

function Padroes-Teste {
  # Aceita lista PowerShell e também "a/*,b/*" num único texto (pwsh -File).
  return @($TestPaths | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().Replace('\', '/') -replace '^\./', '' } | Where-Object { $_ })
}

function Hash-Testes {
  # Rastreados + não rastreados (inclusive ignorados) que casem com algum padrão, com SHA-256.
  $mapa = [ordered]@{}
  foreach ($rel in (Invoke-GitLista @('ls-files', '-z', '--cached', '--others') | Sort-Object -Unique)) {
    if (-not ($script:Padroes | Where-Object { $rel -like $_ })) { continue }
    $abs = Join-Path $script:Repo $rel
    $mapa[$rel] = if (Test-Path -LiteralPath $abs -PathType Leaf) { (Get-FileHash -LiteralPath $abs -Algorithm SHA256).Hash } else { 'AUSENTE' }
  }
  return $mapa
}

function Gatilhos([string]$base, $hashBase) {
  $motivos = [System.Collections.Generic.List[string]]::new()
  # 1) Testes: comparação por hash, não pelo relato do executor nem pelo deny do settings.
  $hashAgora = Hash-Testes
  foreach ($rel in (@($hashBase.Keys) + @($hashAgora.Keys) | Sort-Object -Unique)) {
    $antes = if ($hashBase.Contains($rel)) { $hashBase[$rel] } else { 'AUSENTE' }
    $depois = if ($hashAgora.Contains($rel)) { $hashAgora[$rel] } else { 'AUSENTE' }
    if ($antes -ne $depois) { $motivos.Add("arquivo de teste alterado/criado/removido: $rel") }
  }
  # 2) Mudanças desde o commit base: rastreados (diff contra a base) + não rastreados.
  $diff = @(Invoke-GitLista @('diff', '--name-status', '--no-renames', '-z', $base))
  $mudados = [System.Collections.Generic.List[string]]::new()
  for ($i = 0; $i + 1 -lt $diff.Count; $i += 2) {
    $st = $diff[$i]; $rel = $diff[$i + 1]; $mudados.Add($rel)
    if ($st -eq 'D') { $motivos.Add("arquivo rastreado removido: $rel") }
    if ($rel -like '.claude/*') { $motivos.Add("configuração do executor alterada: $rel") }
  }
  foreach ($rel in (Invoke-GitLista @('ls-files', '-z', '--others', '--exclude-standard'))) { $mudados.Add($rel) }
  foreach ($rel in $mudados) {
    if ($rel -match 'migration') { $motivos.Add("migration: $rel") }
    if ((Split-Path $rel -Leaf) -in $ArquivosCriticos) { $motivos.Add("dependências/manifest: $rel") }
  }
  return @($motivos | Sort-Object -Unique)
}

# ======================= Processos externos (executor e teste) =======================

function Matar-Arvore($proc) {
  # Timeout = encerramento real do processo e de todos os filhos (o claude.cmd inicia outros processos).
  try { $proc.Kill($true) } catch { }
  if ($IsWindows -and -not $proc.HasExited) { & taskkill /T /F /PID $proc.Id 2>$null | Out-Null }
  $proc.WaitForExit(10000) | Out-Null
}

function Rodar-Processo([string]$exe, [string[]]$argumentos, [string]$entrada, [int]$timeoutSeg) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new($exe)
  foreach ($a in $argumentos) { $psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $script:Repo
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8; $psi.StandardErrorEncoding = $Utf8
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
  # Prompt pela entrada padrão: um .cmd cortaria as quebras de linha se fosse argumento.
  try {
    $bytes = $Utf8.GetBytes("$entrada")
    $p.StandardInput.BaseStream.WriteAsync($bytes, 0, $bytes.Length).Wait($timeoutSeg * 1000) | Out-Null
    $p.StandardInput.Close()
  } catch { }   # o processo pode ter saído sem ler a entrada
  $estourou = -not $p.WaitForExit($timeoutSeg * 1000)
  if ($estourou) { Matar-Arvore $p }
  elseif (-not $out.Wait(10000)) { Matar-Arvore $p }   # neto órfão segurando a saída
  $r = @{ Estourou = $estourou; Codigo = $(if ($estourou) { -1 } else { $p.ExitCode })
          Saida = $(if ($out.IsCompleted) { $out.Result } else { '' }); Erro = $(if ($err.Wait(2000)) { $err.Result } else { '' }) }
  $p.Dispose()
  return $r
}

function Resolver-Executor {
  # Acha claude.exe ou claude.cmd pelo PATH/PATHEXT; um caminho completo é usado como está.
  $cmd = Get-Command -Name $ClaudeCmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  return $(if ($cmd) { $cmd.Source } else { $ClaudeCmd })
}

function Chamar-Executor($tarefa) {
  $argumentos = @('-p', '--output-format', 'json', '--permission-mode', 'dontAsk')
  # Confiança da pasta: em claude -p, o allow do settings do projeto é ignorado em pasta não confiada.
  # Solução: passar a cópia congelada do settings por --settings (vale sem confiança e sem escrever no repo).
  if ($script:SettingsExecutor) { $argumentos += @('--settings', $script:SettingsExecutor) }
  $prompt = "$($tarefa.prompt)`n`n---`nRegras do controlador: não altere, crie nem apague arquivos de teste, migrations ou manifestos de dependência; não apague arquivos; não faça commit. O controlador roda os testes e decide."
  $r = Rodar-Processo $script:Executor $argumentos $prompt $TimeoutSec
  $json = $null
  try { $json = $r.Saida.Trim() | ConvertFrom-Json } catch {
    $ultima = @($r.Saida -split "`n" | Where-Object { $_.Trim() }) | Select-Object -Last 1
    try { if ($ultima) { $json = $ultima | ConvertFrom-Json } } catch { }
  }
  $custo = 0.0
  if ($json -and $json.PSObject.Properties['total_cost_usd']) { $custo = [double]$json.total_cost_usd }
  $falhou = $r.Estourou -or ($r.Codigo -ne 0) -or (-not $json) -or ($json.PSObject.Properties['is_error'] -and $json.is_error -eq $true)
  $motivo = if ($r.Estourou) { "timeout de $TimeoutSec s" } elseif (-not $json) { 'saída não é JSON' } elseif ($r.Codigo -ne 0) { "código $($r.Codigo)" } elseif ($falhou) { 'is_error' } else { '' }
  $resumo = if ($json -and $json.PSObject.Properties['result']) { "$($json.result)" } else { $r.Saida }
  Log 'executor' @{ tarefa = $tarefa.id; tentativa = $tarefa.tentativas; falhou = [bool]$falhou; motivo = $motivo; custo_usd = $custo
                    sem_custo_registrado = (-not $json); resumo = $resumo.Substring(0, [math]::Min(400, $resumo.Length)) }
  return @{ Falhou = [bool]$falhou; Custo = $custo }
}

function Rodar-Teste {
  # O próprio controlador roda o teste, no repositório; o relato do executor não vale.
  $r = Rodar-Processo $script:Pwsh @('-NoProfile', '-Command', $TestCmd) '' $TimeoutSec
  $passou = (-not $r.Estourou) -and ($r.Codigo -eq 0)
  $saida = "$($r.Saida)$($r.Erro)"
  Log 'teste' @{ passou = $passou; codigo = $r.Codigo; saida = $saida.Substring([math]::Max(0, $saida.Length - 400)) }
  return $passou
}

# ======================= Limites =======================

function Limite-Estourado {
  if ($script:Custo -gt $MaxCustoUsd) { return "teto de custo: US$ $([math]::Round($script:Custo, 4)) > US$ $MaxCustoUsd" }
  if ($script:Relogio.Elapsed.TotalMinutes -gt $MaxMinutos) { return "teto de tempo: $([math]::Round($script:Relogio.Elapsed.TotalMinutes, 2)) min > $MaxMinutos min" }
  return $null
}

# ======================= Ciclo de uma tarefa =======================

function Proxima-Tarefa {
  # Primeira 'pending', na ordem do arquivo, com todas as dependências 'done'.
  foreach ($t in @($script:Doc.tarefas)) {
    if ($t.status -ne 'pending') { continue }
    $deps = @($t.depends_on | Where-Object { $_ })
    $pendentes = @($deps | Where-Object { $d = $_; -not (@($script:Doc.tarefas) | Where-Object { $_.id -eq $d -and $_.status -eq 'done' }) })
    if ($pendentes.Count -eq 0) { return $t }
  }
  return $null
}

function Executar-Tarefa($tarefa) {
  # Retorna: 'done' | 'failed' | 'hold' | 'pausa'
  $base = Invoke-Git @('rev-parse', 'HEAD')
  $hashBase = Hash-Testes
  $script:Estado.tarefa_atual = $tarefa.id
  $script:Estado.commit_base = $base
  $script:Estado.hash_testes = $hashBase
  while ([int]$tarefa.tentativas -lt $MaxTentativas) {
    # Tentativa contada e gravada ANTES da chamada: uma queda no meio não "devolve" a tentativa.
    $tarefa.tentativas = [int]$tarefa.tentativas + 1
    $script:Estado.tentativa = $tarefa.tentativas
    Definir-Status $tarefa 'in_progress'
    Salvar-Estado 'rodando'

    $exec = Chamar-Executor $tarefa
    $script:Custo += $exec.Custo
    Salvar-Estado 'rodando'

    # Gatilhos R1 primeiro: têm precedência sobre falha do executor e sobre o teste. Sem rollback (evidência).
    $motivos = @(Gatilhos $base $hashBase)
    if ($motivos.Count) {
      Definir-Status $tarefa 'hold'
      Notificar "HOLD na tarefa $($tarefa.id): $($motivos -join '; '). Repositório preservado para análise; nenhuma outra tarefa será iniciada."
      return 'hold'
    }
    if (-not $exec.Falhou -and (Rodar-Teste)) {
      Commitar $tarefa $base
      Definir-Status $tarefa 'done'
      return 'done'
    }
    Rollback $base
    if ([int]$tarefa.tentativas -ge $MaxTentativas) { break }
    if (Limite-Estourado) { Definir-Status $tarefa 'pending'; return 'pausa' }   # retoma depois com as tentativas já gastas
  }
  Definir-Status $tarefa 'failed'
  Notificar "Tarefa $($tarefa.id) falhou após $($tarefa.tentativas) tentativa(s)."
  return 'failed'
}

# ======================= Preparação e retomada =======================

function Preparar {
  $script:Repo = (Resolve-Path -LiteralPath $RepoPath).ProviderPath
  if ("$(Invoke-Git @('rev-parse', '--show-cdup'))".Trim()) { throw "RepoPath precisa ser a raiz de um repositório git: $script:Repo" }
  New-Item -ItemType Directory -Force -Path $EstadoDir | Out-Null
  $estadoAbs = (Resolve-Path -LiteralPath $EstadoDir).ProviderPath
  $tarefasAbs = (Resolve-Path -LiteralPath $TarefasPath).ProviderPath
  $raiz = $script:Repo.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
  foreach ($c in @($estadoAbs + [System.IO.Path]::DirectorySeparatorChar, $tarefasAbs)) {
    # O rollback apagaria o estado se ele estivesse dentro do repositório.
    if ($c.StartsWith($raiz, [System.StringComparison]::OrdinalIgnoreCase)) { throw "TarefasPath e EstadoDir devem ficar FORA do repositório: $c" }
  }
  $script:ArqEstado = Join-Path $estadoAbs 'estado.json'
  $script:ArqLog    = Join-Path $estadoAbs 'log.jsonl'
  $script:ArqNotif  = Join-Path $estadoAbs 'notificacoes.txt'
  $script:Padroes   = Padroes-Teste
  $script:Executor  = Resolver-Executor
  $script:Pwsh      = (Get-Command -Name pwsh -CommandType Application | Select-Object -First 1).Source
  # Cópia congelada do settings do projeto, fora do repo, passada por --settings a cada chamada.
  $script:SettingsExecutor = $null
  $origem = Join-Path $script:Repo '.claude/settings.json'
  if (Test-Path -LiteralPath $origem) {
    $script:SettingsExecutor = Join-Path $estadoAbs 'settings-executor.json'
    Copy-Item -LiteralPath $origem -Destination $script:SettingsExecutor -Force
  }
}

function Retomar {
  # Custo acumula entre execuções; o tempo não (conta a partir de cada início).
  $anterior = $null
  if (Test-Path -LiteralPath $script:ArqEstado) {
    try { $anterior = Get-Content -LiteralPath $script:ArqEstado -Raw | ConvertFrom-Json } catch { Log 'estado_ilegivel' }
  }
  if ($anterior -and $anterior.PSObject.Properties['custo_acumulado_usd']) { $script:Custo = [double]$anterior.custo_acumulado_usd }
  foreach ($t in @($script:Doc.tarefas | Where-Object { $_.status -eq 'in_progress' })) {
    $base = if ($anterior -and $anterior.tarefa_atual -eq $t.id -and $anterior.commit_base) { "$($anterior.commit_base)" } else { Invoke-Git @('rev-parse', 'HEAD') }
    $esperado = "tarefa $($t.id): $($t.titulo)"
    $headPai = & git -C $script:Repo rev-parse 'HEAD~1' 2>$null
    if (((Invoke-Git @('log', '-1', '--format=%s')) -ceq $esperado) -and ($headPai -eq $base) -and -not (Arvore-Suja)) {
      # Caiu entre o commit e a gravação do status: o trabalho já está salvo, não refazer.
      Definir-Status $t 'done'; Log 'retomada' @{ tarefa = $t.id; acao = 'commit ja existia' }; continue
    }
    Rollback $base
    $novo = if ([int]$t.tentativas -ge $MaxTentativas) { 'failed' } else { 'pending' }
    Definir-Status $t $novo
    Log 'retomada' @{ tarefa = $t.id; commit_base = $base; tentativas = $t.tentativas; custo_preservado = $script:Custo }
  }
}

# ======================= Principal =======================

$script:Custo = 0.0
$script:Relogio = [System.Diagnostics.Stopwatch]::StartNew()
$script:Estado = [ordered]@{ tarefa_atual = $null; tentativa = 0; commit_base = $null; custo_acumulado_usd = 0.0
  inicio = (Agora); atualizado_em = (Agora); status_execucao = 'rodando'; hash_testes = @{} }
$codigo = 1
try {
  Preparar
  $script:Doc = Ler-Tarefas
  Normalizar-Tarefas
  $script:Estado.commit_base = Invoke-Git @('rev-parse', 'HEAD')
  Log 'inicio' @{ executor = $script:Executor; padroes_teste = $script:Padroes; settings = $script:SettingsExecutor }
  if (@($script:Doc.tarefas | Where-Object { $_.status -eq 'hold' }).Count) {
    # Hold exige decisão humana: não mexer no repositório nem iniciar nada.
    Notificar 'Há tarefa em hold aguardando análise humana. Resolva e mude o status em TAREFAS.json antes de rodar de novo.'
    Salvar-Estado 'hold'; exit 2
  }
  Retomar
  if (Arvore-Suja) { throw 'Repositório com alterações não commitadas: o rollback as apagaria. Faça commit ou descarte antes.' }
  Salvar-Estado 'rodando'

  $resultado = 'fim'
  while ($true) {
    $limite = Limite-Estourado
    if ($limite) { $resultado = 'pausa'; break }
    $t = Proxima-Tarefa
    if (-not $t) { break }
    $r = Executar-Tarefa $t
    if ($r -eq 'hold') { $resultado = 'hold'; break }
    if ($r -eq 'pausa') { $resultado = 'pausa'; break }
  }

  $script:Estado.tarefa_atual = $null
  $temFalha = @($script:Doc.tarefas | Where-Object { $_.status -eq 'failed' }).Count -gt 0
  switch ($resultado) {
    'hold'  { Salvar-Estado 'hold'; $codigo = 2 }
    'pausa' { Notificar "Execução pausada — $(Limite-Estourado). Rode de novo (com teto maior) para continuar."; Salvar-Estado 'pausado'; $codigo = 3 }
    default {
      if ($temFalha) { Notificar 'Execução terminou com tarefa(s) failed.'; Salvar-Estado 'falhou'; $codigo = 1 }
      else { Salvar-Estado 'concluido'; $codigo = 0 }
    }
  }
  Log 'fim' @{ codigo = $codigo; custo_usd = $script:Custo; minutos = [math]::Round($script:Relogio.Elapsed.TotalMinutes, 3) }
} catch {
  $msg = "Erro do controlador: $($_.Exception.Message)"
  try { Notificar $msg; Salvar-Estado 'falhou' } catch { Write-Error $msg }
  $codigo = 1
}
exit $codigo
