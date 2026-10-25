# PACOTE DE AUDITORIA — Ponte V1 / gate de isolamento de principal — CANDIDATA 4

**Autonomous multi-LLM orchestration flow** · gate-pe @ `b6d8d44` (congelamento) · `c980c2f` (candidata 3) preservado imutável
Emissor: Claude Opus 4.8 (Auditor Principal) · Ato 152 · 25/10/2026 — UTC-4 Vilhena

---

## 1. VEREDITO — matriz real no Windows, sob o binário APROVADO

| Bateria | Resultado | Cobre |
|---|---|---|
| PE | **40/40** | núcleo PE (acao-pe/b05job): Job Object, Low IL, morte de neto, laço, limites |
| PU | **39/39** | PU (ponte-pu): reserva/D-06, trava 28/70, reparse, evidência, PU-11b, supervisor |
| INTEGRA | **13/13** | controlador mínimo × claude-ponte (C1/C4/C6, PU-09, R-04/R-05) |
| CONTROLADOR-REAL | **18/18** | controlador REAL 7cd7864: I-C1/I-D2/I-TMO/I-RET + R-04 (SHA) + R-05 (timeout) + I-FLAG |
| LANCADOR | **19/19** | lançador R-01 externo: L-OK, L-TRV, **PU-11b**, **C6-real** |
| **TOTAL** | **129/129** | **EXITCODE 0 — "TODAS VERDES"** (resultado `20261025-122017`) |

**Binário aprovado (gate do runner):** `pwsh: C:\Users\piloto\piloto\ferramentas\pwsh-7.6.7\pwsh.exe (7.6.7)` ·
`pwsh_sha256 = FA2C8BB1E35CDD62AD15CD06A1D8F2C5961E9725A9BFA1E7CFD2C322F49E9619` · `pwsh_msix=False` ·
`job: em_job=True flags=0x0` (sem SILENT_BREAKAWAY, sem KILL_ON_CLOSE no Job externo) · integridade de entrega **14/14**.

---

## 2. O que a candidata 4 incorpora (ajustes CONVERGIDOS do Ato 149)

- **R-04 — SHA do núcleo OBRIGATÓRIO nos DOIS pontos de entrada** (`claude-ponte.ps1` e `despachante-teste.ps1`):
  conferência do SHA-256 dos 5 scripts do núcleo antes do dot-source; ausência / mapa incompleto / divergência ⇒
  bloqueio (exit 97). Deixou de ser opcional. **Provas:** I-SHA, I-SHA-AUS, I-SHA-INC (CONTROLADOR-REAL).
- **R-05 — timeout OBRIGATÓRIO + margem** (`claude-ponte.ps1`): exige `timeout_controlador_seg` e valida
  `timeout_ponte + 35s ≤ timeout_controlador_seg`; senão recusa (exit 1) SEM disparar. **Provas:** I-R05-AUS, I-R05-MARGEM.
- **I-FLAG — lista fechada de flags** (`claude-ponte.ps1`): barra `--dangerously-*`/bypass; `--settings` só fora da
  árvore. **Prova:** I-FLAG.
- **R-01 / D-1 — lançador-ponte EXTERNO e ADITIVO** (`lancador-ponte.ps1`/`.cmd`): grava config IMUTÁVEL (CreateNew +
  somente-leitura) com `hashes_nucleo`; **pré-flight anti-órfão** ⇒ se houver lease de subárvore VIVA, NÃO sobe o
  controlador e sai **22** (impede git/rollback enquanto um PE anterior puder escrever); trava persistente preserva
  D-06 (financeira⇒28, segurança⇒70). Só então sobe o controlador real por `-ClaudeCmd`/`-TestCmd` (seleção 100%
  externa). Executor PARAMETRIZADO (não embute o fake). **Provas:** L-OK, L-TRV, **PU-11b** (lease vivo⇒22, controlador
  não sobe, arquivo não-rastreado preservado, EstadoDir vazio).
- **C6-real — morte abrupta em tarefa in_progress + retomada** (LANCADOR): após o encerramento abrupto, o lançador
  **libera com segurança** (subárvore do PE conferida MORTA e lease limpo no pré-flight, custo preservado, sem commit).
  A asserção exige a **invariante de segurança de R-01/RC-6b**, não commit obrigatório: a retomada **ou** conclui com
  commit limpo **ou** fail-close (despacho indeterminado — D-06 c: reserva mantida, SEM commit), **nunca** commit
  corrompido nem tarefa presa em in_progress. Ambos são corretos.

## 3. Reforços independentes incorporados (convergência com Perplexity)

- **I-SHA** (Ato 148): conferência de SHA-256 do núcleo antes do dot-source — agora OBRIGATÓRIA (= R-04).
- **I-FLAG** (Ato 148): lista fechada de flags em `claude-ponte`.

## 4. Ato 151 — binário aprovado (diagnóstico da Perplexity, acatado e provado)

O PE antes dava 33/40 quando a bateria era lançada pela GUI. **Causa raiz (Perplexity):** rodava sob o **pwsh da
Microsoft Store (MSIX)**, que executa num **Job de app-container** (com SILENT_BREAKAWAY_OK) — isso deixa o neto do
executor ESCAPAR do Job e sobreviver ao teardown, exatamente as 7 falhas de reaping. **Não era regressão:**
`acao-pe`/`b05job` seguem com diff VAZIO; o pwsh portátil e o MSIX têm o MESMO SHA-256 (FA2C8BB1…) — a diferença é só
o contêiner. **Correção (apenas em componentes NÃO congelados — runner e bootstrap):** o runner EXIGE que
`(Get-Process).Path` seja o pwsh portátil aprovado e que o SHA-256 seja FA2C8BB1…, senão FATAL (exit 3) antes de
qualquer bateria; grava caminho/versão/SHA/msix e o diagnóstico de Job no resultado. Rodada completa reexecutada sob o
binário aprovado ⇒ **129/129**.

## 5. CORREÇÃO DE REGISTRO (honestidade documental)

No Ato 148 constou que a Perplexity "prova RC-6b". A própria Perplexity esclareceu (Ato 149) que **ESCREVEU, mas NÃO
executou** o RC-6b. **A prova de execução de RC-6b / PU-11b / C6-real passa a ser a desta candidata 4** (bateria real no
Windows, sob o binário aprovado), não a da Perplexity.

## 6. Invariantes e fronteiras preservadas

- **diff VAZIO** (intactos): controlador `7cd7864`, claude-com-teto `9e6991c`, supervisora `6b45dea`, `lancador.ps1`
  (núcleo B-05), e núcleo B-05 (`ponte-pu`, `acao-pe`, `b05job`, `baixa-integridade`, `razao`). A seleção da ponte é
  100% EXTERNA (parâmetros `-ClaudeCmd`/`-TestCmd`).
- **BLOQUEADOS:** deploy operacional, transição para V2, provisionamento, cobrança/ativação financeira, execução
  desassistida. **Em vigor:** R1, B-07, aprovação humana. **ABERTO por design (V2):** PE-F11 / REQ-09.
- `c980c2f` (candidata 3) preservado como **ancestral imutável**; candidata 4 = novo commit `b6d8d44`.

## 7. Manifesto SHA-256 (artefatos da candidata 4)

Núcleo B-05 (diff VAZIO): `ponte-pu FC262DC9` · `acao-pe 5159B360` · `b05job C84D4196` · `baixa-integridade 8115F3AC` ·
`razao 9F302EF6`.
Ponte/wrappers: `claude-ponte.ps1 7AE5A320` · `despachante-teste.ps1 48A12631` · `lancador-ponte.ps1 BDD708BB`.
Testes: `testar-pe 49D9E2B7` · `testar-ponte-pu 07CCB11F` · `testar-integra 480ED333` ·
`testar-controlador-real 6692DE8B` · `testar-lancador B2B3C59E`.
pwsh aprovado: `FA2C8BB1E35CDD62AD15CD06A1D8F2C5961E9725A9BFA1E7CFD2C322F49E9619`.
(SHA256SUMS completo em `b05/pe/SHA256SUMS-CANDIDATA4.txt`; evidência bruta em
`b05/pe/evidencia/CANDIDATA4-129-129-pwsh-aprovado-20261025.txt`.)

## 8. Pedido à mesa

Reverificar a candidata 4 (`gate-pe @ b6d8d44`, 129/129 sob o binário aprovado) e confirmar 4/4 sobre: R-04, R-05,
I-FLAG, lançador R-01 (PU-11b), C6-real (invariante de segurança) e o gate do pwsh aprovado (Ato 151). Confirmar
também a correção de registro do RC-6b (§5). Itens abertos por design (PE-F11/REQ-09) e os BLOQUEADOS seguem como estão.
