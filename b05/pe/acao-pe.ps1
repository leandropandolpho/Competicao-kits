# acao-pe.ps1 - embrulho do PE (gate de isolamento de principal). Roda COMO a tarefa agendada, sob o principal PE.
# Ato - Autonomous multi-LLM orchestration flow - 123. Base: contrato v0.2 + Adendo A111. Controlador 7cd7864 congelado.
# Reconstroi sob o PE as garantias do B-05 (E107-01/CA-8): Job proprio KILL_ON_JOB_CLOSE, executor nivel 4096 em_job,
# sem orfaos (Verificar), identidade PID+criacao, varredura reparse fail-closed, timeout proprio. NUNCA escreve o razao.
# Correcoes do Ato 122 (ChatGPT PE-F01..F06 + Gemini): PE-F01 espera distingue sinal/codigo (EsperarSinal); PE-F02
# $TestCmd sob PE E Low IL (nivel 4096); PE-F03 Verificar(job) real + sem orfaos; PE-F04 timeout/falha do teste =
# erro terminal; PE-F05 falha vira estado terminal (falhou.flag), nao reselecionada; PE-F06 hash do pwsh OBRIGATORIO.
# Gemini: metadados IPC em Medium IL (so stdout/stderr/arvore em Low); $TestCmd SEM a chave do PE (T7). ASCII puro.
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$PonteDir,
  [string]$ConfigDir = $env:CLAUDE_CONFIG_DIR,
  [string]$CredFile,
  [Parameter(Mandatory)] [string]$PwshAprovado,
  [Parameter(Mandatory)] [string]$PwshSha256,   # PE-F06: obrigatorio
  [int]$TimeoutSeg = 1800,
  [switch]$Simular,
  [switch]$Laco
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$Utf8 = [System.Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot '..\b05job.ps1')
if (-not $Simular) { . (Join-Path $PSScriptRoot '..\baixa-integridade.ps1') }

function Agora { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
function Grava([string]$dir,[string]$nome,[string]$txt) {   # escrita atomica com overwrite (heartbeat e reescrito)
  $tmp = Join-Path $dir ($nome + '.tmp'); [System.IO.File]::WriteAllText($tmp, $txt, $Utf8)
  [System.IO.File]::Move($tmp, (Join-Path $dir $nome), $true)
}
function Json($o) { $o | ConvertTo-Json -Compress -Depth 6 }
# PE-R4: ler a E/S redirecionada TOLERANDO um descendente que ainda segura o handle herdado (cmd/ping neto do executor
# mantem out.txt aberto ate ser ceifado pelo KILL_ON_JOB_CLOSE). FileShare.ReadWrite evita "being used by another process".
function LerCompart([string]$caminho) {
  if (-not (Test-Path -LiteralPath $caminho)) { return '' }
  $fs = [System.IO.FileStream]::new($caminho, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  try { $sr = [System.IO.StreamReader]::new($fs, $Utf8); try { return $sr.ReadToEnd() } finally { $sr.Dispose() } }
  finally { $fs.Dispose() }
}

# PE-F06 / ADM-V5-02: executor/pwsh APROVADO, acessivel, com hash OBRIGATORIO conferido. Sem isso, falha fechada.
function Conferir-Pwsh([string]$caminho,[string]$shaEsperado) {
  if (-not $caminho) { throw 'ADM-V5-02: PwshAprovado nao informado.' }
  if (-not (Test-Path -LiteralPath $caminho)) { throw "ADM-V5-02: pwsh aprovado inacessivel ao PE: $caminho" }
  if (-not $shaEsperado) { throw 'ADM-V5-02/PE-F06: SHA-256 aprovado OBRIGATORIO.' }
  $h = (Get-FileHash -LiteralPath $caminho -Algorithm SHA256).Hash
  if ($h -ne $shaEsperado.ToUpper().Replace(':','')) { throw "ADM-V5-02: SHA-256 do pwsh ($h) != aprovado." }
}

# Ambiente higienizado (E84-03). $comChave=$false para o $TestCmd (Gemini 2.2 / T7: teste nao recebe a chave do PE).
function Ambiente-PE([string]$cTmp, [bool]$comChave = $true) {
  $v = @{}
  foreach ($e in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
    $n = [string]$e.Key
    if ($n -like 'B05_*' -or $n -match '(?i)openai|anthropic|supervisora|supabase|_KEY$|_TOKEN$|_SECRET$|APIKEY|ACCESS_KEY') { continue }
    $v[$n] = [string]$e.Value
  }
  foreach ($e in Get-ChildItem Env:B05FAKE_* -ErrorAction SilentlyContinue) { $v[$e.Name] = $e.Value }
  $v['TEMP'] = $cTmp; $v['TMP'] = $cTmp
  if ($ConfigDir) { $v['CLAUDE_CONFIG_DIR'] = $ConfigDir }
  if ($comChave -and $CredFile -and (Test-Path -LiteralPath $CredFile)) { $v['ANTHROPIC_API_KEY'] = ([System.IO.File]::ReadAllText($CredFile)).Trim() }
  return $v
}

# Lanca um processo low-IL (executor OU teste), espera com distincao sinal/codigo (PE-F01), confere nivel 4096 e em_job.
# Devolve @{ Codigo; Nivel; EmJob; Pid; Criacao; Saida; Erro }. Em timeout: mata o job e lanca (PE-F04).
function Rodar-LowIL([IntPtr]$job,[string]$exe,[string[]]$argz,[string]$cwd,[hashtable]$env,[string]$cTmp,[int]$timeoutSeg) {
  $inF = "$cTmp\in.txt"; $outF = "$cTmp\out.txt"; $errF = "$cTmp\err.txt"
  if (-not (Test-Path $inF)) { [System.IO.File]::WriteAllText($inF, '', $Utf8) }
  $tok = [IntPtr]::Zero; $m = [B05LowIL]::CriarToken([ref]$tok); if ($m) { throw "token baixo: $m" }
  $cmdline = B05LowIL-Cmdline $exe $argz $inF $outF $errF
  $bloco = B05LowIL-BlocoAmbiente $env
  $lpid = 0; $hProc = [IntPtr]::Zero
  try { $ml = [B05LowIL]::Lancar($tok, $cmdline, $cwd, $bloco, [ref]$lpid, [ref]$hProc) }
  finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($bloco); [B05LowIL]::Fechar($tok) }
  if ($ml) { throw "low-IL nao iniciou: $ml" }
  [void][B05Job]::AssignProcessToJobObject($job, $hProc)   # PE-F05: associa o FILHO (nao o acao-pe) ao job
  try { [B05Job]::Rastrear([uint32]$lpid) } catch { }       # rastreia enquanto vivo (p/ Verificar depois)
  $cri = [B05LowIL]::CriacaoUtc($hProc); $emJob = [B05LowIL]::EmJob($hProc)
  $nivel = [B05LowIL]::NivelH($hProc)   # PE-R1: nivel pelo handle (robusto a executor que sai rapido; Nivel(pid) tem corrida)
  $sinal = [B05LowIL]::EsperarSinal($hProc, [uint32]($timeoutSeg * 1000))
  if ($sinal -ne 0) { [void][B05Job]::TerminateJobObject($job, 29); [B05LowIL]::Fechar($hProc); throw "timeout/espera (sinal 0x$($sinal.ToString('X'))) apos ${timeoutSeg}s: job encerrado" }
  $cod = [int][B05LowIL]::Esperar($hProc, 0)   # ja sinalizado: codigo real (nao 259)
  [B05LowIL]::Fechar($hProc)
  # PE-R1: ler para variaveis ANTES do hashtable. Em @{...} um valor (if...) e lido como pipeline (comando 'if'
  # inexistente) e quebra em runtime (o parser aceita, mas falha ao executar). if-de-atribuicao e valido.
  $saidaTxt = LerCompart $outF
  $erroTxt  = LerCompart $errF
  @{ Codigo=$cod; Nivel=$nivel; EmJob=$emJob; Pid=$lpid; Criacao=$cri; Saida=$saidaTxt; Erro=$erroTxt }
}

function Processar([string]$dir) {
  $ped = Get-Content -LiteralPath (Join-Path $dir 'pedido.json') -Raw -Encoding utf8 | ConvertFrom-Json
  $execId = "$($ped.exec_id)"
  $entrada = if (Test-Path (Join-Path $dir 'prompt.in')) { [System.IO.File]::ReadAllText((Join-Path $dir 'prompt.in'), $Utf8) } else { '' }
  $exe = "$($ped.executor)"
  $argExec = @(if ("$($ped.executor_prefixo)") { "$($ped.executor_prefixo)" -split '\|' }) + @('-p') +
             @(if ($ped.PSObject.Properties['teto_usd'] -and $ped.teto_usd) { '--max-budget-usd', ([string]$ped.teto_usd).Replace(',', '.') })
  Grava $dir 'heartbeat' ([string](Agora))

  # Job proprio: KILL_ON_JOB_CLOSE + UI restrita. PE-F05: o acao-pe NAO se associa ao job (senao TerminateJobObject no
  # timeout mataria o proprio acao-pe antes de marcar o estado terminal). Associa-se o FILHO (executor/teste) pos-criacao;
  # KILL_ON_JOB_CLOSE limpa qualquer remanescente quando o acao-pe sair (fecha o ultimo handle do job).
  $job = [B05Job]::CreateJobObject([IntPtr]::Zero, $null)
  if ($job -eq [IntPtr]::Zero) { throw 'Job Object nao criado' }
  if (-not [B05Job]::Configurar($job, [B05Job]::KILL_ON_JOB_CLOSE)) { throw 'Configurar(KILL_ON_JOB_CLOSE) falhou' }
  [void][B05Job]::RestringirUI($job)

  $cTmp = Join-Path ($env:TEMP) ('pe-' + $execId.Substring(0,12)); New-Item -ItemType Directory -Force $cTmp | Out-Null
  $pid_exec = 0; $criacao = ''; $nivel = $null; $emJob = $null; $saida = ''; $erro = ''; $codigo = -2

  if ($Simular) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new($exe)
    foreach ($a in $argExec) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false; $psi.WorkingDirectory = (Get-Location).Path
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $Utf8; $psi.StandardErrorEncoding = $Utf8
    foreach ($kv in (Ambiente-PE $cTmp).GetEnumerator()) { $psi.Environment[$kv.Key] = $kv.Value }
    $p = [System.Diagnostics.Process]::Start($psi); $pid_exec = $p.Id
    [void][B05Job]::AssignProcessToJobObject($job, $p.Handle)   # associa o filho (nao o acao-pe)
    try { [B05Job]::Rastrear([uint32]$pid_exec) } catch { }
    try { $criacao = $p.StartTime.ToUniversalTime().ToString('o') } catch { $criacao = (Get-Date).ToUniversalTime().ToString('o') }
    $r0 = $false; if ($IsWindows) { try { $emJob = ([B05Job]::IsProcessInJob($p.Handle, [IntPtr]::Zero, [ref]$r0)) -and $r0 } catch { } }
    Grava $dir 'pe.pid' (Json @{ pid = $pid_exec; criacao_utc = $criacao; nivel_il = $nivel; em_job = $emJob })
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    try { $b = $Utf8.GetBytes($entrada); $p.StandardInput.BaseStream.Write($b,0,$b.Length); $p.StandardInput.Close() } catch { }
    if (-not $p.WaitForExit($TimeoutSeg * 1000)) { [void][B05Job]::TerminateJobObject($job, 29); throw "timeout ${TimeoutSeg}s: job encerrado" }
    $saida = $out.Result; $erro = $err.Result; $codigo = $p.ExitCode
  } else {
    $cmd = Get-Command -Name $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $exe = $cmd.Source }
    & icacls $cTmp /setintegritylevel '(OI)(CI)low' /Q 2>&1 | Out-Null   # so a E/S bruta e a arvore sao Low; metadados IPC ficam Medium
    [System.IO.File]::WriteAllText("$cTmp\in.txt", $entrada, $Utf8)
    $res = Rodar-LowIL $job $exe $argExec (Get-Location).Path (Ambiente-PE $cTmp $true) $cTmp $TimeoutSeg
    $pid_exec = $res.Pid; $criacao = [DateTime]::FromFileTimeUtc($res.Criacao).ToString('o'); $nivel = $res.Nivel; $emJob = $res.EmJob
    Grava $dir 'pe.pid' (Json @{ pid = $pid_exec; criacao_utc = $criacao; nivel_il = $nivel; em_job = $emJob })
    if ($emJob -ne $true) { throw "executor fora do job (em_job=$emJob)" }
    if ($nivel -ne 4096) { throw "executor nao esta em baixa integridade (nivel $nivel)" }
    $saida = $res.Saida; $erro = $res.Erro; $codigo = $res.Codigo
    $rep = B05LowIL-ReparsePoints (Get-Location).Path
    if (-not $rep.Ok -or @($rep.Pontos).Count) { throw "reparse point/varredura incompleta: $(@($rep.Pontos) -join '; ')" }
  }

  # PE-F03: verificacao REAL de contencao - nenhum descendente rastreado vivo fora do job. (A prova externa definitiva
  # de ausencia de orfaos + morte do PE e do PU, apos fim.flag, por PID+criacao; aqui e a checagem local fail-closed.)
  $viol = [B05Job]::Verificar($job)
  if (@($viol).Count) { throw "contencao: descendente fora do job/orfao: $(@($viol) -join '; ')" }

  Grava $dir 'stdout.json' $saida
  Grava $dir 'stderr.txt' $erro
  Grava $dir 'exit.code' ([string]$codigo)

  # PE-F02/PE-F04/Gemini-2.2: $TestCmd sob o PE, apos o executor morto, em Low IL (real) e SEM a chave; timeout/falha = erro terminal.
  if ("$($ped.test_cmd)") {
    Grava $dir 'heartbeat' ([string](Agora))
    $argTeste = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command', "$($ped.test_cmd)")
    if ($Simular) {
      $pt = [System.Diagnostics.ProcessStartInfo]::new($PwshAprovado)
      foreach ($a in $argTeste) { $pt.ArgumentList.Add($a) }
      $pt.UseShellExecute = $false; $pt.WorkingDirectory = (Get-Location).Path
      $pt.RedirectStandardOutput = $true; $pt.RedirectStandardError = $true
      foreach ($kv in (Ambiente-PE $cTmp $false).GetEnumerator()) { $pt.Environment[$kv.Key] = $kv.Value }  # SEM chave
      $pp = [System.Diagnostics.Process]::Start($pt)
      $tout = $pp.StandardOutput.ReadToEndAsync(); $terr = $pp.StandardError.ReadToEndAsync()
      if (-not $pp.WaitForExit($TimeoutSeg * 1000)) { [void][B05Job]::TerminateJobObject($job, 29); throw "timeout do TestCmd: job encerrado" }   # PE-F04
      Grava $dir 'teste.txt' ("codigo=$($pp.ExitCode)`n" + $tout.Result + $terr.Result)
    } else {
      $cT = Join-Path ($env:TEMP) ('pet-' + $execId.Substring(0,12)); New-Item -ItemType Directory -Force $cT | Out-Null
      & icacls $cT /setintegritylevel '(OI)(CI)low' /Q 2>&1 | Out-Null
      $rt = Rodar-LowIL $job $PwshAprovado $argTeste (Get-Location).Path (Ambiente-PE $cT $false) $cT $TimeoutSeg
      if ($rt.Nivel -ne 4096) { throw "TestCmd nao rodou em Low IL (nivel $($rt.Nivel))" }   # PE-F02
      Grava $dir 'teste.txt' ("codigo=$($rt.Codigo) nivel=$($rt.Nivel)`n" + $rt.Saida + $rt.Erro)
      try { Remove-Item -Recurse -Force $cT -ErrorAction SilentlyContinue } catch { }
    }
  }
  try { Remove-Item -Recurse -Force $cTmp -ErrorAction SilentlyContinue } catch { }

  Grava $dir 'heartbeat' ([string](Agora))
  Grava $dir 'fim.flag' (Json @{ exec_id = $execId; pe_pid = $PID; codigo = $codigo; fim_utc = (Get-Date).ToUniversalTime().ToString('o') })
  # O job (com este processo) morre com KILL_ON_JOB_CLOSE quando este processo sair => nenhum orfao sobrevive ao PE.
}

# PE-F05: falha vira estado TERMINAL (falhou.flag). Pendente ignora fim.flag E falhou.flag => nao reselecionada; nova
# tentativa so por decisao explicita do PU (que remove falhou.flag/reemite). Evita chamadas cobradas repetidas.
function Pendente { Get-ChildItem -Directory $PonteDir -ErrorAction SilentlyContinue |
  Where-Object { (Test-Path (Join-Path $_.FullName 'go.flag')) -and
                 -not (Test-Path (Join-Path $_.FullName 'fim.flag')) -and
                 -not (Test-Path (Join-Path $_.FullName 'falhou.flag')) } |
  Sort-Object LastWriteTime | Select-Object -First 1 }
function Tratar([string]$d) {
  try { Processar $d }
  catch {
    Grava $d 'erro-pe.txt' $_.Exception.Message
    Grava $d 'falhou.flag' (Json @{ erro = $_.Exception.Message; quando = (Get-Date).ToUniversalTime().ToString('o') })   # terminal
    throw
  }
}

Conferir-Pwsh $PwshAprovado $PwshSha256
if ($Laco) {
  while ($true) { $d = Pendente; if ($d) { try { Tratar $d.FullName } catch { } } else { Start-Sleep -Seconds 2 } }
} else {
  $d = Pendente
  if (-not $d) { throw "nenhuma execucao pendente com go.flag em $PonteDir" }
  Tratar $d.FullName
}
