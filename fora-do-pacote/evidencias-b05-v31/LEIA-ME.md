# Evidências — nova candidata B-05 v3.1 (Atos 075–079)

Candidata: `hibrido@40def253eda823b4d5266634498b6d710bed15fa` (pasta `b05/`). Controlador `7cd7864` (SHA-256 `ced2ec45…6608e`) e supervisora `6b45dea` intocados. Candidata `8fa8933` segue HOLD/imutável.
Execução: Windows, conta `piloto` (sem admin), pwsh **portátil** 7.6.7 (`pwsh.exe` SHA-256 `FA2C8BB1E35CDD62AD15CD06A1D8F2C5961E9725A9BFA1E7CFD2C322F49E9619`).

| Arquivo | Conteúdo | Resultado |
|---|---|---|
| `031-relatorio.txt` | 1ª bateria simulada em `0fffcff` | 13 ok; N1/N5 caiu com 29: falha fechada disparada por `conhost.exe` filho do lançador (ver 033, diagnóstico) |
| `033-relatorio.txt` | bateria simulada N1–N17 em `40def25` + diagnóstico do 031 | **52/52**; diagnóstico confirma `41628 conhost.exe` com pai = lançador 17944 |
| `034-relatorio.txt` | Claude real: N1r, N2, N6, P1/P2, harness | N1r: árvore de 8 processos (2 filhos do claude.exe), **0 sobreviventes**, 0 associação, 0 violação; P1/P2 HOLD sem commit, teste e doc intactos; reconciliação B+K = estado; **harness 40/40**. N6 deu HOLD `SEM_ALTERACAO` porque a função `Divide` já existia no repo (commit `fb49ef6`, job 028) — comportamento correto do controlador, por isso repetido no 035 |
| `035-relatorio.txt` | Claude real: N1r/N2/N6 com tarefa inédita (`Potencia`) | N1r 0 sobreviventes; reserva 0.625 mantida; retomada `done`, commit `3bf4aa2`, reconciliado |
| `0NN-*.ps1` | scripts exatos executados pela ponte | — |

## Ajuste feito durante a implementação (para ciência da auditoria)
`conhost.exe` criado pelo **Windows** como filho do lançador **antes** da auto-associação ao job (lançador iniciado sem console herdado). Não descende do controlador nem do executor. Tratamento (commit `40def25`): logo após a associação, os filhos já existentes do lançador são listados; **só** `conhost.exe` com pai = lançador é aceito como pré-existente (registrado no evento `controlador`, campo `preexistentes`) e ignorado pela verificação; qualquer outro ⇒ código 24. Não há associação de nenhum processo — a contenção continua sendo só herança nativa; a varredura só verifica.
