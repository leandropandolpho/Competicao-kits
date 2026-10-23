# 053 — diag E84-05: (1) um processo BAIXO consegue criar junction? (2) a varredura B05LowIL-ReparsePoints a detecta?
$ErrorActionPreference = 'Continue'; [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$base = "$env:USERPROFILE\piloto"; $out = "$base\ponte\saida\053-relatorio.txt"; $h = "$base\harness"
$PwP = "$base\ferramentas\pwsh-7.6.7\pwsh.exe"
& {
  "=== INICIO $(Get-Date -Format s)"
  git -C $h fetch -q origin hibrido 2>&1 | Out-Null; git -C $h -c advice.detachedHead=false checkout -q ab4442b2e965df70eba9a9d82718c669329c6fe4 2>&1 | Out-Null
  . "$h\b05\baixa-integridade.ps1"
  $raiz = Join-Path $env:TEMP ('j053-' + [guid]::NewGuid().ToString('N').Substring(0,8))
  $low = "$raiz\low"; $alvo = "$raiz\medio"; New-Item -ItemType Directory -Force $low,$alvo | Out-Null
  Set-Content "$alvo\sent.txt" 'x'
  & icacls $low /setintegritylevel '(OI)(CI)low' /T /Q 2>&1 | Out-Null
  # processo BAIXO tenta criar junction low\link -> medio
  $tok=[IntPtr]::Zero; $m=[B05LowIL]::CriarToken([ref]$tok)
  "token: $(if($m){$m}else{'ok'})"
  $script = "cmd /c mklink /J `"$low\link`" `"$alvo`" > `"$low\mk.txt`" 2>&1; exit `$LASTEXITCODE"
  $sb = [IO.Path]::Combine($low,'mk.ps1'); Set-Content $sb $script
  $cl = B05LowIL-Cmdline $PwP @('-NoProfile','-File',$sb) "$low\in.txt" "$low\o.txt" "$low\e.txt"
  Set-Content "$low\in.txt" ''
  $lpid=0;$hp=[IntPtr]::Zero; $ml=[B05LowIL]::Lancar($tok,$cl,$low,[IntPtr]::Zero,[ref]$lpid,[ref]$hp); [B05LowIL]::Fechar($tok)
  if($ml){ "lancar: $ml" } else { $cod=[B05LowIL]::Esperar($hp,30000); [B05LowIL]::Fechar($hp); "mklink saída: $cod" }
  "mk.txt: " + ((Get-Content "$low\mk.txt" -Raw -ErrorAction SilentlyContinue) -replace '\s+',' ')
  "link existe? " + (Test-Path "$low\link") + " | é reparse? " + ((Get-Item "$low\link" -Force -ErrorAction SilentlyContinue).Attributes -band [IO.FileAttributes]::ReparsePoint)
  # agora a varredura (médio)
  $rep = @(B05LowIL-ReparsePoints $low)
  "ReparsePoints detectou: $($rep.Count) → $($rep -join '; ')"
  # alternativa: via New-Item Junction a partir do baixo (caso mklink precise de console)
  Remove-Item -Recurse -Force $raiz -ErrorAction SilentlyContinue
  "=== FIM $(Get-Date -Format s)"
} *>&1 | Out-File -FilePath $out -Encoding utf8
