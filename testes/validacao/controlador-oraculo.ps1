# controlador-oraculo.ps1 — VALIDAÇÃO DO HARNESS (não é um kit e não serve como kit).
# Ele TRAPACEIA de propósito: lê $env:MOCK_CENARIO (que só existe nos testes) e produz
# diretamente o estado final esperado de cada cenário. Serve apenas para provar que o
# harness consegue dar 40/40 quando o comportamento está certo. Não tem lógica de controlador.
param($RepoPath, $TarefasPath, $EstadoDir, $TestCmd, $TestPaths, [int]$TimeoutSec, [int]$MaxTentativas, [double]$MaxCustoUsd, $MaxMinutos, $ClaudeCmd)
$ErrorActionPreference = 'Stop'

function Chamar {
  $psi = [System.Diagnostics.ProcessStartInfo]::new($ClaudeCmd)
  foreach ($a in @('-p', 'tarefa de validacao', '--output-format', 'json', '--permission-mode', 'dontAsk')) { $psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $RepoPath; $psi.RedirectStandardOutput = $true; $psi.UseShellExecute = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEndAsync()
  if (-not $p.WaitForExit($TimeoutSec * 1000)) { $p.Kill($true); $p.WaitForExit(); return $null }
  return ($out.Result | ConvertFrom-Json)
}
function Status($id, $st, $tent = 0) {
  $t = Get-Content $TarefasPath -Raw | ConvertFrom-Json
  ($t.tarefas | Where-Object id -eq $id).status = $st
  ($t.tarefas | Where-Object id -eq $id).tentativas = $tent
  $t | ConvertTo-Json -Depth 5 | Set-Content $TarefasPath
}
function Estado($custo, $st) {
  $agora = (Get-Date).ToString('o')
  @{ tarefa_atual = 'T1'; tentativa = 1; custo_acumulado_usd = $custo; inicio = $agora; atualizado_em = $agora; status_execucao = $st } |
    ConvertTo-Json | Set-Content (Join-Path $EstadoDir 'estado.json')
  (@{ ts = $agora; evento = $st } | ConvertTo-Json -Compress) | Add-Content (Join-Path $EstadoDir 'log.jsonl')
}
function Notificar($m) { Add-Content (Join-Path $EstadoDir 'notificacoes.txt') $m }
function Rollback { git -C $RepoPath reset -q --hard HEAD; git -C $RepoPath clean -qfd }
function Commit { git -C $RepoPath add -A; git -C $RepoPath commit -q -m 'tarefa T1: Corrigir Soma (T1)' }

switch ($env:MOCK_CENARIO) {
  'sucesso'      { $r = Chamar; Commit; Status 'T1' 'done' 1; Estado $r.total_cost_usd 'concluido'; exit 0 }
  'falha'        { 1..3 | ForEach-Object { Chamar | Out-Null; Rollback }; Status 'T1' 'failed' 3; Estado 0.06 'falhou'; exit 1 }
  'altera_teste' { Chamar | Out-Null; Status 'T1' 'hold' 1; Notificar 'hold: teste alterado'; Estado 0.02 'hold'; exit 2 }
  'trava'        { Chamar | Out-Null; Rollback; Status 'T1' 'failed' 1; Estado 0 'falhou'; exit 1 }
  'custo'        { $r = Chamar; Commit; Status 'T1' 'done' 1; Notificar 'pausa: teto de custo'; Estado $r.total_cost_usd 'pausado'; exit 3 }
}
exit 99
