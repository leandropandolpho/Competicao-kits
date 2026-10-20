# cenario-recusa.ps1 — Teste ADICIONAL do piloto (fora do harness congelado v0.2.2).
# B-02: executor termina com sucesso mas sem alterar nada (recusa) -> hold SEM_ALTERACAO, sem commit.
# B-03: resumo do executor com acentos chega íntegro ao log.jsonl.
# Usa o simulado congelado (testes/mock/fake-claude.ps1): T1 'sucesso' corrige; T2 'sucesso' regrava o
# mesmo conteúdo -> nenhuma alteração real.
# Uso: pwsh -NoProfile -File fora-do-pacote/testes-piloto/cenario-recusa.ps1 -KitDir kits/kit-A
param([Parameter(Mandatory)][string]$KitDir)
$ErrorActionPreference = 'Stop'
$raiz = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$KitDir = (Resolve-Path $KitDir).Path
$fake = Join-Path $raiz 'testes/mock/fake-claude.ps1'
$base = Join-Path ([IO.Path]::GetTempPath()) ('rec-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
$repo = Join-Path $base 'repo'; $estado = Join-Path $base 'estado'; $mock = Join-Path $base 'mock'
New-Item -ItemType Directory -Force (Join-Path $repo 'src'), (Join-Path $repo 'testes'), $estado | Out-Null
Set-Content (Join-Path $repo '.fixture-marker') 'x'
Set-Content (Join-Path $repo 'src/calc.ps1') 'function Soma($a, $b) { return $a - $b }'
Set-Content (Join-Path $repo 'testes/teste-calc.ps1') @'
. "$PSScriptRoot/../src/calc.ps1"
if ((Soma 2 3) -ne 5) { Write-Output 'FALHOU'; exit 1 }
Write-Output 'PASSOU'; exit 0
'@
New-Item -ItemType Directory -Force (Join-Path $repo '.claude') | Out-Null
Copy-Item (Join-Path $KitDir '.claude/settings.json') (Join-Path $repo '.claude/settings.json')
git init -q $repo; git -C $repo config user.email t@t; git -C $repo config user.name t; git -C $repo config core.autocrlf false
git -C $repo add -A; git -C $repo commit -qm base
$baseCommit = git -C $repo rev-parse HEAD
function T($id, $dep) { [ordered]@{ id = $id; titulo = "Corrigir Soma ($id)"; prompt = "[[$id]] Corrija a Soma."; depends_on = @($dep); status = 'pending'; tentativas = 0; critica = $false } }
$tarefas = Join-Path $base 'TAREFAS.json'
@{ tarefas = @((T 'T1' @()), (T 'T2' @('T1'))) } | ConvertTo-Json -Depth 5 | Set-Content $tarefas
$plano = Join-Path $base 'plano.json'
@{ T1 = @('sucesso'); T2 = @('sucesso') } | ConvertTo-Json | Set-Content $plano
if ($IsWindows) {
  $lan = Join-Path $base 'claude.cmd'
  Set-Content -Encoding ascii $lan @('@echo off', "set `"MOCK_PLANO=$plano`"", "set `"MOCK_DIR=$mock`"", "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$fake`" %*", 'exit /b %ERRORLEVEL%')
} else {
  $lan = Join-Path $base 'claude.sh'
  Set-Content $lan @('#!/usr/bin/env bash', "export MOCK_PLANO='$plano'", "export MOCK_DIR='$mock'", "pwsh -NoProfile -File '$fake' `"`$@`"", 'exit $?'); chmod +x $lan
}
pwsh -NoProfile -File (Join-Path $KitDir 'controlador.ps1') -RepoPath $repo -TarefasPath $tarefas -EstadoDir $estado `
  -TestCmd 'pwsh -NoProfile -File testes/teste-calc.ps1' -TestPaths 'testes/*' -TimeoutSec 60 -MaxTentativas 2 -ClaudeCmd $lan | Out-Null
$exit = $LASTEXITCODE
$doc = Get-Content $tarefas -Raw | ConvertFrom-Json
$st = @{}; foreach ($t in $doc.tarefas) { $st[$t.id] = $t.status }
$commits = @(git -C $repo log --format=%s "$baseCommit..HEAD")
$notif = Get-Content (Join-Path $estado 'notificacoes.txt') -Raw -ErrorAction SilentlyContinue
$log = Get-Content (Join-Path $estado 'log.jsonl') -Raw -Encoding utf8
$vazios = @(git -C $repo log --format=%H "$baseCommit..HEAD" | Where-Object { -not (git -C $repo show --format= --name-only $_) })
$checks = [ordered]@{
  'exit code 2 (hold)'                         = ($exit -eq 2)
  'T1 = done'                                  = ($st['T1'] -eq 'done')
  'T2 = hold'                                  = ($st['T2'] -eq 'hold')
  'exatamente 1 commit (T1)'                   = ($commits.Count -eq 1 -and $commits[0] -like 'tarefa T1:*')
  'nenhum commit vazio'                        = ($vazios.Count -eq 0)
  'notificação SEM_ALTERACAO'                  = ([bool]($notif -match 'T2: SEM_ALTERACAO'))
  'evento sem_alteracao no log'                = ([bool]($log -match '"evento":"sem_alteracao"'))
  'B-03: acento íntegro no resumo ("função")'  = ([bool]($log -match 'Corrigi a função Soma'))
  'controlador sem --allow-empty'              = (-not (Select-String -Path (Join-Path $KitDir 'controlador.ps1') -Pattern 'allow-empty' -SimpleMatch -Quiet))
}
$ok = $true
foreach ($k in $checks.Keys) { "  [$(if ($checks[$k]) {'ok'} else {'FALHOU'; $ok = $false})] $k" }
Remove-Item -Recurse -Force $base -ErrorAction SilentlyContinue
"RESULTADO cenario-recusa: $(if ($ok) {'APROVADO'} else {'REPROVADO'})"
exit $(if ($ok) { 0 } else { 1 })
