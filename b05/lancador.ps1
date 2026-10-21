# lancador.ps1 — B-05 (contrato v2, Ato 072): roda o controlador CONGELADO dentro de um Job Object do Windows,
# com orçamento controlado pelo razão e o embrulho claude-com-teto no lugar do executor.
# Não altera o controlador: só o chama com -ClaudeCmd <embrulho> e -MaxCustoUsd <orçamento total>.
# Códigos de saída próprios (antes de iniciar o controlador):
#   20 outra instância para o mesmo EstadoDir (R3r) · 21 razão ilegível (E4) · 22 processo antigo vivo (P4)
#   23 saldo insuficiente (C5)            · 24 falha no Job Object (E3)  · 25 versão do Claude diferente (E5)
#   26 configuração inválida (pastas)
# Fora isso, devolve o código do controlador.
param(
  [Parameter(Mandatory)][string]$RepoPath,
  [Parameter(Mandatory)][string]$TarefasPath,
  [Parameter(Mandatory)][string]$EstadoDir,
  [Parameter(Mandatory)][string]$RazaoDir,
  [Parameter(Mandatory)][string]$ControladorPath,
  [Parameter(Mandatory)][string]$TestCmd,
  [Parameter(Mandatory)][string]$TestPaths,
  [Parameter(Mandatory)][double]$OrcamentoUsd,
  [double]$TetoChamadaUsd = 0.50,
  [double]$Folga = 0.25,
  [int]$TimeoutSec = 600,
  [int]$MaxTentativas = 2,
  [double]$MaxMinutos = 60,
  [string]$Executor = 'claude',
  [string]$ExecutorPrefixo = '',
  [string]$VersaoClaude = '2.1.302',
  [switch]$IgnorarVersao,            # só para testes com executor simulado
  [switch]$TesteFalharAssociacao,    # só para o cenário N10
  [switch]$TesteHandleHerdavel       # só para o cenário N10
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'razao.ps1')
$Embrulho = Join-Path $PSScriptRoot 'claude-com-teto.cmd'

function Parar([int]$codigo, [string]$msg) {
  [Console]::Error.WriteLine("B05-LANCADOR ($codigo): $msg")
  try { if (Test-Path -LiteralPath $RazaoDir) { [System.IO.File]::AppendAllText((Join-Path $RazaoDir 'notificacoes-b05.txt'), "[$((Get-Date).ToString('o'))] codigo $codigo — $msg`n", $script:Utf8SemBom) } } catch { }
  exit $codigo
}

if (-not $IsWindows) { Parar 24 'Job Object exige Windows' }

# ---------------- Pastas ----------------
New-Item -ItemType Directory -Force -Path $RazaoDir | Out-Null
$RazaoDir = (Resolve-Path -LiteralPath $RazaoDir).ProviderPath
$repoFull = (Resolve-Path -LiteralPath $RepoPath).ProviderPath.TrimEnd('\') + '\'
if (($RazaoDir.TrimEnd('\') + '\').StartsWith($repoFull, [StringComparison]::OrdinalIgnoreCase)) { Parar 26 'RazaoDir não pode ficar dentro do repositório' }

# ---------------- R3r: uma instância por EstadoDir ----------------
$estadoFull = [IO.Path]::GetFullPath($EstadoDir)
$trava = [System.Threading.Mutex]::new($false, ((Razao-Nome-Trava $estadoFull) + '-lancador'))
$obtida = $false
try { $obtida = $trava.WaitOne(0) } catch {
  # Lançador anterior caiu segurando a trava: o Windows a entrega como "abandonada" — passa a ser nossa.
  $ex = $_.Exception; while ($ex -and -not ($ex -is [System.Threading.AbandonedMutexException])) { $ex = $ex.InnerException }
  if ($ex) { $obtida = $true } else { throw }
}
if (-not $obtida) { Parar 20 "já existe um lançador ativo para $estadoFull" }

# ---------------- E5: versão do Claude ----------------
if (-not $IgnorarVersao) {
  $v = (& $Executor --version 2>$null | Select-Object -First 1)
  if ("$v" -notmatch [regex]::Escape($VersaoClaude)) { Parar 25 "versão do Claude '$v' diferente da fixada '$VersaoClaude'" }
} else { $v = 'ignorada (teste)' }

# ---------------- E4/P4/C5: reconciliação antes de iniciar ----------------
$r = Razao-Ler $RazaoDir
if (-not $r.Ok) { Parar 21 "razão ilegível: $($r.Motivo)" }
$vivos = @(Razao-ProcessosVivos $r.Eventos)
if ($vivos.Count) { Parar 22 "processo de execução anterior ainda vivo: $($vivos -join '; ')" }
$c = Razao-Contabilizar $r.Eventos $Folga
if ($OrcamentoUsd - $c.Total -lt $TetoChamadaUsd * (1 + $Folga)) { Parar 23 "saldo insuficiente: orçamento US$ $OrcamentoUsd, contabilizado US$ $($c.Total) (conhecido $($c.Conhecido) + reservado $($c.Reservado))" }

# ---------------- E3/P1: Job Object ----------------
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class B05Job {
  [StructLayout(LayoutKind.Sequential)] public struct BASIC { public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags; public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass; }
  [StructLayout(LayoutKind.Sequential)] public struct IOC { public ulong a, b, c, d, e, f; }
  [StructLayout(LayoutKind.Sequential)] public struct EXT { public BASIC Basic; public IOC Io; public UIntPtr ProcessMemoryLimit; public UIntPtr JobMemoryLimit; public UIntPtr PeakProcessMemoryUsed; public UIntPtr PeakJobMemoryUsed; }
  public const uint KILL_ON_JOB_CLOSE = 0x2000, BREAKAWAY_OK = 0x800, SILENT_BREAKAWAY_OK = 0x1000, HANDLE_FLAG_INHERIT = 1;
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern IntPtr CreateJobObject(IntPtr attr, string name);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetInformationJobObject(IntPtr job, int cls, ref EXT info, uint len);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool QueryInformationJobObject(IntPtr job, int cls, ref EXT info, uint len, IntPtr ret);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool QueryInformationJobObject(IntPtr job, int cls, IntPtr buf, uint len, IntPtr ret);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr proc);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool IsProcessInJob(IntPtr proc, IntPtr job, out bool result);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetHandleInformation(IntPtr h, out uint flags);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetHandleInformation(IntPtr h, uint mask, uint flags);
  [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
  // Configuração e leitura feitas em C#: em PowerShell, $info.Basic devolve CÓPIA da struct aninhada
  // (alterar LimitFlags por ali não muda nada — foi o que a verificação do 022 pegou: flags 0x0).
  public static bool Configurar(IntPtr job, uint flags) {
    EXT info = new EXT(); info.Basic.LimitFlags = flags;
    return SetInformationJobObject(job, 9, ref info, (uint)Marshal.SizeOf(typeof(EXT)));
  }
  public static long Flags(IntPtr job) {
    EXT info = new EXT();
    if (!QueryInformationJobObject(job, 9, ref info, (uint)Marshal.SizeOf(typeof(EXT)), IntPtr.Zero)) return -1;
    return info.Basic.LimitFlags;
  }
  public static uint[] Membros(IntPtr job) {
    int cap = 256; int size = 8 + cap * IntPtr.Size; IntPtr buf = Marshal.AllocHGlobal(size);
    try {
      if (!QueryInformationJobObject(job, 3, buf, (uint)size, IntPtr.Zero)) return null;
      int n = Marshal.ReadInt32(buf, 4); uint[] r = new uint[n];
      for (int i = 0; i < n; i++) r[i] = (uint)Marshal.ReadIntPtr(buf, 8 + i * IntPtr.Size).ToInt64();
      return r;
    } finally { Marshal.FreeHGlobal(buf); }
  }
}
'@
$job = [B05Job]::CreateJobObject([IntPtr]::Zero, $null)   # sem nome e sem atributos: handle não herdável
if ($job -eq [IntPtr]::Zero) { Parar 24 "CreateJobObject falhou ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
if (-not [B05Job]::Configurar($job, [B05Job]::KILL_ON_JOB_CLOSE)) { Parar 24 "SetInformationJobObject falhou ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
# Confere os limites efetivos: KILL_ON_JOB_CLOSE ligado; breakaway proibido.
$fl = [B05Job]::Flags($job)
if ($fl -lt 0) { Parar 24 'QueryInformationJobObject falhou' }
if (-not ($fl -band [B05Job]::KILL_ON_JOB_CLOSE) -or ($fl -band [B05Job]::BREAKAWAY_OK) -or ($fl -band [B05Job]::SILENT_BREAKAWAY_OK)) { Parar 24 ("limites do job inesperados: 0x{0:X}" -f $fl) }
if ($TesteHandleHerdavel) { [B05Job]::SetHandleInformation($job, [B05Job]::HANDLE_FLAG_INHERIT, [B05Job]::HANDLE_FLAG_INHERIT) | Out-Null }
$hf = [uint32]0
if (-not [B05Job]::GetHandleInformation($job, [ref]$hf)) { Parar 24 'GetHandleInformation falhou' }
if ($hf -band [B05Job]::HANDLE_FLAG_INHERIT) { Parar 24 'handle do job está herdável' }
$eu = [B05Job]::GetCurrentProcess()
$ok = if ($TesteFalharAssociacao) { $false } else { [B05Job]::AssignProcessToJobObject($job, $eu) }
if (-not $ok) { Parar 24 "AssignProcessToJobObject falhou ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
$dentro = $false
if (-not [B05Job]::IsProcessInJob($eu, $job, [ref]$dentro) -or -not $dentro) { Parar 24 'o lançador não está no job após a associação' }

# ---------------- Configuração do embrulho e partida do controlador ----------------
$execucao = [guid]::NewGuid().ToString('N')
$cfg = [ordered]@{ execucao = $execucao; orcamento_usd = $OrcamentoUsd; teto_chamada_usd = $TetoChamadaUsd; folga = $Folga
                   executor = $Executor; executor_prefixo = $ExecutorPrefixo; versao_claude = "$v"; criado_em = (Get-Date).ToString('o') }
$tmp = Join-Path $RazaoDir 'config.json.tmp'
[System.IO.File]::WriteAllText($tmp, ($cfg | ConvertTo-Json), $script:Utf8SemBom); Move-Item -Force $tmp (Join-Path $RazaoDir 'config.json')
$env:B05_DIR = $RazaoDir
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue

$psi = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
foreach ($a in @('-NoProfile', '-File', $ControladorPath, '-RepoPath', $RepoPath, '-TarefasPath', $TarefasPath, '-EstadoDir', $EstadoDir,
                 '-TestCmd', $TestCmd, '-TestPaths', $TestPaths, '-TimeoutSec', "$TimeoutSec", '-MaxTentativas', "$MaxTentativas",
                 '-MaxCustoUsd', ([string]$OrcamentoUsd).Replace(',', '.'), '-MaxMinutos', ([string]$MaxMinutos).Replace(',', '.'), '-ClaudeCmd', $Embrulho)) { $psi.ArgumentList.Add($a) }
$psi.UseShellExecute = $false
$ctl = [System.Diagnostics.Process]::Start($psi)
try { $criacaoCtl = $ctl.StartTime.ToUniversalTime().ToString('o') } catch { $criacaoCtl = (Get-Date).ToUniversalTime().ToString('o') }
Razao-Gravar $RazaoDir @{ evento = 'controlador'; id = 'ctl'; execucao = $execucao; pid = $ctl.Id; criacao = $criacaoCtl; versao_claude = "$v"; flags_job = ('0x{0:X}' -f $fl) }

# P1 (prova de contenção): registra a lista de processos do job sempre que muda.
$ultimo = ''
while (-not $ctl.HasExited) {
  $m = [B05Job]::Membros($job)
  if ($m) { $s = (@($m | Sort-Object) -join ','); if ($s -ne $ultimo) { $ultimo = $s; try { Razao-Gravar $RazaoDir @{ evento = 'membros_job'; execucao = $execucao; pids = @($m) } } catch { } } }
  Start-Sleep -Milliseconds 500
}
$ctl.WaitForExit()
exit $ctl.ExitCode
