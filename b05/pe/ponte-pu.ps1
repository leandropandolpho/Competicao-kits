# ponte-pu.ps1 - lado do PU da ponte (modo principal-isolado), V1 disparo LOCAL. Ato 139. gate-pe.
# NUCLEO da V1 (bateria PU-01..PU-13 e integracao em 2 fases na proxima rodada). Despacha o acao-pe.ps1 como processo
# comum (sem Tarefa Agendada), monitora heartbeat/timeout, confirma a morte da SUBARVORE (PID+criacao) via
# NtQuerySystemInformation, varre reparse (apos a morte, antes de retornar) na arvore E na pasta-ponte, e em VIOLACAO
# preserva evidencia FORA do repo (robocopy /XJ, sem fallback) + grava trava persistente + lease. Nunca executa codigo
# editavel pelo PE (I2). Spec: b05/pe/PONTE-PU-SPEC.md (v2). Codigos: 0=ok; 1=falha comum (retry); 28=financeira; 70=seguranca.
# Correcoes dos Atos 137/138 (Perplexity/ChatGPT): N-01 blindagem de .git (Medium), N-02 recusa de exec_id pre-existente,
# N-03 conferencia de exec_id no fim.flag, N-04 evidencia robusta + varrer pasta-ponte, N-05 identidade obrigatoria,
# N-07 TravaDir obrigatorio/fail-closed, N-08 lease+pre-flight anti-orfao/C6, N-06 classificacao de timeout
# (morte/custo desconhecidos => bloqueio financeiro 28, sem retry; sobrevivente => 70).
Set-StrictMode -Version 3.0
$Utf8 = [System.Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot '..\b05job.ps1')             # [B05Job]: Snapshot, Subarvore, Encerrar
. (Join-Path $PSScriptRoot '..\baixa-integridade.ps1')  # B05LowIL-ReparsePoints, RotularMedio, InfoLabel

function PU-Icacls([string[]]$a){ & "$env:SystemRoot\System32\icacls.exe" @a *> $null; if ($LASTEXITCODE -ne 0) { throw "icacls falhou ($LASTEXITCODE): $($a -join ' ')" } }

# N-07: trava persistente, leitura FAIL-CLOSED (erro ao listar => considera travado). Qualquer .trava bloqueia.
function PU-Trava-Ativa([string]$travaDir) {
  if (-not $travaDir) { throw 'N-07: TravaDir obrigatorio' }
  if (-not (Test-Path -LiteralPath $travaDir)) { return $null }
  try { $t = Get-ChildItem -LiteralPath $travaDir -Filter '*.trava' -ErrorAction Stop | Select-Object -First 1 }
  catch { return "LEITURA DE TRAVA FALHOU (fail-closed): $($_.Exception.Message)" }
  if ($t) { return (Get-Content -LiteralPath $t.FullName -Raw) } else { return $null }
}
function PU-Gravar-Trava([string]$travaDir,[string]$tipo,[string]$motivo,[string]$execId) {
  New-Item -ItemType Directory -Force $travaDir | Out-Null
  $f = Join-Path $travaDir ("$tipo-$execId.trava")
  [System.IO.File]::WriteAllText($f, (@{ tipo=$tipo; motivo=$motivo; exec_id=$execId; quando=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress), $Utf8)
}
# N-08 (lease): registra (pid,criacao) do embrulho FORA do repo ANTES de esperar, para pre-flight/retomada (C6) localizar orfaos.
function PU-Lease-Gravar([string]$travaDir,[string]$execId,[uint32]$pid,[long]$cri) {
  New-Item -ItemType Directory -Force $travaDir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $travaDir "$execId.lease"), (@{ exec_id=$execId; pid=$pid; criacao=$cri; aberto=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress), $Utf8)
}
function PU-Lease-Fechar([string]$travaDir,[string]$execId) { Remove-Item -LiteralPath (Join-Path $travaDir "$execId.lease") -Force -ErrorAction SilentlyContinue }

# N-01: arvore de trabalho BAIXA para o executor Low editar codigo, MAS .git em MEDIO (o executor Low nao toca
# .git/hooks|config). Espelha a blindagem validada do lancador.ps1 (B-05). Falha fechada: confere icacls e re-le o IL.
function PU-RotularArvore([string]$trab) {
  foreach ($e in @(Get-ChildItem -LiteralPath $trab -Force | Where-Object Name -ne '.git')) { PU-Icacls @($e.FullName,'/setintegritylevel','(OI)(CI)low','/T','/Q') }
  $gitDir = Join-Path $trab '.git'
  if (Test-Path -LiteralPath $gitDir) {
    PU-Icacls @($gitDir,'/setintegritylevel','(OI)(CI)medium','/T','/Q')
    $mm = [B05LowIL]::RotularMedio($gitDir); if ($mm) { throw "N-01: falha ao rotular .git medio: $mm" }
    if (Test-Path -LiteralPath "$gitDir\config") { $mm = [B05LowIL]::RotularMedio("$gitDir\config"); if ($mm) { throw "N-01: falha ao rotular .git/config medio: $mm" } }
    $info = [B05LowIL]::InfoLabel($gitDir)                       # releitura fail-closed: .git deve ser Medium (8192)
    if (($info -split '\|')[0] -ne '8192') { throw "N-01: .git nao ficou Medium (InfoLabel=$info) - falha fechada" }
  }
}

# N-03 (V1): toda a SUBARVORE (PID+criacao) enraizada em $raizPid morreu? Fonte inforjavel = Snapshot.
function PU-Subarvore-Morta([uint32]$raizPid,[long]$raizCriacao) {
  $snap = [B05Job]::Snapshot(); $vivos = New-Object System.Collections.Generic.List[string]
  if ($snap.ContainsKey($raizPid)) { $r = $snap[$raizPid]; if ($r.Criacao -eq $raizCriacao) { $vivos.Add("$raizPid|$($r.Nome)|$($r.Pai)|$($r.Criacao)") } }
  $raizes = New-Object 'System.Collections.Generic.Dictionary[uint32,long]'; $raizes[$raizPid] = $raizCriacao
  foreach ($d in [B05Job]::Subarvore($raizes)) { $vivos.Add([string]$d) }
  return @{ Morta = ($vivos.Count -eq 0); Vivos = $vivos.ToArray() }
}
function PU-Encerrar-Subarvore([uint32]$raizPid,[long]$raizCriacao) {
  $m = PU-Subarvore-Morta $raizPid $raizCriacao
  foreach ($linha in $m.Vivos) { $c = $linha -split '\|'; if ($c.Count -ge 4) { try { [void][B05Job]::Encerrar([uint32]$c[0], [long]$c[3]) } catch { } } }
}
# N-08/C6: pre-flight anti-orfao. Antes de despachar, encerra qualquer subarvore de execucao anterior registrada em
# lease (lido fora do repo). Bloqueia (fail-closed) se nao confirmar a morte. Trata a retomada apos morte abrupta do
# controlador: o novo turno nao avanca (nem deixa o controlador fazer git) enquanto um PE anterior puder escrever.
function PU-PreFlight-Orfaos([string]$travaDir) {
  if (-not (Test-Path -LiteralPath $travaDir)) { return @{ Ok=$true; Motivo='' } }
  try { $leases = @(Get-ChildItem -LiteralPath $travaDir -Filter '*.lease' -ErrorAction Stop) }   # R-02: fail-closed
  catch { return @{ Ok=$false; Motivo="R-02: listagem de leases falhou (fail-closed): $($_.Exception.Message)" } }
  foreach ($lf in $leases) {
    try { $ls = Get-Content -LiteralPath $lf.FullName -Raw | ConvertFrom-Json } catch { return @{ Ok=$false; Motivo="lease ilegivel ($($lf.Name)) - fail-closed" } }
    $m = PU-Subarvore-Morta ([uint32]$ls.pid) ([long]$ls.criacao)
    if (-not $m.Morta) { PU-Encerrar-Subarvore ([uint32]$ls.pid) ([long]$ls.criacao); Start-Sleep -Milliseconds 400; $m = PU-Subarvore-Morta ([uint32]$ls.pid) ([long]$ls.criacao) }
    if (-not $m.Morta) { return @{ Ok=$false; Motivo="orfao de execucao anterior nao encerrado (lease $($ls.exec_id)): $([string]::Join('; ',$m.Vivos))" } }
    Remove-Item -LiteralPath $lf.FullName -Force -ErrorAction SilentlyContinue
  }
  return @{ Ok=$true; Motivo='' }
}

# N-04: evidencia FORA do repo, SO via robocopy /XJ (nao atravessa junctions), com checagem de codigo; SEM fallback inseguro.
function PU-Preservar-Evidencia([string]$trabDir,[string]$ponteExecDir,[string]$evidDir,[string]$execId) {
  if (-not (Get-Command robocopy -ErrorAction SilentlyContinue)) { throw 'N-04: robocopy ausente - recuso copiar evidencia sem /XJ (sem fallback inseguro)' }
  $dest = Join-Path $evidDir ("evid-$execId-" + (Get-Date -Format 'yyyyMMdd-HHmmss')); New-Item -ItemType Directory -Force $dest | Out-Null
  & robocopy $trabDir (Join-Path $dest 'trabalho') /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP *> $null; if ($LASTEXITCODE -ge 8) { throw "N-04: robocopy(trabalho) falhou ($LASTEXITCODE)" }
  & robocopy $ponteExecDir (Join-Path $dest 'ponte') /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP *> $null; if ($LASTEXITCODE -ge 8) { throw "N-04: robocopy(ponte) falhou ($LASTEXITCODE)" }
  return $dest
}

function Invoke-PontePU-V1 {
  param(
    [Parameter(Mandatory)][string]$PonteDir,
    [Parameter(Mandatory)][string]$TrabDir,
    [Parameter(Mandatory)][string]$AcaoPs1,
    [Parameter(Mandatory)][string]$PwshAprovado,
    [Parameter(Mandatory)][string]$PwshSha256,
    [Parameter(Mandatory)][hashtable]$Pedido,
    [Parameter(Mandatory)][string]$EvidenciaDir,   # N-04: obrigatorio (fora do repo)
    [Parameter(Mandatory)][string]$TravaDir,       # N-07: obrigatorio (fora do repo)
    [string]$Prompt = '',
    [int]$TimeoutSeg = 120,
    [string]$ExecId
  )
  $res = [ordered]@{ Ok=$false; Codigo=70; Saida=''; Erro=''; Violacao=$false; Motivo=''; ExecId=$null; Evidencia=$null }
  # N-07: trava persistente bloqueia novas chamadas (fail-closed)
  $trava = PU-Trava-Ativa $TravaDir
  if ($trava) { $res.Codigo = 70; $res.Motivo = "trava persistente ativa: $trava"; return $res }
  if (-not $ExecId) { $ExecId = [guid]::NewGuid().ToString('N') }
  $res.ExecId = $ExecId
  # N-08/C6: pre-flight anti-orfao ANTES de qualquer despacho (encerra/confirma orfaos de execucoes anteriores)
  $pf = PU-PreFlight-Orfaos $TravaDir
  if (-not $pf.Ok) { $res.Codigo=70; $res.Violacao=$true; $res.Motivo="N-08 pre-flight: $($pf.Motivo)"; try { PU-Gravar-Trava $TravaDir 'seguranca' $res.Motivo $ExecId } catch { }; return $res }
  $dir = Join-Path $PonteDir $ExecId
  # N-02: recusa pasta exec_id pre-existente (NAO apaga, NAO reutiliza)
  if (Test-Path -LiteralPath $dir) {
    $res.Violacao=$true; $res.Motivo="N-02: pasta exec_id ja existe ($ExecId) - recusado"
    try { PU-Gravar-Trava $TravaDir 'seguranca' $res.Motivo $ExecId } catch { }; return $res
  }
  New-Item -ItemType Directory -Force $dir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dir 'prompt.in'), $Prompt, $Utf8)
  $ped = [ordered]@{ exec_id=$ExecId }; foreach ($k in $Pedido.Keys) { $ped[$k] = $Pedido[$k] }
  $ped['pwsh_sha256'] = $PwshSha256; $ped['criado_em'] = (Get-Date).ToString('o')
  [System.IO.File]::WriteAllText((Join-Path $dir 'pedido.json'), ($ped | ConvertTo-Json -Compress), $Utf8)
  if ($IsWindows) { PU-RotularArvore $TrabDir }   # N-01: Low na arvore, Medium em .git (fail-closed)
  [System.IO.File]::WriteAllText((Join-Path $dir 'go.flag'), '1', $Utf8)
  # Lanca o acao-pe LOCALMENTE (processo comum, execucao unica). N-05: identidade (PID+criacao) OBRIGATORIA.
  $psi = [System.Diagnostics.ProcessStartInfo]::new($PwshAprovado)
  foreach ($a in @('-NoProfile','-ExecutionPolicy','Bypass','-File',$AcaoPs1,'-PonteDir',$PonteDir,'-PwshAprovado',$PwshAprovado,'-PwshSha256',$PwshSha256,'-TimeoutSeg',[string]$TimeoutSeg)) { $psi.ArgumentList.Add($a) }
  $psi.UseShellExecute = $false; $psi.WorkingDirectory = $TrabDir; $psi.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  # N-05/R-03: identidade (PID+criacao) OBRIGATORIA. Criacao em FILETIME do HANDLE (sem conversao local->UTC), com o
  # snapshot (NtQuerySystemInformation) como fonte autoritativa (consistente com Subarvore) e cross-check. Divergente/ausente => bloqueio.
  $embPid = [uint32]$p.Id
  $criH = 0L; try { $criH = [B05LowIL]::CriacaoUtc($p.Handle) } catch { }
  $snap0 = $null; try { $snap0 = [B05Job]::Snapshot() } catch { }
  if (-not $snap0 -or -not $snap0.ContainsKey($embPid)) { try { $p.Kill($true) } catch { }; $res.Violacao=$true; $res.Motivo='N-05/R-03: embrulho ausente no snapshot - bloqueado'; try { PU-Gravar-Trava $TravaDir 'seguranca' $res.Motivo $ExecId } catch { }; return $res }
  $embCri = [long]$snap0[$embPid].Criacao
  if ($embCri -le 0 -or ($criH -gt 0 -and $criH -ne $embCri)) { try { $p.Kill($true) } catch { }; $res.Violacao=$true; $res.Motivo="N-05/R-03: identidade divergente/inconclusiva (handle=$criH snapshot=$embCri) - bloqueado"; try { PU-Gravar-Trava $TravaDir 'seguranca' $res.Motivo $ExecId } catch { }; return $res }
  PU-Lease-Gravar $TravaDir $ExecId $embPid $embCri   # N-08: lease ANTES de esperar
  # REQ-10: prazo com folga; se estourar, encerra a subarvore (V1). (N-06 classificacao fina = proxima rodada.)
  $houveTimeout = $false
  if (-not $p.WaitForExit(($TimeoutSeg + 15) * 1000)) { try { $p.Kill($true) } catch { }; try { $p.WaitForExit(10000) | Out-Null } catch { }; $houveTimeout = $true }
  # N-03: confirma a morte da SUBARVORE (acao-pe + executor + descendentes)
  Start-Sleep -Milliseconds 300
  $morte = PU-Subarvore-Morta $embPid $embCri
  if (-not $morte.Morta) { PU-Encerrar-Subarvore $embPid $embCri; Start-Sleep -Milliseconds 400; $morte = PU-Subarvore-Morta $embPid $embCri }
  if (-not $morte.Morta) { $res.Violacao = $true; $res.Motivo = ("$($res.Motivo) | subarvore do PE viva: " + ([string]::Join('; ', $morte.Vivos))).Trim(' |') }
  # REQ-07/N-04 (apos morte, antes de retornar): varredura de reparse fail-closed na ARVORE e na PASTA-PONTE
  $rep = B05LowIL-ReparsePoints $TrabDir; $repP = B05LowIL-ReparsePoints $dir
  if (-not $rep.Ok -or @($rep.Pontos).Count -or -not $repP.Ok -or @($repP.Pontos).Count) {
    $res.Violacao = $true; $res.Motivo = ("$($res.Motivo) | reparse: " + ([string]::Join('; ', @($rep.Pontos) + @($repP.Pontos)))).Trim(' |')
  }
  # VIOLACAO de seguranca -> evidencia (apos a varredura) + trava + codigo 70
  if ($res.Violacao) {
    try { $res.Evidencia = PU-Preservar-Evidencia $TrabDir $dir $EvidenciaDir $ExecId } catch { $res.Motivo += " | falha evidencia: $($_.Exception.Message)" }
    try { PU-Gravar-Trava $TravaDir 'seguranca' $res.Motivo $ExecId } catch { }
    PU-Lease-Fechar $TravaDir $ExecId; $res.Codigo = 70; return $res
  }
  # N-06: timeout com subarvore MORTA e sem violacao => custo DESCONHECIDO (sem fim.flag). Bloqueio FINANCEIRO, SEM retry.
  if ($houveTimeout) {
    $res.Violacao=$true; $res.Codigo=28
    $res.Motivo=("$($res.Motivo) | N-06: timeout com custo desconhecido (sem fim.flag) - bloqueio financeiro, sem retry").Trim(' |')
    try { $res.Evidencia = PU-Preservar-Evidencia $TrabDir $dir $EvidenciaDir $ExecId } catch { $res.Motivo += " | falha evidencia: $($_.Exception.Message)" }
    try { PU-Gravar-Trava $TravaDir 'financeira' $res.Motivo $ExecId } catch { }
    PU-Lease-Fechar $TravaDir $ExecId; return $res
  }
  PU-Lease-Fechar $TravaDir $ExecId
  # Sem violacao: artefatos confiaveis (PE morto, sem reparse). N-03: confere exec_id no fim.flag.
  if (Test-Path -LiteralPath (Join-Path $dir 'falhou.flag')) { $res.Codigo = 1; $res.Motivo = 'falhou.flag (falha comum)'; $res.Erro = (Get-Content -LiteralPath (Join-Path $dir 'erro-pe.txt') -Raw -ErrorAction SilentlyContinue); return $res }
  if (-not (Test-Path -LiteralPath (Join-Path $dir 'fim.flag'))) { $res.Codigo = 1; $res.Motivo = 'sem fim.flag/falhou.flag (indeterminado = falha comum)'; return $res }
  try { $fim = Get-Content -LiteralPath (Join-Path $dir 'fim.flag') -Raw | ConvertFrom-Json } catch { $res.Violacao=$true; $res.Codigo=70; $res.Motivo='N-03: fim.flag ilegivel'; try { PU-Gravar-Trava $TravaDir 'seguranca' $res.Motivo $ExecId } catch { }; return $res }
  if ("$($fim.exec_id)" -ne $ExecId) { $res.Violacao=$true; $res.Codigo=70; $res.Motivo="N-03: exec_id do fim.flag ($($fim.exec_id)) != esperado ($ExecId)"; try { PU-Gravar-Trava $TravaDir 'seguranca' $res.Motivo $ExecId } catch { }; return $res }
  $res.Saida = (Get-Content -LiteralPath (Join-Path $dir 'stdout.json') -Raw -ErrorAction SilentlyContinue)
  $res.Erro  = (Get-Content -LiteralPath (Join-Path $dir 'stderr.txt') -Raw -ErrorAction SilentlyContinue)
  $res.Ok = $true; $res.Codigo = 0
  return $res
  # PENDENTE (rumo ao congelamento): REQ-02 (reserva/custo no razao do PU), REQ-04/REQ-12 fase teste (Job novo,
  # fronteira de IL, despachante P-B com SHA), REQ-08 integracao 2 fases no claude-com-teto (controlador 7cd7864 diff
  # vazio), bateria PU-01..PU-13 + regressao C4/C6, copia confiavel do PU (hash/IL), precedencia de R1 (HOLD vs failed).
}
