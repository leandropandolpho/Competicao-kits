# Especificação — Ponte do lado do PU (modo principal-isolado)

Ato - Autonomous multi-LLM orchestration flow - 130. Especificação SEM código, para aprovação da mesa junto ao aceite
da bateria real 40/40 do embrulho PE (gate-pe @ 8a17270). Base: contrato v0.2 + A111 + PONTE.md atualizado.
Alvo de implementação: novo modo `principal-isolado` em `b05/claude-com-teto.ps1`, acionado por flag de configuração,
com o controlador `7cd7864` INTOCADO (diff vazio). Implementar SÓ após: (a) parecer do 40/40 sem bloqueante material
e (b) aceite desta especificação.

## 1. Objetivo e escopo
Fazer o wrapper do PU (`claude-com-teto.ps1`), em vez de lançar o executor localmente (modelo B-05), **despachar** a
chamada à ponte para o executor rodar sob um principal próprio (PE / exec-piloto) e colher o resultado com segurança.
Duas etapas de validação, nesta ordem:
- **V1 — disparo LOCAL** (esta spec): o PE é o mesmo `acao-pe.ps1`, iniciado como processo comum (sem Tarefa Agendada),
  para exercitar 100% do protocolo IPC/morte/reconciliação sem depender de provisionamento (conta exec-piloto/credencial).
- **V2 — Tarefa Agendada real** (fase seguinte): troca-se o disparo local pela `Start-ScheduledTask` (roteiro v3, DACL do
  Ato 116) quando o exec-piloto for provisionado. Só V2 exige provisionamento/credencial.

## 2. Invariantes (não negociáveis)
- I1. `controlador.ps1` (7cd7864), supervisora (6b45dea) e baseline B-05 (9e6991c) permanecem com diff VAZIO.
- I2. Nada editável pelo PE roda sob o PU. O PU nunca executa o código do repositório produzido pelo executor.
- I3. O razão (reserva, custo, fim) é gravado SÓ pelo PU. O PE escreve apenas na pasta-ponte da execução.
- I4. `fim.flag` NÃO é prova de morte. Toda saída do PE é não confiável até reconferência (R1) e confirmação de morte.
- I5. Falha fecha: qualquer verificação que não complete é tratada como violação (sem commit, reserva mantida).

## 3. Fluxo em 2 fases (transparente ao controlador — Gemini C2)
O controlador chama `-ClaudeCmd` (passo 4) e depois roda `$TestCmd` (passo 6). A ponte atravessa os dois pontos:
- **Fase Executor** (`-ClaudeCmd`): o PU despacha o pedido SEM `test_cmd` (só o executor roda sob o PE), confirma a morte
  do PE, reconfere, reconcilia o custo (stdout.json) no razão e devolve o JSON ao controlador.
- **Fase Teste** (`$TestCmd` → despachante dedicado do PU): aciona a ponte em modo exclusivo de teste, APÓS a morte já
  confirmada do executor; `$TestCmd` roda sob o PE em Low IL, em Job NOVO; exit!=0 → o despachante devolve exit 1 ao
  controlador, que executa o passo 9 (rollback + nova tentativa até `MaxTentativas`). Custo B+K permanece sincronizado.

## 4. Requisitos (cada um com critério de aceite [CA] e teste(s) negativo(s) [TN])
- **REQ-01 — exec_id único + limpeza prévia (CA-9/N11).**
  O PU gera um `exec_id` (GUID) novo por chamada do controlador; cria a pasta-ponte; remove artefatos residuais
  (fim.flag/falhou.flag/exit.code/stdout.json/stderr.txt/pe.pid/teste.txt) antes de gravar `pedido.json`+`go.flag`.
  CA: nunca reutiliza exec_id; nunca lê artefato de uma chamada anterior. TN: pasta-ponte pré-populada com fim.flag/
  stdout.json de outra execução → o PU ignora e falha fechado se o exec_id devolvido não casar.
- **REQ-02 — reserva e rejeição financeira sob o PU (E84-01/F07).**
  O PU grava a reserva no razão ANTES do disparo; ao colher stdout.json, valida `total_cost_usd` (número JSON finito ≥ 0);
  custo inválido → evento `fim` desconhecido + evidência bruta + trava financeira durável + erro 28 ao controlador.
  CA: admissão B+K+R+T(1+F) ≤ M antes do disparo; custo inválido nunca é contabilizado como normal. TN: stdout.json com
  `total_cost_usd` texto/negativo/não-finito → erro 28, reserva mantida, próxima chamada já cai na trava.
- **REQ-03 — morte do PE por SID + PID+criação, ANTES de ler artefatos (P-01, A111-05).**
  Antes de ler stdout.json/teste.txt, o PU confirma via NtQuerySystemInformation que (a) o processo do executor e (b) o
  processo do EMBRULHO (acao-pe) terminaram por PID+criação, e que NENHUM processo com o SID do exec-piloto segue vivo.
  CA: nenhum processo do SID do PE vivo no instante da leitura. TN: um descendente do PE deixado vivo → o PU NÃO lê os
  artefatos, falha fechado (artefato forjável por sobrevivente com o SID).
- **REQ-04 — teste.txt é confiança residual (P-02).**
  `$TestCmd` roda sob o PE, em Low IL, em Job NOVO (não o do executor), só após a morte confirmada do executor; o PU
  confere o carimbo de hora de `teste.txt` (posterior ao fim do Job do executor). Registrar explicitamente como ponto de
  confiança residual. CA: teste.txt mais novo que o fim do executor; Job do teste ≠ Job do executor. TN: teste.txt com
  hora anterior à morte do executor → rejeitado.
- **REQ-05 — limites do Job sem breakaway (P-03).** (já no embrulho, PE-S9) KILL_ON_JOB_CLOSE ligado; BREAKAWAY_OK e
  SILENT_BREAKAWAY_OK desligados. CA: Flags do Job = só KILL_ON_JOB_CLOSE. TN: filho com CREATE_BREAKAWAY_FROM_JOB falha.
- **REQ-06 — terminalidade por EXECUÇÃO, não por tarefa (P-04).**
  `falhou.flag` encerra a execução daquele exec_id; a próxima tentativa do controlador usa um exec_id NOVO (pasta nova),
  logo não é bloqueada. CA: 3 tentativas do controlador = 3 exec_id = 3 pastas; o passo 9 (rollback+retry) funciona. TN:
  reusar o mesmo exec_id após falhou.flag → recusado (força exec_id novo).
- **REQ-07 — varredura de reparse points antes de git (F10).**
  O PU varre a árvore de trabalho por reparse points/junctions (fail-closed) antes de qualquer operação Git. CA: árvore
  sem reparse → segue; TN: junction plantada na árvore baixa → abortar sem commit.
- **REQ-08 — despacho duplo transparente ao controlador (I1).**
  O controlador continua chamando `-ClaudeCmd` e `$TestCmd` exatamente como hoje; a ponte é escolhida por flag de config.
  CA: `git diff 7cd7864 -- controlador.ps1` = vazio. TN: rodar a suíte do controlador congelada no modo ponte sem alterar o controlador.
- **REQ-09 — isolamento da credencial do PE (PE-F11) [depende de provisionamento].**
  Diretório da credencial com rótulo Medium + NO_READ_UP (RotularNRNW); SACL efetiva conferida; sem resíduo recuperável
  da chave no CLAUDE_CONFIG_DIR Low antes do `$TestCmd`. CA: `$TestCmd` (Low IL) não lê a credencial. TN: credencial
  fictícia + `$TestCmd` tentando lê-la → NEGADO.
- **REQ-10 — heartbeat/timeout do PU.**
  O PU monitora `heartbeat` e um prazo máximo; PE travado → o PU encerra por identidade (PID+criação) e falha fechado.
  CA: heartbeat avança durante o trabalho; TN: PE que trava sem heartbeat → o PU encerra e não comita.

## 5. Bateria da ponte (V1 — disparo local), com negativos
PU-01 fluxo feliz 2 fases (executor + teste ok) → razão com custo reconciliado, commit permitido.
PU-02 custo inválido (REQ-02) → erro 28, trava financeira, sem commit.
PU-03 exec_id/limpeza (REQ-01) → artefato residual ignorado; exec_id divergente recusado.
PU-04 sobrevivente com SID do PE (REQ-03) → PU não lê artefatos, falha fechado.
PU-05 teste reprovado (REQ-06/P-04) → falhou.flag por execução; controlador faz rollback+retry com exec_id novo.
PU-06 teste.txt com hora anterior à morte do executor (REQ-04) → rejeitado.
PU-07 reparse na árvore (REQ-07) → aborta sem commit.
PU-08 timeout/heartbeat (REQ-10) → encerra e não comita.
PU-09 diff do controlador vazio (REQ-08) → suíte congelada do controlador passa no modo ponte.

## 6. Pendências que dependem de provisionamento (fase V2 / Leandro)
- Conta exec-piloto (principal separado do PU) e credencial dedicada (ANTHROPIC_API_KEY) — decisão/financeiro do responsável.
- Tarefa Agendada real (roteiro v3, DACL do Ato 116) + desfazer por proveniência (ADM-V5-01, roteiro v3.2).
- REQ-09 (PE-F11) exercido contra o diretório real da credencial.
- Sondas N1–N17 sob dois principais Windows efetivamente separados (exec-piloto vs PU).

## 7. Condições de retomada (Ato 129)
Implementar a ponte (V1) assim que: parecer do 40/40 sem bloqueante material + aceite desta especificação. Mudança
material na interface PU↔PE → arbitragem técnica antes de alterar arquitetura. Deploy operacional, ativação financeira e
execução desassistida permanecem BLOQUEADOS.
