# REFERÊNCIA VERIFICADA — Claude Code (outubro/2026)

> **STATUS: RASCUNHO NÃO CONGELADO — v0.1 — 15/10/2026**
> Levantada por Claude (Anthropic · Claude Opus 5.5) na documentação oficial em 15/10/2026. Os jurados podem e devem contestar qualquer item com fonte.

## 1. Modo headless
- `claude -p "<prompt>"` roda sem interface. Sai com código 0 no sucesso e diferente de zero na falha; falhas dentro da execução aparecem como resultado na saída padrão. — [headless](https://code.claude.com/docs/en/headless.md)
- `--output-format json` devolve JSON com `result`, `session_id` e metadados, incluindo `total_cost_usd`. O custo é **estimativa do lado do cliente** e pode diferir da cobrança real. — [headless](https://code.claude.com/docs/en/headless.md)
- Encerrado por SIGTERM, sai com código 143 e encerra a árvore de processos dos comandos Bash em andamento. — [headless](https://code.claude.com/docs/en/headless.md)
- `--bare` pula hooks, skills, CLAUDE.md, plugins e `.mcp.json` do projeto, mas **não usa o login da assinatura**: exige `ANTHROPIC_API_KEY`. — [headless](https://code.claude.com/docs/en/headless.md)
- `--permission-prompts none` (v2.1.259+) avisa o Claude de que ninguém pode aprovar e para ele não insistir. — [headless](https://code.claude.com/docs/en/headless.md)

## 2. Modos de permissão
- Modos: `default` (Manual), `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`. — [permission-modes](https://code.claude.com/docs/en/permission-modes.md)
- **`dontAsk`**: nega automaticamente tudo o que pediria aprovação. Roda só leituras na pasta de trabalho, comandos somente-leitura embutidos e o que estiver em `permissions.allow` ou `--allowedTools`. Não aparece no ciclo Shift+Tab; usa-se `--permission-mode dontAsk`. — [permission-modes](https://code.claude.com/docs/en/permission-modes.md)
- O modo inicial de `claude -p` pode ser `default` ou `auto`, conforme versão e conta. **Por isso o kit deve passar o modo explicitamente.** — [permission-modes](https://code.claude.com/docs/en/permission-modes.md)
- `defaultMode` no `.claude/settings.json` do projeto vale para todos os modos, exceto `auto` e `bypassPermissions`. — [permission-modes](https://code.claude.com/docs/en/permission-modes.md)
- `--dangerously-skip-permissions` equivale a `bypassPermissions`; indicado só em container ou VM isolados. — [permission-modes](https://code.claude.com/docs/en/permission-modes.md)
- Escrita em caminhos protegidos (`.git`, `.claude`, `.vscode` etc.) é **negada** em `dontAsk`. — [permission-modes](https://code.claude.com/docs/en/permission-modes.md)

## 3. Ponto crítico: confiança da pasta em `claude -p`
- Regras `permissions.allow` do `.claude/settings.json` do projeto **não são aplicadas** em `claude -p` numa pasta nunca confiada; o Claude Code avisa no stderr. Regras `deny` e `ask` continuam valendo. — [permissions](https://code.claude.com/docs/en/permissions.md)
- Hooks do `.claude/settings.json` do projeto **rodam** em `claude -p` mesmo sem confiança. — [headless](https://code.claude.com/docs/en/headless.md)
- Saídas possíveis: passar as regras por `--settings <arquivo>` ou `--allowedTools`; ou marcar a pasta como confiada em `~/.claude.json` (`projects["<raiz>"].hasTrustDialogAccepted = true`). — [permissions](https://code.claude.com/docs/en/permissions.md)

## 4. Sintaxe das regras
- Formato `Ferramenta(especificador)`. Precedência: **deny → ask → allow**; a primeira que casa decide. — [permissions](https://code.claude.com/docs/en/permissions.md)
- Bash: `Bash(npm run *)`; o espaço antes do `*` importa (`Bash(ls *)` não casa `lsof`). — [permissions](https://code.claude.com/docs/en/permissions.md)
- PowerShell: mesma forma, `PowerShell(Get-ChildItem *)`; aliases são normalizados e a comparação ignora maiúsculas. — [permissions](https://code.claude.com/docs/en/permissions.md)
- Arquivos: `Edit(caminho)` e `Read(caminho)` no padrão gitignore. `/caminho` é relativo à origem do arquivo de settings; `//caminho` é absoluto. No Windows, caminhos viram forma POSIX (`C:\Users` → `/c/Users`). Regras `Write(...)` não são consultadas: use `Edit(...)`. — [permissions](https://code.claude.com/docs/en/permissions.md)
- **Regras de Bash/PowerShell não são barreira de segurança**: `Bash(rm *)` não pega `/bin/rm` nem `bash -c 'rm …'`. A proteção real é a verificação externa do controlador. — [permissions](https://code.claude.com/docs/en/permissions.md)

## 5. Windows
- Ferramenta PowerShell: ativada automaticamente sem Git Bash; com Git Bash, ligada por padrão em contas claude.ai e Console (`CLAUDE_CODE_USE_POWERSHELL_TOOL=0` desliga). — [tools-reference](https://code.claude.com/docs/en/tools-reference.md)
- **Sandbox não é suportado no Windows nativo** (só macOS, Linux e WSL2). — [tools-reference](https://code.claude.com/docs/en/tools-reference.md), [permission-modes](https://code.claude.com/docs/en/permission-modes.md)
- `Remove-Item` em caminhos de sistema ou com curinga final é negado em qualquer modo. — [permission-modes](https://code.claude.com/docs/en/permission-modes.md)

## 6. Consequência para o controlador (não é regra do Claude Code, é conclusão)
- Encerrar o executor por timeout exige matar a **árvore** de processos (por exemplo `Process.Kill($true)` no .NET, ou `taskkill /T /F /PID`), porque no Windows o `claude` pode ser um `.cmd` (instalação via npm) que inicia outros processos, e o próprio executor inicia comandos filhos.
