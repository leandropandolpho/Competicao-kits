# CONTEXTO PERSISTENTE — Supervisora do piloto

> Atualizar ao fim de cada sessão. A supervisora lê este arquivo ANTES de propor tarefas novas.
> Última atualização: DD/MM/AAAA HH:MM (UTC-4) · por: <LLM, modelo, versão>

## 1. Objetivo
- **Produto:** <o que o repositório entrega, em 1 linha>
- **Meta desta fase:** <resultado verificável — ex.: "calc.ps1 com Soma/Subtrai validadas e testadas">
- **Critério de pronto:** `$TestCmd` sai com 0 no HEAD e todas as tarefas da fase estão `done`.

## 2. Como o piloto roda (não mudar sem decisão registrada)
- Executor: Claude Code headless (`claude -p --output-format json --permission-mode dontAsk`), prompt por stdin.
- Permissões: `.claude/settings.json` do repo, copiado para `$EstadoDir` no início e passado por `--settings`
  (resolve a pasta não confiada sem escrever no repo). Conferir com `/permissions` qual shell ficou ativo.
- Controlador: roda o teste ele mesmo, confere os testes por SHA-256, 1 commit por tarefa (`tarefa <id>: <titulo>`).
- `TAREFAS.json` e `$EstadoDir` ficam FORA do repositório.
- Saída: 0 tudo `done` · 1 alguma `failed` · 2 `hold` · 3 pausa por custo/tempo.

## 3. Regras acatadas pela mesa
- **R1 — Gatilhos críticos → `hold`, sem commit e sem rollback, execução encerrada:** teste alterado/criado/removido;
  caminho com `migration`; `package.json`, `package-lock.json`, `requirements.txt`, `pyproject.toml`;
  exclusão de arquivo rastreado. Precedência sobre o resultado do teste.
- **R2:** <texto acatado pela mesa>
- **R3:** <texto acatado pela mesa>
- **R4:** <texto acatado pela mesa>
- **R5:** <texto acatado pela mesa>
- **R6:** <texto acatado pela mesa>
- **R7 (corrigido):** <texto acatado> — não se aplica ao piloto.

## 4. Decisões tomadas
| Data | Decisão | Motivo | Quem decidiu |
|---|---|---|---|
| DD/MM | Ex.: `deny` de testes espelha `-TestPaths` (`testes/*`) | Barreira dupla (deny + hash) | Leandro |

## 5. Última execução
- Comando: `pwsh -File controlador.ps1 -RepoPath ... -TestPaths 'testes/*' ...`
- Código de saída: <0|1|2|3> · `status_execucao`: <...> · custo acumulado: US$ <...>
- Tarefas: T1 <status/tentativas> · T2 <...> · T3 <...>
- Notificações relevantes (copiar de `notificacoes.txt`): <...>

## 6. Hold em aberto (preencher se saiu com código 2)
- Tarefa / motivo do gatilho: <...>
- Evidência (`git -C <repo> diff`): <resumo>
- Decisão humana: [ ] aceitar a mudança  [ ] descartar (`git reset --hard` + `git clean -fd`)  [ ] reescrever a tarefa
- Depois: mudar o status da tarefa em `TAREFAS.json` e rodar de novo.

## 7. Pendências
- [ ] <pendência> — dono: <...> — prazo: <...>
- [ ] Conferir, no Windows, `/permissions` com o settings passado por `--settings`.
