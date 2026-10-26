# gate-lowil.ps1 - spike de confirmacao do C6-real (C4-F01, Ato 165). gate-pe.
# Pergunta: um executor LOW-IL criado por TOKEN (CreateProcessAsUser, como o acao-pe faz) HERDA o JobLancadorPonte
# (Job de supervisao do launcher) como o filho COMUM herdou no gate-jobtopo? Se NAO, a verificacao continua (G5) do
# meu G1 o ve FORA do Job e derruba a arvore -> explica as 2 falhas do C6-real (lease vivo nao detectado).
# ADITIVO: dot-sourca b05job.ps1 + baixa-integridade.ps1 CONGELADOS e usa as primitivas REAIS. Nao toca congelados.
$ErrorActionPreference='Continue'; Set-StrictMode -Version 3.0
[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false); $Utf8=[System.Text.UTF8Encoding]::new($false)
$base=$PSScriptRoot; $pe=Split-Path $base; $nucDir=Split-Path $pe
$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'); $out=Join-Path $pe "gate-lowil-$stamp.txt"
$L=New-Object System.Collections.Generic.List[string]
function Linha($s){ $L.Add([string]$s); Write-Host $s }
function Salvar(){ [IO.File]::WriteAllText($out,($L -join "`r`n"),$Utf8); Write-Host "RESULTADO: $out" }
Linha "=== GATE LOW-IL (C4-F01 / C6-real) - $stamp UTC ==="
$pwsh=(Get-Process -Id $PID).Path
$shaOk='FA2C8BB1E35CDD62AD15CD06A1D8F2C5961E9725A9BFA1E7CFD2C322F49E9619'
$sha=try{(Get-FileHash -LiteralPath $pwsh -Algorithm SHA256).Hash.ToUpper()}catch{'ERRO'}
Linha "pwsh: $pwsh  msix=$($pwsh -like '*\WindowsApps\*')  sha_ok=$($sha -eq $shaOk)"
if (($pwsh -like '*\WindowsApps\*') -or $sha -ne $shaOk -or -not $IsWindows) { Linha 'FATAL: pwsh nao aprovado ou nao-Windows'; Salvar; exit 3 }
. (Join-Path $nucDir 'b05job.ps1')
. (Join-Path $nucDir 'baixa-integridade.ps1')
$falhas=0
function Checar([string]$id,[bool]$ok,[string]$d){ if($ok){Linha "[OK]   $id - $d"}else{Linha "[FALHA] $id - $d"; $script:falhas++} }

$sup=[IntPtr]::Zero; $jpe=[IntPtr]::Zero; $tok=[IntPtr]::Zero; $hP=[IntPtr]::Zero; $hT=[IntPtr]::Zero
try {
  # 1) Job de supervisao + self-assign (o spike faz o papel do acao-pe, ja dentro do JobLancadorPonte).
  $sup=[B05Job]::CreateJobObject([IntPtr]::Zero,$null)
  [void][B05Job]::Configurar($sup,[B05Job]::KILL_ON_JOB_CLOSE)
  $eu=[B05Job]::GetCurrentProcess()
  Checar 'SUP-self-assign' ([B05Job]::AssignProcessToJobObject($sup,$eu)) 'spike associado ao JobLancadorPonte (faz o papel do acao-pe)'
  $dsup=$false; [void][B05Job]::IsProcessInJob($eu,$sup,[ref]$dsup); Checar 'SUP-em-job' $dsup 'spike em_job=True'

  # 2) Launch LOW-IL por TOKEN (identico ao acao-pe): CriarToken + LancarSuspenso.
  $cTmp=Join-Path ([IO.Path]::GetTempPath()) "lowil-$stamp"; New-Item -ItemType Directory -Force $cTmp | Out-Null
  $inF="$cTmp\in.txt"; $outF="$cTmp\out.txt"; $errF="$cTmp\err.txt"; [IO.File]::WriteAllText($inF,'',$Utf8)
  & icacls $cTmp /setintegritylevel '(OI)(CI)low' /Q 2>&1 | Out-Null
  $mt=[B05LowIL]::CriarToken([ref]$tok); Checar 'LOWIL-token' ($mt -eq '' -and $tok -ne [IntPtr]::Zero) "CriarToken ('$mt')"
  $cmd=B05LowIL-Cmdline $pwsh @('-NoProfile','-NoLogo','-Command','Start-Sleep -Seconds 8') $inF $outF $errF
  $lpid=0
  $ml=[B05LowIL]::LancarSuspenso($tok,$cmd,$cTmp,[IntPtr]::Zero,[ref]$lpid,[ref]$hP,[ref]$hT)
  Checar 'LOWIL-suspenso' ($ml -eq '' -and $lpid -ne 0) "LancarSuspenso pid=$lpid ('$ml')"

  # 3) *** PERGUNTA CENTRAL *** antes de qualquer JobPE: o filho low-IL por token HERDOU o JobLancadorPonte?
  $noSupAntes=[B05LowIL]::EmJob($hP)   # EmJob(h) = IsProcessInJob(h, NULL) -> esta em ALGUM job (o do pai, herdado)
  $noSupExpl=$false; [void][B05Job]::IsProcessInJob($hP,$sup,[ref]$noSupExpl)
  Checar 'LOWIL-herdou-supervisor' $noSupExpl "IsProcessInJob(low-IL, JobLancadorPonte)=$noSupExpl (em algum job=$noSupAntes) <-- PERGUNTA CENTRAL do C6-real"

  # 4) acao-pe: JobPE com RestringirUI + associa o filho (como PE-F07/08).
  $jpe=[B05Job]::CreateJobObject([IntPtr]::Zero,$null)
  [void][B05Job]::Configurar($jpe,[B05Job]::KILL_ON_JOB_CLOSE); [void][B05Job]::RestringirUI($jpe)
  $assocPe=[B05Job]::AssignProcessToJobObject($jpe,$hP); $w=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
  Checar 'LOWIL-assoc-jpe' $assocPe "AssignProcessToJobObject(JobPE, low-IL)=$assocPe err=$w"
  $noJpe=$false; [void][B05Job]::IsProcessInJob($hP,$jpe,[ref]$noJpe); Checar 'LOWIL-no-jpe' $noJpe "no JobPE=$noJpe"
  $noSupDepois=$false; [void][B05Job]::IsProcessInJob($hP,$sup,[ref]$noSupDepois)
  Checar 'LOWIL-supervisor-depois' $noSupDepois "no JobLancadorPonte apos JobPE=$noSupDepois (nested: deveria seguir nos dois)"

  # 5) Retomar e ver se a verificacao continua do supervisor o FLAGRA como externo (a causa suspeita do C6-real).
  [void][B05LowIL]::Retomar($hT)
  [B05Job]::Rastrear([uint32]$PID); Start-Sleep -Milliseconds 400
  $viol=[B05Job]::Verificar($sup)
  $flagrado = @($viol | Where-Object { $_ -like "$lpid|*" }).Count -gt 0
  Checar 'LOWIL-nao-flagrado-por-Verificar' (-not $flagrado) ("Verificar(supervisor) violacoes=$($viol.Count) flagra_o_executor=$flagrado")
} catch { Linha "[FALHA] excecao: $($_.Exception.Message)"; $falhas++ }
finally {
  if ($hP -ne [IntPtr]::Zero) { [B05LowIL]::Encerrar($hP); [B05LowIL]::Fechar($hP) }
  if ($hT -ne [IntPtr]::Zero) { [B05LowIL]::Fechar($hT) }
  if ($tok -ne [IntPtr]::Zero) { [B05LowIL]::Fechar($tok) }
  if ($jpe -ne [IntPtr]::Zero) { [void][B05Job]::TerminateJobObject($jpe,0); [void][B05Job]::CloseHandle($jpe) }
}
Linha ''
Linha ("TOTAL GATE LOW-IL: {0} - {1}" -f $(if($falhas -eq 0){'TODAS VERDES'}else{"$falhas FALHA(S)"}),$stamp)
Linha 'LEITURA:'
Linha '  LOWIL-herdou-supervisor OK  -> executor herda o Job; a causa do C6-real e OUTRA (tracking/timing).'
Linha '  LOWIL-herdou-supervisor FALHA -> token nao herda o Job de supervisao; G5 o flagra -> confirma a hipotese (vai a mesa).'
Salvar
exit ([int]($falhas -ne 0))
