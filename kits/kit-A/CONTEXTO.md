# CONTEXTO.md — supervisora do piloto

## Objetivo

Executar tarefas de um repositório Git descartável, por ordem de elegibilidade e dependências, com Claude Code headless em `dontAsk`; conferir cada resultado por teste independente; registrar decisões, custos e evidências para retomada.

## Autoridades e limites

- **Controlador:** seleciona tarefas, grava tentativas antes de invocar o executor, calcula hashes dos testes, aplica gatilhos críticos, executa o teste por conta própria, faz commit/rollback e notifica.
- **Executor:** trabalha somente dentro do repositório, sem alterar testes, migrations, manifests nem apagar arquivos rastreados. Seu relato não comprova sucesso.
- **Persistência:** `TAREFAS.json` e `EstadoDir` são externos ao repositório. `estado.json` e `TAREFAS.json` têm atualização por substituição atômica; `log.jsonl` registra eventos.
- **Permissões:** `--permission-mode dontAsk` é obrigatório; `--settings .claude/settings.json` é passado explicitamente quando presente, para que `allow` funcione mesmo sem confiança prévia na pasta. `deny` é defesa auxiliar, nunca prova de integridade.

## Decisões operacionais

1. Elegível = `pending`, com todas as dependências `done`; respeitar ordem do arquivo e pular `done`.
2. Em cada tentativa, fixar `commit_base` e hashes dos testes; incrementar e persistir `tentativas` antes da chamada externa.
3. Falha do executor = timeout, código não zero, JSON inválido ou `is_error=true`. Custo válido declarado é acumulado, mesmo quando o executor falha.
4. Após execução, o controlador roda `pwsh -NoProfile -Command $TestCmd`. Os gatilhos críticos precedem o resultado desse teste.
5. Sucesso exige teste com código 0 e commit exato `tarefa <id>: <titulo>`; falha comum reverte ao `commit_base` e remove não rastreados, preservando `.claude/` local.
6. HOLD preserva as evidências e não faz commit/rollback. Limite de tempo/custo encerra somente depois de processar a tentativa atual.
7. Retomada de `in_progress` reverte ao `commit_base` registrado sem zerar tentativas nem custo. Tempo reinicia em cada invocação; custo não.

## Regras R1–R7 — limite do material normativo

- **R1 — gatilhos críticos:** alteração/criação/remoção de arquivo de teste; caminho com `migration`; mudança em `package.json`, `package-lock.json`, `requirements.txt`, `pyproject.toml`; exclusão de arquivo rastreado. Qualquer um implica HOLD imediato, sem rollback e sem iniciar outra tarefa.
- **R2–R6:** mencionadas como acatadas na especificação congelada, mas não definidas individualmente no pacote. Não atribuir a elas obrigações novas sem texto normativo aprovado.
- **R7:** versão corrigida declarada **não aplicável ao piloto**. Não presumir exigências adicionais.

## Estados e saídas

- Tarefa: `pending → in_progress → done | failed | hold`, com retorno a `pending` em retry ou retomada.
- Execução: `rodando | concluido | hold | pausado | falhou`.
- Prioridade de saída: `2` HOLD; `3` pausa por teto; `1` ao menos uma falha/bloqueio; `0` todas `done`.
- Evidências em `EstadoDir`: `estado.json`, `log.jsonl`, `notificacoes.txt`; hashes dos testes no estado.

## Pendências para operação real

- Ajustar os prompts de `TAREFAS.json` ao projeto real e conferir o comando/padrões de teste passados pelo chamador.
- Validar as regras efetivas com `/permissions` na versão instalada do Claude Code, especialmente a ferramenta `PowerShell` no Windows.
- Executar os oito cenários no GitHub Actions/Windows e registrar resultados; este modelo não declara aprovação antecipada.
- Configurar identidade Git e credenciais do Claude Code fora do controlador, sem bypass de permissões.
