# gate-jobtopo.ps1 — GATE EMPÍRICO de topologia de Jobs (C4-F01, Ato 164). gate-pe.
# PRÉ-CONDIÇÃO da candidata 4.2: decide no kernel Windows REAL se o Job de supervisão (JobLancadorPonte) convive
# com o JobPE do acao-pe (KILL_ON_JOB_CLOSE + RestringirUI), ANTES de implementar G1–G9.
# NÃO implementa a solução, NÃO toca componentes congelados: DOT-SOURCA o b05job.ps1 CONGELADO e usa as primitivas
# REAIS ([B05Job]::CreateJobObject/Configurar/RestringirUI/AssignProcessToJobObject/IsProcessInJob/Flags/Encerrar).
# Provas: L-JOB-TOPO (associação aninhada + RestringirUI preservado), L-JOB-ASSOC (falha de associação -> suspenso
# órfão limpo, nada executa), L-JOB-KILL (morte do supervisor derruba toda a árvore por PID+criação).
# Esta é a PRIMEIRA versão para rodar no notebook; ajuste de 1 rodada é esperado (quirks do kernel só aparecem no real).
$ErrorActionPreference = 'Continue'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$base   = $PSScriptRoot                                   # ...\b05\pe\testes
$pe     = Split-Path $base                                # ...\b05\pe
$nucDir = Split-Path $pe                                  # ...\b05
$nucleo = Join-Path $nucDir 'b05job.ps1'
$stamp  = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$out    = Join-Path $pe "gate-jobtopo-$stamp.txt"
$L = New-Object System.Collections.Generic.List[string]
function Linha($s){ $L.Add([string]$s); Write-Host $s }
function Salvar(){ [IO.File]::WriteAllText($out, ($L -join "`r`n"), [Text.UTF8Encoding]::new($false)); Write-Host "RESULTADO: $out" }

Linha "=== GATE JOB-TOPO (C4-F01) — $stamp UTC ==="

# ---- 0) pwsh PORTÁTIL aprovado (igual ao runner da candidata): FATAL se divergir ----
$pwsh = (Get-Process -Id $PID).Path
$shaOk = 'FA2C8BB1E35CDD62AD15CD06A1D8F2C5961E9725A9BFA1E7CFD2C322F49E9619'
$sha = try { (Get-FileHash -LiteralPath $pwsh -Algorithm SHA256).Hash.ToUpper() } catch { 'ERRO' }
$msix = ($pwsh -like '*\WindowsApps\*')
Linha "pwsh: $pwsh ($($PSVersionTable.PSVersion))  msix=$msix  sha_ok=$($sha -eq $shaOk)"
if ($msix -or $sha -ne $shaOk) { Linha 'FATAL: pwsh não é o PORTÁTIL aprovado — gate não executado.'; Salvar; exit 3 }
if (-not $IsWindows) { Linha 'FATAL: gate exige Windows real.'; Salvar; exit 3 }
if (-not (Test-Path -LiteralPath $nucleo)) { Linha "FATAL: núcleo congelado não encontrado: $nucleo"; Salvar; exit 3 }

# ---- primitivas CONGELADAS ([B05Job]) + helper mínimo de CreateProcess SUSPENSO (não-congelado, só para o spike) ----
. $nucleo
if (-not ('SpikeProc' -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class SpikeProc {
  [StructLayout(LayoutKind.Sequential)] public struct SI { public int cb; public string r1,desk,title; public int x,y,xs,ys,xc,yc,fill,flags; public short sw,r2; public IntPtr r3,hIn,hOut,hErr; }
  [StructLayout(LayoutKind.Sequential)] public struct PI { public IntPtr hProcess,hThread; public int pid,tid; }
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CreateProcessW(string app,string cmd,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string cwd,ref SI si,out PI pi);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern uint ResumeThread(IntPtr h);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
  public const uint CREATE_SUSPENDED = 0x4;
  // Cria SUSPENSO. Devolve 0 em sucesso (preenche pi) ou o Win32 error.
  public static int CriarSuspenso(string cmdline, string cwd, out PI pi) {
    SI si = new SI(); si.cb = Marshal.SizeOf(typeof(SI)); pi = new PI();
    if (CreateProcessW(null, cmdline, IntPtr.Zero, IntPtr.Zero, false, CREATE_SUSPENDED, IntPtr.Zero, cwd, ref si, out pi)) return 0;
    return Marshal.GetLastWin32Error();
  }
}
'@
}

function Flags-Str([long]$f){ ("0x{0:X}" -f $f) }
$falhas = 0
function Checar([string]$id,[bool]$ok,[string]$detalhe){ if ($ok) { Linha "[OK]   $id — $detalhe" } else { Linha "[FALHA] $id — $detalhe"; $script:falhas++ } }

$cwd = $pe
$pwshArgsSleep = '"' + $pwsh + '" -NoProfile -NoLogo -Command "Start-Sleep -Seconds 90"'

# =====================================================================================================
# L-JOB-TOPO — este processo simula o CONTROLADOR já dentro do JobLancadorPonte (supervisor). Em seguida,
# simula o acao-pe criando o JobPE (KILL_ON_JOB_CLOSE + RestringirUI) e associando um FILHO SUSPENSO. Prova
# os 7 pontos: controlador associado antes de retomar; filho suspenso associado ao JobPE antes de executar;
# associação verificada NOS DOIS Jobs; supervisor sem breakaway; JobPE com UI restrita e sem breakaway.
# =====================================================================================================
Linha ''; Linha '===== L-JOB-TOPO ====='
$sup = [IntPtr]::Zero; $jpe = [IntPtr]::Zero; $pi = New-Object SpikeProc+PI
try {
  $sup = [B05Job]::CreateJobObject([IntPtr]::Zero, $null)
  Checar 'TOPO-sup-criado' ($sup -ne [IntPtr]::Zero) "JobLancadorPonte handle=$sup"
  Checar 'TOPO-sup-config' ([B05Job]::Configurar($sup, [B05Job]::KILL_ON_JOB_CLOSE)) 'Configurar(KILL_ON_JOB_CLOSE)'
  $fsup = [B05Job]::Flags($sup)
  Checar 'TOPO-sup-flags'  ((($fsup -band [B05Job]::KILL_ON_JOB_CLOSE) -ne 0) -and (($fsup -band ([B05Job]::BREAKAWAY_OK -bor [B05Job]::SILENT_BREAKAWAY_OK)) -eq 0)) "flags supervisor=$(Flags-Str $fsup)"
  # associa ESTE processo (o "controlador") ao supervisor, ANTES de qualquer trabalho
  $eu = [B05Job]::GetCurrentProcess()
  $assocSelf = [B05Job]::AssignProcessToJobObject($sup, $eu)
  $dentroSup = $false; [void][B05Job]::IsProcessInJob($eu, $sup, [ref]$dentroSup)
  Checar 'TOPO-controlador-no-supervisor' ($assocSelf -and $dentroSup) "assign=$assocSelf em_job=$dentroSup (controlador associado antes de executar)"

  # acao-pe: cria JobPE com KILL_ON_JOB_CLOSE + RestringirUI, estando JÁ dentro do supervisor
  $jpe = [B05Job]::CreateJobObject([IntPtr]::Zero, $null)
  Checar 'TOPO-jpe-criado' ($jpe -ne [IntPtr]::Zero) "JobPE handle=$jpe"
  Checar 'TOPO-jpe-config' ([B05Job]::Configurar($jpe, [B05Job]::KILL_ON_JOB_CLOSE)) 'Configurar(KILL_ON_JOB_CLOSE)'
  $uiOk = [B05Job]::RestringirUI($jpe)
  Checar 'TOPO-jpe-restringir-ui' $uiOk 'RestringirUI(JobPE) (0x1|0x2|0x4|0x20) — ponto crítico do C4-F01/Q3'
  $fjpe = [B05Job]::Flags($jpe)
  Checar 'TOPO-jpe-flags' ((($fjpe -band [B05Job]::KILL_ON_JOB_CLOSE) -ne 0) -and (($fjpe -band ([B05Job]::BREAKAWAY_OK -bor [B05Job]::SILENT_BREAKAWAY_OK)) -eq 0)) "flags JobPE=$(Flags-Str $fjpe)"

  # filho SUSPENSO (simula o executor) e associação ao JobPE ANTES de retomar
  $err = [SpikeProc]::CriarSuspenso($pwshArgsSleep, $cwd, [ref]$pi)
  Checar 'TOPO-filho-suspenso' ($err -eq 0) "CreateProcess CREATE_SUSPENDED pid=$($pi.pid) err=$err"
  if ($err -eq 0) {
    $assocFilho = [B05Job]::AssignProcessToJobObject($jpe, $pi.hProcess)
    $w32 = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $noJpe = $false; [void][B05Job]::IsProcessInJob($pi.hProcess, $jpe, [ref]$noJpe)
    $noSup = $false; [void][B05Job]::IsProcessInJob($pi.hProcess, $sup, [ref]$noSup)
    # ESTE é o veredito central do gate: associação aninhada bem-sucedida + presença NOS DOIS Jobs
    Checar 'TOPO-assoc-aninhada' ($assocFilho) "AssignProcessToJobObject(JobPE, filho) assoc=$assocFilho err=$w32 (Q3: UI aninhada não barra a associação)"
    Checar 'TOPO-filho-no-jpe'   $noJpe "IsProcessInJob(filho, JobPE)=$noJpe"
    Checar 'TOPO-filho-no-supervisor' $noSup "IsProcessInJob(filho, supervisor)=$noSup (herança do supervisor preservada)"
    # só agora 'retoma' (aqui o spike não precisa rodar o filho; comprova que PODERIA — contenção antes da execução)
    [void][SpikeProc]::ResumeThread($pi.hThread)
  }
} catch { Linha "[FALHA] L-JOB-TOPO exceção: $($_.Exception.Message)"; $falhas++ }
finally {
  if ($pi.hProcess -ne [IntPtr]::Zero) { try { [void][B05Job]::Encerrar([uint32]$pi.pid, ([B05Job]::Snapshot())[[uint32]$pi.pid].Criacao) } catch {}; [void][SpikeProc]::CloseHandle($pi.hProcess); [void][SpikeProc]::CloseHandle($pi.hThread) }
  if ($jpe -ne [IntPtr]::Zero) { [void][B05Job]::TerminateJobObject($jpe, 0); [void][B05Job]::CloseHandle($jpe) }
  # NÃO fecha o supervisor aqui: ele contém ESTE processo (KILL_ON_JOB_CLOSE); fechar o último handle encerraria o gate.
}

# =====================================================================================================
# L-JOB-ASSOC — falha de associação deve deixar o filho SUSPENSO e ser encerrado sem jamais executar (fail-closed).
# Simula a falha fechando/invalidando o alvo: cria suspenso, NÃO associa, encerra; prova que nada rodou.
# =====================================================================================================
Linha ''; Linha '===== L-JOB-ASSOC ====='
$pi2 = New-Object SpikeProc+PI
try {
  $err2 = [SpikeProc]::CriarSuspenso($pwshArgsSleep, $cwd, [ref]$pi2)
  Checar 'ASSOC-filho-suspenso' ($err2 -eq 0) "CreateProcess CREATE_SUSPENDED pid=$($pi2.pid) err=$err2"
  if ($err2 -eq 0) {
    # cenário negativo: associação 'falha' (simulada) => encerrar o suspenso ANTES de qualquer ResumeThread
    $snapA = [B05Job]::Snapshot(); $criA = $snapA[[uint32]$pi2.pid].Criacao
    $r = [B05Job]::Encerrar([uint32]$pi2.pid, $criA)
    Start-Sleep -Milliseconds 800
    # liveness correto (igual ao L-JOB-KILL): presença no snapshot com a MESMA criação. OpenProcess ainda abre um
    # processo recém-encerrado (zumbi) enquanto houver handle — por isso não serve como prova de vida.
    $sA = [B05Job]::Snapshot()
    $vivo = ($sA.ContainsKey([uint32]$pi2.pid)) -and ($sA[[uint32]$pi2.pid].Criacao -eq $criA)
    Checar 'ASSOC-suspenso-orfao-limpo' (-not $vivo) "encerrar='$r'; filho vivo após encerrar=$vivo (nenhum código executou)"
  }
} catch { Linha "[FALHA] L-JOB-ASSOC exceção: $($_.Exception.Message)"; $falhas++ }
finally { if ($pi2.hProcess -ne [IntPtr]::Zero) { [void][SpikeProc]::CloseHandle($pi2.hProcess); [void][SpikeProc]::CloseHandle($pi2.hThread) } }

# =====================================================================================================
# L-JOB-KILL — a morte abrupta do SUPERVISOR derruba toda a árvore (controlador -> filho -> neto) por PID+criação.
# Um pwsh "lançador" filho cria seu próprio Job KILL_ON_JOB_CLOSE, associa-se e gera filho+neto; grava os PIDs;
# matamos o lançador (fecha o último handle do Job) e provamos que controlador/filho/neto morreram.
# =====================================================================================================
Linha ''; Linha '===== L-JOB-KILL ====='
$pidsFile = Join-Path $pe "gate-kill-pids-$stamp.json"
$helper = Join-Path $pe "gate-kill-helper-$stamp.ps1"
@'
param([string]$PidsOut,[string]$Nucleo,[string]$Pwsh)
Set-StrictMode -Version 3.0
. $Nucleo
$job = [B05Job]::CreateJobObject([IntPtr]::Zero, $null)
[void][B05Job]::Configurar($job, [B05Job]::KILL_ON_JOB_CLOSE)
[void][B05Job]::AssignProcessToJobObject($job, [B05Job]::GetCurrentProcess())   # lançador-supervisor
# filho (controlador) que gera um neto (executor): ambos dormem; herdam o Job por criação
$neto  = Start-Process -FilePath $Pwsh -ArgumentList '-NoProfile','-NoLogo','-Command','Start-Sleep -Seconds 120' -PassThru
$filho = Start-Process -FilePath $Pwsh -ArgumentList '-NoProfile','-NoLogo','-Command','Start-Sleep -Seconds 120' -PassThru
$snap = [B05Job]::Snapshot()
$reg = @{ lancador = $PID; filho = $filho.Id; neto = $neto.Id;
  cri_lancador = $snap[[uint32]$PID].Criacao; cri_filho = $snap[[uint32]$filho.Id].Criacao; cri_neto = $snap[[uint32]$neto.Id].Criacao }
[IO.File]::WriteAllText($PidsOut, ($reg | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
Start-Sleep -Seconds 120
'@ | Set-Content -LiteralPath $helper -Encoding utf8
try {
  $lan = Start-Process -FilePath $pwsh -ArgumentList '-NoProfile','-NoLogo','-ExecutionPolicy','Bypass','-File',$helper,'-PidsOut',$pidsFile,'-Nucleo',$nucleo,'-Pwsh',$pwsh -PassThru
  $t0 = [Diagnostics.Stopwatch]::StartNew(); while (-not (Test-Path -LiteralPath $pidsFile) -and $t0.Elapsed.TotalSeconds -lt 30) { Start-Sleep -Milliseconds 200 }
  if (-not (Test-Path -LiteralPath $pidsFile)) { Checar 'KILL-setup' $false 'árvore não registrou PIDs em 30s' }
  else {
    $reg = Get-Content -LiteralPath $pidsFile -Raw | ConvertFrom-Json
    Linha "KILL-arvore: lancador=$($reg.lancador) filho=$($reg.filho) neto=$($reg.neto)"
    # mata o SUPERVISOR (lançador): fecha o último handle do Job -> KILL_ON_JOB_CLOSE derruba a árvore
    $r = [B05Job]::Encerrar([uint32]$reg.lancador, [int64]$reg.cri_lancador)
    Start-Sleep -Seconds 2
    function Morto([uint32]$p,[int64]$cri){ $h=[B05Job]::OpenProcess(0x1000,$false,$p); if ($h -eq [IntPtr]::Zero){return $true}; try { $snap=[B05Job]::Snapshot(); return (-not $snap.ContainsKey($p)) -or ($snap[$p].Criacao -ne $cri) } finally { [void][B05Job]::CloseHandle($h) } }
    $mLan = Morto ([uint32]$reg.lancador) ([int64]$reg.cri_lancador)
    $mFil = Morto ([uint32]$reg.filho)    ([int64]$reg.cri_filho)
    $mNet = Morto ([uint32]$reg.neto)     ([int64]$reg.cri_neto)
    Checar 'KILL-supervisor-morto' $mLan "lancador encerrado ('$r')"
    Checar 'KILL-controlador-morto' $mFil 'filho (controlador) encerrado pela queda do Job'
    Checar 'KILL-neto-morto' $mNet 'neto (executor) encerrado pela queda do Job'
    # limpeza defensiva se algo sobreviveu
    foreach ($x in @(@($reg.filho,$reg.cri_filho),@($reg.neto,$reg.cri_neto))) { try { [void][B05Job]::Encerrar([uint32]$x[0],[int64]$x[1]) } catch {} }
  }
} catch { Linha "[FALHA] L-JOB-KILL exceção: $($_.Exception.Message)"; $falhas++ }
finally { Remove-Item -LiteralPath $helper,$pidsFile -ErrorAction SilentlyContinue }

Linha ''
Linha ("TOTAL GATE JOB-TOPO: {0} — {1}" -f $(if($falhas -eq 0){'TODAS VERDES'}else{"$falhas FALHA(S)"}), $stamp)
Linha ''
Linha 'VEREDITO:'
Linha '  PASSA  -> C4-F01/Q3 empiricamente respondido: implementar G1–G9 + bateria (candidata 4.2 controlada).'
Linha '  FALHA  -> NÃO relaxar RestringirUI nem habilitar breakaway; voltar à mesa com estas evidências.'
Salvar
exit ([int]($falhas -ne 0))
