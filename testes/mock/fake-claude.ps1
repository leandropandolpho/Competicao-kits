# fake-claude.ps1 — Claude Code SIMULADO para os testes objetivos.
# v0.2.2.
# Variáveis de ambiente (definidas pelo script de teste, nunca pelo kit):
#   MOCK_PLANO = arquivo JSON: { "T1": ["erro","sucesso"], "T2": ["apaga"] }
#                lista de comportamentos por tarefa; a N-ésima chamada da tarefa usa o N-ésimo item
#                (o último se repete).
#   MOCK_DIR   = pasta (fora do repo) onde o simulado grava o registro das chamadas e PIDs.
# A tarefa é identificada pelo marcador [[Tn]], que está no texto do prompt de cada tarefa.
# O prompt pode chegar como argumento (depois de -p) ou pela entrada padrão (stdin).
# Imita a saída de: claude -p "<prompt>" --output-format json
$ErrorActionPreference = 'Stop'
$dir = $env:MOCK_DIR
if (-not $env:MOCK_PLANO -or -not $dir) { Write-Error 'MOCK_PLANO e MOCK_DIR são obrigatórios'; exit 90 }
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$plano = Get-Content $env:MOCK_PLANO -Raw | ConvertFrom-Json

# 1) Descobre a tarefa: primeiro nos argumentos; só lê stdin se não achar (evita bloquear).
$textoArgs = ($args -join ' ')
$stdin = ''
$marcador = [regex]::Match($textoArgs, '\[\[(T\d+)\]\]')
if (-not $marcador.Success -and [Console]::IsInputRedirected) {
  $stdin = [Console]::In.ReadToEnd()
  $marcador = [regex]::Match($stdin, '\[\[(T\d+)\]\]')
}
$tarefa = if ($marcador.Success) { $marcador.Groups[1].Value } else { '?' }

# 2) Conta as chamadas (total e por tarefa)
$contFile = Join-Path $dir 'chamadas.txt'
$n = 1; if (Test-Path $contFile) { $n = [int](Get-Content $contFile -Raw) + 1 }
Set-Content -Path $contFile -Value $n -NoNewline
$contTarefa = Join-Path $dir "chamadas-$tarefa.txt"
$k = 1; if (Test-Path $contTarefa) { $k = [int](Get-Content $contTarefa -Raw) + 1 }
Set-Content -Path $contTarefa -Value $k -NoNewline

$lista = @()
if ($tarefa -ne '?' -and $plano.PSObject.Properties.Name -contains $tarefa) { $lista = @($plano.$tarefa) }
$comportamento = if ($lista.Count -gt 0) { $lista[[math]::Min($k, $lista.Count) - 1] } else { 'sem-plano' }

# 3) Registra a chamada (argumentos, diretório, tarefa, comportamento)
[ordered]@{ chamada = $n; tarefa = $tarefa; chamada_da_tarefa = $k; comportamento = $comportamento
  args = @($args); cwd = (Get-Location).Path; stdin_chars = $stdin.Length } |
  ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $dir "args-$n.json")

function Saida([string]$texto, [double]$custo, [bool]$erro = $false) {
  [ordered]@{
    type = 'result'; subtype = $(if ($erro) { 'error_during_execution' } else { 'success' })
    is_error = $erro; duration_ms = 1000; num_turns = 1; result = $texto
    session_id = "mock-$n"; total_cost_usd = $custo
  } | ConvertTo-Json -Compress
}

# 4) O executor deve ser iniciado DENTRO do repositório
if (-not (Test-Path (Join-Path (Get-Location) '.fixture-marker'))) {
  Set-Content -Path (Join-Path $dir "cwd-errado-$n.txt") -Value (Get-Location).Path
  Saida 'diretorio de trabalho incorreto' 0.01 $true
  exit 1
}

$calc  = Join-Path (Get-Location) 'src/calc.ps1'
$teste = Join-Path (Get-Location) 'testes/teste-calc.ps1'
$certo = 'function Soma($a, $b) { return $a + $b }'

switch ($comportamento) {
  'sucesso' { Set-Content -Path $calc -Value $certo; Saida 'Corrigi a função Soma.' 0.02 }
  'falha' {
    Set-Content -Path $calc -Value 'function Soma($a, $b) { return $a * $b }'
    Set-Content -Path (Join-Path (Get-Location) 'src/lixo.tmp') -Value "lixo da chamada $n"
    Saida 'Tentei corrigir.' 0.02
  }
  'altera_teste' { Set-Content -Path $teste -Value 'exit 0'; Saida 'Ajustei o teste para passar.' 0.02 }
  'trava' {
    Set-Content -Path (Join-Path (Get-Location) 'src/lixo.tmp') -Value "lixo da chamada $n"
    Set-Content -Path (Join-Path $dir 'pid-mock.txt') -Value $PID
    $pwshExe = (Get-Process -Id $PID).Path
    $filho = Start-Process -FilePath $pwshExe -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 600' -NoNewWindow -PassThru
    Set-Content -Path (Join-Path $dir 'pid-filho.txt') -Value $filho.Id
    Start-Sleep -Seconds 600
    Saida 'nunca deveria chegar aqui' 0.02
  }
  'complemento' {
    # Muda outro arquivo (a Soma já foi corrigida por uma tarefa anterior); o teste continua passando.
    Set-Content -Path (Join-Path (Get-Location) 'src/notas.ps1') -Value "# nota da chamada $n"
    Saida 'Acrescentei as notas.' 0.02
  }
  'custo' { Set-Content -Path $calc -Value $certo; Saida 'Corrigi a função Soma (execução cara).' 6.0 }
  'lento' { Start-Sleep -Seconds 10; Set-Content -Path $calc -Value $certo; Saida 'Corrigi devagar.' 0.02 }
  'erro'  { Write-Output 'Erro interno: isto não é JSON'; exit 1 }
  'apaga' {
    Remove-Item -Path (Join-Path (Get-Location) 'src/extra.ps1') -Force
    Saida 'Removi um arquivo que achei desnecessário.' 0.02
  }
  default { Saida "sem plano para a tarefa $tarefa" 0.01 $true; exit 1 }
}
exit 0
