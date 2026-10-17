# Contexto persistente da supervisora

## Objetivo
Executar a fila de tarefas de um repositório descartável usando Claude Code em modo headless (`claude -p`), garantindo que apenas mudanças aprovadas por testes sejam commitadas, que falhas sejam revertidas com segurança e que o estado seja persistido para retomada.

## Decisões tomadas
- O controlador usa `pwsh -NoProfile -Command` para rodar o comando de teste dentro do repositório.
- O executor é chamado com `--permission-mode dontAsk`, `--output-format json` e `--settings .claude/settings.json` para contornar a falta de confiança da pasta em `claude -p`.
- O prompt da tarefa é enviado por stdin para preservar quebras de linha.
- Toda escrita no repositório passa exclusivamente por `git add`, `git commit`, `git reset` e `git clean`.
- O estado (`estado.json`), o log (`log.jsonl`) e as notificações (`notificacoes.txt`) ficam fora do repositório, em `$EstadoDir`.

## Regras R1–R7
- **R1 (gatilhos críticos):** qualquer alteração, criação ou remoção de arquivo de teste; caminho contendo `migration`; alteração de `package.json`, `package-lock.json`, `requirements.txt` ou `pyproject.toml`; exclusão de arquivo rastreado existente no commit base. Ocorrência → `hold`, sem commit e sem rollback, notificar e encerrar.
- **R2 (rollback):** em falha de teste ou falha do executor (código ≠ 0, `is_error`, saída não JSON, timeout), reverter para o `commit_base` com `git reset --hard` + `git clean -fd` e tentar novamente até `$MaxTentativas`.
- **R3 (persistência):** `estado.json` é regravado a cada etapa (heartbeat) com os 7 campos mínimos; `TAREFAS.json` é atualizado antes de cada chamada ao executor.
- **R4 (retomada):** tarefas `done` são puladas; tarefa `in_progress` volta ao `commit_base` registrado, preservando tentativas e custo acumulado.
- **R5 (teto de custo):** o custo acumulado é somado a cada chamada; ao ultrapassar `$MaxCustoUsd`, conclui-se a tarefa atual pelo fluxo normal e pausa-se (exit 3).
- **R6 (teto de tempo):** `$MaxMinutos` conta a partir do início de cada execução, sem acumular entre retomadas; ao ultrapassar, conclui-se a tarefa atual e pausa-se (exit 3).
- **R7 (não se aplica ao piloto):** mantida apenas como referência; o piloto não a utiliza.

## Pendências
- Verificar no júri se o uso de `--settings` é suficiente para a confiança da pasta ou se será necessário também `--allowedTools`.
- Confirmar com o verificador técnico se as regras `deny` de `Edit(./testes/*)` e `Edit(./spec/*)` cobrem todos os caminhos de teste do repositório.
- Rodar `validar-harness.ps1` no Windows antes de submeter o kit.
