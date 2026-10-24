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

"`nTOTAL PE-SIM: $ok / $tot"
exit ([int]($ok -ne $tot))
