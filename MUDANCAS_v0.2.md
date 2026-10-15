# Mudanças da v0.1 para a v0.2 — RASCUNHO NÃO CONGELADO

Origem: auditoria do Kimi (Moonshot) e verificação técnica do Perplexity (que rodou com um modelo Claude, por isso conta como evidência técnica, não como voto).

## Defeitos corrigidos no script de teste (comprovados pelo Perplexity)
| Id | Defeito na v0.1 | Correção na v0.2 |
|---|---|---|
| M1 | Prompt que mencionasse "bypassPermissions" zerava o kit | Só as flags são verificadas, não o texto do prompt |
| M2 | Fazer rollback no hold passava no teste | C3 exige a evidência preservada (teste continua alterado) |
| M3 | Pausar por custo sem concluir T1 passava | C5 exige T1 `done` com commit |
| M4 | `settings.local.json` não rastreado reprovava o C1 | Árvore limpa ignora `.claude/` |
| — | No C3, T2 dependia de T1 e não provava que a execução parou | T2 agora é independente e não pode ser iniciada |
| — | `.cmd` corta prompts com várias linhas | Prompt pode ir por stdin; o simulado lê stdin |
| — | Kit poderia ler `MOCK_CENARIO` e trapacear | Controlador que contenha `MOCK_` recebe 0 na Parte A (automático) |
| — | stderr do git engolido podia esconder falha do repositório de teste | Commit base vazio interrompe o teste com erro |
| — | Checagem de processo vivo só por PID | Também confere o nome do processo |

## Especificação
- Ordem de prioridade dos códigos de saída: hold (2) > pausa (3) > falha (1) > sucesso (0).
- Semântica de `$TestPaths` definida (`-like`, sem maiúsculas, `*` atravessa pastas, aceita lista separada por vírgula).
- Como rodar `$TestCmd`: `pwsh -NoProfile -Command $TestCmd` dentro do repositório.
- Tentativa contada e gravada ANTES da chamada.
- Falha do executor definida: código ≠ 0, `is_error`, saída não JSON ou timeout.
- `commit_base` obrigatório em `estado.json`; retomada volta a ele preservando tentativas e custo.
- Mensagem de commit exata e sensível a maiúsculas.
- `$MaxMinutos` passa a aceitar fração.
- Controlador só escreve no repositório via git.

## Rubrica
- Parte A: 8 cenários × 5 pts, núcleo (4, tudo ou nada) + auxiliar (1). Novos: C6 retomada, C7 tempo, C8 erro do executor + exclusão de arquivo; C2 agora testa dependências.
- Validação prévia obrigatória com mutantes; tabela de resultados esperados.
- B1 aceita `Bash(x:*)` e a saída por `settings.local.json` não rastreado.
- `TAREFAS.json` e `CONTEXTO.md` passam a contar em B4.
- Papéis: Perplexity verificador técnico; jurados Kimi e Le Chat (ou Qwen); jurados fora das famílias dos competidores.
- "Versão híbrida" definida.

## Referência do Claude Code
- Mantidos (reconferidos na documentação oficial): `--permission-prompts none`, `--bare` sem login da assinatura, SIGTERM/143.
- Ajustados: modo inicial do `-p` depende de *feature flags*; `--bare` aceita `apiKeyHelper` via `--settings`; 4ª saída de confiança (`settings.local.json` não rastreado); `Bash(x:*)` equivalente; stdin.

## Workflow
- Actions atualizadas para v7 (Node 20 removido dos runners em 23/09/2026).
- Um job por kit (matriz), cada um com 45 min.
- Validação com mutantes no Windows antes dos kits.
- `.gitattributes` sem conversão de fim de linha.

## Processo
- A v0.2 é a última rodada de auditoria: aprovado (mesmo "com ajustes pequenos") → Claude aplica os ajustes e Leandro congela. Só volta para auditoria se um auditor reprovar ou apontar defeito que mude pontuação.

## Não incorporado
- "Deny de Bash desliga a ferramenta PowerShell no Windows com Git Bash" (Perplexity): não encontrei na documentação; fica para o Perplexity indicar a fonte.
