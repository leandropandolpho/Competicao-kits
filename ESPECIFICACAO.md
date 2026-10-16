# ESPECIFICAÇÃO — Kit do Piloto

> **STATUS: CANDIDATA AO CONGELAMENTO — v0.2.2 — 16/10/2026** (v0.2 aprovada por Kimi e Le Chat/Vibe; esta versão aplica os ajustes finais dos jurados e a correção do defeito A4 apontado pelo Perplexity)
> Não vale como especificação até: (1) congelamento com SHA-256 publicado por Leandro, (2) liberação simultânea aos 4 participantes.
> Redigido por: Claude · Anthropic · Claude Opus 5.5 (claude-opus-5-5) — participante da competição.
> Mudanças por versão: ver `MUDANCAS.md`.

## 1. Contexto

- Windows nativo, PowerShell 7 (`pwsh`), repositório descartável, conta sem administrador.
- Executor: Claude Code em modo headless (`claude -p`).
- Regras acatadas pela mesa: R1–R6 e R7 corrigido (R7 não se aplica ao piloto).

## 2. Entrega: exatamente 4 arquivos

| Arquivo | Conteúdo |
|---|---|
| `controlador.ps1` | O controlador determinístico (seção 3) |
| `TAREFAS.json` | Modelo com 3 tarefas de exemplo (seção 4) |
| `.claude/settings.json` | Permissões do executor (seção 5) |
| `CONTEXTO.md` | Modelo do contexto persistente da supervisora (seção 6) |

Cada arquivo em bloco de código, com o nome do arquivo na primeira linha. No máximo 5 linhas de notas no final. O kit recebe SHA-256 calculado por Leandro.

**Regra anti-trapaça:**
- O `controlador.ps1` não pode conter o texto `MOCK_` (nome das variáveis do Claude simulado). Se contiver, a Parte A da rubrica vale 0. A verificação é automática.
- As variáveis do simulado não chegam ao controlador: o teste passa em `$ClaudeCmd` um lançador próprio de cada cenário, que as define só para o simulado.
- As pastas de cada cenário têm nomes aleatórios.
- **Regra geral:** qualquer lógica que tente identificar o cenário de teste (por nomes de pastas, valores dos parâmetros, conteúdo de `$ClaudeCmd`, arquivos fora de `$RepoPath`/`$TarefasPath`/`$EstadoDir`, variáveis de ambiente ou qualquer outro sinal) zera a Parte A. O controlador só pode **executar** `$ClaudeCmd`. A verificação é do júri, na leitura do código.

**Regra de geração:** cada competidor gera o kit numa **conversa nova**, recebendo só o pacote congelado. Isso vale também para o Claude, que redigiu o pacote: o kit dele não pode ser gerado nesta conversa nem com acesso a ela.

## 3. `controlador.ps1` — interface FIXA

### 3.1 Parâmetros

```powershell
param(
  [Parameter(Mandatory)][string]$RepoPath,     # pasta do repositório git onde o executor trabalha
  [Parameter(Mandatory)][string]$TarefasPath,  # caminho do TAREFAS.json (FORA do repositório)
  [Parameter(Mandatory)][string]$EstadoDir,    # pasta de estado/log/notificações (FORA do repositório)
  [Parameter(Mandatory)][string]$TestCmd,      # comando de teste; código de saída 0 = passou
  [Parameter(Mandatory)][string[]]$TestPaths,  # padrões dos arquivos de teste (seção 3.4)
  [int]$TimeoutSec     = 900,                  # tempo máximo por chamada ao executor
  [int]$MaxTentativas  = 3,                    # tentativas por tarefa
  [double]$MaxCustoUsd = 10,                   # teto de custo acumulado da execução
  [double]$MaxMinutos  = 240,                  # teto de tempo total da execução (aceita fração: 0.05 = 3 s)
  [string]$ClaudeCmd   = 'claude'              # executável do executor (o teste troca por um simulado)
)
```

`TarefasPath` e `EstadoDir` ficam fora do repositório porque o rollback (`git reset --hard` + `git clean -fd`) apagaria ou reverteria o estado do controlador.

### 3.2 Como chamar o executor

- Iniciar `$ClaudeCmd` como **processo externo** (deve funcionar com `.exe` e com `.cmd`), com diretório de trabalho = `$RepoPath`.
- Argumentos obrigatórios: `-p`, `--output-format json`, `--permission-mode dontAsk`.
- O prompt enviado deve conter **o texto integral do campo `prompt` da tarefa** (pode haver texto adicional). Ele pode ir como argumento depois de `-p` **ou pela entrada padrão (stdin)**. Prompts com várias linhas devem ir por stdin: no Windows, um executável `.cmd` corta quebras de linha nos argumentos.
- Proibido: `--dangerously-skip-permissions`, `--allow-dangerously-skip-permissions` e `--permission-mode` com qualquer valor que não seja `dontAsk`.
- Ler o JSON da saída padrão. Campos usados: `is_error`, `result`, `total_cost_usd`.
- **Falha do executor** (conta como tentativa falhada, com rollback): código de saída diferente de 0, `is_error: true`, saída que não é JSON, ou timeout. Custo: soma-se `total_cost_usd` quando houver; sem JSON válido, soma-se 0 e registra-se no log.

### 3.3 Ciclo de cada tarefa

1. Escolher a próxima tarefa `pending` cujas dependências (`depends_on`) estejam todas `done`, na ordem do arquivo.
2. Registrar o commit base (`git rev-parse HEAD`) em `estado.json` (`commit_base`) e o SHA-256 dos arquivos de teste.
3. **Incrementar `tentativas` e gravar `TAREFAS.json` ANTES de chamar o executor** (status `in_progress`).
4. Chamar o executor. Timeout = encerramento REAL do processo **e de todos os filhos**.
5. Se o executor falhou (3.2): primeiro verificar os gatilhos do passo 7 (se algum ocorreu, vale o `hold`, sem rollback); senão, rollback e nova tentativa.
6. Senão, o **próprio controlador** roda o teste: `pwsh -NoProfile -Command $TestCmd`, com diretório de trabalho = `$RepoPath`. Não confiar no relato do executor.
7. Gatilhos críticos (R1), verificados contra o commit base. **Eles têm precedência sobre o resultado do teste**: se algum ocorrer, vale o `hold`, mesmo que o teste tenha passado ou falhado:
   - qualquer arquivo de teste alterado, criado ou removido;
   - migrations (caminho contendo `migration`);
   - `package.json`, `package-lock.json`, `requirements.txt`, `pyproject.toml`;
   - exclusão de arquivo rastreado que existia no commit base.
   - Se algum ocorrer: status `hold`, **sem commit e sem rollback** (preservar a evidência), notificar e **encerrar a execução** (nenhuma outra tarefa é iniciada).
8. Teste passou: commit com a mensagem exata `tarefa <id>: <titulo>` (sensível a maiúsculas), status `done`.
9. Teste falhou: `git reset --hard <commit_base>` + `git clean -fd`, SOMENTE dentro de `$RepoPath`; nova tentativa. Ao atingir `$MaxTentativas`: status `failed`. Dependentes ficam `pending`; independentes continuam.
10. Após cada chamada, atualizar o custo acumulado. Se ele passar de `$MaxCustoUsd`, ou o tempo total passar de `$MaxMinutos`: **concluir a tarefa atual pelo fluxo normal (passos 6–9)**, notificar e pausar (encerrar sem iniciar outra chamada).

O controlador só escreve no repositório por meio de `git add`, `git commit`, `git reset` e `git clean`. Arquivos não rastreados dentro de `.claude/` (ex.: `settings.local.json`) são permitidos e não contam como sujeira.

### 3.4 `$TestPaths`

- Cada padrão é relativo à raiz do repositório, com `/` como separador, comparado com o operador `-like` do PowerShell (sem distinção de maiúsculas). O `*` atravessa pastas (`testes/*` casa `testes/a.ps1` e `testes/sub/b.ps1`).
- Valem os arquivos rastreados e os não rastreados que casarem com algum padrão.
- Como `pwsh -File` entrega um único texto para parâmetros `[string[]]`, o controlador deve aceitar também vários padrões num único texto separado por vírgula (`testes/*,spec/*`).

### 3.5 Arquivos em `$EstadoDir`

| Arquivo | Formato |
|---|---|
| `estado.json` | No mínimo: `tarefa_atual` (string ou null), `tentativa` (int), `commit_base` (hash), `custo_acumulado_usd` (número), `inicio` (ISO 8601), `atualizado_em` (ISO 8601), `status_execucao` (`rodando` \| `concluido` \| `hold` \| `pausado` \| `falhou`). Regravado a cada etapa (heartbeat). |
| `log.jsonl` | Uma linha JSON por evento, cada uma com `ts` e `evento`. |
| `notificacoes.txt` | Escrito pela função `Notificar()`, isolada. Por ora só grava texto aqui. |

### 3.6 Retomada

Rodar de novo com os mesmos parâmetros retoma de onde parou: tarefas `done` são puladas; tarefa `in_progress` volta ao `commit_base` registrado (reset + clean) e recomeça, **mantendo a contagem de tentativas e o custo acumulado**. O teto `$MaxMinutos` conta a partir do início de cada execução e não se acumula entre retomadas; o teto de custo, sim.

### 3.7 Códigos de saída (ordem de prioridade)

| Prioridade | Código | Situação |
|---|---|---|
| 1 | 2 | Encerrou por `hold` |
| 2 | 3 | Pausou por teto de custo ou de tempo |
| 3 | 1 | Terminou com ao menos uma tarefa `failed` |
| 4 | 0 | Todas as tarefas `done` |

## 4. `TAREFAS.json`

```json
{
  "tarefas": [
    { "id": "T1", "titulo": "...", "prompt": "...", "depends_on": [], "status": "pending", "tentativas": 0, "critica": false }
  ]
}
```

Status válidos: `pending`, `in_progress`, `done`, `failed`, `hold`. O controlador atualiza o próprio arquivo.

## 5. `.claude/settings.json`

- `permissions.defaultMode`: `"dontAsk"`.
- `allow`: apenas git (`status`, `diff`, `add`, `commit`, `log`), o comando de teste, leitura e edição dentro do repositório. A forma `Bash(x *)` e a forma `Bash(x:*)` são equivalentes.
- `deny`: remoção fora do repo, `Invoke-Expression`, `Start-Process`, `curl`/`Invoke-WebRequest`, `git push`, edição dos arquivos de teste.
- Cuidado obrigatório (ver `REFERENCIA_CLAUDE_CODE.md`, seção 3): em `claude -p`, regras `allow` do `.claude/settings.json` do projeto **não valem** se a pasta não for confiada. O kit precisa resolver isso. Como resolve é avaliado pelo júri.

## 6. `CONTEXTO.md`

Modelo do contexto persistente da supervisora: objetivo, decisões tomadas, regras R1–R7, pendências.

## 7. Testes objetivos

`testes/run-cenarios.ps1` roda 8 cenários contra cada kit, com um Claude simulado. Antes de qualquer kit, `testes/validacao/validar-harness.ps1` prova que o script pontua certo (nulo, oráculo, trapaceiro e mutantes). Execução no GitHub Actions, `windows-latest`, um job por kit, logs públicos.
