# CONTEXTO.md — Contexto Persistente da Supervisora (Piloto)

## 1. Objetivo
Orquestrar a execução autônoma e determinística de tarefas de desenvolvimento em repositório Git descartável no Windows nativo (`pwsh`), separando estritamente:
- **Controlador determinístico (`controlador.ps1`)**: gerencia fila de tarefas, dependências, estado persistente fora do repositório, verificação independente de testes e hashes SHA-256, tetos de custo/tempo, rollback e commits padronizados.
- **Executor headless (`claude -p`)**: opera sob menor privilégio (`--permission-mode dontAsk`), restrito à árvore do repositório.

## 2. Decisões Técnicas Tomadas
- **Confiança em modo headless (`claude -p`)**: em pastas nunca confiadas interativamente, o Claude Code ignora regras `permissions.allow` do `.claude/settings.json` do projeto. O `controlador.ps1` resolve isso passando explicitamente `--settings <caminho-do-settings.json>` na invocação do executor.
- **Envio de prompts via `stdin`**: o prompt integral da tarefa é enviado pela entrada padrão (`StandardInput`) com fechamento imediato do stream, evitando truncamento de múltiplas linhas em lançadores `.cmd` no Windows.
- **Defesa em profundidade nos testes (SHA-256)**: como regras `deny` de shell não constituem barreira absoluta de segurança, o controlador calcula os hashes SHA-256 de todos os arquivos que casam com `$TestPaths` antes e depois de cada chamada ao executor, além de inspecionar `git diff`, arquivos não rastreados e a lista de arquivos rastreados do `commit_base`.
- **Escrita atômica de estado e tarefas**: `estado.json` e `TAREFAS.json` são gravados via arquivo temporário no mesmo diretório seguido de `[System.IO.File]::Move(..., $true)`, prevenindo corrupção de JSON caso o processo seja interrompido no meio da escrita.
- **Encerramento de árvore de processos**: em caso de timeout, o controlador encerra toda a árvore de processos filhos (`taskkill /T /F /PID` no Windows + `Process.Kill($true)`).

## 3. Regras da Mesa (R1 a R7)
- **R1 (Gatilhos críticos de `hold` — prioridade máxima, saída `2`)**: qualquer criação, edição ou remoção de arquivo de teste (`$TestPaths`), caminhos contendo `migration`, alterações em `package.json`, `package-lock.json`, `requirements.txt` ou `pyproject.toml`, ou exclusão de arquivo rastreado existente no `commit_base` interrompe imediatamente a execução com status `hold`, **sem commit e sem rollback** (preservando a evidência), e emite notificação.
- **R2 (Verificação externa independente)**: o controlador nunca confia no relato do executor; executa `pwsh -NoProfile -Command $TestCmd` diretamente em `$RepoPath`.
- **R3 (Isolamento de estado e rollback seguro)**: `TAREFAS.json` e `$EstadoDir` residem obrigatoriamente fora de `$RepoPath`; `git reset --hard <commit_base>` e `git clean -fd` rodam exclusivamente dentro de `$RepoPath`.
- **R4 (Tetos operacionais — saída `3`)**: se `custo_acumulado_usd > $MaxCustoUsd` ou o tempo da execução atual ultrapassar `$MaxMinutos`, o controlador conclui o fluxo normal da tarefa corrente (passos 6–9), notifica e pausa sem iniciar novas chamadas.
- **R5 (Controle de tentativas e dependências — saída `1`)**: tentativas são incrementadas e persistidas em `TAREFAS.json` **antes** da chamada ao executor; ao atingir `$MaxTentativas`, a tarefa recebe `failed`, bloqueando dependentes (`pending`) e permitindo tarefas independentes.
- **R6 (Retomada determinística)**: na retomada, tarefas `done` são puladas; tarefas `in_progress` voltam ao `commit_base` mantendo `tentativas` e `custo_acumulado_usd` (enquanto `$MaxMinutos` vale por execução).
- **R7 (Corrigido)**: **não se aplica ao piloto** (registrado conforme decisão da mesa).

## 4. Prioridade de Códigos de Saída e Ação da Supervisora
| Prioridade | Exit Code | Status | Ação da Supervisora |
|---|---|---|---|
| 1 | `2` | `hold` | Inspecionar a evidência preservada na árvore de trabalho e `notificacoes.txt`; decidir aprovação manual ou descarte. |
| 2 | `3` | `pausado` | Avaliar o consumo em `estado.json` (`custo_acumulado_usd`) e retomar a execução se autorizado. |
| 3 | `1` | `falhou` | Revisar `log.jsonl` das tarefas `failed` e ajustar o prompt ou dividir a tarefa antes de reabrir tentativas. |
| 4 | `0` | `concluido` | Validar os commits `tarefa <id>: <titulo>` gerados na branch de trabalho. |

## 5. Pendências para Evolução Pós-Piloto
- Integrar a função isolada `Notificar()` a um canal externo (webhook/mensageria) mantendo o registro local em `notificacoes.txt`.
- Validar em ambiente real com `/permissions` a interação entre regras `Bash(...)` e `PowerShell(...)` na estação Windows de destino.
