# validar-harness.ps1 — Prova que o script de teste pontua certo ANTES de rodar qualquer kit.
# v0.2.2. Falha (exit 1) se qualquer resultado diferir do esperado.
param([string]$SaidaDir = 'saida/validacao')
$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
$casos = @(
  @{ nome = 'nulo';               arquivo = 'controlador-nulo.ps1';    mutante = '';                   permitir = $false; esperado = 0 }
  @{ nome = 'oraculo';            arquivo = 'controlador-oraculo.ps1'; mutante = '';                   permitir = $true;  esperado = 40 }
  @{ nome = 'trapaceiro';         arquivo = 'controlador-oraculo.ps1'; mutante = '';                   permitir = $false; esperado = 0 }
  @{ nome = 'ingenuo';            arquivo = 'controlador-oraculo.ps1'; mutante = 'ingenuo';            permitir = $true;  esperado = 35 }
  @{ nome = 'rollback-no-hold';   arquivo = 'controlador-oraculo.ps1'; mutante = 'rollback-no-hold';   permitir = $true;  esperado = 39 }
  @{ nome = 'pausa-sem-concluir'; arquivo = 'controlador-oraculo.ps1'; mutante = 'pausa-sem-concluir'; permitir = $true;  esperado = 35 }
  @{ nome = 'prompt-bypass';      arquivo = 'controlador-oraculo.ps1'; mutante = 'prompt-bypass';      permitir = $true;  esperado = 40 }
  @{ nome = 'settings-local';     arquivo = 'controlador-oraculo.ps1'; mutante = 'settings-local';     permitir = $true;  esperado = 40 }
  @{ nome = 'prompt-stdin';       arquivo = 'controlador-oraculo.ps1'; mutante = 'prompt-stdin';       permitir = $true;  esperado = 40 }
  @{ nome = 'custo-nao-preservado'; arquivo = 'controlador-oraculo.ps1'; mutante = 'custo-nao-preservado'; permitir = $true; esperado = 39 }
  @{ nome = 'trapaceiro-caminho'; arquivo = 'controlador-oraculo.ps1'; mutante = 'caminho';            permitir = $true;  esperado = 0 }
  @{ nome = 'espiao';             arquivo = 'controlador-espiao.ps1';  mutante = '';                   permitir = $false; esperado = 0 }
)
$falhas = 0
$tabela = foreach ($c in $casos) {
  $kit = Join-Path $SaidaDir "kits/$($c.nome)"
  New-Item -ItemType Directory -Force $kit | Out-Null
  Copy-Item (Join-Path $PSScriptRoot $c.arquivo) (Join-Path $kit 'controlador.ps1') -Force
  $env:ORACULO_MUTANTE = $c.mutante
  $argsH = @('-NoProfile', '-File', (Join-Path $raiz 'run-cenarios.ps1'), '-KitDir', $kit, '-SaidaDir', (Join-Path $SaidaDir "resultados/$($c.nome)"))
  if ($c.permitir) { $argsH += '-PermitirTrapaca' }
  & pwsh @argsH | Out-Null
  $obtido = (Get-Content (Join-Path $SaidaDir "resultados/$($c.nome)/resultados.json") -Raw | ConvertFrom-Json).pontos_objetivos
  $ok = $obtido -eq $c.esperado; if (-not $ok) { $falhas++ }
  [pscustomobject]@{ caso = $c.nome; esperado = $c.esperado; obtido = $obtido; ok = $ok }
}
$env:ORACULO_MUTANTE = ''
# O controlador não pode enxergar as variáveis do simulado em nenhum cenário.
$espioes = Get-ChildItem (Join-Path $SaidaDir 'resultados/espiao/work') -Recurse -Filter 'variaveis-do-simulado-visiveis.txt' -ErrorAction SilentlyContinue
$vazou = @($espioes | Where-Object { (Get-Content $_.FullName -Raw) -match '\S' })
if (-not $espioes) { Write-Host 'ESPIÃO: nenhum registro gerado.'; $falhas++ }
elseif ($vazou) { Write-Host "ESPIÃO: variáveis do simulado visíveis ao controlador em $($vazou.Count) cenário(s)."; $falhas++ }
else { Write-Host "ESPIÃO: nenhuma variável do simulado visível ao controlador ($($espioes.Count) cenários)." }
$tabela | Format-Table -AutoSize | Out-String | Write-Host
if ($falhas) { Write-Host "VALIDAÇÃO FALHOU em $falhas caso(s)."; exit 1 }
Write-Host 'VALIDAÇÃO OK: o script de teste pontua exatamente como esperado.'
exit 0
