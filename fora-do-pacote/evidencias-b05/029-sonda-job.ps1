# 029 — sonda (Ato 075): herança de Job Object com pwsh EMPACOTADO (Store) × pwsh PORTÁTIL (zip oficial).
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$base = "$env:USERPROFILE\piloto"; $out = "$base\ponte\saida\029-relatorio.txt"
& {
  "=== INICIO $(Get-Date -Format s)"
  $dest = "$base\ferramentas\pwsh-7.6.7"; $zip = "$base\ferramentas\PowerShell-7.6.7-win-x64.zip"
  if (-not (Test-Path "$dest\pwsh.exe")) {
    Invoke-WebRequest -Uri 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.7/PowerShell-7.6.7-win-x64.zip' -OutFile $zip -UseBasicParsing
    $hz = (Get-FileHash $zip).Hash
    "SHA256 do zip: $hz | confere com a página oficial: $($hz -eq 'D2F952EBDBF24386CB8923553AA58E41A846DB35A6155EA04C58142A4B16DBB7')"
    if ($hz -ne 'D2F952EBDBF24386CB8923553AA58E41A846DB35A6155EA04C58142A4B16DBB7') { 'ABORTADO: hash'; return }
    Expand-Archive $zip -DestinationPath $dest -Force
  }
  $portatil = "$dest\pwsh.exe"; $loja = (Get-Process -Id $PID).Path
  "pwsh portátil: $portatil | versão: $(& $portatil -NoProfile -c '$PSVersionTable.PSVersion.ToString()')"
  $sonda = "$base\ferramentas\sonda-job.ps1"
  foreach ($caso in @(@('LOJA', $loja), @('PORTATIL', $portatil))) {
    $marca = "sonda-$($caso[0])"
    $psi = [System.Diagnostics.ProcessStartInfo]::new($caso[1]); foreach ($x in @('-NoProfile', '-File', $sonda, '-Filho', $caso[1], '-Marca', $marca)) { $psi.ArgumentList.Add($x) }
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
    $s = [System.Diagnostics.Process]::Start($psi); $leit = $s.StandardOutput.ReadToEndAsync()
    Start-Sleep 9
    $todos = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name
    $desc = @(); $fila = @($s.Id)
    while ($fila.Count) { $x0 = $fila[0]; $fila = @($fila | Select-Object -Skip 1); foreach ($c in @($todos | Where-Object ParentProcessId -eq $x0)) { $desc += $c; $fila += $c.ProcessId } }
    "--- $($caso[0]): hospedeiro $($s.Id) ($($caso[1])); descendentes: " + (($desc | ForEach-Object { "$($_.ProcessId) $($_.Name)" }) -join ' | ')
    $s.Kill(); Start-Sleep 5
    "    saída da sonda: " + (($leit.Result -split "`n" | Where-Object { $_.Trim() }) -join ' / ')
    $vivos = @($desc | Where-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
    "    após matar o hospedeiro, descendentes vivos: $($vivos.Count) $(($vivos | ForEach-Object { "$($_.ProcessId) $($_.Name)" }) -join ' | ')"
    foreach ($v in $vivos) { Stop-Process -Id $v.ProcessId -Force -ErrorAction SilentlyContinue }
  }
  "=== FIM $(Get-Date -Format s)"
} *>&1 | Out-File -FilePath $out -Encoding utf8
