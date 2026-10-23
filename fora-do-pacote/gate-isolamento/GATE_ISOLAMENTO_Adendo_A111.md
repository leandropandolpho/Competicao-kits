# GATE — ISOLAMENTO DE PRINCIPAL · Adendo A111 à v0.2

Ato - Autonomous multi-LLM orchestration flow - 112
Autor: Claude · Anthropic · AUDITOR_BASE_CLAUDE (ambiente reporta `claude-opus-4-8`; o modelo que serve pode diferir)
Data: 23/10/2026 — UTC-4 Vilhena
Consolida: Atos 109 (Gemini, aceite), 110 (Perplexity, errata de implementação), 111 (ChatGPT, ACATO com adendo obrigatório)
Base: `GATE_ISOLAMENTO_PRINCIPAL_contrato_v0.2.md` — SHA-256 `5ef4ed23afce724c8656a869b05f0ad858e1e7bb5d3a195777d0c4f1109e6ca1` (intocado)
Baseline: 9e6991c · caa2c84 · controlador 7cd7864 · supervisora 6b45dea · fechamento 71096e9

> Status: ADENDO ACEITO (Ato 111). Não autoriza criar conta Windows, alterar permissões/tarefas nem ativar cobrança — tudo isso depende de ação e autorização do responsável (Leandro). Nada aqui revoga R1, B-07, aprovação humana ou o bloqueio da execução desassistida. O fechamento do B-05 permanece válido.

## A. Decisão P4 — consolidada
**Credencial do PE = chave de API dedicada**, em **workspace Anthropic exclusivo** (ex.: `exec-piloto`), com **limite mensal no provedor** (o Default Workspace não admite esse limite). O teto mensal **não** substitui o orçamento por execução do B-05 (`--max-budget-usd` + reserva); ambos valem.
**Implicação financeira (decisão do Leandro):** o executor passa a ser cobrado **por uso na API**, separado da assinatura Max. A ativação da cobrança e a definição do orçamento **dependem de autorização do responsável** (Ato 111). O auditor não cria workspace, chave nem habilita cobrança.

## B. Adendo A111 (obrigatório — Ato 111), com erratas de implementação do Ato 110
| ID | Determinação | Validação |
|---|---|---|
| A111-01 | Tarefa registrada com `TASK_DONT_ADD_PRINCIPAL_ACE` (`0x10`) e **DACL explícita** (SYSTEM e Administradores: controle total; PU: ler+executar; **PE: nenhuma entrada**). Sem a flag, o Agendador adiciona automaticamente uma ACE para o próprio PE, contrariando §5. | **N17** |
| A111-02 | PU **inicia, consulta e para** a tarefa; encerramento alternativo seguro (tarefa auxiliar de kill) se `Stop-ScheduledTask` não bastar. | **P4** (prova de parada + ausência de órfãos + fim do Job) |
| A111-03 | Validar `SeBatchLogonRight`, negações de logon interativo/remoto, política efetiva e **ciclo de vida da senha** do PE. | Capturas antes/depois, SID, tipo de logon, Last Run Result |
| A111-04 | `CLAUDE_CONFIG_DIR` em área **gravável de baixa integridade** do PE (o perfil `~/.claude` é médio e o token Low IL do PE não grava nele — mesmo problema do `clihome` do B-05); credencial exclusiva protegida. | **N16/CA-5/CA-10**; Claude real conclui tarefa |
| A111-05 | Conferir término do PE por **identidade PID + instante de criação** (`NtQuerySystemInformation`, que o B-05 já usa e funciona entre usuários — o PU não abre processos de outro SID), vinculado ao `exec.id`. | Falha segura diante de PID reutilizado ou morte não comprovada |
| A111-06 | Workspace Anthropic **exclusivo**, limite mensal **e** orçamento B-05 por chamada/execução. | Configuração financeira comprovada antes de habilitar chamadas pagas |

### Precisões de redação (Ato 111)
- **CA-9 / N11 (precisão)**: a saída de um processo comprometido **pode** ser fabricada; o que é protegido contra falsificação é o **estado de autorização e finalização controlado pelo PU**. Reenunciado: *nenhuma saída manipulada pelo PE produz aceite, commit ou redução indevida de custo*; só o estado terminal e a autorização sob PU geram efeitos. (CA-9 e N11 passam a adotar esta redação.)
- **Credencial permanente × cópias temporárias**: eliminar material temporário após a execução **sem** destruir a configuração necessária a futuras autenticações autorizadas (distinção explícita em CA-5/A111-04).
- **A111-03 (senha)**: não exige obrigatoriamente "senha que nunca expira"; admite-se em conta local dedicada com justificativa e controle, **ou** política de renovação monitorada que evite falha silenciosa do Agendador. O roteiro registra o *Last Run Result* de cada execução.
- **S4U × PASSWORD**: `TASK_LOGON_PASSWORD` é a opção **conservadora**; não se afirma que S4U bloqueie HTTPS de saída — isso é decidido pelo teste real **P1**.
- **`secedit`**: as negações de logon interativo/remoto (`SeDenyInteractiveLogonRight`, `SeDenyRemoteInteractiveLogonRight`) não têm cmdlet nativo — aplicar via `secedit` (exportar → editar → aplicar) e **conferir** com nova exportação. A negação de interativo **não** afeta o logon em lote.
- **`safe.directory`**: caminho exato com **barras normais** (`C:/piloto-work/...`), em configuração protegida; o PU segue dono da raiz e de `.git` e nunca adiciona `safe.directory` para pastas do PE.

## C. Teste novo N17 (A111-01)
**N17 — DACL da tarefa**: o PE tenta `Set-ScheduledTask`, desabilitar e remover a **própria** tarefa, e alterar seu comando/principal → **tudo negado** (flag `0x10` + DACL sem entrada para o PE). Evidência: comando, código, mensagem de negação, DACL efetiva relida.

## D. Acréscimos à matriz de rastreabilidade (§8 da v0.2)
| Origem | Determinação | Requisito | Teste/Critério |
|---|---|---|---|
| A111-01 (111) | `0x10` + DACL sem ACE do PE | §5 (início/DACL) | **N17**, CA-11 |
| A111-02 (111) | PU inicia/consulta/para; kill alternativo | §5 (encerramento) | P4, CA-8 |
| A111-03 (111) | Logon/senha/política comprovados | §5 (logon) | CA-11 |
| A111-04 (110/111) | `CLAUDE_CONFIG_DIR` Low IL; credencial protegida | §2.1, §5 (credencial) | CA-5, CA-10, N16 |
| A111-05 (110/111) | Morte por PID+criação (`NtQuerySystemInformation`) | §2.3(3) | CA-9, N10, N11 |
| A111-06 (109/110/111) | Workspace exclusivo + teto mensal + orçamento B-05 | §5 (credencial), §10 | CA-10 |
| Precisão CA-9 (111) | Só estado terminal/autorização sob PU gera efeito | §2.3(3)(5) | CA-9, N11 |
| Errata (110) | `secedit`, senha, `safe.directory` barras normais | §5, §11 | CA-11, N15 |

## E. Situação e autorizações (Ato 111)
- **Contrato v0.2 + Adendo A111**: aceito como base normativa da implementação experimental da arquitetura A.
- **Autorizado ao AUDITOR_BASE_CLAUDE**: consolidar A111 (este documento), preparar o roteiro administrativo, desenvolver a ponte/embrulho e os testes (N1–N17) em **ramo isolado** sobre `b05/`, e submeter evidências para nova auditoria.
- **NÃO autorizado**: execução desassistida; revogar R1/B-07; alterar componentes congelados; **ativar cobrança** ou criar a conta/credencial sem ação e autorização do responsável.
- Permanecem intactos: controlador `7cd7864`, supervisora `6b45dea`, baseline `9e6991c`; R1, B-07, aprovação humana; execução desassistida BLOQUEADA; **T8 pendente**.

## F. Plano imediato (§12 da v0.2, atualizado)
1. **Roteiro administrativo** (admin, 1 vez) → Leandro — entregue junto a este adendo; inclui A111-01..06 (flag `0x10`+DACL, `secedit`, senha, `CLAUDE_CONFIG_DIR` Low IL, placeholders de workspace/chave). **Não executado pelo auditor.**
2. Lançador/embrulho do PE (Job próprio, IPC com `exec.id`+heartbeat, morte por PID+criação, checagens CA) sobre `b05/`, em **ramo novo**; **controlador 7cd7864 intocado** (diff=vazio).
3. Script-sonda N1–N17 + bateria P1–P4; execução 2× (CA-7) → pacote de evidências imutável com hashes.
4. Verificação independente (Perplexity) → parecer da mesa → aceite da **implementação** (distinto do aceite do contrato).
