-- =============================================================================
-- 0215 — O HISTÓRICO DO MANDATO: QUEM FEZ O QUÊ E QUANDO, NUMA SÓ CONSULTA (fn_historico_do_caso)
-- (Portal, redesenho, fase 3, item 24. Só ACRESCENTA uma função de leitura e a registra na sonda. Sem tabela, sem
--  gatilho, sem backfill, sem GRANT de tabela: nenhuma linha muda e o que existia não é tocado.)
--
-- O DEFEITO. A trilha de um mandato existe e está espalhada em OITO lugares que nenhuma tela junta: o recebimento
-- mora em `documento_versao`, o aceite da extração e a revisão do documento em `evento_auditoria`, a correção de
-- classe em `campo_classe_override`, a decisão de pendência em `evento_auditoria`, a pergunta ao cliente em
-- `caso_pergunta`, a premissa em `decisao`, o fechamento em `evento_auditoria` e as colunas `atualizado_por` das
-- tabelas de modelagem. Quem pergunta "o que aconteceu neste caso, e quem fez?" (o sócio antes de assinar, o
-- analista que herda o mandato) hoje abre cinco telas ou o SQL Editor. A função devolve a linha do tempo, da mais
-- nova para a mais velha, a partir do que JÁ é gravado — nada novo passa a ser escrito.
--
-- O QUE ENTRA (medido em 28/10/2026 nas funções de escrita do schema, não por memória), um `tipo` estável por linha:
--   documento_recebido          documento_versao (criada_em, nome_original; versão 2+ diz "nova versão"). Autor NULL: quem
--                               recebe é o n8n. A tabela `documento` não guarda quem enviou; não inventamos.
--   extracao_aceita             evento `extracao_aceita` (fn_aceitar_extracao), com o número de campos aceitos.
--   documento_revisado          evento `documento_revisado` (fn_revisar_documento): "corrigido de X para Y" quando o tipo
--                               mudou, "confirmado" quando não.
--   transcricao_humana          evento `transcricao_humana` (fn_registrar_transcricao_humana).
--   classe_corrigida            campo_classe_override (fn_registrar_classe_override): a linha e a classe final.
--   pendencia_decidida          evento `pendencia_decidida` (fn_decidir_pendencia), com o rótulo da decisão e o motivo.
--   pergunta_enviada / pergunta_descartada   caso_pergunta (append-only, autor + criado_em).
--   premissa_ativada / premissa_removida / premissa_aplicada_em_lote   decisao tipo override (0026/0108 etc.).
--   premissa_vinculada_a_linha  caso_linha_premissa (atualizado_por/em) AGRUPADA por autor e instante, e SEM as linhas
--                               que a aplicação em lote acabou de gravar (essas já aparecem como premissa_aplicada_em_lote:
--                               mesmo `now()` da transação, mesmo autor).
--   modelagem_definida          evento `modelagem_parametros` (fn_definir_modelagem).
--   apresentacao_preenchida     caso_apresentacao_campo (preenchido_por/em): a versão VIGENTE de cada campo, não o histórico
--                               de edições (a tabela não guarda o anterior).
--   caso_criado / caso_aprovado / caso_fechado / caso_reaberto / caso_reconferido   eventos do caso (+ decisao do Portão 2).
--   perimetro_alterado          eventos entidade_* e perimetro_escopo_* (papel, forma de controle, controlador,
--                               participação, escopo definido/encerrado, fusão).
--
-- O QUE NÃO ENTRA, e por quê (regra 1: ausência dita, não fabricada):
--   * EXPORTAÇÕES. Não existe log: o book é gerado no portal e `evento_auditoria` não tem nenhuma ação de exportação
--     (medido: nenhuma acao com "export" no schema inteiro). Quem exportou o quê e quando NÃO é recuperável hoje; criar
--     o registro é uma migration à parte (tabela ou evento), e esta função passa a mostrá-lo no dia em que ele existir.
--   * MUDANÇA DE DIAL: é global (estágio, não caso), conforme o escopo pedido.
--   * RECUSAS (aceite_recusado, aprovacao_recusada, premissa_recusada, mudanca_dial_recusada): são a trilha de uma
--     tentativa que NÃO mudou nada no caso. O histórico conta o que mudou.
--   * Eventos de controlador (`controlador:<id>`: registrado, vínculo familiar): a referência não aponta para o caso e o
--     caso só vem dentro do JSON; resolver pelo JSON varre `evento_auditoria` inteira. Ficam fora até alguém precisar.
--   * Pendência ABERTA pelo sistema: é estado, não ação de pessoa; a decisão sobre ela é que aparece.
--   * `decisao` tipo aprovacao/correcao_classificacao/ressalva/override de pendência: já aparecem pelos eventos acima (o
--     aceite, a revisão e a pendência gravam os DOIS). Ler as duas fontes mostraria cada ato em dobro.
--
-- AUTOR. Texto como foi gravado (e-mail de quem estava logado, ou `portal:desconhecido`); NULL quando o ator é
-- `sistema:*` ou `n8n*`. A tela escreve "sistema" para o NULL: a palavra é da tela, o banco só diz que não foi pessoa.
--
-- COLUNAS: em, tipo, autor, resumo (português corrido, sem código; o nome do tipo de documento e da classe contábil vêm do
-- catálogo), documento_id (quando o evento é de um documento, para a tela abrir o painel) e referencia (jsonb com os
-- ids e o que mais sirva a quem quiser abrir o item).
--
-- PAGINAÇÃO: `p_antes` devolve só o que é ESTRITAMENTE anterior a ele (a tela passa o `em` da última linha que tem).
-- TETO CONHECIDO: dois eventos com o MESMO instante exato (a mesma transação grava vários documentos com o mesmo
-- now()) podem cair um em cada página e o segundo se perder; a ordem de desempate é fixa (tipo, depois referencia)
-- para a ordem ao menos não mudar entre chamadas. Quando doer, o cursor passa a ser (em, tipo, id) — não agora.
-- `p_limite` é cortado em 1..1000 (padrão 200): a função nunca devolve o histórico inteiro de um caso grande de uma vez.
--
-- SEGURANÇA: SECURITY INVOKER (o padrão das leituras vizinhas, 0208 e 0207) — a RLS de quem chama vale; as tabelas
-- lidas já têm policy de SELECT para authenticated (medido em pg_policies). `stable`, só lê. GRANT EXECUTE ao
-- authenticated (a 0028/0207 registra que o Supabase não concede EXECUTE por default privilege) e ao service_role.
-- 0214: nenhuma tabela é criada aqui, então nenhum GRANT de tabela é devido; a sonda do tipo `privilegio` segue verde.
-- Não afirma nada sobre o caso inexistente ou de outra pessoa: sem linha, devolve zero linhas (nunca erro).
--
-- DESEMPENHO. `evento_auditoria` não tem coluna de caso; o caso está no PREFIXO da `entidade_ref`. Por isso as
-- referências do caso (caso, documentos, versões, pendências, entidades) são montadas primeiro, em CTE MATERIALIZED,
-- e `evento_auditoria` entra por igualdade com `idx_evento_entidade_ref`, nunca por LIKE nem por varredura. MATERIALIZED
-- não é enfeite: os dois CTEs são lidos mais de uma vez, mas é a marca de que NÃO podem ser inlinados no join.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/historico_do_caso.test.sql — 35 asserts, medidos em 28/10/2026 com o
-- assert em `raise warning` (voltou para `raise exception`; o log inteiro, sem nenhum FALHOU), a migration conferida como
-- APLICADA em cada variante e a função reaplicada a cada guarda desligada UMA por vez. Controle intacto: 0 dos 35 asserts
-- reprovam (35 ok). Guardas desligadas:
--   * ordem invertida (`order by em asc`): 3 dos 35 asserts reprovam;
--   * ramo da pergunta sem o filtro de caso: 3 dos 35 asserts reprovam e o bloco aborta ("more than one row", o que
--     reprova também todo o resto do arquivo); o mesmo sem o filtro de caso no ramo das premissas: 3 e aborta; no ramo
--     do documento recebido: 2 e aborta;
--   * eventos de auditoria sem a restrição às referências do caso (join `on true`): 12 dos 35 asserts reprovam e aborta;
--   * `p_antes` ignorado: 2 dos 35 asserts reprovam;
--   * autor do sistema não anulado (`sistema:n8n` sai literal): 3 dos 35 asserts reprovam;
--   * `p_limite` sem o piso 1 (0 ou negativo passa direto): 1 dos 35 asserts reprova;
--   * a `decisao` que repete o aceite deixada entrar (cada ato em dobro): 3 dos 35 asserts reprovam e aborta.
-- NÃO MEDIDO, e dito: o ramo que tira de `premissa_vinculada_a_linha` as linhas da aplicação em lote. O teste cobre o
-- vínculo individual (1 linha do tempo com "2 linha(s)"), mas não monta uma aplicação em lote real (exigiria a
-- carga de linhas com seção canônica de fn_aplicar_premissa_em_lote); o `not exists` de `decisao` fica sem assert.
-- =============================================================================

create or replace function fn_historico_do_caso(
  p_caso_id uuid,
  p_limite  int         default 200,
  p_antes   timestamptz default null
)
returns table (
  em           timestamptz,
  tipo         text,
  autor        text,
  resumo       text,
  documento_id uuid,
  referencia   jsonb
)
language sql
stable
security invoker
as $$
  with refs as materialized (
    select 'caso:' || p_caso_id::text as ref, null::uuid as documento_id
    union all
    select 'documento:' || d.id::text, d.id from documento d where d.caso_id = p_caso_id
    union all
    select 'documento_versao:' || v.id::text, d.id
      from documento_versao v join documento d on d.id = v.documento_id
     where d.caso_id = p_caso_id
    union all
    select 'pendencia:' || p.id::text, p.documento_id from pendencia p where p.caso_id = p_caso_id
    union all
    select 'entidade:' || e.id::text, null::uuid from entidade e where e.caso_id = p_caso_id
  ),
  ev as materialized (
    select a.*, r.documento_id as doc_id
      from refs r
      join evento_auditoria a on a.entidade_ref = r.ref
     where a.acao in ('extracao_aceita', 'documento_revisado', 'transcricao_humana', 'pendencia_decidida',
                      'modelagem_parametros', 'caso_criado', 'caso_fechado', 'caso_reaberto', 'reconferir_caso',
                      'perimetro_escopo_definido', 'perimetro_escopo_encerrado', 'entidade_papel_no_grupo_definido',
                      'entidade_forma_de_controle_definida', 'entidade_controlador_definido',
                      'entidade_participacao_definida', 'entidade_fundida')
  ),
  eventos as (
    -- documento recebido
    select v.criada_em as em, 'documento_recebido'::text as tipo, null::text as autor,
           case when v.n_versao > 1
                then format('Nova versão (%s) do arquivo "%s" recebida', v.n_versao, coalesce(v.nome_original, '(sem nome)'))
                else format('Arquivo "%s" recebido', coalesce(v.nome_original, '(sem nome)')) end as resumo,
           d.id as documento_id,
           jsonb_build_object('documento_versao_id', v.id, 'n_versao', v.n_versao) as referencia
      from documento d join documento_versao v on v.documento_id = d.id
     where d.caso_id = p_caso_id

    union all
    select e.criado_em, 'extracao_aceita', e.ator,
           format('Extração aceita: %s campo(s)%s', coalesce(e.depois->>'n_campos_aceitos', '?'),
                  case when nullif(e.depois->>'motivo', '') is not null then ' — ' || (e.depois->>'motivo') else '' end),
           e.doc_id, jsonb_build_object('documento_versao_id', substring(e.entidade_ref from 18))
      from ev e where e.acao = 'extracao_aceita'

    union all
    select e.criado_em, 'documento_revisado', e.ator,
           case when e.antes->>'tipo' is distinct from e.depois->>'tipo'
                then format('Tipo do documento corrigido de "%s" para "%s"',
                            coalesce((select t.documento from taxonomia_tipo_documento t where t.codigo = e.antes->>'tipo'
                                       order by t.versao desc limit 1), e.antes->>'tipo', '(sem tipo)'),
                            coalesce((select t.documento from taxonomia_tipo_documento t where t.codigo = e.depois->>'tipo'
                                       order by t.versao desc limit 1), e.depois->>'tipo', '(sem tipo)'))
                else 'Classificação do documento confirmada' end
             || case when nullif(e.depois->>'motivo', '') is not null then ' — ' || (e.depois->>'motivo') else '' end,
           e.doc_id, jsonb_build_object('tipo_de', e.antes->>'tipo', 'tipo_para', e.depois->>'tipo')
      from ev e where e.acao = 'documento_revisado'

    union all
    select e.criado_em, 'transcricao_humana', e.ator,
           format('Transcrição manual: %s linha(s) digitadas a partir de arquivo ilegível', coalesce(e.depois->>'linhas', '?')),
           coalesce(e.doc_id, nullif(e.depois->>'documento_id', '')::uuid),
           jsonb_build_object('documento_versao_id', substring(e.entidade_ref from 18), 'n_versao', e.depois->'n_versao')
      from ev e where e.acao = 'transcricao_humana'

    union all
    select o.criado_em, 'classe_corrigida', o.autor,
           format('Classe contábil da linha "%s" definida como "%s"', c.chave,
                  coalesce((select k.nome from classe_contabil_catalogo k where k.codigo = o.classe_final), o.classe_final))
             || case when nullif(o.motivo, '') is not null then ' — ' || o.motivo else '' end,
           d.id, jsonb_build_object('campo_extraido_id', o.campo_extraido_id, 'classe_final', o.classe_final,
                                    'sugestao_original', o.sugestao_original)
      from documento d
      join documento_versao v on v.documento_id = d.id
      join campo_extraido c on c.documento_versao_id = v.id
      join campo_classe_override o on o.campo_extraido_id = c.id
     where d.caso_id = p_caso_id

    union all
    select e.criado_em, 'pendencia_decidida', e.ator,
           format('Pendência "%s": %s', coalesce(p.descricao, '(sem descrição)'), coalesce(e.depois->>'rotulo', 'decidida'))
             || case when nullif(e.depois->>'motivo', '') is not null then ' — ' || (e.depois->>'motivo') else '' end,
           p.documento_id, jsonb_build_object('pendencia_id', p.id, 'estado', e.depois->>'estado')
      from ev e join pendencia p on e.entidade_ref = 'pendencia:' || p.id::text
     where e.acao = 'pendencia_decidida'

    union all
    select q.criado_em, 'pergunta_' || case q.acao when 'enviada' then 'enviada' else 'descartada' end, q.autor,
           format('Pergunta "%s" %s', coalesce(pc.titulo, q.pergunta_codigo),
                  case q.acao when 'enviada' then 'enviada ao cliente' else 'descartada' end),
           null::uuid, jsonb_build_object('caso_pergunta_id', q.id, 'pergunta_codigo', q.pergunta_codigo,
                                          'entidade_id', q.entidade_id)
      from caso_pergunta q left join pergunta_catalogo pc on pc.codigo = q.pergunta_codigo
     where q.caso_id = p_caso_id

    union all
    select x.criado_em,
           case when x.payload ? 'n_linhas' then 'premissa_aplicada_em_lote'
                when (x.payload->>'ativo') = 'false' then 'premissa_removida'
                else 'premissa_ativada' end,
           x.autor, x.motivo, null::uuid, x.payload
      from decisao x
     where x.caso_id = p_caso_id and x.tipo = 'override' and x.payload ? 'premissa'

    union all
    select g.atualizado_em, 'premissa_vinculada_a_linha', g.atualizado_por,
           format('%s linha(s) do modelo vinculada(s) a premissa', count(*)),
           null::uuid, jsonb_build_object('n_linhas', count(*), 'premissas', jsonb_agg(distinct g.premissa_codigo))
      from caso_linha_premissa g
     where g.caso_id = p_caso_id
       and g.premissa_codigo is not null
       and not exists (select 1 from decisao x
                        where x.caso_id = p_caso_id and x.tipo = 'override' and x.payload ? 'n_linhas'
                          and x.criado_em = g.atualizado_em and x.autor is not distinct from g.atualizado_por)
     group by g.atualizado_em, g.atualizado_por

    union all
    select e.criado_em, 'modelagem_definida', e.ator,
           format('Parâmetros da modelagem definidos (último exercício real %s, %s ano(s) projetados)',
                  coalesce(e.depois->>'ultimo_exercicio_real', 'não informado'), coalesce(e.depois->>'anos_projetados', '?')),
           null::uuid, e.depois
      from ev e where e.acao = 'modelagem_parametros'

    union all
    select c.preenchido_em, 'apresentacao_preenchida', c.preenchido_por,
           'Dado da apresentação preenchido' || case when c.fonte is not null then ' (fonte: ' || c.fonte || ')' else '' end,
           null::uuid, jsonb_build_object('chave', c.chave)
      from caso_apresentacao_campo c where c.caso_id = p_caso_id

    union all
    select x.criado_em, 'caso_aprovado', x.autor,
           'Caso aprovado no Portão 2' || case when nullif(x.motivo, '') is not null and x.motivo <> 'Portão 2: caso aprovado'
                                               then ' — ' || x.motivo else '' end,
           null::uuid, jsonb_build_object('decisao_id', x.id)
      from decisao x
     where x.caso_id = p_caso_id and x.tipo = 'aprovacao' and x.payload ? 'portao'

    union all
    select e.criado_em, e.acao, e.ator,
           case e.acao
             when 'caso_criado'     then 'Mandato criado'
             when 'caso_fechado'    then 'Mandato fechado'
                                         || case when nullif(e.depois->>'motivo', '') is not null then ' — ' || (e.depois->>'motivo') else '' end
             when 'caso_reaberto'   then 'Mandato reaberto'
             else format('Caso reconferido: %s pendência(s) aberta(s) antes, %s depois',
                         coalesce(e.antes->>'pendencias_abertas', '?'), coalesce(e.depois->>'pendencias_abertas', '?'))
           end,
           null::uuid, '{}'::jsonb
      from ev e where e.acao in ('caso_criado', 'caso_fechado', 'caso_reaberto', 'reconferir_caso')

    union all
    select e.criado_em, 'perimetro_alterado', e.ator,
           format('%s — %s',
                  case e.acao
                    when 'perimetro_escopo_definido'          then 'Escopo do perímetro definido'
                    when 'perimetro_escopo_encerrado'         then 'Escopo do perímetro encerrado'
                    when 'entidade_papel_no_grupo_definido'   then 'Papel no grupo definido'
                    when 'entidade_forma_de_controle_definida' then 'Forma de controle definida'
                    when 'entidade_controlador_definido'      then 'Controlador definido'
                    when 'entidade_participacao_definida'     then 'Participação societária definida'
                    else 'Entidades fundidas' end,
                  coalesce(en.razao_social, '(entidade removida)')),
           null::uuid, jsonb_build_object('acao', e.acao, 'entidade_id', substring(e.entidade_ref from 10))
      from ev e left join entidade en on e.entidade_ref = 'entidade:' || en.id::text
     where e.acao in ('perimetro_escopo_definido', 'perimetro_escopo_encerrado', 'entidade_papel_no_grupo_definido',
                      'entidade_forma_de_controle_definida', 'entidade_controlador_definido',
                      'entidade_participacao_definida', 'entidade_fundida')
  )
  select h.em, h.tipo,
         case when h.autor ~ '^(sistema|n8n)(:|$)' then null else h.autor end,
         h.resumo, h.documento_id, h.referencia
    from eventos h
   where h.em is not null
     and (p_antes is null or h.em < p_antes)
   order by h.em desc, h.tipo, h.referencia::text
   limit least(greatest(coalesce(p_limite, 200), 1), 1000)
$$;

comment on function fn_historico_do_caso(uuid, int, timestamptz) is
  '0215: linha do tempo do mandato (quem fez o quê e quando), da mais nova para a mais velha, montada do que já é gravado: documento recebido, extração aceita, documento revisado, transcrição, classe corrigida, pendência decidida, pergunta enviada/descartada, premissa ativada/removida/em lote/vinculada, modelagem, apresentação, caso criado/aprovado/fechado/reaberto/reconferido, perímetro. autor NULL = o sistema (sistema:* e n8n*). p_antes pagina (estritamente anterior); p_limite 1..1000. NÃO inclui exportações (não há log) nem mudança de dial (global). Somente leitura, security invoker.';

grant execute on function fn_historico_do_caso(uuid, int, timestamptz) to authenticated, service_role;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('historico_do_caso_funcao', '0215', 'funcao', 'fn_historico_do_caso', null, null,
   'A linha do tempo do mandato (quem fez o quê e quando). Ausente, a tela do histórico do portal leva "function does not exist" e o analista volta a juntar a trilha à mão em cinco telas.',
   'importante', 920),
  ('historico_do_caso_corpo', '0215', 'corpo', 'fn_historico_do_caso', 'premissa_vinculada_a_linha', null,
   'Corpo anterior ao desta migration não existe (a função é nova); o marcador pega uma reedição futura que perca o ramo das premissas vinculadas a linhas, e com ele a trilha da modelagem.',
   'importante', 921)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0215', revisado_em = current_date,
       observacao = 'A 0215 cria fn_historico_do_caso (leitura, sem tabela nem backfill). Catalogada por nome e pelo corpo.'
 where id = true;
