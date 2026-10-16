# Pacote da competição de kits — v0.2.1, CANDIDATA AO CONGELAMENTO

> **Não distribuir aos competidores antes do congelamento.**
> Redigido por: Claude · Anthropic · Claude Opus 5.5 (claude-opus-5-5), que também é participante.
> Data: 16/10/2026. A v0.2 foi aprovada pelos jurados (Kimi: aprovado; Le Chat/Vibe: aprovado com ajustes). Esta versão aplica só os ajustes finais. Próximo passo: congelamento com SHA-256 publicado por Leandro → liberação simultânea.

## Conteúdo

| Arquivo | Função |
|---|---|
| `ESPECIFICACAO.md` | O que cada kit deve entregar, com a interface FIXA do `controlador.ps1` |
| `RUBRICA.md` | 40 pontos objetivos (8 cenários) + 60 do júri, com âncoras e papéis |
| `REFERENCIA_CLAUDE_CODE.md` | Fatos atuais do Claude Code, com link e seção da documentação oficial |
| `MUDANCAS.md` | O que mudou em cada versão e por quê |
| `testes/run-cenarios.ps1` | Script dos 8 cenários |
| `testes/mock/fake-claude.ps1` | Claude Code simulado, guiado por um plano por tarefa (o teste cria um lançador por cenário; `fake-claude.cmd`/`.sh` são só para uso manual) |
| `testes/validacao/validar-harness.ps1` | Prova que o script pontua certo (nulo, oráculo, trapaceiro, mutantes) |
| `testes/validacao/controlador-nulo.ps1` | Não faz nada; deve tirar 0/40 |
| `testes/validacao/controlador-espiao.ps1` | Procura as variáveis do simulado; prova que elas não chegam ao controlador |
| `testes/validacao/controlador-oraculo.ps1` | Trapaceia de propósito (lê o cenário); com mutantes, prova que o script reprova onde deve |
| `.github/workflows/competicao.yml` | GitHub Actions, `windows-latest`: valida o script e depois roda um job por kit |
| `PACOTE_COMPLETO_v0.2.1.txt` | Todos os arquivos acima num único texto, com SHA-256 |
| `SHA256_v0.2.1.txt` | Lista de SHA-256 para o congelamento |

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
| espião | 0, sem variáveis do simulado visíveis | 0, nenhuma visível nos 8 cenários | tudo |

No Windows, a mesma validação é o primeiro job do workflow, que para tudo se qualquer número diferir.

## Como rodar os kits
1. Commitar cada kit anonimizado em `kits/kit-A/` … `kits/kit-D/` (com `controlador.ps1` e `.claude/settings.json`). Kit ausente é pulado sem erro.
2. No GitHub, aba **Actions** → `competicao-kits` → **Run workflow**.
3. Baixar os artefatos `resultados-kit-X` (pontuação em `resultados.json`).
