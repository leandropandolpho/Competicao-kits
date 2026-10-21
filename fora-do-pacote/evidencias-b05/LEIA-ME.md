# Evidências da candidata B-05 (Windows, conta `piloto`) — Ato 073

Código: branch `hibrido`, commit `8fa89331f3f06de0d4dcf9e21316de20084418b0`, pasta `b05/`.
| Arquivo | SHA-256 |
|---|---|
| `b05/lancador.ps1` | `b46c50c03d7a86ef7447da0f7dcd64dcb17f4e3230ac462880c89fe01c257e8f` |
| `b05/claude-com-teto.ps1` | `103413eeee5578911eb5641b566eceda46ab29ee1aa4ff1b8e9577558ae3c12c` |
| `b05/claude-com-teto.cmd` | `b683d9a80e791782c5487d7eaaad562cf014a7187ce506ee18ca9a50802f57cd` |
| `b05/razao.ps1` | `e39515a13f99130a27c1ddbcba79d764ea4d37f210349f782b0694d1d467bba7` |
| `b05/testes/testar-b05.ps1` | `70798cd516d8488145e9eb31b3bfe8c0c5b1146b02f98aabc76da1f84086a04c` |
| `b05/testes/fake-executor.ps1` | `4fdfa1a983d13b9dcd669879fdcedc862905e7202af395caffd776ea287da883` |
Controlador congelado `7cd7864` (`ced2ec45…608e`): **inalterado** (conferido em cada relatório).

## Histórico (relatórios brutos, sem edição)
| Arquivo | O que mostra |
|---|---|
| `019` | 1ª rodada: teste parou (simulado não chamado) |
| `022` | Diagnóstico: **E3 funcionou** — flags do job vieram 0x0 (struct aninhada copiada no PowerShell) e o lançador **recusou iniciar** (código 24). Corrigido configurando o job em C#. |
| `023` | 20/23: interface, orçamento, N3, N10 ok; defeitos no razão (leitura concorrente, data ISO, amostragem) |
| `024` | 23/27: **achado grave** — após derrubar o lançador, o executor continuou vivo (não estava no job) |
| `025` | Diagnóstico da contenção: filhos do controlador (pwsh empacotado da Microsoft Store) **não herdaram** o job aninhado; sobreviveram à queda |
| `026` | Com **associação ativa** dos descendentes (varredura a cada 100 ms): ninguém sobrevive à queda; 24/28 (N6 com erro do teste: 1 tentativa só) |
| `027` | **28/28** no Windows; diagnóstico: nenhum sobrevivente, nenhum erro de associação |
| `028` | **Claude real**: claude.exe dentro do job antes da queda, morto após (≤ 8 s), reserva 0,625 da chamada derrubada, retomada concluída com 1 commit, razão = estado.json; P1/P2 pelo lançador → hold SEM_ALTERACAO sem commit; **harness 40/40** |

## Limites e riscos residuais (declarados)
- **Contenção por varredura**: neste Windows, a herança do job não funcionou para os filhos do pwsh empacotado; a contenção depende da varredura ativa (100 ms). Um processo que nasça e crie filhos entre duas varreduras pode ficar fora do job até a varredura seguinte; processos que morrem antes não importam. No 026 apareceram 2 erros transitórios de associação ("acesso negado", processos de vida curta); no 027 e no 028, nenhum. Mitigação futura possível: pwsh não empacotado (instalação MSI, que falhou sem administrador no início do piloto).
- `--max-budget-usd` é estimativa local; T × 1,25 é reserva contábil, não garantia de cobrança.
- TOCTOU e sistema de arquivos adversarial: fora do escopo (como no aceite da fase 5).
