# Aceite formal da fase 5 — Supervisora combinada (Ato 068, 21/10/2026)

**Despacho:** Ato 067 — ChatGPT (GPT-6): F5-01-R/F5-04-R aprovados; INTEGRAÇÃO OPERACIONAL SUPERVISIONADA LIBERADA.
Histórico de auditoria: Ato 063 (F5-01..05) → Ato 064 (correções) → Ato 065 (F5-01-R, F5-04-R) → Ato 066 (correções) → Ato 067 (aceite).

## Referência validada (branch `hibrido`, commit `6b45dea1d11f092179230bf6df6771f6b00dd934`)
| Arquivo | SHA-256 |
|---|---|
| `supervisora/supervisora.ps1` | `79a7f3eb5f439e9f33f91c552a5107a190b37b094b6a2e1f59bdb4be8df4d0eb` |
| `supervisora/supervisao-combinada.ps1` | `042fec7fffd3e749a60d49d5bb5be624475bd0a8b1b05fcea728de1cfab04a56` |
| `supervisora/caminhos.ps1` | `5bfd0266515302705dd94ef19fa481384e6919ae5d6aba234986e3e3b058512a` |
Controlador congelado da fase 4 (`7cd7864`, `ced2ec45…608e`): inalterado.
Evidências: `fora-do-pacote/evidencias-fase5/` (commit `b51d313`), testes Windows 40/40 e 17/17, regressão real 7/7.

## Condições da integração supervisionada (Ato 067)
1. A supervisora só recomenda; não altera o repositório nem executa decisões.
2. Aprovações operacionais sob autoridade humana.
3. Gatilhos R1 prevalecem sobre consenso e arbitragem.
4. Tetos de custo e segregação de credenciais (chave OpenAI restrita a `/v1/responses`, em arquivo da conta `piloto`).
5. O controlador congelado não muda por causa deste aceite.

## Bloqueios mantidos
- **B-05** custo de chamada interrompida e processos órfãos → impede execução desassistida.
- **B-06** OpenCode → avaliação na fase 6.
- **B-07** `liberar_por_desempate` → não autoriza execução desassistida.
- Limite declarado pelo auditor: a checagem de links/junctions não protege contra alteração concorrente maliciosa entre verificação e uso (TOCTOU); não certificado para sistema de arquivos adversarial.

## Estado
Fase 4 encerrada · **Fase 5 aprovada** · Fase 6 autorizada em ambiente controlado · Execução desassistida bloqueada.
