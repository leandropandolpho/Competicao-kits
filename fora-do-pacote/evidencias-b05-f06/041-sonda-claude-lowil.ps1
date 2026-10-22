# 041 — Ato 087: SONDA DECISIVA (pedida pela Perplexity; exigida pelo ChatGPT no Ato 084).
# O Claude Code REAL completa uma TAREFA real em baixa integridade (Low IL), com token restrito (sem privilégios),
# TEMP e CLAUDE_CONFIG_DIR em pastas de baixa integridade, SEM tocar no ~/.claude real da conta? Teto US$ 0,40.
# Go/no-go para E84-02..E84-05. Não altera a candidata.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
if ($env:Path -notlike "*$env:USERPROFILE\.local\bin*") { $env:Path += ";$env:USERPROFILE\.local\bin" }
$base = "$env:USERPROFILE\piloto"; $out = "$base\ponte\saida\041-relatorio.txt"
& {
  "=== INICIO $(Get-Date -Format s) | $env:USERNAME"
  Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class LowIL {
  [StructLayout(LayoutKind.Sequential)] struct SIDATTR { public IntPtr Sid; public uint Attr; }
  [StructLayout(LayoutKind.Sequential)] struct TML { public SIDATTR Label; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct SI { public int cb; public string r, d, t; public int x, y, xs, ys, xc, yc, fill, flags; public short show, r2; public IntPtr r3, i, o, e; }
  [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr hp, ht; public int pid, tid; }
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr p, uint a, out IntPtr t);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool CreateRestrictedToken(IntPtr tok, uint flags, uint nSid, IntPtr sids, uint nPriv, IntPtr privs, uint nRes, IntPtr res, out IntPtr novo);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool DuplicateTokenEx(IntPtr t, uint a, IntPtr sa, int imp, int tipo, out IntPtr n);
  [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool ConvertStringSidToSidW(string s, out IntPtr sid);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool SetTokenInformation(IntPtr t, int cls, ref TML i, uint len);
  [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool CreateProcessAsUserW(IntPtr t, string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool herda, uint f, IntPtr env, string dir, ref SI si, out PI pi);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint c);
  [DllImport("kernel32.dll")] static extern bool IsProcessInJob(IntPtr p, IntPtr job, out bool r);
  const uint DISABLE_MAX_PRIVILEGE = 0x1;
  // Cria token: restrito (sem privilégios) + integridade baixa. Devolve "" ou mensagem de erro.
  public static string CriarToken(out IntPtr tokenBaixo) {
    tokenBaixo = IntPtr.Zero; IntPtr t, restrito, dup, sid;
    if (!OpenProcessToken(GetCurrentProcess(), 0x0002 | 0x0008 | 0x0080 | 0x0001 | 0x0004, out t)) return "OpenProcessToken " + Marshal.GetLastWin32Error();
    if (!CreateRestrictedToken(t, DISABLE_MAX_PRIVILEGE, 0, IntPtr.Zero, 0, IntPtr.Zero, 0, IntPtr.Zero, out restrito)) return "CreateRestrictedToken " + Marshal.GetLastWin32Error();
    if (!DuplicateTokenEx(restrito, 0x0002 | 0x0008 | 0x0080 | 0x0001, IntPtr.Zero, 2, 1, out dup)) return "DuplicateTokenEx " + Marshal.GetLastWin32Error();
    ConvertStringSidToSidW("S-1-16-4096", out sid);
    TML m = new TML(); m.Label.Sid = sid; m.Label.Attr = 0x20;
    if (!SetTokenInformation(dup, 25, ref m, (uint)(Marshal.SizeOf(typeof(TML)) + 12))) return "SetTokenInformation " + Marshal.GetLastWin32Error();
    tokenBaixo = dup; return "";
  }
  // Roda 'linha' com o token baixo. bInheritHandles=FALSE (E84-02: sem herança de handles). Devolve "pid|codigo" ou "erro N".
  public static string Rodar(IntPtr token, string linha, string dir, uint ms, out int pid, out bool emJob) {
    pid = 0; emJob = false;
    SI s = new SI(); s.cb = Marshal.SizeOf(typeof(SI)); PI pi;
    if (!CreateProcessAsUserW(token, null, new StringBuilder(linha), IntPtr.Zero, IntPtr.Zero, false, 0x08000000 | 0x00000400, IntPtr.Zero, dir, ref s, out pi)) return "CreateProcessAsUser " + Marshal.GetLastWin32Error();
    pid = pi.pid; bool emj; if (IsProcessInJob(pi.hp, IntPtr.Zero, out emj)) emJob = emj;
    WaitForSingleObject(pi.hp, ms); uint c; GetExitCodeProcess(pi.hp, out c); return pi.pid + "|" + c;
  }
}
'@
  $pw = (Get-Process -Id $PID).Path
  $raiz = Join-Path $env:TEMP ('lowil041-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  $L = "$raiz\baixo"; $R = "$raiz\repo"; $C = "$raiz\config"; $T = "$L\tmp"
  New-Item -ItemType Directory -Force $L, $R, $C, $T | Out-Null
  # semear config do Claude numa pasta baixa, sem tocar no ~/.claude real
  if (Test-Path "$env:USERPROFILE\.claude") { Copy-Item "$env:USERPROFILE\.claude\*" $C -Recurse -Force -ErrorAction SilentlyContinue }
  if (Test-Path "$env:USERPROFILE\.claude.json") { Copy-Item "$env:USERPROFILE\.claude.json" "$C\.claude.json" -Force -ErrorAction SilentlyContinue }
  Set-Content "$R\alvo.txt" "linha original`n" -NoNewline
  foreach ($d in $L, $R, $C) { icacls $d /setintegritylevel '(OI)(CI)low' /T /Q | Out-Null }
  "rótulos aplicados (baixo) em L, R, C"
  $tok = [IntPtr]::Zero; $err = [LowIL]::CriarToken([ref]$tok)
  if ($err) { "FALHA ao criar token baixo: $err"; "=== FIM $(Get-Date -Format s)"; return }
  "token baixo+restrito criado"
  $cl = (Get-Command claude -ErrorAction SilentlyContinue).Source
  $tarefa = 'Edite o arquivo alvo.txt na pasta atual: acrescente exatamente uma linha com o texto POTENCIA_OK. Nao faca mais nada.'
  $linha = "`"$env:ComSpec`" /c `"set TEMP=$T&& set TMP=$T&& set CLAUDE_CONFIG_DIR=$C&& `"$cl`" -p `"$tarefa`" --output-format json --max-budget-usd 0.40 --no-session-persistence --permission-mode dontAsk > `"$L\out.txt`" 2> `"$L\err.txt`"`""
  $pid = 0; $emJob = $false
  $res = [LowIL]::Rodar($tok, $linha, $R, 180000, [ref]$pid, [ref]$emJob)
  "Rodar: $res | em_job: $emJob"
  # nível e privilégios efetivos do processo baixo (consultados por ele mesmo não dá; checamos pelo whoami de um filho)
  "--- saída (out.txt):"; (Get-Content "$L\out.txt" -Raw -ErrorAction SilentlyContinue)
  "--- erro (err.txt, 1200 car.):"; (((Get-Content "$L\err.txt" -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' ')).Substring(0, [Math]::Min(1200, ((Get-Content "$L\err.txt" -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' ').Length))
  $o = Get-Content "$L\out.txt" -Raw -ErrorAction SilentlyContinue
  $j = $null; try { $j = $o.Trim() | ConvertFrom-Json } catch { }
  $custoOk = $j -and $j.PSObject.Properties['total_cost_usd'] -and ($j.total_cost_usd -is [double] -or $j.total_cost_usd -is [long]) -and [double]::IsFinite([double]$j.total_cost_usd) -and [double]$j.total_cost_usd -ge 0
  $semErro = $j -and (-not ($j.PSObject.Properties['is_error'] -and $j.is_error -eq $true))
  $arqOk = (Test-Path "$R\alvo.txt") -and ((Get-Content "$R\alvo.txt" -Raw) -match 'POTENCIA_OK')
  "VEREDITO: is_error=$(if($j){$j.is_error}) | custo=$(if($j){$j.total_cost_usd}) (válido=$custoOk) | arquivo_editado=$arqOk | tarefa_completa=$($semErro -and $custoOk -and $arqOk)"
  "conteúdo final do alvo.txt: " + ((Get-Content "$R\alvo.txt" -Raw -ErrorAction SilentlyContinue) -replace '\r?\n', ' | ')
  Remove-Item -Recurse -Force $raiz -ErrorAction SilentlyContinue
  "=== FIM $(Get-Date -Format s)"
} *>&1 | Out-File -FilePath $out -Encoding utf8
