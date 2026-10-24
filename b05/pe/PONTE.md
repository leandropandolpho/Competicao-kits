# Ponte PU <-> PE (gate de isolamento de principal)

Contrato de IPC por arquivos entre o controlador (PU) e o executor sob principal proprio (PE).
Ato - Autonomous multi-LLM orchestration flow - 128. Base: contrato v0.2 + Adendo A111. Controlador 7cd7864 congelado.
Atualizado apos PE-F01..F12 (Atos 122/125/127) e a bateria real 38/38 (evidencia 091).

## Principio
- O PE NUNCA escreve no estado do PU (EstadoDir, TAREFAS.json, razao). So escreve na pasta-ponte da execucao.
- Toda saida do PE e NAO confiavel ate o PU reconferir (hashes/R1) e confirmar a morte do PE.
- fim.flag NAO e prova de morte. O PU confirma independentemente, por PID+criacao (NtQuerySystemInformation), que
  (a) o processo do executor e (b) o processo do EMBRULHO (acao-pe) terminaram, e que NENHUM processo com o SID do
  exec-piloto segue vivo (P-01), ANTES de ler stdout.json/teste.txt — artefatos escritos pela identidade do PE sao
  forjaveis por qualquer sobrevivente com esse SID.
- O razao (reserva, custo, fim) e gravado SO pelo PU (E107-01). O PE devolve stdout/exit; o PU contabiliza.

## Nivel de integridade dos artefatos (Gemini 2.1 / CA-9 / N11)
- Metadados de controle do IPC (pe.pid, exit.code, teste.txt, fim.flag) ficam em Medium IL (rotulo padrao do PE) — o
  filho em Low IL (4096) nao pode forja-los (NO_WRITE_UP).
- So a E/S bruta redirecionada (in/out/err) e a arvore de trabalho ficam em Low IL (icacls no diretorio temporario).

## Pasta-ponte por execucao
`<PonteDir>\<exec.id>\`  (exec.id = GUID de 32 hex). ACL: PU controle total; PE Modificar so nesta pasta.
O PU gera um exec_id NOVO por chamada do controlador e limpa artefatos residuais (fim.flag/falhou.flag/exit.code/
stdout.json/pe.pid) antes de gravar o pedido (correlacao inforjavel por chamada).

| Arquivo        | Escreve | Le  | Conteudo |
|----------------|---------|-----|----------|
| `prompt.in`    | PU      | PE  | stdin da tarefa (prompt do executor), UTF-8 |
| `pedido.json`  | PU      | PE  | { exec_id, executor, executor_prefixo, test_cmd, teto_usd, pwsh_sha256, criado_em } |
| `go.flag`      | PU      | PE  | marca que o pedido esta completo (PE so age quando existe) |
| `heartbeat`    | PE      | PU  | epoch ms atualizado pelo PE enquanto trabalha (PU detecta travamento) |
| `stdout.json`  | PE      | PU  | saida bruta do executor (JSON do claude -p). NAO confiavel ate conferencia |
| `stderr.txt`   | PE      | PU  | stderr do executor |
| `exit.code`    | PE      | PU  | codigo de saida do executor (inteiro) |
| `pe.pid`       | PE      | PU  | { pid, criacao_utc, nivel_il, em_job } do EXECUTOR (nao do embrulho) |
| `teste.txt`    | PE      | PU  | resultado do $TestCmd (apos o executor morto, em instancia/Job separados). Confianca residual (ver abaixo) |
| `fim.flag`     | PE      | PU  | { exec_id, pe_pid, codigo, fim_utc } — sinal de termino, NAO prova de morte |
| `falhou.flag`  | PE      | PU  | estado TERMINAL de erro desta execucao (PE-F05). Nao bloqueia nova tentativa do controlador (novo exec_id) |

## Sequencia
1. PU: gera exec_id novo, cria `<PonteDir>\<exec.id>\`, limpa residuos, grava `prompt.in` + `pedido.json`, depois `go.flag`.
2. PU: dispara a tarefa do PE (Start-ScheduledTask) OU o PE ja esta em laco (-Laco) observando a pasta.
3. PE (acao-pe.ps1): ve `go.flag`, le o pedido. O proprio acao-pe NAO entra no Job (sobrevive a timeouts para marcar
   estado terminal). Cria o PROPRIO Job do executor (KILL_ON_JOB_CLOSE; UI restrita com retorno conferido, PE-F12; SEM
   BREAKAWAY_OK/SILENT_BREAKAWAY_OK, P-03). Lanca o executor em baixa integridade SUSPENSO (CREATE_SUSPENDED, PE-F07),
   associa-o ao Job com retorno OBRIGATORIO, confirma em_job, rastreia (fail-closed, PE-F10) e SO ENTAO retoma
   (ResumeThread) — nenhuma instrucao roda fora do Job. Confere nivel 4096; grava `pe.pid`; espera com distincao
   sinal/codigo (PE-F01); grava stdout/stderr/exit.
4. PE: Verificar(job) real — nenhum descendente rastreado vivo FORA do job (fail-closed). Varre reparse points
   (fail-closed). Roda `$TestCmd` sob o PE, em Low IL, num Job NOVO e SO depois de o executor estar morto (P-02/N14),
   SEM a ANTHROPIC_API_KEY no ambiente (Gemini 2.2/T7); teste exit!=0 = estado terminal sem fim.flag (PE-F09); grava
   `teste.txt`. Encerra o Job da execucao (TerminateJobObject + CloseHandle) ANTES de sinalizar (PE-F08) e grava `fim.flag`.
5. PU: ve `fim.flag`, confirma por PID+criacao que o EXECUTOR e o EMBRULHO morreram e que nenhum processo com o SID do
   exec-piloto segue vivo (P-01); reconfere hashes (R1); valida o custo (E84-01, rejeicao previa de custo invalido = 28);
   so entao grava o razao e decide commit/rollback. Nada editavel pelo PE roda sob o PU.

## Garantias reconstruidas sob o PE (E107-01 / CA-8) — bateria real 38/38 (091)
- Job proprio KILL_ON_JOB_CLOSE, sem breakaway; executor nivel 4096; em_job confirmado ANTES de executar (PE-F07).
- Sem orfaos: Verificar(job) + teardown por execucao (TerminateJobObject/CloseHandle), independente de -Laco (PE-F08).
  Provado por PID+criacao apos encerramento normal/falha/timeout (PE-R4a/b/c).
- Identidade por PID+criacao (NtQuerySystemInformation) entre usuarios diferentes; rastreamento fail-closed (PE-F10).
- Varredura fail-closed de reparse points; timeout proprio mata o Job (nao depende de Stop-ScheduledTask, A111-02).
- ADM-V5-02/PE-F06: executor/pwsh APROVADO e acessivel, com SHA-256 OBRIGATORIO conferido antes de rodar.
- $TestCmd: terminal em exit!=0 (PE-F09); sem chave no ambiente (T7).

## Pendencias da ponte do PU (proxima fase; nao bloqueiam o embrulho)
- P-01: confirmacao de morte por SID (nenhum processo do exec-piloto vivo) + PID+criacao do executor E do embrulho.
- P-02: teste.txt e confianca residual — mitigado por P-01 + teste apos o fim do Job do executor (hora conferida pelo
  PU) + Job NOVO para o teste. Registrar explicitamente como ponto de confianca residual.
- P-04: PE-F09 "terminal" vale por EXECUCAO; o controlador 7cd7864 segue o passo 9 (rollback + nova tentativa ate
  MaxTentativas) com exec_id novo — falhou.flag de uma execucao nao bloqueia a proxima.
- Despacho em 2 fases (Gemini C2): fase executor (-ClaudeCmd, sem teste) reconcilia custo e devolve JSON; fase teste
  (-TestCmd) aciona a ponte em modo exclusivo de teste apos a morte confirmada do executor.
- PE-F11: diretorio da credencial do PE com rotulo Medium + NO_READ_UP (RotularNRNW), SACL efetiva conferida, teste
  negativo com credencial ficticia e verificacao de residuo no CLAUDE_CONFIG_DIR Low antes do $TestCmd — junto ao
  provisionamento do exec-piloto (roteiro v3.2).
