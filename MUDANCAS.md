# Mudanças

## v0.2.1 → v0.2.2 (16/10/2026) — correção do defeito A4 (Perplexity) e ajustes finais

O Perplexity (verificador técnico; rodou com Claude Opus 5.5, não vota) deu **APROVADO COM AJUSTES, condicionado ao A4**: um controlador que só lia o nome do cenário no caminho recebido em `-RepoPath` tirava 40/40 sem fazer o trabalho. Como muda pontuação, foi corrigido antes do congelamento e provado por um caso novo na validação.

| Origem | Achado | O que foi feito |
|---|---|---|
| Perplexity A4 (**defeito**) | Nome do cenário nos caminhos (`work/C3-altera-teste/...`) | Cada cenário roda numa pasta temporária de nome aleatório, sem pastas de outros cenários ao lado; só depois é copiada para `work/<cenário>`. Regra geral nova: qualquer lógica que tente identificar o cenário (nomes, valores dos parâmetros, `$ClaudeCmd`, arquivos fora dos parâmetros, variáveis) zera a Parte A, verificada pelo júri. Caso novo na validação: **trapaceiro-caminho** (o oráculo procurando o cenário nos caminhos) tem de dar 0. |
| Perplexity A3 | O auxiliar "custo preservado" do C6 não testava nada (a 1ª execução não gerava custo) | No C6, a 1ª execução agora conclui T0 (custo 0,02) antes de travar em T1; a retomada tem de terminar com custo ≥ 0,04. Caso novo: **custo-nao-preservado** tem de dar 39. |
| Perplexity A3 | Margem do C7 apertada no Windows | Teto de 0,1 min (6 s) e simulado lento de 10 s. |
| Perplexity A3 | `MOCK_` sem distinguir maiúsculas pegava nomes como `$useMock_x` | Busca sensível a maiúsculas. |
| Perplexity A3 | Prompt por stdin não era testado no Windows | Caso novo: **prompt-stdin** tem de dar 40. |
| Perplexity A1 | Falha do executor que alterou um teste: rollback ou hold? | Passo 5: os gatilhos R1 são verificados antes do rollback; se ocorrerem, vale o `hold`. |
| Perplexity A1 | Faltava `git add` | Incluído entre os comandos permitidos. |
| Perplexity A1 | `$MaxMinutos` na retomada | Conta por execução e não se acumula; o custo, sim. |
| Perplexity A1 | Kit do Claude gerado com acesso à conversa do pacote | Regra de geração: cada competidor, inclusive o Claude, gera o kit numa conversa nova, só com o pacote congelado. |
| Perplexity A7 | Hashes só impressos; token exposto ao código do kit | O workflow confere cada arquivo contra `SHA256_v*.txt` e falha se divergir; `permissions: contents: read`; `persist-credentials: false`; registra a versão da imagem do runner. |
| Perplexity A5/A2 | "Deny de Bash desliga a ferramenta PowerShell" | **Não confirmado:** a página que o Claude recebeu em 16/10/2026 não tem essa seção. Registrado na referência como ponto em disputa, com consequência neutra: jurados não penalizam deny de shell em `Bash(...)` nem em `PowerShell(...)`; o piloto confere com `/permissions`. Não entrou na âncora de B1. |

**Não incorporado:** fixar a imagem do Windows (opcional). O workflow passa a registrar a versão da imagem em cada execução.

## v0.2 → v0.2.1 (16/10/2026) — ajustes finais, candidata ao congelamento

Vereditos da v0.2: **Kimi (Moonshot) APROVADO**; **Le Chat/Vibe (executou GLM-5, da Z.ai) APROVADO COM AJUSTES**. Nenhum defeito que mude pontuação. Pela regra do processo, não há nova rodada de auditoria.

| Origem | Ajuste | O que foi feito |
|---|---|---|
| Le Chat A3/A4 | As variáveis `MOCK_*` eram herdadas pelo controlador; a regra anti-trapaça era só textual | Cada cenário recebe um lançador próprio (`claude.cmd`/`claude.sh`, fora do repositório) que define as variáveis só para o simulado. O controlador não as enxerga. O nome do cenário não aparece no lançador. Novo caso de validação **espião** (procura as variáveis sem escrever o prefixo): 0 pts e nenhuma variável visível nos 8 cenários. Regra nova: ler o conteúdo de `$ClaudeCmd` ou arquivos fora dos parâmetros para descobrir o cenário zera a Parte A (constatação do júri) |
| Le Chat A1 | Redação do passo 7 (gatilhos R1) | Agora diz explicitamente que os gatilhos têm precedência sobre o resultado do teste |
| Le Chat A5 | Citar o texto exato de dois itens | `CLAUDE_CODE_USE_POWERSHELL_TOOL=0` e `Remove-Item`: texto da documentação oficial colado na referência (reconferido em 16/10/2026) |
| Le Chat A7 | O passo de hashes do workflow excluía `*.md` | Agora registra todos os arquivos |
| Kimi (nota) | Aviso de que os kits precisam estar em `kits/` | Incluído no LEIA-ME |

**Validação refeita (Linux, PowerShell 7.4.6):** nulo 0 · oráculo 40 · trapaceiro 0 · ingênuo 35 · rollback-no-hold 39 · pausa-sem-concluir 35 · prompt-bypass 40 · settings-local 40 · espião 0, sem variáveis visíveis. Teste negativo: com uma variável `MOCK_TESTE` posta de propósito no ambiente, o espião a detectou.

**Não incorporado:**
- Cenário para gatilhos de migration e manifest (Le Chat A6, marcado como opcional). Fica de fora para não mudar o total de 40 pontos nem a tabela de validação aprovada. O comportamento continua exigido na especificação e é avaliado pelo júri em B2.
- "Deny de Bash desliga a ferramenta PowerShell" (Perplexity, v0.1). Reconferido em 16/10/2026: a seção "Glob tool behavior" de `tools-reference.md` diz que um deny de `Bash` remove o Bash e devolve Glob/Grep (em macOS/Linux/WSL), mas nada fala da ferramenta PowerShell. Continua sem fonte.
- Lançadores `fake-claude.cmd`/`.sh`: mantidos só para uso manual. O script de teste não os usa mais.

## v0.1 → v0.2 (15/10/2026)

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
