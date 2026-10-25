# Ato - Autonomous multi-LLM orchestration flow - 164

## ESPECIFICAÇÃO ADITIVA C4-F01 — v2 (correções contratuais do Ato 163, verificadas no B-05 congelado)

**ORIGEM:** Claude (Opus 4.8) — Auditor Principal
**BASE:** candidata 4.1 `gate-pe @ 0c1f2fe` (137/137), ancestral `b6d8d44` preservado
**RATIFICAÇÕES Ato 163:** Gemini 3.1 Pro (ratificação INTEGRAL) + ChatGPT GPT-6 (ratificação CONDICIONAL com
correções contratuais). Perplexity fora desta rodada por decisão do responsável (sem crédito) — reservada para
reauditar a 4.2 pronta.
**NATUREZA:** DOCUMENTO DE PROJETO. Nenhum código implementado; congelados com diff VAZIO. Implementação só
após o gate empírico (§4) passar no Windows real.

---

## 0. Correções da v2 (o que mudou desde o Ato 158) — por verificação no `lancador.ps1` B-05

Conferi o contrato do `b05/lancador.ps1` CONGELADO (v3.1, Atos 075–077). As correções do ChatGPT (A1/A2 + G6)
são o **contrato real do B-05** — acato por FATO, não por voto; a ratificação integral do Gemini não prevalece
sobre o contrato congelado, e as correções só AUMENTAM a equivalência (que é o objetivo do C4-F01):

- **Códigos de saída (A1) — tabela normativa do B-05, a espelhar na ponte:**
  `20` trava ocupada (EstadoDir/RazaoDir = concorrência) · `21` razão ilegível · `22` processo antigo vivo ·
  `23` saldo insuficiente (admissão) · `24` falha no Job Object · `25` versão do Claude · `26` pastas inválidas ·
  `27` pwsh empacotado/hash · `28` reconciliação financeira divergente · `29` contenção violada (ou violação
  anterior sem LIBERACAO_HUMANA) · `30` vínculo divergente · `31` rótulo indeterminado/reprovado.
  → **Meu `exit 23` para concorrência (v1) estava ERRADO** (23 = saldo insuficiente). Concorrência = **20**.
  → **Vínculo** = **30** (não 28). **Admissão/orçamento** = **23**. **Reconciliação financeira** = **28**.
- **Reserva pendente (A2):** `inicio` sem `fim` conhecido **NÃO** exige `LIBERACAO_HUMANA.txt`. O B-05 contabiliza
  como **reserva pendente = `teto×(1+folga)`** (lancador.ps1 L141; ponte-pu D-06(c)). `LIBERACAO_HUMANA.txt`
  pertence à liberação de **violação de contenção anterior** (código 29), não à conversão de custo desconhecido.
  → Corrigido o G4 (eu havia misturado as duas coisas).
- **G6 rótulos (ChatGPT):** Médio é **`>=8192`** (verificável), não apenas "≠4096" (lancador.ps1 L229). Repositório
  recém-criado NÃO começa Low: aplicar rótulos de confiança e **reler** antes de autorizar executor Low.
- **Achado relevante:** o `lancador.ps1` B-05 **já é a implementação de referência** de G1–G9 com essa tabela —
  inclusive `RestringirUI` (B05-F11 sem bypass, L152), handle não-herdável (L156), dispensa de processo
  pré-existente (L176), e os testes N10 `-TesteFalharAssociacao`/`-TesteHandleHerdavel`. A ponte deve
  **espelhar** esse contrato de forma ADITIVA, sem chamá-lo (motivo de interface, §2.2).

---

## 1. Convergentes FECHADOS (não reabrir) — ratificados pelo Gemini (Ato 155/163)

- **C4-F02** (gate pwsh em toda entrada; recusa MSIX/SHA → exit 31 no gate de pwsh; cf. B-05 código 27 p/ pwsh).
- **C4-F03** (âncora de manifesto `hashes-nucleo-aprovado.json`; divergência → exit 97).
- **C6-complemento** (T1 `in_progress` na morte; árvore LIMPA; invariante commit íntegro XOR fail-close).

---

## 2. Convergência do C4-F01 (Atos 155 + 163)

| Ponto | Gemini 3.1 Pro | ChatGPT GPT-6 | Claude (Principal) | Situação |
| --- | --- | --- | --- | --- |
| Arquitetura aditiva G1–G9 | ratifica integral | ratifica condicional | adoto | **CONVERGE** |
| Chamar `lancador.ps1` vedado | sim | sim (motivo: interface) | sim (§2.2) | **CONVERGE** |
| Gate empírico antes do código | sim, suficiente | sim, com complementos (§4) | adoto o maior | **CONVERGE no maior** |
| Bateria 12 propriedades | aceita | aceita c/ códigos corrigidos | adoto | **CONVERGE** |
| **Códigos de saída** | OK ao `exit 23` (mutex) | OBJEÇÃO: 20=mutex, 23=saldo, 30=vínculo | **verifiquei no B-05 → ChatGPT certo** | **resolvido por FATO** |
| Reserva pendente / LIBERACAO_HUMANA | — | separar (A2) | **verifiquei no B-05 → ChatGPT certo** | **resolvido por FATO** |

### 2.2. Por que não chamar o `lancador.ps1` congelado
Conclusão convergente. Motivo correto (ChatGPT, confirmado no código): o `lancador.ps1` fixa `claude-com-teto.cmd`
(L36: `$Embrulho = ...claude-com-teto.cmd`), enquanto a ponte precisa selecionar `claude-ponte.cmd` e
`despachante-teste.cmd` separadamente — incompatibilidade de interface/contrato. Alterá-lo violaria o diff VAZIO (I1).

---

## 3. Garantias a reproduzir no `lancador-ponte.ps1` (G1–G9, v2 com códigos do B-05)

Todas ADITIVAS; espelham o `lancador.ps1` B-05; reutilizam primitivas congeladas ancoradas por SHA (C4-F03);
sem tocar `controlador.ps1`/`claude-com-teto.ps1`/`supervisora.ps1`/`lancador.ps1`/núcleo B-05.

- **G1 — Job de supervisão.** `JobLancadorPonte` com `KILL_ON_JOB_CLOSE` (0x2000), sem `BREAKAWAY_OK`/
  `SILENT_BREAKAWAY_OK`; controlador `CREATE_SUSPENDED` → `AssignProcessToJobObject` → associação COMPROVADA →
  só então `ResumeThread`. Falha de associação encerra o suspenso (sem executar código) com confirmação de morte.
  Handle do job **não-herdável** (sem vazamento que mantenha o job vivo). Falha de Job → **exit 24**.
- **G2 — Exclusão mútua (H7).** Mutexes nomeados por `EstadoDir` e `RazaoDir`, nomes/canonização compatíveis com
  o B-05, adquiridos antes do despacho e mantidos por TODA a vida do controlador (inclusive reconciliação pós).
  Concorrência → **exit 20**.
- **G3 — Vínculo persistente bidirecional (E76-03).** Criar vínculo só quando ambos os lados ausentes e o razão
  sem histórico incompatível; recusar unilateral/incompleto/divergente ou razão histórico associado indevido →
  **exit 30** (nada gravado no RazaoDir).
- **G4 — Finanças (E76-04/H8/H9).** Distinguir base histórica B, custo conhecido K, reserva pendente R
  (`teto×(1+folga)`) e custo desconhecido. Admissão: **B + K + R + T(1+F) ≤ M** → senão **exit 23**.
  Reconciliar `estado.json == B + K` antes e depois → divergência **exit 28** + trava durável. Dados
  inconclusivos → bloqueio. Reserva pendente **não** exige LIBERACAO_HUMANA (≠ contenção).
- **G5 — Contenção e processo anterior (E76-01/P4).** Descendentes por (PID + CreateTime) via
  `NtQuerySystemInformation`; descendente fora do Job / violação sem LIBERACAO_HUMANA válida → **exit 29**;
  evidência durável; tratamento restrito de processo pré-existente como no B-05 (dispensa qualificada ou **exit 22**).
- **G6 — Rótulos de integridade (B05-F09).** Aplicar e RELER via `GetNamedSecurityInfo`: RepoPath Low = 4096 no
  estágio em que o executor edita; `.git`, `.git/config`, `.git/hooks` e metadados protegidos **Médio ≥ 8192**;
  `RazaoDir` e segredos com `NO_READ_UP` (mask&2). Repositório recém-criado: aplicar rótulos de confiança e reler
  ANTES de autorizar executor Low (nunca presumir Low no início). Indeterminado/reprovado → **exit 31**.
- **G7 — Reparse points (B05-F10).** `B05LowIL-ReparsePoints` pré e pós (fail-closed se `Ok=false` ou `Pontos>0`).
- **G8 — Encerramento verificado.** Fechar `JobLancadorPonte`; confirmar via `NtQuerySystemInformation` nenhum
  descendente sobrevivente; sem handle remanescente que impeça `KILL_ON_JOB_CLOSE`.
- **G9 — Integridade operacional / falha fechada.** Gate do pwsh (C4-F02 → exit 27/pwsh), âncora de manifesto
  (C4-F03 → exit 97), versão/hash/config/origem; nenhum resultado inconclusivo convertido em sucesso.

---

## 4. GATE EMPÍRICO (pré-condição de QUALQUER implementação da 4.2) — v2 com complementos do ChatGPT

Spike isolado no Windows real, pwsh portátil aprovado, sem tocar congelados, sem implementar a solução:

**L-JOB-TOPO — reproduzir a cadeia efetiva** `JobLancadorPonte → controlador → claude-ponte → acao-pe → JobPE →
executor Low` e comprovar:
1. Controlador suspenso, associado e só então retomado.
2. Executor criado suspenso e associado ao `JobPE` antes de executar.
3. Associação do executor verificada **no Job supervisor E no JobPE** (dupla verificação).
4. Job supervisor com `KILL_ON_JOB_CLOSE`, sem breakaway.
5. `JobPE` com `KILL_ON_JOB_CLOSE`, `RestringirUI` (0x27) preservado, sem breakaway.
6. Mesmo resultado na invocação separada da fase de teste.
7. Todos os resultados de API e erros do Windows registrados.
A documentação Microsoft prevê restrições de UI para Jobs aninhados → **inconclusivo ou falha de associação REPROVA**.

**L-JOB-KILL —** matar abruptamente o lançador com a cadeia viva; comprovar por (PID + CreateTime) o encerramento
de controlador, embrulho, executor, teste (quando aplicável) e netos; demonstrar ausência de handle remanescente.

**Falha de associação —** injetar falha entre criação suspensa e associação; comprovar **limpeza do suspenso órfão**
(ou prevenção equivalente). Reusar como referência os testes N10 do B-05 (`-TesteFalharAssociacao`,
`-TesteHandleHerdavel`). `PROC_THREAD_ATTRIBUTE_JOB_LIST` só como ALTERNATIVA a avaliar se o procedimento
tradicional não cumprir as invariantes — nenhuma substituição arquitetural automática autorizada.

**PASSA** → implementar G1–G9 + bateria §5 (contrato corrigido). **FALHA** → NÃO relaxar `RestringirUI` nem
habilitar breakaway; retornar com evidências da incompatibilidade para decisão focal da mesa.

---

## 5. Bateria negativa consolidada (12 propriedades) — v2 com códigos do B-05

| ID | Garantia | Cenário negativo → aceite (código) |
| --- | --- | --- |
| L-JOB-TOPO | G1 topologia | associação aninhada + RestringirUI compatível (§4); inconclusivo REPROVA |
| L-JOB-ASSOC | G1 fail-closed | falha de associação/UI → nenhum executor roda; suspenso órfão limpo (**24**) |
| L-JOB-KILL | G1 cascata | matar lancador-ponte → controlador+executor+neto morrem (PID+CreateTime), sem conflitar com JobPE |
| L-MUTEX | G2 | 2ª instância no mesmo EstadoDir/RazaoDir → aborta **exit 20**, sem tocar Git/estado/razão |
| L-VINC | G3 | parear estado novo com razão vinculado / vínculo adulterado → **exit 30** (nada no RazaoDir) |
| L-RECON-PRE | G4 | `estado.json ≠ B+K` antes → **exit 28**, controlador não sobe |
| L-RECON-POS | G4 | divergência financeira ao final → trava + **exit 28** |
| L-ADMIS | G4 | `B+K+R+T(1+F) > M` (orçamento insuficiente c/ reservas) → **exit 23**, sem chamada cobrável |
| L-CONTEN | G5 | processo anterior / violação sem LIBERACAO_HUMANA → **exit 29**, execução bloqueada |
| L-ROTULO-31 | G6 | `.git` em Low, Médio `<8192`, ou `RazaoDir` sem NO_READ_UP → **exit 31** antes do controlador |
| L-REPARSE | G7 | reparse point plantado (pré/pós) → fail-closed |
| L-C6-CONC | G5/C6 | morte em in_progress + lease vivo → sem rollback/despacho enquanto o anterior puder escrever |

Incluir nos grupos: prova de **ausência de suspenso órfão**, **verificação simultânea dos dois Jobs**, e os
cenários de **primeira inicialização** e **razão histórico**. Cada negativo registra: tentativa efetiva,
(PID+CreateTime), códigos Windows, código final, eventos do razão e efeitos sobre o Git. Falha esperada nunca
vira verde sem demonstrar a tentativa. Agrupamento permitido (12 PROPRIEDADES, não 12 execuções).

---

## 6. Autorizações e limites (consolidado do Ato 163)

- **Gemini:** ratificação INTEGRAL; autoriza o avanço imediato à 4.2 controlada (gate primeiro).
- **ChatGPT:** ratificação CONDICIONAL — autoriza (1) incorporar as correções na spec [FEITO nesta v2];
  (2) executar o gate isolado L-JOB-TOPO/L-JOB-KILL + verificações de falha; (3) se aprovado e com Gemini
  ratificando [FEITO], prosseguir à implementação G1–G9 + bateria; (4) preservar a 4.1 e entregar nova candidata
  com commit, hashes, diffs e evidências.
- **NÃO autorizado:** relaxar UI do PE, habilitar breakaway, modificar congelados, provisionar V2, ativar cobrança,
  implantar ou executar operacionalmente sem assistência. R1/B-07/aprovação humana em vigor. PE-F11/REQ-09 aberto.

**Situação:** os dois auditores ratificaram a arquitetura aditiva; as correções contratuais estão incorporadas e
são o contrato congelado do B-05. Resta o **gate empírico no Windows real** — única coisa que ainda decide o
C4-F01 — e, passando, a implementação controlada da 4.2.

---

## 7. Estado

- Candidata 4.1 CONGELADA E PRESERVADA (`0c1f2fe`, 137/137); `b6d8d44` intacta.
- Convergentes C4-F02/F03/C6: FECHADOS e RATIFICADOS.
- C4-F01: arquitetura aditiva G1–G9 **RATIFICADA pelos dois auditores**; códigos alinhados ao contrato B-05;
  **implementação condicionada ao gate empírico (§4)**. Nenhum código escrito; congelados com diff VAZIO.
- BLOQUEADOS mantidos: deploy, V2, provisionamento, cobrança/ativação financeira, execução desassistida.

---

ASSUNTO: Espec C4-F01 v2 — ratificada por Gemini (integral) e ChatGPT (condicional); códigos corrigidos para o contrato B-05 congelado (verificado); resta o gate empírico no Windows
PROGRESSO: 99% (ponderado) — arquitetura ratificada 2/2; implementação condicionada ao gate empírico (precisa do notebook)
HORÁRIO: 25/10/2026 — 13:47 UTC-4 Vilhena
Claude (Opus 4.8) Auditor Principal Ato 164
ENVIAR PARA: Leandro (próximo passo = gate no notebook); cópia mesa (Gemini, ChatGPT) para registro da v2

FASE ATUAL (C4-F01: ratificado 2/2 → gate empírico pendente de Windows): ████████████████████░ 98%
PROJETO TOTAL (Ponte V1 / gate de isolamento): ████████████████████░ 99%
