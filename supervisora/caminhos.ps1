# caminhos.ps1 — verificações FÍSICAS de caminho (F5-01-R e F5-04-R, Ato 065).
# GetFullPath só normaliza o texto; links simbólicos e junctions do Windows redirecionam no disco.
# Regra: qualquer ponto de redirecionamento no caminho (em qualquer nível existente) → recusar.

function Eh-Redirecionamento($item) {
  return [bool]($item.LinkType) -or [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Primeiro-Redirecionamento([string]$caminho) {
  # Sobe do caminho até a raiz do volume; devolve o primeiro componente existente que seja link/junction.
  $atual = [IO.Path]::GetFullPath($caminho)
  $raiz = [IO.Path]::GetPathRoot($atual)
  if ($atual.Length -gt $raiz.Length) { $atual = $atual.TrimEnd('\', '/') }
  while ($atual -and $atual.Length -gt $raiz.Length) {
    if (Test-Path -LiteralPath $atual) {
      $i = Get-Item -LiteralPath $atual -Force -ErrorAction SilentlyContinue
      if ($i -and (Eh-Redirecionamento $i)) { return $atual }
    }
    $atual = [IO.Path]::GetDirectoryName($atual)
  }
  return $null
}

function Redirecionamentos-Dentro([string]$dir) {
  # Entradas já existentes dentro da pasta que sejam links/junctions (não segue os links).
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return @() }
  return @(Get-ChildItem -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { Eh-Redirecionamento $_ } | ForEach-Object { $_.FullName })
}

function Validar-Saida([string]$saida, [string]$repoRaiz) {
  # Devolve '' se a pasta de saída é segura; senão, o motivo. Chamar ANTES e DEPOIS de criar a pasta.
  $f = [IO.Path]::GetFullPath($saida).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  if ($f.StartsWith($repoRaiz, [StringComparison]::OrdinalIgnoreCase)) { return "SaidaDir dentro do repositório: $saida" }
  $r = Primeiro-Redirecionamento $saida
  if ($r) { return "SaidaDir passa por link/junction: $r" }
  $d = @(Redirecionamentos-Dentro $saida)
  if ($d.Count) { return "SaidaDir contém link/junction: $($d[0])" }
  return ''
}
