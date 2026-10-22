# b05job.ps1 — tipo [B05Job] (Job Object, verificação de contenção, identidade de processo). Usado pelo lançador e pelos testes.
if (-not ('B05Job' -as [type])) {
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
  // conhost criado pelo Windows ANTES do lançador entrar no job: identidade = PID + instante de criação (FILETIME UTC).
  public static Dictionary<uint, long> PreExistentes = new Dictionary<uint, long>();
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetProcessTimes(IntPtr h, out long criacao, out long saida, out long kernel, out long usuario);
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageNameW(IntPtr h, uint flags, System.Text.StringBuilder nome, ref uint tam);
  // Devolve "" se não abriu; senão "criacao|caminho" (criação em FILETIME UTC).
  public static string Info(uint pid) {
    IntPtr h = OpenProcess(0x1000, false, pid);
    if (h == IntPtr.Zero) return "";
    try {
      long c, x, k, u; if (!GetProcessTimes(h, out c, out x, out k, out u)) return "";
      var sb = new System.Text.StringBuilder(1024); uint t = 1024;
      string cam = QueryFullProcessImageNameW(h, 0, sb, ref t) ? sb.ToString() : "";
      return c + "|" + cam;
    } finally { CloseHandle(h); }
  }
  static bool EhPreExistente(uint pid) {
    long c; if (!PreExistentes.TryGetValue(pid, out c)) return false;
    string i = Info(pid); return i != "" && i.Split('|')[0] == c.ToString();   // PID reutilizado ⇒ não é o mesmo processo
  }
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
        if (Verificados.Contains(p.th32ProcessID) || !Verificados.Contains(p.th32ParentProcessID) || EhPreExistente(p.th32ProcessID)) continue;
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
}
