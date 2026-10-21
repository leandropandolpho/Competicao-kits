# claude-com-teto.ps1 — embrulho do executor (B-05, contrato v2). Chamado pelo controlador congelado via
# claude-com-teto.cmd, no lugar do "claude". Antes de CADA chamada: trava → reconcilia o razão → reserva
# (inicio durável) → inicia o executor com --max-budget-usd → registra pid+criação → registra fim.
# Configuração: variável B05_DIR (pasta do razão, definida pelo lançador) com config.json.
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

$dir = $env:B05_DIR
if (-not $dir -or -not (Test-Path -LiteralPath (Join-Path $dir 'config.json'))) { Sair-Erro 'B05_DIR/config.json ausente' }
$cfg = Get-Content -LiteralPath (Join-Path $dir 'config.json') -Raw -Encoding utf8 | ConvertFrom-Json
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
    Sair-Erro "orçamento insuficiente (contabilizado US$ $($c.Total) + reserva $([math]::Round($teto * (1 + $folga), 4)) > US$ $orc)"
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
try { Razao-Gravar $dir @{ evento = 'pid'; id = $id; execucao = "$($cfg.execucao)"; pid = $p.Id; criacao = $criacao; argumentos = @($psi.ArgumentList) } } catch { }
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
