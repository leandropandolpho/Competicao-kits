# controlador.ps1
param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$TarefasPath,
    [Parameter(Mandatory)][string]$EstadoDir,
    [Parameter(Mandatory)][string]$TestCmd,
    [Parameter(Mandatory)][string[]]$TestPaths,
    [int]$TimeoutSec = 900,
    [int]$MaxTentativas = 3,
    [double]$MaxCustoUsd = 10,
    [double]$MaxMinutos = 240,
    [string]$ClaudeCmd = 'claude'
)

$ErrorActionPreference = 'Stop'
$script:Relogio = [Diagnostics.Stopwatch]::StartNew()
$script:Utf8 = [Text.UTF8Encoding]::new($false)

function Agora {
    (Get-Date).ToUniversalTime().ToString('o')
}

function Dentro-De([string]$caminho, [string]$raiz) {
    $r = [IO.Path]::GetFullPath($raiz).TrimEnd(
        [char[]]@('/', '\')
    )
    $p = [IO.Path]::GetFullPath($caminho)
    $cmp = if ($IsWindows) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    return $p.Equals($r, $cmp) -or
        $p.StartsWith(
            $r + [IO.Path]::DirectorySeparatorChar, $cmp
        )
}

function Gravar-Atomico(
    [string]$caminho,
    [string]$conteudo
) {
    $temp = "$caminho.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText(
            $temp, $conteudo, $script:Utf8
        )
        if ([IO.File]::Exists($caminho)) {
            [IO.File]::Replace($temp, $caminho, $null)
        } else {
            [IO.File]::Move($temp, $caminho)
        }
    } finally {
        if ([IO.File]::Exists($temp)) {
            [IO.File]::Delete($temp)
        }
    }
}

function Salvar-Tarefas {
    Gravar-Atomico $script:TarefasPath (
        $script:Doc | ConvertTo-Json -Depth 40
    )
}

function Salvar-Estado {
    $script:Estado.atualizado_em = Agora
    Gravar-Atomico $script:EstadoPath (
        $script:Estado | ConvertTo-Json -Depth 40
    )
}

function Registrar(
    [string]$evento,
    [object]$detalhes = $null
) {
    $linha = [ordered]@{
        ts = Agora
        evento = $evento
        detalhes = $detalhes
    } | ConvertTo-Json -Compress -Depth 20

    [IO.File]::AppendAllText(
        $script:LogPath, "$linha`n", $script:Utf8
    )
}

function Notificar([string]$mensagem) {
    [IO.File]::AppendAllText(
        $script:NotificacoesPath,
        "$(Agora) $mensagem`n",
        $script:Utf8
    )
    Registrar 'notificacao' $mensagem
}

function Git([string[]]$argumentos) {
    $resposta = @(
        & git -C $script:RepoPath @argumentos 2>&1
    )
    if ($LASTEXITCODE -ne 0) {
        throw "git $($argumentos -join ' ') falhou: $($resposta -join '; ')"
    }
    return $resposta
}

function Reverter([string]$base) {
    if ($base -notmatch '^[0-9a-fA-F]{40,64}$') {
        throw 'Commit base invalido para rollback.'
    }

    Git @('reset', '--hard', $base) | Out-Null

    # Preserva configuracao local nao rastreada.
    Git @('clean', '-fd', '-e', '.claude/') |
        Out-Null

    Registrar 'rollback' @{
        commit_base = $base
    }
}

function Padroes-De-Teste {
    $p = foreach ($item in $TestPaths) {
        foreach ($parte in ($item -split ',')) {
            $limpo = $parte.Trim().Replace('\', '/')
            if ($limpo) { $limpo }
        }
    }
    return @($p)
}

function Foto-Dos-Testes {
    $foto = @{}
    $padroes = @(Padroes-De-Teste)

    foreach ($arquivo in (
        Get-ChildItem -LiteralPath $script:RepoPath `
            -Recurse -Force -File
    )) {
        $relativo = [IO.Path]::GetRelativePath(
            $script:RepoPath, $arquivo.FullName
        ).Replace('\', '/')

        if (
            $relativo -eq '.git' -or
            $relativo.StartsWith('.git/')
        ) {
            continue
        }

        $casou = $false
        foreach ($padrao in $padroes) {
            if ($relativo -like $padrao) {
                $casou = $true
                break
            }
        }

        if ($casou) {
            $foto[$relativo] = (
                Get-FileHash -LiteralPath $arquivo.FullName `
                    -Algorithm SHA256
            ).Hash
        }
    }
    return $foto
}

function Testes-Mudaram(
    [hashtable]$anterior,
    [hashtable]$atual
) {
    if ($anterior.Count -ne $atual.Count) {
        return $true
    }

    foreach ($chave in $anterior.Keys) {
        if (
            -not $atual.ContainsKey($chave) -or
            $anterior[$chave] -ne $atual[$chave]
        ) {
            return $true
        }
    }
    return $false
}

function Gatilhos(
    [string]$base,
    [hashtable]$hashesAntes
) {
    $razoes = [Collections.Generic.List[string]]::new()

    $hashesDepois = Foto-Dos-Testes
    if (Testes-Mudaram $hashesAntes $hashesDepois) {
        $razoes.Add(
            'Arquivo de teste criado, removido ou alterado'
        )
    }

    # Compara index e worktree com o commit base.
    # --no-renames permite identificar exclusoes.
    $diff = @(
        Git @(
            'diff', '--name-status',
            '--no-renames', $base, '--'
        )
    )

    $nomes = [Collections.Generic.List[string]]::new()

    foreach ($linha in $diff) {
        $partes = ([string]$linha) -split "`t", 2
        if ($partes.Count -lt 2) { continue }

        $nomes.Add($partes[1].Replace('\', '/'))

        if ($partes[0] -match '^D') {
            $razoes.Add(
                "Arquivo rastreado excluido: $($partes[1])"
            )
        }
    }

    foreach ($linha in @(
        Git @(
            'ls-files', '--others', '--exclude-standard'
        )
    )) {
        if ($linha) {
            $nomes.Add(
                ([string]$linha).Replace('\', '/')
            )
        }
    }

    foreach ($nome in $nomes) {
        if ($nome -match 'migration') {
            $razoes.Add("Migration: $nome")
        }

        $baseNome = ($nome -split '/')[-1]

        if ($baseNome -in @(
            'package.json',
            'package-lock.json',
            'requirements.txt',
            'pyproject.toml'
        )) {
            $razoes.Add(
                "Manifesto ou dependencia: $nome"
            )
        }
    }

    return @($razoes | Select-Object -Unique)
}

function Executar-Processo(
    [string]$programa,
    [string[]]$argumentos,
    [string]$entrada,
    [int]$limite,
    [switch]$ComandoWindows
) {
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $script:RepoPath
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    if ($ComandoWindows) {
        $psi.FileName = if ($env:ComSpec) {
            $env:ComSpec
        } else {
            'cmd.exe'
        }

        # Encaminha .cmd/.bat via cmd.exe.
        $argLinha = @(
            $argumentos | ForEach-Object {
                if ($_ -match '[\s"&|<>^%]') {
                    '"' + $_.Replace('"', '') + '"'
                } else {
                    $_
                }
            }
        ) -join ' '

        $psi.Arguments = '/D /S /C ""' +
            $programa.Replace('"', '') +
            '" ' + $argLinha + '"'
    } else {
        $psi.FileName = $programa
        foreach ($a in $argumentos) {
            $psi.ArgumentList.Add($a)
        }
    }

    $p = [Diagnostics.Process]::new()
    $p.StartInfo = $psi

    try {
        if (-not $p.Start()) {
            throw 'Nao foi possivel iniciar o processo externo.'
        }

        # Leitura assincrona evita deadlock dos pipes.
        $saida = $p.StandardOutput.ReadToEndAsync()
        $erro = $p.StandardError.ReadToEndAsync()

        if ($entrada) {
            $p.StandardInput.Write($entrada)
        }
        $p.StandardInput.Close()

        $terminou = $p.WaitForExit(
            [math]::Max(1, $limite) * 1000
        )

        if (-not $terminou) {
            # Kill(true) encerra tambem os descendentes.
            $p.Kill($true)
            $p.WaitForExit(10000) | Out-Null
        }

        $saida.Wait(5000) | Out-Null
        $erro.Wait(5000) | Out-Null

        return [pscustomobject]@{
            timeout = -not $terminou
            exit_code = $(if ($terminou) {
                $p.ExitCode
            } else {
                -1
            })
            stdout = $(if ($saida.IsCompletedSuccessfully) {
                $saida.Result
            } else {
                ''
            })
            stderr = $(if ($erro.IsCompletedSuccessfully) {
                $erro.Result
            } else {
                ''
            })
        }
    } finally {
        try {
            if (-not $p.HasExited) {
                $p.Kill($true)
            }
        } catch {}
        $p.Dispose()
    }
}

function Invocar-Executor([string]$prompt) {
    $argsExec = @(
        '-p',
        '--output-format', 'json',
        '--permission-mode', 'dontAsk'
    )

    $config = Join-Path `
        $script:RepoPath '.claude/settings.json'

    # --settings resolve o problema de allow
    # em pasta ainda nao confiada.
    if (Test-Path -LiteralPath $config) {
        $argsExec += @('--settings', $config)
    }

    # stdin preserva prompts de varias linhas.
    $eCmd = $ClaudeCmd -match '\.(cmd|bat)$'

    return Executar-Processo `
        $ClaudeCmd $argsExec $prompt $TimeoutSec `
        -ComandoWindows:$eCmd
}

function Rodar-Teste {
    # Teste executado pelo controlador, nao pelo agente.
    return Executar-Processo `
        'pwsh' `
        @('-NoProfile', '-Command', $TestCmd) `
        '' `
        ([math]::Max(30, $TimeoutSec))
}

function Teto-Atingido {
    return (
        $script:Estado.custo_acumulado_usd -gt $MaxCustoUsd
    ) -or (
        $script:Relogio.Elapsed.TotalMinutes -gt $MaxMinutos
    )
}

function Encerrar(
    [int]$codigo,
    [string]$status
) {
    $script:Estado.status_execucao = $status
    $script:Estado.tarefa_atual = $null
    Salvar-Estado
    Registrar 'fim' @{
        codigo = $codigo
        status = $status
    }
    return $codigo
}

try {
    $script:RepoPath = (
        Resolve-Path -LiteralPath $RepoPath
    ).ProviderPath

    $script:TarefasPath = (
        Resolve-Path -LiteralPath $TarefasPath
    ).ProviderPath

    $EstadoDir = [IO.Path]::GetFullPath($EstadoDir)

    if (
        (Dentro-De $script:TarefasPath $script:RepoPath) -or
        (Dentro-De $EstadoDir $script:RepoPath)
    ) {
        throw 'TarefasPath e EstadoDir devem ficar fora do repositorio.'
    }

    $gitRoot = (
        (
            Git @('rev-parse', '--show-toplevel')
        ) | Select-Object -First 1
    ).Trim()

    if (
        -not (Dentro-De $script:RepoPath $gitRoot) -or
        -not (Dentro-De $gitRoot $script:RepoPath)
    ) {
        throw 'RepoPath deve ser a raiz do repositorio Git.'
    }

    New-Item -ItemType Directory -Force `
        -Path $EstadoDir | Out-Null

    $script:EstadoPath = Join-Path `
        $EstadoDir 'estado.json'

    $script:LogPath = Join-Path `
        $EstadoDir 'log.jsonl'

    $script:NotificacoesPath = Join-Path `
        $EstadoDir 'notificacoes.txt'

    $script:Doc = Get-Content `
        -LiteralPath $script:TarefasPath -Raw |
        ConvertFrom-Json -Depth 40

    if ($null -eq $script:Doc.tarefas) {
        throw 'TAREFAS.json nao contem tarefas.'
    }

    if (Test-Path -LiteralPath $script:EstadoPath) {
        $script:Estado = Get-Content `
            -LiteralPath $script:EstadoPath -Raw |
            ConvertFrom-Json -Depth 40
    } else {
        $script:Estado = [pscustomobject]@{
            tarefa_atual = $null
            tentativa = 0
            commit_base = (
                Git @('rev-parse', 'HEAD') |
                Select-Object -First 1
            )
            custo_acumulado_usd = 0.0
            inicio = Agora
            atualizado_em = Agora
            status_execucao = 'rodando'
            hashes_testes = @{}
        }
    }

    $script:Estado.inicio = Agora
    $script:Estado.status_execucao = 'rodando'
    Salvar-Estado

    Registrar 'inicio' @{
        tarefas = @($script:Doc.tarefas).Count
        custo_herdado = $script:Estado.custo_acumulado_usd
    }

    # Retomada: desfaz somente a tarefa interrompida.
    # Tentativas e custo permanecem persistidos.
    foreach ($t in @($script:Doc.tarefas)) {
        if ($t.status -eq 'in_progress') {
            if ($script:Estado.tarefa_atual -ne $t.id) {
                throw "Estado inconsistente na retomada: $($t.id)"
            }

            Reverter ([string]$script:Estado.commit_base)

            $t.status = 'pending'
            Salvar-Tarefas

            Registrar 'retomada' @{
                tarefa = $t.id
                tentativas_preservadas = $t.tentativas
            }
        }
    }

    $script:Estado.tarefa_atual = $null
    Salvar-Estado

    while ($true) {
        if (Teto-Atingido) {
            Notificar (
                'Pausa: teto de custo ou tempo atingido; ' +
                'nenhuma nova chamada sera iniciada.'
            )
            exit (Encerrar 3 'pausado')
        }

        # Seleciona primeira tarefa elegivel.
        $proxima = $null

        foreach ($t in @($script:Doc.tarefas)) {
            if ($t.status -ne 'pending') {
                continue
            }

            $pronta = $true

            foreach ($d in @($t.depends_on)) {
                $dep = @(
                    $script:Doc.tarefas |
                    Where-Object { $_.id -eq $d }
                )

                if (
                    $dep.Count -ne 1 -or
                    $dep[0].status -ne 'done'
                ) {
                    $pronta = $false
                    break
                }
            }

            if ($pronta) {
                $proxima = $t
                break
            }
        }

        if ($null -eq $proxima) {
            if (
                @(
                    $script:Doc.tarefas |
                    Where-Object { $_.status -eq 'failed' }
                ).Count -gt 0
            ) {
                exit (Encerrar 1 'falhou')
            }

            if (
                @(
                    $script:Doc.tarefas |
                    Where-Object { $_.status -ne 'done' }
                ).Count -gt 0
            ) {
                Registrar 'dependencia_bloqueada' (
                    'Nenhuma tarefa pendente esta pronta.'
                )
                exit (Encerrar 1 'falhou')
            }

            exit (Encerrar 0 'concluido')
        }

        # Baseline duravel antes de iniciar a tentativa.
        $base = [string](
            Git @('rev-parse', 'HEAD') |
            Select-Object -First 1
        )

        $hashes = Foto-Dos-Testes

        $script:Estado.tarefa_atual = $proxima.id
        $script:Estado.tentativa = `
            [int]$proxima.tentativas + 1
        $script:Estado.commit_base = $base
        $script:Estado.hashes_testes = $hashes

        Salvar-Estado

        # Contagem registrada ANTES de chamar o executor.
        $proxima.tentativas = `
            [int]$proxima.tentativas + 1
        $proxima.status = 'in_progress'
        Salvar-Tarefas

        Registrar 'chamada' @{
            tarefa = $proxima.id
            tentativa = $proxima.tentativas
            commit_base = $base
        }

        $prompt = @"
Execute somente a tarefa indicada abaixo dentro do repositorio atual.
Nao altere arquivos de testes, migrations ou manifests; nao apague arquivos rastreados.
Nao execute git commit ou git push. O controlador executara os testes e fara o commit.

$($proxima.prompt)
"@

        $retorno = $null

        try {
            $retorno = Invocar-Executor $prompt
        } catch {
            $retorno = [pscustomobject]@{
                timeout = $false
                exit_code = -1
                stdout = ''
                stderr = $_.Exception.Message
            }
        }

        $json = $null

        if ($retorno.stdout.Trim()) {
            try {
                $json = $retorno.stdout |
                    ConvertFrom-Json -Depth 40
            } catch {
                $json = $null
            }
        }

        # Custo e acumulado mesmo quando a tarefa falha.
        if (
            $null -ne $json -and
            $null -ne $json.total_cost_usd
        ) {
            $valor = [double]$json.total_cost_usd

            if (
                -not [double]::IsNaN($valor) -and
                -not [double]::IsInfinity($valor) -and
                $valor -ge 0
            ) {
                $script:Estado.custo_acumulado_usd = `
                    [double]$script:Estado.custo_acumulado_usd +
                    $valor
            }
        }

        Salvar-Estado

        Registrar 'executor_terminou' @{
            tarefa = $proxima.id
            exit = $retorno.exit_code
            timeout = $retorno.timeout
            custo = $script:Estado.custo_acumulado_usd
            json_valido = ($null -ne $json)
        }

        $falhaExecutor = (
            $retorno.timeout -or
            $retorno.exit_code -ne 0 -or
            $null -eq $json -or
            $json.is_error -eq $true
        )

        $passou = $false

        if (-not $falhaExecutor) {
            $resultadoTeste = Rodar-Teste
            $passou = (
                -not $resultadoTeste.timeout
            ) -and (
                $resultadoTeste.exit_code -eq 0
            )

            Registrar 'teste' @{
                tarefa = $proxima.id
                passou = $passou
                exit = $resultadoTeste.exit_code
            }
        }

        # R1 tem prioridade sobre o resultado do executor
        # e sobre o resultado dos testes.
        $criticos = @(Gatilhos $base $hashes)

        if ($criticos.Count -gt 0) {
            $proxima.status = 'hold'
            Salvar-Tarefas

            Notificar (
                "HOLD na tarefa $($proxima.id): " +
                "$($criticos -join '; '). " +
                'Evidencia preservada.'
            )

            exit (Encerrar 2 'hold')
        }

        if (-not $falhaExecutor -and $passou) {
            # Somente Git escreve/commita no repositorio.
            # Configuracao local nao rastreada fica excluida.
            Git @(
                'add', '-A', '--', '.',
                ':(exclude).claude/settings.local.json'
            ) | Out-Null

            Git @(
                'commit', '--allow-empty', '-m',
                "tarefa $($proxima.id): $($proxima.titulo)"
            ) | Out-Null

            $proxima.status = 'done'

            Registrar 'commit' @{
                tarefa = $proxima.id
                commit = (
                    Git @('rev-parse', 'HEAD') |
                    Select-Object -First 1
                )
            }
        } else {
            Reverter $base

            $proxima.status = if (
                $proxima.tentativas -ge $MaxTentativas
            ) {
                'failed'
            } else {
                'pending'
            }

            Registrar 'tentativa_falhou' @{
                tarefa = $proxima.id
                tentativa = $proxima.tentativas
                executor_falhou = $falhaExecutor
            }
        }

        Salvar-Tarefas
        $script:Estado.tarefa_atual = $null
        Salvar-Estado

        # Limites sao avaliados apos o fluxo normal
        # da tentativa, antes de iniciar outra chamada.
        if (Teto-Atingido) {
            Notificar (
                "Pausa por limite apos processar a tarefa $($proxima.id)."
            )
            exit (Encerrar 3 'pausado')
        }
    }
} catch {
    if ($script:LogPath) {
        try {
            Registrar 'erro_controlador' $_.Exception.Message
        } catch {}
    }

    if ($script:Estado) {
        try {
            $script:Estado.status_execucao = 'falhou'
            Salvar-Estado
        } catch {}
    }

    Write-Error $_
    exit 1
}
