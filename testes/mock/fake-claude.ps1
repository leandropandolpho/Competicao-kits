# fake-claude.ps1 — Claude Code SIMULADO para os testes objetivos.
# RASCUNHO NÃO CONGELADO v0.1. Comportamento controlado por variáveis de ambiente:
#   MOCK_CENARIO = sucesso | falha | altera_teste | trava | custo
#   MOCK_DIR     = pasta (fora do repo) onde o mock grava contador, argumentos e PIDs
# Imita a saída de: claude -p "<prompt>" --output-format json
$ErrorActionPreference = 'Stop'
$cenario = $env:MOCK_CENARIO
$dir     = $env:MOCK_DIR
if (-not $cenario -or -not $dir) { Write-Error 'MOCK_CENARIO e MOCK_DIR são obrigatórios'; exit 90 }
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# Contador de chamadas
$contFile = Join-Path $dir 'chamadas.txt'
$n = 1
if (Test-Path $contFile) { $n = [int](Get-Content $contFile -Raw) + 1 }
Set-Content -Path $contFile -Value $n -NoNewline

# Registra argumentos e diretório de trabalho
@{ chamada = $n; args = @($args); cwd = (Get-Location).Path } |
  ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $dir "args-$n.json")

function Saida([string]$texto, [double]$custo, [bool]$erro = $false) {
  [ordered]@{
    type = 'result'; subtype = $(if ($erro) { 'error_during_execution' } else { 'success' })
    is_error = $erro; duration_ms = 1000; num_turns = 1; result = $texto
    session_id = "mock-$n"; total_cost_usd = $custo
  } | ConvertTo-Json -Compress
}

# O controlador deve iniciar o executor DENTRO do repositório
if (-not (Test-Path (Join-Path (Get-Location) '.fixture-marker'))) {
  Set-Content -Path (Join-Path $dir "cwd-errado-$n.txt") -Value (Get-Location).Path
  Saida 'diretorio de trabalho incorreto' 0.01 $true
  exit 1
}

$calc  = Join-Path (Get-Location) 'src/calc.ps1'
$teste = Join-Path (Get-Location) 'testes/teste-calc.ps1'

switch ($cenario) {
  'sucesso' {
    Set-Content -Path $calc -Value 'function Soma($a, $b) { return $a + $b }'
    Saida 'Corrigi a função Soma.' 0.02
  }
  'falha' {
    Set-Content -Path $calc -Value 'function Soma($a, $b) { return $a * $b }'
    Set-Content -Path (Join-Path (Get-Location) 'src/lixo.tmp') -Value "lixo da tentativa $n"
    Saida 'Tentei corrigir.' 0.02
  }
  'altera_teste' {
    Set-Content -Path $teste -Value 'exit 0'
    Saida 'Ajustei o teste para passar.' 0.02
  }
  'trava' {
    Set-Content -Path (Join-Path $dir 'pid-mock.txt') -Value $PID
    $pwshExe = (Get-Process -Id $PID).Path
    $filho = Start-Process -FilePath $pwshExe -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 600' -NoNewWindow -PassThru
    Set-Content -Path (Join-Path $dir 'pid-filho.txt') -Value $filho.Id
    Start-Sleep -Seconds 600
    Saida 'nunca deveria chegar aqui' 0.02
  }
  'custo' {
    Set-Content -Path $calc -Value 'function Soma($a, $b) { return $a + $b }'
    Saida 'Corrigi a função Soma (execução cara).' 6.0
  }
  default { Write-Error "cenário desconhecido: $cenario"; exit 91 }
}
exit 0
