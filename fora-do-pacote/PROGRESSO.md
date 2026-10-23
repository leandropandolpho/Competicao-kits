# Progresso — Autonomous multi-LLM orchestration flow

Registro para manter as barrinhas consistentes entre Atos (mesmo se o histórico do chat for resumido).
Regra: o projeto total só recua com regressão real de trabalho, registrada aqui com o motivo.

| Ato | Fase atual | % fase | % projeto total | Observação |
|---|---|---|---|---|
| 075 | B-05 (pré-requisito da autonomia) | 60% | 91% | referência informada por Leandro |
| 077 | B-05 v3.1 | 60% | 58% → **corrigido para 91%** | 58% foi erro de recálculo após resumo do histórico; sem regressão real |
| 078 | B-05 v3.1 — implementação e bateria no Windows | 60% | 91% | correção do conhost, bateria rodando |
| 079 | B-05 v3.1 | 70% | 92% | bateria simulada 52/52 |
| 080 | B-05 v3.1 — submissão à auditoria | 85% | 93% | N1r real 0 sobreviventes, P1/P2, 40/40 |
| 081 | (ChatGPT) B-05 v3.1 — acato parcial | — | — | novo escopo: B05-F06 (alta, exige contrato + implementação + N18), F07, ressalva do conhost |
| 082 | B-05 — correções do Ato 081 | 80% | 92% | **recuo registrado**: o Ato 081 aumentou o escopo restante (F06 com contrato novo) e devolveu o B-05 a HOLD; F07 e conhost já corrigidos |
| 083 | B-05 — contrato v3.2 (F06) submetido | 82% | 92% | 66/66 com F07, conhost, F08; sonda de baixa integridade viável |
| 087 | E84-01 validada (75/75); sonda Low IL | 83% | 92% | custo inválido rejeitado antes do controlador |
| 088 | sonda Low IL decisiva VERDE | 84% | 92% | Claude real completa tarefa em baixa integridade (041 inconclusiva por bug $pid + falta de --settings; 042 corrigida: arquivo editado, is_error=false) |
| 089 | E84-01+E84-02+G2 implementadas | 86% | 93% | bateria 81/81 (050): N18b nega 5 subversões do executor em baixa integridade (razão, liberação, config, hook e config do .git), tarefa normal completa e comita; achados corrigidos: máscara do token (ADJUST_DEFAULT), $args automático, cmd /s, .git médio explícito |
| 090 | E84-03 implementada (NO_READ_UP + ambiente limpo) | 88% | 94% | bateria 82/82 (051); confidencialidade de credenciais resolvida (R-a) |
| 091 | E84-04+E84-05 implementadas | 90% | 95% | bateria 86/86 (054); SO nega junction ao executor (N18c-1); varredura fecha reparse pré-existente (N18c-2); UI limits no job; falta só Claude real (N18a + e2e) |
| 092 | causa-raiz do fluxo real corrigida (EstadoDir sem NR) | 92% | 96% | 7 achados corrigidos (token, $args, cmd/s, .git, env, UI, EstadoDir/settings); 070/073 provam Claude real OK em baixa integridade dentro e fora do job; 074 rodou, falta reler (ponte offline) |
