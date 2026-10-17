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
$startTime = Get-Date
$script:totalCost = 0.0
$script:status = 'rodando'

$testPathList = @()
foreach ($p in $TestPaths) {
    if ($p -match ',') {
        $testPathList += $p -split ',' | ForEach-Object { $_.Trim() }
    } else {
        $testPathList += $p.Trim()
    }
}
$testPathList = $testPathList | Where-Object { $_ -ne '' }

function Log-Event {
    param([string]$Evento, [hashtable]$Dados = @{})
    $entry = @{ ts = (Get-Date).ToString('o'); evento = $Evento } + $Dados
    $entry | ConvertTo-Json -Compress | Add-Content -Path (Join-Path $EstadoDir 'log.jsonl')
}

function Notificar {
    param([string]$Mensagem)
    $Mensagem | Add-Content -Path (Join-Path $EstadoDir 'notificacoes.txt')
    Log-Event -Evento 'notificacao' -Dados @{ mensagem = $Mensagem }
}

function Save-Estado {
    param([hashtable]$Estado)
    $Estado.atualizado_em = (Get-Date).ToString('o')
    $Estado | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $EstadoDir 'estado.json')
}

function Get-TestFileHashes {
    $hashes = @{}
    $allFiles = @(git -C $RepoPath ls-files) + @(git -C $RepoPath ls-files --others --exclude-standard)
    foreach ($pattern in $testPathList) {
        foreach ($file in $allFiles) {
            $normalized = $file -replace '\\', '/'
            if ($normalized -like $pattern) {
                $fullPath = Join-Path $RepoPath $file
                if (Test-Path $fullPath) {
                    $hashes[$normalized] = (Get-FileHash -Path $fullPath -Algorithm SHA256).Hash
                }
            }
        }
    }
    return $hashes
}

function Get-RepoSnapshot {
    $snapshot = @{
        testHashes   = Get-TestFileHashes
        trackedFiles = @(git -C $RepoPath ls-files)
        keyFiles     = @{}
    }
    foreach ($f in @('package.json', 'package-lock.json', 'requirements.txt', 'pyproject.toml')) {
        $full = Join-Path $RepoPath $f
        if (Test-Path $full) { $snapshot.keyFiles[$f] = (Get-FileHash -Path $full -Algorithm SHA256).Hash }
    }
    return $snapshot
}

function Test-Triggers {
    param($Snapshot, $CommitBase)
    $current = Get-RepoSnapshot
    foreach ($f in $Snapshot.testHashes.Keys) {
        if (-not $current.testHashes.ContainsKey($f) -or $current.testHashes[$f] -ne $Snapshot.testHashes[$f]) { return $true }
    }
    foreach ($f in $current.testHashes.Keys) {
        if (-not $Snapshot.testHashes.ContainsKey($f)) { return $true }
    }
    foreach ($f in $Snapshot.keyFiles.Keys) {
        if (-not $current.keyFiles.ContainsKey($f) -or $current.keyFiles[$f] -ne $Snapshot.keyFiles[$f]) { return $true }
    }
    $status = git -C $RepoPath status --porcelain
    foreach ($line in $status) {
        $path = $line.Substring(3).Trim()
        if ($path -match 'migration') { return $true }
    }
    $baseFiles = git -C $RepoPath ls-tree -r --name-only $CommitBase
    $currentFiles = git -C $RepoPath ls-files
    foreach ($f in $baseFiles) { if ($f -notin $currentFiles) { return $true } }
    return $false
}

function Invoke-Executor {
    param([string]$Prompt, [string]$WorkDir, [string]$SettingsPath)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ClaudeCmd
    $psi.Arguments = "-p `"`" --output-format json --permission-mode dontAsk --settings `"$SettingsPath`""
    $psi.WorkingDirectory = $WorkDir
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()
    $proc.StandardInput.Write($Prompt)
    $proc.StandardInput.Close()
    $finished = $proc.WaitForExit($TimeoutSec * 1000)
    if (-not $finished) {
        try { taskkill /T /F /PID $proc.Id 2>$null } catch {}
        $proc.Kill()
        return @{ timeout = $true; exitCode = -1; stdout = ''; stderr = '' }
    }
    return @{
        timeout  = $false
        exitCode = $proc.ExitCode
        stdout   = $proc.StandardOutput.ReadToEnd()
        stderr   = $proc.StandardError.ReadToEnd()
    }
}

function Run-Test {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'pwsh'
    $psi.Arguments = "-NoProfile -Command `"$TestCmd`""
    $psi.WorkingDirectory = $RepoPath
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()
    $proc.WaitForExit()
    return $proc.ExitCode
}

function Reset-Repo {
    param([string]$CommitBase)
    git -C $RepoPath reset --hard $CommitBase | Out-Null
    git -C $RepoPath clean -fd | Out-Null
}

function Commit-Task {
    param([string]$TaskId, [string]$Titulo)
    git -C $RepoPath add -A
    git -C $RepoPath commit -m "tarefa $TaskId`: $Titulo" | Out-Null
}

$tarefasData = Get-Content -Path $TarefasPath -Raw | ConvertFrom-Json
$tarefas = $tarefasData.tarefas

$estadoPath = Join-Path $EstadoDir 'estado.json'
$estado = @{
    tarefa_atual       = $null
    tentativa          = 0
    commit_base        = ''
    custo_acumulado_usd = 0.0
    inicio             = $startTime.ToString('o')
    atualizado_em      = $startTime.ToString('o')
    status_execucao    = 'rodando'
}
if (Test-Path $estadoPath) {
    $existing = Get-Content -Path $estadoPath -Raw | ConvertFrom-Json
    $estado.custo_acumulado_usd = [double]$existing.custo_acumulado_usd
    if ($existing.status_execucao -eq 'hold') { Log-Event -Evento 'retomada_hold' }
}
Save-Estado -Estado $estado

$settingsPath = Join-Path $RepoPath '.claude/settings.json'

while ($true) {
    $elapsedMin = ((Get-Date) - $startTime).TotalMinutes
    if ($elapsedMin -gt $MaxMinutos) {
        $estado.status_execucao = 'pausado'
        Save-Estado -Estado $estado
        Notificar "Pausado por tempo: $([math]::Round($elapsedMin,2)) min > $MaxMinutos"
        exit 3
    }
    if ($script:totalCost -gt $MaxCustoUsd) {
        $estado.status_execucao = 'pausado'
        Save-Estado -Estado $estado
        Notificar "Pausado por custo: $script:totalCost > $MaxCustoUsd"
        exit 3
    }

    $nextTask = $null
    foreach ($t in $tarefas) {
        if ($t.status -ne 'pending') { continue }
        $depsOk = $true
        foreach ($dep in $t.depends_on) {
            $depTask = $tarefas | Where-Object { $_.id -eq $dep }
            if (-not $depTask -or $depTask.status -ne 'done') { $depsOk = $false; break }
        }
        if ($depsOk) { $nextTask = $t; break }
    }
    if (-not $nextTask) { break }

    $taskId = $nextTask.id
    $estado.tarefa_atual = $taskId
    $commitBase = git -C $RepoPath rev-parse HEAD
    $estado.commit_base = $commitBase
    $snapshot = Get-RepoSnapshot
    Save-Estado -Estado $estado
    Log-Event -Evento 'tarefa_inicio' -Dados @{ id = $taskId; commit_base = $commitBase }

    $nextTask.status = 'in_progress'
    $nextTask.tentativas = [int]$nextTask.tentativas + 1
    $estado.tentativa = $nextTask.tentativas
    $tarefasData | ConvertTo-Json -Depth 5 | Set-Content -Path $TarefasPath
    Save-Estado -Estado $estado

    $attempt = 0
    $success = $false
    while ($attempt -lt $MaxTentativas) {
        $attempt++
        $result = Invoke-Executor -Prompt $nextTask.prompt -WorkDir $RepoPath -SettingsPath $settingsPath

        if ($result.timeout) {
            Log-Event -Evento 'executor_timeout' -Dados @{ id = $taskId; tentativa = $attempt }
            Reset-Repo -CommitBase $commitBase
            continue
        }
        if ($result.exitCode -ne 0) {
            Log-Event -Evento 'executor_falha' -Dados @{ id = $taskId; tentativa = $attempt; exitCode = $result.exitCode }
            Reset-Repo -CommitBase $commitBase
            continue
        }
        try { $json = $result.stdout | ConvertFrom-Json } catch {
            Log-Event -Evento 'executor_json_invalido' -Dados @{ id = $taskId; tentativa = $attempt }
            Reset-Repo -CommitBase $commitBase
            continue
        }
        if ($json.is_error) {
            Log-Event -Evento 'executor_is_error' -Dados @{ id = $taskId; tentativa = $attempt }
            Reset-Repo -CommitBase $commitBase
            continue
        }
        if ($json.total_cost_usd) {
            $script:totalCost += [double]$json.total_cost_usd
            $estado.custo_acumulado_usd = $script:totalCost
            Save-Estado -Estado $estado
        }
        if (Test-Triggers -Snapshot $snapshot -CommitBase $commitBase) {
            $estado.status_execucao = 'hold'
            $nextTask.status = 'hold'
            $tarefasData | ConvertTo-Json -Depth 5 | Set-Content -Path $TarefasPath
            Save-Estado -Estado $estado
            Notificar "Hold na tarefa $taskId`: gatilho crítico detectado."
            Log-Event -Evento 'hold' -Dados @{ id = $taskId }
            exit 2
        }
        $testExit = Run-Test
        if ($testExit -eq 0) {
            Commit-Task -TaskId $taskId -Titulo $nextTask.titulo
            $nextTask.status = 'done'
            $tarefasData | ConvertTo-Json -Depth 5 | Set-Content -Path $TarefasPath
            Log-Event -Evento 'tarefa_done' -Dados @{ id = $taskId }
            $success = $true
            break
        } else {
            Log-Event -Evento 'teste_falhou' -Dados @{ id = $taskId; tentativa = $attempt; exitCode = $testExit }
            Reset-Repo -CommitBase $commitBase
        }
        if ($attempt -ge $MaxTentativas) { break }
    }

    if (-not $success) {
        $nextTask.status = 'failed'
        $tarefasData | ConvertTo-Json -Depth 5 | Set-Content -Path $TarefasPath
        Log-Event -Evento 'tarefa_failed' -Dados @{ id = $taskId }
        $estado.status_execucao = 'falhou'
    }

    $estado.tarefa_atual = $null
    $estado.tentativa = 0
    Save-Estado -Estado $estado
}

$allDone = ($tarefas | Where-Object { $_.status -ne 'done' }).Count -eq 0
$anyFailed = ($tarefas | Where-Object { $_.status -eq 'failed' }).Count -gt 0
if ($allDone) {
    $estado.status_execucao = 'concluido'
    Save-Estado -Estado $estado
    exit 0
} elseif ($anyFailed) {
    $estado.status_execucao = 'falhou'
    Save-Estado -Estado $estado
    exit 1
} else {
    exit 0
}
