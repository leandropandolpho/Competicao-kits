# controlador-oraculo.ps1 — VALIDAÇÃO DO SCRIPT DE TESTE (não é um kit e não serve como kit).
# Ele TRAPACEIA de propósito: lê $env:MOCK_CENARIO (que só existe nos testes) e produz diretamente o
# estado final esperado de cada cenário. Só roda com -PermitirTrapaca; sem isso, o script de teste o zera
# (é assim que a regra anti-trapaça é validada).
# $env:ORACULO_MUTANTE introduz um defeito por vez, para provar que o script reprova exatamente onde deve:
#   ingenuo            -> mata só o processo pai no timeout          (esperado: C4 reprovado no núcleo)
#   rollback-no-hold   -> desfaz as mudanças ao entrar em hold        (esperado: C3 perde o auxiliar)
#   pausa-sem-concluir -> pausa por custo sem concluir T1             (esperado: C5 reprovado no núcleo)
#   prompt-bypass      -> prompt contém a palavra bypassPermissions   (esperado: nada muda, 40/40)
#   settings-local     -> cria .claude/settings.local.json não rastreado (esperado: nada muda, 40/40)
param($RepoPath, $TarefasPath, $EstadoDir, $TestCmd, $TestPaths, [int]$TimeoutSec, [int]$MaxTentativas, [double]$MaxCustoUsd, [double]$MaxMinutos, $ClaudeCmd)
$ErrorActionPreference = 'Stop'
$mut = "$env:ORACULO_MUTANTE"
$Base = (git -C $RepoPath rev-parse HEAD)
$script:custo = 0.0
if ($mut -eq 'settings-local') {
  New-Item -ItemType Directory -Force (Join-Path $RepoPath '.claude') | Out-Null
  Set-Content (Join-Path $RepoPath '.claude/settings.local.json') '{ "permissions": { "allow": [] } }'
}

function Prompt($id) {
  $p = ((Get-Content $TarefasPath -Raw | ConvertFrom-Json).tarefas | Where-Object id -eq $id).prompt
  if ($mut -eq 'prompt-bypass') { $p += ' (nunca use bypassPermissions)' }
  $p
}
function Chamar($id) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new($ClaudeCmd)
  foreach ($a in @('-p', (Prompt $id), '--output-format', 'json', '--permission-mode', 'dontAsk')) { $psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $RepoPath; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardInput = $true; $psi.UseShellExecute = $false
  $p = [System.Diagnostics.Process]::Start($psi); $p.StandardInput.Close()
  $out = $p.StandardOutput.ReadToEndAsync()
  if (-not $p.WaitForExit($TimeoutSec * 1000)) { $p.Kill($mut -ne 'ingenuo'); $p.WaitForExit(5000) | Out-Null; return $null }
  try { $j = $out.Result | ConvertFrom-Json; $script:custo += [double]$j.total_cost_usd; $j } catch { $null }
}
function Tarefa($id, $st, $tent) {
  $t = Get-Content $TarefasPath -Raw | ConvertFrom-Json
  $x = $t.tarefas | Where-Object id -eq $id; $x.status = $st; $x.tentativas = $tent
  $t | ConvertTo-Json -Depth 5 | Set-Content $TarefasPath
}
function Estado($id, $tent, $st) {
  $agora = (Get-Date).ToString('o')
  [ordered]@{ tarefa_atual = $id; tentativa = $tent; commit_base = (git -C $RepoPath rev-parse HEAD); custo_acumulado_usd = $script:custo
    inicio = $agora; atualizado_em = $agora; status_execucao = $st } | ConvertTo-Json | Set-Content (Join-Path $EstadoDir 'estado.json')
  (@{ ts = $agora; evento = $st } | ConvertTo-Json -Compress) | Add-Content (Join-Path $EstadoDir 'log.jsonl')
}
function Notificar($m) { Add-Content (Join-Path $EstadoDir 'notificacoes.txt') $m }
function Rollback($para) { git -C $RepoPath reset -q --hard $para; git -C $RepoPath clean -qfd }
function Commit($id) { git -C $RepoPath add -A; git -C $RepoPath commit -q -m "tarefa ${id}: Corrigir Soma ($id)" }

switch ($env:MOCK_CENARIO) {
  'C1-sucesso' { Chamar 'T1' | Out-Null; Commit 'T1'; Tarefa 'T1' 'done' 1; Estado 'T1' 1 'concluido'; exit 0 }
  'C2-falha-e-dependencias' {
    1..3 | ForEach-Object { Chamar 'T1' | Out-Null; Rollback $Base }; Tarefa 'T1' 'failed' 3
    Chamar 'T3' | Out-Null; Commit 'T3'; Tarefa 'T3' 'done' 1; Estado 'T3' 1 'falhou'; exit 1 }
  'C3-altera-teste' {
    Chamar 'T1' | Out-Null; if ($mut -eq 'rollback-no-hold') { Rollback $Base }
    Tarefa 'T1' 'hold' 1; Notificar 'hold: teste alterado'; Estado 'T1' 1 'hold'; exit 2 }
  'C4-trava' { Chamar 'T1' | Out-Null; Rollback $Base; Tarefa 'T1' 'failed' 1; Estado 'T1' 1 'falhou'; exit 1 }
  'C5-custo' {
    Chamar 'T1' | Out-Null
    if ($mut -eq 'pausa-sem-concluir') { Rollback $Base } else { Commit 'T1'; Tarefa 'T1' 'done' 1 }
    Notificar 'pausa: teto de custo'; Estado 'T1' 1 'pausado'; exit 3 }
  'C6-retomada' {
    $ef = Join-Path $EstadoDir 'estado.json'
    if (Test-Path $ef) {
      $e = Get-Content $ef -Raw | ConvertFrom-Json; Rollback $e.commit_base
      Chamar 'T1' | Out-Null; Commit 'T1'; Tarefa 'T1' 'done' 2; Estado 'T1' 2 'concluido'; exit 0
    }
    Tarefa 'T1' 'in_progress' 1; Estado 'T1' 1 'rodando'; Chamar 'T1' | Out-Null; exit 1 }
  'C7-tempo' { Chamar 'T1' | Out-Null; Commit 'T1'; Tarefa 'T1' 'done' 1; Notificar 'pausa: teto de tempo'; Estado 'T1' 1 'pausado'; exit 3 }
  'C8-erro-e-exclusao' {
    Chamar 'T1' | Out-Null; Rollback $Base; Chamar 'T1' | Out-Null; Commit 'T1'; Tarefa 'T1' 'done' 2
    Chamar 'T2' | Out-Null; Tarefa 'T2' 'hold' 1; Notificar 'hold: arquivo rastreado apagado'; Estado 'T2' 1 'hold'; exit 2 }
}
exit 99
