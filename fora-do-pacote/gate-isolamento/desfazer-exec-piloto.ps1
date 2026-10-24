<#
  REVERSAO do roteiro exec-piloto (GATE ISOLAMENTO DE PRINCIPAL) - V4-05 (Ato 117/118)
  Ato - Autonomous multi-LLM orchestration flow - 119

  ATENCAO:
  - Desfaz SOMENTE o que o roteiro-admin-exec-piloto criou: a tarefa agendada, os 3 direitos do PE,
    o usuario PE e as pastas do piloto. NAO toca em contas/tarefas/permissoes preexistentes.
  - Protecoes: so remove o usuario PE se a descricao for a que o roteiro grava (evita apagar conta homonima
    preexistente); pede confirmacao 'SIM'; grava um backup da politica (secedit) antes de alterar direitos.
  - Rode no Windows PowerShell 5.1 (powershell.exe) ELEVADO. Nada aqui libera execucao desassistida.
#>
[CmdletBinding()]
param(
  [string]$PE = 'exec-piloto',
  [string]$WorkRoot = 'C:\piloto-work',
  [string]$ConfigDir = 'C:\piloto-pe\cfg',
  [string]$CredDir   = 'C:\piloto-pe\cred',
  [string]$TaskName  = 'ExecPiloto_Executor',
  [string]$AcaoScript= 'C:\piloto-ctrl\acao-pe.ps1',
  [switch]$RemoverPastas      # so apaga as pastas se pedido explicitamente (podem conter a chave do PE)
)
$ErrorActionPreference = 'Stop'
$DESC_ESPERADA = 'PE do gate de isolamento - sem admin'
function Passo($m){ Write-Host "`n== $m" -ForegroundColor Cyan }
function Invoke-Secedit { & "$env:SystemRoot\System32\secedit.exe" @args | Out-Null; if ($LASTEXITCODE -ne 0) { throw "secedit falhou ($LASTEXITCODE)" } }

if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Rode no Windows PowerShell 5.1 (powershell.exe) ELEVADO.' }
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
      ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Rode ELEVADO (Administrador).' }
if ((Read-Host "Confirma a REVERSAO de '$PE' e da tarefa '$TaskName'? Digite SIM") -cne 'SIM') { throw 'Abortado.' }

$u = Get-LocalUser -Name $PE -ErrorAction SilentlyContinue
$peSid = if ($u) { $u.SID.Value } else { $null }

# 1. Tarefa agendada (remove so a nossa, pela descricao)
Passo "Remover tarefa $TaskName (se criada pelo roteiro)"
try {
  $svc = New-Object -ComObject 'Schedule.Service'; $svc.Connect(); $root = $svc.GetFolder('\')
  $t = $root.GetTask($TaskName)
  if ($t.Definition.RegistrationInfo.Description -eq 'Executor isolado (PE) - gate de isolamento') {
    $root.DeleteTask($TaskName, 0); Write-Host "  Tarefa removida." -ForegroundColor Green
  } else { Write-Host "  Tarefa existe mas NAO foi criada por este roteiro (descricao diferente) - preservada." -ForegroundColor Yellow }
} catch { Write-Host "  Tarefa nao encontrada - nada a remover." }

# 2. Direitos do PE (backup antes; remove so o SID do PE das 3 chaves)
if ($peSid) {
  Passo "Remover SeBatchLogonRight / negacoes de logon do PE (backup da politica antes)"
  $bkp = Join-Path $env:TEMP ("exec-piloto-backup-{0}.inf" -f (Get-Date -Format yyyyMMdd-HHmmss))
  Invoke-Secedit /export /cfg $bkp /quiet
  Write-Host "  Backup da politica: $bkp"
  $inf = Join-Path $env:TEMP 'exec-piloto-undo.inf'; $sdb = Join-Path $env:TEMP 'exec-piloto-undo.sdb'
  $txt = @(Get-Content $bkp)
  foreach ($r in 'SeBatchLogonRight','SeDenyInteractiveLogonRight','SeDenyRemoteInteractiveLogonRight') {
    for ($i=0; $i -lt $txt.Count; $i++) {
      if ($txt[$i] -match "^$r\s*=") {
        $itens = (($txt[$i] -split '=',2)[-1] -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne "*$peSid" }
        $txt[$i] = if ($itens) { "$r = " + ($itens -join ',') } else { "$r =" }
      }
    }
  }
  Set-Content -Path $inf -Value $txt -Encoding Unicode
  Invoke-Secedit /configure /db $sdb /cfg $inf /areas USER_RIGHTS /quiet
  Remove-Item $inf,$sdb -Force -ErrorAction SilentlyContinue
  Write-Host "  Direitos do PE removidos." -ForegroundColor Green
}

# 3. Usuario PE (so se descricao casar - nao apaga conta homonima preexistente)
Passo "Remover usuario $PE (so se criado pelo roteiro)"
if ($u -and $u.Description -eq $DESC_ESPERADA) {
  Remove-LocalUser -Name $PE; Write-Host "  Usuario removido." -ForegroundColor Green
} elseif ($u) {
  Write-Host "  Usuario existe mas descricao != esperada - PRESERVADO (pode ser conta sua)." -ForegroundColor Yellow
} else { Write-Host "  Usuario nao existe." }

# 4. Pastas (so com -RemoverPastas; CredDir pode conter a chave)
if ($RemoverPastas) {
  Passo "Remover pastas do piloto"
  foreach ($d in @($WorkRoot,$ConfigDir,$CredDir,(Split-Path $AcaoScript))) {
    if (Test-Path $d) { Remove-Item $d -Recurse -Force; Write-Host "  removido: $d" }
  }
} else { Write-Host "`n(Use -RemoverPastas para apagar $WorkRoot / C:\piloto-pe / C:\piloto-ctrl. CredDir pode conter a chave do PE.)" -ForegroundColor Yellow }
Write-Host "`nReversao concluida." -ForegroundColor Green
