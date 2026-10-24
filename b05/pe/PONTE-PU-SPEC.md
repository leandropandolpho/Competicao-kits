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
- R1/REQ-11: a trava impede novo despacho e preserva evidencia; o estado final pode ser HOLD (exit 2) quando houver
  gatilho R1 concomitante, em vez de failed — respeitar a precedencia do controlador congelado.
- Copia confiavel do PU: a copia da ponte e do despachante executada pelo PU fica fora da arvore editavel pelo PE
  (ACL/IL efetivas) com SHA-256 conferido; o fonte no GitHub nao substitui a protecao em runtime.
