---
id: decisao-de-pessoa-so-da-mesma-causa
tipo: defeito
toca:
  - Supabase/migrations/0231_o_balanco_sem_dado_financeiro_que_ninguem_via.sql
  - Supabase/test/o_balanco_sem_dado_financeiro.test.sql
prova: Supabase/test/run.sh
---

**Defeito (0231, S124, 10/11/2026; escrita, NÃO aplicada no momento da ficha):** o balanço que a IA
declarava `tem_dado_financeiro = false`, com zero linha e tipo não societário, fechava sem linha e sem
pendência. Medido em produção em 09/11: 42 documentos (13 em mandatos reais: AMOBELEZA 10,
Krauspenhar 1, AMO teste 00 2). A 0231 faz esse caso abrir `extracao_falhou`.

**A armadilha, achada na 2ª revisão independente (ALTO):** a primeira versão tratava QUALQUER
pendência resolvida por pessoa nesse documento como "a pessoa decidiu que não tem número". Uma cota
resolvida à mão calava o balanço para sempre. A 0231 final só conta como decisão a pendência
**desta causa** (`fn_pessoa_decidiu_sem_dado`); a lista de tipos que não precisam de número está em
`fn_tipo_sem_dado_por_natureza`.

**Medido:** o backfill não reabre decisão humana (0 dos 42). `run.sh` rc 0, 3.270 ok.

**A lição:** quando um critério automático respeita "uma pessoa já decidiu", a decisão tem de ser
casada pela MESMA causa. Resolução de outra pendência não vale como resposta a esta.
