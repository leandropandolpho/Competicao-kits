# Pacote da competição de kits — RASCUNHO NÃO CONGELADO v0.1

> **Não distribuir aos competidores. Não iniciar nenhum kit com base neste rascunho.**
> Redigido por: Claude · Anthropic · Claude Opus 5.5 (claude-opus-5-5), que também é participante.
> Data: 15/10/2026. Próximos passos (M8 corrigido): auditoria de Grok e Perplexity → nova versão se houver ajuste → congelamento com SHA-256 publicado por Leandro → liberação simultânea.

## Conteúdo

| Arquivo | Função |
|---|---|
| `ESPECIFICACAO.md` | O que cada kit deve entregar, com a interface FIXA do `controlador.ps1` |
| `RUBRICA.md` | 40 pontos objetivos (5 cenários) + 60 do júri, com âncoras |
| `REFERENCIA_CLAUDE_CODE.md` | Fatos atuais do Claude Code, com link da documentação oficial |
| `testes/run-cenarios.ps1` | Script dos 5 cenários (testes objetivos) |
| `testes/mock/fake-claude.*` | Claude Code simulado, controlado por `MOCK_CENARIO` |
| `testes/validacao/controlador-nulo.ps1` | Não faz nada; deve tirar 0/40 |
| `testes/validacao/controlador-oraculo.ps1` | Trapaceia lendo o cenário; deve tirar 40/40. Só prova que o script consegue dar pontos |
| `.github/workflows/competicao.yml` | Roda tudo no GitHub Actions, `windows-latest`, logs públicos |

## Validação já feita (Linux, PowerShell 7.4.6)

| Controlador | Resultado | Esperado |
|---|---|---|
| Nulo | 0/40 | 0/40 |
| Oráculo | 40/40 | 40/40 |
| Oráculo com encerramento ingênuo (mata só o processo pai) | C4 reprovado (processo e filho vivos) | C4 reprovado |

Limitações conhecidas:
- A validação foi em **Linux**. No Windows ela só acontece no primeiro passo do workflow, que falha se o nulo não der 0 ou o oráculo não der 40.
- O oráculo foi escrito pelo mesmo autor do script de teste. A auditoria deve conferir se ele não esconde algum atalho.
- Os 40 pontos são tudo ou nada por cenário. Os jurados podem propor pontuação parcial.

## O que os auditores devem verificar
1. Se algum cenário favorece um estilo de implementação sem que a especificação peça isso.
2. Se a interface fixa (seção 3 da especificação) é suficiente e não ambígua.
3. Se as âncoras da rubrica são justas e verificáveis.
4. Se a referência do Claude Code tem algum fato errado ou desatualizado.
5. Se os cenários cobrem o que importa (por exemplo: falta um cenário de retomada?).
