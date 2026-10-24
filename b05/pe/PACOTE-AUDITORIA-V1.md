# Pacote de auditoria — Ponte do PU (modo principal-isolado), V1 (disparo local) — candidata 2

Ato - Autonomous multi-LLM orchestration flow - 148. Gate de isolamento de principal. Branch gate-pe.
Responde ao parecer da mesa no Ato 147 (Perplexity, ChatGPT, Gemini). O congelamento anterior (a2c002f) é PRESERVADO
imutável como evidência histórica; esta é uma candidata NOVA com as objeções materiais resolvidas.
Spec: `b05/pe/PONTE-PU-SPEC.md` (v2 + emendas 141-144 + emendas do Ato 148, seção 10). Contrato de custo: `b05/razao.ps1`.

## 0. Posição da mesa no Ato 147 e o que mudou
- D-1 (wrapper externo): Perplexity ACATO, Gemini RATIFICO, ChatGPT ACATO CONDICIONAL (provar seleção com controlador real).
  → ATENDIDO: errata na spec (REQ-08) + integração com o CONTROLADOR REAL 7cd7864 (seção 3.4).
- D-2 (fase de teste): Perplexity/ChatGPT OBJEÇÃO MATERIAL (despachante P-B já na V1); Gemini V1-ok + P-B na V2.
  → ACATADA A OBJEÇÃO: o despachante P-B entra na V1. O `$TestCmd` do controlador passa a ser o despachante, que
  despacha o teste à ponte (modo somente-teste, Job novo, Low IL). O passo 6 do controlador NÃO roda mais código do
  repositório como PU. Provas: PU-14 e I-D2 (controlador real).
- D-3 (contabilidade unificada): 3/3 ACATAM com condições. → CORRIGIDO: trava financeira preserva 28; custo conhecido
  devolvido ao controlador em falha; reserva fail-closed; 'fim' sempre com custo_desconhecido; C6 real (I-RET).
- Achados V1-F01..F04 + trava 28/70 + cobertura com controlador real + renomear casos + REQ-04 completo + registro de
  mudanças de teste: todos endereçados (seções 3, 4, 7).

## 1. Invariantes (I1) — componentes congelados com diff VAZIO
- `kits/kit-A/controlador.ps1` vs **7cd7864** — VAZIO (SHA ced2ec45; a ponte é externa, escolhida por ClaudeCmd/TestCmd).
- `b05/claude-com-teto.ps1` vs **9e6991c** — VAZIO (o modo isolado é um wrapper SEPARADO, não toca o B-05).
- `supervisora/supervisora.ps1` vs **6b45dea** — VAZIO. Núcleo B-05 (lancador/razao/b05job) vs 9e6991c — VAZIO.
- `b05/baixa-integridade.ps1`: ESTENDIDO (+32, aceito para o PE) — não remove/altera API existente.

## 2. Artefatos sob teste (SHA-256) — candidata 2
| Arquivo | SHA-256 |
|---|---|
| b05/b05job.ps1 | C84D41969DE097F9EA04D9C11C6E126651E22C89CFD2A735439EB6CCA525D0FA |
| b05/baixa-integridade.ps1 | 8115F3ACF8386DA166147F33C460F935ECCD3A393F52E0B5AE1B5C88A43FFB27 |
| b05/razao.ps1 | 9F302EF681A03A045315925120BD1A216EB3434F900DE5772F15CA5E0FB5DF56 |
| b05/pe/acao-pe.ps1 | 5159B36084B82782AA9BF0E141A99FC7D10BB82628E4D3852628675FB9031A62 |
| b05/pe/ponte-pu.ps1 | FC262DC947F4DDC3D55C2FE569F5AAF421F55C24C27BDBD0EFFBA2D8EF41B6A4 |
| b05/pe/claude-ponte.ps1 | E66377243DA196649E77C35D843CD0442CF0267F5B7FB680C3D858CC635F22C3 |
| b05/pe/claude-ponte.cmd | B7B2E7F445C7AD02CECB02553D13722C19A8DB248708F34AFC58EB8D1D6E33B8 |
| b05/pe/despachante-teste.ps1 | 2261B1118CCEE3326F6D04B0F61BA9FA07A85B03D5CDCD105744E1062F58FC0A |
| b05/pe/despachante-teste.cmd | BEDC456E4D73C2BA9CDBEFE9B2691D0CD1B8032CA972A69ACA2BE460B52178B1 |
| b05/testes/fake-executor.ps1 | 3EE1DB213CCEEB54A7274F64DF5BB797B8AF9920BA9558422723CDA76964F3B8 |
| b05/pe/testes/testar-pe.ps1 | 49D9E2B7383185AA06895C6532B8A4D7BE1DEFA3F8F5B30AE3981FBCDE85AB62 |
| b05/pe/testes/testar-ponte-pu.ps1 | 07CCB11FCEF9A19E03DEFB15A4B16C1F64AEC9B3139B7BD75459094E7D8D6EBA |
| b05/pe/testes/testar-integra-ponte.ps1 | BE1034A8BE4274B4ED30E157807C1826F6BEDB41C8BA49A534DC1DCC930A390C |
| b05/pe/testes/testar-controlador-real-ponte.ps1 | C73E0D9590043E1F617D48151E959C057F158598F5393C30BD28750D9225A02F |

## 3. Matriz de testes (bateria REAL no notebook, conta piloto, pwsh 7.6.7)

### 3.1 Embrulho PE (`testar-pe.ps1`) — 40/40
PE-S1..S9, PE-R1..R4c, PE-L. (inalterado; invocou.flag e modo somente_teste não regrediram — job 105.)

### 3.2 Lado PU (`testar-ponte-pu.ps1`) — 39/39
PU-01 (reconciliação D-06 b), PU-02 (custo inválido→28+trava), **PU-02b (trava financeira barra com 28, não 70)**,
PU-03 (N-02→70), PU-04 (sobrevivente→70), PU-05 (teste reprovado D-06 d, custo conhecido, retry), PU-07 (reparse→70),
PU-08 (timeout→28), PU-10 (trava barra 2ª), PU-12 (teste Low; .git Medium NEGADO), PU-13 (N-01 end-to-end),
**PU-14 (fase somente-teste via ponte: teste Low 4096, .git NEGADA — D-2)**, **PU-15 (REQ-04 completo: alvo Medium e
acesso perigoso ao supervisor NEGADOS; supervisor vivo)**.

### 3.3 Integração — controlador MÍNIMO (`testar-integra-ponte.ps1`)
PU-09 (ponte externa; diffs vazios), M-C1 (sucesso→commit+custo), M-CUSTO (custo inválido→28→rollback+trava),
M-ORFAO (pré-flight encerra órfão vivo). Casos renomeados (M-) para não colidir com os nomes do harness do oráculo.

### 3.4 Integração — CONTROLADOR REAL 7cd7864 (`testar-controlador-real-ponte.ps1`) — 10/10
ClaudeCmd=claude-ponte.cmd, TestCmd=despachante-teste.cmd, executor=fake. Seleção EXTERNA (parâmetros), sem tocar
controlador/lancador (fecha V1-F01).
| Caso | REQ | Prova |
|---|---|---|
| I-C1 | REQ-08 | controlador real → ponte → executor(PE) edita + teste(PE) passa → commit (done); razão reconciliado |
| I-D2 | REQ-04/S-03/V1-F02 | o $TestCmd roda via ponte sob o PE em Low IL (nível 4096), NÃO como PU; escrita Low em .git NEGADA |
| I-TMO | REQ-10 | executor trava via ponte → ponte encerra → controlador rollback (HEAD=base, árvore limpa) |
| I-RET | REQ-12/C6 | retomada preserva o custo do razão (não zera) + pré-flight encerra o órfão vivo anterior |

### 3.5 Congelamento consolidado (job 113, uma execução, SHAs congelados) — 102/102, EXITCODE 0
PE 40/40 + PU 39/39 + INTEGRA (mínimo) 13/13 + CTRL-REAL 10/10 = **102/102**. Evidência: b05/pe/evidencias/113-congelamento-candidata2-102-102.txt.
Residual honesto (C6): a morte ABRUPTA do controlador no timing exato não é injetada deterministicamente; o mecanismo de
defesa (pré-flight anti-órfão + custo preservado na retomada) é que está provado (I-RET, M-ORFAO). Declarado, não presumido.

### 3.6 Linha C-02 (obrigatória): TRAVA DE SEGURANÇA 70 / FINANCEIRA 28
Violação de segurança → 70 + evidência fora do repo + trava persistente (2ª chamada barrada); violação financeira → 28 +
trava financeira (preservada como 28 na 2ª chamada, PU-02b). No controlador congelado aparece como `failed` (exit 1,
tentativas barradas) e a matriz/notificação registram "TRAVA DE SEGURANÇA 70 — evidência em <pasta>". Precedência de R1:
havendo gatilho R1 concomitante, HOLD (exit 2) em vez de failed.

## 4. Decisões (Ato 147) — status
- **D-1 ACATADO** (wrapper externo). Errata na spec (REQ-08, seção 10): a flag de config = o ClaudeCmd/TestCmd recebido.
  Provado com o controlador real (3.4). controlador 7cd7864 e claude-com-teto 9e6991c permanecem diff VAZIO.
- **D-2 — objeção ACATADA**: despachante P-B na V1 (não postergado). b05/pe/despachante-teste.ps1(+.cmd) como $TestCmd;
  acao-pe modo somente_teste (Job novo, Low IL, sem chave). O passo 6 do controlador não executa código do repo como PU.
- **D-3 CORRIGIDO**: trava financeira 28 (PU-02b); custo conhecido devolvido em falha (V1-F04); reserva fail-closed;
  'fim' sempre com custo_desconhecido; C6 real (I-RET).

## 5. Pendências da V2 (provisionamento — decisão de Leandro)
Conta exec-piloto + credencial (teto); Tarefa Agendada real (v3.2 reverificada; não rodar v3/v3.1); REQ-09/PE-F11;
identidade por SID (WTSEnumerateProcesses) e encerramento por Stop-ScheduledTask; R-01/PU-11b (guarda externo);
sondas N1-N17 sob dois principais. A V1 NÃO cobre isolamento real de credencial/principal — só o protocolo + contenção
por subárvore com disparo local.

## 6. Decisão técnica (apta/não-apta)
Trilha B COMPLETA: PE 40/40, PU 39/39, integração (mínimo) e CONTROLADOR REAL 10/10 — com cada negativo comprovando a
tentativa (comando/PID/IL/erro do Windows). As três objeções do Ato 147 (D-1 condição, D-2 material, D-3 condições) foram
endereçadas com prova. Resta à mesa: reverificar esta candidata e confirmar 4/4. ABERTO por design (V2): REQ-09/PE-F11 e
a contenção entre dois principais Windows.

## 7. Registro formal de mudanças de teste por commit (exigência do despacho / Perplexity)
- 4697953 — N-01 fix (árvore Low + .git Medium); testar-ponte-pu passa a 16/16.
- c0fe9b6 — REQ-02/D-06: PU-01 ganha checagens de reconciliação; PU-02 (custo inválido) adicionado; fake 'custo'.
- 74a24f8 — PU-05 (teste reprovado) e PU-12 (fronteira de IL do teste) adicionados; Ped generaliza test_cmd.
- 1a18ac3 — testar-integra-ponte (controlador mínimo): PU-09/C1/C4/C6; correção do check PU-09 (ignora comentários).
- e47c7dd — PU-02b (trava 28), PU-14 (fase somente-teste), PU-15 (REQ-04 completo) adicionados.
- 961ba6f — testar-controlador-real-ponte (controlador real 7cd7864): I-C1/I-D2/I-TMO/I-RET.
- (candidata 2) — renomeados M-C1/M-CUSTO/M-ORFAO no teste mínimo; sem afrouxamento de verificação em nenhum commit.
