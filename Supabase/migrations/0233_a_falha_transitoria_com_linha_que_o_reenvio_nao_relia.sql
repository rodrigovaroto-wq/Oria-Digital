-- =============================================================================
-- 0233 — A FALHA TRANSITÓRIA COM LINHA QUE O REENVIO NÃO RELIA (P8, lado do banco: o reenvio re-extrai quando o PRINCIPAL esgotou a falha transitória e nenhum humano aceitou linha)
-- (Reemite 1 função, fn_versao_extracao_concluida, com a MESMA assinatura, o MESMO retorno e a MESMA ACL; fn_registrar_documento e fn_fila_de_reprocesso a chamam e NÃO são reemitidas.
--  Acrescenta 2 requisitos à sonda. Sem tabela, sem gatilho, sem backfill.)
--
-- O DEFEITO. A 0230 deixou, como teto declarado ("sobe na P8"), a falha COM linha reaproveitada no reenvio: a versão tem linha, logo "concluída". Mas uma parte dessas falhas é do SERVIÇO e não do
-- documento (resposta sem conteúdo, limite de cadência do provedor): o bloco ficou sem leitura porque o modelo principal esgotou a falha transitória, e reenviar o mesmo arquivo com o mesmo prompt teria
-- boa chance de ler. Hoje o reenvio devolve a versão velha em silêncio e a falha fica aberta para sempre.
--
-- A INFORMAÇÃO NOVA. O n8n (fatia P8) passa a gravar no evento `extracao_sombra`, em `depois->'medicao'`, o booleano `falha_transitoria_esgotada` (true = algum bloco ficou sem leitura porque o
-- PRINCIPAL esgotou a falha transitória, mesmo depois do modelo de reserva); `versao_medicao` vira 'p4-2'. Campo ausente (n8n anterior) = comportamento de antes, intacto.
--
-- PARTIDA DO CORPO VIGENTE. Esta função é reemitida a partir do corpo da 0231 (a vigente; a 0230 foi estreitada por ela), não da 0230: a primeira versão desta migration partiu da 0230 e o teste da sonda
-- (instalacao.test.sql) acusou os 2 requisitos da 0231 ausentes. A parte (B) abaixo é a da 0231 sem mudar uma letra.
--
-- A REGRA NOVA. A versão NÃO está concluída (o reenvio re-extrai) quando TODAS valem:
--   1. o ÚLTIMO evento extracao_sombra da versão (criado_em desc, o mesmo critério da 0230) traz `medicao.falha_transitoria_esgotada` igual ao booleano `true` (string "true", número, nulo, ausente = não);
--   2. há `extracao_falhou` aberta no documento (estado <> 'resolvida', o predicado de sempre): sem falha aberta não há o que re-tentar;
--   3. NENHUMA linha da versão foi aceita por humano: `status_aceite <> 'pendente'` E `aceito_por` preenchido E `aceito_por not like 'sistema:%'`. O aceite do sistema (`sistema:auto_aceite`, 0019, confiança >= 95%)
--      NÃO protege: é a máquina aceitando a máquina. `com_ressalva` conta como humano (só pelo fn_aceitar/ressalva de uma pessoa).
-- Quando as 3 valem, a função devolve false mesmo com linha; fora disso o critério é o da 0231 intacto (tem linha OU declaração societária sem dado). A parte societária exige "sem falha aberta", então as duas
-- disjunções não se sobrepõem. Evento ilegível (medicao nula, campo não-booleano) = a regra nova é falsa: NÃO paga (o erro cai para o lado de reaproveitar, ao contrário da 0230: aqui pagar é o risco).
--
-- TETO CONHECIDO, DECLARADO: com aceite HUMANO em qualquer linha da versão o reenvio continua reaproveitando, porque re-extrair cria versão nova e tira da Modelagem a linha aceita (a revisão da 0230 mediu no banco
-- de teste: v1 aceita com valor 100 -> reenvio -> v2 pendente com valor 90). O custo é que essa falha transitória fica aberta até alguém resolvê-la ou o prompt mudar. Sobe quando o reenvio souber
-- reaproveitar as linhas aceitas na versão nova (outra fatia).
--
-- A FILA (0232) ACOMPANHA SOZINHA. `fn_fila_de_reprocesso` pergunta a mesma função: o documento com falha transitória esgotada e sem aceite humano passa de 'reaproveitaria' a `reprocessavel` (se há original no
-- bucket). Os chamadores de fn_versao_extracao_concluida (grep em Supabase/ N8N/ portal/src/): fn_registrar_documento (0230), fn_fila_de_reprocesso (0232) e N8N/build-workflow.mjs:188 (só texto/consulta);
-- a semântica muda para todos juntos, no ponto único. O n8n NÃO precisa ser republicado por esta migration (a coluna do retorno é a mesma; só passa a valer quando o n8n P8 gravar o campo).
--
-- MEDIDO EM PRODUÇÃO (somente leitura, 10/11/2026), ANTES:
--   * eventos extracao_sombra: 2.064, NENHUM com `medicao.falha_transitoria_esgotada` (maior versao_medicao = 'p4-1'). Logo a regra nova alcança 0 versões hoje: é esperado, o campo é novo. Depois do n8n P8 passa a valer.
--   * 535 documentos com extracao_falhou aberta; 77 têm linha na última versão (a medição da 0232 dizia 70: mais falhas abriram desde então); 4 desses 77 têm aceite humano em alguma linha
--     (285 linhas aceitas por humano no banco todo, 88.913 pelo sistema, 34.679 pendentes). Dos 77, 4 trazem no texto da falha um motivo transitório (`sem conteúdo`, cadência, 429, overload, timeout).
--   * DEPOIS (regra simulada em CTE, sem o campo): 0 versões mudam de resposta. Das 4 com texto transitório, o texto NÃO é o gatilho (a regra só olha o campo do n8n): elas continuam reaproveitadas até o reenvio por um n8n P8.
--
-- SEM BACKFILL: o critério é lido na hora.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/reextracao_transitoria.test.sql — 23 asserts (23 execuções), medidos em 10/11/2026 com o assert trocado por raise warning (`p8.medindo = on`), que CONTA; cada sabotagem
-- é a função reemitida sobre o banco já montado pelo run.sh (cópia por template, teste rodado inteiro, aviso MEDIDO lido; conferido que a sabotagem aplicou). Controle (migration intacta): 0 dos 23 reprovam.
-- Sem a condição do campo (a regra valendo para qualquer evento): 7 reprovam (6 de comportamento, 1 da sonda). Sem a condição da falha aberta: 2. Sem a do aceite humano: 5 (4 + 1 da sonda). Com o aceite do SISTEMA
-- contando como humano: 2 (1 + 1 da sonda). Função da 0231 de volta (regra nova ausente): 6 (5 + 1 da sonda). Os asserts de controle (campo ausente/falso/"true" em texto/medição nula, falha resolvida, evento mais
-- novo) passam na função antiga de propósito: protegem o comportamento de antes.
-- =============================================================================

begin;

create or replace function fn_versao_extracao_concluida(p_documento_versao_id uuid)
returns boolean
language sql
stable
as $$
  -- (1) tem linha (0118) E NÃO é falha transitória esgotada sem aceite humano (0233); (2) ou a declaração sem dado financeiro (0230, estreitada pela 0231: tipo sem dado por natureza OU decisão de pessoa). Parte ilegível = não vale como "re-extrair" (a 0233 reaproveita) e
  -- não vale como "declaração" (a 0230 paga): cada lado erra para o seu lado seguro.
  select (exists (select 1 from campo_extraido ce where ce.documento_versao_id = p_documento_versao_id)
          and not coalesce((
            select u.depois->'medicao'->'falha_transitoria_esgotada' = 'true'::jsonb
               -- falha aberta no documento: o predicado de sempre (estado <> resolvida)
               and exists (select 1
                             from documento_versao dv
                             join pendencia pe on pe.documento_id = dv.documento_id
                            where dv.id = p_documento_versao_id
                              and pe.tipo = 'extracao_falhou'
                              and pe.estado <> 'resolvida')
               -- aceite HUMANO em alguma linha da versão: re-extrair tiraria da Modelagem a linha aceita (teto declarado no cabeçalho)
               and not exists (select 1
                                 from campo_extraido ce
                                where ce.documento_versao_id = p_documento_versao_id
                                  and ce.status_aceite <> 'pendente'
                                  and ce.aceito_por is not null
                                  and ce.aceito_por not like 'sistema:%')
              from evento_auditoria u
             where u.acao = 'extracao_sombra'
               and u.entidade_ref = 'documento_versao:' || p_documento_versao_id::text
             order by u.criado_em desc
             limit 1
          ), false))
      or coalesce((
    select u.depois->>'falha_motivo' is null
       and u.depois->>'tem_dado_financeiro' = 'false'
       -- (2a) tipo societário/legal SEM conta contada pela régua, OU uma PESSOA resolveu a extracao_falhou do documento. A decisão
       -- de pessoa vale com qualquer contagem: a régua conta CPF/OAB/percentual como conta (medido na procuração do book-espelho: 9),
       -- e foi a pessoa, com o arquivo aberto, que decidiu que não há número. Pagar de novo só repetiria a leitura que ela já julgou.
       and ((fn_tipo_sem_dado_por_natureza((select d.tipo_taxonomia from documento_versao dv join documento d on d.id = dv.documento_id where dv.id = p_documento_versao_id))
             and (u.depois->'medicao'->>'contas_no_documento' is null
                  or (u.depois->'medicao'->>'contas_no_documento' ~ '^[0-9]+(\.[0-9]+)?$'
                      and (u.depois->'medicao'->>'contas_no_documento')::numeric = 0)))
            or fn_pessoa_decidiu_sem_dado((select dv.documento_id from documento_versao dv where dv.id = p_documento_versao_id)))
       and not exists (select 1
                         from documento_versao dv
                         join pendencia pe on pe.documento_id = dv.documento_id
                        where dv.id = p_documento_versao_id
                          and pe.tipo = 'extracao_falhou'
                          and pe.estado <> 'resolvida')
      from evento_auditoria u
     where u.acao = 'extracao_sombra'
       and u.entidade_ref = 'documento_versao:' || p_documento_versao_id::text
     order by u.criado_em desc
     limit 1
  ), false)
$$;

comment on function fn_versao_extracao_concluida(uuid) is
  '0233 (sobre a 0231): a versão já foi extraída (vale reaproveitar no reenvio)? Verdadeira quando (A) a versão TEM linha em campo_extraido (o critério da 0118) E NÃO se dá o caso de falha transitória esgotada: o ÚLTIMO evento extracao_sombra traz medicao.falha_transitoria_esgotada = true (booleano; o n8n P8 grava), há extracao_falhou aberta no documento (estado <> resolvida) e nenhuma linha da versão foi aceita por humano (status_aceite <> pendente, aceito_por preenchido e fora de sistema:%); OU (B) o corpo da 0231 INTACTO: o último evento extracao_sombra existe, sem falha_motivo, com tem_dado_financeiro = false explícito, e (tipo sem dado por natureza, fn_tipo_sem_dado_por_natureza, sem conta contada, OU uma pessoa resolveu a falha, fn_pessoa_decidiu_sem_dado), e sem extracao_falhou aberta (0230/0231). Com aceite humano o reenvio continua reaproveitando mesmo com falha transitória (teto: re-extrair tira da Modelagem a linha aceita). Campo ausente/ilegível = reaproveita como antes. A pergunta de fn_registrar_documento e de fn_fila_de_reprocesso: uma implementação só. SECURITY INVOKER, somente leitura.';

revoke all on function fn_versao_extracao_concluida(uuid) from public;
grant execute on function fn_versao_extracao_concluida(uuid) to authenticated, service_role;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_versao_extracao_concluida(uuid) to supabase_read_only_user';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO, nunca de comentário (pg_get_functiondef traz os comentários do corpo: um marcador citado num comentário passaria sem a lógica).
-- ---------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('reenvio_rele_falha_transitoria_esgotada', '0233', 'corpo', 'fn_versao_extracao_concluida', '''falha_transitoria_esgotada''', null,
   'A versão com linha e com o último evento marcando falha_transitoria_esgotada = true, falha aberta e sem aceite humano NÃO é concluída. Corpo sem isto = a falha transitória com linha nunca ganha nova chance no reenvio (teto da 0230), e a fila a mostra como reaproveitaria.',
   'importante', 1074),
  ('reenvio_respeita_aceite_humano', '0233', 'corpo', 'fn_versao_extracao_concluida', 'aceito_por not like ''sistema:%''', null,
   'O aceite HUMANO de uma linha da versão segura o reaproveitamento (re-extrair tira da Modelagem a linha aceita: v1 aceita 100 -> v2 pendente 90). Corpo sem isto = o reenvio por falha transitória apaga o aceite do analista; com o aceite do sistema (auto_aceite) a proteção não vale.',
   'importante', 1075)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0233', revisado_em = current_date,
       observacao = 'A 0233 reemite fn_versao_extracao_concluida: falha transitória esgotada (campo do n8n P8 em medicao) com linha, falha aberta e sem aceite humano deixa de ser reaproveitada no reenvio; 2 requisitos novos.'
 where id = true;

commit;
