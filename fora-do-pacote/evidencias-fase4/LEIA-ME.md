# Evidências brutas da fase 4 (piloto Windows, conta `piloto`) — Ato 042

Arquivos copiados **sem edição** do notebook (`C:\Users\piloto\piloto`), lidos direto pela ponte.
Conferência dos hashes: `sha256sum -c SHA256SUMS.txt` nesta pasta.

| Arquivo | O que prova | Versão do controlador |
|---|---|---|
| `ponte/001-provocacoes.log`, `ponte/002-inspecao.log` | P1/P2 antes da correção: recusa, mas `done` + commit vazio (B-02) | antigo (`f392439`) |
| `ponte/003-relatorio.txt` | Clone do `hibrido@7cd7864`, hash do controlador confere, **harness v0.2.2 40/40 no Windows**, cenário de recusa aprovado, instalação no kit | corrigido (`ced2ec45…`) |
| `ponte/004-relatorio.txt` + `estados/provoca-*-v2/` | P1/P2 repetidas → `hold SEM_ALTERACAO`, sem commit, teste e doc intactos | corrigido |
| `ponte/005-relatorio.txt` | 1ª tentativa de interrupção: **não interrompeu** (defeito do script de teste, não do controlador) | corrigido |
| `ponte/006-relatorio.txt` + `estados/interrupcao2/` | Interrupção real no meio do executor → retomada com rollback, 2 tentativas, 1 commit, teste passa | corrigido |

Observação: o 003 lista só as linhas-resumo do harness (filtro `==|FALHOU|pts|TOTAL`); nenhuma linha FALHOU apareceu.
