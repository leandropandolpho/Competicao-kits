# testar-combinada.ps1 — testes determinísticos da regra de combinação (A, B, troca, árbitro) com provedores simulados.
# Uso: pwsh -NoProfile -File supervisora/testes/testar-combinada.ps1
$ErrorActionPreference = 'Stop'
$Comb = (Resolve-Path (Join-Path $PSScriptRoot '../supervisao-combinada.ps1')).Path
$Fake = (Resolve-Path (Join-Path $PSScriptRoot 'fake-supervisora.ps1')).Path
$falhas = 0; $total = 0

function Novo-Caso([string]$status, [bool]$semAlteracao, [bool]$alterarTesteDepois = $false, [string]$relato = 'Não alterei nada.', [string]$prompt = 'Faça algo.') {
  $b = Join-Path ([IO.Path]::GetTempPath()) ('supt-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
  $repo = Join-Path $b 'repo'; $est = Join-Path $b 'estado'
  New-Item -ItemType Directory -Force (Join-Path $repo 'testes'), (Join-Path $repo 'src'), $est | Out-Null
  Set-Content (Join-Path $repo 'src/calc.ps1') 'function Soma($a,$b){ $a + $b }'
  Set-Content (Join-Path $repo 'testes/teste-calc.ps1') 'exit 0'
  git init -q $repo; git -C $repo config user.email t@t; git -C $repo config user.name t; git -C $repo add -A; git -C $repo commit -qm base
  $base = git -C $repo rev-parse HEAD
  $h = (Get-FileHash (Join-Path $repo 'testes/teste-calc.ps1')).Hash
  [ordered]@{ tarefa_atual = $null; commit_base = $base; hash_testes = @{ 'testes/teste-calc.ps1' = $h }; status_execucao = $status } | ConvertTo-Json | Set-Content (Join-Path $est 'estado.json')
  @{ tarefas = @(@{ id = 'X1'; titulo = 'Tarefa de teste'; prompt = $prompt; status = $status; tentativas = 1; depends_on = @(); critica = $false }) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $b 'TAREFAS.json')
  $ev = @(
    @{ ts = 't0'; evento = 'inicio' },
    @{ ts = 't1'; evento = 'executor'; tarefa = 'X1'; tentativa = 1; resumo = $relato; custo_usd = 0.1; falhou = $false },
    @{ ts = 't2'; evento = 'teste'; passou = ($status -ne 'failed'); saida = 'PASSOU' })
  if ($semAlteracao) { $ev += @{ ts = 't3'; evento = 'sem_alteracao'; tarefa = 'X1'; tentativa = 1 } }
  $msg = if ($status -eq 'failed') { 'Tarefa X1 falhou após 1 tentativa(s).' } elseif ($semAlteracao) { 'HOLD na tarefa X1: SEM_ALTERACAO — o executor terminou sem alterar nenhum arquivo.' } else { 'HOLD na tarefa X1: arquivo rastreado removido: src/extra.ps1.' }
  $ev += @{ ts = 't4'; evento = 'status_tarefa'; tarefa = 'X1'; status = $status }
  $ev += @{ ts = 't5'; evento = 'notificacao'; mensagem = $msg }
  ($ev | ForEach-Object { $_ | ConvertTo-Json -Compress }) | Set-Content (Join-Path $est 'log.jsonl')
  Set-Content (Join-Path $est 'notificacoes.txt') "[t4] $msg"
  if ($alterarTesteDepois) { Set-Content (Join-Path $repo 'testes/teste-calc.ps1') 'exit 1' }
  return @{ Base = $b; Repo = $repo; Estado = $est; Tarefas = (Join-Path $b 'TAREFAS.json'); Mock = (Join-Path $b 'mock') }
}

function Lancador($c, [string]$modo) {
  # Chama o simulado direto pelo pwsh, com prefixo de argumentos. Sem .cmd/.sh no meio: o cmd.exe corta
  # argumentos com quebra de linha (o prompt de sistema), o que falsearia os testes de argumentos.
  $pw = (Get-Process -Id $PID).Path
  return @{ Cmd = $pw; Prefixo = (@('-NoProfile', '-File', $Fake, '--mock-modo', $modo, '--mock-dir', $c.Mock) -join '|') }
}



function Novo-LinkPasta([string]$link, [string]$alvo) {
  # Windows: junction (não exige administrador); Linux/macOS: link simbólico.
  New-Item -ItemType Directory -Force $alvo | Out-Null
  if ($IsWindows) { New-Item -ItemType Junction -Path $link -Target $alvo | Out-Null } else { New-Item -ItemType SymbolicLink -Path $link -Target $alvo | Out-Null }
}

function LancadorEm($c, [string]$nome, [string]$modos) {
  $sub = @{ Base = (Join-Path $c.Base $nome); Mock = (Join-Path $c.Base "mock-$nome") }
  New-Item -ItemType Directory -Force $sub.Base | Out-Null
  $l = Lancador $sub $modos; return @{ Cmd = $l.Cmd; Prefixo = $l.Prefixo; Mock = $sub.Mock }
}
function Chamadas($m) { $f = Join-Path $m 'chamadas.txt'; if (Test-Path $f) { [int](Get-Content $f -Raw) } else { 0 } }
function ArgsDe($m, $n) { $f = Join-Path $m "args-$n.json"; if (Test-Path $f) { Get-Content $f -Raw | ConvertFrom-Json } else { $null } }

function Combinar($c, [string]$modosA, [string]$modosB, [string]$modosM = 'escalar') {
  $A = LancadorEm $c 'A' $modosA; $B = LancadorEm $c 'B' $modosB; $M = LancadorEm $c 'M' $modosM
  $hT = (Get-FileHash $c.Tarefas).Hash; $head = git -C $c.Repo rev-parse HEAD
  $saida = Join-Path $c.Base 'comb'
  $out = & pwsh -NoProfile -File $Comb -RepoPath $c.Repo -TarefasPath $c.Tarefas -EstadoDir $c.Estado -SaidaDir $saida `
           -ProvedorA claude -ProvedorB claude -ProvedorArbitro claude -CmdA $A.Cmd -CmdB $B.Cmd -CmdArbitro $M.Cmd -PrefixoA $A.Prefixo -PrefixoB $B.Prefixo -PrefixoArbitro $M.Prefixo -TimeoutSec 60 2>&1
  $res = Get-Content (Join-Path $saida 'decisao-combinada.json') -Raw | ConvertFrom-Json
  return @{ Res = $res; A = $A.Mock; B = $B.Mock; M = $M.Mock; Saida = ($out -join ' ')
            Intacto = ((Get-FileHash $c.Tarefas).Hash -eq $hT) -and ((git -C $c.Repo rev-parse HEAD) -eq $head) -and -not (git -C $c.Repo status --porcelain) }
}
function Checar([string]$nome, [scriptblock]$cond, $r) {
  $script:total++; $ok = $false; try { $ok = [bool](& $cond $r) } catch { }
  if (-not $ok) { $script:falhas++ }
  "  [$(if ($ok) {'ok'} else {'FALHOU'})] $nome" + $(if (-not $ok) { " → final=$($r.Res.decisao_final) via=$($r.Res.via) marca=$($r.Res.marca) | $($r.Saida)" } else { '' })
}

"== K1 A e B concordam (escalar)"
$c = Novo-Caso 'hold' $true; $r = Combinar $c 'escalar' 'escalar'
Checar 'final escalar por consenso independente' { param($r) $r.Res.decisao_final -eq 'escalar' -and $r.Res.via -eq 'consenso_independente' } $r
Checar 'sem troca nem árbitro (1 chamada cada, árbitro 0)' { param($r) (Chamadas $r.A) -eq 1 -and (Chamadas $r.B) -eq 1 -and (Chamadas $r.M) -eq 0 } $r
Checar 'nada do projeto alterado' { param($r) $r.Intacto } $r

"== K2 divergem e convergem na troca"
$c = Novo-Caso 'hold' $true; $r = Combinar $c 'liberar_alta,liberar_alta' 'escalar,liberar_alta'
Checar 'final liberar por consenso após troca' { param($r) $r.Res.decisao_final -eq 'liberar' -and $r.Res.via -eq 'consenso_apos_troca' } $r
Checar 'na troca, A recebeu o parecer de B e B o de A' { param($r) (ArgsDe $r.A 2).tem_parecer -and (ArgsDe $r.B 2).tem_parecer -and -not (ArgsDe $r.A 1).tem_parecer } $r
Checar 'árbitro não chamado' { param($r) (Chamadas $r.M) -eq 0 } $r

"== K3 divergem após troca; árbitro decide com confiança alta (escalar)"
$c = Novo-Caso 'hold' $true; $r = Combinar $c 'liberar_alta' 'escalar' 'escalar'
Checar 'final escalar por voto de Minerva' { param($r) $r.Res.decisao_final -eq 'escalar' -and $r.Res.via -eq 'voto_de_minerva' } $r
Checar 'árbitro recebeu os dois pareceres e o papel de árbitro' { param($r) $a = ArgsDe $r.M 1; $a.tem_parecer -and $a.arbitro } $r
Checar 'trilha com 5 etapas' { param($r) @($r.Res.trilha).Count -eq 5 } $r

"== K4 árbitro libera contra B"
$c = Novo-Caso 'hold' $true; $r = Combinar $c 'liberar_alta' 'escalar' 'liberar_alta'
Checar 'final liberar, marcado liberar_por_desempate' { param($r) $r.Res.decisao_final -eq 'liberar' -and $r.Res.marca -eq 'liberar_por_desempate' } $r

"== K5 árbitro em dúvida (confiança média)"
$c = Novo-Caso 'failed' $false; $r = Combinar $c 'escalar' 'replanejar' 'replanejar'
Checar 'final escalar (arbitro_em_duvida)' { param($r) $r.Res.decisao_final -eq 'escalar' -and $r.Res.via -eq 'arbitro_em_duvida' } $r

"== K6 gatilho R1"
$c = Novo-Caso 'hold' $false; $r = Combinar $c 'liberar_alta' 'liberar_alta' 'liberar_alta'
Checar 'final escalar por regra_R1, sem votação' { param($r) $r.Res.decisao_final -eq 'escalar' -and $r.Res.via -eq 'regra_R1' -and (Chamadas $r.A) -eq 0 -and (Chamadas $r.B) -eq 0 -and (Chamadas $r.M) -eq 0 } $r

"== K7 B falha (saída não-JSON)"
$c = Novo-Caso 'hold' $true; $r = Combinar $c 'liberar_alta' 'naojson'
Checar 'final escalar por falha, sem troca' { param($r) $r.Res.decisao_final -eq 'escalar' -and $r.Res.via -like 'falha*' -and (Chamadas $r.M) -eq 0 } $r

"== K8 liberar de A invalidado (confiança média) não vira voto"
$c = Novo-Caso 'hold' $true; $r = Combinar $c 'liberar_media' 'liberar_alta'
Checar 'final escalar' { param($r) $r.Res.decisao_final -eq 'escalar' } $r

"== K9 (F5-03) A contra, B a favor, árbitro libera"
$c = Novo-Caso 'hold' $true; $r = Combinar $c 'escalar' 'liberar_alta' 'liberar_alta'
Checar 'final liberar, marcado liberar_por_desempate' { param($r) $r.Res.decisao_final -eq 'liberar' -and $r.Res.via -eq 'voto_de_minerva' -and $r.Res.marca -eq 'liberar_por_desempate' } $r

"== K10 (F5-01) SaidaDir dentro do repositório"
$c = Novo-Caso 'hold' $true; $A = LancadorEm $c 'A' 'escalar'
& pwsh -NoProfile -File $Comb -RepoPath $c.Repo -TarefasPath $c.Tarefas -EstadoDir $c.Estado -SaidaDir (Join-Path $c.Repo 'comb') -CmdA $A.Cmd -CmdB $A.Cmd -CmdArbitro $A.Cmd -PrefixoA $A.Prefixo -PrefixoB $A.Prefixo -PrefixoArbitro $A.Prefixo -ProvedorB claude 2>&1 | Out-Null
$codigo = $LASTEXITCODE
Checar 'recusado (código 4), nada criado no repo' { param($r) $codigo -eq 4 -and -not (Test-Path (Join-Path $c.Repo 'comb')) -and -not (git -C $c.Repo status --porcelain) } $null

"== K11 (F5-01-R) SaidaDir da combinada é link/junction para dentro do repo"
$c = Novo-Caso 'hold' $true; $A = LancadorEm $c 'A' 'escalar'; $alvo = Join-Path $c.Repo 'alvo'
Novo-LinkPasta (Join-Path $c.Base 'comb-link') $alvo
& pwsh -NoProfile -File $Comb -RepoPath $c.Repo -TarefasPath $c.Tarefas -EstadoDir $c.Estado -SaidaDir (Join-Path $c.Base 'comb-link') -CmdA $A.Cmd -CmdB $A.Cmd -CmdArbitro $A.Cmd -PrefixoA $A.Prefixo -PrefixoB $A.Prefixo -PrefixoArbitro $A.Prefixo -ProvedorB claude 2>&1 | Out-Null
$codigo = $LASTEXITCODE
Checar 'recusado (4), nada gravado no repo' { param($r) $codigo -eq 4 -and -not @(Get-ChildItem $alvo -Force).Count } $null

"TOTAL COMBINADA: $($total - $falhas) / $total"
exit $(if ($falhas) { 1 } else { 0 })
