# claude-ponte.ps1 - wrapper do modo PRINCIPAL-ISOLADO (REQ-08). gate-pe. Ato 145.
# Chamado pelo CONTROLADOR CONGELADO (7cd7864) como ClaudeCmd, no lugar do claude, quando a config seleciona a ponte
# (flag de config = qual ClaudeCmd o controlador recebe). NAO modifica claude-com-teto.ps1 nem o controlador: ambos
# permanecem com diff VAZIO vs a baseline (I1). A escolha da ponte e EXTERNA aos dois (transparente ao controlador).
# Delega o disparo+contabilidade ao Invoke-PontePU-V1 (o PU, b05/pe/ponte-pu.ps1): reserva/admissao (REQ-02), morte do
# PE (REQ-03), reparse (REQ-07), evidencia+trava (REQ-11), reconciliacao D-06. NAO importa nada da arvore de trabalho (I2).
# Traduz o resultado da ponte para o formato do `claude -p --output-format json`. Codigos: 0 ok; 1 falha comum (retry do
# controlador); 28 financeiro; 70 seguranca (a notificacao/matriz diz "TRAVA DE SEGURANCA 70 - evidencia em <pasta>", C-02).
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Resp([string]$result,[bool]$isErr,[double]$custo,[string]$subtype) {
  $o = [ordered]@{ type='result'; is_error=$isErr; result=$result; total_cost_usd=$custo }
  if ($subtype) { $o['subtype'] = $subtype }
  [Console]::Out.Write(($o | ConvertTo-Json -Compress))
}
# Falha controlada no formato do claude -p: o controlador congelado trata como falha da tentativa (custo 0, sem commit).
function Sair-Erro([string]$msg,[int]$cod) { Resp "ponte: $msg" $true 0 'error_ponte'; exit $cod }

$dir = $env:B05_DIR; $execucao = $env:B05_EXECUCAO
if (-not $dir -or -not $execucao -or $execucao -notmatch '^[0-9a-f]{32}$') { Sair-Erro 'B05_DIR/B05_EXECUCAO ausente/invalido' 1 }
$arqCfg = Join-Path $dir "config-$execucao.json"
if (-not (Test-Path -LiteralPath $arqCfg)) { Sair-Erro "config da execucao ausente: config-$execucao.json" 1 }
$cfg = Get-Content -LiteralPath $arqCfg -Raw -Encoding utf8 | ConvertFrom-Json
if ("$($cfg.execucao)" -ne $execucao) { Sair-Erro 'config nao corresponde a execucao' 1 }

# Prompt: o controlador passa `-p <prompt>` (ou o prompt via stdin). Extrai sem depender de parser nomeado.
$prompt = ''
$lista = @($args | ForEach-Object { [string]$_ })
for ($i = 0; $i -lt $lista.Count; $i++) { if ($lista[$i] -eq '-p' -and ($i + 1) -lt $lista.Count) { $prompt = $lista[$i + 1]; break } }
if (-not $prompt -and [Console]::IsInputRedirected) { $prompt = [Console]::In.ReadToEnd() }

# Nucleo do PU, carregado de FORA da arvore de trabalho (I2): mesma pasta deste wrapper (b05/pe), protegida por ACL/IL
# e com SHA-256 conferido pelo provisionamento (copia confiavel do PU). O fonte no GitHub nao substitui a protecao runtime.
. (Join-Path $PSScriptRoot 'ponte-pu.ps1')

$teto = [double]$cfg.teto_chamada_usd; $folga = [double]$cfg.folga; $orc = [double]$cfg.orcamento_usd
$timeout = if ($cfg.PSObject.Properties['timeout_ponte_seg'] -and $cfg.timeout_ponte_seg) { [int]$cfg.timeout_ponte_seg } else { 120 }
$pedido = @{ executor = "$($cfg.executor)"; executor_prefixo = "$($cfg.executor_prefixo)"; test_cmd = ''; teto_usd = $teto }

$res = Invoke-PontePU-V1 -PonteDir "$($cfg.ponte_dir)" -TrabDir (Get-Location).Path -AcaoPs1 "$($cfg.acao_pe)" `
  -PwshAprovado "$($cfg.pwsh_aprovado)" -PwshSha256 "$($cfg.pwsh_sha256)" -Pedido $pedido -Prompt $prompt `
  -TimeoutSeg $timeout -EvidenciaDir "$($cfg.evidencia_dir)" -TravaDir "$($cfg.trava_dir)" `
  -RazaoDir $dir -Folga $folga -MaxUsd $orc

# V1-F04 (ChatGPT Ato 147): quando o razao tem custo CONHECIDO (ex.: falha de teste apos executor), devolver esse custo
# ao controlador, nunca 0 - senao o controlador subcontabiliza o gasto ja reconhecido no razao.
$custoResp = if ($res.CustoConhecido) { [double]$res.CustoUsd } else { 0.0 }
switch ([int]$res.Codigo) {
  0  { [Console]::Out.Write([string]$res.Saida); if ($res.Erro) { [Console]::Error.Write([string]$res.Erro) }; exit 0 }
  70 { Resp "ponte: TRAVA DE SEGURANCA 70 - evidencia em $($res.Evidencia): $($res.Motivo)" $true $custoResp 'error_ponte'; exit 70 }
  28 { Resp "ponte: bloqueio financeiro (28): $($res.Motivo)" $true $custoResp 'error_ponte'; exit 28 }
  default { Resp "ponte: falha (codigo $($res.Codigo)): $($res.Motivo)" $true $custoResp 'error_ponte'; exit ([int]$res.Codigo) }
}
