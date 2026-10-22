# lancador.ps1 — B-05, contrato v3.1 (Atos 075–077). Roda o controlador CONGELADO dentro de um Job Object,
# no pwsh PORTÁTIL (não empacotado), com orçamento controlado pelo razão e o embrulho no lugar do executor.
# Contenção = herança nativa do job na criação dos processos (H1–H3). A varredura só VERIFICA (não associa):
# descendente fora do job ⇒ falha fechada (E76-01).
# Códigos próprios (antes de iniciar o controlador, salvo 28/29 que também podem ocorrer depois):
#   20 trava ocupada (EstadoDir ou RazaoDir) · 21 razão ilegível · 22 processo antigo vivo · 23 saldo insuficiente
#   24 falha no Job Object · 25 versão do Claude · 26 pastas inválidas · 27 pwsh empacotado ou hash diferente
#   28 reconciliação divergente · 29 contenção violada (ou violação anterior sem liberação humana) · 30 vínculo divergente
param(
  [Parameter(Mandatory)][string]$RepoPath,
  [Parameter(Mandatory)][string]$TarefasPath,
  [Parameter(Mandatory)][string]$EstadoDir,
  [Parameter(Mandatory)][string]$RazaoDir,
  [Parameter(Mandatory)][string]$ControladorPath,
  [Parameter(Mandatory)][string]$TestCmd,
  [Parameter(Mandatory)][string]$TestPaths,
  [Parameter(Mandatory)][double]$OrcamentoUsd,
  [double]$TetoChamadaUsd = 0.50,
  [double]$Folga = 0.25,
  [int]$TimeoutSec = 600,
  [int]$MaxTentativas = 2,
  [double]$MaxMinutos = 60,
  [string]$Executor = 'claude',
  [string]$ExecutorPrefixo = '',
  [string]$VersaoClaude = '2.1.302',
  [string]$PwshSha256 = 'FA2C8BB1E35CDD62AD15CD06A1D8F2C5961E9725A9BFA1E7CFD2C322F49E9619',   # pwsh.exe 7.6.7 portátil
  [switch]$BaixaIntegridade,         # E84-02: executor em baixa integridade
  [switch]$IgnorarVersao,            # só testes com executor simulado
  [switch]$TesteFalharAssociacao,    # só N10
  [switch]$TesteHandleHerdavel       # só N10
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'razao.ps1')
$Embrulho = Join-Path $PSScriptRoot 'claude-com-teto.cmd'

function Parar([int]$codigo, [string]$msg) {
  [Console]::Error.WriteLine("B05-LANCADOR ($codigo): $msg")
  if ($codigo -eq 30) { exit 30 }   # E76-03: vínculo divergente ⇒ nada é gravado no RazaoDir
  try { if (Test-Path -LiteralPath $RazaoDir) { [System.IO.File]::AppendAllText((Join-Path $RazaoDir 'notificacoes-b05.txt'), "[$((Get-Date).ToString('o'))] codigo $codigo — $msg`n", $script:Utf8SemBom) } } catch { }
  exit $codigo
}
function Canonico([string]$p) { [IO.Path]::GetFullPath($p).TrimEnd('\') }

if (-not $IsWindows) { Parar 24 'Job Object exige Windows' }

# ---------------- H1/H2: pwsh portátil, nunca o empacotado ----------------
$PwshProprio = (Get-Process -Id $PID).Path
if ($PwshProprio -match '\\WindowsApps\\') { Parar 27 "lançador rodando no pwsh empacotado (Microsoft Store): $PwshProprio" }
if ((Get-FileHash -LiteralPath $PwshProprio).Hash -ne $PwshSha256) { Parar 27 "hash do pwsh.exe diferente do fixado: $PwshProprio" }
$PwshDir = Split-Path $PwshProprio

# ---------------- Pastas ----------------
foreach ($d in $RazaoDir, $EstadoDir) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
$RazaoDir = Canonico (Resolve-Path -LiteralPath $RazaoDir).ProviderPath
$EstadoCan = Canonico (Resolve-Path -LiteralPath $EstadoDir).ProviderPath
$repoFull = (Canonico (Resolve-Path -LiteralPath $RepoPath).ProviderPath) + '\'
if (($RazaoDir + '\').StartsWith($repoFull, [StringComparison]::OrdinalIgnoreCase)) { Parar 26 'RazaoDir não pode ficar dentro do repositório' }

# ---------------- H7: travas por EstadoDir E por RazaoDir ----------------
function Tomar-Trava([string]$nome) {
  $m = [System.Threading.Mutex]::new($false, $nome); $ok = $false
  try { $ok = $m.WaitOne(0) } catch {
    $ex = $_.Exception; while ($ex -and -not ($ex -is [System.Threading.AbandonedMutexException])) { $ex = $ex.InnerException }
    if ($ex) { $ok = $true } else { throw }   # lançador anterior caiu: a trava abandonada passa a ser nossa
  }
  return @{ Mutex = $m; Ok = $ok }
}
$t1 = Tomar-Trava ((Razao-Nome-Trava $EstadoCan) + '-lancador-estado')
if (-not $t1.Ok) { Parar 20 "já existe um lançador ativo para o estado $EstadoCan" }
$t2 = Tomar-Trava ((Razao-Nome-Trava $RazaoDir) + '-lancador-razao')
if (-not $t2.Ok) { Parar 20 "já existe um lançador ativo para o razão $RazaoDir" }

# ---------------- E76-03: vínculo permanente EstadoDir ↔ RazaoDir ----------------
$vR = Join-Path $RazaoDir 'vinculo.json'; $vE = Join-Path $EstadoCan 'b05-vinculo.json'
$r = Razao-Ler $RazaoDir
if (-not $r.Ok) { Parar 21 "razão ilegível: $($r.Motivo)" }
$criarVinculo = $false
if ((Test-Path -LiteralPath $vR) -or (Test-Path -LiteralPath $vE)) {
  if (-not ((Test-Path -LiteralPath $vR) -and (Test-Path -LiteralPath $vE))) { Parar 30 'vínculo incompleto entre estado e razão (um dos lados ausente)' }
  $jr = Get-Content -LiteralPath $vR -Raw | ConvertFrom-Json; $je = Get-Content -LiteralPath $vE -Raw | ConvertFrom-Json
  if ("$($jr.estado_dir)" -ne $EstadoCan -or "$($je.razao_dir)" -ne $RazaoDir -or "$($jr.id)" -ne "$($je.id)") {
    Parar 30 "vínculo divergente: razão ligado a '$($jr.estado_dir)', estado ligado a '$($je.razao_dir)'"
  }
} else {
  if (@($r.Eventos | Where-Object { $_.evento -in @('inicio', 'fim', 'base_historica') }).Count) { Parar 30 'razão já usado e sem vínculo: não pode ser ligado a outro estado' }
  $criarVinculo = $true
}

# ---------------- E76-01 (verificação externa): violação anterior sem liberação humana ----------------
$violacoes = @($r.Eventos | Where-Object evento -eq 'contencao_violada')
if ($violacoes.Count) {
  $liberadas = @($r.Eventos | Where-Object evento -eq 'liberacao_humana' | ForEach-Object { "$($_.execucao_violada)" })
  $pend = @($violacoes | Where-Object { "$($_.execucao)" -notin $liberadas })
  if ($pend.Count) {
    $lib = Join-Path $RazaoDir 'LIBERACAO_HUMANA.txt'
    $texto = if (Test-Path -LiteralPath $lib) { Get-Content -LiteralPath $lib -Raw } else { '' }
    $ok = @($pend | Where-Object { $texto -match [regex]::Escape("$($_.execucao)") }).Count -eq $pend.Count
    if (-not $ok) { Parar 29 "contenção violada na execução $(@($pend | ForEach-Object { $_.execucao }) -join ', ') sem liberação humana (LIBERACAO_HUMANA.txt)" }
    foreach ($p in $pend) { Razao-Gravar $RazaoDir @{ evento = 'liberacao_humana'; execucao_violada = "$($p.execucao)"; texto = $texto.Trim() } }
    $r = Razao-Ler $RazaoDir
  }
}

# ---------------- E5: versão do Claude ----------------
if (-not $IgnorarVersao) {
  $v = (& $Executor --version 2>$null | Select-Object -First 1)
  if ("$v" -notmatch [regex]::Escape($VersaoClaude)) { Parar 25 "versão do Claude '$v' diferente da fixada '$VersaoClaude'" }
} else { $v = 'ignorada (teste)' }

# ---------------- P4: processos antigos ----------------
$vivos = @(Razao-ProcessosVivos $r.Eventos)
if ($vivos.Count) { Parar 22 "processo de execução anterior ainda vivo: $($vivos -join '; ')" }

# ---------------- E76-04/H8: base histórica, reconciliação e admissão ----------------
$arqEstado = Join-Path $EstadoCan 'estado.json'
function Custo-Estado { if (Test-Path -LiteralPath $arqEstado) { [double]((Get-Content -LiteralPath $arqEstado -Raw | ConvertFrom-Json).custo_acumulado_usd) } else { 0.0 } }
if ($criarVinculo) {
  $id = [guid]::NewGuid().ToString('N'); $ts = (Get-Date).ToString('o')
  try { $b0 = Custo-Estado } catch { Parar 28 "estado.json ilegível na criação do vínculo: $($_.Exception.Message)" }
  if (-not [double]::IsFinite($b0) -or $b0 -lt 0) { Parar 28 "custo histórico inválido no estado.json: $b0" }
  Razao-Gravar $RazaoDir @{ evento = 'base_historica'; valor_usd = $b0; vinculo = $id }
  [System.IO.File]::WriteAllText($vR, ([ordered]@{ id = $id; estado_dir = $EstadoCan; criado_em = $ts } | ConvertTo-Json), $script:Utf8SemBom)
  [System.IO.File]::WriteAllText($vE, ([ordered]@{ id = $id; razao_dir = $RazaoDir; criado_em = $ts } | ConvertTo-Json), $script:Utf8SemBom)
  $r = Razao-Ler $RazaoDir
}
function Conferir-Reconciliacao([string]$momento) {
  $rr = Razao-Ler $RazaoDir
  if (-not $rr.Ok) { return "razão ilegível: $($rr.Motivo)" }
  $cc = Razao-Contabilizar $rr.Eventos $Folga
  try { $est = Custo-Estado } catch { return "estado.json ilegível ($momento): $($_.Exception.Message)" }
  if (-not [double]::IsFinite($est)) { return "estado.json com custo não finito ($momento)" }
  if ([math]::Abs($est - ($cc.Base + $cc.Conhecido)) -gt 1e-6) { return "estado.json $est ≠ base $($cc.Base) + conhecido $($cc.Conhecido) ($momento)" }
  return ''
}
$m = Conferir-Reconciliacao 'antes'
if ($m) { Parar 28 $m }
$c = Razao-Contabilizar $r.Eventos $Folga
if ($c.Total + $TetoChamadaUsd * (1 + $Folga) -gt $OrcamentoUsd) {
  Parar 23 "saldo insuficiente: base $($c.Base) + conhecido $($c.Conhecido) + reservado $($c.Reservado) + reserva $([math]::Round($TetoChamadaUsd * (1 + $Folga), 4)) > orçamento $OrcamentoUsd"
}

# ---------------- E3/P1: Job Object ----------------
. (Join-Path $PSScriptRoot 'b05job.ps1')
$job = [B05Job]::CreateJobObject([IntPtr]::Zero, $null)   # sem nome e sem atributos: handle não herdável e exclusivo
if ($job -eq [IntPtr]::Zero) { Parar 24 "CreateJobObject falhou ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
if (-not [B05Job]::Configurar($job, [B05Job]::KILL_ON_JOB_CLOSE)) { Parar 24 "SetInformationJobObject falhou ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
$fl = [B05Job]::Flags($job)
if ($fl -lt 0) { Parar 24 'QueryInformationJobObject falhou' }
if (-not ($fl -band [B05Job]::KILL_ON_JOB_CLOSE) -or ($fl -band [B05Job]::BREAKAWAY_OK) -or ($fl -band [B05Job]::SILENT_BREAKAWAY_OK)) { Parar 24 ("limites do job inesperados: 0x{0:X}" -f $fl) }
if ($TesteHandleHerdavel) { [B05Job]::SetHandleInformation($job, [B05Job]::HANDLE_FLAG_INHERIT, [B05Job]::HANDLE_FLAG_INHERIT) | Out-Null }
$hf = [uint32]0
if (-not [B05Job]::GetHandleInformation($job, [ref]$hf)) { Parar 24 'GetHandleInformation falhou' }
if ($hf -band [B05Job]::HANDLE_FLAG_INHERIT) { Parar 24 'handle do job está herdável' }
$eu = [B05Job]::GetCurrentProcess()
$ok = if ($TesteFalharAssociacao) { $false } else { [B05Job]::AssignProcessToJobObject($job, $eu) }
$instanteAssoc = [DateTime]::UtcNow.ToFileTimeUtc()   # depois da associação: todo processo criado antes disso nasceu fora do job
if (-not $ok) { Parar 24 "AssignProcessToJobObject falhou ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
$dentro = $false
if (-not [B05Job]::IsProcessInJob($eu, $job, [ref]$dentro) -or -not $dentro) { Parar 24 'o lançador não está no job após a associação' }

# Filhos do lançador que já existiam antes da associação: só o conhost.exe que o Windows cria quando o lançador nasce
# sem console herdado. Ele não descende do controlador; é registrado e ignorado pela verificação. Qualquer outro ⇒ 24.
# Ressalva do Ato 081: a dispensa exige, por processo, (1) pai = lançador, (2) caminho = %SystemRoot%\System32\conhost.exe,
# (3) criação entre a criação do lançador e o instante da associação (prova de que já existia; afasta PID reutilizado).
. (Join-Path $PSScriptRoot 'dispensa.ps1')
[B05Job]::Rastrear([uint32]$PID)   # identidade do lançador = PID + criação (snapshot)
$criacaoLanc = [B05Job]::Verificados[[uint32]$PID]
$raizL = [System.Collections.Generic.Dictionary[uint32, long]]::new(); $raizL[[uint32]$PID] = $criacaoLanc
$pre = [System.Collections.Generic.List[object]]::new()
foreach ($x in @([B05Job]::Subarvore($raizL))) {
  $pp = $x -split '\|'
  $d = Testar-Dispensa ([uint32]$pp[0]) ([uint32]$pp[2]) ([uint32]$PID) $criacaoLanc $instanteAssoc
  if (-not $d.Ok) { Parar 24 "processo pré-existente sob o lançador não qualificado para dispensa: $x ($($d.Motivo))" }
  [B05Job]::PreExistentes[[uint32]$pp[0]] = [long]$d.Criacao
  $pre.Add([ordered]@{ pid = [uint32]$pp[0]; caminho = $d.Caminho; criacao_utc = [DateTime]::FromFileTimeUtc($d.Criacao).ToString('o') })
}

# ---------------- H6: configuração imutável por execução; partida do controlador ----------------
$execucao = [guid]::NewGuid().ToString('N')
$cfg = [ordered]@{ execucao = $execucao; orcamento_usd = $OrcamentoUsd; teto_chamada_usd = $TetoChamadaUsd; folga = $Folga
                   executor = $Executor; executor_prefixo = $ExecutorPrefixo; versao_claude = "$v"; pwsh = $PwshProprio
                   baixa_integridade = [bool]$BaixaIntegridade; criado_em = (Get-Date).ToString('o') }
$arqCfg = Join-Path $RazaoDir "config-$execucao.json"
$fs = [System.IO.FileStream]::new($arqCfg, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)   # CreateNew: nunca sobrescreve
try { $b = $script:Utf8SemBom.GetBytes(($cfg | ConvertTo-Json)); $fs.Write($b, 0, $b.Length); $fs.Flush($true) } finally { $fs.Dispose() }
(Get-Item -LiteralPath $arqCfg).IsReadOnly = $true
$env:B05_DIR = $RazaoDir; $env:B05_EXECUCAO = $execucao; $env:B05_PWSH = $PwshProprio
if ($BaixaIntegridade) {
  # E84-02: pasta de baixa integridade para a E/S do executor (ele não escreve em nada de nível médio).
  $baixoDir = Join-Path ([IO.Path]::GetTempPath()) "b05-baixo-$execucao"
  New-Item -ItemType Directory -Force $baixoDir | Out-Null
  & icacls $baixoDir /setintegritylevel '(OI)(CI)low' /Q 2>&1 | Out-Null
  $env:B05_BAIXO_DIR = $baixoDir
  # G2: a árvore de trabalho do repositório fica BAIXA (o executor baixo edita o código), mas .git fica MÉDIO
  # (o executor não planta hooks nem reescreve histórico; o controlador médio continua escrevendo por write-down).
  Get-ChildItem -LiteralPath $RepoPath -Force | Where-Object Name -ne '.git' | ForEach-Object { & icacls $_.FullName /setintegritylevel '(OI)(CI)low' /T /Q 2>&1 | Out-Null }
  & icacls $RepoPath /setintegritylevel '(OI)(CI)low' /Q 2>&1 | Out-Null
  # A raiz ganhou um rótulo BAIXO herdável; .git não tinha rótulo próprio e passaria a HERDAR baixo (achado N18b/049).
  # Rótulo MÉDIO explícito em .git e em toda a sua subárvore sobrepõe a herança: o executor baixo não escreve lá.
  if (Test-Path -LiteralPath (Join-Path $RepoPath '.git')) { & icacls (Join-Path $RepoPath '.git') /setintegritylevel '(OI)(CI)medium' /T /Q 2>&1 | Out-Null }
  # E84-03: NO_READ_UP nas pastas sensíveis — o executor baixo não LÊ razão, estado nem a chave da supervisora.
  . (Join-Path $PSScriptRoot 'baixa-integridade.ps1')
  foreach ($p in @($RazaoDir, $EstadoCan, (Join-Path $env:USERPROFILE '.supervisora'))) {
    if (Test-Path -LiteralPath $p) { $mr = [B05LowIL]::RotularNRNW($p); if ($mr) { Parar 26 "falha ao proteger '$p' (NO_READ_UP): $mr" } }
  }
  # E84-03: cópia da config do Claude em nível BAIXO (o executor real precisa escrever sessão/cache; não toca em ~/.claude).
  $cliHome = Join-Path $baixoDir 'clihome'; New-Item -ItemType Directory -Force $cliHome | Out-Null
  if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.claude')) { Copy-Item (Join-Path $env:USERPROFILE '.claude\*') $cliHome -Recurse -Force -ErrorAction SilentlyContinue }
  if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.claude.json')) { Copy-Item (Join-Path $env:USERPROFILE '.claude.json') (Join-Path $cliHome '.claude.json') -Force -ErrorAction SilentlyContinue }
  & icacls $cliHome /setintegritylevel '(OI)(CI)low' /T /Q 2>&1 | Out-Null
  $env:B05_BAIXO_CLAUDE = $cliHome
}
$env:PATH = "$PwshDir;$env:PATH"   # E76-02: "pwsh" pedido por qualquer descendente resolve para o portátil
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue

$psi = [System.Diagnostics.ProcessStartInfo]::new($PwshProprio)
foreach ($a in @('-NoProfile', '-File', $ControladorPath, '-RepoPath', $RepoPath, '-TarefasPath', $TarefasPath, '-EstadoDir', $EstadoDir,
                 '-TestCmd', $TestCmd, '-TestPaths', $TestPaths, '-TimeoutSec', "$TimeoutSec", '-MaxTentativas', "$MaxTentativas",
                 '-MaxCustoUsd', ([string]$OrcamentoUsd).Replace(',', '.'), '-MaxMinutos', ([string]$MaxMinutos).Replace(',', '.'), '-ClaudeCmd', $Embrulho)) { $psi.ArgumentList.Add($a) }
$psi.UseShellExecute = $false
$ctl = [System.Diagnostics.Process]::Start($psi)
try { $criacaoCtl = $ctl.StartTime.ToUniversalTime().ToString('o') } catch { $criacaoCtl = (Get-Date).ToUniversalTime().ToString('o') }
Razao-Gravar $RazaoDir @{ evento = 'controlador'; id = 'ctl'; execucao = $execucao; pid = $ctl.Id; criacao = $criacaoCtl; versao_claude = "$v"; flags_job = ('0x{0:X}' -f $fl); pwsh = $PwshProprio; preexistentes = @($pre); associacao_utc = [DateTime]::FromFileTimeUtc($instanteAssoc).ToString('o') }

# ---------------- H3/H4/E76-01: verificação contínua; falha fechada ----------------
$dctl = $false; [void][B05Job]::IsProcessInJob($ctl.Handle, $job, [ref]$dctl)
if (-not $dctl) {
  Razao-Gravar $RazaoDir @{ evento = 'contencao_violada'; execucao = $execucao; violacoes = @("$($ctl.Id)|controlador|$PID|0|fora do job") }
  [void][B05Job]::TerminateJobObject($job, 29); exit 29
}
[B05Job]::Rastrear([uint32]$ctl.Id)
$ultimo = ''; $tick = 0
while (-not $ctl.HasExited) {
  $viol = [B05Job]::Verificar($job)
  if ($viol.Count) {
    # 1) registro durável ANTES de encerrar  2) encerra os externos e registra  3) encerra o job (inclusive este lançador)
    Razao-Gravar $RazaoDir @{ evento = 'contencao_violada'; execucao = $execucao; violacoes = @($viol) }
    # Encerra os externos e, em até 5 passadas, os descendentes deles (inclusive os criados entre um snapshot e outro).
    # Identidade de cada alvo = PID + criação: nunca se encerra um processo alheio que herdou o PID.
    $alvos = [System.Collections.Generic.Dictionary[uint32, long]]::new()
    foreach ($x in $viol) { $pp = $x -split '\|'; $pv = [uint32]0; $cv = [long]0
      if ([uint32]::TryParse($pp[0], [ref]$pv) -and $pv -ne 0 -and [long]::TryParse($pp[3], [ref]$cv) -and $cv -gt 0) { $alvos[$pv] = $cv } }
    $res = [System.Collections.Generic.List[string]]::new()
    foreach ($kv in @($alvos.GetEnumerator())) { $res.Add("$($kv.Key)|externo|$([B05Job]::Encerrar($kv.Key, $kv.Value))") }
    for ($pass = 0; $pass -lt 5; $pass++) {
      $novos = @([B05Job]::Subarvore($alvos) | Where-Object { -not $alvos.ContainsKey([uint32](($_ -split '\|')[0])) })
      if (-not $novos.Count) { break }
      foreach ($x in $novos) { $pp = $x -split '\|'; $alvos[[uint32]$pp[0]] = [long]$pp[3]; $res.Add("$x|descendente de externo|$([B05Job]::Encerrar([uint32]$pp[0], [long]$pp[3]))") }
    }
    try { Razao-Gravar $RazaoDir @{ evento = 'externos_encerramento'; execucao = $execucao; resultados = @($res) } } catch { }
    [void][B05Job]::TerminateJobObject($job, 29)
    exit 29   # só alcançado se o próprio lançador não tiver sido encerrado pelo job
  }
  if (($tick++ % 5) -eq 0) {
    $mb = [B05Job]::Membros($job)
    if ($mb) { $s = (@($mb | Sort-Object) -join ','); if ($s -ne $ultimo) { $ultimo = $s; try { Razao-Gravar $RazaoDir @{ evento = 'membros_job'; execucao = $execucao; pids = @($mb) } } catch { } } }
  }
  Start-Sleep -Milliseconds 100
}
$ctl.WaitForExit()
$codigo = $ctl.ExitCode

# ---------------- H9: reconciliação depois ----------------
$m = Conferir-Reconciliacao 'depois'
if ($m) { try { Razao-Gravar $RazaoDir @{ evento = 'divergencia_reconciliacao'; execucao = $execucao; detalhe = $m } } catch { }; Parar 28 $m }
if ($BaixaIntegridade -and $env:B05_BAIXO_DIR -and (Test-Path -LiteralPath $env:B05_BAIXO_DIR)) { try { Remove-Item -Recurse -Force $env:B05_BAIXO_DIR -ErrorAction SilentlyContinue } catch { } }
exit $codigo
