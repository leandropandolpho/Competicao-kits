<#
  ROTEIRO ADMINISTRATIVO v3.2 - exec-piloto (GATE ISOLAMENTO DE PRINCIPAL)
  Ato - Autonomous multi-LLM orchestration flow - 136  -  base: v3.1 (Ato 119) + v3 (116) + v2 (114) + contrato v0.2 + A111
  v3.1: V4-01..05 (Perplexity/ChatGPT) + V3-01..08 + R-1/R-2/R-3 + ADM-01..06 - mantidos.
  v3.2: correcoes da mesa (Atos 122/134):
    ADM-V5-01 (Gemini): manifesto de PROVENIENCIA + deteccao de COLISAO. Antes de criar, se o usuario PE ou a tarefa
        ja existirem SEM terem sido criados por este roteiro (manifesto ausente ou nao os lista), RECUSA (falha fechada)
        a menos que -PermitirColisao. Grava C:\piloto-ctrl\proveniencia-install.json (ACL SYSTEM+Admins) com o
        inventario do que ESTE roteiro criou e o estado ANTERIOR das 3 linhas do secedit. O desfazer reverte SO itens
        com proveniencia confirmada.
    PE-F11 (ChatGPT): a pasta da credencial recebe rotulo Medium + NO_READ_UP (SACL "S:(ML;OICI;NRNWNX;;;ME)") e a
        SACL EFETIVA e reconferida (rid 8192 + NR), falha fechada. Low IL (inclui o $TestCmd sob o PE) NAO le a chave,
        mesmo tendo o mesmo SID do PE (a omissao da env var, sozinha, nao bastava).
    ADM-V5-02: registra no manifesto o caminho e o SHA-256 do pwsh aprovado (conferencia em runtime pelo embrulho).
  So ASCII, CRLF; parse a validar em 5.1 E pwsh 7 (como a v3.1, job 079).

  ATENCAO / LEIA ANTES DE RODAR:
  - Preparado pelo AUDITOR_BASE_CLAUDE para VOCE (Leandro) executar UMA VEZ, como ADMINISTRADOR, APOS a mesa reverificar.
  - O AUDITOR NAO executou nada disto. NAO rode a v3 nem a v3.1; use esta v3.2 apenas depois de reaprovada.
  - NAO coloca chave de API aqui. Workspace Anthropic 'exec-piloto' + chave dedicada com teto mensal sao criados por
    VOCE no provedor. Deixe a chave em $CredDir (ACL so-PE, Medium+NO_READ_UP).
  - Nada aqui libera execucao desassistida. R1, B-07 e aprovacao humana continuam valendo. Falha fechada.
#>
[CmdletBinding()]
param(
  [string]$PE = 'exec-piloto',
  [string]$WorkRoot = 'C:\piloto-work',
  [string]$ConfigDir = 'C:\piloto-pe\cfg',
  [string]$CredDir   = 'C:\piloto-pe\cred',
  [string]$CtrlDir   = 'C:\piloto-ctrl',                 # V5-01: pasta de controle do PU (manifesto); PE sem acesso
  [string]$TaskName  = 'ExecPiloto_Executor',
  [string]$AcaoScript= 'C:\piloto-ctrl\acao-pe.ps1',
  [string]$PwshPath  = '',
  [string]$PwshSha256= '',      # ADM-V5-02: SHA-256 do pwsh aprovado p/ registrar no manifesto (vazio = so registra o caminho)
  [switch]$ResetSenha,
  [switch]$PermitirColisao,     # V5-01: autoriza adotar usuario/tarefa pre-existentes NAO criados por este roteiro
  [bool]$SenhaNuncaExpira = $true,
  [string]$ExecTimeLimit = 'PT2H'
)
$ErrorActionPreference = 'Stop'
function Passo($m){ Write-Host "`n== $m" -ForegroundColor Cyan }
function Invoke-Icacls  { & "$env:SystemRoot\System32\icacls.exe"  @args | Out-Null; if ($LASTEXITCODE -ne 0) { throw "icacls falhou (codigo $LASTEXITCODE): $($args -join ' ')" } }
function Invoke-Secedit { & "$env:SystemRoot\System32\secedit.exe" @args | Out-Null; if ($LASTEXITCODE -ne 0) { throw "secedit falhou (codigo $LASTEXITCODE): $($args -join ' ')" } }
function Tem-Sid([string]$linha, [string]$sid) { return [bool](($linha -split '=', 2)[-1] -split ',' | Where-Object { $_.Trim() -eq "*$sid" }) }
$SID_SYSTEM='S-1-5-18'; $SID_ADMINS='S-1-5-32-544'

# PE-F11: helper de rotulo de integridade (Medium + NO_READ_UP) + releitura da SACL efetiva. ASCII; compila em 5.1 e 7.
if (-not ('B05Label' -as [type])) {
  Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class B05Label {
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string s, uint rev, out IntPtr sd, out uint sz);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool GetSecurityDescriptorSacl(IntPtr sd, out bool present, out IntPtr sacl, out bool deflt);
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern uint SetNamedSecurityInfoW(string name, int type, uint info, IntPtr o, IntPtr g, IntPtr dacl, IntPtr sacl);
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern uint GetNamedSecurityInfoW(string name, int type, uint info, IntPtr o, IntPtr g, IntPtr dacl, out IntPtr sacl, out IntPtr sd);
  [DllImport("advapi32.dll")] static extern bool GetAce(IntPtr acl, int i, out IntPtr ace);
  [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthority(IntPtr sid, uint i);
  [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
  // Aplica Medium IL + NO_READ_UP|NO_WRITE_UP|NO_EXECUTE_UP, herdavel. type SE_FILE_OBJECT=1, info LABEL=0x10.
  public static string Rotular(string caminho) {
    IntPtr sd; uint sz;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW("S:(ML;OICI;NRNWNX;;;ME)", 1, out sd, out sz)) return "ConvertSD " + Marshal.GetLastWin32Error();
    try { bool pres, def; IntPtr sacl;
      if (!GetSecurityDescriptorSacl(sd, out pres, out sacl, out def) || !pres) return "GetSacl " + Marshal.GetLastWin32Error();
      uint rc = SetNamedSecurityInfoW(caminho, 1, 0x10, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, sacl);
      return rc == 0 ? "" : ("SetNamedSecurityInfo " + rc);
    } finally { LocalFree(sd); }
  }
  // Le o rotulo efetivo: "rid|mask" (rid 8192=Medium; mask NR=2 NW=1 NX=4), "nenhum" ou "erro:<n>".
  public static string Info(string caminho) {
    IntPtr sacl, sd; uint rc = GetNamedSecurityInfoW(caminho, 1, 0x10, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, out sacl, out sd);
    if (rc != 0) return "erro:" + rc;
    try {
      if (sacl == IntPtr.Zero) return "nenhum";
      int count = Marshal.ReadInt16(sacl, 4); if (count < 1) return "nenhum";
      IntPtr ace; if (!GetAce(sacl, 0, out ace)) return "erro:getace";
      if (Marshal.ReadByte(ace, 0) != 0x11) return "nao-ml";
      uint mask = (uint)Marshal.ReadInt32(ace, 4);
      IntPtr sid = (IntPtr)(ace.ToInt64() + 8);
      int cont = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
      uint rid = (uint)Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(cont - 1)));
      return rid + "|" + mask;
    } finally { if (sd != IntPtr.Zero) LocalFree(sd); }
  }
}
'@
}

# --- 0. Pre-checagens -------------------------------------------------------
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Rode no Windows PowerShell 5.1 (powershell.exe) ELEVADO, nao no pwsh 7.' }
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
      ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Rode este roteiro em um PowerShell ELEVADO (Administrador).'
}
$puSid = ([Security.Principal.NTAccount]"$env:USERDOMAIN\$env:USERNAME").Translate([Security.Principal.SecurityIdentifier]).Value
Write-Host "PU = $env:USERDOMAIN\$env:USERNAME (SID $puSid)" -ForegroundColor Yellow
if ((Read-Host "O PU (usuario dono do controlador) e '$env:USERDOMAIN\$env:USERNAME'? Digite SIM para seguir") -cne 'SIM') { throw 'Abortado: PU nao confirmado. Eleve o PowerShell a partir da conta do PU.' }

# --- V5-01: manifesto de proveniencia + deteccao de colisao -----------------
Passo "Proveniencia (ADM-V5-01): checar colisao e preparar o manifesto"
New-Item -ItemType Directory -Force $CtrlDir | Out-Null
$Manifesto = Join-Path $CtrlDir 'proveniencia-install.json'
$provAnt = $null
if (Test-Path $Manifesto) { try { $provAnt = Get-Content -LiteralPath $Manifesto -Raw -Encoding utf8 | ConvertFrom-Json } catch { $provAnt = $null } }
$usuarioExiste = [bool](Get-LocalUser -Name $PE -ErrorAction SilentlyContinue)
$svcCol = New-Object -ComObject 'Schedule.Service'; $svcCol.Connect(); $rootCol = $svcCol.GetFolder('\')
$tarefaExiste = $false; try { $null = $rootCol.GetTask($TaskName); $tarefaExiste = $true } catch {}
function Prov-Marca($prov,[string]$chave){ return ($prov -and $prov.PSObject.Properties[$chave] -and $prov.$chave) }
$colisaoUsuario = $usuarioExiste -and -not (Prov-Marca $provAnt 'usuario_criado')
$colisaoTarefa  = $tarefaExiste  -and -not (Prov-Marca $provAnt 'tarefa_criada')
if (($colisaoUsuario -or $colisaoTarefa) -and -not $PermitirColisao) {
  throw ("V5-01 (colisao): " + (@(if($colisaoUsuario){"usuario '$PE'"}; if($colisaoTarefa){"tarefa '$TaskName'"}) -join ' e ') +
         " ja existe(m) e NAO consta(m) no manifesto deste roteiro. Recusado (falha fechada). Use -PermitirColisao para adotar, ou remova manualmente.")
}
# inventario desta execucao
$prov = [ordered]@{ versao='v3.2'; gerado_em=(Get-Date).ToUniversalTime().ToString('o'); pu_sid=$puSid;
  usuario_criado=$false; tarefa_criada=$false; pastas_criadas=@(); secedit_antes=@{};
  pwsh_aprovado=''; pwsh_sha256=$PwshSha256 }

# --- 1. Usuario PE (padrao, sem admin) - ADM-05 idempotente -----------------
Passo "Criar/validar usuario $PE (padrao, fora de Administradores)"
$sec = Read-Host "Senha do $PE (a ATUAL, se a conta ja existe; necessaria para registrar a tarefa)" -AsSecureString
if (-not $usuarioExiste) {
  New-LocalUser -Name $PE -Password $sec -PasswordNeverExpires:$SenhaNuncaExpira -AccountNeverExpires `
    -FullName 'Executor Piloto (isolado)' -Description 'PE do gate de isolamento - sem admin' | Out-Null
  $prov.usuario_criado = $true; Write-Host "  Conta criada."
} elseif ($ResetSenha) {
  Set-LocalUser -Name $PE -Password $sec; Write-Host "  Conta existia; senha REDEFINIDA (-ResetSenha)."
} else {
  Write-Host "  Conta existia; senha NAO alterada. Use -ResetSenha para trocar. (A senha informada sera usada so para registrar a tarefa.)" -ForegroundColor Yellow
}
Set-LocalUser -Name $PE -PasswordNeverExpires:$SenhaNuncaExpira
try { Remove-LocalGroupMember -SID $SID_ADMINS -Member $PE -ErrorAction Stop } catch {}
$peSid = (Get-LocalUser $PE).SID.Value
function Get-AdminMemberSids {
  try { return @(Get-LocalGroupMember -SID $SID_ADMINS -ErrorAction Stop | ForEach-Object { $_.SID.Value }) }
  catch { Write-Host "  Get-LocalGroupMember falhou ($($_.Exception.Message)); tentando ADSI..." -ForegroundColor Yellow }
  try {
    $nome = ([Security.Principal.SecurityIdentifier]$SID_ADMINS).Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
    $grp = [ADSI]("WinNT://./$nome,group"); $sids = @()
    foreach ($m in @($grp.psbase.Invoke('Members'))) { $b = ([ADSI]$m).InvokeGet('objectSID'); $sids += (New-Object Security.Principal.SecurityIdentifier($b,0)).Value }
    return $sids
  } catch { throw "V4-01: nao foi possivel enumerar Administradores por nenhum metodo ($($_.Exception.Message)) - falha fechada." }
}
$admins = Get-AdminMemberSids
if ($admins -contains $peSid) { throw "ADM-06: $PE ($peSid) ainda consta em Administradores - aborte e remova manualmente." }
Write-Host "SID do $PE = $peSid ; admin? NAO (verificado)" -ForegroundColor Green

# --- 2. Pastas + ACL (R-3: por SID) -----------------------------------------
Passo "Pastas (trabalho/config/credencial/acao) com ACL explicita por SID (heranca desligada)"
foreach ($d in @($WorkRoot,$ConfigDir,$CredDir,(Split-Path $AcaoScript))) {
  if (-not (Test-Path $d)) { $prov.pastas_criadas += $d }
  New-Item -ItemType Directory -Force $d | Out-Null
}
foreach ($mae in @((Split-Path $ConfigDir),(Split-Path $AcaoScript)) | Select-Object -Unique) {
  if ((Split-Path $mae -Qualifier) -eq $mae.TrimEnd('\')) { continue }
  Invoke-Icacls $mae /inheritance:r /Q
  Invoke-Icacls $mae /grant:r "*${SID_SYSTEM}:(OI)(CI)F" "*${SID_ADMINS}:(OI)(CI)F" "*${puSid}:(OI)(CI)RX" "*${peSid}:(OI)(CI)RX" /Q
}
Invoke-Icacls $WorkRoot /inheritance:r /Q
Invoke-Icacls $WorkRoot /grant:r "*${puSid}:(OI)(CI)F" "*${SID_SYSTEM}:(OI)(CI)F" "*${SID_ADMINS}:(OI)(CI)F" "*${peSid}:(OI)(CI)M" /Q
Invoke-Icacls $ConfigDir /inheritance:r /Q
Invoke-Icacls $ConfigDir /grant:r "*${peSid}:(OI)(CI)F" "*${SID_SYSTEM}:(OI)(CI)F" "*${SID_ADMINS}:(OI)(CI)F" /Q
Invoke-Icacls $ConfigDir /setintegritylevel "(OI)(CI)Low" /Q
# Credencial do PE: ACL so-PE E (PE-F11) rotulo Medium + NO_READ_UP, para o Low IL (inclusive o $TestCmd sob o PE) NAO ler a chave
Invoke-Icacls $CredDir /inheritance:r /Q
Invoke-Icacls $CredDir /grant:r "*${peSid}:(OI)(CI)F" "*${SID_SYSTEM}:(OI)(CI)F" "*${SID_ADMINS}:(OI)(CI)F" /Q
$msgRot = [B05Label]::Rotular($CredDir)
if ($msgRot) { throw "PE-F11: nao rotulou a credencial (Medium+NO_READ_UP): $msgRot" }
$infoRot = [B05Label]::Info($CredDir)
$ridRot = ($infoRot -split '\|')[0]; $maskRot = [int](($infoRot -split '\|') | Select-Object -Last 1)
if ($ridRot -ne '8192' -or (($maskRot -band 2) -eq 0)) { throw "PE-F11: SACL efetiva da credencial invalida ($infoRot); esperado rid 8192 (Medium) com NR (mask&2). Falha fechada." }
Write-Host "  Credencial ${CredDir}: rotulo Medium + NO_READ_UP CONFERIDO ($infoRot)." -ForegroundColor Green
Invoke-Icacls (Split-Path $AcaoScript) /inheritance:r /Q
Invoke-Icacls (Split-Path $AcaoScript) /grant:r "*${puSid}:(OI)(CI)F" "*${SID_SYSTEM}:(OI)(CI)F" "*${SID_ADMINS}:(OI)(CI)F" "*${peSid}:(OI)(CI)RX" /Q
if (-not (Test-Path $AcaoScript)) {
  Set-Content $AcaoScript "# acao da tarefa (PE). Sera substituida pelo lancador/embrulho do PE (ramo isolado).`nWrite-Output 'placeholder-acao-pe'"
}

# --- 3. secedit: SeBatchLogonRight + negar interativo/remoto - R-2 + ADM-02 --
Passo "secedit: conceder SeBatchLogonRight e NEGAR logon interativo/remoto (falha fechada)"
$inf = Join-Path $env:TEMP 'exec-piloto.inf'; $sdb = Join-Path $env:TEMP 'exec-piloto.sdb'
Invoke-Secedit /export /cfg $inf /quiet
$txt = @(Get-Content $inf)
# V5-01: guarda o estado ANTERIOR das 3 linhas (para reversao cirurgica pelo desfazer)
foreach ($r in 'SeBatchLogonRight','SeDenyInteractiveLogonRight','SeDenyRemoteInteractiveLogonRight') {
  $ln = ($txt | Select-String "^$r\s*=") | Select-Object -First 1
  $prov.secedit_antes[$r] = if ($ln) { $ln.Line } else { '' }
}
function Merge-Right([string[]]$lines,[string]$right,[string]$sid){
  $m = $lines | Select-String "^$right\s*="
  if ($m) { $idx = $m.LineNumber - 1; if (-not (Tem-Sid $lines[$idx] $sid)) { $lines[$idx] = $lines[$idx].TrimEnd() + ",*$sid" }; return $lines }
  $p = ($lines | Select-String '^\[Privilege Rights\]').LineNumber
  if (-not $p) { throw "Secao [Privilege Rights] nao encontrada no .inf do secedit." }
  $antes  = $lines[0..($p-1)]; $depois = if ($p -lt $lines.Count) { $lines[$p..($lines.Count-1)] } else { @() }
  return @($antes + @("$right = *$sid") + $depois)
}
$txt = Merge-Right $txt 'SeBatchLogonRight'                 $peSid
$txt = Merge-Right $txt 'SeDenyInteractiveLogonRight'       $peSid
$txt = Merge-Right $txt 'SeDenyRemoteInteractiveLogonRight' $peSid
Set-Content -Path $inf -Value $txt -Encoding Unicode
Invoke-Secedit /configure /db $sdb /cfg $inf /areas USER_RIGHTS /quiet
Invoke-Secedit /export /cfg "$inf.check" /quiet
$chk = @(Get-Content "$inf.check")
foreach($r in 'SeBatchLogonRight','SeDenyInteractiveLogonRight','SeDenyRemoteInteractiveLogonRight'){
  $linha = ($chk | Select-String "^$r\s*=")
  $ok = $linha -and (Tem-Sid $linha.Line $peSid)
  if (-not $ok) { throw "ADM-02: '$r' nao foi aplicada ao PE (verifique GPO de dominio sobrepondo a politica local)." }
  Write-Host "  ${r}: OK" -ForegroundColor Green
}
Remove-Item $inf, "$inf.check", $sdb -Force -ErrorAction SilentlyContinue

# --- 4. Tarefa agendada: flag 0x10 + DACL sem ACE do PE - A111-01/02, ADM-03 -
Passo "Registrar tarefa $TaskName (TASK_LOGON_PASSWORD, DONT_ADD_PRINCIPAL_ACE=0x10)"
if ([string]::IsNullOrWhiteSpace($PwshPath)) {
  $cand = @("$env:ProgramFiles\PowerShell\7\pwsh.exe","$env:USERPROFILE\piloto\ferramentas\pwsh-7.6.7\pwsh.exe")
  $PwshPath = ($cand | Where-Object { Test-Path $_ } | Select-Object -First 1)
  if ($PwshPath -and $PwshPath.StartsWith($env:USERPROFILE, [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "  pwsh 7 so existe no perfil do PU ($PwshPath): o PE nao alcanca. Usando powershell.exe; copie o pwsh para uma pasta do PE (RX) e rode de novo com -PwshPath se quiser o 7." -ForegroundColor Yellow
    $PwshPath = $null
  }
  if (-not $PwshPath) { $PwshPath = 'powershell.exe'; Write-Host "  pwsh 7 nao encontrado; usando powershell.exe (ajuste depois no embrulho)." -ForegroundColor Yellow }
}
$prov.pwsh_aprovado = $PwshPath
$svc = New-Object -ComObject 'Schedule.Service'; $svc.Connect()
$root = $svc.GetFolder('\')
$td = $svc.NewTask(0)
$td.RegistrationInfo.Description = 'Executor isolado (PE) - gate de isolamento'
$td.Principal.LogonType = 1
$td.Principal.RunLevel  = 0
$td.Settings.MultipleInstances = 2
$td.Settings.DisallowStartIfOnBatteries = $false
$td.Settings.StopIfGoingOnBatteries = $false
$td.Settings.ExecutionTimeLimit = $ExecTimeLimit
$act = $td.Actions.Create(0)
$act.Path = $PwshPath
$act.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$AcaoScript`""
$sddl  = "D:(A;;FA;;;$SID_ADMINS)(A;;FA;;;$SID_SYSTEM)(A;;GRGX;;;$puSid)"
$flags = 6 -bor 0x10
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
try {
  $root.RegisterTaskDefinition($TaskName, $td, $flags, "$env:COMPUTERNAME\$PE",
    [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr), 1, $sddl) | Out-Null
  if (-not $tarefaExiste) { $prov.tarefa_criada = $true }
} finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr); $sec.Dispose() }
$reg = $root.GetTask($TaskName)
$sddlEff = $reg.GetSecurityDescriptor(4)
Write-Host "  SDDL efetiva da tarefa: $sddlEff"
if ($sddlEff -match ([regex]::Escape($peSid) + '(?![0-9-])')) { throw "ADM-03/A111-01: a DACL da tarefa contem o SID do PE - a flag 0x10 nao surtiu efeito. Aborte." }
Write-Host "  DACL sem ACE do PE: OK (0x10 efetivo). N17/P4 ainda devem PROVAR: PU inicia/consulta/para e PE nao altera." -ForegroundColor Green

# --- V5-01: grava o manifesto de proveniencia (ACL SYSTEM+Admins) -----------
Passo "Gravar manifesto de proveniencia (ADM-V5-01)"
$prov.pe_sid = $peSid; $prov.pe = $PE; $prov.tarefa = $TaskName
Set-Content -Path $Manifesto -Value ($prov | ConvertTo-Json -Depth 6) -Encoding UTF8
Invoke-Icacls $Manifesto /inheritance:r /Q
Invoke-Icacls $Manifesto /grant:r "*${SID_SYSTEM}:F" "*${SID_ADMINS}:F" /Q
Write-Host "  Manifesto: $Manifesto (ACL SYSTEM+Admins). O desfazer reverte SO o que consta aqui." -ForegroundColor Green

# --- 5. Resumo --------------------------------------------------------------
Passo "RESUMO"
Write-Host @"
  PE:            $PE  (SID $peSid) - padrao, sem admin (verificado), interativo NEGADO, lote PERMITIDO
  Trabalho:      $WorkRoot   (PU: F+dono ; PE: M)
  Config PE:     $ConfigDir  (Low IL ; so PE)       -> CLAUDE_CONFIG_DIR=$ConfigDir no embrulho do PE
  Credencial:    $CredDir    (so PE ; Medium+NO_READ_UP CONFERIDO) -> coloque aqui a CHAVE DEDICADA (teto mensal)
  Tarefa:        $TaskName   (PASSWORD, 0x10, DACL sem ACE do PE; acao: $PwshPath)
  Acao (PU):     $AcaoScript (PE so RX)
  Manifesto:     $Manifesto  (proveniencia; usado pelo desfazer)   criado_usuario=$($prov.usuario_criado) criado_tarefa=$($prov.tarefa_criada)

  PENDENTE (VOCE): criar workspace Anthropic 'exec-piloto' + chave dedicada com teto mensal; por a chave em $CredDir.
  NAO feito aqui:  execucao de tarefa, commit, cobranca. N17/P4 (prova de DACL/parada) rodam na bateria, nao aqui.
"@ -ForegroundColor Yellow
