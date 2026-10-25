# Especificação — Ponte do lado do PU (modo principal-isolado) — v2 consolidada

Ato - Autonomous multi-LLM orchestration flow - 135. Consolida as emendas aprovadas pela mesa (Atos 131-134):
S-01..S-04 (Ato 132), P-A..P-D (Ato 133) e as 2 precisoes do ChatGPT (Ato 134). Versao original preservada no
historico git (gate-pe @ 7ce759a). Alvo: novo modo `principal-isolado` em `b05/claude-com-teto.ps1` + despachante do PU,
com o controlador `7cd7864` INTOCADO (diff vazio). Retomada automatica ACIONADA (Ato 129/134): implementar V1 (disparo
local) e rodar PU-01..PU-12 sem nova autorizacao; mudanca arquitetural ou de fronteira de seguranca volta a mesa antes.

Correcao de registro (Ato 133/134): PE-F11 (isolamento da credencial) permanece ABERTO — a bateria 40/40 (092, um
principal `piloto`) NAO o demonstra. PE-F11 e a contencao entre dois principais Windows ficam para a V2/provisionamento.

## 1. Objetivo e escopo
Fazer o wrapper do PU (`claude-com-teto.ps1`) despachar a chamada do executor para rodar sob um principal proprio (PE)
e colher o resultado com seguranca, em vez de lancar localmente (modelo B-05). Duas etapas:
- V1 — disparo LOCAL (esta spec): o PE e o mesmo `acao-pe.ps1`, iniciado como processo comum (sem Tarefa Agendada),
  exercitando 100% do protocolo IPC/morte/reconciliacao sem provisionamento. Identidade por subarvore (PID+criacao).
- V2 — Tarefa Agendada real (fase seguinte, exige provisionamento): identidade por SID do exec-piloto; encerramento por
  Stop-ScheduledTask/timeout do Job; PE-F11 exercido contra o diretorio real da credencial.

## 2. Invariantes (nao negociaveis)
- I1. controlador.ps1 (7cd7864), supervisora (6b45dea) e baseline B-05 (9e6991c) com diff VAZIO.
- I2. Nada editavel pelo PE roda sob o PU. O PU nunca executa o codigo do repositorio produzido pelo executor; o
  despachante do PU nao importa nada da arvore de trabalho (P-B).
- I3. O razao (reserva, custo, fim) e gravado SO pelo PU. O PE escreve apenas na pasta-ponte da execucao.
- I4. fim.flag NAO e prova de morte. Toda saida do PE e nao confiavel ate reconferencia (R1) e confirmacao de morte.
- I5. Falha fecha: qualquer verificacao que nao complete e violacao (sem commit, reserva mantida).

## 3. Fluxo em 2 fases (transparente ao controlador — Gemini C2)
- Fase Executor (`-ClaudeCmd`): o PU despacha o pedido SEM test_cmd; confirma a morte do PE; varre reparse (apos a morte,
  imediatamente antes de retornar — P-A); reconcilia o custo (stdout.json) no razao; devolve o JSON ao controlador.
- Fase Teste (`$TestCmd` -> despachante dedicado do PU): aciona a ponte em modo exclusivo de teste, APOS a morte
  confirmada do executor; $TestCmd roda sob o PE em Low IL, em Job NOVO; exit!=0 -> despachante devolve exit 1 ao
  controlador (passo 9: rollback + nova tentativa ate MaxTentativas). Custo B+K sincronizado.

## 4. Requisitos (cada um com criterio de aceite [CA] e teste(s) negativo(s) [TN])
- REQ-01 — exec_id unico + limpeza previa (CA-9/N11). PU gera exec_id (GUID) novo por chamada; cria a pasta-ponte;
  remove residuos antes de gravar pedido.json+go.flag. CA: nunca reutiliza exec_id nem le artefato de chamada anterior.
  TN: pasta pre-populada -> ignora e falha fechado se o exec_id devolvido nao casar.
- REQ-02 — reserva e rejeicao financeira sob o PU (E84-01/F07). Reserva ANTES do disparo; valida total_cost_usd (numero
  JSON finito >= 0); invalido -> fim desconhecido + evidencia bruta + trava financeira (infra comum do REQ-11, codigo
  proprio) + erro 28. CA: admissao B+K+R+T(1+F) <= M antes do disparo. TN: custo texto/negativo/nao-finito -> 28.
- REQ-03 — morte do PE ANTES de ler artefatos (P-01/S-04/A111-05). Fonte inforjavel; classificacao inconclusiva BLOQUEIA.
  - V1 (disparo local): o PU confirma, por NtQuerySystemInformation (PID+criacao), que toda a SUBARVORE enraizada no
    acao-pe (o processo do embrulho, o executor e descendentes) terminou. Teste negativo usa um marcador de processo
    simulado do PE para distinguir da sessao do proprio PU.
  - V2 (dois principais): identidade por SID do exec-piloto. NtQuerySystemInformation(SystemProcessInformation) NAO
    fornece o SID sozinho; usar fonte capaz (ex.: WTSEnumerateProcesses/consulta de token quando permitido). Sem
    classificacao confiavel por SID -> bloqueia.
- REQ-04 — confianca do teste.txt ancorada na INTEGRIDADE (S-03), nao no timestamp. CA: pasta-ponte e teste.txt em
  Medium IL (metadados protegidos contra escrita por codigo Low). TN: o codigo do teste (Low) tenta (a) escrever em
  teste.txt/pasta-ponte e (b) acesso perigoso ao processo supervisor (PROCESS_VM_WRITE/PROCESS_CREATE_THREAD) -> NEGADO
  (nao a negacao indiscriminada de consulta limitada). O timestamp (regra `>=`, alta resolucao) e evidencia complementar.
- REQ-05 — limites do Job sem breakaway (P-03) [embrulho, PE-S9]. KILL_ON_JOB_CLOSE ligado; BREAKAWAY_OK e
  SILENT_BREAKAWAY_OK desligados. TN: filho com CREATE_BREAKAWAY_FROM_JOB falha.
- REQ-06 — terminalidade por EXECUCAO, nao por tarefa (P-04). falhou.flag encerra aquele exec_id; a proxima tentativa
  do controlador usa exec_id NOVO (pasta nova), nao e bloqueada. TN: reusar exec_id apos falhou.flag -> recusado.
- REQ-07 — varredura de reparse points fail-closed (F10/P-A). QUANDO: depois da morte confirmada (REQ-03) e
  imediatamente antes de devolver o controle ao controlador, nas duas fases. A preservacao de evidencia (REQ-11) ocorre
  apos esta varredura e NAO atravessa reparse points. TN: junction na arvore -> aborta sem commit.
- REQ-08 — despacho duplo transparente ao controlador (I1). O controlador continua chamando -ClaudeCmd e $TestCmd; a
  ponte e escolhida por flag de config. CA: git diff 7cd7864 -- controlador.ps1 = vazio. TN: suite congelada do
  controlador passa no modo ponte (incluir C4 trava/timeout e C6 controlador morto — P-C).
- REQ-09 — isolamento da credencial do PE (PE-F11) [ABERTO; depende de provisionamento, V2]. Diretorio da credencial
  com rotulo Medium + NO_READ_UP (RotularNRNW); SACL conferida; sem residuo recuperavel no CLAUDE_CONFIG_DIR Low antes
  do $TestCmd. CA: $TestCmd (Low) nao le a credencial. TN: credencial ficticia + $TestCmd lendo-a -> NEGADO.
- REQ-10 — heartbeat/timeout do PU (S-02). Prazo da ponte < TimeoutSec do controlador, com margem declarada; o PU
  monitora heartbeat. V1: o PU encerra a subarvore por PID+criacao e falha fechado. V2: o PU NAO tem PROCESS_TERMINATE
  sobre o outro usuario — encerramento por Stop-ScheduledTask/timeout do Job do acao-pe; o PU so CONFIRMA a morte.
- REQ-11 — violacao de seguranca != falha comum (S-01/P-D). Em violacao (REQ-03 sobrevivente, REQ-07 reparse, REQ-04
  rejeitado): (1) o PU copia arvore+artefatos para pasta de EVIDENCIA fora do repo ANTES de devolver o controle, sem
  atravessar reparse points (so apos a varredura do REQ-07); (2) grava trava PERSISTENTE -> chamadas seguintes falham
  sem despachar; (3) notifica. Codigos de saida SEPARADOS: falha comum -> retry (passo 9); violacao -> trava, tarefa
  termina `failed`. Infra de trava compartilhada com o REQ-02, causas/codigos distintos (financeiro vs seguranca).
- REQ-12 — sobrevivente ao timeout do controlador (S-02). (1) prazo da ponte < TimeoutSec com margem; (2) PRE-FLIGHT em
  TODA chamada (executor e teste): nenhum PE vivo de execucao anterior — senao encerra (V1) / Stop-ScheduledTask +
  confirma (V2) ANTES de despachar; (3) intertravamento/supervisao independente que impeca git/rollback enquanto um PE
  anterior puder escrever, inclusive apos morte abrupta do controlador. TN: matar o claude-com-teto no meio -> a proxima
  chamada encerra o PE anterior antes de disparar; nenhuma escrita apos o rollback.

## 5. Despachante da Fase Teste (P-B)
Script separado, fora do repositorio (pasta do PU; o PE so le/executa), com SHA-256 conferido (como o pwsh, ADM-V5-02);
nao importa nada da arvore de trabalho. Reforca I2.

## 6. Bateria da ponte (V1 — disparo local), com negativos
- PU-01 fluxo feliz 2 fases -> razao reconciliado, commit permitido.
- PU-02 custo invalido (REQ-02) -> erro 28, trava financeira, sem commit.
- PU-03 exec_id/limpeza (REQ-01) -> residuo ignorado; exec_id divergente recusado.
- PU-04 sobrevivente na subarvore do PE (REQ-03 V1) -> PU nao le artefatos, falha fechado.
- PU-05 teste reprovado (REQ-06/P-04) -> falhou.flag por execucao; retry com exec_id novo.
- PU-06 teste.txt forjado/antigo (REQ-04) -> rejeitado (ancora = IL; timestamp complementar `>=`).
- PU-07 reparse na arvore (REQ-07) -> aborta sem commit; varredura apos morte e antes do retorno.
- PU-08 timeout/heartbeat (REQ-10) -> encerra e nao comita.
- PU-09 diff do controlador vazio (REQ-08) -> suite congelada passa no modo ponte (inclui C4 e C6).
- PU-10 violacao (REQ-11) -> evidencia fora do repo ANTES do retorno; 2a tentativa NAO dispara o PE (trava).
- PU-11 morte abrupta do controlador (REQ-12) -> proxima chamada encerra o PE anterior antes de disparar; sem escrita
  apos rollback (cobre C4/C6).
- PU-12 fronteira de IL (REQ-04/S-03) -> codigo Low nao escreve em teste.txt/pasta-ponte nem faz acesso perigoso ao
  processo supervisor (PROCESS_VM_WRITE/PROCESS_CREATE_THREAD) -> NEGADO.

## 7. Pendencias que dependem de provisionamento (fase V2 / Leandro)
- Conta exec-piloto (principal separado) e credencial dedicada — decisao/financeiro do responsavel.
- Tarefa Agendada real (roteiro v3.2 reverificado; NAO rodar v3 nem v3.1) + desfazer por proveniencia (ADM-V5-01).
- REQ-09 (PE-F11) e REQ-03/REQ-10 no modo V2 (SID; encerramento sem PROCESS_TERMINATE); contencao entre dois principais.
- Sondas N1-N17 sob dois principais Windows efetivamente separados.

## 8. Pacote de auditoria exigido ao fim da V1 (Ato 134)
Commit + hashes dos arquivos sob teste; provas negativas (PU-02..PU-13); diffs; e pendencias explicitas da V2.
Cada teste negativo COMPROVA a tentativa (comando/operacao, PID, identidade, IL quando aplicavel, resultado e o erro
efetivo devolvido pelo Windows). Verde sem tentativa comprovada NAO e aprovacao. A V1 nao e declarada apta so por
bateria verde: exige reconciliacao de evidencias e objecoes materiais (decisao tecnica fundamentada apta/nao-apta).

## 9. Emendas dos Atos 141-144 (arbitragem ChatGPT 144)
- C-01 (resolvido): NAO ha conflito N-06/N-08 x C6 na V1 — ao matar a arvore do controlador, a ponte morre antes de
  gravar a trava 28; sobra o lease, e o pre-flight confirma a morte, apaga o lease e segue. PROVAR no C6/PU-11. NAO
  converter reserva em custo conhecido: o razao preserva a distincao custo-conhecido vs reserva-pendente (b05/razao.ps1).
- R-01 (ALTO na V2; PU-11b): o controlador congelado faz rollback (git reset/clean) ANTES de chamar a ponte; um PE
  sobrevivente (V2, tarefa agendada, fora da arvore) poderia escrever apos o rollback e antes do pre-flight da ponte.
  Solucao: GUARDA de pre-inicializacao SEPARADO e confiavel, EXTERNO ao B-05, executado ANTES do lancador/controlador,
  com intertravamento e sem contorno — NAO modificar lancador.ps1 (congelado). Bloqueante da V2; prova por PU-11b
  (PE anterior vivo -> a inicializacao e impedida antes do controlador e de qualquer rollback). Na V1, demonstrar que o
  C6 encerra toda a arvore e nao ha escrita apos o rollback.
- R-02 (feito): listagem de leases do pre-flight e FAIL-CLOSED (erro ao listar bloqueia).
- R-03 (feito): identidade do embrulho por criacao em FILETIME do HANDLE (CriacaoUtc) + snapshot autoritativo
  (NtQuerySystemInformation) com cross-check; ausente/divergente/inconclusiva => bloqueio.
- C-02: violacao 70 aparece como `failed` (exit 1) no controlador congelado (ele repete tentativas, todas barradas pela
  trava). A notificacao e o relatorio final DEVEM dizer "TRAVA DE SEGURANCA 70 — evidencia em <pasta>"; linha propria
  na matriz, distinguindo o estado externo do controlador do motivo interno de seguranca e eventual precedencia de R1.
- C-03: a regressao C4 preserva o resultado da baseline (exit 1, T1 failed, HEAD=base, arvore limpa); qualquer
  divergencia e declarada/justificada na matriz.
- D-06 (REQ-02, classificacao financeira por FASE): eliminar a equivalencia generica falhou.flag / sem-marcadores /
  falha-comum-com-retry. Classificar: (a) anterior a invocacao; (b) posterior com custo CONHECIDO; (c) posterior com
  custo DESCONHECIDO; (d) falha exclusivamente de teste. Custo desconhecido NAO vira zero nem autoriza nova invocacao
  sem reconciliacao/admissao suficientes; reserva pendente permanece contabilizada (sem virar gasto conhecido).

## 10. Emendas do Ato 148 (resposta ao parecer da mesa no Ato 147; candidata nova, a2c002f preservado)
- ERRATA REQ-08 (D-1, pedido por Perplexity): "a ponte e escolhida por flag de config" = a ponte e escolhida por QUAL
  ClaudeCmd/TestCmd o controlador RECEBE (parametros externos). O modo principal-isolado e um WRAPPER SEPARADO
  (b05/pe/claude-ponte.ps1 + .cmd) passado como ClaudeCmd; a fase teste e o despachante P-B (b05/pe/despachante-teste.ps1
  + .cmd) passado como TestCmd. NAO se modifica claude-com-teto.ps1 (baseline 9e6991c diff VAZIO) nem o controlador
  (7cd7864 diff VAZIO) nem o lancador. Provado com o CONTROLADOR REAL (testar-controlador-real-ponte.ps1, I-C1/I-D2/I-TMO/I-RET).
- D-2 RESOLVIDO na V1 (objecao de Perplexity/ChatGPT acatada): o despachante P-B entra JA na V1. O controlador recebe o
  despachante como $TestCmd; o despachante despacha o teste a ponte em modo SOMENTE-TESTE (acao-pe com somente_teste=true,
  invocacao NOVA => Job NOVO), rodando o $TestCmd sob o PE em Low IL (nivel 4096), sem a chave, IPC em Medium, apos a morte
  do executor. Assim o passo 6 do controlador NUNCA executa o codigo do repositorio como PU (I2/E105-01 preservada).
  Provas: PU-14 (nucleo), I-D2 (controlador real) - escrita Low em .git via a fase teste NEGADA.
- D-3 CORRIGIDO (condicoes de ChatGPT/Perplexity): (1) a trava persistente FINANCEIRA preserva o codigo 28 (nao 70
  generico) - PU-Trava-Ativa expoe o tipo (PU-02b). (2) em falha com custo CONHECIDO o wrapper devolve esse custo ao
  controlador, nunca 0 (CustoUsd no resultado; V1-F04). (3) falha ao gravar a RESERVA bloqueia fail-closed (28, sem
  disparo). (4) o evento 'fim' sempre inclui custo_desconhecido (contrato do razao.ps1). C6 real: a retomada preserva o
  custo do razao e o pre-flight encerra orfao anterior (I-RET).
- REQ-04 completo (PU-15): o codigo do teste (Low) nao escreve em alvo Medium (teste.txt/pasta-ponte) nem faz acesso
  perigoso ao processo supervisor (Stop-Process NEGADO; supervisor segue vivo).
- Cobertura do REQ-08 com o CONTROLADOR REAL 7cd7864 (nao o minimo): I-C1 (sucesso->commit), I-D2 (teste em Low, nao PU),
  I-TMO (timeout->rollback), I-RET (retomada/custo+pre-flight). O teste 'minimo' foi renomeado (M-C1/M-CUSTO/M-ORFAO)
  para nao colidir com os nomes do harness do oraculo (C4=timeout, C6=morte do controlador).
- R1/REQ-11: a trava impede novo despacho e preserva evidencia; o estado final pode ser HOLD (exit 2) quando houver
  gatilho R1 concomitante, em vez de failed — respeitar a precedencia do controlador congelado.
- Copia confiavel do PU: a copia da ponte e do despachante executada pelo PU fica fora da arvore editavel pelo PE
  (ACL/IL efetivas) com SHA-256 conferido; o fonte no GitHub nao substitui a protecao em runtime.

## 11. Emendas do Ato 150 (ajustes convergidos do Ato 149; candidata 4, c980c2f preservado)
Convergência do Ato 149: ChatGPT e Perplexity exigem R-04/R-05 obrigatórios já (ChatGPT: candidata 3 "NÃO totalmente
fechada" sem eles); Gemini aprova c980c2f e não se opõe à inclusão do lançador como script complementar EXTERNO, desde
que c980c2f seja preservado imutável. Candidata 4 = NOVO commit sobre c980c2f (preservado como ancestral), incorporando:

- R-04 (SHA do núcleo OBRIGATÓRIO, nos DOIS pontos de entrada): claude-ponte.ps1 e despachante-teste.ps1 conferem o
  SHA-256 dos 5 scripts do núcleo (ponte-pu, acao-pe, b05job, baixa-integridade, razao) ANTES do dot-source. A config
  DEVE trazer hashes_nucleo completo; ausência, mapa incompleto ou qualquer divergência => BLOQUEIO (exit 97), sem
  carregar nem despachar. Deixou de ser opcional (era "se houver hashes_nucleo"). Provas: I-SHA (divergente), I-SHA-AUS
  (ausente), I-SHA-INC (incompleto) no controlador real.
- R-05 (timeout OBRIGATÓRIO + margem): claude-ponte.ps1 exige timeout_controlador_seg na config e valida
  timeout_ponte + margem (35s: 15s de espera interna + 20s de encerramento/reconciliação) <= timeout_controlador_seg;
  caso contrário recusa (exit 1) SEM disparar. Provas: I-R05-AUS (ausente), I-R05-MARGEM (margem insuficiente -> sem
  despacho).
- R-01/D-1 (lançador-ponte EXTERNO e ADITIVO): novo lancador-ponte.ps1/.cmd. NÃO altera uma linha de controlador
  (7cd7864), claude-com-teto (9e6991c), supervisora (6b45dea), lancador.ps1 nem do núcleo B-05 (todos diff=VAZIO). Antes
  de subir/retomar o controlador: (a) grava a config IMUTÁVEL da execução (FileMode CreateNew + somente-leitura) com
  hashes_nucleo obrigatório (R-04) e o executor PARAMETRIZADO (não embute o fake como operacional); (b) PRÉ-FLIGHT
  ANTI-ÓRFÃO (R-01): se existir lease de execução anterior com subárvore VIVA, NÃO sobe o controlador e sai 22 — impede
  qualquer git/rollback enquanto um PE anterior puder escrever (fail-closed); lease de subárvore morta é conferido e
  limpo; (c) trava persistente preserva D-06 (financeira=>28, seguranca=>70, senão 26). Só então sobe o controlador real
  via -ClaudeCmd=claude-ponte.cmd e -TestCmd=despachante-teste.cmd (seleção 100% externa). Provas: PU-11b (lease vivo =>
  22, controlador não sobe, arquivo não-rastreado preservado, EstadoDir vazio), C6-real (morte abrupta em in_progress =>
  nenhum commit; 2º lançador retoma após liberação segura => commit, custo preservado), L-OK (config imutável +
  hashes_nucleo + commit), L-TRV (trava financeira => 28, controlador não sobe).
- Códigos de saída do lançador: 0 (controlador done); 22 (R-01: órfão vivo, não sobe); 26 (trava persistente
  genérica); 28 (trava financeira); 29 (R-05: margem de prazo insuficiente na validação prévia); 70 (trava segurança);
  97 não se aplica ao lançador (ele ESTABELECE os hashes; R-04 bloqueia nos pontos de entrada).
- CORREÇÃO DE REGISTRO (honestidade documental): no Ato 148 constou que a Perplexity "prova RC-6b". A Perplexity
  esclareceu (Ato 149) que ESCREVEU, mas NÃO executou o RC-6b. A prova de execução de RC-6b/PU-11b/C6-real passa a ser a
  deste pacote (candidata 4, bateria real no Windows), não a da Perplexity.

## 12. Ato 151 (Perplexity) — binário aprovado e CONGELAMENTO da candidata 4 (129/129)
Causa raiz do PE 33/40 nas rodadas pela GUI (isolada pela Perplexity, Ato 151): a bateria rodava sob o pwsh da
Microsoft Store (MSIX, em C:\...\WindowsApps\...), não o pwsh PORTÁTIL aprovado. Um app MSIX roda num Job de
app-container (com SILENT_BREAKAWAY_OK), o que deixa o neto do executor ESCAPAR do Job e sobreviver ao teardown —
exatamente as 7 falhas de reaping (PE-R4a/b/c, PE-L). Não era regressão de código: `acao-pe`/`b05job` seguem com
diff VAZIO. Comprovado: o pwsh portátil e o MSIX têm o MESMO SHA-256 (FA2C8BB1…E9E9619); a diferença é só o
contêiner de execução.
- Correção (só em componentes NÃO congelados — runner e bootstrap): o runner (roda-cand4) passou a EXIGIR, antes de
  qualquer bateria, que (Get-Process -Id $PID).Path seja o pwsh portátil aprovado
  (C:\Users\piloto\piloto\ferramentas\pwsh-7.6.7\pwsh.exe) e que o SHA-256 seja FA2C8BB1…E9E9619 — senão FATAL
  (exit 3). Registra no resultado caminho/versão/SHA/msix e o diagnóstico de Job (IsProcessInJob +
  QueryInformationJobObject). O bootstrap chama o portátil por caminho completo.
- Evidência do binário aprovado (resultado 20261025-122017): `pwsh_msix=False`; `job: em_job=True flags=0x0`
  (SEM SILENT_BREAKAWAY, SEM KILL_ON_CLOSE no Job externo) — contexto limpo para o reaping aninhado.
- CONGELAMENTO CANDIDATA 4 — matriz real sob o binário aprovado: **PE 40/40 · PU 39/39 · INTEGRA 13/13 ·
  CONTROLADOR-REAL 18/18 · LANCADOR 19/19 = 129/129, EXITCODE 0, "TODAS VERDES"**. Integridade de entrega 14/14.
  c980c2f (candidata 3) preservado como ancestral imutável. Congelados intactos (diff VAZIO): controlador 7cd7864,
  claude-com-teto 9e6991c, supervisora 6b45dea, lancador.ps1 e núcleo B-05. Bloqueios mantidos: deploy, V2,
  provisionamento, cobrança, execução desassistida; R1/B-07/aprovação humana.

## 13. Ato 153 — ajustes convergidos (C4-F02, C4-F03, C6-complemento) — CANDIDATA 4.1 (137/137)
Da reverificação da mesa (Ato 153): Gemini 4/4; Perplexity aprova com C4-01; ChatGPT acata 129/129 mas objeta o
fechamento integral (C4-F01/F02/F03). Acatados e incorporados os itens CONVERGENTES e não-congelados:
- **C4-F02 — gate do pwsh no LANÇADOR** (não só no runner): `lancador-ponte.ps1` exige caminho canônico + SHA-256
  aprovado (FA2C8BB1…E9E9619) do pwsh e RECUSA MSIX (`\WindowsApps\`) antes de qualquer despacho (exit 31);
  `lancador-ponte.cmd` recusa `B05_PWSH` do WindowsApps. **Prova:** L-PWSH (pwsh não aprovado ⇒ 31, controlador não sobe).
- **C4-F03 — âncora de confiança**: o lançador compara os hashes do núcleo contra um MANIFESTO APROVADO e protegido
  (`hashes-nucleo-aprovado.json`), não apenas os arquivos do runtime; ausência/não-cobertura/divergência ⇒ FATAL (97);
  a config carrega os valores APROVADOS. **Prova:** L-MANIF (núcleo diverge do manifesto ⇒ 97).
- **C6-complemento**: o C6-real passou a comprovar também: T1 estava in_progress na morte (tentativas≥1); árvore de
  trabalho LIMPA após a retomada; integridade do commit (notas.txt no HEAD) no caso limpo OU HEAD=base + reserva mantida
  no fail-close.
- Matriz real sob o binário aprovado: **PE 40/40 · PU 39/39 · INTEGRA 13/13 · CONTROLADOR-REAL 18/18 · LANCADOR 27/27 =
  137/137, EXITCODE 0** (resultado 20261025-131950). Integridade de entrega 15/15. b6d8d44 preservado como ancestral.
- **ABERTO → MESA (C4-F01, ChatGPT):** equivalência do lançador externo às garantias do `lancador.ps1` B-05 (Job de
  supervisão do controlador, mutex EstadoDir/RazaoDir, reconciliação/anti-concorrência). Por ser ARQUITETURAL, não é
  decidido nem implementado unilateralmente: submetido à mesa (parecer focal de Gemini/Perplexity). Posição do Auditor
  Principal: proposta ADITIVA (mutex por EstadoDir/RazaoDir + Job de supervisão com KILL_ON_JOB_CLOSE envolvendo o
  controlador), sem tocar componentes congelados, a ratificar pela mesa antes de implementar.
