# claude-com-teto.ps1 — embrulho do executor (B-05, contrato v3.1). Chamado pelo controlador congelado via
# claude-com-teto.cmd (que usa o pwsh portátil de B05_PWSH), no lugar do "claude". Antes de CADA chamada:
# trava → reconcilia o razão → admissão B+K+R+T(1+F) ≤ M → reserva (inicio durável) → executor com
# --max-budget-usd → pid+criação obrigatórios (H10) → fim.
# Configuração imutável por execução (H6): B05_DIR/config-<B05_EXECUCAO>.json.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$Utf8 = [System.Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'razao.ps1')

function Sair-Erro([string]$msg, [int]$codigo = 1) {
  # Resposta no formato do claude -p: o controlador trata como falha da tentativa (custo 0, sem alteração).
  [Console]::Out.Write(([ordered]@{ type = 'result'; subtype = 'error_b05'; is_error = $true; result = "B05: $msg"; total_cost_usd = 0 } | ConvertTo-Json -Compress))
  exit $codigo
}

$dir = $env:B05_DIR; $execucao = $env:B05_EXECUCAO
if (-not $dir -or -not $execucao -or $execucao -notmatch '^[0-9a-f]{32}$') { Sair-Erro 'B05_DIR ou B05_EXECUCAO ausente/inválido' }
$arqCfg = Join-Path $dir "config-$execucao.json"
if (-not (Test-Path -LiteralPath $arqCfg)) { Sair-Erro "configuração da execução ausente: config-$execucao.json" }
$cfg = Get-Content -LiteralPath $arqCfg -Raw -Encoding utf8 | ConvertFrom-Json
if ("$($cfg.execucao)" -ne $execucao) { Sair-Erro 'configuração não corresponde à execução' }
$teto = [double]$cfg.teto_chamada_usd; $folga = [double]$cfg.folga; $orc = [double]$cfg.orcamento_usd
$entrada = if ([Console]::IsInputRedirected) { [Console]::In.ReadToEnd() } else { '' }

# ---- Trava + reconciliação + reserva (E1, E4) ----
$mtx = [System.Threading.Mutex]::new($false, (Razao-Nome-Trava $dir))
$id = [guid]::NewGuid().ToString('N')
try {
  $obtida = $false
  try { $obtida = $mtx.WaitOne(60000) } catch {
    $ex = $_.Exception; while ($ex -and -not ($ex -is [System.Threading.AbandonedMutexException])) { $ex = $ex.InnerException }
    if ($ex) { $obtida = $true } else { Sair-Erro "trava do razão: $($_.Exception.Message)" }
  }
  if (-not $obtida) { Sair-Erro 'trava do razão não obtida em 60 s' }
  $r = Razao-Ler $dir
  if (-not $r.Ok) { Sair-Erro "razão ilegível: $($r.Motivo)" }
  # E84-01: trava financeira durável. Depois de uma resposta com custo inválido, nenhuma chamada da MESMA execução
  # volta a invocar o executor — falha fecha em 28 sem gastar nada.
  if (@($r.Eventos | Where-Object { $_.evento -eq 'trava_financeira' -and "$($_.execucao)" -eq $execucao }).Count) {
    Sair-Erro 'trava financeira ativa: resposta anterior do executor trouxe custo inválido; execução bloqueada' 28
  }
  $c = Razao-Contabilizar $r.Eventos $folga
  if ($c.Total + $teto * (1 + $folga) -gt $orc) {
    try { Razao-Gravar $dir @{ evento = 'bloqueado'; execucao = "$($cfg.execucao)"; motivo = 'orcamento'; gasto_contabilizado = $c.Total; orcamento_usd = $orc } } catch { }
    Sair-Erro "orçamento insuficiente (base $($c.Base) + conhecido $($c.Conhecido) + reservado $($c.Reservado) = US$ $($c.Total) + reserva $([math]::Round($teto * (1 + $folga), 4)) > US$ $orc)"
  }
  try { Razao-Gravar $dir @{ evento = 'inicio'; id = $id; execucao = "$($cfg.execucao)"; teto_usd = $teto; folga = $folga } }
  catch { Sair-Erro "falha ao gravar a reserva no razão: $($_.Exception.Message)" }
} finally { try { $mtx.ReleaseMutex() } catch { }; $mtx.Dispose() }

# ---- Executor (C1, E2, E5) ----
$exe = "$($cfg.executor)"
$cmd = Get-Command -Name $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cmd) { $exe = $cmd.Source }
$argExec = @(if ("$($cfg.executor_prefixo)") { "$($cfg.executor_prefixo)" -split '\|' }) + @($args | ForEach-Object { [string]$_ }) + @('--max-budget-usd', ([string]$teto).Replace(',', '.'))
$lowil = $IsWindows -and $cfg.PSObject.Properties['baixa_integridade'] -and $cfg.baixa_integridade

if (-not $lowil) {
  # ---- Caminho de integridade MÉDIA (tests simulados, não-Windows, fallback) ----
  $psi = [System.Diagnostics.ProcessStartInfo]::new($exe)
  foreach ($a in $argExec) { $psi.ArgumentList.Add($a) }
  $psi.UseShellExecute = $false; $psi.WorkingDirectory = (Get-Location).Path
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8; $psi.StandardErrorEncoding = $Utf8
  try { $p = [System.Diagnostics.Process]::Start($psi) }
  catch {
    try { Razao-Gravar $dir @{ evento = 'fim'; id = $id; custo_usd = 0.0; custo_desconhecido = $false; motivo = 'falha_antes_da_invocacao'; codigo = -2 } } catch { }
    Sair-Erro "executor não iniciou: $($_.Exception.Message)"
  }
  try { $criacao = $p.StartTime.ToUniversalTime().ToString('o') } catch { $criacao = (Get-Date).ToUniversalTime().ToString('o') }
  $emJob = $null
  if ($IsWindows) {
    try {
      Add-Type -Namespace B05 -Name Proc -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true)] public static extern bool IsProcessInJob(System.IntPtr proc, System.IntPtr job, out bool result);' -ErrorAction Stop
      $r0 = $false; if ([B05.Proc]::IsProcessInJob($p.Handle, [IntPtr]::Zero, [ref]$r0)) { $emJob = $r0 }
    } catch { }
  }
  try {
    if ($env:B05_TESTE_FALHAR_PID -eq '1') { throw 'falha de gravação injetada (teste N15)' }
    Razao-Gravar $dir @{ evento = 'pid'; id = $id; execucao = $execucao; pid = $p.Id; criacao = $criacao; em_job = $emJob; nivel_il = $null; argumentos = @($argExec) }
  } catch {
    $msg = $_.Exception.Message
    try { $p.Kill($true) } catch { }; try { $p.WaitForExit(10000) | Out-Null } catch { }
    Sair-Erro "falha ao gravar o pid no razão ($msg): executor encerrado, reserva mantida" 3
  }
  if ($IsWindows -and $emJob -ne $true) { try { $p.Kill($true) } catch { }; Sair-Erro "executor fora do Job Object (em_job=$emJob): encerrado, reserva mantida" 4 }
  $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
  try { $b = $Utf8.GetBytes($entrada); $p.StandardInput.BaseStream.Write($b, 0, $b.Length); $p.StandardInput.Close() } catch { }
  $p.WaitForExit()
  $saida = $out.Result; $erro = $err.Result; $codigo = $p.ExitCode
} else {
  # ---- E84-02: executor em BAIXA integridade (token restrito, sem herança de handles), E/S por redireção de arquivo ----
  . (Join-Path $PSScriptRoot 'baixa-integridade.ps1')
  $raizBaixo = if ($env:B05_BAIXO_DIR) { $env:B05_BAIXO_DIR } else { $env:TEMP }
  $cTmp = Join-Path $raizBaixo ('chamada-' + $id.Substring(0, 12))
  New-Item -ItemType Directory -Force $cTmp | Out-Null
  & icacls $cTmp /setintegritylevel '(OI)(CI)low' /Q 2>&1 | Out-Null   # pasta baixa: o executor baixo escreve out/err aqui
  $inFile = "$cTmp\in.txt"; $outFile = "$cTmp\out.txt"; $errFile = "$cTmp\err.txt"
  [System.IO.File]::WriteAllText($inFile, $entrada, $Utf8)
  $tok = [IntPtr]::Zero; $msgTok = [B05LowIL]::CriarToken([ref]$tok)
  if ($msgTok) {
    try { Razao-Gravar $dir @{ evento = 'fim'; id = $id; custo_usd = 0.0; custo_desconhecido = $false; motivo = 'falha_token_baixo'; codigo = -2 } } catch { }
    Sair-Erro "token de baixa integridade não criado: $msgTok"
  }
  $cmdline = B05LowIL-Cmdline $exe $argExec $inFile $outFile $errFile
  # E84-03: ambiente HIGIENIZADO por LISTA DE BLOQUEIO (lista branca estrita matava o Claude — achado 056). Parte do
  # ambiente completo (o Claude real precisa dele) e REMOVE: variáveis internas B05_* (o executor não sabe onde fica o
  # razão), segredos da supervisora/OpenAI/Anthropic e quaisquer *_KEY/_TOKEN/_SECRET. TEMP e a config do Claude ⇒ baixos.
  $vars = @{}
  foreach ($e in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
    $n = [string]$e.Key
    if ($n -like 'B05_*' -or $n -match '(?i)openai|anthropic|supervisora|supabase|_KEY$|_TOKEN$|_SECRET$|APIKEY|ACCESS_KEY') { continue }
    $vars[$n] = [string]$e.Value
  }
  foreach ($e in Get-ChildItem Env:B05FAKE_* -ErrorAction SilentlyContinue) { $vars[$e.Name] = $e.Value }   # só testes
  $vars['TEMP'] = $cTmp; $vars['TMP'] = $cTmp
  if ($env:B05_BAIXO_CLAUDE) { $vars['CLAUDE_CONFIG_DIR'] = $env:B05_BAIXO_CLAUDE }
  $blocoEnv = B05LowIL-BlocoAmbiente $vars
  $lpid = 0; $hProc = [IntPtr]::Zero
  try { $msgLan = [B05LowIL]::Lancar($tok, $cmdline, (Get-Location).Path, $blocoEnv, [ref]$lpid, [ref]$hProc) }
  finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($blocoEnv); [B05LowIL]::Fechar($tok) }
  if ($msgLan) {
    try { Razao-Gravar $dir @{ evento = 'fim'; id = $id; custo_usd = 0.0; custo_desconhecido = $false; motivo = 'falha_lancar_baixo'; codigo = -2 } } catch { }
    Sair-Erro "executor em baixa integridade não iniciou: $msgLan"
  }
  $criacao = [DateTime]::FromFileTimeUtc([B05LowIL]::CriacaoUtc($hProc)).ToString('o')
  $emJob = [B05LowIL]::EmJob($hProc)
  Start-Sleep -Milliseconds 150
  $nivel = [B05LowIL]::Nivel($lpid)   # 4096 = baixo
  # H10 + E84-02: pid obrigatório COM nível de integridade; sem ele, ou se o nível não for baixo, mata e mantém a reserva.
  try {
    if ($env:B05_TESTE_FALHAR_PID -eq '1') { throw 'falha de gravação injetada (teste N15)' }
    Razao-Gravar $dir @{ evento = 'pid'; id = $id; execucao = $execucao; pid = $lpid; criacao = $criacao; em_job = $emJob; nivel_il = $nivel; argumentos = @($argExec) }
  } catch {
    $msg = $_.Exception.Message; [B05LowIL]::Encerrar($hProc); [B05LowIL]::Fechar($hProc)
    Sair-Erro "falha ao gravar o pid no razão ($msg): executor encerrado, reserva mantida" 3
  }
  if ($emJob -ne $true) { [B05LowIL]::Encerrar($hProc); [B05LowIL]::Fechar($hProc); Sair-Erro "executor fora do Job Object (em_job=$emJob): encerrado, reserva mantida" 4 }
  if ($nivel -ne 4096) { [B05LowIL]::Encerrar($hProc); [B05LowIL]::Fechar($hProc); Sair-Erro "executor NÃO está em baixa integridade (nível $nivel): encerrado, reserva mantida" 5 }
  $codigo = [int][B05LowIL]::Esperar($hProc, [uint32]::MaxValue)
  [B05LowIL]::Fechar($hProc)
  $saida = [System.IO.File]::ReadAllText($outFile, $Utf8)
  $erro = if (Test-Path $errFile) { [System.IO.File]::ReadAllText($errFile, $Utf8) } else { '' }
  try { Remove-Item -Recurse -Force $cTmp -ErrorAction SilentlyContinue } catch { }
  # E84-05: antes de devolver ao controlador (que fará git e teste em nível médio), varre a árvore de trabalho por
  # reparse points/junctions que o executor baixo possa ter plantado para redirecionar uma escrita média. Qualquer um
  # ⇒ falha fechada (reserva mantida; sem 'fim'; o controlador reverte sem commit).
  $rep = B05LowIL-ReparsePoints (Get-Location).Path
  if ($env:B05_TESTE_VARREDURA_FALHA -eq '1') { $rep = @{ Ok = $false; Pontos = @() } }   # injeção p/ teste de F10
  if (-not $rep.Ok -or @($rep.Pontos).Count) {
    $motivo = if (-not $rep.Ok) { 'varredura de reparse points NÃO completou (incompleta = falha fechada)' } else { "reparse point/junction: $(@($rep.Pontos) -join '; ')" }
    try { Razao-Gravar $dir @{ evento = 'reparse_detectado'; id = $id; execucao = $execucao; ok_varredura = $rep.Ok; pontos = @($rep.Pontos) } } catch { }
    Sair-Erro "$motivo — execução abortada, reserva mantida" 6
  }
}
$custo = $null
$custoBruto = $null
$custoPresente = $false
$custoInvalido = $false
try {
  $j = $saida.Trim() | ConvertFrom-Json
  if ($j.PSObject.Properties['total_cost_usd']) {
    $custoPresente = $true
    $v = $j.total_cost_usd; $custoBruto = "$v"
    # B05-F07: só número JSON finito e não negativo vira custo conhecido. Texto, nulo, negativo ou não finito = INVÁLIDO.
    if ($v -is [double] -or $v -is [long] -or $v -is [int] -or $v -is [decimal]) {
      $d = [double]$v
      if ([double]::IsFinite($d) -and $d -ge 0) { $custo = $d } else { $custoInvalido = $true }
    } else { $custoInvalido = $true }
  }
} catch { }

# E84-01 (B05-F07-R): resposta COM campo de custo presente mas inválido NÃO pode chegar ao controlador como resultado
# normal (ele contabilizaria e comitaria antes de o lançador fechar em 28). Rejeição PRÉVIA: grava evidência bruta +
# 'fim' desconhecido (reserva mantida) + trava financeira durável, e devolve ERRO controlado (exit 28, is_error) ao
# controlador, que faz rollback sem rodar teste e sem comitar. A próxima chamada da execução já cai na trava (acima).
# (Custo AUSENTE continua sendo 'semcusto' legítimo — não é violação.)
if ($custoInvalido) {
  try { Razao-Gravar $dir @{ evento = 'fim'; id = $id; custo_usd = $null; custo_desconhecido = $true; custo_bruto = $custoBruto; custo_invalido = $true; codigo = $codigo } } catch { }
  try { Razao-Gravar $dir @{ evento = 'evidencia_bruta'; id = $id; execucao = $execucao; saida = ($saida.Substring(0, [Math]::Min(4000, $saida.Length))) } } catch { }
  try { Razao-Gravar $dir @{ evento = 'trava_financeira'; id = $id; execucao = $execucao; motivo = 'custo_invalido'; custo_bruto = $custoBruto } } catch { }
  Sair-Erro "custo inválido na resposta do executor ($custoBruto): reserva mantida, execução travada (28)" 28
}

try { Razao-Gravar $dir @{ evento = 'fim'; id = $id; custo_usd = $custo; custo_desconhecido = ($null -eq $custo); custo_bruto = $custoBruto; codigo = $codigo } } catch { }
[Console]::Out.Write($saida)
if ($erro) { [Console]::Error.Write($erro) }
exit $codigo
