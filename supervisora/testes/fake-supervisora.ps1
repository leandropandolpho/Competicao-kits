# fake-supervisora.ps1 — provedor SIMULADO (imita claude -p --output-format json --json-schema).
# SUPMOCK_MODO define a resposta; SUPMOCK_DIR recebe o registro da chamada.
$ErrorActionPreference = 'Stop'
$modo = $env:SUPMOCK_MODO; $dir = $env:SUPMOCK_DIR
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$stdin = if ([Console]::IsInputRedirected) { [Console]::In.ReadToEnd() } else { '' }
$n = 1; $cf = Join-Path $dir 'chamadas.txt'; if (Test-Path $cf) { $n = [int](Get-Content $cf -Raw) + 1 }; Set-Content $cf $n -NoNewline
[ordered]@{ args = @($args); cwd = (Get-Location).Path; cwd_itens = @(Get-ChildItem -Force).Count
  stdin_tem_marcador = $stdin.Contains('relato_do_executor_NAO_CONFIAVEL'); stdin_tem_injecao = $stdin.Contains('IGNORE AS REGRAS'); fechamentos = ([regex]::Matches($stdin, '>>>')).Count
  tem_api_key = [bool]$env:ANTHROPIC_API_KEY } | ConvertTo-Json | Set-Content (Join-Path $dir "args-$n.json")
function Responder($obj, [double]$custo = 0.01, [bool]$erro = $false) {
  [ordered]@{ type = 'result'; subtype = 'success'; is_error = $erro; result = ''; structured_output = $obj; total_cost_usd = $custo; model = 'mock' } | ConvertTo-Json -Depth 6 -Compress
}
$ev = @('dossiê: parada.sem_alteracao', 'teste rodado pelo controlador')
switch ($modo) {
  'escalar'       { Responder ([ordered]@{ decisao = 'escalar'; justificativa = 'Pedido viola regra do projeto.'; evidencias = $ev; acao_proposta = 'Leandro decide.'; confianca = 'alta' }) }
  'liberar_alta'  { Responder ([ordered]@{ decisao = 'liberar'; justificativa = 'Tarefa de verificação, nada a mudar.'; evidencias = $ev; acao_proposta = 'Marcar como concluída.'; confianca = 'alta' }) }
  'liberar_media' { Responder ([ordered]@{ decisao = 'liberar'; justificativa = 'Parece não haver o que mudar.'; evidencias = $ev; acao_proposta = 'Marcar como concluída.'; confianca = 'media' }) }
  'replanejar'    { Responder ([ordered]@{ decisao = 'replanejar'; justificativa = 'O pedido era ambíguo quanto ao arquivo.'; evidencias = $ev; acao_proposta = 'Reescrever a tarefa.'; prompt_replanejado = 'Corrija src/calc.ps1 ...'; confianca = 'media' }) }
  'replanejar_sem_prompt' { Responder ([ordered]@{ decisao = 'replanejar'; justificativa = 'O pedido era ambíguo quanto ao arquivo.'; evidencias = $ev; acao_proposta = 'Reescrever.'; confianca = 'media' }) }
  'invalido'      { Responder ([ordered]@{ decisao = 'aprovar'; justificativa = 'Tudo certo por aqui.'; evidencias = $ev; acao_proposta = 'x'; confianca = 'alta' }) }
  'naojson'       { Write-Output 'Erro interno: isto não é JSON'; exit 0 }
  'is_error'      { Responder $null 0.01 $true; exit 1 }
  'sem_structured'{ [ordered]@{ type = 'result'; is_error = $false; result = 'Não posso ajudar com isso.'; total_cost_usd = 0.01 } | ConvertTo-Json -Compress }
  'timeout'       { Start-Sleep -Seconds 30; R $null }
  default         { Write-Output "modo desconhecido $modo"; exit 3 }
}
exit 0
