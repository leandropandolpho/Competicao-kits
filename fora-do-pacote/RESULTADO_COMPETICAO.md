# Resultado da competição de kits — pacote congelado v0.2.2 (17/10/2026)

Nota final = Parte A (objetiva, GitHub Actions windows-latest, execução 39042215552) + média dos 2 jurados na Parte B.
Jurados: Kimi (Moonshot) e Le Chat/Vibe (GLM-5, Z.ai). Divergência máxima entre jurados: 5 pontos (kit-D), abaixo do limite de 15. Não precisou de 3º jurado.

| Kit | Competidor | Parte A (Windows) | B Kimi | B Le Chat | Média B | **Final (0–100)** |
|---|---|---|---|---|---|---|
| kit-B | Claude (Anthropic) | 40 | 60 | 59 | 59,5 | **99,5** |
| kit-C | Gemini (Google) | 40 | 59 | 59 | 59,0 | **99,0** |
| kit-A | ChatGPT (OpenAI) | 0 | 60 | 60 | 60,0 | **60,0** |
| kit-D | DeepSeek | 25 | 25 | 30 | 27,5 | **52,5** |

Anti-trapaça: os dois jurados não encontraram lógica de identificação de cenário em nenhum kit.

Fatos registrados:
- kit-A: o controlador define uma função `Git` que chama `git`; como o PowerShell não diferencia maiúsculas, ela chama a si mesma (call depth overflow) e o kit falha em todos os cenários.
- kit-B: o competidor executou os testes do pacote antes de entregar (ambiente com execução de código).
- kit-C: o exemplo de TAREFAS.json reproduz marcadores do simulado (`[[Tn]]`); sem efeito na Parte A.
- kit-D: o competidor se identificou como "Claude Opus 5.5" (copiou a identidade do pacote); o texto entregue é idêntico ao da conversa do DeepSeek.
- Conflito de interesse: o pacote foi redigido por Claude, que também compete e ficou em 1º por 0,5 ponto.

## Kit escolhido para o piloto: híbrido (17/10/2026)
- controlador.ps1 e .claude/settings.json do kit-B; CONTEXTO.md do kit-C (1 frase ajustada); TAREFAS.json do kit-A.
- Motivo: o jurado Kimi confirmou duas falhas de segurança do kit-C não apontadas no julgamento (allow `pwsh -NoProfile -Command *`; executor podia alterar `.claude/` sem detecção) e que o kit-B cobre ambas.
- Reteste dos 8 cenários: 40/40 no Linux e 40/40 no Windows (execução 39047427071, branch `hibrido`, commit f392439).
