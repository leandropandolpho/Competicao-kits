# baixa-integridade.ps1 — B-05 E84-02 (Atos 084–088). Tipo [B05LowIL]: cria um token de BAIXA integridade e
# RESTRITO (sem privilégios) e lança um processo com ele, sem herança de handles. Também lê o nível de integridade
# de um processo (para a verificação G4 no lançador). Usado pelo embrulho e pelos testes.
# Viabilidade comprovada na sonda 042 (Windows real, conta piloto sem admin): Claude Code completou tarefa em Low IL.
if (-not ('B05LowIL' -as [type])) {
  Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class B05LowIL {
  [StructLayout(LayoutKind.Sequential)] struct SIDATTR { public IntPtr Sid; public uint Attr; }
  [StructLayout(LayoutKind.Sequential)] struct TML { public SIDATTR Label; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct SI { public int cb; public string r, d, t; public int x, y, xs, ys, xc, yc, fill, flags; public short show, r2; public IntPtr r3, i, o, e; }
  [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr hp, ht; public int pid, tid; }
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr p, uint a, out IntPtr t);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool CreateRestrictedToken(IntPtr tok, uint flags, uint nSid, IntPtr sids, uint nPriv, IntPtr privs, uint nRes, IntPtr res, out IntPtr novo);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool DuplicateTokenEx(IntPtr t, uint a, IntPtr sa, int imp, int tipo, out IntPtr n);
  [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool ConvertStringSidToSidW(string s, out IntPtr sid);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool SetTokenInformation(IntPtr t, int cls, ref TML i, uint len);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool GetTokenInformation(IntPtr t, int cls, IntPtr buf, uint len, out uint ret);
  [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool CreateProcessAsUserW(IntPtr t, string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool herda, uint f, IntPtr env, string dir, ref SI si, out PI pi);
  [DllImport("advapi32.dll", SetLastError = true)] static extern IntPtr GetSidSubAuthority(IntPtr sid, uint i);
  [DllImport("advapi32.dll", SetLastError = true)] static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint a, bool h, int pid);
  [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h, out uint c);
  [DllImport("kernel32.dll")] static extern bool GetProcessTimes(IntPtr h, out long c, out long x, out long k, out long u);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h, uint c);
  [DllImport("kernel32.dll")] static extern bool IsProcessInJob(IntPtr p, IntPtr job, out bool r);
  [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string s, uint rev, out IntPtr sd, out uint sz);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool GetSecurityDescriptorSacl(IntPtr sd, out bool present, out IntPtr sacl, out bool deflt);
  [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern uint SetNamedSecurityInfoW(string name, int type, uint info, IntPtr owner, IntPtr grp, IntPtr dacl, IntPtr sacl);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
  const uint DISABLE_MAX_PRIVILEGE = 0x1;
  public static bool EmJob(IntPtr h) { bool r; return IsProcessInJob(h, IntPtr.Zero, out r) && r; }

  // E84-03: rótulo de integridade MÉDIO com NO_WRITE_UP + NO_READ_UP + NO_EXECUTE_UP (SDDL "S:(ML;OICI;NRNWNX;;;ME)"),
  // herdável. Processos abaixo de médio não leem/escrevem/executam o alvo. Médio+ continuam normais. Não exige admin.
  // type: SE_FILE_OBJECT=1. info: LABEL_SECURITY_INFORMATION=0x10. Devolve "" ou erro.
  public static string RotularNRNW(string caminho) { return RotularSacl(caminho, "S:(ML;OICI;NRNWNX;;;ME)"); }
  // B05-F09-R: rótulo MÉDIO explícito e herdável (NO_WRITE_UP), para que a releitura confirme um rótulo verificável
  // (icacls medium pode não deixar ACE explícito; aqui garantimos "8192|1" legível por InfoLabel).
  public static string RotularMedio(string caminho) { return RotularSacl(caminho, "S:(ML;OICI;NW;;;ME)"); }
  static string RotularSacl(string caminho, string sddl) {
    IntPtr sd; uint sz;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, 1, out sd, out sz)) return "ConvertSD " + Marshal.GetLastWin32Error();
    try {
      bool pres, def; IntPtr sacl;
      if (!GetSecurityDescriptorSacl(sd, out pres, out sacl, out def) || !pres) return "GetSacl " + Marshal.GetLastWin32Error();
      uint rc = SetNamedSecurityInfoW(caminho, 1, 0x10, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, sacl);
      return rc == 0 ? "" : ("SetNamedSecurityInfo " + rc);
    } finally { LocalFree(sd); }
  }

  // B05-F09: lê o rótulo de integridade EFETIVO de um arquivo/pasta. Devolve "rid|mask" (rid 4096 baixo, 8192 médio,
  // 12288 alto; mask: NW=1 NR=2 NX=4), "nenhum" (sem rótulo explícito = médio por padrão), ou "erro:<n>".
  [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern uint GetNamedSecurityInfoW(string name, int type, uint info, IntPtr owner, IntPtr grp, IntPtr dacl, out IntPtr sacl, out IntPtr sd);
  [DllImport("advapi32.dll")] static extern bool GetAce(IntPtr acl, int index, out IntPtr ace);
  public static string InfoLabel(string caminho) {
    IntPtr sacl, sd;
    uint rc = GetNamedSecurityInfoW(caminho, 1, 0x10, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, out sacl, out sd);
    if (rc != 0) return "erro:" + rc;
    try {
      if (sacl == IntPtr.Zero) return "nenhum";
      int count = Marshal.ReadInt16(sacl, 4);
      if (count < 1) return "nenhum";
      IntPtr ace;
      if (!GetAce(sacl, 0, out ace)) return "erro:getace";
      if (Marshal.ReadByte(ace, 0) != 0x11) return "nao-ml";   // SYSTEM_MANDATORY_LABEL_ACE
      uint mask = (uint)Marshal.ReadInt32(ace, 4);
      IntPtr sid = (IntPtr)(ace.ToInt64() + 8);
      int cont = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
      uint rid = (uint)Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(cont - 1)));
      return rid + "|" + mask;
    } finally { if (sd != IntPtr.Zero) LocalFree(sd); }
  }

  // Token de baixa integridade + restrito (sem privilégios). Devolve "" ou a mensagem de erro.
  public static string CriarToken(out IntPtr tokenBaixo) {
    tokenBaixo = IntPtr.Zero; IntPtr t, restrito, dup, sid;
    // TOKEN_ADJUST_DEFAULT (0x0080) é obrigatório para SetTokenInformation(TokenIntegrityLevel); sem ele dá ACCESS_DENIED (5).
    if (!OpenProcessToken(GetCurrentProcess(), 0x0002 | 0x0008 | 0x0001 | 0x0004, out t)) return "OpenProcessToken " + Marshal.GetLastWin32Error();
    if (!CreateRestrictedToken(t, DISABLE_MAX_PRIVILEGE, 0, IntPtr.Zero, 0, IntPtr.Zero, 0, IntPtr.Zero, out restrito)) return "CreateRestrictedToken " + Marshal.GetLastWin32Error();
    if (!DuplicateTokenEx(restrito, 0x0002 | 0x0008 | 0x0080 | 0x0001, IntPtr.Zero, 2, 1, out dup)) return "DuplicateTokenEx " + Marshal.GetLastWin32Error();
    if (!ConvertStringSidToSidW("S-1-16-4096", out sid)) return "ConvertStringSid " + Marshal.GetLastWin32Error();
    TML m = new TML(); m.Label.Sid = sid; m.Label.Attr = 0x20;   // SE_GROUP_INTEGRITY
    if (!SetTokenInformation(dup, 25, ref m, (uint)(Marshal.SizeOf(typeof(TML)) + 12))) return "SetTokenInformation " + Marshal.GetLastWin32Error();
    tokenBaixo = dup; return "";
  }

  // Lança 'cmdline' com o token. bInheritHandles=FALSE (E84-02: sem herança de handles) — a E/S vai por redireção de
  // arquivo embutida na própria linha (cmd /c "... < in > out 2> err"). CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT.
  // 'env' = bloco de ambiente (IntPtr.Zero herda o do pai; a E84-03 passa um bloco higienizado). Devolve "" ou erro.
  public static string Lancar(IntPtr token, string cmdline, string cwd, IntPtr env, out int pid, out IntPtr hProc) {
    pid = 0; hProc = IntPtr.Zero;
    SI s = new SI(); s.cb = Marshal.SizeOf(typeof(SI)); PI pi;
    uint flags = 0x08000000 | 0x00000400;   // CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT
    if (!CreateProcessAsUserW(token, null, new StringBuilder(cmdline), IntPtr.Zero, IntPtr.Zero, false, flags, env, cwd, ref s, out pi)) return "CreateProcessAsUser " + Marshal.GetLastWin32Error();
    pid = pi.pid; hProc = pi.hp; CloseHandle(pi.ht); return "";
  }
  public static uint Esperar(IntPtr hProc, uint ms) { WaitForSingleObject(hProc, ms); uint c; return GetExitCodeProcess(hProc, out c) ? c : 0xFFFFFFFF; }
  // PE-F01: devolve o RESULTADO da espera (0=WAIT_OBJECT_0 sinalizado; 0x102=258 WAIT_TIMEOUT; 0xFFFFFFFF=WAIT_FAILED).
  // So apos sinalizado e que GetExitCodeProcess devolve o codigo real (senao 259 STILL_ACTIVE). Esperar() fica intacto (B-05).
  public static uint EsperarSinal(IntPtr hProc, uint ms) { return WaitForSingleObject(hProc, ms); }
  public static long CriacaoUtc(IntPtr hProc) { long c, x, k, u; return GetProcessTimes(hProc, out c, out x, out k, out u) ? c : 0; }
  public static void Encerrar(IntPtr hProc) { try { TerminateProcess(hProc, 1); } catch { } }
  public static void Fechar(IntPtr h) { if (h != IntPtr.Zero) CloseHandle(h); }

  // Nível de integridade de um PID (RID: 4096 baixo, 8192 médio, 12288 alto). -1 se não deu para ler.
  public static int Nivel(int pid) {
    IntPtr h = OpenProcess(0x0400, false, pid);   // PROCESS_QUERY_INFORMATION
    if (h == IntPtr.Zero) { h = OpenProcess(0x1000, false, pid); if (h == IntPtr.Zero) return -1; }
    IntPtr tok;
    try { if (!OpenProcessToken(h, 0x0008, out tok)) return -1; } finally { }
    try {
      uint need = 0; GetTokenInformation(tok, 25, IntPtr.Zero, 0, out need);
      if (need == 0) return -1;
      IntPtr buf = Marshal.AllocHGlobal((int)need);
      try {
        if (!GetTokenInformation(tok, 25, buf, need, out need)) return -1;
        IntPtr sid = Marshal.ReadIntPtr(buf);   // TOKEN_MANDATORY_LABEL.Label.Sid
        int cont = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
        return (int)(uint)Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(cont - 1)));
      } finally { Marshal.FreeHGlobal(buf); }
    } finally { CloseHandle(tok); CloseHandle(h); }
  }
}
'@
}

# Monta a linha do cmd: cmd /s /c "<exe> <args...> < in > out 2> err".
# O /s com aspas externas na 1ª e última posição faz o cmd usar o miolo LITERALMENTE (sem a regra de remoção de aspas
# que, sem /s, embaralhava os argumentos e fazia o pwsh abrir em modo interativo — achado do diag 046).
function B05LowIL-Cmdline([string]$exe, [string[]]$argumentos, [string]$inFile, [string]$outFile, [string]$errFile) {
  $q = { param($s) '"' + ($s -replace '"', '""') + '"' }
  $partes = @((& $q $exe)) + @($argumentos | ForEach-Object { & $q $_ })
  $interno = ($partes -join ' ') + " < $(& $q $inFile) > $(& $q $outFile) 2> $(& $q $errFile)"
  return "`"$env:ComSpec`" /s /c `"$interno`""
}

# E84-05: pontos de reparse (junctions, symlinks) sob $raiz. O executor baixo pode criar uma junction na árvore de
# trabalho apontando para uma pasta média; se o controlador médio (git, teste) a atravessar, operaria com autoridade
# média no alvo. Qualquer reparse ⇒ falha fechada. B05-F10: QUALQUER falha de enumeração também ⇒ falha fechada
# (uma varredura incompleta NÃO é "sem junctions"). Devolve @{ Ok; Pontos }: Ok=$false se não deu para varrer tudo.
function B05LowIL-ReparsePoints([string]$raiz) {
  $pontos = [System.Collections.Generic.List[string]]::new(); $ok = $true
  $pilha = [System.Collections.Generic.Stack[string]]::new(); $pilha.Push($raiz)
  while ($pilha.Count) {
    $d = $pilha.Pop()
    try { $filhos = [System.IO.Directory]::GetFileSystemEntries($d) }
    catch { $ok = $false; continue }   # não conseguiu enumerar este diretório → varredura incompleta
    foreach ($f in $filhos) {
      try { $attr = [System.IO.File]::GetAttributes($f) } catch { $ok = $false; continue }
      if (($attr -band [IO.FileAttributes]::ReparsePoint) -eq [IO.FileAttributes]::ReparsePoint) { $pontos.Add($f) }   # não desce
      elseif (($attr -band [IO.FileAttributes]::Directory) -eq [IO.FileAttributes]::Directory) { $pilha.Push($f) }
    }
  }
  return @{ Ok = $ok; Pontos = $pontos.ToArray() }
}

# Bloco de ambiente UTF-16 terminado em NUL duplo, a partir de um hashtable (E84-03: ambiente higienizado).
function B05LowIL-BlocoAmbiente([hashtable]$vars) {
  $sb = [System.Text.StringBuilder]::new()
  foreach ($k in ($vars.Keys | Sort-Object)) { [void]$sb.Append("$k=$($vars[$k])`0") }
  [void]$sb.Append("`0")
  $bytes = [System.Text.Encoding]::Unicode.GetBytes($sb.ToString())
  $mem = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($bytes.Length)
  [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $mem, $bytes.Length)
  return $mem
}
