# 036 — Ato 082: (1) bateria B-05 em ec26dcb (N1–N17 + N19 + N20) e (2) SONDA de viabilidade para B05-F06:
# executor em BAIXA INTEGRIDADE (Low IL) na mesma conta, sem admin. Não altera a candidata; só coleta evidência.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
if ($env:Path -notlike "*$env:USERPROFILE\.local\bin*") { $env:Path += ";$env:USERPROFILE\.local\bin" }
$base = "$env:USERPROFILE\piloto"; $out = "$base\ponte\saida\036-relatorio.txt"; $h = "$base\harness"
$PwP = "$base\ferramentas\pwsh-7.6.7\pwsh.exe"
& {
  "=== INICIO $(Get-Date -Format s) | $env:USERNAME"
  git -C $h fetch -q origin hibrido 2>&1; git -C $h -c advice.detachedHead=false checkout -q ec26dcb3622e915bbee68c6d7fb53148513903df 2>&1
  "commit: " + (git -C $h rev-parse HEAD) + " | controlador: " + (Get-FileHash "$h\kits\kit-A\controlador.ps1").Hash
  "pwsh portátil: " + (Get-FileHash $PwP).Hash
  Get-FileHash "$h\b05\*.ps1", "$h\b05\*.cmd", "$h\b05\testes\*.ps1" | ForEach-Object { "$($_.Hash) $(Split-Path $_.Path -Leaf)" }
  $env:Path = "$(Split-Path $PwP);$env:Path"
  "##### PARTE 1 — bateria simulada"
  & $PwP -NoProfile -File "$h\b05\testes\testar-b05.ps1" -ControladorPath "$h\kits\kit-A\controlador.ps1" -SettingsPath "$h\kits\kit-A\.claude\settings.json" 2>&1
  "código: $LASTEXITCODE"

  "##### PARTE 2 — sonda Low IL"
  & $PwP -NoProfile -Command {
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class Baixo {
  [StructLayout(LayoutKind.Sequential)] struct SID_AND_ATTRIBUTES { public IntPtr Sid; public uint Attributes; }
  [StructLayout(LayoutKind.Sequential)] struct TML { public SID_AND_ATTRIBUTES Label; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct SI { public int cb; public string r, d, t; public int x, y, xs, ys, xc, yc, fill, flags; public short show, r2; public IntPtr r3, i, o, e; }
  [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr hp, ht; public int pid, tid; }
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr p, uint a, out IntPtr t);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool DuplicateTokenEx(IntPtr t, uint a, IntPtr sa, int imp, int tipo, out IntPtr n);
  [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool ConvertStringSidToSidW(string s, out IntPtr sid);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool SetTokenInformation(IntPtr t, int cls, ref TML i, uint len);
  [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool CreateProcessAsUserW(IntPtr t, string app, System.Text.StringBuilder cmd, IntPtr pa, IntPtr ta, bool h, uint f, IntPtr env, string dir, ref SI si, out PI pi);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint c);
  // Executa 'linha' em BAIXA integridade (mesmo usuário), espera até 'ms' e devolve "pid|código" ou "erro N".
  public static string Rodar(string linha, string dir, uint ms) {
    IntPtr t, n, sid;
    if (!OpenProcessToken(GetCurrentProcess(), 0x0002 | 0x0008 | 0x0080 | 0x0001, out t)) return "erro OpenProcessToken " + Marshal.GetLastWin32Error();
    if (!DuplicateTokenEx(t, 0x0002 | 0x0008 | 0x0080 | 0x0001, IntPtr.Zero, 2, 1, out n)) return "erro DuplicateTokenEx " + Marshal.GetLastWin32Error();
    ConvertStringSidToSidW("S-1-16-4096", out sid);
    TML m = new TML(); m.Label.Sid = sid; m.Label.Attributes = 0x20;
    if (!SetTokenInformation(n, 25, ref m, (uint)(Marshal.SizeOf(typeof(TML)) + 12))) return "erro SetTokenInformation " + Marshal.GetLastWin32Error();
    SI s = new SI(); s.cb = Marshal.SizeOf(typeof(SI)); PI pi;
    if (!CreateProcessAsUserW(n, null, new System.Text.StringBuilder(linha), IntPtr.Zero, IntPtr.Zero, false, 0x08000000 | 0x00000400, IntPtr.Zero, dir, ref s, out pi)) return "erro CreateProcessAsUser " + Marshal.GetLastWin32Error();
    WaitForSingleObject(pi.hp, ms); uint c; GetExitCodeProcess(pi.hp, out c); return pi.pid + "|" + c;
  }
}
'@
    $pw = (Get-Process -Id $PID).Path
    $raiz = Join-Path $env:TEMP ('sonda036-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $M = "$raiz\medio-razao"; $L = "$raiz\baixo"; $R = "$raiz\repo"
    New-Item -ItemType Directory -Force $M, $L, $R | Out-Null
    Set-Content "$M\razao.jsonl" '{"evento":"base_historica","valor_usd":0}'
    icacls $L /setintegritylevel '(OI)(CI)low' | Out-Null
    git init -q $R; Set-Content "$R\a.txt" 'base'; git -C $R add -A; git -C $R -c user.email=t@t -c user.name=t commit -qm base
    # árvore de trabalho em baixa integridade, .git continua média
    Get-ChildItem $R -Force | Where-Object Name -ne '.git' | ForEach-Object { icacls $_.FullName /setintegritylevel '(OI)(CI)low' | Out-Null }
    icacls $R /setintegritylevel low | Out-Null
    "rótulos: L=" + ((icacls $L | Select-String 'Mandatory') -join ' ') + " | R=" + ((icacls $R | Select-String 'Mandatory') -join ' ') + " | M=" + ((icacls $M | Select-String 'Mandatory') -join ' ' ) + "(sem rótulo = médio)"
    $sent = Start-Process $pw -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 120' -PassThru -WindowStyle Hidden
    $mtx = [System.Threading.Mutex]::new($false, 'Local\sonda036-trava')
    $script = @"
`$o = '$L\resultado.txt'
function T(`$n, [scriptblock]`$b) { try { & `$b; Add-Content `$o "`$n = OK" } catch { Add-Content `$o "`$n = NEGADO (`$(`$_.Exception.GetType().Name): `$(`$_.Exception.Message.Split([char]10)[0]))" } }
Add-Content `$o ('nível: ' + ((whoami /groups | Select-String 'Mandatory Label') -replace '\s+', ' '))
T 'ler razão (médio)' { Get-Content '$M\razao.jsonl' -ErrorAction Stop | Out-Null }
T 'acrescentar no razão (médio)' { [IO.File]::AppendAllText('$M\razao.jsonl', 'x') }
T 'criar LIBERACAO_HUMANA.txt no RazaoDir (médio)' { [IO.File]::WriteAllText('$M\LIBERACAO_HUMANA.txt', 'falso') }
T 'apagar razão (médio)' { Remove-Item '$M\razao.jsonl' -ErrorAction Stop }
T 'escrever na pasta baixa' { [IO.File]::WriteAllText('$L\x.txt', 'ok') }
T 'escrever na árvore de trabalho do repo (baixa)' { Add-Content '$R\a.txt' 'mudou' -ErrorAction Stop }
T 'criar hook em .git (médio)' { [IO.File]::WriteAllText('$R\.git\hooks\pre-commit', 'echo x') }
T 'alterar .git\config (médio)' { [IO.File]::AppendAllText('$R\.git\config', '[core]') }
T 'git status no repo' { `$s = git -C '$R' status --porcelain 2>&1; if (`$LASTEXITCODE) { throw "git `$LASTEXITCODE: `$s" }; Add-Content `$o "   git status: `$s" }
T 'encerrar processo médio (sentinela)' { Stop-Process -Id $($sent.Id) -Force -ErrorAction Stop }
T 'abrir trava nomeada do médio' { [System.Threading.Mutex]::OpenExisting('Local\sonda036-trava') | Out-Null }
T 'escrever em %USERPROFILE%\.claude (médio)' { [IO.File]::WriteAllText("`$env:USERPROFILE\.claude\sonda036.txt", 'x') }
T 'claude --version' { `$v = & claude --version 2>&1; Add-Content `$o "   versão: `$v"; if (`$LASTEXITCODE) { throw "código `$LASTEXITCODE" } }
"@
    Set-Content "$L\teste.ps1" $script -Encoding utf8
    "Low pwsh: " + [Baixo]::Rodar("`"$pw`" -NoProfile -ExecutionPolicy Bypass -File `"$L\teste.ps1`"", $L, 120000)
    Get-Content "$L\resultado.txt" -ErrorAction SilentlyContinue
    "sentinela médio ainda vivo: " + [bool](Get-Process -Id $sent.Id -ErrorAction SilentlyContinue)
    "razão intacto: " + ((Get-Content "$M\razao.jsonl" -Raw).Trim() -eq '{"evento":"base_historica","valor_usd":0}') + " | LIBERACAO criada: " + (Test-Path "$M\LIBERACAO_HUMANA.txt")
    # claude -p real em baixa integridade (custo máx. US$ 0.05), configuração padrão do usuário
    $cl = (Get-Command claude -ErrorAction SilentlyContinue).Source
    "claude: $cl"
    $cmdCl = "`"$env:ComSpec`" /c `"`"$cl`" -p `"Responda apenas: ok`" --output-format json --max-budget-usd 0.05 --no-session-persistence > `"$L\claude-saida.txt`" 2> `"$L\claude-erro.txt`"`""
    "claude -p em Low IL: " + [Baixo]::Rodar($cmdCl, $L, 120000)
    "   saída: " + ((Get-Content "$L\claude-saida.txt" -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' ')
    "   erro:  " + ((Get-Content "$L\claude-erro.txt" -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' ')
    Stop-Process -Id $sent.Id -Force -ErrorAction SilentlyContinue; $mtx.Dispose()
    Remove-Item "$env:USERPROFILE\.claude\sonda036.txt" -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $raiz -ErrorAction SilentlyContinue
  } 2>&1
  "=== FIM $(Get-Date -Format s)"
} *>&1 | Out-File -FilePath $out -Encoding utf8
