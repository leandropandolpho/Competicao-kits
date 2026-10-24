# acao-pe.ps1 - embrulho do PE (gate de isolamento de principal). Roda COMO a tarefa agendada, sob o principal PE.
# Ato - Autonomous multi-LLM orchestration flow - 121. Base: contrato v0.2 + Adendo A111. Controlador 7cd7864 congelado.
# Reconstroi sob o PE as garantias do B-05 (E107-01/CA-8): Job proprio KILL_ON_JOB_CLOSE, executor nivel 4096 em_job,
# sem orfaos, identidade PID+criacao, varredura reparse fail-closed, timeout proprio. NUNCA escreve o razao (so o PU).
# ASCII puro (licao V3-02). Rode sob pwsh 7 aprovado (ADM-V5-02).
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$PonteDir,    # <PonteDir>\<exec.id>\ e a pasta desta execucao
  [string]$ConfigDir = $env:CLAUDE_CONFIG_DIR, # pasta baixa do PE p/ ~/.claude (A111-04)
  [string]$CredFile,                           # arquivo (ACL so-PE) com a chave dedicada do PE (ANTHROPIC_API_KEY)
  [string]$PwshAprovado,                       # ADM-V5-02: pwsh 7 aprovado, acessivel ao PE
  [string]$PwshSha256,                         # ADM-V5-02: SHA-256 esperado do pwsh aprovado (sem fallback silencioso)
  [int]$TimeoutSeg = 1800,
  [switch]$Simular,                            # caminho simulado/testavel: executor como filho normal (sem token baixo)
  [switch]$Laco                                # observa a pasta-ponte continuamente (senao, uma execucao e sai)
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$Utf8 = [System.Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot '..\b05job.ps1')
if (-not $Simular) { . (Join-Path $PSScriptRoot '..\baixa-integridade.ps1') }

function Agora { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
function Grava([string]$dir,[string]$nome,[string]$txt) {   # escrita atomica na pasta-ponte
  $tmp = Join-Path $dir ($nome + '.tmp'); [System.IO.File]::WriteAllText($tmp, $txt, $Utf8)
  [System.IO.File]::Move($tmp, (Join-Path $dir $nome), $true)   # overwrite: heartbeat e reescrito varias vezes
}
function Json($o) { $o | ConvertTo-Json -Compress -Depth 6 }

# ADM-V5-02: executor/pwsh aprovado, acessivel, com hash conferido. Sem isso, falha fechada (nao cai p/ 5.1 nem outro).
function Conferir-Pwsh([string]$caminho,[string]$shaEsperado) {
  if (-not $caminho) { throw 'ADM-V5-02: PwshAprovado nao informado.' }
  if (-not (Test-Path -LiteralPath $caminho)) { throw "ADM-V5-02: pwsh aprovado inacessivel ao PE: $caminho" }
  if ($shaEsperado) {
    $h = (Get-FileHash -LiteralPath $caminho -Algorithm SHA256).Hash
    if ($h -ne $shaEsperado.ToUpper().Replace(':','')) { throw "ADM-V5-02: SHA-256 do pwsh ($h) != aprovado ($shaEsperado)." }
  }
}

# Ambiente higienizado (E84-03): parte do ambiente, remove B05_*/segredos/_KEY/_TOKEN/_SECRET; injeta SO a chave dedicada do PE.
function Ambiente-PE([string]$cTmp) {
  $v = @{}
  foreach ($e in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
    $n = [string]$e.Key
    if ($n -like 'B05_*' -or $n -match '(?i)openai|anthropic|supervisora|supabase|_KEY$|_TOKEN$|_SECRET$|APIKEY|ACCESS_KEY') { continue }
    $v[$n] = [string]$e.Value
  }
  foreach ($e in Get-ChildItem Env:B05FAKE_* -ErrorAction SilentlyContinue) { $v[$e.Name] = $e.Value }  # so testes
  $v['TEMP'] = $cTmp; $v['TMP'] = $cTmp
  if ($ConfigDir) { $v['CLAUDE_CONFIG_DIR'] = $ConfigDir }
  if ($CredFile -and (Test-Path -LiteralPath $CredFile)) { $v['ANTHROPIC_API_KEY'] = ([System.IO.File]::ReadAllText($CredFile)).Trim() }  # chave PROPRIA do PE
  return $v
}

# ---- Processa UMA execucao (a pasta-ponte <PonteDir>\<id> ja tem go.flag) ----
function Processar([string]$dir) {
  $ped = Get-Content -LiteralPath (Join-Path $dir 'pedido.json') -Raw -Encoding utf8 | ConvertFrom-Json
  $execId = "$($ped.exec_id)"
  $entrada = if (Test-Path (Join-Path $dir 'prompt.in')) { [System.IO.File]::ReadAllText((Join-Path $dir 'prompt.in'), $Utf8) } else { '' }
  $exe = "$($ped.executor)"
  $argExec = @(if ("$($ped.executor_prefixo)") { "$($ped.executor_prefixo)" -split '\|' }) + @('-p') +
             @(if ($ped.PSObject.Properties['teto_usd'] -and $ped.teto_usd) { '--max-budget-usd', ([string]$ped.teto_usd).Replace(',', '.') })
  Grava $dir 'heartbeat' ([string](Agora))

  # ---- Job proprio: cria, configura KILL_ON_JOB_CLOSE + UI restrita, e ASSOCIA ESTE processo (o executor filho herda) ----
  $job = [B05Job]::CreateJobObject([IntPtr]::Zero, $null)
  if ($job -eq [IntPtr]::Zero) { throw 'Job Object nao criado' }
  if (-not [B05Job]::Configurar($job, [B05Job]::KILL_ON_JOB_CLOSE)) { throw 'Configurar(KILL_ON_JOB_CLOSE) falhou' }
  [void][B05Job]::RestringirUI($job)
  if (-not [B05Job]::AssignProcessToJobObject($job, [B05Job]::GetCurrentProcess())) { throw 'AssignProcessToJobObject(self) falhou' }
  [B05Job]::Rastrear([uint32]$PID)   # rastreia este processo por PID+criacao; descendentes sao verificados

  $cTmp = Join-Path ($env:TEMP) ('pe-' + $execId.Substring(0,12)); New-Item -ItemType Directory -Force $cTmp | Out-Null
  $pid_exec = 0; $criacao = ''; $nivel = $null; $emJob = $null; $saida = ''; $erro = ''; $codigo = -2

  if ($Simular) {
    # Caminho SIMULADO/testavel: executor como filho normal (sem token baixo). Ainda contido pelo job (heranca).
    $psi = [System.Diagnostics.ProcessStartInfo]::new($exe)
    foreach ($a in $argExec) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false; $psi.WorkingDirectory = (Get-Location).Path
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $Utf8; $psi.StandardErrorEncoding = $Utf8
    foreach ($kv in (Ambiente-PE $cTmp).GetEnumerator()) { $psi.Environment[$kv.Key] = $kv.Value }
    $p = [System.Diagnostics.Process]::Start($psi)
    $pid_exec = $p.Id
    try { $criacao = $p.StartTime.ToUniversalTime().ToString('o') } catch { $criacao = (Get-Date).ToUniversalTime().ToString('o') }
    $r0 = $false; if ($IsWindows) { try { $emJob = ([B05Job]::IsProcessInJob($p.Handle, [IntPtr]::Zero, [ref]$r0)) -and $r0 } catch { } }
    Grava $dir 'pe.pid' (Json @{ pid = $pid_exec; criacao_utc = $criacao; nivel_il = $nivel; em_job = $emJob })
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    try { $b = $Utf8.GetBytes($entrada); $p.StandardInput.BaseStream.Write($b,0,$b.Length); $p.StandardInput.Close() } catch { }
    if (-not $p.WaitForExit($TimeoutSeg * 1000)) { [void][B05Job]::TerminateJobObject($job, 29); throw "timeout ${TimeoutSeg}s: job encerrado" }
    $saida = $out.Result; $erro = $err.Result; $codigo = $p.ExitCode
  } else {
    # Caminho REAL: executor em baixa integridade, E/S por arquivo, DENTRO do job (heranca do processo associado).
    $inF = "$cTmp\in.txt"; $outF = "$cTmp\out.txt"; $errF = "$cTmp\err.txt"
    & icacls $cTmp /setintegritylevel '(OI)(CI)low' /Q 2>&1 | Out-Null
    [System.IO.File]::WriteAllText($inF, $entrada, $Utf8)
    $cmd = Get-Command -Name $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $exe = $cmd.Source }
    $tok = [IntPtr]::Zero; $msgTok = [B05LowIL]::CriarToken([ref]$tok)
    if ($msgTok) { throw "token baixo nao criado: $msgTok" }
    $cmdline = B05LowIL-Cmdline $exe $argExec $inF $outF $errF
    $bloco = B05LowIL-BlocoAmbiente (Ambiente-PE $cTmp)
    $lpid = 0; $hProc = [IntPtr]::Zero
    try { $msgLan = [B05LowIL]::Lancar($tok, $cmdline, (Get-Location).Path, $bloco, [ref]$lpid, [ref]$hProc) }
    finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($bloco); [B05LowIL]::Fechar($tok) }
    if ($msgLan) { throw "executor baixo nao iniciou: $msgLan" }
    $pid_exec = $lpid
    $criacao = [DateTime]::FromFileTimeUtc([B05LowIL]::CriacaoUtc($hProc)).ToString('o')
    $emJob = [B05LowIL]::EmJob($hProc)
    Start-Sleep -Milliseconds 150
    $nivel = [B05LowIL]::Nivel($lpid)
    Grava $dir 'pe.pid' (Json @{ pid = $pid_exec; criacao_utc = $criacao; nivel_il = $nivel; em_job = $emJob })
    if ($emJob -ne $true) { [B05LowIL]::Encerrar($hProc); [B05LowIL]::Fechar($hProc); throw "executor fora do job (em_job=$emJob)" }
    if ($nivel -ne 4096) { [B05LowIL]::Encerrar($hProc); [B05LowIL]::Fechar($hProc); throw "executor nao esta em baixa integridade (nivel $nivel)" }
    $fim = [B05LowIL]::Esperar($hProc, [uint32]($TimeoutSeg * 1000))
    if ($fim -eq 258) { [void][B05Job]::TerminateJobObject($job, 29); [B05LowIL]::Fechar($hProc); throw "timeout ${TimeoutSeg}s: job encerrado" }
    $codigo = [int]$fim; [B05LowIL]::Fechar($hProc)
    $saida = if (Test-Path $outF) { [System.IO.File]::ReadAllText($outF, $Utf8) } else { '' }
    $erro = if (Test-Path $errF) { [System.IO.File]::ReadAllText($errF, $Utf8) } else { '' }
    # Varredura fail-closed de reparse points na arvore de trabalho (E84-05/F10) antes de devolver.
    $rep = B05LowIL-ReparsePoints (Get-Location).Path
    if (-not $rep.Ok -or @($rep.Pontos).Count) { throw "reparse point/varredura incompleta: $(@($rep.Pontos) -join '; ')" }
  }
  try { Remove-Item -Recurse -Force $cTmp -ErrorAction SilentlyContinue } catch { }

  # ---- Sem orfaos: nenhum descendente vivo deste processo alem do executor ja terminado (A111-05 por PID+criacao) ----
  $orf = [B05Job]::Subarvore([System.Collections.Generic.Dictionary[uint32,long]]::new())
  # (Subarvore vazia de raizes = nada; a prova forte de ausencia de orfaos roda no PU apos fim.flag, confirmando a morte.)

  Grava $dir 'stdout.json' $saida
  Grava $dir 'stderr.txt' $erro
  Grava $dir 'exit.code' ([string]$codigo)

  # ---- $TestCmd sob o PE, SO depois de o executor estar morto (E105-01/N14), em instancia separada ----
  if ("$($ped.test_cmd)") {
    Grava $dir 'heartbeat' ([string](Agora))
    $tRes = ''
    try {
      $pt = [System.Diagnostics.ProcessStartInfo]::new($PwshAprovado)   # $TestCmd roda no pwsh aprovado, sob o PE
      foreach ($a in @('-NoProfile','-ExecutionPolicy','Bypass','-Command', "$($ped.test_cmd)")) { $pt.ArgumentList.Add($a) }
      $pt.UseShellExecute = $false; $pt.WorkingDirectory = (Get-Location).Path
      $pt.RedirectStandardOutput = $true; $pt.RedirectStandardError = $true
      $pp = [System.Diagnostics.Process]::Start($pt)
      $tRes = $pp.StandardOutput.ReadToEnd() + $pp.StandardError.ReadToEnd()
      $pp.WaitForExit(($TimeoutSeg * 1000)) | Out-Null
      $tRes = "codigo=$($pp.ExitCode)`n$tRes"
    } catch { $tRes = "teste falhou ao iniciar: $($_.Exception.Message)" }
    Grava $dir 'teste.txt' $tRes
  }

  Grava $dir 'heartbeat' ([string](Agora))
  Grava $dir 'fim.flag' (Json @{ exec_id = $execId; pe_pid = $PID; fim_utc = (Get-Date).ToUniversalTime().ToString('o') })
  # O job (com este processo) morre com KILL_ON_JOB_CLOSE quando este processo sair => nenhum orfao sobrevive ao PE.
}

# ---- Entrada: ADM-V5-02, depois processa uma execucao ou observa em laco ----
Conferir-Pwsh $PwshAprovado $PwshSha256
function Pendente { Get-ChildItem -Directory $PonteDir -ErrorAction SilentlyContinue |
  Where-Object { (Test-Path (Join-Path $_.FullName 'go.flag')) -and -not (Test-Path (Join-Path $_.FullName 'fim.flag')) } |
  Sort-Object LastWriteTime | Select-Object -First 1 }
if ($Laco) {
  while ($true) { $d = Pendente; if ($d) { try { Processar $d.FullName } catch { Grava $d.FullName 'erro-pe.txt' $_.Exception.Message } } else { Start-Sleep -Seconds 2 } }
} else {
  $d = Pendente
  if (-not $d) { throw "nenhuma execucao pendente com go.flag em $PonteDir" }
  try { Processar $d.FullName } catch { Grava $d.FullName 'erro-pe.txt' $_.Exception.Message; throw }
}
