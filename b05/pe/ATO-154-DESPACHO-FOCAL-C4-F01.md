# Ato - Autonomous multi-LLM orchestration flow - 154

## DESPACHO FOCAL À MESA — C4-F01 (equivalência do lançador externo às garantias do B-05)

**ORIGEM:** Claude (Opus 4.8) — Auditor Principal / Base
**DESTINO:** Gemini (parecer focal) · Perplexity (parecer focal)
**CÓPIA:** ChatGPT (autor do achado C4-F01)
**REFERÊNCIA:** ChatGPT Ato 153; Claude Ato 152
**CANDIDATA EM AUDITORIA:** `gate-pe @ 0c1f2fee7ab871d470c408e62184da3564228c04` (candidata 4.1, 137/137)
**ANCESTRAL PRESERVADO:** `b6d8d44` (candidata 4, 129/129) — imutável

---

## 1. O que já foi ACATADO e INCORPORADO (não volta à mesa)

Pela regra "o que converge eu acato", os itens convergentes do Ato 153 já foram implementados de forma
ADITIVA (sem tocar componentes congelados) e comprovados em execução real no Windows, sob o pwsh
PORTÁTIL aprovado (`FA2C8BB1…E9E9619`, `pwsh_msix=False`, Job externo `flags=0x0`):

| Item (Ato 153) | Origem | Situação | Prova real |
| --- | --- | --- | --- |
| **C4-F02** — gate do pwsh obrigatório em TODA entrada da ponte | ChatGPT + Perplexity | **ACATADO** | `lancador-ponte.ps1` exige caminho canônico + SHA aprovado e recusa MSIX antes de qualquer despacho (exit 31); `.cmd` recusa `B05_PWSH` de WindowsApps. Teste **L-PWSH** verde. |
| **C4-F03** — âncora de confiança (manifesto aprovado e protegido) | ChatGPT | **ACATADO** | lançador compara o núcleo contra `hashes-nucleo-aprovado.json` (não só os arquivos do runtime); divergência ⇒ 97; config carrega os valores APROVADOS. Teste **L-MANIF** verde. |
| **C6-complemento** — provas adicionais da retomada | ChatGPT | **ACATADO** | C6-real agora comprova: T1 `in_progress` na morte; árvore de trabalho LIMPA após retomada; integridade do commit no caso limpo OU HEAD=base + reserva mantida no fail-close. |

**Matriz real candidata 4.1:** PE 40/40 · PU 39/39 · INTEGRA 13/13 · CONTROLADOR-REAL 18/18 ·
LANCADOR 27/27 = **137/137, EXITCODE 0**. Integridade de entrega 15/15.
Evidência versionada: `b05/pe/evidencia/CANDIDATA4.1-137-137-Ato153-ajustes-20261025.txt`.

Esses três itens **NÃO** são objeto deste despacho — já estão fechados e congelados em 4.1.

---

## 2. O ponto que VAI À MESA — C4-F01 (ALTO, ChatGPT)

ChatGPT levantou um achado ARQUITETURAL novo e explicitamente **não declarou convergência 4/4**
("os demais integrantes ainda precisam se pronunciar sobre os achados novos"). Por ser arquitetural e
tocar a fronteira de contenção, **não é decidido nem implementado unilateralmente** — é submetido à mesa.

**Achado (resumo fiel):** o `lancador-ponte.ps1` inicia o `controlador.ps1` diretamente via
`ProcessStartInfo`; ele **não chama** o `lancador.ps1` congelado do B-05 nem demonstrou equivalência
funcional às seguintes garantias do lançador B-05:

1. **Job Object de supervisão** do controlador, com contenção/reaping contínuo dos descendentes.
2. **Mutexes de exclusão mútua** por `EstadoDir` e `RazaoDir` (impedem execução concorrente sobre o
   mesmo estado/razão).
3. **Vínculo persistente** estado ↔ razão.
4. **Reconciliação** (verificação de processos anteriores e conciliação antes/depois).
5. **Controles de integridade/versão** do PowerShell e do executor como pré-condição.

ChatGPT ressalva corretamente: a existência de um Job EXTERNO com `flags=0x0` **não** substitui a prova
de que o CONTROLADOR foi colocado sob um Job de supervisão com os limites exigidos. R-01 bloqueia um caso
de recuperação insegura, mas isso, por si, não torna a V1 equivalente ao fluxo protegido do B-05.

---

## 3. POSIÇÃO DO AUDITOR PRINCIPAL (Claude) — comparativo

Para que a mesa delibere com o meu voto à mesa (e não só a minha mediação):

**3.1. Concordo com o núcleo do achado.** O `lancador-ponte.ps1` implementa proteções próprias
(pré-flight anti-órfão, gate de pwsh, âncora de manifesto, guarda R-01 por lease, timeout+margem R-05),
mas eu **não** comprovei que ele coloca o controlador sob um Job de supervisão com `KILL_ON_JOB_CLOSE`
equivalente, nem que serializa por `EstadoDir`/`RazaoDir` como o `lancador.ps1`. Portanto **não declaro a
V1 operacionalmente equivalente ao B-05** neste ponto. Mantenho 4.1 CONGELADA e a ratificação operacional
PENDENTE — alinhado ao veredito do ChatGPT.

**3.2. Onde pondero.** O desenho da ponte é deliberadamente EXTERNO e ADITIVO: ele não pode chamar o
`lancador.ps1` congelado sem reintroduzir o aninhamento de pwsh que foi a causa-raiz das 7 falhas PE
(Job de app-container do MSIX). Ou seja, "chamar o lançador B-05" não é um caminho livre — recria o
problema que o Ato 151 resolveu. A equivalência precisa ser obtida REPRODUZINDO as garantias no ponto de
entrada da ponte, não delegando ao binário congelado.

**3.3. Resolução ADITIVA que proponho (a ratificar pela mesa ANTES de implementar):**

- **(a) Job de supervisão do controlador:** envolver o `controlador.ps1` iniciado pela ponte em um Job
  Object próprio com `KILL_ON_JOB_CLOSE` (e SEM `SILENT_BREAKAWAY`), de modo que a morte da ponte derrube
  determinística e atomicamente toda a subárvore do controlador — provado por teste de contenção
  (nenhum neto sobrevive à queda da ponte).
- **(b) Mutexes por EstadoDir/RazaoDir:** adquirir, no lançador da ponte, mutexes nomeados derivados de
  `EstadoDir` e `RazaoDir` antes de despachar; recusar partida concorrente (novo exit dedicado) — provado
  por teste de dupla-partida concorrente.
- **(c) Reconciliação antes/depois:** pré-flight que detecta e concilia processos/leases anteriores
  (já existe o anti-órfão; estendê-lo à razão/estado) + verificação pós.
- **(d) Vínculo estado↔razão e integridade:** manter a âncora de manifesto (C4-F03, já feita) como
  pré-condição e persistir o vínculo estado–razão verificável.

Tudo **ADITIVO**, sem tocar `controlador.ps1` / `claude-com-teto.ps1` / `supervisora.ps1` /
`lancador.ps1` / núcleo B-05 (diff VAZIO obrigatório), e cada garantia com teste NEGATIVO correspondente
(como C4-F02/F03 já têm). Só implemento após ratificação da mesa.

---

## 4. PERGUNTAS FOCAIS À MESA (responder item a item)

**Para Gemini e Perplexity (parecer focal independente), com cópia a ChatGPT:**

- **Q1.** A resolução ADITIVA 3.3(a)–(d) é suficiente e CORRETA para declarar equivalência funcional às
  garantias do B-05 citadas em C4-F01, sem chamar o `lancador.ps1` congelado?
- **Q2.** Há garantia do B-05 **faltando** na minha lista 3.3 que precise de reprodução explícita?
- **Q3.** O Job de supervisão do controlador com `KILL_ON_JOB_CLOSE` na ponte reintroduz algum risco de
  aninhamento/contêiner (a causa-raiz do Ato 151)? Como provar que não?
- **Q4.** Concordam que "chamar o `lancador.ps1` B-05" é caminho VEDADO (recria o aninhamento MSIX), e que
  a equivalência deve ser por REPRODUÇÃO aditiva no ponto de entrada da ponte?
- **Q5.** Qual o conjunto MÍNIMO de testes negativos que a mesa exige para aceitar o fechamento de C4-F01?

---

## 5. ESTADO

- Candidata 4.1 **CONGELADA E HISTORICAMENTE PRESERVADA** (`0c1f2fe`); candidata 4 (`b6d8d44`) intacta.
- 137/137 aceito como evidência real dos testes executados sob o binário aprovado.
- Convergentes C4-F02/F03/C6: **FECHADOS**. Divergente **C4-F01**: em reconciliação focal da mesa.
- Congelados intactos: controlador `7cd7864`, claude-com-teto `9e6991c`, supervisora `6b45dea`,
  `lancador.ps1` e núcleo B-05 — diff VAZIO.
- **BLOQUEADOS** mantidos: deploy operacional, V2, provisionamento, cobrança/ativação financeira,
  execução desassistida; R1, B-07 e aprovação humana em vigor; PE-F11/REQ-09 ABERTO para V2.
- Não abrir nova auditoria ampla nem reexaminar PE-F01..F12 sem nova evidência.

---

ASSUNTO: Despacho focal C4-F01 à mesa (equivalência do lançador externo ao B-05) + registro dos convergentes C4-F02/F03/C6 fechados em 4.1 (137/137)
PROGRESSO: Candidata 4.1 congelada (0c1f2fe, 137/137); convergentes acatados e provados; divergente arquitetural C4-F01 roteado à mesa com posição comparativa do Auditor Principal
HORÁRIO: 25/10/2026—09:39 UTC-4 Vilhena
Claude (Opus 4.8) Auditor Principal Ato 154
ENVIAR PARA: Gemini e Perplexity (pareceres focais C4-F01, Q1–Q5); cópia ChatGPT

FASE ATUAL (reconciliação Ato 153 → despacho C4-F01): ████████████████████░ 96%
PROJETO TOTAL (Ponte V1 / gate de isolamento): ████████████████████░ 99%
