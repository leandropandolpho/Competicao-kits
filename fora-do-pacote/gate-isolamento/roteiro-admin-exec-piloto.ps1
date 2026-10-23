<#
  ROTEIRO ADMINISTRATIVO — exec-piloto (GATE ISOLAMENTO DE PRINCIPAL)
  Ato - Autonomous multi-LLM orchestration flow - 112  ·  base: contrato v0.2 + Adendo A111

  ATENCAO / LEIA ANTES DE RODAR:
  - Preparado pelo AUDITOR_BASE_CLAUDE para VOCE (Leandro) executar UMA VEZ, como ADMINISTRADOR, no notebook.
  - O AUDITOR NAO executou nada disto. Revise linha a linha antes de rodar.
  - Cria o usuario PE (exec-piloto), a pasta de trabalho com ACL, a tarefa agendada com DACL
    (flag 0x10), nega logon interativo via secedit e prepara CLAUDE_CONFIG_DIR de baixa integridade.
  - NAO coloca chave de API aqui. A chave dedicada e o workspace Anthropic com teto mensal sao
    criados por VOCE no provedor (decisao financeira: o executor passa a ser cobrado por uso de API,
    separado da assinatura Max). Deixe a chave num arquivo com ACL so-PE, fora da arvore editavel.
  - Nada aqui libera execucao desassistida. R1, B-07 e aprovacao humana continuam valendo.
  - Idempotente onde possivel; rode em PowerShell ELEVADO (Run as administrator).
#>
[CmdletBinding()]
param(
  [string]$PE = 'exec-piloto',
  [string]$WorkRoot = 'C:\piloto-work',
  [string]$ConfigDir = 'C:\piloto-pe\cfg',     # CLAUDE_CONFIG_DIR do PE (baixa integridade) — A111-04
  [string]$CredDir   = 'C:\piloto-pe\cred',    # pasta da chave do PE, ACL so-PE — A111-04/06
  [string]$TaskName  = 'ExecPiloto_Executor',
  [string]$AcaoScript= 'C:\piloto-ctrl\acao-pe.ps1'  # script da acao (pasta do PU; PE so RX) — A111-01
)
$ErrorActionPreference = 'Stop'
function Passo($m){ Write-Host "`n== $m" -ForegroundColor Cyan }

# --- 0. Pre-checagens -------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
      ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Rode este roteiro em um PowerShell ELEVADO (Administrador).'
}
$PU = "$env:USERDOMAIN\$env:USERNAME"
Write-Host "PU (usuario principal) = $PU" -ForegroundColor Yellow

# --- 1. Usuario PE (padrao, sem admin) -------------------------------------
Passo "Criar/atualizar usuario $PE (padrao, fora de Administradores)"
$sec = Read-Host "Defina a senha do $PE" -AsSecureString
if (Get-LocalUser -Name $PE -ErrorAction SilentlyContinue) {
  Set-LocalUser -Name $PE -Password $sec -PasswordNeverExpires $true   # A111-03 (ou politica monitorada)
} else {
  New-LocalUser -Name $PE -Password $sec -PasswordNeverExpires $true -AccountNeverExpires `
    -FullName 'Executor Piloto (isolado)' -Description 'PE do gate de isolamento — sem admin' | Out-Null
}
# garantir que NAO esta em Administradores
try { Remove-LocalGroupMember -Group 'Administradores' -Member $PE -ErrorAction Stop } catch {}
try { Remove-LocalGroupMember -Group 'Administrators' -Member $PE -ErrorAction Stop } catch {}
$peSid = (Get-LocalUser $PE).SID.Value
Write-Host "SID do $PE = $peSid"

# --- 2. Pastas + ACL --------------------------------------------------------
Passo "Pastas de trabalho/config/credencial com ACL explicita (heranca desligada)"
foreach ($d in @($WorkRoot,$ConfigDir,$CredDir,(Split-Path $AcaoScript))) { New-Item -ItemType Directory -Force $d | Out-Null }

# Pasta de trabalho: PU controle total + dono; PE modifica a arvore (os subdirs .git/settings recebem RX depois, por execucao)
icacls $WorkRoot /inheritance:r /Q | Out-Null
icacls $WorkRoot /grant:r "${PU}:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "Administradores:(OI)(CI)F" "${PE}:(OI)(CI)M" /Q | Out-Null
# CLAUDE_CONFIG_DIR do PE (baixa integridade): so o PE grava; rotulo Low via icacls /setintegritylevel
icacls $ConfigDir /inheritance:r /Q | Out-Null
icacls $ConfigDir /grant:r "${PE}:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "Administradores:(OI)(CI)F" /Q | Out-Null
icacls $ConfigDir /setintegritylevel (Low)(OI)(CI) /Q | Out-Null         # A111-04 (Low IL)
# Pasta da credencial do PE: ACL so-PE (voce coloca a chave aqui, fora da arvore editavel)
icacls $CredDir /inheritance:r /Q | Out-Null
icacls $CredDir /grant:r "${PE}:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "Administradores:(OI)(CI)F" /Q | Out-Null
# Script da acao: pasta do PU; PE so le/executa (A111-01)
icacls (Split-Path $AcaoScript) /inheritance:r /Q | Out-Null
icacls (Split-Path $AcaoScript) /grant:r "${PU}:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "Administradores:(OI)(CI)F" "${PE}:(OI)(CI)RX" /Q | Out-Null
if (-not (Test-Path $AcaoScript)) {
  Set-Content $AcaoScript "# acao da tarefa (PE). Sera substituida pelo lancador/embrulho do PE (ramo isolado).`nWrite-Output 'placeholder-acao-pe'"
}

# --- 3. Direito de logon em lote + negar interativo/remoto (secedit) --------
Passo "secedit: conceder SeBatchLogonRight ao PE e NEGAR logon interativo/remoto"  # A111-03 / Perplexity
$inf = Join-Path $env:TEMP 'exec-piloto.inf'; $sdb = Join-Path $env:TEMP 'exec-piloto.sdb'
secedit /export /cfg $inf /quiet
$txt = Get-Content $inf
function Merge-Right([string[]]$lines,[string]$right,[string]$sid){
  $i = ($lines | Select-String "^$right").LineNumber
  if ($i){ $idx=$i-1; if($lines[$idx] -notmatch [regex]::Escape($sid)){ $lines[$idx] = $lines[$idx].TrimEnd() + ",*$sid" } }
  else { $lines += "$right = *$sid" }
  return $lines
}
$txt = Merge-Right $txt 'SeBatchLogonRight'            $peSid
$txt = Merge-Right $txt 'SeDenyInteractiveLogonRight'  $peSid
$txt = Merge-Right $txt 'SeDenyRemoteInteractiveLogonRight' $peSid
Set-Content $inf $txt
secedit /configure /db $sdb /cfg $inf /areas USER_RIGHTS /quiet
# Conferencia (reexportar e checar) — A111-03
secedit /export /cfg "$inf.check" /quiet
$chk = Get-Content "$inf.check"
foreach($r in 'SeBatchLogonRight','SeDenyInteractiveLogonRight','SeDenyRemoteInteractiveLogonRight'){
  $ok = ($chk | Select-String "^$r").ToString() -match [regex]::Escape($peSid)
  Write-Host ("  {0}: {1}" -f $r, ($(if($ok){'OK'}else{'FALTANDO — verifique GPO'})))
}

# --- 4. Tarefa agendada com DACL explicita e flag 0x10 ---------------------
Passo "Registrar tarefa $TaskName (TASK_LOGON_PASSWORD, DONT_ADD_PRINCIPAL_ACE=0x10)"  # A111-01/02
# Via Schedule.Service COM para controlar RegistrationInfo flags e SDDL (o cmdlet Register-ScheduledTask nao expoe 0x10).
$svc = New-Object -ComObject 'Schedule.Service'; $svc.Connect()
$root = $svc.GetFolder('\')
$td = $svc.NewTask(0)
$td.RegistrationInfo.Description = 'Executor isolado (PE) — gate de isolamento'
$td.Principal.LogonType = 1            # TASK_LOGON_PASSWORD (nao S4U) — A111-03
$td.Principal.RunLevel  = 0            # LUA (sem elevacao)
$td.Settings.MultipleInstances = 2    # IgnoreNew
$td.Settings.DisallowStartIfOnBatteries = $false
$act = $td.Actions.Create(0)          # TASK_ACTION_EXEC
$act.Path = 'powershell.exe'
$act.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$AcaoScript`""
# SDDL da tarefa: SYSTEM(BA)+Admins controle total; PU ler+executar+parar; PE SEM entrada.
# GR=ler, GX=executar, RP/WP cobrem run/stop; sem GW/GA/DE/WD para o PU (nao altera o comando).
$peAcc = (New-Object System.Security.Principal.NTAccount($PE)).Translate([System.Security.Principal.SecurityIdentifier]).Value
$puAcc = (New-Object System.Security.Principal.NTAccount($env:USERNAME)).Translate([System.Security.Principal.SecurityIdentifier]).Value
$sddl  = "D:(A;;FA;;;BA)(A;;FA;;;SY)(A;;GRGX;;;$puAcc)"   # PE: NENHUMA ACE
# flags: 6 = TASK_CREATE_OR_UPDATE ; 0x10 = DONT_ADD_PRINCIPAL_ACE
$flags = 6 -bor 0x10
$pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
$root.RegisterTaskDefinition($TaskName, $td, $flags, "$env:COMPUTERNAME\$PE", $pw, 1, $sddl) | Out-Null
$pw = $null
Write-Host "  Tarefa registrada com DACL sem ACE para o PE (0x10). Confira: (Get-ScheduledTask $TaskName)" -ForegroundColor Green

# --- 5. Resumo / proximos passos -------------------------------------------
Passo "RESUMO"
Write-Host @"
  PE:            $PE  (SID $peSid) — padrao, sem admin, logon interativo NEGADO, lote PERMITIDO
  Trabalho:      $WorkRoot   (PU: F+dono ; PE: M)
  Config PE:     $ConfigDir  (Low IL ; so PE)   -> defina CLAUDE_CONFIG_DIR=$ConfigDir no lancador do PE
  Credencial:    $CredDir    (so PE) -> coloque aqui a CHAVE DEDICADA do workspace Anthropic 'exec-piloto'
                 com TETO MENSAL no provedor (voce cria no console; cobranca por uso de API).
  Tarefa:        $TaskName   (TASK_LOGON_PASSWORD, 0x10, DACL sem ACE do PE; PU inicia/consulta/para)
  Acao (PU):     $AcaoScript (PE so RX) -> sera substituida pelo lancador/embrulho do PE (ramo isolado)

  PENDENTE (VOCE): criar o workspace Anthropic 'exec-piloto' + chave dedicada com teto mensal,
                   e autorizar a cobranca por uso de API. So depois a bateria real roda.
  NAO feito aqui:  nenhuma execucao de tarefa, nenhum commit, nenhuma cobranca ativada.
"@ -ForegroundColor Yellow
