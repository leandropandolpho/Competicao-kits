# testar-pe.ps1 - bateria SIMULADA do embrulho do PE (acao-pe.ps1). Roda sob Windows/pwsh7 (usa [B05Job]).
# Nao exige a conta exec-piloto: valida a logica de ponte/Job/orfaos/timeout com o fake-executor no caminho -Simular.
# Ato 121. Nao escreve estado do PU. Sondas N1-N17 reais (sob o PE) virao depois da conta provisionada.
param([string]$PwshAprovado = (Get-Process -Id $PID).Path)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$raiz = $PSScriptRoot
$acao = (Resolve-Path (Join-Path $raiz '..\acao-pe.ps1')).Path
$fake = (Resolve-Path (Join-Path $raiz '..\..\testes\fake-executor.ps1')).Path
$shaPwsh = (Get-FileHash -LiteralPath $PwshAprovado -Algorithm SHA256).Hash
$ok = 0; $tot = 0
function Checar($nome,[bool]$cond,[string]$detalhe=''){ $script:tot++; if($cond){ $script:ok++; "[ok] $nome" } else { "[FALHA] $nome $detalhe" } }

function Nova-Execucao([string]$modo,[string]$testCmd='') {
  $base = Join-Path $env:TEMP ('pe-teste-' + [guid]::NewGuid().ToString('N').Substring(0,8))
  $ponte = Join-Path $base 'ponte'; $trab = Join-Path $base 'trabalho'
  New-Item -ItemType Directory -Force $ponte,$trab | Out-Null
  $id = [guid]::NewGuid().ToString('N'); $dir = Join-Path $ponte $id; New-Item -ItemType Directory -Force $dir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dir 'prompt.in'), 'faca a tarefa', [Text.UTF8Encoding]::new($false))
  $ped = [ordered]@{ exec_id=$id; executor=$PwshAprovado; executor_prefixo=("-NoProfile|-File|$fake"); test_cmd=$testCmd; teto_usd=0.5; pwsh_sha256=$shaPwsh; criado_em=(Get-Date).ToString('o') }
  [System.IO.File]::WriteAllText((Join-Path $dir 'pedido.json'), ($ped|ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText((Join-Path $dir 'go.flag'), '1', [Text.UTF8Encoding]::new($false))
  return [pscustomobject]@{ Base=$base; Ponte=$ponte; Trab=$trab; Id=$id; Dir=$dir }
}
function Rodar($a,[string[]]$extra=@()) {
  $env:B05FAKE_DIR = Join-Path $a.Base 'fake'
  Push-Location $a.Trab
  try { & $PwshAprovado -NoProfile -File $acao -PonteDir $a.Ponte -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Simular -TimeoutSeg 60 @extra 2>&1 | Out-Null; $code=$LASTEXITCODE }
  catch { $code = 99 }
  finally { Pop-Location; Remove-Item Env:B05FAKE_DIR -ErrorAction SilentlyContinue }
  return $code
}

"== PE-S1: execucao normal (ok:0.30) -> stdout.json/exit.code/fim.flag, em_job verdadeiro, sem razao"
$a = Nova-Execucao 'ok:0.30'
$env:B05FAKE_MODO = 'ok:0.30'
$code = Rodar $a
Remove-Item Env:B05FAKE_MODO -ErrorAction SilentlyContinue
Checar 'PE-S1: acao-pe saiu 0' ($code -eq 0) "codigo $code"
Checar 'PE-S1: stdout.json existe' (Test-Path (Join-Path $a.Dir 'stdout.json'))
Checar 'PE-S1: exit.code existe' (Test-Path (Join-Path $a.Dir 'exit.code'))
Checar 'PE-S1: fim.flag existe' (Test-Path (Join-Path $a.Dir 'fim.flag'))
if (Test-Path (Join-Path $a.Dir 'stdout.json')) {
  $j = Get-Content (Join-Path $a.Dir 'stdout.json') -Raw | ConvertFrom-Json
  Checar 'PE-S1: stdout tem result do executor' ("$($j.result)" -eq 'feito') "result=$($j.result)"
  Checar 'PE-S1: custo 0.30 preservado na saida bruta' ([double]$j.total_cost_usd -eq 0.30)
}
if (Test-Path (Join-Path $a.Dir 'pe.pid')) {
  $pp = Get-Content (Join-Path $a.Dir 'pe.pid') -Raw | ConvertFrom-Json
  Checar 'PE-S1: em_job verdadeiro (contido pelo Job herdado)' ($pp.em_job -eq $true) "em_job=$($pp.em_job)"
}
Checar 'PE-S1: PE nao gravou razao nem TAREFAS (nenhum fora da pasta-ponte)' (-not (Test-Path (Join-Path $a.Base 'razao.jsonl')))

"== PE-S2: $TestCmd roda sob o PE DEPOIS do executor (teste.txt com codigo)"
$a2 = Nova-Execucao 'ok:0.10' 'Write-Output ("TESTE-PE ok " + $env:USERNAME); exit 0'
$env:B05FAKE_MODO = 'ok:0.10'
$code2 = Rodar $a2
Remove-Item Env:B05FAKE_MODO -ErrorAction SilentlyContinue
Checar 'PE-S2: teste.txt existe' (Test-Path (Join-Path $a2.Dir 'teste.txt'))
if (Test-Path (Join-Path $a2.Dir 'teste.txt')) {
  $t = Get-Content (Join-Path $a2.Dir 'teste.txt') -Raw
  Checar 'PE-S2: teste rodou sob o PE e saiu 0' ($t -match 'TESTE-PE ok' -and $t -match 'codigo=0') "t=$t"
}

"== PE-S3: ADM-V5-02 - pwsh com SHA errado -> falha fechada (nao roda)"
$a3 = Nova-Execucao 'ok:0.10'
Push-Location $a3.Trab
try { & $PwshAprovado -NoProfile -File $acao -PonteDir $a3.Ponte -PwshAprovado $PwshAprovado -PwshSha256 ('0'*64) -Simular 2>&1 | Out-Null; $c3=$LASTEXITCODE } catch { $c3=99 } finally { Pop-Location }
Checar 'PE-S3: SHA divergente bloqueia (codigo != 0, sem fim.flag)' ($c3 -ne 0 -and -not (Test-Path (Join-Path $a3.Dir 'fim.flag'))) "codigo $c3"

"== PE-S4: timeout mata o job (dorme > timeout) -> acao-pe falha, sem fim.flag"
$a4 = Nova-Execucao 'dorme:30'
$env:B05FAKE_MODO = 'dorme:30'
Push-Location $a4.Trab
try { & $PwshAprovado -NoProfile -File $acao -PonteDir $a4.Ponte -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Simular -TimeoutSeg 3 2>&1 | Out-Null; $c4=$LASTEXITCODE } catch { $c4=99 } finally { Pop-Location; Remove-Item Env:B05FAKE_MODO -ErrorAction SilentlyContinue }
Checar 'PE-S4: timeout bloqueia (codigo != 0, sem fim.flag)' ($c4 -ne 0 -and -not (Test-Path (Join-Path $a4.Dir 'fim.flag'))) "codigo $c4"

"== PE-S5 (PE-F05): falha vira estado terminal (falhou.flag) e NAO e reselecionada"
$a5 = Nova-Execucao 'ok:0.10'
# executor inexistente -> Processar lanca -> Tratar grava falhou.flag (terminal)
$ped5 = Get-Content (Join-Path $a5.Dir 'pedido.json') -Raw | ConvertFrom-Json
$ped5.executor = 'executor-inexistente-xyz.exe'; ($ped5|ConvertTo-Json -Compress) | Set-Content (Join-Path $a5.Dir 'pedido.json')
Push-Location $a5.Trab
try { & $PwshAprovado -NoProfile -File $acao -PonteDir $a5.Ponte -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Simular 2>&1 | Out-Null } catch {} finally { Pop-Location }
Checar 'PE-S5: falhou.flag gravado (terminal)' (Test-Path (Join-Path $a5.Dir 'falhou.flag'))
Checar 'PE-S5: sem fim.flag' (-not (Test-Path (Join-Path $a5.Dir 'fim.flag')))
# 2a passada na MESMA ponte: a execucao falha nao e reselecionada -> acao-pe nao acha pendente (sai != 0 por 'nenhuma pendente')
Push-Location $a5.Trab
try { & $PwshAprovado -NoProfile -File $acao -PonteDir $a5.Ponte -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Simular 2>&1 | Out-Null; $c5=$LASTEXITCODE } catch { $c5=99 } finally { Pop-Location }
Checar 'PE-S5: 2a passada nao reprocessa a falha (nenhuma pendente)' ($c5 -ne 0 -and -not (Test-Path (Join-Path $a5.Dir 'fim.flag')))

"== PE-S6 (PE-F09): TestCmd com exit!=0 vira estado terminal (falhou.flag, sem fim.flag)"
$a6 = Nova-Execucao 'ok:0.10' 'exit 1'
$env:B05FAKE_MODO = 'ok:0.10'
$c6 = Rodar $a6
Remove-Item Env:B05FAKE_MODO -ErrorAction SilentlyContinue
Checar 'PE-S6: TestCmd reprovado -> falhou.flag, sem fim.flag' ((Test-Path (Join-Path $a6.Dir 'falhou.flag')) -and -not (Test-Path (Join-Path $a6.Dir 'fim.flag'))) "codigo $c6"
Checar 'PE-S6: teste.txt registrado (codigo=1) como evidencia' ((Test-Path (Join-Path $a6.Dir 'teste.txt')) -and ((Get-Content (Join-Path $a6.Dir 'teste.txt') -Raw) -match 'codigo=1'))

# ---- Casos REAIS (Low IL): so no Windows. Executor fake rodado em baixa integridade; arvore de trabalho rotulada Low. ----
if ($IsWindows) {
  function Real($a,[int]$to=60){ & icacls $a.Trab /setintegritylevel '(OI)(CI)low' /Q 2>&1 | Out-Null
    Push-Location $a.Trab
    try { & $PwshAprovado -NoProfile -File $acao -PonteDir $a.Ponte -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -TimeoutSeg $to 2>&1 | Out-Null; $c=$LASTEXITCODE } catch { $c=99 } finally { Pop-Location }
    return $c }

  "== PE-R1 (real): executor em Low IL -> nivel_il 4096, em_job, fim.flag"
  $r1 = Nova-Execucao 'ok:0.20'; $env:B05FAKE_MODO='ok:0.20'; $cr1 = Real $r1; Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue
  Checar 'PE-R1: acao-pe saiu 0' ($cr1 -eq 0) "codigo $cr1"
  Checar 'PE-R1: fim.flag existe' (Test-Path (Join-Path $r1.Dir 'fim.flag'))
  if (Test-Path (Join-Path $r1.Dir 'pe.pid')) { $pp=Get-Content (Join-Path $r1.Dir 'pe.pid') -Raw|ConvertFrom-Json
    Checar 'PE-R1: executor em nivel 4096 (Low IL real)' ($pp.nivel_il -eq 4096) "nivel=$($pp.nivel_il)"
    Checar 'PE-R1: em_job verdadeiro' ($pp.em_job -eq $true) "em_job=$($pp.em_job)" }

  "== PE-R2 (real, PE-F01): timeout real -> EsperarSinal detecta, falhou.flag, SEM fim.flag (acao-pe sobrevive)"
  $r2 = Nova-Execucao 'dorme:20'; $env:B05FAKE_MODO='dorme:20'; $cr2 = Real $r2 3; Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue
  Checar 'PE-R2: timeout real -> falhou.flag (terminal)' (Test-Path (Join-Path $r2.Dir 'falhou.flag'))
  Checar 'PE-R2: sem fim.flag' (-not (Test-Path (Join-Path $r2.Dir 'fim.flag')))

  "== PE-R3 (real, PE-F02): `$TestCmd roda sob o PE em Low IL (nivel 4096)"
  $r3 = Nova-Execucao 'ok:0.10' 'Write-Output ok; exit 0'; $env:B05FAKE_MODO='ok:0.10'; $cr3 = Real $r3; Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue
  Checar 'PE-R3: teste.txt com nivel=4096 (teste em Low IL)' ((Test-Path (Join-Path $r3.Dir 'teste.txt')) -and ((Get-Content (Join-Path $r3.Dir 'teste.txt') -Raw) -match 'nivel=4096')) "t=$(if(Test-Path (Join-Path $r3.Dir 'teste.txt')){Get-Content (Join-Path $r3.Dir 'teste.txt') -Raw})"

  # PE-R4 (Ato 122 / PE-F03): rejeicao de processo sobrevivente = ausencia de orfaos apos encerramento normal/falha/timeout.
  # Determinstico (ChatGPT): executor legitimo gera um neto DENTRO do job; prova por identidade PID+criacao que o neto
  # NAO sobrevive ao fim do acao-pe. fim.flag NAO e aceito como prova de termino (a morte do neto e checada externamente).
  function NetoVivo($trab,[ref]$pidOut) {
    $pidOut.Value = 0
    $f = Join-Path $trab 'neto-pid.txt'; if (-not (Test-Path $f)) { return $null }   # null = sem registro (falha de setup)
    if ((Get-Content $f -Raw) -notmatch '^(\d+)\|(\d+)$') { return $null }
    $np = [int]$Matches[1]; $nt = [long]$Matches[2]; $pidOut.Value = $np
    Start-Sleep -Seconds 2
    $pp = Get-Process -Id $np -ErrorAction SilentlyContinue
    return ($pp -and $pp.StartTime.ToUniversalTime().Ticks -eq $nt)   # $true = MESMO processo ainda vivo (orfao)
  }

  "== PE-R4a (real): sem orfao apos encerramento NORMAL (neto no job morre com KILL_ON_JOB_CLOSE)"
  $r4 = Nova-Execucao 'neto:60:0:0'; $env:B05FAKE_MODO='neto:60:0:0'; $cr4 = Real $r4; Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue
  Checar 'PE-R4a: acao-pe saiu 0 e fim.flag existe' ($cr4 -eq 0 -and (Test-Path (Join-Path $r4.Dir 'fim.flag'))) "codigo $cr4"
  $p4 = 0; $v4 = NetoVivo $r4.Trab ([ref]$p4)
  Checar 'PE-R4a: neto (PID+criacao) NAO sobrevive ao encerramento normal' ($p4 -gt 0 -and $v4 -eq $false) "netoPid=$p4 vivo=$v4"

  "== PE-R4b (real): sem orfao apos TIMEOUT (TerminateJobObject mata toda a arvore)"
  $r5 = Nova-Execucao 'neto:60:20:0'; $env:B05FAKE_MODO='neto:60:20:0'; $cr5 = Real $r5 3; Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue
  Checar 'PE-R4b: timeout -> falhou.flag, sem fim.flag' ((Test-Path (Join-Path $r5.Dir 'falhou.flag')) -and -not (Test-Path (Join-Path $r5.Dir 'fim.flag')))
  $p5 = 0; $v5 = NetoVivo $r5.Trab ([ref]$p5)
  Checar 'PE-R4b: neto NAO sobrevive ao timeout' ($p5 -gt 0 -and $v5 -eq $false) "netoPid=$p5 vivo=$v5"

  "== PE-R4c (real): sem orfao apos FALHA do executor (exit!=0), codigo preservado"
  $r6 = Nova-Execucao 'neto:60:0:7'; $env:B05FAKE_MODO='neto:60:0:7'; $cr6 = Real $r6; Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue
  Checar 'PE-R4c: exit.code preserva 7 e fim.flag existe' ((Test-Path (Join-Path $r6.Dir 'exit.code')) -and ((Get-Content (Join-Path $r6.Dir 'exit.code') -Raw).Trim() -eq '7') -and (Test-Path (Join-Path $r6.Dir 'fim.flag')))
  $p6 = 0; $v6 = NetoVivo $r6.Trab ([ref]$p6)
  Checar 'PE-R4c: neto NAO sobrevive a falha do executor' ($p6 -gt 0 -and $v6 -eq $false) "netoPid=$p6 vivo=$v6"

  "== PE-S7 (PE-F10): rastreamento indisponivel bloqueia (fail-closed); executor NAO roda"
  $r7 = Nova-Execucao 'ok:0.20'; $env:B05FAKE_MODO='ok:0.20'; $env:PE_TESTE_RASTREAR_FALHA='1'
  $cr7 = Real $r7; Remove-Item Env:B05FAKE_MODO, Env:PE_TESTE_RASTREAR_FALHA -EA SilentlyContinue
  Checar 'PE-S7: falhou.flag, sem fim.flag' ((Test-Path (Join-Path $r7.Dir 'falhou.flag')) -and -not (Test-Path (Join-Path $r7.Dir 'fim.flag')))
  Checar 'PE-S7: executor bloqueado antes de executar (sem stdout.json)' (-not (Test-Path (Join-Path $r7.Dir 'stdout.json')))

  "== PE-S8 (PE-F07): falha de associacao ao Job bloqueia ANTES de executar (suspenso encerrado)"
  $r8 = Nova-Execucao 'ok:0.20'; $env:B05FAKE_MODO='ok:0.20'; $env:PE_TESTE_ASSOC_FALHA='1'
  $cr8 = Real $r8; Remove-Item Env:B05FAKE_MODO, Env:PE_TESTE_ASSOC_FALHA -EA SilentlyContinue
  Checar 'PE-S8: falhou.flag, sem fim.flag' ((Test-Path (Join-Path $r8.Dir 'falhou.flag')) -and -not (Test-Path (Join-Path $r8.Dir 'fim.flag')))
  Checar 'PE-S8: executor nao resumido (sem stdout.json)' (-not (Test-Path (Join-Path $r8.Dir 'stdout.json')))

  "== PE-L (PE-F08): -Laco encerra o Job por execucao (neto da 1a morre antes da 2a; acao-pe segue vivo)"
  $Lb = Nova-Execucao 'neto:60:0:0'
  & icacls $Lb.Trab /setintegritylevel '(OI)(CI)low' /Q 2>&1 | Out-Null
  $env:B05FAKE_MODO = 'neto:60:0:0'
  $lacoProc = Start-Process -FilePath $PwshAprovado -PassThru -WindowStyle Hidden -WorkingDirectory $Lb.Trab -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$acao,'-PonteDir',$Lb.Ponte,'-PwshAprovado',$PwshAprovado,'-PwshSha256',$shaPwsh,'-TimeoutSeg','60','-Laco')
  $t0=Get-Date; while(-not (Test-Path (Join-Path $Lb.Dir 'fim.flag')) -and ((Get-Date)-$t0).TotalSeconds -lt 40){ Start-Sleep -Milliseconds 300 }
  Checar 'PE-L: 1a execucao concluiu (fim.flag) sob -Laco' (Test-Path (Join-Path $Lb.Dir 'fim.flag'))
  $np=''; if (Test-Path (Join-Path $Lb.Trab 'neto-pid.txt')) { $np=(Get-Content (Join-Path $Lb.Trab 'neto-pid.txt') -Raw) }
  $np1=0; $nt1=0; if($np -match '^(\d+)\|(\d+)$'){ $np1=[int]$Matches[1]; $nt1=[long]$Matches[2] }
  Start-Sleep -Seconds 2
  $lacoVivo = $false; try { $gp=Get-Process -Id $lacoProc.Id -EA SilentlyContinue; $lacoVivo = [bool]$gp -and -not $gp.HasExited } catch {}
  $neto1Vivo=$false; if($np1 -gt 0){ $pp=Get-Process -Id $np1 -EA SilentlyContinue; if($pp -and $pp.StartTime.ToUniversalTime().Ticks -eq $nt1){ $neto1Vivo=$true } }
  Checar 'PE-L: acao-pe -Laco ainda vivo apos a 1a execucao' $lacoVivo
  Checar 'PE-L: neto da 1a morto pelo teardown do Job (nao so na saida do processo)' ($np1 -gt 0 -and -not $neto1Vivo) "netoPid=$np1 vivo=$neto1Vivo"
  $id2=[guid]::NewGuid().ToString('N'); $d2=Join-Path $Lb.Ponte $id2; New-Item -ItemType Directory -Force $d2|Out-Null
  [System.IO.File]::WriteAllText((Join-Path $d2 'prompt.in'),'t2',[Text.UTF8Encoding]::new($false))
  $pd2=[ordered]@{exec_id=$id2;executor=$PwshAprovado;executor_prefixo=("-NoProfile|-File|$fake");test_cmd='';teto_usd=0.5;pwsh_sha256=$shaPwsh;criado_em=(Get-Date).ToString('o')}
  [System.IO.File]::WriteAllText((Join-Path $d2 'pedido.json'),($pd2|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText((Join-Path $d2 'go.flag'),'1',[Text.UTF8Encoding]::new($false))
  $t0=Get-Date; while(-not (Test-Path (Join-Path $d2 'fim.flag')) -and ((Get-Date)-$t0).TotalSeconds -lt 40){ Start-Sleep -Milliseconds 300 }
  Checar 'PE-L: 2a execucao concluiu na MESMA instancia -Laco' (Test-Path (Join-Path $d2 'fim.flag'))
  try { Stop-Process -Id $lacoProc.Id -Force -EA SilentlyContinue } catch {}
  Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue

  "== PE-S9 (P-03): limites do Job — KILL_ON_JOB_CLOSE ligado; BREAKAWAY desligado"
  . (Join-Path $raiz '..\..\b05job.ps1')   # [B05Job] no processo de teste
  $jt = [B05Job]::CreateJobObject([IntPtr]::Zero, $null)
  [void][B05Job]::Configurar($jt, [B05Job]::KILL_ON_JOB_CLOSE)
  $fl = [B05Job]::Flags($jt)
  Checar 'PE-S9: KILL_ON_JOB_CLOSE ligado' (($fl -band [B05Job]::KILL_ON_JOB_CLOSE) -ne 0) "flags=$fl"
  Checar 'PE-S9: BREAKAWAY_OK/SILENT_BREAKAWAY_OK desligados' (($fl -band ([B05Job]::BREAKAWAY_OK -bor [B05Job]::SILENT_BREAKAWAY_OK)) -eq 0) "flags=$fl"
  [void][B05Job]::TerminateJobObject($jt, 0); [void][B05Job]::CloseHandle($jt)
}

"`nTOTAL PE: $ok / $tot"
exit ([int]($ok -ne $tot))
