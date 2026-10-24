# ponte-pu.ps1 - lado do PU da ponte (modo principal-isolado), V1 disparo LOCAL. Ato 135. gate-pe.
# NUCLEO da V1 (bateria PU-01..PU-12 na proxima rodada). Despacha o acao-pe.ps1 como processo comum (sem Tarefa
# Agendada), monitora heartbeat/timeout, confirma a morte da SUBARVORE (PID+criacao) via NtQuerySystemInformation,
# varre reparse points (apos a morte, imediatamente antes de retornar) e, em VIOLACAO de seguranca, preserva evidencia
# FORA do repo (sem atravessar reparse) + grava trava persistente. Nunca executa codigo editavel pelo PE (I2).
# Spec: b05/pe/PONTE-PU-SPEC.md (v2, Ato 135). Codigos: 0=ok; 1=falha comum (retry); 28=violacao financeira;
# 70=violacao de seguranca. NAO toca controlador 7cd7864 (integracao em 2 fases vem com o modo no claude-com-teto).
Set-StrictMode -Version 3.0
$Utf8 = [System.Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot '..\b05job.ps1')             # [B05Job]: Snapshot, Subarvore, Encerrar
. (Join-Path $PSScriptRoot '..\baixa-integridade.ps1')  # B05LowIL-ReparsePoints

# REQ-11/REQ-02: trava persistente. Qualquer .trava no diretorio bloqueia novas chamadas ate decisao humana.
function PU-Trava-Ativa([string]$travaDir) {
  if (-not $travaDir -or -not (Test-Path -LiteralPath $travaDir)) { return $null }
  $t = Get-ChildItem -LiteralPath $travaDir -Filter '*.trava' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($t) { return (Get-Content -LiteralPath $t.FullName -Raw) } else { return $null }
}
function PU-Gravar-Trava([string]$travaDir,[string]$tipo,[string]$motivo,[string]$execId) {
  New-Item -ItemType Directory -Force $travaDir | Out-Null
  $f = Join-Path $travaDir ("$tipo-$execId.trava")
  [System.IO.File]::WriteAllText($f, (@{ tipo=$tipo; motivo=$motivo; exec_id=$execId; quando=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress), $Utf8)
}

# REQ-03 (V1): toda a SUBARVORE (PID+criacao) enraizada em $raizPid morreu? Fonte inforjavel = Snapshot
# (NtQuerySystemInformation, classe 5). $raizCriacao casa a identidade da raiz (evita PID reutilizado).
# Devolve @{ Morta; Vivos } (Vivos = ["pid|nome|pai|criacao", ...], a raiz incluida se ainda viva com a mesma criacao).
function PU-Subarvore-Morta([uint32]$raizPid,[long]$raizCriacao) {
  $snap = [B05Job]::Snapshot()
  $vivos = New-Object System.Collections.Generic.List[string]
  if ($snap.ContainsKey($raizPid)) { $r = $snap[$raizPid]; if ($r.Criacao -eq $raizCriacao) { $vivos.Add("$raizPid|$($r.Nome)|$($r.Pai)|$($r.Criacao)") } }
  $raizes = New-Object 'System.Collections.Generic.Dictionary[uint32,long]'; $raizes[$raizPid] = $raizCriacao
  foreach ($d in [B05Job]::Subarvore($raizes)) { $vivos.Add([string]$d) }
  return @{ Morta = ($vivos.Count -eq 0); Vivos = $vivos.ToArray() }
}
# Encerra (best-effort) a raiz e os descendentes vivos SO por identidade (PID+criacao) — nunca um PID reutilizado.
function PU-Encerrar-Subarvore([uint32]$raizPid,[long]$raizCriacao) {
  $m = PU-Subarvore-Morta $raizPid $raizCriacao
  foreach ($linha in $m.Vivos) {
    $campos = $linha -split '\|'; if ($campos.Count -ge 4) { try { [void][B05Job]::Encerrar([uint32]$campos[0], [long]$campos[3]) } catch { } }
  }
}

# REQ-11/P-A: copia arvore+artefatos para FORA do repo, SEM atravessar reparse points (robocopy /XJ). Pressupoe REQ-07 OK.
function PU-Preservar-Evidencia([string]$trabDir,[string]$ponteExecDir,[string]$evidDir,[string]$execId) {
  $dest = Join-Path $evidDir ("evid-$execId-" + (Get-Date -Format 'yyyyMMdd-HHmmss')); New-Item -ItemType Directory -Force $dest | Out-Null
  if (Get-Command robocopy -ErrorAction SilentlyContinue) { & robocopy $trabDir (Join-Path $dest 'trabalho') /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP *> $null }
  else { Copy-Item -Recurse -Force $trabDir (Join-Path $dest 'trabalho') -ErrorAction SilentlyContinue }
  Copy-Item -Recurse -Force $ponteExecDir (Join-Path $dest 'ponte') -ErrorAction SilentlyContinue
  return $dest
}

# Despacho V1 (disparo local) de UMA execucao (fase executor; a fase teste reusa o mesmo nucleo com test_cmd).
# Devolve @{ Ok; Codigo; Saida; Erro; Violacao; Motivo; ExecId; Evidencia }.
function Invoke-PontePU-V1 {
  param(
    [Parameter(Mandatory)][string]$PonteDir,
    [Parameter(Mandatory)][string]$TrabDir,
    [Parameter(Mandatory)][string]$AcaoPs1,
    [Parameter(Mandatory)][string]$PwshAprovado,
    [Parameter(Mandatory)][string]$PwshSha256,
    [Parameter(Mandatory)][hashtable]$Pedido,   # executor, executor_prefixo, test_cmd, teto_usd
    [string]$Prompt = '',
    [int]$TimeoutSeg = 120,
    [string]$EvidenciaDir,
    [string]$TravaDir,
    [string]$ExecId
  )
  $res = [ordered]@{ Ok=$false; Codigo=70; Saida=''; Erro=''; Violacao=$false; Motivo=''; ExecId=$null; Evidencia=$null }
  # REQ-11: trava persistente bloqueia novas chamadas sem despachar
  $trava = PU-Trava-Ativa $TravaDir
  if ($trava) { $res.Codigo = 70; $res.Motivo = "trava persistente ativa: $trava"; return $res }
  # REQ-01: exec_id novo + limpeza previa da pasta-ponte
  if (-not $ExecId) { $ExecId = [guid]::NewGuid().ToString('N') }
  $res.ExecId = $ExecId
  $dir = Join-Path $PonteDir $ExecId
  if (Test-Path -LiteralPath $dir) { Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue }
  New-Item -ItemType Directory -Force $dir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dir 'prompt.in'), $Prompt, $Utf8)
  $ped = [ordered]@{ exec_id=$ExecId }
  foreach ($k in $Pedido.Keys) { $ped[$k] = $Pedido[$k] }
  $ped['pwsh_sha256'] = $PwshSha256; $ped['criado_em'] = (Get-Date).ToString('o')
  [System.IO.File]::WriteAllText((Join-Path $dir 'pedido.json'), ($ped | ConvertTo-Json -Compress), $Utf8)
  if ($IsWindows) { & icacls $TrabDir /setintegritylevel '(OI)(CI)low' /Q 2>&1 | Out-Null }
  [System.IO.File]::WriteAllText((Join-Path $dir 'go.flag'), '1', $Utf8)
  # Lanca o acao-pe LOCALMENTE (processo comum, execucao unica). Captura PID+criacao do EMBRULHO (identidade REQ-03).
  $psi = [System.Diagnostics.ProcessStartInfo]::new($PwshAprovado)
  foreach ($a in @('-NoProfile','-ExecutionPolicy','Bypass','-File',$AcaoPs1,'-PonteDir',$PonteDir,'-PwshAprovado',$PwshAprovado,'-PwshSha256',$PwshSha256,'-TimeoutSeg',[string]$TimeoutSeg)) { $psi.ArgumentList.Add($a) }
  $psi.UseShellExecute = $false; $psi.WorkingDirectory = $TrabDir; $psi.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $embPid = [uint32]$p.Id; $embCri = 0L; try { $embCri = $p.StartTime.ToFileTimeUtc() } catch { }
  # REQ-10: prazo da ponte com folga; se estourar, encerra a subarvore (V1: mesmo usuario)
  if (-not $p.WaitForExit(($TimeoutSeg + 15) * 1000)) {
    try { $p.Kill($true) } catch { }; try { $p.WaitForExit(10000) | Out-Null } catch { }
    $res.Violacao = $true; $res.Motivo = "timeout do PU (> ${TimeoutSeg}s + folga)"
  }
  # REQ-03 (V1): confirma a morte da SUBARVORE (acao-pe + executor + descendentes). Tenta encerrar e reconfere.
  Start-Sleep -Milliseconds 300
  $morte = PU-Subarvore-Morta $embPid $embCri
  if (-not $morte.Morta) { PU-Encerrar-Subarvore $embPid $embCri; Start-Sleep -Milliseconds 400; $morte = PU-Subarvore-Morta $embPid $embCri }
  if (-not $morte.Morta) { $res.Violacao = $true; $res.Motivo = ("$($res.Motivo) | subarvore do PE viva: " + ([string]::Join('; ', $morte.Vivos))).Trim(' |') }
  # REQ-07 (apos morte confirmada, antes de retornar): varredura de reparse fail-closed
  $rep = B05LowIL-ReparsePoints $TrabDir
  if (-not $rep.Ok -or @($rep.Pontos).Count) { $res.Violacao = $true; $res.Motivo = ("$($res.Motivo) | reparse: " + ([string]::Join('; ', @($rep.Pontos)))).Trim(' |') }
  # VIOLACAO de seguranca -> evidencia (apos REQ-07) + trava + codigo 70
  if ($res.Violacao) {
    if ($EvidenciaDir) { try { $res.Evidencia = PU-Preservar-Evidencia $TrabDir $dir $EvidenciaDir $ExecId } catch { $res.Motivo += " | falha evidencia: $($_.Exception.Message)" } }
    if ($TravaDir) { try { PU-Gravar-Trava $TravaDir 'seguranca' $res.Motivo $ExecId } catch { } }
    $res.Codigo = 70; return $res
  }
  # Sem violacao: artefatos agora confiaveis (PE morto, sem reparse).
  if (Test-Path -LiteralPath (Join-Path $dir 'falhou.flag')) {   # REQ-06: falha comum -> retry do controlador (exec_id novo)
    $res.Codigo = 1; $res.Motivo = 'falhou.flag (falha comum)'; $res.Erro = (Get-Content -LiteralPath (Join-Path $dir 'erro-pe.txt') -Raw -ErrorAction SilentlyContinue); return $res
  }
  if (-not (Test-Path -LiteralPath (Join-Path $dir 'fim.flag'))) { $res.Codigo = 1; $res.Motivo = 'sem fim.flag/falhou.flag (indeterminado = falha comum)'; return $res }
  $res.Saida = (Get-Content -LiteralPath (Join-Path $dir 'stdout.json') -Raw -ErrorAction SilentlyContinue)
  $res.Erro  = (Get-Content -LiteralPath (Join-Path $dir 'stderr.txt') -Raw -ErrorAction SilentlyContinue)
  $res.Ok = $true; $res.Codigo = 0
  return $res
  # PENDENTE nesta rodada (vem com a bateria PU-01..PU-12 e o modo no claude-com-teto): REQ-02 (reserva/custo invalido
  # no razao), REQ-04/REQ-12 fase teste (Job novo, fronteira de IL, despachante P-B), REQ-08 integracao 2 fases.
}
