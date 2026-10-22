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
$psi = [System.Diagnostics.ProcessStartInfo]::new($exe)
foreach ($a in @(if ("$($cfg.executor_prefixo)") { "$($cfg.executor_prefixo)" -split '\|' })) { $psi.ArgumentList.Add($a) }
foreach ($a in $args) { $psi.ArgumentList.Add([string]$a) }
$psi.ArgumentList.Add('--max-budget-usd'); $psi.ArgumentList.Add(([string]$teto).Replace(',', '.'))
$psi.UseShellExecute = $false; $psi.WorkingDirectory = (Get-Location).Path
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = $Utf8; $psi.StandardErrorEncoding = $Utf8
try { $p = [System.Diagnostics.Process]::Start($psi) }
catch {
  # Falha comprovadamente anterior à invocação: o processo não foi criado → custo 0 conhecido (E5).
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
# H10: o evento pid é obrigatório. Sem ele, o executor é morto (com a árvore), a reserva fica (sem 'fim') e a chamada falha.
try {
  if ($env:B05_TESTE_FALHAR_PID -eq '1') { throw 'falha de gravação injetada (teste N15)' }
  Razao-Gravar $dir @{ evento = 'pid'; id = $id; execucao = $execucao; pid = $p.Id; criacao = $criacao; em_job = $emJob; argumentos = @($psi.ArgumentList) }
} catch {
  $msg = $_.Exception.Message
  try { $p.Kill($true) } catch { }
  try { $p.WaitForExit(10000) | Out-Null } catch { }
  Sair-Erro "falha ao gravar o pid no razão ($msg): executor encerrado, reserva mantida" 3
}
# Defesa adicional: executor fora de job ⇒ não segue (o lançador também detecta e encerra tudo).
if ($IsWindows -and $emJob -ne $true) {
  try { $p.Kill($true) } catch { }
  Sair-Erro "executor fora do Job Object (em_job=$emJob): encerrado, reserva mantida" 4
}
$out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
try { $b = $Utf8.GetBytes($entrada); $p.StandardInput.BaseStream.Write($b, 0, $b.Length); $p.StandardInput.Close() } catch { }
$p.WaitForExit()
$saida = $out.Result; $erro = $err.Result; $codigo = $p.ExitCode
$custo = $null
try { $j = $saida.Trim() | ConvertFrom-Json; if ($j.PSObject.Properties['total_cost_usd'] -and $null -ne $j.total_cost_usd) { $custo = [double]$j.total_cost_usd } } catch { }
try { Razao-Gravar $dir @{ evento = 'fim'; id = $id; custo_usd = $custo; custo_desconhecido = ($null -eq $custo); codigo = $codigo } } catch { }
[Console]::Out.Write($saida)
if ($erro) { [Console]::Error.Write($erro) }
exit $codigo
