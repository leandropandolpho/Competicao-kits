# testar-controlador-real-ponte.ps1 - INTEGRACAO com o CONTROLADOR REAL (7cd7864) em modo ponte. Ato 148.
# Fecha os achados V1-F01/F02 do Ato 147: o controlador congelado roda com ClaudeCmd = claude-ponte.cmd (executor via
# ponte/PE) e TestCmd = despachante-teste.cmd (teste via ponte/PE, em Low IL - NAO como PU). A selecao da ponte e
# EXTERNA (parametros ClaudeCmd/TestCmd que QUEM INVOCA passa) - o controlador e o lancador nao sao tocados.
# Cenarios (nomes proprios, para nao colidir com o harness do oraculo):
#  I-C1   sucesso: executor via ponte edita + teste via ponte passa -> commit (done, exit 0); razao reconciliado.
#  I-D2   o $TestCmd roda via ponte sob o PE em Low IL (nivel 4096); escrita Low em .git (Medium) NEGADA (nao roda como PU).
#  I-TMO  timeout do executor via ponte -> controlador trata como falha -> rollback (HEAD=base, arvore limpa).
#  I-RET  retomada: apos uma execucao, o razao PRESERVA o custo (nao zera) e o pre-flight encerra orfao anterior.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$raiz = $PSScriptRoot
$pontecmd = (Resolve-Path (Join-Path $raiz '..\claude-ponte.cmd')).Path
$despcmd  = (Resolve-Path (Join-Path $raiz '..\despachante-teste.cmd')).Path
$acao     = (Resolve-Path (Join-Path $raiz '..\acao-pe.ps1')).Path
$fake     = (Resolve-Path (Join-Path $raiz '..\..\testes\fake-executor.ps1')).Path
$ctrlPath = (Resolve-Path (Join-Path $raiz '..\..\..\kits\kit-A\controlador.ps1')).Path
. (Resolve-Path (Join-Path $raiz '..\ponte-pu.ps1')).Path   # p/ Razao-Ler/Contabilizar e PU-Lease-Gravar
$Pw = (Get-Process -Id $PID).Path; $sha = (Get-FileHash -LiteralPath $Pw -Algorithm SHA256).Hash
$Utf8 = [Text.UTF8Encoding]::new($false)
$ok = 0; $tot = 0
function Checar($n,[bool]$c,[string]$d=''){ $script:tot++; if($c){ $script:ok++; "[ok] $n" } else { "[FALHA] $n $d" } }
if (-not $IsWindows) { "INTEGRA-CTRL: so Windows."; exit 0 }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { "INTEGRA-CTRL: git ausente - pulado."; exit 0 }

# Monta repo git + B05_DIR (config/razao) + ponte/evid/trava + EstadoDir + TAREFAS.json. test_cmd_real controla a fase teste.
function Novo-Ambiente([string]$testeReal,[int]$timeoutPonte=60,[double]$orc=100) {
  $base = Join-Path $env:TEMP ('ic-' + [guid]::NewGuid().ToString('N').Substring(0,8))
  $repo = Join-Path $base 'repo'; $ctrl = Join-Path $base 'ctrl'; $ponte = Join-Path $base 'ponte'
  $evid = Join-Path $base 'evid'; $trava = Join-Path $base 'trava'; $estado = Join-Path $base 'estado'
  New-Item -ItemType Directory -Force $repo,$ctrl,$ponte,$evid,$trava,$estado | Out-Null
  Push-Location $repo
  try {
    & git init -q *>$null; & git config user.email t@t *>$null; & git config user.name t *>$null; & git config commit.gpgsign false *>$null
    [IO.File]::WriteAllText((Join-Path $repo 'codigo.txt'), "base`n", $Utf8)
    [IO.File]::WriteAllText((Join-Path $repo 'teste-marker.txt'), "t`n", $Utf8)   # TestPath (o executor nao deve altera-lo)
    & git add -A *>$null; & git commit -q -m base *>$null
  } finally { Pop-Location }
  $exec = [guid]::NewGuid().ToString('N')
  $cfg = [ordered]@{ execucao=$exec; teto_chamada_usd=0.5; folga=0.25; orcamento_usd=$orc
    executor=$Pw; executor_prefixo="-NoProfile|-File|$fake"; test_cmd_real=$testeReal
    ponte_dir=$ponte; acao_pe=$acao; pwsh_aprovado=$Pw; pwsh_sha256=$sha
    trava_dir=$trava; evidencia_dir=$evid; timeout_ponte_seg=$timeoutPonte }
  [IO.File]::WriteAllText((Join-Path $ctrl "config-$exec.json"), ($cfg | ConvertTo-Json -Compress), $Utf8)
  $taref = Join-Path $ctrl 'TAREFAS.json'
  [IO.File]::WriteAllText($taref, (@{ versao='1'; tarefas=@(@{ id='T1'; titulo='Tarefa 1'; prompt='corrige'; status='pending'; tentativas=0; depends_on=@(); critica=$false }) } | ConvertTo-Json -Depth 6), $Utf8)
  return [pscustomobject]@{ Base=$base; Repo=$repo; Ctrl=$ctrl; Ponte=$ponte; Evid=$evid; Trava=$trava; Estado=$estado; Taref=$taref; Exec=$exec }
}
function Rodar-Ctrl($amb,[string]$modo,[int]$timeoutCtrl=120,[int]$maxTent=1) {
  $headBase = (& git -C $amb.Repo rev-parse HEAD).Trim()
  $psi = [System.Diagnostics.ProcessStartInfo]::new($Pw)
  foreach ($a in @('-NoProfile','-ExecutionPolicy','Bypass','-File',$ctrlPath,
      '-RepoPath',$amb.Repo,'-TarefasPath',$amb.Taref,'-EstadoDir',$amb.Estado,
      '-TestCmd',("& `"$despcmd`""),'-TestPaths','teste-marker.txt','-ClaudeCmd',$pontecmd,
      '-TimeoutSec',[string]$timeoutCtrl,'-MaxTentativas',[string]$maxTent,'-MaxCustoUsd','100')) { $psi.ArgumentList.Add($a) }
  $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.WorkingDirectory=$amb.Repo
  $psi.Environment['B05_PWSH']=$Pw; $psi.Environment['B05_DIR']=$amb.Ctrl; $psi.Environment['B05_EXECUCAO']=$amb.Exec
  $psi.Environment['B05FAKE_MODO']=$modo
  $psi.Environment['PATH']=(Split-Path $Pw) + ';' + $psi.Environment['PATH']
  $p=[System.Diagnostics.Process]::Start($psi)
  $out=$p.StandardOutput.ReadToEndAsync(); $err=$p.StandardError.ReadToEndAsync()
  $estourou = -not $p.WaitForExit(($timeoutCtrl+60)*1000)
  if ($estourou) { try { $p.Kill($true) } catch {} }
  $code = if ($estourou) { -1 } else { $p.ExitCode }
  return @{ Codigo=$code; HeadBase=$headBase; HeadAgora=(& git -C $amb.Repo rev-parse HEAD).Trim(); Saida=$out.Result; Erro=$err.Result; Estourou=$estourou }
}
# Acha o teste.txt da fase-teste (pasta-ponte que o tem) na ponte_dir.
function TesteTxt($amb) {
  $f = Get-ChildItem -Directory $amb.Ponte -EA SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'teste.txt' } | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($f) { Get-Content $f -Raw } else { '' }
}
function Custo($amb) { $r = Razao-Ler $amb.Ctrl; if (-not $r.Ok) { return -1 }; (Razao-Contabilizar $r.Eventos 0.25).Total }

"== I-C1 (REQ-08): controlador REAL -> ponte -> executor edita + teste passa -> commit (done)"
$a1 = Novo-Ambiente 'exit 0'
$r1 = Rodar-Ctrl $a1 'ok:0.20'
Checar 'I-C1: controlador saiu 0 (done)' ($r1.Codigo -eq 0) "cod=$($r1.Codigo) err=$($r1.Erro)"
Checar 'I-C1: commit efetivado (HEAD avancou)' ($r1.HeadAgora -ne $r1.HeadBase)
Checar 'I-C1: executor editou a arvore via ponte (notas.txt)' (Test-Path (Join-Path $a1.Repo 'notas.txt'))
Checar 'I-C1: razao reconciliado com custo > 0' ((Custo $a1) -gt 0)

"== I-D2 (fecha V1-F02): o TestCmd roda via ponte sob o PE em Low IL; escrita Low em .git (Medium) NEGADA (nao e PU)"
$tcD2 = "try { [IO.File]::WriteAllText((Join-Path (Get-Location) '.git\hooks\ph.txt'),'x'); 'git_hook_teste=OK' } catch { 'git_hook_teste=NEGADO' }"
$a2 = Novo-Ambiente $tcD2
$r2 = Rodar-Ctrl $a2 'ok:0.10'
$tt2 = TesteTxt $a2
Checar 'I-D2: teste rodou sob o PE em Low IL (nivel=4096), NAO como PU' ($tt2 -match 'nivel=4096') "t=$tt2"
Checar 'I-D2: escrita Low em .git (Medium) pela via do TESTE -> NEGADA' ($tt2 -match 'git_hook_teste=NEGADO') "t=$tt2"

"== I-TMO (REQ-10): executor trava via ponte -> ponte encerra -> controlador rollback (sem commit)"
$a3 = Novo-Ambiente 'exit 0' 4
$r3 = Rodar-Ctrl $a3 'dorme:99' 90 1
$limpa3 = [string]::IsNullOrWhiteSpace((& git -C $a3.Repo status --porcelain))
Checar 'I-TMO: controlador NAO comitou (HEAD=base)' ($r3.HeadAgora -eq $r3.HeadBase) "cod=$($r3.Codigo)"
Checar 'I-TMO: arvore limpa apos rollback' ($limpa3)

"== I-RET (REQ-12): retomada preserva o custo do razao (nao zera) e pre-flight encerra orfao vivo anterior"
$custoAntes = Custo $a1
$orf = [System.Diagnostics.Process]::Start((New-Object System.Diagnostics.ProcessStartInfo -Property @{ FileName=$env:ComSpec; Arguments='/c ping -n 60 127.0.0.1 > nul'; UseShellExecute=$false; CreateNoWindow=$true }))
$orfPid=[uint32]$orf.Id; $orfCri=0L; try { $orfCri=[B05LowIL]::CriacaoUtc($orf.Handle) } catch {}
PU-Lease-Gravar $a1.Trava 'exec-anterior' $orfPid $orfCri
# nova tarefa pendente para a retomada
[IO.File]::WriteAllText($a1.Taref, (@{ versao='1'; tarefas=@(@{ id='T2'; titulo='Tarefa 2'; prompt='corrige2'; status='pending'; tentativas=0; depends_on=@(); critica=$false }) } | ConvertTo-Json -Depth 6), $Utf8)
$r1b = Rodar-Ctrl $a1 'ok:0.15'
Start-Sleep -Milliseconds 400
$orfMorto = (PU-Subarvore-Morta $orfPid $orfCri).Morta
try { if (-not $orf.HasExited) { $orf.Kill($true) } } catch {}
Checar 'I-RET: custo preservado na retomada (nao zerou; acumulou)' ((Custo $a1) -ge $custoAntes -and $custoAntes -gt 0) "antes=$custoAntes depois=$(Custo $a1)"
Checar 'I-RET: pre-flight encerrou o orfao vivo antes de despachar' ($orfMorto)

"`nTOTAL INTEGRA-CTRL: $ok / $tot"
exit ([int]($ok -ne $tot))
