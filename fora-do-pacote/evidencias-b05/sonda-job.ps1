# sonda-job.ps1 — Ato 075: cria job (KILL_ON_JOB_CLOSE), associa-se, inicia filho pwsh → cmd → ping.
param([string]$Filho, [string]$Marca)
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
  // Varredura ativa (achado do 025): no Windows desta máquina, filhos do controlador (pwsh da Microsoft Store,
  // empacotado) NÃO herdaram o job aninhado. Por isso o lançador também associa ativamente ao job todo
  // descendente que encontrar (pai já rastreado), a cada ~100 ms. Herança continua valendo quando funciona.
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct PE32 { public uint dwSize, cntUsage, th32ProcessID; public IntPtr th32DefaultHeapID; public uint th32ModuleID, cntThreads, th32ParentProcessID; public int pcPriClassBase; public uint dwFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile; }
  [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool Process32FirstW(IntPtr snap, ref PE32 e);
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool Process32NextW(IntPtr snap, ref PE32 e);
  [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool CloseHandle(IntPtr h);
  public static System.Collections.Generic.HashSet<uint> Rastreados = new System.Collections.Generic.HashSet<uint>();
  public static System.Collections.Generic.List<string> Erros = new System.Collections.Generic.List<string>();
  public static System.Collections.Generic.Dictionary<uint, string> Nomes = new System.Collections.Generic.Dictionary<uint, string>();
  public static int Varrer(IntPtr job) {
    IntPtr snap = CreateToolhelp32Snapshot(2, 0); if (snap == (IntPtr)(-1)) { Erros.Add("snapshot " + Marshal.GetLastWin32Error()); return -1; }
    int n = 0;
    try {
      var lista = new System.Collections.Generic.List<uint[]>();
      PE32 e = new PE32(); e.dwSize = (uint)Marshal.SizeOf(typeof(PE32));
      if (Process32FirstW(snap, ref e)) { do { lista.Add(new uint[] { e.th32ProcessID, e.th32ParentProcessID }); Nomes[e.th32ProcessID] = e.szExeFile; e.dwSize = (uint)Marshal.SizeOf(typeof(PE32)); } while (Process32NextW(snap, ref e)); }
      bool mudou = true;
      while (mudou) {
        mudou = false;
        foreach (var pp in lista) {
          if (Rastreados.Contains(pp[0]) || !Rastreados.Contains(pp[1])) continue;
          Rastreados.Add(pp[0]); mudou = true;
          IntPtr h = OpenProcess(0x0101, false, pp[0]);   // SET_QUOTA | TERMINATE
          if (h == IntPtr.Zero) { Erros.Add("open " + pp[0] + " " + Nomes[pp[0]] + " (filho de " + pp[1] + ") erro " + Marshal.GetLastWin32Error()); continue; }
          bool dentro; IsProcessInJob(h, job, out dentro);
          if (!dentro) { if (AssignProcessToJobObject(job, h)) n++; else Erros.Add("assign " + pp[0] + " " + Nomes[pp[0]] + " (filho de " + pp[1] + ") erro " + Marshal.GetLastWin32Error()); }
          CloseHandle(h);
        }
      }
    } finally { CloseHandle(snap); }
    return n;
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
$job = [B05Job]::CreateJobObject([IntPtr]::Zero, $null)
[void][B05Job]::Configurar($job, [B05Job]::KILL_ON_JOB_CLOSE)
$ok = [B05Job]::AssignProcessToJobObject($job, [B05Job]::GetCurrentProcess())
"associou-se: $ok | flags: 0x{0:X}" -f [B05Job]::Flags($job)
# Mesmo jeito do controlador: ProcessStartInfo com UseShellExecute = false (sem ShellExecute).
$psi = [System.Diagnostics.ProcessStartInfo]::new($Filho); foreach ($x in @('-NoProfile', '-Command', "cmd /c ping -n 40 127.0.0.1 & rem $Marca")) { $psi.ArgumentList.Add($x) }
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
Start-Sleep 6
"membros do job: " + ((([B05Job]::Membros($job)) | Sort-Object) -join ',')
Start-Sleep 60
