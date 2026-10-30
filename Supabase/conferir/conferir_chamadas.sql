-- ═══════════════════════════════════════════════════════════════════════════
-- CONFERIDOR DE CHAMADAS — versão SQL, para colar no SQL Editor do Supabase.
--
-- MESMA PERGUNTA do `Supabase/test/conferir-chamadas.mjs`, sem precisar de
-- terminal: o que o workflow do n8n chama existe NESTE banco, com estes tipos?
-- Rode ANTES de subir documento. Leva 1 segundo e evita a rodada que morre no
-- primeiro nó.
--
-- SÓ LEITURA. `PREPARE` faz o Postgres resolver nome e tipos da chamada e NÃO
-- executa a consulta; o `deallocate` logo em seguida não deixa nada para trás.
--
-- POR QUE NÃO É `to_regprocedure`, que seria uma linha. Porque ele exige a
-- assinatura EXATA, e o Postgres resolve chamada com argumento default e com
-- cast implícito. Medido em 02/09 contra o banco completo: a versão com
-- `to_regprocedure` acusou 6 das 15 chamadas como quebradas quando todas as 15
-- funcionam — entre elas `fn_reconciliar_por_documento($1::uuid)`, que resolve
-- pelo default de `p_escopo`. Portão que acusa à toa é portão que se aprende a
-- ignorar, então ele confere a CHAMADA do jeito que o Postgres a resolveria.
--
-- ESTE ARQUIVO É GERADO a partir dos nós Postgres de `N8N/workflow*.json`, por
-- `node Supabase/conferir/gerar-conferir-chamadas.mjs`, e o CI reprova se ele
-- divergir do commitado. Não edite à mão: regere.
-- ═══════════════════════════════════════════════════════════════════════════
create temp table if not exists _conferir(no text, chamada text, resolve boolean, erro text);
truncate _conferir;
do $conf$
declare
  r record; i int := 0;
  alvos text[][] := array[
    ['workflow.e1-ingestao.json · Conferir Envio', 'select r.envio_autorizado as envio_autorizado, r.caso_id as caso_id, r.etapa_recusa as etapa_recusa, r.motivo_recusa as motivo_recusa, r.orcamento_mensagem as orcamento_mensagem, r.usuario_id as usuario_id from fn_conferir_envio($1::text, $2::text) r'],
    ['workflow.e1-ingestao.json · Upsert Caso (Postgres)', 'select fn_upsert_caso($1::text) as caso_id, (select limiar_auto_clear from estagio_autonomia where estagio = ''classificacao_doc_checklist'') as limiar_classificacao'],
    ['workflow.e1-ingestao.json · Registrar Recusa', 'select fn_registrar_falha_execucao($1::uuid, $2::text, $3::text, $4::text, null) as r'],
    ['workflow.e1-ingestao.json · Registrar Documento', 'select fn_registrar_documento($1::uuid,$2::text,$3::text,$4::text,$5::text,$6::numeric,$7::text,$8::origem_arquivo,$9::text,$10::text,$11::boolean,$12::text,$13::legibilidade, p_justificativa=>$14::text, p_fingerprint_extracao=>$15::text, p_cnpj=>$16::text) as r'],
    ['workflow.e1-ingestao.json · Recomputar Completude', 'select fn_recomputar_completude($1::uuid) as resultado'],
    ['workflow.e1-ingestao.json · Gravar Campos (Sombra)', 'select fn_registrar_campos_extraidos($1::uuid, $2::jsonb, p_falha_motivo=>$3::text, p_tem_dado_financeiro=>$4::boolean) as n_campos,
       $5::uuid as documento_id, $1::uuid as documento_versao_id, $6::jsonb as diagnostico'],
    ['workflow.e1-ingestao.json · Registrar Diagnostico', 'select fn_registrar_diagnostico($1::uuid,$2::uuid,$3::text,$4::boolean,$5::text,$6::text,$7::text,$8::legibilidade,$9::text,$10::text,$11::text, p_cnpj=>$13::text) as resultado,
       fn_registrar_fatos($2::uuid,$12::jsonb) as fatos,
       $1::uuid as documento_id'],
    ['workflow.e1-ingestao.json · Reconciliar (Classe A)', 'select fn_reconciliar_por_documento($1::uuid, ''documento'') as resultado'],
    ['workflow.e1-ingestao.json · Reconciliar Lote', 'select fn_reconciliar_caso($1::uuid) as resultado'],
    ['workflow.e1-ingestao.json · Gravar Uso do Lote', 'select fn_registrar_uso_lote($1::uuid,$2::text,$3::jsonb) as resultado'],
    ['workflow.e1-ingestao.json · Abrir Lote', 'select fn_abrir_lote_execucao($1::uuid, $2::text, $3::jsonb) as resultado'],
    ['workflow.e1-ingestao.json · Conferir Lote', 'select fn_conferir_lote($1::uuid) as resultado'],
    ['workflow.erros.json · Registrar Falha', 'select fn_registrar_falha_execucao($1::uuid, $2::text, $3::text, $4::text, $5::jsonb) as r'],
    ['workflow.macro.json · Gravar Índices', 'select * from fn_registrar_indice_macro($1::jsonb)'],
    ['workflow.macro.json · Conferir Fontes', 'select * from fn_divergencias_indice_macro()'],
    ['workflow.macro.json · Gravar Expectativas', 'select fn_registrar_expectativa_macro($1::jsonb) as n']
  ];
begin
  for i in 1 .. array_length(alvos, 1) loop
    begin
      execute 'prepare _c' || i || ' as ' || alvos[i][2];
      execute 'deallocate _c' || i;
      insert into _conferir values (alvos[i][1], alvos[i][2], true, null);
    exception when others then
      insert into _conferir values (alvos[i][1], alvos[i][2], false, SQLERRM);
    end;
  end loop;
end $conf$;
select
  case when count(*) filter (where resolve = false) > 0
       then '*** NAO RODE *** ' || count(*) filter (where resolve = false) || ' de ' || count(*) filter (where resolve is not null) || ' NAO resolvem'
       when count(*) filter (where resolve is null) > 0
       then '*** CONFERENCIA INCOMPLETA *** as ' || count(*) filter (where resolve) || ' chamadas conferidas resolvem, mas '
            || count(*) filter (where resolve is null) || ' NAO FORAM CONFERIDAS (listadas abaixo) — nao rode ate conferi-las'
       else 'PODE RODAR — as ' || count(*) || ' chamadas do n8n resolvem neste banco'
  end as veredito
from _conferir;
select no, erro from _conferir where resolve is not true order by no;
