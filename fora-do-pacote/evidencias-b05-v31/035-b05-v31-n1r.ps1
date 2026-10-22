# 035 — (repetição de N1r/N6 com tarefa inédita: Divide já existia desde o 028) Ato 077: nova candidata B-05 v3.1 com o Claude REAL e o pwsh PORTÁTIL: N1r (queda real, descendentes do claude.exe),
# N2/N6, P1/P2 pelo lançador, reconciliação, harness 40/40.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
if ($env:Path -notlike "*$env:USERPROFILE\.local\bin*") { $env:Path += ";$env:USERPROFILE\.local\bin" }
$base = "$env:USERPROFILE\piloto"; $out = "$base\ponte\saida\035-relatorio.txt"; $h = "$base\harness"
$PwP = "$base\ferramentas\pwsh-7.6.7\pwsh.exe"; $env:Path = "$(Split-Path $PwP);$env:Path"
& {
  "=== INICIO $(Get-Date -Format s) | $env:USERNAME"
  git -C $h fetch -q origin hibrido 2>&1; git -C $h -c advice.detachedHead=false checkout -q 40def253eda823b4d5266634498b6d710bed15fa 2>&1
  "commit: " + (git -C $h rev-parse HEAD) + " | controlador: " + (Get-FileHash "$h\kits\kit-A\controlador.ps1").Hash.Substring(0, 16)
  Get-FileHash "$h\b05\*.ps1", "$h\b05\*.cmd" | ForEach-Object { "$($_.Hash) $(Split-Path $_.Path -Leaf)" }
  . "$h\b05\razao.ps1"
  $Pw = $PwP
  "pwsh portátil: " + (Get-FileHash $PwP).Hash
  function Lancar($tf, $ed, $rz, [int]$tent, [switch]$Assinc) {
    $a = @('-NoProfile', '-File', "$h\b05\lancador.ps1", '-RepoPath', "$base\repo", '-TarefasPath', $tf, '-EstadoDir', $ed, '-RazaoDir', $rz,
           '-ControladorPath', "$h\kits\kit-A\controlador.ps1", '-TestCmd', 'pwsh -NoProfile -File testes/teste-calc.ps1', '-TestPaths', 'testes/*',
           '-OrcamentoUsd', '3', '-TetoChamadaUsd', '0.5', '-Folga', '0.25', '-MaxTentativas', "$tent", '-TimeoutSec', '300', '-MaxMinutos', '10')
    if ($Assinc) { $psi = [System.Diagnostics.ProcessStartInfo]::new($Pw); foreach ($x in $a) { $psi.ArgumentList.Add($x) }; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; return [System.Diagnostics.Process]::Start($psi) }
    & $Pw @a 2>&1 | Select-Object -Last 3; return $LASTEXITCODE
  }
  function Nova-Tarefa($nome, $id, $titulo, $prompt) {
    $tf = "$base\TAREFAS-$nome.json"; $ed = "$base\estado-$nome"; $rz = "$base\razao-$nome"
    foreach ($d in $ed, $rz) { if (Test-Path $d) { Get-ChildItem $d -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }; Remove-Item -Recurse -Force $d } }
    @{ tarefas = @(@{ id = $id; titulo = $titulo; prompt = $prompt; depends_on = @(); status = 'pending'; tentativas = 0; critica = $false }) } | ConvertTo-Json -Depth 5 | Set-Content $tf
    return @{ T = $tf; E = $ed; R = $rz }
  }
  function Status($tf) { (Get-Content $tf -Raw | ConvertFrom-Json).tarefas[0].status }

  "===== N1/N2/N6 com Claude real"
  $x = Nova-Tarefa 'b05-n1r' 'I5' 'Adicionar funcao Potencia' 'Em src/calc.ps1, adicione uma funcao Potencia($a, $b) que retorna [math]::Pow($a, $b), com um comentario curto em portugues. Nao altere as outras funcoes nem os testes.'
  $head0 = git -C "$base\repo" rev-parse HEAD
  $l = Lancar $x.T $x.E $x.R 2 -Assinc
  $lim = (Get-Date).AddSeconds(60); $pe = $null
  while ((Get-Date) -lt $lim -and -not $pe) { Start-Sleep 1; $ev = @((Razao-Ler $x.R).Eventos | Where-Object evento -eq 'pid'); if ($ev.Count) { $pe = $ev[-1] } }
  Start-Sleep 3
  $evs = (Razao-Ler $x.R).Eventos
  $membros = @($evs | Where-Object evento -eq 'membros_job' | ForEach-Object { @($_.pids) })
  $exe = (Get-Process -Id $pe.pid -ErrorAction SilentlyContinue).Path
  "claude pid $($pe.pid) ($exe) | em_job: $($pe.em_job) | na lista do job: $($membros -contains [int]$pe.pid) | --max-budget-usd nos args: $((@($pe.argumentos) -join ' ') -match '--max-budget-usd 0\.5')"
  "versão registrada: " + (@($evs | Where-Object evento -eq 'controlador'))[0].versao_claude
  # Árvore inteira abaixo do lançador antes da queda (inclui filhos do claude.exe)
  $todos = @(Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name, CreationDate)
  $arv = [System.Collections.Generic.List[object]]::new(); $fila = [System.Collections.Generic.Queue[int]]::new(); $fila.Enqueue($l.Id)
  while ($fila.Count) { $pp = $fila.Dequeue(); foreach ($q in @($todos | Where-Object ParentProcessId -eq $pp)) { if (-not @($arv | Where-Object ProcessId -eq $q.ProcessId).Count) { $arv.Add($q); $fila.Enqueue([int]$q.ProcessId) } } }
  $filhosClaude = @($arv | Where-Object ParentProcessId -eq $pe.pid)
  "árvore do lançador antes da queda: $($arv.Count) processos ($((@($arv | ForEach-Object { "$($_.ProcessId) $($_.Name)" })) -join ', ')) | filhos do claude: $($filhosClaude.Count)"
  Stop-Process -Id $l.Id -Force; Start-Sleep 8
  $sobrev = @($arv | Where-Object { $p2 = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.ProcessId)"; $p2 -and $p2.CreationDate -eq $_.CreationDate })
  "N1r: sobreviventes da árvore: $($sobrev.Count) $((@($sobrev | ForEach-Object { "$($_.ProcessId) $($_.Name)" })) -join ', ')"
  $evq = (Razao-Ler $x.R).Eventos
  "claude vivo após a queda: $(Processo-Vivo ([int]$pe.pid) $pe.criacao) | eventos de associação: $(@($evq | Where-Object { $_.evento -in @('erro_job','associado') }).Count) | contencao_violada: $(@($evq | Where-Object evento -eq 'contencao_violada').Count)"
  "status após queda: $(Status $x.T)"
  $c = Razao-Contabilizar (Razao-Ler $x.R).Eventos 0.25
  "N2 reservado: $($c.Reservado) | abertas: $($c.Abertas.Count)"
  $cod = Lancar $x.T $x.E $x.R 2
  $c = Razao-Contabilizar (Razao-Ler $x.R).Eventos 0.25
  $est = Get-Content "$($x.E)\estado.json" -Raw | ConvertFrom-Json
  "N6 retomada: código $cod | status $(Status $x.T) | razão conhecido $($c.Conhecido) reservado $($c.Reservado) total $($c.Total) | estado.json $($est.custo_acumulado_usd) | reconciliado (B+K): $([math]::Abs($c.Base + $c.Conhecido - [double]$est.custo_acumulado_usd) -lt 1e-6)"
  "commits novos: " + ((git -C "$base\repo" log --format='%h %s' "$head0..HEAD") -join ' | ')

  "Potencia no repo: " + [bool](Select-String -Path "$base\repo\src\calc.ps1" -Pattern "function Potencia" -Quiet)
  "=== FIM $(Get-Date -Format s)"
} *>&1 | Out-File -FilePath $out -Encoding utf8
