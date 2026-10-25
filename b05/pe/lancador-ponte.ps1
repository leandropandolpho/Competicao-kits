# lancador-ponte.ps1 - Lancador do modo PRINCIPAL-ISOLADO (R-01 / D-1 / REQ-12). gate-pe. Ato 150.
# Resolve o achado do ChatGPT (Ato 149): nao existia procedimento definido para INICIAR o controlador no modo ponte
# ("quem invoca passa ClaudeCmd/TestCmd" era o que o harness fazia a mao). Este lancador e EXTERNO e ADITIVO: NAO toca
# controlador (7cd7864), claude-com-teto (9e6991c), supervisora (6b45dea), lancador.ps1 nem o nucleo B-05.
# Faz, ANTES de subir/retomar o controlador:
#  (a) grava a config imutavel da execucao (CreateNew + somente-leitura) com hashes_nucleo OBRIGATORIOS (R-04), o
#      TestCmd fixo (despachante), timeout_controlador_seg (R-05) e os caminhos do PU fora do repo;
#  (b) PRE-FLIGHT ANTI-ORFAO (R-01): se houver lease de execucao anterior com subarvore VIVA, NAO sobe o controlador e
#      sai 22 - impede qualquer git/rollback enquanto um PE anterior puder escrever (fail-closed). Lease morto e limpo.
#  (c) confere trava persistente (financeira 28 / seguranca 70) e o prazo (REQ-12(1)).
# So entao sobe o controlador real com -ClaudeCmd claude-ponte.cmd e -TestCmd despachante-teste.cmd.
param(
  [Parameter(Mandatory)][string]$RepoPath,
  [Parameter(Mandatory)][string]$CtrlDir,          # B05_DIR: config-<exec>.json + razao.jsonl (FORA do repo)
  [Parameter(Mandatory)][string]$EstadoDir,
  [Parameter(Mandatory)][string]$TarefasPath,
  [Parameter(Mandatory)][string]$Controlador,      # controlador.ps1 real (7cd7864)
  [Parameter(Mandatory)][string]$TesteReal,        # comando de teste real (vai para config.test_cmd_real)
  [Parameter(Mandatory)][string]$PwshPortatil,     # pwsh aprovado (B05_PWSH)
  [string]$TestPaths = 'teste-marker.txt',
  [int]$TimeoutControladorSeg = 180,
  [int]$TimeoutPonteSeg = 60,
  [int]$MaxTentativas = 1,
  [double]$Teto = 0.5, [double]$Folga = 0.25, [double]$Orcamento = 100,
  [string]$ExecId,
  # Executor real: parametrizado (nao embutido). Default = fake-executor para a BATERIA V1; a operacao real passaria o
  # claude (BLOQUEADA ate decisao de provisionamento). Mantem o lancador generico, sem assumir o fake como operacional.
  [string]$Executor,
  [string]$ExecutorPrefixo
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$Utf8 = [System.Text.UTF8Encoding]::new($false)
$raizPe = $PSScriptRoot
$pontecmd = Join-Path $raizPe 'claude-ponte.cmd'
$despcmd  = Join-Path $raizPe 'despachante-teste.cmd'
$acao     = Join-Path $raizPe 'acao-pe.ps1'

# Pastas do PU FORA do repo (irmas do CtrlDir)
$ponte = Join-Path $CtrlDir 'ponte'; $evid = Join-Path $CtrlDir 'evid'; $trava = Join-Path $CtrlDir 'trava'
New-Item -ItemType Directory -Force $CtrlDir,$EstadoDir,$ponte,$evid,$trava | Out-Null

# --- C4-F02 (Ato 153, ChatGPT+Perplexity): GATE do binario pwsh aprovado no proprio lancador, ANTES de qualquer
# despacho. Hoje o lancador recebia PwshPortatil e so calculava o SHA; agora EXIGE caminho canonico + SHA aprovado e
# RECUSA execucao MSIX (WindowsApps = Job de app-container). A restricao deixa de valer so no runner de testes.
$PWSH_SHA_APROVADO = 'FA2C8BB1E35CDD62AD15CD06A1D8F2C5961E9725A9BFA1E7CFD2C322F49E9619'
if (-not (Test-Path -LiteralPath $PwshPortatil)) { [Console]::Error.Write("C4-F02: pwsh aprovado inexistente: $PwshPortatil"); exit 31 }
if ("$PwshPortatil" -like '*\WindowsApps\*') { [Console]::Error.Write("C4-F02: pwsh MSIX (WindowsApps) recusado: $PwshPortatil"); exit 31 }
$shaPwshReal = (Get-FileHash -LiteralPath $PwshPortatil -Algorithm SHA256).Hash.ToUpper()
if ($shaPwshReal -ne $PWSH_SHA_APROVADO) { [Console]::Error.Write("C4-F02: SHA do pwsh diverge do aprovado (real=$shaPwshReal)"); exit 31 }

# --- C4-F03 (Ato 153): ANCORA DE CONFIANCA. Os hashes do nucleo NAO sao apenas calculados dos arquivos do runtime: sao
# conferidos contra um MANIFESTO APROVADO e protegido (hashes-nucleo-aprovado.json). Se a origem foi adulterada antes do
# calculo, o runtime nao baterá com o manifesto aprovado => FATAL (97). A config passa a carregar os valores APROVADOS.
$mapaNucleo = [ordered]@{ 'ponte-pu.ps1'=(Join-Path $raizPe 'ponte-pu.ps1'); 'acao-pe.ps1'=$acao
  'b05job.ps1'=(Join-Path $raizPe '..\b05job.ps1'); 'baixa-integridade.ps1'=(Join-Path $raizPe '..\baixa-integridade.ps1')
  'razao.ps1'=(Join-Path $raizPe '..\razao.ps1') }
$manifestoAprov = if ($env:B05_MANIFESTO_NUCLEO) { $env:B05_MANIFESTO_NUCLEO } else { Join-Path $raizPe 'hashes-nucleo-aprovado.json' }
if (-not (Test-Path -LiteralPath $manifestoAprov)) { [Console]::Error.Write("C4-F03: manifesto aprovado ausente: $manifestoAprov"); exit 97 }
try { $aprov = Get-Content -LiteralPath $manifestoAprov -Raw -Encoding utf8 | ConvertFrom-Json } catch { [Console]::Error.Write("C4-F03: manifesto aprovado ilegivel"); exit 97 }
$hashes = [ordered]@{}
foreach ($k in $mapaNucleo.Keys) {
  if (-not $aprov.PSObject.Properties[$k]) { [Console]::Error.Write("C4-F03: manifesto aprovado nao cobre $k"); exit 97 }
  $esp = "$($aprov.$k)".ToUpper()
  $real = (Get-FileHash -LiteralPath $mapaNucleo[$k] -Algorithm SHA256).Hash.ToUpper()
  if ($real -ne $esp) { [Console]::Error.Write("C4-F03: nucleo $k diverge do manifesto aprovado (real=$real)"); exit 97 }
  $hashes[$k] = $esp
}

# REQ-12(1)/R-05: o prazo da ponte + margem precisa caber no TimeoutSec do controlador.
if (($TimeoutPonteSeg + 35) -gt $TimeoutControladorSeg) { [Console]::Error.Write("R-05: TimeoutPonteSeg($TimeoutPonteSeg)+35 > TimeoutControladorSeg($TimeoutControladorSeg)"); exit 29 }

if (-not $ExecId) { $ExecId = [guid]::NewGuid().ToString('N') }
$execBin = if ($Executor) { $Executor } else { $PwshPortatil }
$execPref = if ($ExecutorPrefixo) { $ExecutorPrefixo } else { "-NoProfile|-File|$(Join-Path $raizPe '..\testes\fake-executor.ps1')" }
$cfg = [ordered]@{ execucao=$ExecId; teto_chamada_usd=$Teto; folga=$Folga; orcamento_usd=$Orcamento
  executor=$execBin; executor_prefixo=$execPref
  test_cmd_real=$TesteReal; ponte_dir=$ponte; acao_pe=$acao; pwsh_aprovado=$PwshPortatil
  pwsh_sha256=(Get-FileHash -LiteralPath $PwshPortatil -Algorithm SHA256).Hash
  trava_dir=$trava; evidencia_dir=$evid; timeout_ponte_seg=$TimeoutPonteSeg; timeout_controlador_seg=$TimeoutControladorSeg
  hashes_nucleo=$hashes }
$arqCfg = Join-Path $CtrlDir "config-$ExecId.json"
# Config imutavel: CreateNew (recusa sobrescrita) + somente-leitura.
$fsCfg = [System.IO.FileStream]::new($arqCfg, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
try { $b = $Utf8.GetBytes(($cfg | ConvertTo-Json -Depth 8)); $fsCfg.Write($b,0,$b.Length) } finally { $fsCfg.Dispose() }
Set-ItemProperty -LiteralPath $arqCfg -Name IsReadOnly -Value $true

# Nucleo (ja hasheado acima; confiavel) para o PRE-FLIGHT anti-orfao.
. (Join-Path $raizPe 'ponte-pu.ps1')

# (c) trava persistente primeiro (fail-closed). Preserva a semantica D-06: financeira=>28, seguranca=>70, senao 26.
$tv = PU-Trava-Ativa $trava
if ($tv.Ativa) {
  $codTrava = switch ("$($tv.Tipo)") { 'financeira' { 28 } 'seguranca' { 70 } default { 26 } }
  [Console]::Error.Write("lancador: trava persistente ativa ($($tv.Tipo)) - nao sobe (exit $codTrava). $($tv.Detalhe)"); exit $codTrava
}

# (b) R-01: PRE-FLIGHT ANTI-ORFAO antes de subir/retomar. Lease de subarvore VIVA => NAO sobe (22). Lease morto => limpa.
if (Test-Path -LiteralPath $trava) {
  try { $leases = @(Get-ChildItem -LiteralPath $trava -Filter '*.lease' -ErrorAction Stop) }
  catch { [Console]::Error.Write("R-01: listagem de leases falhou (fail-closed): $($_.Exception.Message)"); exit 22 }
  foreach ($lf in $leases) {
    try { $ls = Get-Content -LiteralPath $lf.FullName -Raw | ConvertFrom-Json } catch { [Console]::Error.Write("R-01: lease ilegivel ($($lf.Name)) - fail-closed"); exit 22 }
    $m = PU-Subarvore-Morta ([uint32]$ls.pid) ([long]$ls.criacao)
    if (-not $m.Morta) { [Console]::Error.Write("R-01: execucao anterior VIVA (lease $($ls.exec_id)): $([string]::Join('; ',$m.Vivos)) - lancador NAO sobe o controlador, sem git/rollback"); exit 22 }
    Remove-Item -LiteralPath $lf.FullName -Force -ErrorAction SilentlyContinue   # morto: limpo com seguranca
  }
}

# So agora sobe o controlador real. A ponte e escolhida pelos parametros ClaudeCmd/TestCmd (externo; nada congelado muda).
$psi = [System.Diagnostics.ProcessStartInfo]::new($PwshPortatil)
foreach ($a in @('-NoProfile','-ExecutionPolicy','Bypass','-File',$Controlador,
    '-RepoPath',$RepoPath,'-TarefasPath',$TarefasPath,'-EstadoDir',$EstadoDir,
    '-TestCmd',("& `"$despcmd`""),'-TestPaths',$TestPaths,'-ClaudeCmd',$pontecmd,
    '-TimeoutSec',[string]$TimeoutControladorSeg,'-MaxTentativas',[string]$MaxTentativas,'-MaxCustoUsd','100')) { $psi.ArgumentList.Add($a) }
$psi.UseShellExecute = $false; $psi.WorkingDirectory = $RepoPath
$psi.Environment['B05_PWSH'] = $PwshPortatil; $psi.Environment['B05_DIR'] = $CtrlDir; $psi.Environment['B05_EXECUCAO'] = $ExecId
$psi.Environment['PATH'] = (Split-Path $PwshPortatil) + ';' + $psi.Environment['PATH']
$p = [System.Diagnostics.Process]::Start($psi); $p.WaitForExit()
$cod = $p.ExitCode
# C-02: ao fim, deixa explicita qualquer trava remanescente.
$tv2 = PU-Trava-Ativa $trava
if ($tv2.Ativa) { [Console]::Error.Write("lancador: TRAVA $($tv2.Tipo.ToUpper()) remanescente - $($tv2.Detalhe)") }
exit $cod
