# dispensa.ps1 — B-05 (Ato 081, ressalva do conhost). Decide se um processo pré-existente sob o lançador pode ser
# dispensado da verificação de contenção. Usado pelo lançador e pelo teste N20 (com processos reais).
# Requer o tipo [B05Job] (Info) já carregado.
function Testar-Dispensa([uint32]$processId, [uint32]$pai, [uint32]$lancador, [long]$criacaoLancador, [long]$instanteAssoc) {
  $r = @{ Ok = $false; Motivo = ''; Caminho = ''; Criacao = 0L }
  if ($pai -ne $lancador) { $r.Motivo = "pai $pai ≠ lançador $lancador"; return $r }
  $i = [B05Job]::Info($processId)
  if (-not $i) { $r.Motivo = 'identidade não verificável (OpenProcess/GetProcessTimes)'; return $r }
  $c, $cam = $i -split '\|', 2
  $r.Criacao = [long]$c; $r.Caminho = $cam
  $esperado = Join-Path $env:SystemRoot 'System32\conhost.exe'
  if (-not [string]::Equals($cam, $esperado, [StringComparison]::OrdinalIgnoreCase)) { $r.Motivo = "caminho '$cam' ≠ '$esperado'"; return $r }
  if ($r.Criacao -lt $criacaoLancador) { $r.Motivo = 'criado antes do lançador (PID reutilizado)'; return $r }
  if ($r.Criacao -gt $instanteAssoc) { $r.Motivo = 'criado depois da associação ao job'; return $r }
  $r.Ok = $true; return $r
}
