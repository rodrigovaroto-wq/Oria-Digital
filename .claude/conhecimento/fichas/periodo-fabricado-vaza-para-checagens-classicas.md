---
id: periodo-fabricado-vaza-para-checagens-classicas
tipo: armadilha
toca:
  - Supabase/migrations/0277_o_aging_que_apagava_a_divergencia_de_um_ano_e_somava_o_pai_com_as_filhas.sql
  - Supabase/test/o_aging_que_apagava_a_divergencia_de_um_ano_e_somava_o_pai_com_as_filhas.test.sql
prova: Supabase/test/run.sh
substitui: []
---

# Período fabricado para separar pendência vaza para as checagens clássicas

**Descoberto em:** 12/11/2026, sessão 129, revisão independente da conciliação do aging (0274).

Uma pendência de conciliação precisa de um período para ser achada. Se o aging é
conciliado por data-base, é tentador criar, uma vez por carteira, um período `data-base`
('AAAA-MM-DD') e prender a pendência a ele. **Não faça isso.**

## O que aconteceu

A primeira versão da 0277 fabricou esse período. Ele entrou no laço de
`fn_periodos_compativeis_array`, que as checagens clássicas usam. Medido na revisão: um
`ativo_passivo_pl` passou a `ok` num período que nenhum documento trouxe. Ou seja, importar um
arquivo de aging mudou o resultado de uma checagem que não tem nada a ver com aging.

Além disso, o período fabricado não tinha forma canônica: o mesmo ano podia ficar com datas-base
diferentes dentro da mesma pendência.

## O remédio que ficou

A chave própria da pendência vai em `fn_registrar_reconciliacao`, do mesmo jeito que `secao_fecha`
e `aging` já são achados pela própria chave, e não por período. Os quatro tipos do aging acham a
pendência pela data-base da carteira. Os outros tipos ficam como estavam.

Nenhum período novo é criado. Importar aging não cria linha em `periodo`.

## A prova

A suíte da 0277 tem o assert do ALTO 2 da revisão: importar aging NÃO muda o que a mesma rodada
das checagens clássicas produz (contagem por tipo, resultado, motivo, período e contagem de
pendências). Está em `Supabase/test/o_aging_que_apagava_a_divergencia_de_um_ano_e_somava_o_pai_com_as_filhas.test.sql`
(linhas 298–322), e o `run.sh` a executa, que o CI roda.

Se a suíte reprovar nesse assert, a lição foi violada. Não ajuste a expectativa para passar: o
assert é o que segura o defeito.
