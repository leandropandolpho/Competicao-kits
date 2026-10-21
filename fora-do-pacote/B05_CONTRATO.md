# Contrato da candidata B-05 — custo de chamada interrompida, processos órfãos e retomada
**Ato 070 · 21/10/2026 · Autor: Claude (Auditor Base) · Situação: PROPOSTA, aguardando aprovação do contrato (Ato 069 do ChatGPT exigiu contrato antes da implementação)**

Base: convergência dos Atos 068 (Claude), 069 (ChatGPT) e 069 (Perplexity, mesma família do Claude): resolver o B-05 **sem alterar o controlador congelado** `7cd7864` (`ced2ec45…608e`) nem a supervisora `6b45dea`.

## 0. Escopo e limites
- Componentes novos, **por fora** do controlador: `b05/lancador.ps1` (Job Object + orçamento + reconciliação) e `b05/claude-com-teto.cmd` + `.ps1` (embrulho do executor: teto por chamada + razão).
- O controlador continua igual: recebe o embrulho por `-ClaudeCmd` e um `-MaxCustoUsd` calculado pelo lançador.
- **Não autoriza execução desassistida.** Continuam valendo R1, B-07 (`liberar_por_desempate`) e a aprovação humana. A aprovação do B-05 habilita só o próximo marco: um piloto de autonomia limitada, com decisão separada.
- A reserva conservadora é **controle interno**: não comprova a cobrança real nem é teto financeiro absoluto. O teto efetivo no provedor (assinatura/limite de conta) continua sendo a garantia financeira de fundo.

## 1. Contrato de contabilização de custo
| ID | Regra | Verificável por |
|---|---|---|
| C1 | Toda chamada ao executor recebe `--max-budget-usd T` (T = teto por chamada, parâmetro do lançador). | Argumentos registrados no razão |
| C2 | **Antes** de iniciar a chamada, o embrulho grava no razão (`razao.jsonl`, fora do repo) o evento `inicio` com id único, horário e T. | Linha `inicio` existe antes de qualquer saída do executor |
| C3 | Ao terminar, grava `fim` com o `total_cost_usd` devolvido. Sem esse campo, grava `fim` com `custo_desconhecido=true`. | Linha `fim` correspondente |
| C4 | Custo contabilizado por chamada: `fim` com custo → o custo; `fim` desconhecido **ou** `inicio` sem `fim` → **T × (1 + folga)**, folga padrão 0,25 (o CLI avisa que o gasto pode passar do teto). **Desconhecido nunca vira zero.** | Reconciliação reproduz a soma a partir do razão |
| C5 | O lançador calcula `gasto_contabilizado` pelo razão e passa ao controlador `-MaxCustoUsd = orçamento − gasto_contabilizado`. Se isso for menor que T × (1 + folga), **não inicia** (código próprio) e notifica. | Cenário N3 |
| C6 | Uma interrupção nunca devolve orçamento: a reserva só cai se uma linha `fim` posterior, do mesmo id, trouxer custo conhecido. | Cenário N2 |

## 2. Contrato de encerramento de processos
| ID | Regra | Verificável por |
|---|---|---|
| P1 | O lançador cria um **Job Object** com `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, **associa a si mesmo ao job** e só então inicia o controlador. Assim, todos os descendentes (controlador → embrulho → `claude.exe` → filhos) nascem dentro do job, sem janela de corrida. | PIDs registrados pertencem ao job |
| P2 | Se o lançador cair ou for encerrado, o Windows fecha o handle e encerra **todo** o job. | Cenário N1 |
| P3 | O embrulho grava no razão o PID do `claude.exe` que iniciou; a prova de órfão é por **PID** (não por caminho de executável, o filtro que falhou no teste 006). | Cenário N1: nenhum PID registrado vivo após a queda |
| P4 | Antes de iniciar, o lançador confere que nenhum PID registrado em execução anterior está vivo; se estiver, não inicia e notifica. | Cenário N4 |

## 3. Contrato de retomada
| ID | Regra | Verificável por |
|---|---|---|
| R1r | A retomada da tarefa continua sendo do controlador congelado (rollback para `commit_base`, tentativas já gastas preservadas) — comportamento já validado no 006. | Regressão do 006 |
| R2r | Antes de relançar, o lançador reconcilia o razão (C4/C6) e confere P4. | Cenários N2 e N4 |
| R3r | Sem execução duplicada: o lançador usa uma trava (mutex nomeado por `EstadoDir`); uma segunda instância para o mesmo estado não inicia. | Cenário N5 |

## 4. Cenários negativos (todos no Windows real, conta `piloto`)
| ID | Cenário | Resultado exigido |
|---|---|---|
| N1 | Derrubar o **lançador** com `claude.exe` em execução | Nenhum PID registrado vivo em ≤ 10 s; tarefa fica `in_progress` para a retomada |
| N2 | Após N1, reconciliar | Chamada derrubada contabilizada como T × 1,25; `gasto_contabilizado` > 0 |
| N3 | Orçamento restante < T × 1,25 | Lançador não inicia; código e notificação próprios; nenhuma chamada nova |
| N4 | PID antigo vivo (simulado por processo-sentinela registrado no razão) | Lançador não inicia |
| N5 | Duas instâncias simultâneas para o mesmo `EstadoDir` | A segunda não inicia |
| N6 | Retomada após N1, com orçamento suficiente | Controlador retoma (rollback + nova tentativa), conclui; custo total = reserva da derrubada + custo real da nova |
| N7 | Chamada normal | `inicio` + `fim` com custo real; `--max-budget-usd` presente nos argumentos |

## 5. Regressão exigida para aceitar a candidata (Ato 069 do ChatGPT)
- Harness original v0.2.2 **40/40** no Windows (o kit não muda; confirmar mesmo assim).
- Provocações **P1/P2** repetidas pelo lançador + embrulho (esperado: `hold SEM_ALTERACAO`, sem commit).
- Cenários **N1–N7** com evidência bruta + manifesto.
- Auditoria independente restrita a `b05/` e às evidências.

## 6. Próximo marco (não incluído aqui)
Piloto de autonomia limitada: tarefas não críticas, limites financeiros, alertas, intervenção humana obrigatória nas exceções, e decisão separada sobre o B-07 (proposta a discutir: o desempate nunca libera sozinho — `liberar_por_desempate` vira escalar quando não há humano).
