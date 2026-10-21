# supervisao-combinada.ps1 — Regra de combinação da fase 5 (condição 7 do Ato 047, ajustada por Leandro no Ato 061).
#   1) A (Claude) e B (OpenAI) avaliam o mesmo dossiê, independentes.
#   2) Concordaram → decisão final.
#   3) Divergiram → 1 rodada de TROCA: cada uma recebe o parecer da outra e reavalia.
#   4) Ainda divergem → ÁRBITRO (voto de Minerva, Claude em papel de árbitro, com os dois pareceres).
#   5) Árbitro sem confiança alta, ou qualquer falha → ESCALAR para Leandro.
# Travas que nenhuma votação derruba:
#   - Gatilho R1 → escalar, sem votação (a supervisora nem chama a LLM).
#   - Falha de qualquer provedor → escalar.
#   - "liberar" decidido só pelo árbitro (B não concordou) fica marcado como 'liberar_por_desempate':
#     vale como recomendação na fase 5, mas NÃO pode ser usado em execução sem supervisão (B-07).
# Como a supervisora, este script só recomenda: não altera tarefas, repositório nem estado do controlador.
param(
  [Parameter(Mandatory)][string]$RepoPath,
  [Parameter(Mandatory)][string]$TarefasPath,
  [Parameter(Mandatory)][string]$EstadoDir,
  [Parameter(Mandatory)][string]$SaidaDir,
  [string]$ContextoPath = '',
  [ValidateSet('claude', 'openai')][string]$ProvedorA = 'claude',
  [ValidateSet('claude', 'openai')][string]$ProvedorB = 'openai',
  [ValidateSet('claude', 'openai')][string]$ProvedorArbitro = 'claude',
  [string]$CmdA = 'claude', [string]$CmdB = 'claude', [string]$CmdArbitro = 'claude',
  [string]$PrefixoA = '', [string]$PrefixoB = '', [string]$PrefixoArbitro = '',
  [double]$MaxCustoChamadaUsd = 0.50,
  [double]$MaxCustoTotalUsd   = 5.00,
  [int]$TimeoutSec            = 180,
  [string]$OpenAIChavePath    = '',
  [string]$OpenAIUrl          = 'https://api.openai.com/v1/responses',
  [int]$PausaEntreChamadasSec = 0
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$Utf8 = [System.Text.UTF8Encoding]::new($false)
$Sup = Join-Path $PSScriptRoot 'supervisora.ps1'
# F5-01/F5-01-R: saída fora do repositório, sem links/junctions no caminho nem dentro dela.
. (Join-Path $PSScriptRoot 'caminhos.ps1')
$RepoRaiz = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepoPath).ProviderPath).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$rr = Primeiro-Redirecionamento $RepoPath
if ($rr) { [Console]::Error.WriteLine("RepoPath passa por link/junction: $rr"); exit 4 }
$m = Validar-Saida $SaidaDir $RepoRaiz
if ($m) { [Console]::Error.WriteLine($m); exit 4 }
New-Item -ItemType Directory -Force -Path $SaidaDir | Out-Null
$SaidaDir = (Resolve-Path -LiteralPath $SaidaDir).ProviderPath
$m = Validar-Saida $SaidaDir $RepoRaiz
if ($m) { [Console]::Error.WriteLine($m); exit 4 }
$ArqCusto = Join-Path $SaidaDir 'custo-combinado.json'

function Prop($o, [string]$n) { if ($null -ne $o -and $o.PSObject.Properties[$n]) { $o.$n } else { $null } }

function Custo-Acumulado {
  $t = 0.0
  foreach ($f in @(Get-ChildItem -Path $SaidaDir -Recurse -Filter 'supervisora-estado.json' -ErrorAction SilentlyContinue)) {
    $c = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json; $t += [double]$c.custo_acumulado_usd
  }
  return $t
}

function Chamar([string]$etapa, [string]$provedor, [string]$cmd, [string]$papel, [object[]]$pareceres, [string]$prefixo = '') {
  # Teto TOTAL da combinação: soma de todas as etapas. Cada etapa tem pasta própria.
  $gasto = Custo-Acumulado
  $dir = Join-Path $SaidaDir $etapa
  if ($gasto + $MaxCustoChamadaUsd -gt $MaxCustoTotalUsd) {
    return [pscustomobject]@{ decisao = 'escalar'; origem = 'teto_de_custo_combinado'; confianca = ''; justificativa = "Teto total: US$ $gasto + $MaxCustoChamadaUsd > $MaxCustoTotalUsd"; custo_usd = 0; motivo_override = ''; tarefa = '' }
  }
  if ($PausaEntreChamadasSec -gt 0) { Start-Sleep -Seconds $PausaEntreChamadasSec }
  $a = @{ RepoPath = $RepoPath; TarefasPath = $TarefasPath; EstadoDir = $EstadoDir; SaidaDir = $dir; Provedor = $provedor
          MaxCustoChamadaUsd = $MaxCustoChamadaUsd; MaxCustoTotalUsd = $MaxCustoTotalUsd; TimeoutSec = $TimeoutSec
          ClaudeCmd = $cmd; Papel = $papel; OpenAIUrl = $OpenAIUrl }
  if ($prefixo) { $a.ClaudePrefixo = $prefixo }
  if ($ContextoPath) { $a.ContextoPath = $ContextoPath }
  if ($OpenAIChavePath) { $a.OpenAIChavePath = $OpenAIChavePath }
  if ($pareceres -and $pareceres.Count) {
    $pp = Join-Path $SaidaDir "pareceres-para-$etapa.json"
    [System.IO.File]::WriteAllText($pp, (ConvertTo-Json -InputObject @($pareceres) -Depth 5), $Utf8)
    $a.PareceresPath = $pp
  }
  & pwsh -NoProfile -File $Sup @a | Out-Null
  $rec = @(Get-Content -LiteralPath (Join-Path $dir 'recomendacoes.jsonl') -Encoding utf8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }) | Select-Object -Last 1
  if (-not $rec) { $rec = [pscustomobject]@{ decisao = 'escalar'; origem = 'sem_recomendacao'; confianca = ''; justificativa = 'A supervisora não produziu recomendação.'; custo_usd = 0; motivo_override = ''; tarefa = '' } }
  return $rec
}

function Parecer([string]$nome, $rec) { [ordered]@{ supervisora = $nome; decisao = "$($rec.decisao)"; confianca = "$($rec.confianca)"; justificativa = "$($rec.justificativa)" } }
function Falhou($rec) { "$($rec.origem)" -notin @('llm') }   # llm_invalidada, falha_do_provedor, teto… = não é voto válido

$trilha = [System.Collections.Generic.List[object]]::new()
function Registrar([string]$etapa, [string]$quem, $rec) { $trilha.Add([ordered]@{ etapa = $etapa; supervisora = $quem; decisao = "$($rec.decisao)"; origem = "$($rec.origem)"; confianca = "$($rec.confianca)"; motivo_override = "$(Prop $rec 'motivo_override')"; custo_usd = $(Prop $rec 'custo_usd'); justificativa = "$($rec.justificativa)" }) }

$final = $null; $via = ''; $marca = ''
$recA = Chamar 'A1' $ProvedorA $CmdA 'supervisora' @() $PrefixoA; Registrar 'independente' 'A' $recA
if ("$($recA.origem)" -eq 'regra_R1') { $final = 'escalar'; $via = 'regra_R1' }
else {
  $recB = Chamar 'B1' $ProvedorB $CmdB 'supervisora' @() $PrefixoB; Registrar 'independente' 'B' $recB
  if ((Falhou $recA) -or (Falhou $recB)) { $final = 'escalar'; $via = 'falha_ou_invalidada_na_avaliacao_independente' }
  elseif ($recA.decisao -eq $recB.decisao) { $final = "$($recA.decisao)"; $via = 'consenso_independente' }
  else {
    # Rodada de troca: cada uma vê o parecer da outra.
    $recA2 = Chamar 'A2' $ProvedorA $CmdA 'supervisora' @((Parecer 'B' $recB)) $PrefixoA; Registrar 'troca' 'A' $recA2
    $recB2 = Chamar 'B2' $ProvedorB $CmdB 'supervisora' @((Parecer 'A' $recA)) $PrefixoB; Registrar 'troca' 'B' $recB2
    if ((Falhou $recA2) -or (Falhou $recB2)) { $final = 'escalar'; $via = 'falha_ou_invalidada_na_troca' }
    elseif ($recA2.decisao -eq $recB2.decisao) { $final = "$($recA2.decisao)"; $via = 'consenso_apos_troca' }
    else {
      $recM = Chamar 'M' $ProvedorArbitro $CmdArbitro 'arbitro' @((Parecer 'A' $recA2), (Parecer 'B' $recB2)) $PrefixoArbitro; Registrar 'desempate' 'arbitro' $recM
      if (Falhou $recM) { $final = 'escalar'; $via = 'falha_ou_invalidada_no_desempate' }
      elseif ("$($recM.confianca)" -ne 'alta') { $final = 'escalar'; $via = 'arbitro_em_duvida' }
      else {
        $final = "$($recM.decisao)"; $via = 'voto_de_minerva'
        # F5-03: TODA liberação decidida pelo voto de Minerva é marcada, seja quem for que discordou.
        if ($final -eq 'liberar') { $marca = 'liberar_por_desempate' }
      }
    }
  }
}

$res = [ordered]@{ ts = (Get-Date).ToString('o'); decisao_final = $final; via = $via; marca = $marca
                   custo_total_usd = [math]::Round((Custo-Acumulado), 6); trilha = @($trilha) }
[System.IO.File]::WriteAllText((Join-Path $SaidaDir 'decisao-combinada.json'), ($res | ConvertTo-Json -Depth 6), $Utf8)
"COMBINADA | decisão final: $final | via: $via$(if ($marca) { " | $marca" }) | etapas: $($trilha.Count) | US$ $($res.custo_total_usd)"
exit 0
