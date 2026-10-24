<#
  REVERSAO do roteiro exec-piloto v3.2 (GATE ISOLAMENTO DE PRINCIPAL) - ADM-V5-01 (Atos 122/134)
  Ato - Autonomous multi-LLM orchestration flow - 136  -  base: desfazer v3.1 (Ato 119)

  ATENCAO:
  - Reverte SOMENTE itens com PROVENIENCIA CONFIRMADA no manifesto C:\piloto-ctrl\proveniencia-install.json
    (usuario/tarefa/pastas que ESTE roteiro criou) e restaura cirurgicamente as 3 linhas do secedit a partir do
    estado ANTERIOR gravado no manifesto. Dupla checagem: tarefa/usuario tambem conferidos pela descricao.
  - Sem manifesto: cai para o comportamento conservador (so remove o que casar pela descricao; NAO remove pastas
    nem mexe em secedit sem confirmacao), e avisa. Nunca apaga conta/tarefa/pasta preexistente nao provada.
  - Rode no Windows PowerShell 5.1 (powershell.exe) ELEVADO. Nada aqui libera execucao desassistida.
#>
[CmdletBinding()]
param(
  [string]$CtrlDir   = 'C:\piloto-ctrl',
  [string]$PE = 'exec-piloto',
  [string]$TaskName  = 'ExecPiloto_Executor',
  [switch]$RemoverPastas,       # so apaga pastas provadas se pedido (CredDir pode conter a chave)
  [switch]$ForcarSemManifesto   # permite o modo conservador quando nao ha manifesto
)
$ErrorActionPreference = 'Stop'
$DESC_ESPERADA = 'PE do gate de isolamento - sem admin'
$DESC_TAREFA   = 'Executor isolado (PE) - gate de isolamento'
function Passo($m){ Write-Host "`n== $m" -ForegroundColor Cyan }
function Invoke-Secedit { & "$env:SystemRoot\System32\secedit.exe" @args | Out-Null; if ($LASTEXITCODE -ne 0) { throw "secedit falhou ($LASTEXITCODE)" } }

if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Rode no Windows PowerShell 5.1 (powershell.exe) ELEVADO.' }
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
      ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Rode ELEVADO (Administrador).' }

# --- Manifesto de proveniencia (ADM-V5-01) ---
$Manifesto = Join-Path $CtrlDir 'proveniencia-install.json'
$prov = $null
if (Test-Path $Manifesto) { try { $prov = Get-Content -LiteralPath $Manifesto -Raw -Encoding utf8 | ConvertFrom-Json } catch { throw "Manifesto ilegivel: $Manifesto ($($_.Exception.Message))" } }
if (-not $prov) {
  if (-not $ForcarSemManifesto) { throw "Sem manifesto em $Manifesto. Use -ForcarSemManifesto para o modo conservador (so por descricao, sem pastas/secedit)." }
  Write-Host "AVISO: sem manifesto; modo conservador (so remove tarefa/usuario que casem pela descricao)." -ForegroundColor Yellow
}
if ((Read-Host "Confirma a REVERSAO de '$PE' e da tarefa '$TaskName' conforme o manifesto? Digite SIM") -cne 'SIM') { throw 'Abortado.' }
$peSid = if ($prov -and $prov.PSObject.Properties['pe_sid']) { $prov.pe_sid } else { $u = Get-LocalUser -Name $PE -ErrorAction SilentlyContinue; if ($u) { $u.SID.Value } else { $null } }
function Prov-Marca([string]$chave){ return ($prov -and $prov.PSObject.Properties[$chave] -and $prov.$chave) }

# 1. Tarefa (so se proveniencia confirmada E descricao casar)
Passo "Remover tarefa $TaskName"
try {
  $svc = New-Object -ComObject 'Schedule.Service'; $svc.Connect(); $root = $svc.GetFolder('\')
  $t = $root.GetTask($TaskName)
  $descOk = ($t.Definition.RegistrationInfo.Description -eq $DESC_TAREFA)
  $provOk = if ($prov) { Prov-Marca 'tarefa_criada' } else { $descOk }
  if ($descOk -and $provOk) { $root.DeleteTask($TaskName, 0); Write-Host "  Tarefa removida (proveniencia+descricao OK)." -ForegroundColor Green }
  else { Write-Host "  Tarefa PRESERVADA (proveniencia=$provOk descricao=$descOk)." -ForegroundColor Yellow }
} catch { Write-Host "  Tarefa nao encontrada - nada a remover." }

# 2. Direitos do PE: restaura cirurgicamente do estado anterior (manifesto); senao remove so o SID do PE
if ($peSid) {
  Passo "Reverter SeBatchLogonRight / negacoes de logon do PE (backup antes)"
  $bkp = Join-Path $env:TEMP ("exec-piloto-backup-{0}.inf" -f (Get-Date -Format yyyyMMdd-HHmmss))
  Invoke-Secedit /export /cfg $bkp /quiet; Write-Host "  Backup da politica: $bkp"
  $inf = Join-Path $env:TEMP 'exec-piloto-undo.inf'; $sdb = Join-Path $env:TEMP 'exec-piloto-undo.sdb'
  $txt = @(Get-Content $bkp)
  foreach ($r in 'SeBatchLogonRight','SeDenyInteractiveLogonRight','SeDenyRemoteInteractiveLogonRight') {
    $anterior = if ($prov -and $prov.secedit_antes -and $prov.secedit_antes.PSObject.Properties[$r]) { [string]$prov.secedit_antes.$r } else { $null }
    for ($i=0; $i -lt $txt.Count; $i++) {
      if ($txt[$i] -match "^$r\s*=") {
        if ($null -ne $anterior) {
          # restauracao cirurgica: se a linha anterior existia, repoe; se nao existia (''), remove a chave
          $txt[$i] = if ($anterior -ne '') { $anterior } else { "$r =" }
        } else {
          # sem manifesto: remove so o SID do PE
          $itens = (($txt[$i] -split '=',2)[-1] -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne "*$peSid" }
          $txt[$i] = if ($itens) { "$r = " + ($itens -join ',') } else { "$r =" }
        }
      }
    }
  }
  Set-Content -Path $inf -Value $txt -Encoding Unicode
  Invoke-Secedit /configure /db $sdb /cfg $inf /areas USER_RIGHTS /quiet
  Remove-Item $inf,$sdb -Force -ErrorAction SilentlyContinue
  Write-Host "  Direitos do PE revertidos." -ForegroundColor Green
}

# 3. Usuario PE (so se proveniencia confirmada E descricao casar)
Passo "Remover usuario $PE"
$u = Get-LocalUser -Name $PE -ErrorAction SilentlyContinue
$descU = ($u -and $u.Description -eq $DESC_ESPERADA)
$provU = if ($prov) { Prov-Marca 'usuario_criado' } else { $descU }
if ($u -and $descU -and $provU) { Remove-LocalUser -Name $PE; Write-Host "  Usuario removido (proveniencia+descricao OK)." -ForegroundColor Green }
elseif ($u) { Write-Host "  Usuario PRESERVADO (proveniencia=$provU descricao=$descU) - pode ser conta sua." -ForegroundColor Yellow }
else { Write-Host "  Usuario nao existe." }

# 4. Pastas: so as que o manifesto registra como criadas por este roteiro, e so com -RemoverPastas
if ($RemoverPastas) {
  Passo "Remover pastas criadas por este roteiro (do manifesto)"
  $pastas = if ($prov -and $prov.pastas_criadas) { @($prov.pastas_criadas) } else { @() }
  if (-not $pastas.Count) { Write-Host "  Manifesto nao lista pastas criadas - nada removido." -ForegroundColor Yellow }
  foreach ($d in $pastas) { if (Test-Path $d) { Remove-Item $d -Recurse -Force; Write-Host "  removido: $d" } }
} else { Write-Host "`n(Use -RemoverPastas para apagar as pastas provadas no manifesto. CredDir pode conter a chave do PE.)" -ForegroundColor Yellow }

# 5. Manifesto (por ultimo; renomeia para .revertido em vez de apagar, como trilha)
if ($prov) {
  $rev = "$Manifesto.revertido-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
  try { Rename-Item -LiteralPath $Manifesto -NewName (Split-Path $rev -Leaf); Write-Host "  Manifesto marcado como revertido: $rev" -ForegroundColor Green } catch {}
}
Write-Host "`nReversao concluida." -ForegroundColor Green
