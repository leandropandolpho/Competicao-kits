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
  // E84-04: restrições de UI do Job (classe 4 = JobObjectBasicUIRestrictions). 0xFF = todas:
  // HANDLES|READCLIPBOARD|WRITECLIPBOARD|SYSTEMPARAMETERS|DISPLAYSETTINGS|GLOBALATOMS|DESKTOP|EXITWINDOWS.
  // Barra ataques de UI (shatter/clipboard/atoms) a partir do executor. Subconjunto SEGURO: HANDLES (0x1, impede usar
  // handles de USER de processos fora do job — o anti-shatter), READCLIPBOARD (0x2), WRITECLIPBOARD (0x4) e
  // GLOBALATOMS (0x20). NÃO inclui DESKTOP/EXITWINDOWS/SYSTEMPARAMETERS/DISPLAYSETTINGS: 0xFF impedia o Claude (node)
  // de iniciar no job (achado 057/058 — sem job funcionava, com 0xFF não).
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr job, int cls, ref uint info, uint len);
  public static bool RestringirUI(IntPtr job) { uint r = 0x1 | 0x2 | 0x4 | 0x20; return SetInformationJobObject(job, 4, ref r, 4); }
  public static long Flags(IntPtr job) { EXT i = new EXT(); if (!QueryInformationJobObject(job, 9, ref i, (uint)Marshal.SizeOf(typeof(EXT)), IntPtr.Zero)) return -1; return i.Basic.LimitFlags; }
  public static uint[] Membros(IntPtr job) {
    int cap = 512; int size = 8 + cap * IntPtr.Size; IntPtr buf = Marshal.AllocHGlobal(size);
    try { if (!QueryInformationJobObject(job, 3, buf, (uint)size, IntPtr.Zero)) return null;
          int n = Marshal.ReadInt32(buf, 4); uint[] r = new uint[n];
          for (int i = 0; i < n; i++) r[i] = (uint)Marshal.ReadIntPtr(buf, 8 + i * IntPtr.Size).ToInt64(); return r; }
    finally { Marshal.FreeHGlobal(buf); }
  }

  // ---- Snapshot com instante de criação de TODOS os processos, sem precisar abri-los (NtQuerySystemInformation, classe 5).
  // Achado do 036/037: com o toolhelp (sem criação), um processo alheio cujo pai MORTO tinha o mesmo PID de um processo
  // nosso foi tomado por descendente. Regra agora: filho de P só se criado DEPOIS de P (identidade = PID + criação).
  public struct Proc { public uint Pid, Pai; public long Criacao; public string Nome; }
  [DllImport("ntdll.dll")] static extern int NtQuerySystemInformation(int cls, IntPtr buf, int len, out int ret);
  public static Dictionary<uint, Proc> Snapshot() {
    var r = new Dictionary<uint, Proc>(); int tam = 1 << 20;
    for (int t = 0; t < 8; t++) {
      IntPtr buf = Marshal.AllocHGlobal(tam); int ret;
      try {
        int st = NtQuerySystemInformation(5, buf, tam, out ret);
        if (st == unchecked((int)0xC0000004)) { tam = Math.Max(tam * 2, ret + 65536); continue; }   // STATUS_INFO_LENGTH_MISMATCH
        if (st != 0) throw new Exception("NtQuerySystemInformation 0x" + st.ToString("X"));
        long off = 0;
        while (true) {
          IntPtr e = (IntPtr)(buf.ToInt64() + off);
          Proc p = new Proc();
          p.Criacao = Marshal.ReadInt64(e, 32);
          short len = Marshal.ReadInt16(e, 56); IntPtr nb = Marshal.ReadIntPtr(e, 64);
          p.Nome = (nb == IntPtr.Zero || len == 0) ? "" : Marshal.PtrToStringUni(nb, len / 2);
          p.Pid = (uint)Marshal.ReadIntPtr(e, 80).ToInt64(); p.Pai = (uint)Marshal.ReadIntPtr(e, 88).ToInt64();
          r[p.Pid] = p;
          int prox = Marshal.ReadInt32(e, 0); if (prox == 0) break; off += prox;
        }
        return r;
      } finally { Marshal.FreeHGlobal(buf); }
    }
    throw new Exception("snapshot: buffer insuficiente");
  }
  // p é descendente direto do processo rastreado (pidPai, criacaoPai)?
  static bool FilhoDe(Proc p, uint pidPai, long criacaoPai, Dictionary<uint, Proc> snap) {
    if (p.Pai != pidPai || p.Criacao < criacaoPai) return false;
    Proc atual;   // o PID do pai foi reutilizado por outro processo vivo? então filhos criados depois dele são desse outro
    if (snap.TryGetValue(pidPai, out atual) && atual.Criacao != criacaoPai && p.Criacao >= atual.Criacao) return false;
    return true;
  }

  // VERIFICAÇÃO (não associa nada): descendentes vivos de processos rastreados (PID + criação). Um processo só passa a
  // rastreado depois de IsProcessInJob = true (H5). Devolve as violações: "pid|nome|pai|criação|motivo".
  public static Dictionary<uint, long> Verificados = new Dictionary<uint, long>();
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
  public static void Rastrear(uint pid) { var s = Snapshot(); Proc p; if (s.TryGetValue(pid, out p)) Verificados[pid] = p.Criacao; else throw new Exception("processo " + pid + " não encontrado para rastrear"); }
  public static List<string> Verificar(IntPtr job) {
    var viol = new List<string>();
    Dictionary<uint, Proc> snap;
    try { snap = Snapshot(); } catch (Exception ex) { viol.Add("0|snapshot|0|0|" + ex.Message); return viol; }
    bool mudou = true;
    while (mudou) {
      mudou = false;
      foreach (var p in snap.Values) {
        long c;
        if (Verificados.TryGetValue(p.Pid, out c) && c == p.Criacao) continue;          // já verificado (mesmo processo)
        if (PreExistentes.TryGetValue(p.Pid, out c) && c == p.Criacao) continue;        // conhost pré-existente dispensado
        long cp; if (!Verificados.TryGetValue(p.Pai, out cp) || !FilhoDe(p, p.Pai, cp, snap)) continue;
        string id = p.Pid + "|" + p.Nome + "|" + p.Pai + "|" + p.Criacao;
        IntPtr h = OpenProcess(0x1000 | 0x00100000, false, p.Pid);   // QUERY_LIMITED_INFORMATION | SYNCHRONIZE
        if (h == IntPtr.Zero) {
          int err = Marshal.GetLastWin32Error();
          if (err == 87) continue;   // processo já não existe: não conta
          viol.Add(id + "|não verificável (OpenProcess " + err + ")"); continue;
        }
        try {
          uint code; bool vivo = GetExitCodeProcess(h, out code) && code == 259;   // STILL_ACTIVE
          if (!vivo) continue;
          long cr, x, k, u; if (GetProcessTimes(h, out cr, out x, out k, out u) && cr != p.Criacao) continue;   // PID trocou entre snapshot e abertura
          bool dentro;
          if (!IsProcessInJob(h, job, out dentro)) { viol.Add(id + "|IsProcessInJob falhou " + Marshal.GetLastWin32Error()); continue; }
          if (!dentro) { viol.Add(id + "|fora do job"); continue; }
          Verificados[p.Pid] = p.Criacao; mudou = true;
        } finally { CloseHandle(h); }
      }
    }
    return viol;
  }
  // Descendentes vivos (mesma regra PID + criação) das raízes informadas. Devolve "pid|nome|pai|criação".
  public static List<string> Subarvore(Dictionary<uint, long> raizes) {
    var r = new List<string>(); var snap = Snapshot();
    var conj = new Dictionary<uint, long>(raizes); bool mudou = true;
    while (mudou) {
      mudou = false;
      foreach (var p in snap.Values) {
        long c; if (p.Pid == 0 || (conj.TryGetValue(p.Pid, out c) && c == p.Criacao)) continue;
        long cp; if (!conj.TryGetValue(p.Pai, out cp) || !FilhoDe(p, p.Pai, cp, snap)) continue;
        conj[p.Pid] = p.Criacao; r.Add(p.Pid + "|" + p.Nome + "|" + p.Pai + "|" + p.Criacao); mudou = true;
      }
    }
    return r;
  }
  // Encerra SÓ se o processo ainda for o mesmo (PID + criação) — nunca um processo alheio que herdou o PID.
  public static string Encerrar(uint pid, long criacao) {
    IntPtr h = OpenProcess(0x0001 | 0x1000, false, pid);   // TERMINATE | QUERY_LIMITED_INFORMATION
    if (h == IntPtr.Zero) { int err = Marshal.GetLastWin32Error(); return err == 87 ? "já terminado" : ("falhou: OpenProcess " + err); }
    try {
      long cr, x, k, u;
      if (!GetProcessTimes(h, out cr, out x, out k, out u)) return "falhou: GetProcessTimes " + Marshal.GetLastWin32Error();
      if (cr != criacao) return "não encerrado: PID reutilizado por outro processo";
      return TerminateProcess(h, 29) ? "encerrado" : ("falhou: TerminateProcess " + Marshal.GetLastWin32Error());
    } finally { CloseHandle(h); }
  }

}
'@
}
