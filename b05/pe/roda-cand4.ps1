# roda-cand4.ps1 - executor da bateria CANDIDATA 4 (Ato 150). gate-pe-083 no notebook.
# Autocontido: (1) confere o SHA-256 de cada artefato entregue contra o esperado (integridade da entrega, licao do
# cache do device_commit_files); (2) roda as 5 baterias reais, cada uma em processo pwsh proprio; (3) grava um unico
# arquivo de resultado com TOTais, EXITCODEs e o manifesto de SHA. NAO roda roteiro v3/v3.1 (BLOQUEADO).
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$base = $PSScriptRoot
$pe = Join-Path $base 'b05\pe'; $tst = Join-Path $pe 'testes'; $nuc = Join-Path $base 'b05'
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$out = Join-Path $base "cand4-resultado-$stamp.txt"
$pwsh = (Get-Process -Id $PID).Path
$L = New-Object System.Collections.Generic.List[string]
function Linha($s){ $L.Add($s); Write-Host $s }

# SHA-256 esperado (workspace, pre-entrega). Confere integridade da entrega antes de rodar.
$esperado = [ordered]@{
  "$pe\lancador-ponte.ps1"        = 'BDD708BBD79488D086D05AE2D19032F75580D8456DCF4B5185DB1DBCF2EE6455'
  "$pe\lancador-ponte.cmd"        = 'D4817DFD5397E4BBE36E06F2A6C1AF52BDD61BB44A74D895B3AD6ECE40831D7A'
  "$pe\claude-ponte.ps1"          = '7AE5A32061E6A0D871298186DBC1DF3B3135DF6432E5E696BF69C8117157C170'
  "$pe\despachante-teste.ps1"     = '48A1263145F7BE3F2DFE24090B1452A4707133A33D33EF4ADF8980E996FD24C5'
  "$tst\testar-controlador-real-ponte.ps1" = '6692DE8B7DDF699E123A73D053D46FB320EC9198D87FC863344F4BACACD3ECE8'
  "$tst\testar-lancador-ponte.ps1"          = '744DF45A8082CB629662F8E21B3AA09441B7A2D641E9B5FFFA4CB07524BE482E'
  "$tst\testar-pe.ps1"                      = '49D9E2B7383185AA06895C6532B8A4D7BE1DEFA3F8F5B30AE3981FBCDE85AB62'
  "$tst\testar-ponte-pu.ps1"                = '07CCB11FCEF9A19E03DEFB15A4B16C1F64AEC9B3139B7BD75459094E7D8D6EBA'
  "$tst\testar-integra-ponte.ps1"           = '480ED33377171A40B7D9D587C63982B1006C5B524E383F7CE5FFDDE6F7E814E7'
  "$pe\ponte-pu.ps1"              = 'FC262DC947F4DDC3D55C2FE569F5AAF421F55C24C27BDBD0EFFBA2D8EF41B6A4'
  "$pe\acao-pe.ps1"              = '5159B36084B82782AA9BF0E141A99FC7D10BB82628E4D3852628675FB9031A62'
  "$nuc\b05job.ps1"              = 'C84D41969DE097F9EA04D9C11C6E126651E22C89CFD2A735439EB6CCA525D0FA'
  "$nuc\baixa-integridade.ps1"   = '8115F3ACF8386DA166147F33C460F935ECCD3A393F52E0B5AE1B5C88A43FFB27'
  "$nuc\razao.ps1"               = '9F302EF681A03A045315925120BD1A216EB3434F900DE5772F15CA5E0FB5DF56'
}
Linha "=== CANDIDATA 4 - gate-pe - $stamp UTC ==="
Linha "pwsh: $pwsh ($($PSVersionTable.PSVersion))"
Linha "--- MANIFESTO SHA-256 (entrega) ---"
$integro = $true
foreach ($p in $esperado.Keys) {
  if (-not (Test-Path -LiteralPath $p)) { Linha ("AUSENTE      " + $p); $integro = $false; continue }
  $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpper()
  $okh = ($h -eq $esperado[$p].ToUpper())
  if (-not $okh) { $integro = $false }
  Linha ("{0}  {1}  {2}" -f ($(if($okh){'OK '}else{'XX '}), $h, (Split-Path $p -Leaf)))
}
if (-not $integro) {
  Linha "FATAL: integridade da entrega FALHOU - baterias NAO executadas."
  [IO.File]::WriteAllText($out, ($L -join "`r`n"), [Text.UTF8Encoding]::new($false))
  Write-Host "RESULTADO: $out"; exit 2
}
Linha ("--- integridade da entrega: OK ({0}/{0}) ---" -f $esperado.Count)

$baterias = [ordered]@{
  'PE'              = (Join-Path $tst 'testar-pe.ps1')
  'PU'              = (Join-Path $tst 'testar-ponte-pu.ps1')
  'INTEGRA'         = (Join-Path $tst 'testar-integra-ponte.ps1')
  'CONTROLADOR-REAL'= (Join-Path $tst 'testar-controlador-real-ponte.ps1')
  'LANCADOR'        = (Join-Path $tst 'testar-lancador-ponte.ps1')
}
$falhou = $false
foreach ($nome in $baterias.Keys) {
  $arq = $baterias[$nome]
  Linha ""
  Linha "===== BATERIA $nome ====="
  $log = Join-Path $base "cand4-$nome-$stamp.log"
  $psi = [System.Diagnostics.ProcessStartInfo]::new($pwsh)
  foreach ($a in @('-NoProfile','-ExecutionPolicy','Bypass','-File',$arq)) { $psi.ArgumentList.Add($a) }
  $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
  $psi.WorkingDirectory = (Split-Path $arq)
  $p=[System.Diagnostics.Process]::Start($psi)
  $o=$p.StandardOutput.ReadToEndAsync(); $e=$p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  $saida = $o.Result; $erro = $e.Result
  [IO.File]::WriteAllText($log, $saida + "`r`n--STDERR--`r`n" + $erro, [Text.UTF8Encoding]::new($false))
  $total = ($saida -split "`r?`n" | Where-Object { $_ -match 'TOTAL' } | Select-Object -Last 1)
  $falhas = ($saida -split "`r?`n" | Where-Object { $_ -match '\[FALHA\]' })
  Linha ("EXITCODE: {0}" -f $p.ExitCode)
  Linha ("TOTAL   : {0}" -f ($total ?? '(sem linha TOTAL)'))
  if ($p.ExitCode -ne 0) { $falhou = $true; Linha "  -> BATERIA NAO VERDE" }
  if ($falhas) { foreach ($f in $falhas) { Linha ("  $f") } }
}
Linha ""
Linha ("=== VEREDITO CANDIDATA 4: {0} ===" -f ($(if($falhou){'HA FALHAS'}else{'TODAS VERDES'})))
[IO.File]::WriteAllText($out, ($L -join "`r`n"), [Text.UTF8Encoding]::new($false))
Write-Host "RESULTADO: $out"
exit ([int]$falhou)
