# ESPECIFICAÇÃO — Kit do Piloto (Rodada 4)

> **STATUS: RASCUNHO NÃO CONGELADO — v0.1 — 15/10/2026**
> Não vale como especificação. Não pode ser distribuído aos competidores nem usado para iniciar kits.
> Só passa a valer depois de: (1) auditoria de Grok e Perplexity, (2) congelamento com SHA-256 publicado por Leandro, (3) liberação simultânea aos 4 participantes.
> Redigido por: Claude · Anthropic · Claude Opus 5.5 (claude-opus-5-5) — participante da competição.

## 1. Contexto

- Windows nativo, PowerShell 7 (`pwsh`), repositório descartável, conta sem administrador.
- Executor: Claude Code em modo headless (`claude -p`).
- Regras acatadas pela mesa: R1–R6 e R7 corrigido (R7 não se aplica ao piloto).

## 2. Entrega: exatamente 4 arquivos

| Arquivo | Conteúdo |
|---|---|
| `controlador.ps1` | O controlador determinístico (seção 3) |
| `TAREFAS.json` | Modelo com 3 tarefas de exemplo (seção 4) |
| `.claude/settings.json` | Permissões do executor (seção 5) |
| `CONTEXTO.md` | Modelo do contexto persistente da supervisora (seção 6) |

Cada arquivo em bloco de código, com o nome do arquivo na primeira linha. No máximo 5 linhas de notas no final. O kit entregue recebe SHA-256 calculado por Leandro.

## 3. `controlador.ps1` — interface FIXA

A interface abaixo é obrigatória. É o que permite aos testes objetivos rodarem igualmente para todos os kits.

### 3.1 Parâmetros

```powershell
param(
  [Parameter(Mandatory)][string]$RepoPath,     # pasta do repositório git onde o executor trabalha
  [Parameter(Mandatory)][string]$TarefasPath,  # caminho do TAREFAS.json (FORA do repositório)
  [Parameter(Mandatory)][string]$EstadoDir,    # pasta de estado/log/notificações (FORA do repositório)
  [Parameter(Mandatory)][string]$TestCmd,      # comando de teste; exit code 0 = passou
  [Parameter(Mandatory)][string[]]$TestPaths,  # caminhos/globs relativos ao repo dos arquivos de teste
  [int]$TimeoutSec    = 900,                   # tempo máximo por chamada ao executor
  [int]$MaxTentativas = 3,                     # tentativas por tarefa
  [double]$MaxCustoUsd = 10,                   # teto de custo acumulado da execução
  [int]$MaxMinutos    = 240,                   # teto de tempo total da execução
  [string]$ClaudeCmd  = 'claude'               # executável do executor (o teste troca por um simulado)
)
```

Por que `TarefasPath` e `EstadoDir` ficam fora do repositório: dentro dele, o `git reset --hard` e o `git clean -fd` do rollback apagariam ou reverteriam o próprio estado do controlador.

### 3.2 Como chamar o executor

- Iniciar `$ClaudeCmd` como **processo externo** (deve funcionar com `.exe` e com `.cmd`), com diretório de trabalho = `$RepoPath`.
- Argumentos obrigatórios: `-p "<prompt>"`, `--output-format json`, `--permission-mode dontAsk`.
- Proibido: `--dangerously-skip-permissions` e `--permission-mode bypassPermissions`.
- Ler o JSON da saída padrão. Campos usados: `is_error`, `result`, `total_cost_usd`.

### 3.3 Ciclo de cada tarefa

1. Escolher a próxima tarefa `pending` cujas dependências (`depends_on`) estejam todas `done`.
2. Registrar o commit base (`git rev-parse HEAD`) e o SHA-256 dos arquivos de `$TestPaths`.
3. Chamar o executor. Timeout = encerramento REAL do processo **e de todos os filhos**; conta como tentativa falhada.
4. O **próprio controlador** roda `$TestCmd` no repositório. Não confiar no relato do executor.
5. Gatilhos críticos (R1), verificados por `git diff`/`git status` contra o commit base:
   - qualquer arquivo de teste alterado, criado ou removido (hash diferente);
   - migrations (caminho contendo `migration`);
   - `package.json`, `package-lock.json`, `requirements.txt`, `pyproject.toml`;
   - exclusão de arquivo que existia no commit base.
   - Se algum ocorrer: status `hold`, **sem commit**, sem rollback (preservar evidência), notificar e **encerrar a execução**.
6. Teste passou e nenhum gatilho: commit com mensagem `tarefa <id>: <titulo>`, status `done`.
7. Teste falhou: `git reset --hard <base>` + `git clean -fd`, SOMENTE dentro de `$RepoPath`; nova tentativa. Ao atingir `$MaxTentativas`: status `failed`. Tarefas que dependem dela permanecem `pending`. As tarefas independentes continuam.
8. Após cada chamada, somar `total_cost_usd`. Se o acumulado passar de `$MaxCustoUsd`, ou o tempo total passar de `$MaxMinutos`: concluir a tarefa atual pelo fluxo normal (passos 4–7), notificar e **pausar** (encerrar sem iniciar outra chamada).

### 3.4 Arquivos em `$EstadoDir`

| Arquivo | Formato |
|---|---|
| `estado.json` | Objeto com, no mínimo: `tarefa_atual` (string ou null), `tentativa` (int), `custo_acumulado_usd` (número), `inicio` (ISO 8601), `atualizado_em` (ISO 8601), `status_execucao` (`rodando` \| `concluido` \| `hold` \| `pausado` \| `falhou`). Regravado a cada etapa (heartbeat). |
| `log.jsonl` | Uma linha JSON por evento, cada uma com `ts` e `evento`. |
| `notificacoes.txt` | Escrito pela função `Notificar()`, isolada. Por ora só grava texto aqui. |

### 3.5 Retomada

Rodar de novo com os mesmos parâmetros retoma de onde parou: tarefas `done` são puladas; tarefa `in_progress` volta ao commit base registrado e recomeça, mantendo a contagem de tentativas.

### 3.6 Códigos de saída

| Código | Situação |
|---|---|
| 0 | Todas as tarefas `done` |
| 1 | Terminou com ao menos uma tarefa `failed` (sem hold nem pausa) |
| 2 | Encerrou por `hold` |
| 3 | Pausou por teto de custo ou de tempo |

## 4. `TAREFAS.json`

```json
{
  "tarefas": [
    { "id": "T1", "titulo": "...", "prompt": "...", "depends_on": [], "status": "pending", "tentativas": 0, "critica": false }
  ]
}
```

Status válidos: `pending`, `in_progress`, `done`, `failed`, `hold`. O controlador atualiza o próprio arquivo.

## 5. `.claude/settings.json`

- `permissions.defaultMode`: `"dontAsk"`.
- `allow`: apenas git (`status`, `diff`, `add`, `commit`, `log`), o comando de teste, leitura e edição dentro do repositório.
- `deny`: remoção fora do repo, `Invoke-Expression`, `Start-Process`, `curl`/`Invoke-WebRequest`, `git push`, edição dos arquivos de teste.
- Cuidado obrigatório (ver `REFERENCIA_CLAUDE_CODE.md`): em `claude -p`, regras `allow` do `.claude/settings.json` do projeto **não valem** se a pasta não for confiada. O kit precisa resolver isso (por exemplo, passando as regras por `--settings` ou `--allowedTools`). Como resolve é avaliado pelo júri.

## 6. `CONTEXTO.md`

Modelo do contexto persistente da supervisora: objetivo, decisões tomadas, regras R1–R7, pendências.

## 7. Testes objetivos

O script `testes/run-cenarios.ps1` (publicado junto com esta especificação) roda 5 cenários contra cada kit, com um Claude simulado. Os cenários e as verificações estão descritos em `RUBRICA.md` e no próprio script. Execução no GitHub Actions, runner `windows-latest`, logs públicos.
