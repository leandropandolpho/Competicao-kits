# Pacote da competição de kits — v0.2.2 CONGELADO

Congelado por decisão de Leandro em 17/10/2026. A partir daqui, nenhum arquivo do pacote muda. Qualquer mudança gera nova versão, com novos hashes.

| Item | Valor |
|---|---|
| Commit | `61a09d2f7030ec798b96b8cf809cc4965d036874` |
| Arquivo único | `PACOTE_COMPLETO_v0.2.2.txt` |
| SHA-256 do arquivo único | `674ddac0d19670ad0ab605567344cf76685a9dd05554239c107bfae6559bd157` |
| Lista por arquivo | `SHA256_v0.2.2.txt` (15 arquivos), conferida automaticamente pelo workflow a cada execução |
| Validação no Windows | [Execução 38928263066](https://github.com/leandropandolpho/Competicao-kits/actions/runs/38928263066): sucesso |

## Vereditos
- **Kimi (Moonshot), jurado:** APROVADO (v0.2)
- **Le Chat/Vibe (executou GLM-5, da Z.ai), jurado:** APROVADO COM AJUSTES (v0.2); ajustes aplicados na v0.2.1
- **Perplexity (executou Claude Opus 5.5), verificador técnico, não vota:** APROVADO COM AJUSTES, condicionado ao defeito A4; corrigido na v0.2.2 e coberto pelo caso `trapaceiro-caminho` (0 pontos)

## Validação do script de teste (Linux e Windows)
oráculo 40 · prompt-bypass 40 · settings-local 40 · prompt-stdin 40 · rollback-no-hold 39 · custo-nao-preservado 39 · ingênuo 35 · pausa-sem-concluir 35 · nulo 0 · trapaceiro 0 · trapaceiro-caminho 0 · espião 0 (nenhuma variável do simulado visível)

## Regras de geração dos kits
Cada competidor (Claude, ChatGPT, Gemini, DeepSeek) gera o kit numa **conversa nova**, recebendo só o pacote congelado. Isso vale também para o Claude, que redigiu o pacote.
