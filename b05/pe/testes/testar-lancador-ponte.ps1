# testar-lancador-ponte.ps1 - LANCADOR do modo PRINCIPAL-ISOLADO (R-01 / RC-6b / PU-11b). gate-pe. Ato 150.
# Prova o guarda externo PRE-CONTROLADOR pedido pelo ChatGPT/Perplexity no Ato 149, como SCRIPT COMPLEMENTAR EXTERNO
# (lancador-ponte.ps1/.cmd) que NAO altera uma linha dos artefatos hasheados em c980c2f (controlador 7cd7864,
# claude-ponte, despachante, nucleo B-05): a selecao continua 100% externa por -ClaudeCmd/-TestCmd.
# Cenarios (nomes proprios L-*):
#  L-OK    sem lease: lancador grava config IMUTAVEL (CreateNew+readonly) com hashes_nucleo, sobe o controlador -> commit.
#  L-TRV   trava persistente (financeira) presente -> lancador NAO sobe o controlador (exit 26), estado intacto.
#  PU-11b  lease de SUBARVORE VIVA (sobrevivente real anterior) -> lancador sai 22, controlador NAO sobe, sem git/rollback.
#  C6-real encerramento ABRUPTO do controlador em tarefa in_progress -> nenhum commit; 2o lancador retoma apos liberacao
#          segura (lease morto conferido e limpo no pre-flight) -> commit, custo preservado.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$raiz = $PSScriptRoot
$lanPs1   = (Resolve-Path (Join-Path $raiz '..\lancador-ponte.ps1')).Path
$acao     = (Resolve-Path (Join-Path $raiz '..\acao-pe.ps1')).Path
$ctrlPath = (Resolve-Path (Join-Path $raiz '..\..\..\kits\kit-A\controlador.ps1')).Path
. (Resolve-Path (Join-Path $raiz '..\ponte-pu.ps1')).Path   # PU-Lease-Gravar / PU-Subarvore-Morta / PU-Gravar-Trava / Razao-*
$Pw = (Get-Process -Id $PID).Path
$Utf8 = [Text.UTF8Encoding]::new($false)
$ok = 0; $tot = 0
function Checar($n,[bool]$c,[string]$d=''){ $script:tot++; if($c){ $script:ok++; "[ok] $n" } else { "[FALHA] $n $d" } }
if (-not $IsWindows) { "LANCADOR: so Windows."; exit 0 }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { "LANCADOR: git ausente - pulado."; exit 0 }

function Novo-Amb([string]$testeReal='exit 0') {
  # Raiz dos ambientes: TEMP por padrao; B05_LAN_BASE permite apontar para uma pasta inspecionavel (ex.: pasta conectada),
  # util para auditar os artefatos do teste (estado/log.jsonl, razao) sem depender de acesso ao TEMP.
  $raizBase = if ($env:B05_LAN_BASE) { $env:B05_LAN_BASE } else { $env:TEMP }
  $base = Join-Path $raizBase ('lan-' + [guid]::NewGuid().ToString('N').Substring(0,8))
  $repo = Join-Path $base 'repo'; $ctrl = Join-Path $base 'ctrl'; $estado = Join-Path $base 'estado'
  New-Item -ItemType Directory -Force $repo,$ctrl,$estado | Out-Null
  Push-Location $repo
  try {
    & git init -q *>$null; & git config user.email t@t *>$null; & git config user.name t *>$null; & git config commit.gpgsign false *>$null
    [IO.File]::WriteAllText((Join-Path $repo 'codigo.txt'), "base`n", $Utf8)
    [IO.File]::WriteAllText((Join-Path $repo 'teste-marker.txt'), "t`n", $Utf8)
    & git add -A *>$null; & git commit -q -m base *>$null
  } finally { Pop-Location }
  $taref = Join-Path $ctrl 'TAREFAS.json'
  [IO.File]::WriteAllText($taref, (@{ versao='1'; tarefas=@(@{ id='T1'; titulo='Tarefa 1'; prompt='corrige'; status='pending'; tentativas=0; depends_on=@(); critica=$false }) } | ConvertTo-Json -Depth 6), $Utf8)
  # trava/ponte/evid sao criadas pelo lancador (irmas de ctrl)
  return [pscustomobject]@{ Base=$base; Repo=$repo; Ctrl=$ctrl; Estado=$estado; Taref=$taref; Trava=(Join-Path $ctrl 'trava') }
}
# Sobe o lancador. Devolve o Process (vivo se bg) + head base. $Bg=$true nao espera (para o C6 matar no meio).
function Rodar-Lancador($amb,[string]$modo,[int]$tmoCtrl=180,[int]$tmoPonte=60,[int]$maxTent=2,[switch]$Bg,[string]$PwshOverride,[string]$ManifestoOverride) {
  $headBase = (& git -C $amb.Repo rev-parse HEAD).Trim()
  $pwUsar = if ($PwshOverride) { $PwshOverride } else { $Pw }
  $psi = [System.Diagnostics.ProcessStartInfo]::new($Pw)
  foreach ($a in @('-NoProfile','-ExecutionPolicy','Bypass','-File',$lanPs1,
      '-RepoPath',$amb.Repo,'-CtrlDir',$amb.Ctrl,'-EstadoDir',$amb.Estado,'-TarefasPath',$amb.Taref,
      '-Controlador',$ctrlPath,'-TesteReal',$testeReal_,'-PwshPortatil',$pwUsar,
      '-TimeoutControladorSeg',[string]$tmoCtrl,'-TimeoutPonteSeg',[string]$tmoPonte,'-MaxTentativas',[string]$maxTent)) { $psi.ArgumentList.Add($a) }
  $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.WorkingDirectory=$amb.Repo
  $psi.Environment['B05FAKE_MODO']=$modo
  if ($ManifestoOverride) { $psi.Environment['B05_MANIFESTO_NUCLEO']=$ManifestoOverride }
  $psi.Environment['PATH']=(Split-Path $Pw) + ';' + $psi.Environment['PATH']
  $p=[System.Diagnostics.Process]::Start($psi)
  $outT=$p.StandardOutput.ReadToEndAsync(); $errT=$p.StandardError.ReadToEndAsync()
  if ($Bg) { return @{ Proc=$p; HeadBase=$headBase; OutT=$outT; ErrT=$errT } }
  $estourou = -not $p.WaitForExit(($tmoCtrl+90)*1000)
  if ($estourou) { try { $p.Kill($true) } catch {} }
  $cod = if ($estourou) { -1 } else { $p.ExitCode }
  return @{ Codigo=$cod; HeadBase=$headBase; HeadAgora=(& git -C $amb.Repo rev-parse HEAD).Trim(); Saida=$outT.Result; Erro=$errT.Result }
}
$testeReal_ = 'exit 0'
function Custo($amb) { $r = Razao-Ler $amb.Ctrl; if (-not $r.Ok) { return -1 }; (Razao-Contabilizar $r.Eventos 0.25).Total }
function LeasesVivos($amb) { @(Get-ChildItem -LiteralPath $amb.Trava -Filter '*.lease' -EA SilentlyContinue).Count }

"== L-OK: sem lease -> lancador grava config imutavel (hashes_nucleo) e sobe o controlador -> commit (done)"
$aOK = Novo-Amb
$rOK = Rodar-Lancador $aOK 'ok:0.20'
$cfgOK = Get-ChildItem -LiteralPath $aOK.Ctrl -Filter 'config-*.json' -EA SilentlyContinue | Select-Object -First 1
$cfgRO = $false; $cfgTemHash = $false
if ($cfgOK) { $cfgRO = (Get-Item $cfgOK.FullName).IsReadOnly; $co = Get-Content $cfgOK.FullName -Raw | ConvertFrom-Json; $cfgTemHash = ($co.PSObject.Properties['hashes_nucleo'] -and $co.hashes_nucleo.PSObject.Properties['razao.ps1']) }
Checar 'L-OK: lancador saiu 0 (controlador done)' ($rOK.Codigo -eq 0) "cod=$($rOK.Codigo) err=$($rOK.Erro)"
Checar 'L-OK: commit efetivado (HEAD avancou)' ($rOK.HeadAgora -ne $rOK.HeadBase)
Checar 'L-OK: config gravada IMUTAVEL (somente-leitura)' ($cfgRO)
Checar 'L-OK: config traz hashes_nucleo completo (R-04)' ($cfgTemHash)

"== L-TRV: trava persistente (financeira 28) presente -> lancador NAO sobe o controlador (exit 26)"
$aTRV = Novo-Amb
New-Item -ItemType Directory -Force $aTRV.Trava | Out-Null
PU-Gravar-Trava $aTRV.Trava 'financeira' 'teste L-TRV' 'exec-x'
$rTRV = Rodar-Lancador $aTRV 'ok:0.20'
Checar 'L-TRV: lancador recusou subir, preservando 28 (financeira)' ($rTRV.Codigo -eq 28) "cod=$($rTRV.Codigo)"
Checar 'L-TRV: controlador NAO comitou (HEAD=base)' ($rTRV.HeadAgora -eq $rTRV.HeadBase)
Checar 'L-TRV: EstadoDir vazio (controlador nem iniciou)' (@(Get-ChildItem -LiteralPath $aTRV.Estado -EA SilentlyContinue).Count -eq 0)

"== L-PWSH (C4-F02, Ato 153): lancador com pwsh NAO aprovado (SHA diverge) -> recusa (31), controlador NAO sobe"
$aPW = Novo-Amb
$rPW = Rodar-Lancador $aPW 'ok:0.20' -PwshOverride $env:ComSpec   # cmd.exe: existe, nao-MSIX, SHA != aprovado
Checar 'L-PWSH: pwsh nao aprovado -> exit 31' ($rPW.Codigo -eq 31) "cod=$($rPW.Codigo) err=$($rPW.Erro)"
Checar 'L-PWSH: controlador NAO comitou (HEAD=base)' ($rPW.HeadAgora -eq $rPW.HeadBase)
Checar 'L-PWSH: EstadoDir vazio (nem iniciou)' (@(Get-ChildItem -LiteralPath $aPW.Estado -EA SilentlyContinue).Count -eq 0)

"== L-MANIF (C4-F03, Ato 153): nucleo diverge do MANIFESTO APROVADO -> FATAL (97), controlador NAO sobe"
$aMN = Novo-Amb
$manifReal = (Resolve-Path (Join-Path $raiz '..\hashes-nucleo-aprovado.json')).Path
$manObj = Get-Content -LiteralPath $manifReal -Raw | ConvertFrom-Json
$manObj.'razao.ps1' = '0000000000000000000000000000000000000000000000000000000000000000'   # força divergência
$manBad = Join-Path $aMN.Base 'manifesto-divergente.json'
[IO.File]::WriteAllText($manBad, ($manObj | ConvertTo-Json -Depth 5), $Utf8)
$rMN = Rodar-Lancador $aMN 'ok:0.20' -ManifestoOverride $manBad
Checar 'L-MANIF: nucleo diverge do manifesto aprovado -> exit 97' ($rMN.Codigo -eq 97) "cod=$($rMN.Codigo) err=$($rMN.Erro)"
Checar 'L-MANIF: controlador NAO comitou (HEAD=base)' ($rMN.HeadAgora -eq $rMN.HeadBase)

"== PU-11b: lease de SUBARVORE VIVA -> lancador sai 22, controlador NAO sobe, sem git/rollback"
$aLV = Novo-Amb
New-Item -ItemType Directory -Force $aLV.Trava | Out-Null
[IO.File]::WriteAllText((Join-Path $aLV.Repo 'sobrevivente.txt'), "nao-rastreado`n", $Utf8)   # untracked: um rollback o removeria
$ping = [System.Diagnostics.Process]::Start((New-Object System.Diagnostics.ProcessStartInfo -Property @{ FileName=$env:ComSpec; Arguments='/c ping -n 90 127.0.0.1 > nul'; UseShellExecute=$false; CreateNoWindow=$true }))
$pPid=[uint32]$ping.Id; $pCri=0L; try { $pCri=[B05LowIL]::CriacaoUtc($ping.Handle) } catch {}
PU-Lease-Gravar $aLV.Trava 'exec-sobrevivente' $pPid $pCri
$rLV = Rodar-Lancador $aLV 'ok:0.20'
$vivoAindaMarcado = (LeasesVivos $aLV) -ge 1
try { if (-not $ping.HasExited) { $ping.Kill($true) } } catch {}
Checar 'PU-11b: lancador saiu 22 (guarda anti-orfao vivo)' ($rLV.Codigo -eq 22) "cod=$($rLV.Codigo) err=$($rLV.Erro)"
Checar 'PU-11b: controlador NAO subiu (HEAD=base, sem rollback)' ($rLV.HeadAgora -eq $rLV.HeadBase)
Checar 'PU-11b: arquivo nao-rastreado PRESERVADO (nenhum git reset ocorreu)' (Test-Path (Join-Path $aLV.Repo 'sobrevivente.txt'))
Checar 'PU-11b: EstadoDir vazio (controlador nem iniciou)' (@(Get-ChildItem -LiteralPath $aLV.Estado -EA SilentlyContinue).Count -eq 0)
Checar 'PU-11b: lease do vivo NAO foi removido (nao limpa lease vivo)' ($vivoAindaMarcado)

# Encerra, de forma DETERMINISTICA, a subarvore de cada lease remanescente (nao depende do taskkill /T alcancar o PE do
# Job Object) e confirma a morte antes de prosseguir. Devolve o nro de leases cuja subarvore ficou comprovadamente morta.
function Reapar-Leases($amb) {
  $mortos = 0
  foreach ($lf in @(Get-ChildItem -LiteralPath $amb.Trava -Filter '*.lease' -EA SilentlyContinue)) {
    try { $ls = Get-Content -LiteralPath $lf.FullName -Raw | ConvertFrom-Json } catch { continue }
    try { & taskkill /PID ([int]$ls.pid) /T /F *>$null } catch {}
    try { PU-Encerrar-Subarvore ([uint32]$ls.pid) ([long]$ls.criacao) | Out-Null } catch {}
    Start-Sleep -Milliseconds 500
    if ((PU-Subarvore-Morta ([uint32]$ls.pid) ([long]$ls.criacao)).Morta) { $mortos++ }
  }
  return $mortos
}

"== C6-real: encerramento ABRUPTO em tarefa in_progress -> nenhum commit; 2o lancador RETOMA com SEGURANCA (commit limpo XOR fail-close D-06)"
$aC6 = Novo-Amb
$bg = Rodar-Lancador $aC6 'dorme:99' 180 60 2 -Bg
# espera o PE entrar em execucao (lease vivo gravado pela ponte em N-08). Janela ate ~50s: com o Job de supervisao
# do G1 (C4-F01) o startup do controlador ganha alguns segundos (repro-c6: lease ~23.5s isolado; mais sob a carga da
# matriz), e a antiga janela de 25s ficava na borda. 50s segue bem abaixo do TimeoutControladorSeg (180s). Nada de
# contencao muda: o spike gate-lowil comprovou que o executor herda o Job e Verificar nao o flagra.
$entrou = $false
for ($i=0; $i -lt 100; $i++) { Start-Sleep -Milliseconds 500; if ((Test-Path $aC6.Trava) -and (LeasesVivos $aC6) -ge 1) { $entrou = $true; break } }
# morte ABRUPTA: mata a arvore do lancador E garante a morte da subarvore do PE do Job (determinismo, nao depende do /T).
try { & taskkill /PID $bg.Proc.Id /T /F *>$null } catch {}
try { $bg.Proc.WaitForExit(10000) | Out-Null } catch {}
$reapados = Reapar-Leases $aC6
$headPosMorte = (& git -C $aC6.Repo rev-parse HEAD).Trim()
$leaseRemanesc = (LeasesVivos $aC6) -ge 1
Checar 'C6-real: PE chegou a executar (lease vivo gravado antes da morte)' ($entrou)
Checar 'C6-real: morte abrupta NAO deixou commit (HEAD=base)' ($headPosMorte -eq $bg.HeadBase)
Checar 'C6-real: subarvore do PE confirmada MORTA e lease remanescente p/ a retomada conferir' ($reapados -ge 1 -and $leaseRemanesc)
# C6-complemento (ChatGPT Ato 153): confirmar que T1 estava in_progress NO momento da morte (ler ANTES da retomada
# sobrescrever o TAREFAS.json). Prova que a interrupcao atingiu uma tarefa de fato em andamento.
$docMorte = try { Get-Content -LiteralPath $aC6.Taref -Raw | ConvertFrom-Json } catch { $null }
$t1Morte = if ($docMorte) { @($docMorte.tarefas | Where-Object { $_.id -eq 'T1' })[0] } else { $null }
Checar 'C6-real: T1 estava in_progress na morte (tentativas>=1)' ($t1Morte -and "$($t1Morte.status)" -eq 'in_progress' -and [int]$t1Morte.tentativas -ge 1) "status=$($t1Morte.status) tent=$($t1Morte.tentativas)"
# 2a subida: o pre-flight confere a morte do lease (subarvore morta), limpa e o controlador RETOMA a T1. A invariante de
# R-01/RC-6b e a SEGURANCA da retomada, nao uma liveness obrigatoria: ou o despacho conclui limpo e commita, OU o despacho
# fica indeterminado (race morte/fim.flag em HW restrito) e o controlador FAIL-CLOSE (D-06 c: reserva mantida, SEM commit).
# Os dois sao corretos; o proibido e commit corrompido/parcial ou tarefa presa em in_progress.
Start-Sleep -Seconds 1
$rC6b = Rodar-Lancador $aC6 'ok:0.20' 180 60 3
$commitLimpo = ($rC6b.Codigo -eq 0 -and $rC6b.HeadAgora -ne $bg.HeadBase)
$failClose   = ($rC6b.Codigo -ne 0 -and $rC6b.HeadAgora -eq $bg.HeadBase)   # fail-close: nenhum commit
Checar 'C6-real: retomada SEGURA (commit limpo XOR fail-close sem commit; nunca corrompe)' ($commitLimpo -or $failClose) "cod=$($rC6b.Codigo) avancou=$($rC6b.HeadAgora -ne $bg.HeadBase)"
$docC6 = Get-Content -LiteralPath $aC6.Taref -Raw | ConvertFrom-Json
$t1C6 = @($docC6.tarefas | Where-Object { $_.id -eq 'T1' })[0]
Checar 'C6-real: tarefa em estado TERMINAL (done/failed), nunca presa em in_progress' ("$($t1C6.status)" -in @('done','failed')) "status=$($t1C6.status)"
Checar 'C6-real: lease morto foi limpo no pre-flight (sem lease ao fim)' ((LeasesVivos $aC6) -eq 0)
Checar 'C6-real: custo do razao preservado (> 0 apos retomada; reserva mantida se fail-close)' ((Custo $aC6) -gt 0) "custo=$(Custo $aC6)"
# C6-complemento: integridade do estado Git apos a retomada (ChatGPT Ato 153).
$arvoreLimpa = [string]::IsNullOrWhiteSpace((& git -C $aC6.Repo status --porcelain))
Checar 'C6-real: arvore de trabalho LIMPA apos a retomada (sem resto nao-commitado)' ($arvoreLimpa)
if ($commitLimpo) {
  $temNotas = (@(& git -C $aC6.Repo ls-tree -r --name-only HEAD) -contains 'notas.txt')
  Checar 'C6-real: commit limpo -> conteudo integro (notas.txt no HEAD, criado pela retomada)' ($temNotas)
} else {
  Checar 'C6-real: fail-close -> SEM commit (HEAD=base) e reserva mantida no razao' (($rC6b.HeadAgora -eq $bg.HeadBase) -and ((Custo $aC6) -gt 0))
}

"`nTOTAL LANCADOR: $ok / $tot"
exit ([int]($ok -ne $tot))
