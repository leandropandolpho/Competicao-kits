# lancador.ps1 — B-05, contrato v3.1 (Atos 075–077). Roda o controlador CONGELADO dentro de um Job Object,
# no pwsh PORTÁTIL (não empacotado), com orçamento controlado pelo razão e o embrulho no lugar do executor.
# Contenção = herança nativa do job na criação dos processos (H1–H3). A varredura só VERIFICA (não associa):
# descendente fora do job ⇒ falha fechada (E76-01).
# Códigos próprios (antes de iniciar o controlador, salvo 28/29 que também podem ocorrer depois):
#   20 trava ocupada (EstadoDir ou RazaoDir) · 21 razão ilegível · 22 processo antigo vivo · 23 saldo insuficiente
#   24 falha no Job Object · 25 versão do Claude · 26 pastas inválidas · 27 pwsh empacotado ou hash diferente
#   28 reconciliação divergente · 29 contenção violada (ou violação anterior sem liberação humana) · 30 vínculo divergente
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
  [string]$PwshSha256 = 'FA2C8BB1E35CDD62AD15CD06A1D8F2C5961E9725A9BFA1E7CFD2C322F49E9619',   # pwsh.exe 7.6.7 portátil
  [switch]$IgnorarVersao,            # só testes com executor simulado
  [switch]$TesteFalharAssociacao,    # só N10
  [switch]$TesteHandleHerdavel       # só N10
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'razao.ps1')
$Embrulho = Join-Path $PSScriptRoot 'claude-com-teto.cmd'

function Parar([int]$codigo, [string]$msg) {
  [Console]::Error.WriteLine("B05-LANCADOR ($codigo): $msg")
  if ($codigo -eq 30) { exit 30 }   # E76-03: vínculo divergente ⇒ nada é gravado no RazaoDir
  try { if (Test-Path -LiteralPath $RazaoDir) { [System.IO.File]::AppendAllText((Join-Path $RazaoDir 'notificacoes-b05.txt'), "[$((Get-Date).ToString('o'))] codigo $codigo — $msg`n", $script:Utf8SemBom) } } catch { }
  exit $codigo
}
function Canonico([string]$p) { [IO.Path]::GetFullPath($p).TrimEnd('\') }

if (-not $IsWindows) { Parar 24 'Job Object exige Windows' }

# ---------------- H1/H2: pwsh portátil, nunca o empacotado ----------------
$PwshProprio = (Get-Process -Id $PID).Path
if ($PwshProprio -match '\\WindowsApps\\') { Parar 27 "lançador rodando no pwsh empacotado (Microsoft Store): $PwshProprio" }
if ((Get-FileHash -LiteralPath $PwshProprio).Hash -ne $PwshSha256) { Parar 27 "hash do pwsh.exe diferente do fixado: $PwshProprio" }
$PwshDir = Split-Path $PwshProprio

# ---------------- Pastas ----------------
foreach ($d in $RazaoDir, $EstadoDir) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
$RazaoDir = Canonico (Resolve-Path -LiteralPath $RazaoDir).ProviderPath
$EstadoCan = Canonico (Resolve-Path -LiteralPath $EstadoDir).ProviderPath
$repoFull = (Canonico (Resolve-Path -LiteralPath $RepoPath).ProviderPath) + '\'
if (($RazaoDir + '\').StartsWith($repoFull, [StringComparison]::OrdinalIgnoreCase)) { Parar 26 'RazaoDir não pode ficar dentro do repositório' }

# ---------------- H7: travas por EstadoDir E por RazaoDir ----------------
function Tomar-Trava([string]$nome) {
  $m = [System.Threading.Mutex]::new($false, $nome); $ok = $false
  try { $ok = $m.WaitOne(0) } catch {
    $ex = $_.Exception; while ($ex -and -not ($ex -is [System.Threading.AbandonedMutexException])) { $ex = $ex.InnerException }
    if ($ex) { $ok = $true } else { throw }   # lançador anterior caiu: a trava abandonada passa a ser nossa
  }
  return @{ Mutex = $m; Ok = $ok }
}
$t1 = Tomar-Trava ((Razao-Nome-Trava $EstadoCan) + '-lancador-estado')
if (-not $t1.Ok) { Parar 20 "já existe um lançador ativo para o estado $EstadoCan" }
$t2 = Tomar-Trava ((Razao-Nome-Trava $RazaoDir) + '-lancador-razao')
if (-not $t2.Ok) { Parar 20 "já existe um lançador ativo para o razão $RazaoDir" }

# ---------------- E76-03: vínculo permanente EstadoDir ↔ RazaoDir ----------------
$vR = Join-Path $RazaoDir 'vinculo.json'; $vE = Join-Path $EstadoCan 'b05-vinculo.json'
$r = Razao-Ler $RazaoDir
if (-not $r.Ok) { Parar 21 "razão ilegível: $($r.Motivo)" }
$criarVinculo = $false
if ((Test-Path -LiteralPath $vR) -or (Test-Path -LiteralPath $vE)) {
  if (-not ((Test-Path -LiteralPath $vR) -and (Test-Path -LiteralPath $vE))) { Parar 30 'vínculo incompleto entre estado e razão (um dos lados ausente)' }
  $jr = Get-Content -LiteralPath $vR -Raw | ConvertFrom-Json; $je = Get-Content -LiteralPath $vE -Raw | ConvertFrom-Json
  if ("$($jr.estado_dir)" -ne $EstadoCan -or "$($je.razao_dir)" -ne $RazaoDir -or "$($jr.id)" -ne "$($je.id)") {
    Parar 30 "vínculo divergente: razão ligado a '$($jr.estado_dir)', estado ligado a '$($je.razao_dir)'"
  }
} else {
  if (@($r.Eventos | Where-Object { $_.evento -in @('inicio', 'fim', 'base_historica') }).Count) { Parar 30 'razão já usado e sem vínculo: não pode ser ligado a outro estado' }
  $criarVinculo = $true
}

# ---------------- E76-01 (verificação externa): violação anterior sem liberação humana ----------------
$violacoes = @($r.Eventos | Where-Object evento -eq 'contencao_violada')
if ($violacoes.Count) {
  $liberadas = @($r.Eventos | Where-Object evento -eq 'liberacao_humana' | ForEach-Object { "$($_.execucao_violada)" })
  $pend = @($violacoes | Where-Object { "$($_.execucao)" -notin $liberadas })
  if ($pend.Count) {
    $lib = Join-Path $RazaoDir 'LIBERACAO_HUMANA.txt'
    $texto = if (Test-Path -LiteralPath $lib) { Get-Content -LiteralPath $lib -Raw } else { '' }
    $ok = @($pend | Where-Object { $texto -match [regex]::Escape("$($_.execucao)") }).Count -eq $pend.Count
    if (-not $ok) { Parar 29 "contenção violada na execução $(@($pend | ForEach-Object { $_.execucao }) -join ', ') sem liberação humana (LIBERACAO_HUMANA.txt)" }
    foreach ($p in $pend) { Razao-Gravar $RazaoDir @{ evento = 'liberacao_humana'; execucao_violada = "$($p.execucao)"; texto = $texto.Trim() } }
    $r = Razao-Ler $RazaoDir
  }
}

# ---------------- E5: versão do Claude ----------------
if (-not $IgnorarVersao) {
  $v = (& $Executor --version 2>$null | Select-Object -First 1)
  if ("$v" -notmatch [regex]::Escape($VersaoClaude)) { Parar 25 "versão do Claude '$v' diferente da fixada '$VersaoClaude'" }
} else { $v = 'ignorada (teste)' }

# ---------------- P4: processos antigos ----------------
$vivos = @(Razao-ProcessosVivos $r.Eventos)
if ($vivos.Count) { Parar 22 "processo de execução anterior ainda vivo: $($vivos -join '; ')" }

# ---------------- E76-04/H8: base histórica, reconciliação e admissão ----------------
$arqEstado = Join-Path $EstadoCan 'estado.json'
function Custo-Estado { if (Test-Path -LiteralPath $arqEstado) { [double]((Get-Content -LiteralPath $arqEstado -Raw | ConvertFrom-Json).custo_acumulado_usd) } else { 0.0 } }
if ($criarVinculo) {
  $id = [guid]::NewGuid().ToString('N'); $ts = (Get-Date).ToString('o')
  Razao-Gravar $RazaoDir @{ evento = 'base_historica'; valor_usd = (Custo-Estado); vinculo = $id }
  [System.IO.File]::WriteAllText($vR, ([ordered]@{ id = $id; estado_dir = $EstadoCan; criado_em = $ts } | ConvertTo-Json), $script:Utf8SemBom)
  [System.IO.File]::WriteAllText($vE, ([ordered]@{ id = $id; razao_dir = $RazaoDir; criado_em = $ts } | ConvertTo-Json), $script:Utf8SemBom)
  $r = Razao-Ler $RazaoDir
}
function Conferir-Reconciliacao([string]$momento) {
  $rr = Razao-Ler $RazaoDir
  if (-not $rr.Ok) { return "razão ilegível: $($rr.Motivo)" }
  $cc = Razao-Contabilizar $rr.Eventos $Folga
  $est = Custo-Estado
  if ([math]::Abs($est - ($cc.Base + $cc.Conhecido)) -gt 1e-6) { return "estado.json $est ≠ base $($cc.Base) + conhecido $($cc.Conhecido) ($momento)" }
  return ''
}
$m = Conferir-Reconciliacao 'antes'
if ($m) { Parar 28 $m }
$c = Razao-Contabilizar $r.Eventos $Folga
if ($c.Total + $TetoChamadaUsd * (1 + $Folga) -gt $OrcamentoUsd) {
  Parar 23 "saldo insuficiente: base $($c.Base) + conhecido $($c.Conhecido) + reservado $($c.Reservado) + reserva $([math]::Round($TetoChamadaUsd * (1 + $Folga), 4)) > orçamento $OrcamentoUsd"
}

# ---------------- E3/P1: Job Object ----------------
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
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
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool TerminateJobObject(IntPtr job, uint code);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool TerminateProcess(IntPtr p, uint code);
  [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool Process32FirstW(IntPtr snap, ref PE32 e);
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool Process32NextW(IntPtr snap, ref PE32 e);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct PE32 { public uint dwSize, cntUsage, th32ProcessID; public IntPtr th32DefaultHeapID; public uint th32ModuleID, cntThreads, th32ParentProcessID; public int pcPriClassBase; public uint dwFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile; }

  // Configuração e leitura em C# (em PowerShell, $info.Basic devolve CÓPIA da struct aninhada — achado do 022).
  public static bool Configurar(IntPtr job, uint flags) { EXT i = new EXT(); i.Basic.LimitFlags = flags; return SetInformationJobObject(job, 9, ref i, (uint)Marshal.SizeOf(typeof(EXT))); }
  public static long Flags(IntPtr job) { EXT i = new EXT(); if (!QueryInformationJobObject(job, 9, ref i, (uint)Marshal.SizeOf(typeof(EXT)), IntPtr.Zero)) return -1; return i.Basic.LimitFlags; }
  public static uint[] Membros(IntPtr job) {
    int cap = 512; int size = 8 + cap * IntPtr.Size; IntPtr buf = Marshal.AllocHGlobal(size);
    try { if (!QueryInformationJobObject(job, 3, buf, (uint)size, IntPtr.Zero)) return null;
          int n = Marshal.ReadInt32(buf, 4); uint[] r = new uint[n];
          for (int i = 0; i < n; i++) r[i] = (uint)Marshal.ReadIntPtr(buf, 8 + i * IntPtr.Size).ToInt64(); return r; }
    finally { Marshal.FreeHGlobal(buf); }
  }

  // VERIFICAÇÃO (não associa nada): descendentes vivos cujo pai está rastreado. Um PID só entra em Verificados
  // depois de IsProcessInJob = true (H5). Devolve as violações: "pid|nome|pai|motivo".
  public static HashSet<uint> Verificados = new HashSet<uint>();
  public static HashSet<uint> PreExistentes = new HashSet<uint>();   // conhost criado pelo Windows ANTES do lançador entrar no job
  public static List<string> Verificar(IntPtr job) {
    var viol = new List<string>();
    IntPtr snap = CreateToolhelp32Snapshot(2, 0);
    if (snap == (IntPtr)(-1)) { viol.Add("0|snapshot|0|CreateToolhelp32Snapshot " + Marshal.GetLastWin32Error()); return viol; }
    var lista = new List<PE32>();
    try { PE32 e = new PE32(); e.dwSize = (uint)Marshal.SizeOf(typeof(PE32));
          if (Process32FirstW(snap, ref e)) { do { lista.Add(e); e.dwSize = (uint)Marshal.SizeOf(typeof(PE32)); } while (Process32NextW(snap, ref e)); } }
    finally { CloseHandle(snap); }
    bool mudou = true;
    while (mudou) {
      mudou = false;
      foreach (var p in lista) {
        if (Verificados.Contains(p.th32ProcessID) || PreExistentes.Contains(p.th32ProcessID) || !Verificados.Contains(p.th32ParentProcessID)) continue;
        IntPtr h = OpenProcess(0x1000 | 0x00100000, false, p.th32ProcessID);   // QUERY_LIMITED_INFORMATION | SYNCHRONIZE
        if (h == IntPtr.Zero) {
          int err = Marshal.GetLastWin32Error();
          if (err == 87) continue;   // processo já não existe: não conta
          viol.Add(p.th32ProcessID + "|" + p.szExeFile + "|" + p.th32ParentProcessID + "|não verificável (OpenProcess " + err + ")"); continue;
        }
        try {
          uint code; bool vivo = GetExitCodeProcess(h, out code) && code == 259;   // STILL_ACTIVE
          if (!vivo) continue;
          bool dentro;
          if (!IsProcessInJob(h, job, out dentro)) { viol.Add(p.th32ProcessID + "|" + p.szExeFile + "|" + p.th32ParentProcessID + "|IsProcessInJob falhou " + Marshal.GetLastWin32Error()); continue; }
          if (!dentro) { viol.Add(p.th32ProcessID + "|" + p.szExeFile + "|" + p.th32ParentProcessID + "|fora do job"); continue; }
          Verificados.Add(p.th32ProcessID); mudou = true;
        } finally { CloseHandle(h); }
      }
    }
    return viol;
  }
  // Processos vivos cuja cadeia de pais (no snapshot) chega a uma das raízes — os filhos de um externo também são externos.
  public static List<string> Subarvore(HashSet<uint> raizes) {
    var r = new List<string>();
    IntPtr snap = CreateToolhelp32Snapshot(2, 0);
    if (snap == (IntPtr)(-1)) return r;
    var lista = new List<PE32>();
    try { PE32 e = new PE32(); e.dwSize = (uint)Marshal.SizeOf(typeof(PE32));
          if (Process32FirstW(snap, ref e)) { do { lista.Add(e); e.dwSize = (uint)Marshal.SizeOf(typeof(PE32)); } while (Process32NextW(snap, ref e)); } }
    finally { CloseHandle(snap); }
    var conj = new HashSet<uint>(raizes); bool mudou = true;
    while (mudou) {
      mudou = false;
      foreach (var p in lista) {
        if (conj.Contains(p.th32ProcessID) || !conj.Contains(p.th32ParentProcessID) || p.th32ProcessID == 0) continue;
        conj.Add(p.th32ProcessID); r.Add(p.th32ProcessID + "|" + p.szExeFile + "|" + p.th32ParentProcessID); mudou = true;
      }
    }
    return r;
  }
  public static string Encerrar(uint pid) {
    IntPtr h = OpenProcess(0x0001, false, pid);   // TERMINATE
    if (h == IntPtr.Zero) { int err = Marshal.GetLastWin32Error(); return err == 87 ? "já terminado" : ("falhou: OpenProcess " + err); }
    try { return TerminateProcess(h, 29) ? "encerrado" : ("falhou: TerminateProcess " + Marshal.GetLastWin32Error()); } finally { CloseHandle(h); }
  }
}
'@
$job = [B05Job]::CreateJobObject([IntPtr]::Zero, $null)   # sem nome e sem atributos: handle não herdável e exclusivo
if ($job -eq [IntPtr]::Zero) { Parar 24 "CreateJobObject falhou ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
if (-not [B05Job]::Configurar($job, [B05Job]::KILL_ON_JOB_CLOSE)) { Parar 24 "SetInformationJobObject falhou ($([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
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

# Filhos do lançador que já existiam antes da associação: só o conhost.exe que o Windows cria quando o lançador nasce
# sem console herdado. Ele não descende do controlador; é registrado e ignorado pela verificação. Qualquer outro ⇒ 24.
$pre = @([B05Job]::Subarvore([System.Collections.Generic.HashSet[uint32]]::new([uint32[]]@([uint32]$PID))))
foreach ($x in $pre) {
  $pp = $x -split '\|'
  if ($pp[1] -ne 'conhost.exe' -or [uint32]$pp[2] -ne [uint32]$PID) { Parar 24 "processo pré-existente inesperado sob o lançador: $x" }
  [void][B05Job]::PreExistentes.Add([uint32]$pp[0])
}

# ---------------- H6: configuração imutável por execução; partida do controlador ----------------
$execucao = [guid]::NewGuid().ToString('N')
$cfg = [ordered]@{ execucao = $execucao; orcamento_usd = $OrcamentoUsd; teto_chamada_usd = $TetoChamadaUsd; folga = $Folga
                   executor = $Executor; executor_prefixo = $ExecutorPrefixo; versao_claude = "$v"; pwsh = $PwshProprio; criado_em = (Get-Date).ToString('o') }
$arqCfg = Join-Path $RazaoDir "config-$execucao.json"
$fs = [System.IO.FileStream]::new($arqCfg, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)   # CreateNew: nunca sobrescreve
try { $b = $script:Utf8SemBom.GetBytes(($cfg | ConvertTo-Json)); $fs.Write($b, 0, $b.Length); $fs.Flush($true) } finally { $fs.Dispose() }
(Get-Item -LiteralPath $arqCfg).IsReadOnly = $true
$env:B05_DIR = $RazaoDir; $env:B05_EXECUCAO = $execucao; $env:B05_PWSH = $PwshProprio
$env:PATH = "$PwshDir;$env:PATH"   # E76-02: "pwsh" pedido por qualquer descendente resolve para o portátil
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue

$psi = [System.Diagnostics.ProcessStartInfo]::new($PwshProprio)
foreach ($a in @('-NoProfile', '-File', $ControladorPath, '-RepoPath', $RepoPath, '-TarefasPath', $TarefasPath, '-EstadoDir', $EstadoDir,
                 '-TestCmd', $TestCmd, '-TestPaths', $TestPaths, '-TimeoutSec', "$TimeoutSec", '-MaxTentativas', "$MaxTentativas",
                 '-MaxCustoUsd', ([string]$OrcamentoUsd).Replace(',', '.'), '-MaxMinutos', ([string]$MaxMinutos).Replace(',', '.'), '-ClaudeCmd', $Embrulho)) { $psi.ArgumentList.Add($a) }
$psi.UseShellExecute = $false
$ctl = [System.Diagnostics.Process]::Start($psi)
try { $criacaoCtl = $ctl.StartTime.ToUniversalTime().ToString('o') } catch { $criacaoCtl = (Get-Date).ToUniversalTime().ToString('o') }
Razao-Gravar $RazaoDir @{ evento = 'controlador'; id = 'ctl'; execucao = $execucao; pid = $ctl.Id; criacao = $criacaoCtl; versao_claude = "$v"; flags_job = ('0x{0:X}' -f $fl); pwsh = $PwshProprio; preexistentes = @($pre) }

# ---------------- H3/H4/E76-01: verificação contínua; falha fechada ----------------
[void][B05Job]::Verificados.Add([uint32]$PID)
$dctl = $false; [void][B05Job]::IsProcessInJob($ctl.Handle, $job, [ref]$dctl)
if (-not $dctl) {
  Razao-Gravar $RazaoDir @{ evento = 'contencao_violada'; execucao = $execucao; violacoes = @("$($ctl.Id)|controlador|$PID|fora do job") }
  [void][B05Job]::TerminateJobObject($job, 29); exit 29
}
[void][B05Job]::Verificados.Add([uint32]$ctl.Id)
$ultimo = ''; $tick = 0
while (-not $ctl.HasExited) {
  $viol = [B05Job]::Verificar($job)
  if ($viol.Count) {
    # 1) registro durável ANTES de encerrar  2) encerra os externos e registra  3) encerra o job (inclusive este lançador)
    Razao-Gravar $RazaoDir @{ evento = 'contencao_violada'; execucao = $execucao; violacoes = @($viol) }
    # Encerra os externos e, em até 5 passadas, os descendentes deles (inclusive os criados entre um snapshot e outro).
    $alvos = [System.Collections.Generic.HashSet[uint32]]::new()
    foreach ($x in $viol) { $pv = [uint32]0; if ([uint32]::TryParse(($x -split '\|')[0], [ref]$pv) -and $pv -ne 0) { [void]$alvos.Add($pv) } }
    $res = [System.Collections.Generic.List[string]]::new()
    foreach ($pv in @($alvos)) { $res.Add("$pv|externo|$([B05Job]::Encerrar($pv))") }
    for ($pass = 0; $pass -lt 5; $pass++) {
      $novos = @([B05Job]::Subarvore($alvos) | Where-Object { -not $alvos.Contains([uint32](($_ -split '\|')[0])) })
      if (-not $novos.Count) { break }
      foreach ($x in $novos) { $pv = [uint32](($x -split '\|')[0]); [void]$alvos.Add($pv); $res.Add("$x|descendente de externo|$([B05Job]::Encerrar($pv))") }
    }
    try { Razao-Gravar $RazaoDir @{ evento = 'externos_encerramento'; execucao = $execucao; resultados = @($res) } } catch { }
    [void][B05Job]::TerminateJobObject($job, 29)
    exit 29   # só alcançado se o próprio lançador não tiver sido encerrado pelo job
  }
  if (($tick++ % 5) -eq 0) {
    $mb = [B05Job]::Membros($job)
    if ($mb) { $s = (@($mb | Sort-Object) -join ','); if ($s -ne $ultimo) { $ultimo = $s; try { Razao-Gravar $RazaoDir @{ evento = 'membros_job'; execucao = $execucao; pids = @($mb) } } catch { } } }
  }
  Start-Sleep -Milliseconds 100
}
$ctl.WaitForExit()
$codigo = $ctl.ExitCode

# ---------------- H9: reconciliação depois ----------------
$m = Conferir-Reconciliacao 'depois'
if ($m) { try { Razao-Gravar $RazaoDir @{ evento = 'divergencia_reconciliacao'; execucao = $execucao; detalhe = $m } } catch { }; Parar 28 $m }
exit $codigo
