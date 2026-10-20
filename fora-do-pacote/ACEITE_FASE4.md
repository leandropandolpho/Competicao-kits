# Aceite formal da fase 4 — Piloto Windows (Ato 044, 20/10/2026)

**Despacho:** Ato 043 — ChatGPT (GPT-6): FASE 4 APROVADA — FASE 5 LIBERADA.

## Referência validada
- Controlador: branch `hibrido`, commit `7cd786462e27c81f3711c37ab5ee73da83c01a6d`, `kits/kit-A/controlador.ps1`, SHA-256 `ced2ec45be2ff8405c57874bc29373f7e8ac6f20b696dee512a3e562f3e6608e` (o mesmo instalado em `C:\Users\piloto\piloto\kit\`).
- Settings, CONTEXTO e TAREFAS do kit: inalterados desde `f392439`.

## Condições de avanço (Ato 038) — todas satisfeitas
| # | Condição | Evidência |
|---|---|---|
| 1 | Harness v0.2.2 pós-correção 40/40 no Windows | Actions 39487994430 (job kit-A) + `evidencias-fase4/ponte/003` |
| 2 | Recusa sem alteração → HOLD, sem commit | `cenario-recusa.ps1` (003) |
| 3 | P1/P2 → HOLD, integridade preservada | `evidencias-fase4/ponte/004` + `estados/provoca-*-v2` |
| 4 | Retomada após interrupção real | `evidencias-fase4/ponte/006` + `estados/interrupcao2` (commit `e1cb206`) |

Evidência `005` excluída do aceite (falha do script de teste, não demonstra retomada).

## Limites da liberação da fase 5
- Desenvolvimento e testes **controlados**, com supervisão humana e tetos de custo efetivos.
- **Não autorizado:** execução autônoma desassistida, até B-05 ser resolvido ou mitigado de forma verificável.
- B-06 (OpenCode) só na fase 6; kit congelado não muda.

## Pendências rastreadas
B-04, B-05, B-06 em `BACKLOG.md`. Ponte: correção de UTF-8 (B-03) vale a partir do próximo login da conta `piloto`.
