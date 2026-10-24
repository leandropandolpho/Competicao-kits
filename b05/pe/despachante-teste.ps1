# despachante-teste.ps1 - Despachante P-B da FASE TESTE (D-2, Ato 147). gate-pe.
# O controlador CONGELADO recebe este script como $TestCmd (passo 6). Ele roda como PU, mas NAO executa o codigo do
# teste diretamente: despacha o $TestCmd real a ponte em modo SOMENTE-TESTE, de modo que o teste roda sob o PE em
# Low IL, em Job NOVO e independente, sem a chave, com a pasta-ponte/teste.txt em Medium. Preserva I2 (o PU nunca roda
# codigo do repositorio no passo 6) e fecha o achado V1-F02/F03 do Ato 147. Vive FORA da arvore de trabalho; o fonte
# confiavel e conferido por SHA no provisionamento (como o pwsh e o claude-ponte). Nao importa nada da arvore (I2).
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$dir = $env:B05_DIR; $execucao = $env:B05_EXECUCAO
if (-not $dir -or -not $execucao -or $execucao -notmatch '^[0-9a-f]{32}$') { [Console]::Error.Write('despachante-teste: B05_DIR/B05_EXECUCAO ausente/invalido'); exit 1 }
$arqCfg = Join-Path $dir "config-$execucao.json"
if (-not (Test-Path -LiteralPath $arqCfg)) { [Console]::Error.Write("despachante-teste: config ausente: config-$execucao.json"); exit 1 }
$cfg = Get-Content -LiteralPath $arqCfg -Raw -Encoding utf8 | ConvertFrom-Json
if ("$($cfg.execucao)" -ne $execucao) { [Console]::Error.Write('despachante-teste: config nao corresponde a execucao'); exit 1 }
$testeReal = "$($cfg.test_cmd_real)"
if (-not $testeReal) { [Console]::Error.Write('despachante-teste: config sem test_cmd_real'); exit 1 }

# Copia confiavel do PU (convergencia com a Perplexity, Ato 148): confere o SHA-256 do NUCLEO ANTES do dot-source. Se a
# config traz hashes_nucleo, qualquer divergencia => exit 97 (SHA divergente), sem carregar/disparar nada. O fonte no
# GitHub nao substitui a protecao em runtime; este check garante que o PU nao carregue um nucleo adulterado.
if ($cfg.PSObject.Properties['hashes_nucleo'] -and $cfg.hashes_nucleo) {
  $raizPe = $PSScriptRoot
  $mapa = @{ 'ponte-pu.ps1' = (Join-Path $raizPe 'ponte-pu.ps1'); 'acao-pe.ps1' = (Join-Path $raizPe 'acao-pe.ps1')
    'b05job.ps1' = (Join-Path $raizPe '..\b05job.ps1'); 'baixa-integridade.ps1' = (Join-Path $raizPe '..\baixa-integridade.ps1')
    'razao.ps1' = (Join-Path $raizPe '..\razao.ps1') }
  foreach ($k in $cfg.hashes_nucleo.PSObject.Properties.Name) {
    $esperado = "$($cfg.hashes_nucleo.$k)".ToUpper().Replace(':', '')
    $p = $mapa[$k]
    if (-not $p -or -not (Test-Path -LiteralPath $p)) { [Console]::Error.Write("despachante: arquivo do nucleo ausente: $k"); exit 97 }
    $real = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpper()
    if ($real -ne $esperado) { [Console]::Error.Write("despachante: SHA-256 do nucleo divergente ($k): $real != $esperado"); exit 97 }
  }
}
# Nucleo do PU, de fora da arvore de trabalho (I2), protegido por ACL/IL e SHA no provisionamento.
. (Join-Path $PSScriptRoot 'ponte-pu.ps1')

# Modo somente-teste: o acao-pe NAO roda o executor; roda SO o $TestCmd sob o PE em Low IL, no Job novo, sem a chave.
$pedido = @{ somente_teste = $true; test_cmd = $testeReal; teto_usd = 0 }
$timeout = if ($cfg.PSObject.Properties['timeout_ponte_seg'] -and $cfg.timeout_ponte_seg) { [int]$cfg.timeout_ponte_seg } else { 120 }
$res = Invoke-PontePU-V1 -PonteDir "$($cfg.ponte_dir)" -TrabDir (Get-Location).Path -AcaoPs1 "$($cfg.acao_pe)" `
  -PwshAprovado "$($cfg.pwsh_aprovado)" -PwshSha256 "$($cfg.pwsh_sha256)" -Pedido $pedido -Prompt '' `
  -TimeoutSeg $timeout -EvidenciaDir "$($cfg.evidencia_dir)" -TravaDir "$($cfg.trava_dir)" -RazaoDir ''

# Codigo 0 = teste passou. !=0 = reprovado/violacao -> o controlador faz rollback/retry (passo 9). Preserva 28/70.
if ([int]$res.Codigo -eq 0) { exit 0 }
[Console]::Error.Write("despachante-teste: teste NAO aprovado via ponte (codigo=$($res.Codigo)): $($res.Motivo)")
exit ([int]$res.Codigo)
