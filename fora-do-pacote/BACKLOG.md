# Backlog do fluxo autônomo — FORA DO PACOTE DA COMPETIÇÃO

> Este arquivo não faz parte do pacote auditado nem do congelamento. Não altera regras, rubrica ou testes.

## Pós-piloto

### B-01 · Avaliar os mods Output Diet e Reread Guard no loop autônomo
- **Origem:** vídeo "Claude Code: 10 Mods Contra Desperdício e Retrabalho" (ViktorKav), aprovado por Leandro em 15/10/2026.
- **Objetivo:** reduzir tokens e custo por tarefa no `claude -p` (saídas longas de testes e logs; releituras do mesmo arquivo).
- **Condições obrigatórias antes de usar:**
  1. Só mods que observam ou resumem saída. Nenhum mod que aprove ou negue chamadas de ferramenta (um mod pode passar por cima de `ask`, hooks `PreToolUse` e, em máquina não gerenciada, de regras `deny`).
  2. Auditar o código e rodar `claude plugin validate` para listar o que o mod registra.
  3. Conferir que o kit vencedor não usa `--bare` nem `--safe-mode` (esses modos não carregam mods instalados).
  4. Medir antes e depois: `total_cost_usd` e tempo por tarefa no mesmo `TAREFAS.json`, no repositório descartável.
- **Fora do escopo:** competição e piloto rodam sem mods.
- **Descartados para o loop:** Tool Diet e Cache Keeper (já cobertos pelo nativo e pelo `estado.json`/`CONTEXTO.md`), Context Bar, Goal Meter, Replay Theater e MD Preview (são visuais, não desenham no `-p`), Collision Guard (só se houver agentes em paralelo) e Blast Radius (espera confirmação e trava o headless).
- **Uso interativo de Leandro (opcional, fora do loop):** amostras oficiais `token-weather`, `blast-radius` e `replay-theater`.
