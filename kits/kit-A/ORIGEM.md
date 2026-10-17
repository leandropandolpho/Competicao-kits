# Kit híbrido do piloto (17/10/2026)
- controlador.ps1 e .claude/settings.json: kit-B (sem alteração)
- CONTEXTO.md: kit-C, com 1 frase ajustada (linha 9) para descrever o --settings do controlador do kit-B
- TAREFAS.json: kit-A (sem alteração)
Motivo: falhas de segurança do kit-C confirmadas pelo jurado Kimi (allow de `pwsh -Command *`; executor podia alterar `.claude/` sem detecção).
