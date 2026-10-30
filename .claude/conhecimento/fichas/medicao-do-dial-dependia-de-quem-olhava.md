---
id: medicao-do-dial-dependia-de-quem-olhava
tipo: defeito
toca:
  - Supabase/migrations/0218_a_medicao_que_dependia_de_quem_olhava.sql
  - Supabase/test/medicao_global.test.sql
  - Supabase/migrations/0137_a_promocao_automatica_do_dial.sql
  - Supabase/migrations/0216_o_acesso_que_so_o_portal_decidia.sql
prova: Supabase/test/run.sh
ancora: Supabase/migrations/0218_a_medicao_que_dependia_de_quem_olhava.sql#fn_exige_ler_caso
ancora_sha: 634e3fe5a7e4
substitui: []
---

# A medição do dial dependia de quem olhava (0218, P1b)

Termos de busca: dial, promoção automática, auto_dial, veredito de produção, concordância, golden,
security definer, invoker, RLS por mandato, Analista, Leitura, sem papel, relrowsecurity, sonda rls.

**O que surpreende:** a revisão do PR #264 disse que "um Analista promove o dial de todos com a
concordância só dos mandatos dele". **Sob a 0216 isso não acontecia.** A guarda
`trg_estagio_autonomia_so_socio` barrava a escrita, e o gatilho engolia o erro como NOTICE. O defeito
real era o INVERSO, e foi medido: com o global em 30 a 1,0, a decisão do Analista que completava o
critério deixava o dial em N1 e gravava **0 eventos**. A promoção sumia sem rastro.

**Regra que sobra:** função que MEDE para decidir algo global (dial, critério, cobertura) não pode ser
INVOKER sob RLS por mandato. Ela vira `security definer`, recebe guarda de mandato no parâmetro de
recorte (`fn_exige_ler_caso`: 42501 em vez do zero calado) e ganha requisito `corpo` com o marcador
`SECURITY DEFINER\n SET search_path`. Só o marcador da guarda não basta: `CREATE OR REPLACE` sem
`security definer` volta a função a invoker com o corpo certo e a sonda verde.

**Armadilhas medidas nesta rodada:**
- A exceção da guarda do dial é `current_user` fora de `authenticated`/`anon`. Ela abre para TODA
  definer chamável pelo navegador. A promoção (`fn_dial_auto_promover`) não pode ser RPC: na primeira
  versão, uma Leitura subia o dial por `rpc()`. Quem a chama é o gatilho, também definer.
- "Sem papel: nada" (0216) vale também para agregado global. A primeira guarda deixava passar.
- Assert de trilha no `tdf_test` precisa de `criado_em >= transaction_timestamp()`: outras suítes
  deixam eventos iguais, e o assert passava com a promoção quebrada.
- A sonda não via RLS desligada (a policy continua no catálogo). O tipo `rls` fecha isso, e exclui
  tabela de extensão.

**Pendência registrada, não feita:** view de `public` sem `security_invoker` lê como o dono e
ignora a RLS. As 10 de hoje só tocam catálogo e fixture. Uma view futura sobre dado de mandato vazaria
com a sonda verde.
