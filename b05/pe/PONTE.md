# Ponte PU <-> PE (gate de isolamento de principal)

Contrato de IPC por arquivos entre o controlador (PU) e o executor sob principal proprio (PE).
Ato - Autonomous multi-LLM orchestration flow - 121. Base: contrato v0.2 + Adendo A111. Controlador 7cd7864 congelado.

## Principio
- O PE NUNCA escreve no estado do PU (EstadoDir, TAREFAS.json, razao). So escreve na pasta-ponte da execucao.
- Toda saida do PE e NAO confiavel ate o PU reconferir (hashes/R1) e confirmar a morte do PE por PID+criacao (A111-05).
- O razao (reserva, custo, fim) e gravado SO pelo PU (E107-01). O PE devolve stdout/exit; o PU contabiliza.

## Pasta-ponte por execucao
`<PonteDir>\<exec.id>\`  (exec.id = GUID de 32 hex). ACL: PU controle total; PE Modificar so nesta pasta.

| Arquivo        | Escreve | Le  | Conteudo |
|----------------|---------|-----|----------|
| `prompt.in`    | PU      | PE  | stdin da tarefa (prompt do executor), UTF-8 |
| `pedido.json`  | PU      | PE  | { exec_id, executor, executor_prefixo, test_cmd, teto_usd, pwsh_sha256, criado_em } |
| `go.flag`      | PU      | PE  | marca que o pedido esta completo (PE so age quando existe) |
| `heartbeat`    | PE      | PU  | epoch ms atualizado pelo PE enquanto trabalha (PU detecta travamento) |
| `stdout.json`  | PE      | PU  | saida bruta do executor (JSON do claude -p). NAO confiavel ate conferencia |
| `stderr.txt`   | PE      | PU  | stderr do executor |
| `exit.code`    | PE      | PU  | codigo de saida do executor (inteiro) |
| `pe.pid`       | PE      | PU  | { pid, criacao_utc, nivel_il, em_job } do processo do executor (p/ o PU confirmar morte) |
| `teste.txt`    | PE      | PU  | resultado do $TestCmd rodado sob o PE (apos o executor morrer) |
| `fim.flag`     | PE      | PU  | marca que o PE terminou e nenhum processo do PE segue vivo |

## Sequencia
1. PU: cria `<PonteDir>\<exec.id>\`, grava `prompt.in` + `pedido.json`, depois `go.flag`.
2. PU: dispara a tarefa do PE (Start-ScheduledTask) OU o PE ja esta em laco observando a pasta.
3. PE (acao-pe.ps1): ve `go.flag`, le o pedido, cria o PROPRIO Job (KILL_ON_JOB_CLOSE) e se associa; roda o executor
   em baixa integridade DENTRO do job; confirma em_job e nivel 4096; grava `pe.pid`; espera; grava stdout/stderr/exit.
4. PE: confirma que nenhum descendente escapou (Subarvore); varre reparse points; roda `$TestCmd` sob o PE numa
   instancia separada, SO depois de o executor estar morto (E105-01/N14); grava `teste.txt`; grava `fim.flag`.
5. PU: ve `fim.flag`, confirma pela identidade (PID+criacao) que o processo do PE morreu (A111-05), reconfere hashes (R1),
   valida o custo (E84-01) e so entao grava o razao e decide commit/rollback. Nada editavel pelo PE roda sob o PU.

## Garantias herdadas do B-05, reconstruidas sob o PE (E107-01 / CA-8)
- Job Object proprio com KILL_ON_JOB_CLOSE; executor em nivel 4096; em_job verdadeiro; sem orfaos (Subarvore vazia).
- Identidade por PID+criacao (NtQuerySystemInformation) entre usuarios diferentes.
- Varredura fail-closed de reparse points antes de devolver.
- Timeout proprio: o PE mata o job (TerminateJobObject) ao estourar; nao depende de Stop-ScheduledTask (A111-02).
- ADM-V5-02: o executor/pwsh e um binario APROVADO, acessivel ao PE, com SHA-256 conferido antes de rodar.
