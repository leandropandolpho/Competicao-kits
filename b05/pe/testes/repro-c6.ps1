# repro-c6.ps1 - reproducao DIRIGIDA do cenario C6-real (so a parte que falha) para diagnosticar o timing/tracking.
# Sobe o lancador-ponte com 'dorme:99' em background (como o C6-real), espera ~25s pelo LEASE VIVO e, se nao vier,
# SURFACE o exit code + stderr + stdout do launcher (+ lista a evidencia g1-*.json). Artefatos na pasta conectada.
$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$raiz=$PSScriptRoot; $Utf8=[Text.UTF8Encoding]::new($false)
$lanPs1=(Resolve-Path (Join-Path $raiz '..\lancador-ponte.ps1')).Path
$ctrlPath=(Resolve-Path (Join-Path $raiz '..\..\..\kits\kit-A\controlador.ps1')).Path
$Pw=(Get-Process -Id $PID).Path
$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$out=Join-Path (Split-Path $raiz) "repro-c6-$stamp.txt"
$Lg=New-Object System.Collections.Generic.List[string]
function Linha($s){ $Lg.Add([string]$s); Write-Host $s }
Linha "=== REPRO C6-real - $stamp UTC ==="

# ambiente inspecionavel na pasta conectada (ao lado deste repo)
$base=Join-Path (Split-Path $raiz) ("repro-lan-"+[guid]::NewGuid().ToString('N').Substring(0,8))
$repo=Join-Path $base 'repo'; $ctrl=Join-Path $base 'ctrl'; $estado=Join-Path $base 'estado'
New-Item -ItemType Directory -Force $repo,$ctrl,$estado | Out-Null
Push-Location $repo
try { & git init -q *>$null; & git config user.email t@t *>$null; & git config user.name t *>$null; & git config commit.gpgsign false *>$null
      [IO.File]::WriteAllText((Join-Path $repo 'codigo.txt'),"base`n",$Utf8); [IO.File]::WriteAllText((Join-Path $repo 'teste-marker.txt'),"t`n",$Utf8)
      & git add -A *>$null; & git commit -q -m base *>$null } finally { Pop-Location }
$taref=Join-Path $ctrl 'TAREFAS.json'
[IO.File]::WriteAllText($taref,(@{versao='1';tarefas=@(@{id='T1';titulo='T1';prompt='corrige';status='pending';tentativas=0;depends_on=@();critica=$false})}|ConvertTo-Json -Depth 6),$Utf8)
$trava=Join-Path $ctrl 'trava'

$psi=[System.Diagnostics.ProcessStartInfo]::new($Pw)
foreach($a in @('-NoProfile','-ExecutionPolicy','Bypass','-File',$lanPs1,'-RepoPath',$repo,'-CtrlDir',$ctrl,'-EstadoDir',$estado,
  '-TarefasPath',$taref,'-Controlador',$ctrlPath,'-TesteReal','exit 0','-PwshPortatil',$Pw,
  '-TimeoutControladorSeg','180','-TimeoutPonteSeg','60','-MaxTentativas','2')){ $psi.ArgumentList.Add($a) }
$psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.WorkingDirectory=$repo
$psi.Environment['B05FAKE_MODO']='dorme:99'; $psi.Environment['PATH']=(Split-Path $Pw)+';'+$psi.Environment['PATH']
$p=[System.Diagnostics.Process]::Start($psi)
$outT=$p.StandardOutput.ReadToEndAsync(); $errT=$p.StandardError.ReadToEndAsync()
Linha "launcher pid=$($p.Id); esperando lease vivo (ate 25s)..."
$entrou=$false; $tLease=0
for($i=0;$i -lt 50;$i++){ Start-Sleep -Milliseconds 500
  $nl=@(Get-ChildItem -LiteralPath $trava -Filter '*.lease' -EA SilentlyContinue).Count
  if((Test-Path $trava) -and $nl -ge 1){ $entrou=$true; $tLease=[math]::Round($i*0.5,1); break }
  if($p.HasExited){ break }
}
Linha "ENTROU (lease vivo)=$entrou em ${tLease}s   launcher_saiu=$($p.HasExited)"
if($p.HasExited){ Linha "launcher EXIT CODE=$($p.ExitCode)" }
# evidencia g1-*.json do launcher
$evid=Join-Path $ctrl 'evid'
$gs=@(Get-ChildItem -LiteralPath $evid -Filter 'g1-*.json' -EA SilentlyContinue)
Linha "evidencia g1-*.json: $($gs.Count) arquivo(s)"
foreach($g in $gs){ Linha ("  -> "+$g.Name+": "+((Get-Content -LiteralPath $g.FullName -Raw) -replace '\s+',' ')) }
# estado do PE
Linha "EstadoDir itens: $(@(Get-ChildItem -LiteralPath $estado -EA SilentlyContinue).Count)"
# encerra o launcher e a arvore
try{ & taskkill /PID $p.Id /T /F *>$null }catch{}
try{ $p.WaitForExit(8000)|Out-Null }catch{}
$so=$outT.Result; $se=$errT.Result
Linha ""; Linha "----- STDERR do launcher -----"; Linha ($se.Trim())
Linha ""; Linha "----- STDOUT do launcher (ultimas linhas) -----"
Linha (($so -split "`r?`n" | Select-Object -Last 15) -join "`n")
[IO.File]::WriteAllText($out,($Lg -join "`r`n"),$Utf8); Write-Host "RESULTADO: $out"
# limpeza best-effort do ambiente de repro
try{ Remove-Item -Recurse -Force $base -EA SilentlyContinue }catch{}
