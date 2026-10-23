# 073 — isola: Claude em BAIXA integridade DENTRO de um Job Object mínimo (KILL_ON_JOB_CLOSE). Captura out+err+código.
$ErrorActionPreference='Continue'; [Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false)
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
if ($env:Path -notlike "*$env:USERPROFILE\.local\bin*") { $env:Path += ";$env:USERPROFILE\.local\bin" }
$base="$env:USERPROFILE\piloto"; $out="$base\ponte\saida\073-relatorio.txt"; $h="$base\harness"
$PwP="$base\ferramentas\pwsh-7.6.7\pwsh.exe"
& {
  "=== INICIO $(Get-Date -Format s)"
  git -C $h fetch -q origin hibrido 2>&1|Out-Null; git -C $h -c advice.detachedHead=false checkout -q 763a74481c6ccfeee0820f327162223477e0b427 2>&1|Out-Null
  . "$h\b05\b05job.ps1"; . "$h\b05\baixa-integridade.ps1"
  $cl=(Get-Command claude).Source; $set="$h\kits\kit-A\.claude\settings.json"
  $raiz=Join-Path $env:TEMP ('j073-'+[guid]::NewGuid().ToString('N').Substring(0,8))
  $L="$raiz\low"; $C="$raiz\cfg"; New-Item -ItemType Directory -Force $L,$C,"$L\tmp"|Out-Null
  if(Test-Path "$env:USERPROFILE\.claude"){Copy-Item "$env:USERPROFILE\.claude\*" $C -Recurse -Force -ErrorAction SilentlyContinue}
  if(Test-Path "$env:USERPROFILE\.claude.json"){Copy-Item "$env:USERPROFILE\.claude.json" "$C\.claude.json" -Force -ErrorAction SilentlyContinue}
  foreach($d in $L,$C){& icacls $d /setintegritylevel '(OI)(CI)low' /T /Q 2>&1|Out-Null}
  $vars=@{}; foreach($e in [Environment]::GetEnvironmentVariables().GetEnumerator()){ $n=[string]$e.Key; if($n -match '(?i)^B05_|openai|anthropic|supervisora|_KEY$|_TOKEN$'){continue}; $vars[$n]=[string]$e.Value }
  $vars['TEMP']="$L\tmp"; $vars['TMP']="$L\tmp"; $vars['CLAUDE_CONFIG_DIR']=$C
  function RodaClaude($emJob,$tag){
    $inF="$L\in.txt"; $oF="$L\o-$tag.txt"; $eF="$L\e-$tag.txt"; Set-Content $inF 'Responda apenas: OK' -NoNewline
    $job=[IntPtr]::Zero
    if($emJob){
      $job=[B05Job]::CreateJobObject([IntPtr]::Zero,$null)
      [void][B05Job]::Configurar($job,[B05Job]::KILL_ON_JOB_CLOSE)
      [void][B05Job]::AssignProcessToJobObject($job,[B05Job]::GetCurrentProcess())
    }
    $tok=[IntPtr]::Zero; $m=[B05LowIL]::CriarToken([ref]$tok); if($m){ "$tag token: $m"; return }
    $args=@('-p','--output-format','json','--permission-mode','dontAsk','--settings',$set,'--max-budget-usd','0.20','--no-session-persistence')
    $cmd=B05LowIL-Cmdline $cl $args $inF $oF $eF
    $env2=B05LowIL-BlocoAmbiente $vars
    $lpid=0;$hp=[IntPtr]::Zero
    try{ $ml=[B05LowIL]::Lancar($tok,$cmd,$L,$env2,[ref]$lpid,[ref]$hp) } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($env2); [B05LowIL]::Fechar($tok) }
    if($ml){ "$tag lancar: $ml"; return }
    $dentro=[B05LowIL]::EmJob($hp)
    $cod=[B05LowIL]::Esperar($hp,120000); [B05LowIL]::Fechar($hp)
    $o=(Get-Content $oF -Raw -ErrorAction SilentlyContinue); $e=(Get-Content $eF -Raw -ErrorAction SilentlyContinue)
    $ie=[regex]::Match($o,'"is_error":(true|false)').Groups[1].Value
    $res=[regex]::Match($o,'"result":"([^"]{0,120})').Groups[1].Value
    "$tag => em_job:$dentro código:$cod is_error:$ie result:$res"
    "$tag    out(80): " + (($o -replace '\s+',' ').Substring(0,[Math]::Min(80,($o -replace '\s+',' ').Length)))
    "$tag    err(300): " + (($e -replace '\s+',' ').Substring(0,[Math]::Min(300,($e -replace '\s+',' ').Length)))
    if($job -ne [IntPtr]::Zero){ [void][B05Job]::TerminateJobObject($job,0) }
  }
  "--- CONTROLE: Claude baixo FORA de job"
  RodaClaude $false 'FORA'
  "--- TESTE: Claude baixo DENTRO de job (KILL_ON_JOB_CLOSE)"
  RodaClaude $true 'DENTRO'
  Remove-Item -Recurse -Force $raiz -ErrorAction SilentlyContinue
  "=== FIM $(Get-Date -Format s)"
} *>&1 | Out-File -FilePath $out -Encoding utf8
