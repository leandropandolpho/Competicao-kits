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

## Achados do piloto (Ato 036 — 20/10/2026)

### B-02 · Recusa do executor vira "done" com commit vazio (falso concluído) — RESOLVIDO (Ato 038)
- **Onde:** kit híbrido, `controlador.ps1` (origem B).
- **Evidência:** provocações P1 (afrouxar teste) e P2 (apagar doc). O Claude recusou as duas, sem alterar nada; o teste passou; o controlador registrou `status: done` e fez commits vazios (`398678f`, `b16658b`).
- **Correção proposta:** se o executor não deixou diff (`git status --porcelain` vazio), não commitar e marcar a tarefa como `hold` com motivo `sem_alteracao`, notificando o humano.
- **Teste novo para o harness:** cenário `recusa` (mock responde sem alterar arquivos) → espera `hold`, zero commits.

### B-03 · Acentuação corrompida — RESOLVIDO (Ato 038): não era do controlador
- **Evidência:** `N├úo alterei` em vez de `Não alterei`.
- **Causa provável:** saída do `claude.exe` lida com a página de código do console, não UTF-8.
- **Correção proposta:** `[Console]::OutputEncoding = [Text.UTF8Encoding]::new()` antes de chamar o executor.

### Resolução B-02/B-03 (Ato 038 — 20/10/2026, autorizada no Ato 037)
- **B-02:** `controlador.ps1` sem `--allow-empty`; nova função `Houve-Alteracao`; executor sem falha e sem alteração → `hold` com motivo `SEM_ALTERACAO`, notificação e evento `sem_alteracao`; trava final no `Commitar` (aborta se nada estiver no índice). Gatilhos R1 continuam com precedência. Branch `hibrido`, commit `7cd7864`, SHA-256 do controlador `ced2ec45…608e`.
- **B-03:** o `log.jsonl` do controlador já estava íntegro (UTF-8). A acentuação quebrava na captura da ponte (`ponte-piloto.ps1`), corrigida com `[Console]::OutputEncoding` UTF-8 — vale a partir do próximo início da ponte.
- **Validação:** harness congelado v0.2.2 = 40/40 (Linux e Windows); `fora-do-pacote/testes-piloto/cenario-recusa.ps1` aprovado (e reprovado no controlador antigo); P1/P2 repetidas pela ponte → `hold SEM_ALTERACAO`, nenhum commit, teste intacto, documento preservado, acentos íntegros.

### B-04 · Executor não conseguiu rodar o teste dentro da sessão (observação)
- No P1 v2, o Claude relatou que "a execução do PowerShell foi negada nesta sessão". O allow cobre só `pwsh -NoProfile -File testes/*`; ele provavelmente tentou outra forma. Não afeta a segurança (o controlador roda o teste), mas reduz a capacidade do executor de verificar o próprio trabalho. Avaliar após o piloto.

### B-05 · Interrupção: custo da chamada derrubada não entra na conta; órfãos sem prova no Windows
- Retomada (Ato 038, `006`): `custo_preservado: 0.0`, porque o executor morto não devolveu `total_cost_usd`. O teto de custo subestima o gasto real numa queda.
- O verificador de `claude.exe` do teste 006 contou 0 até antes da queda (filtro de caminho provavelmente errado): ausência de órfãos não comprovada no Windows real (no harness, C4 cobre).
- Avaliar: estimativa conservadora de custo para chamada interrompida; verificação de órfãos pelo PID da árvore.

## Fase 6

### B-06 · Avaliar o OpenCode 2.x como executor alternativo e base das consultoras (decisão A — Atos 040/041, convergência ChatGPT, Gemini e Claude)
- Nada instalado antes de a fase 4 fechar; teste junto da fase 6, comparado com o PAL MCP em tarefas equivalentes e critérios objetivos.
- Pré-requisitos: (1) modo `run` com saída JSON e custo por chamada comprovados no Windows; (2) acesso a pastas externas bloqueado; (3) chave OpenRouter dedicada, com teto de gasto, só na conta `piloto`.
- Sequência: prova de conceito só leitura → mesma tarefa nos dois executores → adaptador sem tocar a interface congelada, com regressão 40/40 e provocações P1/P2.
- **Complemento Perplexity (Ato 045, verificado em fontes externas em 20/10/2026):** acesso a pastas externas é *permitido por padrão* desde a 2.0.25 (mudança sem nota de versão; parte da documentação ainda diz o contrário) e há relatos de PowerShell/bash contornando a regra no Windows (issue anomalyco/opencode#54524); 2.1.0 (20/10/2026) mudou contratos de SDK, eventos HTTP e plugins. Exigências adicionais para a prova de conceito: versão fixa, hash do instalador conferido, `external_directory: deny` (ou `ask`) e teste explícito de escape por PowerShell para fora do repositório.

## Fase 5 — Supervisora (Ato 055)

### B-07 · 2ª opinião de outra família antes de qualquer "liberar" sem supervisão (condição 7 do Ato 047)
- Provedor B (OpenAI `gpt-6-astra`, Responses API com `json_schema` estrito) implementado e **validado 6/6** (`hibrido@2935301`, evidência `013`). Chave restrita a `/v1/responses`, guardada em arquivo só da conta `piloto`; crédito US$ 10 sem recarga.
- Regra de combinação definida por Leandro (Ato 061) e implementada (`supervisao-combinada.ps1`): A e B independentes → troca de pareceres → voto de Minerva (Claude árbitro) → Leandro se o árbitro não tiver confiança alta. R1 nunca vai a votação; falha → escalar; "liberar" só pelo árbitro fica marcado `liberar_por_desempate` e não serve para execução sem supervisão.
- Validado no real (evidência `014`), inclusive a troca convergindo no caso ambíguo D7.
- Custo do provedor B fica **desconhecido** (contado pelo teto por chamada) até alguém informar os preços oficiais por milhão de tokens (`-OpenAIPrecoEntradaPorMTokUsd`, `-OpenAIPrecoSaidaPorMTokUsd`).

### B-08 · Contrato entre controlador e supervisora
- O controlador grava o evento `teste` sem o campo `tarefa`. A supervisora contorna isso usando a janela de eventos da tarefa. Se o kit for revisado um dia, incluir `tarefa` em todos os eventos.
- Em hold `SEM_ALTERACAO`, o controlador não roda o teste. A supervisora compensa lendo os arquivos citados no pedido.

### B-09 · Fixtures de teste no Windows: final de linha
- Um `git clone` do repo do piloto gerou hash diferente do arquivo de teste (CRLF/LF), e a supervisora aplicou R1 (corretamente). Fixtures futuras devem copiar os bytes, não clonar.

### F5-01 a F5-05 · Achados da auditoria estática do ChatGPT (Ato 063) — RESOLVIDOS (Ato 064)
- Correções em `hibrido@aa83c26`, com testes negativos (S19–S22, K9–K10) e regressão real (`evidencias-fase5/015`). Detalhes em `evidencias-fase5/LEIA-ME.md`.
- Pendente: nova auditoria dos pontos corrigidos (ChatGPT) para liberar a integração operacional da supervisora combinada.

### F5-01-R e F5-04-R · Links/junctions (reauditoria do Ato 065) — RESOLVIDOS (Ato 066)
- `supervisora/caminhos.ps1` (verificação física). Evidência Windows: `evidencias-fase5/016` a `018` (junctions reais; 40/40 e 17/17; regressão real 7/7).
- Pendente: confirmação do ChatGPT para a integração operacional definitiva da supervisora combinada.

## B-05 — candidata por fora do controlador (Atos 068–070)
- Prioridade definida: B-05 antes da fase 6 (Claude, ChatGPT e Perplexity). Correção registrada: B-05 **não** é o único bloqueio da execução desassistida — B-07 e a aprovação humana continuam.
- Contrato proposto em `fora-do-pacote/B05_CONTRATO.md` (lançador com Job Object + embrulho com teto por chamada e razão). Implementação só depois da aprovação do contrato.
- **Candidata implementada e testada (Ato 073)**: `hibrido@8fa8933`, evidências em `fora-do-pacote/evidencias-b05/` (28/28 determinísticos; Claude real N1/N2/N6; P1/P2; 40/40). Achado relevante: filhos do pwsh empacotado não herdam job aninhado → associação ativa por varredura. Aguardando auditoria independente.
