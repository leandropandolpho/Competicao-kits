# testar-ponte-pu.ps1 - bateria do LADO PU da ponte V1 (disparo local). Ato 145. Roda sob Windows/pwsh7 (usa [B05Job]).
# Exercita Invoke-PontePU-V1 (b05/pe/ponte-pu.ps1) com provas REAIS. Casos que o nucleo ja sustenta (executor-fase):
# PU-01 feliz; PU-03 exec_id/residuo (N-02); PU-04 sobrevivente -> 70 (acao falsa nao-contida); PU-07 reparse -> 70;
# PU-08 timeout da ponte -> 28 (N-06); PU-10 trava barra a 2a chamada; PU-13 Low tenta .git/hooks|config -> NEGADO (N-01).
# PENDENTE (com a integracao 2 fases/REQ-02 no claude-com-teto): PU-02 (custo invalido), PU-05 (teste reprovado),
# PU-06 (teste.txt IL), PU-09 (diff do controlador), PU-11/PU-11b (C6/guarda externo), PU-12 (fronteira de IL do teste).
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$raiz = $PSScriptRoot
$acao = (Resolve-Path (Join-Path $raiz '..\acao-pe.ps1')).Path
$fake = (Resolve-Path (Join-Path $raiz '..\..\testes\fake-executor.ps1')).Path
. (Resolve-Path (Join-Path $raiz '..\ponte-pu.ps1')).Path
$PwshAprovado = (Get-Process -Id $PID).Path
$shaPwsh = (Get-FileHash -LiteralPath $PwshAprovado -Algorithm SHA256).Hash
$ok = 0; $tot = 0
function Checar($nome,[bool]$cond,[string]$det=''){ $script:tot++; if($cond){ $script:ok++; "[ok] $nome" } else { "[FALHA] $nome $det" } }

# Monta um ambiente limpo: base com ponte/ trabalho/(+.git) evid/ trava/. Devolve os caminhos.
function Novo-Amb([bool]$comGit=$true) {
  $base = Join-Path $env:TEMP ('pu-' + [guid]::NewGuid().ToString('N').Substring(0,8))
  $ponte = Join-Path $base 'ponte'; $trab = Join-Path $base 'trabalho'; $evid = Join-Path $base 'evid'; $trava = Join-Path $base 'trava'; $razao = Join-Path $base 'razao'
  New-Item -ItemType Directory -Force $ponte,$trab,$evid,$trava,$razao | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $trab 'codigo.txt'), 'x', [Text.UTF8Encoding]::new($false))
  if ($comGit) { New-Item -ItemType Directory -Force (Join-Path $trab '.git\hooks') | Out-Null; [System.IO.File]::WriteAllText((Join-Path $trab '.git\config'), "[core]`n", [Text.UTF8Encoding]::new($false)) }
  return [pscustomobject]@{ Base=$base; Ponte=$ponte; Trab=$trab; Evid=$evid; Trava=$trava; Razao=$razao }
}
# Le o razao.jsonl do ambiente e devolve os eventos (ou @() se vazio).
function Eventos-Razao($amb) {
  $arq = Join-Path $amb.Razao 'razao.jsonl'
  if (-not (Test-Path $arq)) { return @() }
  @(Get-Content $arq | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}
function Ped([string]$testCmd=''){ return @{ executor=$PwshAprovado; executor_prefixo=("-NoProfile|-File|$fake"); test_cmd=$testCmd; teto_usd=0.5 } }

if (-not $IsWindows) { "PU-SUITE: so roda no Windows (usa [B05Job]/icacls/processos reais)."; exit 0 }

# --- acoes FALSAS (nao-contidas), para exercitar o PROPRIO nucleo do PU em isolamento ---
$fakeAcaoSobrev = Join-Path $env:TEMP 'fake-acao-sobrev.ps1'
@'
param([string]$PonteDir,[string]$PwshAprovado,[string]$PwshSha256,[int]$TimeoutSeg)
$d = Get-ChildItem -Directory $PonteDir | Where-Object { Test-Path (Join-Path $_.FullName 'go.flag') } | Select-Object -First 1
$psi = [System.Diagnostics.ProcessStartInfo]::new($env:ComSpec); foreach($x in @('/c','ping -n 30 127.0.0.1 > nul')){$psi.ArgumentList.Add($x)}; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
[void][System.Diagnostics.Process]::Start($psi)   # neto que SOBREVIVE (embrulho defeituoso, nao contem)
if ($d) { Set-Content (Join-Path $d.FullName 'stdout.json') '{"result":"feito","total_cost_usd":0.1}'; Set-Content (Join-Path $d.FullName 'exit.code') '0'; Set-Content (Join-Path $d.FullName 'fim.flag') ('{"exec_id":"'+$d.Name+'","codigo":0}') }
exit 0
'@ | Set-Content $fakeAcaoSobrev -Encoding utf8
$fakeAcaoHang = Join-Path $env:TEMP 'fake-acao-hang.ps1'
@'
param([string]$PonteDir,[string]$PwshAprovado,[string]$PwshSha256,[int]$TimeoutSeg)
Start-Sleep -Seconds 999   # trava: forca o timeout do LADO PU
'@ | Set-Content $fakeAcaoHang -Encoding utf8
$fakeAcaoReparse = Join-Path $env:TEMP 'fake-acao-reparse.ps1'
@'
param([string]$PonteDir,[string]$PwshAprovado,[string]$PwshSha256,[int]$TimeoutSeg)
$d = Get-ChildItem -Directory $PonteDir | Where-Object { Test-Path (Join-Path $_.FullName 'go.flag') } | Select-Object -First 1
cmd /c mklink /J (Join-Path (Get-Location) 'linkjun') "$env:TEMP" > $null 2>&1   # planta junction e NAO varre
if ($d) { Set-Content (Join-Path $d.FullName 'stdout.json') '{"result":"feito","total_cost_usd":0.1}'; Set-Content (Join-Path $d.FullName 'exit.code') '0'; Set-Content (Join-Path $d.FullName 'fim.flag') ('{"exec_id":"'+$d.Name+'","codigo":0}') }
exit 0
'@ | Set-Content $fakeAcaoReparse -Encoding utf8

"== PU-01: fluxo feliz (executor ok) -> codigo 0, stdout, subarvore morta, sem trava, razao reconciliado (REQ-02)"
$a = Novo-Amb
$env:B05FAKE_MODO = 'ok:0.20'
$r = Invoke-PontePU-V1 -PonteDir $a.Ponte -TrabDir $a.Trab -AcaoPs1 $acao -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Pedido (Ped) -Prompt 'faca' -TimeoutSeg 60 -EvidenciaDir $a.Evid -TravaDir $a.Trava -RazaoDir $a.Razao
Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue
Checar 'PU-01: codigo 0 e Ok' ($r.Codigo -eq 0 -and $r.Ok) "cod=$($r.Codigo) motivo=$($r.Motivo)"
Checar 'PU-01: stdout com result do executor' ("$($r.Saida)" -match 'feito')
Checar 'PU-01: sem violacao e sem trava' (-not $r.Violacao -and -not (Get-ChildItem $a.Trava -Filter *.trava -EA SilentlyContinue))
$ev1 = Eventos-Razao $a
$ini1 = @($ev1 | Where-Object { $_.evento -eq 'inicio' -and "$($_.id)" -eq $r.ExecId })
$fim1 = @($ev1 | Where-Object { $_.evento -eq 'fim' -and "$($_.id)" -eq $r.ExecId })
Checar 'PU-01: razao com reserva (inicio teto=0.5)' ($ini1.Count -eq 1 -and [double]$ini1[0].teto_usd -eq 0.5) "ini=$($ini1.Count)"
Checar 'PU-01: razao reconciliado (fim custo_usd=0.20 conhecido, D-06 b)' ($fim1.Count -eq 1 -and -not $fim1[0].PSObject.Properties['custo_desconhecido'] -and [double]$fim1[0].custo_usd -eq 0.20) "fim=$($fim1.Count) custo=$($fim1[0].custo_usd)"

"== PU-02 (REQ-02): executor reporta total_cost_usd INVALIDO (texto) -> custo desconhecido -> 28 + trava financeira"
$a2 = Novo-Amb
$env:B05FAKE_MODO = 'custo'; $env:B05FAKE_CUSTO = '"caro"'
$r2 = Invoke-PontePU-V1 -PonteDir $a2.Ponte -TrabDir $a2.Trab -AcaoPs1 $acao -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Pedido (Ped) -Prompt 'x' -TimeoutSeg 60 -EvidenciaDir $a2.Evid -TravaDir $a2.Trava -RazaoDir $a2.Razao
Remove-Item Env:B05FAKE_MODO,Env:B05FAKE_CUSTO -EA SilentlyContinue
$ev2 = Eventos-Razao $a2
$fim2 = @($ev2 | Where-Object { $_.evento -eq 'fim' -and "$($_.id)" -eq $r2.ExecId })
Checar 'PU-02: custo invalido -> codigo 28, violacao' ($r2.Codigo -eq 28 -and $r2.Violacao) "cod=$($r2.Codigo) motivo=$($r2.Motivo)"
Checar 'PU-02: trava FINANCEIRA gravada' ([bool](Get-ChildItem $a2.Trava -Filter 'financeira-*.trava' -EA SilentlyContinue))
Checar 'PU-02: razao fim custo_desconhecido (nao vira zero, D-06 c)' ($fim2.Count -eq 1 -and $fim2[0].custo_desconhecido -eq $true) "fim=$($fim2.Count)"
Checar 'PU-02: evidencia bruta preservada fora do repo' ([bool]$r2.Evidencia -and (Test-Path $r2.Evidencia))

"== PU-13 (N-01): executor Low tenta escrever .git/hooks e .git/config -> NEGADO (.git Medium)"
$b = Novo-Amb $true
$env:B05FAKE_MODO = 'atacar'
$r13 = Invoke-PontePU-V1 -PonteDir $b.Ponte -TrabDir $b.Trab -AcaoPs1 $acao -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Pedido (Ped) -Prompt 'x' -TimeoutSeg 60 -EvidenciaDir $b.Evid -TravaDir $b.Trava
Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue
$ataque = Join-Path $b.Trab 'ataque.txt'
$txtAt = if (Test-Path $ataque) { Get-Content $ataque -Raw } else { '' }
Checar 'PU-13: executor rodou e gravou ataque.txt' (Test-Path $ataque)
Checar 'PU-13: git_hook NEGADO (.git Medium barra Low)' ($txtAt -match 'git_hook=NEGADO') "t=$txtAt"
Checar 'PU-13: git_config NEGADO' ($txtAt -match 'git_config=NEGADO') "t=$txtAt"

"== PU-03 (N-02): pasta exec_id pre-existente -> recusa (70), nao despacha"
$c = Novo-Amb
$fixo = [guid]::NewGuid().ToString('N'); $dirFixo = Join-Path $c.Ponte $fixo; New-Item -ItemType Directory -Force $dirFixo | Out-Null
[System.IO.File]::WriteAllText((Join-Path $dirFixo 'fim.flag'), '{"exec_id":"residuo"}', [Text.UTF8Encoding]::new($false))
$env:B05FAKE_MODO = 'ok:0.10'
$r3 = Invoke-PontePU-V1 -PonteDir $c.Ponte -TrabDir $c.Trab -AcaoPs1 $acao -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Pedido (Ped) -TimeoutSeg 60 -EvidenciaDir $c.Evid -TravaDir $c.Trava -ExecId $fixo
Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue
Checar 'PU-03: recusou exec_id pre-existente (codigo 70, violacao)' ($r3.Codigo -eq 70 -and $r3.Violacao) "cod=$($r3.Codigo)"
Checar 'PU-03: nao reutilizou/apagou (residuo fim.flag intacto)' ((Get-Content (Join-Path $dirFixo 'fim.flag') -Raw) -match 'residuo')

"== PU-07 (reparse): junction na arvore, embrulho NAO varre -> varredura do PU pos-morte -> 70"
$d = Novo-Amb
$r7 = Invoke-PontePU-V1 -PonteDir $d.Ponte -TrabDir $d.Trab -AcaoPs1 $fakeAcaoReparse -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Pedido (Ped) -TimeoutSeg 60 -EvidenciaDir $d.Evid -TravaDir $d.Trava
Checar 'PU-07: reparse detectado -> codigo 70, violacao' ($r7.Codigo -eq 70 -and $r7.Violacao) "cod=$($r7.Codigo) motivo=$($r7.Motivo)"
Checar 'PU-07: evidencia preservada fora do repo' ([bool]$r7.Evidencia -and (Test-Path $r7.Evidencia))
Checar 'PU-07: trava de seguranca gravada' ([bool](Get-ChildItem $d.Trava -Filter 'seguranca-*.trava' -EA SilentlyContinue))

"== PU-04 (sobrevivente): acao nao-contida deixa neto vivo -> REQ-03 do PU detecta -> 70 + evidencia + trava"
$e = Novo-Amb
$r4 = Invoke-PontePU-V1 -PonteDir $e.Ponte -TrabDir $e.Trab -AcaoPs1 $fakeAcaoSobrev -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Pedido (Ped) -TimeoutSeg 60 -EvidenciaDir $e.Evid -TravaDir $e.Trava
Checar 'PU-04: sobrevivente -> codigo 70, violacao' ($r4.Codigo -eq 70 -and $r4.Violacao) "cod=$($r4.Codigo) motivo=$($r4.Motivo)"
Checar 'PU-04: evidencia preservada' ([bool]$r4.Evidencia -and (Test-Path $r4.Evidencia))
"== PU-10: apos a violacao (PU-04), a 2a chamada e BARRADA pela trava (sem despachar)"
$r10 = Invoke-PontePU-V1 -PonteDir $e.Ponte -TrabDir $e.Trab -AcaoPs1 $acao -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Pedido (Ped) -TimeoutSeg 60 -EvidenciaDir $e.Evid -TravaDir $e.Trava
Checar 'PU-10: 2a chamada barrada pela trava (codigo 70, motivo=trava)' ($r10.Codigo -eq 70 -and $r10.Motivo -match 'trava persistente ativa')

"== PU-08 (N-06): acao que trava -> timeout do PU, subarvore morta, sem fim.flag -> 28 (financeiro), sem retry"
$g = Novo-Amb
$r8 = Invoke-PontePU-V1 -PonteDir $g.Ponte -TrabDir $g.Trab -AcaoPs1 $fakeAcaoHang -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Pedido (Ped) -TimeoutSeg 3 -EvidenciaDir $g.Evid -TravaDir $g.Trava
Checar 'PU-08: timeout do PU -> codigo 28 (financeiro), violacao' ($r8.Codigo -eq 28 -and $r8.Violacao) "cod=$($r8.Codigo) motivo=$($r8.Motivo)"
Checar 'PU-08: trava FINANCEIRA gravada' ([bool](Get-ChildItem $g.Trava -Filter 'financeira-*.trava' -EA SilentlyContinue))

"== PU-05 (REQ-06/D-06 d): executor OK (custo conhecido) mas teste REPROVA -> falhou.flag por execucao, custo conhecido, retry com exec_id novo"
$h5 = Novo-Amb
$env:B05FAKE_MODO = 'ok:0.20'
$r5 = Invoke-PontePU-V1 -PonteDir $h5.Ponte -TrabDir $h5.Trab -AcaoPs1 $acao -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Pedido (Ped 'exit 3') -Prompt 'x' -TimeoutSeg 60 -EvidenciaDir $h5.Evid -TravaDir $h5.Trava -RazaoDir $h5.Razao
$pp5 = Join-Path $h5.Ponte $r5.ExecId; $teste5 = Join-Path $pp5 'teste.txt'
$ev5 = Eventos-Razao $h5; $fim5 = @($ev5 | Where-Object { $_.evento -eq 'fim' -and "$($_.id)" -eq $r5.ExecId })
Checar 'PU-05: teste reprovado -> codigo 1 (falha comum, nao violacao)' ($r5.Codigo -eq 1 -and -not $r5.Violacao) "cod=$($r5.Codigo) motivo=$($r5.Motivo)"
Checar 'PU-05: classificado D-06(d) falha de teste' ($r5.Motivo -match 'falha de teste')
Checar 'PU-05: teste.txt registrou reprovacao (codigo=3)' ((Test-Path $teste5) -and ((Get-Content $teste5 -Raw) -match 'codigo=3'))
Checar 'PU-05: razao fim custo CONHECIDO (executor rodou, 0.20; nao desconhecido)' ($fim5.Count -eq 1 -and -not $fim5[0].PSObject.Properties['custo_desconhecido'] -and [double]$fim5[0].custo_usd -eq 0.20) "fim=$($fim5.Count)"
# REQ-06: falha de teste NAO grava trava; a 2a tentativa (exec_id NOVO) despacha normalmente
$r5b = Invoke-PontePU-V1 -PonteDir $h5.Ponte -TrabDir $h5.Trab -AcaoPs1 $acao -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Pedido (Ped) -Prompt 'x' -TimeoutSeg 60 -EvidenciaDir $h5.Evid -TravaDir $h5.Trava -RazaoDir $h5.Razao
Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue
Checar 'PU-05: 2a tentativa (exec_id novo) NAO barrada -> executa (codigo 0)' ($r5b.Codigo -eq 0 -and $r5b.ExecId -ne $r5.ExecId) "cod=$($r5b.Codigo)"

"== PU-12 (REQ-04/S-03): o codigo do TESTE roda em Low IL e NAO escreve em alvo Medium (.git) -> NEGADO (fronteira de IL)"
$h12 = Novo-Amb $true
$env:B05FAKE_MODO = 'ok:0.15'
$tcmd = "try { [IO.File]::WriteAllText((Join-Path (Get-Location) '.git\forj.txt'),'x'); 'git_forj=OK' } catch { 'git_forj=NEGADO' }"
$r12 = Invoke-PontePU-V1 -PonteDir $h12.Ponte -TrabDir $h12.Trab -AcaoPs1 $acao -PwshAprovado $PwshAprovado -PwshSha256 $shaPwsh -Pedido (Ped $tcmd) -Prompt 'x' -TimeoutSeg 60 -EvidenciaDir $h12.Evid -TravaDir $h12.Trava -RazaoDir $h12.Razao
Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue
$pp12 = Join-Path $h12.Ponte $r12.ExecId; $teste12 = Join-Path $pp12 'teste.txt'
$txt12 = if (Test-Path $teste12) { Get-Content $teste12 -Raw } else { '' }
Checar 'PU-12: fluxo OK (teste tratou o erro e saiu 0) -> codigo 0' ($r12.Codigo -eq 0) "cod=$($r12.Codigo) motivo=$($r12.Motivo)"
Checar 'PU-12: teste rodou em Low IL (nivel=4096)' ($txt12 -match 'nivel=4096') "t=$txt12"
Checar 'PU-12: escrita Low em .git (Medium) NEGADA (fronteira de IL)' ($txt12 -match 'git_forj=NEGADO') "t=$txt12"
Checar 'PU-12: teste.txt NAO forjavel pelo codigo Low (gravado pelo PE em Medium)' (Test-Path $teste12)

"`nTOTAL PU: $ok / $tot"
exit ([int]($ok -ne $tot))
