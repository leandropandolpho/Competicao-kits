# REFERÊNCIA VERIFICADA — Claude Code (outubro/2026)

> **STATUS: CANDIDATA AO CONGELAMENTO — v0.2.2 — 16/10/2026** (v0.2 aprovada por Kimi e Le Chat/Vibe; esta versão aplica os ajustes finais dos jurados e a correção do defeito A4 apontado pelo Perplexity)
> Levantada por Claude (Anthropic · Claude Opus 5.5) na documentação oficial, reconferida em 15/10/2026. Os jurados podem e devem contestar qualquer item com fonte.
> Na v0.1, o Kimi não encontrou três itens (`--permission-prompts`, `--bare` sem login da assinatura, SIGTERM/143). Foram reconferidos na página `headless.md` nas seções indicadas abaixo; o Perplexity também os confirmou.

## 1. Modo headless — [headless](https://code.claude.com/docs/en/headless.md)
- `claude -p "<prompt>"` roda sem interface. Sai com código 0 no sucesso e diferente de zero na falha; falhas dentro da execução aparecem como resultado na saída padrão. (seção "Basic usage")
- O modo não interativo lê a entrada padrão (stdin): `cat arquivo | claude -p "..."`. (seção "Pipe data through Claude")
- `--output-format json` devolve JSON com `result`, `session_id` e metadados, incluindo `total_cost_usd`, que é **estimativa do lado do cliente**. (mesma seção)
- Encerrado por SIGTERM, sai com código 143 e encerra a árvore de processos dos comandos Bash em andamento. (seção "Stop a run with SIGTERM")
- `--bare` pula hooks, skills, CLAUDE.md, plugins e `.mcp.json`, e **não usa o login da assinatura**: exige `ANTHROPIC_API_KEY` ou um `apiKeyHelper` passado em `--settings`. (seção "Start faster with bare mode")
- `--permission-prompts none` (v2.1.259+) avisa o Claude de que ninguém pode aprovar e para não insistir. (seção "Turn off permission prompts in unattended runs")

## 2. Modos de permissão — [permission-modes](https://code.claude.com/docs/en/permission-modes.md)
- Modos: `default` (Manual), `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`.
- **`dontAsk`**: nega automaticamente tudo o que pediria aprovação. Roda só leituras na pasta de trabalho, comandos somente-leitura embutidos e o que estiver em `permissions.allow` ou `--allowedTools`. Não aparece no ciclo Shift+Tab; usa-se `--permission-mode dontAsk`.
- O modo inicial de `claude -p` depende de a sessão buscar *feature flags* (e da versão): pode ser `default` ou `auto`. **Por isso o kit deve passar o modo explicitamente.**
- `defaultMode` no `.claude/settings.json` do projeto vale para todos os modos, exceto `auto` e `bypassPermissions`.
- `--dangerously-skip-permissions` equivale a `bypassPermissions`; indicado só em container ou VM isolados.
- Escrita em caminhos protegidos (`.git`, `.claude`, `.vscode` etc.) é **negada** em `dontAsk`.

## 3. Ponto crítico: confiança da pasta em `claude -p` — [permissions](https://code.claude.com/docs/en/permissions.md)
- Regras `permissions.allow` do `.claude/settings.json` do projeto **não são aplicadas** em `claude -p` numa pasta nunca confiada; o Claude Code avisa no stderr. Regras `deny` e `ask` continuam valendo.
- Hooks do `.claude/settings.json` do projeto **rodam** em `claude -p` mesmo sem confiança. ([headless](https://code.claude.com/docs/en/headless.md), seção "Start faster with bare mode")
- Saídas documentadas: (a) passar as regras por `--settings <arquivo>` ou (b) `--allowedTools`; (c) marcar a pasta como confiada em `~/.claude.json` (`projects["<raiz>"].hasTrustDialogAccepted = true`); (d) colocar as regras num `.claude/settings.local.json` **não rastreado pelo git**, que em `-p` é aplicado após a checagem do git (seção "When your local settings file needs trust").

## 4. Sintaxe das regras — [permissions](https://code.claude.com/docs/en/permissions.md)
- Formato `Ferramenta(especificador)`. Precedência: **deny → ask → allow**; a primeira que casa decide.
- Bash: `Bash(npm run *)`; o espaço antes do `*` importa (`Bash(ls *)` não casa `lsof`). A forma `Bash(ls:*)` é equivalente a `Bash(ls *)`.
- PowerShell: mesma forma, `PowerShell(Get-ChildItem *)`; aliases são normalizados e a comparação ignora maiúsculas.
- Arquivos: `Edit(caminho)` e `Read(caminho)` no padrão gitignore. `/caminho` é relativo à origem do arquivo de settings; `//caminho` é absoluto. No Windows, caminhos viram forma POSIX (`C:\Users` → `/c/Users`). Regras `Write(...)` não são consultadas: use `Edit(...)`.
- **Regras de Bash/PowerShell não são barreira de segurança**: `Bash(rm *)` não pega `/bin/rm` nem `bash -c 'rm …'`. A proteção real é a verificação externa do controlador.

## 5. Windows — [tools-reference](https://code.claude.com/docs/en/tools-reference.md)
- Ferramenta PowerShell: ativada automaticamente sem Git Bash; com Git Bash, ligada por padrão em contas claude.ai e Console. `CLAUDE_CODE_USE_POWERSHELL_TOOL=0` desliga, `=1` liga. Texto da doc: "On Windows, set the variable to `0` to turn the tool off." (seção "Enable the PowerShell tool").
- **Sandbox não é suportado no Windows nativo** (seção "Preview limitations"; ver também [permission-modes](https://code.claude.com/docs/en/permission-modes.md)).
- **Ponto em disputa, não confirmado:** o Perplexity afirma que a página tools-reference tem uma seção "Bash deny rules also turn off the PowerShell tool", segundo a qual, no Windows com Git Bash, até um deny com escopo (ex.: `Bash(git push *)`) desliga a ferramenta PowerShell. Em 16/10/2026, a página entregue ao Claude não tinha essa seção (as seções da ferramenta PowerShell eram "Enable the PowerShell tool", "Shell selection…", "Windows encoding and exit codes" e "Preview limitations"). Consequência neutra para todos: os jurados **não** penalizam denies de shell escritos como `Bash(...)` nem como `PowerShell(...)`, e o piloto deve conferir com `/permissions` qual ferramenta de shell ficou ativa.
- `Remove-Item` em caminhos de sistema ou com curinga final é negado em qualquer modo. Texto da doc: "**System paths**: … Claude Code denies the command in every mode, without asking you." e "**Wildcards**: a bare `*`, or any target ending in `/*` or `\*` … Claude Code denies the command in every mode, without asking you". Com `-Recurse` na pasta de trabalho ou numa pasta acima dela, é negado em `dontAsk`. ([permission-modes](https://code.claude.com/docs/en/permission-modes.md), seção "Remove-Item in PowerShell")

## 6. Consequências para o controlador (conclusões, não regras do Claude Code)
- Encerrar o executor por timeout exige matar a **árvore** de processos (`Process.Kill($true)` no .NET, ou `taskkill /T /F /PID`): no Windows o `claude` pode ser um `.cmd` (instalação via npm) que inicia outros processos, e o executor inicia comandos filhos.
- Um `.cmd` corta quebras de linha nos argumentos: prompts com várias linhas devem ir por stdin.
