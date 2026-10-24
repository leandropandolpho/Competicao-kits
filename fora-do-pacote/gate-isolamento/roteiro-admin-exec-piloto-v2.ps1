<#
  ROTEIRO ADMINISTRATIVO v2 — exec-piloto (GATE ISOLAMENTO DE PRINCIPAL)
  Ato - Autonomous multi-LLM orchestration flow - 114  ·  base: contrato v0.2 + Adendo A111
  Correcoes do Ato 113: Gemini R-1/R-2/R-3 + ChatGPT ADM-01..ADM-06.

  ATENCAO / LEIA ANTES DE RODAR:
  - Preparado pelo AUDITOR_BASE_CLAUDE para VOCE (Leandro) executar UMA VEZ, como ADMINISTRADOR.
  - O AUDITOR NAO executou nada disto. Recomendacao da mesa (ChatGPT): validar antes em ambiente descartavel.
  - NAO coloca chave de API aqui. Workspace Anthropic 'exec-piloto' + chave dedicada com teto mensal sao
    criados por VOCE no provedor (cobranca por uso de API, separada do Max). Deixe a chave em $CredDir (ACL so-PE).
  - Nada aqui libera execucao desassistida. R1, B-07 e aprovacao humana continuam valendo.
  - Idempotente onde possivel; FALHA FECHADA em icacls/secedit; rode em PowerShell ELEVADO.
#>
[CmdletBinding()]
param(
  [string]$PE = 'exec-piloto',
  [string]$WorkRoot = 'C:\piloto-work',
  [string]$ConfigDir = 'C:\piloto-pe\cfg',     # CLAUDE_CONFIG_DIR do PE (baixa integridade) — A111-04
  [string]$CredDir   = 'C:\piloto-pe\cred',    # pasta da chave do PE, ACL so-PE — A111-04/06
  [string]$TaskName  = 'ExecPiloto_Executor',
  [string]$AcaoScript= 'C:\piloto-ctrl\acao-pe.ps1',  # script da acao (pasta do PU; PE so RX) — A111-01
  [string]$PwshPath  = '',    # R-3: caminho do pwsh 7 p/ a acao; vazio = autodetect; cai p/ powershell.exe
  [switch]$ResetSenha         # ADM-05: so troca a senha de conta existente se explicitamente pedido
)
$ErrorActionPreference = 'Stop'
function Passo($m){ Write-Host "`n== $m" -ForegroundColor Cyan }
# ADM-01: comandos nativos com FALHA FECHADA (checam $LASTEXITCODE)
function Icacls { icacls @args | Out-Null; if ($LASTEXITCODE -ne 0) { throw "icacls falhou (codigo $LASTEXITCODE): $($args -join ' ')" } }
function Secedit { secedit @args | Out-Null; if ($LASTEXITCODE -ne 0) { throw "secedit falhou (codigo $LASTEXITCODE): $($args -join ' ')" } }
# SIDs conhecidos (R-3: portabilidade de idioma)
$SID_SYSTEM='S-1-5-18'; $SID_ADMINS='S-1-5-32-544'

# --- 0. Pre-checagens -------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
      ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Rode este roteiro em um PowerShell ELEVADO (Administrador).'
}
$puSid = ([Security.Principal.NTAccount]"$env:USERDOMAIN\$env:USERNAME").Translate([Security.Principal.SecurityIdentifier]).Value
Write-Host "PU = $env:USERDOMAIN\$env:USERNAME (SID $puSid)" -ForegroundColor Yellow

# --- 1. Usuario PE (padrao, sem admin) — ADM-05 idempotente -----------------
Passo "Criar/validar usuario $PE (padrao, fora de Administradores)"
$existe = [bool](Get-LocalUser -Name $PE -ErrorAction SilentlyContinue)
$sec = Read-Host "Senha do $PE (a ATUAL, se a conta ja existe; necessaria para registrar a tarefa)" -AsSecureString
if (-not $existe) {
  New-LocalUser -Name $PE -Password $sec -PasswordNeverExpires:$true -AccountNeverExpires `
    -FullName 'Executor Piloto (isolado)' -Description 'PE do gate de isolamento — sem admin' | Out-Null
  Write-Host "  Conta criada."
} elseif ($ResetSenha) {
  Set-LocalUser -Name $PE -Password $sec -PasswordNeverExpires:$true
  Write-Host "  Conta existia; senha REDEFINIDA (-ResetSenha)."
} else {
  Write-Host "  Conta existia; senha NAO alterada. Use -ResetSenha para trocar. (A senha informada sera usada so para registrar a tarefa.)" -ForegroundColor Yellow
}
# garantir que NAO esta em Administradores (por SID; idioma-neutro)
try { Remove-LocalGroupMember -SID $SID_ADMINS -Member $PE -ErrorAction Stop } catch {}
$peSid = (Get-LocalUser $PE).SID.Value
# ADM-06: VERIFICAR (falha fechada) que o PE nao e admin
$admins = @(Get-LocalGroupMember -SID $SID_ADMINS -ErrorAction SilentlyContinue | ForEach-Object { $_.SID.Value })
if ($admins -contains $peSid) { throw "ADM-06: $PE ($peSid) ainda consta em Administradores — aborte e remova manualmente." }
Write-Host "SID do $PE = $peSid ; admin? NAO (verificado)" -ForegroundColor Green

# --- 2. Pastas + ACL (R-3: por SID) -----------------------------------------
Passo "Pastas (trabalho/config/credencial/acao) com ACL explicita por SID (heranca desligada)"
foreach ($d in @($WorkRoot,$ConfigDir,$CredDir,(Split-Path $AcaoScript))) { New-Item -ItemType Directory -Force $d | Out-Null }
# Pasta de trabalho: PU controle total + dono; PE Modifica a arvore (.git/settings recebem RX por execucao, no embrulho)
Icacls $WorkRoot /inheritance:r /Q
Icacls $WorkRoot /grant:r "*${puSid}:(OI)(CI)F" "*${SID_SYSTEM}:(OI)(CI)F" "*${SID_ADMINS}:(OI)(CI)F" "*${peSid}:(OI)(CI)M" /Q
# CLAUDE_CONFIG_DIR do PE (baixa integridade): so o PE grava. R-1: nivel entre aspas, flags antes do nivel.
Icacls $ConfigDir /inheritance:r /Q
Icacls $ConfigDir /grant:r "*${peSid}:(OI)(CI)F" "*${SID_SYSTEM}:(OI)(CI)F" "*${SID_ADMINS}:(OI)(CI)F" /Q
Icacls $ConfigDir /setintegritylevel "(OI)(CI)Low" /Q                     # A111-04 (Low IL) — R-1 corrigido
# Pasta da credencial do PE: ACL so-PE
Icacls $CredDir /inheritance:r /Q
Icacls $CredDir /grant:r "*${peSid}:(OI)(CI)F" "*${SID_SYSTEM}:(OI)(CI)F" "*${SID_ADMINS}:(OI)(CI)F" /Q
# Script da acao: pasta do PU; PE so le/executa (A111-01)
Icacls (Split-Path $AcaoScript) /inheritance:r /Q
Icacls (Split-Path $AcaoScript) /grant:r "*${puSid}:(OI)(CI)F" "*${SID_SYSTEM}:(OI)(CI)F" "*${SID_ADMINS}:(OI)(CI)F" "*${peSid}:(OI)(CI)RX" /Q
if (-not (Test-Path $AcaoScript)) {
  Set-Content $AcaoScript "# acao da tarefa (PE). Sera substituida pelo lancador/embrulho do PE (ramo isolado).`nWrite-Output 'placeholder-acao-pe'"
}

# --- 3. secedit: SeBatchLogonRight + negar interativo/remoto — R-2 + ADM-02 --
Passo "secedit: conceder SeBatchLogonRight e NEGAR logon interativo/remoto (falha fechada)"
$inf = Join-Path $env:TEMP 'exec-piloto.inf'; $sdb = Join-Path $env:TEMP 'exec-piloto.sdb'
Secedit /export /cfg $inf /quiet
$txt = @(Get-Content $inf)
# R-2: insere a chave DENTRO de [Privilege Rights] quando ausente; mantem politica existente
function Merge-Right([string[]]$lines,[string]$right,[string]$sid){
  $m = $lines | Select-String "^$right\s*="
  if ($m) {
    $idx = $m.LineNumber - 1
    if ($lines[$idx] -notmatch [regex]::Escape($sid)) { $lines[$idx] = $lines[$idx].TrimEnd() + ",*$sid" }
    return $lines
  }
  $p = ($lines | Select-String '^\[Privilege Rights\]').LineNumber
  if (-not $p) { throw "Secao [Privilege Rights] nao encontrada no .inf do secedit." }
  $antes  = $lines[0..($p-1)]
  $depois = if ($p -lt $lines.Count) { $lines[$p..($lines.Count-1)] } else { @() }
  return @($antes + @("$right = *$sid") + $depois)
}
$txt = Merge-Right $txt 'SeBatchLogonRight'                 $peSid
$txt = Merge-Right $txt 'SeDenyInteractiveLogonRight'       $peSid
$txt = Merge-Right $txt 'SeDenyRemoteInteractiveLogonRight' $peSid
Set-Content -Path $inf -Value $txt -Encoding Unicode        # R-2: .inf do secedit e UTF-16 LE
Secedit /configure /db $sdb /cfg $inf /areas USER_RIGHTS /quiet
# ADM-02: conferencia que ABORTA se faltar
Secedit /export /cfg "$inf.check" /quiet
$chk = @(Get-Content "$inf.check")
foreach($r in 'SeBatchLogonRight','SeDenyInteractiveLogonRight','SeDenyRemoteInteractiveLogonRight'){
  $linha = ($chk | Select-String "^$r\s*=")
  $ok = $linha -and ($linha.ToString() -match [regex]::Escape($peSid))
  if (-not $ok) { throw "ADM-02: '$r' nao foi aplicada ao PE (verifique GPO de dominio sobrepondo a politica local)." }
  Write-Host "  ${r}: OK" -ForegroundColor Green
}

# --- 4. Tarefa agendada: flag 0x10 + DACL sem ACE do PE — A111-01/02, ADM-03 -
Passo "Registrar tarefa $TaskName (TASK_LOGON_PASSWORD, DONT_ADD_PRINCIPAL_ACE=0x10)"
if ([string]::IsNullOrWhiteSpace($PwshPath)) {           # R-3: apontar a acao para pwsh 7 se existir
  $cand = @("$env:ProgramFiles\PowerShell\7\pwsh.exe","$env:USERPROFILE\piloto\ferramentas\pwsh-7.6.7\pwsh.exe")
  $PwshPath = ($cand | Where-Object { Test-Path $_ } | Select-Object -First 1)
  if (-not $PwshPath) { $PwshPath = 'powershell.exe'; Write-Host "  pwsh 7 nao encontrado; usando powershell.exe (ajuste depois no embrulho)." -ForegroundColor Yellow }
}
$svc = New-Object -ComObject 'Schedule.Service'; $svc.Connect()
$root = $svc.GetFolder('\')
$td = $svc.NewTask(0)
$td.RegistrationInfo.Description = 'Executor isolado (PE) — gate de isolamento'
$td.Principal.LogonType = 1            # TASK_LOGON_PASSWORD (nao S4U) — A111-03
$td.Principal.RunLevel  = 0            # LUA (sem elevacao)
$td.Settings.MultipleInstances = 2    # IgnoreNew
$td.Settings.DisallowStartIfOnBatteries = $false
$act = $td.Actions.Create(0)          # TASK_ACTION_EXEC
$act.Path = $PwshPath
$act.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$AcaoScript`""
# DACL: SYSTEM+Admins controle total; PU ler+executar (GRGX); PE SEM entrada. 0x10 impede ACE implicita do PE.
$sddl  = "D:(A;;FA;;;$SID_ADMINS)(A;;FA;;;$SID_SYSTEM)(A;;GRGX;;;$puSid)"
$flags = 6 -bor 0x10                   # 6=CREATE_OR_UPDATE | 0x10=DONT_ADD_PRINCIPAL_ACE
$pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
try {
  $root.RegisterTaskDefinition($TaskName, $td, $flags, "$env:COMPUTERNAME\$PE", $pw, 1, $sddl) | Out-Null
} finally { $pw = $null; [GC]::Collect() }
# ADM-03: reler a DACL EFETIVA da tarefa e exibir (nao presumir); N17/P4 provam o comportamento em runtime
$reg = $root.GetTask($TaskName)
$sddlEff = $reg.GetSecurityDescriptor(4)   # 4 = DACL_SECURITY_INFORMATION
Write-Host "  SDDL efetiva da tarefa: $sddlEff"
if ($sddlEff -match [regex]::Escape($peSid)) { throw "ADM-03/A111-01: a DACL da tarefa contem o SID do PE — a flag 0x10 nao surtiu efeito. Aborte." }
Write-Host "  DACL sem ACE do PE: OK (0x10 efetivo). N17/P4 ainda devem PROVAR: PU inicia/consulta/para e PE nao altera." -ForegroundColor Green

# --- 5. Resumo --------------------------------------------------------------
Passo "RESUMO"
Write-Host @"
  PE:            $PE  (SID $peSid) — padrao, sem admin (verificado), interativo NEGADO, lote PERMITIDO
  Trabalho:      $WorkRoot   (PU: F+dono ; PE: M)   [ACL por SID]
  Config PE:     $ConfigDir  (Low IL ; so PE)       -> CLAUDE_CONFIG_DIR=$ConfigDir no embrulho do PE
  Credencial:    $CredDir    (so PE)                 -> coloque aqui a CHAVE DEDICADA (workspace Anthropic 'exec-piloto', teto mensal)
  Tarefa:        $TaskName   (PASSWORD, 0x10, DACL sem ACE do PE; acao: $PwshPath)
  Acao (PU):     $AcaoScript (PE so RX)             -> sera substituida pelo lancador/embrulho do PE (ramo isolado)

  PENDENTE (VOCE): criar workspace Anthropic 'exec-piloto' + chave dedicada com teto mensal e autorizar a cobranca por uso de API.
  NAO feito aqui:  execucao de tarefa, commit, cobranca. N17/P4 (prova de DACL/parada) rodam na bateria, nao aqui.
"@ -ForegroundColor Yellow
