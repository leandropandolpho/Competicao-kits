# Pacote de auditoria — Ponte do PU (modo principal-isolado), V1 (disparo local)

Ato - Autonomous multi-LLM orchestration flow - 145. Gate de isolamento de principal. Branch gate-pe.
Este pacote consolida o estado da V1 para a reverificação da mesa (Trilha A) em paralelo com a bateria real (Trilha B).
Spec de referência: `b05/pe/PONTE-PU-SPEC.md` (v2 + emendas Atos 141-144). Contrato de custo: `b05/razao.ps1`.

## 1. Invariantes (I1) — componentes congelados com diff VAZIO
Verificado por `git diff <ancora> HEAD -- <arquivo>` (vazio = intacto):
- `kits/kit-A/controlador.ps1` vs **7cd7864** — VAZIO (o controlador nunca é tocado; a ponte é externa).
- `b05/claude-com-teto.ps1` vs **9e6991c** — VAZIO (a ponte NÃO modifica o wrapper do B-05; ver decisão D-1).
- `supervisora/supervisora.ps1` vs **6b45dea** — VAZIO.
- Núcleo B-05 `b05/lancador.ps1`, `b05/razao.ps1`, `b05/b05job.ps1` vs 9e6991c — VAZIO.
- `b05/baixa-integridade.ps1`: ESTENDIDO (+32: EsperarSinal, LancarSuspenso/Retomar, NivelH) — extensão aceita pela mesa para o PE; não remove nem altera a API existente do B-05.

## 2. Artefatos sob teste (SHA-256) — estado congelável
| Arquivo | SHA-256 |
|---|---|
| b05/b05job.ps1 | C84D41969DE097F9EA04D9C11C6E126651E22C89CFD2A735439EB6CCA525D0FA |
| b05/baixa-integridade.ps1 | 8115F3ACF8386DA166147F33C460F935ECCD3A393F52E0B5AE1B5C88A43FFB27 |
| b05/razao.ps1 | 9F302EF681A03A045315925120BD1A216EB3434F900DE5772F15CA5E0FB5DF56 |
| b05/pe/acao-pe.ps1 | 0A1B570FC11426159B7F9B4857613CE843D7776D2DA55BD605A5685B950FC4A7 |
| b05/pe/ponte-pu.ps1 | CEF8A13F3A587A240584C98AB8DC807956F76FE13BF292D37ADF81CB5A958A46 |
| b05/pe/claude-ponte.ps1 | 7A458FA4615CFD2DC94386567C81C2A3EB5617469E650CC54B5DB52BB2AE4DEC |
| b05/pe/claude-ponte.cmd | B7B2E7F445C7AD02CECB02553D13722C19A8DB248708F34AFC58EB8D1D6E33B8 |
| b05/testes/fake-executor.ps1 | 3EE1DB213CCEEB54A7274F64DF5BB797B8AF9920BA9558422723CDA76964F3B8 |
| b05/pe/testes/testar-pe.ps1 | 49D9E2B7383185AA06895C6532B8A4D7BE1DEFA3F8F5B30AE3981FBCDE85AB62 |
| b05/pe/testes/testar-ponte-pu.ps1 | E9A7B4BB861B7A590BB25DD6FDA8B9584F081E778417335D6CEDAF618A9067F5 |
| b05/pe/testes/testar-integra-ponte.ps1 | 4C2CE531E33C246841DA4CEE2F54EAB80EC523B8A668A70DD007DAB6D0F3C8AD |

## 3. Matriz de testes — V1
Legenda: PROVADO = verde em bateria REAL no notebook (conta piloto, pwsh 7.6.7), com a tentativa comprovada
(comando/PID/IL/erro efetivo do Windows); PENDENTE-NB = implementado, parse real OK, aguardando bateria no notebook.

### 3.1 Embrulho PE (`testar-pe.ps1`) — 40/40 PROVADO (job 098)
PE-S1..S9, PE-R1..R4c, PE-L. Job proprio KILL_ON_JOB_CLOSE sem breakaway (P-03), executor/teste em Low IL 4096 em_job,
identidade PID+criacao, varredura reparse fail-closed, timeout proprio (EsperarSinal), falha terminal (falhou.flag),
rastreamento/associacao ao Job fail-closed (PE-F07/F10), sem orfaos apos normal/timeout/falha (PE-R4a/b/c), -Laco (PE-F08).

### 3.2 Lado PU (`testar-ponte-pu.ps1`) — 31/31 PROVADO (job 101)
| Caso | REQ | Prova | Status |
|---|---|---|---|
| PU-01 | REQ-01/02/03/07 | fluxo feliz; morte da subarvore; sem trava; razao reconciliado (inicio teto=0.5 -> fim custo_usd=0.20 CONHECIDO, D-06 b) | PROVADO |
| PU-02 | REQ-02 | total_cost_usd invalido (texto) -> custo DESCONHECIDO -> **28** + trava financeira + fim desconhecido (nao vira zero) + evidencia bruta | PROVADO |
| PU-03 | REQ-01 | pasta exec_id pre-existente -> recusa **70**, nao despacha, nao reutiliza/apaga residuo | PROVADO |
| PU-04 | REQ-03 | sobrevivente na subarvore do PE -> **70** + evidencia (mesmo apos limpeza do PU) | PROVADO |
| PU-05 | REQ-06/D-06(d) | executor OK (custo conhecido) + teste REPROVA -> falhou.flag por execucao, codigo 1, custo CONHECIDO, retry com exec_id NOVO nao barrado | PROVADO |
| PU-07 | REQ-07 | junction na arvore; embrulho nao varre -> varredura do PU pos-morte -> **70** + evidencia + trava | PROVADO |
| PU-08 | REQ-10/N-06 | acao trava -> timeout do PU, subarvore morta, sem fim.flag -> **28** (financeiro), trava financeira | PROVADO |
| PU-10 | REQ-11 | apos violacao, 2a chamada BARRADA pela trava persistente (fail-closed) | PROVADO |
| PU-12 | REQ-04/S-03 | codigo do teste em Low IL (4096); escrita Low em .git (Medium) NEGADA; teste.txt nao-forjavel | PROVADO |
| PU-13 | N-01 | executor Low tenta .git/hooks e .git/config (Medium) -> NEGADO; ataque.txt na raiz Low (prova end-to-end) | PROVADO |

### 3.3 Integracao modo principal-isolado (`testar-integra-ponte.ps1`) — 13/13 PROVADO (job 103)
Controlador MINIMO (replicando o padrao de chamada do controlador congelado) invocando o claude-ponte como ClaudeCmd.
| Caso | REQ | Prova | Status |
|---|---|---|---|
| PU-09 | REQ-08 | claude-ponte (codigo) nao carrega/invoca controlador.ps1 nem claude-com-teto; diff 7cd7864/9e6991c = VAZIO (container, item 1) | PROVADO |
| C1 | REQ-08 | controlador -> claude-ponte -> PE edita a arvore (notas.txt) -> custo reconciliado (fim 0.20 conhecido) -> commit (HEAD avancou) | PROVADO |
| C4 | REQ-08/C-02/C-03 | custo invalido -> claude-ponte 28 -> rollback (HEAD=base, arvore limpa) + trava financeira | PROVADO |
| C6 | REQ-12/R-01(V1) | PE orfao VIVO (lease de execucao anterior) -> pre-flight da ponte ENCERROU o orfao ANTES de despachar; chamada prosseguiu | PROVADO |

### 3.4 Linha C-02 (obrigatoria): TRAVA DE SEGURANCA 70
Em violacao de seguranca (PU-04 sobrevivente, PU-07 reparse, PU-03 exec_id, N-03/N-05): codigo **70**, evidencia
preservada FORA do repo (robocopy /XJ) ANTES do retorno, trava persistente de seguranca gravada; a 2a chamada e barrada.
No controlador congelado isso aparece como `failed` (exit 1, todas as tentativas barradas pela trava). A notificacao e a
matriz DEVEM registrar: **"TRAVA DE SEGURANCA 70 — evidencia em <pasta de evidencia>"**. Precedencia de R1: quando houver
gatilho R1 concomitante, o estado final pode ser HOLD (exit 2) em vez de failed (respeitar o controlador congelado).

## 4. Decisoes de design a ratificar pela mesa
- **D-1 (REQ-08 — wrapper externo em vez de modificar claude-com-teto.ps1).** A spec v2 falava em "novo modo
  principal-isolado em b05/claude-com-teto.ps1". Como `claude-com-teto.ps1` pertence a baseline congelada (9e6991c) e o
  invariante I1 exige diff VAZIO, a ponte foi implementada como wrapper SEPARADO `b05/pe/claude-ponte.ps1` (+ .cmd),
  que o controlador recebe como ClaudeCmd (a "flag de config" do REQ-08 = qual ClaudeCmd o controlador recebe). Resultado:
  controlador (7cd7864) E claude-com-teto (9e6991c) permanecem diff VAZIO. Decisao MAIS conservadora que a letra da spec;
  preserva mais invariantes. Pedir ratificacao.
- **D-2 (fase de teste — interna ao acao-pe vs despachante P-B dedicado).** Na V1 a fase de teste e exercida pelo
  acao-pe (test_cmd roda sob o PE em Low IL 4096, IPC em Medium, sem a chave; morte confirmada ao final) — provado por
  PU-05 e PU-12. O "despachante P-B dedicado, fora do repo, com SHA, em Job TOTALMENTE novo numa 2a invocacao" (spec
  secao 5) e um refinamento arquitetural: na V1 de disparo local o executor ja morreu quando o teste roda, de modo que o
  Job contem apenas o teste (equivalente material a Job novo). Propor: aceitar a fase-teste-interna para a V1 e mover o
  P-B dedicado para a integracao plena/V2. Pedir ratificacao.
- **D-3 (contabilidade unificada no modo isolado).** O claude-ponte delega reserva/admissao/reconciliacao ao
  Invoke-PontePU-V1 (RazaoDir = o razao do B-05), que e "o PU" tanto quanto o claude-com-teto — evita dupla contabilidade
  e preserva I3 (razao so o PU grava). A trava persistente no modo isolado e a .trava da ponte (arquivo em TravaDir),
  consultada fail-closed no inicio de cada chamada.

## 5. Pendencias da V2 (dependem de provisionamento — decisao de Leandro)
- Conta exec-piloto (principal separado) + credencial dedicada com teto de orcamento.
- Tarefa Agendada real: roteiro v3.2 (NAO rodar v3/v3.1) apos reverificacao da mesa + desfazer por proveniencia.
- REQ-09 (PE-F11, isolamento da credencial) — ABERTO; so demonstravel sob dois principais Windows.
- REQ-03/REQ-10 no modo V2: identidade por SID (WTSEnumerateProcesses); encerramento sem PROCESS_TERMINATE (Stop-ScheduledTask).
- R-01/PU-11b: guarda de pre-inicializacao EXTERNO ao B-05 (nao modificar lancador.ps1), ANTES do controlador/rollback.
- Sondas N1-N17 sob dois principais efetivamente separados.

## 6. Decisao tecnica (apta/nao-apta)
Trilha B (bateria real no notebook, conta piloto, pwsh 7.6.7) — COMPLETA:
- PE 40/40 (job 098); PU 31/31 (job 101); Integracao 13/13 (job 103). Todos os negativos comprovam a tentativa
  (comando/PID/IL/erro efetivo do Windows), nao apenas verde.
- CONGELAMENTO consolidado (job 104, uma unica execucao com os SHAs congelados): PE 40/40 + PU 31/31 + INTEGRA 13/13
  = 84/84, EXITCODE 0. Evidencia: b05/pe/evidencias/104-congelamento-84-84.txt.
Cobertura por requisito: REQ-01 (PU-03), REQ-02/D-06 (PU-01/02 + C1/C4), REQ-03 (PU-04), REQ-04/S-03 (PU-12),
REQ-06/D-06(d) (PU-05), REQ-07 (PU-07), REQ-08 (PU-09/C1/C4/C6), REQ-10/N-06 (PU-08), REQ-11 (PU-10/PU-04/PU-07),
REQ-12/R-01(V1) (C6). N-01 (PU-13), N-02 (PU-03), N-03/N-05 (nucleo), N-04 (evidencia), N-07 (trava), N-08 (lease/pre-flight).
Pendente para a decisao FINAL apta/nao-apta: reconciliar com as objecoes materiais da mesa (Trilha A) e ratificar as
decisoes D-1/D-2/D-3 (secao 4). ABERTO por design (V2/provisionamento): REQ-09/PE-F11 e a contencao entre dois
principais Windows (secao 5) — a V1 NAO cobre isolamento real de credencial/principal, apenas o protocolo e a contencao
por subarvore com disparo local.
