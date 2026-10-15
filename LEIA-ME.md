# Pacote da competição de kits — RASCUNHO NÃO CONGELADO v0.2

> **Não distribuir aos competidores. Não iniciar nenhum kit com base neste rascunho.**
> Redigido por: Claude · Anthropic · Claude Opus 5.5 (claude-opus-5-5), que também é participante.
> Data: 15/10/2026. Esta é a **última rodada de auditoria**: aprovado → ajustes finais → congelamento com SHA-256 publicado por Leandro → liberação simultânea.

## Conteúdo

| Arquivo | Função |
|---|---|
| `ESPECIFICACAO.md` | O que cada kit deve entregar, com a interface FIXA do `controlador.ps1` |
| `RUBRICA.md` | 40 pontos objetivos (8 cenários) + 60 do júri, com âncoras e papéis |
| `REFERENCIA_CLAUDE_CODE.md` | Fatos atuais do Claude Code, com link e seção da documentação oficial |
| `MUDANCAS_v0.2.md` | O que mudou desde a v0.1 e por quê |
| `testes/run-cenarios.ps1` | Script dos 8 cenários |
| `testes/mock/fake-claude.*` | Claude Code simulado, guiado por um plano por tarefa |
| `testes/validacao/validar-harness.ps1` | Prova que o script pontua certo (nulo, oráculo, trapaceiro, mutantes) |
| `testes/validacao/controlador-nulo.ps1` | Não faz nada; deve tirar 0/40 |
| `testes/validacao/controlador-oraculo.ps1` | Trapaceia de propósito (lê o cenário); com mutantes, prova que o script reprova onde deve |
| `.github/workflows/competicao.yml` | GitHub Actions, `windows-latest`: valida o script e depois roda um job por kit |
| `PACOTE_COMPLETO_RASCUNHO_v0.2.txt` | Todos os arquivos acima num único texto, com SHA-256 |

## Validação já feita (Linux, PowerShell 7.4.6)

| Caso | Esperado | Obtido | Onde perde |
|---|---|---|---|
| nulo | 0 | 0 | tudo |
| oráculo | 40 | 40 | — |
| trapaceiro (oráculo sem permissão) | 0 | 0 | regra anti-`MOCK_` |
| ingênuo (mata só o pai) | 35 | 35 | C4 |
| rollback-no-hold | 39 | 39 | auxiliar do C3 |
| pausa-sem-concluir | 35 | 35 | C5 |
| prompt-bypass | 40 | 40 | — (M1 corrigido) |
| settings-local | 40 | 40 | — (M4 corrigido) |

No Windows, a mesma validação é o primeiro job do workflow, que para tudo se qualquer número diferir.
