# testar-integra-ponte.ps1 - INTEGRACAO REQ-08 (modo principal-isolado). Ato 145. Windows/pwsh7 + git.
# Um controlador MINIMO (replicando o padrao de chamada do controlador congelado: ClaudeCmd com -p/--output-format json,
# timeout, rollback por git) invoca o claude-ponte.ps1 como ClaudeCmd. Prova, de ponta a ponta:
#  PU-09  controlador 7cd7864 e claude-com-teto 9e6991c continuam com diff VAZIO (a ponte e EXTERNA aos dois).
#  C1     sucesso: a ponte despacha o PE, o executor edita a arvore, custo reconciliado no razao -> controlador comita.
#  C4     violacao financeira (custo invalido): claude-ponte devolve erro 28 -> controlador faz rollback (HEAD=base,
#         arvore limpa) e NAO comita; trava financeira gravada (C-02/C-03).
#  C6     controlador morto na chamada anterior: lease de PE orfao VIVO -> o pre-flight da ponte o encerra ANTES de
#         despachar; nenhuma escrita apos o rollback (R-01 na V1 demonstrado pelo encerramento da arvore).
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$raiz = $PSScriptRoot
$pontePs1 = (Resolve-Path (Join-Path $raiz '..\claude-ponte.ps1')).Path
$acao = (Resolve-Path (Join-Path $raiz '..\acao-pe.ps1')).Path
$fake = (Resolve-Path (Join-Path $raiz '..\..\testes\fake-executor.ps1')).Path
. (Resolve-Path (Join-Path $raiz '..\ponte-pu.ps1')).Path   # p/ PU-Lease-Gravar no C6
$PwshAprovado = (Get-Process -Id $PID).Path
$shaPwsh = (Get-FileHash -LiteralPath $PwshAprovado -Algorithm SHA256).Hash
$ok = 0; $tot = 0
function Checar($n,[bool]$c,[string]$d=''){ $script:tot++; if($c){ $script:ok++; "[ok] $n" } else { "[FALHA] $n $d" } }
if (-not $IsWindows) { "INTEGRA: so Windows."; exit 0 }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { "INTEGRA: git ausente - pulado."; exit 0 }

# Monta um ambiente: repo git de trabalho + B05_DIR (config/razao) + ponte/evid/trava (fora do repo).
function Novo-Ambiente {
  $base = Join-Path $env:TEMP ('it-' + [guid]::NewGuid().ToString('N').Substring(0,8))
  $repo = Join-Path $base 'repo'; $ctrl = Join-Path $base 'ctrl'   # ctrl = B05_DIR (razao+config), fora do repo
  $ponte = Join-Path $base 'ponte'; $evid = Join-Path $base 'evid'; $trava = Join-Path $base 'trava'
  New-Item -ItemType Directory -Force $repo,$ctrl,$ponte,$evid,$trava | Out-Null
  Push-Location $repo
  try {
    & git init -q; & git config user.email t@t; & git config user.name t; & git config commit.gpgsign false
    [System.IO.File]::WriteAllText((Join-Path $repo 'codigo.txt'), "base`n", [Text.UTF8Encoding]::new($false))
    & git add -A; & git commit -q -m base
  } finally { Pop-Location }
  $execucao = [guid]::NewGuid().ToString('N')
  $cfg = [ordered]@{ execucao=$execucao; teto_chamada_usd=0.5; folga=0.25; orcamento_usd=100.0
    executor=$PwshAprovado; executor_prefixo="-NoProfile|-File|$fake"
    ponte_dir=$ponte; acao_pe=$acao; pwsh_aprovado=$PwshAprovado; pwsh_sha256=$shaPwsh
    trava_dir=$trava; evidencia_dir=$evid; timeout_ponte_seg=60 }
  [System.IO.File]::WriteAllText((Join-Path $ctrl "config-$execucao.json"), ($cfg | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
  return [pscustomobject]@{ Base=$base; Repo=$repo; Ctrl=$ctrl; Ponte=$ponte; Evid=$evid; Trava=$trava; Exec=$execucao }
}
# Controlador MINIMO: chama o ClaudeCmd (claude-ponte) como o controlador congelado faz. Em sucesso comita; em erro, rollback.
function Controlador-Chamar($amb,[int]$timeoutSeg=60) {
  $headBase = (& git -C $amb.Repo rev-parse HEAD).Trim()
  $psi = [System.Diagnostics.ProcessStartInfo]::new($PwshAprovado)
  foreach ($a in @('-NoProfile','-ExecutionPolicy','Bypass','-File',$pontePs1,'-p','corrige o codigo','--output-format','json','--permission-mode','dontAsk')) { $psi.ArgumentList.Add($a) }
  $psi.WorkingDirectory = $amb.Repo; $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.Environment['B05_DIR'] = $amb.Ctrl; $psi.Environment['B05_EXECUCAO'] = $amb.Exec; $psi.Environment['B05_PWSH'] = $PwshAprovado
  foreach ($e in Get-ChildItem Env:B05FAKE_* -EA SilentlyContinue) { $psi.Environment[$e.Name] = $e.Value }
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEndAsync(); $errA = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($timeoutSeg * 1000)) { try { $p.Kill($true) } catch {}; return @{ Codigo=124; Saida=''; Commitou=$false } }
  $saida = $out.Result; $cod = $p.ExitCode
  $commitou = $false
  if ($cod -eq 0) {
    try { $j = $saida | ConvertFrom-Json } catch { $j = $null }
    if ($j -and -not $j.is_error) { & git -C $amb.Repo add -A *>$null; & git -C $amb.Repo commit -q -m "tarefa"; $commitou = $true }
  } else {
    & git -C $amb.Repo reset -q --hard $headBase; & git -C $amb.Repo clean -qfd   # rollback (controlador congelado)
  }
  return @{ Codigo=$cod; Saida=$saida; Commitou=$commitou; HeadBase=$headBase; HeadAgora=(& git -C $amb.Repo rev-parse HEAD).Trim() }
}

# ---------- PU-09: a ponte e EXTERNA; controlador e claude-com-teto continuam diff VAZIO ----------
"== PU-09 (REQ-08): controlador 7cd7864 e claude-com-teto 9e6991c com diff VAZIO (ponte externa) =="
$repoRaiz = (& git -C $raiz rev-parse --show-toplevel).Trim()
$dCtrl = (& git -C $repoRaiz diff --stat 7cd7864 HEAD -- kits/kit-A/controlador.ps1) 2>$null
$dTeto = (& git -C $repoRaiz diff --stat 9e6991c HEAD -- b05/claude-com-teto.ps1) 2>$null
Checar 'PU-09: controlador.ps1 diff vazio vs 7cd7864' ([string]::IsNullOrWhiteSpace("$dCtrl")) "d=$dCtrl"
Checar 'PU-09: claude-com-teto.ps1 diff vazio vs 9e6991c' ([string]::IsNullOrWhiteSpace("$dTeto")) "d=$dTeto"

# ---------- C1: sucesso -> ponte despacha PE, executor edita, custo reconciliado, controlador comita ----------
"== C1 (REQ-08): fluxo feliz pela ponte -> executor edita a arvore, custo reconciliado, commit"
$a1 = Novo-Ambiente
$env:B05FAKE_MODO = 'ok:0.20'
$r1 = Controlador-Chamar $a1
Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue
$razao1 = Join-Path $a1.Ctrl 'razao.jsonl'
$ev1 = if (Test-Path $razao1) { @(Get-Content $razao1 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() }
$fim1 = @($ev1 | Where-Object { $_.evento -eq 'fim' -and -not $_.PSObject.Properties['custo_desconhecido'] -and [double]$_.custo_usd -eq 0.20 })
Checar 'C1: claude-ponte saiu 0' ($r1.Codigo -eq 0) "cod=$($r1.Codigo) saida=$($r1.Saida)"
Checar 'C1: controlador comitou (HEAD avancou)' ($r1.Commitou -and $r1.HeadAgora -ne $r1.HeadBase)
Checar 'C1: executor editou a arvore (notas.txt commitado)' (Test-Path (Join-Path $a1.Repo 'notas.txt'))
Checar 'C1: razao reconciliado (fim custo_usd=0.20 conhecido)' ($fim1.Count -ge 1)

# ---------- C4: custo invalido -> claude-ponte 28 -> rollback, sem commit, trava financeira ----------
"== C4 (REQ-08/C-02/C-03): custo invalido pela ponte -> erro 28 -> rollback (HEAD=base, arvore limpa), trava financeira"
$a4 = Novo-Ambiente
$env:B05FAKE_MODO = 'custo'; $env:B05FAKE_CUSTO = '"caro"'
$r4 = Controlador-Chamar $a4
Remove-Item Env:B05FAKE_MODO,Env:B05FAKE_CUSTO -EA SilentlyContinue
$limpa = [string]::IsNullOrWhiteSpace((& git -C $a4.Repo status --porcelain))
Checar 'C4: claude-ponte devolveu 28 (financeiro)' ($r4.Codigo -eq 28) "cod=$($r4.Codigo) saida=$($r4.Saida)"
Checar 'C4: NAO comitou; HEAD=base (rollback)' (-not $r4.Commitou -and $r4.HeadAgora -eq $r4.HeadBase)
Checar 'C4: arvore limpa apos rollback (C-03)' ($limpa)
Checar 'C4: trava FINANCEIRA gravada (C-02)' ([bool](Get-ChildItem $a4.Trava -Filter 'financeira-*.trava' -EA SilentlyContinue))

# ---------- C6: controlador morto -> lease de PE orfao VIVO -> pre-flight encerra antes de despachar ----------
"== C6 (REQ-12/R-01 V1): PE orfao VIVO de execucao anterior -> pre-flight da ponte encerra ANTES de despachar"
$a6 = Novo-Ambiente
$orf = [System.Diagnostics.Process]::Start((New-Object System.Diagnostics.ProcessStartInfo -Property @{ FileName=$env:ComSpec; Arguments='/c ping -n 60 127.0.0.1 > nul'; UseShellExecute=$false; CreateNoWindow=$true }))
$orfPid = [uint32]$orf.Id; $orfCri = 0L; try { $orfCri = [B05LowIL]::CriacaoUtc($orf.Handle) } catch {}
PU-Lease-Gravar $a6.Trava 'exec-anterior' $orfPid $orfCri   # lease de uma execucao anterior (controlador morto antes de fechar)
$vivoAntes = -not (PU-Subarvore-Morta $orfPid $orfCri).Morta
$env:B05FAKE_MODO = 'ok:0.10'
$r6 = Controlador-Chamar $a6
Remove-Item Env:B05FAKE_MODO -EA SilentlyContinue
Start-Sleep -Milliseconds 400
$mortoDepois = (PU-Subarvore-Morta $orfPid $orfCri).Morta
try { if (-not $orf.HasExited) { $orf.Kill($true) } } catch {}
Checar 'C6: orfao estava VIVO antes da chamada' ($vivoAntes)
Checar 'C6: pre-flight encerrou o orfao (morto depois)' ($mortoDepois)
Checar 'C6: chamada subsequente prosseguiu (claude-ponte 0)' ($r6.Codigo -eq 0) "cod=$($r6.Codigo)"

"`nTOTAL INTEGRA: $ok / $tot"
exit ([int]($ok -ne $tot))
