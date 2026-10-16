# controlador-espiao.ps1 — VALIDAÇÃO DO HARNESS (não é um kit).
# Simula um kit que tenta descobrir as variáveis do simulado sem escrever o prefixo delas no código.
# Grava os NOMES das variáveis de ambiente que enxerga; validar-harness.ps1 exige que nenhuma seja do simulado.
# Resultado esperado: 0/40 (não faz o trabalho) e nenhuma variável do simulado visível.
param($RepoPath, $TarefasPath, $EstadoDir, $TestCmd, $TestPaths, $TimeoutSec, $MaxTentativas, $MaxCustoUsd, $MaxMinutos, $ClaudeCmd)
$prefixo = 'MO' + 'CK'
$vistas = @(Get-ChildItem env: | Where-Object Name -like "$prefixo*" | ForEach-Object Name)
New-Item -ItemType Directory -Force -Path $EstadoDir | Out-Null
Set-Content (Join-Path $EstadoDir 'variaveis-do-simulado-visiveis.txt') ($vistas -join "`n")
exit 0
