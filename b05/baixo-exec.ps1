# baixo-exec.ps1 (E84-05/G3) — executa o comando recebido em $args em BAIXA integridade, na pasta atual (a árvore de
# trabalho do repositório). Usado pelo baixo.cmd, que o controlador congelado chama como prefixo do TestCmd. Assim o
# código de teste do repositório — que o executor pode ter alterado — roda contido, sem autoridade de nível médio.
# Antes de rodar, varre a árvore por reparse points (falha fechada). Repassa stdout/stderr e o código de saída.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$Utf8 = [System.Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'baixa-integridade.ps1')

if (-not $args -or $args.Count -eq 0) { [Console]::Error.Write('baixo-exec: sem comando'); exit 96 }
$cwd = (Get-Location).Path

# E84-05/F10: reparse points OU varredura incompleta na árvore de trabalho ⇒ falha fechada antes de qualquer execução.
$rep = B05LowIL-ReparsePoints $cwd
if (-not $rep.Ok) { [Console]::Error.Write('baixo-exec: varredura de reparse points NÃO completou — abortado'); exit 29 }
if (@($rep.Pontos).Count) { [Console]::Error.Write("baixo-exec: reparse point/junction ($(@($rep.Pontos) -join '; ')) — abortado"); exit 29 }

if (-not $IsWindows) { [Console]::Error.Write('baixo-exec exige Windows'); exit 95 }

$exe = [string]$args[0]
$cmd = Get-Command -Name $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cmd) { $exe = $cmd.Source }
$rest = @($args | Select-Object -Skip 1 | ForEach-Object { [string]$_ })

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('baixo-exec-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
New-Item -ItemType Directory -Force $tmp | Out-Null
& icacls $tmp /setintegritylevel '(OI)(CI)low' /Q 2>&1 | Out-Null
$inFile = "$tmp\in.txt"; $outFile = "$tmp\out.txt"; $errFile = "$tmp\err.txt"
[System.IO.File]::WriteAllText($inFile, '', $Utf8)

$tok = [IntPtr]::Zero; $msg = [B05LowIL]::CriarToken([ref]$tok)
if ($msg) { [Console]::Error.Write("baixo-exec: token baixo: $msg"); exit 94 }
$cmdline = B05LowIL-Cmdline $exe $rest $inFile $outFile $errFile
$lpid = 0; $hProc = [IntPtr]::Zero
try { $msg = [B05LowIL]::Lancar($tok, $cmdline, $cwd, [IntPtr]::Zero, [ref]$lpid, [ref]$hProc) }
finally { [B05LowIL]::Fechar($tok) }
if ($msg) { [Console]::Error.Write("baixo-exec: lançar baixo: $msg"); exit 93 }
$codigo = [int][B05LowIL]::Esperar($hProc, [uint32]::MaxValue)
[B05LowIL]::Fechar($hProc)
if (Test-Path $outFile) { [Console]::Out.Write([System.IO.File]::ReadAllText($outFile, $Utf8)) }
if (Test-Path $errFile) { $e = [System.IO.File]::ReadAllText($errFile, $Utf8); if ($e) { [Console]::Error.Write($e) } }
try { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue } catch { }
exit $codigo
