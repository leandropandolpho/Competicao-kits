# razao.ps1 — razão de custos do B-05 (contrato v2, Ato 072). Usado pelo embrulho e pelo lançador.
# Formato: JSON Lines em <RazaoDir>/razao.jsonl. Eventos: inicio, pid, fim, bloqueado, controlador, membros_job.
# Regras: desconhecido nunca vira zero (C4); reserva só cai com 'fim' de custo conhecido do mesmo id (C6);
# razão ilegível bloqueia (E4).

$script:Utf8SemBom = [System.Text.UTF8Encoding]::new($false)

function Razao-Arquivo([string]$dir) { Join-Path $dir 'razao.jsonl' }

function Razao-Gravar([string]$dir, [hashtable]$evento) {
  # Escrita durável: abre, acrescenta UMA linha, WriteThrough + Flush(true). Exceção = falha de gravação.
  $evento['ts'] = (Get-Date).ToString('o')
  $linha = ($evento | ConvertTo-Json -Compress -Depth 5) + "`n"
  $bytes = $script:Utf8SemBom.GetBytes($linha)
  $fs = [System.IO.FileStream]::new((Razao-Arquivo $dir), [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write,
                                    [System.IO.FileShare]::Read, 4096, [System.IO.FileOptions]::WriteThrough)
  try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
}

function Razao-Ler([string]$dir) {
  # Devolve @{ Ok; Motivo; Eventos }. Qualquer linha ilegível ou parcial → Ok = $false.
  $arq = Razao-Arquivo $dir
  if (-not (Test-Path -LiteralPath $arq)) { return @{ Ok = $true; Motivo = ''; Eventos = @() } }
  $texto = [System.IO.File]::ReadAllText($arq, $script:Utf8SemBom)
  if ($texto.Length -and -not $texto.EndsWith("`n")) { return @{ Ok = $false; Motivo = 'última linha do razão incompleta'; Eventos = @() } }
  $ev = [System.Collections.Generic.List[object]]::new(); $n = 0
  foreach ($l in ($texto -split "`n")) {
    $n++; if (-not $l.Trim()) { continue }
    try { $o = $l | ConvertFrom-Json -ErrorAction Stop } catch { return @{ Ok = $false; Motivo = "linha $n do razão ilegível"; Eventos = @() } }
    if (-not $o.PSObject.Properties['evento']) { return @{ Ok = $false; Motivo = "linha $n sem campo evento"; Eventos = @() } }
    $ev.Add($o)
  }
  return @{ Ok = $true; Motivo = ''; Eventos = $ev.ToArray() }
}

function Razao-Contabilizar($eventos, [double]$folga) {
  # Soma por chamada (id): fim com custo conhecido → custo; fim desconhecido ou inicio sem fim → teto × (1+folga);
  # fim de falha comprovadamente anterior à invocação → 0 conhecido.
  $ini = @{}; $fim = @{}
  foreach ($e in $eventos) {
    if ($e.evento -eq 'inicio') { $ini["$($e.id)"] = $e }
    elseif ($e.evento -eq 'fim') { $fim["$($e.id)"] = $e }
  }
  $conhecido = 0.0; $reservado = 0.0; $abertas = @()
  foreach ($id in $ini.Keys) {
    $i = $ini[$id]; $teto = [double]$i.teto_usd
    if ($fim.ContainsKey($id)) {
      $f = $fim[$id]
      if ($f.PSObject.Properties['custo_usd'] -and $null -ne $f.custo_usd -and -not $f.custo_desconhecido) { $conhecido += [double]$f.custo_usd }
      else { $reservado += $teto * (1 + $folga) }
    } else { $reservado += $teto * (1 + $folga); $abertas += $id }
  }
  return @{ Conhecido = [math]::Round($conhecido, 6); Reservado = [math]::Round($reservado, 6)
            Total = [math]::Round($conhecido + $reservado, 6); Abertas = $abertas }
}

function Processo-Vivo([int]$processId, [string]$criacaoIso) {
  # E4: vivo só se o PID existir COM o mesmo horário de criação (PID reutilizado não conta).
  $p = Get-Process -Id $processId -ErrorAction SilentlyContinue
  if (-not $p) { return $false }
  try { $c = $p.StartTime.ToUniversalTime().ToString('o') } catch { return $true }   # sem acesso: conservador
  return ([datetime]::Parse($criacaoIso).ToUniversalTime().ToString('o') -eq $c)
}

function Razao-ProcessosVivos($eventos) {
  # P4: processos registrados (executor e controlador) ainda vivos.
  return @($eventos | Where-Object { $_.evento -in @('pid', 'controlador') } | Where-Object { Processo-Vivo ([int]$_.pid) "$($_.criacao)" } |
           ForEach-Object { "$($_.evento) pid $($_.pid) (chamada $($_.id))" })
}

function Razao-Nome-Trava([string]$dir) {
  $h = [System.Security.Cryptography.SHA256]::HashData($script:Utf8SemBom.GetBytes([IO.Path]::GetFullPath($dir).ToLowerInvariant()))
  return 'Local\b05-' + ([Convert]::ToHexString($h).Substring(0, 24))
}
