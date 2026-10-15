--
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';

--
-- Name: caso_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.caso_status AS ENUM (
    'intake',
    'em_triagem',
    'completude_ok',
    'em_revisao',
    'aprovado',
    'pronto_para_base',
    'bloqueado',
    'aguardando_cliente'
);

--
-- Name: controlador_tipo_pessoa; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.controlador_tipo_pessoa AS ENUM (
    'fisica',
    'juridica'
);

--
-- Name: TYPE controlador_tipo_pessoa; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TYPE public.controlador_tipo_pessoa IS '0182: pessoa física ou jurídica que detém participação num controlador comum. Vocabulário FECHADO e universalmente conhecido (dicotomia do direito civil brasileiro) — não é um rótulo de domínio deste projeto que possa crescer, ao contrário de `perimetro.escopo` (0180, texto livre por vocabulário não medido). Mesmo critério da 0179 para `papel_no_grupo` (enum): vocabulário fechado e conhecido vira enum; vocabulário aberto e não medido fica texto livre.';

--
-- Name: decisao_tipo; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.decisao_tipo AS ENUM (
    'aprovacao',
    'override',
    'ressalva',
    'mudanca_dial',
    'correcao_classificacao'
);

--
-- Name: documento_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.documento_status AS ENUM (
    'solicitado',
    'recebido',
    'em_validacao',
    'valido',
    'invalido',
    'recebido_nao_valido',
    'vencido'
);

--
-- Name: entidade_forma_de_controle; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.entidade_forma_de_controle AS ENUM (
    'indefinido',
    'controlada_por_entidade',
    'controle_comum'
);

--
-- Name: TYPE entidade_forma_de_controle; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TYPE public.entidade_forma_de_controle IS '0183 (fatia 1.7b do plano F1): o que torna `entidade.controladora_id` NULO distinguível de "ninguém preencheu ainda". TRÊS rótulos, e um QUARTO foi CONSIDERADO E RECUSADO por falta de medição — ver o cabeçalho da migration 0183 para o motivo completo. `indefinido` é o DEFAULT de toda entidade (a ausência honesta); `controlada_por_entidade` é o mundo da 0181 (controladora_id preenchido); `controle_comum` é o mundo da 0182 (grupo horizontal, controladora_id NULO e pelo menos um vínculo em entidade_controlador). Só `fn_entidade_definir_forma_de_controle` escreve aqui — nunca inferência automática (regra 1 do CLAUDE.md).';

--
-- Name: entidade_papel_no_grupo; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.entidade_papel_no_grupo AS ENUM (
    'holding',
    'operacional',
    'veiculo',
    'coligada',
    'fora_do_perimetro'
);

--
-- Name: TYPE entidade_papel_no_grupo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TYPE public.entidade_papel_no_grupo IS '0179: papel da entidade dentro do grupo do mandato. Tipado a partir de `entidade.papel_no_grupo` (text livre desde a 0001, NULL em todo caso do banco — fatia 1.3 do plano F1). Não existe sinal automático para preenchê-lo (sem tabela participacao/hierarquia — fatia 1.5, futura): o único caminho de escrita é `fn_entidade_definir_papel_no_grupo`, chamado por um humano.';

--
-- Name: golden_estrato; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.golden_estrato AS ENUM (
    'digital',
    'pdf_nativo',
    'escaneado',
    'foto'
);

--
-- Name: TYPE golden_estrato; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TYPE public.golden_estrato IS 'Qualidade de captura do documento (Arquitetura do Sistema/2 Especificação/f0/06, amostragem estratificada). A métrica agregada sobre estratos misturados esconde o pior caso, que é justamente o que decide se o dial pode subir.';

--
-- Name: golden_origem; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.golden_origem AS ENUM (
    'real',
    'sintetico'
);

--
-- Name: TYPE golden_origem; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TYPE public.golden_origem IS 'real = documento de cliente. sintetico = book gerado (Dados de Teste/). As métricas que governam o dial contam SÓ real: rotular um book cujo GABARITO.json já se conhece mede o instrumento, não o modelo — é a ressalva que o cabeçalho do medir-auto-aceite.mts carrega desde que existe.';

--
-- Name: granularidade; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.granularidade AS ENUM (
    'caso',
    'entidade',
    'periodo',
    'entidade_periodo'
);

--
-- Name: legibilidade; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.legibilidade AS ENUM (
    'ok',
    'degradado',
    'ilegivel'
);

--
-- Name: nivel_autonomia; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.nivel_autonomia AS ENUM (
    'N0',
    'N1',
    'N2',
    'N3'
);

--
-- Name: obrigatoriedade; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.obrigatoriedade AS ENUM (
    'obrigatorio',
    'complementar'
);

--
-- Name: origem_arquivo; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.origem_arquivo AS ENUM (
    'supabase_storage',
    'sharepoint'
);

--
-- Name: pendencia_estado; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.pendencia_estado AS ENUM (
    'aberta',
    'em_correcao_interna',
    'reenviada_ao_cliente',
    'aceita_com_ressalva',
    'rejeitada',
    'resolvida'
);

--
-- Name: pendencia_severidade; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.pendencia_severidade AS ENUM (
    'bloqueante',
    'importante',
    'complementar'
);

--
-- Name: pendencia_tipo; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.pendencia_tipo AS ENUM (
    'item_faltante',
    'periodo_faltante',
    'item_vencido',
    'arquivo_ilegivel',
    'arquivo_corrompido',
    'entidade_incorreta',
    'periodo_incorreto',
    'tipo_incorreto',
    'classificacao_pendente',
    'divergencia_reconciliacao',
    'precondicao_nao_satisfeita',
    'extracao_baixa_confianca',
    'extracao_padrao_suspeito',
    'extracao_falhou',
    'item_sem_conteudo',
    'documento_nao_extraido',
    'linha_exigida_ausente',
    'papel_no_grupo_indefinido',
    'forma_de_controle_indefinida'
);

--
-- Name: premissa_formula; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.premissa_formula AS ENUM (
    'indice_macro',
    'crescimento_composto',
    'pct_de_linha',
    'dias_de_giro',
    'valor_por_ano',
    'preco_x_volume',
    'curva_mensal'
);

--
-- Name: premissa_natureza; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.premissa_natureza AS ENUM (
    'macro',
    'receita',
    'custo',
    'despesa',
    'giro',
    'investimento',
    'divida',
    'tributo',
    'socios',
    'sazonalidade',
    'operacional'
);

--
-- Name: sensibilidade_lgpd; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.sensibilidade_lgpd AS ENUM (
    'nenhuma',
    'pii',
    'pii_sensivel'
);

--
-- Name: fn_abrir_lote_execucao(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_abrir_lote_execucao(p_caso_id uuid, p_execucao_ref text, p_plano jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_id uuid;
begin
  if p_caso_id is null then
    return jsonb_build_object('aberto', false, 'motivo', 'caso_id ausente');
  end if;
  -- SEM REFERÊNCIA DE EXECUÇÃO NÃO SE ABRE, pelo mesmo motivo da 0115: é a chave
  -- que impede a duplicidade. Sem ela, cada ramo abriria a sua linha.
  if nullif(btrim(coalesce(p_execucao_ref, '')), '') is null then
    return jsonb_build_object('aberto', false, 'motivo', 'execucao_ref ausente');
  end if;

  insert into lote_execucao (
    caso_id, execucao_ref,
    documentos_planejados, chamadas_planejadas, cota_fracao_planejada,
    custo_estimado_usd, orcamento_versao
  ) values (
    p_caso_id, btrim(p_execucao_ref),
    (p_plano->>'documentos_planejados')::int,
    (p_plano->>'chamadas_planejadas')::int,
    (p_plano->>'cota_fracao_planejada')::numeric,
    (p_plano->>'custo_estimado_usd')::numeric,
    p_plano->>'orcamento_versao'
  )
  on conflict (caso_id, execucao_ref) do update set
    atualizado_em = now(),
    -- SÓ O PLANO É REESCRITO AQUI. As colunas do realizado ficam intocadas: se
    -- os dois ramos abrirem o lote e um deles chegar depois do fechamento (o n8n
    -- não garante ordem entre ramos), reescrever o realizado com nulo apagaria a
    -- medição da execução que terminou. `coalesce` mantém o que já havia quando
    -- a segunda abertura vier sem o campo.
    documentos_planejados = coalesce(excluded.documentos_planejados, lote_execucao.documentos_planejados),
    chamadas_planejadas   = coalesce(excluded.chamadas_planejadas, lote_execucao.chamadas_planejadas),
    cota_fracao_planejada = coalesce(excluded.cota_fracao_planejada, lote_execucao.cota_fracao_planejada),
    custo_estimado_usd    = coalesce(excluded.custo_estimado_usd, lote_execucao.custo_estimado_usd),
    orcamento_versao      = coalesce(excluded.orcamento_versao, lote_execucao.orcamento_versao)
  returning id into v_id;

  return jsonb_build_object('aberto', true, 'lote_execucao_id', v_id);
end $$;

--
-- Name: FUNCTION fn_abrir_lote_execucao(p_caso_id uuid, p_execucao_ref text, p_plano jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_abrir_lote_execucao(p_caso_id uuid, p_execucao_ref text, p_plano jsonb) IS 'Abre a linha de lote_execucao no instante em que o orçamento aceita o lote, com o PLANO. Existe porque a linha só era escrita no fim da cadeia: a rodada de 190 documentos de 27/08 foi cancelada e não deixou rastro nenhum, levando junto documentos_fatiados — o número de que a investigação precisava. Observabilidade que depende de a rodada dar certo não é observabilidade.';

--
-- Name: fn_aceitar_extracao(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_aceitar_extracao(p_documento_versao_id uuid, p_autor text, p_motivo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_documento_id uuid;
  v_caso_id      uuid;
  v_nome         text;
  v_n_campos     int;
  v_n_aceitos    int;
begin
  select d.id, d.caso_id, dv.nome_original into v_documento_id, v_caso_id, v_nome
  from documento_versao dv
  join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    raise exception 'documento_versao % não encontrada', p_documento_versao_id;
  end if;

  select count(*) into v_n_campos from campo_extraido where documento_versao_id = p_documento_versao_id;

  if v_n_campos = 0 then
    -- RECUSA RETORNADA, não `raise exception` — e a razão é técnica, não de gosto:
    -- exceção em plpgsql desfaz TUDO o que a função fez, inclusive o registro da
    -- tentativa em `evento_auditoria`. A primeira versão desta função levantava
    -- exceção e o teste flagrou que o rastro da tentativa desaparecia junto. Como
    -- Postgres não tem transação autônoma, ou se tem a exceção, ou se tem o
    -- registro. O registro é mais valioso: a recusa já é evidente no retorno.
    --
    -- Nada é gravado como aprovação, e `recusado` sai no payload para nenhum
    -- chamador poder confundir isto com sucesso.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'aceite_recusado', 'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('porque', 'versao sem nenhum campo extraido',
                                 'documento_id', v_documento_id, 'motivo_informado', p_motivo));
    return jsonb_build_object(
      'documento_versao_id', p_documento_versao_id,
      'n_campos_aceitos', 0,
      'recusado', true,
      'motivo_recusa', format(
        'Não há o que aceitar em "%s": esta versão não tem NENHUMA linha extraída. Aceitar aqui '
        'gravaria uma aprovação formal de nada na trilha de auditoria (e `decisao` é append-only). '
        'Veja a pendência de extração deste documento — formato não convertido, arquivo ilegível ou '
        'chamada que falhou — e reenvie o arquivo.',
        coalesce(v_nome, p_documento_versao_id::text)));
  end if;

  update campo_extraido
    set status_aceite = 'aceito', aceito_por = p_autor, aceito_em = now()
  where documento_versao_id = p_documento_versao_id
    and status_aceite <> 'aceito';
  get diagnostics v_n_aceitos = row_count;

  if v_n_aceitos = 0 then
    -- Tudo já estava aceito: não há decisão nova a registrar. O evento fica,
    -- para o clique não desaparecer do histórico.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'aceite_sem_efeito', 'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('porque', 'todas as linhas ja estavam aceitas', 'n_campos', v_n_campos));
    return jsonb_build_object('documento_versao_id', p_documento_versao_id,
                              'n_campos_aceitos', 0, 'ja_estava_aceito', true);
  end if;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (v_caso_id, 'aprovacao', p_autor, p_motivo,
      jsonb_build_object('documento_versao_id', p_documento_versao_id, 'n_campos_aceitos', v_n_aceitos));

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values (p_autor, 'extracao_aceita', 'documento_versao:' || p_documento_versao_id,
      jsonb_build_object('n_campos_aceitos', v_n_aceitos, 'motivo', p_motivo));

  return jsonb_build_object('documento_versao_id', p_documento_versao_id, 'n_campos_aceitos', v_n_aceitos);
end;
$$;

--
-- Name: fn_ano4(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_ano4(a text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
  select case
    when a is null or a = '' then a
    when length(a) = 4 then a
    when a ~ '^\d{1,2}$' and (a)::int <= 79 then (2000 + (a)::int)::text
    when a ~ '^\d{1,2}$' then (1900 + (a)::int)::text
    else a end;
$_$;

--
-- Name: fn_ano_da_coluna(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_ano_da_coluna(p_periodo_coluna text, p_referencia text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $_$
  -- Quatro dígitos que comecem com 19 ou 20, na coluna primeiro. `substring` com
  -- classe de caractere e não regexp guloso: "12M25" não pode virar 1225.
  select coalesce(
    (select (regexp_match(p_periodo_coluna, '((?:19|20)\d{2})'))[1]::int),
    (select (regexp_match(p_referencia, '((?:19|20)\d{2})'))[1]::int),
    -- "12M25"/"24,25" — dois dígitos que o repositório usa como referência curta.
    -- 2000+ é seguro para este projeto (mandato de reestruturação não tem balanço
    -- de 1925), e o teste trava o comportamento.
    (select 2000 + (regexp_match(p_referencia, '(\d{2})\s*$'))[1]::int)
  );
$_$;

--
-- Name: FUNCTION fn_ano_da_coluna(p_periodo_coluna text, p_referencia text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_ano_da_coluna(p_periodo_coluna text, p_referencia text) IS 'Exercício de uma ocorrência: ano da coluna de período, senão da referência do período do documento, senão dois dígitos finais + 2000. A coluna vem primeiro porque num balanço comparativo é ela que diz de qual exercício é o número.';

--
-- Name: fn_anos_alvo(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_anos_alvo(p_periodo_id uuid) RETURNS integer[]
    LANGUAGE plpgsql STABLE
    AS $$
declare
  t text; r text; anos int[];
begin
  if p_periodo_id is null then return array[null]::int[]; end if;
  select tipo, referencia into t, r from periodo where id = p_periodo_id;
  anos := fn_anos_periodo(t, r);
  if cardinality(coalesce(anos, '{}'::int[])) = 0 then return array[null]::int[]; end if;
  return anos;
end;
$$;

--
-- Name: fn_anos_do_periodo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_anos_do_periodo(p_referencia text) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
    AS $_$
  select case
    when p_referencia is null then '{}'::int[]
    when p_referencia ~ '^\s*[0-9]{2}\s*(,\s*[0-9]{2}\s*)+$' then (
      select array_agg(distinct ('20' || trim(t))::int order by ('20' || trim(t))::int)
      from unnest(string_to_array(p_referencia, ',')) t)
    else fn_anos_texto(p_referencia)
  end;
$_$;

--
-- Name: FUNCTION fn_anos_do_periodo(p_referencia text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_anos_do_periodo(p_referencia text) IS 'Anos que uma referência de PERÍODO denota (0122). Difere de fn_anos_texto por expandir a lista de dois dígitos do formato multi ("23,24,25" → 2023, 2024, 2025), que é formato nosso — em rótulo de coluna de planilha a mesma sequência pode ser um valor.';

--
-- Name: fn_anos_periodo(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_anos_periodo(p_tipo text, p_ref text) RETURNS integer[]
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
declare
  canonico text := fn_periodo_canonico(p_tipo, p_ref);
  anos int[] := '{}';
  tok text;
  m text[];
begin
  if canonico is null then return anos; end if;
  -- 0198: FAIXA "AAAA-AAAA" (ou "AAAAaAAAA", "AAAA–AAAA") inteira = todos os anos dela. Só quando
  -- é crescente e de até 10 anos; fora disso cai no comportamento antigo (as pontas).
  m := regexp_match(canonico, '^((?:19|20)[0-9]{2})(?:-|–|—|a|ate|até)((?:19|20)[0-9]{2})$');
  if m is not null and m[2]::int >= m[1]::int and m[2]::int - m[1]::int <= 10 then
    return array(select generate_series(m[1]::int, m[2]::int));
  end if;
  -- anos de 4 dígitos explícitos (cobre ISO, ano isolado, listas já expandidas)
  foreach tok in array regexp_split_to_array(canonico, '[^0-9]+') loop
    if tok ~ '^(19|20)[0-9]{2}$' then
      anos := anos || (tok)::int;
    end if;
  end loop;
  select array_agg(distinct a order by a) into anos from unnest(anos) a;
  return coalesce(anos, '{}'::int[]);
end;
$_$;

--
-- Name: FUNCTION fn_anos_periodo(p_tipo text, p_ref text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_anos_periodo(p_tipo text, p_ref text) IS 'Conjunto ordenado de anos implícito num período (qualquer notação). Vazio quando a referência não ancora ano. 0198: a FAIXA "AAAA-AAAA" devolve todos os anos dela (2024-2026 = 2024, 2025, 2026); a lista "2024,2026" devolve só os listados.';

--
-- Name: fn_anos_texto(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_anos_texto(p_texto text) RETURNS integer[]
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
declare
  anos int[] := '{}';
  tok  text;
  m    text[];
  txt  text;
begin
  if p_texto is null then return anos; end if;
  -- A NOTAÇÃO DE JANELA MÓVEL SAI ANTES DE PROCURAR ANO. `L24M`, `L36M`, `L12M`
  -- (Arquitetura do Sistema/2 Especificação/f0/03) dizem QUANTOS MESES a série cobre, não em que ano ela termina. A
  -- borda de palavra impede comer o "L" de outra coisa, e a limpeza é cirúrgica:
  -- "L24M 2025" continua devolvendo 2025, e `12M25` continua devolvendo 2025
  -- (lá o final é o ano, e a janela está na frente).
  txt := regexp_replace(p_texto, '(^|[^0-9A-Za-z])[Ll][0-9]{1,3}[Mm]([^0-9A-Za-z]|$)',
                        '\1 \2', 'g');
  foreach tok in array regexp_split_to_array(txt, '[^0-9]+') loop
    if tok ~ '^(19|20)[0-9]{2}$' then
      anos := anos || (tok)::int;
    end if;
  end loop;
  if cardinality(anos) = 0 then
    -- ano de 2 dígitos no fim ("dez/25", "12M25")
    m := regexp_match(txt, '([0-9]{2})[^0-9]*$');
    if m is not null then
      anos := anos || ('20' || m[1])::int;
    end if;
  end if;
  select array_agg(distinct a order by a) into anos from unnest(anos) a;
  return coalesce(anos, '{}'::int[]);
end;
$_$;

--
-- Name: FUNCTION fn_anos_texto(p_texto text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_anos_texto(p_texto text) IS 'Anos que um rótulo de período/coluna denota (0023). Desde a 0122 a notação de JANELA MÓVEL (L24M, L36M) não é lida como ano: ela diz o tamanho da série, não o exercício — antes L36M devolvia 2036 e vencia a escolha de período da pergunta ao cliente.';

--
-- Name: fn_aplicar_premissa_em_lote(uuid, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_aplicar_premissa_em_lote(p_caso_id uuid, p_secao_canonica text, p_premissa text, p_autor text, p_sazonalidade text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_n int := 0;
  v_ignoradas jsonb := '[]'::jsonb;
  v_r jsonb;
  v_linha record;
begin
  if not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_premissa and ativo
  ) then
    return jsonb_build_object('recusado', true, 'escopo', 'premissa',
      'motivo_recusa', format('A premissa "%s" não está ativa neste caso.', p_premissa));
  end if;

  for v_linha in
    select l.secao_canonica, l.chave, l.entidade, l.papel
    from fn_linhas_para_modelagem(p_caso_id) l
    where coalesce(l.secao_canonica, '') = coalesce(p_secao_canonica, '')
  loop
    if v_linha.papel <> 'conta' then
      v_ignoradas := v_ignoradas || jsonb_build_object('linha', v_linha.chave, 'papel', v_linha.papel);
      continue;
    end if;
    v_r := fn_vincular_linha_premissa(p_caso_id, v_linha.secao_canonica, v_linha.chave,
                                      v_linha.entidade, p_premissa, p_autor, p_sazonalidade);
    if coalesce((v_r->>'recusado')::boolean, false) then
      -- Global: não adianta tentar as outras.
      if v_r->>'escopo' = 'premissa' then
        return v_r;
      end if;
      -- Por linha: registra e segue.
      --
      -- HONESTIDADE SOBRE ESTE RAMO: com a guarda lendo o papel da SEÇÃO, ele
      -- fica INALCANÇÁVEL a partir daqui — o laço só percorre linhas cujo papel
      -- na seção é 'conta', e a guarda agora responde exatamente isso para a
      -- mesma seção. Ou seja: **este ramo não está coberto por teste**, e não dá
      -- para cobrir sem religar o defeito que a migration corrige.
      --
      -- Fica assim mesmo, por uma razão: ele é a diferença entre "uma linha
      -- divergente é declarada" e "o lote inteiro cai", e a divergência volta a
      -- existir no instante em que alguém mudar um dos dois lados sem mudar o
      -- outro — que é precisamente o que aconteceu entre a 0039 e a 0042.
      v_ignoradas := v_ignoradas || jsonb_build_object(
        'linha', v_linha.chave,
        'papel', coalesce(v_r->>'papel', 'recusada'),
        'motivo', v_r->>'motivo_recusa');
      continue;
    end if;
    v_n := v_n + 1;
  end loop;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'override', p_autor,
            format('Premissa "%s" aplicada em lote a %s linha(s) da seção "%s" (%s fora por papel)',
                   p_premissa, v_n, coalesce(p_secao_canonica, '(sem seção)'),
                   jsonb_array_length(v_ignoradas)),
            jsonb_build_object('premissa', p_premissa, 'secao_canonica', p_secao_canonica,
                               'n_linhas', v_n, 'sazonalidade', p_sazonalidade,
                               'ignoradas', v_ignoradas));

  return jsonb_build_object('caso_id', p_caso_id, 'secao_canonica', p_secao_canonica,
                            'premissa', p_premissa, 'n_linhas', v_n,
                            'n_ignoradas', jsonb_array_length(v_ignoradas),
                            'ignoradas', v_ignoradas);
end;
$$;

--
-- Name: fn_aprovar_caso(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_aprovar_caso(p_caso_id uuid, p_autor text, p_motivo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_aval   jsonb;
  v_status caso_status;
begin
  v_aval := fn_avaliar_portao2(p_caso_id);
  select status into v_status from caso where id = p_caso_id;

  if not (v_aval->>'elegivel')::boolean then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'aprovacao_recusada', 'caso:'||p_caso_id,
              jsonb_build_object('avaliacao', v_aval, 'motivo_informado', p_motivo));
    return v_aval || jsonb_build_object(
      'recusado', true,
      'motivo_recusa',
        'Este caso NÃO é elegível ao Portão 2: '
        || array_to_string(array(select jsonb_array_elements_text(v_aval->'motivos')), '; ')
        || '. A regra é determinística (Arquitetura do Sistema/2 Especificação/f0/04) e não tem exceção por autor — resolva as '
        || 'pendências ou registre ressalva onde ela é permitida.');
  end if;

  -- Idempotente: aprovar um caso já aprovado não gera decisão nova.
  if v_status in ('aprovado', 'pronto_para_base') then
    return v_aval || jsonb_build_object('ja_aprovado', true);
  end if;

  update caso set status = 'aprovado' where id = p_caso_id;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'aprovacao', p_autor,
            coalesce(p_motivo, 'Portão 2: caso aprovado'),
            jsonb_build_object('portao', 2, 'avaliacao', v_aval, 'status_anterior', v_status));

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'transicao_status', 'caso:'||p_caso_id,
            jsonb_build_object('status', v_status),
            jsonb_build_object('status', 'aprovado', 'avaliacao', v_aval));

  return v_aval || jsonb_build_object('elegivel', true, 'status_atual', 'aprovado', 'aprovado', true);
end;
$$;

--
-- Name: FUNCTION fn_aprovar_caso(p_caso_id uuid, p_autor text, p_motivo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_aprovar_caso(p_caso_id uuid, p_autor text, p_motivo text) IS 'Portão 2 por CASO. Recusa (payload com recusado=true) quando fn_avaliar_portao2 diz que não; aprova, registra decisao+evento e transiciona para `aprovado` quando diz que sim. Sem exceção para nenhum autor: a regra de Arquitetura do Sistema/2 Especificação/f0/04 é determinística.';

--
-- Name: fn_ativar_premissa(uuid, text, jsonb, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_ativar_premissa(p_caso_id uuid, p_codigo text, p_valores jsonb, p_origem text, p_autor text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_nome     text;
  v_natureza text;
  v_valores  jsonb := coalesce(p_valores, '{}'::jsonb);
  v_origem   text := p_origem;
  v_ano      int;
  v_anos     int;
begin
  select nome, natureza::text into v_nome, v_natureza
  from premissa_catalogo where codigo = p_codigo and ativo;
  if v_nome is null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'premissa_recusada', 'caso:'||p_caso_id,
              jsonb_build_object('codigo', p_codigo, 'porque', 'codigo inexistente ou inativo no catalogo'));
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não existe no catálogo (ou está inativa). '
                              'Premissa nova entra por semente no catálogo, não por caso.', p_codigo));
  end if;

  if v_natureza = 'macro' and v_valores = '{}'::jsonb then
    select coalesce(ultimo_exercicio_real, extract(year from now())::int) + 1,
           coalesce(anos_projetados, 5)
      into v_ano, v_anos
    from caso_modelagem where caso_id = p_caso_id;
    -- Sem parâmetros do caso ainda: usa o ano corrente + 1 e 5 anos. A tela pede
    -- os parâmetros no passo 1, mas o analista pode ativar a premissa antes, e
    -- devolver vazio aqui só empurraria o trabalho para ele.
    v_ano := coalesce(v_ano, extract(year from now())::int + 1);
    v_anos := coalesce(v_anos, 5);
    v_valores := fn_premissa_valores_sugeridos(p_codigo, v_ano, v_anos);
    if v_valores <> '{}'::jsonb then
      v_origem := 'focus';
    end if;
  end if;

  insert into caso_premissa (caso_id, premissa_codigo, valores, origem, ativo, atualizado_por, atualizado_em)
    values (p_caso_id, p_codigo, v_valores, v_origem, true, p_autor, now())
  on conflict (caso_id, premissa_codigo) do update
    set valores = excluded.valores, origem = excluded.origem, ativo = true,
        atualizado_por = excluded.atualizado_por, atualizado_em = now();

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'override', p_autor,
            format('Premissa "%s" ativada/ajustada na modelagem%s', v_nome,
                   case when v_origem = 'focus' then ' (valores do Focus)' else '' end),
            jsonb_build_object('premissa', p_codigo, 'valores', v_valores, 'origem', v_origem));

  return jsonb_build_object('caso_id', p_caso_id, 'premissa', p_codigo, 'ativo', true,
                            'valores', v_valores, 'origem', v_origem);
end;
$$;

--
-- Name: fn_autoridade_do_documento(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_autoridade_do_documento(p_documento_id uuid) RETURNS TABLE(autoridade integer, motivo text, decide_sozinho boolean)
    LANGUAGE sql STABLE
    AS $$
  -- 0155: um documento cujas linhas nomeiam VÁRIAS empresas é derivado, e a
  -- autoridade dele não pode passar da de COMBINADO — senão o combinado empata
  -- com o balanço individual e o empate volta a "fica com o maior".
  with base as (
    select
      coalesce(t.autoridade, 0) as do_tipo,
      coalesce(t.codigo, 'sem tipo') as codigo,
      coalesce(t.autoridade, 0) = 0 as sem_declaracao,
      dv.assinado is true as assinado,
      fn_documento_preliminar(dv.nome_original) as preliminar,
      fn_documento_de_varias_empresas(d.id) as varias_empresas,
      (select coalesce(tc.autoridade, 30) from taxonomia_tipo_documento tc
        where tc.codigo = 'COMBINADO') as teto_derivado,
      -- 0159: o mesmo sinal que já aparece na tela de pendências do caso —
      -- ver o cabeçalho desta migration para por que NÃO é um critério
      -- estrutural sobre `campo_extraido`.
      exists (
        select 1 from pendencia pd
        where pd.documento_id = d.id
          and pd.tipo = 'tipo_incorreto'
          and pd.estado <> 'resolvida'
      ) as tipo_incorreto_aberto
    from documento d
    left join taxonomia_tipo_documento t on t.codigo = d.tipo_taxonomia
    left join documento_versao dv on dv.id = fn_versao_com_extracao(d.id)
    where d.id = p_documento_id
  ),
  com_confianca as (
    select b.*, fn_documento_decide_sozinho(b.codigo, b.tipo_incorreto_aberto) as decide_sozinho
    from base b
  )
  select
    (case when b.varias_empresas then least(b.do_tipo, b.teto_derivado) else b.do_tipo end
     + case when b.assinado then 5 else 0 end
     - case when b.preliminar then 25 else 0 end)::integer,
    b.codigo
      || case when b.sem_declaracao
              then ' (o catálogo não declara autoridade para este tipo)' else '' end
      || case when b.varias_empresas
              then format(', mas as colunas nomeiam VÁRIAS empresas — é peça derivada, e a '
                       || 'autoridade não passa da de combinado (%s)', b.teto_derivado)
              else '' end
      || case when not b.decide_sozinho
              then ' — o diagnóstico de conteúdo já contesta este rótulo (pendência '
                   || 'tipo_incorreto aberta): o documento não decide sozinho contra outro (0159)'
              else '' end
      || case when b.assinado then ', assinado' else '' end
      || case when b.preliminar
              then ', e o nome do arquivo diz que é preliminar' else '' end,
    b.decide_sozinho
  from com_confianca b;
$$;

--
-- Name: FUNCTION fn_autoridade_do_documento(p_documento_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_autoridade_do_documento(p_documento_id uuid) IS 'A autoridade documental de UM documento, o motivo por extenso, e se ele decide sozinho contra outro (0151): a do tipo no catálogo, mais 5 se assinada, menos 25 se o nome do arquivo declara preliminar. Desde a 0155, colunas nomeando VÁRIAS empresas limitam a autoridade à de COMBINADO — o rótulo diz "fechada" e a estrutura diz "derivada". Desde a 0159, `decide_sozinho` vira falso quando o documento é COMBINADO e tem uma pendência `tipo_incorreto` ABERTA — o próprio diagnóstico de conteúdo já contesta o rótulo. Medido no araucária (03/09): seis documentos assim, com a autoridade baixa (35) perdendo em silêncio contra um BALANCO mal extraído (55) da mesma empresa. A autoridade NUMÉRICA não muda nesse caso — não há piso honesto para promovê-la a (ver o cabeçalho da 0159) — só a confiança de que o documento pode decidir um conflito sozinho.';

--
-- Name: fn_avaliar_guardas_extracao(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_avaliar_guardas_extracao(p_documento_versao_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
declare
  v_n_campos      int;
  v_n_baixa       int;
  v_max_repet     int;
  v_valor_repet   numeric;
  v_rotulos       text[];
begin
  select count(*), count(*) filter (where confianca is not null and confianca < 0.7)
    into v_n_campos, v_n_baixa
  from campo_extraido where documento_versao_id = p_documento_versao_id;

  select valor, n_contas into v_valor_repet, v_max_repet
  from fn_contas_repetindo_valor(p_documento_versao_id);

  -- 0043: os RÓTULOS que repetiram entram no diagnóstico. A pendência do v35
  -- dizia "4 contas diferentes … com o MESMO valor (14529)" e não dizia QUAIS —
  -- e sem os nomes é impossível julgar, da tela, se é alucinação ou identidade
  -- contábil. Precisei abrir o banco para descobrir; ninguém mais deveria.
  if coalesce(v_max_repet, 0) >= 4 then
    select array_agg(distinct ce.chave order by ce.chave) into v_rotulos
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.valor_num = v_valor_repet;
  end if;

  return jsonb_build_object(
    'n_campos', v_n_campos,
    'padrao_suspeito', coalesce(v_max_repet, 0) >= 4,
    'valor_repetido', v_valor_repet,
    'n_contas_repetindo', coalesce(v_max_repet, 0),
    'rotulos_repetindo', to_jsonb(coalesce(v_rotulos, array[]::text[])),
    'baixa_confianca', v_n_baixa >= 3 and v_n_campos > 0 and v_n_baixa::numeric / v_n_campos >= 0.3,
    'n_baixa_confianca', v_n_baixa,
    'vazia', v_n_campos = 0
  );
end;
$$;

--
-- Name: fn_avaliar_portao2(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_avaliar_portao2(p_caso_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
declare
  v_bloqueantes      int;
  v_nao_sobrepujavel int;
  v_ressalvas        int;
  v_rejeitadas       int;
  v_rejeitadas_ns    int;
  v_motivos          text[] := array[]::text[];
  v_status           caso_status;
begin
  select status into v_status from caso where id = p_caso_id;
  if v_status is null then
    raise exception 'caso % não encontrado', p_caso_id;
  end if;

  -- A ÚNICA condição de bloqueio: bloqueante que ninguém decidiu ainda.
  select count(*) into v_bloqueantes
  from pendencia
  where caso_id = p_caso_id and severidade = 'bloqueante'
    and estado in ('aberta', 'em_correcao_interna', 'reenviada_ao_cliente');

  -- INFORMAÇÃO, não bloqueio (0109). As três contagens abaixo não entram em
  -- `elegivel`; elas existem para a tela e para a `decisao` de aprovação
  -- dizerem sobre o que se passou por cima. Um caso aprovado com seis
  -- ressalvas continua sendo distinguível de um caso limpo — o que ele deixou
  -- de ser é impedido.
  select count(*) into v_nao_sobrepujavel
  from pendencia
  where caso_id = p_caso_id and sobrepujavel = false
    and estado in ('aberta', 'em_correcao_interna', 'reenviada_ao_cliente');

  select count(*) into v_ressalvas
  from pendencia
  where caso_id = p_caso_id and estado = 'aceita_com_ressalva';

  select count(*) filter (where true),
         count(*) filter (where sobrepujavel = false)
    into v_rejeitadas, v_rejeitadas_ns
  from pendencia
  where caso_id = p_caso_id and estado = 'rejeitada';

  if v_bloqueantes > 0 then
    v_motivos := array_append(v_motivos,
      format('%s pendência(s) BLOQUEANTE(s) sem decisão', v_bloqueantes));
  end if;

  return jsonb_build_object(
    'caso_id', p_caso_id,
    'status_atual', v_status,
    'elegivel', array_length(v_motivos, 1) is null,
    'motivos', to_jsonb(v_motivos),
    'bloqueantes_abertas', v_bloqueantes,
    'nao_sobrepujaveis_abertas', v_nao_sobrepujavel,
    'ressalvas_ativas', v_ressalvas,
    'ressalvas_expiradas', 0,
    'rejeitadas', v_rejeitadas,
    'rejeitadas_nao_sobrepujaveis', v_rejeitadas_ns,
    'teto_ressalvas', null
  );
end;
$$;

--
-- Name: FUNCTION fn_avaliar_portao2(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_avaliar_portao2(p_caso_id uuid) IS 'Portão 2 (0109): elegível quando não há pendência BLOQUEANTE sem decisão. O teto de ressalvas e a lista fechada de Arquitetura do Sistema/2 Especificação/f0/04 deixaram de bloquear por decisão do dono — as contagens continuam publicadas como informação, e vão gravadas dentro da decisão de aprovação.';

--
-- Name: fn_classe_contabil_concordancia(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_classe_contabil_concordancia(p_caso_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  with par as (
    select s.classe_codigo as sugerida, o.classe_final as humana, s.rubrica_id
    from campo_classe_sugerida s
    join lateral (
      select o.classe_final from campo_classe_override o
      where o.campo_extraido_id = s.campo_extraido_id
      order by o.criado_em desc, o.id desc limit 1
    ) o on true
    join campo_extraido ce on ce.id = s.campo_extraido_id
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where (p_caso_id is null or d.caso_id = p_caso_id)
      and s.criado_em = (select max(s2.criado_em) from campo_classe_sugerida s2
                          where s2.campo_extraido_id = s.campo_extraido_id)
  ),
  sem_veredito as (
    select count(*) as n
    from campo_classe_sugerida s
    join campo_extraido ce on ce.id = s.campo_extraido_id
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where (p_caso_id is null or d.caso_id = p_caso_id)
      and not exists (select 1 from campo_classe_override o
                       where o.campo_extraido_id = s.campo_extraido_id)
  )
  select jsonb_build_object(
    'com_veredito_humano', (select count(*) from par),
    'concordaram', (select count(*) from par where sugerida = humana),
    'concordancia', case when (select count(*) from par) = 0 then null
                        else round((select count(*) from par where sugerida = humana)::numeric
                                   / (select count(*) from par), 4) end,
    'sem_veredito_humano', (select n from sem_veredito),
    'rubricas_que_mais_erram', (
      select coalesce(jsonb_agg(x order by x->>'erros' desc), '[]'::jsonb) from (
        select jsonb_build_object(
                 'padrao', rc.padrao, 'sugeria', rc.classe_codigo,
                 'erros', count(*),
                 'humano_disse', jsonb_agg(distinct par.humana)) as x
        from par join rubrica_classe rc on rc.id = par.rubrica_id
        where par.sugerida <> par.humana
        group by rc.padrao, rc.classe_codigo
        order by count(*) desc limit 10
      ) t),
    'como_ler', 'O denominador são as linhas com sugestao E override. Linha que ninguem olhou fica '
                'FORA, contada a parte: "a maquina acertou" e "ninguem conferiu" sao estados '
                'diferentes. E este numero NAO autoriza subir o dial por si: o teto de '
                'classificacao_contabil e N1 para sempre (Arquitetura do Sistema/1 Visão e Doutrina/01).'
  );
$$;

--
-- Name: FUNCTION fn_classe_contabil_concordancia(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_classe_contabil_concordancia(p_caso_id uuid) IS 'A concordância humano-máquina na classe contábil — o "sinal de calibração" que o Arquitetura do Sistema/2 Especificação/05 pede, em número, mais as rubricas que mais erram. Da mesma família do achado da 0126 sobre a Classe A: o rótulo vem do trabalho que o analista já faz, sem rotulagem dedicada. Denominador = linhas com os DOIS lados; quem ninguém olhou fica fora e é contado à parte.';

--
-- Name: fn_classe_contabil_do_campo(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_classe_contabil_do_campo(p_campo_extraido_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  with sug as (
    select s.classe_codigo, s.confianca, s.justificativa, s.criado_em, s.nivel_autonomia
    from campo_classe_sugerida s
    where s.campo_extraido_id = p_campo_extraido_id
    order by s.criado_em desc, s.id desc limit 1
  ), ovr as (
    select o.classe_final, o.autor, o.motivo, o.criado_em
    from campo_classe_override o
    where o.campo_extraido_id = p_campo_extraido_id
    order by o.criado_em desc, o.id desc limit 1
  )
  select jsonb_build_object(
    -- SÓ o override. A sugestão nunca vira fato — fechamento #5 do Arquitetura do Sistema/1 Visão e Doutrina/01.
    'classe_efetiva', (select classe_final from ovr),
    'aceita_por_humano', exists (select 1 from ovr),
    'sugestao', (select jsonb_build_object(
                   'classe', classe_codigo, 'confianca', confianca,
                   'justificativa', justificativa, 'em', criado_em,
                   'nivel_quando_sugerida', nivel_autonomia) from sug),
    'override', (select jsonb_build_object(
                   'classe', classe_final, 'autor', autor, 'motivo', motivo,
                   'em', criado_em) from ovr),
    'humano_discordou', (select o.classe_final from ovr o) is not null
                        and (select s.classe_codigo from sug s) is not null
                        and (select o.classe_final from ovr o)
                            <> (select s.classe_codigo from sug s)
  );
$$;

--
-- Name: FUNCTION fn_classe_contabil_do_campo(p_campo_extraido_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_classe_contabil_do_campo(p_campo_extraido_id uuid) IS 'A classe contábil efetiva de uma linha — e ela é SÓ o override humano. A sugestão vem no mesmo objeto, separada, e nunca conta como fato: é o fechamento #5 do Arquitetura do Sistema/1 Visão e Doutrina/01 aplicado à classificação, e a razão de o teto dela ser N1 para sempre. Mudar isso exige mudar esta função, de propósito.';

--
-- Name: fn_classe_contabil_sugerir(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_classe_contabil_sugerir(p_chave text, p_secao_canonica text, p_tipo_taxonomia text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
declare
  v_norm text;
  v_r    record;
begin
  if not fn_secao_e_de_resultado(p_secao_canonica) then
    return null;   -- a pergunta não se aplica; ausência de sugestão é a resposta
  end if;

  v_norm := fn_normalizar_texto(coalesce(p_chave, ''));
  if v_norm = '' then
    return null;
  end if;

  -- SUBTOTAL NÃO TEM RECORRÊNCIA PRÓPRIA: ela é herdada dos componentes. Mandar um
  -- subtotal para revisão humana é pedir uma decisão que não existe.
  --
  -- E aqui vai a ressalva medida, porque ela importa: `fn_papel_linha` NÃO pega
  -- todo subtotal impresso. Conferido — ela devolve `conta` para
  -- "CUSTO DOS PRODUTOS VENDIDOS" e para "(-) DESPESAS OPERACIONAIS", que são
  -- subtotais no documento. Então este filtro REDUZ o ruído sem eliminá-lo, e
  -- dizer o contrário seria prometer o que ele não cumpre. Quando ela diz
  -- `subtotal` ou `derivado`, aí é confiável — e é só nesse caso que se pula.
  if fn_papel_linha(p_chave, p_tipo_taxonomia, null) in ('subtotal', 'derivado') then
    return null;
  end if;

  -- Mais específico ganha, e o desempate é DECLARADO (especificidade, depois
  -- comprimento do padrão): duas regras que casam a mesma linha não podem dar
  -- resultado dependente da ordem em que o banco devolveu.
  select rc.id, rc.classe_codigo, rc.confianca, rc.justificativa, rc.versao
    into v_r
  from rubrica_classe rc
  where rc.ativo
    and position(fn_normalizar_texto(rc.padrao) in v_norm) > 0
    and (rc.secao_canonica is null or rc.secao_canonica = p_secao_canonica)
    and (rc.tipo_taxonomia is null or rc.tipo_taxonomia = p_tipo_taxonomia)
  order by rc.especificidade desc, length(rc.padrao) desc, rc.padrao
  limit 1;

  if v_r.id is null then
    return jsonb_build_object(
      'classe', 'revisar_manual',
      'confianca', null,
      'rubrica_id', null,
      'justificativa', format('Nenhuma rubrica do catálogo casa com "%s". O Arquitetura do Sistema/2 Especificação/05 manda o default '
                              'ser conservador: rubrica nova vai para revisão humana, não recebe '
                              'palpite.', p_chave),
      'versao_taxonomia', (select max(versao) from classe_contabil_catalogo));
  end if;

  return jsonb_build_object(
    'classe', v_r.classe_codigo,
    'confianca', v_r.confianca,
    'rubrica_id', v_r.id,
    'justificativa', v_r.justificativa,
    'versao_taxonomia', v_r.versao);
end;
$$;

--
-- Name: FUNCTION fn_classe_contabil_sugerir(p_chave text, p_secao_canonica text, p_tipo_taxonomia text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_classe_contabil_sugerir(p_chave text, p_secao_canonica text, p_tipo_taxonomia text) IS 'A regra determinística do Arquitetura do Sistema/2 Especificação/05 (condição 2: casa com padrão pré-registrado). NULL = a pergunta não se aplica (linha que não é de resultado); revisar_manual = ela se aplica e o catálogo não sabe. Confundir as duas produziria 3.195 pedidos de revisão em vez de 527. Desempate DECLARADO por especificidade: duas regras que casam a mesma linha não podem depender da ordem do banco.';

--
-- Name: fn_classificar_contabil(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_classificar_contabil(p_documento_versao_id uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
  v_nivel   nivel_autonomia;
  v_c       record;
  v_sug     jsonb;
  v_ultima  text;
  v_n       int := 0;
begin
  select ea.nivel_atual into v_nivel
  from estagio_autonomia ea where ea.estagio = 'classificacao_contabil';
  -- Sem linha no dial (banco antigo), NÃO classifica. Ausência de configuração não
  -- é permissão para escrever — mesma regra da 0041 e da 0127.
  if v_nivel is null then
    return 0;
  end if;

  for v_c in
    select ce.id, ce.chave, ce.secao_canonica, d.tipo_taxonomia
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where ce.documento_versao_id = p_documento_versao_id
      and fn_secao_e_de_resultado(ce.secao_canonica)
  loop
    v_sug := fn_classe_contabil_sugerir(v_c.chave, v_c.secao_canonica, v_c.tipo_taxonomia);
    if v_sug is null then
      continue;   -- a pergunta não se aplica a esta linha
    end if;

    select s.classe_codigo into v_ultima
    from campo_classe_sugerida s
    where s.campo_extraido_id = v_c.id
    order by s.criado_em desc, s.id desc
    limit 1;

    if v_ultima is not null and v_ultima = (v_sug->>'classe') then
      continue;   -- a regra não mudou de opinião: não há o que acrescentar
    end if;

    insert into campo_classe_sugerida
      (campo_extraido_id, classe_codigo, confianca, rubrica_id, justificativa,
       versao_taxonomia, nivel_autonomia)
    values (v_c.id, v_sug->>'classe',
            (v_sug->>'confianca')::numeric,
            (v_sug->>'rubrica_id')::uuid,
            v_sug->>'justificativa',
            coalesce((v_sug->>'versao_taxonomia')::int, 1),
            v_nivel);
    v_n := v_n + 1;
  end loop;

  if v_n > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:classificacao_contabil', 'classificacao_contabil_sombra',
              'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('sugestoes', v_n, 'nivel', v_nivel,
                                 'porque', 'N0: registra a sugestao e nao influencia decisao '
                                           '(Arquitetura do Sistema/1 Visão e Doutrina/01). Nenhuma pendencia aberta, nenhum numero '
                                           'do export tocado.'));
  end if;
  return v_n;
end;
$$;

--
-- Name: FUNCTION fn_classificar_contabil(p_documento_versao_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_classificar_contabil(p_documento_versao_id uuid) IS 'Roda a classificação contábil sobre uma versão e REGISTRA a sugestão — a primeira metade de N0. A segunda ("não influencia decisão") é garantida por construção: só escreve em campo_classe_sugerida, não abre pendência e não entra em caminho de export. Append-only sem duplicar: grava só quando a regra muda de opinião, e aí a sequência é o histórico.';

--
-- Name: fn_cnpj_canonico(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_cnpj_canonico(p_cnpj text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
declare
  d     text;
  peso  int;
  soma  int;
  -- `dv` e `i` NÃO são declarados: os `for` abaixo declaram os próprios e
  -- sombreariam estes. Declará-los é ruído que `plpgsql.extra_warnings =
  -- shadowed_variables` acusa.
begin
  if p_cnpj is null then return null; end if;
  d := regexp_replace(p_cnpj, '[^0-9]', '', 'g');
  if length(d) <> 14 then return null; end if;
  if d ~ ('^' || substr(d, 1, 1) || '{14}$') then return null; end if;

  -- DV1 sobre os 12 primeiros; DV2 sobre os 13 primeiros. Os pesos descem de 9
  -- a 2 e reiniciam, que é o algoritmo do módulo 11 da Receita.
  for dv in 1 .. 2 loop
    soma := 0;
    peso := 1;
    for i in reverse (11 + dv) .. 1 loop
      peso := peso + 1;
      if peso > 9 then peso := 2; end if;
      soma := soma + substr(d, i, 1)::int * peso;
    end loop;
    soma := soma % 11;
    if soma < 2 then soma := 0; else soma := 11 - soma; end if;
    if substr(d, 12 + dv, 1)::int <> soma then return null; end if;
  end loop;

  return d;
end;
$_$;

--
-- Name: FUNCTION fn_cnpj_canonico(p_cnpj text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_cnpj_canonico(p_cnpj text) IS '14 dígitos de CNPJ com o DV conferido, ou NULO. 0169: o CNPJ vai chegar de uma IA lendo PDF escaneado — um número inventado que passe como identidade funde duas empresas de verdade em silêncio, que é pior que não ter CNPJ nenhum. DV que não fecha é AUSÊNCIA, não dado.';

--
-- Name: fn_cobertura_de_tipos(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_cobertura_de_tipos() RETURNS TABLE(tipo_taxonomia text, obrigatoriedade text, exigencias_vivas integer, estado_declarado text, consumidor text, consumidor_existe boolean, marcador_presente boolean, veredito text)
    LANGUAGE sql STABLE
    AS $$
  with vivas as (
    select e.tipo_taxonomia, count(*)::int as n
      from taxonomia_linha_exigida e
     where e.ativo and e.origem = 'codigo'
     group by e.tipo_taxonomia
  ),
  base as (
    select t.codigo, t.obrigatoriedade::text as obrigatoriedade,
           coalesce(v.n, 0) as n_vivas,
           c.tipo_taxonomia is not null as declarado,
           c.estado, c.consumidor,
           case when c.consumidor is null then null
                else exists (select 1 from pg_proc p
                               join pg_namespace ns on ns.oid = p.pronamespace
                              where ns.nspname = 'public' and p.proname = c.consumidor)
           end as consumidor_existe,
           -- 0187 (revisão): o nome em pg_proc não prova que a função AINDA lê
           -- o tipo. O marcador precisa estar no corpo PUBLICADO, com o \r
           -- tirado dos dois lados — produção guarda corpo com CRLF
           -- (.claude/memory/ancora-de-texto-quebra-com-crlf.md).
           case when c.marcador is null then null
                else exists (select 1 from pg_proc p
                               join pg_namespace ns on ns.oid = p.pronamespace
                              where ns.nspname = 'public' and p.proname = c.marcador_em
                                and p.prokind = 'f'
                                and position(replace(c.marcador, E'\r', '')
                                             in replace(pg_get_functiondef(p.oid), E'\r', '')) > 0)
           end as marcador_presente
      from taxonomia_tipo_documento t
      left join vivas v on v.tipo_taxonomia = t.codigo
      left join taxonomia_tipo_cobertura c on c.tipo_taxonomia = t.codigo
     where t.ativo
  )
  select b.codigo, b.obrigatoriedade, b.n_vivas, b.estado, b.consumidor, b.consumidor_existe,
         b.marcador_presente,
         case
           -- Duplo registro: o tipo ganhou exigência viva e a declaração ficou.
           -- Ela envelhece calada (o consumidor pode sumir, o motivo mentir), e
           -- o portão quer UMA fonte por tipo.
           when b.n_vivas > 0 and b.declarado            then 'DECLARACAO_QUEBRADA'
           when b.n_vivas > 0                            then 'exigencia_viva'
           when not b.declarado                          then 'SEM_COBERTURA'
           when b.estado = 'consumidor_nomeado'
            and not b.consumidor_existe                  then 'DECLARACAO_QUEBRADA'
           -- O consumidor existe mas o trecho que faz a leitura sumiu do corpo
           -- (do dele ou do despachante que o chama): a declaração mente.
           when b.estado = 'consumidor_nomeado'
            and not coalesce(b.marcador_presente, false) then 'DECLARACAO_QUEBRADA'
           when b.estado = 'consumidor_nomeado'          then 'consumidor_nomeado'
           else 'sem_consumidor_declarado'
         end
    from base b
   order by b.codigo;
$$;

--
-- Name: FUNCTION fn_cobertura_de_tipos(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_cobertura_de_tipos() IS '0187 — portão D6. Uma linha por tipo ATIVO da taxonomia. D6 estrito = nenhuma linha com veredito SEM_COBERTURA (sem exigência viva e sem declaração) nem DECLARACAO_QUEBRADA (consumidor nomeado que não existe em pg_proc, marcador que sumiu do corpo de marcador_em, ou declaração para tipo que já tem exigência viva). Não depende de documento: roda igual no banco de teste e em produção.';

--
-- Name: fn_coluna_de_dimensao(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_coluna_de_dimensao(p_coluna text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  select case
    when p_coluna is null or btrim(p_coluna) = '' then false
    -- Os parênteses em volta do padrão NÃO são estilo: `~` liga mais forte que
    -- `||`, então sem eles o Postgres lê `(texto ~ 'a') || 'b'` — booleano
    -- concatenado com texto — e a função devolve texto em vez de booleano.
    else fn_normalizar_texto(p_coluna) ~ (
      -- Dimensões temporais que NÃO são período de valor: o ano solto numa
      -- coluna própria (v47, doc 19).
      '^(exercicio|ano|periodo|competencia|data|mes|vencimento)$'
      -- Contagens e medidas físicas: repetem por natureza e não são dinheiro.
      || '|^(quantidade|qtd|qtde|unidade|efetivo|efetivo \(pessoas\)|pessoas|headcount|dias|prazo)$'
      -- Classificadores textuais.
      || '|^(natureza|tipo|classe|categoria|situacao|status|moeda|indexador|empresa.*|contraparte|banco|contrato|historico|documento)$'
      -- Proporções e unitários: 100,00 repetido em "% do total" é aritmética,
      -- não alucinação; e custo unitário repete entre itens do mesmo insumo.
      || '|(^|\s)(%|percentual|participacao|custo unitario|preco unitario|valor unitario|taxa)($|\s)'
    )
  end;
$_$;

--
-- Name: FUNCTION fn_coluna_de_dimensao(p_coluna text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_coluna_de_dimensao(p_coluna text) IS 'A coluna ROTULA a linha (exercício, quantidade, natureza, %) em vez de medi-la em dinheiro. Nasceu do falso positivo da v47: a guarda de padrão suspeito acusou o ano 2023 repetido na coluna "Exercício" como alucinação (0140).';

--
-- Name: fn_coluna_e_abertura(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_coluna_e_abertura(p_coluna text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  select coalesce(p_coluna, '') ~* '^\s*saldo\s+(inicial|anterior)\s*$'
$_$;

--
-- Name: FUNCTION fn_coluna_e_abertura(p_coluna text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_coluna_e_abertura(p_coluna text) IS '"Saldo Inicial"/"Saldo anterior": o fechamento do ano ANTERIOR ao do documento (0199 b). Conta única de fn_valores_por_ano e fn_linhas_do_realizado (0201).';

--
-- Name: fn_coluna_e_movimento(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_coluna_e_movimento(p_coluna text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  select coalesce(p_coluna, '') ~* '^\s*(d[ée]bito|cr[ée]dito)s?\s*$'
$_$;

--
-- Name: FUNCTION fn_coluna_e_movimento(p_coluna text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_coluna_e_movimento(p_coluna text) IS '"Débito"/"Crédito": movimento do período, nunca saldo (0199 a). Conta única de fn_valores_por_ano e fn_linhas_do_realizado (0201).';

--
-- Name: fn_coluna_e_saldo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_coluna_e_saldo(p_coluna text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  select coalesce(p_coluna, '') ~* '^\s*saldo\s+(final|atual|inicial|anterior)\s*$'
$_$;

--
-- Name: FUNCTION fn_coluna_e_saldo(p_coluna text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_coluna_e_saldo(p_coluna text) IS 'Coluna que NOMEIA um saldo sem trazer ano (final, atual, inicial, anterior): o ano vem da referência do documento (0201). "Saldo", "Valor" e "Ticket médio" não são — continuam sem exercício.';

--
-- Name: fn_coluna_entidade(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_coluna_entidade(p_documento_versao_id uuid, p_entidade_id uuid) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
  v_tem_col boolean;
  v_razao   text;
  v_col     text;
  v_dono    boolean;
begin
  select exists (
    select 1 from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id and ce.entidade_coluna is not null
  ) into v_tem_col;
  if not v_tem_col then return null; end if;

  select e.razao_social into v_razao from entidade e where e.id = p_entidade_id;
  if v_razao is not null then
    -- 0030: era `fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(v_razao)`.
    -- Igualdade exata nunca casa apelido de coluna com razão social completa, que é
    -- o formato NORMAL de um balanço combinado.
    select ce.entidade_coluna into v_col
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.entidade_coluna is not null
      and fn_mesma_entidade(ce.entidade_coluna, v_razao)
    limit 1;
    if v_col is not null then return v_col; end if;
  end if;

  select (d.entidade_id = p_entidade_id) into v_dono
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if coalesce(v_dono, false) then
    -- Total do próprio documento. Mesmo vocabulário de `tipoColunaNaoEntidade`
    -- em portal/src/lib/export.ts, para o portal e o banco concordarem.
    select ce.entidade_coluna into v_col
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.entidade_coluna is not null
      and fn_normalizar_texto(ce.entidade_coluna) ~ '^(combinad|consolidad|total|soma)'
    limit 1;
    if v_col is not null then return v_col; end if;
  end if;

  return E'\x01';
end;
$$;

--
-- Name: fn_coluna_periodo_do_ano(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_coluna_periodo_do_ano(p_documento_versao_id uuid, p_ano integer) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
declare
  v_col text;
  v_tem boolean;
begin
  select ce.periodo_coluna into v_col
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.periodo_coluna is not null
    and p_ano = any (fn_anos_texto(ce.periodo_coluna))
  group by ce.periodo_coluna
  order by count(*) desc, ce.periodo_coluna
  limit 1;
  if v_col is not null then return v_col; end if;

  select exists (
    select 1 from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id and ce.periodo_coluna is not null
  ) into v_tem;
  return case when v_tem then E'\x01' else null end;
end;
$$;

--
-- Name: fn_combinado_estrutural_apto(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_combinado_estrutural_apto(p_tipo_fonte text, p_empresas_com_valor integer) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select
    -- Achado B: só demonstração contábil PRIMÁRIA pode se apresentar em forma
    -- combinada. DF_AUDITADA fica de fora de propósito — pergunta aberta do
    -- dono, ver o cabeçalho da 0157.
    p_tipo_fonte = any (array['DRE', 'BALANCO', 'FLUXO_CAIXA'])
    -- Achado A: cabeçalho de várias empresas sem NENHUM número não é
    -- combinado — é a sub-extração que a 0154 já mediu (40%-78% no
    -- araucária). ">1", não ">0", pela mesma razão da 0155: duas colunas
    -- iguais (comparativo de anos da mesma empresa) não é grupo.
    and coalesce(p_empresas_com_valor, 0) > 1;
$$;

--
-- Name: FUNCTION fn_combinado_estrutural_apto(p_tipo_fonte text, p_empresas_com_valor integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_combinado_estrutural_apto(p_tipo_fonte text, p_empresas_com_valor integer) IS '(Revisão da 0157, achados A e B) Este par — tipo do documento-FONTE, quantas empresas têm VALOR extraído nas colunas (não só cabeçalho) — o torna apto a servir como o item COMBINADO do Kit Básico? Fonte precisa ser demonstração contábil PRIMÁRIA (DRE/BALANCO/FLUXO_CAIXA — DF_AUDITADA fica fora, decisão aberta do dono) E precisa haver mais de uma empresa com número de verdade. Função pura de propósito: a sonda de instalação a exercita por literais, sem fixture de documento (instalacao_sonda_combinado_estrutural) — um marcador textual não sobrevive a um "false and" que mate o predicado e deixe os comentários intactos; uma função executada, sim.';

--
-- Name: fn_conferir_arvore(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_conferir_arvore(p_documento_versao_id uuid) RETURNS TABLE(entidade_coluna text, periodo_coluna text, pai text, pai_valor numeric, soma_filhos numeric, n_filhos integer, n_reafirmacoes integer, unidade text, divergencia_abs numeric, tolerancia numeric, resultado text, achado text, porque text, filhos text[])
    LANGUAGE sql STABLE
    AS $$
  with linha as (
    select ce.chave,
           fn_normalizar_texto(ce.chave) as chave_norm,
           fn_normalizar_texto(ce.secao) as secao_norm,
           ce.valor_num,
           ce.unidade,
           ce.entidade_coluna,
           ce.periodo_coluna,
           coalesce(fn_normalizar_texto(ce.entidade_coluna), '') as ck_ent,
           coalesce(fn_normalizar_texto(ce.periodo_coluna),  '') as ck_per,
           fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) as papel
      from campo_extraido ce
      join documento_versao dv on dv.id = ce.documento_versao_id
      join documento d         on d.id  = dv.documento_id
     where ce.documento_versao_id = p_documento_versao_id
       and ce.valor_num is not null
  ),
  eh_pai as (
    select distinct f.secao_norm as pai_norm, f.ck_ent, f.ck_per
      from linha f
     where f.secao_norm is not null
       and f.chave_norm is distinct from f.secao_norm
  ),
  pai as (
    select l.chave_norm as pai_norm, l.ck_ent, l.ck_per,
           min(l.chave)           as pai_chave,
           min(l.valor_num)       as pai_valor,
           min(l.unidade)         as pai_unidade,
           min(l.entidade_coluna) as ent_col,
           min(l.periodo_coluna)  as per_col,
           count(*)::int          as n_pai
      from linha l
      join eh_pai e
        on e.pai_norm = l.chave_norm
       and e.ck_ent   = l.ck_ent
       and e.ck_per   = l.ck_per
     group by l.chave_norm, l.ck_ent, l.ck_per
  ),
  -- O CLASSIFICADOR DE FILHO. Esta é a parte que a primeira versão errou, e o
  -- fixture disse na cara: a soma dava EXATAMENTE 2x o pai em 31 seções.
  --
  -- Depois da 0116 o total impresso chega como LINHA, e ele fica na MESMA seção
  -- que as parcelas — "TOTAL DO ATIVO" é irmão de "Ativo Circulante", não pai
  -- dele. Somá-lo às parcelas conta a seção duas vezes. Ele não é parcela: é a
  -- REAFIRMAÇÃO do pai, e o próprio documento a imprime para ser conferida.
  --
  -- A regra é por VALOR, não por rótulo, e isso foi medido: "TOTAL DO PASSIVO E
  -- DO PATRIMÔNIO LÍQUIDO" contra a seção "PASSIVO E PATRIMÔNIO LÍQUIDO" não
  -- casa por texto (sobra o "do" do meio), e casar por semelhança traria de
  -- volta a adivinhação que `secao` existe para evitar.
  --
  -- E a reafirmação que NÃO bate não é descartada — vira achado PRÓPRIO. Se
  -- "TOTAL DO ATIVO" foi lido 95.000 com "ATIVO" em 95.780, o defeito não é
  -- "a seção não fecha": é "o documento declara o mesmo total duas vezes e as
  -- duas leituras discordam". Tratá-la como parcela produziria uma divergência
  -- de ~95.000 e um diagnóstico errado sobre um defeito verdadeiro.
  filho as (
    select p.pai_norm, p.ck_ent, p.ck_per, p.pai_valor, p.pai_unidade,
           f.chave, f.valor_num, f.unidade,
           f.chave_norm,
           case
             when f.papel = 'derivado'  then 'derivado'
             when f.papel = 'subtotal' and f.valor_num = p.pai_valor
               then 'reafirmacao'
             when f.papel = 'subtotal'
                  and fn_normalizar_texto(f.chave) ~ '^(total|soma)\y'
                  and f.valor_num is distinct from p.pai_valor
               then 'reafirmacao_divergente'
             else 'parcela'
           end as tipo
      from pai p
      join linha f
        on f.secao_norm = p.pai_norm
       and f.ck_ent     = p.ck_ent
       and f.ck_per     = p.ck_per
       and f.chave_norm is distinct from f.secao_norm
  ),
  agregado as (
    select p.ent_col, p.per_col, p.pai_chave, p.pai_valor, p.pai_unidade, p.n_pai,
           coalesce(sum(c.valor_num) filter (where c.tipo = 'parcela'), 0) as soma,
           count(*) filter (where c.tipo = 'parcela')::int                 as n,
           count(*) filter (where c.tipo = 'reafirmacao')::int             as n_reaf,
           count(*) filter (where c.tipo = 'reafirmacao_divergente')::int  as n_reaf_div,
           array_agg(c.chave order by c.chave)
             filter (where c.tipo = 'parcela')                             as chaves,
           min(c.chave) filter (where c.tipo = 'reafirmacao_divergente')   as reaf_div_chave,
           min(c.valor_num) filter (where c.tipo = 'reafirmacao_divergente') as reaf_div_valor,
           count(*) filter (
             where c.tipo = 'parcela'
               and c.unidade is not null and p.pai_unidade is not null
               and fn_normalizar_texto(c.unidade) <> fn_normalizar_texto(p.pai_unidade)
           )::int                                                          as n_unid_dif,
           (count(*) filter (where c.tipo = 'parcela')
            - count(distinct c.chave_norm) filter (where c.tipo = 'parcela'))::int
                                                                           as n_parcela_dup
      from pai p
      join filho c
        on c.pai_norm = p.pai_norm
       and c.ck_ent   = p.ck_ent
       and c.ck_per   = p.ck_per
     group by p.ent_col, p.per_col, p.pai_chave, p.pai_valor, p.pai_unidade, p.n_pai
  ),
  medido as (
    select a.*,
           abs(a.pai_valor - a.soma)                    as div_abs,
           greatest(1, ceil(0.5 * (a.n + 1)))::numeric  as tol
      from agregado a
  )
  select m.ent_col, m.per_col, m.pai_chave, m.pai_valor, m.soma, m.n, m.n_reaf, m.pai_unidade,
         m.div_abs, m.tol,
         case
           when m.n_pai > 1          then 'precondicao_nao_satisfeita'
           when m.n_parcela_dup > 0  then 'precondicao_nao_satisfeita'
           when m.n_unid_dif > 0     then 'precondicao_nao_satisfeita'
           when m.n_reaf_div > 0   then 'divergente'
           when m.n = 0            then 'precondicao_nao_satisfeita'
           -- 0143: soma ≈ 2× o pai é hierarquia achatada, não divergência.
           when m.pai_valor <> 0 and abs(m.soma - 2 * m.pai_valor) <= m.tol
                                   then 'precondicao_nao_satisfeita'
           when m.div_abs > m.tol  then 'divergente'
           else 'ok'
         end,
         case
           when m.n_pai > 1         then 'rotulo_duplicado'
           when m.n_parcela_dup > 0 then 'rotulo_duplicado'
           when m.n_unid_dif > 0    then 'unidade_mista'
           when m.n_reaf_div > 0 then 'total_declarado_diverge'
           when m.n = 0          then 'sem_parcela'
           when m.pai_valor <> 0 and abs(m.soma - 2 * m.pai_valor) <= m.tol
                                  then 'hierarquia_achatada'
           when m.div_abs > m.tol then 'secao_nao_fecha'
           else 'ok'
         end,
         case
           when m.n_pai > 1 then
             format('O rótulo "%s" aparece %s vezes nesta coluna: o pai é ambíguo e a soma não '
                    'decide nada. Quem cobra isso é reconciliacao:duplicidade_de_rotulo (0105) — '
                    'duas pendências para um defeito seriam dois toques humanos onde cabe um.',
                    m.pai_chave, m.n_pai)
           when m.n_parcela_dup > 0 then
             format('%s parcela(s) de "%s" aparecem com o rótulo repetido nesta coluna. A soma '
                    'passaria do pai e esta checagem acusaria — mas o defeito já tem dono, '
                    'reconciliacao:duplicidade_de_rotulo (0105), e duas pendências para um defeito '
                    'seriam dois toques humanos onde cabe um.',
                    m.n_parcela_dup, m.pai_chave)
           when m.n_unid_dif > 0 then
             format('%s de %s parcelas de "%s" estão em unidade diferente da do pai (%s). Somar '
                    'unidades diferentes erraria por ordem de grandeza, e descartar a parcela '
                    'divergente produziria uma soma errada com cara de certa.',
                    m.n_unid_dif, m.n, m.pai_chave, coalesce(m.pai_unidade, 'não declarada'))
           when m.n_reaf_div > 0 then
             format('O documento declara o total de "%s" DUAS vezes e as duas leituras discordam: '
                    'a seção diz %s e "%s" diz %s. Uma das duas foi lida errado — não é a soma das '
                    'parcelas que está em questão aqui.',
                    m.pai_chave, m.pai_valor, m.reaf_div_chave, m.reaf_div_valor)
           when m.n = 0 then
             format('"%s" nomeia uma seção, mas nenhum filho dela é parcela somável nesta coluna '
                    '(só reafirmação do próprio total, derivados, ou linhas sem número).',
                    m.pai_chave)
           when m.pai_valor <> 0 and abs(m.soma - 2 * m.pai_valor) <= m.tol then
             format('"%s" informa %s e as %s parcelas somam %s — exatamente o DOBRO. '
                    'Isto não é a seção deixando de fechar: é a hierarquia do documento chegando '
                    'ACHATADA, com o subtotal de grupo e as folhas dele no mesmo nível, então a '
                    'soma conta os dois. Não há o que conferir no PDF — a extração dos valores '
                    'está correta; o que falta é o nível intermediário da árvore.',
                    m.pai_chave, m.pai_valor, m.n, m.soma)

           when m.div_abs > m.tol then
             format('"%s" informa %s e a soma das %s parcelas dá %s — diferença de %s (tolerância '
                    'de arredondamento: %s). Ou a extração perdeu/errou uma linha desta seção, ou '
                    'o documento não fecha consigo mesmo; as duas exigem olhar o PDF.',
                    m.pai_chave, m.pai_valor, m.n, m.soma, m.div_abs, m.tol)
           else
             format('"%s" = soma das %s parcelas (%s)%s.', m.pai_chave, m.n, m.soma,
                    case when m.n_reaf > 0
                         then format(', e o total reafirmado pelo documento (%s vez) confere',
                                     m.n_reaf)
                         else '' end)
         end,
         m.chaves
    from medido m;
$$;

--
-- Name: FUNCTION fn_conferir_arvore(p_documento_versao_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_conferir_arvore(p_documento_versao_id uuid) IS 'Confere, por (pai × coluna), se o valor da linha-pai é igual à soma dos filhos diretos — a identidade que todo demonstrativo obedece e que a extração teve de satisfazer sem saber que seria conferida. `campo_extraido.secao` é o pai IMEDIATO, então "os filhos de P" é pergunta exata e não casamento por semelhança. Pega linha perdida, valor errado, linha duplicada e sinal invertido, e localiza o defeito na seção. Tolerância é de ARREDONDAMENTO (~0,5·(n+1)), não percentual: 0,5% de um Ativo grande deixaria passar a conta inteira que a checagem existe para achar.';

--
-- Name: fn_conferir_lote(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_conferir_lote(p_caso_id uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_total       int;
  v_nao_extr    int := 0;
  v_d           record;
  v_nomes       text[] := array[]::text[];
begin
  if not exists (select 1 from caso where id = p_caso_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('caso %s não encontrado', p_caso_id));
  end if;

  select count(*) into v_total from documento where caso_id = p_caso_id;

  -- Resolve as que voltaram a ter extração (reprocessamento fecha sozinho).
  update pendencia p
     set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:conferir_lote'
   where p.caso_id = p_caso_id
     and p.tipo = 'documento_nao_extraido'
     and p.estado <> 'resolvida'
     and not exists (
       select 1 from fn_documentos_nao_extraidos(p_caso_id) x
        where p.motivo = 'lote:nao_extraido:' || x.documento_id::text
     );

  for v_d in select * from fn_documentos_nao_extraidos(p_caso_id) loop
    v_nao_extr := v_nao_extr + 1;
    v_nomes := v_nomes || coalesce(v_d.nome_original, '(sem nome)');

    if not exists (
      select 1 from pendencia p
       where p.caso_id = p_caso_id
         and p.tipo = 'documento_nao_extraido'
         and p.estado <> 'resolvida'
         and p.motivo = 'lote:nao_extraido:' || v_d.documento_id::text
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel,
                             descricao, documento_id, motivo)
        values (p_caso_id, 'extracao', 'documento_nao_extraido', 'bloqueante', false,
          format('O documento "%s" (%s) foi registrado no caso, mas a extração NUNCA foi '
                 'chamada para ele — não é extração vazia nem truncada: a chamada não '
                 'aconteceu. O book sai sem NENHUMA linha deste documento. Reprocessar o '
                 'lote; se repetir, o defeito é de roteamento no workflow (ver o log da '
                 'execução no n8n).',
                 coalesce(v_d.nome_original, '(sem nome)'),
                 coalesce(v_d.tipo_taxonomia, 'sem tipo')),
          v_d.documento_id, 'lote:nao_extraido:' || v_d.documento_id::text);
    end if;
  end loop;

  return jsonb_build_object(
    'caso_id', p_caso_id,
    'documentos_no_caso', v_total,
    'documentos_extraidos', v_total - v_nao_extr,
    'documentos_nao_extraidos', v_nao_extr,
    'nomes_nao_extraidos', to_jsonb(v_nomes),
    -- O lote só está íntegro quando TODO documento registrado passou pela
    -- extração. É a pergunta que faltava, e a resposta é um booleano só.
    'lote_integro', v_nao_extr = 0
  );
end;
$$;

--
-- Name: FUNCTION fn_conferir_lote(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_conferir_lote(p_caso_id uuid) IS 'Conferência de FORA do caminho da extração: nomeia os documentos que o pipeline pulou e abre pendência bloqueante por documento. Existe porque as guardas de extração vivem DENTRO da extração, e não cobrem o caso de a chamada nunca ter sido feita (Teste V45: 19 de 35).';

--
-- Name: fn_conferir_modelagem(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_conferir_modelagem(p_caso_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  with linhas as (
    select * from fn_linhas_para_modelagem(p_caso_id)
  ),
  contas as (
    select rotulo_norm from linhas where papel = 'conta'
  ),
  vinculadas as (
    select distinct l.rotulo_norm
    from caso_linha_premissa l
    where l.caso_id = p_caso_id and l.premissa_codigo is not null
      and l.rotulo_norm in (select rotulo_norm from contas)
  ),
  orfaos as (
    select distinct l.rotulo_norm
    from caso_linha_premissa l
    where l.caso_id = p_caso_id and l.premissa_codigo is not null
      and l.rotulo_norm not in (select rotulo_norm from linhas)
  ),
  nao_projetaveis as (
    select jsonb_object_agg(papel, n) as j
    from (select papel, count(*) as n from linhas where papel <> 'conta' group by papel) x
  ),
  -- 0134: a premissa ativa, com a FÓRMULA dela ao lado. É a fórmula que decide
  -- se `valores` vazio é defeito ou é o estado normal — não o código, que
  -- envelheceria a cada premissa nova.
  ativas as (
    select cp.premissa_codigo, cp.valores, pc.formula
    from caso_premissa cp
    join premissa_catalogo pc on pc.codigo = cp.premissa_codigo
    where cp.caso_id = p_caso_id and cp.ativo
  ),
  premissas as (
    select count(*) as ativas,
           array_agg(premissa_codigo order by premissa_codigo)
             filter (where formula <> 'curva_mensal'
                       and (valores is null or valores = '{}'::jsonb)) as sem_valor,
           -- O caso ruim DE VERDADE: curva mensal ativa e o caso sem documento
           -- mensal de onde derivá-la. As linhas vinculadas ficam com rateio
           -- liso, e isso precisa ser DITO — não bloqueia, porque o anual
           -- continua certo.
           array_agg(premissa_codigo order by premissa_codigo)
             filter (where formula = 'curva_mensal'
                       and not exists (select 1 from fn_sazonalidade_do_caso(p_caso_id)))
             as saz_sem_curva
    from ativas
  ),
  param as (
    select to_jsonb(m) as j from caso_modelagem m where m.caso_id = p_caso_id
  )
  select jsonb_build_object(
    'parametros', (select j from param),
    'premissas_ativas', (select ativas from premissas),
    'premissas_sem_valor', to_jsonb(coalesce((select sem_valor from premissas), array[]::text[])),
    -- 0134: informação, não bloqueio. Ver o cabeçalho.
    'sazonalidade_sem_curva',
      to_jsonb(coalesce((select saz_sem_curva from premissas), array[]::text[])),
    'linhas_do_caso', (select count(*) from contas),
    'linhas_nao_projetaveis', coalesce((select j from nao_projetaveis), '{}'::jsonb),
    'linhas_com_premissa', (select count(*) from vinculadas),
    'linhas_sem_premissa', greatest((select count(*) from contas) - (select count(*) from vinculadas), 0),
    'vinculos_orfaos', to_jsonb(coalesce(
      (select array_agg(rotulo_norm order by rotulo_norm) from orfaos), array[]::text[])),
    -- 0158: a fração de linhas PROJETÁVEIS (papel='conta') que têm premissa —
    -- mesmo denominador de `linhas_do_caso` (já exclui subtotal/serie_mensal/
    -- derivado, contados à parte em `linhas_nao_projetaveis`). NULL, não
    -- zero, quando o caso não tem linha projetável nenhuma: zero coberto de
    -- zero possível não é a mesma coisa que zero coberto de 480 possíveis, e
    -- fabricar um dos dois números pela ausência do outro é a regra 1.
    'fracao_linhas_com_premissa',
      case when (select count(*) from contas) > 0
        then round((select count(*) from vinculadas)::numeric
                    / (select count(*) from contas), 4)
        else null
      end,
    'pronto', fn_modelagem_esta_pronta(
      (select j from param) is not null,
      (select ativas from premissas),
      coalesce(array_length((select sem_valor from premissas), 1), 0),
      (select count(*) from vinculadas))
  );
$$;

--
-- Name: FUNCTION fn_conferir_modelagem(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_conferir_modelagem(p_caso_id uuid) IS 'Diagnóstico da Modelagem de um caso. Desde a 0134, premissa de `curva_mensal` (SAZONALIDADE, CRONOGRAMA_FISICO, PARADA_MANUTENCAO) NÃO conta como "sem valor": a curva dela é derivada do documento mensal por fn_sazonalidade_do_caso, não digitada, e cobrá-la travava o "pronto" com uma pendência sem ação possível. O caso ruim de verdade — curva ativa e caso sem documento mensal — ganhou nome próprio em `sazonalidade_sem_curva`, que informa e não bloqueia, porque os números ANUAIS continuam certos e só o rateio mensal fica liso. Desde a 0158, `pronto` (fn_modelagem_esta_pronta) também exige que ALGUMA linha real esteja vinculada — parâmetros definidos e premissas com valor não bastam quando zero linha do caso foi de fato coberta, ou quando a cobertura é uma fração ínfima do total (medido: 23 de 480, Grupo Vertentes) — e o retorno ganha `fracao_linhas_com_premissa` para o portal poder mostrar QUANTO, não só "pronto"/"não pronto". `vinculos_orfaos` e `sazonalidade_sem_curva` continuam informando e não bloqueando: nenhum dos dois deixa um número do book errado.';

--
-- Name: fn_conflitos_do_caso(uuid, text, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_conflitos_do_caso(p_caso_id uuid, p_entidade text DEFAULT NULL::text, p_tolerancia_abs numeric DEFAULT 100, p_tolerancia_pct numeric DEFAULT 0.005) RETURNS TABLE(secao_canonica text, chave text, entidade text, exercicio integer, documento_vencedor uuid, tipo_vencedor text, valor_vencedor numeric, documento_perdedor uuid, tipo_perdedor text, valor_perdedor numeric, diferenca numeric, decidido boolean, criterio text)
    LANGUAGE sql STABLE
    AS $$
  -- 0152: o par nasce DEPOIS do agrupamento. A versão anterior pedia o produto
  -- cartesiano (6.859.127 pares comparados para achar 34, 12,4 s por chamada).
  --
  -- A versão vigente de cada documento do caso, UMA VEZ (era chamada no join e
  -- de novo dentro de fn_autoridade_do_documento).
  with versao as materialized (
    select d.id as documento_id, d.tipo_taxonomia, d.entidade_id, d.periodo_id,
           fn_versao_com_extracao(d.id) as documento_versao_id
    from documento d
    where d.caso_id = p_caso_id
  ),
  -- (b) 0146: a capa só responde quando o documento é de UMA empresa. Num
  -- documento de várias, a linha sem coluna não tem dono e fica de fora —
  -- atribuí-la à capa criaria conflito entre uma empresa e um fantasma. UMA
  -- linha por versão, em vez de uma avaliação por linha extraída.
  multi_entidade as materialized (
    select v.documento_versao_id,
           count(distinct ce.entidade_coluna) > 1 as varias
    from versao v
    left join campo_extraido ce
      on ce.documento_versao_id = v.documento_versao_id
     and ce.entidade_coluna is not null
    group by v.documento_versao_id
  ),
  -- As linhas candidatas, com os filtros baratos (índice + coluna) primeiro.
  -- `fn_papel_linha` NÃO entra aqui — ela é a cara, e entra depois de já ter
  -- sido calculada uma vez por tripla distinta.
  cru as materialized (
    select ce.id, ce.chave, ce.unidade, ce.valor_num, ce.secao_canonica,
           ce.entidade_coluna, ce.periodo_coluna,
           v.documento_id, v.tipo_taxonomia, v.documento_versao_id,
           e.razao_social, p.referencia as periodo_referencia,
           m.varias
    from versao v
    join campo_extraido ce on ce.documento_versao_id = v.documento_versao_id
    join multi_entidade m  on m.documento_versao_id = v.documento_versao_id
    left join entidade e   on e.id = v.entidade_id
    left join periodo p    on p.id = v.periodo_id
    where ce.valor_num is not null
      and ce.secao_canonica is not null
      and ce.secao_canonica <> 'NAO_CLASSIFICAVEL'
      and fn_fator_escala(ce.unidade) is not null
  ),
  -- (d) `fn_papel_linha` uma vez por tripla distinta, não uma por linha.
  papeis as materialized (
    select t.chave, t.tipo_taxonomia, t.unidade,
           fn_papel_linha(t.chave, t.tipo_taxonomia, t.unidade) as papel
    from (select distinct chave, tipo_taxonomia, unidade from cru) t
  ),
  bruto as materialized (
    select
      c.secao_canonica,
      fn_normalizar_texto(c.chave) as rotulo,
      c.chave,
      coalesce(c.entidade_coluna, case when c.varias then null else c.razao_social end) as entidade,
      coalesce(fn_exercicio_da_coluna(c.periodo_coluna),
               fn_exercicio_da_coluna(c.periodo_referencia)) as exercicio,
      fn_valor_em_base(c.valor_num, c.unidade) as valor,
      c.documento_id,
      c.tipo_taxonomia
    from cru c
    join papeis pp
      on pp.chave = c.chave
     and pp.tipo_taxonomia is not distinct from c.tipo_taxonomia
     and pp.unidade is not distinct from c.unidade
    where pp.papel = 'conta'
  ),
  -- (e) `fn_mesma_entidade` É PLPGSQL E ESTAVA SENDO CHAMADA POR LINHA. Medido
  -- no araucária: 10.570 linhas extraídas para **40 strings de entidade
  -- distintas**. É a mesma correção do `papeis` logo acima, e o mesmo defeito:
  -- função pura avaliada sobre LINHAS quando o argumento tem poucos valores.
  entidades_do_caso as materialized (
    select distinct b.entidade from bruto b where b.entidade is not null
  ),
  entidades_alvo as materialized (
    select e.entidade from entidades_do_caso e
    where p_entidade is null or fn_mesma_entidade(e.entidade, p_entidade)
  ),
  filtrado as materialized (
    select b.* from bruto b
    join entidades_alvo ea on ea.entidade = b.entidade
    where b.exercicio is not null
  ),
  -- Um valor por (conceito, exercício, entidade, DOCUMENTO). Dentro do mesmo
  -- documento a mesma conta pode aparecer em mais de uma linha (a coluna de
  -- outro exercício, uma repetição de página); o de maior módulo representa o
  -- documento, e é a regra da 0042 usada onde ela é inofensiva — aqui ela
  -- escolhe entre linhas de UMA fonte, não entre fontes que discordam.
  por_documento as materialized (
    select f.secao_canonica, f.rotulo, f.entidade, f.exercicio, f.documento_id,
           max(f.tipo_taxonomia) as tipo,
           (array_agg(f.chave order by length(f.chave)))[1] as chave,
           (array_agg(f.valor order by abs(f.valor) desc nulls last))[1] as valor
    from filtrado f
    group by f.secao_canonica, f.rotulo, f.entidade, f.exercicio, f.documento_id
  ),
  -- (a) O AGRUPAMENTO QUE MATA O CARTESIANO. Só grupo com mais de um documento
  -- e com dispersão acima do piso da tolerância pode conter par. Ver a prova de
  -- que o pré-filtro é conservador no cabeçalho.
  grupos as materialized (
    select secao_canonica, rotulo, entidade, exercicio
    from por_documento
    group by secao_canonica, rotulo, entidade, exercicio
    having count(*) > 1
       and (max(valor) - min(valor)) > p_tolerancia_abs
  ),
  candidatos as materialized (
    select pd.*
    from por_documento pd
    join grupos g
      on g.secao_canonica = pd.secao_canonica
     and g.rotulo         = pd.rotulo
     and g.entidade       is not distinct from pd.entidade
     and g.exercicio      = pd.exercicio
  ),
  -- (c) A autoridade uma vez por DOCUMENTO — e só dos documentos que sobraram.
  -- 0159: `decide_sozinho` vem junto — é a mesma chamada, sem custo extra.
  autoridade as materialized (
    select dd.documento_id, a.autoridade, a.motivo, a.decide_sozinho
    from (select distinct documento_id from candidatos) dd
    cross join lateral fn_autoridade_do_documento(dd.documento_id) a
  ),
  com_autoridade as materialized (
    select c.*, au.autoridade, au.motivo, au.decide_sozinho
    from candidatos c join autoridade au on au.documento_id = c.documento_id
  ),
  pares as (
    select
      a.secao_canonica, a.chave, a.entidade, a.exercicio,
      a.documento_id as doc_a, a.tipo as tipo_a, a.valor as valor_a,
      a.autoridade as aut_a, a.motivo as motivo_a, a.decide_sozinho as decide_sozinho_a,
      b.documento_id as doc_b, b.tipo as tipo_b, b.valor as valor_b,
      b.autoridade as aut_b, b.motivo as motivo_b, b.decide_sozinho as decide_sozinho_b
    from com_autoridade a
    join com_autoridade b
      on b.secao_canonica = a.secao_canonica
     and b.rotulo         = a.rotulo
     and b.entidade       is not distinct from a.entidade
     and b.exercicio      = a.exercicio
     and b.documento_id   > a.documento_id          -- par sem repetir a ordem
    where abs(a.valor - b.valor)
            > greatest(p_tolerancia_abs, abs(a.valor) * p_tolerancia_pct)
  )
  select
    p.secao_canonica,
    p.chave,
    p.entidade,
    p.exercicio,
    case when p.aut_a >= p.aut_b then p.doc_a   else p.doc_b   end,
    case when p.aut_a >= p.aut_b then p.tipo_a  else p.tipo_b  end,
    case when p.aut_a >= p.aut_b then p.valor_a else p.valor_b end,
    case when p.aut_a >= p.aut_b then p.doc_b   else p.doc_a   end,
    case when p.aut_a >= p.aut_b then p.tipo_b  else p.tipo_a  end,
    case when p.aut_a >= p.aut_b then p.valor_b else p.valor_a end,
    abs(p.valor_a - p.valor_b),
    -- 0159: um lado com o rótulo contestado pelo próprio diagnóstico não
    -- decide sozinho — nem para vencer, nem para perder em silêncio.
    -- `decidido` passa a exigir os dois lados confiáveis, além da
    -- autoridade diferir.
    (p.aut_a <> p.aut_b) and p.decide_sozinho_a and p.decide_sozinho_b,
    case
      when not (p.decide_sozinho_a and p.decide_sozinho_b) then
        format('SEM DECISÃO AUTOMÁTICA: %s (autoridade %s) tem o rótulo contestado pelo próprio '
               || 'diagnóstico de conteúdo — %s. O valor em uso não foi trocado; a escolha é '
               || 'humana.',
               case when not p.decide_sozinho_a then p.tipo_a else p.tipo_b end,
               case when not p.decide_sozinho_a then p.aut_a else p.aut_b end,
               case when not p.decide_sozinho_a then p.motivo_a else p.motivo_b end)
      when p.aut_a <> p.aut_b then
        format('%s vence: %s (autoridade %s) contra %s (autoridade %s)',
               case when p.aut_a > p.aut_b then p.tipo_a else p.tipo_b end,
               case when p.aut_a > p.aut_b then p.motivo_a else p.motivo_b end,
               greatest(p.aut_a, p.aut_b),
               case when p.aut_a > p.aut_b then p.motivo_b else p.motivo_a end,
               least(p.aut_a, p.aut_b))
      else
        format('EMPATE em autoridade %s (%s × %s): a escolha é humana — o valor '
               || 'não foi trocado, continua o de maior módulo',
               p.aut_a, p.motivo_a, p.motivo_b)
    end
  from pares p;
$$;

--
-- Name: FUNCTION fn_conflitos_do_caso(p_caso_id uuid, p_entidade text, p_tolerancia_abs numeric, p_tolerancia_pct numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_conflitos_do_caso(p_caso_id uuid, p_entidade text, p_tolerancia_abs numeric, p_tolerancia_pct numeric) IS 'Dois documentos do mesmo período discordando sobre a MESMA conta, com o vencedor por autoridade documental e o critério por extenso (0151). Compara na base, só entre linhas com seção canônica, papel conta e unidade conversível. `decidido = false` é empate OU rótulo contestado pelo diagnóstico (0159, um lado com `decide_sozinho = false`) — nos dois casos ninguém vence e a decisão é humana. O par nasce DEPOIS do agrupamento (0152) — a versão anterior pedia o produto cartesiano e levava 12,4 s por chamada no lote de 190 documentos.';

--
-- Name: fn_contas_repetindo_valor(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_contas_repetindo_valor(p_documento_versao_id uuid) RETURNS TABLE(valor numeric, n_contas integer)
    LANGUAGE sql STABLE
    AS $$
  select ce.valor_num, count(distinct ce.chave)::int
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and ce.valor_num <> 0
    -- MATERIAL: 1% do maior valor da versão. Valores pequenos (18, 40, 180)
    -- coincidem à toa e geraram os falsos da v24.
    and abs(ce.valor_num) >= (
      select greatest(coalesce(max(abs(c2.valor_num)), 0) * 0.01, 1)
      from campo_extraido c2 where c2.documento_versao_id = p_documento_versao_id
    )
    -- …e NÃO são totais de grupo. Ativo = Passivo + PL faz essas quatro linhas
    -- terem o mesmo valor por construção contábil.
    and not fn_rotulo_estrutural(ce.chave, array['ativo'])
    and not fn_rotulo_estrutural(ce.chave, array['passivo','patrimonio'])
    -- 0140: …e a coluna mede dinheiro. `Exercício` repetindo 2023 é o ano, não
    -- alucinação — foi o falso positivo da v47.
    and not fn_coluna_de_dimensao(ce.periodo_coluna)
  group by ce.valor_num, coalesce(ce.entidade_coluna, ''), coalesce(ce.periodo_coluna, '')
  order by count(distinct ce.chave) desc
  limit 1;
$$;

--
-- Name: FUNCTION fn_contas_repetindo_valor(p_documento_versao_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_contas_repetindo_valor(p_documento_versao_id uuid) IS 'O valor material mais repetido entre contas DISTINTAS da mesma coluna, ignorando os totais estruturais (0034) e as colunas de dimensão (0140). Insumo do sinal 1 da guarda de extração (0013).';

--
-- Name: fn_contraparte_intragrupo(uuid, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_contraparte_intragrupo(p_caso_id uuid, p_chave text, p_entidade_dona uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  with pedacos as (
    select trim(x) as parte
    from unnest(regexp_split_to_array(coalesce(p_chave, ''), '\s+(?:-|—|–|×|x|→)\s+')) as x
    -- O primeiro pedaço é o QUE a conta é ("Conta corrente a pagar"); a
    -- contraparte está nos seguintes. Sem este corte, "Fornecedores nacionais"
    -- casaria com qualquer empresa cujo nome tivesse um token em comum.
    offset 1
  )
  select e.id
  from entidade e, pedacos p
  where e.caso_id = p_caso_id
    and (p_entidade_dona is null or e.id <> p_entidade_dona)
    and length(p.parte) >= 4
    and fn_mesma_entidade(p.parte, e.razao_social)
  limit 1;
$$;

--
-- Name: FUNCTION fn_contraparte_intragrupo(p_caso_id uuid, p_chave text, p_entidade_dona uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_contraparte_intragrupo(p_caso_id uuid, p_chave text, p_entidade_dona uuid) IS '0124: a empresa DO CASO que o rótulo nomeia como contraparte (o sufixo depois do separador), ou null. É o que permite conferir intragrupo sem adivinhar qual conta casa com qual.';

--
-- Name: fn_controlador_registrar(uuid, text, text, public.controlador_tipo_pessoa, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_controlador_registrar(p_caso_id uuid, p_nome text, p_documento text, p_tipo_pessoa public.controlador_tipo_pessoa, p_autor text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_existe boolean;
  v_documento   text := nullif(trim(coalesce(p_documento, '')), '');
  v_id          uuid;
begin
  if p_nome is null or length(trim(p_nome)) = 0 then
    raise exception 'p_nome não pode ser vazio — um controlador sem nome não é registrável';
  end if;

  select exists(select 1 from caso where id = p_caso_id) into v_caso_existe;
  if not v_caso_existe then
    raise exception 'caso % não encontrado', p_caso_id;
  end if;

  insert into controlador (caso_id, nome, documento, tipo_pessoa)
  values (p_caso_id, trim(p_nome), v_documento, p_tipo_pessoa)
  returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'controlador_registrado', 'controlador:' || v_id,
          jsonb_build_object('caso_id', p_caso_id, 'nome', trim(p_nome),
                              'documento', v_documento, 'tipo_pessoa', p_tipo_pessoa));

  return v_id;
end;
$$;

--
-- Name: FUNCTION fn_controlador_registrar(p_caso_id uuid, p_nome text, p_documento text, p_tipo_pessoa public.controlador_tipo_pessoa, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_controlador_registrar(p_caso_id uuid, p_nome text, p_documento text, p_tipo_pessoa public.controlador_tipo_pessoa, p_autor text) IS '0182: o ÚNICO caminho de escrita de `controlador` — chamado por um humano/analista (portal ou SQL direto; o portal não é escopo desta fatia). Grava evento_auditoria (ator = p_autor, nunca ''sistema:...''). NADA é inferido de campo_extraido, nome ou CNPJ — a decisão de QUEM é controlador vem do contrato social na mão de quem chama.';

--
-- Name: fn_decidir_pendencia(uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_decidir_pendencia(p_pendencia_id uuid, p_autor text, p_decisao text, p_motivo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_p       pendencia%rowtype;
  v_estado  pendencia_estado;
  v_motivo  text := nullif(trim(coalesce(p_motivo, '')), '');
  v_rotulo  text;
  v_tipo    decisao_tipo;
begin
  select * into v_p from pendencia where id = p_pendencia_id;
  if v_p.id is null then
    raise exception 'pendência % não encontrada', p_pendencia_id;
  end if;

  -- Os três botões da tela, nas palavras da tela.
  case p_decisao
    when 'contatar_cliente' then
      v_estado := 'reenviada_ao_cliente'; v_rotulo := 'Contatar o Cliente'; v_tipo := null;
    when 'prosseguir' then
      v_estado := 'aceita_com_ressalva';  v_rotulo := 'Prosseguir sem resolução'; v_tipo := 'ressalva';
    when 'nao_procede' then
      v_estado := 'rejeitada';            v_rotulo := 'Pendência não procede'; v_tipo := 'override';
    else
      return jsonb_build_object('recusado', true, 'pendencia_id', p_pendencia_id,
        'motivo_recusa', format('Decisão desconhecida: %s. São três — contatar_cliente, '
                                'prosseguir, nao_procede.', p_decisao));
  end case;

  -- Clicar de novo no mesmo botão é no-op declarado: dois cliques não viram
  -- duas decisões na trilha.
  if v_p.estado = v_estado then
    return jsonb_build_object('sem_mudanca', true, 'pendencia_id', p_pendencia_id,
                              'estado', v_estado, 'rotulo', v_rotulo,
                              'avaliacao', fn_avaliar_portao2(v_p.caso_id));
  end if;

  -- `resolvida` é do SISTEMA: ela significa "a condição que abriu a pendência
  -- deixou de valer", e um clique humano não pode afirmar isso. Trocar uma
  -- resolvida por decisão humana reescreveria o que o motor mediu.
  if v_p.estado = 'resolvida' then
    return jsonb_build_object('recusado', true, 'pendencia_id', p_pendencia_id,
      'motivo_recusa', 'Esta pendência já foi RESOLVIDA pelo próprio sistema: o problema que a '
        || 'abriu deixou de existir. Não há o que decidir sobre ela.');
  end if;

  update pendencia
     set estado        = v_estado,
         motivo        = coalesce(v_motivo, motivo),
         -- `resolvida_em`/`por` marcam QUANDO e QUEM tirou a pendência da fila.
         -- Para o estado de tratamento ficam nulos: contatar o cliente não tira
         -- nada da fila, só diz que alguém está cuidando.
         resolvida_em  = case when v_estado in ('rejeitada', 'aceita_com_ressalva') then now() else null end,
         resolvida_por = case when v_estado in ('rejeitada', 'aceita_com_ressalva') then p_autor else null end
   where id = p_pendencia_id;

  -- Decisão sobre o MÉRITO vira `decisao`; "estou cuidando" não vira, porque
  -- ninguém decidiu nada ainda.
  if v_tipo is not null then
    insert into decisao (caso_id, tipo, autor, motivo, payload)
      values (v_p.caso_id, v_tipo, p_autor, coalesce(v_motivo, v_rotulo),
              jsonb_build_object('acao', 'decidir_pendencia', 'decisao', p_decisao,
                                 'rotulo', v_rotulo, 'pendencia_id', p_pendencia_id,
                                 'tipo', v_p.tipo, 'severidade', v_p.severidade,
                                 'sobrepujavel', v_p.sobrepujavel,
                                 'estado_anterior', v_p.estado));
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'pendencia_decidida', 'pendencia:'||p_pendencia_id,
            jsonb_build_object('estado', v_p.estado),
            jsonb_build_object('estado', v_estado, 'rotulo', v_rotulo,
                               'caso_id', v_p.caso_id, 'motivo', v_motivo));

  return jsonb_build_object('decidida', true, 'pendencia_id', p_pendencia_id,
                            'estado', v_estado, 'rotulo', v_rotulo,
                            'avaliacao', fn_avaliar_portao2(v_p.caso_id));
end;
$$;

--
-- Name: FUNCTION fn_decidir_pendencia(p_pendencia_id uuid, p_autor text, p_decisao text, p_motivo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_decidir_pendencia(p_pendencia_id uuid, p_autor text, p_decisao text, p_motivo text) IS 'Os três botões da tela em UMA função: contatar_cliente (não libera o portão — o documento ainda não chegou), prosseguir (aceita com ressalva) e nao_procede (rejeita). Sem motivo obrigatório, sem expiração e sem teto, por decisão do dono (0109). Nada é apagado e tudo é contado.';

--
-- Name: fn_definir_modelagem(uuid, text, integer, text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_definir_modelagem(p_caso_id uuid, p_entidade text, p_ultimo_exercicio_real integer, p_indice_macro text, p_setor text, p_autor text, p_anos_projetados integer DEFAULT 5) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_antes jsonb;
begin
  if not exists (select 1 from caso where id = p_caso_id) then
    raise exception 'caso % não encontrado', p_caso_id;
  end if;

  select to_jsonb(m) into v_antes from caso_modelagem m where m.caso_id = p_caso_id;

  insert into caso_modelagem (caso_id, entidade, ultimo_exercicio_real, indice_macro, setor,
                              anos_projetados, atualizado_por, atualizado_em)
    values (p_caso_id, p_entidade, p_ultimo_exercicio_real, p_indice_macro, p_setor,
            p_anos_projetados, p_autor, now())
  on conflict (caso_id) do update
    set entidade = excluded.entidade,
        ultimo_exercicio_real = excluded.ultimo_exercicio_real,
        indice_macro = excluded.indice_macro,
        setor = excluded.setor,
        anos_projetados = excluded.anos_projetados,
        atualizado_por = excluded.atualizado_por,
        atualizado_em = now();

  -- Parâmetro de modelagem é DECISÃO DE ANÁLISE: trocar a entidade modelada ou o
  -- corte do último exercício real muda todos os números projetados do book.
  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'modelagem_parametros', 'caso:'||p_caso_id, v_antes,
            (select to_jsonb(m) from caso_modelagem m where m.caso_id = p_caso_id));

  return (select to_jsonb(m) from caso_modelagem m where m.caso_id = p_caso_id);
end;
$$;

--
-- Name: fn_desativar_premissa(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_desativar_premissa(p_caso_id uuid, p_codigo text, p_autor text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_nome     text;
  v_ativa    boolean;
  v_vinculos int := 0;
  v_sazo     int := 0;
  v_orfas    int := 0;
begin
  select nome into v_nome from premissa_catalogo where codigo = p_codigo;
  if v_nome is null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'premissa_recusada', 'caso:'||p_caso_id,
              jsonb_build_object('codigo', p_codigo, 'porque', 'codigo inexistente no catalogo',
                                 'acao_pedida', 'desativar'));
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não existe no catálogo.', p_codigo));
  end if;

  select ativo into v_ativa
  from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_codigo;

  -- Nunca ativada, ou já desativada. Não é exceção — é um clique que não tem o
  -- que desfazer, e a resposta precisa dizer isso em vez de fingir sucesso.
  if v_ativa is null or v_ativa = false then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não está ativa neste caso — não há o que remover.',
                              v_nome));
  end if;

  -- 1. O vínculo que dirige a projeção da linha.
  update caso_linha_premissa
     set premissa_codigo = null, atualizado_por = p_autor, atualizado_em = now()
   where caso_id = p_caso_id and premissa_codigo = p_codigo;
  get diagnostics v_vinculos = row_count;

  -- 2. O mesmo código usado como CURVA MENSAL da linha (natureza sazonalidade).
  update caso_linha_premissa
     set sazonalidade_codigo = null, atualizado_por = p_autor, atualizado_em = now()
   where caso_id = p_caso_id and sazonalidade_codigo = p_codigo;
  get diagnostics v_sazo = row_count;

  -- 3. Linha que ficou sem as duas não é "linha sem premissa": é linha sobre a
  -- qual não há mais decisão registrada. Mantê-la faria a trilha afirmar uma
  -- escolha que o analista desfez.
  delete from caso_linha_premissa
   where caso_id = p_caso_id and premissa_codigo is null and sazonalidade_codigo is null;
  get diagnostics v_orfas = row_count;

  update caso_premissa
     set ativo = false, atualizado_por = p_autor, atualizado_em = now()
   where caso_id = p_caso_id and premissa_codigo = p_codigo;

  -- `valores` NÃO é apagado, de propósito: reativar a premissa devolve o que já
  -- tinha sido digitado. Remover por engano custa um clique para desfazer, não
  -- cinco anos de valores redigitados.
  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'override', p_autor,
            format('Premissa "%s" REMOVIDA da modelagem (%s vínculo(s) e %s sazonalidade(s) desfeitos)',
                   v_nome, v_vinculos, v_sazo),
            jsonb_build_object('premissa', p_codigo, 'ativo', false,
                               'n_vinculos_desfeitos', v_vinculos,
                               'n_sazonalidades_desfeitas', v_sazo,
                               'n_linhas_removidas', v_orfas));

  return jsonb_build_object(
    'caso_id', p_caso_id, 'premissa', p_codigo, 'nome', v_nome, 'ativo', false,
    'n_vinculos_desfeitos', v_vinculos,
    'n_sazonalidades_desfeitas', v_sazo,
    'n_linhas_removidas', v_orfas);
end;
$$;

--
-- Name: FUNCTION fn_desativar_premissa(p_caso_id uuid, p_codigo text, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_desativar_premissa(p_caso_id uuid, p_codigo text, p_autor text) IS 'Desativa a premissa no caso e LIMPA os vínculos que ela dirigia (premissa e sazonalidade), devolvendo quantos foram desfeitos. Vínculo órfão faria tela, conferência e export lerem o mesmo caso de três formas diferentes. `valores` é preservado para a reativação.';

--
-- Name: fn_descricao_extracao_falhou(text, integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_descricao_extracao_falhou(p_nome_original text, p_pares integer, p_motivo text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  -- 0154: a unidade vai escrita. `p_pares` conta linhas de `campo_extraido`,
  -- que são PARES conta × coluna — uma conta com cinco exercícios são cinco.
  -- O motivo, quando vem da guarda de cobertura, fala em LINHAS do documento.
  -- Sem os dois nomes por extenso a frase parece se contradizer.
  select format(
    'Extração de "%s" falhou ou veio incompleta (%s par(es) conta×coluna gravado(s)). Motivo: %s',
    coalesce(p_nome_original, '?'),
    coalesce(p_pares, 0),
    coalesce(p_motivo,
             'a chamada respondeu sem erro, mas não trouxe NENHUMA linha. '
             'Causa mais comum: formato que o pipeline ainda não converte em texto '
             '(.xlsx/.docx) — nesses casos a IA recebe um aviso em vez do arquivo.'));
$$;

--
-- Name: FUNCTION fn_descricao_extracao_falhou(p_nome_original text, p_pares integer, p_motivo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_descricao_extracao_falhou(p_nome_original text, p_pares integer, p_motivo text) IS 'A descrição da pendência de extração incompleta, com a UNIDADE escrita (0154): o número do banco são PARES conta×coluna e o da guarda de cobertura são LINHAS do documento. Juntos e sem nome, "276 gravadas / 68 devolvidas" parece contradição — e uma pendência que parece se contradizer ensina a ignorar a fila.';

--
-- Name: fn_descricao_linha_exigida(text, text, text, text[], text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_descricao_linha_exigida(p_tipo text, p_entidade text, p_rotulo text, p_depende_de text[], p_origem text, p_alternativa_rotulo text, p_alternativa_recado text) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select case
    when p_alternativa_recado is not null and p_entidade is not null then
      format('Nos documentos de %s da entidade "%s", a linha exigida "%s" não existe como tal: o '
             'documento traz "%s" no lugar. %s Sem a linha exigida, PARA ESTA ENTIDADE: %s.%s',
             p_tipo, p_entidade, p_rotulo, p_alternativa_rotulo, p_alternativa_recado,
             array_to_string(p_depende_de, '; '),
             case when p_origem = 'proposta'
                  then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                  else '' end)
    when p_alternativa_recado is not null then
      format('O tipo %s chegou e rendeu linhas, mas a linha exigida "%s" não existe como tal: o '
             'documento traz "%s" no lugar. %s Sem a linha exigida: %s.%s',
             p_tipo, p_rotulo, p_alternativa_rotulo, p_alternativa_recado,
             array_to_string(p_depende_de, '; '),
             case when p_origem = 'proposta'
                  then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                  else '' end)
    when p_entidade is not null then
      format('Nos documentos de %s da entidade "%s", a linha exigida "%s" não foi '
             'localizada na versão vigente. Sem ela, PARA ESTA ENTIDADE: %s.%s Conferir '
             'se o documento dela traz a linha com outro rótulo (e corrigir na revisão) '
             'ou reenviar o arquivo completo.',
             p_tipo, p_entidade, p_rotulo,
             array_to_string(p_depende_de, '; '),
             case when p_origem = 'proposta'
                  then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                  else '' end)
    else
      format('O tipo %s chegou e rendeu linhas, mas a linha exigida "%s" não foi '
             'localizada na versão vigente de nenhum documento do tipo. Sem ela: %s.%s '
             'Conferir se o documento traz a linha com outro rótulo (e corrigir na '
             'revisão) ou reenviar o arquivo completo.',
             p_tipo, p_rotulo,
             array_to_string(p_depende_de, '; '),
             case when p_origem = 'proposta'
                  then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                  else '' end)
  end;
$$;

--
-- Name: FUNCTION fn_descricao_linha_exigida(p_tipo text, p_entidade text, p_rotulo text, p_depende_de text[], p_origem text, p_alternativa_rotulo text, p_alternativa_recado text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_descricao_linha_exigida(p_tipo text, p_entidade text, p_rotulo text, p_depende_de text[], p_origem text, p_alternativa_rotulo text, p_alternativa_recado text) IS '0188: a descrição da pendência linha_exigida_ausente. Sem alternativa, o texto de sempre (0119/0157: "não foi localizada … conferir o rótulo ou reenviar"); com alternativa, o que o documento traz no lugar e o recado de taxonomia_linha_alternativa.';

--
-- Name: fn_diagnostico_modelagem(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_diagnostico_modelagem(p_caso_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  with instalada as (
    select jsonb_object_agg(p.proname, pg_get_functiondef(p.oid) like '%marca-0102%') as j
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_versao_com_extracao', 'fn_linhas_para_modelagem',
                        'fn_papel_do_rotulo_no_caso', 'fn_sazonalidade_do_caso',
                        'fn_valores_por_ano', 'fn_linhas_do_tipo')
  ),
  ocorrencia as (
    select dv.id = fn_versao_com_extracao(d.id) as vigente
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id and ce.valor_num is not null
  ),
  linha as (select papel from fn_linhas_para_modelagem(p_caso_id))
  select jsonb_build_object(
    'caso_id', p_caso_id,
    'correcoes_instaladas', (select j from instalada),
    'conferir_modelagem_e_0101',
      (select pg_get_functiondef(p.oid) like '%with linhas as%'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'fn_conferir_modelagem' limit 1),
    'documentos', (select count(*) from documento where caso_id = p_caso_id),
    'documentos_com_versao_superada', (
      select count(*) from documento d
      where d.caso_id = p_caso_id
        and (select count(*) from documento_versao dv
             where dv.documento_id = d.id
               and exists (select 1 from campo_extraido ce where ce.documento_versao_id = dv.id)) > 1),
    'ocorrencias_total', (select count(*) from ocorrencia),
    'ocorrencias_vigentes', (select count(*) from ocorrencia where vigente),
    'ocorrencias_superadas', (select count(*) from ocorrencia where not vigente),
    'linhas', (select count(*) from linha),
    'linhas_projetaveis', (select count(*) from linha where papel = 'conta'),
    'linhas_por_papel', (select jsonb_object_agg(papel, n)
                         from (select papel, count(*) n from linha group by papel) x)
  );
$$;

--
-- Name: FUNCTION fn_diagnostico_modelagem(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_diagnostico_modelagem(p_caso_id uuid) IS 'Diagnóstico da tela de Modelagem de um caso, para rodar no SQL Editor: se as correções da 0101/0102 estão INSTALADAS no banco (merge não é apply), quantas ocorrências vinham de versão superada, e quantas linhas a tela deve mostrar. Existe porque "já apliquei" e "ainda não apliquei" tinham a mesma aparência na tela.';

--
-- Name: fn_dial(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_dial(p_estagio text) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select jsonb_build_object(
    'estagio', ea.estagio,
    'nivel_atual', ea.nivel_atual,
    'teto', ea.teto,
    'limiar_auto_clear', ea.limiar_auto_clear,
    'no_teto', ea.nivel_atual = ea.teto,
    'natureza', ea.natureza,
    'base_do_nivel', ea.base_do_nivel,
    'medicao_rodada_id', ea.medicao_rodada_id,
    'medicao_em', ea.medicao_em,
    'medicao_resumo', ea.medicao_resumo,
    'atualizado_por', ea.atualizado_por,
    'atualizado_em', ea.atualizado_em
  )
  from estagio_autonomia ea where ea.estagio = p_estagio;
$$;

--
-- Name: fn_dial_auto_promover(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_dial_auto_promover(p_estagio text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  r         record;
  v_med     jsonb;
  v_res     jsonb;
  v_feitos  jsonb := '[]'::jsonb;
begin
  for r in
    select ea.estagio, ea.nivel_atual, ea.teto, ea.auto_promocao, ea.natureza
      from estagio_autonomia ea
     where (p_estagio is null or ea.estagio = p_estagio)
       and ea.natureza = 'interpretativo'
       and ea.auto_promocao
       and ea.nivel_atual < 'N2'::nivel_autonomia
       and ea.teto >= 'N2'::nivel_autonomia
  loop
    v_med := fn_veredito_producao(r.estagio);
    if not coalesce((v_med->>'suficiente')::boolean, false) then
      continue;
    end if;

    -- A PROMOÇÃO PASSA PELA MESMA PORTA DE SEMPRE. Chamar `fn_mudar_dial` em vez
    -- de dar `update` na tabela é o que garante que a automação não escape de
    -- nenhuma guarda: o teto, a regra de ouro e a trilha continuam sendo os
    -- mesmos, e o dia em que uma guarda nova for acrescentada lá ela passa a
    -- valer aqui sem ninguém lembrar de copiar.
    v_res := fn_mudar_dial(
      r.estagio, 'N2'::nivel_autonomia, 'sistema:auto_dial',
      format('Promoção automática (0137): o veredito de produção alcançou o critério — %s vereditos '
             'a %s de concordância, mínimo %s a %s. O número é PISO enviesado, e por isso a subida '
             'para em N2.',
             v_med->>'n', v_med->>'concordancia',
             v_med->>'n_minimo', v_med->>'concordancia_minima'),
      null, null, null, true);

    v_feitos := v_feitos || jsonb_build_object(
      'estagio', r.estagio,
      'de', r.nivel_atual,
      'para', v_res->>'nivel_atual',
      'recusado', coalesce((v_res->>'recusado')::boolean, false),
      'medicao', v_med);
  end loop;

  return jsonb_build_object(
    'promovidos', v_feitos,
    'quantos', jsonb_array_length(v_feitos),
    'como_ler', 'Promoção automática por veredito de produção (0137). Ela sobe no máximo até N2, '
                'nunca N3: o veredito mede um PISO enviesado, e piso não sustenta autonomia plena. '
                'Estágio com auto_promocao = false não entra aqui — é o freio de quem baixou o '
                'nível à mão, e religá-lo é decisão explícita.');
end;
$$;

--
-- Name: FUNCTION fn_dial_auto_promover(p_estagio text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_dial_auto_promover(p_estagio text) IS 'Sobe para N2 todo estágio interpretativo elegível cujo veredito de produção alcançou o critério (0137). Sobe pela fn_mudar_dial, nunca por update direto, para não escapar de guarda nenhuma. Para em N2 por decisão: piso enviesado não sustenta autonomia plena.';

--
-- Name: fn_dial_influencia(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_dial_influencia(p_estagio text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  select coalesce(
    (select ea.nivel_atual <> 'N0' from estagio_autonomia ea where ea.estagio = p_estagio),
    -- Sem linha no dial, INFLUENCIA. Aqui o default seguro é o oposto do de
    -- fn_dial_permite_auto, e de propósito: calar um achado por falta de
    -- configuração esconderia problema, enquanto auto-aceitar por falta de
    -- configuração criaria fato. Em dúvida, mostre para o humano.
    true);
$$;

--
-- Name: FUNCTION fn_dial_influencia(p_estagio text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_dial_influencia(p_estagio text) IS 'O resultado deste estágio pode chegar à fila de alguém? False só em N0, que o Arquitetura do Sistema/1 Visão e Doutrina/01 define como "roda, registra, NÃO influencia decisão" — estágio em N0 que abre pendência não está em N0. Sem linha no dial devolve TRUE (oposto de fn_dial_permite_auto, de propósito: calar achado por falta de configuração esconde problema; auto-aceitar por falta de configuração cria fato).';

--
-- Name: fn_dial_permite_auto(text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_dial_permite_auto(p_estagio text, p_confianca numeric) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  select coalesce(
    (select ea.nivel_atual in ('N2','N3')
              and ea.limiar_auto_clear is not null
              and p_confianca is not null
              and p_confianca >= ea.limiar_auto_clear
       from estagio_autonomia ea where ea.estagio = p_estagio),
    false);
$$;

--
-- Name: FUNCTION fn_dial_permite_auto(p_estagio text, p_confianca numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_dial_permite_auto(p_estagio text, p_confianca numeric) IS 'Este estágio, nesta confiança, pode seguir SEM humano? Leitor único da regra de auto-clear do Arquitetura do Sistema/1 Visão e Doutrina/01, para ela não existir copiada em quatro funções. Sem linha no dial devolve false: ausência de configuração não é permissão (fechamento #1, default-para-humano).';

--
-- Name: fn_divergencias_indice_macro(numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_divergencias_indice_macro(p_tolerancia numeric DEFAULT 0.011) RETURNS TABLE(serie text, data_ref date, fonte_a text, valor_a numeric, fonte_b text, valor_b numeric, delta numeric)
    LANGUAGE sql STABLE
    AS $$
  select a.serie, a.data_ref, a.fonte, a.valor, b.fonte, b.valor, abs(a.valor - b.valor)
  from indice_macro_obs a
  join indice_macro_obs b
    on b.serie = a.serie and b.data_ref = a.data_ref and b.fonte > a.fonte
  where abs(a.valor - b.valor) > p_tolerancia
  order by a.data_ref desc, a.serie;
$$;

--
-- Name: fn_documento_balanco(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_documento_balanco(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid) RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select d.id
  from documento d
  where d.caso_id = p_caso_id
    and d.tipo_taxonomia in ('BALANCO', 'COMBINADO', 'BALANCETE')
    and (p_entidade_id is null or d.entidade_id = p_entidade_id)
    and (p_periodo_id is null or d.periodo_id = p_periodo_id
         or fn_periodos_compativeis(d.periodo_id, p_periodo_id))
  order by array_position(array['BALANCO', 'COMBINADO', 'BALANCETE'], d.tipo_taxonomia),
           d.criado_em desc
  limit 1;
$$;

--
-- Name: fn_documento_de_varias_empresas(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_documento_de_varias_empresas(p_documento_id uuid) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  -- 0155: o critério é ESTRUTURAL — quantas empresas as colunas nomeiam.
  --
  -- DUAS OU MAIS, e não "mais que zero": um comparativo de exercícios de UMA
  -- empresa também declara `entidade_coluna` (a mesma, repetida), e rebaixá-lo
  -- transformaria todo balanço multi-ano em derivado.
  select count(distinct ce.entidade_coluna) > 1
  from campo_extraido ce
  where ce.documento_versao_id = fn_versao_com_extracao(p_documento_id)
    and ce.entidade_coluna is not null;
$$;

--
-- Name: FUNCTION fn_documento_de_varias_empresas(p_documento_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_documento_de_varias_empresas(p_documento_id uuid) IS 'As linhas deste documento nomeiam mais de uma empresa? (0155) Critério ESTRUTURAL de que a peça é derivada — a soma de várias companhias —, independente do rótulo que o classificador lhe deu. Medido no book-araucaria: o mesmo padrão de nome saiu como BALANCO em quatro documentos e COMBINADO num quinto, todos com 14-15 empresas nas colunas.';

--
-- Name: fn_documento_decide_sozinho(text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_documento_decide_sozinho(p_codigo text, p_tipo_incorreto_aberto boolean) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  -- 0159: falso SÓ quando o rótulo é COMBINADO (o único tipo que se
  -- autodeclara "peça derivada" no catálogo) E o próprio diagnóstico de
  -- conteúdo do caso já abriu (e ninguém resolveu) uma pendência dizendo que
  -- o tipo está errado. Não olha estrutura nenhuma — ver o cabeçalho desta
  -- migration para o porquê: um critério estrutural "menos de duas empresas
  -- ⇒ suspeito" derrubou um fixture legítimo (desempate.test.sql) que nunca
  -- teve motivo para marcar `entidade_coluna`.
  select not (p_codigo = 'COMBINADO' and coalesce(p_tipo_incorreto_aberto, false));
$$;

--
-- Name: FUNCTION fn_documento_decide_sozinho(p_codigo text, p_tipo_incorreto_aberto boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_documento_decide_sozinho(p_codigo text, p_tipo_incorreto_aberto boolean) IS '(0159) Um documento rotulado COMBINADO cujo próprio diagnóstico de conteúdo já abriu (e ninguém resolveu) uma pendência tipo_incorreto tem o rótulo contestado pelo sistema que o classificou — medido no araucária de 03/09: seis documentos COMBINADO, ZERO empresas na planilha, com `tipo_incorreto` aberta dizendo "trata-se de balanço... não combinado". Esta função isola a decisão para ser exercitada por literais (instalacao_sonda_rotulo_contraditorio) sem fixture de documento nem de pendência. Não é o espelho estrutural de fn_documento_de_varias_empresas (0155) — esse espelho foi tentado e MEDIDO como falso: menos de duas empresas nas colunas não prova que a peça não é derivada, só que o documento não marcou `entidade_coluna` (ver o cabeçalho da 0159). O sinal usado aqui é o que o próprio sistema já publica na tela de pendências, não uma inferência nova sobre dados que podem simplesmente estar ausentes por outro motivo.';

--
-- Name: fn_documento_por_tipo(uuid, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_documento_por_tipo(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text) RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select d.id
  from documento d
  where d.caso_id = p_caso_id
    and d.tipo_taxonomia = p_tipo
    and (p_entidade_id is null or d.entidade_id = p_entidade_id or d.entidade_id is null)
    and (p_periodo_id is null or d.periodo_id = p_periodo_id
         or fn_periodos_compativeis(d.periodo_id, p_periodo_id))
  order by d.criado_em desc
  limit 1;
$$;

--
-- Name: fn_documento_preliminar(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_documento_preliminar(p_nome text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  -- Os parênteses NÃO são estilo: `~` tem precedência MAIOR que `||`, então sem
  -- eles o Postgres lê `(texto ~ 'primeira metade') || 'segunda metade'` e a
  -- função devolve TEXTO em vez de booleano — casando com meia expressão.
  select fn_normalizar_texto(coalesce(p_nome, '')) ~
    ('(^|[^a-z])(preliminar|preliminary|rascunho|draft|provisori[ao]|minuta|prev[ei]a|wip|'
     || 'nao auditad[ao]|sem auditoria|nao revisad[ao]|para discussao)([^a-z]|$)');
$_$;

--
-- Name: FUNCTION fn_documento_preliminar(p_nome text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_documento_preliminar(p_nome text) IS 'O nome do arquivo declara que o documento é preliminar/rascunho? Só REBAIXA autoridade (0151), nunca levanta: falso positivo custa um degrau e meio e fica escrito na pendência; falso negativo não muda nada.';

--
-- Name: fn_documento_serve_como(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_documento_serve_como(p_documento_id uuid, p_tipo_taxonomia text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  select exists (
    select 1 from documento d
    where d.id = p_documento_id
      and (
        d.tipo_taxonomia = p_tipo_taxonomia
        -- Revisão da 0157: aqui só se calcula o DADO que a decisão pede —
        -- quantas empresas distintas têm valor_num extraído (não só
        -- cabeçalho) na versão vigente. A decisão em si (fonte permitida +
        -- limiar) mora em fn_combinado_estrutural_apto.
        or (
          p_tipo_taxonomia = 'COMBINADO'
          and fn_combinado_estrutural_apto(
                d.tipo_taxonomia,
                (select count(distinct ce.entidade_coluna)::int
                   from campo_extraido ce
                  where ce.documento_versao_id = fn_versao_com_extracao(d.id)
                    and ce.valor_num is not null
                    and ce.entidade_coluna is not null)
              )
        )
      )
  );
$$;

--
-- Name: FUNCTION fn_documento_serve_como(p_documento_id uuid, p_tipo_taxonomia text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_documento_serve_como(p_documento_id uuid, p_tipo_taxonomia text) IS 'Este documento satisfaz o item <tipo_taxonomia> do Kit Básico, mesmo que rotulado diferente? Regra do rótulo (tipo_taxonomia = codigo) OU, só para o código COMBINADO, a decisão de fn_combinado_estrutural_apto (revisão da 0157, achados A e B): fonte é demonstração contábil primária (DRE/BALANCO/FLUXO_CAIXA) E mais de uma empresa tem VALOR extraído nas colunas — não só cabeçalho. Não é fn_documento_de_varias_empresas (0155): aquela serve AUTORIDADE e não exige conteúdo; esta serve o checklist e exige. Medido no lote 7377 (mandato "teste Canastra"): dois documentos com 8 empresas na planilha, confiança 1,0, classificados de BALANCO, travavam o item COMBINADO como ausente e não-sobrepujável. A exceção NÃO generaliza para outros tipos-ALVO — de propósito, para o Kit Básico continuar exigindo o balanço individual mesmo com um combinado no caso.';

--
-- Name: fn_documentos_nao_extraidos(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_documentos_nao_extraidos(p_caso_id uuid) RETURNS TABLE(documento_id uuid, tipo_taxonomia text, nome_original text)
    LANGUAGE sql STABLE
    AS $$
  select d.id, d.tipo_taxonomia,
         (select dv.nome_original from documento_versao dv
           where dv.documento_id = d.id order by dv.n_versao desc limit 1)
  from documento d
  where d.caso_id = p_caso_id
    and not exists (
      select 1
      from documento_versao dv
      join evento_auditoria ea
        on ea.acao = 'extracao_sombra'
       and ea.entidade_ref = 'documento_versao:' || dv.id::text
      where dv.documento_id = d.id
    )
  order by d.tipo_taxonomia, 3;
$$;

--
-- Name: FUNCTION fn_documentos_nao_extraidos(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_documentos_nao_extraidos(p_caso_id uuid) IS 'Documentos do caso para os quais a extração NUNCA foi chamada (sem evento extracao_sombra em nenhuma versão). Zero linha com extração feita NÃO entra aqui — isso é 0111/0036.';

--
-- Name: fn_entidade_aprender_cnpj(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_aprender_cnpj(p_entidade_id uuid, p_cnpj text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_cnpj       text := fn_cnpj_canonico(p_cnpj);
  v_caso_id    uuid;
  v_nome_atual text;
  v_cnpj_atual text;
  v_outra_id   uuid;
  v_outra_nome text;
  v_outra_e_balcao boolean;
  v_esta_e_balcao  boolean;
begin
  if p_entidade_id is null or v_cnpj is null then return p_entidade_id; end if;

  select caso_id, razao_social, cnpj into v_caso_id, v_nome_atual, v_cnpj_atual
    from entidade where id = p_entidade_id;
  if v_caso_id is null then return p_entidade_id; end if;

  -- `cnpj is not null`, NÃO `fn_cnpj_canonico(cnpj) is not null` — a diferença
  -- é a mesma da versão original (0169): com o canônico, um CNPJ INVÁLIDO já
  -- gravado por uma pessoa seria SOBRESCRITO pelo que a IA leu. Coluna vazia é
  -- ausência; coluna com número ruim é registro humano que só humano corrige.
  if v_cnpj_atual is not null then
    return p_entidade_id;
  end if;

  -- 0174: OUTRA entidade do MESMO CASO pode já ter este CNPJ — é o cenário
  -- inteiro desta migration. Ver o cabeçalho para a medição em produção.
  select id, razao_social into v_outra_id, v_outra_nome
    from entidade
   where caso_id = v_caso_id and id <> p_entidade_id
     and fn_cnpj_canonico(cnpj) = v_cnpj
   limit 1;

  if v_outra_id is not null then
    v_outra_e_balcao := fn_entidade_e_balcao_ambiguo(v_caso_id, v_outra_id);
    v_esta_e_balcao  := fn_entidade_e_balcao_ambiguo(v_caso_id, p_entidade_id);

    -- 0177 (CRÍTICO): a guarda da 0176 só olhava a direção
    -- "`v_outra_id` é balcão e `p_entidade_id` não é". Mas desde a 0175, o
    -- caminho PRINCIPAL de `fn_registrar_diagnostico` chama esta função com
    -- `p_entidade_id` = o PRÓPRIO BALCÃO (é ele quem está "aprendendo") — e
    -- nessa direção a condição da 0176 era FALSA (a confirmada não é
    -- balcão) e a fusão passava: `fn_fundir_entidade` deletava o BALCÃO
    -- (`p_de_id = p_entidade_id`) dentro da confirmada, e resolvia a
    -- pendência `entidade_ambigua:<balcão>` — BLOQUEANTE — junto, sem
    -- pendência de colisão nenhuma no lugar. MEDIDO nesta sessão (mesmos
    -- dados do teste da 0176, ordem de chegada invertida): 4 entidades/1
    -- pendência bloqueante → 3 entidades/0 bloqueantes/0 colisões, balcão
    -- deletado, 2 documentos dentro da confirmada (era 1). O invariante
    -- correto é XOR: EXATAMENTE um dos dois lados é balcão bloqueia a
    -- fusão, nas DUAS direções — quando os DOIS são balcão (convergência
    -- 0175) ou os DOIS são confirmados (0169/0174), funde normalmente como
    -- sempre fundiu.
    if v_outra_e_balcao <> v_esta_e_balcao then
      if v_outra_e_balcao then
        perform fn_pendencia_cnpj_colide_balcao(v_caso_id, v_outra_id, v_cnpj, v_nome_atual, p_entidade_id);
      else
        perform fn_pendencia_cnpj_colide_balcao(v_caso_id, p_entidade_id, v_cnpj, v_outra_nome, v_outra_id);
      end if;
      -- Em QUALQUER direção, devolve p_entidade_id inalterado — se ele é o
      -- balcão recusado, continua existindo e continua ambíguo (o mesmo
      -- contrato que a 0176 já tinha para o caso em que a recusa protegia a
      -- entidade que chegou).
      return p_entidade_id;
    end if;

    -- FUNDE sem perguntar ao nome — é a MESMA regra 1 da 0169 ("CNPJ é a
    -- identidade que o nome não é"), chegando pela porta do diagnóstico em
    -- vez da porta de registro. Chega aqui porque os DOIS lados são balcão
    -- (convergência balcão↔balcão, o PONTO da 0175) ou os DOIS são
    -- confirmados (o caso normal desde a 0169/0174). `fn_fundir_entidade`
    -- já move documentos, checklist, pendências e reconciliações, resolve a
    -- pendência de ambiguidade da entidade fundida, e grava
    -- `entidade_fundida` com os dois nomes e quantos documentos mudaram de
    -- dono.
    perform fn_fundir_entidade(v_caso_id, p_entidade_id, v_outra_id, 'sistema:entidade');

    -- E o nome sobrevivente pode não ser o mais completo dos dois — quem
    -- decide são as MESMAS três guardas da 0171/0173 (só entre truncamentos,
    -- nunca cria homônima, recusa com rastro), com o nome da entidade que
    -- acabou de ser fundida (`v_nome_atual`, capturado ANTES da fusão —
    -- depois dela a linha não existe mais para ler).
    perform fn_entidade_talvez_renomear(v_caso_id, v_outra_id, v_nome_atual, v_cnpj);

    return v_outra_id;
  end if;

  update entidade set cnpj = v_cnpj where id = p_entidade_id;
  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
  values ('sistema:entidade', 'entidade_cnpj_aprendido', 'entidade:' || p_entidade_id,
          jsonb_build_object('cnpj', v_cnpj_atual),
          jsonb_build_object('cnpj', v_cnpj, 'como', 'aprendido de um documento posterior'));

  return p_entidade_id;
end;
$$;

--
-- Name: FUNCTION fn_entidade_aprender_cnpj(p_entidade_id uuid, p_cnpj text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_aprender_cnpj(p_entidade_id uuid, p_cnpj text) IS 'Grava o CNPJ numa entidade que ainda não tem um, com rastro (0169). Nunca sobrescreve: um CNPJ já gravado na MESMA entidade (mesmo que divergente) é decisão de humano. 0174: quando o CNPJ já pertence a OUTRA entidade do mesmo caso, funde as duas (fn_fundir_entidade) em vez de tentar gravar — sem isso o UPDATE violava entidade_caso_cnpj_unico e derrubava fn_registrar_diagnostico inteira. 0177: a fusão é recusada quando EXATAMENTE um dos dois lados é um balcão ambíguo (0162/0175) — em QUALQUER direção (a guarda da 0176 só olhava uma) — porque fundir apagaria uma entidade CONFIRMADA dentro de um balcão sem nome validado, ou apagaria o BALCÃO (com sua pendência de ambiguidade bloqueante) dentro de uma confirmada; a colisão vira pendência (fn_pendencia_cnpj_colide_balcao) e nada funde. Quando os DOIS são balcão (convergência 0175) ou os DOIS são confirmados, funde normalmente. Devolve o id da entidade que sobrou: SEMPRE use o retorno, nunca o id que foi passado — depois de uma fusão ele pode apontar para uma linha deletada.';

--
-- Name: fn_entidade_cadeia_controladora(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_cadeia_controladora(p_entidade_id uuid) RETURNS TABLE(entidade_id uuid, razao_social text, nivel integer)
    LANGUAGE sql STABLE
    AS $$
  with recursive cadeia(entidade_id, nivel) as (
    select e0.controladora_id, 1
      from entidade e0
     where e0.id = p_entidade_id
       and e0.controladora_id is not null
    union all
    select e1.controladora_id, c.nivel + 1
      from cadeia c
      join entidade e1 on e1.id = c.entidade_id
     where e1.controladora_id is not null
       and c.nivel < 50
  )
  select c.entidade_id, e2.razao_social, c.nivel
    from cadeia c
    join entidade e2 on e2.id = c.entidade_id
   order by c.nivel;
$$;

--
-- Name: FUNCTION fn_entidade_cadeia_controladora(p_entidade_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_cadeia_controladora(p_entidade_id uuid) IS '0181: sobe a cadeia de controle a partir de uma entidade (nível 1 = controladora direta, nível 2 = a controladora da controladora, …), parando no topo (controladora_id NULL) ou no limite de 50 níveis (mesmo limite de fn_entidade_criaria_ciclo_participacao). Consumidor mínimo — prova que a FK serve para algo além de existir (regra 7 do CLAUDE.md). O consumidor REAL (consolidação/intercompany) é F4, fora do escopo desta fatia — ver roadmap, fatia 1.5.';

--
-- Name: fn_entidade_canonica(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_canonica(p_nome text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
  select nullif(
    trim(regexp_replace(
      regexp_replace(
        -- sufixos societários, no FIM do nome (é onde eles aparecem). 'spe' e
        -- 'scp' NÃO entram: em "Vertentes Imóveis SPE" a sigla faz parte do nome
        -- da sociedade de propósito específico, e tirá-la funde SPEs diferentes.
        regexp_replace(fn_normalizar_texto(p_nome),
          '\s+(ltda|limitada|s\s*a|sa|s\s*/\s*a|eireli|me|epp|mei|em recuperacao judicial|em rj)\.?\s*$',
          '', 'g'),
        '[.,;:/\\()''"-]', ' ', 'g'),
      '\s+', ' ', 'g')),
    '');
$_$;

--
-- Name: FUNCTION fn_entidade_canonica(p_nome text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_canonica(p_nome text) IS 'Forma canônica de nome de entidade para CASAMENTO: sem acento, pontuação nem sufixo societário. Não substitui razao_social, que preserva a grafia da fonte.';

--
-- Name: fn_entidade_canonica_forte(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_canonica_forte(p_nome text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
  select nullif(trim(regexp_replace(
    trim(regexp_replace(
      regexp_replace(fn_normalizar_texto(p_nome), '[.,;:/\\()''"-]', ' ', 'g'),
      '\s+', ' ', 'g')),
    '\s(ltda|limitada|s a|sa|eireli|me|epp|mei|em recuperacao judicial|em rj)$', '', 'g')), '');
$_$;

--
-- Name: FUNCTION fn_entidade_canonica_forte(p_nome text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_canonica_forte(p_nome text) IS '0171: a forma canônica com a pontuação achatada ANTES do sufixo — sem isso "OMNIBEAUTY S.A." vira "omnibeauty s a" (dois tokens fantasma) e a decisão de renomear muda por causa da grafia do sufixo. Local a esta decisão: fn_entidade_canonica (0030) não é tocada.';

--
-- Name: fn_entidade_criaria_ciclo_participacao(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_criaria_ciclo_participacao(p_entidade_id uuid, p_nova_controladora_id uuid) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
declare
  v_atual  uuid := p_nova_controladora_id;
  v_saltos int  := 0;
begin
  while v_atual is not null and v_saltos < 50 loop
    if v_atual = p_entidade_id then
      return true;
    end if;
    select controladora_id into v_atual from entidade where id = v_atual;
    v_saltos := v_saltos + 1;
  end loop;
  return false;
end;
$$;

--
-- Name: FUNCTION fn_entidade_criaria_ciclo_participacao(p_entidade_id uuid, p_nova_controladora_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_criaria_ciclo_participacao(p_entidade_id uuid, p_nova_controladora_id uuid) IS '0181: sobe a cadeia de `controladora_id` a partir de `p_nova_controladora_id` e devolve true se `p_entidade_id` aparecer nela — nesse caso, torná-la controladora de `p_entidade_id` fecharia um ciclo. Limite de 50 saltos (mesmo limite do consumidor de leitura, item 4) evita loop infinito com dado sujo. Chamada por `fn_entidade_definir_participacao` ANTES de gravar — é a MEDIÇÃO NÃO-VAZIA desta migration (ver cabeçalho).';

--
-- Name: fn_entidade_definir_controlador(uuid, uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_definir_controlador(p_entidade_id uuid, p_controlador_id uuid, p_percentual numeric, p_autor text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_entidade       uuid;
  v_caso_controlador    uuid;
  v_percentual_anterior numeric;
  v_id                  uuid;
begin
  select caso_id into v_caso_entidade from entidade where id = p_entidade_id;
  if v_caso_entidade is null then
    raise exception 'entidade % não encontrada', p_entidade_id;
  end if;

  select caso_id into v_caso_controlador from controlador where id = p_controlador_id;
  if v_caso_controlador is null then
    raise exception 'controlador % não encontrado', p_controlador_id;
  end if;

  if v_caso_controlador <> v_caso_entidade then
    raise exception 'controlador % não pertence ao mesmo caso que a entidade %',
      p_controlador_id, p_entidade_id;
  end if;

  select percentual into v_percentual_anterior
    from entidade_controlador
   where entidade_id = p_entidade_id and controlador_id = p_controlador_id;

  insert into entidade_controlador (caso_id, entidade_id, controlador_id, percentual)
  values (v_caso_entidade, p_entidade_id, p_controlador_id, p_percentual)
  on conflict (entidade_id, controlador_id)
  do update set percentual = excluded.percentual, atualizado_em = now()
  returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'entidade_controlador_definido', 'entidade:' || p_entidade_id,
          jsonb_build_object('controlador_id', p_controlador_id,
                              'percentual_novo', p_percentual,
                              'percentual_anterior', v_percentual_anterior));

  return v_id;
end;
$$;

--
-- Name: FUNCTION fn_entidade_definir_controlador(p_entidade_id uuid, p_controlador_id uuid, p_percentual numeric, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_definir_controlador(p_entidade_id uuid, p_controlador_id uuid, p_percentual numeric, p_autor text) IS '0182: o ÚNICO caminho de escrita de `entidade_controlador` — chamado por um humano/analista (portal ou SQL direto; o portal não é escopo desta fatia). Valida que entidade e controlador existem e pertencem ao mesmo caso. Upsert por (entidade_id, controlador_id) — reatribuir o percentual é permitido, é o ESTADO ATUAL (histórico em evento_auditoria). A guarda de soma (fn_trg_entidade_controlador_soma_maxima) recusa a gravação se a soma dos percentuais conhecidos da entidade passasse de 100. Grava evento_auditoria (ator = p_autor, nunca ''sistema:...''). NADA é inferido de campo_extraido, nome ou CNPJ.';

--
-- Name: fn_entidade_definir_forma_de_controle(uuid, public.entidade_forma_de_controle, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_definir_forma_de_controle(p_entidade_id uuid, p_forma public.entidade_forma_de_controle, p_autor text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_forma_anterior entidade_forma_de_controle;
  v_caso_id        uuid;
begin
  select forma_de_controle, caso_id into v_forma_anterior, v_caso_id
    from entidade where id = p_entidade_id;

  if v_caso_id is null then
    raise exception 'entidade % não encontrada', p_entidade_id;
  end if;

  -- As guardas (entidade_forma_de_controle_coerente, trg_entidade_forma_de_controle_tem_vinculo)
  -- recusam este UPDATE se p_forma for incoerente com controladora_id ou entidade_controlador —
  -- esta função NÃO duplica a checagem, ela confia na constraint/trigger para recusar e propagar
  -- a exceção, exatamente como fn_entidade_definir_participacao (0181) confia em
  -- entidade_nao_controla_a_si_mesma para o ciclo de um salto.
  update entidade set forma_de_controle = p_forma where id = p_entidade_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'entidade_forma_de_controle_definida', 'entidade:' || p_entidade_id,
          jsonb_build_object('forma_nova', p_forma, 'forma_anterior', v_forma_anterior));

  -- Resolve a pendência complementar (item 5) quando a forma deixa de ser `indefinido` — mesmo
  -- desenho de fn_entidade_definir_papel_no_grupo (0179). Reatribuir de volta para `indefinido`
  -- (caso raro — desfazer uma decisão) NÃO reabre a pendência automaticamente: reabrir pendência
  -- por UPDATE é decisão de produto que nenhuma migration anterior tomou (0179/0180/0181/0182
  -- também não reabrem as delas), e não há nada medido hoje que peça isso.
  if p_forma <> 'indefinido' then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_autor
     where entidade_id = p_entidade_id
       and tipo = 'forma_de_controle_indefinida'
       and motivo = 'forma_de_controle_indefinida:' || p_entidade_id
       and estado <> 'resolvida';
  end if;

  return p_entidade_id;
end;
$$;

--
-- Name: FUNCTION fn_entidade_definir_forma_de_controle(p_entidade_id uuid, p_forma public.entidade_forma_de_controle, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_definir_forma_de_controle(p_entidade_id uuid, p_forma public.entidade_forma_de_controle, p_autor text) IS '0183: o ÚNICO caminho de escrita de entidade.forma_de_controle — chamado por um humano/analista (portal ou SQL direto; o portal não é escopo desta fatia). NÃO deriva a forma de controladora_id nem de entidade_controlador — a decisão vem de quem chama. As guardas (entidade_forma_de_controle_coerente, trg_entidade_forma_de_controle_tem_vinculo) recusam a gravação se for incoerente. Grava evento_auditoria (ator = p_autor, nunca ''sistema:...''), e resolve fn_pendencia_forma_de_controle_indefinida se estiver aberta, quando p_forma <> ''indefinido''. Reatribuir é permitido — é o estado ATUAL, o histórico mora em evento_auditoria.';

--
-- Name: fn_entidade_definir_papel_no_grupo(uuid, public.entidade_papel_no_grupo, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_definir_papel_no_grupo(p_entidade_id uuid, p_papel public.entidade_papel_no_grupo, p_autor text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_papel_anterior entidade_papel_no_grupo;
  v_caso_id        uuid;
begin
  select papel_no_grupo, caso_id into v_papel_anterior, v_caso_id
  from entidade where id = p_entidade_id;

  if v_caso_id is null then
    raise exception 'entidade % não encontrada', p_entidade_id;
  end if;

  update entidade set papel_no_grupo = p_papel where id = p_entidade_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'entidade_papel_no_grupo_definido', 'entidade:' || p_entidade_id,
          jsonb_build_object('papel_novo', p_papel, 'papel_anterior', v_papel_anterior));

  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_autor
   where entidade_id = p_entidade_id
     and tipo = 'papel_no_grupo_indefinido'
     and motivo = 'papel_no_grupo_indefinido:' || p_entidade_id
     and estado <> 'resolvida';

  return p_entidade_id;
end;
$$;

--
-- Name: FUNCTION fn_entidade_definir_papel_no_grupo(p_entidade_id uuid, p_papel public.entidade_papel_no_grupo, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_definir_papel_no_grupo(p_entidade_id uuid, p_papel public.entidade_papel_no_grupo, p_autor text) IS '0179: o ÚNICO caminho de escrita de entidade.papel_no_grupo — chamado por um humano/analista (portal ou SQL direto; o portal não é escopo da fatia 1.3). Grava evento_auditoria (ator = p_autor, nunca ''sistema:...''), e resolve fn_pendencia_papel_no_grupo_indefinido se estiver aberta para esta entidade. Reatribuir com papel diferente é permitido — é o estado ATUAL, o histórico mora em evento_auditoria.';

--
-- Name: fn_entidade_definir_participacao(uuid, uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_definir_participacao(p_entidade_id uuid, p_controladora_id uuid, p_percentual numeric, p_autor text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_entidade         uuid;
  v_caso_controladora     uuid;
  v_controladora_anterior uuid;
  v_percentual_anterior   numeric;
begin
  if p_controladora_id is null and p_percentual is not null then
    raise exception 'percentual (%) sem controladora não significa nada — informe p_percentual '
                     'null junto com p_controladora_id null', p_percentual;
  end if;

  select caso_id, controladora_id, percentual_participacao
    into v_caso_entidade, v_controladora_anterior, v_percentual_anterior
    from entidade where id = p_entidade_id;

  if v_caso_entidade is null then
    raise exception 'entidade % não encontrada', p_entidade_id;
  end if;

  if p_controladora_id is not null then
    select caso_id into v_caso_controladora from entidade where id = p_controladora_id;
    if v_caso_controladora is null then
      raise exception 'controladora % não encontrada', p_controladora_id;
    end if;
    if v_caso_controladora <> v_caso_entidade then
      raise exception 'controladora % não pertence ao mesmo caso que a entidade %',
        p_controladora_id, p_entidade_id;
    end if;

    -- A MEDIÇÃO NÃO-VAZIA desta migration (ver cabeçalho): sem esta chamada, um ciclo de 2 ou
    -- 3 níveis seria GRAVADO em vez de recusado, e um consumidor futuro que suba a cadeia
    -- (fn_entidade_cadeia_controladora ou qualquer código que a F4 escrever) entraria em loop
    -- até o limite de profundidade, escondendo o defeito em vez de o recusar na escrita.
    if fn_entidade_criaria_ciclo_participacao(p_entidade_id, p_controladora_id) then
      raise exception 'definir % como controladora de % criaria um CICLO de participação — % já '
                       'é controlada (direta ou indiretamente) por %',
        p_controladora_id, p_entidade_id, p_controladora_id, p_entidade_id;
    end if;
  end if;

  update entidade
     set controladora_id = p_controladora_id,
         percentual_participacao = p_percentual
   where id = p_entidade_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'entidade_participacao_definida', 'entidade:' || p_entidade_id,
          jsonb_build_object(
            'controladora_id_novo', p_controladora_id, 'controladora_id_anterior', v_controladora_anterior,
            'percentual_novo', p_percentual, 'percentual_anterior', v_percentual_anterior));

  return p_entidade_id;
end;
$$;

--
-- Name: FUNCTION fn_entidade_definir_participacao(p_entidade_id uuid, p_controladora_id uuid, p_percentual numeric, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_definir_participacao(p_entidade_id uuid, p_controladora_id uuid, p_percentual numeric, p_autor text) IS '0181: o ÚNICO caminho de escrita de `entidade.controladora_id`/`percentual_participacao` — chamado por um humano/analista (portal ou SQL direto; o portal não é escopo desta fatia). p_controladora_id NULL remove a controladora e EXIGE p_percentual NULL. Valida que as duas entidades existem e pertencem ao mesmo caso, e recusa (raise exception) se fn_entidade_criaria_ciclo_participacao disser que fecharia um ciclo. Grava evento_auditoria (ator = p_autor, nunca ''sistema:...''). Reatribuir é permitido — é o estado ATUAL, o histórico mora em evento_auditoria.';

--
-- Name: fn_entidade_e_balcao_ambiguo(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_e_balcao_ambiguo(p_caso_id uuid, p_entidade_id uuid) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  select exists (
    select 1 from pendencia
    where caso_id = p_caso_id
      and entidade_id = p_entidade_id
      and motivo = 'entidade_ambigua:' || p_entidade_id
      and estado <> 'resolvida'
  );
$$;

--
-- Name: FUNCTION fn_entidade_e_balcao_ambiguo(p_caso_id uuid, p_entidade_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_e_balcao_ambiguo(p_caso_id uuid, p_entidade_id uuid) IS 'Verdadeiro quando a entidade é o balcão de perguntas que a 0153 cria para um nome que casa com DUAS ou mais empresas do caso — reconhecido pela pendência `entidade_ambigua:<id>` ainda aberta. (0162) Existe porque o balcão casa com TODO MUNDO por construção (foi criado exatamente porque o nome dele casava com mais de uma empresa), e `fn_registrar_diagnostico` estava tratando esse casamento como confirmação.';

--
-- Name: fn_entidade_nome_mais_completo(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_nome_mais_completo(p_atual text, p_novo text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select case
    -- (1) cara de endereço colado nunca vence, mesmo mais longo.
    when fn_nome_parece_ter_endereco_colado(p_novo)
     and not fn_nome_parece_ter_endereco_colado(p_atual) then p_atual
    when fn_nome_parece_ter_endereco_colado(p_atual)
     and not fn_nome_parece_ter_endereco_colado(p_novo) then p_novo
    -- (2) sufixo societário vence quem não tem.
    when fn_nome_tem_sufixo_societario(p_novo)
     and not fn_nome_tem_sufixo_societario(p_atual) then p_novo
    when fn_nome_tem_sufixo_societario(p_atual)
     and not fn_nome_tem_sufixo_societario(p_novo) then p_atual
    -- (3) empatados nos dois sinais acima: comprimento cru desempata.
    when length(trim(p_novo)) > length(trim(p_atual)) then p_novo
    else p_atual
  end;
$$;

--
-- Name: FUNCTION fn_entidade_nome_mais_completo(p_atual text, p_novo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_nome_mais_completo(p_atual text, p_novo text) IS '0171: entre dois nomes que o CNPJ já provou serem a MESMA empresa, qual fica. Três sinais em ordem: cara de endereço colado (nunca vence, mesmo mais longo) > sufixo societário > comprimento cru. Sem isso, "SURUBIJU, 1930" (55 chars) venceria "MARCAS LTDA" (52) só por ser mais longo — e é o nome ERRADO.';

--
-- Name: fn_entidade_nome_parece_titulo_ou_arquivo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_nome_parece_titulo_ou_arquivo(p_nome text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select fn_entidade_canonica(p_nome) ~
    '^(comparativo|relatorio|controle|status|meses|liquido|empresas|vencidos)\y|\d{4}x\d{4}';
$$;

--
-- Name: FUNCTION fn_entidade_nome_parece_titulo_ou_arquivo(p_nome text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_nome_parece_titulo_ou_arquivo(p_nome text) IS '0178: nome com cara de título de coluna/planilha/arquivo em vez de razão social. Mesma normalização de fn_entidade_canonica (2690); o léxico é referência direta de Supabase/test/perimetro-inventario.mjs (PADRAO_TITULO_OU_ARQUIVO), medido contra os 16 nomes reais da causa nome_de_arquivo_ou_titulo_virou_entidade (fatia 1.1), mais "empresas"/"vencidos" — as 2 palavras que faltavam para cobrir as 4 entidades reais medidas no AMO teste 00 (seção 12.1 do roadmap). Léxico, não estatística: combinar com CNPJ nulo é o chamador, nunca esta função sozinha — ver o cabeçalho da 0178 para a armadilha do balcão ambíguo.';

--
-- Name: fn_entidade_talvez_renomear(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_talvez_renomear(p_caso_id uuid, p_entidade_id uuid, p_nome text, p_cnpj text) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
  v_id         uuid := p_entidade_id;
  v_cnpj       text := fn_cnpj_canonico(p_cnpj);
  v_nome_atual text;
  v_nome_novo  text;
  v_homonima   boolean;
begin
  if p_entidade_id is null or p_nome is null or length(trim(p_nome)) = 0 then return null; end if;
  select razao_social into v_nome_atual from entidade where id = p_entidade_id;
  if v_nome_atual is null then return null; end if;

  -- SEM CNPJ NÃO RENOMEIA. É o que mantém os caminhos de casamento APROXIMADO
  -- (0153/0168) intactos: lá o CNPJ não provou identidade nenhuma, e quem
  -- escolhe o nome continua sendo a 0168, entre os que JÁ EXISTIAM.
  if v_cnpj is null then return v_nome_atual; end if;

  -- 0171: O CNPJ TAMBÉM PODE RENOMEAR, não só fundir — com TRÊS guardas, e
  -- as três nasceram da revisão desta fatia, cada uma de um defeito medido.
  --
  -- O RENOMEIO FICA FORA DA GUARDA CANÔNICA ACIMA (defeito 1 medido): a
  -- canônica TIRA o sufixo societário, então "ALFA COMERCIO" e "ALFA
  -- COMERCIO LTDA" são canonicamente IGUAIS — e o renomeio, aninhado
  -- naquele `if`, nunca rodava justamente no caso em que o sinal 2 (sufixo)
  -- existe para decidir. Medido: o nome final ficava "ALFA COMERCIO".
  v_nome_novo := fn_entidade_nome_mais_completo(v_nome_atual, trim(p_nome));
  v_homonima := exists (
    select 1 from entidade e2
    where e2.caso_id = p_caso_id and e2.id <> v_id
      and fn_entidade_canonica_forte(e2.razao_social) = fn_entidade_canonica_forte(v_nome_novo));

  if v_nome_novo is distinct from v_nome_atual
     -- GUARDA 1 (defeito 2 medido): SÓ RENOMEIA ENTRE NOMES DA MESMA RAIZ.
     -- O CNPJ basta para FUNDIR (é a regra 1 da 0169, e o dono a aprovou),
     -- mas não basta para reescrever o nome: o cenário do rodapé com o CNPJ
     -- do ESCRITÓRIO DE CONTABILIDADE — descrito no cabeçalho desta própria
     -- função — fazia "PADARIA DO JOAO LTDA" virar "METALURGICA SAO PEDRO
     -- COMERCIO LTDA", medido. Antes da 0171 a fusão errada pelo menos
     -- PRESERVAVA o nome; o renomeio piorava o dano em vez de melhorá-lo.
     -- Quando os nomes não compartilham raiz, o `entidade_cnpj_casou` acima
     -- já registrou o casamento suspeito e é ELE que o humano lê.
     --
     -- `fn_pode_renomear_por_cnpj` e NÃO `fn_mesma_entidade` (que bloqueia o
     -- caso motivador) nem "prefixo comum" (que autorizava trocar PADARIA
     -- DO JOAO por PADARIA DO JOSE). Ver o cabeçalho da função para as
     -- quatro medições que derrubaram as duas versões anteriores.
     and fn_pode_renomear_por_cnpj(v_nome_atual, trim(p_nome))
     -- GUARDA 2 (defeito 3 medido): NÃO CRIA HOMÔNIMA. Sem isto, o renomeio
     -- deixava DUAS entidades do mesmo caso com a razão social idêntica, e
     -- o ramo (1) — casamento exato — passava a escolher uma delas por
     -- `order by razao_social limit 1`, empate puro entre strings iguais,
     -- SEM registrar ambiguidade nenhuma. Medido: 2 entidades homônimas, 0
     -- eventos. É o defeito silencioso clássico deste projeto — os
     -- documentos se dividem entre duas linhas que a tela mostra como uma.
     and not v_homonima
  then
    update entidade set razao_social = v_nome_novo where id = v_id;
    insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values ('sistema:entidade', 'entidade_renomeada_por_cnpj', 'entidade:' || v_id,
            jsonb_build_object('razao_social', v_nome_atual),
            jsonb_build_object('razao_social', v_nome_novo, 'cnpj', v_cnpj,
                               'porque', 'nome mais completo pela mesma empresa (CNPJ)'));

  elsif v_nome_novo is distinct from v_nome_atual then
    -- RECUSA COM RASTRO, e não em silêncio. Chegar aqui significa que o
    -- nome que veio ERA mais completo e mesmo assim não foi adotado — ou
    -- porque não é variante do gravado (CNPJ suspeito), ou porque adotá-lo
    -- criaria uma homônima (duas entidades que provavelmente deveriam ser
    -- UMA). As duas coisas são informação para quem revisa; nenhuma delas
    -- pode ser decidida por esta função, que não conhece documento.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_renomeio_recusado', 'entidade:' || v_id,
            jsonb_build_object('caso_id', p_caso_id, 'razao_social_mantida', v_nome_atual,
                               'razao_social_recusada', v_nome_novo, 'cnpj', v_cnpj,
                               'pode_renomear', fn_pode_renomear_por_cnpj(v_nome_atual, trim(p_nome)),
                               -- UM snapshot só, calculado antes do `if`: com dois
                               -- `exists` separados (READ COMMITTED, nó Postgres por
                               -- item) uma entidade inserida entre eles fazia o evento
                               -- culpar a guarda errada.
                               'homonima_existiria', v_homonima));
  end if;

  return coalesce(v_nome_novo, v_nome_atual);
end;
$$;

--
-- Name: FUNCTION fn_entidade_talvez_renomear(p_caso_id uuid, p_entidade_id uuid, p_nome text, p_cnpj text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_talvez_renomear(p_caso_id uuid, p_entidade_id uuid, p_nome text, p_cnpj text) IS '0173: o renomeio por CNPJ da 0171, extraído para ser chamado pelos DOIS caminhos — a classificação (fn_upsert_entidade) e o diagnóstico (fn_registrar_diagnostico, o único que roda para todo documento). As três guardas da 0171 vão inteiras: só entre truncamentos, nunca cria homônima, recusa com rastro. Sem CNPJ não renomeia — ali quem decide continua sendo a 0168.';

--
-- Name: fn_entidades_candidatas(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidades_candidatas(p_caso_id uuid, p_nome text) RETURNS TABLE(entidade_id uuid, razao_social text, exata boolean)
    LANGUAGE sql STABLE
    AS $$
  select e.id, e.razao_social,
         fn_entidade_canonica(e.razao_social) = fn_entidade_canonica(p_nome)
  from entidade e
  where e.caso_id = p_caso_id
    and p_nome is not null
    and length(trim(p_nome)) > 0
    and fn_mesma_entidade(e.razao_social, p_nome)
  order by (fn_entidade_canonica(e.razao_social) = fn_entidade_canonica(p_nome)) desc,
           e.razao_social;
$$;

--
-- Name: FUNCTION fn_entidades_candidatas(p_caso_id uuid, p_nome text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidades_candidatas(p_caso_id uuid, p_nome text) IS 'As entidades do caso com que um nome casa, a exata primeiro (0153). Mais de uma linha sem nenhuma exata é AMBIGUIDADE: o nome não identifica empresa nenhuma, e quem decide é o humano.';

--
-- Name: fn_entidades_candidatas_cnpj(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidades_candidatas_cnpj(p_caso_id uuid, p_nome text, p_cnpj text) RETURNS TABLE(entidade_id uuid, razao_social text, exata boolean)
    LANGUAGE sql STABLE
    AS $$
  select c.entidade_id, c.razao_social, c.exata
  from fn_entidades_candidatas(p_caso_id, p_nome) c
  join entidade e on e.id = c.entidade_id
  where fn_cnpj_canonico(p_cnpj) is null
     or fn_cnpj_canonico(e.cnpj) is null
     or fn_cnpj_canonico(e.cnpj) = fn_cnpj_canonico(p_cnpj)
  order by c.exata desc, c.razao_social;
$$;

--
-- Name: FUNCTION fn_entidades_candidatas_cnpj(p_caso_id uuid, p_nome text, p_cnpj text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidades_candidatas_cnpj(p_caso_id uuid, p_nome text, p_cnpj text) IS 'As candidatas da 0153 menos as que o CNPJ desmente (0169). CNPJ nulo devolve a lista inteira: ausência não desqualifica ninguém. CNPJ conhecido e diferente sai — o nome não tem autoridade para contradizer o registro fiscal.';

--
-- Name: fn_entidades_sao_um_grupo(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidades_sao_um_grupo(p_nomes text[]) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select coalesce(array_length(p_nomes, 1), 0) > 0
     and not exists (
       select 1
       from unnest(p_nomes) with ordinality as a(nome, i)
       join unnest(p_nomes) with ordinality as b(nome, j) on j > i
       where not fn_mesma_entidade(a.nome, b.nome)
     );
$$;

--
-- Name: FUNCTION fn_entidades_sao_um_grupo(p_nomes text[]); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidades_sao_um_grupo(p_nomes text[]) IS 'Os nomes são todos a MESMA empresa? Exige que cada PAR case por fn_mesma_entidade — não é fecho transitivo de propósito: A~B e B~C sem A~C é o apelido curto que casa com duas empresas distintas (o "Araucaria SPE" da 0153), e ali não se escolhe.';

--
-- Name: fn_excluir_caso(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_excluir_caso(p_caso_id uuid, p_autor text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_nome  text;
  v_docs  int;
  v_campos int;
  v_pend  int;
begin
  select nome into v_nome from caso where id = p_caso_id;
  if v_nome is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Este mandato não existe mais — talvez alguém já o tenha excluído.');
  end if;

  select count(*) into v_docs from documento where caso_id = p_caso_id;
  select count(*) into v_campos from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
   where d.caso_id = p_caso_id;
  select count(*) into v_pend from pendencia where caso_id = p_caso_id;

  -- A trilha ANTES do delete: se o delete falhar, sobra um registro de tentativa,
  -- que é informação; se registrássemos depois, uma falha no meio deixaria o
  -- caso apagado e nenhum rastro.
  insert into evento_auditoria (ator, acao, entidade_ref, antes)
    values (p_autor, 'caso_excluido', 'caso:'||p_caso_id,
            jsonb_build_object('nome', v_nome, 'documentos', v_docs,
                               'campos_extraidos', v_campos, 'pendencias', v_pend));

  delete from caso where id = p_caso_id;

  return jsonb_build_object('excluido', true, 'nome', v_nome,
                            'documentos', v_docs, 'campos_extraidos', v_campos,
                            'pendencias', v_pend);
end;
$$;

--
-- Name: FUNCTION fn_excluir_caso(p_caso_id uuid, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_excluir_caso(p_caso_id uuid, p_autor text) IS 'Exclui o mandato e tudo que depende dele (cascade da 0001), devolvendo a contagem do que se perdeu. Grava a exclusão em evento_auditoria ANTES do delete — a trilha não tem FK para caso, então o rastro sobrevive ao caso.';

--
-- Name: fn_exercicio_da_coluna(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_exercicio_da_coluna(p_coluna text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
  select (m[1])::int
  from regexp_match(coalesce(p_coluna, ''), '(19[5-9][0-9]|20[0-9]{2}|21[0-9]{2})') m
  where m[1] is not null
$$;

--
-- Name: FUNCTION fn_exercicio_da_coluna(p_coluna text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_exercicio_da_coluna(p_coluna text) IS 'O exercício que o cabeçalho da coluna nomeia, ou NULL quando ele não nomeia exercício nenhum ("Saldo", "Crédito", "Ticket médio"). Ausência é ausência: coluna sem ano fica FORA da série histórica em vez de virar um ano inventado.';

--
-- Name: fn_exigencias_do_caso(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_exigencias_do_caso(p_caso_id uuid) RETURNS TABLE(exigencia_id uuid, tipo_taxonomia text, conceito text, rotulo text, origem text, depende_de text[], severidade text, sobrepujavel boolean, descricao text, entidade text, entidade_id uuid, satisfeita boolean, alternativa_rotulo text, alternativa_recado text)
    LANGUAGE sql STABLE
    AS $$
  -- UMA CHAMADA POR TIPO, E NÃO POR DOCUMENTO — e o `materialized` é a metade
  -- que faz a diferença existir. A forma herdada da 0113 rodava
  -- `fn_linhas_do_tipo` uma vez por DOCUMENTO (662 ms de 914 num caso de 400
  -- documentos), e separar em duas CTEs simples não mudou nada, porque o
  -- Postgres achata CTE e empurra o filtro de volta para baixo do agrupamento.
  -- É a palavra `materialized` que impede isso; sem ela este comentário estaria
  -- descrevendo uma otimização que não acontece.
  with tipos_do_caso as materialized (
    select distinct d.tipo_taxonomia from documento d where d.caso_id = p_caso_id
    union
    -- Revisão da 0157 (achado C): quando NENHUM documento está rotulado
    -- COMBINADO mas algum SERVE como COMBINADO por estrutura
    -- (fn_documento_serve_como), o tipo precisa entrar aqui do mesmo jeito —
    -- senão as exigências de linha do COMBINADO nunca aparecem no resultado
    -- desta função: nem satisfeitas, nem ausentes, silêncio puro.
    select 'COMBINADO'
     where exists (
       select 1 from documento d
       where d.caso_id = p_caso_id and fn_documento_serve_como(d.id, 'COMBINADO')
     )
  ),
  -- Revisão da 0157 (achado C): "tem conteúdo" pergunta pelo tipo SERVIDO
  -- (fn_documento_serve_como), com fn_linhas_do_tipo mantida como a resposta
  -- para todo tipo que não seja COMBINADO — é a única exceção que
  -- fn_documento_serve_como conhece, então nenhum outro tipo muda de
  -- comportamento aqui. Para COMBINADO, soma-se um segundo caminho: qualquer
  -- documento que SIRVA como COMBINADO e tenha rendido alguma linha.
  tipos_com_conteudo as (
    select t.tipo_taxonomia from tipos_do_caso t
    where fn_linhas_do_tipo(p_caso_id, t.tipo_taxonomia) > 0
       or (
         t.tipo_taxonomia = 'COMBINADO'
         and exists (
           select 1
           from documento d
           join documento_versao dv on dv.documento_id = d.id and dv.id = fn_versao_com_extracao(d.id)
           join campo_extraido ce on ce.documento_versao_id = dv.id
           where d.caso_id = p_caso_id
             and fn_documento_serve_como(d.id, 'COMBINADO')
         )
       )
  ),
  -- A VERSÃO VIGENTE DE CADA DOCUMENTO, resolvida UMA vez (lição de custo da
  -- 0101), e — 0146 — QUANTAS COLUNAS DE ENTIDADE o documento declara.
  --
  -- É esse número que decide se a capa do documento pode responder pela linha
  -- que não tem coluna. Uma coluna (ou nenhuma): o documento é de uma empresa e
  -- a capa é a única fonte. Mais de uma: o documento já disse de quem é cada
  -- número, e a capa não responde por ninguém.
  docs as (
    select d.id, d.tipo_taxonomia, ent.razao_social as ent_doc,
           v.versao,
           (select count(distinct ce.entidade_coluna) from campo_extraido ce
             where ce.documento_versao_id = v.versao and ce.valor_num is not null) > 1
             as multi_entidade,
           -- Revisão da 0157 (achado C): este documento SERVE como COMBINADO —
           -- pelo rótulo ou pela estrutura (fn_documento_serve_como, que já
           -- filtra fonte permitida e exige conteúdo — achados B e A).
           -- Calculado uma vez por documento, não por linha extraída.
           fn_documento_serve_como(d.id, 'COMBINADO') as serve_combinado
    from documento d
    left join entidade ent on ent.id = d.entidade_id
    cross join lateral (select fn_versao_com_extracao(d.id) as versao) v
    where d.caso_id = p_caso_id
  ),
  campos as (
    select dc.tipo_taxonomia,
           ce.chave, ce.secao, ce.secao_canonica,
           -- 0145: o outro eixo da matriz.
           ce.periodo_coluna as coluna,
           -- 0146: a capa só responde pela linha sem coluna quando o documento é
           -- de UMA empresa. Num documento de várias, a linha sem coluna fica sem
           -- entidade — ela vale para o caso, não para a capa.
           case when dc.multi_entidade then ce.entidade_coluna
                else coalesce(ce.entidade_coluna, dc.ent_doc) end as ent_txt
    from docs dc
    join campo_extraido ce on ce.documento_versao_id = dc.versao
    where ce.valor_num is not null

    union all

    -- Revisão da 0157 (achado C): um documento rotulado diferente (ex.:
    -- BALANCO) que SERVE como COMBINADO por estrutura entra AQUI TAMBÉM, sob
    -- o tipo COMBINADO — ADITIVO, não substitui: ele continua contando para
    -- o seu próprio tipo rotulado no ramo acima. Sem este ramo, as linhas
    -- dele nunca casam contra `taxonomia_linha_exigida` de COMBINADO, e as
    -- 3 exigências (ativo_total, caixa_e_equivalentes, passivo_mais_pl) ficam
    -- mudas em vez de avaliadas — medido lado a lado contra o mesmo dado
    -- rotulado COMBINADO, que abre a pendência normalmente.
    select 'COMBINADO' as tipo_taxonomia,
           ce.chave, ce.secao, ce.secao_canonica,
           ce.periodo_coluna as coluna,
           case when dc.multi_entidade then ce.entidade_coluna
                else coalesce(ce.entidade_coluna, dc.ent_doc) end as ent_txt
    from docs dc
    join campo_extraido ce on ce.documento_versao_id = dc.versao
    where ce.valor_num is not null
      and dc.tipo_taxonomia <> 'COMBINADO'
      and dc.serve_combinado
  ),
  -- O NOME vira ENTIDADE REGISTRADA uma vez por nome DISTINTO (lição da 0101:
  -- fn_mesma_entidade custa; pagar por ocorrência seria pagar 770 vezes por
  -- ~10 respostas). Nome que não casa com registro nenhum fica NULL.
  nomes_resolvidos as (
    select n.ent_txt,
           (select e.id from entidade e
             where e.caso_id = p_caso_id
               and fn_mesma_entidade(n.ent_txt, e.razao_social)
             order by e.razao_social, e.id limit 1) as entidade_id
    from (select distinct c.ent_txt from campos c where c.ent_txt is not null) n
  ),
  campos_ent as (
    select c.*, nr.entidade_id
    from campos c
    left join nomes_resolvidos nr on nr.ent_txt = c.ent_txt
  ),
  -- O CASAMENTO exigência × rótulo é avaliado uma vez por LINHA DISTINTA
  -- (mesma lição): fn_normalizar_texto por (rótulo × termo) é o custo.
  linhas_distintas as (
    select distinct c.tipo_taxonomia, c.chave, c.secao, c.secao_canonica, c.coluna
    from campos c
  ),
  casadas as (
    select e.id as exigencia_id, ld.tipo_taxonomia, ld.chave, ld.secao,
           ld.secao_canonica, ld.coluna
    from taxonomia_linha_exigida e
    join linhas_distintas ld on ld.tipo_taxonomia = e.tipo_taxonomia
    where e.ativo
      and case e.checagem
        when 'secao_presente' then ld.secao_canonica = e.secao_canonica
        when 'serie_mensal'   then fn_mes_do_rotulo(ld.chave) is not null
        else exists (
          select 1 from taxonomia_linha_localizador l
          -- O ALVO do casamento, escolhido pelo modo (0145).
          cross join lateral (select fn_normalizar_texto(
            case l.contra
              when 'secao'  then coalesce(ld.secao, '')
              when 'coluna' then coalesce(ld.coluna, '')
              else ld.chave
            end) as alvo) a
          where l.exigencia_id = e.id
            and case
              when l.contra = 'estrutural' then fn_rotulo_estrutural(ld.chave, l.termos_inclui)
              else
                not exists (
                  select 1 from unnest(l.termos_inclui) t
                  where a.alvo not like '%' || fn_normalizar_texto(t) || '%')
                and not exists (
                  select 1 from unnest(l.termos_exclui) t
                  where a.alvo like '%' || fn_normalizar_texto(t) || '%')
            end)
      end
  ),
  -- Quais (exigência, entidade) estão SATISFEITAS: a linha casada volta às
  -- ocorrências para saber DE QUEM ela é.
  satisfazedores as (
    select distinct ca.exigencia_id, c.entidade_id
    from casadas ca
    join campos_ent c
      on c.tipo_taxonomia = ca.tipo_taxonomia
     and c.chave = ca.chave
     and c.secao is not distinct from ca.secao
     and c.secao_canonica is not distinct from ca.secao_canonica
     and c.coluna is not distinct from ca.coluna
  ),
  -- 0188: AS ALTERNATIVAS — o que o documento traz NO LUGAR da linha exigida.
  -- Mesmo casamento (substring do texto normalizado, alvo pelo modo) e a MESMA
  -- volta às ocorrências para saber de quem é: uma atribuição de entidade só,
  -- a desta função (ver o cabeçalho da 0188). Só as exigências que TÊM
  -- alternativa entram no join, então o custo fica restrito a elas.
  alternativas_casadas as (
    select a.exigencia_id, a.ordem, a.recado, ld.tipo_taxonomia, ld.chave, ld.secao,
           ld.secao_canonica, ld.coluna
    from taxonomia_linha_alternativa a
    join taxonomia_linha_exigida e on e.id = a.exigencia_id and e.ativo
    join linhas_distintas ld on ld.tipo_taxonomia = e.tipo_taxonomia
    cross join lateral (select fn_normalizar_texto(
      case a.contra
        when 'secao'  then coalesce(ld.secao, '')
        when 'coluna' then coalesce(ld.coluna, '')
        else ld.chave
      end) as alvo) x
    where not exists (
            select 1 from unnest(a.termos_inclui) t
            where x.alvo not like '%' || fn_normalizar_texto(t) || '%')
      and not exists (
            select 1 from unnest(a.termos_exclui) t
            where x.alvo like '%' || fn_normalizar_texto(t) || '%')
  ),
  alternativas_por_entidade as (
    select distinct ac.exigencia_id, c.entidade_id, ac.ordem, ac.chave, ac.recado
    from alternativas_casadas ac
    join campos_ent c
      on c.tipo_taxonomia = ac.tipo_taxonomia
     and c.chave = ac.chave
     and c.secao is not distinct from ac.secao
     and c.secao_canonica is not distinct from ac.secao_canonica
     and c.coluna is not distinct from ac.coluna
  ),
  -- O EIXO: entidades registradas que TROUXERAM linha do tipo. Quem tem
  -- documento mas nenhuma linha atribuível não entra — cobrar conteúdo de quem
  -- não tem conteúdo é assunto da 0036/0112, não daqui. E, desde a 0146, "linha
  -- atribuível" quer dizer atribuída PELO DOCUMENTO quando ele sabe atribuir.
  eixo as (
    select distinct c.tipo_taxonomia, c.entidade_id
    from campos_ent c
    where c.entidade_id is not null
  )
  select e.id, e.tipo_taxonomia, e.conceito, e.rotulo, e.origem, e.depende_de,
         e.severidade, e.sobrepujavel, e.descricao,
         ent.razao_social, ax.entidade_id,
         s.satisfeita,
         alt.chave, alt.recado
  from taxonomia_linha_exigida e
  join tipos_com_conteudo t on t.tipo_taxonomia = e.tipo_taxonomia
  join taxonomia_tipo_documento tx on tx.codigo = e.tipo_taxonomia
  cross join lateral (
    -- Escopo entidade COM eixo: uma linha por entidade. Senão: a linha única
    -- com entidade NULL (escopo caso, ou fallback nº 2 do cabeçalho da 0119).
    select x.entidade_id
    from eixo x
    where x.tipo_taxonomia = e.tipo_taxonomia
      and coalesce(e.escopo_entidade, tx.granularidade::text in ('entidade', 'entidade_periodo'))
    union all
    select null::uuid
    where not (coalesce(e.escopo_entidade, tx.granularidade::text in ('entidade', 'entidade_periodo'))
               and exists (select 1 from eixo x2 where x2.tipo_taxonomia = e.tipo_taxonomia))
  ) ax
  cross join lateral (
    select case when ax.entidade_id is null
                then exists (select 1 from satisfazedores s where s.exigencia_id = e.id)
                else exists (select 1 from satisfazedores s
                              where s.exigencia_id = e.id and s.entidade_id = ax.entidade_id)
           end as satisfeita
  ) s
  -- 0188: a alternativa só é procurada para o que NÃO está satisfeito — ela
  -- nunca satisfaz, só muda o que a pendência diz.
  left join lateral (
    select ap.chave, ap.recado
    from alternativas_por_entidade ap
    where not s.satisfeita
      and ap.exigencia_id = e.id
      and (ax.entidade_id is null or ap.entidade_id = ax.entidade_id)
    order by ap.ordem, ap.chave
    limit 1
  ) alt on true
  left join entidade ent on ent.id = ax.entidade_id
  where e.ativo;
$$;

--
-- Name: FUNCTION fn_exigencias_do_caso(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_exigencias_do_caso(p_caso_id uuid) IS 'Exigências de linha aplicáveis ao caso (tipos presentes COM conteúdo), com satisfeita s/n. Casa contra a versão VIGENTE (0102), pela chave, pela seção, pela COLUNA (0145) ou pelo rótulo estrutural. Num documento que declara VÁRIAS colunas de entidade, a linha sem coluna não é atribuída à capa (0146). Desde a revisão da 0157 (achado C), um documento que SERVE como COMBINADO por estrutura (rotulado BALANCO/DRE/FLUXO_CAIXA, fn_documento_serve_como) tem suas linhas avaliadas TAMBÉM sob COMBINADO, além do seu próprio tipo rotulado — sem isso as 3 exigências do item (ativo_total, caixa_e_equivalentes, passivo_mais_pl) ficavam mudas assim que o passo 1 de fn_recomputar_completude parou de exigir o rótulo exato. 0188: quando a exigência NÃO está satisfeita e uma linha de taxonomia_linha_alternativa casa para a mesma entidade, alternativa_rotulo diz qual linha o documento traz no lugar e alternativa_recado o que a pendência deve dizer (a alternativa nunca satisfaz). Alimenta o passo 2b de fn_recomputar_completude e a tela do caso.';

--
-- Name: fn_falhas_abertas(text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_falhas_abertas(p_caso_nome text, p_desde timestamp with time zone) RETURNS TABLE(id uuid, etapa text, mensagem text, criado_em timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
  select f.id, f.etapa, f.mensagem, f.criado_em
  from execucao_falha f
  where f.visto_em is null
    and f.criado_em >= p_desde
    and (lower(f.caso_nome) = lower(trim(p_caso_nome))
         or f.caso_id in (select c.id from caso c where lower(c.nome) = lower(trim(p_caso_nome))))
  order by f.criado_em desc;
$$;

--
-- Name: fn_familia_da_secao(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_familia_da_secao(p_secao text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
  select case when p_secao ~ '^(ativo|passivo)(_|$)' or p_secao = 'patrimonio_liquido'
                   then 'patrimonial'
              when p_secao in ('receita_bruta', 'custos', 'despesas_operacionais',
                               'resultado_financeiro', 'impostos_lucro')
                   then 'resultado'
              when p_secao ~ '^atividades_' then 'fluxo'
              else coalesce(p_secao, '')   -- NULL, dmpl, dva, NAO_CLASSIFICAVEL: família própria
         end
$_$;

--
-- Name: FUNCTION fn_familia_da_secao(p_secao text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_familia_da_secao(p_secao text) IS 'Família da demonstração pela seção canônica: patrimonial, resultado, fluxo ou a própria seção (0200). Conta única (0201).';

--
-- Name: fn_fator_escala(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_fator_escala(p_unidade text) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $_$
  select case
    when p_unidade is null or length(trim(p_unidade)) = 0 then null
    when fn_normalizar_texto(p_unidade) in ('unidade', 'unidades', 'reais', 'real', 'r$', 'brl') then 1
    when fn_normalizar_texto(p_unidade) in ('milhar', 'milhares', 'mil', 'r$ mil') then 1000
    when fn_normalizar_texto(p_unidade) in ('milhao', 'milhoes', 'milhao de reais') then 1000000
    else null
  end;
$_$;

--
-- Name: FUNCTION fn_fator_escala(p_unidade text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_fator_escala(p_unidade text) IS 'Fator multiplicativo para levar um valor à base (unidade). null quando a escala é ausente ou desconhecida.';

--
-- Name: fn_fatos_do_caso(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_fatos_do_caso(p_caso_id uuid) RETURNS TABLE(fato_id uuid, documento_id uuid, documento_versao_id uuid, nome_documento text, tipo_taxonomia text, tipo text, rotulo text, severidade text, porque text, trecho text, pagina integer, leitura text)
    LANGUAGE sql STABLE
    AS $$
  -- 0149 (4): a versão que VALE é a mais nova que foi AVALIADA — não a mais
  -- nova, e não a que tem linha extraída.
  --
  -- Não a mais nova: um reenvio ainda não processado apagava da tela os fatos
  -- da versão anterior (medido: zero fatos com um covenant gravado).
  -- Não `fn_versao_com_extracao`: ela exige linha em `campo_extraido`, e os
  -- documentos que mais têm fatos — notas explicativas, parecer de auditoria —
  -- extraem ZERO linha por natureza.
  with corrente as (
    select distinct on (dv.documento_id)
           dv.id, dv.documento_id, dv.arquivo_ref, dv.nome_original
      from documento_versao dv
      join documento d on d.id = dv.documento_id
     where d.caso_id = p_caso_id
       and dv.fatos_avaliados_em is not null
     order by dv.documento_id, dv.n_versao desc
  )
  select f.id, c.documento_id, f.documento_versao_id,
         coalesce(c.nome_original, c.arquivo_ref),
         d.tipo_taxonomia,
         f.tipo, cat.rotulo, cat.severidade, cat.porque,
         f.trecho, f.pagina, f.leitura
    from documento_fato f
    join corrente c            on c.id = f.documento_versao_id
    join documento d           on d.id = c.documento_id
    join fato_tipo_catalogo cat on cat.tipo = f.tipo
   -- 0149 (5): `f.id` desempata. Fatos gravados no mesmo insert compartilham um
   -- único `criado_em`, e sem o desempate a MESMA lista podia sair em ordens
   -- diferentes entre duas leituras — numa tela em que a ordem significa
   -- gravidade.
   order by cat.ordem, cat.rotulo, f.criado_em, f.id;
$$;

--
-- Name: FUNCTION fn_fatos_do_caso(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_fatos_do_caso(p_caso_id uuid) IS 'Os fatos materiais do mandato, da versão mais nova que foi AVALIADA (0149), ordenados por gravidade com desempate estável. Versão não avaliada não apaga o que a anterior achou — era o que fazia os alertas sumirem durante um reenvio de arquivo.';

--
-- Name: fn_fechar_caso(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_fechar_caso(p_caso_id uuid, p_autor text, p_motivo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_nome text;
  v_ja   timestamptz;
begin
  select nome, fechado_em into v_nome, v_ja from caso where id = p_caso_id;
  if v_nome is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Este mandato não existe mais — talvez alguém já o tenha excluído.');
  end if;
  -- Idempotente: fechar duas vezes não reescreve quem fechou nem quando. Dois
  -- cliques no mesmo botão não podem trocar a autoria do primeiro.
  if v_ja is not null then
    return jsonb_build_object('fechado', true, 'nome', v_nome, 'fechado_em', v_ja, 'ja_estava', true);
  end if;

  update caso
     set fechado_em = now(), fechado_por = p_autor, motivo_fechamento = nullif(btrim(p_motivo), '')
   where id = p_caso_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values (p_autor, 'caso_fechado', 'caso:'||p_caso_id,
            jsonb_build_object('nome', v_nome, 'motivo', nullif(btrim(p_motivo), '')));

  return jsonb_build_object('fechado', true, 'nome', v_nome, 'fechado_em', now());
end;
$$;

--
-- Name: FUNCTION fn_fechar_caso(p_caso_id uuid, p_autor text, p_motivo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_fechar_caso(p_caso_id uuid, p_autor text, p_motivo text) IS 'Tira o mandato da mesa sem apagar nada. Idempotente: fechar de novo devolve o fechamento original em vez de reescrever autoria. Reversível por fn_reabrir_caso.';

--
-- Name: fn_fundir_entidade(uuid, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_fundir_entidade(p_caso_id uuid, p_de_id uuid, p_para_id uuid, p_por text DEFAULT 'sistema:fusao'::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_de    text;
  v_para  text;
  v_docs  int;
  -- 0183
  v_forma_de         entidade_forma_de_controle;
  v_vinculos_de      jsonb;
  v_vinculos_movidos int := 0;
  v_descartados      jsonb := '[]'::jsonb;
begin
  if p_de_id = p_para_id then
    raise exception 'fundir uma entidade nela mesma não faz sentido (%)', p_de_id;
  end if;

  select razao_social into v_de   from entidade where id = p_de_id   and caso_id = p_caso_id;
  select razao_social into v_para from entidade where id = p_para_id and caso_id = p_caso_id;
  if v_de is null or v_para is null then
    raise exception 'entidade não encontrada neste mandato (de=%, para=%)', p_de_id, p_para_id;
  end if;

  update documento set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  get diagnostics v_docs = row_count;

  -- Tudo o que aponta para a entidade acompanha o documento. `checklist_item_status`
  -- e `pendencia` guardam entidade_id por conta própria, e deixá-los para trás
  -- faria o Portão 1 continuar cobrando de uma empresa que não existe mais.
  update checklist_item_status set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  update pendencia set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;
  update reconciliacao set entidade_id = p_para_id
   where caso_id = p_caso_id and entidade_id = p_de_id;

  -- 0183: o controle declarado de A. Sem isto, o `on delete cascade` de entidade_controlador o
  -- apagava junto com a linha (ver o item (10) da migration 0183).
  select forma_de_controle into v_forma_de from entidade where id = p_de_id;
  select coalesce(jsonb_agg(jsonb_build_object('controlador_id', ec.controlador_id,
                                               'controlador', k.nome,
                                               'percentual', ec.percentual)
                            order by k.nome), '[]'::jsonb)
    into v_vinculos_de
    from entidade_controlador ec join controlador k on k.id = ec.controlador_id
   where ec.entidade_id = p_de_id;

  if not exists (select 1 from entidade_controlador where entidade_id = p_para_id) then
    update entidade_controlador set entidade_id = p_para_id where entidade_id = p_de_id;
    get diagnostics v_vinculos_movidos = row_count;
  else
    v_descartados := v_vinculos_de;
  end if;

  -- A pendência de ambiguidade da entidade fundida está respondida.
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_por
   where caso_id = p_caso_id and motivo = 'entidade_ambigua:' || p_de_id and estado <> 'resolvida';

  -- 0183: e as de forma e de papel de A também — a pergunta era sobre uma entidade que deixa de
  -- existir; a de B é de B.
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_por
   where caso_id = p_caso_id
     and motivo in ('forma_de_controle_indefinida:' || p_de_id, 'papel_no_grupo_indefinido:' || p_de_id)
     and estado <> 'resolvida';

  delete from entidade where id = p_de_id and caso_id = p_caso_id;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
  values (p_por, 'entidade_fundida', 'entidade:' || p_para_id,
          jsonb_build_object('entidade_id', p_de_id, 'razao_social', v_de,
                             -- 0183
                             'forma_de_controle', v_forma_de, 'vinculos', v_vinculos_de),
          jsonb_build_object('entidade_id', p_para_id, 'razao_social', v_para,
                             'documentos_movidos', v_docs,
                             -- 0183
                             'vinculos_movidos', v_vinculos_movidos,
                             'vinculos_descartados', v_descartados));

  return jsonb_build_object('fundida', v_de, 'em', v_para, 'documentos', v_docs,
                            'vinculos_movidos', v_vinculos_movidos,
                            'vinculos_descartados', jsonb_array_length(v_descartados));
end;
$$;

--
-- Name: FUNCTION fn_fundir_entidade(p_caso_id uuid, p_de_id uuid, p_para_id uuid, p_por text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_fundir_entidade(p_caso_id uuid, p_de_id uuid, p_para_id uuid, p_por text) IS 'Funde duas entidades que são a mesma empresa, levando junto documentos, checklist, pendências e reconciliações (0153). Nada some sem rastro: evento_auditoria guarda o nome que existia e quantos documentos mudaram de dono. 0183: leva também os vínculos de entidade_controlador quando a sobrevivente não tem nenhum (antes, o on delete cascade os apagava); se ela já tem, os da absorvida não são somados e vão para o evento como vinculos_descartados. Não herda forma_de_controle (registra no evento) e resolve as pendências de forma e de papel da absorvida.';

--
-- Name: fn_golden_abrir_rodada(text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_abrir_rodada(p_nome text, p_autor text, p_nota text DEFAULT NULL::text, p_taxonomia_versao integer DEFAULT NULL::integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_nome   text := nullif(trim(coalesce(p_nome, '')), '');
  v_autor  text := nullif(trim(coalesce(p_autor, '')), '');
  v_versao int;
  v_id     uuid;
begin
  if v_nome is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Rodada sem nome. O nome é a referência que uma decisão de dial cita '
                       '("subiu com base na rodada X"), e "a rodada de agosto" não é referência.');
  end if;

  if v_autor is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Rodada sem autor. Quem abriu a rodada é parte da evidência: o golden set '
                       'autoriza subir autonomia, e evidência sem procedência não autoriza nada.');
  end if;

  if exists (select 1 from golden_rodada r where r.nome = v_nome) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Já existe uma rodada chamada "%s". O Arquitetura do Sistema/2 Especificação/f0/06 amplia o golden set com '
                              'rodada NOVA e nunca editando a anterior — reusar o nome faria duas '
                              'evidências diferentes responderem pela mesma citação.', v_nome));
  end if;

  v_versao := coalesce(p_taxonomia_versao,
                       (select max(t.versao) from taxonomia_tipo_documento t where t.ativo),
                       1);

  insert into golden_rodada (nome, taxonomia_versao, criada_por, nota)
  values (v_nome, v_versao, v_autor, p_nota)
  returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (v_autor, 'golden_rodada_aberta', 'golden_rodada:'||v_id,
          jsonb_build_object('nome', v_nome, 'taxonomia_versao', v_versao));

  return jsonb_build_object('rodada_id', v_id, 'nome', v_nome, 'taxonomia_versao', v_versao);
end;
$$;

--
-- Name: FUNCTION fn_golden_abrir_rodada(p_nome text, p_autor text, p_nota text, p_taxonomia_versao integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_abrir_rodada(p_nome text, p_autor text, p_nota text, p_taxonomia_versao integer) IS 'Abre uma rodada de calibração do Arquitetura do Sistema/2 Especificação/f0/06. Recusa nome repetido em vez de deixar o unique estourar: ampliar o golden set é rodada nova, e o nome é o que uma decisão de dial cita como evidência.';

--
-- Name: fn_golden_campos(uuid, public.golden_origem); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_campos(p_rodada uuid, p_origem public.golden_origem DEFAULT 'real'::public.golden_origem) RETURNS TABLE(tipo text, n_rotulado integer, n_exato integer, n_dentro_tolerancia integer, n_errado integer, n_ausente integer, acerto numeric, n_auto_aceito integer, n_auto_aceito_sem_rotulo integer, cobertura_conferida numeric, n_sem_consenso integer)
    LANGUAGE sql STABLE
    AS $$
  with docs as (
    select gd.documento_id, d.tipo_taxonomia, fn_versao_com_extracao(d.id) as versao_id
    from golden_documento gd
    join documento d on d.id = gd.documento_id
    where gd.rodada_id = p_rodada and gd.origem = p_origem
  ),
  -- Consenso do CAMPO. Regra diferente da do documento, de propósito: aqui basta
  -- que os rotuladores que julgaram este campo concordem. O Arquitetura do Sistema/2 Especificação/f0/06 pede dois
  -- rotuladores "nos casos ambíguos", então o segundo confere uma AMOSTRA das
  -- linhas — exigir que ele tenha julgado todas jogaria fora o rótulo do
  -- primeiro em tudo o que a amostra não cobriu.
  rotulo as (
    select gc.documento_id,
           fn_normalizar_texto(gc.chave)            as chave_norm,
           coalesce(gc.periodo_coluna, '')          as periodo,
           coalesce(gc.entidade_coluna, '')         as entidade,
           min(gc.valor_correto)                    as valor_correto,
           max(gc.tolerancia)                       as tolerancia,
           (count(distinct gc.valor_correto) = 1)   as consenso
    from golden_campo gc
    join docs on docs.documento_id = gc.documento_id
    where gc.rodada_id = p_rodada and gc.valor_correto is not null
    group by 1, 2, 3, 4
  ),
  maquina as (
    select docs.documento_id, docs.tipo_taxonomia,
           fn_normalizar_texto(ce.chave)      as chave_norm,
           coalesce(ce.periodo_coluna, '')    as periodo,
           coalesce(ce.entidade_coluna, '')   as entidade,
           -- Mesma regra de desempate da fn_valores_por_ano (0125): quando o
           -- mesmo par volta duas vezes, vale a ocorrência de maior módulo.
           (array_agg(ce.valor_num order by abs(ce.valor_num) desc))[1] as valor_num,
           bool_or(ce.status_aceite = 'aceito' and ce.aceito_por like 'sistema:auto_aceite%')
             as auto_aceito
    from docs
    join campo_extraido ce on ce.documento_versao_id = docs.versao_id
    where ce.valor_num is not null
      -- 0129: LINHA TRANSCRITA POR HUMANO SAI DA MEDIÇÃO DA EXTRAÇÃO.
      --
      -- Ela mora na mesma tabela das linhas que a IA leu, e sem este filtro a
      -- primeira transcrição contaminaria o número: linha digitada por uma pessoa
      -- olhando o documento bate com o rótulo do golden set quase sempre, e o
      -- acerto sairia creditado à EXTRAÇÃO. Pior, subiria justamente nos
      -- documentos mais difíceis — os que precisaram de transcrição.
      --
      -- É a mesma armadilha que golden_documento.origem fecha do outro lado
      -- (rotular book sintético mede o instrumento), reaparecendo por outra porta.
      and ce.origem_valor = 'extracao'
    group by 1, 2, 3, 4, 5
  ),
  par as (
    select docs.tipo_taxonomia as tipo, r.consenso,
           m.valor_num, r.valor_correto, r.tolerancia
    from rotulo r
    join docs on docs.documento_id = r.documento_id
    left join maquina m
      on m.documento_id = r.documento_id and m.chave_norm = r.chave_norm
     and m.periodo = r.periodo and m.entidade = r.entidade
  ),
  -- A cobertura olha o conjunto INVERSO: linha auto-aceita da máquina que nenhum
  -- rótulo confere.
  cob as (
    select m.tipo_taxonomia as tipo,
           count(*) filter (where m.auto_aceito)::int as n_auto,
           count(*) filter (where m.auto_aceito and r.valor_correto is null)::int as n_auto_sem
    from maquina m
    left join rotulo r
      on r.documento_id = m.documento_id and r.chave_norm = m.chave_norm
     and r.periodo = m.periodo and r.entidade = m.entidade
    group by 1
  )
  select coalesce(p.tipo, c.tipo),
         count(p.consenso) filter (where p.consenso)::int,
         count(*) filter (where p.consenso and p.valor_num is not null
                            and p.valor_num = p.valor_correto)::int,
         count(*) filter (where p.consenso and p.valor_num is not null
                            and p.valor_num <> p.valor_correto
                            and abs(p.valor_num - p.valor_correto) <= p.tolerancia)::int,
         count(*) filter (where p.consenso and p.valor_num is not null
                            and abs(p.valor_num - p.valor_correto) > p.tolerancia)::int,
         count(*) filter (where p.consenso and p.valor_num is null)::int,
         case when count(*) filter (where p.consenso) = 0 then null
              else round(count(*) filter (where p.consenso and p.valor_num is not null
                                            and abs(p.valor_num - p.valor_correto)
                                                <= p.tolerancia)::numeric
                         / count(*) filter (where p.consenso), 4) end,
         coalesce(max(c.n_auto), 0),
         coalesce(max(c.n_auto_sem), 0),
         case when coalesce(max(c.n_auto), 0) = 0 then null
              else round((max(c.n_auto) - max(c.n_auto_sem))::numeric / max(c.n_auto), 4) end,
         count(*) filter (where not p.consenso)::int
  from par p full outer join cob c on c.tipo = p.tipo
  group by 1;
$$;

--
-- Name: FUNCTION fn_golden_campos(p_rodada uuid, p_origem public.golden_origem); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_campos(p_rodada uuid, p_origem public.golden_origem) IS 'Erro de extração de campo financeiro (Arquitetura do Sistema/2 Especificação/f0/06) com AUSENTE separado de ERRADO — perda silenciosa é outra família de defeito, e foi ela que custou as três camadas de cobertura. Traz junto a cobertura_conferida: fração das linhas AUTO-ACEITAS que algum rótulo consegue conferir. O resto virou fato sem ninguém olhar, e reduzi-lo exige rótulo mais fino, não limiar mais alto.';

--
-- Name: fn_golden_candidatos(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_candidatos(p_rodada uuid DEFAULT NULL::uuid) RETURNS TABLE(documento_id uuid, caso_id uuid, caso_nome text, nome_original text, tipo_maquina text, tipo_nome text, obrigatoriedade text, legibilidade text, n_linhas integer, estrato_sugerido text, estrato_porque text, ja_na_rodada boolean, ja_rotulado boolean)
    LANGUAGE sql STABLE
    AS $$
  select d.id,
         d.caso_id,
         c.nome,
         dv.nome_original,
         d.tipo_taxonomia,
         t.documento,
         t.obrigatoriedade::text,
         dv.legibilidade::text,
         (select count(*)::int from campo_extraido ce
           where ce.documento_versao_id = fn_versao_com_extracao(d.id)),
         (fn_golden_estrato_sugerido(d.id)->>'estrato'),
         (fn_golden_estrato_sugerido(d.id)->>'porque'),
         (p_rodada is not null and exists (
            select 1 from golden_documento gd
             where gd.rodada_id = p_rodada and gd.documento_id = d.id)),
         (p_rodada is not null and exists (
            select 1 from golden_rotulo gr
             where gr.rodada_id = p_rodada and gr.documento_id = d.id))
  from documento d
  join caso c on c.id = d.caso_id
  left join taxonomia_tipo_documento t on t.codigo = d.tipo_taxonomia
  left join lateral (
    select dv2.nome_original, dv2.legibilidade
    from documento_versao dv2
    where dv2.documento_id = d.id
    order by dv2.n_versao desc
    limit 1
  ) dv on true
  order by c.nome, d.tipo_taxonomia nulls last, dv.nome_original;
$$;

--
-- Name: FUNCTION fn_golden_candidatos(p_rodada uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_candidatos(p_rodada uuid) IS 'Os documentos que podem entrar numa rodada, com estrato sugerido e as bandeiras de já-incluído / já-rotulado. Não sorteia a amostra de propósito: a estratificação do Arquitetura do Sistema/2 Especificação/f0/06 é escolha humana, e amostra sorteada por função é amostra que ninguém consegue defender.';

--
-- Name: fn_golden_classe_a(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_classe_a(p_caso_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  with a as (
    select p.id, p.estado, p.resolvida_por
    from pendencia p
    where p.origem_estagio = 'reconciliacao'
      and (p_caso_id is null or p.caso_id = p_caso_id)
      and exists (
        select 1 from reconciliacao r
        where r.caso_id = p.caso_id
          and r.classe = 'A'
          and p.motivo = 'reconciliacao:' || r.tipo
      )
  ), v as (
    select
      count(*) filter (where estado = 'rejeitada')::int as falso_positivo,
      count(*) filter (where estado in ('resolvida', 'aceita_com_ressalva')
                         and coalesce(resolvida_por, '') not like 'sistema:%')::int as procedia,
      count(*) filter (where estado = 'resolvida'
                         and coalesce(resolvida_por, '') like 'sistema:%')::int as sumiu_sozinha,
      count(*) filter (where estado in ('aberta','em_correcao_interna','reenviada_ao_cliente'))::int
        as sem_veredito
    from a
  )
  select jsonb_build_object(
    'com_veredito_humano', falso_positivo + procedia,
    'falso_positivo', falso_positivo,
    'procedia', procedia,
    'taxa_falso_positivo',
      case when falso_positivo + procedia = 0 then null
           else round(falso_positivo::numeric / (falso_positivo + procedia), 4) end,
    -- O critério é "mais alto e melhor", como os outros três, para a comparação
    -- em fn_golden_suficiente ser uma só.
    'nao_falso_positivo',
      case when falso_positivo + procedia = 0 then null
           else round(1 - falso_positivo::numeric / (falso_positivo + procedia), 4) end,
    'resolvida_pelo_sistema_sem_veredito', sumiu_sozinha,
    'ainda_sem_veredito', sem_veredito,
    'como_ler', 'O rótulo é o veredito humano registrado pela 0106: rejeitada = não procede = falso '
                'positivo do motor. Pendência que o próprio sistema resolveu não conta em nenhum dos '
                'dois lados — ninguém disse que ela procedia.'
  ) from v;
$$;

--
-- Name: FUNCTION fn_golden_classe_a(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_classe_a(p_caso_id uuid) IS 'Taxa de falso-positivo da reconciliação Classe A (Arquitetura do Sistema/2 Especificação/f0/06, linha 5). Única das cinco métricas que NÃO precisa de rotulagem: o rótulo é o estado "rejeitada" que a 0106 define como "não procede (falso positivo do motor)", e o analista o produz desde 11/08. Denominador = vereditos humanos; pendência que o sistema resolveu sozinho fica fora, contada à parte.';

--
-- Name: fn_golden_classificacao(uuid, public.golden_origem); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_classificacao(p_rodada uuid, p_origem public.golden_origem DEFAULT 'real'::public.golden_origem) RETURNS TABLE(tipo text, n_verdade integer, n_maquina integer, tp integer, fp integer, fn_ integer, precisao numeric, recall numeric, f1 numeric)
    LANGUAGE sql STABLE
    AS $$
  with medido as (
    select c.documento_id, c.tipo_correto, d.tipo_taxonomia as tipo_maquina
    from fn_golden_consenso(p_rodada) c
    join documento d on d.id = c.documento_id
    where c.origem = p_origem and c.tipo_consenso
  ),
  -- O universo de tipos é a UNIÃO do que a verdade diz com o que a máquina diz.
  -- Sem a união, um tipo que a máquina inventa (só falso-positivo, nenhum caso
  -- verdadeiro) desapareceria do relatório — e é o erro mais caro que existe
  -- aqui, porque manda o documento para o checklist errado.
  tipos as (
    select tipo_correto as tipo from medido where tipo_correto is not null
    union
    select tipo_maquina from medido where tipo_maquina is not null
  )
  select t.tipo,
         count(*) filter (where m.tipo_correto = t.tipo)::int,
         count(*) filter (where m.tipo_maquina = t.tipo)::int,
         count(*) filter (where m.tipo_maquina = t.tipo and m.tipo_correto = t.tipo)::int,
         count(*) filter (where m.tipo_maquina = t.tipo
                            and m.tipo_correto is distinct from t.tipo)::int,
         count(*) filter (where m.tipo_correto = t.tipo
                            and m.tipo_maquina is distinct from t.tipo)::int,
         case when count(*) filter (where m.tipo_maquina = t.tipo) = 0 then null
              else round(count(*) filter (where m.tipo_maquina = t.tipo
                                            and m.tipo_correto = t.tipo)::numeric
                         / count(*) filter (where m.tipo_maquina = t.tipo), 4) end,
         case when count(*) filter (where m.tipo_correto = t.tipo) = 0 then null
              else round(count(*) filter (where m.tipo_maquina = t.tipo
                                            and m.tipo_correto = t.tipo)::numeric
                         / count(*) filter (where m.tipo_correto = t.tipo), 4) end,
         -- F1 = 2PR/(P+R), calculado dos contadores em vez de P e R já
         -- arredondados: arredondar antes de combinar propaga o erro para a
         -- métrica que decide.
         case when 2 * count(*) filter (where m.tipo_maquina = t.tipo and m.tipo_correto = t.tipo)
                   + count(*) filter (where m.tipo_maquina = t.tipo
                                        and m.tipo_correto is distinct from t.tipo)
                   + count(*) filter (where m.tipo_correto = t.tipo
                                        and m.tipo_maquina is distinct from t.tipo) = 0
              then null
              else round(
                (2.0 * count(*) filter (where m.tipo_maquina = t.tipo and m.tipo_correto = t.tipo))
                / (2 * count(*) filter (where m.tipo_maquina = t.tipo and m.tipo_correto = t.tipo)
                   + count(*) filter (where m.tipo_maquina = t.tipo
                                        and m.tipo_correto is distinct from t.tipo)
                   + count(*) filter (where m.tipo_correto = t.tipo
                                        and m.tipo_maquina is distinct from t.tipo)), 4) end
  from tipos t cross join medido m
  group by t.tipo;
$$;

--
-- Name: FUNCTION fn_golden_classificacao(p_rodada uuid, p_origem public.golden_origem); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_classificacao(p_rodada uuid, p_origem public.golden_origem) IS 'Precisão/recall/F1 da classificação doc->tipo, POR TIPO (Arquitetura do Sistema/2 Especificação/f0/06). O universo de tipos é a união da verdade com a saída da máquina, senão tipo que a máquina inventa (só FP) não apareceria — e é o erro mais caro, porque manda o documento para o item errado do checklist.';

--
-- Name: fn_golden_cobertura(uuid, public.golden_origem); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_cobertura(p_rodada uuid, p_origem public.golden_origem DEFAULT 'real'::public.golden_origem) RETURNS TABLE(tipo text, granularidade public.granularidade, n_documentos integer, n_dois_rotuladores integer, estratos text[], n_minimo integer, atinge_minimo boolean)
    LANGUAGE sql STABLE
    AS $$
  with alvo as (
    -- Um n_minimo por rodada: o critério é por ESTÁGIO, e a cobertura por tipo é
    -- a mesma exigência para todos eles. O maior dos critérios é o que vale, para
    -- a cobertura não aprovar um tipo que o estágio mais exigente reprovaria.
    select coalesce(max(gc.n_minimo), 20) as n from golden_criterio gc
  ),
  -- O TIPO AQUI É O DA VERDADE, NÃO O DA MÁQUINA, e esta linha é a correção de um
  -- defeito que o teste desta migration achou na primeira execução. Agrupar por
  -- `documento.tipo_taxonomia` faria a COBERTURA DO GROUND TRUTH ser medida pela
  -- resposta que está sob avaliação: numa rodada com 25 balanços dos quais o
  -- classificador chamou 5 de DRE, a cobertura reportava "BALANCO 20, DRE 5" e
  -- reprovava por N — quando a rodada tem 25 balanços rotulados e o que ela
  -- deveria acusar é a classificação errada, não falta de amostra. É a mesma
  -- confusão de autoridade das três de unidade que a sessão 52 achou.
  --
  -- Documento em que os rotuladores discordam do tipo não entra em tipo nenhum:
  -- ele não TEM tipo acordado, e atribuí-lo ao palpite de um dos dois seria
  -- inventar a verdade que falta.
  rot as (
    select c.documento_id, c.tipo_correto, c.n_rotuladores as n_rot, c.estrato
    from fn_golden_consenso(p_rodada) c
    where c.origem = p_origem and c.tipo_consenso
  )
  select t.codigo,
         t.granularidade,
         count(rot.documento_id)::int,
         count(rot.documento_id) filter (where rot.n_rot >= 2)::int,
         coalesce(array_agg(distinct rot.estrato::text)
                    filter (where rot.estrato is not null), '{}'),
         (select n from alvo)::int,
         count(rot.documento_id) >= (select n from alvo)
  from taxonomia_tipo_documento t
  left join rot on rot.tipo_correto = t.codigo
  where t.obrigatoriedade = 'obrigatorio' and t.ativo
  group by t.codigo, t.granularidade;
$$;

--
-- Name: FUNCTION fn_golden_cobertura(p_rodada uuid, p_origem public.golden_origem); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_cobertura(p_rodada uuid, p_origem public.golden_origem) IS 'Quantos documentos rotulados a rodada tem por tipo CORE, contra o alvo do Arquitetura do Sistema/2 Especificação/f0/06 (~20-30). Core sai de obrigatoriedade=obrigatorio na taxonomia (0002), que são os mesmos 8 do Kit Básico — não de uma lista repetida aqui. granularidade vem no resultado porque tipo por CASO rende ~1 por mandato: demorar a juntar 20 é esperado, e o Arquitetura do Sistema/2 Especificação/f0/06 diz isso.';

--
-- Name: fn_golden_congelar(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_congelar(p_rodada uuid, p_autor text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_rodada     golden_rodada;
  v_autor      text := nullif(trim(coalesce(p_autor, '')), '');
  v_n_doc      int;
  v_n_rot      int;
  v_n_campos   int;
  v_n_sem_rot  int;
  v_rotuladores text[];
begin
  if v_autor is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Congelar sem autor. O congelamento é o ato que transforma rótulo em '
                       'evidência datada, e evidência sem quem a fechou não datou nada.');
  end if;

  select * into v_rodada from golden_rodada where id = p_rodada;
  if v_rodada.id is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Rodada %s não existe.', p_rodada));
  end if;

  if v_rodada.congelada_em is not null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A rodada "%s" já foi congelada em %s por %s. Descongelar é recusado '
                              'pelo gatilho da 0126: uma rodada que volta a aceitar rótulo depois '
                              'de ter autorizado uma subida de dial reabre o furo que congelar '
                              'fecha.', v_rodada.nome, v_rodada.congelada_em::date,
                              coalesce(v_rodada.congelada_por, '?')));
  end if;

  select count(*)::int into v_n_doc
    from golden_documento gd where gd.rodada_id = p_rodada;
  select count(*)::int into v_n_rot
    from golden_rotulo gr where gr.rodada_id = p_rodada;
  select count(*)::int into v_n_campos
    from golden_campo gc where gc.rodada_id = p_rodada;

  if v_n_rot = 0 then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A rodada "%s" tem %s documento(s) e nenhum rótulo. Congelada assim '
                              'ela apareceria na lista de rodadas parecendo evidência, e não é: '
                              'congelar dá DATA a um julgamento que aqui não existe.',
                              v_rodada.nome, v_n_doc));
  end if;

  select count(*)::int into v_n_sem_rot
  from golden_documento gd
  where gd.rodada_id = p_rodada
    and not exists (select 1 from golden_rotulo gr
                     where gr.rodada_id = gd.rodada_id and gr.documento_id = gd.documento_id);

  select array_agg(distinct gr.rotulador order by gr.rotulador) into v_rotuladores
    from golden_rotulo gr where gr.rodada_id = p_rodada;

  update golden_rodada
     set congelada_em = now(), congelada_por = v_autor
   where id = p_rodada;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (v_autor, 'golden_rodada_congelada', 'golden_rodada:'||p_rodada,
          jsonb_build_object('nome', v_rodada.nome, 'n_documentos', v_n_doc,
                             'n_rotulos', v_n_rot, 'n_campos', v_n_campos,
                             'n_documentos_sem_rotulo', v_n_sem_rot,
                             'rotuladores', to_jsonb(v_rotuladores)));

  return jsonb_build_object(
    'rodada_id', p_rodada, 'nome', v_rodada.nome, 'congelada_por', v_autor,
    'n_documentos', v_n_doc, 'n_rotulos', v_n_rot, 'n_campos', v_n_campos,
    'n_documentos_sem_rotulo', v_n_sem_rot,
    'rotuladores', to_jsonb(v_rotuladores),
    -- UM ROTULADOR SÓ É UMA ESCOLHA LEGÍTIMA COM UMA CONSEQUÊNCIA MEDÍVEL, e ela
    -- fica dita no ato de congelar em vez de descoberta quando o número não
    -- fecha. O Arquitetura do Sistema/2 Especificação/f0/06 pede dois rotuladores "nos casos ambíguos" para que a
    -- discordância entre humanos seja EXCLUÍDA do placar da máquina. Com um só,
    -- não há discordância a excluir: o documento genuinamente ambíguo entra como
    -- erro da máquina, e a medição fica CONSERVADORA — subestima a qualidade.
    -- Conservador é o lado certo para errar, e mesmo assim precisa estar escrito:
    -- quem lê "acerto 0,91" tem direito de saber que 0,91 é um piso.
    'aviso_rotulador_unico', case when coalesce(array_length(v_rotuladores, 1), 0) > 1 then null else
      format('Rodada rotulada só por %s. fn_golden_inter_avaliador não terá dado, e nada será '
             'excluído do placar por "humanos discordam" — documento ambíguo conta como erro da '
             'máquina. A medição fica conservadora: o número que sair é um PISO da qualidade real, '
             'não uma estimativa dela.', coalesce(v_rotuladores[1], '?')) end);
end;
$$;

--
-- Name: FUNCTION fn_golden_congelar(p_rodada uuid, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_congelar(p_rodada uuid, p_autor text) IS 'Congela a rodada — o ato que dá DATA à evidência e sem o qual fn_golden_suficiente não autoriza subida. Recusa rodada sem nenhum rótulo (apareceria na lista parecendo evidência) e não recusa documento incluído sem rótulo (ele não entra em métrica, e exigi-lo produziria rótulo ruim, que é pior que rótulo nenhum). Avisa quando houve um rotulador só: aí a medição é um piso.';

--
-- Name: fn_golden_consenso(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_consenso(p_rodada uuid) RETURNS TABLE(documento_id uuid, estrato public.golden_estrato, origem public.golden_origem, n_rotuladores integer, tipo_correto text, tipo_consenso boolean, entidade_correta text, entidade_consenso boolean, periodo_correto text, periodo_consenso boolean, assinado_correto boolean, assinado_consenso boolean, legibilidade_correta public.legibilidade, legibilidade_consenso boolean, item_checklist_correto text, item_consenso boolean)
    LANGUAGE sql STABLE
    AS $$
  with base as (
    -- Colunas nomeadas, não `gr.*`: golden_rotulo TAMBÉM tem documento_id, e o
    -- `*` faria a CTE devolver duas colunas com esse nome — o `group by
    -- b.documento_id` sai como "column reference is ambiguous".
    select gd.documento_id, gd.estrato, gd.origem,
           gr.rotulador, gr.tipo_correto, gr.entidade_correta, gr.periodo_correto,
           gr.assinado_correto, gr.legibilidade, gr.item_checklist_correto,
           -- O primeiro rotulador (ordem estável por nome) é a referência da
           -- comparação de entidade: fn_mesma_entidade é par a par, e comparar
           -- todos contra um só é o que a torna agregável.
           first_value(gr.entidade_correta) over (
             partition by gd.documento_id order by gr.rotulador
           ) as entidade_ref
    from golden_documento gd
    join golden_rotulo gr
      on gr.rodada_id = gd.rodada_id and gr.documento_id = gd.documento_id
    where gd.rodada_id = p_rodada
  )
  select
    b.documento_id,
    min(b.estrato) as estrato,
    min(b.origem)  as origem,
    count(*)::int  as n_rotuladores,

    -- Consenso: só devolve valor quando TODOS julgaram e todos disseram o mesmo.
    -- `count(x) = count(*)` é o que exige que ninguém tenha se calado, e
    -- `count(distinct x) = 1` é o que exige que todos digam o mesmo.
    case when count(b.tipo_correto) = count(*) and count(distinct b.tipo_correto) = 1
         then min(b.tipo_correto) end,
    (count(b.tipo_correto) = count(*) and count(distinct b.tipo_correto) = 1),

    case when count(b.entidade_correta) = count(*)
              and bool_and(fn_mesma_entidade(b.entidade_correta, b.entidade_ref))
         then min(b.entidade_ref) end,
    (count(b.entidade_correta) = count(*)
       and bool_and(fn_mesma_entidade(b.entidade_correta, b.entidade_ref))),

    case when count(b.periodo_correto) = count(*) and count(distinct b.periodo_correto) = 1
         then min(b.periodo_correto) end,
    (count(b.periodo_correto) = count(*) and count(distinct b.periodo_correto) = 1),

    case when count(b.assinado_correto) = count(*) and count(distinct b.assinado_correto) = 1
         then bool_and(b.assinado_correto) end,
    (count(b.assinado_correto) = count(*) and count(distinct b.assinado_correto) = 1),

    case when count(b.legibilidade) = count(*) and count(distinct b.legibilidade) = 1
         then min(b.legibilidade) end,
    (count(b.legibilidade) = count(*) and count(distinct b.legibilidade) = 1),

    case when count(b.item_checklist_correto) = count(*)
              and count(distinct b.item_checklist_correto) = 1
         then min(b.item_checklist_correto) end,
    (count(b.item_checklist_correto) = count(*)
       and count(distinct b.item_checklist_correto) = 1)
  from base b
  group by b.documento_id;
$$;

--
-- Name: FUNCTION fn_golden_consenso(p_rodada uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_consenso(p_rodada uuid) IS 'O ground truth consolidado de uma rodada, campo a campo. Onde os rotuladores discordam o campo volta null com consenso=false, e as métricas o EXCLUEM: Arquitetura do Sistema/2 Especificação/f0/06, "se humanos discordam, a máquina não tem como acertar". null de rotulador é "não julgou", que também não vira consenso.';

--
-- Name: fn_golden_estrato_sugerido(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_estrato_sugerido(p_documento_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $_$
declare
  v_nome  text;
  v_leg   legibilidade;
  v_ext   text;
begin
  select dv.nome_original, dv.legibilidade into v_nome, v_leg
  from documento_versao dv
  where dv.documento_id = p_documento_id
  order by dv.n_versao desc
  limit 1;

  if v_nome is null and v_leg is null then
    return jsonb_build_object('estrato', null,
      'porque', 'O documento não tem versão com nome de arquivo — não há de onde inferir.');
  end if;

  v_ext := lower(coalesce(substring(v_nome from '\.([A-Za-z0-9]+)$'), ''));

  if v_ext in ('xlsx', 'xls', 'csv', 'docx', 'doc', 'txt') then
    return jsonb_build_object('estrato', 'digital',
      'porque', format('Extensão .%s: arquivo de escritório, texto nativo.', v_ext));
  end if;

  if v_ext in ('jpg', 'jpeg', 'png', 'heic', 'webp') then
    return jsonb_build_object('estrato', 'foto',
      'porque', format('Extensão .%s: imagem, o pior estrato de captura.', v_ext));
  end if;

  if v_ext = 'pdf' then
    -- A legibilidade é o único sinal que o banco tem sobre a qualidade da
    -- captura, e ela é o veredito da extração, não do arquivo. Serve para
    -- separar "PDF que se leu bem" de "PDF que não se leu" — que é quase sempre
    -- um scan ruim. Quase: um PDF nativo com layout hostil também degrada.
    if v_leg is null or v_leg = 'ok' then
      return jsonb_build_object('estrato', 'pdf_nativo',
        'porque', 'PDF que a extração leu sem apontar degradação. CONFIRA: um scan legível cai '
                  'aqui por engano, e escaneado é o estrato que decide se o dial pode subir.');
    end if;
    return jsonb_build_object('estrato', 'escaneado',
      'porque', format('PDF com legibilidade "%s" — degradação é o sintoma típico de scan.', v_leg));
  end if;

  return jsonb_build_object('estrato', null,
    'porque', format('Extensão "%s" não está em nenhuma das quatro faixas. Diga você.',
                     coalesce(nullif(v_ext, ''), '(sem extensão)')));
end;
$_$;

--
-- Name: FUNCTION fn_golden_estrato_sugerido(p_documento_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_estrato_sugerido(p_documento_id uuid) IS 'Sugere o golden_estrato pela extensão e pela legibilidade. É SUGESTÃO: o banco não distingue PDF nativo de PDF escaneado sem olhar as páginas, e escaneado é justamente o estrato cujo pior caso decide a subida de dial. Sugerir aqui não ancora julgamento nenhum — estrato é propriedade do arquivo, não leitura de conteúdo.';

--
-- Name: fn_golden_identificadores(uuid, public.golden_origem); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_identificadores(p_rodada uuid, p_origem public.golden_origem DEFAULT 'real'::public.golden_origem) RETURNS TABLE(identificador text, n_medido integer, n_acerto integer, acuracia numeric, n_sem_consenso integer)
    LANGUAGE sql STABLE
    AS $$
  with c as (select * from fn_golden_consenso(p_rodada) where origem = p_origem),
  j as (
    select c.*,
           d.tipo_taxonomia as tipo_maquina,
           (select p.referencia from periodo p where p.id = d.periodo_id)  as periodo_maquina,
           (select e.razao_social from entidade e where e.id = d.entidade_id) as entidade_maquina
    from c join documento d on d.id = c.documento_id
  ), m as (
    select 'tipo' as identificador, tipo_consenso as tem_consenso,
           (tipo_maquina = tipo_correto) as acertou from j
    union all
    select 'periodo', periodo_consenso,
           (periodo_maquina = periodo_correto) from j
    union all
    select 'entidade', entidade_consenso,
           -- fn_mesma_entidade nunca devolve null aqui: o consenso garante os
           -- dois lados preenchidos do lado da verdade, e do lado da máquina o
           -- coalesce evita que documento sem entidade some da conta — ele é
           -- ERRO quando a verdade nomeia uma empresa, não item não medido.
           fn_mesma_entidade(coalesce(entidade_maquina, ''), entidade_correta) from j
  )
  select m.identificador,
         count(*) filter (where m.tem_consenso)::int,
         count(*) filter (where m.tem_consenso and m.acertou)::int,
         case when count(*) filter (where m.tem_consenso) = 0 then null
              else round(count(*) filter (where m.tem_consenso and m.acertou)::numeric
                         / count(*) filter (where m.tem_consenso), 4) end,
         count(*) filter (where not m.tem_consenso)::int
  from m group by m.identificador;
$$;

--
-- Name: FUNCTION fn_golden_identificadores(p_rodada uuid, p_origem public.golden_origem); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_identificadores(p_rodada uuid, p_origem public.golden_origem) IS 'Acurácia de tipo/período/entidade separadamente (Arquitetura do Sistema/2 Especificação/f0/06). Separados porque as causas de erro são distintas — a 0121 foi entidade pura, a 0122 período puro — e o agregado esconderia a coluna que precisa de trabalho. Entidade casa por fn_mesma_entidade: grafia diferente não é erro.';

--
-- Name: fn_golden_incluir_documento(uuid, uuid, public.golden_estrato, public.golden_origem, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_incluir_documento(p_rodada uuid, p_documento_id uuid, p_estrato public.golden_estrato, p_origem public.golden_origem, p_autor text, p_nota text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_rodada golden_rodada;
  v_autor  text := nullif(trim(coalesce(p_autor, '')), '');
begin
  if v_autor is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Sem autor: quem escolheu a amostra é parte da evidência.');
  end if;

  select * into v_rodada from golden_rodada where id = p_rodada;
  if v_rodada.id is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Rodada %s não existe.', p_rodada));
  end if;

  -- O gatilho da 0126 já barra isto com exceção. Aqui a recusa é RETORNADA
  -- porque a tela precisa dizer o que fazer — e o que fazer é abrir rodada nova,
  -- não tentar de novo.
  if v_rodada.congelada_em is not null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A rodada "%s" foi congelada em %s. Rodada congelada não recebe mais '
                              'documento: o Arquitetura do Sistema/2 Especificação/f0/06 amplia com rodada NOVA, senão a evidência que '
                              'autorizou uma subida de dial muda depois da subida.',
                              v_rodada.nome, v_rodada.congelada_em::date));
  end if;

  if not exists (select 1 from documento d where d.id = p_documento_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Documento %s não existe.', p_documento_id));
  end if;

  if exists (select 1 from golden_documento gd
              where gd.rodada_id = p_rodada and gd.documento_id = p_documento_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Este documento já está nesta rodada. Como estrato e origem não se editam '
                       '(append-only), corrigi-los é rodada nova — e um documento incluído duas '
                       'vezes contaria em dobro na cobertura.');
  end if;

  if p_estrato is null or p_origem is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Estrato e origem são obrigatórios. Estrato porque a métrica agregada sobre '
                       'estratos misturados esconde o pior caso, que é justamente o que decide a '
                       'subida; origem porque as métricas do dial contam só documento real.');
  end if;

  insert into golden_documento (rodada_id, documento_id, estrato, origem, incluido_por, nota)
  values (p_rodada, p_documento_id, p_estrato, p_origem, v_autor, p_nota);

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (v_autor, 'golden_documento_incluido', 'golden_rodada:'||p_rodada,
          jsonb_build_object('documento_id', p_documento_id,
                             'estrato', p_estrato, 'origem', p_origem));

  return jsonb_build_object('rodada_id', p_rodada, 'documento_id', p_documento_id,
                            'estrato', p_estrato, 'origem', p_origem);
end;
$$;

--
-- Name: FUNCTION fn_golden_incluir_documento(p_rodada uuid, p_documento_id uuid, p_estrato public.golden_estrato, p_origem public.golden_origem, p_autor text, p_nota text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_incluir_documento(p_rodada uuid, p_documento_id uuid, p_estrato public.golden_estrato, p_origem public.golden_origem, p_autor text, p_nota text) IS 'Inclui um documento na rodada. Estrato e origem são obrigatórios e não inferidos: o banco não distingue documento de cliente do book sintético, e chutar isso inflaria a amostra com aquilo cujo gabarito já se conhece — que é medir o instrumento, não o modelo.';

--
-- Name: fn_golden_inter_avaliador(uuid, public.golden_origem); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_inter_avaliador(p_rodada uuid, p_origem public.golden_origem DEFAULT 'real'::public.golden_origem) RETURNS TABLE(campo text, n_com_dois_ou_mais integer, n_concordam integer, concordancia numeric)
    LANGUAGE sql STABLE
    AS $$
  with c as (
    select * from fn_golden_consenso(p_rodada) where origem = p_origem
  ), m as (
    select 'tipo' as campo, n_rotuladores, tipo_consenso as ok from c
    union all select 'entidade',     n_rotuladores, entidade_consenso     from c
    union all select 'periodo',      n_rotuladores, periodo_consenso      from c
    union all select 'assinado',     n_rotuladores, assinado_consenso     from c
    union all select 'legibilidade', n_rotuladores, legibilidade_consenso from c
    union all select 'item_checklist', n_rotuladores, item_consenso       from c
  )
  select m.campo,
         count(*) filter (where m.n_rotuladores >= 2)::int,
         count(*) filter (where m.n_rotuladores >= 2 and m.ok)::int,
         case when count(*) filter (where m.n_rotuladores >= 2) = 0 then null
              else round(count(*) filter (where m.n_rotuladores >= 2 and m.ok)::numeric
                         / count(*) filter (where m.n_rotuladores >= 2), 4) end
  from m group by m.campo;
$$;

--
-- Name: FUNCTION fn_golden_inter_avaliador(p_rodada uuid, p_origem public.golden_origem); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_inter_avaliador(p_rodada uuid, p_origem public.golden_origem) IS 'Concordância entre rotuladores, por campo (Arquitetura do Sistema/2 Especificação/f0/06). Conta só documento com 2+ rotuladores — com um só não há discordância possível, e incluí-lo inflaria a concordância humana com itens que ninguém conferiu duas vezes. Não mede o sistema: mede se a pergunta é respondível.';

--
-- Name: fn_golden_linhas_para_rotular(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_linhas_para_rotular(p_rodada uuid, p_documento_id uuid, p_rotulador text DEFAULT NULL::text) RETURNS TABLE(chave text, secao text, periodo_coluna text, entidade_coluna text, origem_pagina integer, unidade text, ja_rotulada boolean)
    LANGUAGE sql STABLE
    AS $$
  select ce.chave, ce.secao, ce.periodo_coluna, ce.entidade_coluna, ce.origem_pagina, ce.unidade,
         exists (
           select 1 from golden_campo gc
            where gc.rodada_id = p_rodada
              and gc.documento_id = p_documento_id
              and (p_rotulador is null or gc.rotulador = p_rotulador)
              and fn_normalizar_texto(gc.chave) = fn_normalizar_texto(ce.chave)
              and coalesce(gc.periodo_coluna, '') = coalesce(ce.periodo_coluna, '')
              and coalesce(gc.entidade_coluna, '') = coalesce(ce.entidade_coluna, '')
         )
  from campo_extraido ce
  where ce.documento_versao_id = fn_versao_com_extracao(p_documento_id)
    and ce.valor_num is not null
  order by ce.origem_pagina nulls last, ce.ordem, ce.chave;
$$;

--
-- Name: FUNCTION fn_golden_linhas_para_rotular(p_rodada uuid, p_documento_id uuid, p_rotulador text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_linhas_para_rotular(p_rodada uuid, p_documento_id uuid, p_rotulador text) IS 'As rubricas que a extração achou, SEM O VALOR. Rotulagem cega (fechamento #5 do Arquitetura do Sistema/1 Visão e Doutrina/01): quem vê o palpite da máquina produz conferência, não ground truth, e a métrica sobe sem nada melhorar. A rubrica vem porque é a chave de casamento de fn_golden_campos — esconde-la faria diferença de grafia entrar como AUSENTE, cobrando da máquina um erro de datilografia.';

--
-- Name: fn_golden_progresso(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_progresso(p_rodada uuid) RETURNS TABLE(tipo text, tipo_nome text, obrigatoriedade text, n_incluidos integer, n_rotulados integer, n_rotulados_verdade integer, n_minimo integer, falta integer)
    LANGUAGE sql STABLE
    AS $$
  with alvo as (
    select coalesce(max(gc.n_minimo), 20) as n from golden_criterio gc
  ),
  incl as (
    select d.tipo_taxonomia as tipo,
           count(*)::int as n_incluidos,
           count(*) filter (where exists (
             select 1 from golden_rotulo gr
              where gr.rodada_id = gd.rodada_id and gr.documento_id = gd.documento_id))::int
             as n_rotulados
    from golden_documento gd
    join documento d on d.id = gd.documento_id
    where gd.rodada_id = p_rodada and gd.origem = 'real'
    group by 1
  ),
  -- A contagem pela VERDADE, para a divergência ficar à vista: é este número que
  -- o portão do dial usa, via fn_golden_cobertura.
  verdade as (
    select c.tipo, c.n_documentos::int as n
    from fn_golden_cobertura(p_rodada) c
  )
  select coalesce(i.tipo, v.tipo),
         t.documento,
         t.obrigatoriedade::text,
         coalesce(i.n_incluidos, 0),
         coalesce(i.n_rotulados, 0),
         coalesce(v.n, 0),
         (select n from alvo),
         greatest((select n from alvo) - coalesce(v.n, 0), 0)
  from incl i
  full outer join verdade v on v.tipo = i.tipo
  left join taxonomia_tipo_documento t on t.codigo = coalesce(i.tipo, v.tipo)
  order by t.obrigatoriedade, 1;
$$;

--
-- Name: FUNCTION fn_golden_progresso(p_rodada uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_progresso(p_rodada uuid) IS 'Quanto falta para a rodada bater o N do Arquitetura do Sistema/2 Especificação/f0/06, por tipo. Traz DUAS contagens de propósito: n_rotulados agrupa pelo tipo que a MÁQUINA diz (é a etiqueta que existe na hora de montar a amostra) e n_rotulados_verdade pelo consenso humano (é o que o portão do dial conta). Divergirem não é bug: é o erro de classificação aparecendo.';

--
-- Name: fn_golden_rodada_congelada(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_rodada_congelada() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_rodada uuid := new.rodada_id;
  v_congelada timestamptz;
  v_nome text;
begin
  select gr.congelada_em, gr.nome into v_congelada, v_nome
  from golden_rodada gr where gr.id = v_rodada;
  if v_congelada is not null then
    raise exception 'A rodada de golden set "%" foi congelada em % e não aceita mais rótulo. '
                    'O Arquitetura do Sistema/2 Especificação/f0/06 manda AMPLIAR criando rodada nova, não editando a medida: a rodada '
                    'congelada é a evidência de uma decisão de dial já tomada.',
                    coalesce(v_nome, v_rodada::text), v_congelada
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

--
-- Name: fn_golden_rodada_congelada_imutavel(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_rodada_congelada_imutavel() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if old.congelada_em is null then
    return new;   -- rodada aberta: nome, nota e versão ainda são editáveis
  end if;
  if new.congelada_em is null then
    raise exception 'A rodada "%" já foi congelada em % e não descongela. Ampliar o golden set é '
                    'rodada NOVA (Arquitetura do Sistema/2 Especificação/f0/06); descongelar permitiria reescrever a evidência depois de '
                    'ela ter autorizado uma subida de dial.', old.nome, old.congelada_em
      using errcode = 'check_violation';
  end if;
  if new.nome <> old.nome or new.taxonomia_versao <> old.taxonomia_versao then
    raise exception 'A rodada "%" está congelada: nome e taxonomia_versao não mudam mais. O nome é '
                    'citado na trilha e em estagio_autonomia.medicao_resumo, e a versão da '
                    'taxonomia é a premissa dos rótulos — mudar qualquer um reescreve a evidência '
                    'de uma decisão de dial sem tocar em um rótulo.', old.nome
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

--
-- Name: fn_golden_rotular(uuid, uuid, text, text, text, text, boolean, public.legibilidade, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_rotular(p_rodada uuid, p_documento_id uuid, p_rotulador text, p_tipo_correto text DEFAULT NULL::text, p_entidade_correta text DEFAULT NULL::text, p_periodo_correto text DEFAULT NULL::text, p_assinado_correto boolean DEFAULT NULL::boolean, p_legibilidade public.legibilidade DEFAULT NULL::public.legibilidade, p_item_checklist_correto text DEFAULT NULL::text, p_nota text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_rodada    golden_rodada;
  v_rotulador text := nullif(trim(coalesce(p_rotulador, '')), '');
  v_tipo      text := nullif(trim(coalesce(p_tipo_correto, '')), '');
  v_id        uuid;
begin
  if v_rotulador is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Rótulo sem rotulador. O Arquitetura do Sistema/2 Especificação/f0/06 mede concordância ENTRE rotuladores, e a '
                       'chave da tabela é (rodada, documento, rotulador) exatamente para isso — '
                       'rótulo anônimo não tem como participar de concordância nenhuma.');
  end if;

  select * into v_rodada from golden_rodada where id = p_rodada;
  if v_rodada.id is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Rodada %s não existe.', p_rodada));
  end if;
  if v_rodada.congelada_em is not null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A rodada "%s" está congelada desde %s e não aceita mais rótulo. '
                              'Ampliar é rodada nova: evidência que ainda muda não sustenta uma '
                              'decisão registrada contra ela.',
                              v_rodada.nome, v_rodada.congelada_em::date));
  end if;

  if not exists (select 1 from golden_documento gd
                  where gd.rodada_id = p_rodada and gd.documento_id = p_documento_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Este documento não está nesta rodada. Inclua-o primeiro, declarando estrato '
                       'e origem — são eles que fazem a amostra ser estratificada em vez de ser um '
                       'monte de arquivos.');
  end if;

  if exists (select 1 from golden_rotulo gr
              where gr.rodada_id = p_rodada and gr.documento_id = p_documento_id
                and gr.rotulador = v_rotulador) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('%s já rotulou este documento nesta rodada, e rótulo é append-only: '
                              'corrigir um rótulo depois da medição é reescrever a justificativa de '
                              'uma decisão de dial a posteriori. Se o rótulo estava errado, a '
                              'correção é rodada nova.', v_rotulador));
  end if;

  if v_tipo is not null
     and not exists (select 1 from taxonomia_tipo_documento t where t.codigo = v_tipo) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('"%s" não é um código de tipo do catálogo. Tipo digitado errado não '
                              'fica errado só no rótulo: ele vira falso negativo permanente da '
                              'máquina no F1 daquele tipo, e ninguém relê um rótulo append-only.',
                              v_tipo));
  end if;

  -- Rótulo com todos os campos nulos é ruído: ele CONTA como documento rotulado
  -- na cobertura (a 0126 conta a existência da linha) e não mede nada. Seria a
  -- forma mais fácil de bater o n_minimo sem produzir evidência.
  if v_tipo is null and p_entidade_correta is null and p_periodo_correto is null
     and p_assinado_correto is null and p_legibilidade is null
     and p_item_checklist_correto is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Rótulo vazio. Ele contaria como documento rotulado na cobertura e não '
                       'mediria nada — é o jeito mais fácil de bater o N mínimo do Arquitetura do Sistema/2 Especificação/f0/06 sem '
                       'produzir evidência. Julgue ao menos um campo.');
  end if;

  insert into golden_rotulo
    (rodada_id, documento_id, rotulador, tipo_correto, entidade_correta, periodo_correto,
     assinado_correto, legibilidade, item_checklist_correto, nota)
  values
    (p_rodada, p_documento_id, v_rotulador, v_tipo,
     nullif(trim(coalesce(p_entidade_correta, '')), ''),
     nullif(trim(coalesce(p_periodo_correto, '')), ''),
     p_assinado_correto, p_legibilidade,
     nullif(trim(coalesce(p_item_checklist_correto, '')), ''), p_nota)
  returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (v_rotulador, 'golden_rotulo', 'golden_rodada:'||p_rodada,
          jsonb_build_object('documento_id', p_documento_id, 'rotulo_id', v_id,
                             'porque', 'rotulagem CEGA: o rotulador nao viu a resposta da maquina '
                                       '(fn_golden_linhas_para_rotular nao devolve valor). '
                                       'fechamento #5 do Arquitetura do Sistema/1 Visão e Doutrina/01.'));

  return jsonb_build_object('rotulo_id', v_id, 'rotulador', v_rotulador,
                            'documento_id', p_documento_id);
end;
$$;

--
-- Name: FUNCTION fn_golden_rotular(p_rodada uuid, p_documento_id uuid, p_rotulador text, p_tipo_correto text, p_entidade_correta text, p_periodo_correto text, p_assinado_correto boolean, p_legibilidade public.legibilidade, p_item_checklist_correto text, p_nota text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_rotular(p_rodada uuid, p_documento_id uuid, p_rotulador text, p_tipo_correto text, p_entidade_correta text, p_periodo_correto text, p_assinado_correto boolean, p_legibilidade public.legibilidade, p_item_checklist_correto text, p_nota text) IS 'Grava o julgamento humano do documento (Arquitetura do Sistema/2 Especificação/f0/06, "o que é rotulado"), um por rotulador. Recusa tipo fora do catálogo porque typo em rótulo append-only vira falso negativo permanente da máquina, e recusa rótulo vazio porque ele contaria na cobertura sem medir nada.';

--
-- Name: fn_golden_rotular_campos(uuid, uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_rotular_campos(p_rodada uuid, p_documento_id uuid, p_rotulador text, p_campos jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
declare
  v_rodada    golden_rodada;
  v_rotulador text := nullif(trim(coalesce(p_rotulador, '')), '');
  v_versao    uuid;
  v_item      jsonb;
  v_chave     text;
  v_valor     numeric;
  v_tol       numeric;
  v_classe    text;
  v_per       text;
  v_ent       text;
  v_casou     boolean;
  v_gravados  jsonb := '[]'::jsonb;
  v_pulados   jsonb := '[]'::jsonb;
  v_n_sem_par int := 0;
begin
  if v_rotulador is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Rótulo de campo sem rotulador.');
  end if;

  select * into v_rodada from golden_rodada where id = p_rodada;
  if v_rodada.id is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Rodada %s não existe.', p_rodada));
  end if;
  if v_rodada.congelada_em is not null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A rodada "%s" está congelada desde %s.',
                              v_rodada.nome, v_rodada.congelada_em::date));
  end if;

  if not exists (select 1 from golden_documento gd
                  where gd.rodada_id = p_rodada and gd.documento_id = p_documento_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Este documento não está nesta rodada.');
  end if;

  if p_campos is null or jsonb_typeof(p_campos) <> 'array' or jsonb_array_length(p_campos) = 0 then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Nenhum campo para rotular.');
  end if;

  v_versao := fn_versao_com_extracao(p_documento_id);

  for v_item in select * from jsonb_array_elements(p_campos)
  loop
    v_chave := nullif(trim(coalesce(v_item->>'chave', '')), '');
    v_per   := nullif(trim(coalesce(v_item->>'periodo_coluna', '')), '');
    v_ent   := nullif(trim(coalesce(v_item->>'entidade_coluna', '')), '');
    v_valor := case when (v_item->>'valor_correto') ~ '^-?\d+(\.\d+)?$'
                    then (v_item->>'valor_correto')::numeric end;
    v_tol   := coalesce(case when (v_item->>'tolerancia') ~ '^\d+(\.\d+)?$'
                             then (v_item->>'tolerancia')::numeric end, 0);
    v_classe := nullif(trim(coalesce(v_item->>'classe_contabil_correta', '')), '');

    if v_chave is null then
      v_pulados := v_pulados || jsonb_build_object(
        'chave', v_item->>'chave', 'porque', 'sem rubrica: não haveria como casar com linha nenhuma');
      continue;
    end if;

    -- Campo sem valor é descartado e DITO. `fn_golden_campos` filtra
    -- `valor_correto is not null`, então gravá-lo criaria uma linha que existe no
    -- banco e não aparece em métrica nenhuma — o pior estado, porque quem conta
    -- rótulos acha que rotulou.
    if v_valor is null then
      v_pulados := v_pulados || jsonb_build_object(
        'chave', v_chave,
        'porque', 'sem valor numérico: fn_golden_campos só conta rótulo com valor, então esta '
                  'linha existiria no banco sem entrar em métrica nenhuma');
      continue;
    end if;

    if v_classe is not null
       and not exists (select 1 from classe_contabil_catalogo cc where cc.codigo = v_classe) then
      v_pulados := v_pulados || jsonb_build_object(
        'chave', v_chave,
        'porque', format('classe contábil "%s" não está no catálogo das cinco do Arquitetura do Sistema/2 Especificação/05', v_classe));
      continue;
    end if;

    if exists (select 1 from golden_campo gc
                where gc.rodada_id = p_rodada and gc.documento_id = p_documento_id
                  and gc.rotulador = v_rotulador
                  and gc.chave = v_chave
                  and coalesce(gc.periodo_coluna, '') = coalesce(v_per, '')
                  and coalesce(gc.entidade_coluna, '') = coalesce(v_ent, '')) then
      v_pulados := v_pulados || jsonb_build_object(
        'chave', v_chave,
        'porque', 'já rotulada por você nesta rodada (append-only: corrigir é rodada nova)');
      continue;
    end if;

    insert into golden_campo
      (rodada_id, documento_id, rotulador, chave, periodo_coluna, entidade_coluna,
       valor_correto, classe_contabil_correta, tolerancia)
    values
      (p_rodada, p_documento_id, v_rotulador, v_chave, v_per, v_ent, v_valor, v_classe, v_tol);

    -- A REVELAÇÃO, calculada com o mesmo casamento de `fn_golden_campos`: chave
    -- normalizada + período + entidade. Usar outro critério aqui faria a tela
    -- prometer um par que a métrica não vai encontrar.
    select exists (
      select 1 from campo_extraido ce
       where ce.documento_versao_id = v_versao
         and ce.valor_num is not null
         and fn_normalizar_texto(ce.chave) = fn_normalizar_texto(v_chave)
         and coalesce(ce.periodo_coluna, '') = coalesce(v_per, '')
         and coalesce(ce.entidade_coluna, '') = coalesce(v_ent, '')
    ) into v_casou;

    if not v_casou then v_n_sem_par := v_n_sem_par + 1; end if;

    v_gravados := v_gravados || jsonb_build_object(
      'chave', v_chave, 'periodo_coluna', v_per, 'entidade_coluna', v_ent,
      'valor_correto', v_valor, 'tolerancia', v_tol, 'casou_com_a_extracao', v_casou);
  end loop;

  if jsonb_array_length(v_gravados) > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values (v_rotulador, 'golden_campos', 'golden_rodada:'||p_rodada,
            jsonb_build_object('documento_id', p_documento_id,
                               'n_gravados', jsonb_array_length(v_gravados),
                               'n_sem_par', v_n_sem_par,
                               'n_pulados', jsonb_array_length(v_pulados)));
  end if;

  return jsonb_build_object(
    'gravados', v_gravados,
    'pulados', v_pulados,
    'n_gravados', jsonb_array_length(v_gravados),
    'n_sem_par', v_n_sem_par,
    -- O texto do aviso mora aqui e não na tela: o motivo é o mesmo de sempre
    -- nesta casa — quem lê o retorno da função no psql precisa ver a mesma coisa
    -- que quem lê a tela, senão existem duas verdades.
    'aviso_sem_par', case when v_n_sem_par = 0 then null else format(
      '%s linha(s) que você rotulou não casaram com nenhuma linha da extração. Isso conta como '
      'AUSENTE no placar (perda silenciosa) e pode ser uma de duas coisas: a extração perdeu a '
      'linha de verdade, ou a rubrica que você escreveu não é reconhecível como a mesma. As duas '
      'importam, e são diferentes.', v_n_sem_par) end);
end;
$_$;

--
-- Name: FUNCTION fn_golden_rotular_campos(p_rodada uuid, p_documento_id uuid, p_rotulador text, p_campos jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_rotular_campos(p_rodada uuid, p_documento_id uuid, p_rotulador text, p_campos jsonb) IS 'Grava os valores lidos pelo humano e REVELA, depois de gravar, quais casaram com a extração. Aceita rubrica fora da lista da máquina de propósito: é o único caminho pelo qual a perda silenciosa (n_ausente) chega a ser medida. Revelar antes de gravar seria ancoragem pela porta de trás — o rótulo passaria a perseguir a grafia que casa.';

--
-- Name: fn_golden_suficiente(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_golden_suficiente(p_estagio text, p_rodada uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
declare
  v_natureza  text;
  v_crit      golden_criterio;
  v_rodada    golden_rodada;
  v_falhas    jsonb := '[]'::jsonb;
  v_detalhe   jsonb;
  v_pior      numeric;
  v_n_min_ok  boolean;
  v_classe_a  jsonb;
begin
  select natureza into v_natureza from estagio_autonomia where estagio = p_estagio;
  if v_natureza is null then
    return jsonb_build_object('aplica', false, 'suficiente', false,
      'porque', format('Estágio "%s" não existe no dial.', p_estagio));
  end if;

  -- Determinístico: a regra de ouro do Arquitetura do Sistema/1 Visão e Doutrina/01 fala de estágio INTERPRETATIVO. A
  -- confiança em aritmética e integridade de arquivo não vem de concordância
  -- humana, e pedir rotulador para conferir se um zip abre não mediria nada.
  if v_natureza = 'deterministico' then
    return jsonb_build_object('aplica', false, 'suficiente', true,
      'porque', 'Estágio determinístico objetivo (Arquitetura do Sistema/1 Visão e Doutrina/01): a regra de ouro governa os '
                'interpretativos. A garantia dele é teste, não concordância medida.');
  end if;

  select * into v_crit from golden_criterio where estagio = p_estagio;
  if v_crit.estagio is null then
    return jsonb_build_object('aplica', true, 'suficiente', false,
      'porque', format('Não há critério de golden set para "%s" em golden_criterio, então não há '
                       'como medir se a concordância basta. Estágio de teto N1 (reconciliação '
                       'Classe B/C, classificação contábil) nunca chega aqui — o teto recusa antes, '
                       'e Arquitetura do Sistema/1 Visão e Doutrina/01 os marca como "nunca autônomo".', p_estagio));
  end if;

  if p_rodada is null then
    return jsonb_build_object('aplica', true, 'suficiente', false,
      'criterio', to_jsonb(v_crit),
      'porque', 'Nenhuma rodada de golden set informada. Arquitetura do Sistema/1 Visão e Doutrina/01, regra de ouro: subir dial de '
                'estágio interpretativo exige concordância MEDIDA — sem rodada não há medição.');
  end if;

  select * into v_rodada from golden_rodada where id = p_rodada;
  if v_rodada.id is null then
    return jsonb_build_object('aplica', true, 'suficiente', false, 'criterio', to_jsonb(v_crit),
      'porque', format('Rodada de golden set %s não existe.', p_rodada));
  end if;
  if v_rodada.congelada_em is null then
    return jsonb_build_object('aplica', true, 'suficiente', false, 'criterio', to_jsonb(v_crit),
      'rodada', v_rodada.nome,
      'porque', format('A rodada "%s" não está CONGELADA. O Arquitetura do Sistema/2 Especificação/f0/06 congela a rodada por medição, e '
                       'evidência que ainda pode mudar não sustenta uma decisão registrada contra '
                       'ela.', v_rodada.nome));
  end if;

  -- --- cobertura: o N do Arquitetura do Sistema/2 Especificação/f0/06, por tipo core PRESENTE na rodada ---------------
  -- Tipo com zero documento não reprova a subida: o Arquitetura do Sistema/2 Especificação/f0/06 diz que tipo sem
  -- exemplo "permanece em N0/N1", e essa é uma afirmação sobre o TIPO, não sobre
  -- o estágio. Reprovar por ausência travaria toda subida para sempre, porque
  -- CONTRATO_SOCIAL rende 1 por mandato.
  select jsonb_agg(to_jsonb(c)), bool_and(c.atinge_minimo)
    into v_detalhe, v_n_min_ok
  from fn_golden_cobertura(p_rodada) c where c.n_documentos > 0;

  if v_detalhe is null then
    return jsonb_build_object('aplica', true, 'suficiente', false, 'criterio', to_jsonb(v_crit),
      'rodada', v_rodada.nome,
      'porque', 'A rodada não tem nenhum documento de tipo CORE com origem "real". Rotular o book '
                'sintético mede o instrumento, não o modelo — é a ressalva que o '
                'medir-auto-aceite.mts carrega no cabeçalho, e aqui ela é guarda.');
  end if;

  if not coalesce(v_n_min_ok, false) then
    v_falhas := v_falhas || jsonb_build_object('falha', 'n_minimo',
      'detalhe', format('Tipo core presente na rodada com menos de %s documentos rotulados. O tipo '
                        'mais fraco governa: o dial é por ESTÁGIO e o Arquitetura do Sistema/2 Especificação/f0/06 raciocina por TIPO, '
                        'então subir com um tipo fraco sobe autonomia sobre ele também.',
                        v_crit.n_minimo));
  end if;

  -- --- a métrica que governa este estágio -------------------------------------
  if v_crit.metrica = 'f1_classificacao' then
    -- `n_verdade > 0`: só tipo para o qual a rodada TEM verdade participa do
    -- "mais fraco governa". Um tipo que aparece apenas como falso-positivo da
    -- máquina tem F1 zero por construção (precisão 0, recall indefinido), e
    -- deixá-lo entrar daria poder de VETO a um único documento — pior, o mesmo
    -- erro seria contado duas vezes, porque o documento cuja verdade era X e que
    -- a máquina chamou de Y já é falso-negativo de X. O erro é contado uma vez,
    -- no tipo que tinha a verdade, que é onde ele tem denominador.
    select min(f1) into v_pior from fn_golden_classificacao(p_rodada) c
      join taxonomia_tipo_documento t on t.codigo = c.tipo
     where t.obrigatoriedade = 'obrigatorio' and c.f1 is not null and c.n_verdade > 0;

  elsif v_crit.metrica = 'acuracia_identificadores' then
    -- Aqui o "mais fraco" é o IDENTIFICADOR, não o tipo: a função mede tipo,
    -- período e entidade separadamente porque as causas de erro são distintas, e
    -- é a pior das três que diz o que o estágio entrega.
    select min(acuracia) into v_pior from fn_golden_identificadores(p_rodada)
     where acuracia is not null;

  elsif v_crit.metrica = 'acerto_campos' then
    select min(acerto) into v_pior from fn_golden_campos(p_rodada) c
      join taxonomia_tipo_documento t on t.codigo = c.tipo
     where t.obrigatoriedade = 'obrigatorio' and c.acerto is not null;

  elsif v_crit.metrica = 'nao_falso_positivo_classe_a' then
    -- A única que não sai da rodada: o rótulo dela é o veredito humano da 0106,
    -- produzido em produção. A rodada continua sendo exigida acima porque o N e o
    -- congelamento são o que datam a decisão.
    v_classe_a := fn_golden_classe_a();
    v_pior := (v_classe_a->>'nao_falso_positivo')::numeric;
    v_detalhe := jsonb_build_object('cobertura', v_detalhe, 'classe_a', v_classe_a);
    if (v_classe_a->>'com_veredito_humano')::int < v_crit.n_minimo then
      v_falhas := v_falhas || jsonb_build_object('falha', 'n_minimo_vereditos',
        'detalhe', format('%s veredito(s) humano(s) sobre divergência Classe A, contra o mínimo de '
                          '%s. Pendência que o próprio sistema resolveu não conta: ninguém disse '
                          'que ela procedia.',
                          v_classe_a->>'com_veredito_humano', v_crit.n_minimo));
    end if;

  else
    return jsonb_build_object('aplica', true, 'suficiente', false, 'criterio', to_jsonb(v_crit),
      'porque', format('Métrica "%s" não é calculada por nenhuma função desta migration. Critério '
                       'com métrica desconhecida RECUSA — aprovar por não saber medir é o oposto '
                       'do que a regra de ouro pede.', v_crit.metrica));
  end if;

  if v_pior is null then
    v_falhas := v_falhas || jsonb_build_object('falha', 'sem_medicao',
      'detalhe', 'A rodada existe e está congelada, mas a métrica deste estágio não pôde ser '
                 'calculada em nenhum tipo core — sem rótulo conferível não há concordância.');
  elsif v_pior < v_crit.concordancia_minima then
    v_falhas := v_falhas || jsonb_build_object('falha', 'concordancia',
      'detalhe', format('Pior caso medido %s, contra o mínimo de %s.',
                        v_pior, v_crit.concordancia_minima));
  end if;

  return jsonb_build_object(
    'aplica', true,
    'suficiente', jsonb_array_length(v_falhas) = 0,
    'estagio', p_estagio,
    'rodada', v_rodada.nome,
    'rodada_id', v_rodada.id,
    'congelada_em', v_rodada.congelada_em,
    'criterio', to_jsonb(v_crit),
    'metrica', v_crit.metrica,
    'pior_caso', v_pior,
    'detalhe', v_detalhe,
    'falhas', v_falhas
  );
end;
$$;

--
-- Name: FUNCTION fn_golden_suficiente(p_estagio text, p_rodada uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_golden_suficiente(p_estagio text, p_rodada uuid) IS 'A pergunta do laço de calibração do Arquitetura do Sistema/2 Especificação/f0/06 ("concordância alta e estável?"), respondida em número. O TIPO MAIS FRACO governa: o dial é por estágio e o Arquitetura do Sistema/2 Especificação/f0/06 raciocina por tipo, e autonomia por (estágio x tipo) não existe no schema — enquanto não existir, a leitura conservadora é a única honesta. Rodada não congelada não autoriza nada. Métrica desconhecida RECUSA.';

--
-- Name: fn_grupo_por_controle_comum(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_grupo_por_controle_comum(p_caso_id uuid) RETURNS TABLE(entidade_id uuid, razao_social text, grupo_id uuid)
    LANGUAGE sql STABLE
    AS $$
  with recursive par_direto as materialized (
    select ec1.entidade_id as a, ec2.entidade_id as b
      from entidade_controlador ec1
      join entidade_controlador ec2
        on ec2.controlador_id = ec1.controlador_id
       and ec2.entidade_id <> ec1.entidade_id
     where ec1.caso_id = p_caso_id
  ),
  alcance(entidade_id, alcancavel) as (
    select e.id, e.id
      from entidade e
     where e.caso_id = p_caso_id
       and exists (
         select 1 from entidade_controlador ec
          where ec.entidade_id = e.id and ec.caso_id = p_caso_id)
    union
    select al.entidade_id, pd.b
      from alcance al
      join par_direto pd on pd.a = al.alcancavel
  )
  select al.entidade_id, e.razao_social, min(al.alcancavel::text)::uuid as grupo_id
    from alcance al
    join entidade e on e.id = al.entidade_id
   group by al.entidade_id, e.razao_social
   order by min(al.alcancavel::text), e.razao_social;
$$;

--
-- Name: FUNCTION fn_grupo_por_controle_comum(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_grupo_por_controle_comum(p_caso_id uuid) IS '0182: agrupa as entidades do caso por CONTROLE COMUM, por FECHO TRANSITIVO — se A e B compartilham um controlador, e B e C compartilham outro, as três caem no mesmo grupo. `par_direto` (pares de um salto) é MATERIALIZED de propósito (evita reavaliação a cada iteração da recursão — mesma lição da 0152, ver comentário acima da função). `grupo_id` é o entidade_id alcançável de menor ordenação textual — representante arbitrário mas estável do componente conexo, não uma entidade "principal". Entidade sem controlador registrado não aparece na saída — ausência não afirma nada sobre grupo real algum (regra 7 do CLAUDE.md). A recursão termina pela DEDUPLICAÇÃO do `union` sobre um conjunto finito (entidade, alcançável) — sem contador de salto na tupla, que era justamente o que impedia a dedup de convergir na primeira versão (ver cabeçalho). É o consumidor mínimo que prova a fatia 1.7 do roadmap: "as 8 entidades do mandato real podem ser reconhecidas como um grupo".';

--
-- Name: fn_herdar_secao_pela_arvore(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_herdar_secao_pela_arvore(p_documento_versao_id uuid DEFAULT NULL::uuid, p_caso_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  c_rodadas constant int := 10;
  v_ids     uuid[] := '{}';
  v_novos   uuid[];
  v_conf    int := 0;
  v_lconf   int := 0;
  v_i       int := 0;
  v_linhas  int; v_versoes int; v_casos int;
begin
  loop
    v_i := v_i + 1;
    with e as materialized (
      select ce.id, ce.documento_versao_id, d.caso_id,
             nullif(btrim(ce.secao_canonica), '')          as sc,
             fn_nome_de_secao_normalizado(ce.chave)          as nc,
             fn_nome_de_secao_normalizado(ce.secao)          as ns,
             (ce.origem_valor = 'extracao' and ce.revisado_por is null) as alvo
        from campo_extraido ce
        join documento_versao dv on dv.id = ce.documento_versao_id
        join documento d on d.id = dv.documento_id
       where d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA', 'DRE')
         and (p_documento_versao_id is null or ce.documento_versao_id = p_documento_versao_id)
         and (p_caso_id is null or d.caso_id = p_caso_id)
    ), fonte as materialized (
      -- o PAI: a linha do documento cuja chave é o nome, e que tem seção
      select documento_versao_id, nc as nome, sc from e
       where sc is not null and nc is not null and not fn_nome_de_topo_ou_total(nc)
      union
      -- as IRMÃS: as outras linhas que estão sob a mesma seção bruta e têm seção
      select documento_versao_id, ns, sc from e
       where sc is not null and ns is not null and not fn_nome_de_topo_ou_total(ns)
    ), unica as materialized (
      select documento_versao_id, nome, min(sc) as sc, count(*) as n   -- (versão, nome, sc) já é distinto: n = nº de seções
        from fonte group by 1, 2
    ), upd as (
      update campo_extraido ce
         set secao_canonica = u.sc, secao_canonica_inferida = true
        from e join unica u on u.documento_versao_id = e.documento_versao_id and u.nome = e.ns
       where ce.id = e.id and e.alvo and e.sc is null and u.n = 1
      returning ce.id
    )
    select (select coalesce(array_agg(id), '{}') from upd),
           (select count(distinct (u.documento_versao_id, u.nome)) from unica u
             where u.n > 1 and exists (select 1 from e where e.documento_versao_id = u.documento_versao_id
                                         and e.ns = u.nome and e.alvo and e.sc is null)),
           (select count(*) from e join unica u on u.documento_versao_id = e.documento_versao_id and u.nome = e.ns
             where u.n > 1 and e.alvo and e.sc is null)
      into v_novos, v_conf, v_lconf;

    v_ids := v_ids || v_novos;
    exit when coalesce(array_length(v_novos, 1), 0) = 0 or v_i >= c_rodadas;
  end loop;

  select count(*), count(distinct ce.documento_versao_id), count(distinct d.caso_id)
    into v_linhas, v_versoes, v_casos
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
   where ce.id = any (v_ids);

  return jsonb_build_object('linhas', v_linhas, 'versoes', v_versoes, 'casos', v_casos,
                            'conflitos', v_conf, 'linhas_em_conflito', v_lconf, 'rodadas', v_i);
end $$;

--
-- Name: FUNCTION fn_herdar_secao_pela_arvore(p_documento_versao_id uuid, p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_herdar_secao_pela_arvore(p_documento_versao_id uuid, p_caso_id uuid) IS '0204: herda secao_canonica pela ÁRVORE do próprio documento. Para linha sem seção (extração, sem revisão humana) cuja seção bruta, normalizada, é a chave de outra linha da MESMA versão que tem seção (o pai) ou a seção bruta de outras que têm (as irmãs), herda — se todas concordam em UMA seção; conflito fica NULL e é contado. Recursivo (até 10 rodadas), nunca herda de/para topo ou total (ATIVO, TOTAL DO ATIVO…), só nos cinco tipos de demonstração. Marca secao_canonica_inferida. Idempotente. Devolve {linhas, versoes, casos, conflitos, linhas_em_conflito, rodadas}.';

--
-- Name: fn_indice_macro_anual(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_indice_macro_anual(p_desde_ano integer DEFAULT NULL::integer) RETURNS TABLE(serie text, ano integer, meses integer, retorno numeric, natureza text)
    LANGUAGE sql STABLE
    AS $$
  with preferida as (
    select distinct on (o.serie, o.data_ref)
      o.serie, o.data_ref, o.valor
    from indice_macro_obs o
    order by o.serie, o.data_ref,
      case o.fonte when 'IBGE/SIDRA' then 0 else 1 end
  ),
  -- Agrega uma vez por (serie, ano) e só então decide como o ano "rende",
  -- conforme a natureza da série. Pré-agregar (em vez de usar função de janela
  -- dentro de FILTER, que o Postgres recusa) mantém a intenção legível: para
  -- TAXA o ano é a composição dos meses; para NÍVEL é a variação entre o
  -- fechamento do ano anterior e o último fechamento do ano.
  por_ano as (
    select
      p.serie,
      extract(year from p.data_ref)::int as ano,
      count(*)::int                      as meses,
      (exp(sum(ln(1 + p.valor / 100.0))) - 1) * 100 as composto,
      max(p.data_ref)                    as ultima_data
    from preferida p
    where p_desde_ano is null or extract(year from p.data_ref)::int >= p_desde_ano
    group by p.serie, extract(year from p.data_ref)
  ),
  -- A BASE de cada ano para série de nível: a ÚLTIMA observação estritamente
  -- anterior ao ano. Vem de `preferida` inteira, não de `por_ano` — o filtro
  -- `p_desde_ano` corta o ano-base, e usar a série já filtrada faria o primeiro
  -- ano da janela pedida cair de novo no jan→dez. Ou seja: o recorte de leitura
  -- não pode mudar o número.
  base_anterior as (
    select
      a.serie,
      a.ano,
      (select p.valor
         from preferida p
        where p.serie = a.serie
          and p.data_ref < make_date(a.ano, 1, 1)
        order by p.data_ref desc
        limit 1) as valor
    from por_ano a
  )
  select
    a.serie,
    a.ano,
    a.meses,
    case s.natureza
      when 'taxa' then a.composto
      -- `nullif(ini.valor, 0)` continua: câmbio zero não existe, mas divisão
      -- por zero derrubaria a consulta inteira do export por causa de uma
      -- observação suja. E `ini.valor` NULL (primeiro ano da série) propaga
      -- NULL de propósito — ver o cabeçalho.
      else (fim.valor / nullif(ini.valor, 0) - 1) * 100
    end as retorno,
    s.natureza
  from por_ano a
  join indice_macro_serie s on s.codigo = a.serie
  left join base_anterior ini on ini.serie = a.serie and ini.ano = a.ano
  left join preferida fim on fim.serie = a.serie and fim.data_ref = a.ultima_data
  order by a.serie, a.ano;
$$;

--
-- Name: FUNCTION fn_indice_macro_anual(p_desde_ano integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_indice_macro_anual(p_desde_ano integer) IS 'Retorno acumulado por ano-calendário. Série de TAXA acumula por composição; série de NÍVEL varia entre FECHAMENTOS (dez do ano anterior → dez do ano), e o primeiro ano da série sai com retorno NULL por não ter base. `meses` revela ano incompleto — incluí-lo numa média de 3/5/10 anos como ano cheio distorce a média.';

--
-- Name: fn_inferir_secao_canonica_das_linhas(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_inferir_secao_canonica_das_linhas(p_caso_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_linhas int; v_versoes int; v_casos int;
begin
  with upd as (
    update campo_extraido ce
       set secao_canonica = x.s,
           secao_canonica_inferida = true
      from (select ce2.id, d.caso_id,
                   fn_secao_canonica_da_secao_bruta(ce2.secao, d.tipo_taxonomia) as s
              from campo_extraido ce2
              join documento_versao dv on dv.id = ce2.documento_versao_id
              join documento d on d.id = dv.documento_id
             where nullif(btrim(ce2.secao_canonica), '') is null
               and ce2.secao is not null
               and ce2.origem_valor = 'extracao'
               and ce2.revisado_por is null
               and (p_caso_id is null or d.caso_id = p_caso_id)) x
     where ce.id = x.id and x.s is not null
    returning ce.documento_versao_id, x.caso_id
  )
  select count(*), count(distinct documento_versao_id), count(distinct caso_id)
    into v_linhas, v_versoes, v_casos from upd;
  return jsonb_build_object('linhas', v_linhas, 'versoes', v_versoes, 'casos', v_casos);
end $$;

--
-- Name: FUNCTION fn_inferir_secao_canonica_das_linhas(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_inferir_secao_canonica_das_linhas(p_caso_id uuid) IS '0203: backfill de secao_canonica nas linhas extraídas que a IA deixou sem seção, a partir da seção bruta (fn_secao_canonica_da_secao_bruta). Marca secao_canonica_inferida. Ignora linha revisada ou transcrita por humano. Idempotente. NÃO recomputa reconciliação nem completude: depois dela, rodar fn_reconciliar_caso e fn_recomputar_completude nos casos afetados.';

--
-- Name: fn_instalacao_conferir(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_instalacao_conferir() RETURNS TABLE(chave text, migration text, tipo text, objeto text, presente boolean, detalhe text, porque text, severidade text)
    LANGUAGE plpgsql STABLE
    AS $$
declare
  r            instalacao_requisito;
  v_ok         boolean;
  v_det        text;
  v_n          bigint;
  v_alvo       regclass;
  v_crit       int;
  v_proc       regproc;
  v_src        text;
  v_tg_enabled "char";
  v_tg_fn      text;
begin
  for r in select * from instalacao_requisito order by ordem, chave loop
    v_ok  := false;
    v_det := null;

    if r.tipo = 'tabela' then
      v_ok := to_regclass('public.' || r.objeto) is not null;

    elsif r.tipo = 'funcao' then
      -- `to_regproc` falha quando a função tem sobrecargas ambíguas; o nome sem
      -- argumentos resolve pelo único candidato, e sobrecarga é sinal de que o
      -- requisito devia declarar a assinatura. Nenhum dos requisitos abaixo tem.
      begin
        v_ok := to_regproc('public.' || r.objeto) is not null;
      exception when others then
        -- Ambiguidade significa que EXISTE mais de uma — logo, existe.
        v_ok := true;
        v_det := 'mais de uma assinatura com este nome';
      end;

    elsif r.tipo = 'corpo' then
      -- 0147: o corpo PUBLICADO tem de conter o marcador.
      --
      -- Como todo ramo desta função, ele não pode derrubar a sonda: função
      -- ausente, nome ambíguo e marcador ausente são três respostas diferentes,
      -- e as três são `presente = false` com o detalhe dizendo QUAL — porque
      -- "aplique a migration" e "há duas assinaturas com este nome" pedem ações
      -- diferentes de quem está lendo a tela.
      begin
        v_proc := to_regproc('public.' || r.objeto);
      exception when others then
        v_proc := null;
        v_det  := 'mais de uma assinatura com este nome — o requisito precisa declarar os argumentos';
      end;

      if v_proc is null then
        v_ok  := false;
        v_det := coalesce(v_det, 'a função nem existe');
      else
        v_src := pg_get_functiondef(v_proc::oid);
        v_ok  := v_src is not null and position(r.marcador in v_src) > 0;
        v_det := case when v_ok then 'corpo com o marcador'
                      else 'a função existe, mas o corpo é ANTERIOR a esta migration' end;
      end if;

    elsif r.tipo = 'coluna' then
      -- 0132: `pg_attribute` em vez de `information_schema.columns` — mesma
      -- resposta, 14× mais barato (3,4 ms → 0,25 ms medidos). A view do
      -- information_schema junta várias tabelas de catálogo e filtra por
      -- privilégio linha a linha; aqui a pergunta é "existe esta coluna", e
      -- `attrelid` já vem resolvido por `to_regclass`.
      --
      -- `to_regclass` devolvendo NULL não é erro: significa que a TABELA não
      -- existe, e aí a coluna também não — `attrelid = null` não casa com nada e
      -- o `exists` dá false, que é a resposta certa. É a mesma proteção do ramo
      -- de seed abaixo, obtida de graça pela forma da consulta.
      v_ok := exists (
        select 1 from pg_attribute a
         where a.attrelid  = to_regclass('public.' || split_part(r.objeto, '.', 1))
           and a.attname   = split_part(r.objeto, '.', 2)
           and a.attnum    > 0
           and not a.attisdropped);

    elsif r.tipo = 'gatilho' then
      -- 0189: gatilho é catalogado POR SI, não pela função que ele chama.
      --
      -- POR QUE ISTO NÃO CABE NO TIPO `funcao`. A função de um gatilho
      -- SOBREVIVE a `drop trigger` e a `alter table ... disable trigger` — o
      -- exemplo já estava no catálogo antes deste tipo existir, em
      -- `gatilho_da_promocao` (0137): a função `fn_trg_auto_promover_dial`
      -- existe e nada garante que algo a chame. `objeto` aqui é
      -- `tabela.nome_do_gatilho`; a tabela é resolvida primeiro, como em todo
      -- ramo desta função — tabela ausente nunca pode virar exceção que
      -- derruba a sonda inteira.
      v_alvo := to_regclass('public.' || split_part(r.objeto, '.', 1));
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        select tgenabled, tgfoid::regproc::text
          into v_tg_enabled, v_tg_fn
          from pg_trigger
         where tgrelid = v_alvo
           and tgname  = split_part(r.objeto, '.', 2)
           and not tgisinternal;

        if v_tg_enabled is null then
          v_ok  := false;
          v_det := 'o gatilho não existe na tabela (a função dele pode existir — ela sobrevive ao drop trigger)';
        elsif v_tg_enabled = 'D' then
          v_ok  := false;
          v_det := 'o gatilho existe mas está DESABILITADO (disable trigger) — a guarda não roda';
        elsif v_tg_enabled = 'R' then
          -- 'R' = ENABLE REPLICA TRIGGER. Decisão deliberada, e mais estrita
          -- que `<> 'D'`: um gatilho em modo réplica NÃO dispara com
          -- `session_replication_role = origin`, que é o padrão de toda sessão
          -- normal (é o que o pooler do Supabase usa). Do ponto de vista de
          -- quem depende da guarda rodando na sessão normal, um gatilho em
          -- modo réplica está tão desligado quanto um desabilitado — só que
          -- calado, porque `tgenabled <> 'D'` deixaria passar.
          v_ok  := false;
          v_det := 'o gatilho existe mas só dispara em modo réplica — na sessão normal a guarda não roda';
        elsif v_tg_enabled in ('O', 'A') then
          -- 'O' = ENABLE (origin, o padrão) · 'A' = ENABLE ALWAYS (dispara em
          -- origin e em réplica). As duas rodam em sessão normal — é só isso
          -- que este ramo promete. Ele NÃO confere se o gatilho chama a
          -- função certa nem em quais eventos (INSERT/UPDATE/DELETE) — só que
          -- existe e dispara. `v_tg_fn` entra no detalhe por informação, sem
          -- afetar `v_ok`.
          v_ok  := true;
          v_det := format('gatilho habilitado (chama %s)', coalesce(v_tg_fn, '?'));
        else
          -- Não deveria acontecer — `tgenabled` só tem estes quatro valores —
          -- mas a sonda nunca assume "presente" por omissão de um `case`.
          v_ok  := false;
          v_det := format('estado de gatilho desconhecido: %s', v_tg_enabled);
        end if;
      end if;

    elsif r.tipo in ('seed', 'comportamento') then
      -- A tabela pode não existir ainda: contar nela levantaria erro e derrubaria
      -- a sonda inteira, transformando "um requisito faltando" em "o painel não
      -- abre". A sonda de instalação é o último lugar do sistema que pode falhar
      -- por causa do que ela existe para medir.
      v_alvo := to_regclass('public.' || r.objeto);
      if v_alvo is null then
        v_ok  := false;
        v_det := 'a tabela nem existe';
      else
        -- 0132: CONTAGEM LIMITADA AO CRITÉRIO. Ver o cabeçalho: a pergunta é
        -- ">= criterio", e varrer a tabela inteira para respondê-la faz o custo
        -- do painel crescer junto com `lote_execucao`, que cresce para sempre.
        v_crit := greatest(coalesce(r.criterio_seed, 1), 1);
        execute format('select count(*) from (select 1 from public.%I limit %s) x',
                       r.objeto, v_crit)
           into v_n;
        v_ok := v_n >= v_crit;
        -- No caso PRESENTE o total exato não é conhecido (nem usado pela tela).
        -- No caso AUSENTE ele é exato por construção — a varredura parou antes do
        -- limite, logo passou por tudo — e é nele que o número informa algo:
        -- "3 linha(s)" com critério 8 diz que o seed rodou pela metade.
        v_det := case when v_ok then format('%s linha(s) ou mais', v_crit)
                      else format('%s linha(s)', v_n) end;
      end if;
    end if;

    return query select r.chave, r.migration, r.tipo, r.objeto, v_ok, v_det,
                        r.porque, r.severidade;
  end loop;
end;
$$;

--
-- Name: FUNCTION fn_instalacao_conferir(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_instalacao_conferir() IS 'Confere cada requisito de instalacao_requisito contra o catálogo do banco. Sobrevive ao objeto ausente (to_regclass/to_regproc devolvem NULL em vez de erro): a sonda não pode falhar por causa do que ela existe para medir. Desde a 0147 confere também o CORPO da função (tipo=corpo), que é o único jeito de distinguir uma correção aplicada de uma função homônima com o corpo velho. Desde a 0189 confere também GATILHO (tipo=gatilho): existência na tabela E tgenabled em (''O'',''A'') — a função do gatilho sobrevive a drop trigger/disable trigger e por isso NUNCA prova, sozinha, que a guarda está ligada.';

--
-- Name: fn_instalacao_resumo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_instalacao_resumo() RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  with c as (select * from fn_instalacao_conferir())
  select jsonb_build_object(
    'total',        (select count(*) from c),
    'presentes',    (select count(*) from c where presente),
    'ausentes',     (select count(*) from c where not presente),
    'bloqueantes_ausentes',
                    (select count(*) from c where not presente and severidade = 'bloqueante'),
    'completa',     (select not exists (select 1 from c where not presente)),
    'faltando',     coalesce((select jsonb_agg(jsonb_build_object(
                       'chave', chave, 'migration', migration, 'porque', porque,
                       'severidade', severidade) order by severidade, chave)
                     from c where not presente), '[]'::jsonb));
$$;

--
-- Name: FUNCTION fn_instalacao_resumo(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_instalacao_resumo() IS 'O veredito de uma linha sobre a instalação, para o painel. "completa" só é true quando NENHUM requisito falta — inclusive os informativos, porque um requisito que não vale a pena conferir não devia estar no catálogo.';

--
-- Name: fn_lado_do_mutuo(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_lado_do_mutuo(p_chave text, p_secao_canonica text DEFAULT NULL::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select case
    -- A seção canônica é o sinal FORTE: ela vem da classificação contábil da
    -- linha, não da grafia do rótulo.
    when p_secao_canonica like 'ativo%'   then 'ativo'
    when p_secao_canonica like 'passivo%' then 'passivo'
    -- Sem seção, o rótulo. "a pagar" antes de "a receber" de propósito: o
    -- rótulo composto ("Mútuos a pagar para controladas a receber de terceiros")
    -- é raro, mas quando aparece o lado que manda é o do começo — e a ordem
    -- aqui é o que decide. Empate real devolve null, e null PARA a checagem.
    when fn_normalizar_texto(p_chave) ~ '(a pagar|tomado|passivo|devedor|obrigac)' then 'passivo'
    when fn_normalizar_texto(p_chave) ~ '(a receber|concedid|ativo|credor|direito)' then 'ativo'
    else null
  end;
$$;

--
-- Name: FUNCTION fn_lado_do_mutuo(p_chave text, p_secao_canonica text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_lado_do_mutuo(p_chave text, p_secao_canonica text) IS 'Lado contábil de uma linha de mútuo: ativo (emprestou) | passivo (tomou) | null (o documento não diz). Usada pela reconciliação de mútuos, que compara lado a lado — somar os dois juntos acusa divergência que não existe.';

--
-- Name: fn_lado_intragrupo(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_lado_intragrupo(p_chave text, p_secao_canonica text DEFAULT NULL::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select case
    when p_secao_canonica like 'ativo%'   then 'ativo'
    when p_secao_canonica like 'passivo%' then 'passivo'
    -- Sem seção canônica, cai no critério da 0117 sobre o rótulo.
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'a receber|a recuperar|credito' then 'ativo'
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'a pagar|fornecedor|obrigac' then 'passivo'
    else null
  end;
$$;

--
-- Name: FUNCTION fn_lado_intragrupo(p_chave text, p_secao_canonica text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_lado_intragrupo(p_chave text, p_secao_canonica text) IS '0124: crédito (ativo) ou obrigação (passivo) de uma linha intragrupo. Seção canônica primeiro; rótulo só como desempate, porque "Fornecedores intragrupo - X" não diz "a pagar".';

--
-- Name: fn_linha_vale_para_ano(uuid, text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_linha_vale_para_ano(p_versao uuid, p_periodo_coluna text, p_periodo_tipo text, p_periodo_ref text, p_ano integer) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
declare
  v_col text;
begin
  if p_ano is null then
    return true;
  end if;

  v_col := fn_coluna_periodo_do_ano(p_versao, p_ano);

  if v_col is not null then
    -- Documento com coluna de período: só a coluna DESTE ano vale — inclusive
    -- quando `v_col` é a sentinela `E'\x01'` (nenhuma coluna é deste ano):
    -- nenhuma `periodo_coluna` normaliza para o byte sentinela, então o
    -- `=` abaixo nunca casa, e a linha corretamente não vale para o ano.
    return fn_normalizar_texto(p_periodo_coluna) = fn_normalizar_texto(v_col);
  end if;

  -- Sem coluna de período nenhuma (retrato/anual de um ano só): vale só
  -- quando o PERÍODO DO PRÓPRIO DOCUMENTO ancora este ano, ou não ancora ano
  -- nenhum (undecidable, passa — comportamento de sempre para este caso).
  return p_periodo_tipo is null
      or cardinality(coalesce(fn_anos_periodo(p_periodo_tipo, p_periodo_ref), '{}'::int[])) = 0
      or p_ano = any(fn_anos_periodo(p_periodo_tipo, p_periodo_ref));
end;
$$;

--
-- Name: FUNCTION fn_linha_vale_para_ano(p_versao uuid, p_periodo_coluna text, p_periodo_tipo text, p_periodo_ref text, p_ano integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_linha_vale_para_ano(p_versao uuid, p_periodo_coluna text, p_periodo_tipo text, p_periodo_ref text, p_ano integer) IS '0195: uma linha (versão do documento, sua periodo_coluna, e o período PRÓPRIO do documento) vale para o ano pedido? Fatorada da lógica que a 0194 escreveu duas vezes dentro de fn_reconciliar_mutuos — documento sem coluna de período só conta para o ano que o SEU período ancora, nunca para qualquer ano perguntado.';

--
-- Name: fn_linhas_do_realizado(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_linhas_do_realizado(p_caso_id uuid, p_entidade text DEFAULT NULL::text) RETURNS TABLE(secao_canonica text, rotulo_norm text, chave text, entidade text, exercicio integer, valor numeric, papel text, documentos text[])
    LANGUAGE sql STABLE
    AS $$
  -- marca-0150
  -- marca-0151
  -- marca-0201
  --
  -- A MARCA FICA, e o motivo é o mesmo da 0102: a sonda de instalação confere se
  -- a correção está APLICADA NO BANCO procurando `0150` no corpo desta função —
  -- é o que separa "mergeado" de "aplicado". Uma reemissão futura mantém a
  -- marca; trocá-la apagaria a resposta da pergunta que ela faz.
  with bruto as materialized (
    select
      ce.secao_canonica,
      ce.chave,
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      -- 0146: a capa só responde quando o documento é de UMA empresa.
      coalesce(ce.entidade_coluna,
               case when (select count(distinct ce2.entidade_coluna)
                            from campo_extraido ce2
                           where ce2.documento_versao_id = ce.documento_versao_id
                             and ce2.entidade_coluna is not null) > 1
                    then null else e.razao_social end) as entidade,
      -- 0201: a coluna que NOMEIA um saldo ("Saldo Final", "Saldo atual", "Saldo Inicial", "Saldo
      -- anterior") não traz ano e herda o da referência do documento; a de ABERTURA é o ano - 1.
      -- Coluna com ano no texto segue lendo o texto; coluna sem ano e sem nome de saldo ("Saldo",
      -- "Valor", "Ticket médio") segue SEM exercício — e portanto fora (0150).
      case when fn_coluna_e_saldo(ce.periodo_coluna)
           then fn_ano_da_coluna(ce.periodo_coluna, p.referencia)
                - (case when fn_coluna_e_abertura(ce.periodo_coluna) then 1 else 0 end)
           else fn_exercicio_da_coluna(ce.periodo_coluna)
      end as exercicio,
      fn_coluna_e_abertura(ce.periodo_coluna) as abertura,
      fn_periodo_e_parcial(ce.periodo_coluna, d.tipo_taxonomia, p.tipo, p.referencia) as parcial,
      fn_familia_da_secao(ce.secao_canonica) as familia,
      ce.valor_num,
      ce.unidade,
      d.tipo_taxonomia,
      dv.documento_id,
      aut.autoridade
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join periodo p on p.id = d.periodo_id
    left join entidade e on e.id = d.entidade_id
    left join taxonomia_tipo_documento t on t.codigo = d.tipo_taxonomia
    cross join lateral fn_autoridade_do_documento(d.id) aut
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and dv.id = fn_versao_com_extracao(d.id)
      -- A ABERTURA ANALÍTICA NÃO SOMA. Tipo desconhecido (fora do catálogo)
      -- entra somando: o padrão seguro é o de sempre, e o catálogo é quem
      -- declara a exceção.
      and coalesce(t.abertura_analitica, false) = false
      -- 0201 (d): a mesma exclusão da série por ano. (O movimento, 0199 a, não precisa de filtro AQUI:
      -- "Débito"/"Crédito" não trazem ano nem nome de saldo, então `exercicio` já é NULL e a linha
      -- cai em `filtrado`. MEDIDO: tirar o filtro explícito não reprova nenhum assert, por isso ele
      -- não foi escrito — código sem efeito medível é o que a regra 2 proíbe.)
      and coalesce(t.categoria, '') not in ('Societário/Legal', 'Garantias/Sócios')
  ),
  filtrado as (
    select b.*,
           fn_normalizar_texto(coalesce(b.entidade, '')) as entidade_chave
    from bruto b
    where b.exercicio is not null
      and (p_entidade is null
           or fn_normalizar_texto(b.entidade) = fn_normalizar_texto(p_entidade))
  ),
  -- 0201 (c'): o período PARCIAL só entra no exercício em que a entidade não tem anual da mesma
  -- família — a decisão é do ANO, como na 0200.
  elegivel as (
    select f.*,
           bool_or(not coalesce(f.parcial, false))
             over (partition by f.entidade_chave, f.familia, f.exercicio) as ano_tem_anual
    from filtrado f
  ),
  papel_do_rotulo as (
    select distinct chave, tipo_taxonomia, unidade,
           fn_papel_linha(chave, tipo_taxonomia, unidade) as papel
    from (select distinct chave, tipo_taxonomia, unidade from elegivel
           where not (coalesce(parcial, false) and ano_tem_anual)) d
  ),
  com_papel as (
    select f.*, p.papel
    from elegivel f
    join papel_do_rotulo p
      on p.chave = f.chave
     and p.tipo_taxonomia is not distinct from f.tipo_taxonomia
     and p.unidade is not distinct from f.unidade
    where not (coalesce(f.parcial, false) and f.ano_tem_anual)
  ),
  agrupado as (
    select
      c.secao_canonica,
      c.rotulo_norm,
      (array_agg(c.chave order by length(c.chave)))[1] as chave,
      max(c.entidade) as entidade,
      c.exercicio,
      -- 0201: o FECHAMENTO vence a abertura do mesmo exercício (a abertura é o eco dele no ano
      -- seguinte), antes da autoridade e do módulo.
      --
      -- 0151: O DESEMPATE ENTRE DOCUMENTOS, QUE ERA SILENCIOSO.
      --
      -- Dentro do MESMO exercício, a mesma conta pode vir de dois documentos (o
      -- balanço e a DF auditada dizem a mesma coisa). Quando eles CONCORDAM, a
      -- escolha é indiferente. Quando discordam, a regra da 0042 — o de maior
      -- módulo — vira "fica com o maior", que num caso de reestruturação
      -- escolhe sempre o número que infla o ativo.
      --
      -- A AUTORIDADE DOCUMENTAL DECIDE PRIMEIRO, e o maior módulo fica como
      -- último recurso: no EMPATE de autoridade o valor não muda, é o mesmo de
      -- antes desta migration. Trocar o número no empate seria substituir uma
      -- regra silenciosa por outra — e quem avisa que houve empate é
      -- `fn_reconciliar_versoes_do_periodo`, com o número perdedor à vista.
      (array_agg(c.valor_num
                 order by c.abertura, c.autoridade desc, abs(c.valor_num) desc nulls last))[1] as valor,
      (array_agg(c.papel order by fn_papel_prioridade(c.papel)))[1] as papel,
      array_agg(distinct c.tipo_taxonomia) as documentos,
      -- Quantos documentos DISTINTOS trouxeram esta linha neste exercício: é o
      -- que o item 4 usa para saber se o total veio acompanhado das componentes.
      array_agg(distinct c.documento_id) as docs_ids
    from com_papel c
    group by c.secao_canonica, c.rotulo_norm, c.exercicio
  ),
  -- ---------------------------------------------------------------------------
  -- 4. O TOTAL QUE VEIO COM AS COMPONENTES É SUBTOTAL, MESMO SEM ESTAR NA LISTA
  -- ---------------------------------------------------------------------------
  --
  -- A `0116` deixou o topo da DRE fora da lista fechada de subtotais porque num
  -- documento RESUMIDO ele é a conta. O discriminador que faltava é estrutural e
  -- só existe olhando o documento inteiro: se o módulo desta linha bate com a
  -- SOMA das outras contas da mesma seção, mesmo exercício e mesma entidade, ela
  -- é o total delas — e somar os dois conta duas vezes.
  --
  -- A tolerância é de 1% e existe porque a soma de valores arredondados ao
  -- milhar não fecha ao centavo: medido no Canastra, 177.077 contra 177.133
  -- (0,03%). Sem folga, o discriminador não dispararia exatamente no caso que o
  -- motivou.
  -- O SINAL SEPARA AS DUAS FAMÍLIAS QUE MORAM NA MESMA SEÇÃO. Medido no Canastra
  -- 2025: `receita_bruta` guarda as receitas (positivas) E as deduções
  -- (negativas), e cada família tem o próprio total impresso —
  -- "Receita operacional bruta" 188.000 e "(-) Deduções da receita bruta"
  -- 48.128. Somando a seção inteira, nenhum dos dois bate com o dobro de si
  -- mesmo, e o discriminador não dispara para nenhum: a receita ficaria certa e
  -- a dedução contaria duas vezes. Agrupando por sinal, os dois batem — 188.000
  -- contra as quatro linhas de venda, 48.128 contra ICMS, PIS/COFINS e
  -- devoluções.
  soma_das_contas as (
    select a.secao_canonica, a.exercicio, a.entidade, sign(a.valor) as sinal,
           sum(abs(a.valor)) filter (where a.papel = 'conta') as total_contas
    from agrupado a
    group by a.secao_canonica, a.exercicio, a.entidade, sign(a.valor)
  )
  select
    a.secao_canonica,
    a.rotulo_norm,
    a.chave,
    a.entidade,
    a.exercicio,
    a.valor,
    case
      when a.papel = 'conta'
       and s.total_contas is not null
       and abs(a.valor) > 0
       -- `2 × |valor|` porque o próprio valor está DENTRO de `total_contas`:
       -- o total mais as componentes dá duas vezes o total. É a mesma
       -- aritmética que a 0143 usa para declarar hierarquia achatada.
       and abs(s.total_contas - 2 * abs(a.valor)) <= 0.01 * abs(a.valor)
      then 'subtotal'
      else a.papel
    end as papel,
    a.documentos
  from agrupado a
  left join soma_das_contas s
    on s.secao_canonica is not distinct from a.secao_canonica
   and s.exercicio = a.exercicio
   and s.entidade is not distinct from a.entidade
   and s.sinal = sign(a.valor)
$$;

--
-- Name: FUNCTION fn_linhas_do_realizado(p_caso_id uuid, p_entidade text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_linhas_do_realizado(p_caso_id uuid, p_entidade text) IS 'As linhas do caso POR EXERCÍCIO, de uma entidade, sem o que não se soma (0150): fora a abertura analítica (balancete, aging, estoque, extrato — elas reabrem contas que a demonstração já declara), fora o combinado (soma das empresas), fora a coluna que não nomeia exercício, e com o total que veio acompanhado das próprias componentes marcado `subtotal`. 0201: lê também o documento anual de "Saldo Final"/"Saldo atual" (ano da referência) e "Saldo Inicial"/"Saldo anterior" (ano - 1, atrás do fechamento), sem movimento, sem Societário/Legal, e com o período parcial só no exercício sem anual da mesma família — as mesmas contas de fn_valores_por_ano. É a base das premissas do realizado e da média histórica; a LISTA da tela continua saindo de fn_linhas_para_modelagem, que agrupa por rótulo.';

--
-- Name: fn_linhas_do_tipo(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_linhas_do_tipo(p_caso_id uuid, p_codigo text) RETURNS bigint
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  select count(ce.id)
  from documento d
  join documento_versao dv on dv.documento_id = d.id
  join campo_extraido ce on ce.documento_versao_id = dv.id
  where d.caso_id = p_caso_id
    and d.tipo_taxonomia = p_codigo
    and dv.id = fn_versao_com_extracao(d.id);
$$;

--
-- Name: FUNCTION fn_linhas_do_tipo(p_caso_id uuid, p_codigo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_linhas_do_tipo(p_caso_id uuid, p_codigo text) IS 'Quantas linhas extraídas o caso tem de um tipo de documento (insumo da completude, 0036). 0102: só a versão vigente — reextração dobrava a contagem e inflava a completude.';

--
-- Name: fn_linhas_para_modelagem(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_linhas_para_modelagem(p_caso_id uuid) RETURNS TABLE(secao_canonica text, chave text, rotulo_norm text, entidade text, valor_ultimo numeric, n_ocorrencias bigint, papel text, unidade text, moeda text, documentos text[], sobreposicao_suspeita boolean)
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  -- marca-0103
  -- marca-0164
  --
  -- AS TRÊS MARCAS FICAM. `fn_diagnostico_modelagem` (0102) confere se a
  -- correção daquela migration está instalada procurando `marca-0102` no
  -- corpo — é o teste que separa "mergeado" de "aplicado". Trocar a marca
  -- apagaria a resposta; a 0164 reemite o corpo e MANTÉM a regra da 0102
  -- ("só a versão vigente"), só muda COMO ela é expressa (join, não filtro
  -- opaco) — então as três marcas continuam verdadeiras.
  with docs_do_caso as (
    select d.id as documento_id, d.tipo_taxonomia, d.entidade_id
    from documento d
    where d.caso_id = p_caso_id
  ),
  -- 0164: A VERSÃO VIGENTE COMO JOIN, NÃO COMO FILTRO OPACO.
  --
  -- Mesma regra da 0102 ("a de maior n_versao que TEM campo_extraido"), mas
  -- como uma CTE nomeada que o planner enxerga e estima — em vez de um
  -- filtro `dv.id = fn_versao_com_extracao(d.id)` por linha, cuja
  -- seletividade o Postgres não sabe estimar (função opaca) e por isso
  -- chutava rows=1 para toda CTE construída em cima de `bruto`, mesmo a
  -- 7.220 linhas reais — a causa medida do Nested Loop que estourava os 8s
  -- do Supabase no caso "Teste 00" (190 documentos). Ver o cabeçalho.
  versao_vigente as (
    select distinct on (dv.documento_id)
           dv.documento_id, dv.id as documento_versao_id
    from documento_versao dv
    join docs_do_caso dc on dc.documento_id = dv.documento_id
    where exists (select 1 from campo_extraido ce where ce.documento_versao_id = dv.id)
    order by dv.documento_id, dv.n_versao desc
  ),
  bruto as (
    select
      ce.secao_canonica,
      ce.chave,
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      coalesce(ce.entidade_coluna, e.razao_social) as entidade,
      ce.valor_num,
      ce.unidade,
      ce.moeda,
      dc.tipo_taxonomia
    from versao_vigente vv
    join docs_do_caso dc on dc.documento_id = vv.documento_id
    join campo_extraido ce on ce.documento_versao_id = vv.documento_versao_id
    left join entidade e on e.id = dc.entidade_id
    where ce.valor_num is not null
  ),
  -- O PAPEL É PROPRIEDADE DO RÓTULO, NÃO DA OCORRÊNCIA (0101).
  --
  -- `fn_papel_linha` depende só de (chave, tipo do documento, unidade) e custa
  -- ~1,6 ms por chamada. Avaliá-la por ocorrência era pagar 760 vezes por uma
  -- resposta que tem ~250 valores distintos. Aqui ela roda uma vez por combinação
  -- distinta e o resultado volta por join — é a mesma resposta, porque a função é
  -- `immutable`.
  papel_do_rotulo as (
    select distinct chave, tipo_taxonomia, unidade,
           fn_papel_linha(chave, tipo_taxonomia, unidade) as papel
    from (select distinct chave, tipo_taxonomia, unidade from bruto) d
  ),
  ocorrencia as (
    select b.*, p.papel
    from bruto b
    join papel_do_rotulo p
      on p.chave = b.chave
     and p.tipo_taxonomia is not distinct from b.tipo_taxonomia
     and p.unidade is not distinct from b.unidade
  ),
  base as (
    select
      o.secao_canonica,
      (array_agg(o.chave order by length(o.chave)))[1] as chave,
      o.rotulo_norm,
      max(o.entidade) as entidade,
      -- valor da ocorrência de MAIOR MÓDULO, COM O SINAL (0042). 0164: em
      -- empate de módulo (duas ocorrências, sinais opostos), o desempate
      -- passa a ser DECLARADO (prefere o positivo) em vez de depender da
      -- ordem física em que o plano entrega as linhas — ver o cabeçalho
      -- desta migration para a divergência que expôs a ambiguidade latente.
      (array_agg(o.valor_num order by abs(o.valor_num) desc nulls last, o.valor_num desc))[1] as valor_ultimo,
      count(*) as n_ocorrencias,
      max(o.unidade) as unidade,
      max(o.moeda) as moeda,
      array_agg(distinct o.tipo_taxonomia) as documentos,
      -- papel da ocorrência de MAIOR PRIORIDADE (fn_papel_prioridade): no empate
      -- entre documentos, o lado seguro é não projetar.
      (array_agg(o.papel order by fn_papel_prioridade(o.papel)))[1] as papel
    from ocorrencia o
    group by o.secao_canonica, o.rotulo_norm
  ),
  -- SOBREPOSIÇÃO SUSPEITA, por join (0101). Mesma regra da 0042: outra linha da
  -- MESMA seção, MESMO valor, e um rótulo descrevendo o outro de forma mais
  -- grossa (`Provisões` × `Provisão para passivo a descoberto de controlada`).
  -- A função não escolhe por ninguém: MARCA, e quem decide é o analista.
  -- 0103: os radicais viram coluna calculada UMA vez por linha lógica, e a
  -- contenção vira o operador `<@`. Antes `fn_rotulo_contido` era avaliada por
  -- PAR de linhas e re-tokenizava OS DOIS rótulos a cada par — com muitas
  -- colisões de valor, milhares de tokenizações dos mesmos poucos rótulos.
  base_r as (
    select b.*,
           fn_radicais_rotulo(b.chave) as radicais,
           fn_tem_palavra_longa(b.chave) as tem_longa
    from base b
  ),
  pares as (
    select b.secao_canonica, b.rotulo_norm as r1, o.rotulo_norm as r2
    from base_r b
    join base_r o
      on coalesce(o.secao_canonica, '') = coalesce(b.secao_canonica, '')
     and o.valor_ultimo = b.valor_ultimo
     -- cada par NÃO ORDENADO uma vez só (antes: duas, uma em cada direção)
     and b.rotulo_norm < o.rotulo_norm
    where b.papel = 'conta' and o.papel = 'conta'
      and ((b.tem_longa and b.radicais <@ o.radicais)
        or (o.tem_longa and o.radicais <@ b.radicais))
  ),
  sobrepostas as (
    select secao_canonica, r1 as rotulo_norm from pares
    union
    select secao_canonica, r2 from pares
  )
  select b.secao_canonica, b.chave, b.rotulo_norm, b.entidade, b.valor_ultimo,
         b.n_ocorrencias, b.papel, b.unidade, b.moeda, b.documentos,
         (s.rotulo_norm is not null) as sobreposicao_suspeita
  from base_r b
  left join sobrepostas s
    on s.rotulo_norm = b.rotulo_norm
   and coalesce(s.secao_canonica, '') = coalesce(b.secao_canonica, '')
  order by b.secao_canonica nulls last, b.rotulo_norm;
$$;

--
-- Name: FUNCTION fn_linhas_para_modelagem(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_linhas_para_modelagem(p_caso_id uuid) IS 'Linhas lógicas do caso para a tela de Modelagem, com PAPEL (conta/subtotal/derivado/serie_mensal), valor COM SINAL, unidade/moeda, documentos de origem e marca de sobreposição. Existe como função porque campo_extraido não tem caso_id — o escopo por caso mora aqui. 0101: papel calculado uma vez por rótulo e sobreposição por join, para caber no statement_timeout. 0102: só a versão VIGENTE de cada documento (reextração deixava a versão superada somando ocorrência e podendo ditar o valor_ultimo). 0164: a versão vigente passa a ser um JOIN nomeado (CTE versao_vigente), não um filtro por função opaca — o filtro antigo (dv.id = fn_versao_com_extracao(d.id)) fazia o planner estimar rows=1 para dezenas de milhares de linhas reais, escolhendo Nested Loop onde deveria escolher Hash Join (medido: 15,0s → 2,6s num fixture de 190 documentos/800 rótulos). Resultado idêntico ao anterior — comparado linha a linha, com except nos dois sentidos, contra 78 casos.';

--
-- Name: fn_linhas_para_transcrever(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_linhas_para_transcrever(p_documento_id uuid) RETURNS TABLE(conceito text, rotulo text, descricao text, secao_canonica text, checagem text, severidade text)
    LANGUAGE sql STABLE
    AS $$
  select le.conceito, le.rotulo, le.descricao, le.secao_canonica, le.checagem,
         coalesce(le.severidade, 'importante')
  from documento d
  join taxonomia_linha_exigida le on le.tipo_taxonomia = d.tipo_taxonomia
  where d.id = p_documento_id and le.ativo
  order by coalesce(le.severidade, 'importante'), le.conceito;
$$;

--
-- Name: FUNCTION fn_linhas_para_transcrever(p_documento_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_linhas_para_transcrever(p_documento_id uuid) IS 'As linhas que o Portão 1 vai COBRAR deste tipo de documento, para a planilha de transcrição listá-las. São poucas de propósito: taxonomia_linha_exigida é o MÍNIMO exigido, não um gabarito de demonstração — planilha que fingisse listar todas as contas de um balanço estaria inventando a estrutura do documento do cliente. O resto vai em linha livre.';

--
-- Name: fn_marcar_falha_vista(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_marcar_falha_vista(p_falha_id uuid, p_autor text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
begin
  update execucao_falha set visto_em = now(), visto_por = p_autor
   where id = p_falha_id and visto_em is null;
  return jsonb_build_object('ok', found);
end;
$$;

--
-- Name: fn_mes_do_rotulo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_mes_do_rotulo(p_chave text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
  with palavras as (
    select unnest(regexp_split_to_array(
      regexp_replace(fn_normalizar_texto(p_chave), '[^a-z0-9]+', ' ', 'g'), '\s+')) as w
  )
  select min(m.mes) from palavras p
  join (values
    ('jan',1),('janeiro',1),   ('fev',2),('fevereiro',2),
    ('mar',3),('marco',3),     ('abr',4),('abril',4),
    ('mai',5),('maio',5),      ('jun',6),('junho',6),
    ('jul',7),('julho',7),     ('ago',8),('agosto',8),
    ('set',9),('setembro',9),  ('out',10),('outubro',10),
    ('nov',11),('novembro',11),('dez',12),('dezembro',12)
  ) as m(nome, mes) on m.nome = p.w;
$$;

--
-- Name: FUNCTION fn_mes_do_rotulo(p_chave text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_mes_do_rotulo(p_chave text) IS 'Mês que o rótulo nomeia (1-12) ou null. Palavra inteira contra lista fechada, em qualquer posição: left(chave,3) reprovava "Faturamento Janeiro" (rótulo real da extração do v35) e um LIKE aprovaria "Marcas e patentes".';

--
-- Name: fn_mesma_entidade(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_mesma_entidade(p_a text, p_b text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
  a text := fn_entidade_canonica(p_a);
  b text := fn_entidade_canonica(p_b);
  curto text[]; longo text[];
  i int; j int; achou boolean;
begin
  if a is null or b is null then return false; end if;
  if a = b then return true; end if;

  if length(a) <= length(b) then
    curto := string_to_array(a, ' '); longo := string_to_array(b, ' ');
  else
    curto := string_to_array(b, ' '); longo := string_to_array(a, ' ');
  end if;

  -- Token significativo no lado curto (4+ chars). "vt logistica" passa por
  -- 'logistica'; um apelido "ab" não passa, e é isso que se quer.
  if not exists (select 1 from unnest(curto) t where length(t) >= 4) then
    return false;
  end if;

  j := 1;
  for i in 1 .. array_length(curto, 1) loop
    achou := false;
    while j <= array_length(longo, 1) loop
      if longo[j] like curto[i] || '%' then
        achou := true; j := j + 1; exit;
      end if;
      j := j + 1;
    end loop;
    if not achou then return false; end if;
  end loop;
  return true;
end;
$$;

--
-- Name: FUNCTION fn_mesma_entidade(p_a text, p_b text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_mesma_entidade(p_a text, p_b text) IS 'Dois nomes são a mesma entidade? Igualdade canônica ou tokens do nome curto como prefixo dos do longo, em ordem (mesmo critério de consolidarNomesDeEntidade no portal).';

--
-- Name: fn_min_motivo_rejeicao(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_min_motivo_rejeicao() RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$ select 15; $$;

--
-- Name: FUNCTION fn_min_motivo_rejeicao(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_min_motivo_rejeicao() IS 'Mínimo de caracteres do motivo de uma rejeição de pendência. Não é estética: rejeitar libera o Portão 2 sem teto, e motivo de duas letras é o que se escreve para tirar o vermelho da tela.';

--
-- Name: fn_modelagem_esta_pronta(boolean, bigint, integer, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_modelagem_esta_pronta(p_parametros_definidos boolean, p_premissas_ativas bigint, p_premissas_sem_valor integer, p_linhas_com_premissa bigint) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select
    -- (a) 0134: sem parâmetro de modelagem não há o que exportar.
    coalesce(p_parametros_definidos, false)
    -- (b) 0134: nenhuma premissa ativa é caso ainda não começado.
    and coalesce(p_premissas_ativas, 0) > 0
    -- (c) 0134: premissa ativa sem valor projetaria com zero, calado.
    and coalesce(p_premissas_sem_valor, 0) = 0
    -- (d) 0158: e pelo menos UMA linha real do caso precisa estar, de fato,
    -- vinculada a alguma dessas premissas — sem isso, (a)+(b)+(c) valem com
    -- zero linha projetando e o "pronto" afirmava só que os parâmetros
    -- existem, não que algo foi coberto.
    and coalesce(p_linhas_com_premissa, 0) > 0;
$$;

--
-- Name: FUNCTION fn_modelagem_esta_pronta(p_parametros_definidos boolean, p_premissas_ativas bigint, p_premissas_sem_valor integer, p_linhas_com_premissa bigint); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_modelagem_esta_pronta(p_parametros_definidos boolean, p_premissas_ativas bigint, p_premissas_sem_valor integer, p_linhas_com_premissa bigint) IS '(0158) A decisão de "pronto" da Modelagem, isolada em função PURA para poder ser exercitada por literais (instalacao_sonda_modelagem_pronta), sem fixture de documento nem de caso. As três primeiras condições são da 0134 (parâmetros definidos, premissa ativa, nenhuma sem valor); a quarta (linhas_com_premissa > 0) é da 0158 — sem ela um caso com premissas configuradas e ZERO linha de fato vinculada (ou uma fração ínfima, como 23 de 480 medido no Grupo Vertentes) respondia "pronto" só porque os parâmetros existiam. Ela NÃO cobra fração mínima de cobertura: isso é limiar de negócio que ninguém mediu, e o número vai em fracao_linhas_com_premissa para o portal decidir como exibir. Também NÃO cobra vinculos_orfaos nem sazonalidade_sem_curva vazios — os dois continuam INFORMANDO no retorno de fn_conferir_modelagem, por desenho: nenhum dos dois torna um número do book ERRADO (o órfão não projeta nada porque não há linha do lado de cá; a curva sem documento mensal deixa o valor ANUAL certo, só lisa o rateio mensal — ver o cabeçalho da 0134).';

--
-- Name: fn_motivo_do_lado(boolean, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_motivo_do_lado(p_achou boolean, p_col_entidade text, p_col_periodo text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select case
    when p_achou then null
    -- A entidade não tem coluna num documento de várias: o código sabe o que
    -- faltou, mas não é nenhum dos três do CONTRATO da 0186 — fica genérico.
    when p_col_entidade is not distinct from E'\x01' then 'precondicao_nao_satisfeita'
    when p_col_periodo  is not distinct from E'\x01' then 'sem_periodo_par'
    else 'linha_nao_localizada'
  end;
$$;

--
-- Name: FUNCTION fn_motivo_do_lado(p_achou boolean, p_col_entidade text, p_col_periodo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_motivo_do_lado(p_achou boolean, p_col_entidade text, p_col_periodo text) IS '0188: motivo de um lado de uma comparação de reconciliação. NULL se achou; sem_periodo_par se o documento declara colunas de período e nenhuma é do ano (sentinela E''\x01''); precondicao_nao_satisfeita se a coluna da ENTIDADE não foi achada; senão linha_nao_localizada.';

--
-- Name: fn_motivo_escala_incomparavel(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_motivo_escala_incomparavel(p_unidade_a text, p_unidade_b text, p_rotulo_a text, p_rotulo_b text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select case
    -- Escala ausente de um dos lados: mesmo critério conservador da 0009 — não
    -- há o que converter, mas também não há o que afirmar. Não bloqueia.
    when p_unidade_a is null or p_unidade_b is null then null
    when fn_normalizar_texto(p_unidade_a) = fn_normalizar_texto(p_unidade_b) then null
    when fn_fator_escala(p_unidade_a) is not null and fn_fator_escala(p_unidade_b) is not null then null
    else format(
      'Escalas não conversíveis entre os documentos: %s está em "%s" e %s está em "%s", e ao menos '
      || 'uma dessas escalas não é reconhecida (esperado: unidade, milhar ou milhao). Comparar assim '
      || 'arriscaria um falso "confere" — confirme o cabeçalho de escala de cada documento.',
      p_rotulo_a, p_unidade_a, p_rotulo_b, p_unidade_b)
  end;
$$;

--
-- Name: fn_motivo_precondicao_agregado(text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_motivo_precondicao_agregado(p_motivos text[]) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select case
    when cardinality(coalesce(array_remove(p_motivos, null), '{}')) = 0
      then 'precondicao_nao_satisfeita'
    when 'linha_nao_localizada' = any(array_remove(p_motivos, null))
      then 'linha_nao_localizada'
    when array_remove(p_motivos, null) <@ array['sem_periodo_par']
      then 'sem_periodo_par'
    else 'precondicao_nao_satisfeita'
  end;
$$;

--
-- Name: FUNCTION fn_motivo_precondicao_agregado(p_motivos text[]); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_motivo_precondicao_agregado(p_motivos text[]) IS '0188: um motivo para a checagem a partir dos motivos por lado/exercício. linha_nao_localizada se algum; sem_periodo_par só se TODOS; senão precondicao_nao_satisfeita.';

--
-- Name: fn_motivo_precondicao_prefixo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_motivo_precondicao_prefixo(p_motivo text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select case p_motivo
    when 'linha_nao_localizada' then
      'MOTIVO: linha não localizada — o documento está presente, mas a linha que esta '
      || 'conferência lê não casou com nenhum rótulo esperado. REMÉDIO: se a linha está no '
      || 'documento com outro nome, o defeito é o padrão de casamento; se não está, ou a '
      || 'extração não a trouxe (reextrair) ou o documento não a publica (pedir ao cliente). '
    when 'sem_periodo_par' then
      'MOTIVO: sem período par — o documento está presente, mas não traz coluna de nenhum '
      || 'exercício deste período. REMÉDIO: conferir o período atribuído ao documento, ou pedir '
      || 'ao cliente o documento do exercício que falta. '
    when 'unidade_divergente' then
      'MOTIVO: unidade divergente — os dois lados têm valor, mas as escalas não são '
      || 'conversíveis entre si. REMÉDIO: confirmar o cabeçalho de escala de cada documento. '
    else ''
  end;
$$;

--
-- Name: FUNCTION fn_motivo_precondicao_prefixo(p_motivo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_motivo_precondicao_prefixo(p_motivo text) IS '0188: MOTIVO e REMÉDIO de um motivo_precondicao, para ir na frente da descrição da pendência. Vazio para precondicao_nao_satisfeita (motivo não especificado) e documento_ausente.';

--
-- Name: fn_mudar_dial(text, public.nivel_autonomia, text, text, numeric, uuid, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_mudar_dial(p_estagio text, p_nivel public.nivel_autonomia, p_autor text, p_motivo text DEFAULT NULL::text, p_limiar numeric DEFAULT NULL::numeric, p_rodada_golden uuid DEFAULT NULL::uuid, p_sem_medicao_porque text DEFAULT NULL::text, p_por_veredito boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_antes     jsonb;
  v_teto      nivel_autonomia;
  v_nivel_ant nivel_autonomia;
  v_natureza  text;
  v_sobe_para_autonomia boolean;
  v_med       jsonb;
  v_base      text;
  v_resumo    jsonb;
  v_freia     boolean;
  v_mede      boolean := false;   -- esta chamada produziu base MEDIDA nova?
begin
  select to_jsonb(ea), ea.teto, ea.nivel_atual, ea.natureza
    into v_antes, v_teto, v_nivel_ant, v_natureza
  from estagio_autonomia ea where ea.estagio = p_estagio;

  if v_antes is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Estágio "%s" não existe no dial. Os estágios são semeados na 0002 '
                              '(Arquitetura do Sistema/2 Especificação/f0/04) — estágio novo entra por migration, não por chamada.', p_estagio));
  end if;

  if p_nivel > v_teto then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
              jsonb_build_object('pedido', p_nivel, 'teto', v_teto, 'motivo_informado', p_motivo));
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('O estágio "%s" tem TETO %s e foi pedido %s. O teto é por natureza do '
                              'estágio (Arquitetura do Sistema/1 Visão e Doutrina/01) e nenhuma chamada o sobrepõe — mudá-lo é decisão de '
                              'doutrina, por migration.', p_estagio, v_teto, p_nivel));
  end if;

  v_sobe_para_autonomia := p_nivel > v_nivel_ant
                           and p_nivel in ('N2', 'N3')
                           and v_natureza = 'interpretativo';

  v_base := case when p_nivel in ('N2','N3') and v_natureza = 'interpretativo'
                 then 'declarada' else 'nao_se_aplica' end;

  -- A TRAVA 2 (0137): descida feita por humano desliga a promoção automática.
  v_freia := p_nivel < v_nivel_ant and coalesce(p_autor, '') not like 'sistema:%';

  if v_sobe_para_autonomia then
    if p_rodada_golden is not null then
      v_med := fn_golden_suficiente(p_estagio, p_rodada_golden);
      if not coalesce((v_med->>'suficiente')::boolean, false) then
        insert into evento_auditoria (ator, acao, entidade_ref, depois)
          values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
                  jsonb_build_object('pedido', p_nivel, 'de', v_nivel_ant,
                                     'motivo_informado', p_motivo, 'medicao', v_med));
        return jsonb_build_object('recusado', true, 'medicao', v_med,
          'motivo_recusa', format('A concordância medida contra a rodada de golden set não basta '
                                  'para subir "%s" de %s para %s. Arquitetura do Sistema/1 Visão e Doutrina/01, regra de ouro: nada de '
                                  'subir dial de estágio interpretativo sem golden set e '
                                  'concordância medida. O que faltou está em "medicao".',
                                  p_estagio, v_nivel_ant, p_nivel));
      end if;
      v_base := 'medida';
      v_resumo := v_med;
      v_mede := true;

    elsif p_por_veredito then
      v_med := fn_veredito_producao(p_estagio);
      if not coalesce((v_med->>'suficiente')::boolean, false) then
        insert into evento_auditoria (ator, acao, entidade_ref, depois)
          values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
                  jsonb_build_object('pedido', p_nivel, 'de', v_nivel_ant,
                                     'motivo_informado', p_motivo, 'medicao', v_med));
        return jsonb_build_object('recusado', true, 'medicao', v_med,
          'motivo_recusa', format('O veredito de produção não basta para subir "%s" de %s para %s. '
                                  'O que faltou está em "medicao"; a fonte do rótulo está em '
                                  '"fonte". Lembrando que este caminho mede um PISO, e o piso ainda '
                                  'não alcançou o critério.', p_estagio, v_nivel_ant, p_nivel));
      end if;
      v_base := 'medida_por_veredito';
      v_resumo := v_med;
      v_mede := true;

    elsif p_sem_medicao_porque is null then
      insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
                jsonb_build_object('pedido', p_nivel, 'de', v_nivel_ant,
                                   'motivo_informado', p_motivo,
                                   'porque', 'sem rodada de golden set, sem veredito e sem motivo declarado'));
      return jsonb_build_object('recusado', true,
        'motivo_recusa', format('Subir "%s" de %s para %s é entrar em auto-clear num estágio '
                                'INTERPRETATIVO, e Arquitetura do Sistema/1 Visão e Doutrina/01 exige concordância medida para isso. '
                                'Três caminhos: `p_rodada_golden` com uma rodada CONGELADA, '
                                '`p_por_veredito` para medir pelo veredito de produção (0136, e o '
                                'número é um piso enviesado), ou assumir a decisão em '
                                '`p_sem_medicao_porque` — nesse caso a subida acontece, fica '
                                'registrada como mudanca_dial_sem_medicao e o nível passa a valer '
                                'como DECLARADO.', p_estagio, v_nivel_ant, p_nivel));
    end if;
  end if;

  -- REAFIRMAR O NÍVEL QUE JÁ VALE NÃO PODE APAGAR A MEDIÇÃO QUE O AUTORIZOU.
  --
  -- `v_mede` é verdadeiro só quando ESTA chamada produziu base nova. Quando não
  -- produziu — e o nível pedido é o que já está lá —, os três campos de medição
  -- ficam como estavam. Sem isso, `fn_mudar_dial(estagio, <mesmo nível>)` trocava
  -- `medida_por_veredito` por `declarada` e zerava `medicao_em`/`medicao_resumo`:
  -- o sistema passava a subdeclarar a própria evidência, e a trilha do que
  -- autorizou o nível sumia. Ver o cabeçalho desta migration.
  update estagio_autonomia
    set nivel_atual = p_nivel,
        limiar_auto_clear = coalesce(p_limiar, limiar_auto_clear),
        base_do_nivel = case when v_mede or p_nivel <> v_nivel_ant then v_base else base_do_nivel end,
        medicao_rodada_id = case when v_mede then (case when v_base = 'medida' then p_rodada_golden else null end)
                                 when p_nivel <> v_nivel_ant then null
                                 else medicao_rodada_id end,
        medicao_em        = case when v_mede then now()
                                 when p_nivel <> v_nivel_ant then null
                                 else medicao_em end,
        medicao_resumo    = case when v_mede then v_resumo
                                 when p_nivel <> v_nivel_ant then null
                                 else medicao_resumo end,
        -- O FREIO GRUDA. Uma vez desligada por descida humana, a promoção
        -- automática só volta por `update` explícito: quem desconfiou é quem
        -- decide voltar a confiar.
        auto_promocao = case when v_freia then false else auto_promocao end,
        atualizado_por = p_autor,
        atualizado_em = now()
  where estagio = p_estagio;

  if v_freia then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'auto_promocao_desligada', 'estagio:'||p_estagio,
              jsonb_build_object('de', v_nivel_ant, 'para', p_nivel, 'motivo_informado', p_motivo,
                                 'porque', 'descida feita por humano desliga a promoção automática '
                                           '(0137); religar é update explícito'));
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor,
            case when v_sobe_para_autonomia and p_rodada_golden is null and not p_por_veredito
                 then 'mudanca_dial_sem_medicao' else 'mudanca_dial' end,
            'estagio:'||p_estagio, v_antes,
            (select to_jsonb(ea) from estagio_autonomia ea where ea.estagio = p_estagio)
            || jsonb_build_object('motivo', p_motivo,
                                  'sem_medicao_porque', p_sem_medicao_porque,
                                  'medicao', v_resumo));

  return fn_dial(p_estagio);
end;
$$;

--
-- Name: FUNCTION fn_mudar_dial(p_estagio text, p_nivel public.nivel_autonomia, p_autor text, p_motivo text, p_limiar numeric, p_rodada_golden uuid, p_sem_medicao_porque text, p_por_veredito boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_mudar_dial(p_estagio text, p_nivel public.nivel_autonomia, p_autor text, p_motivo text, p_limiar numeric, p_rodada_golden uuid, p_sem_medicao_porque text, p_por_veredito boolean) IS 'Muda o nível de autonomia de um estágio aplicando a regra de ouro do Arquitetura do Sistema/1 Visão e Doutrina/01. Três portas para subir interpretativo a N2/N3: rodada de golden set congelada (base medida), veredito de produção suficiente (medida_por_veredito, piso enviesado, 0136), ou motivo declarado. Descer nunca pede nada e DESLIGA a promoção automática daquele estágio (0137). Desde a 0139, reafirmar o nível que já vale NÃO apaga a medição que o autorizou. Recusa é RETORNADA, não exceção.';

--
-- Name: fn_mutuo_com_socio(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_mutuo_com_socio(p_chave text, p_secao text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select fn_normalizar_texto(coalesce(p_chave, '') || ' ' || coalesce(p_secao, ''))
         ~ '(socio|quotista|cotista|acionista)';
$$;

--
-- Name: FUNCTION fn_mutuo_com_socio(p_chave text, p_secao text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_mutuo_com_socio(p_chave text, p_secao text) IS '0123: mútuo cuja contraparte é o SÓCIO, não outra empresa do grupo — não tem espelho no mandato e não se confere contra a planilha intragrupo.';

--
-- Name: fn_natureza_intragrupo(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_natureza_intragrupo(p_chave text, p_secao text DEFAULT NULL::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select case
    when fn_normalizar_texto(coalesce(p_chave, '') || ' ' || coalesce(p_secao, '')) ~ 'mutuo'
      then 'mútuo'
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'conta corrente'  then 'conta corrente'
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'alugue|locac|arrendament'
      then 'aluguel'
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'frete|logistic|transport'
      then 'frete'
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'fornecedor|compra|insumo|materia'
      then 'fornecimento'
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'rateio|compartilh|servic|honorar'
      then 'rateio de despesa'
    else 'conta intragrupo'
  end;
$$;

--
-- Name: FUNCTION fn_natureza_intragrupo(p_chave text, p_secao text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_natureza_intragrupo(p_chave text, p_secao text) IS '0124: a natureza da linha intragrupo, para a MENSAGEM dizer onde procurar. Não é chave de pareamento — cada ponta da relação usa o vocabulário dela.';

--
-- Name: fn_nome_de_secao_normalizado(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_nome_de_secao_normalizado(p_texto text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
  select nullif(
    regexp_replace(
      regexp_replace(
        regexp_replace(fn_normalizar_texto(fn_sem_codigo_de_conta(p_texto)), '^(\(\s*[-+=]\s*\)|[-+=])\s*', ''),
        '^([0-9]+(\.[0-9]+)*|[ivx]+)\s*[-.)]\s*', ''),
      '[\s:.;]+$', ''),
    '')
$_$;

--
-- Name: fn_nome_de_topo_ou_total(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_nome_de_topo_ou_total(p_nome text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  select p_nome ~ '^(ativo|passivo|ativo e passivo|passivo e patrimonio liquido|circulante|nao circulante|balanco patrimonial|balancete analitico|balancete|resumo do balancete|eliminacoes do combinado|contas temporarias|nao classificavel|nao_classificavel|dre|demonstracao do resultado( do exercicio)?)$'
      or p_nome ~ '(^| )(total|totais)( |$)'
$_$;

--
-- Name: fn_nome_parece_ter_endereco_colado(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_nome_parece_ter_endereco_colado(p_nome text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  select trim(p_nome) ~ ',\s*\d+\s*$';
$_$;

--
-- Name: FUNCTION fn_nome_parece_ter_endereco_colado(p_nome text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_nome_parece_ter_endereco_colado(p_nome text) IS '0171: vírgula seguida de número no fim do nome — o padrão exato de "…SURUBIJU, 1930", onde o template do contador colou a linha de endereço na razão social truncada.';

--
-- Name: fn_nome_tem_sufixo_societario(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_nome_tem_sufixo_societario(p_nome text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  -- A PONTUAÇÃO É ACHATADA ANTES, e isso DIVERGE de `fn_entidade_canonica` de
  -- propósito. A 0030 casa o sufixo ANTES de achatar a pontuação, com
  -- `s\s*a` — e `\s*` não casa PONTO. Medido: `S/A` e `SA` eram reconhecidos,
  -- **`S.A.` não**, que é a grafia mais comum das duas. A primeira versão
  -- desta função copiou o padrão da 0030 e herdou o buraco, enquanto o
  -- comentário afirmava cobrir S.A. — achado na revisão desta fatia.
  --
  -- O BURACO DA 0030 CONTINUA LÁ e NÃO é consertado aqui: `fn_entidade_canonica`
  -- é a base do casamento EXATO de todo o produto, e mexer nela reclassifica
  -- entidade em todo caso já aberto. O efeito medido é limitado — "ALFA S.A."
  -- e "ALFA" deixam de casar como EXATAS mas continuam casando por
  -- `fn_mesma_entidade` (aproximado), então o dano é degradar exato→aproximado,
  -- não perder o casamento. Fica declarado aqui, não corrigido de lado.
  select trim(regexp_replace(
           regexp_replace(fn_normalizar_texto(p_nome), '[.,;:/\\()''"-]', ' ', 'g'),
           '\s+', ' ', 'g'))
         ~ '\s(ltda|limitada|s a|sa|eireli|me|epp|mei|em recuperacao judicial|em rj)$';
$_$;

--
-- Name: FUNCTION fn_nome_tem_sufixo_societario(p_nome text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_nome_tem_sufixo_societario(p_nome text) IS '0171: o nome termina em sufixo societário (LTDA, S.A., S/A, EIRELI, …)? MESMA lista da fn_entidade_canonica (0030), mas achatando a pontuação ANTES de casar — sem isso "S.A." não é reconhecido (o ponto não é espaço), e era o caso da primeira versão desta função.';

--
-- Name: fn_normalizar_texto(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_normalizar_texto(p_texto text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select trim(regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '\s+', ' ', 'g'));
$$;

--
-- Name: fn_operacao_lotes(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_operacao_lotes(p_dias integer DEFAULT 30, p_limite integer DEFAULT 50) RETURNS TABLE(lote_id uuid, caso_id uuid, caso_nome text, execucao_ref text, quando timestamp with time zone, documentos integer, com_falha integer, sem_medicao integer, fatiados integer, linhas_extraidas integer, cobertura numeric, custo_usd numeric, custo_estimado numeric, razao_custo numeric, alertas text[])
    LANGUAGE sql STABLE
    AS $$
  select
    le.id, le.caso_id, c.nome, le.execucao_ref, le.criado_em,
    le.documentos, le.documentos_com_falha, le.documentos_sem_medicao,
    le.documentos_fatiados, le.linhas_extraidas, le.cobertura,
    le.custo_total_usd, le.custo_estimado_usd,
    case when coalesce(le.custo_estimado_usd, 0) > 0
         then round(le.custo_total_usd / le.custo_estimado_usd, 2) end,
    array_remove(array[
      case when le.cobertura is null then 'cobertura_nao_medida' end,
      case when coalesce(le.documentos_com_falha, 0) > 0 then 'documento_com_falha' end,
      case when coalesce(le.documentos_sem_medicao, 0) > 0 then 'documento_sem_medicao' end,
      case when coalesce(le.custo_estimado_usd, 0) > 0
                and le.custo_total_usd > le.custo_estimado_usd * 1.5
           then 'custo_acima_do_previsto' end
    ], null)
  from lote_execucao le
  left join caso c on c.id = le.caso_id
  where le.criado_em >= now() - make_interval(days => p_dias)
  order by le.criado_em desc
  limit p_limite;
$$;

--
-- Name: FUNCTION fn_operacao_lotes(p_dias integer, p_limite integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_operacao_lotes(p_dias integer, p_limite integer) IS 'Uma linha por execução de ingestão na janela, com os alertas já decididos NO BANCO — para não haver duas réguas sobre a mesma quantidade no dia em que existir um segundo leitor.';

--
-- Name: fn_operacao_resumo(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_operacao_resumo(p_dias integer DEFAULT 30) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  with l as (select * from fn_operacao_lotes(p_dias, 100000))
  select jsonb_build_object(
    'janela_dias', p_dias,
    'lotes', (select count(*) from l),
    'documentos', (select coalesce(sum(documentos), 0) from l),
    'linhas_extraidas', (select coalesce(sum(linhas_extraidas), 0) from l),
    'custo_usd', (select coalesce(round(sum(custo_usd), 2), 0) from l),
    'custo_por_documento', (select case when coalesce(sum(documentos), 0) > 0
      then round(sum(custo_usd) / sum(documentos), 4) end from l),
    'cobertura_mediana', (select round(
      percentile_cont(0.5) within group (order by cobertura)::numeric, 3)
      from l where cobertura is not null),
    'lotes_com_alerta', (select count(*) from l where cardinality(alertas) > 0),
    -- Por TIPO de alerta, porque "3 lotes com alerta" não diz o que fazer e
    -- "3 sem cobertura medida" diz.
    'por_alerta', coalesce((
      select jsonb_object_agg(a, n) from (
        select unnest(alertas) as a, count(*) as n from l where cardinality(alertas) > 0 group by 1
      ) x), '{}'::jsonb),
    'ultimo_lote', (select max(quando) from l),
    -- O SILÊNCIO TAMBÉM É ESTADO. Um painel que mostra "0 alertas" quando não
    -- roda nada há duas semanas é pior que um painel vazio: ele afirma saúde.
    'dias_desde_o_ultimo', (select case when max(quando) is not null
      then round(extract(epoch from (now() - max(quando))) / 86400) end from l)
  );
$$;

--
-- Name: FUNCTION fn_operacao_resumo(p_dias integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_operacao_resumo(p_dias integer) IS 'Resumo da operação na janela. Cobertura é MEDIANA e não média — média mistura lote de 40 documentos com lote de 1 e descreve nenhum dos dois. Publica `dias_desde_o_ultimo` porque silêncio também é estado: "0 alertas" sem nenhuma execução afirma saúde que ninguém mediu.';

--
-- Name: fn_papel_do_rotulo_no_caso(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_papel_do_rotulo_no_caso(p_caso_id uuid, p_rotulo_norm text, p_secao_canonica text) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  with ocorrencias as (
    select ce.secao_canonica,
           fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) as papel
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and fn_normalizar_texto(ce.chave) = p_rotulo_norm
      and dv.id = fn_versao_com_extracao(d.id)
  ),
  da_secao as (
    select papel from ocorrencias
    where coalesce(secao_canonica, '') = coalesce(p_secao_canonica, '')
  )
  select coalesce(
    -- 1) o papel dentro da seção pedida — o mesmo que fn_linhas_para_modelagem
    --    mostra, porque o agrupamento é o mesmo.
    (select (array_agg(papel order by fn_papel_prioridade(papel)))[1] from da_secao),
    -- 2) e só se o rótulo não existir naquela seção, o do caso inteiro.
    (select (array_agg(papel order by fn_papel_prioridade(papel)))[1] from ocorrencias)
  );
$$;

--
-- Name: FUNCTION fn_papel_do_rotulo_no_caso(p_caso_id uuid, p_rotulo_norm text, p_secao_canonica text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_papel_do_rotulo_no_caso(p_caso_id uuid, p_rotulo_norm text, p_secao_canonica text) IS 'Papel do rótulo DENTRO DA SEÇÃO (0100), com queda para o caso inteiro só quando o rótulo não existe na seção. Tem de concordar com fn_linhas_para_modelagem — discordância entre as duas é o defeito que derrubava o "aplicar em lote". 0102: mesmo filtro de versão vigente que a tela.';

--
-- Name: fn_papel_linha(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_papel_linha(p_chave text, p_tipo_taxonomia text DEFAULT NULL::text, p_unidade text DEFAULT NULL::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  -- marca-0202
  with n as (
    -- 0202: o CÓDIGO CONTÁBIL do ERP na frente do rótulo ("2.3.71 TOTAL — saldo devedor") não é
    -- parte do nome: sem tirá-lo, o prefixo `total` não está mais no INÍCIO e o TOTAL vira conta.
    select fn_normalizar_texto(fn_sem_codigo_de_conta(p_chave)) as t,
           fn_tokens_estruturais(fn_sem_codigo_de_conta(p_chave)) as toks
  )
  select case
    -- ---- DERIVADO: indicador gerencial, não dinheiro ------------------------
    when (select t from n) ~ '^(indice|indices) '
      or (select t from n) ~ '^media (mensal|diaria|anual)'
      or (select t from n) ~ '^ticket medio'
      or (select t from n) ~ '^prazo medio'
      or (select t from n) ~ '^(margem|rentabilidade|retorno) '
      or (select t from n) ~ '^capital circulante liquido'
      or (select t from n) ~ '^(giro|rotacao) (de|do|da) '
      or (select t from n) ~ 'indicador gerencial'
      then 'derivado'

    -- ---- SÉRIE MENSAL: insumo da curva de sazonalidade ----------------------
    when p_tipo_taxonomia = 'FATURAMENTO_24M' and fn_mes_do_rotulo(p_chave) is not null
      then 'serie_mensal'

    -- ---- SUBTOTAL: já é a soma de outras linhas -----------------------------
    -- (a) prefixo "total"/"subtotal"/"soma"
    when (select t from n) ~ '^(total|totais|subtotal|soma) ' or (select t from n) in ('total','totais','subtotal')
      then 'subtotal'
    -- (b) o total do grupo SEM a palavra "total" (0034), agora contra os tokens
    --     já calculados. Arrays em ordem alfabética — é igualdade de array.
    when (select toks from n) in (
        array['ativo'],
        array['passivo'],
        array['patrimonio'],
        array['passivo','patrimonio'],
        array['ativo','circulante'],
        array['ativo','circulante','nao'],
        array['circulante','passivo'],
        array['circulante','nao','passivo'],
        array['longo','prazo','realizavel'])
      then 'subtotal'
    -- (c) as linhas de RESULTADO da DRE e os subtotais do Fluxo, lista fechada
    when (select t from n) in (
        'receita operacional liquida','receita liquida','receita liquida de vendas',
        'lucro bruto','prejuizo bruto',
        'resultado operacional antes do resultado financeiro',
        'resultado antes dos tributos sobre o lucro','resultado antes dos tributos',
        'lucro liquido do exercicio','prejuizo liquido do exercicio',
        'lucro liquido','prejuizo liquido','resultado do exercicio',
        'resultado financeiro liquido','resultado financeiro')
      then 'subtotal'
    -- (c2) 0116: o TOPO da DRE, que só passa a chegar agora que o total
    --      impresso vira linha. A forma longa ("receita operacional bruta") é o
    --      cabeçalho do bloco de receita na estrutura completa — o valor dela é
    --      a soma das receitas por segmento/produto que vêm abaixo.
    when (select t from n) in (
        'receita operacional bruta','receitas operacionais brutas',
        'receita bruta operacional',
        'deducoes da receita bruta','deducoes da receita',
        'resultado antes do resultado financeiro',
        'resultado operacional')
      then 'subtotal'
    -- (c3) 0116: os totais da DVA. A DVA é feita de blocos que terminam em
    --      total ("Valor adicionado bruto", "Valor adicionado líquido
    --      produzido", "Valor adicionado total a distribuir") e a distribuição
    --      repete o mesmo montante por destinatário — contar o total junto com
    --      os destinatários dobra a demonstração inteira.
    when (select t from n) in (
        'valor adicionado bruto',
        'valor adicionado liquido produzido','valor adicionado liquido',
        'valor adicionado recebido em transferencia',
        'valor adicionado total a distribuir','valor adicionado a distribuir',
        'valor adicionado total','distribuicao do valor adicionado')
      then 'subtotal'
    when (select t from n) ~ '^caixa liquido (gerado|aplicado|gerado pelas)'
      or (select t from n) ~ '^(aumento|reducao|variacao) liquida? (de|do|da) caixa'
      then 'subtotal'

    else 'conta'
  end;
$$;

--
-- Name: FUNCTION fn_papel_linha(p_chave text, p_tipo_taxonomia text, p_unidade text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_papel_linha(p_chave text, p_tipo_taxonomia text, p_unidade text) IS 'Papel da linha na modelagem: conta | subtotal | derivado | serie_mensal. Lista FECHADA de padrões (não heurística de semelhança) porque errar para subtotal esconde conta de verdade e errar para conta deixa passar dupla contagem. 0102: tokeniza o rótulo uma vez e compara os nove grupos contra o resultado, em vez de nove chamadas a fn_rotulo_estrutural. 0116: cobre o topo da DRE e os totais da DVA, que só passam a chegar depois de o prompt exigir o total IMPRESSO como linha. 0202: o código contábil do ERP na frente do rótulo ("2.3.71 TOTAL") não conta — o papel é o do nome.';

--
-- Name: fn_papel_prioridade(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_papel_prioridade(p_papel text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
  select case p_papel
    when 'subtotal' then 0
    when 'serie_mensal' then 1
    when 'derivado' then 2
    else 3
  end;
$$;

--
-- Name: fn_pares_duplicados_do_caso(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_pares_duplicados_do_caso(p_caso_id uuid, p_entidade text DEFAULT NULL::text) RETURNS TABLE(secao_canonica text, rotulo_a text, rotulo_b text, colunas integer, valor numeric, radical_comum boolean)
    LANGUAGE sql STABLE
    AS $$
  with ocorrencias as (
    select
      ce.secao_canonica,
      fn_normalizar_texto(ce.chave)                as rotulo,
      coalesce(ce.entidade_coluna, e.razao_social) as ent_col,
      coalesce(ce.periodo_coluna, p.referencia)    as per_col,
      ce.valor_num,
      ce.chave,
      ce.secao,
      ce.unidade,
      d.tipo_taxonomia,
      d.id                                         as doc_id
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d         on d.id = dv.documento_id
    left join entidade e     on e.id = d.entidade_id
    left join periodo p      on p.id = d.periodo_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and ce.valor_num <> 0
      and ce.secao_canonica is not null
      and ce.secao_canonica <> 'NAO_CLASSIFICAVEL'
      -- Só a versão VIGENTE de cada documento (0102): ocorrência de versão
      -- superada faria uma reextração parecer duplicidade.
      and dv.n_versao = (select max(dv2.n_versao) from documento_versao dv2
                          where dv2.documento_id = d.id)
      and (p_entidade is null
           or fn_mesma_entidade(coalesce(ce.entidade_coluna, e.razao_social), p_entidade))
  ),
  contas as (
    -- Subtotal e derivado ficam fora: o export já trata subtotal informado por
    -- estrutura, e cobrar de novo aqui duplicaria a fila de revisão.
    select * from ocorrencias o
    where fn_papel_linha(o.chave, o.tipo_taxonomia, o.unidade) = 'conta'
  ),
  -- Uma linha por (seção, rótulo, coluna): se o mesmo rótulo aparece em dois
  -- documentos com o mesmo valor, isso é concordância, não duplicidade.
  por_coluna as (
    select secao_canonica, rotulo, ent_col, per_col, min(chave) as chave,
           -- A SUBSEÇÃO DECLARADA pelo documento, agregada: é ela que denuncia o
           -- par subtotal × componente (ver o filtro `subtotal_de` abaixo).
           array_agg(distinct fn_normalizar_texto(coalesce(secao, ''))) as secoes,
           -- 0144: DE QUAIS DOCUMENTOS este rótulo veio. É o que sustenta o
           -- filtro `mesmo_documento` — o critério novo, e o mais forte dos três.
           array_agg(distinct doc_id) as docs,
           max(valor_num) as valor_num
    from contas
    group by secao_canonica, rotulo, ent_col, per_col
    having count(distinct valor_num) = 1
  ),
  pares as (
    select
      a.secao_canonica,
      a.rotulo as rotulo_a, b.rotulo as rotulo_b,
      min(a.chave) as chave_a, min(b.chave) as chave_b,
      count(*)     as colunas_iguais,
      max(abs(a.valor_num)) as valor,
      -- 0144: OS DOIS RÓTULOS SAEM DO MESMO DOCUMENTO?
      --
      -- Se saem, ele é a autoridade sobre a relação entre eles — e o que ele está
      -- dizendo é hierarquia, não duplicidade. Uma demonstração é internamente
      -- consistente por construção: cada conta aparece uma vez, e se aparecesse
      -- duas a seção não fecharia, que é trabalho da `fn_conferir_arvore` (0133),
      -- não desta checagem. O dano que a 0105 existe para achar é a soma de DUAS
      -- FONTES — o balanço e o balancete escrevendo o mesmo fato de dois jeitos.
      --
      -- Medido na v48: 33 de 33 pares candidatos estavam no mesmo documento, 32
      -- deles em linhas VIZINHAS (`ordem` a distância 1). Subtotal de grupo
      -- seguido do seu único componente, e não conta transposta duas vezes.
      bool_or(a.docs && b.docs) as mesmo_documento,
      -- É o par SUBTOTAL × COMPONENTE? O documento diz: a subseção declarada de um
      -- é o rótulo do outro. Medido no book (extração fiel): "Obrigações
      -- Tributárias" × "Parcelamentos tributários - longo prazo", "Empréstimos e
      -- Financiamentos" × "Financiamentos - FINAME/BNDES", "Partes Relacionadas" ×
      -- "Mútuos a pagar", "Investimentos" × "Participações em outras sociedades".
      -- São grupo com UM componente, não conta duplicada — e o export já os exclui
      -- da soma pela detecção estrutural. Cobrar de novo aqui encheria a fila de
      -- revisão com o que já está resolvido, que é exatamente o que a 0023 desfez.
      --
      -- 0144: ESTE FILTRO CONTINUA, MAS NÃO SE PODE MAIS CONTAR COM ELE SOZINHO.
      -- Ele depende de `secao` trazer o grupo IMEDIATO, e na v48 `secao` chega
      -- ACHATADA (subtotal e folhas com a seção de topo) — a mesma causa raiz que
      -- a 0143 documentou. Com o sinal ausente, `subtotal_de` nunca dispara.
      bool_or(a.rotulo = any(b.secoes) or b.rotulo = any(a.secoes)) as subtotal_de,
      -- MESMA SUBSEÇÃO DECLARADA? Dois rótulos para o MESMO fato estão, por
      -- construção, no mesmo lugar da demonstração. Quando o documento os coloca em
      -- subseções diferentes, ele está dizendo que são coisas diferentes — e é o
      -- que restou de falso positivo no book depois do filtro de subtotal:
      -- "Créditos tributários - ICMS sobre ativo permanente" (Realizável a Longo
      -- Prazo) e "Veículos e empilhadeiras" (Imobilizado), ambos 3.900 nos dois
      -- exercícios. Coincidência de valor, contas distintas.
      bool_or(a.secoes && b.secoes) as mesma_subsecao,
      -- O SINAL DE SUBSEÇÃO EXISTE NESTE DOCUMENTO? Sem ele o filtro `subtotal_de`
      -- não tem como disparar, e aí "Arrendamentos" × "Arrendamentos a pagar - CPC
      -- 06 (R2)" (grupo com um componente) fica indistinguível de rótulo reescrito —
      -- os dois têm radical contido. Medido no `fixture_modelagem_v35.sql`, que não
      -- traz `secao`: era o único par que ele devolvia, e era falso positivo.
      -- Então o ramo de UMA coluna (que se sustenta no radical) exige a subseção
      -- declarada; o de DUAS colunas não precisa dela, porque ali a evidência é
      -- aritmética e independente do nome.
      bool_or(coalesce(array_to_string(a.secoes, '') || array_to_string(b.secoes, ''), '') <> '') as tem_secao
    from por_coluna a
    join por_coluna b
      on b.secao_canonica = a.secao_canonica
     and b.ent_col = a.ent_col and b.per_col = a.per_col
     and b.rotulo > a.rotulo                       -- par sem repetir a ordem
     and b.valor_num = a.valor_num                 -- idêntico ao centavo
    group by a.secao_canonica, a.rotulo, b.rotulo
  ),
  -- Uma coluna em que os dois aparecem e DISCORDAM derruba o par: contas que
  -- coincidem num ano e divergem no outro são contas diferentes, ponto.
  discordantes as (
    select a.secao_canonica, a.rotulo as rotulo_a, b.rotulo as rotulo_b
    from por_coluna a
    join por_coluna b
      on b.secao_canonica = a.secao_canonica
     and b.ent_col = a.ent_col and b.per_col = a.per_col
     and b.rotulo > a.rotulo
     and b.valor_num <> a.valor_num
  )
  select
    pr.secao_canonica,
    pr.chave_a,
    pr.chave_b,
    pr.colunas_iguais::int,
    pr.valor,
    (fn_tokens_estruturais(pr.chave_a) <@ fn_tokens_estruturais(pr.chave_b)
     or fn_tokens_estruturais(pr.chave_b) <@ fn_tokens_estruturais(pr.chave_a)) as radical_comum
  from pares pr
  where not pr.mesmo_documento
    and not pr.subtotal_de
    and pr.mesma_subsecao
    and not exists (
    select 1 from discordantes dc
    where dc.secao_canonica = pr.secao_canonica
      and dc.rotulo_a = pr.rotulo_a and dc.rotulo_b = pr.rotulo_b
  )
    and (pr.colunas_iguais >= 2
         or (pr.tem_secao
             and (fn_tokens_estruturais(pr.chave_a) <@ fn_tokens_estruturais(pr.chave_b)
                  or fn_tokens_estruturais(pr.chave_b) <@ fn_tokens_estruturais(pr.chave_a))))
  order by pr.valor desc, pr.secao_canonica, pr.chave_a, pr.chave_b;
$$;

--
-- Name: FUNCTION fn_pares_duplicados_do_caso(p_caso_id uuid, p_entidade text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_pares_duplicados_do_caso(p_caso_id uuid, p_entidade text) IS 'Pares de rótulos DIFERENTES, em DOCUMENTOS DIFERENTES, na mesma seção canônica, com valor idêntico nas mesmas colunas — candidatos a ser a MESMA conta transposta duas vezes (achado do v35: "Prejuízos acumulados" e "Resultados Acumulados", ambos -39.150). Dois rótulos no MESMO documento são a hierarquia DELE (0144), não duplicidade. Não decide nada: alimenta a checagem de reconciliação, que abre pendência para decisão humana. Critério estreito de propósito — falso positivo aqui gasta o tempo do analista.';

--
-- Name: fn_pendencia_cnpj_colide_balcao(uuid, uuid, text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_pendencia_cnpj_colide_balcao(p_caso_id uuid, p_balcao_id uuid, p_cnpj text, p_nome_outro text, p_entidade_outro_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_cnpj        text := fn_cnpj_canonico(p_cnpj);
  v_balcao_nome text;
  v_motivo      text;
  v_desc        text;
  v_pend        uuid;
  v_colisoes_acumuladas text[];
begin
  select razao_social into v_balcao_nome from entidade where id = p_balcao_id;
  if v_balcao_nome is null then return null; end if;

  -- Uma pendência por BALCÃO colidido, não por documento — o mesmo desenho
  -- de `fn_pendencia_entidade_ambigua` (0153): vários documentos batendo na
  -- mesma colisão fazem UMA pergunta, não uma enxurrada.
  v_motivo := 'entidade_cnpj_colide_balcao:' || p_balcao_id;

  -- 0177 (MÉDIO 1): grava o evento de auditoria ANTES de montar a descrição
  -- — ele é a fonte de verdade que a lista abaixo acumula, e nunca some
  -- (ao contrário da pendência, que a UPDATE sobrescrevia por inteiro).
  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_cnpj_colisao_recusada', 'entidade:' || p_balcao_id,
      jsonb_build_object('caso_id', p_caso_id, 'balcao_id', p_balcao_id, 'cnpj', v_cnpj,
                         'nome_outro', p_nome_outro, 'entidade_outro_id', p_entidade_outro_id,
                         'porque', 'balcão ambíguo só absorve via CNPJ quando o outro lado também é balcão'));

  -- 0177 (MÉDIO 1): lista TODAS as colisões já registradas contra ESTE
  -- balcão — sem isto, a segunda colisão contra um balcão diferente do
  -- primeiro apagava o nome do primeiro colidente da descrição (só ficava
  -- em evento_auditoria, que o analista não lê ao abrir a fila de
  -- pendências). `distinct` evita repetir o mesmo nome se o mesmo documento
  -- reemitir o diagnóstico mais de uma vez.
  select array_agg(distinct (depois->>'nome_outro') order by (depois->>'nome_outro'))
    into v_colisoes_acumuladas
    from evento_auditoria
   where acao = 'entidade_cnpj_colisao_recusada' and entidade_ref = 'entidade:' || p_balcao_id;

  v_desc := format(
    'O balcão ambíguo "%s" (nome ainda NÃO confirmado — foi criado porque casa com MAIS DE UMA '
    || 'empresa deste mandato) já tinha aprendido o CNPJ %s. Colidiu com o MESMO CNPJ sem ser, '
    || 'ela própria, um balcão ambíguo: %s — pela regra "balcão só absorve balcão", o sistema NÃO '
    || 'fundiu nem atribuiu nenhum destes documentos/entidades a ele; o caminho normal (nome, '
    || 'entidade própria) decidiu como decidiria se o balcão nunca tivesse este CNPJ. Confira de '
    || 'quem é o CNPJ: se for mesmo de alguma das colidentes, funda manualmente com '
    || 'fn_fundir_entidade; se for coincidência (ex.: CNPJ do escritório de contabilidade no '
    || 'rodapé do relatório), o CNPJ pode estar gravado na entidade ERRADA (o balcão) e vale '
    || 'reavaliar quem deveria tê-lo.',
    v_balcao_nome, coalesce(v_cnpj, p_cnpj), array_to_string(v_colisoes_acumuladas, ' × '));

  select id into v_pend from pendencia
   where caso_id = p_caso_id and motivo = v_motivo and estado <> 'resolvida'
   limit 1;

  if v_pend is not null then
    update pendencia set descricao = v_desc where id = v_pend;
  else
    insert into pendencia
      (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, entidade_id, motivo)
      values (p_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
              v_desc, p_balcao_id, v_motivo)
      returning id into v_pend;
  end if;

  return v_pend;
end;
$$;

--
-- Name: FUNCTION fn_pendencia_cnpj_colide_balcao(p_caso_id uuid, p_balcao_id uuid, p_cnpj text, p_nome_outro text, p_entidade_outro_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_pendencia_cnpj_colide_balcao(p_caso_id uuid, p_balcao_id uuid, p_cnpj text, p_nome_outro text, p_entidade_outro_id uuid) IS '0176: registra (idempotente por balcão) a colisão de CNPJ entre um balcão ambíguo e uma entidade CONFIRMADA (documento novo por registrar, ou entidade já existente) que trouxe o MESMO CNPJ — o caso em que o balcão NÃO PODE absorver (ver o CRÍTICO da 0176/0177). Não decide de quem é o CNPJ: só nomeia a colisão para revisão humana, com rastro em evento_auditoria (entidade_cnpj_colisao_recusada). 0177 (MÉDIO 1): a descrição ACUMULA todas as colisões já registradas contra este balcão (lidas de evento_auditoria, que nunca se perde) — uma segunda colisão, contra outra entidade, não apaga mais o nome da primeira colidente.';

--
-- Name: fn_pendencia_entidade_ambigua(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_pendencia_entidade_ambigua(p_caso_id uuid, p_documento_id uuid, p_entidade_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_ev   jsonb;
  v_pend uuid;
  v_nome text;
begin
  select ev.depois into v_ev
  from evento_auditoria ev
  where ev.acao = 'entidade_ambigua'
    and ev.entidade_ref = 'entidade:' || p_entidade_id
  order by ev.criado_em desc
  limit 1;

  if v_ev is null then return null; end if;

  select razao_social into v_nome from entidade where id = p_entidade_id;

  -- Uma pendência por ENTIDADE ambígua, não por documento: cinco balanços da
  -- mesma empresa fazem UMA pergunta, e cinco pendências idênticas são a
  -- enxurrada que ensina o analista a ignorar a fila.
  select id into v_pend from pendencia
  where caso_id = p_caso_id and motivo = 'entidade_ambigua:' || p_entidade_id
    and estado <> 'resolvida'
  limit 1;
  if v_pend is not null then return v_pend; end if;

  insert into pendencia
    (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao,
     documento_id, entidade_id, motivo)
  values (
    p_caso_id, 'classificacao', 'entidade_incorreta', 'bloqueante', false,
    format('O nome "%s" casa com MAIS DE UMA empresa deste mandato (%s) e não identifica '
           || 'nenhuma. O documento foi registrado numa entidade própria com esse nome, para '
           || 'não somar os números dele em nenhuma das candidatas — que é o dano que uma '
           || 'escolha errada aqui causa, e ele não produz erro nenhum: o balanço da empresa '
           || 'errada FECHA. Decida de quem é e funda com fn_fundir_entidade; se for uma '
           || 'empresa nova de verdade, basta renomear.',
           v_nome, v_ev->>'candidatos'),
    p_documento_id, p_entidade_id, 'entidade_ambigua:' || p_entidade_id)
  returning id into v_pend;

  return v_pend;
end;
$$;

--
-- Name: FUNCTION fn_pendencia_entidade_ambigua(p_caso_id uuid, p_documento_id uuid, p_entidade_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_pendencia_entidade_ambigua(p_caso_id uuid, p_documento_id uuid, p_entidade_id uuid) IS 'Transforma a ambiguidade registrada por fn_upsert_entidade em pendência bloqueante, nomeando os candidatos (0153). Uma por entidade, não por documento.';

--
-- Name: fn_pendencia_entidade_nome_suspeito(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_pendencia_entidade_nome_suspeito(p_caso_id uuid, p_entidade_id uuid, p_nome text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_motivo text := 'entidade_nome_suspeito:' || p_entidade_id;
  v_pend   uuid;
begin
  select id into v_pend from pendencia
   where caso_id = p_caso_id and motivo = v_motivo and estado <> 'resolvida'
   limit 1;
  if v_pend is not null then return v_pend; end if;

  insert into pendencia
    (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, entidade_id, motivo)
  values (
    p_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
    format('O nome "%s" tem cara de título de coluna/aba/arquivo, não de razão social — sem '
           || 'CNPJ e sem nenhum outro nome do caso para casar (0178). NÃO foi fundida nem '
           || 'apagada — fundir errado é pior que deixar separada, e apagar perderia a '
           || 'proveniência dos documentos já ligados a ela. O EFEITO, enquanto a pendência '
           || 'estiver aberta: os documentos desta pseudo-entidade ficam contabilizados FORA '
           || 'do book de qualquer empresa real do mandato. Confira o documento: se o nome '
           || 'certo está no conteúdo, funda com fn_fundir_entidade; se é mesmo um artefato '
           || '(cabeçalho de planilha, aba de controle), resolva a pendência sem fundir.',
           p_nome),
    p_entidade_id, v_motivo)
  returning id into v_pend;

  return v_pend;
end;
$$;

--
-- Name: FUNCTION fn_pendencia_entidade_nome_suspeito(p_caso_id uuid, p_entidade_id uuid, p_nome text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_pendencia_entidade_nome_suspeito(p_caso_id uuid, p_entidade_id uuid, p_nome text) IS '0178: pendência entidade_incorreta para entidade cujo nome bate fn_entidade_nome_parece_titulo_ou_arquivo, sem CNPJ e recém-criada. Idempotente por entidade_id (motivo). Nunca funde, nunca apaga — só marca para revisão humana.';

--
-- Name: fn_pendencia_forma_de_controle_backfill(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_pendencia_forma_de_controle_backfill(p_caso_id uuid DEFAULT NULL::uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
  r   record;
  v_n integer := 0;
begin
  for r in
    select e.id, e.caso_id, e.razao_social
      from entidade e
     where e.forma_de_controle = 'indefinido'
       and (p_caso_id is null or e.caso_id = p_caso_id)
       -- a triagem humana que já existe: entidade julgada ruído de caso de teste não recebe
       -- um segundo convite a decidir sobre ela
       and not exists (
         select 1 from pendencia p
          where p.caso_id = e.caso_id
            and p.motivo = 'papel_no_grupo_indefinido:' || e.id
            and p.estado = 'resolvida'
            and p.resolvida_por = 'sessao-claude:ruido-de-caso-de-teste')
  loop
    perform fn_pendencia_forma_de_controle_indefinida(r.caso_id, r.id, r.razao_social);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

--
-- Name: FUNCTION fn_pendencia_forma_de_controle_backfill(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_pendencia_forma_de_controle_backfill(p_caso_id uuid) IS '0183: abre a pendência forma_de_controle_indefinida para as entidades que já existiam quando a coluna nasceu, EXCETO as que a triagem humana da 0179 já julgou ruído de caso de teste (pendência de papel resolvida com resolvida_por = ''sessao-claude:ruido-de-caso-de-teste''). Medido em produção antes de aplicar: 365 entidades, 347 triadas — sem a exclusão o backfill repetiria o ruído da 0179. Devolve quantas entidades visitou. p_caso_id NULL = banco inteiro.';

--
-- Name: fn_pendencia_forma_de_controle_indefinida(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_pendencia_forma_de_controle_indefinida(p_caso_id uuid, p_entidade_id uuid, p_nome text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_motivo text := 'forma_de_controle_indefinida:' || p_entidade_id;
  v_pend   uuid;
begin
  select id into v_pend from pendencia
   where caso_id = p_caso_id and motivo = v_motivo and estado <> 'resolvida'
   limit 1;
  if v_pend is not null then return v_pend; end if;

  insert into pendencia
    (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, entidade_id, motivo)
  values (
    p_caso_id, 'diagnostico', 'forma_de_controle_indefinida', 'complementar', true,
    format('A entidade "%s" ainda não tem forma de controle declarada (controlada por outra '
           || 'entidade / controle comum) — ninguém decidiu ainda, e o sistema não infere isso '
           || 'sozinho (nem de controladora_id, nem de entidade_controlador — regra 1 do '
           || 'CLAUDE.md). O EFEITO, hoje: nenhum, porque nenhum consumidor lê forma_de_controle '
           || 'ainda. Chame fn_entidade_definir_forma_de_controle para esta entidade quando a '
           || 'estrutura societária for conhecida.',
           p_nome),
    p_entidade_id, v_motivo)
  returning id into v_pend;

  return v_pend;
end;
$$;

--
-- Name: FUNCTION fn_pendencia_forma_de_controle_indefinida(p_caso_id uuid, p_entidade_id uuid, p_nome text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_pendencia_forma_de_controle_indefinida(p_caso_id uuid, p_entidade_id uuid, p_nome text) IS '0183: pendência complementar (não bloqueia nada) para entidade sem forma de controle declarada. Idempotente por entidade_id (motivo). Nunca decide a forma — só marca a ausência, regra 1 do CLAUDE.md.';

--
-- Name: fn_pendencia_papel_no_grupo_indefinido(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_pendencia_papel_no_grupo_indefinido(p_caso_id uuid, p_entidade_id uuid, p_nome text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_motivo text := 'papel_no_grupo_indefinido:' || p_entidade_id;
  v_pend   uuid;
begin
  select id into v_pend from pendencia
   where caso_id = p_caso_id and motivo = v_motivo and estado <> 'resolvida'
   limit 1;
  if v_pend is not null then return v_pend; end if;

  insert into pendencia
    (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, entidade_id, motivo)
  values (
    p_caso_id, 'diagnostico', 'papel_no_grupo_indefinido', 'complementar', true,
    format('A entidade "%s" ainda não tem papel no grupo (holding/operacional/veículo/coligada/'
           || 'fora do perímetro) — ninguém decidiu ainda, e o sistema não infere isso sozinho '
           || '(não há hierarquia de participação societária modelada — fatia 1.5, futura). '
           || 'O EFEITO, hoje: nenhum, porque nenhum consumidor lê `papel_no_grupo` ainda — esta '
           || 'entidade entra e sai do book exatamente como as demais. O efeito aparece nas fatias '
           || 'seguintes do plano F1: o perímetro do combinado (1.4) e a participação societária '
           || '(1.5) vão depender deste papel para decidir o que entra em cada agrupamento, e esta '
           || 'entidade ficará de fora de qualquer agrupamento automático até alguém chamar '
           || 'fn_entidade_definir_papel_no_grupo para ela.',
           p_nome),
    p_entidade_id, v_motivo)
  returning id into v_pend;

  return v_pend;
end;
$$;

--
-- Name: FUNCTION fn_pendencia_papel_no_grupo_indefinido(p_caso_id uuid, p_entidade_id uuid, p_nome text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_pendencia_papel_no_grupo_indefinido(p_caso_id uuid, p_entidade_id uuid, p_nome text) IS '0179: pendência complementar (não bloqueia nada) para entidade sem papel no grupo. Idempotente por entidade_id (motivo). Nunca decide o papel — só marca a ausência, regra 1 do CLAUDE.md.';

--
-- Name: fn_perimetro_definir_escopo(uuid, uuid, text, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_perimetro_definir_escopo(p_caso_id uuid, p_entidade_id uuid, p_escopo text, p_desde date, p_autor text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_da_entidade uuid;
  v_novo_id          uuid;
  v_vig_id           uuid;
  v_vig_desde        date;
begin
  if p_desde is null then
    raise exception 'p_desde não pode ser nulo — todo intervalo de perímetro tem início';
  end if;

  select caso_id into v_caso_da_entidade from entidade where id = p_entidade_id;
  if v_caso_da_entidade is null then
    raise exception 'entidade % não encontrada', p_entidade_id;
  end if;
  if v_caso_da_entidade <> p_caso_id then
    raise exception 'entidade % não pertence ao caso %', p_entidade_id, p_caso_id;
  end if;

  select id, desde into v_vig_id, v_vig_desde
    from perimetro
   where caso_id = p_caso_id and entidade_id = p_entidade_id and escopo = p_escopo
     and ate is null;

  if v_vig_id is not null then
    if v_vig_desde = p_desde then
      return v_vig_id;  -- já vigente desde esta data: nada a gravar (ver o cabeçalho)
    end if;
    if v_vig_desde > p_desde then
      raise exception 'a entidade já está no escopo "%" desde %, depois de %: não dá para começar o escopo antes do intervalo vigente. Para mudar o início, encerre o escopo (fn_perimetro_encerrar_escopo) ou corrija o intervalo por SQL direto.',
        p_escopo, v_vig_desde, p_desde;
    end if;
  end if;

  -- A MUDANÇA de perímetro no meio do mandato: o intervalo anterior GANHA UM FIM, não é sobrescrito.
  update perimetro
     set ate = p_desde - 1
   where caso_id = p_caso_id and entidade_id = p_entidade_id and escopo = p_escopo
     and ate is null;

  insert into perimetro (caso_id, entidade_id, escopo, desde, ate)
  values (p_caso_id, p_entidade_id, p_escopo, p_desde, null)
  returning id into v_novo_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'perimetro_escopo_definido', 'entidade:' || p_entidade_id,
          jsonb_build_object('caso_id', p_caso_id, 'escopo', p_escopo, 'desde', p_desde));

  return v_novo_id;
end;
$$;

--
-- Name: FUNCTION fn_perimetro_definir_escopo(p_caso_id uuid, p_entidade_id uuid, p_escopo text, p_desde date, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_perimetro_definir_escopo(p_caso_id uuid, p_entidade_id uuid, p_escopo text, p_desde date, p_autor text) IS '0180: o caminho de escrita que ABRE intervalo de `perimetro`; fecha o vigente anterior do mesmo (caso, entidade, escopo) com `ate = p_desde - 1` em vez de sobrescrever. 0209: confirmar o mesmo escopo com o MESMO desde é idempotente (devolve o id vigente, sem evento); p_desde ANTERIOR ao desde vigente é exceção em português (antes estourava o check perimetro_intervalo_valido). Grava evento_auditoria (ator = p_autor). Para TIRAR a entidade do escopo, fn_perimetro_encerrar_escopo.';

--
-- Name: fn_perimetro_encerrar_escopo(uuid, uuid, text, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_perimetro_encerrar_escopo(p_caso_id uuid, p_entidade_id uuid, p_escopo text, p_ate date, p_autor text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_id    uuid;
  v_desde date;
begin
  if p_ate is null then
    raise exception 'p_ate não pode ser nulo — informe o último dia em que a entidade ainda está no escopo';
  end if;

  select id, desde into v_id, v_desde
    from perimetro
   where caso_id = p_caso_id and entidade_id = p_entidade_id and escopo = p_escopo
     and ate is null;

  if v_id is null then
    raise exception 'a entidade % não tem intervalo vigente no escopo "%" neste caso: nada a encerrar (ela já foi encerrada, ou o escopo tem outro nome)',
      p_entidade_id, p_escopo;
  end if;
  if p_ate < v_desde then
    raise exception 'o intervalo vigente no escopo "%" começou em %: não dá para encerrá-lo em % (antes do começo)',
      p_escopo, v_desde, p_ate;
  end if;

  update perimetro set ate = p_ate where id = v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (p_autor, 'perimetro_escopo_encerrado', 'entidade:' || p_entidade_id,
          jsonb_build_object('caso_id', p_caso_id, 'escopo', p_escopo, 'desde', v_desde, 'ate', p_ate));

  return v_id;
end;
$$;

--
-- Name: FUNCTION fn_perimetro_encerrar_escopo(p_caso_id uuid, p_entidade_id uuid, p_escopo text, p_ate date, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_perimetro_encerrar_escopo(p_caso_id uuid, p_entidade_id uuid, p_escopo text, p_ate date, p_autor text) IS '0209: tira a entidade do escopo fechando o intervalo vigente com ate = p_ate (último dia DENTRO, inclusivo), sem abrir outro. Recusa, em português, p_ate antes do desde e a entidade sem intervalo vigente no escopo (um encerramento silencioso afirmaria uma remoção que não houve). Grava evento_auditoria perimetro_escopo_encerrado. Devolve o id do intervalo.';

--
-- Name: fn_perimetro_situacao(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_perimetro_situacao(p_caso_id uuid) RETURNS TABLE(entidade_id uuid, razao_social text, cnpj text, fantasma boolean, papel_no_grupo public.entidade_papel_no_grupo, forma_de_controle public.entidade_forma_de_controle, controladora_id uuid, percentual_participacao numeric, escopos_vigentes text[], controladores jsonb, pendencias_abertas text[], falta text[], pronta boolean)
    LANGUAGE sql STABLE
    AS $_$
  with pend as materialized (
    -- uma linha por (entidade, rótulo) das pendências de perímetro ABERTAS. A entidade vem da própria
    -- pendência ou, nas entidade_incorreta que só citam o documento, da entidade onde o documento está.
    select distinct
           coalesce(p.entidade_id, d.entidade_id,
                    case when p.motivo ~ '^contrato_social_ausente:[0-9a-f-]{36}$'
                         then substr(p.motivo, 25)::uuid end) as entidade_id,
           case
             when p.tipo = 'entidade_incorreta' then
               case when p.motivo is null or p.motivo like 'diagnostico:%' then 'entidade_incorreta'
                    else split_part(p.motivo, ':', 1) end
             when p.tipo = 'item_faltante' then 'contrato_social_ausente'
             else p.tipo::text
           end as rotulo
      from pendencia p
      left join documento d on d.id = p.documento_id
     where p.caso_id = p_caso_id
       and p.estado in ('aberta', 'em_correcao_interna', 'reenviada_ao_cliente')
       and (p.tipo in ('papel_no_grupo_indefinido', 'forma_de_controle_indefinida', 'entidade_incorreta')
            or (p.tipo = 'item_faltante' and p.motivo like 'contrato_social_ausente:%'))
  ),
  base as (
    select e.id, e.razao_social, e.cnpj, e.papel_no_grupo, e.forma_de_controle,
           e.controladora_id, e.percentual_participacao,
           coalesce((select array_agg(distinct p.escopo order by p.escopo)
                       from perimetro p
                      where p.caso_id = p_caso_id and p.entidade_id = e.id
                        and p.desde <= current_date
                        and (p.ate is null or p.ate >= current_date)), '{}'::text[]) as escopos,
           coalesce((select jsonb_agg(jsonb_build_object(
                         'controlador_id', c.id, 'nome', c.nome, 'tipo_pessoa', c.tipo_pessoa,
                         'documento', c.documento, 'percentual', ec.percentual)
                       order by c.nome, c.id)
                       from entidade_controlador ec
                       join controlador c on c.id = ec.controlador_id
                      where ec.caso_id = p_caso_id and ec.entidade_id = e.id), '[]'::jsonb) as ctrls,
           (select count(*) from entidade_controlador ec
             where ec.caso_id = p_caso_id and ec.entidade_id = e.id) as n_vinculos,
           coalesce((select array_agg(pe.rotulo order by pe.rotulo)
                       from pend pe where pe.entidade_id = e.id), '{}'::text[]) as rotulos
      from entidade e
     where e.caso_id = p_caso_id
  ),
  marcada as (
    select b.*, 'entidade_nome_suspeito' = any (b.rotulos) as eh_fantasma
      from base b
  ),
  faltas as (
    select m.*,
           case
             when m.eh_fantasma then array['entidade_fantasma_pendente_de_revisao']
             else
               array_remove(array[
                 case when m.papel_no_grupo is null then 'papel_no_grupo_indefinido' end,
                 case when m.forma_de_controle = 'indefinido' then 'forma_de_controle_indefinida' end,
                 case when m.forma_de_controle = 'controlada_por_entidade' and m.controladora_id is null
                      then 'controlada_por_entidade_sem_controladora' end,
                 case when m.forma_de_controle = 'controle_comum' and m.n_vinculos = 0
                      then 'controle_comum_sem_vinculo' end,
                 case when m.papel_no_grupo is not null and m.papel_no_grupo <> 'fora_do_perimetro'
                           and cardinality(m.escopos) = 0
                      then 'sem_escopo_vigente' end,
                 case when m.papel_no_grupo = 'fora_do_perimetro' and cardinality(m.escopos) > 0
                      then 'fora_do_perimetro_com_escopo_vigente' end
               ], null)
               || coalesce((select array_agg('pendencia_aberta:' || r order by r)
                              from unnest(m.rotulos) r
                             where not (r = 'papel_no_grupo_indefinido' and m.papel_no_grupo is null)
                               and not (r = 'forma_de_controle_indefinida'
                                        and m.forma_de_controle = 'indefinido')), '{}'::text[])
           end as falta
      from marcada m
  )
  select f.id, f.razao_social, f.cnpj, f.eh_fantasma, f.papel_no_grupo, f.forma_de_controle,
         f.controladora_id, f.percentual_participacao, f.escopos, f.ctrls, f.rotulos, f.falta,
         cardinality(f.falta) = 0
    from faltas f
   order by f.eh_fantasma, f.razao_social, f.id;
$_$;

--
-- Name: FUNCTION fn_perimetro_situacao(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_perimetro_situacao(p_caso_id uuid) IS '0208: uma linha por entidade do caso com o que falta para o perímetro estar fechado, NOMEADO em `falta` (papel_no_grupo_indefinido, forma_de_controle_indefinida, controlada_por_entidade_sem_controladora, controle_comum_sem_vinculo, sem_escopo_vigente, fora_do_perimetro_com_escopo_vigente, pendencia_aberta:<tipo>, entidade_fantasma_pendente_de_revisao). pronta = falta vazia. A fantasma (0178: pendência entidade_nome_suspeito aberta) aparece com falta própria e não conta como entidade real. Escopo vigente = perimetro com desde <= hoje e ate nulo ou >= hoje. Somente leitura, security invoker. A tela consome esta função e NÃO repete a regra.';

--
-- Name: fn_perimetro_veredito(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_perimetro_veredito(p_caso_id uuid) RETURNS TABLE(entidades integer, prontas integer, fantasmas integer, fechado boolean, fechado_motivo text, grupos jsonb, aceite_financeiro text, aceite_motivo text)
    LANGUAGE sql STABLE
    AS $$
  with s as materialized (select * from fn_perimetro_situacao(p_caso_id)),
  n as (
    select count(*) filter (where not s.fantasma)::int as reais,
           count(*) filter (where s.pronta and not s.fantasma)::int as prontas,
           count(*) filter (where s.fantasma)::int as fantasmas
      from s
  ),
  g as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'grupo_id', t.grupo_id, 'quantas', t.quantas, 'entidades', t.membros)
             order by t.grupo_id), '[]'::jsonb) as grupos
      from (select x.grupo_id, count(*) as quantas,
                   jsonb_agg(jsonb_build_object('entidade_id', x.entidade_id,
                                                'razao_social', x.razao_social)
                             order by x.razao_social, x.entidade_id) as membros
              from fn_grupo_por_controle_comum(p_caso_id) x
             group by x.grupo_id) t
  ),
  c as (
    -- COMBINADO de verdade: rotulado COMBINADO e com VALOR em mais de uma coluna de entidade
    -- (o critério de fn_documento_serve_como, 0157).
    select count(*)::int as docs
      from documento d
     where d.caso_id = p_caso_id
       and d.tipo_taxonomia = 'COMBINADO'
       and (select count(distinct ce.entidade_coluna)
              from campo_extraido ce
             where ce.documento_versao_id = fn_versao_com_extracao(d.id)
               and ce.valor_num is not null
               and ce.entidade_coluna is not null) > 1
  )
  select n.reais, n.prontas, n.fantasmas,
         (n.reais > 0 and n.prontas = n.reais and n.fantasmas = 0),
         case
           when n.reais = 0 and n.fantasmas = 0 then
             'O caso não tem nenhuma entidade: zero entidades não é perímetro fechado, é perímetro que nunca foi montado (nenhum documento foi atribuído a uma empresa).'
           when n.reais = 0 then
             format('O caso só tem %s entidade(s) fantasma (nome de coluna, aba ou arquivo tratado como empresa) e nenhuma entidade real: não há perímetro a fechar.', n.fantasmas)
           when n.fantasmas > 0 and n.prontas < n.reais then
             format('%s de %s entidades reais ainda têm falta, e há %s entidade(s) fantasma sem revisão: os documentos delas ficam fora do book de qualquer empresa real até alguém fundir ou descartar.', n.reais - n.prontas, n.reais, n.fantasmas)
           when n.fantasmas > 0 then
             format('Todas as %s entidades reais estão prontas, mas há %s entidade(s) fantasma sem revisão: os documentos delas ficam fora do book de qualquer empresa real até alguém fundir ou descartar.', n.reais, n.fantasmas)
           when n.prontas < n.reais then
             format('%s de %s entidades ainda têm falta (veja fn_perimetro_situacao): enquanto isso o perímetro não afirma quem entra no combinado.', n.reais - n.prontas, n.reais)
           else
             format('As %s entidades têm papel, forma de controle e escopo coerentes e nenhuma pendência de perímetro aberta. Isto diz que o CADASTRO está completo, não que o perímetro bate com o combinado do cliente (ver aceite_financeiro).', n.reais)
         end,
         g.grupos,
         case when c.docs > 0 then 'pendente_conferencia' else 'nao_verificado' end,
         case when c.docs > 0 then
           format('Existe(m) %s documento(s) COMBINADO com valor em mais de uma entidade, mas o sistema NÃO compara o perímetro com ele: a conferência é humana. Enquanto ninguém conferir, o perímetro pode incluir ou excluir uma empresa que o combinado do cliente trata diferente, e todo número consolidado a partir dele herda a diferença sem aviso.', c.docs)
         else
           'Não há documento COMBINADO do cliente com valor em mais de uma entidade neste caso, então o perímetro não foi comparado com nada. O efeito: o perímetro cadastrado pode incluir ou excluir uma empresa que o cliente trata diferente, e o combinado e a consolidação calculados a partir dele herdam a diferença sem aviso. Um grupo por controle comum frequentemente nunca preparou combinado; o aceite fica nao_verificado, não ok.'
         end
    from n, g, c;
$$;

--
-- Name: FUNCTION fn_perimetro_veredito(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_perimetro_veredito(p_caso_id uuid) IS '0208: o veredito do perímetro do caso numa linha: entidades (reais, sem as fantasmas), prontas, fantasmas, fechado (>0 reais, todas prontas, 0 fantasmas) e o motivo por extenso, grupos por controle comum (fn_grupo_por_controle_comum resumido) e o aceite financeiro, que NUNCA é ok: nao_verificado (sem combinado do cliente para comparar, com o efeito dito) ou pendente_conferencia (há combinado, a conferência é humana). Somente leitura, security invoker.';

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: entidade; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entidade (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    razao_social text NOT NULL,
    cnpj text,
    papel_no_grupo public.entidade_papel_no_grupo,
    controladora_id uuid,
    percentual_participacao numeric(6,3),
    forma_de_controle public.entidade_forma_de_controle DEFAULT 'indefinido'::public.entidade_forma_de_controle NOT NULL,
    CONSTRAINT entidade_forma_de_controle_coerente CHECK (((forma_de_controle = 'indefinido'::public.entidade_forma_de_controle) OR ((forma_de_controle = 'controlada_por_entidade'::public.entidade_forma_de_controle) AND (controladora_id IS NOT NULL)) OR ((forma_de_controle = 'controle_comum'::public.entidade_forma_de_controle) AND (controladora_id IS NULL)))),
    CONSTRAINT entidade_nao_controla_a_si_mesma CHECK (((controladora_id IS NULL) OR (controladora_id <> id))),
    CONSTRAINT entidade_percentual_valido CHECK (((percentual_participacao IS NULL) OR ((percentual_participacao > (0)::numeric) AND (percentual_participacao <= (100)::numeric))))
);

--
-- Name: COLUMN entidade.papel_no_grupo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.entidade.papel_no_grupo IS '0179: enum entidade_papel_no_grupo (antes: text livre, NULL em todo caso — 0001 a 0178). NULL continua sendo o estado inicial de TODA entidade nova (fn_upsert_entidade nunca o passa no insert) — a ausência é honesta enquanto ninguém decidir, e fn_pendencia_papel_no_grupo_indefinido marca essa ausência sem afirmar hierarquia nenhuma. Só fn_entidade_definir_papel_no_grupo escreve aqui.';

--
-- Name: COLUMN entidade.controladora_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.entidade.controladora_id IS '0181 (fatia 1.5 do plano F1): a controladora DIRETA desta entidade — no máximo UMA, aqui. NÃO é um grafo completo de participação societária: sócios minoritários múltiplos e participação cruzada NÃO cabem neste modelo simples, e isso é deliberado (ver cabeçalho da 0181) — é a cadeia de controle que a F4 (consolidação/intercompany) vai percorrer subindo por esta coluna. NULL por padrão em toda entidade nova (fn_upsert_entidade nunca o passa no insert) — não há contrato social lido pelo pipeline hoje para inferir isto automaticamente (regra 1 do CLAUDE.md). Só `fn_entidade_definir_participacao` escreve aqui, e só depois de perguntar a `fn_entidade_criaria_ciclo_participacao` se o ciclo se fecharia.';

--
-- Name: COLUMN entidade.percentual_participacao; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.entidade.percentual_participacao IS '0181: o percentual que `controladora_id` detém desta entidade, em (0, 100]. NULL sempre que `controladora_id` for NULL (percentual sem controladora não significa nada — `fn_entidade_definir_participacao` recusa a combinação inversa). `numeric(6,3)`: até 999,999% de headroom não faz sentido para um percentual real, mas a precisão cobre 100,000 com folga de formatação sem exigir um tipo mais estreito — ajustar depois é uma migration aditiva se algum dado real pedir mais casas.';

--
-- Name: COLUMN entidade.forma_de_controle; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.entidade.forma_de_controle IS '0183: o estado DECLARADO de controle desta entidade — `indefinido` (ninguém decidiu ainda, estado inicial de TODA entidade, inclusive as pré-existentes a esta migration), `controlada_por_entidade` (há controladora empresa — exige controladora_id não nulo) ou `controle_comum` (grupo horizontal sob controle comum — exige controladora_id nulo E pelo menos um vínculo em entidade_controlador, guardados por entidade_forma_de_controle_coerente e trg_entidade_forma_de_controle_tem_vinculo). É o que torna controladora_id NULO distinguível de um não preenchido (regra 7 do CLAUDE.md — critério de pronto da fatia 1.7). NADA é inferido: só fn_entidade_definir_forma_de_controle escreve aqui.';

--
-- Name: CONSTRAINT entidade_forma_de_controle_coerente ON entidade; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT entidade_forma_de_controle_coerente ON public.entidade IS '0183: recusa a incoerência entre forma_de_controle e controladora_id mesmo por INSERT/UPDATE direto, sem passar pela função — `controlada_por_entidade` sem controladora_id, ou `controle_comum` COM controladora_id, afirmariam um estado que os dados contradizem. `indefinido` não exige nada — é a ausência (regra 1 do CLAUDE.md). É a MEDIÇÃO NÃO-VAZIA (a) da migration 0183 — ver o cabeçalho dela.';

--
-- Name: CONSTRAINT entidade_nao_controla_a_si_mesma ON entidade; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT entidade_nao_controla_a_si_mesma ON public.entidade IS '0181: recusa `controladora_id = id` mesmo por INSERT/UPDATE direto, sem passar pela função — é o ciclo de UM salto (o caso trivial que `fn_entidade_criaria_ciclo_participacao` também pega, mas o `check` protege o caminho que não chama a função nenhuma).';

--
-- Name: CONSTRAINT entidade_percentual_valido ON entidade; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT entidade_percentual_valido ON public.entidade IS '0181: percentual de participação tem de estar em (0, 100] — zero ou negativo não é participação, e mais de 100% não existe. Protege INSERT/UPDATE direto, mesma doutrina do `perimetro_intervalo_valido` da 0180.';

--
-- Name: fn_perimetro_vigente(uuid, text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_perimetro_vigente(p_caso_id uuid, p_escopo text, p_data date DEFAULT CURRENT_DATE) RETURNS SETOF public.entidade
    LANGUAGE sql STABLE
    AS $$
  select e.*
    from perimetro p
    join entidade e on e.id = p.entidade_id
   where p.caso_id = p_caso_id
     and p.escopo = p_escopo
     and p.desde <= p_data
     and (p.ate is null or p.ate >= p_data)
   order by e.razao_social;
$$;

--
-- Name: FUNCTION fn_perimetro_vigente(p_caso_id uuid, p_escopo text, p_data date); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_perimetro_vigente(p_caso_id uuid, p_escopo text, p_data date) IS '0180: quem está no escopo de um COMBINADO numa data (padrão: hoje). Consumidor mínimo de `perimetro` — prova que desde/ate respondem "quem estava dentro em 30/06" diferente de "quem está dentro hoje" depois de uma troca de escopo. O consumidor REAL (o combinado calculado respeitando o perímetro) é F1.6/F4, fora do escopo desta fatia — ver seção 12.3 do roadmap.';

--
-- Name: fn_periodo_canonico(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_periodo_canonico(p_tipo text, p_ref text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
declare
  r text := lower(trim(coalesce(p_ref, '')));
  m text[]; ano text; n int; toks text[]; t text; acc text[] := '{}';
begin
  if r = '' then return null; end if;
  r := replace(r, ' ', '');

  if r ~ '^\d{4}-\d{2}-\d{2}$' then return r; end if;                    -- ISO YYYY-MM-DD
  m := regexp_match(r, '^(\d{2})/(\d{2})/(\d{4})$');
  if m is not null then return m[3] || '-' || m[2] || '-' || m[1]; end if; -- DD/MM/YYYY
  m := regexp_match(r, '^(\d{2})/(\d{2})/(\d{2})$');
  if m is not null then return fn_ano4(m[3]) || '-' || m[2] || '-' || m[1]; end if; -- DD/MM/YY
  m := regexp_match(r, '^(\d{1,2})m(\d{2,4})$');
  if m is not null then
    ano := fn_ano4(m[2]); n := (m[1])::int;
    return case when n = 12 then ano else n || 'm' || ano end;          -- NM (12M25 → ano)
  end if;
  m := regexp_match(r, '^(\d)t(\d{2,4})$');
  if m is not null then return m[1] || 't' || fn_ano4(m[2]); end if;     -- trimestre (1T25)
  m := regexp_match(r, '^l(\d+)m$');
  if m is not null then return 'l' || m[1] || 'm'; end if;              -- últimos N meses (L24M)

  if position(',' in r) > 0 then                                        -- múltiplos exercícios
    toks := regexp_split_to_array(r, ',');
    foreach t in array toks loop
      t := trim(t);
      if t ~ '^\d{1,2}$' then t := fn_ano4(t); end if;
      if t <> '' then acc := array_append(acc, t); end if;
    end loop;
    acc := (select array_agg(x order by x) from unnest(acc) x);
    return array_to_string(acc, ',');
  end if;

  if r ~ '^\d{4}$' then return r; end if;                               -- ano 4 dígitos
  if r ~ '^\d{2}$' then return fn_ano4(r); end if;                      -- ano 2 dígitos
  return r;                                                             -- texto livre normalizado
end;
$_$;

--
-- Name: fn_periodo_e_parcial(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_periodo_e_parcial(p_coluna text, p_tipo_documento text, p_periodo_tipo text, p_referencia text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $_$
  select (coalesce(p_coluna, '') !~ '(31/12|12/31|-12-31)'
       and (   p_tipo_documento = 'BALANCETE'
            or p_periodo_tipo in ('mes', 'trimestre')
            or (p_periodo_tipo = 'data-base' and coalesce(p_referencia, '') !~ '(31/12|12/31|-12-31)')
            or coalesce(p_referencia, '') ~* '^\s*[1-4]\s*t\s*\d{2,4}\s*$'
            or coalesce(p_referencia, '') ~ '^\s*(0?[1-9]|1[01])/(19|20)\d{2}\s*$'
            or coalesce(p_referencia, '') ~ '^\s*(19|20)\d{2}-(0[1-9]|1[01])\s*$'
            or (coalesce(p_referencia, '') ~* '\d{1,2}/\d{1,2}/(19|20)\d{2}\s*(-|–|—|a|à|até|ate)\s*\d{1,2}/\d{1,2}/(19|20)\d{2}'
                and coalesce(p_referencia, '') !~ '^\s*0?1/0?1/(19|20)\d{2}\s*(-|–|—|a|à|até|ate)\s*31/12/(19|20)\d{2}\s*$')
           ))
$_$;

--
-- Name: FUNCTION fn_periodo_e_parcial(p_coluna text, p_tipo_documento text, p_periodo_tipo text, p_referencia text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_periodo_e_parcial(p_coluna text, p_tipo_documento text, p_periodo_tipo text, p_referencia text) IS 'Ocorrência de período PARCIAL (balancete, mês, trimestre, intervalo que não é o ano, data-base que não é 31/12) — só entra no ano em que a entidade não tem anual da mesma família (0199 c, 0200). Conta única (0201).';

--
-- Name: fn_periodo_por_extenso(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_periodo_por_extenso(p_tipo text, p_referencia text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
declare
  anos  int[];
  m     text[];
  trim_ text;
  lista text;
begin
  if p_referencia is null or length(trim(p_referencia)) = 0 then
    return null;
  end if;

  -- JANELA MÓVEL: é uma janela, e a frase diz isso. Não tem ano para dizer —
  -- desde a 0122 `fn_anos_texto` também não inventa um.
  m := regexp_match(p_referencia, '(^|[^0-9A-Za-z])[Ll]([0-9]{1,3})[Mm]([^0-9A-Za-z]|$)');
  if m is not null then
    return 'um período de ' || m[2] || ' meses';
  end if;

  anos := fn_anos_do_periodo(p_referencia);

  -- TRIMESTRE: o ano vem primeiro (ver o cabeçalho), o trimestre entre
  -- parênteses. Sem ano identificado, cai no fallback do fim.
  m := regexp_match(p_referencia, '([1-4])[Tt]([0-9]{2,4})');
  if m is not null and cardinality(anos) >= 1 then
    return anos[cardinality(anos)]::text || ' (' || m[1] || 'º trimestre)';
  end if;

  if cardinality(anos) = 0 then
    -- NÃO ENTENDI O RÓTULO: devolvo o rótulo. Um período que o sistema não
    -- soube ler tem de aparecer como está, para quem lê perceber — sumir com
    -- ele deixaria a pergunta afirmando um exercício que ninguém verificou.
    return trim(p_referencia);
  end if;

  if cardinality(anos) = 1 then
    return anos[1]::text;
  end if;

  if cardinality(anos) = 2 then
    return anos[1]::text || ' e ' || anos[2]::text;
  end if;

  -- Três ou mais: intervalo quando são seguidos ("2023 a 2025"), lista quando
  -- há buraco ("2021, 2023 e 2025") — o intervalo afirmaria exercícios que o
  -- documento não traz.
  if anos[cardinality(anos)] - anos[1] = cardinality(anos) - 1 then
    return anos[1]::text || ' a ' || anos[cardinality(anos)]::text;
  end if;

  select string_agg(a::text, ', ' order by a) into lista
  from unnest(anos[1:cardinality(anos) - 1]) a;
  return lista || ' e ' || anos[cardinality(anos)]::text;
end;
$_$;

--
-- Name: FUNCTION fn_periodo_por_extenso(p_tipo text, p_referencia text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_periodo_por_extenso(p_tipo text, p_referencia text) IS 'O período como se escreve para o CLIENTE (0122), na forma que cabe depois de "de"/"em": "2025", "2024 e 2025", "2023 a 2025", "2021, 2023 e 2025", "2025 (1º trimestre)", "um período de 36 meses". Rótulo sem ano identificável volta como veio.';

--
-- Name: fn_periodos_compativeis(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_periodos_compativeis(p_periodo_a uuid, p_periodo_b uuid) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
declare
  ta text; ra text; tb text; rb text; aa int[]; ab int[];
begin
  if p_periodo_a is null or p_periodo_b is null then return true; end if;
  if p_periodo_a = p_periodo_b then return true; end if;
  select tipo, referencia into ta, ra from periodo where id = p_periodo_a;
  select tipo, referencia into tb, rb from periodo where id = p_periodo_b;
  aa := fn_anos_periodo(ta, ra);
  ab := fn_anos_periodo(tb, rb);
  if cardinality(aa) = 0 or cardinality(ab) = 0 then return true; end if;
  return aa && ab; -- intersecção de arrays
end;
$$;

--
-- Name: fn_periodos_compativeis_array(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_periodos_compativeis_array(p_caso_id uuid, p_periodo_id uuid) RETURNS uuid[]
    LANGUAGE sql STABLE
    AS $$
  -- O array de períodos do laço, fatorado: ele é idêntico nas seis checagens
  -- que têm laço, e escrevê-lo seis vezes é como as duas contas de espera do
  -- portal divergiram.
  select coalesce(
    (select array_agg(p.id order by (p.id = p_periodo_id) desc, p.referencia)
     from periodo p
     where p.caso_id = p_caso_id
       and (p.id = p_periodo_id or fn_periodos_compativeis(p.id, p_periodo_id))),
    array[p_periodo_id]);
$$;

--
-- Name: FUNCTION fn_periodos_compativeis_array(p_caso_id uuid, p_periodo_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_periodos_compativeis_array(p_caso_id uuid, p_periodo_id uuid) IS 'Os períodos compatíveis do caso, o do documento primeiro (0152). Fatorado das seis checagens que têm laço de período — seis cópias da mesma conta é como as duas esperas do portal divergiram.';

--
-- Name: fn_periodos_equivalentes(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_periodos_equivalentes(p_tipo_a text, p_ref_a text, p_tipo_b text, p_ref_b text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select case
    when fn_periodo_canonico(p_tipo_a, p_ref_a) is null
      or fn_periodo_canonico(p_tipo_b, p_ref_b) is null then true
    when fn_periodo_canonico(p_tipo_a, p_ref_a) = fn_periodo_canonico(p_tipo_b, p_ref_b) then true
    when cardinality(fn_anos_periodo(p_tipo_a, p_ref_a)) = 0
      or cardinality(fn_anos_periodo(p_tipo_b, p_ref_b)) = 0 then true
    else fn_anos_periodo(p_tipo_a, p_ref_a) = fn_anos_periodo(p_tipo_b, p_ref_b)
  end;
$$;

--
-- Name: fn_pode_renomear_por_cnpj(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_pode_renomear_por_cnpj(p_atual text, p_novo text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
  a      text[] := string_to_array(fn_entidade_canonica_forte(p_atual), ' ');
  b      text[] := string_to_array(fn_entidade_canonica_forte(p_novo), ' ');
  curto  text[];
  longo  text[];
  i      int;
  j      int;
  casou  boolean;
begin
  -- (b) o nome atual está provadamente contaminado pelo endereço.
  if fn_nome_parece_ter_endereco_colado(p_atual)
     and not fn_nome_parece_ter_endereco_colado(p_novo) then
    return true;
  end if;

  if a is null or b is null then return false; end if;

  if coalesce(array_length(a, 1), 0) <= coalesce(array_length(b, 1), 0) then
    curto := a; longo := b;
  else
    curto := b; longo := a;
  end if;

  -- O lado contido precisa de um token significativo, mesma régua de 4+ que
  -- `fn_mesma_entidade` (0030) usa: "DE" contido em tudo não é parentesco.
  if not exists (select 1 from unnest(curto) t where length(t) >= 4) then
    return false;
  end if;

  -- (a) o curto é uma sequência CONTÍGUA de tokens do longo?
  for i in 0 .. coalesce(array_length(longo, 1), 0) - coalesce(array_length(curto, 1), 0) loop
    casou := true;
    for j in 1 .. array_length(curto, 1) loop
      if longo[i + j] is distinct from curto[j] then casou := false; exit; end if;
    end loop;
    if casou then return true; end if;
  end loop;

  return false;
end;
$$;

--
-- Name: FUNCTION fn_pode_renomear_por_cnpj(p_atual text, p_novo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_pode_renomear_por_cnpj(p_atual text, p_novo text) IS '0171: o CNPJ já provou que são a mesma empresa — dá para trocar o nome? Sim quando um nome é TRUNCAMENTO do outro (sequência contígua de tokens, em qualquer ponta) ou quando o atual tem cara de endereço colado e o novo não. NÃO basta "os nomes se parecem": a primeira versão desta guarda media comprimento de prefixo e autorizava trocar PADARIA DO JOAO por PADARIA DO JOSE.';

--
-- Name: fn_premissa_valores_sugeridos(text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_premissa_valores_sugeridos(p_codigo text, p_ano_inicial integer, p_anos integer DEFAULT 5) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select coalesce(jsonb_object_agg(x.ano::text, x.mediana), '{}'::jsonb)
  from (
    -- Uma mediana por ano: a coleta MAIS RECENTE. `indice_macro_expectativa` é
    -- append-only por (serie, ano_ref, coletado_em) — o seed tem IPCA/2026 em
    -- duas coletas, e sem o distinct on a mais velha poderia ganhar.
    select distinct on (e.ano_ref) e.ano_ref as ano, e.mediana
    from indice_macro_expectativa e
    where e.serie = p_codigo
      and e.ano_ref between p_ano_inicial and p_ano_inicial + p_anos - 1
    order by e.ano_ref, e.coletado_em desc
  ) x;
$$;

--
-- Name: FUNCTION fn_premissa_valores_sugeridos(p_codigo text, p_ano_inicial integer, p_anos integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_premissa_valores_sugeridos(p_codigo text, p_ano_inicial integer, p_anos integer) IS 'Valores por ano que o Focus afirma para uma premissa macro (mediana da coleta mais recente de cada ano). Ano sem expectativa publicada fica FORA — ausência é ausência.';

--
-- Name: premissa_catalogo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.premissa_catalogo (
    codigo text NOT NULL,
    nome text NOT NULL,
    natureza public.premissa_natureza NOT NULL,
    formula public.premissa_formula NOT NULL,
    unidade text,
    aplica_em text[] DEFAULT '{}'::text[] NOT NULL,
    setores text[] DEFAULT '{}'::text[] NOT NULL,
    fonte text,
    descricao text,
    ativo boolean DEFAULT true NOT NULL
);

--
-- Name: TABLE premissa_catalogo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.premissa_catalogo IS 'Vocabulário de premissas de projeção. Premissa nova = LINHA nova aqui, sem código novo; fórmula-tipo nova = primitiva nova no gerador. `setores` vazio = base comum a todo setor.';

--
-- Name: fn_premissas_sugeridas(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_premissas_sugeridas(p_setor text DEFAULT NULL::text) RETURNS SETOF public.premissa_catalogo
    LANGUAGE sql STABLE
    AS $$
  select *
  from premissa_catalogo
  where ativo
    and (cardinality(setores) = 0 or (p_setor is not null and p_setor = any(setores)))
  order by natureza, codigo;
$$;

--
-- Name: fn_radicais_rotulo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_radicais_rotulo(p_chave text) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$
  select coalesce((
    select array_agg(distinct left(w, 5) order by left(w, 5))
    from unnest(regexp_split_to_array(
      regexp_replace(fn_normalizar_texto(p_chave), '[^a-z0-9]+', ' ', 'g'), '\s+')) as w
    where w <> ''
  ), array[]::text[]);
$$;

--
-- Name: FUNCTION fn_radicais_rotulo(p_chave text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_radicais_rotulo(p_chave text) IS 'Radicais de 5 letras das palavras de um rótulo, ordenados e sem repetição. Extraído de fn_rotulo_contido na 0102 para ser calculado uma vez por linha lógica em vez de duas vezes por PAR de linhas comparadas.';

--
-- Name: fn_reabrir_caso(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reabrir_caso(p_caso_id uuid, p_autor text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_nome text;
  v_ja   timestamptz;
begin
  select nome, fechado_em into v_nome, v_ja from caso where id = p_caso_id;
  if v_nome is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Este mandato não existe mais — talvez alguém já o tenha excluído.');
  end if;
  if v_ja is null then
    return jsonb_build_object('reaberto', true, 'nome', v_nome, 'ja_estava', true);
  end if;

  update caso set fechado_em = null, fechado_por = null, motivo_fechamento = null
   where id = p_caso_id;

  insert into evento_auditoria (ator, acao, entidade_ref, antes)
    values (p_autor, 'caso_reaberto', 'caso:'||p_caso_id,
            jsonb_build_object('nome', v_nome, 'fechado_em', v_ja));

  return jsonb_build_object('reaberto', true, 'nome', v_nome);
end;
$$;

--
-- Name: FUNCTION fn_reabrir_caso(p_caso_id uuid, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reabrir_caso(p_caso_id uuid, p_autor text) IS 'Desfaz fn_fechar_caso. Existe para que fechar não precise de coragem: ação sem volta faz a pessoa não usar, e a lista de mandatos volta a crescer sem fim.';

--
-- Name: fn_reavaliar_guardas_extracao(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reavaliar_guardas_extracao(p_documento_versao_id uuid, p_autor text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_g            jsonb;
  v_documento_id uuid;
  v_caso_id      uuid;
  v_pendencia_id uuid;
  v_abertas      text[] := '{}';
  v_resolvidas   text[] := '{}';
begin
  select d.id, d.caso_id into v_documento_id, v_caso_id
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;
  if v_documento_id is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'documento_versao inexistente — nada a reavaliar.');
  end if;

  v_g := fn_avaliar_guardas_extracao(p_documento_versao_id);

  -- ----- Sinal 1 -------------------------------------------------------------
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:padrao_suspeito:' || v_documento_id and estado <> 'resolvida'
    limit 1;
  if (v_g->>'padrao_suspeito')::boolean then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'extracao', 'extracao_padrao_suspeito', 'importante', true,
          format('%s contas diferentes, na MESMA coluna, vieram com o MESMO valor material (%s) — padrão '
                 'típico de fabricação/alucinação, não de dado real. Conferir contra o arquivo original. '
                 'Contas: %s',
                 v_g->>'n_contas_repetindo', round((v_g->>'valor_repetido')::numeric, 2),
                 array_to_string(array(select jsonb_array_elements_text(v_g->'rotulos_repetindo')), '; ')),
          v_documento_id, 'extracao:padrao_suspeito:' || v_documento_id);
      v_abertas := v_abertas || 'extracao_padrao_suspeito'::text;
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(),
                         resolvida_por = p_autor || ' (reavaliação: a regra de hoje não abriria)'
      where id = v_pendencia_id;
    v_resolvidas := v_resolvidas || 'extracao_padrao_suspeito'::text;
  end if;

  -- ----- Sinal 2 -------------------------------------------------------------
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:baixa_confianca:' || v_documento_id and estado <> 'resolvida'
    limit 1;
  if (v_g->>'baixa_confianca')::boolean then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'extracao', 'extracao_baixa_confianca', 'importante', true,
          format('%s de %s linhas extraídas vieram com confiança abaixo de 70%%. Revisar antes de aceitar.',
                 v_g->>'n_baixa_confianca', v_g->>'n_campos'),
          v_documento_id, 'extracao:baixa_confianca:' || v_documento_id);
      v_abertas := v_abertas || 'extracao_baixa_confianca'::text;
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(),
                         resolvida_por = p_autor || ' (reavaliação: a regra de hoje não abriria)'
      where id = v_pendencia_id;
    v_resolvidas := v_resolvidas || 'extracao_baixa_confianca'::text;
  end if;

  -- ----- Sinal 3: só RESOLVE (ver o comentário do cabeçalho) -----------------
  if not (v_g->>'vazia')::boolean then
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:falhou:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(),
                           resolvida_por = p_autor || ' (reavaliação: a versão tem linhas)'
        where id = v_pendencia_id;
      v_resolvidas := v_resolvidas || 'extracao_falhou'::text;
    end if;
  end if;

  return jsonb_build_object('documento_versao_id', p_documento_versao_id,
                            'guardas', v_g,
                            'abertas', to_jsonb(v_abertas),
                            'resolvidas', to_jsonb(v_resolvidas));
end;
$$;

--
-- Name: fn_recalcular_vigencia_arquivo_oficial(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_recalcular_vigencia_arquivo_oficial(p_caso uuid, p_chave text) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
  v_vigente uuid;
  v_n_ret   int;
begin
  if p_chave is null then return; end if;   -- sem identidade, sem competição

  -- 1) Zera o grupo ANTES de eleger (o índice único parcial é checado linha a linha) e limpa o motivo
  --    de ambiguidade antigo, que pode já não valer.
  update arquivo_oficial set vigente = false, substituido_por = null, detalhe = detalhe - 'vigencia'
   where caso_id = p_caso and chave_natural = p_chave
     and (vigente or substituido_por is not null or detalhe ? 'vigencia');

  -- 2) Mais de uma retificadora lida e nenhuma cadeia: ausência visível, não palpite.
  select count(*) into v_n_ret from arquivo_oficial
   where caso_id = p_caso and chave_natural = p_chave and status = 'lido' and retificadora;
  if v_n_ret > 1 then
    update arquivo_oficial
       set detalhe = detalhe || jsonb_build_object('vigencia',
         'ambigua: ' || v_n_ret || ' retificadoras da mesma escrituração sem cadeia de recibo; escolha manual')
     where caso_id = p_caso and chave_natural = p_chave and status = 'lido';
    return;
  end if;

  -- 3) Retificadora vence original; entre originais, a registrada por último. Só status 'lido' concorre.
  select id into v_vigente
    from arquivo_oficial
   where caso_id = p_caso and chave_natural = p_chave and status = 'lido'
   order by retificadora desc, seq desc
   limit 1;

  if v_vigente is null then return; end if;   -- só há arquivo mal lido: fica sem vigente, de propósito

  update arquivo_oficial set vigente = true where id = v_vigente;
  -- 4) As outras lidas ficam como evidência, apontando para a vigente.
  update arquivo_oficial set substituido_por = v_vigente
   where caso_id = p_caso and chave_natural = p_chave and status = 'lido' and id <> v_vigente;
end $$;

--
-- Name: FUNCTION fn_recalcular_vigencia_arquivo_oficial(p_caso uuid, p_chave text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_recalcular_vigencia_arquivo_oficial(p_caso uuid, p_chave text) IS 'Regra G9 de versão vigente por (caso, chave_natural): retificadora vence original, última registrada vence entre iguais; mais de uma retificadora lida = sem vigente + detalhe.vigencia. Interna de fn_registrar_arquivo_oficial. 0206.';

--
-- Name: fn_recomputar_completude(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_recomputar_completude(p_caso_id uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_faltantes text[];
  v_sem_conteudo text[];
  v_cod text;
  v_nao_sobre boolean;
  v_status_atual caso_status;
  v_novo_status caso_status;
  v_pend_id uuid;
  -- 0113/0119: passo (2b)
  v_ex record;
  v_motivo text;
  v_motivos_ausentes text[] := '{}';
  v_linhas_ausentes jsonb := '[]'::jsonb;
  -- 0188
  v_desc text;
begin
  -- ----- (1) obrigatório sem NENHUM documento QUE SIRVA (0006/0157) ----------
  -- 0157: "sem documento" deixava de contar um documento que ESTÁ no caso só
  -- porque o classificador o rotulou diferente do que ele estruturalmente é —
  -- medido no lote 7377, dois COMBINADOs (8 empresas na planilha) chamados de
  -- BALANCO travavam o item COMBINADO como ausente e bloqueante. Agora a
  -- pergunta é fn_documento_serve_como(documento, tipo): a regra do rótulo,
  -- mais — só para COMBINADO — a decisão de fn_combinado_estrutural_apto
  -- (revisão da 0157, achados A e B: fonte permitida e conteúdo exigido).
  select array_agg(t.codigo order by t.codigo) into v_faltantes
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and not exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and fn_documento_serve_como(d.id, t.codigo)
    );
  v_faltantes := coalesce(v_faltantes, array[]::text[]);

  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:n8n'
  where p.caso_id = p_caso_id and p.tipo = 'item_faltante' and p.estado <> 'resolvida'
    and not (p.descricao = any (select 'Item obrigatório do Kit Básico ausente: '||x from unnest(v_faltantes) x));

  foreach v_cod in array v_faltantes loop
    select nao_sobrepujavel into v_nao_sobre from taxonomia_tipo_documento where codigo = v_cod;
    if not exists (
      select 1 from pendencia p
      where p.caso_id = p_caso_id and p.tipo = 'item_faltante'
        and p.estado <> 'resolvida'
        and p.descricao = 'Item obrigatório do Kit Básico ausente: '||v_cod
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
        values (p_caso_id, 'completude', 'item_faltante', 'bloqueante',
                not coalesce(v_nao_sobre,false),
                'Item obrigatório do Kit Básico ausente: '||v_cod);
    end if;
  end loop;

  -- ----- (2) obrigatório PRESENTE mas sem uma linha aproveitável (0036) ------
  select array_agg(t.codigo order by t.codigo) into v_sem_conteudo
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and d.tipo_taxonomia = t.codigo
    )
    and fn_linhas_do_tipo(p_caso_id, t.codigo) = 0;
  v_sem_conteudo := coalesce(v_sem_conteudo, array[]::text[]);

  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
  where p.caso_id = p_caso_id and p.tipo = 'item_sem_conteudo' and p.estado <> 'resolvida'
    and not (p.motivo = any (select 'completude:sem_conteudo:'||x from unnest(v_sem_conteudo) x));

  foreach v_cod in array v_sem_conteudo loop
    if not exists (
      select 1 from pendencia p
      where p.caso_id = p_caso_id and p.tipo = 'item_sem_conteudo'
        and p.estado <> 'resolvida' and p.motivo = 'completude:sem_conteudo:'||v_cod
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, motivo)
        values (p_caso_id, 'completude', 'item_sem_conteudo', 'bloqueante', false,
                format('Item obrigatório "%s" foi RECEBIDO, mas nenhuma linha foi extraída de nenhuma '
                       'versão dele: o documento existe e o book sai VAZIO nesta parte. Causas comuns: '
                       'formato que o pipeline ainda não converte (.xlsx/.docx), arquivo ilegível, ou '
                       'chamada de extração que falhou. Conferir o arquivo e reenviar — completude não '
                       'é validade (Arquitetura do Sistema/3 Estado e Execução/07), e um obrigatório sem conteúdo não passa o Portão 2.',
                       v_cod),
                'completude:sem_conteudo:'||v_cod);
    end if;
  end loop;

  -- ----- (2b) 0113/0119: tipo COM conteúdo, mas sem uma LINHA exigida --------
  -- 0119: a cobrança desce ao nível da ENTIDADE quando o escopo pede. O motivo
  -- ganha o sufixo canônico da entidade (chave estável mesmo que a grafia da
  -- razão social varie entre extrações), `entidade_id` vai na pendência, e a
  -- descrição nomeia a empresa. Pendência de formato velho (sem sufixo) sai da
  -- lista corrente e é resolvida no fim do bloco — é a transição, e a trilha
  -- guarda as duas gerações.
  for v_ex in
    select * from fn_exigencias_do_caso(p_caso_id) x where not x.satisfeita
  loop
    v_motivo := 'completude:linha_exigida:' || v_ex.tipo_taxonomia || ':' || v_ex.conceito
                || case when v_ex.entidade is not null
                        then ':' || fn_entidade_canonica(v_ex.entidade)
                        else '' end;
    v_motivos_ausentes := v_motivos_ausentes || v_motivo;
    v_linhas_ausentes := v_linhas_ausentes || jsonb_build_object(
      'tipo', v_ex.tipo_taxonomia, 'conceito', v_ex.conceito,
      'rotulo', v_ex.rotulo, 'origem', v_ex.origem,
      'entidade', v_ex.entidade,
      -- 0188: o que o documento traz no lugar, quando traz.
      'alternativa', v_ex.alternativa_rotulo);

    -- 0188: o texto sai de UM lugar, com o recado da alternativa quando ela
    -- casou (taxonomia_linha_alternativa). Sem alternativa, é o texto de sempre.
    v_desc := fn_descricao_linha_exigida(v_ex.tipo_taxonomia, v_ex.entidade, v_ex.rotulo,
                                         v_ex.depende_de, v_ex.origem,
                                         v_ex.alternativa_rotulo, v_ex.alternativa_recado);

    select id into v_pend_id from pendencia p
    where p.caso_id = p_caso_id and p.tipo = 'linha_exigida_ausente'
      and p.estado <> 'resolvida'
      and p.motivo = v_motivo
    limit 1;

    if v_pend_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel,
                             descricao, entidade_id, motivo)
        values (p_caso_id, 'completude', 'linha_exigida_ausente',
                coalesce(v_ex.severidade, 'importante')::pendencia_severidade,
                coalesce(v_ex.sobrepujavel, true),
                v_desc,
                v_ex.entidade_id,
                v_motivo);
    else
      -- 0188: a DESCRIÇÃO também é atualizada. Até a 0187 só a política era, e
      -- a pendência aberta antes de uma alternativa existir ficava para sempre
      -- com o texto da doença errada.
      update pendencia set
        severidade   = coalesce(v_ex.severidade, 'importante')::pendencia_severidade,
        sobrepujavel = coalesce(v_ex.sobrepujavel, true),
        descricao    = case when descricao is distinct from v_desc then v_desc else descricao end
      where id = v_pend_id;
    end if;
  end loop;

  -- A linha apareceu, a exigência foi desativada, ou o formato do motivo mudou
  -- (a transição 0113 → 0119): resolve sozinha, como as da 0036.
  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
  where p.caso_id = p_caso_id and p.tipo = 'linha_exigida_ausente' and p.estado <> 'resolvida'
    and not (p.motivo = any (v_motivos_ausentes));

  -- ----- (3) o checklist reflete os três estados (0036) ----------------------
  update checklist_item_status c
    set status = case
                   when fn_linhas_do_tipo(p_caso_id, c.tipo_taxonomia) = 0 then 'recebido_nao_valido'
                   else 'presente'
                 end,
        atualizado_em = now()
  where c.caso_id = p_caso_id
    and c.documento_id is not null
    and c.status in ('presente', 'recebido_nao_valido');

  -- ----- (4) status do caso: Portão 1 continua sendo CHEGADA (0036) ----------
  select status into v_status_atual from caso where id = p_caso_id;
  if array_length(v_faltantes,1) is null then
    v_novo_status := 'completude_ok';
  else
    v_novo_status := 'em_triagem';
  end if;

  if v_status_atual in ('intake','em_triagem','completude_ok') and v_novo_status <> v_status_atual then
    update caso set status = v_novo_status where id = p_caso_id;
    insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
      values ('sistema:n8n', 'transicao_status', 'caso:'||p_caso_id,
              jsonb_build_object('status', v_status_atual),
              jsonb_build_object('status', v_novo_status));
  end if;

  return jsonb_build_object(
    'portao1_ok', array_length(v_faltantes,1) is null,
    'faltantes', to_jsonb(v_faltantes),
    'sem_conteudo', to_jsonb(v_sem_conteudo),
    -- 0119: cada ausência agora pode nomear a entidade. `pronto_para_revisao`
    -- segue intocado — endurecê-lo é decisão de produto do dono, não efeito
    -- colateral (0113).
    'linhas_exigidas_ausentes', v_linhas_ausentes,
    'pronto_para_revisao',
      array_length(v_faltantes,1) is null and array_length(v_sem_conteudo,1) is null,
    'status', v_novo_status
  );
end;
$$;

--
-- Name: FUNCTION fn_recomputar_completude(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_recomputar_completude(p_caso_id uuid) IS 'Portão 1 (chegada) + 0036 (recebido sem conteúdo) + 0113/0119 (passo 2b: linha exigida ausente, cobrada POR ENTIDADE quando o escopo pede) + 0157 (passo 1: "sem documento do tipo" vira "sem documento que SIRVA como o tipo" — fn_documento_serve_como aceita, só para COMBINADO, um documento estruturalmente combinado e com conteúdo (fn_combinado_estrutural_apto, achados A e B da revisão) classificado como BALANCO/DRE/FLUXO_CAIXA). Política por linha é do dono; default = importante/sobrepujável. `portao1_ok` segue "chegou tudo"; `pronto_para_revisao` segue "chegou tudo E tem conteúdo".';

--
-- Name: fn_reconciliar_arvore(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_arvore(p_documento_id uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_id     uuid;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_tipo        text;
  v_versao      uuid;
  v_n_ok        int := 0;
  v_n_div       int := 0;
  v_n_prec      int := 0;
  v_n_achatada  int := 0;
  v_n_rotulo    int := 0;
  v_n_unidade   int := 0;
  v_n_semparc   int := 0;
  v_pior_abs    numeric;
  v_pior_pct    numeric;
  v_pior_pai    text;
  v_partes      text[] := '{}';
  v_causas      text[] := '{}';
  v_resultado   text;
  v_desc        text;
begin
  select caso_id, entidade_id, periodo_id, tipo_taxonomia
    into v_caso_id, v_entidade_id, v_periodo_id, v_tipo
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  v_versao := fn_versao_atual(p_documento_id);
  if v_versao is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento sem versão');
  end if;

  select count(*) filter (where resultado = 'ok'),
         count(*) filter (where resultado = 'divergente'),
         count(*) filter (where resultado = 'precondicao_nao_satisfeita')
    into v_n_ok, v_n_div, v_n_prec
  from fn_conferir_arvore(v_versao);

  -- Nenhum pai com filho: documento de lista (aging, razão, mapa de dívida) ou
  -- extração sem hierarquia. Não é achado — é ausência de árvore para conferir.
  if v_n_ok + v_n_div + v_n_prec = 0 then
    return fn_registrar_reconciliacao(v_caso_id, v_entidade_id, v_periodo_id,
      'secao_fecha', 'A', p_documento_id, null, null, 'documento_ausente', null, null,
      jsonb_build_object('tolerancia', 'arredondamento ~0,5*(n+1)'),
      'Este documento não tem seção com filhos — não há árvore a conferir. É o esperado em '
      || 'documento de lista (razão, aging, mapa de dívida), não um achado.');
  end if;

  -- 0190: NENHUMA seção fechou de verdade (nem `ok`, nem `divergente`) — só
  -- pré-condição, em TODAS. Antes desta migration isto caía no ramo `else` de
  -- baixo e saía `resultado := 'ok'` ("As 0 seções deste documento fecham…"),
  -- afirmando que a árvore conferiu e fechou quando nenhuma soma real
  -- aconteceu. Grava com o MESMO motivo do ramo "sem árvore" acima
  -- (`documento_ausente` — CONTRATO na 0186:60-130): não abre pendência (o
  -- achado, quando tem dono, já tem — rótulo duplicado é da 0105; hierarquia
  -- achatada é decisão da própria 0143 de não acusar), mas a linha para de
  -- MENTIR que fechou.
  if v_n_ok + v_n_div = 0 then
    select count(*) filter (where achado = 'hierarquia_achatada'),
           count(*) filter (where achado = 'rotulo_duplicado'),
           count(*) filter (where achado = 'unidade_mista'),
           count(*) filter (where achado = 'sem_parcela')
      into v_n_achatada, v_n_rotulo, v_n_unidade, v_n_semparc
    from fn_conferir_arvore(v_versao)
    where resultado = 'precondicao_nao_satisfeita';

    if v_n_achatada > 0 then
      v_causas := v_causas || format('%s por hierarquia achatada (a extração ainda não separa '
                                     'o subgrupo do grupo — remédio é o prompt, não reconciliação)',
                                     v_n_achatada);
    end if;
    if v_n_rotulo > 0 then
      v_causas := v_causas || format('%s por rótulo duplicado (reconciliacao:duplicidade_de_'
                                     'rotulo, 0105, já cobra)', v_n_rotulo);
    end if;
    if v_n_unidade > 0 then
      v_causas := v_causas || format('%s por unidade mista', v_n_unidade);
    end if;
    if v_n_semparc > 0 then
      v_causas := v_causas || format('%s sem parcela somável', v_n_semparc);
    end if;

    return fn_registrar_reconciliacao(v_caso_id, v_entidade_id, v_periodo_id,
      'secao_fecha', 'A', p_documento_id,
      jsonb_build_object('secoes_conferidas', 0, 'pior_secao', null),
      jsonb_build_object('divergentes', 0, 'sem_conferir', v_n_prec),
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia', 'arredondamento ~0,5*(n+1) na unidade do documento'),
      format('Nenhuma das %s seção(ões) deste documento foi conferida (%s). Nenhuma soma real '
             'aconteceu: uma linha perdida dentro de qualquer seção passaria sem aviso, porque '
             'não há aqui nenhuma conferência que a pegasse.',
             v_n_prec, array_to_string(v_causas, '; ')));
  end if;

  select a.divergencia_abs,
         case when a.pai_valor <> 0 then a.divergencia_abs / abs(a.pai_valor) end,
         a.pai
    into v_pior_abs, v_pior_pct, v_pior_pai
  from fn_conferir_arvore(v_versao) a
  where a.resultado = 'divergente'
  order by a.divergencia_abs desc
  limit 1;

  select array_agg(
           format('%s%s: informa %s, filhos somam %s (dif. %s)',
                  a.pai,
                  case when coalesce(a.periodo_coluna, '') <> ''
                       then ' [' || a.periodo_coluna || ']' else '' end,
                  a.pai_valor, a.soma_filhos, a.divergencia_abs)
           order by a.divergencia_abs desc)
    into v_partes
  from (select * from fn_conferir_arvore(v_versao)
         where resultado = 'divergente'
         order by divergencia_abs desc limit 5) a;

  v_resultado := case when v_n_div > 0 then 'divergente' else 'ok' end;

  if v_n_div > 0 then
    v_desc := format(
      '%s seção(ões) não fecham com as próprias linhas neste documento (%s conferem). %s. '
      || 'Ou a extração perdeu/errou linha nessas seções, ou o documento não fecha consigo '
      || 'mesmo — as duas exigem olhar o PDF, e a diferença decide entre reextrair e perguntar '
      || 'ao cliente.',
      v_n_div, v_n_ok, array_to_string(v_partes, '; '));
    if v_n_div > 5 then
      v_desc := v_desc || format(' (mostrando as 5 maiores de %s; muitas seções quebrando de uma '
                                 'vez costuma ser escala ou coluna, não linha perdida.)', v_n_div);
    end if;
  else
    -- 0190: o texto dizia só "rótulo duplicado ou unidade mista" — falso desde
    -- a 0143, que acrescentou hierarquia achatada como terceira causa de
    -- pré-condição. Corrigido na mesma reemissão; comportamento deste ramo
    -- (v_n_ok > 0, `resultado := 'ok'`) não muda.
    v_desc := format('As %s seções deste documento fecham com as próprias linhas. %s ficaram sem '
                     'conferir por pré-condição (hierarquia achatada, rótulo duplicado, unidade '
                     'mista ou sem parcela somável).',
                     v_n_ok, v_n_prec);
  end if;

  return fn_registrar_reconciliacao(v_caso_id, v_entidade_id, v_periodo_id,
    'secao_fecha', 'A', p_documento_id,
    jsonb_build_object('secoes_conferidas', v_n_ok + v_n_div, 'pior_secao', v_pior_pai),
    jsonb_build_object('divergentes', v_n_div, 'sem_conferir', v_n_prec),
    v_resultado, v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia', 'arredondamento ~0,5*(n+1) na unidade do documento'),
    v_desc);
end;
$$;

--
-- Name: FUNCTION fn_reconciliar_arvore(p_documento_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconciliar_arvore(p_documento_id uuid) IS 'Registra, como reconciliação Classe A, se as seções do documento fecham com as próprias linhas. UMA pendência por documento (não uma por seção): erro de escala quebra todas as seções de uma vez, e trinta pendências para um defeito é o oposto do que fazer com o tempo de quem lê a fila. 0190: quando TODAS as seções caem em pré-condição (nenhuma `ok`, nenhuma `divergente`), grava ''documento_ausente'' em vez de ''ok'' — a árvore não conferiu nada, e o resultado deixa de afirmar o contrário.';

--
-- Name: fn_reconciliar_ativo_passivo_pl(uuid, uuid, uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_ativo_passivo_pl(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric DEFAULT 100, p_tolerancia_pct numeric DEFAULT 0.005) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_doc_id     uuid;
  v_versao     uuid;
  v_col_ent    text;
  v_ano        int;
  v_col_per    text;
  v_ativo      campo_extraido;
  v_passivo_pl campo_extraido;
  v_passivo    campo_extraido;
  v_pl         campo_extraido;
  v_esq        numeric;
  v_dir        numeric;
  v_soma       record;
  v_soma_pl    record;
  v_div_abs    numeric;
  v_tol        numeric;
  v_pior_abs   numeric := null;
  v_pior_pct   numeric := null;
  v_resultado  text := 'ok';
  v_partes     text[] := '{}';
  v_n_anos     int := 0;
  v_fonte_a    jsonb;
  v_fonte_b    jsonb;
  v_desc       text;
  v_orig_esq   text;
  v_orig_dir   text;
  v_faltas     text[] := '{}';
  -- 0165: o "PASSIVO" bare veio do casamento ESTRUTURAL (e não de um rótulo que
  -- diz "Passivo Total")? É essa a única via ambígua — ver o comentário grande
  -- da migration.
  v_passivo_estrutural boolean := false;
  -- 0188: o motivo de cada exercício que ficou sem os dois lados.
  v_motivos_ano text[] := '{}';
  v_motivo_prec text;
begin
  v_doc_id := fn_documento_balanco(p_caso_id, p_entidade_id, p_periodo_id);

  if v_doc_id is null then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'ativo_passivo_pl', 'A', null, null, null, 'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'Nenhum Balanço Patrimonial, Combinado ou Balancete classificado para esta '
      || 'entidade/período — nada a reconciliar (a cobrança do documento é do checklist).');
  end if;

  v_versao  := fn_versao_atual(v_doc_id);
  v_col_ent := fn_coluna_entidade(v_versao, p_entidade_id);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_versao, v_ano) end;
    v_orig_esq := null;
    v_orig_dir := null;
    v_esq := null;
    v_dir := null;
    v_passivo_estrutural := false;

    -- ---- lado esquerdo: ATIVO ------------------------------------------------
    -- (a) a linha que diz "total" no rótulo.
    select * into v_ativo from fn_valor_conceito_col(v_versao,
      array['ativo', 'total'], array['circulante', 'nao circulante'], v_col_ent, v_col_per);
    if v_ativo.id is not null then
      v_esq := v_ativo.valor_num;
      v_orig_esq := format('linha "%s"', v_ativo.chave);
    else
      -- (b) 0034: o rótulo ESTRUTURAL — "ATIVO", que é como a maioria dos
      -- balanços brasileiros imprime o total do grupo.
      select * into v_ativo from fn_valor_estrutural_col(v_versao,
        array['ativo'], v_col_ent, v_col_per);
      if v_ativo.id is not null then
        v_esq := v_ativo.valor_num;
        v_orig_esq := format('linha "%s" (total do grupo, sem a palavra "total")', v_ativo.chave);
      else
        -- (c) soma das contas da seção.
        select * into v_soma from fn_soma_secao(v_versao, array['ativo'], v_col_ent, v_col_per,
          array['passivo', 'patrimonio'], array['total do ativo']);
        v_esq := case when coalesce(v_soma.n_linhas, 0) > 0 then v_soma.soma end;
        v_orig_esq := case when v_esq is null then null
          else format('soma da seção ATIVO (%s linhas, sem linha de total impressa)', v_soma.n_linhas) end;
      end if;
    end if;

    -- ---- lado direito: PASSIVO + PL -----------------------------------------
    select * into v_passivo_pl from fn_valor_conceito_col(v_versao,
      array['passivo', 'patrimonio', 'total'], array['circulante'], v_col_ent, v_col_per);
    if v_passivo_pl.id is not null then
      v_dir := v_passivo_pl.valor_num;
      v_orig_dir := format('linha "%s"', v_passivo_pl.chave);
    else
      -- 0034: "PASSIVO E PATRIMÔNIO LÍQUIDO" — o rótulo do v35, que a busca com
      -- "total" não via.
      select * into v_passivo_pl from fn_valor_estrutural_col(v_versao,
        array['passivo', 'patrimonio'], v_col_ent, v_col_per);
      if v_passivo_pl.id is not null then
        v_dir := v_passivo_pl.valor_num;
        v_orig_dir := format('linha "%s" (total do grupo, sem a palavra "total")', v_passivo_pl.chave);
      else
        select * into v_passivo from fn_valor_conceito_col(v_versao,
          array['passivo', 'total'], array['patrimonio', 'circulante', 'nao circulante'],
          v_col_ent, v_col_per);
        select * into v_pl from fn_valor_conceito_col(v_versao,
          array['patrimonio', 'liquido', 'total'], array['circulante'], v_col_ent, v_col_per);
        if v_passivo.id is null then
          select * into v_passivo from fn_valor_estrutural_col(v_versao,
            array['passivo'], v_col_ent, v_col_per);
          v_passivo_estrutural := v_passivo.id is not null;
        end if;
        if v_pl.id is null then
          select * into v_pl from fn_valor_estrutural_col(v_versao,
            array['patrimonio'], v_col_ent, v_col_per);
        end if;
        -- 0165: "PASSIVO" BARE QUE JÁ BATE COM O ATIVO É O TOTAL DO GRUPO.
        -- Ver o cabeçalho desta migration para a medição. Só vale para o rótulo
        -- ESTRUTURAL: um rótulo que DIZ "Passivo Total" (e exclui patrimônio)
        -- está afirmando exigível, e nele a igualdade com o Ativo seria um
        -- balanço que não fecha — que é divergência de verdade, e continua
        -- sendo reportada pelo ramo de baixo.
        if v_passivo_estrutural and v_esq is not null
           and abs(v_passivo.valor_num - v_esq)
               <= greatest(p_tolerancia_abs, abs(v_esq) * p_tolerancia_pct) then
          v_dir := v_passivo.valor_num;
          v_orig_dir := format('linha "%s" (total do grupo, já inclui o Patrimônio Líquido)',
                               v_passivo.chave);
        elsif v_passivo.id is not null and v_pl.id is not null then
          v_dir := v_passivo.valor_num + v_pl.valor_num;
          v_orig_dir := format('linhas "%s" + "%s"', v_passivo.chave, v_pl.chave);
        else
          -- 0034: o fallback de soma, agora ALCANÇÁVEL. Era
          -- `fn_soma_secao(array['passivo','patrimonio'])`, que exige a seção
          -- conter os DOIS termos — e não existe seção "passivo patrimônio".
          -- As seções reais são "Passivo Circulante", "Passivo Não Circulante"
          -- e "Patrimônio Líquido", então são DUAS somas que se juntam.
          select * into v_soma from fn_soma_secao(v_versao, array['passivo'],
            v_col_ent, v_col_per, array['patrimonio'],
            array['total do passivo', 'passivo e patrimonio']);
          select * into v_soma_pl from fn_soma_secao(v_versao, array['patrimonio'],
            v_col_ent, v_col_per, '{}',
            array['total do passivo', 'passivo e patrimonio']);
          if coalesce(v_soma.n_linhas, 0) + coalesce(v_soma_pl.n_linhas, 0) > 0 then
            v_dir := coalesce(v_soma.soma, 0) + coalesce(v_soma_pl.soma, 0);
            v_orig_dir := format('soma das seções PASSIVO (%s linhas) + PL (%s linhas), sem linha de total impressa',
                                 coalesce(v_soma.n_linhas, 0), coalesce(v_soma_pl.n_linhas, 0));
          end if;
        end if;
      end if;
    end if;

    if v_esq is null or v_dir is null then
      -- 0188: os dois lados leem o MESMO documento com as MESMAS colunas, então
      -- o motivo do exercício é o de um lado só.
      v_motivos_ano := v_motivos_ano || fn_motivo_do_lado(false, v_col_ent, v_col_per);
      v_faltas := v_faltas || format('%s: falta %s%s',
        coalesce(v_ano::text, 'período do documento'),
        case
          when v_esq is null and v_dir is null then 'o Ativo Total E o Passivo+PL'
          when v_esq is null then 'o Ativo Total'
          else 'o Passivo+PL'
        end,
        case
          when v_col_per is null and v_col_ent is null then ''
          else format(' (coluna de entidade: %s; coluna de período: %s)',
                      -- 0188: a sentinela é "o documento tem colunas deste eixo
                      -- e NENHUMA é a pedida" — o texto dizia "(qualquer)",
                      -- que é o contrário.
                      case when v_col_ent = E'\x01' then '(nenhuma desta entidade)'
                           else coalesce(v_col_ent, '(qualquer)') end,
                      case when v_col_per = E'\x01' then '(nenhuma deste exercício)'
                           else coalesce(v_col_per, '(qualquer)') end)
        end);
      continue;
    end if;

    v_n_anos := v_n_anos + 1;
    v_div_abs := abs(v_esq - v_dir);
    v_tol := greatest(p_tolerancia_abs, abs(v_esq) * p_tolerancia_pct);
    if v_div_abs > v_tol then
      v_resultado := 'divergente';
      v_partes := v_partes || format('%s: Ativo %s [%s] vs Passivo+PL %s [%s] (diferença de %s)',
        coalesce(v_ano::text, 'período do documento'), v_esq, v_orig_esq, v_dir, v_orig_dir, v_div_abs);
      if v_pior_abs is null or v_div_abs > v_pior_abs then
        v_pior_abs := v_div_abs;
        v_pior_pct := case when v_esq <> 0 then v_div_abs / abs(v_esq) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (Ativo %s [%s] = Passivo+PL %s [%s])',
        coalesce(v_ano::text, 'período do documento'), v_esq, v_orig_esq, v_dir, v_orig_dir);
    end if;
    v_fonte_a := jsonb_build_object('chave', coalesce(v_ativo.chave, 'soma da seção ATIVO'),
      'valor', v_esq, 'ano', v_ano, 'origem', v_orig_esq, 'documento_versao_id', v_versao);
    v_fonte_b := jsonb_build_object('valor', v_dir, 'ano', v_ano, 'origem', v_orig_dir,
      'documento_versao_id', v_versao);
  end loop;

  if v_n_anos = 0 then
    v_motivo_prec := fn_motivo_precondicao_agregado(v_motivos_ano);
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'ativo_passivo_pl', 'A', v_doc_id, null, null, v_motivo_prec, null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      fn_motivo_precondicao_prefixo(v_motivo_prec)
      || 'O Balanço foi encontrado, mas nenhum exercício teve os DOIS lados. '
      || case when array_length(v_faltas, 1) is null then ''
              else array_to_string(v_faltas, '; ') || '. ' end
      || 'Rótulos que a extração TROUXE e que poderiam ser um total: '
      || fn_rotulos_candidatos(v_versao)
      || '. Se o rótulo certo está nessa lista, o defeito é o padrão de casamento; '
      || 'se não está, a extração não trouxe a linha e o caminho é reextrair.');
  end if;

  v_desc := format('Ativo Total vs Passivo+Patrimônio Líquido em %s ano(s): %s.',
                   v_n_anos, array_to_string(v_partes, '; '));
  if array_length(v_faltas, 1) is not null then
    v_desc := v_desc || format(' Exercícios NÃO checados: %s.', array_to_string(v_faltas, '; '));
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'ativo_passivo_pl', 'A', v_doc_id, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n_anos,
                       'anos_nao_checados', coalesce(array_length(v_faltas, 1), 0)),
    v_desc);
end;
$$;

--
-- Name: FUNCTION fn_reconciliar_ativo_passivo_pl(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconciliar_ativo_passivo_pl(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric) IS 'A.1 — Ativo Total = Passivo + PL. 0165: "PASSIVO" bare cujo valor já bate com o Ativo é o total do LADO DIREITO (já inclui o PL) e não é somado ao PL de novo — medido nos balanços reais do caso "teste 143", onde essa soma dupla abriu 11 divergências falsas.';

--
-- Name: fn_reconciliar_caixa_bp_fluxo(uuid, uuid, uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_caixa_bp_fluxo(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric DEFAULT 100, p_tolerancia_pct numeric DEFAULT 0.005) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
declare
  v_doc_bp    uuid;
  v_doc_fx    uuid;
  v_ver_bp    uuid;
  v_ver_fx    uuid;
  v_col_ent   text;
  v_ano       int;
  v_col_per   text;
  v_caixa     campo_extraido;
  v_saldo     campo_extraido;
  v_motivo    text;
  v_a         numeric;
  v_b         numeric;
  v_div_abs   numeric;
  v_tol       numeric;
  v_resultado text := 'ok';
  v_partes    text[] := '{}';
  v_n         int := 0;
  v_pior_abs  numeric;
  v_pior_pct  numeric;
  v_fonte_a   jsonb;
  v_fonte_b   jsonb;
  -- 0188
  v_col_bp      text;
  v_motivos_ano text[] := '{}';
  v_motivo_ano  text;
  v_faltas      text[] := '{}';
  v_motivo_prec text;
  -- 0196: o PERÍODO PRÓPRIO de cada documento (Balanço e DFC), lido uma vez fora do
  -- laço, e se ESTE ano do laço cai fora dele. Ver o cabeçalho da migration.
  v_bp_tipo      text;
  v_bp_ref       text;
  v_fx_tipo      text;
  v_fx_ref       text;
  v_bp_outro_ano boolean;
  v_fx_outro_ano boolean;
begin
  v_doc_bp := fn_documento_balanco(p_caso_id, p_entidade_id, p_periodo_id);
  v_doc_fx := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'FLUXO_CAIXA');

  if v_doc_bp is null or v_doc_fx is null then
    -- Fato comum e legítimo: nem toda empresa do grupo entrega DFC. Quem cobra
    -- documento faltante é o checklist do Kit Básico, não a fila de revisão.
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'caixa_bp_fluxo', 'A', coalesce(v_doc_bp, v_doc_fx), null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar: %s não foi entregue para esta entidade/período.',
        case when v_doc_bp is null and v_doc_fx is null then 'Balanço e Fluxo de Caixa'
             when v_doc_bp is null then 'Balanço Patrimonial' else 'Fluxo de Caixa' end));
  end if;

  v_ver_bp  := fn_versao_atual(v_doc_bp);
  v_ver_fx  := fn_versao_atual(v_doc_fx);
  v_col_ent := fn_coluna_entidade(v_ver_bp, p_entidade_id);
  select pe.tipo, pe.referencia into v_bp_tipo, v_bp_ref
    from documento d left join periodo pe on pe.id = d.periodo_id where d.id = v_doc_bp;
  select pe.tipo, pe.referencia into v_fx_tipo, v_fx_ref
    from documento d left join periodo pe on pe.id = d.periodo_id where d.id = v_doc_fx;

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_bp, v_ano) end;
    -- 0196: Balanço SEM coluna de período (v_col_per nulo) deixava a linha valer para
    -- QUALQUER ano do laço. `fn_linha_vale_para_ano` (0195) responde se o PERÍODO
    -- PRÓPRIO do documento ancora o ano; se não, a sentinela E'\x01' — a mesma que
    -- a 0023 já usa para "documento com colunas, nenhuma é deste ano" — faz a busca
    -- não devolver nada e o motivo sair `sem_periodo_par` (contrato 0186/0188).
    v_bp_outro_ano := false;
    if v_ano is not null and v_col_per is null
       and not fn_linha_vale_para_ano(v_ver_bp, null, v_bp_tipo, v_bp_ref, v_ano) then
      v_col_per := E'\x01';
      v_bp_outro_ano := true;
    end if;
    v_col_bp := v_col_per;

    -- Caixa no Balanço. "Disponível"/"Disponibilidades" é o rótulo mais comum em
    -- demonstração brasileira detalhada — a DFC do book chega a dizer, na nota,
    -- que o saldo final "confere com a rubrica Disponível do balanço".
    select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
      array['caixa', 'equivalentes'], array['circulante', 'fluxo', 'inicio', 'inicial'],
      v_col_ent, v_col_per);
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['disponibilidades'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['disponivel'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['caixa', 'bancos'], array['circulante'], v_col_ent, v_col_per);
    end if;
    -- 0031: as quatro tentativas acima olham SÓ `ce.chave`, e é isso que produzia a
    -- pendência "não foi possível localizar o Caixa/Disponível" no teste v31. Contra
    -- os rótulos reais do book:
    --
    --   Holding      "Caixa e Equivalentes de Caixa"  -> casa (1)
    --   Metalúrgica  "Disponibilidades"               -> casa (2)
    --   Componentes  "Numerário Disponível"           -> casa (3)
    --   SPE          "Caixa"                          -> NÃO casava: (1) exige
    --                                                   'equivalentes' e (4) exige 'bancos'
    --   VT Logística "Bancos Conta Movimento"         -> NÃO casava nenhuma
    --
    -- E o dado que faltava ESTAVA no documento: a `secao` da VT Logística diz
    -- "Disponível". A função nunca olhou `ce.secao`.
    if v_caixa.id is null then
      -- "Caixa" puro (SPE). Vem depois das combinações de dois termos, que são
      -- mais específicas — assim um documento que tem as duas coisas escolhe a
      -- linha certa em vez da mais genérica.
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['caixa'], array['circulante', 'fluxo', 'inicio', 'inicial', 'equivalente'],
        v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      -- Pela SEÇÃO do documento: é o que resolve "Bancos Conta Movimento".
      select * into v_caixa from fn_valor_conceito_secao(v_ver_bp,
        array['disponivel'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_secao(v_ver_bp,
        array['caixa'], array['circulante', 'fluxo'], v_col_ent, v_col_per);
    end if;

    -- Saldo final na DFC (a coluna de período da DFC é a dela, não a do BP).
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_fx, v_ano) end;
    -- 0196: o mesmo do Balanço, agora para a DFC — a DFC ANUAL de um exercício só tem
    -- periodo_coluna nulo e era lida como saldo final de 2024 e de 2025.
    v_fx_outro_ano := false;
    if v_ano is not null and v_col_per is null
       and not fn_linha_vale_para_ano(v_ver_fx, null, v_fx_tipo, v_fx_ref, v_ano) then
      v_col_per := E'\x01';
      v_fx_outro_ano := true;
    end if;
    select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
      array['saldo', 'final'], array['inicial', 'inicio'], null, v_col_per);
    if v_saldo.id is null then
      select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
        array['caixa', 'final'], array['inicial', 'inicio'], null, v_col_per);
    end if;
    if v_saldo.id is null then
      select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
        array['caixa', 'fim'], array['inicial', 'inicio'], null, v_col_per);
    end if;

    if v_caixa.id is null or v_saldo.id is null then
      -- 0188: cada lado com o motivo dele (o Balanço com a coluna de entidade e
      -- a de período do Balanço; a DFC só com a de período dela).
      v_motivo_ano := fn_motivo_precondicao_agregado(array[
        fn_motivo_do_lado(v_caixa.id is not null, v_col_ent, v_col_bp),
        fn_motivo_do_lado(v_saldo.id is not null, null, v_col_per)]);
      v_motivos_ano := v_motivos_ano || v_motivo_ano;
      v_faltas := v_faltas || format('%s: %s',
        coalesce(v_ano::text, 'período do documento'),
        array_to_string(array_remove(array[
          case when v_caixa.id is null then
            case when v_bp_outro_ano then format('o Balanço é de %s — não traz este exercício', v_bp_ref)
                 when v_col_bp = E'\x01' then 'o Balanço não tem coluna deste exercício'
                 when v_col_ent = E'\x01' then 'o Balanço não tem coluna desta entidade'
                 else 'o Caixa/Disponível do Balanço não foi localizado' end end,
          case when v_saldo.id is null then
            case when v_fx_outro_ano then format('o Fluxo de Caixa é de %s — não traz este exercício', v_fx_ref)
                 when v_col_per = E'\x01' then 'o Fluxo de Caixa não tem coluna deste exercício'
                 else 'o Saldo final do Fluxo de Caixa não foi localizado' end end
        ], null), ' e '));
      continue;
    end if;

    v_motivo := fn_motivo_escala_incomparavel(v_caixa.unidade, v_saldo.unidade,
      'o Caixa do Balanço', 'o Saldo final do Fluxo de Caixa');
    if v_motivo is not null then
      return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
        'caixa_bp_fluxo', 'A', v_doc_bp, null, null, 'unidade_divergente', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        fn_motivo_precondicao_prefixo('unidade_divergente') || v_motivo);
    end if;

    v_a := fn_valor_em_base(v_caixa.valor_num, v_caixa.unidade);
    v_b := fn_valor_em_base(v_saldo.valor_num, v_saldo.unidade);
    v_n := v_n + 1;
    v_div_abs := abs(v_a - v_b);
    -- 0193: A TOLERÂNCIA ABSOLUTA ESTÁ NA BASE, como v_a e v_b. Da 0031 até
    -- aqui ela era `p_tolerancia_abs * fator_da_escala`: numa entidade com
    -- Balanço/DFC em 'milhar', os R$ 100 do default viravam R$ 100 MIL, e
    -- qualquer divergência de caixa abaixo disso saía "confere". MEDIDO EM
    -- PRODUÇÃO (25/09/2026, somente leitura, recomputando fonte_a/fonte_b):
    -- das 33 caixa_bp_fluxo com resultado 'ok' (as 33 em 'milhar'), 0
    -- mudariam de resultado com a tolerância na base — diferença zero em
    -- todas. Correção LATENTE: mesmo vício estrutural da despfin (0188), sem
    -- efeito ainda medido nesta checagem. MEDIDO (regra 2): com o `× fator`
    -- de volta, o assert do bloco 1 de
    -- Supabase/test/tolerancia_na_base.test.sql reprova.
    --
    -- REVISÃO DE FIDELIDADE (28/09/2026): a tolerância na base, sozinha, tem
    -- um segundo vício — o piso de ARREDONDAMENTO do próprio documento. Num
    -- Balanço/DFC em 'milhar' cada número impresso já carrega até R$ 1.000
    -- de arredondamento (duas linhas arredondadas podem diferir em 1 unidade
    -- da escala sem que nada esteja errado). Com caixa abaixo de R$ 200 mil,
    -- 0,5% de v_a fica ABAIXO de R$ 1.000: uma DFC "12" contra um Balanço
    -- "11" (em milhar, diferença de R$ 1.000, arredondamento puro) sairia
    -- 'divergente' — mesma forma do vício que motivou esta migration, só que
    -- pela ESCALA DO DOCUMENTO, não pela unidade monetária. MEDIDO EM
    -- PRODUÇÃO (28/09/2026, somente leitura): 0 casos hoje — das 39 linhas de
    -- caixa em 'milhar', nenhuma com caixa abaixo de R$ 200 mil. Correção
    -- LATENTE, mesmo raciocínio da árvore (0133: tolerância de arredondamento
    -- em unidade do documento). Por isso o piso ganha também 1 unidade da
    -- escala mais grossa dos dois lados (Balanço/DFC podem, em tese, estar em
    -- escalas diferentes conhecidas — 0023 permite comparar), coalescida a 1
    -- (unidade/escala ausente = já está na base). Não é `× fator` de volta:
    -- é um PISO fixo de 1 unidade, não uma multiplicação da tolerância
    -- inteira. A receita (fn_reconciliar_receita_dre_vs_faturamento) NÃO
    -- ganha o mesmo piso: com pct 5%, o piso percentual só fica abaixo de 1
    -- unidade da escala quando a receita é menor que R$ 20 mil em 'milhar' —
    -- irrelevante neste domínio (nenhuma receita de mandato chega perto
    -- disso). MEDIDO (regra 2): com o piso removido (voltando a
    -- `greatest(p_tolerancia_abs, abs(v_a) * p_tolerancia_pct)`), o assert do
    -- bloco 3 de Supabase/test/tolerancia_na_base.test.sql reprova.
    v_tol := greatest(p_tolerancia_abs,
      greatest(coalesce(fn_fator_escala(v_caixa.unidade), 1), coalesce(fn_fator_escala(v_saldo.unidade), 1)),
      abs(v_a) * p_tolerancia_pct);
    if v_div_abs > v_tol then
      v_resultado := 'divergente';
      v_partes := v_partes || format('%s: Caixa no Balanço %s ("%s") vs Saldo final na DFC %s ("%s") — diferença de %s',
        coalesce(v_ano::text, 'período do documento'), v_caixa.valor_num, v_caixa.chave,
        v_saldo.valor_num, v_saldo.chave, v_div_abs);
      if v_pior_abs is null or v_div_abs > v_pior_abs then
        v_pior_abs := v_div_abs;
        v_pior_pct := case when v_a <> 0 then v_div_abs / abs(v_a) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (%s "%s" = %s "%s")',
        coalesce(v_ano::text, 'período do documento'), v_caixa.valor_num, v_caixa.chave,
        v_saldo.valor_num, v_saldo.chave);
    end if;
    v_fonte_a := jsonb_build_object('chave', v_caixa.chave, 'valor', v_caixa.valor_num,
      'unidade', v_caixa.unidade, 'documento_versao_id', v_ver_bp);
    v_fonte_b := jsonb_build_object('chave', v_saldo.chave, 'valor', v_saldo.valor_num,
      'unidade', v_saldo.unidade, 'documento_versao_id', v_ver_fx);
  end loop;

  if v_n = 0 then
    v_motivo_prec := fn_motivo_precondicao_agregado(v_motivos_ano);
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'caixa_bp_fluxo', 'A', v_doc_bp, null, null, v_motivo_prec, null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      fn_motivo_precondicao_prefixo(v_motivo_prec)
      || 'Balanço e Fluxo de Caixa presentes, mas não foi possível localizar o Caixa/Disponível do '
      || 'Balanço e/ou o Saldo final de caixa do Fluxo (rótulos extraídos não bateram). '
      || array_to_string(v_faltas, '; ') || '.');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'caixa_bp_fluxo', 'A', v_doc_bp, v_fonte_a, v_fonte_b, v_resultado, v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n),
    format('Caixa do Balanço vs Saldo final do Fluxo de Caixa em %s ano(s): %s.%s',
           v_n, array_to_string(v_partes, '; '),
           -- 0196 (regra 1): ano sem par não some calado — fica dito que não foi comparado.
           case when cardinality(v_faltas) > 0
                then ' Não comparado — ' || array_to_string(v_faltas, '; ') || '.' else '' end));
end;
$_$;

--
-- Name: FUNCTION fn_reconciliar_caixa_bp_fluxo(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconciliar_caixa_bp_fluxo(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric) IS '0196: Balanço e DFC sem periodo_coluna só valem para o ano que o PERÍODO PRÓPRIO do documento ancora (fn_linha_vale_para_ano); ano sem linha válida do outro lado é sem_periodo_par, não divergência. Tolerância na base com piso de arredondamento (0193).';

--
-- Name: fn_reconciliar_caso(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_caso(p_caso_id uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
-- 0152: cada checagem sobre a SUA chave.
-- 0192: `order by` em cada laço — determinismo de qual período a pendência
-- carrega (a guarda de fn_registrar_reconciliacao já não depende da ordem
-- para decidir aberto/resolvido; isto é só reprodutibilidade).
-- 0192 (guarda por CHAVE): cada laço grava em `oria.periodo_chave` o período da chave que visita
-- (set_config local à transação); fn_registrar_reconciliacao o lê e o grava em
-- `reconciliacao.periodo_chave_id`. O laço DESCE a períodos compatíveis (foreach), o que muda o
-- `periodo_id` da linha mas não a chave.
declare
  v_k          record;
  v_per        uuid;
  v_res        jsonb;
  v_checagens  jsonb := '[]'::jsonb;
  v_chamadas   int := 0;
  v_documentos int := 0;
  c_arvore     constant text[] := array['BALANCO','BALANCETE','COMBINADO'];
  c_fluxo      constant text[] := array['BALANCO','BALANCETE','COMBINADO','FLUXO_CAIXA'];
  c_receita    constant text[] := array['DRE','FATURAMENTO_24M'];
  c_despfin    constant text[] := array['DRE','MAPA_DIVIDA'];
  c_mutuos     constant text[] := array['MUTUOS','BALANCO','COMBINADO','DF_AUDITADA'];
  c_intra      constant text[] := array['BALANCO','BALANCETE','DF_AUDITADA'];
  c_conflito   constant text[] := array['BALANCO','BALANCETE','COMBINADO','DF_AUDITADA','DRE',
                                        'FLUXO_CAIXA','DMPL','DVA','NOTAS_EXPL'];
begin
  select count(*) into v_documentos from documento where caso_id = p_caso_id;

  -- ---- (entidade, período), com laço de período -----------------------------
  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_arvore)
             order by d.entidade_id, d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_ativo_passivo_pl(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_fluxo)
             order by d.entidade_id, d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_caixa_bp_fluxo(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_receita)
             order by d.entidade_id, d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_receita_dre_vs_faturamento(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_despfin)
             order by d.entidade_id, d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_despfin_dre_vs_divida(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  -- ---- só (período) — mútuos e intragrupo são do GRUPO, não da empresa ------
  for v_k in select distinct d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_mutuos)
             order by d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_mutuos(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_intra)
             order by d.periodo_id loop
    perform set_config('oria.periodo_chave', coalesce(v_k.periodo_id::text, ''), true);
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_intragrupo(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  -- ---- só (entidade) — sem período nenhum ----------------------------------
  -- 0192: sem chave de período; o que o último laço deixou não pode vazar para estas.
  perform set_config('oria.periodo_chave', '', true);
  for v_k in select distinct d.entidade_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_arvore)
             order by d.entidade_id loop
    v_checagens := v_checagens
      || jsonb_build_array(fn_reconciliar_duplicidade(p_caso_id, v_k.entidade_id));
    v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_conflito)
             order by d.entidade_id loop
    v_checagens := v_checagens
      || jsonb_build_array(fn_reconciliar_versoes_do_periodo(p_caso_id, v_k.entidade_id));
    v_chamadas := v_chamadas + 1;
  end loop;

  perform set_config('oria.periodo_chave', '', true);
  return jsonb_build_object(
    'executado', true, 'caso_id', p_caso_id,
    'documentos', v_documentos, 'chamadas', v_chamadas,
    'checagens', v_checagens);
end;
$$;

--
-- Name: FUNCTION fn_reconciliar_caso(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconciliar_caso(p_caso_id uuid) IS 'Roda cada uma das oito checagens de reconciliação sobre a SUA chave (0152). 0192: `order by` em cada laço `select distinct` — determinismo de qual período a pendência carrega quando mais de um é compatível; o aberto/resolvido em si já não depende da ordem (guarda em fn_registrar_reconciliacao). 0192: cada laço grava o período da CHAVE em oria.periodo_chave (lido por fn_registrar_reconciliacao).';

--
-- Name: fn_reconciliar_chaves_do_documento(uuid, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_chaves_do_documento(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
-- 0152: extraída de fn_reconciliar_por_documento sem mudança de lógica.
-- 0192: REEMITIDA INTEIRA (corpo vigente 0152:394, nenhuma migration a reemitiu) só para gravar a
-- CHAVE em `oria.periodo_chave` (ver fn_registrar_reconciliacao).
-- 0151: o conflito entre documentos do mesmo período mora aqui, no fim.
declare
  v_checagens jsonb := '[]'::jsonb;
  v_periodos  uuid[];
  v_per       uuid;
  v_res       jsonb;
begin
  select array_agg(p.id order by (p.id = p_periodo_id) desc, p.referencia)
    into v_periodos
  from periodo p
  where p.caso_id = p_caso_id
    and (p.id = p_periodo_id or fn_periodos_compativeis(p.id, p_periodo_id));
  if v_periodos is null or cardinality(v_periodos) = 0 then
    v_periodos := array[p_periodo_id];
  end if;

  -- 0192 (guarda por CHAVE): o período do documento é a chave de TODAS as checagens por período
  -- abaixo; o laço desce a períodos compatíveis, a chave não muda. As duas sem período (duplicidade,
  -- versões) zeram o setting.
  perform set_config('oria.periodo_chave', coalesce(p_periodo_id::text, ''), true);

  -- Classe A (0009)
  if p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_ativo_passivo_pl(p_caso_id, p_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'FLUXO_CAIXA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_caixa_bp_fluxo(p_caso_id, p_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Classe B (0015/0021)
  if p_tipo in ('DRE', 'FATURAMENTO_24M') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_receita_dre_vs_faturamento(p_caso_id, p_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if p_tipo in ('DRE', 'MAPA_DIVIDA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_despfin_dre_vs_divida(p_caso_id, p_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Mútuos (0117/0123). Pelos dois lados: quem chega por último fecha o par.
  if p_tipo in ('MUTUOS', 'BALANCO', 'COMBINADO', 'DF_AUDITADA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_mutuos(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Intragrupo FORA mútuo (0124). Disparada por balanço individual, que é a
  -- única peça de que ela precisa — não há documento par a esperar. `COMBINADO`
  -- não dispara e não é lido: as linhas intragrupo dele são eliminações.
  if p_tipo in ('BALANCO', 'BALANCETE', 'DF_AUDITADA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_intragrupo(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Duplicidade de rótulo (0105). Sem laço de período: é por caso/entidade.
  perform set_config('oria.periodo_chave', '', true);
  if p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_duplicidade(p_caso_id, p_entidade_id));
  end if;

  -- Conflito entre documentos do mesmo período (0151). Sem laço de período: a
  -- checagem descobre sozinha quais exercícios existem.
  if p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA', 'DRE',
                'FLUXO_CAIXA', 'DMPL', 'DVA', 'NOTAS_EXPL') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_versoes_do_periodo(p_caso_id, p_entidade_id));
  end if;

  perform set_config('oria.periodo_chave', '', true);
  return v_checagens;
end;
$$;

--
-- Name: FUNCTION fn_reconciliar_chaves_do_documento(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconciliar_chaves_do_documento(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text) IS 'As oito checagens que leem (caso, entidade, período) e não o documento (0152). Extraída de fn_reconciliar_por_documento sem mudança de lógica, para que o lote possa rodá-las uma vez por CHAVE em vez de uma vez por documento. 0192: grava o período da chave em oria.periodo_chave.';

--
-- Name: fn_reconciliar_despfin_dre_vs_divida(uuid, uuid, uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_despfin_dre_vs_divida(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric DEFAULT 50000, p_tolerancia_pct numeric DEFAULT 0.05) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
declare
  v_doc_dre uuid;
  v_doc_div uuid;
  v_ver_dre uuid;
  v_ver_div uuid;
  v_col_ent text;
  v_ano int;
  v_col_per text;
  v_despfin campo_extraido;
  v_juros   record;
  v_unid_div text;
  v_motivo text;
  v_a numeric; v_b numeric; v_div numeric; v_tol numeric;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_fonte_a jsonb; v_fonte_b jsonb;
  -- 0188
  v_motivos_ano text[] := '{}';
  v_faltas      text[] := '{}';
  v_motivo_prec text;
  v_alt         record;
  v_recado      text;
  -- 0191: os anos que o PERÍODO DO DOCUMENTO do Mapa de Dívida ancora. Lido
  -- uma vez, fora do laço — o mapa não muda de período ano a ano. Vazio =
  -- "não há como afirmar o ano" (sem período, ou período que não ancora ano
  -- nenhum): a guarda nova não filtra nada, comportamento de antes.
  v_periodo_id_div uuid;
  v_tipo_div        text;
  v_ref_div         text;
  v_anos_mapa       int[];
  -- 0196: período PRÓPRIO da DRE e se este ano do laço cai fora dele.
  v_dre_tipo      text;
  v_dre_ref       text;
  v_dre_outro_ano boolean;
begin
  v_doc_dre := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'DRE');
  v_doc_div := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'MAPA_DIVIDA');

  if v_doc_dre is null or v_doc_div is null then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'despfin_dre_vs_divida', 'B', coalesce(v_doc_dre, v_doc_div), null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar despesa financeira: %s não foi entregue para esta entidade/período.',
        case when v_doc_dre is null and v_doc_div is null then 'DRE e Mapa de Dívida'
             when v_doc_dre is null then 'DRE' else 'Mapa de Dívida' end));
  end if;

  v_ver_dre  := fn_versao_atual(v_doc_dre);
  v_ver_div  := fn_versao_atual(v_doc_div);
  v_col_ent  := fn_coluna_entidade(v_ver_dre, p_entidade_id);
  v_unid_div := fn_unidade_predominante(v_ver_div);
  select pe.tipo, pe.referencia into v_dre_tipo, v_dre_ref
    from documento d left join periodo pe on pe.id = d.periodo_id where d.id = v_doc_dre;

  -- 0191: o Mapa de Dívida é um retrato de UMA data — MEDIDO EM PRODUÇÃO
  -- (25/09/2026): todo MAPA_DIVIDA hoje tem período de um ano só. Sem este
  -- corte, o laço abaixo compara CADA ano da DRE contra a soma de juros do
  -- documento inteiro (não recortada por ano), inclusive anos que o mapa não
  -- cobre — ver o cabeçalho desta migration.
  select periodo_id into v_periodo_id_div from documento where id = v_doc_div;
  if v_periodo_id_div is not null then
    select tipo, referencia into v_tipo_div, v_ref_div from periodo where id = v_periodo_id_div;
    v_anos_mapa := fn_anos_periodo(v_tipo_div, v_ref_div);
  end if;

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_dre, v_ano) end;
    -- 0196: DRE SEM coluna de período valia para qualquer ano do laço (o corte da
    -- 0191 só olhava o lado do MAPA). Ver o cabeçalho da migration.
    v_dre_outro_ano := false;
    if v_ano is not null and v_col_per is null
       and not fn_linha_vale_para_ano(v_ver_dre, null, v_dre_tipo, v_dre_ref, v_ano) then
      v_col_per := E'\x01';
      v_dre_outro_ano := true;
    end if;

    -- 0191: o ano deste laço não é coberto pelo período do Mapa de Dívida —
    -- não compara. `v_anos_mapa` vazio (mapa sem período, ou período que não
    -- ancora ano nenhum) mantém o comportamento antigo: sem como afirmar que o
    -- ano não é coberto, a guarda não filtra.
    if v_ano is not null and cardinality(coalesce(v_anos_mapa, '{}'::int[])) > 0
       and not (v_ano = any(v_anos_mapa)) then
      v_motivos_ano := v_motivos_ano || 'sem_periodo_par'::text;
      v_faltas := v_faltas || format(
        '%s: o Mapa de Dívida é de %s — não há juros deste exercício para comparar',
        v_ano, coalesce(v_ref_div, 'outro período'));
      continue;
    end if;

    select * into v_despfin from fn_valor_conceito_col(v_ver_dre,
      array['despesa', 'financeira'], array['receita'], v_col_ent, v_col_per);
    if v_despfin.id is null then
      select * into v_despfin from fn_valor_conceito_col(v_ver_dre,
        array['juros', 'encargos'], array['receita', 'pagos'], v_col_ent, v_col_per);
    end if;
    -- 0188 (parte 3): "JUROS E COMISSÕES BANCÁRIAS" — o rótulo de UMA entidade
    -- de produção cuja pendência de despesa financeira era falsa, porque o
    -- localizador de cima exige "juros" E "encargos". Medido sobre TODOS os
    -- rótulos de DRE com juros/financeir/encargo em produção (22/09/2026): casa
    -- "juros e comissoes bancarias" (8 linhas, 4 entidades, todas negativas) e
    -- NENHUM rótulo de receita — o exclui leva 'aplicac' porque "juros s/
    -- aplicação financeira" e "juros de aplicações" são receita. O MESMO par
    -- está em taxonomia_linha_localizador (DRE/despesa_financeira, ordem 3):
    -- duplicação assumida da 0113, para exigência e checagem não divergirem.
    if v_despfin.id is null then
      select * into v_despfin from fn_valor_conceito_col(v_ver_dre,
        array['juros', 'bancari'], array['receita', 'aplicac'], v_col_ent, v_col_per);
    end if;
    if v_despfin.id is null then
      v_motivos_ano := v_motivos_ano || fn_motivo_do_lado(false, v_col_ent, v_col_per);
      -- 0188 (parte 2, do lado da checagem): a DRE traz o LÍQUIDO no lugar? A
      -- alternativa é a mesma linha que a pendência de completude lê.
      if v_recado is null then
        select a.recado, ce.chave into v_alt
          from taxonomia_linha_alternativa a
          join taxonomia_linha_exigida e on e.id = a.exigencia_id
          cross join lateral fn_valor_conceito_col(v_ver_dre, a.termos_inclui, a.termos_exclui,
                                                   v_col_ent, v_col_per) ce
         where e.tipo_taxonomia = 'DRE' and e.conceito = 'despesa_financeira' and e.ativo
           and a.contra = 'chave' and ce.id is not null
         order by a.ordem
         limit 1;
        if v_alt.recado is not null then
          v_recado := format('A DRE traz "%s" no lugar. %s', v_alt.chave, v_alt.recado);
        end if;
      end if;
      v_faltas := v_faltas || format('%s: %s', coalesce(v_ano::text, 'período do documento'),
        case when v_dre_outro_ano then format('a DRE é de %s — não traz este exercício', v_dre_ref)
             when v_col_per = E'\x01' then 'a DRE não tem coluna deste exercício'
             when v_col_ent = E'\x01' then 'a DRE não tem coluna desta entidade'
             else 'a Despesa Financeira da DRE não foi localizada' end);
      continue;
    end if;

    -- Juros do exercício no mapa: soma as linhas por contrato, excluindo o total.
    select coalesce(sum(ce.valor_num), 0)::numeric as soma, count(*)::int as n
      into v_juros
    from campo_extraido ce
    where ce.documento_versao_id = v_ver_div
      and ce.valor_num is not null
      -- 0145: o conceito pode morar na COLUNA. No mapa de dívida matricial a
      -- chave é o contrato ("Banco Meridional S.A. - Capital de giro (…)") e o
      -- cabeçalho é "Juros do exercício (R$)". Sem este segundo ramo a soma vinha
      -- vazia e a checagem devolvia precondicao_nao_satisfeita sobre um documento
      -- perfeitamente extraído — pendência da v48 no 02_DRE_Canastra_Industria.
      and (fn_normalizar_texto(ce.chave) like '%juros%'
           or fn_normalizar_texto(ce.chave) like '%encargos%'
           or fn_normalizar_texto(coalesce(ce.periodo_coluna, '')) like '%juros%'
           or fn_normalizar_texto(coalesce(ce.periodo_coluna, '')) like '%encargos%')
      and fn_normalizar_texto(ce.chave) not like 'total%'
      and fn_normalizar_texto(ce.chave) not like '%total %';
    if coalesce(v_juros.n, 0) = 0 then
      -- 0188: o mapa não é recortado por ano (a soma lê o documento inteiro),
      -- então do lado dele não há "sem período": é linha não localizada.
      v_motivos_ano := v_motivos_ano || 'linha_nao_localizada'::text;
      v_faltas := v_faltas || format('%s: o Mapa de Dívida não tem linha nem coluna de juros/encargos',
        coalesce(v_ano::text, 'período do documento'));
      continue;
    end if;

    v_motivo := fn_motivo_escala_incomparavel(v_despfin.unidade, v_unid_div,
      'a Despesa Financeira da DRE', 'o Mapa de Dívida');
    if v_motivo is not null then
      return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
        'despfin_dre_vs_divida', 'B', v_doc_dre, null, null,
        'unidade_divergente', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        fn_motivo_precondicao_prefixo('unidade_divergente') || v_motivo);
    end if;

    -- Comparação em VALOR ABSOLUTO: a DRE traz a despesa como negativa
    -- (dedução), o mapa traz os juros como positivos.
    v_a := abs(fn_valor_em_base(v_despfin.valor_num, v_despfin.unidade));
    v_b := abs(fn_valor_em_base(v_juros.soma, v_unid_div));
    v_n := v_n + 1;
    v_div := abs(v_a - v_b);
    -- 0188 (revisão, 22/09/2026): A TOLERÂNCIA ABSOLUTA ESTÁ NA BASE, como v_a
    -- e v_b. Da 0023 até aqui ela era `p_tolerancia_abs * fator_da_DRE`: numa
    -- DRE em 'milhar', os 50.000 do default viravam R$ 50 MILHÕES, e qualquer
    -- divergência abaixo disso saía "confere". MEDIDO EM PRODUÇÃO (22/09/2026,
    -- somente leitura): das 33 despfin com resultado 'ok', 32 conferem de
    -- verdade com greatest(R$ 50.000, 5%) e 1 é falsa — R$ 12.400.000 de
    -- diferença saindo "confere". fn_reconciliar_mutuos (0123) já fazia assim
    -- ("tolerância em MOEDA BASE ... senão a checagem é mais frouxa justamente
    -- onde os valores são maiores"). Esta é a SEGUNDA mudança de resultado
    -- desta migration (a primeira é a parte 3) — ver o cabeçalho. MEDIDO
    -- (regra 2): com o `× fator` de volta, 2 asserts reprovam — o bloco 5 de
    -- motivo_especifico.test.sql (8.194 × 5.308 em milhar sai "ok") e o
    -- requisito despfin_tolerancia_na_base de instalacao.test.sql.
    v_tol := greatest(p_tolerancia_abs, abs(v_a) * p_tolerancia_pct);
    if v_div > v_tol then
      v_resultado := 'zona_cinzenta';
      v_partes := v_partes || format('%s: Despesa Financeira %s "%s" vs soma de %s contratos %s "%s" — diferença de %s na base',
        v_ano, v_despfin.valor_num, coalesce(v_despfin.unidade, 'sem escala'),
        v_juros.n, v_juros.soma, coalesce(v_unid_div, 'sem escala'), v_div);
      if v_pior_abs is null or v_div > v_pior_abs then
        v_pior_abs := v_div;
        v_pior_pct := case when v_a <> 0 then v_div / abs(v_a) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (Despesa Financeira %s "%s" = juros de %s contratos %s "%s", convertidos à mesma base)',
        v_ano, v_despfin.valor_num, coalesce(v_despfin.unidade, 'sem escala'),
        v_juros.n, v_juros.soma, coalesce(v_unid_div, 'sem escala'));
    end if;
    v_fonte_a := jsonb_build_object('chave', v_despfin.chave, 'valor', v_despfin.valor_num,
      'unidade', v_despfin.unidade, 'ano', v_ano, 'documento_versao_id', v_ver_dre);
    v_fonte_b := jsonb_build_object('soma_juros', v_juros.soma, 'n_contratos', v_juros.n,
      'unidade', v_unid_div, 'documento_versao_id', v_ver_div);
  end loop;

  if v_n = 0 then
    v_motivo_prec := fn_motivo_precondicao_agregado(v_motivos_ano);
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'despfin_dre_vs_divida', 'B', v_doc_dre, null, null,
      v_motivo_prec, null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      fn_motivo_precondicao_prefixo(v_motivo_prec)
      || 'DRE e Mapa de Dívida presentes, mas não foi possível localizar a Despesa Financeira da DRE '
      || 'e/ou as linhas de juros do mapa (rótulos extraídos não bateram). '
      || array_to_string(v_faltas, '; ') || '.'
      || coalesce(' ' || v_recado, ''));
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'despfin_dre_vs_divida', 'B', v_doc_dre, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n),
    format('Despesa Financeira da DRE vs juros do Mapa de Dívida em %s ano(s): %s.%s',
           v_n, array_to_string(v_partes, '; '),
           case when cardinality(v_faltas) > 0
                then ' Não comparado — ' || array_to_string(v_faltas, '; ') || '.' else '' end));
end;
$_$;

--
-- Name: FUNCTION fn_reconciliar_despfin_dre_vs_divida(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconciliar_despfin_dre_vs_divida(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric) IS 'Reconcilia a Despesa Financeira da DRE contra a soma dos juros do Mapa de Dívida, ano a ano. 0191: só compara o ano quando o período do DOCUMENTO do Mapa de Dívida o cobre (fn_anos_periodo do período do mapa) — o Mapa é um retrato de UMA data, e comparar um ano que ele não cobre contra a soma do documento inteiro é comparação sem sentido. Ano fora: sem_periodo_par, não ok nem zona_cinzenta. Mapa sem período (ou período sem ano ancorado): comportamento antigo, sem filtro.';

--
-- Name: fn_reconciliar_duplicidade(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_duplicidade(p_caso_id uuid, p_entidade_id uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_entidade    text;
  v_pares       record;
  v_n           int := 0;
  v_total       numeric := 0;
  v_detalhe     jsonb := '[]'::jsonb;
  v_descricao   text;
  v_resultado   text;
  v_documento   uuid;
begin
  select razao_social into v_entidade from entidade where id = p_entidade_id;

  for v_pares in
    select * from fn_pares_duplicados_do_caso(p_caso_id, v_entidade)
  loop
    v_n := v_n + 1;
    v_total := v_total + v_pares.valor;
    v_detalhe := v_detalhe || jsonb_build_array(jsonb_build_object(
      'secao_canonica', v_pares.secao_canonica,
      'rotulo_a', v_pares.rotulo_a, 'rotulo_b', v_pares.rotulo_b,
      'valor', v_pares.valor, 'colunas_iguais', v_pares.colunas,
      'radical_comum', v_pares.radical_comum));
  end loop;

  -- Um documento qualquer da entidade, só para a pendência ter onde ancorar o
  -- link da tela. A duplicidade é entre documentos, então não há "o" documento.
  select d.id into v_documento
  from documento d
  where d.caso_id = p_caso_id
    and (p_entidade_id is null or d.entidade_id = p_entidade_id)
  order by d.criado_em
  limit 1;

  if v_n = 0 then
    v_resultado := 'ok';
    v_descricao := 'Nenhum par de rótulos duplicados na entidade.';
  else
    v_resultado := 'divergencia';
    v_descricao := format(
      '%s par(es) de rótulos podem ser a MESMA conta transposta duas vezes (%s no total). '
      || 'Se forem, a soma do grupo está dobrada nesse valor. Pares: %s. '
      || 'NADA foi apagado: decida qual rótulo é a conta e trate o outro na revisão.',
      v_n, to_char(v_total, 'FM999G999G999D00'),
      (select string_agg(format('%s = %s (%s)', x->>'rotulo_a', x->>'rotulo_b',
                                to_char((x->>'valor')::numeric, 'FM999G999G999D00')), '; ')
         from jsonb_array_elements(v_detalhe) x));
  end if;

  return fn_registrar_reconciliacao(
    p_caso_id, p_entidade_id, null, 'duplicidade_de_rotulo', 'A', v_documento,
    jsonb_build_object('pares', v_detalhe), null,
    v_resultado, v_total, null,
    jsonb_build_object('criterio', 'rótulos em DOCUMENTOS DIFERENTES (0144), mesma secao_canonica, '
      || 'valor idêntico na mesma coluna, papel conta, e (>=2 colunas coincidentes ou radical '
      || 'estrutural compartilhado)'),
    v_descricao);
end;
$$;

--
-- Name: FUNCTION fn_reconciliar_duplicidade(p_caso_id uuid, p_entidade_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconciliar_duplicidade(p_caso_id uuid, p_entidade_id uuid) IS 'Checagem de reconciliação: acha a MESMA conta transposta com dois rótulos EM DOCUMENTOS DIFERENTES e abre pendência com o valor dobrado. Não apaga nem reescreve dado — decisão humana. Por caso/entidade (a duplicidade é fato da estrutura dos documentos, não de um exercício), daí periodo_id nulo.';

--
-- Name: fn_reconciliar_intragrupo(uuid, uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_intragrupo(p_caso_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric DEFAULT 50000, p_tolerancia_pct numeric DEFAULT 0.005) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_ano int;
  v_par record;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_div numeric; v_tol numeric;
  v_fonte_a jsonb := '[]'::jsonb;
  v_pares_conferidos int := 0;
begin
  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    for v_par in
      with balancos as (
        -- UM DOCUMENTO POR ENTIDADE **por ano** — o MESMO defeito que a 0194
        -- mediu e corrigiu em fn_reconciliar_mutuos, medido aqui em produção
        -- só-leitura (28/09/2026): escolher só por tipo/`criado_em`, sem
        -- olhar o ano, reaplica o MESMO documento a todo `v_ano` do laço —
        -- "teste - Canastra"/2023: 4 de 4 linhas incluídas vinham de um
        -- documento que não ancora 2023; "Araucária teste", nos 5 anos,
        -- sempre 100%. Critério agora (0195, mesmo da 0194): entre os
        -- documentos do exercício, o que TEM dado intragrupo elegível para
        -- ESTE ano (`fn_linha_vale_para_ano`) vence o que só ANCORA o ano
        -- sem trazer linha; só então a prioridade de tipo e o mais recente
        -- desempatam. `COMBINADO` fica FORA (ver o cabeçalho da 0124: as
        -- linhas intragrupo dele são eliminações).
        select distinct on (d.entidade_id) d.id, d.entidade_id,
               pe.tipo as periodo_tipo, pe.referencia as periodo_ref
        from documento d
        join lateral (select fn_versao_atual(d.id) as ver) v on true
        left join periodo pe on pe.id = d.periodo_id
        where d.caso_id = p_caso_id
          and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'DF_AUDITADA')
          and d.entidade_id is not null
        order by d.entidade_id,
                 (exists (
                    select 1 from campo_extraido ce2
                    where ce2.documento_versao_id = v.ver
                      and ce2.valor_num is not null
                      and ce2.valor_num <> 0
                      and fn_papel_linha(ce2.chave) <> 'subtotal'
                      and not fn_texto_nomeia_mutuo(ce2.chave)
                      and not fn_mutuo_com_socio(ce2.chave, ce2.secao)
                      -- 0195 (achado 3 da revisão): "tem dado intragrupo" = a MESMA
                      -- definição de linha intragrupo que o CTE `intragrupo` usa
                      -- (contraparte, lado e escala), não "qualquer linha ≠ 0" —
                      -- senão o documento com saldo de caixa vence o que tem o espelho.
                      and fn_contraparte_intragrupo(p_caso_id, ce2.chave, d.entidade_id) is not null
                      and fn_lado_intragrupo(ce2.chave, ce2.secao_canonica) is not null
                      and ce2.unidade is not null
                      and fn_linha_vale_para_ano(v.ver, ce2.periodo_coluna, pe.tipo, pe.referencia, v_ano)
                 )) desc,
                 array_position(array['BALANCO','DF_AUDITADA','BALANCETE'], d.tipo_taxonomia),
                 d.criado_em desc,
                 d.id   -- 0195: desempate final determinístico (ver fn_reconciliar_mutuos)
      ), linhas as (
        select
          b.entidade_id as dona,
          fn_contraparte_intragrupo(p_caso_id, ce.chave, b.entidade_id) as contraparte,
          fn_lado_intragrupo(ce.chave, ce.secao_canonica) as lado,
          fn_valor_em_base(ce.valor_num, ce.unidade) as valor_base,
          fn_natureza_intragrupo(ce.chave, ce.secao) as natureza,
          ce.chave,
          ce.unidade
        from balancos b
        join lateral (select fn_versao_atual(b.id) as ver) v on true
        join campo_extraido ce on ce.documento_versao_id = v.ver
        where ce.valor_num is not null
          and ce.valor_num <> 0
          and fn_papel_linha(ce.chave) <> 'subtotal'
          -- MÚTUO É DA OUTRA CHECAGEM. Uma linha, uma régua.
          and not fn_texto_nomeia_mutuo(ce.chave)
          and not fn_mutuo_com_socio(ce.chave, ce.secao)
          -- 0195 (mesmo vício de linha que a 0194 corrigiu em
          -- fn_reconciliar_mutuos): documento SEM `periodo_coluna` (retrato/
          -- anual de um ano só) só vale para `v_ano` quando o PRÓPRIO
          -- PERÍODO do documento ancora esse ano — não para qualquer ano
          -- perguntado. `fn_linha_vale_para_ano` responde a MESMA pergunta
          -- que o `balancos` acima já usou para escolher o documento, com o
          -- período DESSE documento (b.periodo_tipo/periodo_ref).
          and fn_linha_vale_para_ano(v.ver, ce.periodo_coluna, b.periodo_tipo, b.periodo_ref, v_ano)
      ), intragrupo as (
        select * from linhas
        where contraparte is not null and lado is not null
          -- ESCALA AUSENTE NÃO SE CONVERTE, e o critério é o da 0009: sem saber a
          -- escala, afirmar "confere" seria pior que calar.
          and unidade is not null
      )
      select
        least(dona, contraparte)    as ent_a,
        greatest(dona, contraparte) as ent_b,
        sum(case when lado = 'ativo'   then abs(valor_base) else 0 end) as receber,
        sum(case when lado = 'passivo' then abs(valor_base) else 0 end) as pagar,
        count(*)::int as n_linhas,
        string_agg(distinct natureza, ', ' order by natureza) as naturezas,
        min(chave) as exemplo
      from intragrupo
      group by 1, 2
      having
        -- OS DOIS LADOS TÊM DE EXISTIR, e a exigência é sobre o par: A e B ambas
        -- com balanço no mandato. Sem isso a falta de espelho é a falta do
        -- documento — que o Portão 1 já cobra — e não erro de número.
        count(distinct dona) = 2
    loop
      v_pares_conferidos := v_pares_conferidos + 1;
      v_div := abs(v_par.receber - v_par.pagar);
      -- Tolerância em MOEDA BASE, como no resto da família (0117/0123): o mesmo
      -- número tem de significar a mesma coisa num balanço em milhar e noutro em
      -- unidade.
      v_tol := greatest(p_tolerancia_abs, greatest(v_par.receber, v_par.pagar) * p_tolerancia_pct);
      v_fonte_a := v_fonte_a || jsonb_build_array(jsonb_build_object(
        'ano', v_ano,
        'entidade_a', (select razao_social from entidade where id = v_par.ent_a),
        'entidade_b', (select razao_social from entidade where id = v_par.ent_b),
        'a_receber', v_par.receber, 'a_pagar', v_par.pagar,
        'naturezas', v_par.naturezas, 'n_linhas', v_par.n_linhas, 'exemplo', v_par.exemplo));
      if v_div > v_tol then
        v_n := v_n + 1;
        v_resultado := 'zona_cinzenta';
        v_partes := v_partes || format(
          '%s — %s × %s (%s): um lado registra %s a receber e o outro %s a pagar, diferença de %s '
          || '(em reais, já convertidas as escalas). A mesma posição intragrupo tem de fechar nos '
          || 'dois balanços; exemplo de linha: "%s"',
          v_ano,
          (select razao_social from entidade where id = v_par.ent_a),
          (select razao_social from entidade where id = v_par.ent_b),
          v_par.naturezas, round(v_par.receber), round(v_par.pagar), round(v_div), v_par.exemplo);
        if v_pior_abs is null or v_div > v_pior_abs then
          v_pior_abs := v_div;
          v_pior_pct := case when greatest(v_par.receber, v_par.pagar) <> 0
                             then v_div / greatest(v_par.receber, v_par.pagar) end;
        end if;
      end if;
    end loop;
  end loop;

  if v_pares_conferidos = 0 then
    -- SEM PENDÊNCIA, pela mesma doutrina da 0117: não haver par intragrupo com os
    -- DOIS balanços no mandato é o caso comum e correto — mandato de uma empresa
    -- só não tem intragrupo, e mandato de grupo pode não ter recebido todos os
    -- balanços. Abrir pendência aqui encheria a fila com um aviso que não pede
    -- ação, e fila assim é fila que ninguém lê.
    return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
      'intragrupo_espelho', 'B', null, null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'Nenhum par intragrupo com os DOIS balanços no mandato: não há espelho para conferir.');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
    'intragrupo_espelho', 'B', null, v_fonte_a, null, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'pares_conferidos', v_pares_conferidos, 'pares_divergentes', v_n),
    case when v_n = 0
      then format('Intragrupo (fora mútuo): %s par(es) de empresas conferido(s) pelo espelho — '
                  || 'todos fecham nos dois balanços.', v_pares_conferidos)
      else format('Intragrupo (fora mútuo): %s de %s par(es) de empresas NÃO fecham — %s.',
                  v_n, v_pares_conferidos, array_to_string(v_partes, '; ')) end);
end;
$$;

--
-- Name: FUNCTION fn_reconciliar_intragrupo(p_caso_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconciliar_intragrupo(p_caso_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric) IS '0195: a posição intragrupo entre cada PAR de empresas fecha nos dois balanços? Pareia pelo par de empresas (a contraparte vem do rótulo), não pela natureza — cada ponta usa o vocabulário dela. Mútuo fica com fn_reconciliar_mutuos. CORRIGIDO (mesmo vício que a 0194 já tinha corrigido em fn_reconciliar_mutuos, medido em produção só-leitura 28/09/2026): o balanço de cada entidade é escolhido POR ANO (fn_linha_vale_para_ano decide quem TEM dado do exercício, antes da prioridade de tipo) — não mais uma escolha só por criado_em, reaplicada sem mudança a cada ano do laço; e uma linha de documento SEM periodo_coluna só vale para o ano que o PRÓPRIO PERÍODO do documento ancora — não para qualquer ano perguntado.';

--
-- Name: fn_reconciliar_mutuos(uuid, uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_mutuos(p_caso_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric DEFAULT 50000, p_tolerancia_pct numeric DEFAULT 0.005) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_doc_mut uuid;
  v_ver_mut uuid;
  v_ano int;
  v_col_mut text;
  v_unid_mut text;
  v_bp   record;
  v_pl   record;
  v_a numeric; v_b numeric; v_div numeric; v_tol numeric;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_fonte_a jsonb; v_fonte_b jsonb;
  v_tem_balanco boolean;
  -- 0123: os dois degraus específicos, respondidos sobre o DOCUMENTO. Algum
  -- rótulo nomeia (degrau 1)? Alguma seção nomeia (degrau 2)? Nenhum dos dois é
  -- o degrau 3.
  v_pl_rotulo boolean;
  v_pl_secao  boolean;
  -- 0123: os lados do balanço, colhidos ANTES de comparar — é o que permite
  -- perguntar se eles concordam entre si, que a versão anterior não fazia.
  v_lados record;
  v_lado_alvo text;
  v_rotulo_lado text;
  -- 0194: a planilha é um RETRATO de uma data (0145: o conceito mora na
  -- coluna). `v_col_saldo` responde "onde mora a coluna do saldo" no
  -- documento escolhido para ESTE ano; `v_pl_retrato` (achado 2 da revisão de
  -- fidelidade, 28/09/2026) diz se ESTE documento é matricial (chave = par de
  -- empresas) — quando é, o rótulo/a seção da linha não carregam lado nenhum,
  -- e filtrar por `fn_lado_do_mutuo` descarta linha boa (ver o filtro do
  -- LADO B, abaixo).
  v_col_saldo  text;
  v_pl_retrato boolean;
  -- 0194 (achado 3 da revisão): a planilha é escolhida POR ANO, não uma vez
  -- para a checagem inteira — `v_doc_ano` é o documento MUTUOS do caso cujo
  -- período cobre `v_ano` (ou, faltando isso, um documento cujo período não
  -- ancora ano nenhum — o mesmo fallback ambíguo de ANTES desta migration).
  -- `v_doc_ano_cobre_ano` distingue os dois: só no primeiro caso é seguro
  -- resolver a sentinela pela coluna de saldo.
  v_doc_ano           uuid;
  v_doc_ano_cobre_ano boolean;
  -- 0194 (mesmo padrão da 0188/0191/0193): o motivo de cada ano/lado que não
  -- concluiu, e o que fica faltando dito em texto — para o `v_n = 0` do fim
  -- distinguir "nenhum balanço tem conta de mútuo" (silêncio de sempre) de
  -- "documento presente, checagem não concluiu" (achado, abre pendência) de
  -- "a planilha deste exercício não foi entregue" (achado 3: silêncio
  -- também — é cobrança de checklist, não achado — mas ainda assim dita em
  -- texto em `v_faltas`, para quando for o ÚNICO motivo de nada concluir).
  v_motivos_ano text[] := '{}';
  v_faltas      text[] := '{}';
  v_motivo_prec text;
begin
  -- A PLANILHA É DO GRUPO E O SALDO É DE CADA EMPRESA — por isso esta checagem
  -- é por CASO, e não por (caso, entidade) como as outras.
  --
  -- Foi a primeira versão desta função que ensinou isso, errando: ela procurava
  -- o balanço DA MESMA entidade dona da planilha. No book Vertentes a planilha é
  -- do "GRUPO VERTENTES" e a única demonstração dessa entidade é a COMBINADA —
  -- que, por definição, ELIMINA o intragrupo e não tem uma linha de mútuo
  -- sequer. A checagem "não achava o par" e abria pendência de pré-condição num
  -- caso que está perfeitamente em ordem. O par certo é o outro: a planilha
  -- lista "A → B", e o saldo mora no balanço de A (a receber) ou de B (a pagar).
  --
  -- 0194 (achado 3 da revisão): a EXISTÊNCIA da planilha, para esta
  -- pré-condição de abertura, não precisa de período específico — é só
  -- "existe QUALQUER planilha MUTUOS no caso?". QUAL planilha vale para QUAL
  -- ano é resolvido ano a ano, dentro do laço abaixo — nunca uma escolha só
  -- para a checagem inteira (era esse o defeito: aqui em cima ainda tentava
  -- o período específico primeiro, mas o resultado só alimentava a
  -- pré-condição e o `p_documento_id` do registro; era o USO ano a ano, mais
  -- abaixo, que faltava — corrigido no laço, não aqui). A chamada com
  -- `p_periodo_id` é o marcador do catálogo da sonda (D6, 0187,
  -- `d6_cobertura_de_tipos_estrita`) — preservada por isso, embora o valor
  -- que ela devolve não decida mais nada sozinho.
  v_doc_mut := fn_documento_por_tipo(p_caso_id, null, p_periodo_id, 'MUTUOS');
  if v_doc_mut is null then
    v_doc_mut := fn_documento_por_tipo(p_caso_id, null, null, 'MUTUOS');
  end if;

  select exists (
    select 1 from documento d
    where d.caso_id = p_caso_id
      and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA')
  ) into v_tem_balanco;

  if v_doc_mut is null or not v_tem_balanco then
    return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
      'mutuos_planilha_vs_balanco', 'B', v_doc_mut, null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar mútuos: %s não foi entregue neste mandato.',
        case when v_doc_mut is null and not v_tem_balanco then 'a planilha de mútuos e nenhum balanço'
             when v_doc_mut is null then 'a planilha de mútuos' else 'nenhum balanço' end));
  end if;

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    -- ---- LADO A: o saldo de mútuos, somado sobre TODOS os balanços do caso --
    -- Soma, e não `fn_valor_conceito_col`: o saldo aparece numa conta por
    -- empresa, e pegar UMA compararia parte do saldo com a planilha inteira.
    -- A escala entra linha a linha (`fn_valor_em_base`), então um caso com um
    -- balanço em milhar e outro em unidade continua somando certo.
    --
    -- 0123: o resultado é AGREGADO em uma linha só (um objeto por lado), em vez
    -- de percorrido lado a lado. É essa mudança de forma que torna possível
    -- perguntar "os dois lados concordam?" antes de comparar qualquer coisa.
    with balancos as (
      -- UM DOCUMENTO POR ENTIDADE **por ano** — correção de defeito medido,
      -- não zelo. A 0123 escolhia por `criado_em` sem olhar o ano: o book
      -- Vertentes entrega para a mesma controlada um BALANÇO e um BALANCETE
      -- do mesmo exercício, com o mesmo saldo de mútuo (3.974) — somar os
      -- dois duplicava o lado. Essa parte não muda.
      --
      -- 0194 (achado 1 da revisão de fidelidade, MEDIDO em produção
      -- só-leitura, 28/09/2026): olhar só `criado_em` sem o ANO tem o MESMO
      -- vício quando duas peças da MESMA entidade são de ANOS diferentes —
      -- um documento "multi 24,25" sem coluna por ano e sem linha de mútuo
      -- (só lista as controladas) vencia o "anual 2025", que TEM a linha, só
      -- por ter sido carregado depois. Caso "Teste 00", ano 2025: 10/12
      -- controladas escolhiam assim — lado A saía 8,6 mi (só passivo, 2
      -- documentos) contra a planilha 68,16 mi, uma `zona_cinzenta`
      -- fabricada de 59,56 mi; o correto é os dois lados fechando em 74,8 mi
      -- contra 74,56 da planilha — divergência real de 240 mil (a mesma
      -- plantada no book Canastra). Mesmo desenho no "teste alto volume -
      -- grupo araucária" (2024: passivo 25,8 mi de 6 documentos × planilha
      -- 46,76 mi). Critério agora: entre os documentos do exercício, o que
      -- TRAZ dado do ano (linha de mútuo na coluna certa, ou sem coluna
      -- nenhuma — documento de um ano só) vence o que só ANCORA o ano sem
      -- trazer dado; só então a prioridade de tipo da 0123 (BALANCO >
      -- COMBINADO > DF_AUDITADA > BALANCETE) e o mais recente. Um "multi
      -- 24,25" que TEM colunas por ano e linha de mútuo continua valendo — o
      -- critério é "tem dado", não "é anual".
      select distinct on (d.entidade_id) d.id, d.entidade_id,
             pe.tipo as periodo_tipo, pe.referencia as periodo_ref
      from documento d
      join lateral (select fn_versao_atual(d.id) as ver) v on true
      left join periodo pe on pe.id = d.periodo_id
      where d.caso_id = p_caso_id
        and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA')
      order by d.entidade_id,
               -- 0195: fatorada em `fn_linha_vale_para_ano` — mesma conta,
               -- mesmos argumentos (v.ver, ce2.periodo_coluna, pe.tipo,
               -- pe.referencia, v_ano), agora nomeada uma vez só.
               (exists (
                  select 1 from campo_extraido ce2
                  where ce2.documento_versao_id = v.ver
                    and ce2.valor_num is not null
                    and fn_texto_nomeia_mutuo(ce2.chave)
                    and fn_linha_vale_para_ano(v.ver, ce2.periodo_coluna, pe.tipo, pe.referencia, v_ano)
               )) desc,
               array_position(array['BALANCO','COMBINADO','DF_AUDITADA','BALANCETE'],
                              d.tipo_taxonomia),
               d.criado_em desc,
               -- 0195 (achado 2 da revisão): `criado_em` EMPATA em produção (44 grupos,
               -- 160 documentos, 14 casos) e sem último critério o plano escolhe o
               -- documento. `d.id` torna a escolha determinística.
               d.id
    ), linhas as (
      -- 0195 (achado 1 da revisão, CRÍTICO): A MESMA CONTA NA FACE E NA NOTA
      -- ERA SOMADA DUAS VEZES. Medido em produção só-leitura (30/09/2026): o
      -- doc 2f17a7ba (Varejo, multi 21..25) traz "Mútuos a pagar -
      -- controladora" na face do balanço (ordem 38, sem seção) E na nota
      -- "Partes Relacionadas" (ordem 62), mesmo valor, mesma coluna, nos 5
      -- anos — 409 (2021), 890 (2022), 1.600, 2.600, 3.900 mil, todos dobrados.
      -- As "divergências reais" de 409 e 890 mil que o cabeçalho da 0194 e o
      -- Supabase/README.md descreviam ERAM essa duplicata: sem ela os dois
      -- lados fecham exatos. Critério: no MESMO documento, a mesma conta
      -- (rótulo normalizado) na mesma coluna, com o mesmo lado, valor e
      -- escala, lida na FACE e numa seção de NOTA ("Partes Relacionadas",
      -- "Nota 12"...) é UMA posição lida em dois lugares — conta uma vez (fica
      -- a da face). Valor DIFERENTE com o mesmo rótulo não é deduplicado
      -- (seria outra posição).
      -- REVISÃO (30/09/2026, achado 3): a 1ª versão deduplicava QUALQUER par
      -- igual, e com isso fundia duas posições genuínas da FACE ("Mútuos a
      -- receber - controladas" 500.000 no AC e o mesmo no ANC: mesmo rótulo,
      -- mesmo valor, contas DIFERENTES). Agora só se deduplica quando uma das
      -- linhas está em seção de nota: duas linhas de face iguais continuam
      -- somando; nota sem linha de face igual conta (uma vez, se repetida na
      -- própria nota); nota com linha de face igual sai.
      -- REVISÃO 2 (30/09/2026, achado médio): a 2ª versão ainda contava UMA só
      -- linha de nota sem par de face (`rn = 1`). Em produção "partes
      -- relacionadas" é quase sempre a SUBSEÇÃO DE FACE (~85 de ~95 documentos
      -- com mútuo nela não têm outra linha de mútuo fora dela): duas posições
      -- de face ambas em "Partes relacionadas" (AC e ANC, mesmo valor) eram
      -- fundidas numa. Agora linha marcada como nota SEM par de face conta
      -- SEMPRE; só a nota com face igual sai. Nota repetida dentro de si mesma
      -- (a hipótese que o `rn = 1` protegia): 0 grupos em produção, medido só-leitura
      -- (30/09/2026, 448 grupos de mútuo, 0 com duas ou mais linhas e nenhuma de face).
      -- TETO: "nota" é o nome da seção (`partes relacionadas` ou `nota`); uma
      -- face cuja subseção se chame "Partes Relacionadas" é tratada como nota,
      -- e só sai se HOUVER linha de face igual fora da subseção. Em produção a face
      -- do doc 2f17a7ba tem `secao` NULL e a nota, "Partes Relacionadas" (5 pares,
      -- medido de novo em 30/09/2026).
      -- Medido em TODA a produção: 5 grupos assim em mútuos (face ordem 38 +
      -- nota ordem 62), todos nesse único documento, 0 com valor diferente.
      select doc_id, lado, valor_base, chave, unidade
      from (
        select d.id as doc_id,
               fn_lado_do_mutuo(ce.chave, ce.secao_canonica) as lado,
               fn_valor_em_base(ce.valor_num, ce.unidade) as valor_base,
               ce.chave,
               ce.unidade,
               coalesce(fn_normalizar_texto(ce.secao) ~ '(partes relacionadas|\mnotas?\M)', false) as e_nota,
               count(*) filter (where not coalesce(fn_normalizar_texto(ce.secao) ~ '(partes relacionadas|\mnotas?\M)', false)) over (
                 partition by d.id, fn_normalizar_texto(ce.chave), ce.periodo_coluna,
                              fn_lado_do_mutuo(ce.chave, ce.secao_canonica),
                              fn_valor_em_base(ce.valor_num, ce.unidade), ce.unidade) as n_face
        from balancos d
        join lateral (select fn_versao_atual(d.id) as ver) v on true
        join campo_extraido ce on ce.documento_versao_id = v.ver
        where ce.valor_num is not null
          -- O LADO DO BALANÇO CONTINUA LENDO O RÓTULO, e isto é deliberado: o
          -- defeito medido é do lado da PLANILHA, e nos balanços do Canastra e de
          -- Vertentes a conta diz "Mútuos a pagar" / "Mútuos a receber" no próprio
          -- rótulo. Alargar aqui para a seção seria consertar um caso que não
          -- existe — e traria a mesma over-inclusão: a subseção de balanço é
          -- "Partes Relacionadas", que agrupa mútuo, conta corrente e aluguel.
          and fn_texto_nomeia_mutuo(ce.chave)
          -- 0123: mútuo com SÓCIO sai — a outra ponta dele não está no mandato,
          -- então ele não espelha e não é da população da planilha intragrupo.
          and not fn_mutuo_com_socio(ce.chave, ce.secao)
          and fn_papel_linha(ce.chave) <> 'subtotal'
          -- 0195: fatorada em `fn_linha_vale_para_ano` (mesma conta que a 0194
          -- escreveu inline: documento sem coluna de período só conta para
          -- `v_ano` quando o PRÓPRIO PERÍODO do documento ancora esse ano).
          and fn_linha_vale_para_ano(v.ver, ce.periodo_coluna, d.periodo_tipo, d.periodo_ref, v_ano)
          and fn_lado_do_mutuo(ce.chave, ce.secao_canonica) is not null
      ) bruto
      -- face: todas somam. nota: só a primeira, e só se não há face igual.
      where not e_nota or n_face = 0
    ), por_lado as (
      select lado, abs(sum(valor_base)) as soma_base
      from linhas group by lado
    )
    select
      (select count(*)::int from por_lado) as n_lados,
      (select soma_base from por_lado where lado = 'ativo')   as soma_ativo,
      (select soma_base from por_lado where lado = 'passivo') as soma_passivo,
      -- CONTAGENS SOBRE AS LINHAS, não sobre os lados agregados: com os dois
      -- lados somados num número, `max(n_docs)` por lado dizia "2 documentos"
      -- num par que vem de 3. O que a mensagem promete é quantas peças
      -- sustentam o número, e isso só se conta antes de agrupar.
      count(*)::int as n_linhas,
      count(distinct doc_id)::int as n_docs,
      min(chave) as exemplo,
      bool_or(unidade is null) as tem_sem_escala
    into v_lados
    from linhas;

    if coalesce(v_lados.n_lados, 0) = 0 then
      -- SEM MOTIVO: é o caso comum e legítimo (0117/0123, comportamento
      -- desenhado e preservado) — não achar linha de mútuo NO BALANÇO não é
      -- achado. É o ÚNICO `continue` de LADO A que não alimenta `v_motivos_ano`.
      continue;
    end if;

    -- ---- A PLANILHA DESTE ANO ----------------------------------------------
    -- 0194 (achado 3 da revisão): escolhida POR ANO, não uma vez para a
    -- checagem inteira (ver o cabeçalho da função — MEDIDO em produção
    -- só-leitura, 28/09/2026: "Teste 00" e "teste alto volume - grupo
    -- araucária" têm um documento MUTUOS por data-base, um por ano de
    -- 2021 a 2025; escolher só um fazia os outros anos acusarem
    -- `sem_periodo_par` mesmo com a planilha certa presente no caso;
    -- "teste - Canastra", com uma única planilha de 2025, abria a mesma
    -- pendência falsa para os anos 2023/2024 do período de consulta).
    -- Prioridade: o documento cujo período COBRE `v_ano`; faltando isso, um
    -- documento cujo período não ancora ano nenhum (o mesmo fallback
    -- ambíguo de ANTES desta migration — `v_doc_ano_cobre_ano = false` avisa
    -- o resto do laço para não tratar a sentinela como resolvida). Nenhum
    -- dos dois: a planilha deste exercício não foi entregue — não é achado
    -- de reconciliação, é cobrança de checklist (0186), e fica silenciosa
    -- como o `continue` de cima, só registrada em `v_faltas` para o texto do
    -- `documento_ausente` final, se for o caso.
    --
    -- MEDIDO em produção só-leitura (28/09/2026, "Teste 00", MUTUOS de
    -- 31/12/2023): o caso tem DUAS versões de documento para o MESMO ano — a
    -- reextração deixou uma casca de 0 linhas ao lado da que TEM as 13
    -- linhas — e desempatar só por `criado_em` tinha a MESMA falha do achado
    -- 1 (a casca vazia podia vencer por ter sido criada depois). O critério
    -- é o mesmo dos dois achados: entre os documentos empatados no ano, o
    -- que TEM linha (`tem_linha` abaixo) vence antes do mais recente.
    select d.id,
           (v_ano is not null and pe.id is not null
            and v_ano = any(fn_anos_periodo(pe.tipo, pe.referencia)))
      into v_doc_ano, v_doc_ano_cobre_ano
    from documento d
    left join periodo pe on pe.id = d.periodo_id
    where d.caso_id = p_caso_id
      and d.tipo_taxonomia = 'MUTUOS'
      and (v_ano is null
           or pe.id is null
           or cardinality(coalesce(fn_anos_periodo(pe.tipo, pe.referencia), '{}'::int[])) = 0
           or v_ano = any(fn_anos_periodo(pe.tipo, pe.referencia)))
    order by (v_ano is not null and pe.id is not null
              and v_ano = any(fn_anos_periodo(pe.tipo, pe.referencia))) desc,
             (exists (
                select 1 from campo_extraido ce3
                where ce3.documento_versao_id = fn_versao_atual(d.id)
                  and ce3.valor_num is not null
              )) desc,
             d.criado_em desc,
             d.id   -- 0195: desempate final determinístico (ver `balancos`)
    limit 1;

    if v_doc_ano is null then
      v_faltas := v_faltas || format(
        '%s: a planilha de mútuos deste exercício não foi entregue neste mandato', v_ano);
      continue;
    end if;

    v_ver_mut  := fn_versao_atual(v_doc_ano);
    v_unid_mut := fn_unidade_predominante(v_ver_mut);

    -- OS DEGRAUS SÃO RESOLVIDOS UMA VEZ POR DOCUMENTO (0123) — e agora o
    -- documento pode mudar de ano para ano (achado 3), então esta resolução
    -- entra no laço junto com ele. A pergunta do degrau é "este documento
    -- diferencia natureza no rótulo?"; respondê-la por linha faria a linha
    -- calada de um documento que diferencia entrar junto (o erro original),
    -- e a de um que não diferencia ficar de fora (o outro erro).
    select bool_or(fn_texto_nomeia_mutuo(ce.chave)),
           bool_or(fn_texto_nomeia_mutuo(ce.secao))
      into v_pl_rotulo, v_pl_secao
    from campo_extraido ce
    where ce.documento_versao_id = v_ver_mut
      and ce.valor_num is not null
      and fn_papel_linha(ce.chave) <> 'subtotal';
    v_pl_rotulo := coalesce(v_pl_rotulo, false);
    v_pl_secao  := coalesce(v_pl_secao, false);

    -- 0194: A COLUNA DO SALDO, achada pelo MESMO localizador que a 0145 já
    -- cadastrou para este conceito (`taxonomia_linha_localizador`,
    -- MUTUOS/saldo_de_mutuo, termo 'saldo') — reuso do termo, não um `like`
    -- novo. Lida uma vez por documento: o retrato tem uma coluna de saldo
    -- só, não uma por ano. `v_pl_retrato` (achado 2 da revisão) reaproveita
    -- o MESMO achado: um documento com coluna "saldo" é matricial (chave =
    -- par de empresas), e é isso — não uma palavra no rótulo da linha — que
    -- diz se a linha carrega lado.
    select ce.periodo_coluna into v_col_saldo
    from campo_extraido ce
    where ce.documento_versao_id = v_ver_mut
      and ce.periodo_coluna is not null
      and fn_normalizar_texto(ce.periodo_coluna) like '%saldo%'
    group by ce.periodo_coluna
    order by count(*) desc, ce.periodo_coluna
    limit 1;
    v_pl_retrato := v_col_saldo is not null;

    -- Escala ausente de um dos lados é o mesmo critério conservador da 0009:
    -- não há o que converter, e afirmar "confere" seria pior que calar.
    if coalesce(v_lados.tem_sem_escala, false) <> (v_unid_mut is null) then
      -- 0194: o MESMO vício de texto dos outros `continue` — escala ausente
      -- de um lado terminava no MESMO `documento_ausente` falso. É achado (a
      -- escala não é comparável), não ausência de dado.
      v_motivos_ano := v_motivos_ano || 'unidade_divergente'::text;
      v_faltas := v_faltas || format(
        '%s: escala não comparável entre o balanço e a planilha de mútuos (um lado declara, o outro não)',
        v_ano);
      continue;
    end if;

    -- OS DOIS LADOS SE ESPELHAM: CONFERI-LOS ENTRE SI VEM PRIMEIRO.
    if v_lados.n_lados = 2 then
      v_div := abs(v_lados.soma_ativo - v_lados.soma_passivo);
      v_tol := greatest(p_tolerancia_abs, v_lados.soma_ativo * p_tolerancia_pct);
      if v_div > v_tol then
        -- O achado é dos BALANÇOS, e a planilha não é comparada neste ano:
        -- atribuir a um dos lados uma linha de planilha que não declara lado
        -- seria escolher por sorteio qual metade da contradição é a verdade.
        v_n := v_n + 1;
        v_resultado := 'zona_cinzenta';
        v_partes := v_partes || format(
          '%s: os DOIS LADOS do mesmo mútuo não fecham DENTRO do mandato — a receber soma %s e '
          || 'a pagar soma %s, diferença de %s (em reais). A planilha não foi comparada neste '
          || 'exercício: sem saber qual lado é o correto, atribuir a linha da planilha a um deles '
          || 'seria chute.',
          v_ano, round(v_lados.soma_ativo), round(v_lados.soma_passivo), round(v_div));
        if v_pior_abs is null or v_div > v_pior_abs then
          v_pior_abs := v_div;
          v_pior_pct := case when v_lados.soma_ativo <> 0
                             then v_div / v_lados.soma_ativo end;
        end if;
        continue;
      end if;
      -- Concordam: o saldo do balanço está estabelecido por dupla evidência.
      -- UMA comparação, contra o número que as duas pontas confirmam.
      v_lado_alvo := null;
      v_a := v_lados.soma_ativo;
      v_rotulo_lado := 'os dois lados';
    else
      v_lado_alvo := case when v_lados.soma_ativo is not null then 'ativo' else 'passivo' end;
      v_a := coalesce(v_lados.soma_ativo, v_lados.soma_passivo);
      v_rotulo_lado := v_lado_alvo;
    end if;

    -- 0194: A COLUNA DA PLANILHA-RETRATO. Chegamos aqui só quando o BALANÇO
    -- tem conta de mútuo para este ano (n_lados>0, escala comparável) e uma
    -- planilha foi achada PARA ESTE ANO (achado 3) — então o que falta
    -- resolver agora é só a COLUNA, e é aí que morava o defeito original
    -- desta migration.
    --
    -- `fn_coluna_periodo_do_ano` devolve a sentinela quando o documento TEM
    -- colunas de período e nenhuma é deste ano — a pergunta certa para um
    -- documento COMPARATIVO. A planilha de mútuos de produção não é
    -- comparativa: é um RETRATO de uma data (0145 — o documento é matricial,
    -- a chave é o PAR de empresas e o conceito mora na coluna:
    -- "Mutuante"/"Mutuária"/"Saldo devedor"/"TOTAL"). Nenhum desses
    -- cabeçalhos é ano nenhum, então a sentinela sempre disparava — e antes
    -- desta migration o filtro do LADO B (escrito para NULL) zerava a soma, o
    -- laço caía no `continue` mudo e a função devolvia `documento_ausente`
    -- com um texto falso (ver o cabeçalho). A pergunta certa para um retrato:
    -- o documento escolhido para ESTE ano REALMENTE cobre `v_ano`
    -- (`v_doc_ano_cobre_ano`, achado 3 — não o fallback ambíguo)? Se sim, a
    -- coluna do saldo é a que `v_col_saldo` já achou.
    v_col_mut := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_mut, v_ano) end;
    if v_col_mut = E'\x01' and v_doc_ano_cobre_ano then
      v_col_mut := v_col_saldo;
      if v_col_mut is null then
        -- O documento cobre o ano, mas nenhuma coluna diz "saldo": achado
        -- acionável (o documento pode ter mudado de formato), não silêncio.
        v_motivos_ano := v_motivos_ano || 'linha_nao_localizada'::text;
        v_faltas := v_faltas || format(
          '%s: a planilha de mútuos é retrato deste exercício, mas nenhuma coluna diz '
          '"saldo" (o mesmo termo do localizador da 0145)', v_ano);
        continue;
      end if;
    end if;
    -- `v_ano` nulo (período de consulta que não ancora ano nenhum) ou
    -- `v_doc_ano_cobre_ano = false` (o documento MUTUOS achado só pelo
    -- fallback ambíguo — sem período, ou período que não ancora ano
    -- nenhum): sem como afirmar retrato de QUAL ano, `v_col_mut` segue o que
    -- `fn_coluna_periodo_do_ano` devolveu (tipicamente a sentinela) —
    -- comportamento de ANTES desta migration (mesma exceção que a 0191 já
    -- abre para o Mapa de Dívida). A antiga ramificação "documento não cobre
    -- o ano → `sem_periodo_par`" saiu: a seleção acima (achado 3) já garante
    -- que só se chega aqui com um documento que cobre `v_ano`, ou com o
    -- fallback ambíguo — o caso "não cobre" não sobrevive à seleção. Um
    -- `sem_periodo_par` ainda pode nascer adiante (`fn_motivo_do_lado`), no
    -- raro caso do fallback ambíguo cuja sentinela não resolve nenhuma linha.

    -- ---- LADO B: a planilha ----------------------------------------------
    select coalesce(sum(fn_valor_em_base(ce.valor_num, ce.unidade)), 0) as soma_base,
           coalesce(sum(ce.valor_num), 0) as soma_bruta,
           count(*)::int as n
      into v_pl
    from campo_extraido ce
    where ce.documento_versao_id = v_ver_mut
      and ce.valor_num is not null
      and fn_papel_linha(ce.chave) <> 'subtotal'
      -- MÚTUO CONTRA MÚTUO — nos degraus 1 e 2. A planilha de intragrupo lista
      -- mais coisa que mútuo (conta corrente rotativa, aluguel entre
      -- coligadas, rateio de despesa), e o balanço registra cada natureza num
      -- lugar diferente. Comparar a planilha INTEIRA contra as contas de
      -- mútuo do balanço acusaria como divergência aquilo que é só natureza
      -- diferente.
      --
      -- OS TRÊS DEGRAUS, NA ORDEM. O `case` é o que impede o degrau 2 de valer
      -- quando o degrau 1 existe — sem isso, seção larga ("MÚTUOS E CONTAS
      -- INTRAGRUPO") passa a incluir a conta corrente que o rótulo já tinha
      -- separado, que é o defeito de novo.
      and (case
             when v_pl_rotulo then fn_texto_nomeia_mutuo(ce.chave)
             when v_pl_secao  then fn_texto_nomeia_mutuo(ce.secao)
             else true
           end)
      -- A MESMA RÉGUA DOS DOIS LADOS. Se o balanço exclui o mútuo com sócio e a
      -- planilha não, a diferença que sobra é da régua e não do dado — é o defeito
      -- que a 0123 consertou, cometido de novo em espelho.
      and not fn_mutuo_com_socio(ce.chave, ce.secao)
      -- 0194 (achado 2 da revisão de fidelidade, MEDIDO em produção
      -- só-leitura, 28/09/2026): numa planilha-RETRATO (`v_pl_retrato`) a
      -- `chave` é o PAR de empresas ("ARAUCÁRIA PARTICIPAÇÕES … - AR
      -- SERVIÇOS ADMINISTRATIVOS E COMPARTILHADOS LTDA."), não o lado — e
      -- `fn_lado_do_mutuo` casava "administr**ativo**s" com "...ativo" e
      -- derrubava a linha inteira do lado errado (6,4 mi fora da soma, no
      -- book Canastra — o mesmo 74,56 − 6,40 = 68,16 do achado 1). No "teste
      -- alto volume - grupo araucária" de 2021, as 11 linhas da planilha
      -- chegam com `secao_canonica = 'ativo_circulante'` herdada da
      -- classificação genérica da extração — não é lado contábil nenhum para
      -- uma linha de retrato — e o filtro esvaziava a planilha inteira:
      -- `linha_nao_localizada` falso, 8,725 mi somem. Quando o balanço tem
      -- um lado só e a planilha É comparativa de verdade (`not v_pl_retrato`
      -- — formato da 0123, preservado: o rótulo declara lado de verdade e o
      -- filtro continua valendo), a linha que DECLARA lado tem de ser do
      -- mesmo; a que não declara entra (ela é as duas pontas). Com os dois
      -- lados concordando, `v_lado_alvo` é nulo e não há o que filtrar em
      -- nenhum dos dois formatos.
      and (v_pl_retrato or v_lado_alvo is null
           or coalesce(fn_lado_do_mutuo(ce.chave, ce.secao_canonica), v_lado_alvo) = v_lado_alvo)
      and (v_col_mut is null
           or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(v_col_mut));
    if coalesce(v_pl.n, 0) = 0 then
      -- 0194: a coluna FOI resolvida (ou é o caso "sem como afirmar", ver
      -- acima) e mesmo assim nenhuma linha da planilha casou com o lado do
      -- balanço — achado, não ausência.
      v_motivos_ano := v_motivos_ano || fn_motivo_do_lado(false, null, v_col_mut);
      v_faltas := v_faltas || format('%s: %s', v_ano,
        case when v_col_mut = E'\x01'
             then 'a planilha de mútuos não tem coluna deste exercício'
             else 'a planilha de mútuos não tem linha para o lado do balanço neste exercício' end);
      continue;
    end if;

    v_b := abs(coalesce(v_pl.soma_base, 0));
    v_a := abs(coalesce(v_a, 0));
    v_n := v_n + 1;
    v_div := abs(v_a - v_b);
    -- Tolerância em MOEDA BASE (reais), não na escala do documento: o mesmo
    -- número tem de significar a mesma coisa num balanço em milhar e noutro
    -- em unidade, senão a checagem é mais frouxa justamente onde os valores
    -- são maiores.
    v_tol := greatest(p_tolerancia_abs, v_a * p_tolerancia_pct);

    if v_div > v_tol then
      v_resultado := 'zona_cinzenta';
      v_partes := v_partes || format(
        '%s (%s): balanço soma %s em %s linha(s) de %s documento(s) e a planilha soma %s em %s '
        || 'linha(s) — diferença de %s (em reais, já convertidas as escalas)',
        v_ano, v_rotulo_lado, round(v_a), v_lados.n_linhas, v_lados.n_docs, round(v_b),
        v_pl.n, round(v_div));
      if v_pior_abs is null or v_div > v_pior_abs then
        v_pior_abs := v_div;
        v_pior_pct := case when v_a <> 0 then v_div / v_a end;
      end if;
    else
      v_partes := v_partes || format('%s (%s): confere (balanço %s = planilha %s, em reais)',
        v_ano, v_rotulo_lado, round(v_a), round(v_b));
    end if;

    v_fonte_a := jsonb_build_object('lado', v_rotulo_lado, 'soma_base', v_a,
      'n_linhas', v_lados.n_linhas, 'n_documentos', v_lados.n_docs,
      'exemplo', v_lados.exemplo, 'ano', v_ano);
    v_fonte_b := jsonb_build_object('lado', v_rotulo_lado, 'soma_base', v_b,
      'soma_bruta', v_pl.soma_bruta, 'n_linhas', v_pl.n, 'unidade', v_unid_mut,
      'documento_versao_id', v_ver_mut,
      'natureza_no_rotulo', v_pl_rotulo, 'natureza_na_secao', v_pl_secao);
  end loop;

  if v_n = 0 then
    if cardinality(v_motivos_ano) = 0 then
      -- SEM PENDÊNCIA, e é decisão de projeto: `documento_ausente` é o único
      -- resultado que `fn_registrar_reconciliacao` não transforma em pendência.
      -- 0194 (achado 3 da revisão): quando o ÚNICO motivo de nenhum ano ter
      -- concluído é "a planilha deste exercício não foi entregue" (`v_faltas`
      -- não vazio), o texto diz QUAIS anos — ainda é cobrança de checklist,
      -- não achado, mas nomear o ano que falta é a regra 1 (nota com o
      -- efeito, nunca silêncio liso). Sem NENHUM motivo (`v_faltas` também
      -- vazio): o texto genérico de sempre — não achar linha de mútuo NO
      -- BALANÇO é o caso comum e correto (combinado elimina intragrupo;
      -- individual às vezes agrega em "outras partes relacionadas"). Abrir
      -- pendência aqui encheria a fila de todo mandato com um aviso que não
      -- pede ação nenhuma, e uma fila assim é uma fila que ninguém lê.
      return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
        'mutuos_planilha_vs_balanco', 'B', v_doc_mut, null, null,
        'documento_ausente', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        case when cardinality(v_faltas) > 0 then
          'Balanço com conta de mútuo presente, mas a planilha de mútuos não cobre o(s) '
          || 'exercício(s) em que ela seria comparada — ' || array_to_string(v_faltas, '; ')
          || '. Sem a planilha do exercício, não há o que conferir; é cobrança de checklist '
          || '(kit básico), não achado de reconciliação.'
        else
          'Planilha de mútuos presente, mas nenhum balanço do mandato traz conta de mútuo com lado '
          || 'reconhecível (combinado elimina intragrupo; individual às vezes agrega em "partes '
          || 'relacionadas"). Sem par, não há o que conferir.'
        end);
    end if;

    -- 0194: o balanço TEM conta de mútuo em algum ano, mas a checagem não
    -- concluiu por outro motivo — documento presente e algo não localizado é
    -- ACHADO ACIONÁVEL (0186), não ausência. Abre pendência
    -- (fn_registrar_reconciliacao: todo motivo de precondição além de
    -- documento_ausente abre).
    v_motivo_prec := fn_motivo_precondicao_agregado(v_motivos_ano);
    return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
      'mutuos_planilha_vs_balanco', 'B', v_doc_mut, null, null,
      v_motivo_prec, null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      fn_motivo_precondicao_prefixo(v_motivo_prec)
      || 'Planilha de mútuos e balanço com conta de mútuo presentes, mas a checagem não concluiu '
      || 'em nenhum exercício. ' || array_to_string(v_faltas, '; ') || '.');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
    'mutuos_planilha_vs_balanco', 'B', v_doc_mut, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'comparacoes', v_n,
                       'natureza_no_rotulo', v_pl_rotulo,
                       'natureza_na_secao', v_pl_secao),
    format('Mútuos: a planilha intragrupo contra o saldo dos balanços em %s comparação(ões) — %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$$;

--
-- Name: FUNCTION fn_reconciliar_mutuos(p_caso_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconciliar_mutuos(p_caso_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric) IS '0195: mesmo corpo da 0194, SEM MUDAR COMPORTAMENTO — os dois trechos que decidiam "esta linha vale para este ano" (a prioridade de escolha do balanço em ''balancos'' e o filtro de ''linhas'') agora chamam fn_linha_vale_para_ano em vez de repetir a conta inline, para não divergir de fn_reconciliar_intragrupo, que precisa da MESMA resposta. 0194: a planilha de mútuos é um RETRATO de uma data (0145 — o conceito mora na coluna, não é comparativa): quando a coluna de período sai sentinela e o documento escolhido para o ano cobre de fato o ano (achado 3), a coluna do saldo é achada pelo localizador da 0145 (MUTUOS/saldo_de_mutuo, termo ''saldo''), em vez de zerar a comparação e devolver documento_ausente falso. Retrato sem coluna de saldo, ou planilha sem linha para o lado do balanço: linha_nao_localizada; escala incomparável: unidade_divergente — abrem pendência (0186), diferente de documento_ausente. 0123: a natureza "mútuo" é lida na linha OU na seção. Confere os dois lados entre si antes de comparar a planilha; lados que discordam são o achado, e aí a planilha não é atribuída a um deles. Mútuo com sócio fica fora: não tem espelho no mandato.';

--
-- Name: fn_reconciliar_por_documento(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_por_documento(p_documento_id uuid, p_escopo text DEFAULT 'tudo'::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_id     uuid;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_tipo        text;
  v_checagens   jsonb := '[]'::jsonb;
begin
  -- 0152: o escopo passa a ser declarado. As checagens de CHAVE saíram daqui
  -- para fn_reconciliar_chaves_do_documento, porque elas leem (caso, entidade,
  -- período) e não o documento — e por isso o lote as roda uma vez por chave.
  if p_escopo not in ('tudo', 'documento') then
    raise exception 'escopo inválido: % (use ''tudo'' ou ''documento''; o escopo de caso é '
                    'fn_reconciliar_caso)', p_escopo;
  end if;

  select caso_id, entidade_id, periodo_id, tipo_taxonomia
    into v_caso_id, v_entidade_id, v_periodo_id, v_tipo
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  -- 0133: a conferência INTRA-documento. Se as seções do próprio documento não
  -- fecham, as comparações ENTRE documentos estão sendo feitas sobre números
  -- que já não se sustentam — e é melhor que a fila diga isso antes de dizer
  -- que o Ativo bate com o Passivo (que, com totais impressos dos dois lados,
  -- bate mesmo quando faltam contas no meio).
  --
  -- É A ÚNICA CHECAGEM QUE É DE FATO POR DOCUMENTO, e a 0133 já dizia isso em
  -- comentário: "sem loop de período: a árvore é INTRA-documento". As outras
  -- oito leem (caso, entidade, período) e o documento só entrega a chave.
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    v_checagens := v_checagens || jsonb_build_array(fn_reconciliar_arvore(p_documento_id));
  end if;

  if p_escopo = 'tudo' then
    v_checagens := v_checagens
      || fn_reconciliar_chaves_do_documento(v_caso_id, v_entidade_id, v_periodo_id, v_tipo);
  end if;

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id,
                            'escopo', p_escopo, 'checagens', v_checagens);
end;
$$;

--
-- Name: FUNCTION fn_reconciliar_por_documento(p_documento_id uuid, p_escopo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconciliar_por_documento(p_documento_id uuid, p_escopo text) IS 'Despachante de reconciliação de UM documento (0133/0151/0152). `p_escopo = ''documento''` roda só o que é intra-documento (a árvore); ''tudo'' (padrão) mantém o comportamento anterior e roda também as checagens de chave. Num lote, use ''documento'' aqui e fn_reconciliar_caso uma vez no fim — as checagens de chave não leem o documento, leem (caso, entidade, período).';

--
-- Name: fn_reconciliar_receita_dre_vs_faturamento(uuid, uuid, uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_receita_dre_vs_faturamento(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric DEFAULT 50000, p_tolerancia_pct numeric DEFAULT 0.05) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
declare
  v_doc_dre  uuid;
  v_doc_fat  uuid;
  v_ver_dre  uuid;
  v_ver_fat  uuid;
  v_col_ent  text;
  v_ano      int;
  v_col_per  text;
  v_receita  campo_extraido;
  v_soma_sec record;
  v_val_rec  numeric;
  v_unid_rec text;
  v_chave_rec text;
  v_fat      record;
  v_unid_fat text;
  v_motivo   text;
  v_a numeric; v_b numeric; v_div numeric; v_tol numeric;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_fonte_a jsonb; v_fonte_b jsonb;
  -- 0188
  v_motivos_ano text[] := '{}';
  v_faltas      text[] := '{}';
  v_motivo_prec text;
  -- 0196: período PRÓPRIO da DRE e se este ano do laço cai fora dele.
  v_dre_tipo      text;
  v_dre_ref       text;
  v_dre_outro_ano boolean;
begin
  v_doc_dre := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'DRE');
  v_doc_fat := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'FATURAMENTO_24M');

  if v_doc_dre is null or v_doc_fat is null then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'receita_dre_vs_faturamento', 'B', coalesce(v_doc_dre, v_doc_fat), null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar receita: %s não foi entregue para esta entidade/período.',
        case when v_doc_dre is null and v_doc_fat is null then 'DRE e Faturamento (24m)'
             when v_doc_dre is null then 'DRE' else 'Faturamento (24m)' end));
  end if;

  v_ver_dre  := fn_versao_atual(v_doc_dre);
  v_ver_fat  := fn_versao_atual(v_doc_fat);
  v_col_ent  := fn_coluna_entidade(v_ver_dre, p_entidade_id);
  v_unid_fat := fn_unidade_predominante(v_ver_fat);
  select pe.tipo, pe.referencia into v_dre_tipo, v_dre_ref
    from documento d left join periodo pe on pe.id = d.periodo_id where d.id = v_doc_dre;

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    if v_ano is null then
      -- sem ano não há como recortar o mês. 0188: motivo GENÉRICO de propósito.
      v_motivos_ano := v_motivos_ano || 'precondicao_nao_satisfeita'::text;
      v_faltas := v_faltas || 'o período não tem ano, e sem ano não há como recortar os meses do faturamento'::text;
      continue;
    end if;
    v_col_per := fn_coluna_periodo_do_ano(v_ver_dre, v_ano);
    -- 0196: DRE SEM coluna de período valia para qualquer ano do laço, enquanto o
    -- faturamento é recortado POR ANO — a receita de um exercício saía contra os
    -- meses de outro. Ver o cabeçalho da migration.
    v_dre_outro_ano := false;
    if v_col_per is null
       and not fn_linha_vale_para_ano(v_ver_dre, null, v_dre_tipo, v_dre_ref, v_ano) then
      v_col_per := E'\x01';
      v_dre_outro_ano := true;
    end if;

    select * into v_receita from fn_valor_conceito_col(v_ver_dre,
      array['receita', 'bruta'], array['liquida', 'deducoes', 'deducao'], v_col_ent, v_col_per);
    if v_receita.id is not null then
      v_val_rec := v_receita.valor_num; v_unid_rec := v_receita.unidade;
      v_chave_rec := v_receita.chave;
    else
      -- "RECEITA OPERACIONAL BRUTA" costuma ser CABEÇALHO SEM VALOR: soma as
      -- contas da seção (Vendas de produtos, Prestação de serviços...).
      select * into v_soma_sec from fn_soma_secao(v_ver_dre,
        array['receita', 'bruta'], v_col_ent, v_col_per,
        array['deducoes', 'deducao'],
        array['liquida', 'lucro bruto', 'resultado', 'prejuizo']);
      if coalesce(v_soma_sec.n_linhas, 0) = 0 then
        v_motivos_ano := v_motivos_ano || fn_motivo_do_lado(false, v_col_ent, v_col_per);
        v_faltas := v_faltas || format('%s: %s', v_ano,
          case when v_dre_outro_ano then format('a DRE é de %s — não traz este exercício', v_dre_ref)
               when v_col_per = E'\x01' then 'a DRE não tem coluna deste exercício'
               when v_col_ent = E'\x01' then 'a DRE não tem coluna desta entidade'
               else 'a Receita Bruta da DRE não foi localizada (nem como linha, nem como seção)' end);
        continue;
      end if;
      v_val_rec := v_soma_sec.soma; v_unid_rec := v_soma_sec.unidade;
      v_chave_rec := format('soma de %s contas da seção Receita Bruta', v_soma_sec.n_linhas);
    end if;

    select soma, n_linhas into v_fat
    from fn_somar_faturamento_ano(v_ver_fat, v_ano::text, right(v_ano::text, 2));
    if coalesce(v_fat.n_linhas, 0) = 0 then
      -- 0188: GENÉRICO de propósito — "o relatório não tem este ano" e "o
      -- rótulo do mês não carrega o ano" são indistinguíveis daqui.
      v_motivos_ano := v_motivos_ano || 'precondicao_nao_satisfeita'::text;
      v_faltas := v_faltas || format('%s: o Faturamento não traz linha mensal deste ano', v_ano);
      continue;
    end if;

    v_motivo := fn_motivo_escala_incomparavel(v_unid_rec, v_unid_fat,
      'a Receita Bruta da DRE', 'o Faturamento mensal');
    if v_motivo is not null then
      return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
        'receita_dre_vs_faturamento', 'B', v_doc_dre, null, null,
        'unidade_divergente', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        fn_motivo_precondicao_prefixo('unidade_divergente') || v_motivo);
    end if;

    v_a := fn_valor_em_base(v_val_rec, v_unid_rec);
    v_b := fn_valor_em_base(v_fat.soma, v_unid_fat);
    v_n := v_n + 1;
    v_div := abs(v_a - v_b);
    -- 0193: A TOLERÂNCIA ABSOLUTA ESTÁ NA BASE, como v_a e v_b. Da 0023 até
    -- aqui ela era `p_tolerancia_abs * fator_da_escala`: numa DRE em
    -- 'milhar', os R$ 50.000 do default viravam R$ 50 MILHÕES, e uma
    -- diferença de até 30% da receita sairia "confere" (ver o cabeçalho
    -- desta migration). MEDIDO EM PRODUÇÃO (25/09/2026, somente leitura,
    -- recomputando fonte_a/fonte_b): das 30 receita_dre_vs_faturamento com
    -- resultado 'ok' (10 em 'milhar'), 0 mudariam de resultado com a
    -- tolerância na base — a pior diferença entre elas chega a 4,75%, abaixo
    -- do piso percentual de 5%. Correção LATENTE. MEDIDO (regra 2): com o
    -- `× fator` de volta, o assert do bloco 2 de
    -- Supabase/test/tolerancia_na_base.test.sql reprova.
    v_tol := greatest(p_tolerancia_abs, abs(v_a) * p_tolerancia_pct);
    if v_div > v_tol then
      v_resultado := 'zona_cinzenta';
      v_partes := v_partes || format('%s: Receita Bruta %s vs %s meses de faturamento %s — diferença de %s '
        || '(Classe B: faturamento e receita reconhecida podem divergir por competência/recorte)',
        v_ano, v_val_rec, v_fat.n_linhas, v_fat.soma, v_div);
      if v_pior_abs is null or v_div > v_pior_abs then
        v_pior_abs := v_div;
        v_pior_pct := case when v_a <> 0 then v_div / abs(v_a) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (Receita Bruta %s = soma de %s meses %s)',
        v_ano, v_val_rec, v_fat.n_linhas, v_fat.soma);
    end if;
    v_fonte_a := jsonb_build_object('chave', v_chave_rec, 'valor', v_val_rec,
      'unidade', v_unid_rec, 'ano', v_ano, 'documento_versao_id', v_ver_dre);
    v_fonte_b := jsonb_build_object('soma_faturamento', v_fat.soma, 'n_meses', v_fat.n_linhas,
      'ano', v_ano, 'unidade', v_unid_fat, 'documento_versao_id', v_ver_fat);
  end loop;

  if v_n = 0 then
    v_motivo_prec := fn_motivo_precondicao_agregado(v_motivos_ano);
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'receita_dre_vs_faturamento', 'B', v_doc_dre, null, null,
      v_motivo_prec, null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      fn_motivo_precondicao_prefixo(v_motivo_prec)
      || 'DRE e Faturamento presentes, mas não foi possível casar Receita Bruta e meses do mesmo ano '
      || '(rótulos extraídos não bateram, ou o faturamento não traz o mês por linha). '
      || array_to_string(v_faltas, '; ') || '.');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'receita_dre_vs_faturamento', 'B', v_doc_dre, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n),
    format('Receita Bruta da DRE vs faturamento mensal em %s ano(s): %s.%s',
           v_n, array_to_string(v_partes, '; '),
           case when cardinality(v_faltas) > 0
                then ' Não comparado — ' || array_to_string(v_faltas, '; ') || '.' else '' end));
end;
$_$;

--
-- Name: fn_reconciliar_versoes_do_periodo(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_versoes_do_periodo(p_caso_id uuid, p_entidade_id uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_entidade  text;
  v_c         record;
  v_n         int := 0;
  v_empates   int := 0;
  v_maior     numeric := 0;
  v_detalhe   jsonb := '[]'::jsonb;
  v_descricao text;
  v_resultado text;
  v_documento uuid;
begin
  select razao_social into v_entidade from entidade where id = p_entidade_id;

  for v_c in
    select * from fn_conflitos_do_caso(p_caso_id, v_entidade)
    order by diferenca desc
  loop
    v_n := v_n + 1;
    if not v_c.decidido then v_empates := v_empates + 1; end if;
    v_maior := greatest(v_maior, v_c.diferenca);
    v_detalhe := v_detalhe || jsonb_build_array(jsonb_build_object(
      'secao_canonica', v_c.secao_canonica, 'conta', v_c.chave,
      'entidade', v_c.entidade, 'exercicio', v_c.exercicio,
      'vencedor', jsonb_build_object('documento_id', v_c.documento_vencedor,
                                     'tipo', v_c.tipo_vencedor, 'valor', v_c.valor_vencedor),
      'perdedor', jsonb_build_object('documento_id', v_c.documento_perdedor,
                                     'tipo', v_c.tipo_perdedor, 'valor', v_c.valor_perdedor),
      'diferenca', v_c.diferenca, 'decidido', v_c.decidido, 'criterio', v_c.criterio));
  end loop;

  -- O documento de MAIOR diferença ancora o link da tela. O conflito é entre
  -- dois, então não há "o" documento — mas mandar quem lê para o mais material
  -- é melhor que mandar para o mais antigo.
  v_documento := (v_detalhe->0->'perdedor'->>'documento_id')::uuid;
  if v_documento is null then
    select d.id into v_documento
    from documento d
    where d.caso_id = p_caso_id
      and (p_entidade_id is null or d.entidade_id = p_entidade_id)
    order by d.criado_em
    limit 1;
  end if;

  if v_n = 0 then
    v_resultado := 'ok';
    v_descricao := 'Nenhuma conta em que dois documentos do mesmo exercício discordem.';
  else
    v_resultado := 'divergencia';
    v_descricao := format(
      '%s conta(s) em que dois documentos do mesmo exercício discordam (maior diferença: %s). '
      || '%s'
      || 'NADA foi apagado: o número do perdedor continua gravado, e é ele a evidência de que '
      || 'houve escolha. Conflitos: %s',
      v_n, to_char(v_maior, 'FM999G999G999D00'),
      case when v_empates > 0
           -- 0159: "empatam" deixou de ser a única causa de `decidido = false`
           -- — um rótulo contestado pelo diagnóstico (0159) também zera a
           -- decisão automática sem que a autoridade numérica empate.
           then format('%s deles NÃO TÊM decisão automática (empate de autoridade, ou o rótulo '
                       || 'de um dos dois contestado pelo próprio diagnóstico de conteúdo) e '
                       || 'ninguém decidiu por você — o valor em uso continua o de maior módulo, '
                       || 'que é o padrão antigo. ',
                       v_empates)
           else '' end,
      (select string_agg(format('%s (%s): %s diz %s, %s diz %s — %s',
                                x->>'conta', x->>'exercicio',
                                x->'vencedor'->>'tipo',
                                to_char((x->'vencedor'->>'valor')::numeric, 'FM999G999G999D00'),
                                x->'perdedor'->>'tipo',
                                to_char((x->'perdedor'->>'valor')::numeric, 'FM999G999G999D00'),
                                x->>'criterio'), '; ')
         from jsonb_array_elements(v_detalhe) x));
  end if;

  return fn_registrar_reconciliacao(
    p_caso_id, p_entidade_id, null, 'conflito_entre_documentos', 'A', v_documento,
    jsonb_build_object('conflitos', v_detalhe), null,
    v_resultado, v_maior, null,
    jsonb_build_object('tolerancia_abs', 100, 'tolerancia_pct', 0.005,
                       'criterio', 'mesma seção canônica, mesmo rótulo, mesmo exercício, mesma '
                                || 'entidade, papel conta, unidade conversível; vencedor por '
                                || 'autoridade documental (taxonomia_tipo_documento.autoridade)',
                       'empates', v_empates),
    v_descricao);
end;
$$;

--
-- Name: FUNCTION fn_reconciliar_versoes_do_periodo(p_caso_id uuid, p_entidade_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconciliar_versoes_do_periodo(p_caso_id uuid, p_entidade_id uuid) IS 'Checagem de reconciliação (0151): duas versões do mesmo período discordando sobre a mesma conta. Declara o vencedor por autoridade documental e o critério; sem decisão automática (empate de autoridade, ou desde a 0159, rótulo contestado pelo diagnóstico) volta para o humano sem trocar valor nenhum.';

--
-- Name: fn_reconferir_caso(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconferir_caso(p_caso_id uuid, p_autor text DEFAULT 'portal:reconferir'::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_doc          record;
  v_versao       uuid;
  v_n_docs       int := 0;
  v_resolvidas   int := 0;
  v_abertas      int := 0;
  v_r            jsonb;
  v_antes        int;
  v_depois       int;
  v_completude   jsonb;
begin
  if not exists (select 1 from caso where id = p_caso_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Caso %s não existe.', p_caso_id));
  end if;

  select count(*) into v_antes from pendencia where caso_id = p_caso_id and estado <> 'resolvida';

  for v_doc in select id from documento where caso_id = p_caso_id order by criado_em loop
    v_n_docs := v_n_docs + 1;
    -- Reconciliação A/B: as próprias checagens abrem e resolvem pendência, com a
    -- regra de hoje (é o que a 0034 corrigiu e nunca foi reaplicado ao v35).
    perform fn_reconciliar_por_documento(v_doc.id);

    v_versao := fn_versao_atual(v_doc.id);
    if v_versao is not null then
      v_r := fn_reavaliar_guardas_extracao(v_versao, p_autor);
      v_resolvidas := v_resolvidas + coalesce(jsonb_array_length(v_r->'resolvidas'), 0);
      v_abertas := v_abertas + coalesce(jsonb_array_length(v_r->'abertas'), 0);
    end if;
  end loop;

  v_completude := fn_recomputar_completude(p_caso_id);

  select count(*) into v_depois from pendencia where caso_id = p_caso_id and estado <> 'resolvida';

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'reconferir_caso', 'caso:'||p_caso_id,
            jsonb_build_object('pendencias_abertas', v_antes),
            jsonb_build_object('pendencias_abertas', v_depois, 'documentos', v_n_docs,
                               'guardas_resolvidas', v_resolvidas, 'guardas_abertas', v_abertas));

  return jsonb_build_object(
    'caso_id', p_caso_id,
    'documentos_reconferidos', v_n_docs,
    'pendencias_abertas_antes', v_antes,
    'pendencias_abertas_depois', v_depois,
    'guardas_resolvidas', v_resolvidas,
    'guardas_abertas', v_abertas,
    'completude', v_completude,
    -- O NÚMERO QUE IMPORTA para quem clicou: quantos achados eram de regra velha.
    'achados_de_regra_velha', greatest(v_antes - v_depois, 0));
end;
$$;

--
-- Name: FUNCTION fn_reconferir_caso(p_caso_id uuid, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconferir_caso(p_caso_id uuid, p_autor text) IS 'Reaplica as regras de HOJE (reconciliação A/B, guardas de extração, completude) sobre o dado já gravado, sem gastar chamada de IA. Existe porque pendência é estado gravado e nada a reavaliava quando uma migration corrigia a regra — o portal mostrava achado corrigido como se fosse corrente (caso real: as duas pendências do v35 que a 0034 já havia fechado).';

--
-- Name: fn_reescrever_recado_linha_exigida(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reescrever_recado_linha_exigida(p_tipo text, p_conceito text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_caso    uuid;
  v_ex      record;
  v_motivo  text;
  v_n       int;
  v_total   int := 0;
  v_casos   int := 0;
  v_abertas int;
  v_prefixo text := 'completude:linha_exigida:' || p_tipo || ':' || p_conceito;
begin
  -- `like` com o conceito escapado: '_' é curinga, e despesa_financeira o tem.
  select count(*) into v_abertas
    from pendencia
   where tipo = 'linha_exigida_ausente' and estado = 'aberta'
     and (motivo = v_prefixo
          or motivo like replace(v_prefixo, '_', '\_') || ':%');

  for v_caso in
    select distinct caso_id from pendencia
     where tipo = 'linha_exigida_ausente' and estado = 'aberta'
       and (motivo = v_prefixo
            or motivo like replace(v_prefixo, '_', '\_') || ':%')
  loop
    v_casos := v_casos + 1;
    for v_ex in
      select * from fn_exigencias_do_caso(v_caso) x
       where x.tipo_taxonomia = p_tipo and x.conceito = p_conceito
         and not x.satisfeita and x.alternativa_recado is not null
    loop
      -- O MESMO motivo que fn_recomputar_completude monta (0119).
      v_motivo := 'completude:linha_exigida:' || v_ex.tipo_taxonomia || ':' || v_ex.conceito
                  || case when v_ex.entidade is not null
                          then ':' || fn_entidade_canonica(v_ex.entidade) else '' end;
      update pendencia
         set descricao = fn_descricao_linha_exigida(v_ex.tipo_taxonomia, v_ex.entidade,
                           v_ex.rotulo, v_ex.depende_de, v_ex.origem,
                           v_ex.alternativa_rotulo, v_ex.alternativa_recado)
       where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado = 'aberta'
         and motivo = v_motivo
         and descricao is distinct from fn_descricao_linha_exigida(v_ex.tipo_taxonomia,
                           v_ex.entidade, v_ex.rotulo, v_ex.depende_de, v_ex.origem,
                           v_ex.alternativa_rotulo, v_ex.alternativa_recado);
      get diagnostics v_n = row_count;
      v_total := v_total + v_n;
    end loop;
  end loop;

  return jsonb_build_object('abertas', v_abertas, 'casos_olhados', v_casos,
                            'reescritas', v_total);
end;
$$;

--
-- Name: FUNCTION fn_reescrever_recado_linha_exigida(p_tipo text, p_conceito text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reescrever_recado_linha_exigida(p_tipo text, p_conceito text) IS '0188: reescreve SÓ a descrição das pendências linha_exigida_ausente ABERTAS da exigência (tipo, conceito) cuja entidade tem alternativa em taxonomia_linha_alternativa — o texto que o próximo recompute escreveria. Não abre, não resolve, não toca em aceita_com_ressalva. Ação de migration/service_role — sem grant para o portal.';

--
-- Name: fn_registrar_arquivo_oficial(uuid, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_arquivo_oficial(p_caso uuid, p_documento uuid, p_envelope jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_liga  boolean;
  v_id    uuid;
  v_antiga text;
  v_atualizado boolean := false;
  r       arquivo_oficial;   -- o envelope novo
  e       arquivo_oficial;   -- a linha que já existia, se houver
  v_fim   arquivo_oficial;
begin
  select trilha_transacional into v_liga from caso where id = p_caso;
  if v_liga is null then
    raise exception 'fn_registrar_arquivo_oficial: o caso % não existe', p_caso;
  end if;
  if not v_liga then
    raise exception 'fn_registrar_arquivo_oficial: a trilha de arquivos oficiais está DESLIGADA no caso % — recusado, nada foi gravado. Para ligar: update caso set trilha_transacional = true where id = ''%''.', p_caso, p_caso;
  end if;
  if p_envelope is null or coalesce(p_envelope->>'hash_sha256', '') = '' then
    raise exception 'fn_registrar_arquivo_oficial: o envelope não traz hash_sha256 — sem ele não há idempotência';
  end if;

  -- Quem decide id, vigente, substituido_por e seq é a regra, não o envelope: nem o INSERT nem o UPDATE
  -- abaixo leem essas quatro de `r`, mesmo que o jsonb as traga.
  r := jsonb_populate_record(null::arquivo_oficial, p_envelope);

  -- Serializa o mesmo (caso, hash) e o mesmo (caso, chave): dois leitores concorrentes não se atropelam.
  perform pg_advisory_xact_lock(hashtextextended(p_caso::text || '|' || r.hash_sha256, 0));
  select * into e from arquivo_oficial where caso_id = p_caso and hash_sha256 = r.hash_sha256;
  perform pg_advisory_xact_lock(hashtextextended(p_caso::text || '#' || coalesce(r.chave_natural, ''), 0));
  if e.id is not null and e.chave_natural is distinct from r.chave_natural then
    perform pg_advisory_xact_lock(hashtextextended(p_caso::text || '#' || coalesce(e.chave_natural, ''), 0));
  end if;

  if e.id is not null then
    if e.status = 'lido' and e.leitor_versao = r.leitor_versao then
      -- Reenvio puro: devolve o que existe (só completa o documento, se faltava).
      if e.documento_id is null and p_documento is not null then
        update arquivo_oficial set documento_id = p_documento where id = e.id;
      end if;
      v_id := e.id;
    else
      -- Releitura: o arquivo mal lido, ou lido por outro leitor, passa a valer o que o envelope novo diz.
      update arquivo_oficial set
        documento_id = coalesce(p_documento, documento_id), familia = r.familia, subtipo = r.subtipo,
        versao_leiaute = r.versao_leiaute, cnpj = r.cnpj, periodo_ini = r.periodo_ini,
        periodo_fim = r.periodo_fim, chave_natural = r.chave_natural,
        retificadora = coalesce(r.retificadora, false), controle_tipo = r.controle_tipo,
        controle_declarado = r.controle_declarado, controle_lido = r.controle_lido, status = r.status,
        detalhe = coalesce(r.detalhe, '{}'::jsonb), leitor_versao = r.leitor_versao,
        lido_em = coalesce(r.lido_em, now()),
        vigente = false, substituido_por = null
       where id = e.id;
      v_id := e.id;
      v_atualizado := true;
      v_antiga := e.chave_natural;
    end if;
  else
    insert into arquivo_oficial
      (caso_id, documento_id, familia, subtipo, versao_leiaute, hash_sha256, cnpj, periodo_ini, periodo_fim,
       chave_natural, retificadora, controle_tipo, controle_declarado, controle_lido, status, detalhe,
       leitor_versao, lido_em)
    values
      (p_caso, p_documento, r.familia, r.subtipo, r.versao_leiaute, r.hash_sha256, r.cnpj, r.periodo_ini,
       r.periodo_fim, r.chave_natural, coalesce(r.retificadora, false), r.controle_tipo, r.controle_declarado,
       r.controle_lido, r.status, coalesce(r.detalhe, '{}'::jsonb), r.leitor_versao, coalesce(r.lido_em, now()))
    returning id into v_id;
    v_atualizado := false;
  end if;

  if not (e.id is not null and not v_atualizado) then
    -- Linha nova ou atualizada: recalcula a chave nova e, se a linha mudou de chave, a antiga também.
    if r.chave_natural is null then
      update arquivo_oficial set vigente = true where id = v_id and status = 'lido';
    else
      perform fn_recalcular_vigencia_arquivo_oficial(p_caso, r.chave_natural);
    end if;
    if v_atualizado and v_antiga is not null and v_antiga is distinct from r.chave_natural then
      perform fn_recalcular_vigencia_arquivo_oficial(p_caso, v_antiga);
    end if;
  end if;

  select * into v_fim from arquivo_oficial where id = v_id;
  return jsonb_build_object('id', v_fim.id, 'status', v_fim.status, 'vigente', v_fim.vigente,
                            'atualizado', v_atualizado, 'vigencia', v_fim.detalhe->>'vigencia');
end $$;

--
-- Name: FUNCTION fn_registrar_arquivo_oficial(p_caso uuid, p_documento uuid, p_envelope jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_arquivo_oficial(p_caso uuid, p_documento uuid, p_envelope jsonb) IS 'Registra o envelope de um arquivo oficial lido e devolve jsonb {id, status, vigente, atualizado, vigencia}. Recusa com exceção se caso.trilha_transacional = false. Mesmo (caso, hash): lido com o mesmo leitor_versao é reenvio puro; status != lido ou outro leitor_versao ATUALIZA a linha e recalcula a vigência das chaves antiga e nova. Aplica a regra de versão vigente (G9). 0206.';

--
-- Name: fn_registrar_campos_extraidos(uuid, jsonb, public.nivel_autonomia, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_campos_extraidos(p_documento_versao_id uuid, p_campos jsonb, p_nivel public.nivel_autonomia DEFAULT 'N0'::public.nivel_autonomia, p_falha_motivo text DEFAULT NULL::text, p_tem_dado_financeiro boolean DEFAULT NULL::boolean) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
declare
  v_count            int := 0;
  v_item             jsonb;
  v_valor             numeric;
  v_confianca          numeric;
  v_status_aceite      text;
  v_aceito_por         text;
  v_aceito_em          timestamptz;
  v_n_auto_aceitos     int := 0;
  v_documento_id       uuid;
  v_caso_id            uuid;
  v_nome_original      text;
  v_pendencia_id       uuid;
  v_guarda_disparou    boolean := false;
  v_nivel_dial         nivel_autonomia;
  v_limiar             numeric;
  v_auto_permitido     boolean;
  v_n_excluidas        int := 0;
  v_g                  jsonb;
  v_tipo               text;
  v_secao              text;
  v_inferida           boolean;
  v_herdadas           jsonb;
begin
  -- 0203: o tipo do documento entra na inferência da seção (fn_secao_canonica_da_secao_bruta).
  select d.tipo_taxonomia into v_tipo
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  select ea.nivel_atual, ea.limiar_auto_clear into v_nivel_dial, v_limiar
  from estagio_autonomia ea where ea.estagio = 'extracao_linhas_financeiras';
  v_auto_permitido := v_nivel_dial in ('N2', 'N3') and v_limiar is not null;

  if p_campos is not null and jsonb_typeof(p_campos) = 'array' then
    for v_item in select * from jsonb_array_elements(p_campos)
    loop
      v_valor := case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$' then (v_item->>'valor_num')::numeric else null end;
      v_confianca := case when (v_item->>'confianca') ~ '^-?\d+(\.\d+)?$' then (v_item->>'confianca')::numeric else null end;

      -- 0203: a IA devolve `secao_canonica` nula em parte das linhas (medido em produção em 05/10/2026: 136 de
      -- 724 numa DRE) e a linha some de receita/custo/giro. Só quando a IA NÃO deu (nulo ou em branco) a seção
      -- é inferida do texto da seção bruta; o que veio NUNCA é sobrescrito. A linha diz que foi inferida.
      v_secao := v_item->>'secao_canonica';
      v_inferida := false;
      if nullif(btrim(v_secao), '') is null then
        v_secao := fn_secao_canonica_da_secao_bruta(v_item->>'secao', v_tipo);
        v_inferida := v_secao is not null;
      end if;

      v_status_aceite := 'pendente';
      v_aceito_por := null;
      v_aceito_em := null;
      if v_auto_permitido and v_confianca is not null and v_confianca >= v_limiar then
        v_n_auto_aceitos := v_n_auto_aceitos + 1;
      end if;

      insert into campo_extraido
        (documento_versao_id, chave, valor_texto, valor_num, unidade, moeda, confianca,
         origem_pagina, origem_linha, ordem, nivel_autonomia, secao, secao_canonica, secao_canonica_inferida, entidade_coluna, periodo_coluna,
         status_aceite, aceito_por, aceito_em)
      values (
        p_documento_versao_id,
        coalesce(v_item->>'chave', '(sem rótulo)'),
        v_item->>'valor_texto',
        v_valor,
        v_item->>'unidade',
        v_item->>'moeda',
        v_confianca,
        case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int else null end,
        v_item->>'origem_linha',
        case when (v_item->>'ordem') ~ '^\d+$' then (v_item->>'ordem')::int else null end,
        p_nivel,
        v_item->>'secao',
        v_secao,
        v_inferida,
        v_item->>'entidade_coluna',
        v_item->>'periodo_coluna',
        v_status_aceite,
        v_aceito_por,
        v_aceito_em
      );
      v_count := v_count + 1;
    end loop;
  end if;

  -- 0204: a seção que nem a IA nem o nome da seção bruta deram, herdada da ÁRVORE DO PRÓPRIO DOCUMENTO. Precisa do
  -- documento inteiro, por isso depois do laço de inserção e ANTES de tudo o que lê secao_canonica (guardas, completude,
  -- classificação contábil). O n8n grava UMA vez por documento (nó "Gravar Campos (Sombra)", depois de "Juntar Blocos"),
  -- então este é o ponto em que o documento está completo; se um dia a gravação for por bloco, a função é idempotente e
  -- sobre a versão inteira, e a última chamada converge. Não muda a assinatura: sem reimportar workflow.
  v_herdadas := fn_herdar_secao_pela_arvore(p_documento_versao_id);
  if (v_herdadas->>'linhas')::int > 0 or (v_herdadas->>'conflitos')::int > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'secao_herdada_pela_arvore', 'documento_versao:'||p_documento_versao_id, v_herdadas);
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel, 'falha_motivo', p_falha_motivo,
                               'tem_dado_financeiro', p_tem_dado_financeiro, 'auto_aceitos', v_n_auto_aceitos));

  select d.id, d.caso_id, dv.nome_original into v_documento_id, v_caso_id, v_nome_original
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'extracao_orfa', 'documento_versao:'||coalesce(p_documento_versao_id::text,'null'),
              jsonb_build_object('campos_descartados', v_count, 'falha_motivo', p_falha_motivo,
                                 'porque', 'documento_versao inexistente: campos e motivo nao tinham onde ser gravados'));
    raise warning 'fn_registrar_campos_extraidos: documento_versao % inexistente; % campo(s) e o motivo "%" foram descartados',
      p_documento_versao_id, v_count, coalesce(p_falha_motivo, '(sem motivo)');
    return v_count;
  end if;

  v_g := fn_avaliar_guardas_extracao(p_documento_versao_id);

  if v_count > 0 then
    -- ----- Sinal 1 (0013/0022/0034): mesmo valor material repetido em contas ---
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:padrao_suspeito:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if (v_g->>'padrao_suspeito')::boolean then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_padrao_suspeito', 'importante', true,
            format('%s contas diferentes, na MESMA coluna, vieram com o MESMO valor material (%s) — padrão '
                   'típico de fabricação/alucinação, não de dado real. Conferir contra o arquivo original. '
                   'Contas: %s',
                   v_g->>'n_contas_repetindo', round((v_g->>'valor_repetido')::numeric, 2),
                   array_to_string(array(select jsonb_array_elements_text(v_g->'rotulos_repetindo')), '; ')),
            v_documento_id, 'extracao:padrao_suspeito:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;

    -- ----- Sinal 2 (0013): parcela relevante das linhas com confiança baixa ----
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:baixa_confianca:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if (v_g->>'baixa_confianca')::boolean then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_baixa_confianca', 'importante', true,
            format('%s de %s linhas extraídas vieram com confiança abaixo de 70%%. Revisar antes de aceitar.',
                   v_g->>'n_baixa_confianca', v_count),
            v_documento_id, 'extracao:baixa_confianca:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;
  end if;

  -- ----- Sinal 3 (0016/0029, unidade corrigida por 0111) ---------------------
  -- "veio vazia" só é sinal de FALHA quando ninguém disse o contrário. Um
  -- chamador antigo (workflow não reimportado) manda `p_tem_dado_financeiro`
  -- null, e o comportamento é IDÊNTICO ao de antes desta migration
  -- (coalesce(null, true) = true). Só o diagnóstico da própria chamada, com
  -- `false` explícito, prova que zero linhas era o resultado certo.
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:falhou:' || v_documento_id and estado <> 'resolvida'
    limit 1;
  if p_falha_motivo is not null or (v_count = 0 and coalesce(p_tem_dado_financeiro, true)) then
    v_guarda_disparou := true;
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'extracao', 'extracao_falhou', 'importante', true,
          fn_descricao_extracao_falhou(v_nome_original, v_count, p_falha_motivo),
          v_documento_id, 'extracao:falhou:' || v_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
      where id = v_pendencia_id;
  end if;

  -- ----- Auto-aceite (0029): DEPOIS das guardas, nunca antes -----------------
  --
  -- 0141: E A TRILHA PASSA A DIZER QUANTO O LIMIAR FILTROU, porque medido em
  -- 24/08 ele nunca filtrou nada. Em 15.030 linhas gravadas por este sistema, a
  -- confiança auto-reportada assumiu TRÊS valores — 0,95, 0,99 e 1 — e o limiar
  -- de `extracao_linhas_financeiras` é 0,95. O limiar é exatamente o PISO do que
  -- o modelo já emitiu: `confianca >= v_limiar` é satisfeito por toda linha que
  -- já existiu, e 14.470 das 15.030 foram auto-aceitas (as outras 560 foram
  -- barradas por GUARDA, não por confiança).
  --
  -- A guarda de baixa confiança (Sinal 2, limiar 0,70) nunca disparou pelo mesmo
  -- motivo: zero linhas abaixo de 0,70 em toda a história do banco.
  --
  -- Isto NÃO muda comportamento — decisão do dono, 24/08. O que muda é que a
  -- decisão passa a registrar quantas linhas o limiar excluiu. Quando exclui
  -- zero, ela diz isso com todas as letras, porque um portão que aprova tudo e
  -- não declara que aprovou tudo é pior que portão nenhum: ele parece funcionar.
  v_n_excluidas := greatest(v_count - v_n_auto_aceitos, 0);
  if v_n_auto_aceitos > 0 and not v_guarda_disparou then
    update campo_extraido
      set status_aceite = 'aceito',
          aceito_por = format('sistema:auto_aceite (dial %s, limiar %s, sem guarda disparada)',
                              v_nivel_dial, v_limiar),
          aceito_em = now()
      where documento_versao_id = p_documento_versao_id
        and confianca >= v_limiar
        and status_aceite = 'pendente';

    insert into decisao (caso_id, tipo, autor, motivo, payload)
      values (v_caso_id, 'aprovacao', 'sistema:auto_aceite',
        format('%s linha(s) auto-aceitas na extração de "%s" — dial %s, limiar %s, nenhuma guarda disparou. %s',
               v_n_auto_aceitos, coalesce(v_nome_original, '?'), v_nivel_dial, v_limiar,
               case when v_n_excluidas = 0
                 then format('O limiar NAO excluiu nenhuma das %s linhas: a confiança auto-reportada não '
                             'discriminou nada nesta versão, e o que barra linha aqui são as guardas.', v_count)
                 else format('O limiar deixou %s de %s linha(s) pendentes.', v_n_excluidas, v_count)
               end),
        jsonb_build_object('documento_id', v_documento_id, 'documento_versao_id', p_documento_versao_id,
                           'n_auto_aceitos', v_n_auto_aceitos,
                           'n_excluidas_pelo_limiar', v_n_excluidas,
                           'limiar_discriminou', v_n_excluidas > 0));
  elsif v_n_auto_aceitos > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:auto_aceite', 'auto_aceite_suprimido', 'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('n_elegiveis', v_n_auto_aceitos,
                                 'n_excluidas_pelo_limiar', v_n_excluidas,
                                 'limiar_discriminou', v_n_excluidas > 0,
                                 'porque', 'guarda de extracao disparou; linhas seguem pendentes de revisao humana'));
  end if;
  perform fn_recomputar_completude(v_caso_id);

  -- 0128: A CLASSIFICAÇÃO CONTÁBIL RODA AQUI, e o lugar não é arbitrário.
  --
  -- Este é o único ponto do pipeline que roda DEPOIS da extração — é o mesmo
  -- motivo pelo qual a 0036 pôs a recomputação de completude nesta linha, e o
  -- comentário dela explica: `Registrar Documento` liga em paralelo para a
  -- completude e para a extração, então nada que dependa das linhas extraídas pode
  -- morar antes daqui.
  --
  -- Pendurar aqui também é o que evita REIMPORTAR o workflow: um nó novo no canvas
  -- exigiria isso do dono, e o n8n executa o JSON importado (merge não reimporta).
  --
  -- E é seguro por construção: em N0 a função só escreve em campo_classe_sugerida.
  -- Não abre pendência, não toca em campo_extraido, não entra em caminho de export.
  -- O pior caso dela é não fazer nada — se o dial não tiver a linha do estágio, ela
  -- devolve zero e segue.
  perform fn_classificar_contabil(p_documento_versao_id);

  return v_count;
end;
$_$;

--
-- Name: FUNCTION fn_registrar_campos_extraidos(p_documento_versao_id uuid, p_campos jsonb, p_nivel public.nivel_autonomia, p_falha_motivo text, p_tem_dado_financeiro boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_campos_extraidos(p_documento_versao_id uuid, p_campos jsonb, p_nivel public.nivel_autonomia, p_falha_motivo text, p_tem_dado_financeiro boolean) IS 'Grava campos extraídos e roda as três guardas (0043: fn_avaliar_guardas_extracao). Sinal 3 ("veio vazia") só dispara extracao_falhou quando p_tem_dado_financeiro não é explicitamente false — 0111: documento sem valor monetário por natureza (certidão, organograma, parecer de auditoria) não é falha de extração. 0203: quando a IA não dá secao_canonica, ela é inferida do texto da seção bruta (fn_secao_canonica_da_secao_bruta) e a linha grava secao_canonica_inferida = true; o que a IA deu nunca é sobrescrito. 0204: depois do laço, a seção que ainda falta é herdada pela árvore do próprio documento (fn_herdar_secao_pela_arvore).';

--
-- Name: fn_registrar_classe_override(uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_classe_override(p_campo_extraido_id uuid, p_classe_final text, p_autor text, p_motivo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_sug   text;
  v_id    uuid;
begin
  if not exists (select 1 from campo_extraido where id = p_campo_extraido_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Linha extraída %s não existe.', p_campo_extraido_id));
  end if;
  if not exists (select 1 from classe_contabil_catalogo
                  where codigo = p_classe_final and ativo) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('"%s" não é uma classe contábil ativa. A taxonomia é FECHADA '
                              '(Arquitetura do Sistema/2 Especificação/05) e mora em classe_contabil_catalogo — rótulo novo entra por '
                              'linha de catálogo, não por chamada.', p_classe_final));
  end if;
  if coalesce(trim(p_autor), '') = '' then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Override sem autor não é override: o Arquitetura do Sistema/2 Especificação/05 exige autor no registro, e sem '
                       'ele o sinal de calibração não tem de quem discordar.');
  end if;

  select s.classe_codigo into v_sug
  from campo_classe_sugerida s
  where s.campo_extraido_id = p_campo_extraido_id
  order by s.criado_em desc, s.id desc limit 1;

  insert into campo_classe_override
    (campo_extraido_id, classe_final, sugestao_original, autor, motivo)
  values (p_campo_extraido_id, p_classe_final, v_sug, trim(p_autor), p_motivo)
  returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (trim(p_autor), 'classe_contabil_override',
            'campo_extraido:'||p_campo_extraido_id,
            jsonb_build_object('sugestao', v_sug),
            jsonb_build_object('classe_final', p_classe_final, 'motivo', p_motivo,
                               'discordou', v_sug is not null and v_sug <> p_classe_final));

  return jsonb_build_object('override_id', v_id, 'classe_final', p_classe_final,
                            'sugestao_original', v_sug,
                            'discordou', v_sug is not null and v_sug <> p_classe_final);
end;
$$;

--
-- Name: FUNCTION fn_registrar_classe_override(p_campo_extraido_id uuid, p_classe_final text, p_autor text, p_motivo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_classe_override(p_campo_extraido_id uuid, p_classe_final text, p_autor text, p_motivo text) IS 'A decisão humana sobre a classe contábil (Arquitetura do Sistema/2 Especificação/05, "registro de override humano"). Append-only: reclassificar é linha nova. Recusa RETORNADA e não exceção, senão o registro da própria tentativa seria desfeito. Autor é obrigatório: sem ele o sinal de calibração não tem de quem discordar.';

--
-- Name: fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, public.legibilidade, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_diagnostico(p_documento_id uuid, p_documento_versao_id uuid, p_entidade_nome text, p_tipo_confirma boolean, p_tipo_sugerido text, p_periodo_tipo text, p_periodo_referencia text, p_legibilidade public.legibilidade, p_nota_legibilidade text, p_resumo text, p_justificativa text, p_cnpj text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_id            uuid;
  v_entidade_id         uuid;
  v_tipo_atual          text;
  v_periodo_id          uuid;
  v_periodo_tipo_atual  text;
  v_periodo_ref_atual   text;
  v_entidade_atual_nome text;
  v_pendencia_id        uuid;
  v_entidade_criada     boolean := false;
  v_pendencia_grupo_id  uuid;
  v_outros_n            int;
  v_outros_nomes        text;
  v_exatas_ambiguidade_n    int;
  v_exata_ambiguidade_nome  text;
  v_pendencia_ambigua_resp_id uuid;
  v_ambigua_resp_desc       text;
  v_entidade_cnpj_pos_aprender text;
  v_entidade_id_balcao         uuid;
begin
  select caso_id, entidade_id, tipo_taxonomia, periodo_id
    into v_caso_id, v_entidade_id, v_tipo_atual, v_periodo_id
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  if v_periodo_id is not null then
    select tipo, referencia into v_periodo_tipo_atual, v_periodo_ref_atual from periodo where id = v_periodo_id;
  end if;

  -- ----- Entidade: preenche a lacuna se ainda vazia; senão só confere -----
  if p_entidade_nome is not null and length(trim(p_entidade_nome)) > 0 then
    if v_entidade_id is null then
      -- 0121: `fn_upsert_entidade` (0030), e não mais igualdade exata de texto.
      -- Era ela quem criava a segunda linha da MESMA empresa: o classificador
      -- não resolvia a entidade pelo nome do arquivo (6 dos 38 documentos do
      -- book), o diagnóstico lia a razão social completa do conteúdo
      -- ("CANASTRA INDÚSTRIA DE EMBALAGENS LTDA."), não achava igualdade exata
      -- com a que já existia ("Canastra Industria") e INSERIA outra.
      v_entidade_id := fn_upsert_entidade(v_caso_id, p_entidade_nome, p_cnpj);
      update documento set entidade_id = v_entidade_id where id = p_documento_id;
      v_entidade_criada := true;
    else
      select razao_social into v_entidade_atual_nome from entidade where id = v_entidade_id;

      select id into v_pendencia_id from pendencia
        where caso_id = v_caso_id and motivo = 'diagnostico:entidade:' || p_documento_id and estado <> 'resolvida'
        limit 1;
      select id into v_pendencia_grupo_id from pendencia
        where caso_id = v_caso_id and motivo = 'diagnostico:entidade_grupo:' || p_documento_id and estado <> 'resolvida'
        limit 1;

      -- 0162: O CASAMENTO CONTRA O BALCÃO AMBÍGUO NÃO CONFIRMA NADA — ele foi
      -- criado (0153) exatamente porque o nome dele já casava com MAIS DE UMA
      -- empresa do caso, então casa por construção com qualquer nome de
      -- conteúdo que aponte para as candidatas que o originaram. Medido no
      -- araucária (lote 7417, 03/09): o documento 009 ficou no balcão
      -- "Araucaria SPE" (pendência entidade_ambigua bloqueante contra
      -- BIOENERGIA × IMOBILIÁRIA), e o diagnóstico de conteúdo, lendo o
      -- PRÓPRIO documento, nomeou "ARAUCÁRIA IMOBILIÁRIA SPE LTDA." por
      -- extenso — que `fn_mesma_entidade` confirma contra o balcão (ele casa
      -- com as DUAS empresas do grupo, por definição), e o ramo abaixo (0121)
      -- tomava isso como CONFIRMAÇÃO, sem a pendência bloqueante da 0153 nunca
      -- ter sido tocada e sem a resposta deixar rastro em lugar nenhum.
      if fn_entidade_e_balcao_ambiguo(v_caso_id, v_entidade_id) then
        -- 0175: dentro do balcão ambíguo, o CNPJ decide ANTES do nome — a
        -- MESMA regra 1 da 0169 ("CNPJ é a identidade que o nome não é"),
        -- chegando pela porta que faltava. MEDIDO em produção (caso
        -- bf0246bb-c93b-4d08-a7df-5d356c9d6275, OMNIBEAUTY, teste 143): sem
        -- esta chamada, dois documentos da MESMA empresa em DOIS balcões
        -- diferentes nunca convergem — cada um só sabe perguntar ao nome, e
        -- o balcão nasce sem CNPJ. Ver o cabeçalho desta migration para os
        -- dois casos que `fn_entidade_aprender_cnpj` já sabe tratar: grava
        -- no próprio balcão quando é o primeiro a aprender este CNPJ no
        -- caso, ou FUNDE nele quando outra entidade (outro balcão, ou uma
        -- entidade de verdade) já tinha o mesmo CNPJ — usando o RETORNO,
        -- nunca `perform` (0174). 0176/0177: `fn_entidade_aprender_cnpj`
        -- agora RECUSA a fusão quando EXATAMENTE um dos dois lados é um
        -- balcão e o outro não — em QUALQUER direção (ver o CRÍTICO da
        -- 0177) — nesse caso ela devolve o mesmo `v_entidade_id`, sem CNPJ
        -- novo nenhum gravado.
        if p_cnpj is not null then
          -- 0177 (MÉDIO 2): a variável de atribuição é só desta chamada,
          -- para que o texto da chamada dentro do ramo do balcão fique
          -- ÚNICO no corpo — até aqui, a atribuição de v_entidade_id a
          -- partir do resultado do aprender era IDÊNTICA, char por char, à
          -- do ramo `else` (0172): MEDIDO por contagem (2 ocorrências)
          -- contra o corpo do estado da 0176. O marcador da sonda para
          -- `balcao_ambiguo_aprende_cnpj` provava a guarda do renomeio
          -- (MÉDIO 1 da 0176), não esta chamada — se uma reemissão futura
          -- removesse SÓ esta chamada, o requisito continuaria "presente"
          -- via o texto genérico do ramo `else`. Nenhuma mudança de
          -- COMPORTAMENTO: é troca de nome de variável. (Este comentário
          -- evita, de propósito, escrever a chamada antiga por extenso —
          -- fazer isso aqui inflaria a própria contagem que a correção
          -- existe para corrigir.)
          v_entidade_id_balcao := fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj);
          v_entidade_id := v_entidade_id_balcao;

          -- E O RENOMEIO VEM JUNTO, pela MESMA função do ramo `else` (0173) —
          -- não duplica lógica. Se a linha acima FUNDIU, `fn_entidade_aprender_cnpj`
          -- já chamou fn_entidade_talvez_renomear por dentro com o nome do
          -- balcão fundido; esta chamada cobre o caso SEM fusão, em que o
          -- nome lido do CONTEÚDO deste documento pode ser a variante mais
          -- completa para o balcão que acabou de aprender o CNPJ.
          --
          -- 0176 (MÉDIO 1 da revisão da 0175): só chama o renomeio quando o
          -- `aprender` ACIMA realmente confirmou ESTE p_cnpj NESTA entidade —
          -- nunca com o p_cnpj bruto. MEDIDO: uma entidade que já tinha OUTRO
          -- CNPJ gravado (aprender_cnpj devolve sem tocar em nada) ainda era
          -- renomeada com o evento citando um CNPJ ESTRANHO à entidade —
          -- entidade com cnpj real 11222333000181 "renomeada por CNPJ" com o
          -- evento dizendo {"cnpj": "36193378000104", ...}. O mesmo guarda
          -- cobre o refúgio do CRÍTICO da 0176/0177: se
          -- `fn_entidade_aprender_cnpj` recusou fundir (balcão não pode
          -- absorver quem não é balcão, em nenhuma direção), esta entidade
          -- não ficou com este CNPJ, e o `if` abaixo não deixa o renomeio
          -- rodar mesmo assim.
          select cnpj into v_entidade_cnpj_pos_aprender from entidade where id = v_entidade_id;
          if v_entidade_cnpj_pos_aprender is not null
             and fn_cnpj_canonico(v_entidade_cnpj_pos_aprender) = fn_cnpj_canonico(p_cnpj) then
            perform fn_entidade_talvez_renomear(v_caso_id, v_entidade_id, p_entidade_nome, v_entidade_cnpj_pos_aprender);
          end if;
        end if;

        -- 0176 (ALTO da revisão da 0175): o NOME pode ter mudado — o bloco
        -- acima pode ter FUNDIDO (`v_entidade_id` agora aponta para OUTRA
        -- linha, a sobrevivente) ou RENOMEADO a própria entidade.
        -- `v_entidade_atual_nome`, lido ANTES deste ramo (no topo da
        -- função), ficaria citando uma razão social que pode não existir
        -- MAIS no banco — a entidade fundida foi DELETADA — e é ela que a
        -- pendência `entidade_ambigua_respondida`, poucas linhas abaixo,
        -- usa para montar a descrição que o analista lê. MEDIDO contra o
        -- cenário de dois balcões convergindo
        -- (Supabase/test/balcao_ambiguo_e_cnpj.test.sql): a pendência do
        -- segundo balcão citava "OMNIBEAUTY DESENVOLVIMENTO E GESTAO" — o
        -- nome do balcão FUNDIDO, já apagado — atribuída ao balcão
        -- sobrevivente, que se chama "...GESTAO DE". Sintaxe `:=` (não
        -- `select into`), de propósito: o marcador de corpo da sonda para
        -- este requisito precisa de um trecho que só exista por causa DESTA
        -- correção.
        v_entidade_atual_nome := (select razao_social from entidade where id = v_entidade_id);

        -- SÓ TENTA RESOLVER PELO NOME SE O CNPJ NÃO RESOLVEU: se a entidade
        -- (que pode ter mudado de id na linha acima) AINDA é um balcão
        -- ambíguo — sem CNPJ para tentar, ou com CNPJ que só gravou no
        -- próprio balcão sem achar outra dona — o nome continua sendo o
        -- único sinal disponível, e a lógica abaixo é EXATAMENTE a de antes
        -- desta migration.
        if fn_entidade_e_balcao_ambiguo(v_caso_id, v_entidade_id) then
        -- O conteúdo pode ter respondido à própria pergunta: se o nome
        -- diagnosticado casa EXATO com exatamente UMA empresa já cadastrada
        -- neste caso (excluído o próprio balcão), é essa a resposta. NÃO
        -- decide sozinho — não move o documento, não funde — só a NOMEIA,
        -- para o humano confirmar em segundos em vez de abrir o PDF.
        select count(*) into v_exatas_ambiguidade_n
        from fn_entidades_candidatas(v_caso_id, p_entidade_nome) c
        where c.exata and c.entidade_id <> v_entidade_id;

        if v_exatas_ambiguidade_n = 1 then
          select c.razao_social into v_exata_ambiguidade_nome
          from fn_entidades_candidatas(v_caso_id, p_entidade_nome) c
          where c.exata and c.entidade_id <> v_entidade_id
          limit 1;

          select id into v_pendencia_ambigua_resp_id from pendencia
            where caso_id = v_caso_id
              and motivo = 'diagnostico:entidade_ambigua_respondida:' || p_documento_id
              and estado <> 'resolvida'
            limit 1;

          v_ambigua_resp_desc := format(
            'O nome do arquivo casou com MAIS DE UMA empresa deste mandato e não identificou '
            || 'nenhuma — por isso o documento foi registrado numa entidade própria ("%s"). O '
            || 'CONTEÚDO deste documento nomeia "%s", que é uma das empresas JÁ CADASTRADAS '
            || 'neste mandato — e nomeia só ela. Confirme pela revisão (fn_revisar_documento) se '
            || 'o documento é mesmo dela; se as duas linhas forem a mesma empresa, funda com '
            || 'fn_fundir_entidade.%s',
            coalesce(v_entidade_atual_nome, '(nenhuma)'), v_exata_ambiguidade_nome,
            case when p_justificativa is not null and length(trim(p_justificativa)) > 0
                 then ' Justificativa do diagnóstico: ' || p_justificativa else '' end);

          if v_pendencia_ambigua_resp_id is null then
            insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, entidade_id, motivo)
              values (v_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
                v_ambigua_resp_desc, p_documento_id, v_entidade_id,
                'diagnostico:entidade_ambigua_respondida:' || p_documento_id);
          else
            update pendencia set descricao = v_ambigua_resp_desc where id = v_pendencia_ambigua_resp_id;
          end if;
        end if;
        -- Zero, duas ou mais exatas: o conteúdo NÃO respondeu — silêncio aqui
        -- é honesto (regra 1 do CLAUDE.md: não fabricar ausência como dado).
        -- E, em QUALQUER dos casos acima, o casamento contra o balcão NUNCA
        -- resolve `diagnostico:entidade`/`diagnostico:entidade_grupo` — não
        -- tocar `v_pendencia_id`/`v_pendencia_grupo_id` aqui é o que deixa
        -- isso explícito: só o ramo `else` abaixo (comparação contra uma
        -- entidade de VERDADE) resolve essas duas pendências.
        end if;
      else
      -- 0121: divergência de ENTIDADE medida pela forma canônica, como o
      -- período já é desde a 0022. "Canastra Industria" e "CANASTRA INDÚSTRIA
      -- DE EMBALAGENS LTDA." são a mesma empresa, e `fn_mesma_entidade` já
      -- sabia disso.
      if fn_mesma_entidade(v_entidade_atual_nome, p_entidade_nome) then
        -- 0172: É AQUI QUE O CNPJ DO CONTEÚDO ENCONTRA A ENTIDADE, e não na
        -- chamada de `fn_upsert_entidade` acima — ela só roda quando o
        -- documento AINDA NÃO TEM entidade, e `fn_registrar_documento` sempre
        -- resolve uma antes. MEDIDO: com o parâmetro só chegando lá, o CNPJ
        -- entrava e morria; a entidade continuava com `cnpj` nulo depois do
        -- diagnóstico. Era conserto de sintoma, não de causa.
        --
        -- E É NESTE RAMO, não no de cima nem no `else`, por uma razão de
        -- segurança: aqui o nome lido do CONTEÚDO **confirma** a entidade em
        -- que o documento está registrado. Nos outros ramos a função está
        -- justamente em dúvida sobre qual é a empresa certa — gravar ali um
        -- CNPJ na entidade ERRADA seria pior que não gravar nenhum, porque
        -- pela regra 1 da 0169 esse CNPJ passaria a ATRAIR todo documento
        -- futuro da empresa de verdade para dentro da entidade errada, sem
        -- olhar nome. Divergência de entidade é pergunta para humano, e as
        -- pendências logo abaixo são a resposta certa para ela. 0176/0177:
        -- esta proteção agora vale também quando a "outra dona" do CNPJ é um
        -- balcão ambíguo — `fn_entidade_aprender_cnpj` recusa fundir esta
        -- entidade (confirmada) NELE, em qualquer direção (ver o CRÍTICO da
        -- 0177).
        --
        -- `fn_entidade_aprender_cnpj` (0169) nunca sobrescreve CNPJ já gravado
        -- e deixa rastro (`entidade_cnpj_aprendido`) — é a mesma função que o
        -- ramo exato de `fn_upsert_entidade` usa, pelo mesmo motivo.
        -- 0174: usa o RETORNO, não `perform`. Quando a outra entidade do
        -- mesmo caso já tinha este CNPJ, a função acima FUNDE esta entidade
        -- nela e devolve o id da SOBREVIVENTE — sem capturá-lo aqui,
        -- `v_entidade_id` ficaria apontando para uma linha deletada, e tanto o
        -- `fn_entidade_talvez_renomear` logo abaixo quanto o `entidade_id` no
        -- jsonb de retorno (fim da função) mentiriam.
        v_entidade_id := fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj);

        -- 0173: E O RENOMEIO VEM JUNTO, pelo mesmo caminho e pela mesma razão.
        -- A 0172 fez o CNPJ chegar aqui, mas só APRENDIDO — quem adota o nome
        -- mais completo era o bloco dentro de `fn_upsert_entidade`, que neste
        -- ramo não roda (o documento já tem entidade). O resultado medido era
        -- desequilibrado: identidade fiscal em 100% do lote e renomeio em ~50%
        -- — só nos documentos que passam pela classificação (19 de 38 no
        -- book-canastra). Para uma empresa cujo ÚNICO documento chega com o
        -- nome contaminado pelo endereço, o nome errado ficava no book até
        -- aparecer um segundo documento pelo outro caminho.
        --
        -- MESMO PADRÃO do MÉDIO 1 da 0176 (p_cnpj bruto, não o CNPJ real da
        -- entidade) existe AQUI TAMBÉM, e fica FORA do escopo desta fatia —
        -- ver o cabeçalho da 0176. Registrado para o
        -- MAPA_DE_EXECUCAO.md.
        --
        -- As três guardas da 0171 vão inteiras dentro da função (só entre
        -- truncamentos, nunca cria homônima, recusa com rastro), e sem CNPJ
        -- ela não renomeia — então este fio não toca nenhum documento que
        -- chegue sem identidade fiscal.
        perform fn_entidade_talvez_renomear(v_caso_id, v_entidade_id, p_entidade_nome, p_cnpj);

        if v_pendencia_id is not null then
          update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
            where id = v_pendencia_id;
        end if;
        if v_pendencia_grupo_id is not null then
          update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
            where id = v_pendencia_grupo_id;
        end if;
      else
        -- 0160: o nome que não casou com o registrado pode casar com OUTRA(S)
        -- empresa(s) já cadastrada(s) NESTE caso — nesse caso a função não sabe
        -- afirmar que o registro está errado. Excluída a própria entidade do
        -- documento, para não contar "casou consigo mesma" como candidata a
        -- outra empresa. Reaproveita `fn_entidades_candidatas` da 0153 em vez de
        -- duplicar a busca — e, ao contrário da 0153 (que ali resolve escolhendo
        -- SEM decidir, criando entidade nova), aqui `order by ... limit 1`
        -- escolheria no empate quando há mais de um candidato, que é exatamente
        -- o que a 0153 existe para não fazer: conta TODOS os candidatos, para a
        -- mensagem nomear todos, não só o primeiro por ordem alfabética.
        select count(*), string_agg(c.razao_social, ' × ' order by c.razao_social)
          into v_outros_n, v_outros_nomes
        from fn_entidades_candidatas(v_caso_id, p_entidade_nome) c
        where c.entidade_id <> v_entidade_id;

        if v_outros_n >= 1 then
          -- NÃO É AFIRMAÇÃO DE HIERARQUIA: `entidade.papel_no_grupo` é o único
          -- campo que registraria holding × subsidiária, e esta função não o
          -- consulta — não há como saber, só a partir do nome, qual é a relação
          -- entre as duas empresas, ou se há relação alguma. O que dá para
          -- afirmar sem inventar é só isto: as duas (ou mais) já são empresas
          -- cadastradas neste mandato, e o sistema não sabe qual delas é a
          -- certa para este documento — não decide quem está certo, só para de
          -- chamar de "incorreto" um registro que pode estar certo. A pendência
          -- de erro clássica, se estava aberta de uma rodada anterior, fecha —
          -- a resposta mudou de categoria (mas isso só acontece na PRÓXIMA
          -- passada de `fn_registrar_diagnostico` sobre o documento, não ao
          -- aplicar esta migration — ver `Supabase/README.md`).
          if v_pendencia_id is not null then
            update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
              where id = v_pendencia_id;
          end if;
          if v_pendencia_grupo_id is null then
            insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, entidade_id, motivo)
              values (v_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
                case when v_outros_n = 1 then
                  format('O documento está registrado em "%s", mas o diagnóstico de conteúdo aponta "%s" — nome '
                         || 'que também já é uma empresa CADASTRADA neste mandato ("%s"). As duas são empresas '
                         || 'cadastradas neste caso, e o sistema não sabe qual das duas é a certa para este '
                         || 'documento — não presume nenhuma. Confira pela revisão se ele pertence mesmo a "%s" '
                         || 'ou deveria estar em "%s", sem fundir: as duas continuam sendo empresas diferentes.',
                         coalesce(v_entidade_atual_nome, '(nenhuma)'), p_entidade_nome, v_outros_nomes,
                         coalesce(v_entidade_atual_nome, '(nenhuma)'), v_outros_nomes)
                else
                  format('O documento está registrado em "%s", mas o diagnóstico de conteúdo aponta "%s" — nome '
                         || 'que casa com MAIS DE UMA empresa já cadastrada neste mandato (%s). O sistema não '
                         || 'sabe qual delas é a certa para este documento — não presume nenhuma. Confira pela '
                         || 'revisão qual é a empresa certa, sem fundir: continuam sendo empresas diferentes.',
                         coalesce(v_entidade_atual_nome, '(nenhuma)'), p_entidade_nome, v_outros_nomes)
                end,
                p_documento_id, v_entidade_id, 'diagnostico:entidade_grupo:' || p_documento_id);
          end if;
        else
          -- DIVERGÊNCIA DE VERDADE: o nome diagnosticado não bate com NENHUMA
          -- empresa já cadastrada no caso — não há hierarquia a reconhecer, e a
          -- pendência clássica continua acusando exatamente como na 0121.
          if v_pendencia_grupo_id is not null then
            update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
              where id = v_pendencia_grupo_id;
          end if;
          if v_pendencia_id is null then
            insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
              values (v_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
                format('Diagnóstico de conteúdo sugere entidade "%s", mas o documento está registrado com "%s".',
                       p_entidade_nome, coalesce(v_entidade_atual_nome, '(nenhuma)')),
                p_documento_id, 'diagnostico:entidade:' || p_documento_id);
          end if;
        end if;
      end if;
      end if;
    end if;
  end if;

  -- ----- Tipo: confere contra o que já está registrado -----
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:tipo:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  -- 0142: exige divergência ACIONÁVEL. "Não confirmo" sozinho não basta —
  -- o modelo diz isso também quando reconhece o mesmo tipo com outro nome
  -- (doc 27 da v48: NOTAS_EXPL contra NOTAS_EXPL) ou quando não sabe o que o
  -- documento é ("?" contra "(nenhum)", doc 28). Nos dois casos a pendência
  -- pedia decisão sobre uma diferença que não existe.
  if (p_tipo_sugerido is not null and p_tipo_sugerido is distinct from v_tipo_atual)
     or (coalesce(p_tipo_confirma, true) = false
         and v_tipo_atual is not null
         and coalesce(p_tipo_sugerido, '') <> coalesce(v_tipo_atual, '')) then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'diagnostico', 'tipo_incorreto', 'importante', true,
          format('Diagnóstico de conteúdo sugere tipo "%s" (documento está registrado como "%s"). %s',
                 coalesce(p_tipo_sugerido, '?'), coalesce(v_tipo_atual, '(nenhum)'), coalesce(p_justificativa, '')),
          p_documento_id, 'diagnostico:tipo:' || p_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
      where id = v_pendencia_id;
  end if;

  -- ----- Período: confere contra o registrado, por FORMA CANÔNICA (0020) -----
  -- Só diverge quando os períodos são canonicamente distintos — notações
  -- diferentes do MESMO período não geram mais pendência falsa.
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:periodo:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  -- 0022: compara pelo CONJUNTO DE ANOS. "anual 2025" e "data-base 2025-12-31"
  -- são o MESMO exercício com granularidade diferente — não é divergência, é
  -- refinamento; acusar isso enchia a fila de revisão de pendência falsa.
  -- Divergência real (2024 × 2025) continua virando pendência.
  if p_periodo_referencia is not null
     and not fn_periodos_equivalentes(p_periodo_tipo, p_periodo_referencia,
                                      v_periodo_tipo_atual, v_periodo_ref_atual) then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'diagnostico', 'periodo_incorreto', 'importante', true,
          format('Diagnóstico de conteúdo sugere período "%s %s" (documento está registrado com "%s %s"). %s',
                 p_periodo_tipo, p_periodo_referencia, coalesce(v_periodo_tipo_atual, '?'), coalesce(v_periodo_ref_atual, '(nenhum)'),
                 coalesce(p_justificativa, '')),
          p_documento_id, 'diagnostico:periodo:' || p_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
      where id = v_pendencia_id;
  end if;

  -- ----- Legibilidade real do arquivo -----
  update documento_versao set legibilidade = coalesce(p_legibilidade, legibilidade), nota_legibilidade = p_nota_legibilidade
    where id = p_documento_versao_id;

  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:legibilidade:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  if p_legibilidade = 'ilegivel' then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'diagnostico', 'arquivo_ilegivel', 'importante', true,
          coalesce(p_nota_legibilidade, 'Arquivo sinalizado como ilegível pelo diagnóstico de conteúdo.'),
          p_documento_id, 'diagnostico:legibilidade:' || p_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
      where id = v_pendencia_id;
  end if;

  -- ----- Resumo (nunca apaga um resumo anterior com uma resposta vazia) -----
  update documento set resumo = coalesce(p_resumo, resumo) where id = p_documento_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:diagnostico', 'diagnostico_documento', 'documento:'||p_documento_id,
      jsonb_build_object(
        'entidade', p_entidade_nome, 'tipo_confirma', p_tipo_confirma, 'tipo_sugerido', p_tipo_sugerido,
        'periodo_tipo', p_periodo_tipo, 'periodo_referencia', p_periodo_referencia,
        'legibilidade', p_legibilidade, 'resumo', p_resumo, 'justificativa', p_justificativa));

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id, 'entidade_id', v_entidade_id,
    'entidade_criada', v_entidade_criada);
end;
$$;

--
-- Name: FUNCTION fn_registrar_diagnostico(p_documento_id uuid, p_documento_versao_id uuid, p_entidade_nome text, p_tipo_confirma boolean, p_tipo_sugerido text, p_periodo_tipo text, p_periodo_referencia text, p_legibilidade public.legibilidade, p_nota_legibilidade text, p_resumo text, p_justificativa text, p_cnpj text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_diagnostico(p_documento_id uuid, p_documento_versao_id uuid, p_entidade_nome text, p_tipo_confirma boolean, p_tipo_sugerido text, p_periodo_tipo text, p_periodo_referencia text, p_legibilidade public.legibilidade, p_nota_legibilidade text, p_resumo text, p_justificativa text, p_cnpj text) IS 'Registra o diagnóstico de conteúdo (E1/E2) e confere contra o que já está no banco — ver o histórico de 0121/0142/0160/0161/0162/0163 no comentário da 0163. 0172: recebe o CNPJ lido do CONTEÚDO e o aprende no ramo em que o nome CONFIRMA a entidade. 0173: no mesmo ramo, também chama fn_entidade_talvez_renomear. 0174: usa o RETORNO de fn_entidade_aprender_cnpj. 0175: o ramo do balcão ambíguo (0162) agora tenta o CNPJ ANTES do nome. 0176: o renomeio dentro do ramo do balcão só roda com o CNPJ que o aprender de fato confirmou NESTA entidade, e o nome usado pela pendência entidade_ambigua_respondida é RECONFERIDO depois do bloco do balcão. 0177: a chamada a fn_entidade_aprender_cnpj dentro do ramo do balcão usa uma variável local própria (v_entidade_id_balcao) — texto único, para o marcador da sonda de balcao_ambiguo_aprende_cnpj parar de casar também com a chamada IDÊNTICA do ramo `else`. Nenhuma mudança de comportamento.';

--
-- Name: fn_registrar_documento(uuid, text, text, text, text, numeric, text, public.origem_arquivo, text, text, boolean, text, public.legibilidade, numeric, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_documento(p_caso_id uuid, p_entidade_nome text, p_periodo_tipo text, p_periodo_ref text, p_tipo_taxonomia text, p_confianca numeric, p_fonte text, p_origem_arquivo public.origem_arquivo, p_arquivo_ref text, p_nome_original text, p_assinado boolean, p_hash text, p_legibilidade public.legibilidade, p_threshold numeric DEFAULT 0.7, p_justificativa text DEFAULT NULL::text, p_fingerprint_extracao text DEFAULT NULL::text, p_cnpj text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  -- 0127: o limiar da classificacao passa a vir do DIAL.
  v_auto_classif   boolean;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_documento_id uuid;
  v_versao_id   uuid;
  v_n_versao    int := 1;
  v_obrig obrigatoriedade;
  v_reaproveitou boolean := false;
  v_versao_reuso uuid;
  v_doc_reuso    uuid;
  v_n_reuso      int;
begin
  -- ---- REAPROVEITAMENTO DE EXTRAÇÃO: a primeira pergunta, e a mais barata ----
  -- Vem ANTES do upsert de entidade/período de propósito: se o arquivo já foi
  -- extraído com este mesmo prompt, nada precisa ser criado — nem versão, nem
  -- entidade, nem período. Sair daqui é o caminho de custo zero.
  if p_hash is not null and length(trim(p_hash)) > 0
     and p_fingerprint_extracao is not null and length(trim(p_fingerprint_extracao)) > 0 then
    select dv.id, dv.documento_id, dv.n_versao
      into v_versao_reuso, v_doc_reuso, v_n_reuso
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id
      and dv.hash = p_hash
      and dv.fingerprint_extracao = p_fingerprint_extracao
      -- TEM LINHA: extração que falhou não vale como extração feita (ver o
      -- cabeçalho). É o que mantém o reenvio como conserto possível.
      and exists (select 1 from campo_extraido ce where ce.documento_versao_id = dv.id)
    order by dv.n_versao desc
    limit 1;
  end if;

  if v_versao_reuso is not null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'documento_extracao_reaproveitada',
              'documento_versao:' || v_versao_reuso,
              jsonb_build_object('documento_id', v_doc_reuso, 'hash', p_hash,
                                 'fingerprint_extracao', p_fingerprint_extracao,
                                 'nome_original', p_nome_original));
    return jsonb_build_object(
      'documento_id', v_doc_reuso,
      'documento_versao_id', v_versao_reuso,
      'n_versao', v_n_reuso,
      'reaproveitou_documento', true,
      'reaproveitou_extracao', true
    );
  end if;

  -- ENTIDADE E PERÍODO PELA FORMA CANÔNICA (0030), e não por `lower()`. Esta é a
  -- parte que a primeira versão desta migration perdeu por copiar o corpo da
  -- 0026 em vez do corpo VIGENTE: o teste de canonicalização reprovou na hora
  -- ("as duas grafias da mesma empresa viram UMA entidade — achei 2"), que é
  -- exatamente o defeito que a 0030 tinha corrigido. Republicar função neste
  -- banco significa partir do corpo mais recente, nunca do da migration que a
  -- gente está lendo.
  v_entidade_id := fn_upsert_entidade(p_caso_id, p_entidade_nome, p_cnpj);
  v_periodo_id := fn_upsert_periodo(p_caso_id, p_periodo_tipo, p_periodo_ref);

  -- Já existe ESTE arquivo (mesmo hash) neste caso? Então é reextração/reenvio:
  -- versão nova sob o mesmo documento. Hash nulo nunca casa (ver 0026).
  if p_hash is not null and length(trim(p_hash)) > 0 then
    select dv.documento_id into v_documento_id
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id and dv.hash = p_hash
    order by dv.criada_em desc
    limit 1;
    v_reaproveitou := v_documento_id is not null;
  end if;

  if v_reaproveitou then
    select coalesce(max(n_versao), 0) + 1 into v_n_versao
      from documento_versao where documento_id = v_documento_id;
    -- A classificação da versão nova prevalece SOBRE A DO SISTEMA, nunca sobre a
    -- do humano: se alguém já revisou este documento na fila (`fonte='humano'`,
    -- `Supabase/migrations/0008`), a reextração não desfaz a decisão dele — é a
    -- anti-ancoragem de sempre (Arquitetura do Sistema/1 Visão e Doutrina/01), no sentido que importa: máquina não
    -- sobrepõe humano. Entidade/período seguem a mesma regra.
    update documento d set
      tipo_taxonomia = case when d.fonte = 'humano' then d.tipo_taxonomia else p_tipo_taxonomia end,
      entidade_id    = case when d.fonte = 'humano' then d.entidade_id else coalesce(v_entidade_id, d.entidade_id) end,
      periodo_id     = case when d.fonte = 'humano' then d.periodo_id else coalesce(v_periodo_id, d.periodo_id) end,
      confianca      = case when d.fonte = 'humano' then d.confianca else p_confianca end,
      fonte          = case when d.fonte = 'humano' then d.fonte else p_fonte end,
      justificativa  = case when d.fonte = 'humano' then d.justificativa else p_justificativa end,
      status         = case when d.fonte = 'humano' then d.status else 'em_validacao' end
    where d.id = v_documento_id;
  else
    insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, status, confianca, fonte, justificativa)
      values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia, 'em_validacao', p_confianca, p_fonte, p_justificativa)
      returning id into v_documento_id;
  end if;

  insert into documento_versao
    (documento_id, n_versao, origem_arquivo, arquivo_ref, nome_original, assinado, hash,
     legibilidade, fingerprint_extracao)
    values (v_documento_id, v_n_versao, coalesce(p_origem_arquivo,'supabase_storage'),
            p_arquivo_ref, p_nome_original, p_assinado, p_hash, p_legibilidade,
            p_fingerprint_extracao)
    returning id into v_versao_id;

  -- Checklist: só na PRIMEIRA vez. Reextração não é documento novo — inserir de
  -- novo daria dois itens "presente" para o mesmo documento e inflaria a
  -- completude com um arquivo só (a `unique` do checklist não cobre isso porque
  -- `documento_id` faz parte da linha).
  if p_tipo_taxonomia is not null and not v_reaproveitou then
    select obrigatoriedade into v_obrig from taxonomia_tipo_documento where codigo = p_tipo_taxonomia;
    insert into checklist_item_status
      (caso_id, entidade_id, periodo_id, tipo_taxonomia, obrigatoriedade, status, documento_id)
      values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia,
              coalesce(v_obrig,'complementar'), 'presente', v_documento_id);
  end if;

  -- Pendência de classificação incerta: idempotente por documento.
  --
  -- 0127: O LIMIAR SAI DO PARÂMETRO E PASSA A VIR DO DIAL. Até aqui ele era
  -- `p_threshold`, default 0.7 — e o dial de `classificacao_doc_checklist` dizia
  -- limiar 0,95, lido por ninguém. O sistema declarava 0,95 e aplicava 0,70.
  --
  -- O parâmetro fica como QUEDA, para banco que ainda não tem a linha do dial
  -- (a semeadura é da 0002). Não é cortesia: sem a queda, um banco antigo passaria
  -- a abrir pendência de classificação em TODO documento no instante em que esta
  -- migration entrasse, e o motivo seria invisível.
  v_auto_classif := case
    when exists (select 1 from estagio_autonomia
                  where estagio = 'classificacao_doc_checklist')
      then fn_dial_permite_auto('classificacao_doc_checklist', p_confianca)
    else coalesce(p_confianca, 0) >= p_threshold
  end;

  if p_tipo_taxonomia is null or not v_auto_classif then
    if not exists (
      select 1 from pendencia p
      where p.documento_id = v_documento_id
        and p.tipo = 'classificacao_pendente'
        and p.estado <> 'resolvida'
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
        values (p_caso_id, 'classificacao', 'classificacao_pendente', 'importante', true,
                -- 0127: a mensagem passa a dizer QUAL limiar reprovou. Sem isso, o
                -- analista lê "conf=0,62" e não sabe contra o que ela perdeu — e
                -- o limiar agora é dado, então pode ter mudado desde ontem.
                format('Classificação incerta (conf=%s, limiar do dial=%s, fonte=%s) para "%s". Motivo: %s',
                       coalesce(p_confianca,0),
                       coalesce((select ea.limiar_auto_clear::text from estagio_autonomia ea
                                  where ea.estagio = 'classificacao_doc_checklist'),
                                p_threshold::text || ' (queda: dial sem linha)'),
                       coalesce(p_fonte,'?'), coalesce(p_nome_original,'?'),
                       coalesce(nullif(trim(p_justificativa), ''), 'nenhuma justificativa fornecida')),
                v_documento_id);
    end if;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n',
            case when v_reaproveitou then 'documento_reextraido' else 'documento_registrado' end,
            'documento:'||v_documento_id,
            jsonb_build_object('tipo', p_tipo_taxonomia, 'confianca', p_confianca, 'fonte', p_fonte,
                               'justificativa', p_justificativa, 'n_versao', v_n_versao,
                               'hash', p_hash, 'fingerprint_extracao', p_fingerprint_extracao));

  return jsonb_build_object(
    'documento_id', v_documento_id,
    'documento_versao_id', v_versao_id,
    'n_versao', v_n_versao,
    'reaproveitou_documento', v_reaproveitou,
    'reaproveitou_extracao', false
  );
end;
$$;

--
-- Name: FUNCTION fn_registrar_documento(p_caso_id uuid, p_entidade_nome text, p_periodo_tipo text, p_periodo_ref text, p_tipo_taxonomia text, p_confianca numeric, p_fonte text, p_origem_arquivo public.origem_arquivo, p_arquivo_ref text, p_nome_original text, p_assinado boolean, p_hash text, p_legibilidade public.legibilidade, p_threshold numeric, p_justificativa text, p_fingerprint_extracao text, p_cnpj text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_documento(p_caso_id uuid, p_entidade_nome text, p_periodo_tipo text, p_periodo_ref text, p_tipo_taxonomia text, p_confianca numeric, p_fonte text, p_origem_arquivo public.origem_arquivo, p_arquivo_ref text, p_nome_original text, p_assinado boolean, p_hash text, p_legibilidade public.legibilidade, p_threshold numeric, p_justificativa text, p_fingerprint_extracao text, p_cnpj text) IS 'A porta de entrada do documento: acha ou cria caso/entidade/período, versiona e responde se já foi extraído (0118). 0170: recebe o CNPJ do emitente e o repassa a fn_upsert_entidade — sem este fio, as três regras de identidade da 0169 nunca disparam em produção e o sintoma é que nada melhora.';

--
-- Name: fn_registrar_expectativa_macro(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_expectativa_macro(p_exp jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare v_n int := 0;
begin
  if p_exp is null or jsonb_typeof(p_exp) <> 'array' then return 0; end if;

  with dados as (
    select
      (e->>'serie')::text        as serie,
      (e->>'ano_ref')::int       as ano_ref,
      (e->>'mediana')::numeric   as mediana,
      nullif(e->>'media','')::numeric as media,
      nullif(e->>'respondentes','')::int as respondentes,
      (e->>'coletado_em')::date  as coletado_em
    from jsonb_array_elements(p_exp) as e
    where e->>'serie' is not null and e->>'ano_ref' is not null
      and e->>'mediana' is not null and e->>'coletado_em' is not null
  ),
  validos as (select d.* from dados d join indice_macro_serie s on s.codigo = d.serie),
  gravado as (
    insert into indice_macro_expectativa (serie, ano_ref, mediana, media, respondentes, coletado_em)
    select serie, ano_ref, mediana, media, respondentes, coletado_em from validos
    on conflict (serie, ano_ref, coletado_em) do update
      set mediana = excluded.mediana, media = excluded.media,
          respondentes = excluded.respondentes
    returning 1
  )
  select count(*)::int into v_n from gravado;
  return coalesce(v_n, 0);
end;
$$;

--
-- Name: fn_registrar_falha_execucao(uuid, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_falha_execucao(p_caso_id uuid, p_caso_nome text, p_etapa text, p_mensagem text, p_detalhe jsonb DEFAULT NULL::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_id uuid;
begin
  insert into execucao_falha (caso_id, caso_nome, etapa, mensagem, detalhe)
    values (p_caso_id, nullif(trim(coalesce(p_caso_nome, '')), ''),
            coalesce(nullif(trim(p_etapa), ''), 'desconhecida'),
            coalesce(nullif(trim(p_mensagem), ''), 'Falha sem mensagem.'),
            p_detalhe)
    returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'falha_execucao',
            coalesce('caso:' || p_caso_id::text, 'caso_nome:' || coalesce(p_caso_nome, '?')),
            jsonb_build_object('etapa', p_etapa, 'mensagem', p_mensagem, 'detalhe', p_detalhe));

  return jsonb_build_object('falha_id', v_id, 'registrada', true);
end;
$$;

--
-- Name: FUNCTION fn_registrar_falha_execucao(p_caso_id uuid, p_caso_nome text, p_etapa text, p_mensagem text, p_detalhe jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_falha_execucao(p_caso_id uuid, p_caso_nome text, p_etapa text, p_mensagem text, p_detalhe jsonb) IS 'Registra falha do pipeline para a TELA mostrar (e para a trilha guardar). Aceita caso_id nulo: a falha pode acontecer antes de o caso existir, e falha órfã é falha invisível.';

--
-- Name: fn_registrar_fatos(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_fatos(p_documento_versao_id uuid, p_fatos jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_gravados  int := 0;
  v_sem_prova int := 0;
  v_tipo_ruim int := 0;
  v_pag_ruim  int := 0;
  v_erro      text := null;
  v_estado    text := null;
begin
  if p_documento_versao_id is null then
    return jsonb_build_object('erro', 'documento_versao_id nulo');
  end if;

  -- Sem chave `fatos` na resposta (workflow antigo, ou resposta que falhou) NÃO
  -- é o mesmo que "este documento não tem fato nenhum". Apagar os fatos de uma
  -- versão porque a chave veio ausente destruiria trilha por causa de um
  -- workflow desatualizado — o mesmo modo de falha do `Gravar Campos` que
  -- desligou a reconciliação por onze dias. E NÃO marca como avaliada: não foi.
  if p_fatos is null or jsonb_typeof(p_fatos) <> 'array' then
    return jsonb_build_object('gravados', 0, 'sem_prova', 0, 'tipo_desconhecido', 0,
                              'nota', 'sem lista de fatos na resposta — nada foi tocado');
  end if;

  -- 0149 (2)(3): O BLOCO PROTEGIDO.
  --
  -- Esta função roda na MESMA query que `fn_registrar_diagnostico`. Qualquer
  -- exceção aqui aborta a query e o documento perde o DIAGNÓSTICO — um número
  -- de página alucinado custando o estágio inteiro. O `exception` transforma
  -- isso em recusa DECLARADA no retorno, e o retorno é uma coluna da query, que
  -- aparece na execução do n8n.
  --
  -- Declarada, e não engolida: a diferença é o campo `erro` abaixo. Recusa que
  -- não se conta vira ausência, e ausência parece "este documento não disse
  -- nada" — o estado exato que este canal existe para acabar.
  --
  -- O bloco cobre o DELETE junto com o INSERT de propósito: se o insert falhar,
  -- o savepoint desfaz o delete também, e a versão fica com os fatos que já
  -- tinha em vez de ficar sem nenhum.
  begin
    delete from documento_fato where documento_versao_id = p_documento_versao_id;

    insert into documento_fato (documento_versao_id, tipo, trecho, pagina, leitura)
    select p_documento_versao_id,
           f->>'tipo',
           btrim(f->>'trecho'),
           -- 0149 (2): página fora do plausível vira NULL em vez de estourar.
           -- O teste é feito em `numeric`, que aguenta o absurdo; só depois
           -- vira `int`. Página zero ou negativa também não existe.
           case when jsonb_typeof(f->'pagina') = 'number'
                 and (f->>'pagina')::numeric between 1 and 100000
                then (f->>'pagina')::int end,
           nullif(btrim(coalesce(f->>'leitura', '')), '')
      from jsonb_array_elements(p_fatos) f
     where length(btrim(coalesce(f->>'trecho', ''))) >= 20
       and exists (select 1 from fato_tipo_catalogo c where c.tipo = f->>'tipo');
    get diagnostics v_gravados = row_count;
  exception when others then
    v_erro   := sqlerrm;
    v_estado := sqlstate;
    v_gravados := 0;
  end;

  select count(*)::int into v_sem_prova
    from jsonb_array_elements(p_fatos) f
   where length(btrim(coalesce(f->>'trecho', ''))) < 20;

  select count(*)::int into v_tipo_ruim
    from jsonb_array_elements(p_fatos) f
   where length(btrim(coalesce(f->>'trecho', ''))) >= 20
     and not exists (select 1 from fato_tipo_catalogo c where c.tipo = f->>'tipo');

  -- A página descartada é CONTADA à parte: o fato entra (o trecho é a
  -- evidência, não a página), mas quem confere merece saber que o número não
  -- era utilizável em vez de achar que o documento não tinha página.
  select count(*)::int into v_pag_ruim
    from jsonb_array_elements(p_fatos) f
   where jsonb_typeof(f->'pagina') = 'number'
     and (f->>'pagina')::numeric not between 1 and 100000;

  -- 0149 (4): a versão foi LIDA. Vale mesmo com zero fatos gravados — é
  -- exatamente esse caso que a coluna existe para registrar. Não vale quando
  -- houve erro: aí a leitura não chegou ao fim.
  if v_erro is null then
    update documento_versao set fatos_avaliados_em = now()
     where id = p_documento_versao_id;
  end if;

  return jsonb_build_object('gravados', v_gravados,
                            'sem_prova', v_sem_prova,
                            'tipo_desconhecido', v_tipo_ruim,
                            'pagina_descartada', v_pag_ruim,
                            'erro', v_erro,
                            'sqlstate', v_estado);
end;
$$;

--
-- Name: FUNCTION fn_registrar_fatos(p_documento_versao_id uuid, p_fatos jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_fatos(p_documento_versao_id uuid, p_fatos jsonb) IS 'Grava os fatos materiais de uma versão, substituindo os anteriores dela, e marca a versão como avaliada. Recusa entrada sem trecho literal e tipo fora do catálogo, e CONTA cada recusa no retorno. Desde a 0149 NÃO levanta exceção: ela roda na mesma query do diagnóstico, e uma página absurda derrubava o registro do diagnóstico junto — o erro passa a voltar declarado no retorno.';

--
-- Name: fn_registrar_indice_macro(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_indice_macro(p_obs jsonb) RETURNS TABLE(n_inseridas integer, n_atualizadas integer)
    LANGUAGE plpgsql
    AS $$
declare
  v_ins int := 0;
  v_upd int := 0;
begin
  if p_obs is null or jsonb_typeof(p_obs) <> 'array' then
    return query select 0, 0;
    return;
  end if;

  with dados as (
    select
      (o->>'serie')::text                        as serie,
      (o->>'fonte')::text                        as fonte,
      (o->>'data_ref')::date                     as data_ref,
      (o->>'valor')::numeric                     as valor
    from jsonb_array_elements(p_obs) as o
    where o->>'serie' is not null
      and o->>'data_ref' is not null
      and o->>'valor' is not null
  ),
  -- Série desconhecida é IGNORADA de propósito: um código novo tem de passar
  -- por migration (o catálogo é a fonte da verdade), não entrar pela ingestão.
  validos as (
    select d.* from dados d join indice_macro_serie s on s.codigo = d.serie
  ),
  gravado as (
    insert into indice_macro_obs (serie, fonte, data_ref, valor)
    select serie, fonte, data_ref, valor from validos
    on conflict (serie, fonte, data_ref) do update
      set valor = excluded.valor, coletado_em = now()
      where indice_macro_obs.valor is distinct from excluded.valor
    returning (xmax = 0) as inserida
  )
  select
    count(*) filter (where inserida)::int,
    count(*) filter (where not inserida)::int
  into v_ins, v_upd
  from gravado;

  return query select coalesce(v_ins, 0), coalesce(v_upd, 0);
end;
$$;

--
-- Name: fn_registrar_pergunta_acao(uuid, text, text, text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_pergunta_acao(p_caso_id uuid, p_codigo text, p_acao text, p_texto text, p_autor text, p_entidade_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_id uuid;
begin
  if p_acao not in ('enviada', 'descartada') then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Ação "%s" não existe: as ações são enviada e descartada.', p_acao));
  end if;
  if not exists (select 1 from pergunta_catalogo pc where pc.codigo = p_codigo and pc.ativo) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A pergunta "%s" não existe no catálogo (ou está inativa).', p_codigo));
  end if;
  if p_acao = 'enviada' and (p_texto is null or length(trim(p_texto)) = 0) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Enviar exige o TEXTO enviado: o template pode mudar depois, e a trilha '
        || 'precisa dizer O QUE foi perguntado ao cliente, não só que se perguntou.');
  end if;

  insert into caso_pergunta (caso_id, pergunta_codigo, entidade_id, acao, texto_enviado, autor)
    values (p_caso_id, p_codigo, p_entidade_id, p_acao,
            case when p_acao = 'enviada' then p_texto end, p_autor)
    returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values (p_autor, 'pergunta_' || p_acao, 'caso:' || p_caso_id,
            jsonb_build_object('pergunta_codigo', p_codigo, 'caso_pergunta_id', v_id,
                               'entidade_id', p_entidade_id));

  return jsonb_build_object('caso_pergunta_id', v_id, 'pergunta_codigo', p_codigo, 'acao', p_acao);
end;
$$;

--
-- Name: FUNCTION fn_registrar_pergunta_acao(p_caso_id uuid, p_codigo text, p_acao text, p_texto text, p_autor text, p_entidade_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_pergunta_acao(p_caso_id uuid, p_codigo text, p_acao text, p_texto text, p_autor text, p_entidade_id uuid) IS 'Registra a ação HUMANA sobre uma pergunta sugerida (0120). Enviada exige o texto renderizado (congelado na linha). Recusa em jsonb, nunca exceção — o rastro fica. Append-only: reenviar é linha nova.';

--
-- Name: fn_registrar_reconciliacao(uuid, uuid, uuid, text, text, uuid, jsonb, jsonb, text, numeric, numeric, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_reconciliacao(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text, p_classe text, p_documento_id uuid, p_fonte_a jsonb, p_fonte_b jsonb, p_resultado text, p_divergencia_abs numeric, p_divergencia_pct numeric, p_materialidade jsonb, p_descricao text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_reconciliacao_id uuid;
  v_pendencia_id     uuid;
  v_motivo           text := 'reconciliacao:' || p_tipo;
  -- 0186: O CONTRATO — todo motivo que o achatamento reconhece como "a
  -- checagem não concluiu". `resultado` sai `precondicao_nao_satisfeita` para
  -- QUALQUER um destes; o valor ORIGINAL vai para `motivo_precondicao` (ver
  -- abaixo). Desde a 0188 os cinco têm emissor.
  v_motivos_precondicao text[] := array[
    'documento_ausente', 'precondicao_nao_satisfeita',
    'linha_nao_localizada', 'unidade_divergente', 'sem_periodo_par'
  ];
  -- CORRIGIDO após revisão independente (achado mais grave: um p_resultado
  -- fora do vocabulário virava 'a checagem concluiu' — precondicoes_ok =
  -- TRUE, afirmação positiva e FALSA, medido passando 'linha_nao_localizado',
  -- uma letra fora do contrato). Todo valor que QUALQUER `fn_reconciliar_*`
  -- hoje realmente emite (grep em todas as migrations) mais os três
  -- reservados do CONTRATO acima — nada além disso é reconhecido.
  v_vocabulario_resultado text[] := array['ok', 'divergente', 'divergencia', 'zona_cinzenta']
                                       || v_motivos_precondicao;
  -- 'documento_ausente' é um resultado NOSSO, para decidir a pendência; no log
  -- ele é gravado como pré-condição não satisfeita (é o que ele é).
  v_res_log          text := case when p_resultado = any(v_motivos_precondicao)
                                  then 'precondicao_nao_satisfeita' else p_resultado end;
  -- motivo_precondicao: o valor ORIGINAL, antes do achatamento acima — NULL
  -- quando a checagem concluiu (v_res_log não é 'precondicao_nao_satisfeita').
  -- Quando p_resultado já chega como 'precondicao_nao_satisfeita' (a função de
  -- checagem não detalhou o motivo), grava esse mesmo valor: é honesto — "sem
  -- motivo específico" é informação, não lacuna.
  v_motivo_precondicao text := case when v_res_log = 'precondicao_nao_satisfeita'
                                     then p_resultado else null end;
  -- 0188: O QUE A FUNÇÃO DEVOLVE em `resultado`. Os despachantes (0152)
  -- decidem se tentam o PRÓXIMO período por
  -- `exit when v_res->>'resultado' <> 'precondicao_nao_satisfeita'`. Até a
  -- 0187 isso era o p_resultado cru, e só dois valores de precondição
  -- existiam: 'documento_ausente' (para o laço — falta a contraparte, outro
  -- período não a cria) e o genérico (segue o laço). Os três motivos da 0188
  -- são refinamentos do GENÉRICO, então devolvem o genérico: o laço continua
  -- exatamente como antes. 'documento_ausente' continua saindo cru.
  v_res_retorno      text := case when p_resultado in ('linha_nao_localizada',
                                                       'unidade_divergente',
                                                       'sem_periodo_par')
                                  then 'precondicao_nao_satisfeita' else p_resultado end;
  -- 0127: a decisão passa para o corpo, porque agora ela depende do DIAL da
  -- classe — e o dial não se lê no declare sem esconder a regra.
  --
  -- 0186: ESTA LINHA NÃO MUDA. `documento_ausente` continua sendo o ÚNICO
  -- motivo de precondição que NÃO abre pendência — é cobrança do checklist do
  -- Kit Básico, não achado de revisão (0023, reafirmado pela 0127). Qualquer
  -- motivo novo do array acima que não seja 'documento_ausente' cai do lado
  -- de ABRE pendência por esta mesma linha, sem precisar tocá-la: documento
  -- presente e algo não localizado é sempre achado acionável, mesmo quando o
  -- motivo específico ainda não existe (default seguro).
  v_divergente       boolean := p_resultado not in ('ok', 'documento_ausente');
  v_abre_pendencia   boolean;
  v_estagio_dial     text;
  v_influencia       boolean;
  -- 0192: o período que a pendência JÁ CARREGA (pode ser diferente de
  -- p_periodo_id — a busca acima acha por compatibilidade, não igualdade), e
  -- se, NA MESMA TRANSAÇÃO, outra checagem do mesmo caso/tipo/entidade já
  -- CONCLUIU divergente para um período compatível com ele.
  v_pendencia_periodo_id    uuid;
  v_divergencia_concorrente boolean := false;
  -- 0192 (terceira correção da guarda): o período da CHAVE que originou esta chamada — o que o
  -- laço de fn_reconciliar_caso / fn_reconciliar_chaves_do_documento deixou em `oria.periodo_chave`.
  -- Chamada avulsa (sem laço, como a `fn_reconciliar_arvore` e os testes) é a sua própria chave.
  v_periodo_chave_id        uuid := coalesce(nullif(current_setting('oria.periodo_chave', true), '')::uuid,
                                             p_periodo_id);
  -- 0192 (achado 5): os tipos cuja checagem é POR DOCUMENTO — a pendência e o estado
  -- vigente são do documento, não da chave (caso, entidade, período). Hoje só `secao_fecha`
  -- (fn_reconciliar_arvore, 0133/0190). Tipo novo por documento entra AQUI e na sonda.
  c_tipos_por_documento constant text[] := array['secao_fecha'];
  v_por_documento boolean := p_tipo = any(c_tipos_por_documento);
begin
  -- 0186 (achado 1 da revisão): p_resultado FORA do vocabulário conhecido
  -- REPROVA ALTO — não vira 'a checagem concluiu' por acidente de digitação.
  -- `raise` em vez de `check constraint` na coluna `resultado`: a tabela tem
  -- histórico com valores legados (ok, divergente, divergencia, zona_cinzenta,
  -- precondicao_nao_satisfeita) e um check retroativo recusaria linha antiga
  -- ou faria o `alter table` falhar — o raise protege só a ESCRITA daqui pra
  -- frente, sem tocar no que já está gravado.
  if not (p_resultado = any(v_vocabulario_resultado)) then
    raise exception 'fn_registrar_reconciliacao: p_resultado=% fora do vocabulario conhecido (%)',
      p_resultado, array_to_string(v_vocabulario_resultado, ', ');
  end if;

  -- 0127: O DIAL DA CLASSE DECIDE SE O ACHADO CHEGA À FILA DE ALGUÉM.
  --
  -- `reconciliacao_classe_bc` declarava N0 — "roda, registra a saída, mas NÃO
  -- influencia decisão" (Arquitetura do Sistema/1 Visão e Doutrina/01) — e abria pendência: as checagens B passam 'B'
  -- para cá e esta função nunca olhou a classe. Pendência entra na fila do painel
  -- e é contada na avaliação do Portão 2; isso é influenciar. O comportamento era
  -- N1, que é o teto dela — não era inseguro, era MAL DECLARADO.
  --
  -- Note que o registro em `reconciliacao` acontece SEMPRE, inclusive em N0: "roda
  -- e registra" é a primeira metade da definição de sombra, e é ela que permite
  -- medir um estágio antes de confiar nele.
  v_estagio_dial := case when upper(coalesce(p_classe, 'A')) = 'A'
                         then 'reconciliacao_classe_a'
                         else 'reconciliacao_classe_bc' end;
  v_influencia := fn_dial_influencia(v_estagio_dial);
  v_abre_pendencia := v_divergente and v_influencia;

  insert into reconciliacao
    (caso_id, entidade_id, periodo_id, tipo, classe, fonte_a, fonte_b,
     precondicoes_ok, resultado, motivo_precondicao, divergencia_abs, divergencia_pct, materialidade,
     documento_id, descricao, periodo_chave_id)
  values (
    p_caso_id, p_entidade_id, p_periodo_id, p_tipo, p_classe, p_fonte_a, p_fonte_b,
    v_res_log <> 'precondicao_nao_satisfeita', v_res_log, v_motivo_precondicao,
    p_divergencia_abs, p_divergencia_pct, p_materialidade,
    -- 0192 (achados 4/5/6): o documento que a checagem recebeu e o texto que ela deu, SEMPRE.
    p_documento_id, p_descricao,
    -- 0192 (guarda por CHAVE): o período da chave que originou a chamada, não o que o laço desceu.
    v_periodo_chave_id
  )
  returning id into v_reconciliacao_id;

  select id, periodo_id into v_pendencia_id, v_pendencia_periodo_id from pendencia
  where caso_id = p_caso_id and motivo = v_motivo
    and coalesce(entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
    -- Período COMPATÍVEL, não igual: a mesma checagem chega por dois documentos
    -- com granularidade diferente (DRE "multi 24,25" × Faturamento "L24M") e sem
    -- isso o mesmo achado abriria duas pendências.
    and (periodo_id is not distinct from p_periodo_id
         or fn_periodos_compativeis(periodo_id, p_periodo_id))
    -- 0192 (achado 5): tipo POR DOCUMENTO só casa a pendência do PRÓPRIO documento.
    and (not v_por_documento or documento_id is not distinct from p_documento_id)
    and estado <> 'resolvida'
  order by criada_em
  limit 1;

  -- 0192: O OK (OU A PRÉ-CONDIÇÃO) QUE MATAVA A DIVERGÊNCIA IRMÃ — ESTADO VIGENTE POR CHAVE.
  -- Duas checagens do mesmo tipo/entidade com períodos COMPATÍVEIS (Balanço "multi 24,25" ×
  -- "anual 12M25", {2024,2025} ∩ {2025} ≠ ∅) caem na MESMA pendência (busca acima, desde a
  -- 0023), e sem guarda SÓ A ORDEM de visita decidia se o `ok` de uma RESOLVIA a divergência da
  -- outra: dentro da rodada (medido em produção, 25/09/2026: v33/v35, `caixa_bp_fluxo`,
  -- 4.340.000 criada e resolvida no mesmo instante) e ENTRE rodadas.
  -- A guarda raciocina por CHAVE (o período do documento que o laço visita), não pelo período
  -- em que o resultado FICOU gravado: o laço desce a períodos compatíveis de outras entidades
  -- enquanto der pré-condição, e o resultado conclusivo fica num período sem documento da
  -- entidade (332 estados vigentes assim em produção, 30/09/2026). Duas versões que olhavam o
  -- período gravado (db6a258, 0202b8f) descartavam exatamente esse estado e resolviam.
  -- Bloqueia se:
  --   (a) alguma CHAVE VIVA (há documento do caso com `periodo_id` = a chave, da entidade quando
  --       ela não é nula) tem como ÚLTIMO registro (`periodo_chave_id` = a chave; `criado_em desc`,
  --       `cmin` desempata dentro da transação) um resultado divergente, gravado num período
  --       igual ou compatível com o da pendência. Chave sem documento (reclassificada, NULL) não
  --       prende; linha anterior à 0192 (sem `periodo_chave_id`) não bloqueia — teto declarado;
  --   (b) OU alguma linha DESTA transação (`criado_em = now()`), de outro período que o desta
  --       chamada, é divergente e compatível — a guarda original da mesma rodada, que vale
  --       mesmo sem documento na chave.
  -- Tipo POR DOCUMENTO (secao_fecha) não roda a guarda: o casamento por `documento_id`
  -- (acima) já isola a pendência do próprio documento.
  if v_pendencia_id is not null and not v_por_documento then
    select exists (
      select 1 from (
        select distinct on (r.periodo_chave_id) r.periodo_id, r.resultado
        from reconciliacao r
        where r.caso_id = p_caso_id and r.tipo = p_tipo
          and coalesce(r.entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
            = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
          and r.periodo_chave_id is not null
          and exists (
            select 1 from documento d
            where d.caso_id = p_caso_id
              and (p_entidade_id is null or d.entidade_id = p_entidade_id)
              and d.periodo_id = r.periodo_chave_id)
        order by r.periodo_chave_id, r.criado_em desc, r.cmin::text::int desc
      ) ultimo_por_chave
      where ultimo_por_chave.resultado in ('divergente', 'divergencia', 'zona_cinzenta')
        and (ultimo_por_chave.periodo_id is not distinct from v_pendencia_periodo_id
             or fn_periodos_compativeis(ultimo_por_chave.periodo_id, v_pendencia_periodo_id))
    ) or exists (
      select 1 from (
        select distinct on (r.periodo_id) r.periodo_id, r.resultado
        from reconciliacao r
        where r.caso_id = p_caso_id and r.tipo = p_tipo
          and coalesce(r.entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
            = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
          and r.periodo_id is distinct from p_periodo_id
          and r.criado_em = now()
        order by r.periodo_id, r.criado_em desc, r.cmin::text::int desc
      ) ultimo_na_rodada
      where ultimo_na_rodada.resultado in ('divergente', 'divergencia', 'zona_cinzenta')
        and (ultimo_na_rodada.periodo_id is not distinct from v_pendencia_periodo_id
             or fn_periodos_compativeis(ultimo_na_rodada.periodo_id, v_pendencia_periodo_id))
    ) into v_divergencia_concorrente;
  end if;

  if v_abre_pendencia then
    if v_pendencia_id is null then
      insert into pendencia
        (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao,
         documento_id, entidade_id, periodo_id, motivo)
      values (
        p_caso_id, 'reconciliacao',
        case when v_res_log = 'precondicao_nao_satisfeita' then 'precondicao_nao_satisfeita'
             else 'divergencia_reconciliacao' end::pendencia_tipo,
        'importante', true, p_descricao, p_documento_id, p_entidade_id, p_periodo_id, v_motivo
      )
      returning id into v_pendencia_id;
    elsif v_res_log = 'precondicao_nao_satisfeita' and v_divergencia_concorrente then
      -- 0192: este achado é PRÉ-CONDIÇÃO, e o ESTADO VIGENTE de um período
      -- IRMÃO (chave viva, ou linha desta rodada) compatível é divergente — não troca a descrição
      -- da divergência pela de "não especificado"/checklist. A pendência
      -- continua com o texto e o `tipo` da divergência.
      null;
    else
      update pendencia set descricao = p_descricao where id = v_pendencia_id;
    end if;
  elsif v_divergente and not v_influencia then
    -- 0127: SOMBRA COM DIVERGÊNCIA PRESENTE — e este ramo existe para não mentir.
    --
    -- Sem ele, este caso cairia no `elsif` de baixo e a pendência aberta seria
    -- marcada "resolvida por sistema:reconciliacao". Mas o sintoma NÃO sumiu: o
    -- estágio foi silenciado. Resolver aqui escreveria na trilha que o problema
    -- acabou, quando o que acabou foi o direito daquele estágio de falar — e a
    -- trilha é append-only justamente para não permitir esse tipo de reescrita.
    --
    -- Então: registra em sombra, e deixa em paz a pendência que um humano já pode
    -- estar tratando.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:reconciliacao', 'reconciliacao_em_sombra',
              'reconciliacao:' || v_reconciliacao_id,
              jsonb_build_object('estagio', v_estagio_dial, 'classe', p_classe,
                                 'tipo', p_tipo, 'resultado', p_resultado,
                                 'divergencia_abs', p_divergencia_abs,
                                 'pendencia_preexistente', v_pendencia_id,
                                 'porque', 'estagio em N0: registra e nao abre pendencia (Arquitetura do Sistema/1 Visão e Doutrina/01). '
                                           'Pendencia anterior, se existe, NAO foi resolvida: o '
                                           'sintoma nao sumiu, o estagio foi silenciado.'));

  elsif v_pendencia_id is not null then
    if v_divergencia_concorrente then
      -- 0192: este achado CONCLUIU (ok/documento_ausente), mas o estado VIGENTE de
      -- uma chave IRMÃ (desta ou de rodada anterior) ainda é divergente num período compatível — não
      -- resolve. O `ok` de um período não apaga a divergência de outro.
      null;
    else
      -- Sumiu o sintoma (reextração corrigiu, ou a pendência era falsa e a regra
      -- nova não a emite mais): fecha. Não escreve número nenhum em base viva.
      update pendencia set estado = 'resolvida', resolvida_em = now(),
             resolvida_por = 'sistema:reconciliacao'
      where id = v_pendencia_id;
      v_pendencia_id := null;
    end if;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:reconciliacao', 'reconciliacao_' || p_tipo,
            'reconciliacao:' || v_reconciliacao_id,
            jsonb_build_object('resultado', p_resultado, 'divergencia_abs', p_divergencia_abs));

  return jsonb_build_object(
    'reconciliacao_id', v_reconciliacao_id, 'tipo', p_tipo,
    'resultado', v_res_retorno, 'motivo_precondicao', v_motivo_precondicao,
    'pendencia_id', v_pendencia_id
  );
end;
$$;

--
-- Name: FUNCTION fn_registrar_reconciliacao(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text, p_classe text, p_documento_id uuid, p_fonte_a jsonb, p_fonte_b jsonb, p_resultado text, p_divergencia_abs numeric, p_divergencia_pct numeric, p_materialidade jsonb, p_descricao text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_reconciliacao(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text, p_classe text, p_documento_id uuid, p_fonte_a jsonb, p_fonte_b jsonb, p_resultado text, p_divergencia_abs numeric, p_divergencia_pct numeric, p_materialidade jsonb, p_descricao text) IS 'Registro unificado de reconciliação (0023), motivo fino por pré-condição (0186/0188). 0192: a pendência só resolve (ou troca a descrição por uma de pré-condição) se nenhuma CHAVE viva (período de documento) tem como último registro uma divergência em período compatível, em qualquer rodada; tipo por documento (secao_fecha) casa a pendência e o estado por documento_id; grava documento_id, descricao e periodo_chave_id em toda linha de reconciliacao.';

--
-- Name: fn_registrar_reconciliacao_b(uuid, uuid, uuid, text, uuid, jsonb, jsonb, text, numeric, numeric, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_reconciliacao_b(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text, p_documento_id uuid, p_fonte_a jsonb, p_fonte_b jsonb, p_resultado text, p_divergencia_abs numeric, p_divergencia_pct numeric, p_materialidade jsonb, p_descricao text) RETURNS jsonb
    LANGUAGE sql
    AS $$
  select fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id, p_tipo, 'B',
    p_documento_id, p_fonte_a, p_fonte_b, p_resultado, p_divergencia_abs,
    p_divergencia_pct, p_materialidade, p_descricao);
$$;

--
-- Name: fn_registrar_transcricao_humana(uuid, jsonb, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_transcricao_humana(p_documento_id uuid, p_linhas jsonb, p_autor text, p_motivo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
declare
  v_caso_id     uuid;
  v_ref         text;
  v_nome        text;
  v_origem      origem_arquivo;
  v_hash        text;
  v_n_versao    int;
  v_versao_id   uuid;
  v_item        jsonb;
  v_valor       numeric;
  v_n           int := 0;
  v_pendencia   uuid;
  v_autor       text := nullif(trim(coalesce(p_autor, '')), '');
begin
  if v_autor is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Transcrição sem autor não é transcrição. O número passa a valer como fato '
                       'na base de modelagem, e a única coisa que o sustenta é quem o digitou — '
                       'não há guarda de máquina para isso, por desenho.');
  end if;

  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Nenhuma linha para transcrever. Gravar uma versão vazia criaria um documento '
                       'que parece transcrito e não tem número nenhum — o pior dos dois estados.');
  end if;

  select d.caso_id into v_caso_id from documento d where d.id = p_documento_id;
  if v_caso_id is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Documento %s não existe.', p_documento_id));
  end if;

  -- A versão de referência é a mais recente: dela saem o arquivo e o nome, para a
  -- versão transcrita apontar para o MESMO arquivo. Transcrição não é upload novo.
  select dv.arquivo_ref, dv.nome_original, dv.origem_arquivo, dv.hash
    into v_ref, v_nome, v_origem, v_hash
  from documento_versao dv
  where dv.documento_id = p_documento_id
  order by dv.n_versao desc
  limit 1;

  if v_ref is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'O documento não tem nenhuma versão. Transcrição é leitura nova de um arquivo '
                       'que já está no sistema, não um caminho para inserir arquivo.');
  end if;

  -- VERSÃO NOVA (doutrina da 0026): a transcrição é uma leitura nova do mesmo
  -- arquivo, e `fn_versao_com_extracao` (0102) a elege como vigente por ela ter
  -- linhas. A versão ilegível fica preservada, com suas zero linhas, contando a
  -- história de por que houve transcrição.
  select coalesce(max(dv.n_versao), 0) + 1 into v_n_versao
    from documento_versao dv where dv.documento_id = p_documento_id;

  insert into documento_versao
    (documento_id, n_versao, origem_arquivo, arquivo_ref, nome_original, hash,
     legibilidade, nota_legibilidade)
  values (p_documento_id, v_n_versao, v_origem, v_ref, v_nome, v_hash,
          -- A legibilidade da VERSÃO TRANSCRITA é 'ok': o conteúdo dela é legível
          -- por construção, foi uma pessoa que o escreveu. O arquivo continua
          -- ilegível, e é a versão anterior que guarda esse fato.
          'ok',
          format('Transcrição humana assistida por %s%s', v_autor,
                 case when p_motivo is null then '' else ' — ' || p_motivo end))
  returning id into v_versao_id;

  -- AS GUARDAS DE EXTRAÇÃO NÃO RODAM AQUI, e por isso não se chama
  -- `fn_registrar_campos_extraidos`. Elas existem para pegar alucinação de modelo;
  -- "quatro contas com o mesmo valor" é padrão suspeito numa saída de IA e é rotina
  -- num balanço com contas zeradas. O que substitui a guarda é a AUTORIA.
  for v_item in select * from jsonb_array_elements(p_linhas)
  loop
    v_valor := case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$'
                    then (v_item->>'valor_num')::numeric else null end;

    insert into campo_extraido
      (documento_versao_id, chave, valor_texto, valor_num, unidade, moeda,
       secao, secao_canonica, entidade_coluna, periodo_coluna, ordem,
       origem_pagina, origem_linha,
       -- Confiança NULA de propósito: confiança é a autoavaliação de um modelo, e
       -- não existe equivalente para uma pessoa. Escrever 1.0 aqui inventaria uma
       -- medida e faria a linha transcrita passar em qualquer filtro de limiar.
       confianca,
       origem_valor, status_aceite, aceito_por, aceito_em)
    values (
      v_versao_id,
      coalesce(nullif(trim(v_item->>'chave'), ''), '(sem rótulo)'),
      v_item->>'valor_texto', v_valor,
      v_item->>'unidade', v_item->>'moeda',
      v_item->>'secao', v_item->>'secao_canonica',
      v_item->>'entidade_coluna', v_item->>'periodo_coluna',
      case when (v_item->>'ordem') ~ '^\d+$' then (v_item->>'ordem')::int else v_n end,
      case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int end,
      v_item->>'origem_linha',
      null,
      'transcricao_humana', 'aceito', v_autor, now());
    v_n := v_n + 1;
  end loop;

  -- A SAÍDA FOI TOMADA: a pendência de ilegibilidade fecha, com o nome de quem a
  -- fechou. É isto que faz o gate deixar de ser "dead-end de pendência infinita" —
  -- e é a única metade do fechamento #2 que já existia pela metade.
  select p.id into v_pendencia from pendencia p
   where p.documento_id = p_documento_id
     and p.tipo = 'arquivo_ilegivel'
     and p.estado <> 'resolvida'
   limit 1;
  if v_pendencia is not null then
    update pendencia
       set estado = 'resolvida', resolvida_em = now(),
           resolvida_por = v_autor
     where id = v_pendencia;
  end if;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (v_caso_id, 'aprovacao', v_autor,
      format('Transcrição humana assistida de "%s": %s linha(s) digitadas a partir do arquivo '
             'ilegível.%s', coalesce(v_nome, '?'), v_n,
             case when p_motivo is null then '' else ' Motivo: ' || p_motivo end),
      jsonb_build_object('documento_id', p_documento_id, 'documento_versao_id', v_versao_id,
                         'n_versao', v_n_versao, 'linhas', v_n,
                         'pendencia_resolvida', v_pendencia));

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values (v_autor, 'transcricao_humana', 'documento_versao:'||v_versao_id,
            jsonb_build_object('documento_id', p_documento_id, 'linhas', v_n,
                               'n_versao', v_n_versao,
                               'porque', 'fechamento #2 do Arquitetura do Sistema/1 Visão e Doutrina/01: gate de captura COM SAIDA. As '
                                         'guardas de extracao nao rodam (elas pegam alucinacao de '
                                         'modelo) e origem_valor marca as linhas para elas nao '
                                         'contaminarem a medicao da extracao.'));

  -- A completude precisa saber que as linhas chegaram, senão o Portão 1 continua
  -- cobrando o que já foi transcrito.
  perform fn_recomputar_completude(v_caso_id);

  -- E a classificação contábil roda sobre a versão nova, como roda sobre qualquer
  -- outra: em sombra, sem tocar em nada.
  perform fn_classificar_contabil(v_versao_id);

  return jsonb_build_object(
    'documento_versao_id', v_versao_id,
    'n_versao', v_n_versao,
    'linhas', v_n,
    'pendencia_resolvida', v_pendencia,
    'autor', v_autor);
end;
$_$;

--
-- Name: FUNCTION fn_registrar_transcricao_humana(p_documento_id uuid, p_linhas jsonb, p_autor text, p_motivo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_transcricao_humana(p_documento_id uuid, p_linhas jsonb, p_autor text, p_motivo text) IS 'A SAÍDA do gate de captura (fechamento #2 do Arquitetura do Sistema/1 Visão e Doutrina/01), que era o único dos oito fechamentos sem código. Cria VERSÃO NOVA (doutrina da 0026), marca as linhas com origem_valor=''transcricao_humana'' para elas não contaminarem fn_golden_campos, NÃO roda as guardas de extração (elas pegam alucinação de modelo, e acusariam um humano de fabricar por ler um balanço com contas zeradas), grava confiança NULA (não existe autoavaliação de pessoa) e resolve a pendência de ilegibilidade com o nome de quem a fechou.';

--
-- Name: fn_registrar_uso_lote(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_uso_lote(p_caso_id uuid, p_execucao_ref text, p_resumo jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_id uuid;
  v_num numeric;
begin
  if p_caso_id is null then
    return jsonb_build_object('gravado', false, 'motivo', 'caso_id ausente');
  end if;
  if nullif(btrim(coalesce(p_execucao_ref, '')), '') is null then
    -- SEM REFERÊNCIA DE EXECUÇÃO NÃO SE GRAVA. É a chave que impede a
    -- duplicidade; sem ela, a segunda passada viraria uma segunda linha e o
    -- custo do mandato sairia dobrado — exatamente o que esta tabela existe
    -- para não deixar acontecer.
    return jsonb_build_object('gravado', false, 'motivo', 'execucao_ref ausente');
  end if;

  -- Cobertura recalculada aqui, e não lida do resumo: é uma divisão, e divisão
  -- feita em dois lugares é divisão que diverge. O resumo continua trazendo a
  -- dele — se um dia os dois discordarem, a diferença é o sintoma.
  v_num := nullif((p_resumo->>'contas_nos_documentos')::numeric, 0);

  insert into lote_execucao (
    caso_id, execucao_ref,
    documentos, documentos_com_classificacao, documentos_fatiados,
    documentos_com_falha, documentos_sem_medicao,
    custo_total_usd, custo_extracao_usd, custo_classificacao_usd, custo_estimado_usd,
    tokens_entrada, tokens_saida, tokens_cache,
    linhas_extraidas, contas_nos_documentos, contas_extraidas, cobertura,
    orcamento_versao, fechado_em
  ) values (
    p_caso_id, btrim(p_execucao_ref),
    (p_resumo->>'documentos')::int,
    (p_resumo->>'documentos_com_classificacao')::int,
    (p_resumo->>'documentos_fatiados')::int,
    (p_resumo->>'documentos_com_falha')::int,
    (p_resumo->>'documentos_sem_medicao')::int,
    (p_resumo->>'custo_total_usd')::numeric,
    (p_resumo->>'custo_extracao_usd')::numeric,
    (p_resumo->>'custo_classificacao_usd')::numeric,
    (p_resumo->>'custo_estimado_usd')::numeric,
    (p_resumo#>>'{tokens,entrada}')::bigint,
    (p_resumo#>>'{tokens,saida}')::bigint,
    (p_resumo#>>'{tokens,cache}')::bigint,
    (p_resumo->>'linhas_extraidas')::int,
    (p_resumo->>'contas_nos_documentos')::int,
    (p_resumo->>'contas_extraidas')::int,
    case when v_num is null then null
         else round((p_resumo->>'contas_extraidas')::numeric / v_num, 4) end,
    p_resumo->>'orcamento_versao', now()
  )
  on conflict (caso_id, execucao_ref) do update set
    atualizado_em                = now(),
    -- O CARIMBO, e é a linha inteira da 0156 deste lado. `fechado_em` nulo
    -- significa "começou e não terminou"; sem esta linha, TODA execução ficaria
    -- com ele nulo e o sinal diria o contrário do que é.
    fechado_em                   = now(),
    documentos                   = excluded.documentos,
    documentos_com_classificacao = excluded.documentos_com_classificacao,
    documentos_fatiados          = excluded.documentos_fatiados,
    documentos_com_falha         = excluded.documentos_com_falha,
    documentos_sem_medicao       = excluded.documentos_sem_medicao,
    custo_total_usd              = excluded.custo_total_usd,
    custo_extracao_usd           = excluded.custo_extracao_usd,
    custo_classificacao_usd      = excluded.custo_classificacao_usd,
    custo_estimado_usd           = excluded.custo_estimado_usd,
    tokens_entrada               = excluded.tokens_entrada,
    tokens_saida                 = excluded.tokens_saida,
    tokens_cache                 = excluded.tokens_cache,
    linhas_extraidas             = excluded.linhas_extraidas,
    contas_nos_documentos        = excluded.contas_nos_documentos,
    contas_extraidas             = excluded.contas_extraidas,
    cobertura                    = excluded.cobertura,
    orcamento_versao             = excluded.orcamento_versao
  returning id into v_id;

  return jsonb_build_object(
    'gravado', true,
    'lote_execucao_id', v_id,
    'custo_total_usd', (p_resumo->>'custo_total_usd')::numeric
  );
end;
$$;

--
-- Name: FUNCTION fn_registrar_uso_lote(p_caso_id uuid, p_execucao_ref text, p_resumo jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_uso_lote(p_caso_id uuid, p_execucao_ref text, p_resumo jsonb) IS 'Grava (ou reescreve) o resumo de custo/cobertura de UMA execução de ingestão, e CARIMBA fechado_em (0156). Idempotente por (caso_id, execucao_ref): o Resumo de Custo roda uma vez por ramo do lote e as duas passadas trazem o total inteiro — sem isto, todo custo sairia dobrado.';

--
-- Name: fn_resolver_linha_exigida_superada(text[], text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_resolver_linha_exigida_superada(p_tipos text[], p_ator text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_caso       uuid;
  v_vivos      text[];
  v_p          record;
  v_razao      text;
  v_resolvidas int := 0;
  v_ficaram    int := 0;
  v_ressalva   int;
begin
  if p_ator is null or p_ator not like 'sistema:%' then
    raise exception 'fn_resolver_linha_exigida_superada: p_ator precisa ser ''sistema:<quem>'' (recebeu %)', p_ator;
  end if;

  for v_caso in
    select distinct p.caso_id
      from pendencia p
     where p.tipo = 'linha_exigida_ausente'
       and p.estado = 'aberta'
       and split_part(p.motivo, ':', 3) = any (p_tipos)
  loop
    select coalesce(array_agg(
             'completude:linha_exigida:' || x.tipo_taxonomia || ':' || x.conceito
             || case when x.entidade is not null
                     then ':' || fn_entidade_canonica(x.entidade) else '' end), '{}')
      into v_vivos
      from fn_exigencias_do_caso(v_caso) x
     where not x.satisfeita
       and x.tipo_taxonomia = any (p_tipos);

    for v_p in
      select p.id, p.motivo
        from pendencia p
       where p.caso_id = v_caso
         and p.tipo = 'linha_exigida_ausente'
         and p.estado = 'aberta'
         and split_part(p.motivo, ':', 3) = any (p_tipos)
       for update
    loop
      if v_p.motivo = any (v_vivos) then
        v_ficaram := v_ficaram + 1;
        continue;
      end if;

      v_razao := case when exists (
                        select 1 from taxonomia_linha_exigida e
                         where e.tipo_taxonomia = split_part(v_p.motivo, ':', 3)
                           and e.conceito = split_part(v_p.motivo, ':', 4)
                           and e.ativo)
                      then 'exigencia_ativa_nao_mais_ausente'
                      else 'exigencia_inativa' end;

      update pendencia
         set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_ator
       where id = v_p.id;

      insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
      values (p_ator, 'pendencia_resolvida', 'pendencia:' || v_p.id,
              jsonb_build_object('estado', 'aberta', 'motivo', v_p.motivo),
              jsonb_build_object('estado', 'resolvida', 'resolvida_por', p_ator,
                                 'razao', v_razao));
      v_resolvidas := v_resolvidas + 1;
    end loop;
  end loop;

  select count(*) into v_ressalva
    from pendencia p
   where p.tipo = 'linha_exigida_ausente'
     and p.estado = 'aceita_com_ressalva'
     and split_part(p.motivo, ':', 3) = any (p_tipos);

  return jsonb_build_object('resolvidas', v_resolvidas,
                            'ficaram_abertas', v_ficaram,
                            'ressalvadas_intocadas', v_ressalva);
end;
$$;

--
-- Name: FUNCTION fn_resolver_linha_exigida_superada(p_tipos text[], p_ator text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_resolver_linha_exigida_superada(p_tipos text[], p_ator text) IS '0187: resolve as pendências linha_exigida_ausente ABERTAS dos tipos pedidos que o Portão 1 não abriria mais hoje (exigência inativa ou satisfeita, pelo critério de fn_exigencias_do_caso), com um evento_auditoria por pendência. Não toca aceita_com_ressalva, não roda o resto da completude. Ação de migration/service_role — sem grant para o portal.';

--
-- Name: fn_resumo_anexar(uuid, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_resumo_anexar(p_arquivo uuid, p_registros jsonb, p_grupos jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_status text;
  v_nr integer := 0;
  v_ng integer := 0;
begin
  select resumo_status into v_status from arquivo_oficial where id = p_arquivo for update;
  if not found then raise exception 'fn_resumo_anexar: o arquivo oficial % não existe', p_arquivo; end if;
  if v_status is distinct from 'em_carga' then
    raise exception 'fn_resumo_anexar: o resumo do arquivo % está "%", não "em_carga" — recusado, nada foi gravado (reabra com fn_resumo_iniciar)',
      p_arquivo, coalesce(v_status, 'nunca iniciado');
  end if;
  p_registros := coalesce(p_registros, '[]'::jsonb);
  p_grupos := coalesce(p_grupos, '[]'::jsonb);
  if jsonb_typeof(p_registros) <> 'array' or jsonb_typeof(p_grupos) <> 'array' then
    raise exception 'fn_resumo_anexar: registros e grupos têm de ser arrays';
  end if;
  if jsonb_array_length(p_registros) > 10000 or jsonb_array_length(p_grupos) > 10000 then
    raise exception 'fn_resumo_anexar: parte grande demais (% registros, % grupos; teto 10000 de cada, o combinado é ~5000)',
      jsonb_array_length(p_registros), jsonb_array_length(p_grupos);
  end if;
  if exists (select 1 from jsonb_array_elements(p_registros) e
              where jsonb_typeof(e) <> 'array' or jsonb_array_length(e) <> 2
                 or jsonb_typeof(e->0) <> 'number' or jsonb_typeof(e->1) <> 'string') then
    raise exception 'fn_resumo_anexar: cada registro tem de ser [linha, texto]';
  end if;

  insert into arquivo_oficial_registro (arquivo_oficial_id, linha, registro, conteudo)
  select p_arquivo, (e->>0)::integer, split_part(e->>1, '|', 2), e->>1
    from jsonb_array_elements(p_registros) e;
  get diagnostics v_nr = row_count;

  insert into arquivo_oficial_lancamento_mes
    (arquivo_oficial_id, conta, mes, ind_lcto, debito, credito, partidas, partidas_sem_valor, primeira_linha)
  select p_arquivo, g.conta,
         case when g.mes is null then null else (g.mes || '-01')::date end,
         g.ind_lcto, g.debito, g.credito, g.partidas, g.partidas_sem_valor, g.primeira_linha
    from jsonb_to_recordset(p_grupos) as g(conta text, mes text, ind_lcto text, debito bigint, credito bigint,
                                            partidas integer, partidas_sem_valor integer, primeira_linha integer);
  get diagnostics v_ng = row_count;

  return jsonb_build_object('registros', v_nr, 'grupos', v_ng);
end $$;

--
-- Name: FUNCTION fn_resumo_anexar(p_arquivo uuid, p_registros jsonb, p_grupos jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_resumo_anexar(p_arquivo uuid, p_registros jsonb, p_grupos jsonb) IS 'Anexa uma parte (até 10000 itens de cada) ao resumo em_carga: p_registros = [[linha,texto],...], p_grupos = objetos {conta,mes,ind_lcto,debito,credito,partidas,partidas_sem_valor,primeira_linha}. Linha repetida no mesmo arquivo é erro (pk). Só aceita com resumo_status = em_carga. Devolve {registros, grupos} inseridos. 0207.';

--
-- Name: fn_resumo_concluir(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_resumo_concluir(p_arquivo uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
declare
  a        arquivo_oficial;
  v_motivos text[] := '{}';
  v_nr     integer;
  v_ng     integer;
  v_fora   integer;
  v_div    text;
  v_part   bigint;
  v_i250   bigint;
  v_i155   jsonb;
  v_motivo text;
begin
  select * into a from arquivo_oficial where id = p_arquivo for update;
  if not found then raise exception 'fn_resumo_concluir: o arquivo oficial % não existe', p_arquivo; end if;
  if a.resumo_status in ('completo', 'recusado') then   -- idempotente: o navegador pode repetir depois de perder a resposta
    return jsonb_build_object('resumo', a.resumo_status, 'motivo', a.resumo_motivo,
      'registros', (select count(*) from arquivo_oficial_registro where arquivo_oficial_id = p_arquivo),
      'grupos', (select count(*) from arquivo_oficial_lancamento_mes where arquivo_oficial_id = p_arquivo),
      'i155_nao_fecham', (a.resumo_conferencia->'i155'->>'nao_fecham')::integer);
  end if;
  if a.resumo_status is distinct from 'em_carga' then
    raise exception 'fn_resumo_concluir: o resumo do arquivo % está "%", não "em_carga"', p_arquivo, coalesce(a.resumo_status, 'nunca iniciado');
  end if;

  select count(*) into v_nr from arquivo_oficial_registro where arquivo_oficial_id = p_arquivo;
  select count(*) into v_ng from arquivo_oficial_lancamento_mes where arquivo_oficial_id = p_arquivo;

  -- (a) o que chegou é o que foi declarado.
  if v_nr <> a.resumo_total_registros then
    v_motivos := v_motivos || format('registros gravados %s, declarados %s', v_nr, a.resumo_total_registros);
  end if;
  if v_ng <> a.resumo_total_grupos then
    v_motivos := v_motivos || format('grupos gravados %s, declarados %s', v_ng, a.resumo_total_grupos);
  end if;

  -- (b) linha de um arquivo de controle_lido linhas está entre 1 e controle_lido.
  select (select count(*) from arquivo_oficial_registro
           where arquivo_oficial_id = p_arquivo and (linha < 1 or linha > a.controle_lido))
       + (select count(*) from arquivo_oficial_lancamento_mes
           where arquivo_oficial_id = p_arquivo and primeira_linha is not null
             and (primeira_linha < 1 or primeira_linha > a.controle_lido))
    into v_fora;
  if v_fora > 0 then
    v_motivos := v_motivos || format('%s linha(s) fora de 1..%s (o arquivo tem %s linhas)', v_fora, a.controle_lido, a.controle_lido);
  end if;

  -- (c) cada tipo que aparece no resumo tem a contagem do envelope (já conferida contra o 9900).
  select string_agg(format('%s: resumo %s, envelope %s', t.registro, t.n, coalesce(a.detalhe->'por_registro'->>t.registro, '0')), '; ' order by t.registro)
    into v_div
    from (select registro, count(*) n from arquivo_oficial_registro where arquivo_oficial_id = p_arquivo group by registro) t
   where coalesce((a.detalhe->'por_registro'->>t.registro)::bigint, 0) <> t.n;
  if v_div is not null then
    v_motivos := v_motivos || ('contagem por registro diverge do envelope (' || v_div || ')');
  end if;

  -- (d) as partidas somadas nos grupos são as I250 do envelope; só a ECD tem grupos.
  select coalesce(sum(partidas), 0) into v_part from arquivo_oficial_lancamento_mes where arquivo_oficial_id = p_arquivo;
  if a.familia = 'sped' and a.subtipo = 'ECD' then
    v_i250 := coalesce((a.detalhe->'por_registro'->>'I250')::bigint, 0);
    if v_part <> v_i250 then
      v_motivos := v_motivos || format('soma de partidas dos grupos %s, I250 do envelope %s', v_part, v_i250);
    end if;
  elsif v_ng > 0 then
    v_motivos := v_motivos || format('%s grupo(s) de lançamento em arquivo %s/%s, que não os tem', v_ng, a.familia, a.subtipo);
  end if;

  if cardinality(v_motivos) > 0 then
    v_motivo := array_to_string(v_motivos, ' | ');
    delete from arquivo_oficial_registro where arquivo_oficial_id = p_arquivo;
    delete from arquivo_oficial_lancamento_mes where arquivo_oficial_id = p_arquivo;
    update arquivo_oficial set resumo_status = 'recusado', resumo_motivo = v_motivo where id = p_arquivo;
    return jsonb_build_object('resumo', 'recusado', 'motivo', v_motivo, 'registros', 0, 'grupos', 0, 'i155_nao_fecham', null);
  end if;

  -- A aritmética do I155 é ACHADO e não recusa. |I155|COD_CTA|COD_CCUS|VL_SLD_INI|IND_DC_INI|VL_DEB|VL_CRED|VL_SLD_FIN|IND_DC_FIN|
  -- (split_part: 3 = conta, 5 = saldo ini, 6 = D/C ini, 7 = débito, 8 = crédito, 9 = saldo fin, 10 = D/C fin).
  with i as (
    select linha, split_part(conteudo, '|', 3) conta,
           split_part(conteudo, '|', 5) sini, split_part(conteudo, '|', 6) dcini,
           split_part(conteudo, '|', 7) deb,  split_part(conteudo, '|', 8) cred,
           split_part(conteudo, '|', 9) sfin, split_part(conteudo, '|', 10) dcfin
      from arquivo_oficial_registro where arquivo_oficial_id = p_arquivo and registro = 'I155'
  ), n as (
    select linha, conta, dcini, dcfin,
           (sini ~ '^[0-9]+(,[0-9]+)?$' or sini ~ '^[0-9]{1,3}(\.[0-9]{3})+(,[0-9]+)?$')
             and (deb ~ '^[0-9]+(,[0-9]+)?$' or deb ~ '^[0-9]{1,3}(\.[0-9]{3})+(,[0-9]+)?$')
             and (cred ~ '^[0-9]+(,[0-9]+)?$' or cred ~ '^[0-9]{1,3}(\.[0-9]{3})+(,[0-9]+)?$')
             and (sfin ~ '^[0-9]+(,[0-9]+)?$' or sfin ~ '^[0-9]{1,3}(\.[0-9]{3})+(,[0-9]+)?$')
             and dcini in ('D', 'C') and dcfin in ('D', 'C') as legivel,
           sini, deb, cred, sfin
      from i
  ), v as (
    select linha, conta, legivel,
           case when legivel then
             (replace(replace(sini, '.', ''), ',', '.')::numeric * case dcini when 'D' then 1 else -1 end)
             + replace(replace(deb, '.', ''), ',', '.')::numeric - replace(replace(cred, '.', ''), ',', '.')::numeric
           end esperado,
           case when legivel then replace(replace(sfin, '.', ''), ',', '.')::numeric * case dcfin when 'D' then 1 else -1 end end declarado
      from n
  )
  select jsonb_build_object(
           'total', count(*),
           'ilegiveis', count(*) filter (where not legivel),
           'nao_fecham', count(*) filter (where legivel and esperado <> declarado),
           'amostra', coalesce((select jsonb_agg(jsonb_build_object('linha', linha, 'conta', conta, 'esperado', esperado, 'declarado', declarado) order by linha)
                                  from (select * from v where legivel and esperado <> declarado order by linha limit 20) s), '[]'::jsonb))
    into v_i155 from v;

  update arquivo_oficial set resumo_status = 'completo', resumo_motivo = null,
         resumo_conferencia = coalesce(resumo_conferencia, '{}'::jsonb) || jsonb_build_object('i155', v_i155)
   where id = p_arquivo;
  return jsonb_build_object('resumo', 'completo', 'registros', v_nr, 'grupos', v_ng,
                            'i155_nao_fecham', (v_i155->>'nao_fecham')::integer);
end $_$;

--
-- Name: FUNCTION fn_resumo_concluir(p_arquivo uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_resumo_concluir(p_arquivo uuid) IS 'A reconferência do servidor sobre o resumo carregado: gravado = declarado, linhas em 1..controle_lido, contagem por registro = detalhe.por_registro do envelope, soma de partidas = I250 (ECD). Falhou: recusado + linhas apagadas. Passou: completo, e conta (sem recusar) os I155 cuja aritmética saldo_ini + débito - crédito = saldo_fin não fecha, em resumo_conferencia->i155. Idempotente. 0207.';

--
-- Name: fn_resumo_iniciar(uuid, uuid, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_resumo_iniciar(p_caso uuid, p_documento uuid, p_envelope jsonb, p_cabecalho jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
declare
  v_reg  jsonb;
  v_arq  arquivo_oficial;
  v_ver  text;
  v_totr integer;
  v_totg integer;
  v_motivo text;
begin
  if p_envelope is null or p_cabecalho is null then
    raise exception 'fn_resumo_iniciar: envelope e cabeçalho do resumo são obrigatórios';
  end if;
  -- Antes de gravar QUALQUER coisa: um resumo de outro arquivo não pode ser pendurado neste envelope.
  if p_cabecalho->>'hash_sha256' is distinct from p_envelope->>'hash_sha256' then
    raise exception 'fn_resumo_iniciar: o hash do resumo (%) não é o do envelope (%) — resumo de outro arquivo, recusado',
      p_cabecalho->>'hash_sha256', p_envelope->>'hash_sha256';
  end if;

  v_reg := fn_registrar_arquivo_oficial(p_caso, p_documento, p_envelope);   -- recusa a trilha desligada
  select * into v_arq from arquivo_oficial where id = (v_reg->>'id')::uuid for update;
  v_ver := coalesce(p_cabecalho->>'versao', '');
  if v_ver = '' then
    raise exception 'fn_resumo_iniciar: o cabeçalho não traz a versão do resumo';
  end if;

  if v_arq.resumo_status = 'completo' and v_arq.resumo_versao = v_ver then
    return v_reg || jsonb_build_object('resumo', 'reenvio');
  end if;

  if v_arq.status <> 'lido' or nullif(p_cabecalho->>'ausente', '') is not null then
    v_motivo := case when v_arq.status <> 'lido'
      then 'arquivo não lido por inteiro (' || v_arq.status || '): sem resumo, para que nada parcial seja tomado pelo arquivo'
           || coalesce(' — ' || nullif(p_cabecalho->>'ausente', ''), '')
      else p_cabecalho->>'ausente' end;
    delete from arquivo_oficial_registro where arquivo_oficial_id = v_arq.id;
    delete from arquivo_oficial_lancamento_mes where arquivo_oficial_id = v_arq.id;
    update arquivo_oficial set resumo_status = 'ausente', resumo_versao = v_ver, resumo_motivo = v_motivo,
           resumo_conferencia = p_cabecalho->'conferencia', resumo_descartado = p_cabecalho->>'descartado',
           resumo_total_registros = null, resumo_total_grupos = null
     where id = v_arq.id;
    return v_reg || jsonb_build_object('resumo', 'ausente', 'motivo', v_motivo);
  end if;

  if coalesce(p_cabecalho->>'total_registros', '') !~ '^[0-9]+$' or coalesce(p_cabecalho->>'total_grupos', '') !~ '^[0-9]+$' then
    raise exception 'fn_resumo_iniciar: o cabeçalho não declara total_registros e total_grupos (inteiros >= 0); sem eles o servidor não tem contra o que conferir';
  end if;
  v_totr := (p_cabecalho->>'total_registros')::integer;
  v_totg := (p_cabecalho->>'total_grupos')::integer;

  delete from arquivo_oficial_registro where arquivo_oficial_id = v_arq.id;
  delete from arquivo_oficial_lancamento_mes where arquivo_oficial_id = v_arq.id;
  update arquivo_oficial set resumo_status = 'em_carga', resumo_versao = v_ver, resumo_motivo = null,
         resumo_conferencia = p_cabecalho->'conferencia', resumo_descartado = p_cabecalho->>'descartado',
         resumo_total_registros = v_totr, resumo_total_grupos = v_totg
   where id = v_arq.id;
  return v_reg || jsonb_build_object('resumo', 'em_carga');
end $_$;

--
-- Name: FUNCTION fn_resumo_iniciar(p_caso uuid, p_documento uuid, p_envelope jsonb, p_cabecalho jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_resumo_iniciar(p_caso uuid, p_documento uuid, p_envelope jsonb, p_cabecalho jsonb) IS 'Abre a carga do resumo de um arquivo oficial: registra o envelope (fn_registrar_arquivo_oficial, que recusa a trilha desligada), recusa resumo de outro hash, e devolve {id,status,vigente,resumo} com resumo = em_carga (mande as partes), ausente (nada a mandar) ou reenvio (já completo nesta versão). Apaga a carga anterior do mesmo arquivo. 0207.';

--
-- Name: fn_revisar_documento(uuid, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_revisar_documento(p_documento_id uuid, p_autor text, p_novo_tipo_taxonomia text DEFAULT NULL::text, p_nova_entidade_nome text DEFAULT NULL::text, p_novo_periodo_tipo text DEFAULT NULL::text, p_novo_periodo_ref text DEFAULT NULL::text, p_motivo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_id     uuid;
  v_tipo_antigo text;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_tipo_final  text;
  v_obrig       obrigatoriedade;
  v_mudou_tipo  boolean;
begin
  select caso_id, tipo_taxonomia, entidade_id, periodo_id
    into v_caso_id, v_tipo_antigo, v_entidade_id, v_periodo_id
  from documento where id = p_documento_id;

  if v_caso_id is null then
    raise exception 'documento % não encontrado', p_documento_id;
  end if;

  if p_nova_entidade_nome is not null and length(trim(p_nova_entidade_nome)) > 0 then
    select id into v_entidade_id from entidade
      where caso_id = v_caso_id and lower(razao_social) = lower(p_nova_entidade_nome) limit 1;
    if v_entidade_id is null then
      insert into entidade (caso_id, razao_social) values (v_caso_id, p_nova_entidade_nome)
        returning id into v_entidade_id;
    end if;
  end if;

  if p_novo_periodo_ref is not null and length(trim(p_novo_periodo_ref)) > 0 then
    select id into v_periodo_id from periodo
      where caso_id = v_caso_id and tipo = coalesce(p_novo_periodo_tipo,'outro') and referencia = p_novo_periodo_ref limit 1;
    if v_periodo_id is null then
      insert into periodo (caso_id, tipo, referencia)
        values (v_caso_id, coalesce(p_novo_periodo_tipo,'outro'), p_novo_periodo_ref)
        returning id into v_periodo_id;
    end if;
  end if;

  v_tipo_final := coalesce(p_novo_tipo_taxonomia, v_tipo_antigo);
  v_mudou_tipo := v_tipo_final is distinct from v_tipo_antigo;

  update documento set
    tipo_taxonomia = v_tipo_final,
    entidade_id     = v_entidade_id,
    periodo_id      = v_periodo_id,
    confianca       = 1.0,
    fonte           = 'humano',
    justificativa   = coalesce(p_motivo, justificativa)
  where id = p_documento_id;

  -- Checklist: a entrada antiga (se houver) ficaria presa ao tipo errado —
  -- remove e recria para o tipo final (idempotente: sempre reflete o estado atual).
  delete from checklist_item_status where documento_id = p_documento_id;
  if v_tipo_final is not null then
    select obrigatoriedade into v_obrig from taxonomia_tipo_documento where codigo = v_tipo_final;
    insert into checklist_item_status
      (caso_id, entidade_id, periodo_id, tipo_taxonomia, obrigatoriedade, status, documento_id)
      values (v_caso_id, v_entidade_id, v_periodo_id, v_tipo_final,
              coalesce(v_obrig,'complementar'), 'presente', p_documento_id);
  end if;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (v_caso_id,
            (case when v_mudou_tipo then 'correcao_classificacao' else 'aprovacao' end)::decisao_tipo,
            p_autor, p_motivo,
            jsonb_build_object('documento_id', p_documento_id, 'tipo_de', v_tipo_antigo, 'tipo_para', v_tipo_final));

  -- FIX (0018): resolve TODOS os tipos de pendência de revisão gerados para
  -- este documento — não só `classificacao_pendente`. `tipo_incorreto`/
  -- `entidade_incorreta`/`periodo_incorreto` (migration 0010) são fechados
  -- pela MESMA ação de revisão (o formulário já reenvia tipo+entidade+período
  -- juntos), então a resolução tem que cobrir os quatro.
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_autor
  where documento_id = p_documento_id
    and tipo in ('classificacao_pendente', 'tipo_incorreto', 'entidade_incorreta', 'periodo_incorreto')
    and estado <> 'resolvida';

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'documento_revisado', 'documento:'||p_documento_id,
            jsonb_build_object('tipo', v_tipo_antigo),
            jsonb_build_object('tipo', v_tipo_final, 'motivo', p_motivo));

  perform fn_recomputar_completude(v_caso_id);

  return jsonb_build_object('documento_id', p_documento_id, 'tipo_taxonomia', v_tipo_final, 'mudou_tipo', v_mudou_tipo);
end;
$$;

--
-- Name: fn_rotulo_contido(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_rotulo_contido(p_curto text, p_longo text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select fn_tem_palavra_longa(p_curto)
     and fn_radicais_rotulo(p_curto) <@ fn_radicais_rotulo(p_longo);
$$;

--
-- Name: FUNCTION fn_rotulo_contido(p_curto text, p_longo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_rotulo_contido(p_curto text, p_longo text) IS 'O primeiro rótulo é uma descrição mais grossa do segundo (radicais de 5 letras contidos, com ao menos uma palavra de 4+ letras)? Usado por sobreposicao_suspeita: valor igual sozinho acusa coincidência, e guarda que acusa coincidência é guarda que se aprende a ignorar.';

--
-- Name: fn_rotulo_estrutural(text, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_rotulo_estrutural(p_chave text, p_tokens_exigidos text[]) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select fn_tokens_estruturais(p_chave)
       = coalesce((select array_agg(distinct t order by t) from unnest(p_tokens_exigidos) as t),
                  array[]::text[]);
$$;

--
-- Name: FUNCTION fn_rotulo_estrutural(p_chave text, p_tokens_exigidos text[]); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_rotulo_estrutural(p_chave text, p_tokens_exigidos text[]) IS 'Um rótulo É o total de um grupo quando, tiradas ligação e a palavra "total", sobram exatamente as palavras estruturais do grupo. Tradução do `soEstrutural` do classificador TypeScript (0034); desde a 0102 apoiada em fn_tokens_estruturais.';

--
-- Name: fn_rotulos_candidatos(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_rotulos_candidatos(p_documento_versao_id uuid) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  with cand as (
    select distinct
      ce.chave,
      coalesce(nullif(ce.entidade_coluna, ''), '—') as ec,
      coalesce(nullif(ce.periodo_coluna, ''), '—')  as pc
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.valor_num is not null
      and (fn_normalizar_texto(ce.chave) like '%total%'
           or fn_normalizar_texto(ce.chave) like '%ativo%'
           or fn_normalizar_texto(ce.chave) like '%passivo%'
           or fn_normalizar_texto(ce.chave) like '%patrimonio%')
    order by ce.chave
    limit 12
  )
  select case when count(*) = 0
    then 'nenhum rótulo com ativo/passivo/patrimônio/total foi extraído desta versão'
    else string_agg(format('"%s" [entidade: %s; período: %s]', chave, ec, pc), ', ' order by chave)
  end
  from cand;
$$;

--
-- Name: FUNCTION fn_rotulos_candidatos(p_documento_versao_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_rotulos_candidatos(p_documento_versao_id uuid) IS 'Rótulos extraídos que poderiam ser um total de Ativo/Passivo/PL, com a coluna de entidade/período de cada um. Existe para a pendência de pré-condição poder NOMEAR o que não casou — inclusive quando o que não casou foi a COLUNA (0033).';

--
-- Name: fn_saldo_mutuos_do_documento(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_saldo_mutuos_do_documento(p_linhas jsonb) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
  v_n        int;
  v_cols     text[];
  v_ano      int;
  v_cand     text[];
  v_col      text;
  v_tot_n    int;
  v_tot_vals numeric[];
  v_tot_unid text[];
  v_it_n     int;
  v_it_unid  text[];
  v_soma     numeric;
begin
  select count(*)::int, array_agg(distinct l.coluna order by l.coluna)
    into v_n, v_cols from fn_saldo_mutuos_linhas(p_linhas) l;
  if v_n = 0 then
    return jsonb_build_object('valor', null, 'porque', null, 'n_linhas', 0);
  end if;

  -- 1. A COLUNA
  if cardinality(v_cols) = 1 then
    v_col := v_cols[1];
  else
    select max(a) into v_ano from unnest(v_cols) c, unnest(fn_anos_texto(c)) a;
    if v_ano is null then
      return jsonb_build_object('valor', null, 'n_linhas', v_n, 'porque',
        format('a relação tem %s colunas de valor (%s) e nenhuma diz o exercício — somá-las '
               'misturaria saldo com juros ou com o ano anterior',
               cardinality(v_cols), array_to_string(v_cols, ', ')));
    end if;
    select array_agg(c order by c) into v_cand from unnest(v_cols) c
     where v_ano = any (fn_anos_texto(c));
    if cardinality(v_cand) > 1 then
      select array_agg(c order by c) into v_cand from unnest(v_cand) c
       where fn_normalizar_texto(c) like '%saldo%';
    end if;
    if coalesce(cardinality(v_cand), 0) <> 1 then
      return jsonb_build_object('valor', null, 'n_linhas', v_n, 'porque',
        format('a relação tem mais de uma coluna do exercício %s (%s) e nenhuma é, sozinha, a '
               'do saldo', v_ano, array_to_string(v_cols, ', ')));
    end if;
    v_col := v_cand[1];
  end if;

  -- 2. O TOTAL GERAL
  select count(*)::int, array_agg(distinct l.valor order by l.valor),
         array_agg(distinct coalesce(l.unidade, '') order by coalesce(l.unidade, ''))
    into v_tot_n, v_tot_vals, v_tot_unid
    from fn_saldo_mutuos_linhas(p_linhas) l
   where l.coluna = v_col and l.eh_total_geral;
  if v_tot_n > 0 then
    if cardinality(v_tot_vals) = 1 and cardinality(v_tot_unid) = 1 then
      return jsonb_build_object('valor', v_tot_vals[1], 'unidade', nullif(v_tot_unid[1], ''),
        'forma', 'linha_de_total', 'coluna', nullif(v_col, ''), 'n_linhas', v_n, 'porque', null);
    end if;
    return jsonb_build_object('valor', null, 'n_linhas', v_n, 'porque',
      format('a relação tem %s linhas de total geral que não concordam entre si', v_tot_n));
  end if;

  -- 3. A SOMA DOS ITENS
  select count(*), array_agg(distinct coalesce(l.unidade, '') order by coalesce(l.unidade, '')),
         sum(l.valor)
    into v_it_n, v_it_unid, v_soma
    from fn_saldo_mutuos_linhas(p_linhas) l
   where l.coluna = v_col and not l.eh_total;
  if v_it_n = 0 then
    return jsonb_build_object('valor', null, 'n_linhas', v_n, 'porque',
      'a relação só traz subtotais parciais, sem total geral nem os itens');
  end if;
  if cardinality(v_it_unid) > 1 then
    return jsonb_build_object('valor', null, 'n_linhas', v_n, 'porque',
      'as linhas da relação estão em escalas diferentes');
  end if;
  return jsonb_build_object('valor', v_soma, 'unidade', nullif(v_it_unid[1], ''),
    'forma', 'soma_dos_itens', 'coluna', nullif(v_col, ''), 'n_itens', v_it_n,
    'n_linhas', v_n, 'porque', null);
end;
$$;

--
-- Name: FUNCTION fn_saldo_mutuos_do_documento(p_linhas jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_saldo_mutuos_do_documento(p_linhas jsonb) IS '0187 (revisão): o saldo de UMA relação de mútuos a partir das linhas com valor ([{chave, valor, unidade, coluna}]). Coluna do exercício mais recente; linha de total geral se houver, senão a soma dos itens numa escala só. Devolve {valor, unidade, forma, coluna} ou {valor: null, porque} quando não dá para apurar com segurança — nunca uma soma cega. Pura: a sonda instalacao_sonda_saldo_mutuos a executa sobre literais.';

--
-- Name: fn_saldo_mutuos_linhas(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_saldo_mutuos_linhas(p_linhas jsonb) RETURNS TABLE(chave text, valor numeric, unidade text, coluna text, eh_total boolean, eh_total_geral boolean)
    LANGUAGE sql IMMUTABLE
    AS $_$
  select x->>'chave', (x->>'valor')::numeric, nullif(btrim(x->>'unidade'), ''),
         coalesce(nullif(btrim(x->>'coluna'), ''), ''),
         t.eh_total,
         t.eh_total and fn_tokens_estruturais(x->>'chave')
                        <@ array['saldo','saldos','mutuo','mutuos','emprestimo','emprestimos',
                                 'intragrupo','partes','relacionadas','grupo','operacoes',
                                 'operacao','entre','empresas']::text[]
    from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) x
    cross join lateral (select fn_normalizar_texto(x->>'chave')
                               ~ '(^|[^a-z])(total|totais|subtotal|soma|somatorio)([^a-z]|$)'
                               as eh_total) t
   where x->>'valor' is not null
     and fn_papel_linha(x->>'chave') <> 'derivado';
$_$;

--
-- Name: fn_saldo_mutuos_texto(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_saldo_mutuos_texto(p_caso_id uuid) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  with docs as (
    select d.id, dv.nome_original,
           (select max(a) from unnest(fn_anos_do_periodo(p.referencia)) a) as ano,
           fn_saldo_mutuos_do_documento((
             select jsonb_agg(jsonb_build_object('chave', ce.chave, 'valor', ce.valor_num,
                                                 'unidade', ce.unidade,
                                                 'coluna', ce.periodo_coluna))
               from campo_extraido ce
              where ce.documento_versao_id = dv.id and ce.valor_num is not null)) as r
      from documento d
      join documento_versao dv on dv.id = fn_versao_com_extracao(d.id)
      left join periodo p on p.id = d.periodo_id
     where d.caso_id = p_caso_id
       and d.tipo_taxonomia = 'MUTUOS'
  ),
  com_valor as (
    select * from docs where coalesce((r->>'n_linhas')::int, 0) > 0
  ),
  recentes as (
    select * from com_valor
     where ano is not distinct from (select max(ano) from com_valor)
        or (select max(ano) from com_valor) is null
  )
  select case
    when count(*) = 0 then null
    when count(*) = 1 then
      coalesce(fn_valor_pt_br(max((r->>'valor')::numeric), max(r->>'unidade')),
               '(não foi possível apurar o saldo: ' || max(r->>'porque') || ' — conferir na relação enviada)')
    when count(*) filter (where r->>'valor' is null) > 0 then
      '(não foi possível apurar o saldo: ' || string_agg(nome_original || ' — ' || (r->>'porque'), '; ')
        filter (where r->>'valor' is null) || ')'
    when count(distinct coalesce(r->>'unidade', '')) > 1 then '(valores em escalas mistas — conferir)'
    else format('(não foi possível apurar um saldo único: o caso tem %s relações de mútuos do mesmo '
                'exercício — conferir qual vale)', count(*))
  end
  from recentes;
$$;

--
-- Name: FUNCTION fn_saldo_mutuos_texto(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_saldo_mutuos_texto(p_caso_id uuid) IS '0187 (revisão): o texto do marcador {saldo_mutuos} da pergunta 5.1. NULL sem relação de mútuos com valor (a pergunta diz "(não localizado)"); o saldo em reais quando UMA relação do período mais recente o apura; "(não foi possível apurar…)" com o motivo em qualquer outro caso.';

--
-- Name: fn_sazonalidade_do_caso(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_sazonalidade_do_caso(p_caso_id uuid) RETURNS TABLE(mes integer, fracao numeric, n_observacoes bigint)
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  with mensal as (
    select fn_mes_do_rotulo(ce.chave) as mes, abs(ce.valor_num) as valor
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id
      and d.tipo_taxonomia = 'FATURAMENTO_24M'
      and ce.valor_num is not null
      -- A linha de TOTAL não é um mês. Continua sendo o `fn_mes_do_rotulo` que a
      -- exclui (nenhuma palavra de mês em "TOTAL DO EXERCÍCIO"); este filtro é
      -- REDUNDANTE de propósito, para um rótulo como "Total jan-dez", e está
      -- anotado como redundante para ninguém escrever um teste acreditando estar
      -- provando ele — foi o que aconteceu na primeira versão do teste da 0040.
      and fn_normalizar_texto(ce.chave) not like 'total%'
      -- 0042: e a linha DERIVADA também não é um mês. "Média mensal" não casa
      -- palavra de mês, mas "Ticket médio por pedido 2024" tampouco deveria
      -- entrar numa curva de faturamento se algum dia casar.
      and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) <> 'derivado'
      and dv.id = fn_versao_com_extracao(d.id)
  ),
  somado as (
    select mes, sum(valor) as valor, count(*) as n
    from mensal where mes is not null
    group by mes
  ),
  total as (select sum(valor) as t from somado)
  select s.mes,
         case when t.t is null or t.t = 0 then null else s.valor / t.t end as fracao,
         s.n as n_observacoes
  from somado s cross join total t
  -- Só devolve curva COMPLETA: 12 meses ou nada. Curva parcial distribuiria o
  -- ano inteiro nos meses que existem, inflando cada um — pior que não ter curva.
  where (select count(*) from somado) = 12
  order by s.mes;
$$;

--
-- Name: FUNCTION fn_sazonalidade_do_caso(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_sazonalidade_do_caso(p_caso_id uuid) IS 'Curva de sazonalidade DERIVADA do faturamento mensal do caso (0040), 12 meses ou nada. 0102: só a versão vigente do documento de faturamento — versão superada faria o mesmo mês entrar duas vezes e deslocaria a curva que reparte o valor anual no Excel.';

--
-- Name: fn_secao_canonica_da_secao_bruta(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_secao_canonica_da_secao_bruta(p_secao text, p_tipo_documento text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
declare
  n       text;
  v_patr  boolean := p_tipo_documento in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA');
  v_res   boolean := p_tipo_documento in ('DRE', 'DF_AUDITADA', 'BALANCETE', 'COMBINADO');
  v_dre   boolean := p_tipo_documento in ('DRE', 'DF_AUDITADA');
  v_lp    boolean;
begin
  -- Fora dos cinco tipos de demonstração a seção bruta tem outro significado (DMPL, DVA, fluxo, mapa de
  -- dívida, faturamento…): quem decide é a IA, e a função não opina.
  if p_secao is null or not (v_patr or v_res) then
    return null;
  end if;

  n := fn_normalizar_texto(p_secao);
  -- tira o marcador de sinal e a numeração do cabeçalho: "(-) Deduções", "= Receita", "1.1 Ativo circulante", "II - Passivo"
  n := regexp_replace(n, '^(\(\s*[-+=]\s*\)|[-+=])\s*', '');
  n := regexp_replace(n, '^([0-9]+(\.[0-9]+)*|[ivx]+)\s*[-.)]\s*', '');
  n := regexp_replace(n, '[\s:.;]+$', '');
  if n = '' then
    return null;
  end if;

  -- "longo prazo" / "não circulante" / "LP" no texto: o lado do prazo é explícito
  v_lp := n ~ '(longo prazo|nao circulante|\mlp\M)';

  -- ---- PATRIMONIAL ---------------------------------------------------------
  -- O LADO (ativo × passivo) tem de estar NO TEXTO. "CIRCULANTE", "NÃO CIRCULANTE", "ATIVO", "PASSIVO",
  -- "TOTAL DO ATIVO", "PASSIVO E PATRIMÔNIO LÍQUIDO" não dizem a seção — ficam NULL (abaixo).
  if v_patr then
    if n ~ '^(ativo (nao circulante|permanente|realizavel a longo prazo)|nao circulante ativo|realizavel a longo prazo|ativo realizavel a longo prazo|imobilizado|ativo imobilizado|intangivel|ativo intangivel|investimentos|direito de uso)$' then
      return 'ativo_nao_circulante';
    end if;
    if n ~ '^(passivo (nao circulante|exigivel a longo prazo|de longo prazo)|nao circulante passivo|exigivel a longo prazo)$'
       or (v_lp and n ~ '^(emprestimos|financiamentos|obrigacoes|contas a pagar|fornecedores)') then
      return 'passivo_nao_circulante';
    end if;
    if n ~ '^(ativo circulante|circulante ativo|disponivel|disponibilidades|caixa e equivalentes( de caixa)?|bancos( conta movimento)?|aplicacoes financeiras)$' then
      return 'ativo_circulante';
    end if;
    if n ~ '^(passivo circulante|circulante passivo|contas a pagar|fornecedores)$'
       or n ~ '^obrigacoes( (com o pessoal|com pessoal|trabalhistas|sociais|fiscais|tributarias|previdenciarias)( e (trabalhistas|sociais|fiscais|tributarias|previdenciarias))*)?$'
       or n ~ '^(emprestimos e financiamentos|emprestimos|financiamentos)( -| /)? (de |a )?(curto prazo|cp)$' then
      return 'passivo_circulante';
    end if;
    if n = 'patrimonio liquido' then
      return 'patrimonio_liquido';
    end if;
  end if;

  -- ---- RESULTADO -----------------------------------------------------------
  -- Âncora nas duas pontas, sempre: "despesas antecipadas" (ativo), "receitas diferidas" (passivo),
  -- "impostos a recolher" (passivo) e "provisão para IR" no balancete NÃO podem cair aqui por conterem
  -- uma palavra de resultado.
  if v_res then
    if n ~ '^((resultado|receitas?|despesas?)( e (receitas?|despesas?))? financeir[oa]s?( liquid[oa]s?)?)$' then
      return 'resultado_financeiro';
    end if;
    if v_dre and n ~ '^(imposto de renda( e contribuicao social)?( sobre o lucro)?|contribuicao social( sobre o lucro)?|irpj( e csll)?|csll|tributos sobre o lucro|impostos sobre o lucro|provisao para (imposto de renda|irpj)( e contribuicao social| e csll)?)$' then
      return 'impostos_lucro';
    end if;
    if v_dre and n ~ '^deducoes( da receita( bruta)?| de vendas| e abatimentos)?$' then
      return 'receita_bruta';
    end if;
    if n ~ '^(receitas?( operacionais?)?( brutas?)?|receitas? brutas? operacionais?|receitas? (de )?(vendas?|servicos|vendas e servicos|vendas de mercadorias)|faturamento( bruto)?|vendas( brutas)?( de (produtos|mercadorias|servicos|produtos e servicos|mercadorias e servicos|produtos, mercadorias e servicos))?)$' then
      return 'receita_bruta';
    end if;
    if n ~ '^(cmv|cpv|csp|custos?( operacionais?)?|custos? d[aeo]s? (vendas|produtos vendidos|mercadorias vendidas|servicos prestados|produtos e servicos|produtos|mercadorias|servicos)( vendid[oa]s| prestad[oa]s)?)$' then
      return 'custos';
    end if;
    if n ~ '^despesas (operacionais|administrativas|gerais|comerciais|com vendas|de vendas|com pessoal|gerais e administrativas|administrativas e gerais|administrativas e comerciais|com vendas e administrativas)$' then
      return 'despesas_operacionais';
    end if;
  end if;

  -- NULL de propósito (cada um é "procurei e não é inequívoco", não "esqueci"): ver o cabeçalho da 0203.
  return null;
end $_$;

--
-- Name: FUNCTION fn_secao_canonica_da_secao_bruta(p_secao text, p_tipo_documento text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_secao_canonica_da_secao_bruta(p_secao text, p_tipo_documento text) IS '0203: seção canônica inferida do texto da seção BRUTA (campo_extraido.secao) quando a IA não deu secao_canonica. Pura e conservadora: casa o texto INTEIRO (âncora nas duas pontas) e só nos cinco tipos de demonstração (BALANCO, BALANCETE, COMBINADO, DF_AUDITADA, DRE). Ambíguo -> NULL: ATIVO/PASSIVO sozinhos, TOTAL DO ATIVO, PASSIVO E PL, TOTAL(IS), LUCRO BRUTO, RESULTADO (menos o financeiro), RECEITA LÍQUIDA, Eliminações do combinado, Balancete Analítico, RESUMO DO BALANCETE, CIRCULANTE sem lado, PROVISÕES, EMPRÉSTIMOS E FINANCIAMENTOS sem prazo, NAO_CLASSIFICAVEL, CONTAS DE RESULTADO - RECEITAS.';

--
-- Name: fn_secao_e_de_resultado(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_secao_e_de_resultado(p_secao text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select coalesce(p_secao, '') in
    ('receita_bruta', 'custos', 'despesas_operacionais', 'resultado_financeiro', 'impostos_lucro');
$$;

--
-- Name: FUNCTION fn_secao_e_de_resultado(p_secao text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_secao_e_de_resultado(p_secao text) IS 'Esta seção canônica é de RESULTADO? Só nelas a pergunta "é recorrente?" faz sentido — conta de balanço não é recorrente nem não recorrente. Medido: rodar a classificação em tudo produziria 3.195 pedidos de revisão contra 527 linhas em que a pergunta cabe, e um analista que recebe 3.195 itens não revisa nenhum (é a lição do Sinal 1 refinado na 0022).';

--
-- Name: fn_sem_codigo_de_conta(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_sem_codigo_de_conta(p_rotulo text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  -- A MESMA definição de `CODIGO_DE_CONTA_NO_INICIO` (portal/src/lib/modelo-institucional.ts).
  select regexp_replace(coalesce(p_rotulo, ''), '^\s*\d+(?:\.\d+){2,}\s*[-–—.)]?\s*', '')
$$;

--
-- Name: FUNCTION fn_sem_codigo_de_conta(p_rotulo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_sem_codigo_de_conta(p_rotulo text) IS 'Tira do INÍCIO do rótulo o código contábil do ERP ("2.3.71 TOTAL" -> "TOTAL"): três grupos numéricos ou mais separados por ponto, separador opcional. A mesma definição de CODIGO_DE_CONTA_NO_INICIO do portal (0202).';

--
-- Name: fn_soma_secao(uuid, text[], text, text, text[], text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_soma_secao(p_documento_versao_id uuid, p_termos_secao text[], p_entidade_coluna text DEFAULT NULL::text, p_periodo_coluna text DEFAULT NULL::text, p_exclui_secao text[] DEFAULT '{}'::text[], p_exclui_chave text[] DEFAULT '{}'::text[]) RETURNS TABLE(soma numeric, n_linhas integer, unidade text)
    LANGUAGE sql STABLE
    AS $$
  with folhas as (
    select ce.valor_num, ce.unidade
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.valor_num is not null
      and ce.secao is not null
      and p_entidade_coluna is distinct from E'\x01'
      and p_periodo_coluna is distinct from E'\x01'
      and (p_entidade_coluna is null
           or fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(p_entidade_coluna))
      and (p_periodo_coluna is null
           or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(p_periodo_coluna))
      and not exists (
        select 1 from unnest(p_termos_secao) as termo
        where fn_normalizar_texto(ce.secao) not like '%' || fn_normalizar_texto(termo) || '%'
      )
      and not exists (
        select 1 from unnest(p_exclui_secao) as termo
        where fn_normalizar_texto(ce.secao) like '%' || fn_normalizar_texto(termo) || '%'
      )
      and not exists (
        select 1 from unnest(p_exclui_chave) as termo
        where fn_normalizar_texto(ce.chave) like '%' || fn_normalizar_texto(termo) || '%'
      )
      and fn_normalizar_texto(ce.chave) <> fn_normalizar_texto(ce.secao)
      and fn_normalizar_texto(ce.chave) not like 'total%'
      and fn_normalizar_texto(ce.chave) not like 'subtotal%'
  )
  select coalesce(sum(valor_num), 0)::numeric,
         count(*)::int,
         (select f2.unidade from folhas f2 where f2.unidade is not null
          group by f2.unidade order by count(*) desc, f2.unidade limit 1)
  from folhas;
$$;

--
-- Name: fn_somar_conceito(uuid, text[], text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_somar_conceito(p_documento_versao_id uuid, p_inclui text[], p_exclui text[] DEFAULT '{}'::text[]) RETURNS TABLE(soma numeric, n_linhas integer)
    LANGUAGE sql STABLE
    AS $$
  select coalesce(sum(ce.valor_num), 0)::numeric, count(*)::int
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and not exists (
      select 1 from unnest(p_inclui) as termo
      where fn_normalizar_texto(ce.chave) not like '%' || fn_normalizar_texto(termo) || '%'
    )
    and not exists (
      select 1 from unnest(p_exclui) as termo
      where fn_normalizar_texto(ce.chave) like '%' || fn_normalizar_texto(termo) || '%'
    );
$$;

--
-- Name: fn_somar_faturamento_ano(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_somar_faturamento_ano(p_documento_versao_id uuid, p_ano4 text, p_ano2 text) RETURNS TABLE(soma numeric, n_linhas integer)
    LANGUAGE sql STABLE
    AS $_$
  with modo as (
    -- O documento traz o ANO na coluna? ('2024', 'jan/2024', '31/12/2024'...) Só então
    -- o ano sai da `periodo_coluna`; colunas de CATEGORIA (Saídas R$, Total R$) não
    -- ancoram ano nenhum e ficam no modo do rótulo, o de sempre (0167).
    select exists (
      select 1 from campo_extraido ce
      where ce.documento_versao_id = p_documento_versao_id
        and ce.periodo_coluna is not null
        and cardinality(fn_anos_texto(ce.periodo_coluna)) > 0
    ) as ano_na_coluna
  ),
  celulas as (
    select ce.chave, ce.periodo_coluna, ce.valor_num,
           -- 0197: a COLUNA é, ela mesma, um mês DESTE ano ("jan/2024", "Janeiro/2023",
           -- "01/2024"). O intervalo "jan/2024 — jan/2025" não casa (ancorado no fim).
           (
             fn_normalizar_texto(ce.periodo_coluna)
               ~ ('^(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)[a-z]*[/. -]+(' || p_ano4 || '|' || p_ano2 || ')$')
             or fn_normalizar_texto(ce.periodo_coluna)
               ~ ('^(0?[1-9]|1[0-2])[/. -]+(' || p_ano4 || '|' || p_ano2 || ')$')
           ) as coluna_e_mes
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
  ),
  candidatos as (
    select ce.chave, ce.periodo_coluna, ce.valor_num,
           case when ce.coluna_e_mes then fn_normalizar_texto(ce.periodo_coluna) else '' end as mes_da_coluna
    from celulas ce cross join modo
    where ce.valor_num is not null
      and (
        case when modo.ano_na_coluna then
          -- 0196: a célula é do ano pedido quando a COLUNA diz que é; o rótulo só
          -- precisa parecer um mês (o "jan/2024 — jan/2025" traz os DOIS anos, e a
          -- linha "Ticket médio…" não é mês nenhum). 0197: ou a coluna É o mês.
          fn_anos_texto(ce.periodo_coluna) && fn_anos_texto(p_ano4)
          and (
            ce.coluna_e_mes
            or position(p_ano4 in fn_normalizar_texto(ce.chave)) > 0
            or fn_normalizar_texto(ce.chave) ~ ('[/. -]' || p_ano2 || '($|[^0-9])')
            or fn_normalizar_texto(ce.chave) ~ '^(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)'
          )
        else
          position(p_ano4 in fn_normalizar_texto(ce.chave)) > 0
          or fn_normalizar_texto(ce.chave) ~ ('[/. -]' || p_ano2 || '($|[^0-9])')
        end
      )
      and fn_normalizar_texto(ce.chave) not like '%total%'
      and fn_normalizar_texto(ce.chave) not like '%acumulad%'
      -- 0197: a forma NORMALIZADA (sem acento) é "medio"/"media". O '%médi%' da 0196 nunca
      -- casava, porque o acento já tinha sido tirado. Por palavra, para não pegar "remédios".
      and fn_normalizar_texto(ce.chave) !~ '(^|[^a-z])(medio|media)s?([^a-z]|$)'
      -- 0196: coluna de PERCENTUAL nunca é dinheiro (a 'Variação %' do relatório de
      -- 3 colunas somava -41,2 a -6,7 ao faturamento de cada mês).
      and position('%' in coalesce(ce.periodo_coluna, '')) = 0
      and fn_normalizar_texto(coalesce(ce.periodo_coluna, '')) not like '%variac%'
  ),
  -- UM VALOR POR MÊS (0167). 0197: com o mês na COLUNA, o mês entra na chave do grupo —
  -- senão as 12 células de chave "Faturamento" virariam uma linha só.
  por_rotulo as (
    select
      chave,
      mes_da_coluna,
      coalesce(
        max(valor_num) filter (where fn_normalizar_texto(periodo_coluna) like '%total%'),
        sum(valor_num)
      ) as valor
    from candidatos
    group by chave, mes_da_coluna
  )
  select coalesce(sum(valor), 0)::numeric,
         count(distinct case when mes_da_coluna <> '' then mes_da_coluna else chave end)::int
  from por_rotulo;
$_$;

--
-- Name: FUNCTION fn_somar_faturamento_ano(p_documento_versao_id uuid, p_ano4 text, p_ano2 text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_somar_faturamento_ano(p_documento_versao_id uuid, p_ano4 text, p_ano2 text) IS 'Soma o faturamento de um ano, UM VALOR POR MÊS. 0167: a categoria mora em periodo_coluna (Saídas/Serviços/Outros/Total) e a chave repete o mês nas quatro — com coluna de total, ela manda. 0196: quando as colunas do documento são ANOS (2024, 2025), o ano sai da COLUNA; coluna de percentual nunca entra na soma. 0197: coluna "mês/ano" do ano pedido conta como mês mesmo com rótulo genérico ("Faturamento"); intervalo de dois anos numa célula não é atribuído; "Ticket médio"/média ficam fora também no modo por rótulo.';

--
-- Name: fn_sugerir_perguntas(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_sugerir_perguntas(p_caso_id uuid) RETURNS TABLE(codigo text, titulo text, prioridade integer, entidade text, entidade_id uuid, pergunta text, motivo text, risco text, impacto text, gatilho text, fonte text, ja_enviada boolean)
    LANGUAGE sql STABLE
    AS $$
  with tem_conteudo as (
    select exists (
      select 1
      from documento d
      join campo_extraido ce on ce.documento_versao_id = fn_versao_com_extracao(d.id)
      where d.caso_id = p_caso_id and ce.valor_num is not null
    ) as ok
  ),
  -- QUAIS CÓDIGOS DISPARAM, E PARA QUEM (0120/0119): a espécie `sempre` vale
  -- para o caso; as ancoradas disparam uma vez por ENTIDADE que não satisfaz,
  -- espelhando a pendência `linha_exigida_ausente`.
  disparos as (
    select pc.codigo, null::text as entidade, null::uuid as entidade_id
    from pergunta_catalogo pc
    where pc.ativo and pc.gatilho_especie = 'sempre'
      and (select ok from tem_conteudo)
    union
    select distinct pc.codigo, x.entidade, x.entidade_id
    from pergunta_catalogo pc
    join fn_exigencias_do_caso(p_caso_id) x
      on x.tipo_taxonomia = pc.gatilho_tipo_taxonomia
     and x.conceito = pc.gatilho_conceito
    where pc.ativo
      and ((pc.gatilho_especie = 'exigencia_ausente' and not x.satisfeita)
        or (pc.gatilho_especie = 'linha_presente' and x.satisfeita))
  ),
  -- {saldo_mutuos}: 0187 — o saldo da relação de mútuos como a RELAÇÃO o diz
  -- (linha de total geral, senão soma dos itens, na coluna do exercício mais
  -- recente), ou "(não foi possível apurar…)" com o motivo. Era a soma das
  -- linhas cujo rótulo casava o léxico MUTUOS/saldo_de_mutuo, e no arranjo
  -- real (o rótulo é o par de empresas) nada casava: a pergunta ao cliente
  -- dizia "(não localizado)" sobre um saldo que está no documento.
  saldo_mutuos as (
    select fn_saldo_mutuos_texto(p_caso_id) as txt
  )
  select pc.codigo, pc.titulo, pc.prioridade, di.entidade, di.entidade_id,
         -- A ENTIDADE ENTRA COMO PREFIXO, e não reescrevendo o texto da entrega.
         case when di.entidade is not null then 'Sobre a ' || di.entidade || ': ' else '' end ||
         replace(replace(replace(pc.pergunta,
           -- 0122: o período vai POR EXTENSO. Era a `referencia` crua, e o que
           -- chegava ao cliente era "Na DRE de 24,25" / "de L36M" / "de 12M25".
           '{data_base}',    coalesce(per.por_extenso, '(período não informado)')),
           '{ano}',          coalesce(per.por_extenso, '(período não informado)')),
           '{saldo_mutuos}', coalesce(sm.txt, '(não localizado)')) as pergunta,
         pc.motivo, pc.risco, pc.impacto,
         case when pc.gatilho_especie = 'sempre' then 'sempre'
              else pc.gatilho_especie || ':' || pc.gatilho_tipo_taxonomia || ':' || pc.gatilho_conceito
         end as gatilho,
         pc.fonte,
         exists (
           select 1 from caso_pergunta cp
           where cp.caso_id = p_caso_id and cp.pergunta_codigo = pc.codigo and cp.acao = 'enviada'
             and cp.entidade_id is not distinct from di.entidade_id
         ) as ja_enviada
  from pergunta_catalogo pc
  join disparos di on di.codigo = pc.codigo
  cross join saldo_mutuos sm
  -- O PERÍODO MAIS RECENTE É POR ANO, NÃO POR ORDEM ALFABÉTICA (0120) — e desde
  -- a 0122 a janela móvel não finge um ano para vencer essa escolha: `L36M`
  -- devolvia 2036 e ganhava de um 2025 real.
  left join lateral (
    select fn_periodo_por_extenso(p2.tipo, p2.referencia) as por_extenso
    from documento d2
    join periodo p2 on p2.id = d2.periodo_id
    where d2.caso_id = p_caso_id
      and (pc.gatilho_tipo_taxonomia is null or d2.tipo_taxonomia = pc.gatilho_tipo_taxonomia)
      -- O PERÍODO É O DA EMPRESA DE QUE A PERGUNTA FALA (0122). A sugestão é
      -- por (pergunta × entidade) desde a 0119, e o período não acompanhava:
      -- num grupo em que a DRE da Indústria cobre 2023–2025 e a da Comercial
      -- só 2024–2025, a pergunta sobre a Comercial saía dizendo "Na DRE de
      -- 2023 a 2025" — um exercício que o documento DELA não tem. Quem recebe
      -- não reconhece o próprio documento na pergunta.
      and (di.entidade_id is null or d2.entidade_id = di.entidade_id)
    order by coalesce((select max(a) from unnest(fn_anos_do_periodo(p2.referencia)) a), -1) desc,
             -- EMPATE NO ANO MAIS RECENTE: ganha o período MAIS ESPECÍFICO. Um
             -- caso com "2025" e "24,25" tem os dois terminando em 2025, e
             -- perguntar "no faturamento de 2025" é mais preciso que "de 2024 e
             -- 2025". Sem este critério o desempate era alfabético — e o
             -- alfabeto punha o comparativo na frente.
             cardinality(coalesce(fn_anos_do_periodo(p2.referencia), '{}'::int[])) asc,
             p2.referencia desc
    limit 1
  ) per on true
  order by pc.prioridade, pc.codigo, di.entidade nulls first;
$$;

--
-- Name: FUNCTION fn_sugerir_perguntas(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_sugerir_perguntas(p_caso_id uuid) IS 'Perguntas ao cliente SUGERIDAS para o caso (0120): exigencia_ausente/linha_presente avaliadas sobre fn_exigencias_do_caso (a mesma fonte da pendência linha_exigida_ausente — as duas faces nunca divergem); sempre = caso com conteúdo. Marcadores {data_base}/{ano} saem por EXTENSO e {saldo_mutuos} em reais (0122); desconhecidos ficam visíveis. Nada é gravado ao sugerir; ja_enviada informa, não filtra. Uma sugestão por (pergunta × entidade que não satisfaz).';

--
-- Name: fn_tem_palavra_longa(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_tem_palavra_longa(p_chave text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select exists (
    select 1
    from unnest(regexp_split_to_array(
      regexp_replace(fn_normalizar_texto(p_chave), '[^a-z0-9]+', ' ', 'g'), '\s+')) as w
    where length(w) >= 4
  );
$$;

--
-- Name: FUNCTION fn_tem_palavra_longa(p_chave text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_tem_palavra_longa(p_chave text) IS 'O rótulo tem ao menos uma palavra de 4+ letras? Metade da regra de fn_rotulo_contido: sem isto, "de" contido em qualquer coisa marcaria sobreposição em toda linha.';

--
-- Name: fn_teto_ressalvas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_teto_ressalvas() RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$ select 3; $$;

--
-- Name: FUNCTION fn_teto_ressalvas(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_teto_ressalvas() IS 'Teto de pendências aceitas com ressalva ATIVAS por caso. 3 é o valor que o dono confirmou em Arquitetura do Sistema/2 Especificação/f0/04 ("Teto de ressalvas confirmado em 3") — não é palpite deste código.';

--
-- Name: fn_texto_nomeia_mutuo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_texto_nomeia_mutuo(p_texto text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select fn_normalizar_texto(coalesce(p_texto, '')) like '%mutuo%';
$$;

--
-- Name: FUNCTION fn_texto_nomeia_mutuo(p_texto text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_texto_nomeia_mutuo(p_texto text) IS '0123: a natureza "mútuo" nomeada NESTE texto. Usada no rótulo (degrau 1) e na seção (degrau 2), com precedência do rótulo — nunca nos dois de uma vez.';

--
-- Name: fn_tokens_estruturais(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_tokens_estruturais(p_chave text) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$
  select coalesce((
    select array_agg(distinct w order by w)
    from unnest(
      regexp_split_to_array(
        regexp_replace(fn_normalizar_texto(p_chave), '[^a-z0-9]+', ' ', 'g'),
        '\s+')
    ) as w
    where w <> ''
      and w not in ('total','totais','geral','gerais','soma','somatorio','subtotal',
                    'de','do','da','dos','das','e','o','a','os','as','em','no','na',
                    'liquido','liquida','consolidado','consolidada','combinado','combinada')
  ), array[]::text[]);
$$;

--
-- Name: FUNCTION fn_tokens_estruturais(p_chave text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_tokens_estruturais(p_chave text) IS 'Palavras estruturais de um rótulo (sem ligação, ruído de rodapé e a palavra "total"), ordenadas e sem repetição. Extraída de fn_rotulo_estrutural na 0102 para ser calculada UMA vez por rótulo: fn_papel_linha comparava nove grupos e pagava nove tokenizações iguais.';

--
-- Name: fn_trg_auto_promover_dial(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_trg_auto_promover_dial() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_r jsonb;
begin
  if pg_trigger_depth() > 1 then
    return null;
  end if;

  begin
    v_r := fn_dial_auto_promover();
    if coalesce((v_r->>'quantos')::int, 0) > 0 then
      raise notice '0137: promoção automática do dial — %', v_r->'promovidos';
    end if;
  exception when others then
    raise notice '0137: a promoção automática falhou e foi ignorada (a decisão que a disparou está '
                 'gravada). Erro: %', sqlerrm;
  end;

  return null;
end;
$$;

--
-- Name: FUNCTION fn_trg_auto_promover_dial(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_trg_auto_promover_dial() IS 'Gatilho da promoção automática (0137): toda decisão humana nova pode ter completado o critério do veredito de produção. NUNCA derruba a transação de quem o disparou — falha vira NOTICE, porque o analista não pode perder a rejeição de uma pendência por causa do dial.';

--
-- Name: fn_trg_entidade_ambigua(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_trg_entidade_ambigua() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if new.entidade_id is not null then
    perform fn_pendencia_entidade_ambigua(new.caso_id, new.id, new.entidade_id);
  end if;
  return null;
end;
$$;

--
-- Name: FUNCTION fn_trg_entidade_ambigua(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_trg_entidade_ambigua() IS 'Chama fn_pendencia_entidade_ambigua quando um documento ganha entidade (0153). Existe porque checagem instalada e sem chamador é indistinguível de checagem que não achou nada.';

--
-- Name: fn_trg_entidade_controlador_soma_maxima(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_trg_entidade_controlador_soma_maxima() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_soma  numeric;
  v_razao text;
begin
  select coalesce(sum(percentual), 0) into v_soma
    from entidade_controlador
   where entidade_id = NEW.entidade_id
     and percentual is not null;

  if v_soma > 100 then
    select razao_social into v_razao from entidade where id = NEW.entidade_id;
    raise exception 'a soma dos percentuais CONHECIDOS de "%" passaria de 100%% (chegaria a %) — '
                     'conhecimento parcial é normal aqui (nem toda entidade tem todos os sócios '
                     'medidos), mas a soma do que É CONHECIDO nunca pode superar o todo',
      coalesce(v_razao, NEW.entidade_id::text), v_soma;
  end if;

  return NEW;
end;
$$;

--
-- Name: FUNCTION fn_trg_entidade_controlador_soma_maxima(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_trg_entidade_controlador_soma_maxima() IS '0182: a guarda de soma — nunca deixa a soma dos percentuais NÃO-NULOS de uma entidade passar de 100. NÃO exige que some 100 (regra 1 do CLAUDE.md pelo avesso — ver cabeçalho): conhecimento parcial (4 de 8 entidades do mandato real sem estrutura lida) é o estado normal, e exigir soma exata puniria isso. É a MEDIÇÃO NÃO-VAZIA (a) desta migration — sem o trigger abaixo chamando esta função, uma terceira participação que ultrapassasse 100% seria gravada em silêncio.';

--
-- Name: fn_trg_entidade_forma_de_controle_tem_vinculo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_trg_entidade_forma_de_controle_tem_vinculo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_tem_vinculo boolean;
begin
  select exists(select 1 from entidade_controlador where entidade_id = NEW.id) into v_tem_vinculo;

  if not v_tem_vinculo then
    raise exception 'entidade "%" não pode ser declarada controle_comum sem NENHUM vínculo '
                     'registrado em entidade_controlador — registre os controladores primeiro '
                     '(fn_controlador_registrar/fn_entidade_definir_controlador, 0182)',
      coalesce(NEW.razao_social, NEW.id::text);
  end if;

  return NEW;
end;
$$;

--
-- Name: FUNCTION fn_trg_entidade_forma_de_controle_tem_vinculo(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_trg_entidade_forma_de_controle_tem_vinculo() IS '0183: a guarda do vínculo — recusa declarar `controle_comum` sem NENHUMA linha em `entidade_controlador` para a entidade. É a MEDIÇÃO NÃO-VAZIA (b) desta migration — sem o trigger abaixo chamando esta função, `controle_comum` seria gravado em silêncio mesmo sem nenhum controlador registrado. LIMITAÇÃO DELIBERADA: prova o vínculo na declaração, não reage a DELETE posterior em entidade_controlador (ver cabeçalho da migration 0183).';

--
-- Name: fn_trg_instalacao_cobertura_nao_regride(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_trg_instalacao_cobertura_nao_regride() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  -- `ate_migration` é texto de 4 dígitos zero-padded, então a ordem lexicográfica coincide com a
  -- numérica ('0183' < '0188'). Quando quem chega é MAIS ANTIGO que o que está gravado, a linha
  -- inteira fica como estava: só o marcador não bastaria, porque a `observacao` ao lado passaria a
  -- descrever outra migration e a linha diria "cobertura até a 0188" com o texto da 0183.
  if NEW.ate_migration < OLD.ate_migration then
    -- Sem aviso, o `UPDATE 1` desta linha pareceria ter funcionado — um rollback deliberado do
    -- marcador ficaria indistinguível de um que pegou (achado da revisão de 23/09/2026).
    raise notice 'instalacao_cobertura: ate_migration % ignorado — o marcador já está em % e não regride',
      NEW.ate_migration, OLD.ate_migration;
    NEW.ate_migration := greatest(OLD.ate_migration, NEW.ate_migration);
    NEW.observacao    := OLD.observacao;
    NEW.revisado_em   := OLD.revisado_em;
  end if;
  return NEW;
end;
$$;

--
-- Name: FUNCTION fn_trg_instalacao_cobertura_nao_regride(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_trg_instalacao_cobertura_nao_regride() IS '0183: o marcador de cobertura da sonda nunca regride. Motivo medido: a 0182, aplicada em produção DEPOIS da 0188 (sessões paralelas), escreveu ate_migration = ''0182'' por cima de ''0188'' — 39 migrations terminam com esse update incondicional, e a tabela aceitava o valor menor sem erro. Corrigido na tabela, não nas migrations.';

--
-- Name: fn_unidade_predominante(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_unidade_predominante(p_documento_versao_id uuid) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select ce.unidade
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.unidade is not null
    and length(trim(ce.unidade)) > 0
  group by ce.unidade
  order by count(*) desc, ce.unidade
  limit 1;
$$;

--
-- Name: FUNCTION fn_unidade_predominante(p_documento_versao_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_unidade_predominante(p_documento_versao_id uuid) IS 'Escala predominante (unidade) das linhas extraídas de uma versão de documento; null quando nenhuma linha declara escala.';

--
-- Name: fn_upsert_caso(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_upsert_caso(p_nome text, p_ator text DEFAULT 'sistema:n8n'::text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_id uuid;
begin
  if p_ator not in ('sistema:n8n', 'portal:navegador') then
    raise exception 'fn_upsert_caso: ator % fora da lista (sistema:n8n, portal:navegador)', p_ator;
  end if;
  select id into v_id from caso where nome = p_nome limit 1;
  if v_id is null then
    insert into caso (nome) values (p_nome) returning id into v_id;
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_ator, 'caso_criado', 'caso:'||v_id, jsonb_build_object('nome', p_nome));
  end if;
  return v_id;
end;
$$;

--
-- Name: fn_upsert_entidade(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_upsert_entidade(p_caso_id uuid, p_nome text, p_cnpj text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_id         uuid;
  v_n          int;
  v_candidatos text;
  v_nomes      text[];
  v_cnpj       text := fn_cnpj_canonico(p_cnpj);
  v_nome_atual text;
  v_e_balcao   boolean;
  v_mesmo_nome_do_balcao boolean;
begin
  -- 0153: no empate, não escolhe. (E o requisito de sonda `entidade_ambigua_nao_decide`
  -- tem o literal "0153" como MARCADOR DE CORPO — tirar esta linha derruba a sonda
  -- sem mudar comportamento nenhum. Achado ao rodar a suíte desta fatia.)
  if p_nome is null or length(trim(p_nome)) = 0 then return null; end if;

  -- (0) 0169: CNPJ IGUAL É A MESMA EMPRESA, e ele não pergunta o nome. É esta
  -- regra que funde as variantes truncadas em QUALQUER ordem de chegada —
  -- a 0168 só conseguia quando a ordem ajudava.
  if v_cnpj is not null then
    -- `order by` sem efeito prático desde a 0169: o índice único
    -- `entidade_caso_cnpj_unico (caso_id, cnpj)` garante NO MÁXIMO uma linha.
    -- Fica como documentação da invariante, não como desempate de verdade.
    select e.id, e.razao_social into v_id, v_nome_atual
    from entidade e
    where e.caso_id = p_caso_id and fn_cnpj_canonico(e.cnpj) = v_cnpj
    order by length(e.razao_social) desc, e.razao_social
    limit 1;

    if v_id is not null then
      v_e_balcao := fn_entidade_e_balcao_ambiguo(p_caso_id, v_id);

      -- 0177 (ALTO): o nome que chega pode ser o PRÓPRIO nome do balcão —
      -- um SEGUNDO documento do MESMO balcão, chegando pela classificação,
      -- com o CNPJ que ele já aprendeu. A 0176 tratava QUALQUER chegada
      -- contra um balcão como colisão externa, mesmo quando é o balcão
      -- recebendo mais um documento seu: a pendência abria dizendo que o
      -- nome "chegou... sem ser, ela própria, um balcão ambíguo" e que "o
      -- sistema NÃO... atribuiu este documento/entidade a ele" — as DUAS
      -- afirmações falsas, porque o nome que chegou É o do balcão e o
      -- documento SIM termina atribuído a ele pelo ramo (1) de casamento
      -- exato por nome, alguns passos abaixo. MEDIDO nesta sessão: uma
      -- pendência de colisão nascia (0→1) mesmo quando o documento novo era
      -- só mais um do MESMO balcão.
      v_mesmo_nome_do_balcao := v_e_balcao
        and fn_entidade_canonica(v_nome_atual) is not distinct from fn_entidade_canonica(trim(p_nome));

      -- MEDIDO (0176): um documento novo de OUTRA empresa (mesmo CNPJ de
      -- rodapé de contador) virava absorvido pelo balcão sem nunca ganhar
      -- linha própria — entidades no caso ficavam em 3 em vez de virarem 4.
      -- Trata o CNPJ como se nunca tivesse chegado (`v_cnpj := null`) para o
      -- resto desta chamada: sem isso, o `insert` do fim desta função
      -- tentaria gravar este MESMO CNPJ numa entidade nova e violaria
      -- `entidade_caso_cnpj_unico` — e, pior, atribuiria à empresa nova um
      -- CNPJ que pode não ser dela.
      if v_e_balcao and not v_mesmo_nome_do_balcao then
        perform fn_pendencia_cnpj_colide_balcao(p_caso_id, v_id, v_cnpj, trim(p_nome), null);
        v_id := null;
        v_cnpj := null;
      else
        -- O EVENTO DE CASAMENTO fica na forma CANÔNICA: ele existe para registrar
        -- que o CNPJ respondeu um nome MATERIALMENTE diferente do gravado, e
        -- diferença só de sufixo/pontuação não é isso. Quando é o PRÓPRIO
        -- balcão (v_mesmo_nome_do_balcao), esta condição já é falsa por
        -- construção — nenhum evento de "casamento" nasce, porque não houve
        -- casamento: é o mesmo nome de sempre.
        if fn_entidade_canonica(v_nome_atual) is distinct from fn_entidade_canonica(trim(p_nome)) then
          insert into evento_auditoria (ator, acao, entidade_ref, depois)
          values ('sistema:entidade', 'entidade_cnpj_casou', 'entidade:' || v_id,
                  jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                                     'nome_mantido_antes_do_renomeio', v_nome_atual,
                                     'cnpj', v_cnpj,
                                     'pode_renomear', fn_pode_renomear_por_cnpj(v_nome_atual, trim(p_nome)),
                                     'porque', 'o CNPJ é o mesmo — o nome não foi consultado'));
        end if;

        -- 0173: O RENOMEIO VIROU FUNÇÃO PRÓPRIA, e os DOIS caminhos a chamam.
        -- Antes ele morava aqui dentro, e só este caminho (a classificação) o
        -- executava — o diagnóstico, que é o único que roda para TODO documento,
        -- gravava o CNPJ e ia embora sem renomear. Medido: identidade fiscal em
        -- 100% do lote e renomeio em ~50%.
        perform fn_entidade_talvez_renomear(p_caso_id, v_id, trim(p_nome), v_cnpj);

        return v_id;
      end if;
    end if;
  end if;

  -- (1) exato pela forma canônica — não há o que desempatar.
  select c.entidade_id into v_id
  from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c
  where c.exata
  order by c.razao_social
  limit 1;
  if v_id is not null then
    -- 0174: usa o RETORNO, não `perform`. Sem isto, quando `fn_entidade_aprender_cnpj`
    -- funde esta entidade numa OUTRA que já tinha o mesmo CNPJ (a corrida entre
    -- o ramo (0) acima e este ramo, ou a mesma situação chegando pela porta do
    -- diagnóstico — ver o cabeçalho da função), `v_id` ficaria apontando para
    -- uma linha DELETADA, e o `insert into documento` em `fn_registrar_documento`
    -- quebraria a FK `documento.entidade_id → entidade.id`.
    v_id := fn_entidade_aprender_cnpj(v_id, v_cnpj);
    return v_id;
  end if;

  -- (2)/(3) quantos APROXIMADOS existem?
  select count(*), string_agg(c.razao_social, ' × ' order by c.razao_social),
         array_agg(c.razao_social)
    into v_n, v_candidatos, v_nomes
  from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c;

  -- APRENDER SÓ NO CASAMENTO EXATO, e este `return` SEM `aprender` é a
  -- correção mais importante que a revisão desta fatia trouxe. Este ramo é o
  -- casamento FROUXO (subsequência de prefixos) — é ele que faz "Metalúrgica"
  -- ser absorvido por "VERTENTES METALÚRGICA LTDA.". Deixá-lo GRAVAR o CNPJ
  -- transformaria um palpite de nome em identidade fiscal permanente:
  -- "Canastra" com o CNPJ do GRUPO CANASTRA (a holding, impressa no
  -- consolidado) seria absorvido pela subsidiária e escreveria nela o CNPJ da
  -- holding — e daí em diante TODO documento da holding cairia na subsidiária
  -- pelo ramo (0), sem olhar nome. A própria 0168 já diz que o nome que CHEGA é
  -- o que pode estar contaminado; o CNPJ do mesmo documento não pode ser
  -- promovido a identidade por um casamento que o nome só aproximou.
  if v_n = 1 then
    select c.entidade_id into v_id
    from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c limit 1;
    return v_id;
  end if;

  -- (3b) 0168: dois ou mais candidatos que casam ENTRE SI não são ambiguidade.
  if v_n > 1 and fn_entidades_sao_um_grupo(v_nomes || trim(p_nome)) then
    select c.entidade_id into v_id
    from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c
    order by length(c.razao_social) desc, c.razao_social
    limit 1;

    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_alias_fundido', 'entidade:' || v_id,
            jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                               'candidatos', v_candidatos, 'quantos', v_n,
                               'porque', 'os candidatos casam todos entre si — é um nome só, '
                                      || 'truncado de jeitos diferentes pela fonte'));
    -- Sem `aprender` pelo mesmo motivo do ramo acima, e aqui é PIOR: o nome que
    -- chega é justamente o truncado, o que pode trazer o endereço colado.
    return v_id;
  end if;

  insert into entidade (caso_id, razao_social, cnpj) values (p_caso_id, trim(p_nome), v_cnpj)
    returning id into v_id;

  -- NASCER COM CNPJ MERECE O MESMO RASTRO QUE APRENDER DEPOIS. É uma afirmação
  -- de identidade tirada de UM documento, que nunca mais é revisitada e que
  -- passa a mandar sobre todo nome — o mínimo honesto é ela aparecer no log.
  if v_cnpj is not null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_cnpj_aprendido', 'entidade:' || v_id,
            jsonb_build_object('cnpj', v_cnpj, 'como', 'nasceu com ele'));
  end if;

  if v_n > 1 then
    -- A AMBIGUIDADE É REGISTRADA AQUI e virada em pendência por quem tem o
    -- documento na mão. Esta função não conhece documento.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_ambigua', 'entidade:' || v_id,
            jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                               'candidatos', v_candidatos, 'quantos', v_n,
                               -- O CNPJ VAI JUNTO, e a revisão achou ele faltando:
                               -- `fn_pendencia_entidade_ambigua` (0153) monta a descrição
                               -- a partir deste payload, e o analista lia "casa com mais de
                               -- uma empresa: A × B" sem o único número que decide — a
                               -- regra 1 pelo avesso (a nota existe e cala o dado).
                               'cnpj', v_cnpj));
  end if;

  -- 0178: NEM CNPJ NEM CANDIDATO NENHUM CASOU, e o nome tem cara de
  -- título/coluna/aba/arquivo — a CONJUNÇÃO que separa isso do balcão
  -- ambíguo real (que também chega sem CNPJ por este mesmo `insert`, mas com
  -- nome vindo do CONTEÚDO do documento, não de um título). Não recusa o
  -- `insert` (o documento não pode ficar sem entidade — perderia
  -- proveniência) e não funde com nada — só marca para revisão humana.
  -- MEDIDO (`Supabase/test/entidade_titulo_suspeito.test.sql`): os 4 nomes
  -- reais do AMO teste 00 (Empresas, Vencidos, Status Extratos, Controle
  -- Extratos Ofx) batem aqui; um nome real de empresa do mesmo mandato,
  -- AMOBELEZA COMERCIO DIGITAL E OFFLINE LTDA (com CNPJ), não passa por este
  -- `if` porque `v_cnpj` não é nulo — nem chega a ser avaliado contra o léxico.
  if v_cnpj is null and fn_entidade_nome_parece_titulo_ou_arquivo(trim(p_nome)) then
    perform fn_pendencia_entidade_nome_suspeito(p_caso_id, v_id, trim(p_nome));
  end if;

  -- 0179: TODA entidade nasce aqui com papel_no_grupo NULL por construção (a
  -- coluna não é passada no insert acima) — marca a ausência, incondicional,
  -- porque não existe sinal automático para decidir o papel (fatia 1.3;
  -- roadmap, seção 12.1: sem participacao/hierarquia modelada). Vale tanto
  -- para a entidade real quanto para a suspeita de título/arquivo logo acima
  -- e para o balcão ambíguo (0153/0162, 0175-0177) — são sinais diferentes, e
  -- é honesto os dois estarem abertos ao mesmo tempo.
  perform fn_pendencia_papel_no_grupo_indefinido(p_caso_id, v_id, trim(p_nome));

  -- 0183: TODA entidade nasce aqui com forma_de_controle 'indefinido' pelo DEFAULT da coluna
  -- (item 1 desta migration) — marca a ausência, incondicional, mesmo espírito da chamada acima
  -- (0179): é honesto uma entidade estar, ao mesmo tempo, sem papel no grupo E sem forma de
  -- controle declarada — são sinais diferentes.
  perform fn_pendencia_forma_de_controle_indefinida(p_caso_id, v_id, trim(p_nome));

  return v_id;
end;
$$;

--
-- Name: FUNCTION fn_upsert_entidade(p_caso_id uuid, p_nome text, p_cnpj text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_upsert_entidade(p_caso_id uuid, p_nome text, p_cnpj text) IS 'Acha ou cria a entidade do caso (0030), sem ESCOLHER no empate (0153), com o nome truncado fundido no mais completo (0168), com o CNPJ como identidade (0169) e adotando a variante mais completa ao fundir por CNPJ (0171/0173 — a decisão mora em fn_entidade_talvez_renomear, chamada dos dois caminhos). 0174: o ramo (1) usa o RETORNO de fn_entidade_aprender_cnpj. 0176: o ramo (0) não devolve mais um balcão ambíguo (0162/0175) direto para OUTRA empresa — trata o CNPJ como ausente e registra a colisão (fn_pendencia_cnpj_colide_balcao). 0177: essa colisão só é registrada quando quem chegou NÃO é, ela própria, o mesmo balcão — um segundo documento do PRÓPRIO balcão (mesmo nome, mesmo CNPJ) não abre pendência falsa; segue pelo caminho normal. 0178: uma entidade NOVA (nenhum candidato casou), sem CNPJ, com nome que bate fn_entidade_nome_parece_titulo_ou_arquivo, ainda é criada (documento não perde dona) mas ganha pendência entidade_incorreta/entidade_nome_suspeito para revisão humana — nunca fundida nem apagada. 0179: toda entidade nova (real, suspeita ou balcão) ganha também a pendência papel_no_grupo_indefinido, incondicional — não há sinal automático para classificar o papel no grupo. 0183: toda entidade nova ganha também a pendência forma_de_controle_indefinida, incondicional — não há sinal automático para declarar a forma de controle.';

--
-- Name: fn_upsert_periodo(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_upsert_periodo(p_caso_id uuid, p_tipo text, p_ref text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_id  uuid;
  v_can text;
begin
  if p_ref is null or length(trim(p_ref)) = 0 then return null; end if;
  v_can := fn_periodo_canonico(coalesce(p_tipo, 'outro'), p_ref);

  -- Casa por forma CANÔNICA: '2025' e '12M25' são o mesmo exercício e não podem
  -- virar duas linhas. A 0022 já canonicalizava na comparação; aqui é na ESCRITA,
  -- que é o que faz o dashboard, o checklist e o export verem um período só.
  select p.id into v_id
  from periodo p
  where p.caso_id = p_caso_id
    and fn_periodo_canonico(p.tipo, p.referencia) = v_can
  order by p.referencia
  limit 1;

  if v_id is null then
    insert into periodo (caso_id, tipo, referencia)
      values (p_caso_id, coalesce(p_tipo, 'outro'), trim(p_ref))
      returning id into v_id;
  end if;
  return v_id;
end;
$$;

--
-- Name: FUNCTION fn_upsert_periodo(p_caso_id uuid, p_tipo text, p_ref text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_upsert_periodo(p_caso_id uuid, p_tipo text, p_ref text) IS 'Acha ou cria o período casando pela forma canônica (0030). Impede que 2025 e 12M25 virem dois exercícios.';

--
-- Name: campo_extraido; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campo_extraido (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    documento_versao_id uuid NOT NULL,
    chave text NOT NULL,
    valor_texto text,
    valor_num numeric,
    unidade text,
    confianca numeric,
    origem_pagina integer,
    origem_linha text,
    nivel_autonomia public.nivel_autonomia DEFAULT 'N0'::public.nivel_autonomia NOT NULL,
    revisado_por text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    secao text,
    status_aceite text DEFAULT 'pendente'::text NOT NULL,
    aceito_por text,
    aceito_em timestamp with time zone,
    secao_canonica text,
    entidade_coluna text,
    periodo_coluna text,
    ordem integer,
    moeda text,
    origem_valor text DEFAULT 'extracao'::text NOT NULL,
    secao_canonica_inferida boolean DEFAULT false NOT NULL,
    CONSTRAINT campo_extraido_origem_valor_check CHECK ((origem_valor = ANY (ARRAY['extracao'::text, 'transcricao_humana'::text]))),
    CONSTRAINT campo_extraido_status_aceite_check CHECK ((status_aceite = ANY (ARRAY['pendente'::text, 'aceito'::text, 'com_ressalva'::text])))
);

--
-- Name: COLUMN campo_extraido.secao; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.secao IS 'Agrupador de planilha extraído pela IA (espelha a estrutura do documento original). Livre, não é enum.';

--
-- Name: COLUMN campo_extraido.status_aceite; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.status_aceite IS 'Portão 2 (E4, Arquitetura do Sistema/2 Especificação/f0/07): pendente = sugestão N0/N1, não é fato; aceito = decisao humana ligada, entra no export como fato; com_ressalva = aceito com ressalva.';

--
-- Name: COLUMN campo_extraido.secao_canonica; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.secao_canonica IS 'Seção canônica SUGERIDA pela IA na extração (E2), pelo significado contábil da conta. Chaves = as de statement-templates.ts (ativo_circulante, dre custos, atividades_investimento, etc.). N1/advisory: usada só como fallback do classificador determinístico do export; nunca vira fato sem aceite humano.';

--
-- Name: COLUMN campo_extraido.entidade_coluna; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.entidade_coluna IS 'Nome da coluna/entidade a que esta linha pertence, quando o documento traz várias entidades lado a lado na mesma tabela (ex.: balanço combinado "Empresa A | Empresa B | Total"). Null quando o documento é de uma entidade só (caso comum) — não confundir com documento.entidade_id, que segue sendo a entidade PRINCIPAL do documento como um todo.';

--
-- Name: COLUMN campo_extraido.periodo_coluna; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.periodo_coluna IS 'Rótulo da coluna de período a que esta linha pertence, quando o documento é comparativo e traz vários períodos lado a lado na mesma tabela (ex.: "2023" e "2024"). Null quando o documento é de período único (caso comum) — aí o período vem de documento.periodo_id. Ortogonal a entidade_coluna: um documento pode ter as duas dimensões (várias empresas E vários anos).';

--
-- Name: COLUMN campo_extraido.ordem; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.ordem IS 'Posição 0-based da linha no documento, como o arquivo a imprime. Permite reconhecer subtotal impresso acima dos seus componentes (teste v28). null em extração feita antes da 0027.';

--
-- Name: COLUMN campo_extraido.moeda; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.moeda IS 'Moeda ISO da linha (BRL/USD/EUR/…), herdada do documento pela extração; null = desconhecida, NUNCA presumida. Separada de `unidade`, que é a ESCALA (milhar/unidade). Somar linhas de moedas diferentes é erro pelo câmbio inteiro — ver o cabeçalho da 0035.';

--
-- Name: COLUMN campo_extraido.origem_valor; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.origem_valor IS 'De onde veio o número: extracao (a IA leu o arquivo) ou transcricao_humana (uma pessoa digitou, porque o arquivo não se lê — fechamento #2 do Arquitetura do Sistema/1 Visão e Doutrina/01). Existe porque sem ela a primeira transcrição contaminaria fn_golden_campos: linha digitada por humano bate com o rótulo do golden set quase sempre, e o acerto sairia creditado à EXTRAÇÃO. Default extracao: nenhuma linha existente muda de significado.';

--
-- Name: COLUMN campo_extraido.secao_canonica_inferida; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.secao_canonica_inferida IS '0203: true = a secao_canonica NÃO veio da IA; foi inferida do texto da seção bruta (campo_extraido.secao) por fn_secao_canonica_da_secao_bruta, na gravação ou no backfill. false = a IA deu (ou a linha segue sem seção). A inferência é conservadora e determinística; o que ela não reconhece fica NULL.';

--
-- Name: fn_valor_conceito(uuid, text[], text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_valor_conceito(p_documento_versao_id uuid, p_inclui text[], p_exclui text[] DEFAULT '{}'::text[]) RETURNS public.campo_extraido
    LANGUAGE sql STABLE
    AS $$
  select ce.*
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and not exists (
      select 1 from unnest(p_inclui) as termo
      where fn_normalizar_texto(ce.chave) not like '%' || fn_normalizar_texto(termo) || '%'
    )
    and not exists (
      select 1 from unnest(p_exclui) as termo
      where fn_normalizar_texto(ce.chave) like '%' || fn_normalizar_texto(termo) || '%'
    )
  order by coalesce(ce.confianca, 0) desc, length(ce.chave) asc
  limit 1;
$$;

--
-- Name: fn_valor_conceito_col(uuid, text[], text[], text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_valor_conceito_col(p_documento_versao_id uuid, p_inclui text[], p_exclui text[] DEFAULT '{}'::text[], p_entidade_coluna text DEFAULT NULL::text, p_periodo_coluna text DEFAULT NULL::text) RETURNS public.campo_extraido
    LANGUAGE sql STABLE
    AS $$
  select ce.*
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and p_entidade_coluna is distinct from E'\x01'
    and p_periodo_coluna is distinct from E'\x01'
    and (p_entidade_coluna is null
         or fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(p_entidade_coluna))
    and (p_periodo_coluna is null
         or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(p_periodo_coluna))
    and not exists (
      select 1 from unnest(p_inclui) as termo
      where fn_normalizar_texto(ce.chave) not like '%' || fn_normalizar_texto(termo) || '%'
    )
    and not exists (
      select 1 from unnest(p_exclui) as termo
      where fn_normalizar_texto(ce.chave) like '%' || fn_normalizar_texto(termo) || '%'
    )
  order by coalesce(ce.confianca, 0) desc, length(ce.chave) asc
  limit 1;
$$;

--
-- Name: fn_valor_conceito_secao(uuid, text[], text[], text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_valor_conceito_secao(p_documento_versao_id uuid, p_inclui text[], p_exclui text[] DEFAULT '{}'::text[], p_entidade_coluna text DEFAULT NULL::text, p_periodo_coluna text DEFAULT NULL::text) RETURNS public.campo_extraido
    LANGUAGE sql STABLE
    AS $$
  select ce.*
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and ce.secao is not null
    and p_entidade_coluna is distinct from E'\x01'
    and p_periodo_coluna is distinct from E'\x01'
    and (p_entidade_coluna is null
         or fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(p_entidade_coluna))
    and (p_periodo_coluna is null
         or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(p_periodo_coluna))
    and not exists (
      select 1 from unnest(p_inclui) as termo
      where fn_normalizar_texto(ce.secao) not like '%' || fn_normalizar_texto(termo) || '%'
    )
    -- O EXCLUI olha os dois: seção que casou não salva um rótulo que o exclui
    -- proíbe (ex.: seção "Disponível" com rótulo "Total do Ativo Circulante").
    and not exists (
      select 1 from unnest(p_exclui) as termo
      where fn_normalizar_texto(ce.secao) like '%' || fn_normalizar_texto(termo) || '%'
         or fn_normalizar_texto(ce.chave) like '%' || fn_normalizar_texto(termo) || '%'
    )
  order by coalesce(ce.confianca, 0) desc, length(ce.chave) asc
  limit 1;
$$;

--
-- Name: FUNCTION fn_valor_conceito_secao(p_documento_versao_id uuid, p_inclui text[], p_exclui text[], p_entidade_coluna text, p_periodo_coluna text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_valor_conceito_secao(p_documento_versao_id uuid, p_inclui text[], p_exclui text[], p_entidade_coluna text, p_periodo_coluna text) IS 'Como fn_valor_conceito_col, mas casa contra ce.secao. Fallback para rótulo que não nomeia o conceito ("Bancos Conta Movimento" debaixo de "Disponível") — 0031.';

--
-- Name: fn_valor_em_base(numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_valor_em_base(p_valor numeric, p_unidade text) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $$
  select p_valor * coalesce(fn_fator_escala(p_unidade), 1);
$$;

--
-- Name: fn_valor_estrutural_col(uuid, text[], text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_valor_estrutural_col(p_documento_versao_id uuid, p_tokens text[], p_entidade_coluna text DEFAULT NULL::text, p_periodo_coluna text DEFAULT NULL::text) RETURNS public.campo_extraido
    LANGUAGE sql STABLE
    AS $$
  select ce.*
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and p_entidade_coluna is distinct from E'\x01'
    and p_periodo_coluna is distinct from E'\x01'
    and (p_entidade_coluna is null
         or fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(p_entidade_coluna))
    and (p_periodo_coluna is null
         or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(p_periodo_coluna))
    and fn_rotulo_estrutural(ce.chave, p_tokens)
  -- Se houver mais de um (o cabeçalho do grupo E o rodapé "TOTAL DO ..."), o
  -- de MAIOR rótulo vem primeiro: é o rodapé, a linha conferida do documento.
  order by coalesce(ce.confianca, 0) desc, length(ce.chave) desc
  limit 1;
$$;

--
-- Name: fn_valor_pt_br(numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_valor_pt_br(p_valor numeric, p_unidade text DEFAULT NULL::text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
declare
  num    text;
  escala text;
begin
  if p_valor is null then return null; end if;

  -- Centavos só quando existem: "R$ 16.060 mil" e não "R$ 16.060,00 mil".
  if p_valor = trunc(p_valor) then
    num := to_char(abs(p_valor), 'FM999,999,999,999,990');
  else
    num := to_char(abs(p_valor), 'FM999,999,999,999,990.00');
  end if;
  num := translate(num, '.,', ',.');
  -- O SINAL VEM ANTES DA MOEDA ("-R$ 240 mil"), que é como se escreve — e não
  -- "R$ -240 mil", que é como o `to_char` entregaria.
  if p_valor < 0 then num := '-R$ ' || num; else num := 'R$ ' || num; end if;

  escala := case fn_normalizar_texto(coalesce(p_unidade, ''))
    when 'milhar'  then ' mil'
    when 'milhares' then ' mil'
    when 'mil'     then ' mil'
    -- Singular quando é UM milhão. Detalhe pequeno e visível: o texto sai da casa.
    when 'milhao'  then case when abs(p_valor) = 1 then ' milhão' else ' milhões' end
    when 'milhoes' then case when abs(p_valor) = 1 then ' milhão' else ' milhões' end
    when 'unidade' then ''
    when ''        then ''
    -- ESCALA QUE NÃO CONHEÇO FICA VISÍVEL, com a palavra que veio do documento:
    -- é informação sobre a extração, e some-la faria o número mudar de tamanho
    -- em silêncio.
    else ' ' || p_unidade
  end;

  return num || escala;
end;
$_$;

--
-- Name: FUNCTION fn_valor_pt_br(p_valor numeric, p_unidade text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_valor_pt_br(p_valor numeric, p_unidade text) IS 'Valor em reais como se escreve no Brasil (0122): "R$ 16.060 mil". A escala vira palavra (milhar → mil, milhao → milhões); escala desconhecida fica visível no fim. Independe do lc_numeric do servidor — o texto sai igual em qualquer instalação.';

--
-- Name: fn_valores_por_ano(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_valores_por_ano(p_caso_id uuid, p_entidade text DEFAULT NULL::text) RETURNS TABLE(rotulo_norm text, secao_canonica text, ano integer, valor numeric, n_ocorrencias bigint, arquivo text, origem_pagina integer, confianca numeric, status_aceite text, aceito_por text)
    LANGUAGE sql STABLE
    AS $$
  -- marca-0125
  -- marca-0200
  -- marca-0201
  with ocorrencias as materialized (
    select
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      ce.secao_canonica,
      -- 0199 (b): a coluna de ABERTURA é o fechamento do ano ANTERIOR ao do documento.
      fn_ano_da_coluna(ce.periodo_coluna, p.referencia)
        - (case when fn_coluna_e_abertura(ce.periodo_coluna) then 1 else 0 end) as ano,
      fn_coluna_e_abertura(ce.periodo_coluna) as abertura,
      -- 0199 (c): o saldo de um documento de período PARCIAL só vale na falta do anual.
      fn_periodo_e_parcial(ce.periodo_coluna, d.tipo_taxonomia, p.tipo, p.referencia) as parcial,
      -- 0200: a FAMÍLIA da demonstração e a ENTIDADE, para decidir o parcial por ano e não por rótulo.
      fn_familia_da_secao(ce.secao_canonica) as familia,
      case when p_entidade is not null then ''   -- a consulta já é de UMA entidade
           else fn_normalizar_texto(coalesce(ce.entidade_coluna, e.razao_social, '')) end as entidade_chave,
      ce.valor_num as valor,
      dv.nome_original as arquivo,
      ce.origem_pagina,
      ce.confianca,
      ce.status_aceite,
      ce.aceito_por,
      ce.ordem
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join periodo p on p.id = d.periodo_id
    left join entidade e on e.id = d.entidade_id
    left join taxonomia_tipo_documento t on t.codigo = d.tipo_taxonomia
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and (p_entidade is null
           or fn_mesma_entidade(coalesce(ce.entidade_coluna, e.razao_social, ''), p_entidade))
      and dv.id = fn_versao_com_extracao(d.id)
      -- 0199 (d): documento que não é demonstração não tem saldo (quotas, % de participação).
      and coalesce(t.categoria, '') not in ('Societário/Legal', 'Garantias/Sócios')
      -- 0199 (a): movimento do período (Débito/Crédito) nunca é saldo.
      and not fn_coluna_e_movimento(ce.periodo_coluna)
  ),
  -- 0200: a decisão "parcial entra se for a única fonte" é do ANO (da entidade e da família da
  -- demonstração), não do rótulo. Um balancete semestral traz centenas de contas analíticas que o
  -- balanço anual (sintético) não tem; para cada rótulo o balancete era a "única fonte" e entrava
  -- POR CIMA das contas do balanço do mesmo ano.
  elegiveis as (
    select o.*,
           bool_or(not coalesce(o.parcial, false)) over (partition by o.entidade_chave, o.familia, o.ano) as ano_tem_anual
    from ocorrencias o
    where o.ano is not null
  ),
  escolhido as (
    select
      o.rotulo_norm, o.secao_canonica, o.ano, o.valor,
      -- quantas ocorrências elegíveis o (rótulo, seção, ano) tem, incluindo as que perderam
      count(*) over (partition by o.rotulo_norm, o.secao_canonica, o.ano) as n_ocorrencias,
      o.arquivo, o.origem_pagina, o.confianca, o.status_aceite, o.aceito_por,
      row_number() over (
        partition by o.rotulo_norm, o.secao_canonica, o.ano
        order by o.abertura,           -- (b) fechamento antes de abertura
                 abs(o.valor) desc,    -- maior módulo COM SINAL, a regra da 0042
                 o.valor desc,         -- (e) empate de módulo com sinais opostos: o positivo
                 o.confianca desc nulls last,
                 o.origem_pagina asc nulls last,
                 o.arquivo,
                 o.ordem
      ) as rn
    from elegiveis o
    -- 0200: parcial só vale num ano em que a família não tem NENHUMA ocorrência anual
    where not (coalesce(o.parcial, false) and o.ano_tem_anual)
  )
  select rotulo_norm, secao_canonica, ano, valor, n_ocorrencias,
         arquivo, origem_pagina, confianca, status_aceite, aceito_por
  from escolhido
  where rn = 1
  order by rotulo_norm, ano;
$$;

--
-- Name: FUNCTION fn_valores_por_ano(p_caso_id uuid, p_entidade text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_valores_por_ano(p_caso_id uuid, p_entidade text) IS 'Série histórica por (rótulo, seção, ano), só da versão vigente (0102), com a proveniência DA CÉLULA (0125). 0199: coluna de movimento (Débito/Crédito) nunca é saldo; "Saldo Inicial"/"Saldo Anterior" é o fechamento do ano ANTERIOR e perde para o fechamento do mesmo ano; tipo de categoria Societário/Legal e Garantias/Sócios não entra. 0200: ocorrência de período PARCIAL (balancete, mês, trimestre, intervalo) só entra num ano em que a entidade não tem NENHUMA ocorrência anual da mesma família (patrimonial / resultado / fluxo / seção própria) — decisão do ANO, não do rótulo. 0201: a classificação da coluna e do período vem das funções puras fn_coluna_e_*, fn_periodo_e_parcial e fn_familia_da_secao, as MESMAS de fn_linhas_do_realizado. Dentro da camada, maior módulo com sinal (0042); desempate determinístico.';

--
-- Name: fn_veredito_producao(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_veredito_producao(p_estagio text, p_caso_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
declare
  v_natureza  text;
  v_crit      record;
  v_n         int     := 0;
  v_conc      numeric;
  v_por_tipo  jsonb   := '[]'::jsonb;
  v_fonte     text;
  v_pior      jsonb;
  v_falhas    text[]  := '{}';
  v_delegado  jsonb;
begin
  select natureza into v_natureza from estagio_autonomia where estagio = p_estagio;
  if v_natureza is null then
    return jsonb_build_object(
      'estagio', p_estagio, 'suficiente', false,
      'motivo', format('Estágio "%s" não existe no dial.', p_estagio));
  end if;

  select n_minimo_veredito, concordancia_minima, metrica
    into v_crit
    from golden_criterio where estagio = p_estagio;

  if v_crit is null then
    return jsonb_build_object(
      'estagio', p_estagio, 'suficiente', false,
      'motivo', format('O estágio "%s" não tem linha em golden_criterio, então não há limiar '
                       'contra o que comparar. Critério é dado (0126): acrescente a linha.',
                       p_estagio));
  end if;

  if p_estagio = 'classificacao_doc_checklist' then
    -- O VEREDITO É A REVISÃO DE DOCUMENTO. `fn_revisar_documento` grava
    -- 'correcao_classificacao' quando o humano trocou o tipo e 'aprovacao' quando
    -- não trocou, com `tipo_de`/`tipo_para` no payload. O payload é o filtro que
    -- separa esta decisão das outras 'aprovacao' do sistema — a do auto-aceite,
    -- por exemplo, que não é veredito sobre classificação nenhuma.
    --
    -- AUTOR HUMANO, e a exclusão é por prefixo 'sistema:' porque é assim que a
    -- casa marca ator de máquina desde a 0019. Contar o auto-aceite aqui seria a
    -- máquina se dando razão.
    v_fonte := 'decisao (fn_revisar_documento): aprovacao = tipo confirmado, '
               'correcao_classificacao = tipo trocado';
    with v as (
      select d.payload->>'tipo_de' as tipo_sugerido,
             (d.tipo = 'aprovacao') as concordou
        from decisao d
       where d.payload ? 'tipo_para'
         -- SEM PALPITE NÃO HÁ VEREDITO. Documento que chegou à revisão sem tipo
         -- nenhum (`tipo_de` nulo) não tem com o que concordar: contar a correção
         -- dele como erro da máquina puniria o classificador por uma resposta que
         -- ele não deu. Achado no book, onde uma linha assim derrubava a
         -- concordância de 1,00 para 0,83 sozinha.
         and d.payload->>'tipo_de' is not null
         and coalesce(d.autor, '') not like 'sistema:%'
         and d.tipo in ('aprovacao', 'correcao_classificacao')
         and (p_caso_id is null or d.caso_id = p_caso_id)
    ), por_tipo as (
      select tipo_sugerido,
             count(*)::int as n,
             count(*) filter (where concordou)::int as acertos,
             round(count(*) filter (where concordou)::numeric / count(*), 4) as concordancia
        from v group by tipo_sugerido
    )
    select coalesce(sum(n), 0)::int,
           case when coalesce(sum(n), 0) = 0 then null
                else round(sum(acertos)::numeric / sum(n), 4) end,
           coalesce(jsonb_agg(jsonb_build_object(
             'tipo', tipo_sugerido, 'n', n, 'acertos', acertos, 'concordancia', concordancia)
             order by concordancia, tipo_sugerido), '[]'::jsonb)
      into v_n, v_conc, v_por_tipo
      from por_tipo;

  elsif p_estagio = 'reconciliacao_classe_a' then
    -- Já existia desde a 0126 e nunca esteve ligada ao dial. Delegar em vez de
    -- reescrever: duas contagens da mesma quantidade divergem no dia em que
    -- alguém corrigir uma só.
    v_fonte := 'fn_golden_classe_a (0126): rejeitada = falso positivo do motor';
    v_delegado := fn_golden_classe_a(p_caso_id);
    v_n    := coalesce((v_delegado->>'com_veredito_humano')::int, 0);
    v_conc := (v_delegado->>'nao_falso_positivo')::numeric;

  elsif p_estagio = 'classificacao_contabil' then
    -- A 0128 mede isto desde que existe. O teto deste estágio é N1, então o
    -- número não sobe dial nenhum hoje; ele entra aqui para a tela de autonomia
    -- poder mostrar medição onde existe, em vez de silêncio.
    v_fonte := 'fn_classe_contabil_concordancia (0128): sugestão em sombra contra override humano';
    v_delegado := fn_classe_contabil_concordancia(p_caso_id);
    v_n    := coalesce((v_delegado->>'com_veredito_humano')::int, 0);
    v_conc := (v_delegado->>'concordancia')::numeric;

  else
    return jsonb_build_object(
      'estagio', p_estagio, 'suficiente', false, 'n', 0,
      'metrica', v_crit.metrica,
      'motivo', format('Não há veredito de produção para "%s". O trabalho normal não emite rótulo '
                       'sobre este estágio: o analista não confirma nem corrige a saída dele numa '
                       'tela, então não existe o que contar. Medir este estágio exige rotulagem, e '
                       'é o caso que a saída C do B3 cobre.', p_estagio));
  end if;

  -- O TIPO MAIS FRACO, quando há tipo. Um tipo com N pequeno não reprova sozinho:
  -- ele não tem massa para afirmar nada, e tratá-lo como reprovação faria o
  -- estágio inteiro depender do tipo mais raro da mesa.
  select jsonb_agg(t) filter (where (t->>'n')::int >= greatest(v_crit.n_minimo_veredito / 4, 5)
                                and (t->>'concordancia')::numeric < v_crit.concordancia_minima)
    into v_pior
    from jsonb_array_elements(v_por_tipo) t;

  if v_n < v_crit.n_minimo_veredito then
    v_falhas := v_falhas || format('vereditos de produção: %s, mínimo %s',
                                   v_n, v_crit.n_minimo_veredito);
  end if;
  if v_conc is null then
    -- O `::text` NÃO é enfeite — ver o cabeçalho desta migration.
    v_falhas := v_falhas || 'concordância: não medida (nenhum veredito com os dois lados)'::text;
  elsif v_conc < v_crit.concordancia_minima then
    v_falhas := v_falhas || format('concordância: %s, mínimo %s', v_conc, v_crit.concordancia_minima);
  end if;
  if v_pior is not null then
    v_falhas := v_falhas || format('%s tipo(s) com massa e concordância abaixo do mínimo',
                                   jsonb_array_length(v_pior));
  end if;

  return jsonb_build_object(
    'estagio', p_estagio,
    'suficiente', array_length(v_falhas, 1) is null,
    'fonte', v_fonte,
    'metrica', v_crit.metrica,
    'n', v_n,
    'n_minimo', v_crit.n_minimo_veredito,
    'concordancia', v_conc,
    'concordancia_minima', v_crit.concordancia_minima,
    'por_tipo', v_por_tipo,
    'tipos_abaixo_do_minimo', coalesce(v_pior, '[]'::jsonb),
    'falhas', coalesce(to_jsonb(v_falhas), '[]'::jsonb),
    'piso_enviesado', true,
    'como_ler', 'Este número é um PISO, não um ground truth. O veredito vem do trabalho normal, e '
                'quem o emite VÊ o palpite da máquina antes de decidir — o viés de confirmação '
                'empurra a concordância para cima. Serve para dizer "a máquina acerta pelo menos '
                'isto"; não substitui rotulagem cega no dia em que for preciso sustentar o número '
                'para fora.');
end;
$$;

--
-- Name: FUNCTION fn_veredito_producao(p_estagio text, p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_veredito_producao(p_estagio text, p_caso_id uuid) IS 'Concordância medida a partir do veredito que o trabalho normal já produz (saída B do B3, 21/08). Despacha por estágio e RECUSA o que não sabe medir, em vez de devolver zero. É PISO ENVIESADO: quem emite o veredito vê o palpite da máquina, e o viés de confirmação puxa para cima. Vale menos que rodada de golden set congelada e mais que nível declarado.';

--
-- Name: fn_versao_atual(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_versao_atual(p_documento_id uuid) RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select id from documento_versao where documento_id = p_documento_id order by n_versao desc limit 1;
$$;

--
-- Name: fn_versao_com_extracao(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_versao_com_extracao(p_documento_id uuid) RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  select dv.id
  from documento_versao dv
  where dv.documento_id = p_documento_id
    and exists (select 1 from campo_extraido ce where ce.documento_versao_id = dv.id)
  order by dv.n_versao desc
  limit 1;
$$;

--
-- Name: FUNCTION fn_versao_com_extracao(p_documento_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_versao_com_extracao(p_documento_id uuid) IS 'A documento_versao VIGENTE para quem lê conteúdo: a de maior n_versao que TEM campo_extraido. Difere de fn_versao_atual (max(n_versao)) de propósito: entre fn_registrar_documento e fn_registrar_campos_extraidos a versão mais recente está vazia, e max(n_versao) puro deixaria a tela de Modelagem em branco nessa janela — o mesmo sintoma que a 0101 corrigiu.';

--
-- Name: fn_vincular_linha_premissa(uuid, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_vincular_linha_premissa(p_caso_id uuid, p_secao_canonica text, p_rotulo text, p_entidade text, p_premissa text, p_autor text, p_sazonalidade text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_rotulo_norm text := fn_normalizar_texto(p_rotulo);
  v_papel text;
begin
  -- Papel primeiro (0042). Desvincular (premissa null) é SEMPRE permitido: limpar
  -- configuração antiga não pode ser bloqueado pela regra nova.
  if p_premissa is not null then
    v_papel := fn_papel_do_rotulo_no_caso(p_caso_id, v_rotulo_norm, p_secao_canonica);
    if v_papel is not null and v_papel <> 'conta' then
      return jsonb_build_object('recusado', true, 'papel', v_papel,
        'motivo_recusa', case v_papel
          when 'subtotal' then
            format('"%s" é um SUBTOTAL — já é a soma de outras linhas. No Excel ele sai como a '
                   'soma dos componentes projetados, então se move sozinho; projetá-lo por '
                   'premissa própria contaria o mesmo dinheiro duas vezes.', p_rotulo)
          when 'serie_mensal' then
            format('"%s" é uma linha da SÉRIE MENSAL de faturamento — ela alimenta a curva de '
                   'sazonalidade (que sai do próprio histórico do caso), não é uma conta a '
                   'projetar. Projetá-la contaria a receita de novo, mês a mês.', p_rotulo)
          else
            format('"%s" é um indicador DERIVADO (resultado de outras contas, não dinheiro). '
                   'Projetá-lo por premissa própria o faria divergir das linhas que o compõem.',
                   p_rotulo)
        end);
    end if;
  end if;

  if p_premissa is not null and not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_premissa and ativo
  ) then
    return jsonb_build_object('recusado', true, 'escopo', 'premissa',
      'motivo_recusa', format('A premissa "%s" não está ATIVA neste caso. Ative-a (com valores) '
                              'antes de vincular linha — senão a linha sairia "projetada" por uma '
                              'premissa vazia, o que é projetar com zero.', p_premissa));
  end if;
  if p_sazonalidade is not null and not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_sazonalidade and ativo
  ) then
    return jsonb_build_object('recusado', true, 'escopo', 'premissa',
      'motivo_recusa', format('A sazonalidade "%s" não está ativa neste caso.', p_sazonalidade));
  end if;

  insert into caso_linha_premissa (caso_id, secao_canonica, rotulo_norm, entidade,
                                   premissa_codigo, sazonalidade_codigo, atualizado_por, atualizado_em)
    values (p_caso_id, p_secao_canonica, v_rotulo_norm, p_entidade, p_premissa, p_sazonalidade, p_autor, now())
  on conflict (caso_id, rotulo_norm, coalesce(entidade, ''), coalesce(secao_canonica, '')) do update
    set premissa_codigo = excluded.premissa_codigo,
        sazonalidade_codigo = excluded.sazonalidade_codigo,
        atualizado_por = excluded.atualizado_por, atualizado_em = now();

  return jsonb_build_object('caso_id', p_caso_id, 'rotulo', v_rotulo_norm, 'premissa', p_premissa);
end;
$$;

--
-- Name: arquivo_oficial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.arquivo_oficial (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    documento_id uuid,
    familia text NOT NULL,
    subtipo text,
    versao_leiaute text,
    hash_sha256 text NOT NULL,
    cnpj text,
    periodo_ini date,
    periodo_fim date,
    chave_natural text,
    retificadora boolean DEFAULT false NOT NULL,
    controle_tipo text NOT NULL,
    controle_declarado bigint,
    controle_lido bigint,
    status text NOT NULL,
    vigente boolean DEFAULT false NOT NULL,
    substituido_por uuid,
    detalhe jsonb DEFAULT '{}'::jsonb NOT NULL,
    leitor_versao text NOT NULL,
    lido_em timestamp with time zone DEFAULT now() NOT NULL,
    seq bigint NOT NULL,
    resumo_status text,
    resumo_versao text,
    resumo_motivo text,
    resumo_conferencia jsonb,
    resumo_descartado text,
    resumo_total_registros integer,
    resumo_total_grupos integer,
    CONSTRAINT arquivo_oficial_controle_tipo_check CHECK ((controle_tipo = ANY (ARRAY['contagem_declarada'::text, 'documento_unico'::text, 'sem_controle_no_formato'::text]))),
    CONSTRAINT arquivo_oficial_divergente_tem_as_duas CHECK (((status <> 'controle_divergente'::text) OR ((controle_declarado IS NOT NULL) AND (controle_lido IS NOT NULL) AND (controle_declarado <> controle_lido)))),
    CONSTRAINT arquivo_oficial_familia_check CHECK ((familia = ANY (ARRAY['sped'::text, 'nfe'::text, 'cte'::text, 'mdfe'::text, 'nfse'::text, 'esocial'::text, 'reinf'::text, 'cnab240'::text, 'cnab400'::text, 'cnab150'::text, 'ofx'::text, 'zip'::text]))),
    CONSTRAINT arquivo_oficial_lido_tem_contagem CHECK (((status <> 'lido'::text) OR ((controle_lido IS NOT NULL) AND ((controle_tipo <> 'contagem_declarada'::text) OR ((controle_declarado IS NOT NULL) AND (controle_declarado = controle_lido)))))),
    CONSTRAINT arquivo_oficial_resumo_status_check CHECK ((resumo_status = ANY (ARRAY['em_carga'::text, 'completo'::text, 'ausente'::text, 'recusado'::text]))),
    CONSTRAINT arquivo_oficial_status_check CHECK ((status = ANY (ARRAY['lido'::text, 'controle_divergente'::text, 'versao_desconhecida'::text, 'familia_desconhecida'::text, 'falhou'::text]))),
    CONSTRAINT arquivo_oficial_vigente_so_se_lido CHECK (((NOT vigente) OR (status = 'lido'::text)))
);

--
-- Name: TABLE arquivo_oficial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.arquivo_oficial IS 'Envelope de cada arquivo de leiaute oficial lido pelo serviço leitor (Espec. 12, D12.9): o que é, de quem, de quando, quantos registros declarava e quantos foram lidos. Idempotente por (caso, hash). Uma vigente por (caso, chave_natural), regra G9. 0206.';

--
-- Name: COLUMN arquivo_oficial.chave_natural; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.arquivo_oficial.chave_natural IS 'Identidade do CONTEÚDO, para a regra de versão vigente: sped cnpj|subtipo|ini|fim; nfe/cte/mdfe a chave de acesso (44 dígitos); esocial/reinf o Id do evento; ofx banco|conta|ini|fim; cnab o próprio hash.';

--
-- Name: COLUMN arquivo_oficial.controle_tipo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.arquivo_oficial.controle_tipo IS 'Como o formato se auto-confere: contagem_declarada (|9999|, rodapé CNAB, S-1299), documento_unico (um XML = um documento) ou sem_controle_no_formato.';

--
-- Name: COLUMN arquivo_oficial.seq; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.arquivo_oficial.seq IS 'Ordem de registro. Desempata "o registrado por último vence" na versão vigente; lido_em não serve, pois duas linhas na mesma transação têm o mesmo now().';

--
-- Name: COLUMN arquivo_oficial.resumo_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.arquivo_oficial.resumo_status IS 'Estado do resumo enviado pelo navegador: em_carga (partes chegando), completo (o servidor reconferiu), ausente (não há resumo, e resumo_motivo diz por quê) ou recusado (incoerente, linhas apagadas). NULL = nunca tentado. 0207.';

--
-- Name: COLUMN arquivo_oficial.resumo_conferencia; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.arquivo_oficial.resumo_conferencia IS 'A conferência do leitor (i250_lidos, valores_invalidos, lançamentos desbalanceados...) mais a chave i155 que o SERVIDOR calcula no concluir: {total, nao_fecham, ilegiveis, amostra}. 0207.';

--
-- Name: COLUMN arquivo_oficial.resumo_descartado; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.arquivo_oficial.resumo_descartado IS 'O que o resumo NÃO guarda, dito pelo próprio leitor (ex.: o lançamento individual I200/I250). 0207.';

--
-- Name: CONSTRAINT arquivo_oficial_lido_tem_contagem ON arquivo_oficial; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT arquivo_oficial_lido_tem_contagem ON public.arquivo_oficial IS 'Regra 7: "lido" nunca sem contagem. O is not null explícito evita o check que dá NULL e passa.';

--
-- Name: arquivo_oficial_lancamento_mes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.arquivo_oficial_lancamento_mes (
    arquivo_oficial_id uuid NOT NULL,
    conta text NOT NULL,
    mes date,
    ind_lcto text,
    debito bigint NOT NULL,
    credito bigint NOT NULL,
    partidas integer NOT NULL,
    partidas_sem_valor integer NOT NULL,
    primeira_linha integer
);

--
-- Name: TABLE arquivo_oficial_lancamento_mes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.arquivo_oficial_lancamento_mes IS 'O I250 da ECD somado por (conta, mês, IND_LCTO), em centavos. mes NULL = partida sem I200 antes ou com data inválida: é DADO, a marca do problema, e não erro. partidas_sem_valor > 0 = o grupo é incompleto. 0207.';

--
-- Name: COLUMN arquivo_oficial_lancamento_mes.mes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.arquivo_oficial_lancamento_mes.mes IS 'Primeiro dia do mês; NULL = partida sem I200 ou data inválida.';

--
-- Name: arquivo_oficial_registro; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.arquivo_oficial_registro (
    arquivo_oficial_id uuid NOT NULL,
    linha integer NOT NULL,
    registro text NOT NULL,
    conteudo text NOT NULL
);

--
-- Name: TABLE arquivo_oficial_registro; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.arquivo_oficial_registro IS 'Os registros guardados NA ÍNTEGRA do resumo de um arquivo oficial, com o número da linha do arquivo (proveniência). registro é o código (split_part(conteudo,''|'',2)). Só existe para resumo em_carga ou completo. 0207.';

--
-- Name: arquivo_oficial_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.arquivo_oficial ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.arquivo_oficial_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: campo_classe_override; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campo_classe_override (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campo_extraido_id uuid NOT NULL,
    classe_final text NOT NULL,
    sugestao_original text,
    autor text NOT NULL,
    motivo text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: TABLE campo_classe_override; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.campo_classe_override IS 'A decisão humana sobre a classe contábil de uma linha (Arquitetura do Sistema/2 Especificação/05, "registro de override humano"). Append-only: reclassificar é linha nova, e a sequência é o histórico. É ele o SINAL DE CALIBRAÇÃO da F4 — cada override é um ponto de concordância medida que o uso do produto gera sozinho, sem rotulagem dedicada.';

--
-- Name: campo_classe_sugerida; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campo_classe_sugerida (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campo_extraido_id uuid NOT NULL,
    classe_codigo text NOT NULL,
    confianca numeric,
    rubrica_id uuid,
    justificativa text NOT NULL,
    versao_taxonomia integer NOT NULL,
    nivel_autonomia public.nivel_autonomia NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: TABLE campo_classe_sugerida; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.campo_classe_sugerida IS 'A sugestão da classificação contábil, com a justificativa que o Arquitetura do Sistema/2 Especificação/05 exige de toda sugestão. AUSÊNCIA de linha aqui significa "a pergunta não se aplica" — linha de balanço não é recorrente nem não recorrente. nivel_autonomia guarda em que nível o estágio estava quando sugeriu, porque uma sugestão feita em N0 e uma feita em N1 têm peso diferente na leitura de quem confere.';

--
-- Name: caso; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.caso (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    produto text DEFAULT 'reestruturacao'::text NOT NULL,
    status public.caso_status DEFAULT 'intake'::public.caso_status NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    fechado_em timestamp with time zone,
    fechado_por text,
    motivo_fechamento text,
    trilha_transacional boolean DEFAULT false NOT NULL
);

--
-- Name: COLUMN caso.fechado_em; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.caso.fechado_em IS 'Quando o mandato saiu da mesa. NULL = ativo. Não é status de trabalho (esse é `status`, Arquitetura do Sistema/2 Especificação/f0/04): é a resposta a "ainda estamos nisso?". Fechar preserva tudo — para apagar existe fn_excluir_caso.';

--
-- Name: COLUMN caso.trilha_transacional; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.caso.trilha_transacional IS 'Liga/desliga por caso da trilha de arquivos oficiais (Espec. 12, G25). Default false: nada muda em produção até alguém ligar, e desligada fn_registrar_arquivo_oficial RECUSA com exceção (regra 7). 0206.';

--
-- Name: caso_apresentacao_campo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.caso_apresentacao_campo (
    caso_id uuid NOT NULL,
    chave text NOT NULL,
    valor text NOT NULL,
    fonte text,
    preenchido_por text,
    preenchido_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT caso_apresentacao_campo_chave_check CHECK ((chave ~ '^[a-z0-9]+(\.[a-z0-9_]+)+$'::text)),
    CONSTRAINT caso_apresentacao_campo_valor_check CHECK ((length(btrim(valor, ' 	
'::text)) > 0))
);

--
-- Name: TABLE caso_apresentacao_campo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.caso_apresentacao_campo IS 'Valor dos campos "[a preencher]" da apresentação de crédito, por caso e chave estável. Ausência de linha = o deck escreve "[a preencher]"; valor em branco é recusado (regra 1: vazio não é valor). 0205.';

--
-- Name: COLUMN caso_apresentacao_campo.chave; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.caso_apresentacao_campo.chave IS 'Capítulo.grupo.campo em minúsculas, ex.: xiv.ajuste.nao_recorrentes. Formato travado por check para que typo não vire campo órfão.';

--
-- Name: COLUMN caso_apresentacao_campo.fonte; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.caso_apresentacao_campo.fonte IS 'De onde veio o valor (documento, URL, "analista"). Vai para a nota de fonte do slide.';

--
-- Name: caso_linha_premissa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.caso_linha_premissa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    secao_canonica text,
    rotulo_norm text NOT NULL,
    entidade text,
    premissa_codigo text,
    sazonalidade_codigo text,
    atualizado_por text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: caso_modelagem; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.caso_modelagem (
    caso_id uuid NOT NULL,
    entidade text,
    ultimo_exercicio_real integer,
    indice_macro text,
    setor text,
    anos_projetados integer DEFAULT 5 NOT NULL,
    atualizado_por text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: caso_pergunta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.caso_pergunta (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    pergunta_codigo text NOT NULL,
    entidade_id uuid,
    acao text NOT NULL,
    texto_enviado text,
    autor text NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT caso_pergunta_acao_check CHECK ((acao = ANY (ARRAY['enviada'::text, 'descartada'::text]))),
    CONSTRAINT caso_pergunta_check CHECK (((acao <> 'enviada'::text) OR ((texto_enviado IS NOT NULL) AND (length(TRIM(BOTH FROM texto_enviado)) > 0))))
);

--
-- Name: TABLE caso_pergunta; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.caso_pergunta IS 'Ação HUMANA sobre uma pergunta sugerida: enviada (com o texto renderizado congelado) ou descartada. O sistema sugere, o humano decide (Arquitetura do Sistema/1 Visão e Doutrina/01); nenhum envio é automático — o canal continua sendo o analista (o botão da 0109 só rotula a pendência).';

--
-- Name: caso_premissa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.caso_premissa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    premissa_codigo text NOT NULL,
    valores jsonb DEFAULT '{}'::jsonb NOT NULL,
    origem text,
    ativo boolean DEFAULT true NOT NULL,
    atualizado_por text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: checklist_item_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.checklist_item_status (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    entidade_id uuid,
    periodo_id uuid,
    tipo_taxonomia text NOT NULL,
    obrigatoriedade public.obrigatoriedade NOT NULL,
    status text DEFAULT 'faltante'::text NOT NULL,
    documento_id uuid,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: classe_contabil_catalogo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.classe_contabil_catalogo (
    codigo text NOT NULL,
    nome text NOT NULL,
    descricao text NOT NULL,
    versao integer DEFAULT 1 NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    ordem integer NOT NULL
);

--
-- Name: TABLE classe_contabil_catalogo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.classe_contabil_catalogo IS 'A taxonomia contábil fechada do Arquitetura do Sistema/2 Especificação/05 (recorrente, nao_recorrente, extraordinario, candidato_ajuste_ebitda, revisar_manual). TABELA e não enum de propósito: acrescentar um sexto rótulo deve custar uma linha de seed, não uma migration que altera tipo — no Postgres alterar enum não remove valor e não volta atrás. Mesma escolha que a 0038 fez com premissas.';

--
-- Name: controlador; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.controlador (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    nome text NOT NULL,
    documento text,
    tipo_pessoa public.controlador_tipo_pessoa NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: TABLE controlador; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.controlador IS '0182 (fatia 1.7a do plano F1): a pessoa (física, ou jurídica externa ao perímetro do caso) que detém participação em uma ou mais entidades do caso — escopada por `caso_id`, como `entidade`. Existe para registrar CONTROLE COMUM sem inventar uma holding que não existe (ver `.claude/memory/grupo-por-controle-comum-sem-holding.md`): o vínculo mora em `entidade_controlador`, e `fn_grupo_por_controle_comum` agrupa as entidades por FECHO TRANSITIVO de controladores compartilhados. Não confundir com `entidade` — um controlador PESSOA FÍSICA nunca vira `entidade` (essa tabela é só de pessoas jurídicas do mandato); um controlador PESSOA JURÍDICA aqui é externo ao perímetro (senão a hierarquia seria `entidade.controladora_id`, 0181, não isto). Os dois caminhos de escrita são `fn_controlador_registrar` e `fn_entidade_definir_controlador` — nunca inferência automática a partir de `campo_extraido`, nome ou CNPJ (regra 1 do CLAUDE.md).';

--
-- Name: COLUMN controlador.documento; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.controlador.documento IS '0182: CPF ou CNPJ do controlador, texto livre e OPCIONAL — não há função de canonicalização de CPF neste repositório (só `fn_cnpj_canonico`, 0169, que é de CNPJ), e exigir o documento transformaria "sabemos que é sócio, mas não temos o CPF no contrato" (o estado normal aqui) em bloqueio. NULL é um documento não informado, distinto de um documento informado errado.';

--
-- Name: decisao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.decisao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    tipo public.decisao_tipo NOT NULL,
    autor text NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    motivo text,
    payload jsonb
);

--
-- Name: documento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documento (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    entidade_id uuid,
    periodo_id uuid,
    tipo_taxonomia text,
    status public.documento_status DEFAULT 'recebido'::public.documento_status NOT NULL,
    sensibilidade_lgpd public.sensibilidade_lgpd DEFAULT 'nenhuma'::public.sensibilidade_lgpd NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    confianca numeric,
    fonte text,
    justificativa text,
    resumo text
);

--
-- Name: COLUMN documento.confianca; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.documento.confianca IS 'Confiança da classificação atual (nome-do-arquivo/IA/humano). 1.0 quando confirmado por humano.';

--
-- Name: COLUMN documento.fonte; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.documento.fonte IS 'Origem da classificação atual: nome_arquivo | openai_conteudo | humano.';

--
-- Name: COLUMN documento.justificativa; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.documento.justificativa IS 'Explicação objetiva da classificação atual (da IA na origem, ou motivo informado na revisão humana).';

--
-- Name: COLUMN documento.resumo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.documento.resumo IS 'Resumo objetivo (2-3 frases) do conteúdo do documento, gerado no diagnóstico (E2).';

--
-- Name: documento_fato; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documento_fato (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    documento_versao_id uuid NOT NULL,
    tipo text NOT NULL,
    trecho text NOT NULL,
    pagina integer,
    leitura text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT documento_fato_trecho_check CHECK ((length(btrim(trecho)) >= 20))
);

--
-- Name: TABLE documento_fato; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.documento_fato IS 'Fato material declarado por um documento EM TEXTO — covenant rompido, ressalva de auditoria, continuidade operacional. Não é pendência: pendência significa "há algo a corrigir", e um covenant rompido não é defeito do dado, é o dado. Nasceu da v48, onde as Notas Explicativas e o Parecer do Auditor entravam, eram classificados e ficavam mudos. A política de escrita é a mesma de campo_extraido (0149): a 0148 só dava SELECT, e a gravação funcionava por acidente da credencial em vez de por decisão.';

--
-- Name: COLUMN documento_fato.trecho; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.documento_fato.trecho IS 'A frase COPIADA do documento. NOT NULL e com tamanho mínimo: um resumo escrito pelo modelo é afirmação, a frase do documento é evidência — e este alerta é o que vai ao comitê.';

--
-- Name: documento_versao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documento_versao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    documento_id uuid NOT NULL,
    n_versao integer DEFAULT 1 NOT NULL,
    origem_arquivo public.origem_arquivo DEFAULT 'supabase_storage'::public.origem_arquivo NOT NULL,
    arquivo_ref text NOT NULL,
    nome_original text,
    assinado boolean,
    hash text,
    legibilidade public.legibilidade,
    criada_em timestamp with time zone DEFAULT now() NOT NULL,
    nota_legibilidade text,
    fingerprint_extracao text,
    fatos_avaliados_em timestamp with time zone
);

--
-- Name: COLUMN documento_versao.nota_legibilidade; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.documento_versao.nota_legibilidade IS 'Motivo objetivo quando legibilidade != ok (ex.: páginas faltando, digitalização ruim).';

--
-- Name: COLUMN documento_versao.fingerprint_extracao; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.documento_versao.fingerprint_extracao IS 'Impressão do que determinou a extração desta versão: prompt de sistema + modelo + esquema de resposta, calculada no build do workflow. É o que autoriza NÃO pagar a extração de novo quando o mesmo arquivo volta — junto com a exigência de a versão ter linha extraída (0118).';

--
-- Name: COLUMN documento_versao.fatos_avaliados_em; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.documento_versao.fatos_avaliados_em IS 'Quando esta versão foi lida à procura de fatos materiais (0149). NULL = ainda não foi — e nesse caso os fatos da versão anterior continuam valendo na tela. Preenchida mesmo quando a leitura não achou nada: é o que distingue "sem fatos" de "não processada".';

--
-- Name: entidade_controlador; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entidade_controlador (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    entidade_id uuid NOT NULL,
    controlador_id uuid NOT NULL,
    percentual numeric(6,3),
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT entidade_controlador_percentual_valido CHECK (((percentual IS NULL) OR ((percentual > (0)::numeric) AND (percentual <= (100)::numeric))))
);

--
-- Name: TABLE entidade_controlador; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.entidade_controlador IS '0182 (fatia 1.7a do plano F1): quem controla o quê, por CONTROLE COMUM — o vínculo N:N entre `entidade` e `controlador` que `entidade.controladora_id` (0181, FK de empresa para empresa) não alcança quando não há holding (ver `.claude/memory/grupo-por-controle-comum-sem-holding.md` e o cabeçalho desta migration). SEM `desde`/`ate` — DELIBERADO, é uma limitação documentada, não um esquecimento (ver cabeçalho): não há nada medido hoje que justifique temporalidade aqui, ao contrário do `perimetro` da 0180. NO MÁXIMO uma linha por (entidade_id, controlador_id) — reatribuir o percentual é permitido (fn_entidade_definir_controlador sobrescreve o ESTADO ATUAL), o histórico mora em evento_auditoria. O único caminho de escrita é `fn_entidade_definir_controlador`.';

--
-- Name: COLUMN entidade_controlador.percentual; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.entidade_controlador.percentual IS '0182: o percentual que este controlador detém desta entidade, em (0, 100], ou NULL. A DISTINÇÃO da regra 7 do CLAUDE.md: percentual NULL com a LINHA PRESENTE significa "é sócio CONHECIDO, o percentual NÃO foi medido" (ex.: um contrato que nomeia o sócio sem discriminar a fração, ou um dos 4 casos deste mandato em que o contrato social ainda não foi lido). A AUSÊNCIA DA LINHA inteira significa "não se sabe se esta pessoa é sócia desta entidade" — nem chegou a ser perguntado. As duas ausências (percentual NULL vs. linha ausente) NÃO SÃO A MESMA COISA, e confundi-las apagaria a diferença entre "sabemos que é sócio, falta o número" e "não sabemos nada". Nunca inserir uma linha só para registrar incerteza quando não há vínculo de sociedade conhecido algum.';

--
-- Name: CONSTRAINT entidade_controlador_percentual_valido ON entidade_controlador; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT entidade_controlador_percentual_valido ON public.entidade_controlador IS '0182: percentual tem de estar em (0, 100] quando informado — zero ou negativo não é participação, mais de 100% não existe. Protege INSERT/UPDATE direto, mesma doutrina do `entidade_percentual_valido` da 0181 e do `perimetro_intervalo_valido` da 0180.';

--
-- Name: estagio_autonomia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.estagio_autonomia (
    estagio text NOT NULL,
    nivel_atual public.nivel_autonomia NOT NULL,
    teto public.nivel_autonomia NOT NULL,
    atualizado_por text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    limiar_auto_clear numeric DEFAULT 0.95,
    natureza text DEFAULT 'interpretativo'::text NOT NULL,
    base_do_nivel text DEFAULT 'nao_se_aplica'::text NOT NULL,
    medicao_rodada_id uuid,
    medicao_em timestamp with time zone,
    medicao_resumo jsonb,
    auto_promocao boolean DEFAULT true NOT NULL,
    CONSTRAINT estagio_autonomia_base_check CHECK ((base_do_nivel = ANY (ARRAY['nao_se_aplica'::text, 'declarada'::text, 'medida'::text, 'medida_por_veredito'::text]))),
    CONSTRAINT estagio_autonomia_natureza_check CHECK ((natureza = ANY (ARRAY['deterministico'::text, 'interpretativo'::text])))
);

--
-- Name: TABLE estagio_autonomia; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.estagio_autonomia IS 'O "dial" de autonomia por estágio. Nível é estado do sistema, não constante de código (Arquitetura do Sistema/1 Visão e Doutrina/01).';

--
-- Name: COLUMN estagio_autonomia.limiar_auto_clear; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.estagio_autonomia.limiar_auto_clear IS 'Confiança mínima para auto-aceite quando o estágio está em N2/N3. Era 0.95 HARDCODED em fn_registrar_campos_extraidos (0019); virou dado na 0041 para poder ser ajustado sem migration. Null = não auto-aceita, independentemente do nível.';

--
-- Name: COLUMN estagio_autonomia.natureza; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.estagio_autonomia.natureza IS 'Arquitetura do Sistema/1 Visão e Doutrina/01, "regra de teto por natureza do estágio": deterministico = aritmética/integridade, cuja confiança não vem de concordância humana; interpretativo = tudo o que a regra de ouro governa. Default interpretativo porque, em dúvida, a regra APLICA — estágio novo nasce cobrado.';

--
-- Name: COLUMN estagio_autonomia.base_do_nivel; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.estagio_autonomia.base_do_nivel IS 'Em que o nível de HOJE se apoia. nao_se_aplica = N0/N1 ou determinístico; declarada = N2/N3 por decisão, sem medição; medida_por_veredito = concordância medida no trabalho normal, que é PISO ENVIESADO (0136); medida = concordância contra rodada de golden set congelada, que é a única cega. A ordem da lista é a da força da evidência.';

--
-- Name: COLUMN estagio_autonomia.medicao_resumo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.estagio_autonomia.medicao_resumo IS 'A medição que autorizou o nível, congelada no momento da subida. Guardar o resultado (e não só o ponteiro para a rodada) é o que permite responder "com que número isto subiu?" mesmo depois de o golden set crescer em rodadas seguintes.';

--
-- Name: COLUMN estagio_autonomia.auto_promocao; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.estagio_autonomia.auto_promocao IS 'Se este estágio pode subir SOZINHO quando o veredito de produção alcançar o critério (0137). Nasce ligado. É DESLIGADO automaticamente quando um humano baixa o nível, para que o freio não seja desfeito pela máquina no veredito seguinte, e religar é um update explícito — a decisão de voltar a confiar é de quem desconfiou.';

--
-- Name: evento_auditoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evento_auditoria (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    ator text NOT NULL,
    acao text NOT NULL,
    entidade_ref text,
    antes jsonb,
    depois jsonb
);

--
-- Name: execucao_falha; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.execucao_falha (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid,
    caso_nome text,
    etapa text NOT NULL,
    mensagem text NOT NULL,
    detalhe jsonb,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    visto_em timestamp with time zone,
    visto_por text
);

--
-- Name: TABLE execucao_falha; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.execucao_falha IS 'Falha do pipeline (n8n) que a TELA precisa mostrar. Existe porque o portal deduzia progresso de sinais positivos, e falha produz ausência — indistinguível de "ainda processando". Tabela própria e não evento_auditoria: isto é estado operacional que se marca como visto, não trilha.';

--
-- Name: fato_tipo_catalogo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fato_tipo_catalogo (
    tipo text NOT NULL,
    rotulo text NOT NULL,
    severidade text NOT NULL,
    porque text NOT NULL,
    ordem integer DEFAULT 100 NOT NULL,
    CONSTRAINT fato_tipo_catalogo_severidade_check CHECK ((severidade = ANY (ARRAY['critico'::text, 'relevante'::text, 'informativo'::text])))
);

--
-- Name: TABLE fato_tipo_catalogo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.fato_tipo_catalogo IS 'Os tipos de fato material que a extração pode declarar, com a severidade e o rótulo humano. É catálogo e não enum no corpo da função porque acrescentar um tipo não pode exigir reescrever a função — e porque a TELA precisa do rótulo sem manter um switch paralelo.';

--
-- Name: COLUMN fato_tipo_catalogo.porque; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.fato_tipo_catalogo.porque IS 'Por que este fato importa para quem decide. É o texto que a tela mostra abaixo do trecho, e é o que separa um alerta acionável de uma etiqueta.';

--
-- Name: golden_campo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.golden_campo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    rodada_id uuid NOT NULL,
    documento_id uuid NOT NULL,
    rotulador text NOT NULL,
    chave text NOT NULL,
    periodo_coluna text,
    entidade_coluna text,
    valor_correto numeric,
    classe_contabil_correta text,
    tolerancia numeric DEFAULT 0 NOT NULL,
    rotulado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: TABLE golden_campo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.golden_campo IS 'Os campos_chave do Arquitetura do Sistema/2 Especificação/f0/06: que valor o humano leu no documento, para a linha que a extração devolve. tolerancia é por LINHA porque escala é por documento — 1 unidade é arredondamento legítimo em milhares e é cegueira em milhões.';

--
-- Name: COLUMN golden_campo.classe_contabil_correta; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.golden_campo.classe_contabil_correta IS 'A classe contábil que o humano atribuiu (recorrente/EBITDA…). É o ground truth da quinta linha da tabela de métricas do Arquitetura do Sistema/2 Especificação/f0/06 — e o estágio classificacao_contabil tem teto N1 em Arquitetura do Sistema/1 Visão e Doutrina/01, então este número serve para MANTER o teto honesto, nunca para soltá-lo.';

--
-- Name: golden_criterio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.golden_criterio (
    estagio text NOT NULL,
    n_minimo integer DEFAULT 20 NOT NULL,
    concordancia_minima numeric DEFAULT 0.95 NOT NULL,
    metrica text NOT NULL,
    nota text,
    n_minimo_veredito integer DEFAULT 30 NOT NULL
);

--
-- Name: TABLE golden_criterio; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.golden_criterio IS 'O que "concordância alta e estável" (Arquitetura do Sistema/2 Especificação/f0/06) significa em número, por estágio. n_minimo vem do Arquitetura do Sistema/2 Especificação/f0/06 (~20-30 por tipo core); concordancia_minima é DECISÃO e entra em 0.95 porque é o limiar_auto_clear em vigor desde a 0019 — auto-aceitar a 0.95 com medição abaixo de 0.95 seria apostar acima do que se sabe. Dado, não constante: muda por update.';

--
-- Name: COLUMN golden_criterio.metrica; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.golden_criterio.metrica IS 'Qual das cinco métricas do Arquitetura do Sistema/2 Especificação/f0/06 governa este estágio. É o mapa que fn_golden_suficiente segue, e existe como dado para que acrescentar estágio não exija reescrever aquela função.';

--
-- Name: COLUMN golden_criterio.n_minimo_veredito; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.golden_criterio.n_minimo_veredito IS 'Quantos vereditos de produção este estágio precisa para o dial aceitá-los como base (0136). Maior que n_minimo (20, do Arquitetura do Sistema/2 Especificação/f0/06) de propósito: o veredito de produção vê o palpite da máquina, então é rótulo enviesado, e rótulo enviesado precisa de mais massa para dizer a mesma coisa. DECISÃO, não medição — muda por update, como o 0.95 da 0126.';

--
-- Name: golden_documento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.golden_documento (
    rodada_id uuid NOT NULL,
    documento_id uuid NOT NULL,
    estrato public.golden_estrato NOT NULL,
    origem public.golden_origem NOT NULL,
    incluido_em timestamp with time zone DEFAULT now() NOT NULL,
    incluido_por text,
    nota text
);

--
-- Name: TABLE golden_documento; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.golden_documento IS 'Quais documentos a rodada cobre. A resposta da MÁQUINA para cada um já está em documento/campo_extraido — não existe tabela de predição de propósito: medir contra o estado de produção é medir o sistema, e não uma cópia dele que pode divergir.';

--
-- Name: golden_rodada; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.golden_rodada (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    taxonomia_versao integer NOT NULL,
    criada_em timestamp with time zone DEFAULT now() NOT NULL,
    criada_por text,
    congelada_em timestamp with time zone,
    congelada_por text,
    nota text
);

--
-- Name: TABLE golden_rodada; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.golden_rodada IS 'Rodada de calibração do golden set (Arquitetura do Sistema/2 Especificação/f0/06). Congelada = não aceita mais rótulo; ampliar é rodada nova, nunca edição da anterior — senão a evidência que autorizou uma subida de dial muda depois da subida. taxonomia_versao amarra os rótulos à versão da taxonomia em que foram feitos, porque tipo correto em v1 pode não ser tipo correto em v2.';

--
-- Name: golden_rotulo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.golden_rotulo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    rodada_id uuid NOT NULL,
    documento_id uuid NOT NULL,
    rotulador text NOT NULL,
    tipo_correto text,
    entidade_correta text,
    periodo_correto text,
    assinado_correto boolean,
    legibilidade public.legibilidade,
    item_checklist_correto text,
    rotulado_em timestamp with time zone DEFAULT now() NOT NULL,
    nota text
);

--
-- Name: TABLE golden_rotulo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.golden_rotulo IS 'O ground truth por rotulador (Arquitetura do Sistema/2 Especificação/f0/06, "o que é rotulado"). Campo null = "este rotulador não julgou isto", que NÃO é o mesmo que discordar: entra como item não medido, nunca como acerto.';

--
-- Name: COLUMN golden_rotulo.entidade_correta; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.golden_rotulo.entidade_correta IS 'Razão social como o humano leu NO documento. A comparação usa fn_mesma_entidade (0030), então duas grafias da mesma companhia não contam como erro da máquina nem como discordância entre rotuladores — foi exatamente esse par de grafias que a 0121 mostrou duplicando empresa.';

--
-- Name: indice_macro_expectativa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.indice_macro_expectativa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    serie text NOT NULL,
    fonte text DEFAULT 'BCB/Focus'::text NOT NULL,
    ano_ref integer NOT NULL,
    mediana numeric NOT NULL,
    media numeric,
    respondentes integer,
    coletado_em date NOT NULL,
    registrado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: indice_macro_obs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.indice_macro_obs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    serie text NOT NULL,
    fonte text NOT NULL,
    data_ref date NOT NULL,
    valor numeric NOT NULL,
    coletado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: indice_macro_serie; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.indice_macro_serie (
    codigo text NOT NULL,
    nome text NOT NULL,
    natureza text NOT NULL,
    unidade text NOT NULL,
    descricao text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT indice_macro_serie_natureza_check CHECK ((natureza = ANY (ARRAY['taxa'::text, 'nivel'::text])))
);

--
-- Name: COLUMN indice_macro_serie.natureza; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.indice_macro_serie.natureza IS 'taxa = variação % do mês (o ano acumula por COMPOSIÇÃO); nivel = preço/estoque na data (o ano é o fechamento). Compor nível, ou somar taxa, é erro conceitual.';

--
-- Name: instalacao_cobertura; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instalacao_cobertura (
    id boolean DEFAULT true NOT NULL,
    ate_migration text NOT NULL,
    revisado_em date DEFAULT CURRENT_DATE NOT NULL,
    observacao text NOT NULL,
    CONSTRAINT instalacao_cobertura_id_check CHECK (id)
);

--
-- Name: TABLE instalacao_cobertura; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.instalacao_cobertura IS 'Até que migration o catálogo instalacao_requisito foi revisado. Uma linha só. O Supabase/test/run.sh reprova quando ela fica para trás da migration mais nova — é o mesmo portão do ESTADO.md, e existe porque o catálogo passou 16 migrations parado na 0130 sem que nada acusasse.';

--
-- Name: instalacao_requisito; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.instalacao_requisito (
    chave text NOT NULL,
    migration text NOT NULL,
    tipo text NOT NULL,
    objeto text NOT NULL,
    criterio_seed integer,
    porque text NOT NULL,
    severidade text DEFAULT 'importante'::text NOT NULL,
    ordem integer DEFAULT 100 NOT NULL,
    marcador text,
    CONSTRAINT instalacao_requisito_marcador_check CHECK (((tipo <> 'corpo'::text) OR ((marcador IS NOT NULL) AND (length(marcador) >= 4)))),
    CONSTRAINT instalacao_requisito_severidade_check CHECK ((severidade = ANY (ARRAY['bloqueante'::text, 'importante'::text, 'informativo'::text]))),
    CONSTRAINT instalacao_requisito_tipo_check CHECK ((tipo = ANY (ARRAY['tabela'::text, 'coluna'::text, 'funcao'::text, 'seed'::text, 'comportamento'::text, 'corpo'::text, 'gatilho'::text])))
);

--
-- Name: TABLE instalacao_requisito; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.instalacao_requisito IS 'O que precisa existir no banco de PRODUÇÃO para o portal não mentir — um requisito por linha, com o sintoma visível escrito. Existe porque estes requisitos moravam em prosa no ESTADO.md, onde nada os executa: quem abre o portal não lê o ESTADO.md, e a tela sem a migration não quebra, mostra um traço.';

--
-- Name: COLUMN instalacao_requisito.tipo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instalacao_requisito.tipo IS 'tabela/funcao: o nome. coluna: tabela.coluna. corpo: o nome da função, com marcador de CÓDIGO (pg_get_functiondef tem de conter o trecho). seed: tabela (criterio_seed diz o quanto se espera). comportamento: tabela cuja existência de LINHA é a prova — é o único que não sonda o catálogo, porque alguns requisitos não são de banco (reimportar o workflow do n8n) e só se provam pelo EFEITO: a tabela que aquele nó grava tem linha. gatilho (0189): tabela.nome_do_gatilho — presente exige o gatilho existir E estar habilitado para disparar em sessão normal (tgenabled em ''O'' ou ''A''; ver o ramo da sonda para o porquê de ''R'' não contar). A função do gatilho NÃO serve como prova: ela sobrevive a `drop trigger` e a `alter table ... disable trigger`, que é exatamente o defeito que este tipo fecha (ver gatilho_da_promocao, tipo funcao, cujo próprio `porque` descreve o problema).';

--
-- Name: COLUMN instalacao_requisito.porque; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instalacao_requisito.porque IS 'O SINTOMA VISÍVEL da ausência, não a descrição da migration. É o que torna o painel acionável para quem está com a tela aberta e não com o repositório.';

--
-- Name: COLUMN instalacao_requisito.marcador; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.instalacao_requisito.marcador IS 'Para tipo=''corpo'': o TRECHO que precisa aparecer em pg_get_functiondef(objeto). É a única forma de a sonda distinguir uma função corrigida de uma função homônima com o corpo velho — e essa distinção é a maior parte do catálogo, porque a maioria das migrations recentes só republica corpo.';

--
-- Name: instalacao_sonda_cobertura_de_tipos; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.instalacao_sonda_cobertura_de_tipos AS
 SELECT 1 AS d6_estrito
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.fn_cobertura_de_tipos() c(tipo_taxonomia, obrigatoriedade, exigencias_vivas, estado_declarado, consumidor, consumidor_existe, marcador_presente, veredito)
          WHERE (c.veredito = ANY (ARRAY['SEM_COBERTURA'::text, 'DECLARACAO_QUEBRADA'::text])))));

--
-- Name: VIEW instalacao_sonda_cobertura_de_tipos; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.instalacao_sonda_cobertura_de_tipos IS 'Sonda da 0187: uma linha = D6 estrito verde (todo tipo ativo tem exigência viva ou declaração válida em taxonomia_tipo_cobertura). Zero linhas: select * from fn_cobertura_de_tipos() where veredito in (''SEM_COBERTURA'',''DECLARACAO_QUEBRADA'') diz qual.';

--
-- Name: instalacao_sonda_combinado_estrutural; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.instalacao_sonda_combinado_estrutural AS
 SELECT 1 AS ok
  WHERE ((public.fn_combinado_estrutural_apto('BALANCO'::text, 2) = true) AND (public.fn_combinado_estrutural_apto('DRE'::text, 3) = true) AND (public.fn_combinado_estrutural_apto('FLUXO_CAIXA'::text, 3) = true) AND (public.fn_combinado_estrutural_apto('BALANCO'::text, 0) = false) AND (public.fn_combinado_estrutural_apto('BALANCO'::text, 1) = false) AND (public.fn_combinado_estrutural_apto('MUTUOS'::text, 5) = false) AND (public.fn_combinado_estrutural_apto('DF_AUDITADA'::text, 5) = false));

--
-- Name: VIEW instalacao_sonda_combinado_estrutural; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.instalacao_sonda_combinado_estrutural IS '(0157, achado D da revisão) Autoteste da decisão de fn_combinado_estrutural_apto, EXECUTADA por literais (função pura, sem fixture de documento): 1 linha só se o positivo, o achado A (conteúdo exigido) e o achado B (fonte permitida) valem TODOS ao mesmo tempo. Um marcador textual de corpo/função não pega um "false and" que mate o predicado e deixe os comentários intactos — esta view pega, porque o predicado É executado.';

--
-- Name: instalacao_sonda_entidade_balcao_ambiguo; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.instalacao_sonda_entidade_balcao_ambiguo AS
 SELECT 1 AS ok
  WHERE ((public.fn_entidade_e_balcao_ambiguo('01620000-0000-0000-0000-000000000001'::uuid, '01620000-0000-0000-0000-000000000002'::uuid) = true) AND (public.fn_entidade_e_balcao_ambiguo('01620000-0000-0000-0000-000000000001'::uuid, '01620000-0000-0000-0000-000000000003'::uuid) = false) AND (public.fn_entidade_e_balcao_ambiguo('01620000-0000-0000-0000-000000000001'::uuid, '01620000-0000-0000-0000-000000000004'::uuid) = false) AND (public.fn_entidade_e_balcao_ambiguo('01620000-0000-0000-0000-000000000001'::uuid, '01620000-0000-0000-0000-000000000009'::uuid) = false) AND (public.fn_entidade_e_balcao_ambiguo('01620000-0000-0000-0000-000000000099'::uuid, '01620000-0000-0000-0000-000000000002'::uuid) = false));

--
-- Name: VIEW instalacao_sonda_entidade_balcao_ambiguo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.instalacao_sonda_entidade_balcao_ambiguo IS '(0162) Autoteste de fn_entidade_e_balcao_ambiguo, EXECUTADO contra um fixture PERMANENTE e isolado (o caso "Sonda 0162", que não é mandato real): 1 linha só se a entidade com pendência entidade_ambigua ABERTA responde true, a entidade sem pendência e a com a MESMA pendência RESOLVIDA respondem false, e o predicado não quebra para entidade inexistente nem confunde caso. Um marcador textual de corpo/função não pega um "false and" que mate o predicado e deixe os comentários intactos (achado D da revisão da 0157) — esta view pega, porque o predicado É executado.';

--
-- Name: taxonomia_linha_exigida; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taxonomia_linha_exigida (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo_taxonomia text NOT NULL,
    conceito text NOT NULL,
    rotulo text NOT NULL,
    checagem text NOT NULL,
    secao_canonica text,
    origem text NOT NULL,
    depende_de text[] DEFAULT '{}'::text[] NOT NULL,
    descricao text NOT NULL,
    severidade text,
    sobrepujavel boolean,
    ativo boolean DEFAULT true NOT NULL,
    versao integer DEFAULT 1 NOT NULL,
    escopo_entidade boolean,
    CONSTRAINT taxonomia_linha_exigida_checagem_check CHECK ((checagem = ANY (ARRAY['linha_por_termos'::text, 'secao_presente'::text, 'serie_mensal'::text]))),
    CONSTRAINT taxonomia_linha_exigida_check CHECK (((checagem <> 'secao_presente'::text) OR (secao_canonica IS NOT NULL))),
    CONSTRAINT taxonomia_linha_exigida_origem_check CHECK ((origem = ANY (ARRAY['codigo'::text, 'proposta'::text]))),
    CONSTRAINT taxonomia_linha_exigida_severidade_check CHECK ((severidade = ANY (ARRAY['bloqueante'::text, 'importante'::text])))
);

--
-- Name: TABLE taxonomia_linha_exigida; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.taxonomia_linha_exigida IS 'Linhas/seções que um tipo de documento PRECISA ter para ser utilizável (entrega aprovada, sessão de 13/08/2026). Filha da taxonomia: a taxonomia diz QUAIS tipos são obrigatórios; esta diz O QUE cada tipo precisa conter. Lida pelo Portão 1 (fn_recomputar_completude, passo 2b).';

--
-- Name: COLUMN taxonomia_linha_exigida.checagem; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_exigida.checagem IS 'linha_por_termos = existe linha casando algum localizador; secao_presente = existe linha com a secao_canonica; serie_mensal = existe linha cujo rótulo tem mês (fn_mes_do_rotulo, 0042).';

--
-- Name: COLUMN taxonomia_linha_exigida.origem; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_exigida.origem IS '''codigo'' = a exigência JÁ está hardcoded numa reconciliação vigente (termos copiados literalmente de 0009/0023/0031/0034); ''proposta'' = saiu da análise do estagiário e NENHUMA checagem a lê hoje. Distinção para o revisor ver a diferença sem abrir o documento da entrega.';

--
-- Name: COLUMN taxonomia_linha_exigida.depende_de; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_exigida.depende_de IS 'FATO, não política: qual reconciliação/indicador deixa de funcionar sem esta linha. Insumo para o dono definir severidade linha a linha.';

--
-- Name: COLUMN taxonomia_linha_exigida.severidade; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_exigida.severidade IS 'DECISÃO DO DONO, por linha. NULL = ainda não decidida; o Portão 1 usa então ''importante'' — o mesmo peso que a ausência já tem hoje via precondicao_nao_satisfeita. A migration não endurece nada sozinha.';

--
-- Name: COLUMN taxonomia_linha_exigida.sobrepujavel; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_exigida.sobrepujavel IS 'DECISÃO DO DONO, por linha. NULL = ainda não decidida; o Portão 1 usa então TRUE (sobrepujável, como a precondicao_nao_satisfeita de hoje).';

--
-- Name: COLUMN taxonomia_linha_exigida.escopo_entidade; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_exigida.escopo_entidade IS 'DECISÃO DO DONO, por exigência. NULL (default do seed) = o escopo segue a granularidade do tipo na taxonomia: entidade/entidade_periodo cobram POR ENTIDADE, caso/periodo cobram por caso. true força por entidade (ex.: COMBINADO, granularidade periodo mas linhas com entidade_coluna); false força por caso. Mesmo padrão de severidade/sobrepujavel (0113): a migration não define política.';

--
-- Name: taxonomia_linha_localizador; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taxonomia_linha_localizador (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    exigencia_id uuid NOT NULL,
    ordem integer NOT NULL,
    contra text DEFAULT 'chave'::text NOT NULL,
    termos_inclui text[] NOT NULL,
    termos_exclui text[] DEFAULT '{}'::text[] NOT NULL,
    CONSTRAINT taxonomia_linha_localizador_contra_check CHECK ((contra = ANY (ARRAY['chave'::text, 'secao'::text, 'estrutural'::text, 'coluna'::text])))
);

--
-- Name: TABLE taxonomia_linha_localizador; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.taxonomia_linha_localizador IS 'Tentativas de localização de uma exigência, em cascata (a ordem espelha o código: o caixa do BP tem 7 tentativas na 0031). Formato de fn_valor_conceito (0009): inclui/exclui por substring do texto normalizado. A exigência satisfaz-se quando QUALQUER localizador casa.';

--
-- Name: COLUMN taxonomia_linha_localizador.contra; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_localizador.contra IS '''chave'' = casa contra ce.chave (fn_valor_conceito); ''secao'' = contra ce.secao; ''coluna'' = contra ce.periodo_coluna, o cabeçalho da coluna (0145 — em documento MATRICIAL o conceito é a coluna e a linha é a entidade concreta: no mapa de dívida a chave é o contrato e "Juros do exercício (R$)" é o cabeçalho); ''estrutural'' = fn_rotulo_estrutural.';

--
-- Name: instalacao_sonda_exigencias_0187; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.instalacao_sonda_exigencias_0187 AS
 SELECT e.tipo_taxonomia,
    e.conceito,
    'desativada'::text AS mudanca
   FROM public.taxonomia_linha_exigida e
  WHERE ((e.origem = 'proposta'::text) AND (NOT e.ativo) AND (((e.tipo_taxonomia = 'MUTUOS'::text) AND (e.conceito = 'saldo_de_mutuo'::text)) OR ((e.tipo_taxonomia = 'FAT_INTRAGRUPO'::text) AND (e.conceito = 'faturamento_entre_partes'::text))))
UNION ALL
 SELECT e.tipo_taxonomia,
    e.conceito,
    'localizador_secao'::text AS mudanca
   FROM (public.taxonomia_linha_localizador l
     JOIN public.taxonomia_linha_exigida e ON ((e.id = l.exigencia_id)))
  WHERE ((e.tipo_taxonomia = 'CONTRATO_SOCIAL'::text) AND (e.conceito = 'capital_social'::text) AND e.ativo AND (l.contra = 'secao'::text) AND (l.termos_inclui = ARRAY['capital'::text, 'social'::text]));

--
-- Name: VIEW instalacao_sonda_exigencias_0187; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.instalacao_sonda_exigencias_0187 IS 'Sonda da 0187: MUTUOS/saldo_de_mutuo e FAT_INTRAGRUPO/faturamento_entre_partes desativadas + o localizador por seção de CONTRATO_SOCIAL/capital_social. Três linhas.';

--
-- Name: taxonomia_linha_alternativa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taxonomia_linha_alternativa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    exigencia_id uuid NOT NULL,
    ordem integer NOT NULL,
    contra text DEFAULT 'chave'::text NOT NULL,
    termos_inclui text[] NOT NULL,
    termos_exclui text[] DEFAULT '{}'::text[] NOT NULL,
    recado text NOT NULL,
    CONSTRAINT taxonomia_linha_alternativa_contra_check CHECK ((contra = ANY (ARRAY['chave'::text, 'secao'::text, 'coluna'::text]))),
    CONSTRAINT taxonomia_linha_alternativa_recado_check CHECK ((length(btrim(recado)) > 0)),
    CONSTRAINT taxonomia_linha_alternativa_termos_inclui_check CHECK ((cardinality(termos_inclui) > 0))
);

--
-- Name: TABLE taxonomia_linha_alternativa; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.taxonomia_linha_alternativa IS '0188: o que um documento pode trazer NO LUGAR de uma linha exigida, e o recado que a pendência linha_exigida_ausente passa a dar quando isso acontece. A alternativa NUNCA satisfaz a exigência (a linha exigida continua ausente e a pendência continua aberta) — ela só troca o "não localizada, confira o rótulo" pelo motivo real e o remédio. Casamento no formato de taxonomia_linha_localizador (substring do texto normalizado).';

--
-- Name: COLUMN taxonomia_linha_alternativa.recado; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_alternativa.recado IS 'O que a pendência diz quando a alternativa casa: o que o documento traz, o efeito, e o que pedir. Vai inteiro na descrição (fn_descricao_linha_exigida).';

--
-- Name: instalacao_sonda_exigencias_0188; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.instalacao_sonda_exigencias_0188 AS
 SELECT e.tipo_taxonomia,
    e.conceito,
    'alternativa_resultado_liquido'::text AS mudanca
   FROM (public.taxonomia_linha_alternativa a
     JOIN public.taxonomia_linha_exigida e ON ((e.id = a.exigencia_id)))
  WHERE ((e.tipo_taxonomia = 'DRE'::text) AND (e.conceito = 'despesa_financeira'::text) AND e.ativo AND (a.termos_inclui = ARRAY['resultado'::text, 'financeiro'::text]))
UNION ALL
 SELECT e.tipo_taxonomia,
    e.conceito,
    'localizador_juros_bancarios'::text AS mudanca
   FROM (public.taxonomia_linha_localizador l
     JOIN public.taxonomia_linha_exigida e ON ((e.id = l.exigencia_id)))
  WHERE ((e.tipo_taxonomia = 'DRE'::text) AND (e.conceito = 'despesa_financeira'::text) AND e.ativo AND (l.contra = 'chave'::text) AND (l.termos_inclui = ARRAY['juros'::text, 'bancari'::text]));

--
-- Name: VIEW instalacao_sonda_exigencias_0188; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.instalacao_sonda_exigencias_0188 IS 'Sonda da 0188: a alternativa "resultado financeiro" de DRE/despesa_financeira e o localizador ["juros","bancari"] da mesma exigência. Duas linhas.';

--
-- Name: instalacao_sonda_modelagem_pronta; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.instalacao_sonda_modelagem_pronta AS
 SELECT 1 AS ok
  WHERE ((public.fn_modelagem_esta_pronta(true, (6)::bigint, 0, (23)::bigint) = true) AND (public.fn_modelagem_esta_pronta(false, (6)::bigint, 0, (23)::bigint) = false) AND (public.fn_modelagem_esta_pronta(true, (0)::bigint, 0, (23)::bigint) = false) AND (public.fn_modelagem_esta_pronta(true, (6)::bigint, 1, (23)::bigint) = false) AND (public.fn_modelagem_esta_pronta(true, (6)::bigint, 0, (0)::bigint) = false));

--
-- Name: VIEW instalacao_sonda_modelagem_pronta; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.instalacao_sonda_modelagem_pronta IS '(0158) Autoteste da decisão de fn_modelagem_esta_pronta, EXECUTADA por literais (função pura, sem fixture de caso nem documento): 1 linha só se o positivo e as quatro negações — sem parâmetro, sem premissa ativa, premissa sem valor, e ZERO linha vinculada — valem todas ao mesmo tempo. Um marcador textual de corpo/função não pega um "false and" que mate o predicado e deixe os comentários intactos; esta view pega, porque o predicado É executado (achado D da revisão da 0157).';

--
-- Name: instalacao_sonda_modelagem_versao_vigente; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.instalacao_sonda_modelagem_versao_vigente AS
 SELECT 1 AS ok
  WHERE ((( SELECT l.valor_ultimo
           FROM public.fn_linhas_para_modelagem('01640000-0000-0000-0000-000000000001'::uuid) l(secao_canonica, chave, rotulo_norm, entidade, valor_ultimo, n_ocorrencias, papel, unidade, moeda, documentos, sobreposicao_suspeita)
          WHERE (l.rotulo_norm = public.fn_normalizar_texto('Sonda 0164 caixa e equivalentes'::text))) = (250)::numeric) AND (( SELECT l.n_ocorrencias
           FROM public.fn_linhas_para_modelagem('01640000-0000-0000-0000-000000000001'::uuid) l(secao_canonica, chave, rotulo_norm, entidade, valor_ultimo, n_ocorrencias, papel, unidade, moeda, documentos, sobreposicao_suspeita)
          WHERE (l.rotulo_norm = public.fn_normalizar_texto('Sonda 0164 caixa e equivalentes'::text))) = 1) AND (( SELECT l.valor_ultimo
           FROM public.fn_linhas_para_modelagem('01640000-0000-0000-0000-000000000001'::uuid) l(secao_canonica, chave, rotulo_norm, entidade, valor_ultimo, n_ocorrencias, papel, unidade, moeda, documentos, sobreposicao_suspeita)
          WHERE (l.rotulo_norm = public.fn_normalizar_texto('Sonda 0164 fornecedores a pagar'::text))) = (777)::numeric));

--
-- Name: VIEW instalacao_sonda_modelagem_versao_vigente; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.instalacao_sonda_modelagem_versao_vigente IS '(0164) Autoteste de fn_linhas_para_modelagem, EXECUTADO contra um fixture PERMANENTE e isolado (o caso "Sonda 0164", que não é mandato real) com dois documentos multi-versão: 1 linha só se a reextração que CORRIGE o valor (v2 substitui v1, sem somar nem duplicar) e a reextração AINDA EM ANDAMENTO (v2 sem campo_extraido, a vigente continua v1) resolvem certo ao mesmo tempo. Prova que a CTE versao_vigente (0164, join que substituiu o filtro opaco fn_versao_com_extracao) preserva a regra da 0102 — não prova que o PLANO é bom (isso é papel de Supabase/test/modelagem_versao_vigente_escala.test.sql, que só roda em CI/dev): prova que a reescrita não regrediu a semântica.';

--
-- Name: instalacao_sonda_passivo_bare; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.instalacao_sonda_passivo_bare AS
 SELECT l.id,
    e.tipo_taxonomia
   FROM (public.taxonomia_linha_localizador l
     JOIN public.taxonomia_linha_exigida e ON ((e.id = l.exigencia_id)))
  WHERE ((e.conceito = 'passivo_mais_pl'::text) AND (l.contra = 'estrutural'::text) AND (l.termos_inclui = ARRAY['passivo'::text]));

--
-- Name: VIEW instalacao_sonda_passivo_bare; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.instalacao_sonda_passivo_bare IS 'Sonda da 0166: os localizadores que casam o rótulo "PASSIVO" sozinho. Duas linhas (BALANCO e COMBINADO) — zero significa que o Kit Básico volta a cobrar do cliente uma linha que ele já entregou.';

--
-- Name: instalacao_sonda_rotulo_contraditorio; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.instalacao_sonda_rotulo_contraditorio AS
 SELECT 1 AS ok
  WHERE ((public.fn_documento_decide_sozinho('COMBINADO'::text, true) = false) AND (public.fn_documento_decide_sozinho('COMBINADO'::text, false) = true) AND (public.fn_documento_decide_sozinho('COMBINADO'::text, NULL::boolean) = true) AND (public.fn_documento_decide_sozinho('BALANCO'::text, true) = true) AND (public.fn_documento_decide_sozinho('RAZAO'::text, true) = true));

--
-- Name: VIEW instalacao_sonda_rotulo_contraditorio; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.instalacao_sonda_rotulo_contraditorio IS '(0159) Autoteste de fn_documento_decide_sozinho, EXECUTADA por literais (função pura, sem fixture de documento nem de pendência): 1 linha só se o caso medido (COMBINADO com tipo_incorreto aberta), o caso comum (COMBINADO sem pendência, decide sozinho), o NULL (coalesce trata como ausente), o espelho da 0155 (BALANCO com tipo_incorreto continua decidindo sozinho — é a autoridade que cai, não a confiança) e o irrelevante (RAZAO, nunca se autodeclarou derivado) valem todos ao mesmo tempo. Um marcador textual de corpo/função não pega um "false and" que mate o predicado e deixe os comentários intactos (achado D da revisão da 0157) — esta view pega, porque o predicado É executado.';

--
-- Name: instalacao_sonda_saldo_mutuos; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.instalacao_sonda_saldo_mutuos AS
 WITH casos(arranjo, linhas, esperado) AS (
         VALUES ('canastra_par_de_empresas_e_TOTAL'::text,jsonb_build_array(jsonb_build_object('chave', 'CANASTRA PARTICIPAÇÕES S.A. → CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'valor', 11160, 'unidade', 'milhar', 'coluna', '2025'), jsonb_build_object('chave', 'CANASTRA PARTICIPAÇÕES S.A. → CANASTRA COMERCIAL E DISTRIBUIDORA LTDA.', 'valor', 4900, 'unidade', 'milhar', 'coluna', '2025'), jsonb_build_object('chave', 'TOTAL', 'valor', 16060, 'unidade', 'milhar', 'coluna', '2025')),(16060)::numeric), ('itens_e_total_geral'::text,jsonb_build_array(jsonb_build_object('chave', 'Mútuo a receber - Beta', 'valor', 100, 'unidade', 'milhar'), jsonb_build_object('chave', 'Mútuo a pagar - Gama', 'valor', 50, 'unidade', 'milhar'), jsonb_build_object('chave', 'Saldo total dos mútuos', 'valor', 150, 'unidade', 'milhar')),(150)::numeric), ('matricial_saldo_juros_saldo'::text,jsonb_build_array(jsonb_build_object('chave', 'Alfa → Beta', 'valor', 7991, 'unidade', 'milhar', 'coluna', 'Saldo 2024'), jsonb_build_object('chave', 'Alfa → Beta', 'valor', 1088, 'unidade', 'milhar', 'coluna', 'Juros'), jsonb_build_object('chave', 'Alfa → Beta', 'valor', 11079, 'unidade', 'milhar', 'coluna', 'Saldo 2025')),(11079)::numeric), ('duas_colunas_sem_exercicio'::text,jsonb_build_array(jsonb_build_object('chave', 'Alfa → Beta', 'valor', 100, 'unidade', 'milhar', 'coluna', 'Saldo inicial'), jsonb_build_object('chave', 'Alfa → Beta', 'valor', 120, 'unidade', 'milhar', 'coluna', 'Saldo final')),NULL::numeric)
        )
 SELECT c.arranjo
   FROM (casos c
     CROSS JOIN LATERAL ( SELECT public.fn_saldo_mutuos_do_documento(c.linhas) AS r) x)
  WHERE
        CASE
            WHEN (c.esperado IS NULL) THEN (((x.r ->> 'valor'::text) IS NULL) AND (COALESCE((x.r ->> 'porque'::text), ''::text) <> ''::text))
            ELSE (((x.r ->> 'valor'::text))::numeric = c.esperado)
        END;

--
-- Name: VIEW instalacao_sonda_saldo_mutuos; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.instalacao_sonda_saldo_mutuos IS 'Sonda da 0187 (revisão): uma linha por arranjo em que fn_saldo_mutuos_do_documento dá o saldo CERTO (canastra real 16.060; item + total 150; matricial 11.079; sem exercício → não apura). Quatro linhas.';

--
-- Name: lote_execucao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lote_execucao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    execucao_ref text NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    documentos integer,
    documentos_com_classificacao integer,
    documentos_fatiados integer,
    documentos_com_falha integer,
    documentos_sem_medicao integer,
    custo_total_usd numeric(12,6),
    custo_extracao_usd numeric(12,6),
    custo_classificacao_usd numeric(12,6),
    custo_estimado_usd numeric(12,6),
    tokens_entrada bigint,
    tokens_saida bigint,
    tokens_cache bigint,
    linhas_extraidas integer,
    contas_nos_documentos integer,
    contas_extraidas integer,
    cobertura numeric(6,4),
    orcamento_versao text,
    fechado_em timestamp with time zone,
    documentos_planejados integer,
    chamadas_planejadas integer,
    cota_fracao_planejada numeric(6,4)
);

--
-- Name: TABLE lote_execucao; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.lote_execucao IS 'Uma linha por execução de ingestão: quanto custou de IA, quantos tokens, quantas linhas e que cobertura. Existe porque o custo era calculado e morria na saída do nó do n8n — ninguém respondia "quanto gastamos neste mandato". A chave (caso_id, execucao_ref) é o que impede o custo de sair DOBRADO: o Resumo de Custo roda uma vez por ramo, as duas com o total inteiro.';

--
-- Name: COLUMN lote_execucao.cobertura; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lote_execucao.cobertura IS 'contas_extraidas / contas_nos_documentos, 0..1. NULL quando a camada 1 não conseguiu medir o texto do PDF — e NULL aqui é honesto: sem medição não há cobertura, e 0 diria o contrário.';

--
-- Name: COLUMN lote_execucao.fechado_em; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lote_execucao.fechado_em IS 'Quando a cadeia chegou ao fim. NULO significa que a execução começou e não terminou — cancelada, morta por cota, ou parada num nó. Antes desta coluna, "começou e morreu" e "nunca rodou" tinham a mesma aparência: nenhuma linha na tabela.';

--
-- Name: COLUMN lote_execucao.chamadas_planejadas; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.lote_execucao.chamadas_planejadas IS 'Chamadas de IA que o Orcamento do Lote previu, contando os blocos do fatiamento. Comparada com o consumo real, é o que diz se o estimador acerta; sozinha, é o que diz quanto da cota do dia esta execução reservou antes de começar.';

--
-- Name: pendencia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pendencia (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    origem_estagio text,
    tipo public.pendencia_tipo NOT NULL,
    severidade public.pendencia_severidade NOT NULL,
    estado public.pendencia_estado DEFAULT 'aberta'::public.pendencia_estado NOT NULL,
    descricao text,
    documento_id uuid,
    entidade_id uuid,
    periodo_id uuid,
    sobrepujavel boolean DEFAULT true NOT NULL,
    expira_em timestamp with time zone,
    motivo text,
    criada_em timestamp with time zone DEFAULT now() NOT NULL,
    resolvida_em timestamp with time zone,
    resolvida_por text
);

--
-- Name: pergunta_catalogo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pergunta_catalogo (
    codigo text NOT NULL,
    titulo text NOT NULL,
    pergunta text NOT NULL,
    motivo text NOT NULL,
    risco text NOT NULL,
    impacto text NOT NULL,
    prioridade integer NOT NULL,
    gatilho_especie text NOT NULL,
    gatilho_tipo_taxonomia text,
    gatilho_conceito text,
    gatilho_descricao text NOT NULL,
    fonte text NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    versao integer DEFAULT 1 NOT NULL,
    CONSTRAINT pergunta_catalogo_check CHECK (((gatilho_especie = 'sempre'::text) = ((gatilho_tipo_taxonomia IS NULL) AND (gatilho_conceito IS NULL)))),
    CONSTRAINT pergunta_catalogo_gatilho_especie_check CHECK ((gatilho_especie = ANY (ARRAY['exigencia_ausente'::text, 'linha_presente'::text, 'sempre'::text]))),
    CONSTRAINT pergunta_catalogo_prioridade_check CHECK (((prioridade >= 1) AND (prioridade <= 4)))
);

--
-- Name: TABLE pergunta_catalogo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.pergunta_catalogo IS 'Banco de perguntas ao cliente (onboarding cap. 10 + análise aprovada, sessão de 13/08/2026). Texto VERBATIM da entrega. gatilho_especie é o que o motor avalia; gatilho_descricao é a condição como a entrega a descreveu — insumo das espécies futuras (ver cabeçalho da 0120).';

--
-- Name: COLUMN pergunta_catalogo.prioridade; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pergunta_catalogo.prioridade IS '1 crítica … 4 contextual — dado da entrega. NENHUM comportamento é atrelado a ela (corte, envio automático, teto seriam política do dono); a função de sugestão apenas ordena por ela.';

--
-- Name: COLUMN pergunta_catalogo.gatilho_descricao; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pergunta_catalogo.gatilho_descricao IS 'O gatilho nas palavras da ENTREGA, inclusive quando pede espécie que ainda não existe. Fato, não configuração: é daqui que as espécies futuras (reconciliação, comparação, limiar…) saem.';

--
-- Name: perimetro; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.perimetro (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    entidade_id uuid NOT NULL,
    escopo text NOT NULL,
    desde date NOT NULL,
    ate date,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT perimetro_intervalo_valido CHECK (((ate IS NULL) OR (ate >= desde)))
);

--
-- Name: TABLE perimetro; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.perimetro IS '0180 (fatia 1.4 do plano F1): quem entra no COMBINADO de um caso, por escopo e por intervalo de tempo. `escopo` é texto livre (o nome do combinado — não há vocabulário fechado medido ainda, mesmo raciocínio de `periodo.tipo`). `ate` NULL = ainda vigente. NÃO é derivada de `entidade.papel_no_grupo` (0179) — ligar as duas é decisão de F4 (consolidação), fora do escopo desta migration. O único caminho de escrita é `fn_perimetro_definir_escopo`.';

--
-- Name: COLUMN perimetro.escopo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.perimetro.escopo IS '0180: o nome do COMBINADO a que este período de perímetro pertence (texto livre, como `periodo.tipo`) — inventar um enum aqui seria estrutura sem medição (regra 1 do CLAUDE.md).';

--
-- Name: COLUMN perimetro.ate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.perimetro.ate IS '0180: NULL = ainda vigente. Trocar o escopo de uma entidade (fn_perimetro_definir_escopo) FECHA este campo no intervalo anterior — nunca sobrescreve silenciosamente — porque um perímetro sem data mente sobre o exercício anterior (roadmap, fatia 1.4).';

--
-- Name: periodo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.periodo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    tipo text NOT NULL,
    referencia text NOT NULL
);

--
-- Name: reconciliacao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reconciliacao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    entidade_id uuid,
    periodo_id uuid,
    tipo text NOT NULL,
    classe text DEFAULT 'A'::text NOT NULL,
    fonte_a jsonb,
    fonte_b jsonb,
    precondicoes_ok boolean NOT NULL,
    resultado text NOT NULL,
    divergencia_abs numeric,
    divergencia_pct numeric,
    materialidade jsonb,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    motivo_precondicao text,
    documento_id uuid,
    descricao text,
    periodo_chave_id uuid
);

--
-- Name: COLUMN reconciliacao.motivo_precondicao; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reconciliacao.motivo_precondicao IS 'O motivo que o emissor passou ANTES do achatamento de resultado, quando a checagem NÃO concluiu; NULL quando concluiu (ok/divergente/divergencia/zona_cinzenta). NENHUM DOS DOIS MOTIVOS PROVA PRESENÇA OU AUSÊNCIA DE DOCUMENTO, e quem construir tela sobre esta coluna precisa saber disso. documento_ausente NÃO é confiável como "a contraparte não foi entregue": fn_reconciliar_arvore (0133) o emite com documento_id NÃO-NULO para "este documento não tem seção com filhos", e fn_reconciliar_mutuos (0123) o emite para "planilha de mútuos presente, mas nenhum balanço traz conta de mútuo com lado reconhecível" — nos dois o documento FOI entregue. Medido no banco de teste: 42 linhas de secao_fecha e 9 de mutuos_planilha_vs_balanco com este motivo e documento presente. O que documento_ausente garante é só o que o código faz com ele: NÃO abre pendência. precondicao_nao_satisfeita como MOTIVO significa apenas "o emissor não especificou o motivo" — NÃO AUTORIZA concluir que o documento estava presente: é o mesmo literal que o legado (0009/0022, antes da reescrita da 0023 de fn_reconciliar_ativo_passivo_pl) usava tanto para documento ausente quanto para documento presente com linha não localizada, e é esse literal que o backfill grava a partir de evento_auditoria para as linhas antigas. Ver o CONTRATO no cabeçalho da 0186 para a lista completa de valores reconhecidos.';

--
-- Name: COLUMN reconciliacao.documento_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reconciliacao.documento_id IS 'O documento que a checagem recebeu (p_documento_id de fn_registrar_reconciliacao), ou NULL. Só é CRITÉRIO para os tipos POR DOCUMENTO (hoje secao_fecha): ali a pendência e o estado vigente são por documento. Nos demais tipos é o documento REPRESENTATIVO que o emissor escolheu e não distingue nada. NULL também nas linhas anteriores à 0192 e quando o documento foi apagado (on delete set null).';

--
-- Name: COLUMN reconciliacao.descricao; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reconciliacao.descricao IS 'O texto que o emissor deu ao achado (p_descricao), gravado SEMPRE — inclusive quando a checagem NÃO abre pendência (ok, documento_ausente, estágio em sombra). É o que separa "não conferiu, e por quê" de "conferiu e fechou". NULL nas linhas anteriores à 0192: o texto delas não existe em lugar nenhum (ausência, não string vazia).';

--
-- Name: COLUMN reconciliacao.periodo_chave_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.reconciliacao.periodo_chave_id IS 'O período da CHAVE que originou a chamada (o período do documento que o laço de fn_reconciliar_caso / fn_reconciliar_chaves_do_documento estava visitando), que NÃO é o `periodo_id` quando o laço DESCEU para um período compatível de outra entidade. É por esta coluna que a guarda de fn_registrar_reconciliacao lê o ESTADO VIGENTE de cada chave. NULL nas linhas anteriores à 0192 (não bloqueiam a resolução: ninguém sabe de que chave vieram) e quando o período foi apagado (on delete set null).';

--
-- Name: rubrica_classe; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rubrica_classe (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    padrao text NOT NULL,
    classe_codigo text NOT NULL,
    secao_canonica text,
    tipo_taxonomia text,
    especificidade integer DEFAULT 100 NOT NULL,
    confianca numeric DEFAULT 1.0 NOT NULL,
    justificativa text NOT NULL,
    versao integer DEFAULT 1 NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: TABLE rubrica_classe; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.rubrica_classe IS 'Mapeamento rubrica -> classe contábil: a "condição 2" do Arquitetura do Sistema/2 Especificação/05 ("bate com um padrão conhecido pré-registrado"). Semeado SÓ com rubricas medidas nos dois books e no caso de referência — rubrica imaginada criaria uma segunda régua. justificativa é NOT NULL porque o Arquitetura do Sistema/2 Especificação/05 exige justificativa em toda sugestão, e a da sugestão é a da regra que a produziu.';

--
-- Name: COLUMN rubrica_classe.padrao; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rubrica_classe.padrao IS 'Casado contra fn_normalizar_texto(chave) por CONTENÇÃO de substring normalizada. Não é regex: padrão de regex em tabela editável por humano é a porta para uma linha quebrar a classificação do caso inteiro sem ninguém saber por quê.';

--
-- Name: COLUMN rubrica_classe.especificidade; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.rubrica_classe.especificidade IS 'Desempate: mais ALTO ganha. Regra com seção e tipo declarados é mais específica que a genérica, e sem desempate declarado duas regras que casam a mesma linha dariam resultado dependente da ordem em que o banco devolveu — que é a forma de erro que a 0125 corrigiu na proveniência.';

--
-- Name: taxonomia_tipo_cobertura; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taxonomia_tipo_cobertura (
    tipo_taxonomia text NOT NULL,
    estado text NOT NULL,
    consumidor text,
    motivo text NOT NULL,
    efeito text NOT NULL,
    declarado_em date DEFAULT CURRENT_DATE NOT NULL,
    marcador text,
    marcador_em text,
    CONSTRAINT taxonomia_tipo_cobertura_check CHECK (((estado = 'consumidor_nomeado'::text) = (consumidor IS NOT NULL))),
    CONSTRAINT taxonomia_tipo_cobertura_check1 CHECK (((estado = 'consumidor_nomeado'::text) = ((marcador IS NOT NULL) AND (marcador_em IS NOT NULL)))),
    CONSTRAINT taxonomia_tipo_cobertura_check2 CHECK (((marcador IS NULL) = (marcador_em IS NULL))),
    CONSTRAINT taxonomia_tipo_cobertura_efeito_check CHECK ((length(btrim(efeito)) > 0)),
    CONSTRAINT taxonomia_tipo_cobertura_estado_check CHECK ((estado = ANY (ARRAY['consumidor_nomeado'::text, 'sem_consumidor'::text]))),
    CONSTRAINT taxonomia_tipo_cobertura_marcador_check CHECK (((marcador IS NULL) OR (length(btrim(marcador)) > 0))),
    CONSTRAINT taxonomia_tipo_cobertura_motivo_check CHECK ((length(btrim(motivo)) > 0))
);

--
-- Name: TABLE taxonomia_tipo_cobertura; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.taxonomia_tipo_cobertura IS '0187 (portão D6): para cada tipo ATIVO sem exigência viva (taxonomia_linha_exigida ativa com origem=codigo), QUEM confere o número dele — ou a declaração de que ninguém confere, com o motivo e o EFEITO (o que passa sem aviso). Desempate (fn_conflitos_do_caso, 0151) e soma para premissa (fn_linhas_do_realizado, 0150) NÃO contam como consumidor: leem, não conferem. Conferida por fn_cobertura_de_tipos().';

--
-- Name: COLUMN taxonomia_tipo_cobertura.consumidor; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_tipo_cobertura.consumidor IS 'Nome (proname, schema public) da função SQL que LÊ documentos do tipo e CONFERE o número. Obrigatório quando estado=consumidor_nomeado, NULL caso contrário. Se a função sumir, fn_cobertura_de_tipos devolve DECLARACAO_QUEBRADA.';

--
-- Name: COLUMN taxonomia_tipo_cobertura.efeito; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_tipo_cobertura.efeito IS 'O que deixa de ser conferido por causa desta declaração (regra 1 do CLAUDE.md): "não tem consumidor" sem o efeito é ausência apresentada como dado.';

--
-- Name: COLUMN taxonomia_tipo_cobertura.marcador; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_tipo_cobertura.marcador IS 'Trecho de UMA linha que precisa aparecer no corpo publicado (pg_get_functiondef, \r removido) da função marcador_em para a declaração valer: é o que prova que ela AINDA lê o tipo. Obrigatório quando estado=consumidor_nomeado. Some do corpo → DECLARACAO_QUEBRADA.';

--
-- Name: COLUMN taxonomia_tipo_cobertura.marcador_em; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_tipo_cobertura.marcador_em IS 'proname (schema public) da função cujo corpo carrega o marcador — o consumidor ou o despachante que o chama para o tipo (BALANCETE: fn_reconciliar_por_documento).';

--
-- Name: taxonomia_tipo_documento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taxonomia_tipo_documento (
    codigo text NOT NULL,
    categoria text NOT NULL,
    documento text NOT NULL,
    obrigatoriedade public.obrigatoriedade NOT NULL,
    granularidade public.granularidade NOT NULL,
    vigencia text,
    sensibilidade public.sensibilidade_lgpd DEFAULT 'nenhuma'::public.sensibilidade_lgpd NOT NULL,
    versao integer DEFAULT 1 NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    nao_sobrepujavel boolean DEFAULT false NOT NULL,
    abertura_analitica boolean DEFAULT false NOT NULL,
    autoridade smallint DEFAULT 0 NOT NULL
);

--
-- Name: TABLE taxonomia_tipo_documento; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.taxonomia_tipo_documento IS 'Taxonomia documental v1 (Arquitetura do Sistema/2 Especificação/f0/03). Kit Básico = obrigatorio; Variáveis = complementar.';

--
-- Name: COLUMN taxonomia_tipo_documento.abertura_analitica; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_tipo_documento.abertura_analitica IS 'Este tipo REAFIRMA aberta uma conta que uma demonstração já declara (o balancete abre o balanço; o aging abre clientes; o extrato abre bancos). Linha que só aparece em documento assim NÃO entra na soma do realizado: somá-la conta a mesma conta duas vezes. `false` é o padrão seguro — o tipo novo entra somando, e quem o cadastra decide.';

--
-- Name: COLUMN taxonomia_tipo_documento.autoridade; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_tipo_documento.autoridade IS 'Peso da EVIDÊNCIA deste tipo de documento quando dois documentos do mesmo período discordam sobre a mesma conta (0151). Maior vence, e o motivo vai por extenso na pendência. 0 = o catálogo não declarou autoridade para este tipo: ele não decide (dois zeros empatam e a decisão volta para o humano). Nada é apagado em nenhum caso — o perdedor é a evidência de que houve escolha.';

--
-- Name: arquivo_oficial arquivo_oficial_caso_hash_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.arquivo_oficial
    ADD CONSTRAINT arquivo_oficial_caso_hash_uk UNIQUE (caso_id, hash_sha256);

--
-- Name: arquivo_oficial_lancamento_mes arquivo_oficial_lancamento_mes_uk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.arquivo_oficial_lancamento_mes
    ADD CONSTRAINT arquivo_oficial_lancamento_mes_uk UNIQUE NULLS NOT DISTINCT (arquivo_oficial_id, conta, mes, ind_lcto);

--
-- Name: arquivo_oficial arquivo_oficial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.arquivo_oficial
    ADD CONSTRAINT arquivo_oficial_pkey PRIMARY KEY (id);

--
-- Name: arquivo_oficial_registro arquivo_oficial_registro_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.arquivo_oficial_registro
    ADD CONSTRAINT arquivo_oficial_registro_pkey PRIMARY KEY (arquivo_oficial_id, linha);

--
-- Name: campo_classe_override campo_classe_override_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campo_classe_override
    ADD CONSTRAINT campo_classe_override_pkey PRIMARY KEY (id);

--
-- Name: campo_classe_sugerida campo_classe_sugerida_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campo_classe_sugerida
    ADD CONSTRAINT campo_classe_sugerida_pkey PRIMARY KEY (id);

--
-- Name: campo_extraido campo_extraido_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campo_extraido
    ADD CONSTRAINT campo_extraido_pkey PRIMARY KEY (id);

--
-- Name: caso_apresentacao_campo caso_apresentacao_campo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_apresentacao_campo
    ADD CONSTRAINT caso_apresentacao_campo_pkey PRIMARY KEY (caso_id, chave);

--
-- Name: caso_linha_premissa caso_linha_premissa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_linha_premissa
    ADD CONSTRAINT caso_linha_premissa_pkey PRIMARY KEY (id);

--
-- Name: caso_modelagem caso_modelagem_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_modelagem
    ADD CONSTRAINT caso_modelagem_pkey PRIMARY KEY (caso_id);

--
-- Name: caso_pergunta caso_pergunta_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_pergunta
    ADD CONSTRAINT caso_pergunta_pkey PRIMARY KEY (id);

--
-- Name: caso caso_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso
    ADD CONSTRAINT caso_pkey PRIMARY KEY (id);

--
-- Name: caso_premissa caso_premissa_caso_id_premissa_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_premissa
    ADD CONSTRAINT caso_premissa_caso_id_premissa_codigo_key UNIQUE (caso_id, premissa_codigo);

--
-- Name: caso_premissa caso_premissa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_premissa
    ADD CONSTRAINT caso_premissa_pkey PRIMARY KEY (id);

--
-- Name: checklist_item_status checklist_item_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item_status
    ADD CONSTRAINT checklist_item_status_pkey PRIMARY KEY (id);

--
-- Name: classe_contabil_catalogo classe_contabil_catalogo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classe_contabil_catalogo
    ADD CONSTRAINT classe_contabil_catalogo_pkey PRIMARY KEY (codigo);

--
-- Name: controlador controlador_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.controlador
    ADD CONSTRAINT controlador_pkey PRIMARY KEY (id);

--
-- Name: decisao decisao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decisao
    ADD CONSTRAINT decisao_pkey PRIMARY KEY (id);

--
-- Name: documento_fato documento_fato_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento_fato
    ADD CONSTRAINT documento_fato_pkey PRIMARY KEY (id);

--
-- Name: documento documento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_pkey PRIMARY KEY (id);

--
-- Name: documento_versao documento_versao_documento_id_n_versao_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento_versao
    ADD CONSTRAINT documento_versao_documento_id_n_versao_key UNIQUE (documento_id, n_versao);

--
-- Name: documento_versao documento_versao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento_versao
    ADD CONSTRAINT documento_versao_pkey PRIMARY KEY (id);

--
-- Name: entidade_controlador entidade_controlador_par_unico; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entidade_controlador
    ADD CONSTRAINT entidade_controlador_par_unico UNIQUE (entidade_id, controlador_id);

--
-- Name: entidade_controlador entidade_controlador_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entidade_controlador
    ADD CONSTRAINT entidade_controlador_pkey PRIMARY KEY (id);

--
-- Name: entidade entidade_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entidade
    ADD CONSTRAINT entidade_pkey PRIMARY KEY (id);

--
-- Name: estagio_autonomia estagio_autonomia_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estagio_autonomia
    ADD CONSTRAINT estagio_autonomia_pkey PRIMARY KEY (estagio);

--
-- Name: evento_auditoria evento_auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evento_auditoria
    ADD CONSTRAINT evento_auditoria_pkey PRIMARY KEY (id);

--
-- Name: execucao_falha execucao_falha_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execucao_falha
    ADD CONSTRAINT execucao_falha_pkey PRIMARY KEY (id);

--
-- Name: fato_tipo_catalogo fato_tipo_catalogo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fato_tipo_catalogo
    ADD CONSTRAINT fato_tipo_catalogo_pkey PRIMARY KEY (tipo);

--
-- Name: golden_campo golden_campo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_campo
    ADD CONSTRAINT golden_campo_pkey PRIMARY KEY (id);

--
-- Name: golden_criterio golden_criterio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_criterio
    ADD CONSTRAINT golden_criterio_pkey PRIMARY KEY (estagio);

--
-- Name: golden_documento golden_documento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_documento
    ADD CONSTRAINT golden_documento_pkey PRIMARY KEY (rodada_id, documento_id);

--
-- Name: golden_rodada golden_rodada_nome_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_rodada
    ADD CONSTRAINT golden_rodada_nome_key UNIQUE (nome);

--
-- Name: golden_rodada golden_rodada_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_rodada
    ADD CONSTRAINT golden_rodada_pkey PRIMARY KEY (id);

--
-- Name: golden_rotulo golden_rotulo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_rotulo
    ADD CONSTRAINT golden_rotulo_pkey PRIMARY KEY (id);

--
-- Name: golden_rotulo golden_rotulo_rodada_id_documento_id_rotulador_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_rotulo
    ADD CONSTRAINT golden_rotulo_rodada_id_documento_id_rotulador_key UNIQUE (rodada_id, documento_id, rotulador);

--
-- Name: indice_macro_expectativa indice_macro_expectativa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_expectativa
    ADD CONSTRAINT indice_macro_expectativa_pkey PRIMARY KEY (id);

--
-- Name: indice_macro_expectativa indice_macro_expectativa_serie_ano_ref_coletado_em_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_expectativa
    ADD CONSTRAINT indice_macro_expectativa_serie_ano_ref_coletado_em_key UNIQUE (serie, ano_ref, coletado_em);

--
-- Name: indice_macro_obs indice_macro_obs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_obs
    ADD CONSTRAINT indice_macro_obs_pkey PRIMARY KEY (id);

--
-- Name: indice_macro_obs indice_macro_obs_serie_fonte_data_ref_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_obs
    ADD CONSTRAINT indice_macro_obs_serie_fonte_data_ref_key UNIQUE (serie, fonte, data_ref);

--
-- Name: indice_macro_serie indice_macro_serie_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_serie
    ADD CONSTRAINT indice_macro_serie_pkey PRIMARY KEY (codigo);

--
-- Name: instalacao_cobertura instalacao_cobertura_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instalacao_cobertura
    ADD CONSTRAINT instalacao_cobertura_pkey PRIMARY KEY (id);

--
-- Name: instalacao_requisito instalacao_requisito_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.instalacao_requisito
    ADD CONSTRAINT instalacao_requisito_pkey PRIMARY KEY (chave);

--
-- Name: lote_execucao lote_execucao_caso_id_execucao_ref_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote_execucao
    ADD CONSTRAINT lote_execucao_caso_id_execucao_ref_key UNIQUE (caso_id, execucao_ref);

--
-- Name: lote_execucao lote_execucao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote_execucao
    ADD CONSTRAINT lote_execucao_pkey PRIMARY KEY (id);

--
-- Name: pendencia pendencia_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pendencia
    ADD CONSTRAINT pendencia_pkey PRIMARY KEY (id);

--
-- Name: pergunta_catalogo pergunta_catalogo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pergunta_catalogo
    ADD CONSTRAINT pergunta_catalogo_pkey PRIMARY KEY (codigo);

--
-- Name: perimetro perimetro_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perimetro
    ADD CONSTRAINT perimetro_pkey PRIMARY KEY (id);

--
-- Name: periodo periodo_caso_id_tipo_referencia_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.periodo
    ADD CONSTRAINT periodo_caso_id_tipo_referencia_key UNIQUE (caso_id, tipo, referencia);

--
-- Name: periodo periodo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.periodo
    ADD CONSTRAINT periodo_pkey PRIMARY KEY (id);

--
-- Name: premissa_catalogo premissa_catalogo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.premissa_catalogo
    ADD CONSTRAINT premissa_catalogo_pkey PRIMARY KEY (codigo);

--
-- Name: reconciliacao reconciliacao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliacao
    ADD CONSTRAINT reconciliacao_pkey PRIMARY KEY (id);

--
-- Name: rubrica_classe rubrica_classe_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rubrica_classe
    ADD CONSTRAINT rubrica_classe_pkey PRIMARY KEY (id);

--
-- Name: taxonomia_linha_alternativa taxonomia_linha_alternativa_exigencia_id_ordem_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_alternativa
    ADD CONSTRAINT taxonomia_linha_alternativa_exigencia_id_ordem_key UNIQUE (exigencia_id, ordem);

--
-- Name: taxonomia_linha_alternativa taxonomia_linha_alternativa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_alternativa
    ADD CONSTRAINT taxonomia_linha_alternativa_pkey PRIMARY KEY (id);

--
-- Name: taxonomia_linha_exigida taxonomia_linha_exigida_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_exigida
    ADD CONSTRAINT taxonomia_linha_exigida_pkey PRIMARY KEY (id);

--
-- Name: taxonomia_linha_exigida taxonomia_linha_exigida_tipo_taxonomia_conceito_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_exigida
    ADD CONSTRAINT taxonomia_linha_exigida_tipo_taxonomia_conceito_key UNIQUE (tipo_taxonomia, conceito);

--
-- Name: taxonomia_linha_localizador taxonomia_linha_localizador_exigencia_id_ordem_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_localizador
    ADD CONSTRAINT taxonomia_linha_localizador_exigencia_id_ordem_key UNIQUE (exigencia_id, ordem);

--
-- Name: taxonomia_linha_localizador taxonomia_linha_localizador_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_localizador
    ADD CONSTRAINT taxonomia_linha_localizador_pkey PRIMARY KEY (id);

--
-- Name: taxonomia_tipo_cobertura taxonomia_tipo_cobertura_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_tipo_cobertura
    ADD CONSTRAINT taxonomia_tipo_cobertura_pkey PRIMARY KEY (tipo_taxonomia);

--
-- Name: taxonomia_tipo_documento taxonomia_tipo_documento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_tipo_documento
    ADD CONSTRAINT taxonomia_tipo_documento_pkey PRIMARY KEY (codigo);

--
-- Name: arquivo_oficial_caso_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX arquivo_oficial_caso_idx ON public.arquivo_oficial USING btree (caso_id, familia);

--
-- Name: arquivo_oficial_lancamento_mes_arq_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX arquivo_oficial_lancamento_mes_arq_idx ON public.arquivo_oficial_lancamento_mes USING btree (arquivo_oficial_id);

--
-- Name: arquivo_oficial_registro_tipo_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX arquivo_oficial_registro_tipo_idx ON public.arquivo_oficial_registro USING btree (arquivo_oficial_id, registro);

--
-- Name: arquivo_oficial_uma_vigente_por_chave; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX arquivo_oficial_uma_vigente_por_chave ON public.arquivo_oficial USING btree (caso_id, chave_natural) WHERE vigente;

--
-- Name: controlador_caso_documento_unico; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX controlador_caso_documento_unico ON public.controlador USING btree (caso_id, documento) WHERE (documento IS NOT NULL);

--
-- Name: INDEX controlador_caso_documento_unico; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.controlador_caso_documento_unico IS '0182: o mesmo documento não pode virar dois controladores diferentes no mesmo caso — duplicaria a contagem da guarda de soma sem decisão nenhuma. Documento NULL não colide com nada (vários controladores sem documento informado são permitidos).';

--
-- Name: documento_fato_versao_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX documento_fato_versao_idx ON public.documento_fato USING btree (documento_versao_id);

--
-- Name: entidade_caso_cnpj_unico; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX entidade_caso_cnpj_unico ON public.entidade USING btree (caso_id, cnpj) WHERE (cnpj IS NOT NULL);

--
-- Name: INDEX entidade_caso_cnpj_unico; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.entidade_caso_cnpj_unico IS 'A regra 1 da 0169 afirmada pelo BANCO: dentro de um caso, um CNPJ identifica UMA entidade. Sem ela, duas chamadas concorrentes de fn_upsert_entidade inserem as duas.';

--
-- Name: idx_campo_classe_override_campo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campo_classe_override_campo ON public.campo_classe_override USING btree (campo_extraido_id, criado_em DESC);

--
-- Name: idx_campo_classe_sugerida_campo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campo_classe_sugerida_campo ON public.campo_classe_sugerida USING btree (campo_extraido_id, criado_em DESC);

--
-- Name: idx_campo_docversao; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campo_docversao ON public.campo_extraido USING btree (documento_versao_id);

--
-- Name: idx_campo_extraido_origem_valor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campo_extraido_origem_valor ON public.campo_extraido USING btree (documento_versao_id, origem_valor);

--
-- Name: idx_campo_extraido_versao_ordem; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campo_extraido_versao_ordem ON public.campo_extraido USING btree (documento_versao_id, ordem);

--
-- Name: idx_caso_ativos; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_caso_ativos ON public.caso USING btree (criado_em DESC) WHERE (fechado_em IS NULL);

--
-- Name: idx_caso_linha_premissa_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_caso_linha_premissa_caso ON public.caso_linha_premissa USING btree (caso_id);

--
-- Name: idx_caso_linha_premissa_unica; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_caso_linha_premissa_unica ON public.caso_linha_premissa USING btree (caso_id, rotulo_norm, COALESCE(entidade, ''::text), COALESCE(secao_canonica, ''::text));

--
-- Name: idx_caso_pergunta_caso_codigo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_caso_pergunta_caso_codigo ON public.caso_pergunta USING btree (caso_id, pergunta_codigo);

--
-- Name: idx_caso_premissa_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_caso_premissa_caso ON public.caso_premissa USING btree (caso_id);

--
-- Name: idx_checklist_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklist_caso ON public.checklist_item_status USING btree (caso_id);

--
-- Name: idx_controlador_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_controlador_caso ON public.controlador USING btree (caso_id);

--
-- Name: idx_decisao_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_decisao_caso ON public.decisao USING btree (caso_id);

--
-- Name: idx_documento_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_documento_caso ON public.documento USING btree (caso_id);

--
-- Name: idx_documento_versao_hash_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_documento_versao_hash_fingerprint ON public.documento_versao USING btree (hash, fingerprint_extracao) WHERE ((hash IS NOT NULL) AND (fingerprint_extracao IS NOT NULL));

--
-- Name: idx_docversao_documento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_docversao_documento ON public.documento_versao USING btree (documento_id);

--
-- Name: idx_entidade_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entidade_caso ON public.entidade USING btree (caso_id);

--
-- Name: idx_entidade_controlador_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entidade_controlador_caso ON public.entidade_controlador USING btree (caso_id);

--
-- Name: idx_entidade_controlador_controlador; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entidade_controlador_controlador ON public.entidade_controlador USING btree (controlador_id);

--
-- Name: idx_entidade_controlador_entidade; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entidade_controlador_entidade ON public.entidade_controlador USING btree (entidade_id);

--
-- Name: idx_evento_entidade_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_evento_entidade_ref ON public.evento_auditoria USING btree (entidade_ref);

--
-- Name: idx_execucao_falha_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_execucao_falha_caso ON public.execucao_falha USING btree (caso_id, criado_em DESC);

--
-- Name: idx_execucao_falha_nome; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_execucao_falha_nome ON public.execucao_falha USING btree (lower(caso_nome), criado_em DESC);

--
-- Name: idx_golden_campo_unico; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_golden_campo_unico ON public.golden_campo USING btree (rodada_id, documento_id, rotulador, chave, COALESCE(periodo_coluna, ''::text), COALESCE(entidade_coluna, ''::text));

--
-- Name: idx_golden_documento_rodada; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_golden_documento_rodada ON public.golden_documento USING btree (rodada_id, origem);

--
-- Name: idx_indice_macro_exp_serie_ano; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_indice_macro_exp_serie_ano ON public.indice_macro_expectativa USING btree (serie, ano_ref, coletado_em DESC);

--
-- Name: idx_indice_macro_obs_serie_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_indice_macro_obs_serie_data ON public.indice_macro_obs USING btree (serie, data_ref);

--
-- Name: idx_lote_execucao_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lote_execucao_caso ON public.lote_execucao USING btree (caso_id, criado_em DESC);

--
-- Name: idx_pendencia_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pendencia_caso ON public.pendencia USING btree (caso_id);

--
-- Name: idx_pendencia_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pendencia_estado ON public.pendencia USING btree (estado);

--
-- Name: idx_perimetro_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_perimetro_caso ON public.perimetro USING btree (caso_id);

--
-- Name: idx_perimetro_entidade; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_perimetro_entidade ON public.perimetro USING btree (entidade_id);

--
-- Name: idx_periodo_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_periodo_caso ON public.periodo USING btree (caso_id);

--
-- Name: idx_reconciliacao_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reconciliacao_caso ON public.reconciliacao USING btree (caso_id);

--
-- Name: idx_reconciliacao_vigente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reconciliacao_vigente ON public.reconciliacao USING btree (caso_id, tipo, periodo_chave_id, criado_em DESC);

--
-- Name: idx_rubrica_classe_unica; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_rubrica_classe_unica ON public.rubrica_classe USING btree (padrao, COALESCE(secao_canonica, ''::text), COALESCE(tipo_taxonomia, ''::text), versao);

--
-- Name: perimetro_atual_unico; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX perimetro_atual_unico ON public.perimetro USING btree (caso_id, entidade_id, escopo) WHERE (ate IS NULL);

--
-- Name: decisao trg_auto_promover_dial; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_auto_promover_dial AFTER INSERT ON public.decisao FOR EACH ROW EXECUTE FUNCTION public.fn_trg_auto_promover_dial();

--
-- Name: documento trg_entidade_ambigua; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_entidade_ambigua AFTER INSERT OR UPDATE OF entidade_id ON public.documento FOR EACH ROW EXECUTE FUNCTION public.fn_trg_entidade_ambigua();

--
-- Name: entidade_controlador trg_entidade_controlador_soma_maxima; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_entidade_controlador_soma_maxima AFTER INSERT OR UPDATE OF percentual, entidade_id ON public.entidade_controlador FOR EACH ROW WHEN ((new.percentual IS NOT NULL)) EXECUTE FUNCTION public.fn_trg_entidade_controlador_soma_maxima();

--
-- Name: entidade trg_entidade_forma_de_controle_tem_vinculo; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_entidade_forma_de_controle_tem_vinculo AFTER INSERT OR UPDATE OF forma_de_controle ON public.entidade FOR EACH ROW WHEN ((new.forma_de_controle = 'controle_comum'::public.entidade_forma_de_controle)) EXECUTE FUNCTION public.fn_trg_entidade_forma_de_controle_tem_vinculo();

--
-- Name: golden_campo trg_golden_campo_congelada; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_golden_campo_congelada BEFORE INSERT OR UPDATE ON public.golden_campo FOR EACH ROW EXECUTE FUNCTION public.fn_golden_rodada_congelada();

--
-- Name: golden_documento trg_golden_documento_congelada; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_golden_documento_congelada BEFORE INSERT OR UPDATE ON public.golden_documento FOR EACH ROW EXECUTE FUNCTION public.fn_golden_rodada_congelada();

--
-- Name: golden_rodada trg_golden_rodada_imutavel; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_golden_rodada_imutavel BEFORE UPDATE ON public.golden_rodada FOR EACH ROW EXECUTE FUNCTION public.fn_golden_rodada_congelada_imutavel();

--
-- Name: golden_rotulo trg_golden_rotulo_congelada; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_golden_rotulo_congelada BEFORE INSERT OR UPDATE ON public.golden_rotulo FOR EACH ROW EXECUTE FUNCTION public.fn_golden_rodada_congelada();

--
-- Name: instalacao_cobertura trg_instalacao_cobertura_nao_regride; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_instalacao_cobertura_nao_regride BEFORE UPDATE OF ate_migration ON public.instalacao_cobertura FOR EACH ROW EXECUTE FUNCTION public.fn_trg_instalacao_cobertura_nao_regride();

--
-- Name: arquivo_oficial arquivo_oficial_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.arquivo_oficial
    ADD CONSTRAINT arquivo_oficial_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: arquivo_oficial arquivo_oficial_documento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.arquivo_oficial
    ADD CONSTRAINT arquivo_oficial_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES public.documento(id) ON DELETE SET NULL;

--
-- Name: arquivo_oficial_lancamento_mes arquivo_oficial_lancamento_mes_arquivo_oficial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.arquivo_oficial_lancamento_mes
    ADD CONSTRAINT arquivo_oficial_lancamento_mes_arquivo_oficial_id_fkey FOREIGN KEY (arquivo_oficial_id) REFERENCES public.arquivo_oficial(id) ON DELETE CASCADE;

--
-- Name: arquivo_oficial_registro arquivo_oficial_registro_arquivo_oficial_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.arquivo_oficial_registro
    ADD CONSTRAINT arquivo_oficial_registro_arquivo_oficial_id_fkey FOREIGN KEY (arquivo_oficial_id) REFERENCES public.arquivo_oficial(id) ON DELETE CASCADE;

--
-- Name: arquivo_oficial arquivo_oficial_substituido_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.arquivo_oficial
    ADD CONSTRAINT arquivo_oficial_substituido_por_fkey FOREIGN KEY (substituido_por) REFERENCES public.arquivo_oficial(id) ON DELETE SET NULL;

--
-- Name: campo_classe_override campo_classe_override_campo_extraido_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campo_classe_override
    ADD CONSTRAINT campo_classe_override_campo_extraido_id_fkey FOREIGN KEY (campo_extraido_id) REFERENCES public.campo_extraido(id) ON DELETE CASCADE;

--
-- Name: campo_classe_override campo_classe_override_classe_final_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campo_classe_override
    ADD CONSTRAINT campo_classe_override_classe_final_fkey FOREIGN KEY (classe_final) REFERENCES public.classe_contabil_catalogo(codigo);

--
-- Name: campo_classe_sugerida campo_classe_sugerida_campo_extraido_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campo_classe_sugerida
    ADD CONSTRAINT campo_classe_sugerida_campo_extraido_id_fkey FOREIGN KEY (campo_extraido_id) REFERENCES public.campo_extraido(id) ON DELETE CASCADE;

--
-- Name: campo_classe_sugerida campo_classe_sugerida_classe_codigo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campo_classe_sugerida
    ADD CONSTRAINT campo_classe_sugerida_classe_codigo_fkey FOREIGN KEY (classe_codigo) REFERENCES public.classe_contabil_catalogo(codigo);

--
-- Name: campo_classe_sugerida campo_classe_sugerida_rubrica_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campo_classe_sugerida
    ADD CONSTRAINT campo_classe_sugerida_rubrica_id_fkey FOREIGN KEY (rubrica_id) REFERENCES public.rubrica_classe(id);

--
-- Name: campo_extraido campo_extraido_documento_versao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campo_extraido
    ADD CONSTRAINT campo_extraido_documento_versao_id_fkey FOREIGN KEY (documento_versao_id) REFERENCES public.documento_versao(id) ON DELETE CASCADE;

--
-- Name: caso_apresentacao_campo caso_apresentacao_campo_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_apresentacao_campo
    ADD CONSTRAINT caso_apresentacao_campo_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: caso_linha_premissa caso_linha_premissa_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_linha_premissa
    ADD CONSTRAINT caso_linha_premissa_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: caso_linha_premissa caso_linha_premissa_premissa_codigo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_linha_premissa
    ADD CONSTRAINT caso_linha_premissa_premissa_codigo_fkey FOREIGN KEY (premissa_codigo) REFERENCES public.premissa_catalogo(codigo);

--
-- Name: caso_linha_premissa caso_linha_premissa_sazonalidade_codigo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_linha_premissa
    ADD CONSTRAINT caso_linha_premissa_sazonalidade_codigo_fkey FOREIGN KEY (sazonalidade_codigo) REFERENCES public.premissa_catalogo(codigo);

--
-- Name: caso_modelagem caso_modelagem_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_modelagem
    ADD CONSTRAINT caso_modelagem_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: caso_pergunta caso_pergunta_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_pergunta
    ADD CONSTRAINT caso_pergunta_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: caso_pergunta caso_pergunta_entidade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_pergunta
    ADD CONSTRAINT caso_pergunta_entidade_id_fkey FOREIGN KEY (entidade_id) REFERENCES public.entidade(id);

--
-- Name: caso_pergunta caso_pergunta_pergunta_codigo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_pergunta
    ADD CONSTRAINT caso_pergunta_pergunta_codigo_fkey FOREIGN KEY (pergunta_codigo) REFERENCES public.pergunta_catalogo(codigo);

--
-- Name: caso_premissa caso_premissa_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_premissa
    ADD CONSTRAINT caso_premissa_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: caso_premissa caso_premissa_premissa_codigo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_premissa
    ADD CONSTRAINT caso_premissa_premissa_codigo_fkey FOREIGN KEY (premissa_codigo) REFERENCES public.premissa_catalogo(codigo);

--
-- Name: checklist_item_status checklist_item_status_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item_status
    ADD CONSTRAINT checklist_item_status_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: checklist_item_status checklist_item_status_documento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item_status
    ADD CONSTRAINT checklist_item_status_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES public.documento(id);

--
-- Name: checklist_item_status checklist_item_status_entidade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item_status
    ADD CONSTRAINT checklist_item_status_entidade_id_fkey FOREIGN KEY (entidade_id) REFERENCES public.entidade(id);

--
-- Name: checklist_item_status checklist_item_status_periodo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item_status
    ADD CONSTRAINT checklist_item_status_periodo_id_fkey FOREIGN KEY (periodo_id) REFERENCES public.periodo(id);

--
-- Name: checklist_item_status checklist_item_status_tipo_taxonomia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item_status
    ADD CONSTRAINT checklist_item_status_tipo_taxonomia_fkey FOREIGN KEY (tipo_taxonomia) REFERENCES public.taxonomia_tipo_documento(codigo);

--
-- Name: controlador controlador_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.controlador
    ADD CONSTRAINT controlador_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: decisao decisao_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decisao
    ADD CONSTRAINT decisao_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: documento documento_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: documento documento_entidade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_entidade_id_fkey FOREIGN KEY (entidade_id) REFERENCES public.entidade(id);

--
-- Name: documento_fato documento_fato_documento_versao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento_fato
    ADD CONSTRAINT documento_fato_documento_versao_id_fkey FOREIGN KEY (documento_versao_id) REFERENCES public.documento_versao(id) ON DELETE CASCADE;

--
-- Name: documento_fato documento_fato_tipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento_fato
    ADD CONSTRAINT documento_fato_tipo_fkey FOREIGN KEY (tipo) REFERENCES public.fato_tipo_catalogo(tipo);

--
-- Name: documento documento_periodo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_periodo_id_fkey FOREIGN KEY (periodo_id) REFERENCES public.periodo(id);

--
-- Name: documento documento_tipo_taxonomia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_tipo_taxonomia_fkey FOREIGN KEY (tipo_taxonomia) REFERENCES public.taxonomia_tipo_documento(codigo);

--
-- Name: documento_versao documento_versao_documento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento_versao
    ADD CONSTRAINT documento_versao_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES public.documento(id) ON DELETE CASCADE;

--
-- Name: entidade entidade_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entidade
    ADD CONSTRAINT entidade_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: entidade_controlador entidade_controlador_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entidade_controlador
    ADD CONSTRAINT entidade_controlador_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: entidade_controlador entidade_controlador_controlador_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entidade_controlador
    ADD CONSTRAINT entidade_controlador_controlador_id_fkey FOREIGN KEY (controlador_id) REFERENCES public.controlador(id) ON DELETE CASCADE;

--
-- Name: entidade_controlador entidade_controlador_entidade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entidade_controlador
    ADD CONSTRAINT entidade_controlador_entidade_id_fkey FOREIGN KEY (entidade_id) REFERENCES public.entidade(id) ON DELETE CASCADE;

--
-- Name: entidade entidade_controladora_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entidade
    ADD CONSTRAINT entidade_controladora_id_fkey FOREIGN KEY (controladora_id) REFERENCES public.entidade(id);

--
-- Name: estagio_autonomia estagio_autonomia_medicao_rodada_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estagio_autonomia
    ADD CONSTRAINT estagio_autonomia_medicao_rodada_id_fkey FOREIGN KEY (medicao_rodada_id) REFERENCES public.golden_rodada(id);

--
-- Name: execucao_falha execucao_falha_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execucao_falha
    ADD CONSTRAINT execucao_falha_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: golden_campo golden_campo_rodada_id_documento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_campo
    ADD CONSTRAINT golden_campo_rodada_id_documento_id_fkey FOREIGN KEY (rodada_id, documento_id) REFERENCES public.golden_documento(rodada_id, documento_id) ON DELETE CASCADE;

--
-- Name: golden_criterio golden_criterio_estagio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_criterio
    ADD CONSTRAINT golden_criterio_estagio_fkey FOREIGN KEY (estagio) REFERENCES public.estagio_autonomia(estagio) ON DELETE CASCADE;

--
-- Name: golden_documento golden_documento_documento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_documento
    ADD CONSTRAINT golden_documento_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES public.documento(id) ON DELETE CASCADE;

--
-- Name: golden_documento golden_documento_rodada_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_documento
    ADD CONSTRAINT golden_documento_rodada_id_fkey FOREIGN KEY (rodada_id) REFERENCES public.golden_rodada(id) ON DELETE CASCADE;

--
-- Name: golden_rotulo golden_rotulo_rodada_id_documento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.golden_rotulo
    ADD CONSTRAINT golden_rotulo_rodada_id_documento_id_fkey FOREIGN KEY (rodada_id, documento_id) REFERENCES public.golden_documento(rodada_id, documento_id) ON DELETE CASCADE;

--
-- Name: indice_macro_expectativa indice_macro_expectativa_serie_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_expectativa
    ADD CONSTRAINT indice_macro_expectativa_serie_fkey FOREIGN KEY (serie) REFERENCES public.indice_macro_serie(codigo);

--
-- Name: indice_macro_obs indice_macro_obs_serie_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_obs
    ADD CONSTRAINT indice_macro_obs_serie_fkey FOREIGN KEY (serie) REFERENCES public.indice_macro_serie(codigo);

--
-- Name: lote_execucao lote_execucao_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote_execucao
    ADD CONSTRAINT lote_execucao_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: pendencia pendencia_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pendencia
    ADD CONSTRAINT pendencia_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: pendencia pendencia_documento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pendencia
    ADD CONSTRAINT pendencia_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES public.documento(id);

--
-- Name: pendencia pendencia_entidade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pendencia
    ADD CONSTRAINT pendencia_entidade_id_fkey FOREIGN KEY (entidade_id) REFERENCES public.entidade(id);

--
-- Name: pendencia pendencia_periodo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pendencia
    ADD CONSTRAINT pendencia_periodo_id_fkey FOREIGN KEY (periodo_id) REFERENCES public.periodo(id);

--
-- Name: pergunta_catalogo pergunta_catalogo_gatilho_tipo_taxonomia_gatilho_conceito_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pergunta_catalogo
    ADD CONSTRAINT pergunta_catalogo_gatilho_tipo_taxonomia_gatilho_conceito_fkey FOREIGN KEY (gatilho_tipo_taxonomia, gatilho_conceito) REFERENCES public.taxonomia_linha_exigida(tipo_taxonomia, conceito);

--
-- Name: perimetro perimetro_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perimetro
    ADD CONSTRAINT perimetro_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: perimetro perimetro_entidade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perimetro
    ADD CONSTRAINT perimetro_entidade_id_fkey FOREIGN KEY (entidade_id) REFERENCES public.entidade(id) ON DELETE CASCADE;

--
-- Name: periodo periodo_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.periodo
    ADD CONSTRAINT periodo_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: reconciliacao reconciliacao_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliacao
    ADD CONSTRAINT reconciliacao_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: reconciliacao reconciliacao_documento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliacao
    ADD CONSTRAINT reconciliacao_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES public.documento(id) ON DELETE SET NULL;

--
-- Name: reconciliacao reconciliacao_entidade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliacao
    ADD CONSTRAINT reconciliacao_entidade_id_fkey FOREIGN KEY (entidade_id) REFERENCES public.entidade(id);

--
-- Name: reconciliacao reconciliacao_periodo_chave_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliacao
    ADD CONSTRAINT reconciliacao_periodo_chave_id_fkey FOREIGN KEY (periodo_chave_id) REFERENCES public.periodo(id) ON DELETE SET NULL;

--
-- Name: reconciliacao reconciliacao_periodo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliacao
    ADD CONSTRAINT reconciliacao_periodo_id_fkey FOREIGN KEY (periodo_id) REFERENCES public.periodo(id);

--
-- Name: rubrica_classe rubrica_classe_classe_codigo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rubrica_classe
    ADD CONSTRAINT rubrica_classe_classe_codigo_fkey FOREIGN KEY (classe_codigo) REFERENCES public.classe_contabil_catalogo(codigo);

--
-- Name: taxonomia_linha_alternativa taxonomia_linha_alternativa_exigencia_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_alternativa
    ADD CONSTRAINT taxonomia_linha_alternativa_exigencia_id_fkey FOREIGN KEY (exigencia_id) REFERENCES public.taxonomia_linha_exigida(id) ON DELETE CASCADE;

--
-- Name: taxonomia_linha_exigida taxonomia_linha_exigida_tipo_taxonomia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_exigida
    ADD CONSTRAINT taxonomia_linha_exigida_tipo_taxonomia_fkey FOREIGN KEY (tipo_taxonomia) REFERENCES public.taxonomia_tipo_documento(codigo);

--
-- Name: taxonomia_linha_localizador taxonomia_linha_localizador_exigencia_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_localizador
    ADD CONSTRAINT taxonomia_linha_localizador_exigencia_id_fkey FOREIGN KEY (exigencia_id) REFERENCES public.taxonomia_linha_exigida(id) ON DELETE CASCADE;

--
-- Name: taxonomia_tipo_cobertura taxonomia_tipo_cobertura_tipo_taxonomia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_tipo_cobertura
    ADD CONSTRAINT taxonomia_tipo_cobertura_tipo_taxonomia_fkey FOREIGN KEY (tipo_taxonomia) REFERENCES public.taxonomia_tipo_documento(codigo);

--
-- Name: arquivo_oficial; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.arquivo_oficial ENABLE ROW LEVEL SECURITY;

--
-- Name: arquivo_oficial arquivo_oficial_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY arquivo_oficial_authenticated_all ON public.arquivo_oficial TO authenticated USING (true) WITH CHECK (true);

--
-- Name: arquivo_oficial_lancamento_mes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.arquivo_oficial_lancamento_mes ENABLE ROW LEVEL SECURITY;

--
-- Name: arquivo_oficial_lancamento_mes arquivo_oficial_lancamento_mes_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY arquivo_oficial_lancamento_mes_authenticated_all ON public.arquivo_oficial_lancamento_mes TO authenticated USING (true) WITH CHECK (true);

--
-- Name: arquivo_oficial_registro; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.arquivo_oficial_registro ENABLE ROW LEVEL SECURITY;

--
-- Name: arquivo_oficial_registro arquivo_oficial_registro_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY arquivo_oficial_registro_authenticated_all ON public.arquivo_oficial_registro TO authenticated USING (true) WITH CHECK (true);

--
-- Name: campo_classe_override; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.campo_classe_override ENABLE ROW LEVEL SECURITY;

--
-- Name: campo_classe_override campo_classe_override_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY campo_classe_override_insert ON public.campo_classe_override FOR INSERT TO authenticated WITH CHECK (true);

--
-- Name: campo_classe_override campo_classe_override_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY campo_classe_override_read ON public.campo_classe_override FOR SELECT TO authenticated USING (true);

--
-- Name: campo_classe_sugerida; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.campo_classe_sugerida ENABLE ROW LEVEL SECURITY;

--
-- Name: campo_classe_sugerida campo_classe_sugerida_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY campo_classe_sugerida_insert ON public.campo_classe_sugerida FOR INSERT TO authenticated WITH CHECK (true);

--
-- Name: campo_classe_sugerida campo_classe_sugerida_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY campo_classe_sugerida_read ON public.campo_classe_sugerida FOR SELECT TO authenticated USING (true);

--
-- Name: campo_extraido; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.campo_extraido ENABLE ROW LEVEL SECURITY;

--
-- Name: campo_extraido campo_extraido_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY campo_extraido_authenticated_all ON public.campo_extraido TO authenticated USING (true) WITH CHECK (true);

--
-- Name: caso; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.caso ENABLE ROW LEVEL SECURITY;

--
-- Name: caso_apresentacao_campo; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.caso_apresentacao_campo ENABLE ROW LEVEL SECURITY;

--
-- Name: caso_apresentacao_campo caso_apresentacao_campo_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY caso_apresentacao_campo_authenticated_all ON public.caso_apresentacao_campo TO authenticated USING (true) WITH CHECK (true);

--
-- Name: caso caso_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY caso_authenticated_all ON public.caso TO authenticated USING (true) WITH CHECK (true);

--
-- Name: caso_linha_premissa; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.caso_linha_premissa ENABLE ROW LEVEL SECURITY;

--
-- Name: caso_linha_premissa caso_linha_premissa_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY caso_linha_premissa_authenticated_all ON public.caso_linha_premissa TO authenticated USING (true) WITH CHECK (true);

--
-- Name: caso_modelagem; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.caso_modelagem ENABLE ROW LEVEL SECURITY;

--
-- Name: caso_modelagem caso_modelagem_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY caso_modelagem_authenticated_all ON public.caso_modelagem TO authenticated USING (true) WITH CHECK (true);

--
-- Name: caso_pergunta; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.caso_pergunta ENABLE ROW LEVEL SECURITY;

--
-- Name: caso_pergunta caso_pergunta_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY caso_pergunta_insert ON public.caso_pergunta FOR INSERT TO authenticated WITH CHECK (true);

--
-- Name: caso_pergunta caso_pergunta_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY caso_pergunta_read ON public.caso_pergunta FOR SELECT TO authenticated USING (true);

--
-- Name: caso_premissa; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.caso_premissa ENABLE ROW LEVEL SECURITY;

--
-- Name: caso_premissa caso_premissa_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY caso_premissa_authenticated_all ON public.caso_premissa TO authenticated USING (true) WITH CHECK (true);

--
-- Name: checklist_item_status; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.checklist_item_status ENABLE ROW LEVEL SECURITY;

--
-- Name: checklist_item_status checklist_item_status_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY checklist_item_status_authenticated_all ON public.checklist_item_status TO authenticated USING (true) WITH CHECK (true);

--
-- Name: classe_contabil_catalogo; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.classe_contabil_catalogo ENABLE ROW LEVEL SECURITY;

--
-- Name: classe_contabil_catalogo classe_contabil_catalogo_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY classe_contabil_catalogo_read ON public.classe_contabil_catalogo FOR SELECT TO authenticated USING (true);

--
-- Name: controlador; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.controlador ENABLE ROW LEVEL SECURITY;

--
-- Name: controlador controlador_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY controlador_read ON public.controlador FOR SELECT TO authenticated USING (true);

--
-- Name: decisao; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.decisao ENABLE ROW LEVEL SECURITY;

--
-- Name: decisao decisao_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY decisao_authenticated_all ON public.decisao TO authenticated USING (true) WITH CHECK (true);

--
-- Name: documento; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.documento ENABLE ROW LEVEL SECURITY;

--
-- Name: documento documento_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY documento_authenticated_all ON public.documento TO authenticated USING (true) WITH CHECK (true);

--
-- Name: documento_fato; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.documento_fato ENABLE ROW LEVEL SECURITY;

--
-- Name: documento_fato documento_fato_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY documento_fato_authenticated_all ON public.documento_fato TO authenticated USING (true) WITH CHECK (true);

--
-- Name: documento_versao; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.documento_versao ENABLE ROW LEVEL SECURITY;

--
-- Name: documento_versao documento_versao_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY documento_versao_authenticated_all ON public.documento_versao TO authenticated USING (true) WITH CHECK (true);

--
-- Name: entidade; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.entidade ENABLE ROW LEVEL SECURITY;

--
-- Name: entidade entidade_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY entidade_authenticated_all ON public.entidade TO authenticated USING (true) WITH CHECK (true);

--
-- Name: entidade_controlador; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.entidade_controlador ENABLE ROW LEVEL SECURITY;

--
-- Name: entidade_controlador entidade_controlador_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY entidade_controlador_read ON public.entidade_controlador FOR SELECT TO authenticated USING (true);

--
-- Name: estagio_autonomia; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.estagio_autonomia ENABLE ROW LEVEL SECURITY;

--
-- Name: estagio_autonomia estagio_autonomia_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY estagio_autonomia_authenticated_all ON public.estagio_autonomia TO authenticated USING (true) WITH CHECK (true);

--
-- Name: evento_auditoria; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.evento_auditoria ENABLE ROW LEVEL SECURITY;

--
-- Name: evento_auditoria evento_auditoria_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY evento_auditoria_insert ON public.evento_auditoria FOR INSERT TO authenticated WITH CHECK (true);

--
-- Name: evento_auditoria evento_auditoria_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY evento_auditoria_read ON public.evento_auditoria FOR SELECT TO authenticated USING (true);

--
-- Name: execucao_falha; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.execucao_falha ENABLE ROW LEVEL SECURITY;

--
-- Name: execucao_falha execucao_falha_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY execucao_falha_authenticated_all ON public.execucao_falha TO authenticated USING (true) WITH CHECK (true);

--
-- Name: fato_tipo_catalogo; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fato_tipo_catalogo ENABLE ROW LEVEL SECURITY;

--
-- Name: fato_tipo_catalogo fato_tipo_catalogo_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY fato_tipo_catalogo_read ON public.fato_tipo_catalogo FOR SELECT TO authenticated USING (true);

--
-- Name: golden_campo; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.golden_campo ENABLE ROW LEVEL SECURITY;

--
-- Name: golden_campo golden_campo_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY golden_campo_insert ON public.golden_campo FOR INSERT TO authenticated WITH CHECK (true);

--
-- Name: golden_campo golden_campo_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY golden_campo_read ON public.golden_campo FOR SELECT TO authenticated USING (true);

--
-- Name: golden_documento; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.golden_documento ENABLE ROW LEVEL SECURITY;

--
-- Name: golden_documento golden_documento_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY golden_documento_insert ON public.golden_documento FOR INSERT TO authenticated WITH CHECK (true);

--
-- Name: golden_documento golden_documento_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY golden_documento_read ON public.golden_documento FOR SELECT TO authenticated USING (true);

--
-- Name: golden_rodada; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.golden_rodada ENABLE ROW LEVEL SECURITY;

--
-- Name: golden_rodada golden_rodada_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY golden_rodada_insert ON public.golden_rodada FOR INSERT TO authenticated WITH CHECK (true);

--
-- Name: golden_rodada golden_rodada_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY golden_rodada_read ON public.golden_rodada FOR SELECT TO authenticated USING (true);

--
-- Name: golden_rodada golden_rodada_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY golden_rodada_update ON public.golden_rodada FOR UPDATE TO authenticated USING (true);

--
-- Name: golden_rotulo; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.golden_rotulo ENABLE ROW LEVEL SECURITY;

--
-- Name: golden_rotulo golden_rotulo_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY golden_rotulo_insert ON public.golden_rotulo FOR INSERT TO authenticated WITH CHECK (true);

--
-- Name: golden_rotulo golden_rotulo_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY golden_rotulo_read ON public.golden_rotulo FOR SELECT TO authenticated USING (true);

--
-- Name: indice_macro_expectativa; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.indice_macro_expectativa ENABLE ROW LEVEL SECURITY;

--
-- Name: indice_macro_expectativa indice_macro_expectativa_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY indice_macro_expectativa_read ON public.indice_macro_expectativa FOR SELECT TO authenticated USING (true);

--
-- Name: indice_macro_obs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.indice_macro_obs ENABLE ROW LEVEL SECURITY;

--
-- Name: indice_macro_obs indice_macro_obs_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY indice_macro_obs_read ON public.indice_macro_obs FOR SELECT TO authenticated USING (true);

--
-- Name: indice_macro_serie; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.indice_macro_serie ENABLE ROW LEVEL SECURITY;

--
-- Name: indice_macro_serie indice_macro_serie_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY indice_macro_serie_read ON public.indice_macro_serie FOR SELECT TO authenticated USING (true);

--
-- Name: instalacao_cobertura; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.instalacao_cobertura ENABLE ROW LEVEL SECURITY;

--
-- Name: instalacao_cobertura instalacao_cobertura_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY instalacao_cobertura_read ON public.instalacao_cobertura FOR SELECT TO authenticated USING (true);

--
-- Name: instalacao_requisito; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.instalacao_requisito ENABLE ROW LEVEL SECURITY;

--
-- Name: instalacao_requisito instalacao_requisito_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY instalacao_requisito_read ON public.instalacao_requisito FOR SELECT TO authenticated USING (true);

--
-- Name: lote_execucao; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lote_execucao ENABLE ROW LEVEL SECURITY;

--
-- Name: lote_execucao lote_execucao_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY lote_execucao_authenticated_all ON public.lote_execucao TO authenticated USING (true) WITH CHECK (true);

--
-- Name: pendencia; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pendencia ENABLE ROW LEVEL SECURITY;

--
-- Name: pendencia pendencia_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pendencia_authenticated_all ON public.pendencia TO authenticated USING (true) WITH CHECK (true);

--
-- Name: pergunta_catalogo; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pergunta_catalogo ENABLE ROW LEVEL SECURITY;

--
-- Name: pergunta_catalogo pergunta_catalogo_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pergunta_catalogo_read ON public.pergunta_catalogo FOR SELECT TO authenticated USING (true);

--
-- Name: perimetro; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.perimetro ENABLE ROW LEVEL SECURITY;

--
-- Name: perimetro perimetro_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY perimetro_read ON public.perimetro FOR SELECT TO authenticated USING (true);

--
-- Name: periodo; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.periodo ENABLE ROW LEVEL SECURITY;

--
-- Name: periodo periodo_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY periodo_authenticated_all ON public.periodo TO authenticated USING (true) WITH CHECK (true);

--
-- Name: premissa_catalogo; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.premissa_catalogo ENABLE ROW LEVEL SECURITY;

--
-- Name: premissa_catalogo premissa_catalogo_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY premissa_catalogo_authenticated_all ON public.premissa_catalogo TO authenticated USING (true) WITH CHECK (true);

--
-- Name: reconciliacao; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reconciliacao ENABLE ROW LEVEL SECURITY;

--
-- Name: reconciliacao reconciliacao_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reconciliacao_authenticated_all ON public.reconciliacao TO authenticated USING (true) WITH CHECK (true);

--
-- Name: rubrica_classe; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.rubrica_classe ENABLE ROW LEVEL SECURITY;

--
-- Name: rubrica_classe rubrica_classe_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY rubrica_classe_read ON public.rubrica_classe FOR SELECT TO authenticated USING (true);

--
-- Name: taxonomia_linha_alternativa; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taxonomia_linha_alternativa ENABLE ROW LEVEL SECURITY;

--
-- Name: taxonomia_linha_alternativa taxonomia_linha_alternativa_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY taxonomia_linha_alternativa_read ON public.taxonomia_linha_alternativa FOR SELECT TO authenticated USING (true);

--
-- Name: taxonomia_linha_exigida; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taxonomia_linha_exigida ENABLE ROW LEVEL SECURITY;

--
-- Name: taxonomia_linha_exigida taxonomia_linha_exigida_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY taxonomia_linha_exigida_read ON public.taxonomia_linha_exigida FOR SELECT TO authenticated USING (true);

--
-- Name: taxonomia_linha_localizador; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taxonomia_linha_localizador ENABLE ROW LEVEL SECURITY;

--
-- Name: taxonomia_linha_localizador taxonomia_linha_localizador_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY taxonomia_linha_localizador_read ON public.taxonomia_linha_localizador FOR SELECT TO authenticated USING (true);

--
-- Name: taxonomia_tipo_documento taxonomia_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY taxonomia_read ON public.taxonomia_tipo_documento FOR SELECT TO authenticated USING (true);

--
-- Name: taxonomia_tipo_cobertura; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taxonomia_tipo_cobertura ENABLE ROW LEVEL SECURITY;

--
-- Name: taxonomia_tipo_cobertura taxonomia_tipo_cobertura_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY taxonomia_tipo_cobertura_read ON public.taxonomia_tipo_cobertura FOR SELECT TO authenticated USING (true);

--
-- Name: taxonomia_tipo_documento; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taxonomia_tipo_documento ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;

--
-- Name: FUNCTION fn_aceitar_extracao(p_documento_versao_id uuid, p_autor text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_aceitar_extracao(p_documento_versao_id uuid, p_autor text, p_motivo text) TO authenticated;

--
-- Name: FUNCTION fn_ano_da_coluna(p_periodo_coluna text, p_referencia text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_ano_da_coluna(p_periodo_coluna text, p_referencia text) TO authenticated;

--
-- Name: FUNCTION fn_anos_do_periodo(p_referencia text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_anos_do_periodo(p_referencia text) TO authenticated;

--
-- Name: FUNCTION fn_anos_periodo(p_tipo text, p_ref text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_anos_periodo(p_tipo text, p_ref text) TO authenticated;

--
-- Name: FUNCTION fn_aplicar_premissa_em_lote(p_caso_id uuid, p_secao_canonica text, p_premissa text, p_autor text, p_sazonalidade text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_aplicar_premissa_em_lote(p_caso_id uuid, p_secao_canonica text, p_premissa text, p_autor text, p_sazonalidade text) TO authenticated;

--
-- Name: FUNCTION fn_aprovar_caso(p_caso_id uuid, p_autor text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_aprovar_caso(p_caso_id uuid, p_autor text, p_motivo text) TO authenticated;

--
-- Name: FUNCTION fn_ativar_premissa(p_caso_id uuid, p_codigo text, p_valores jsonb, p_origem text, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_ativar_premissa(p_caso_id uuid, p_codigo text, p_valores jsonb, p_origem text, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_autoridade_do_documento(p_documento_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_autoridade_do_documento(p_documento_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_avaliar_guardas_extracao(p_documento_versao_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_avaliar_guardas_extracao(p_documento_versao_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_avaliar_portao2(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_avaliar_portao2(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_classe_contabil_concordancia(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_classe_contabil_concordancia(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_classe_contabil_do_campo(p_campo_extraido_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_classe_contabil_do_campo(p_campo_extraido_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_classe_contabil_sugerir(p_chave text, p_secao_canonica text, p_tipo_taxonomia text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_classe_contabil_sugerir(p_chave text, p_secao_canonica text, p_tipo_taxonomia text) TO authenticated;

--
-- Name: FUNCTION fn_classificar_contabil(p_documento_versao_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_classificar_contabil(p_documento_versao_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_cnpj_canonico(p_cnpj text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_cnpj_canonico(p_cnpj text) TO authenticated;

--
-- Name: FUNCTION fn_cobertura_de_tipos(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_cobertura_de_tipos() TO authenticated;

--
-- Name: FUNCTION fn_coluna_e_abertura(p_coluna text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_coluna_e_abertura(p_coluna text) TO authenticated;

--
-- Name: FUNCTION fn_coluna_e_movimento(p_coluna text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_coluna_e_movimento(p_coluna text) TO authenticated;

--
-- Name: FUNCTION fn_coluna_e_saldo(p_coluna text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_coluna_e_saldo(p_coluna text) TO authenticated;

--
-- Name: FUNCTION fn_combinado_estrutural_apto(p_tipo_fonte text, p_empresas_com_valor integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_combinado_estrutural_apto(p_tipo_fonte text, p_empresas_com_valor integer) TO authenticated;

--
-- Name: FUNCTION fn_conferir_arvore(p_documento_versao_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_conferir_arvore(p_documento_versao_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_conferir_lote(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_conferir_lote(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_conferir_modelagem(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_conferir_modelagem(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_conflitos_do_caso(p_caso_id uuid, p_entidade text, p_tolerancia_abs numeric, p_tolerancia_pct numeric); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_conflitos_do_caso(p_caso_id uuid, p_entidade text, p_tolerancia_abs numeric, p_tolerancia_pct numeric) TO authenticated;

--
-- Name: FUNCTION fn_contas_repetindo_valor(p_documento_versao_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_contas_repetindo_valor(p_documento_versao_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_contraparte_intragrupo(p_caso_id uuid, p_chave text, p_entidade_dona uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_contraparte_intragrupo(p_caso_id uuid, p_chave text, p_entidade_dona uuid) TO authenticated;

--
-- Name: FUNCTION fn_controlador_registrar(p_caso_id uuid, p_nome text, p_documento text, p_tipo_pessoa public.controlador_tipo_pessoa, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_controlador_registrar(p_caso_id uuid, p_nome text, p_documento text, p_tipo_pessoa public.controlador_tipo_pessoa, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_decidir_pendencia(p_pendencia_id uuid, p_autor text, p_decisao text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_decidir_pendencia(p_pendencia_id uuid, p_autor text, p_decisao text, p_motivo text) TO authenticated;

--
-- Name: FUNCTION fn_definir_modelagem(p_caso_id uuid, p_entidade text, p_ultimo_exercicio_real integer, p_indice_macro text, p_setor text, p_autor text, p_anos_projetados integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_definir_modelagem(p_caso_id uuid, p_entidade text, p_ultimo_exercicio_real integer, p_indice_macro text, p_setor text, p_autor text, p_anos_projetados integer) TO authenticated;

--
-- Name: FUNCTION fn_desativar_premissa(p_caso_id uuid, p_codigo text, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_desativar_premissa(p_caso_id uuid, p_codigo text, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_diagnostico_modelagem(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_diagnostico_modelagem(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_dial(p_estagio text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_dial(p_estagio text) TO authenticated;

--
-- Name: FUNCTION fn_dial_auto_promover(p_estagio text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_dial_auto_promover(p_estagio text) TO authenticated;

--
-- Name: FUNCTION fn_dial_influencia(p_estagio text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_dial_influencia(p_estagio text) TO authenticated;

--
-- Name: FUNCTION fn_dial_permite_auto(p_estagio text, p_confianca numeric); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_dial_permite_auto(p_estagio text, p_confianca numeric) TO authenticated;

--
-- Name: FUNCTION fn_documento_de_varias_empresas(p_documento_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_documento_de_varias_empresas(p_documento_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_documento_decide_sozinho(p_codigo text, p_tipo_incorreto_aberto boolean); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_documento_decide_sozinho(p_codigo text, p_tipo_incorreto_aberto boolean) TO authenticated;

--
-- Name: FUNCTION fn_documento_preliminar(p_nome text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_documento_preliminar(p_nome text) TO authenticated;

--
-- Name: FUNCTION fn_documento_serve_como(p_documento_id uuid, p_tipo_taxonomia text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_documento_serve_como(p_documento_id uuid, p_tipo_taxonomia text) TO authenticated;

--
-- Name: FUNCTION fn_documentos_nao_extraidos(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_documentos_nao_extraidos(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_entidade_aprender_cnpj(p_entidade_id uuid, p_cnpj text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_entidade_aprender_cnpj(p_entidade_id uuid, p_cnpj text) TO authenticated;

--
-- Name: FUNCTION fn_entidade_cadeia_controladora(p_entidade_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_entidade_cadeia_controladora(p_entidade_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_entidade_canonica_forte(p_nome text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_entidade_canonica_forte(p_nome text) TO authenticated;

--
-- Name: FUNCTION fn_entidade_criaria_ciclo_participacao(p_entidade_id uuid, p_nova_controladora_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_entidade_criaria_ciclo_participacao(p_entidade_id uuid, p_nova_controladora_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_entidade_definir_controlador(p_entidade_id uuid, p_controlador_id uuid, p_percentual numeric, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_entidade_definir_controlador(p_entidade_id uuid, p_controlador_id uuid, p_percentual numeric, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_entidade_definir_forma_de_controle(p_entidade_id uuid, p_forma public.entidade_forma_de_controle, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_entidade_definir_forma_de_controle(p_entidade_id uuid, p_forma public.entidade_forma_de_controle, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_entidade_definir_papel_no_grupo(p_entidade_id uuid, p_papel public.entidade_papel_no_grupo, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_entidade_definir_papel_no_grupo(p_entidade_id uuid, p_papel public.entidade_papel_no_grupo, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_entidade_definir_participacao(p_entidade_id uuid, p_controladora_id uuid, p_percentual numeric, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_entidade_definir_participacao(p_entidade_id uuid, p_controladora_id uuid, p_percentual numeric, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_entidade_e_balcao_ambiguo(p_caso_id uuid, p_entidade_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_entidade_e_balcao_ambiguo(p_caso_id uuid, p_entidade_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_entidade_nome_mais_completo(p_atual text, p_novo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_entidade_nome_mais_completo(p_atual text, p_novo text) TO authenticated;

--
-- Name: FUNCTION fn_entidade_talvez_renomear(p_caso_id uuid, p_entidade_id uuid, p_nome text, p_cnpj text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_entidade_talvez_renomear(p_caso_id uuid, p_entidade_id uuid, p_nome text, p_cnpj text) TO authenticated;

--
-- Name: FUNCTION fn_entidades_candidatas(p_caso_id uuid, p_nome text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_entidades_candidatas(p_caso_id uuid, p_nome text) TO authenticated;

--
-- Name: FUNCTION fn_entidades_candidatas_cnpj(p_caso_id uuid, p_nome text, p_cnpj text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_entidades_candidatas_cnpj(p_caso_id uuid, p_nome text, p_cnpj text) TO authenticated;

--
-- Name: FUNCTION fn_excluir_caso(p_caso_id uuid, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_excluir_caso(p_caso_id uuid, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_exercicio_da_coluna(p_coluna text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_exercicio_da_coluna(p_coluna text) TO authenticated;

--
-- Name: FUNCTION fn_exigencias_do_caso(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_exigencias_do_caso(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_falhas_abertas(p_caso_nome text, p_desde timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_falhas_abertas(p_caso_nome text, p_desde timestamp with time zone) TO authenticated;

--
-- Name: FUNCTION fn_familia_da_secao(p_secao text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_familia_da_secao(p_secao text) TO authenticated;

--
-- Name: FUNCTION fn_fatos_do_caso(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_fatos_do_caso(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_fechar_caso(p_caso_id uuid, p_autor text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_fechar_caso(p_caso_id uuid, p_autor text, p_motivo text) TO authenticated;

--
-- Name: FUNCTION fn_fundir_entidade(p_caso_id uuid, p_de_id uuid, p_para_id uuid, p_por text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_fundir_entidade(p_caso_id uuid, p_de_id uuid, p_para_id uuid, p_por text) TO authenticated;

--
-- Name: FUNCTION fn_golden_abrir_rodada(p_nome text, p_autor text, p_nota text, p_taxonomia_versao integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_abrir_rodada(p_nome text, p_autor text, p_nota text, p_taxonomia_versao integer) TO authenticated;

--
-- Name: FUNCTION fn_golden_campos(p_rodada uuid, p_origem public.golden_origem); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_campos(p_rodada uuid, p_origem public.golden_origem) TO authenticated;

--
-- Name: FUNCTION fn_golden_candidatos(p_rodada uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_candidatos(p_rodada uuid) TO authenticated;

--
-- Name: FUNCTION fn_golden_classe_a(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_classe_a(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_golden_classificacao(p_rodada uuid, p_origem public.golden_origem); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_classificacao(p_rodada uuid, p_origem public.golden_origem) TO authenticated;

--
-- Name: FUNCTION fn_golden_cobertura(p_rodada uuid, p_origem public.golden_origem); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_cobertura(p_rodada uuid, p_origem public.golden_origem) TO authenticated;

--
-- Name: FUNCTION fn_golden_congelar(p_rodada uuid, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_congelar(p_rodada uuid, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_golden_consenso(p_rodada uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_consenso(p_rodada uuid) TO authenticated;

--
-- Name: FUNCTION fn_golden_estrato_sugerido(p_documento_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_estrato_sugerido(p_documento_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_golden_identificadores(p_rodada uuid, p_origem public.golden_origem); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_identificadores(p_rodada uuid, p_origem public.golden_origem) TO authenticated;

--
-- Name: FUNCTION fn_golden_incluir_documento(p_rodada uuid, p_documento_id uuid, p_estrato public.golden_estrato, p_origem public.golden_origem, p_autor text, p_nota text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_incluir_documento(p_rodada uuid, p_documento_id uuid, p_estrato public.golden_estrato, p_origem public.golden_origem, p_autor text, p_nota text) TO authenticated;

--
-- Name: FUNCTION fn_golden_inter_avaliador(p_rodada uuid, p_origem public.golden_origem); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_inter_avaliador(p_rodada uuid, p_origem public.golden_origem) TO authenticated;

--
-- Name: FUNCTION fn_golden_linhas_para_rotular(p_rodada uuid, p_documento_id uuid, p_rotulador text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_linhas_para_rotular(p_rodada uuid, p_documento_id uuid, p_rotulador text) TO authenticated;

--
-- Name: FUNCTION fn_golden_progresso(p_rodada uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_progresso(p_rodada uuid) TO authenticated;

--
-- Name: FUNCTION fn_golden_rotular(p_rodada uuid, p_documento_id uuid, p_rotulador text, p_tipo_correto text, p_entidade_correta text, p_periodo_correto text, p_assinado_correto boolean, p_legibilidade public.legibilidade, p_item_checklist_correto text, p_nota text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_rotular(p_rodada uuid, p_documento_id uuid, p_rotulador text, p_tipo_correto text, p_entidade_correta text, p_periodo_correto text, p_assinado_correto boolean, p_legibilidade public.legibilidade, p_item_checklist_correto text, p_nota text) TO authenticated;

--
-- Name: FUNCTION fn_golden_rotular_campos(p_rodada uuid, p_documento_id uuid, p_rotulador text, p_campos jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_rotular_campos(p_rodada uuid, p_documento_id uuid, p_rotulador text, p_campos jsonb) TO authenticated;

--
-- Name: FUNCTION fn_golden_suficiente(p_estagio text, p_rodada uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_golden_suficiente(p_estagio text, p_rodada uuid) TO authenticated;

--
-- Name: FUNCTION fn_grupo_por_controle_comum(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_grupo_por_controle_comum(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_indice_macro_anual(p_desde_ano integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_indice_macro_anual(p_desde_ano integer) TO authenticated;

--
-- Name: FUNCTION fn_instalacao_conferir(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_instalacao_conferir() TO authenticated;

--
-- Name: FUNCTION fn_instalacao_resumo(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_instalacao_resumo() TO authenticated;

--
-- Name: FUNCTION fn_lado_do_mutuo(p_chave text, p_secao_canonica text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_lado_do_mutuo(p_chave text, p_secao_canonica text) TO authenticated;

--
-- Name: FUNCTION fn_lado_intragrupo(p_chave text, p_secao_canonica text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_lado_intragrupo(p_chave text, p_secao_canonica text) TO authenticated;

--
-- Name: FUNCTION fn_linha_vale_para_ano(p_versao uuid, p_periodo_coluna text, p_periodo_tipo text, p_periodo_ref text, p_ano integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_linha_vale_para_ano(p_versao uuid, p_periodo_coluna text, p_periodo_tipo text, p_periodo_ref text, p_ano integer) TO authenticated;

--
-- Name: FUNCTION fn_linhas_do_realizado(p_caso_id uuid, p_entidade text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_linhas_do_realizado(p_caso_id uuid, p_entidade text) TO authenticated;

--
-- Name: FUNCTION fn_linhas_do_tipo(p_caso_id uuid, p_codigo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_linhas_do_tipo(p_caso_id uuid, p_codigo text) TO authenticated;

--
-- Name: FUNCTION fn_linhas_para_modelagem(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_linhas_para_modelagem(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_linhas_para_transcrever(p_documento_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_linhas_para_transcrever(p_documento_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_marcar_falha_vista(p_falha_id uuid, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_marcar_falha_vista(p_falha_id uuid, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_mes_do_rotulo(p_chave text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_mes_do_rotulo(p_chave text) TO authenticated;

--
-- Name: FUNCTION fn_min_motivo_rejeicao(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_min_motivo_rejeicao() TO authenticated;

--
-- Name: FUNCTION fn_modelagem_esta_pronta(p_parametros_definidos boolean, p_premissas_ativas bigint, p_premissas_sem_valor integer, p_linhas_com_premissa bigint); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_modelagem_esta_pronta(p_parametros_definidos boolean, p_premissas_ativas bigint, p_premissas_sem_valor integer, p_linhas_com_premissa bigint) TO authenticated;

--
-- Name: FUNCTION fn_mudar_dial(p_estagio text, p_nivel public.nivel_autonomia, p_autor text, p_motivo text, p_limiar numeric, p_rodada_golden uuid, p_sem_medicao_porque text, p_por_veredito boolean); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_mudar_dial(p_estagio text, p_nivel public.nivel_autonomia, p_autor text, p_motivo text, p_limiar numeric, p_rodada_golden uuid, p_sem_medicao_porque text, p_por_veredito boolean) TO authenticated;

--
-- Name: FUNCTION fn_mutuo_com_socio(p_chave text, p_secao text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_mutuo_com_socio(p_chave text, p_secao text) TO authenticated;

--
-- Name: FUNCTION fn_natureza_intragrupo(p_chave text, p_secao text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_natureza_intragrupo(p_chave text, p_secao text) TO authenticated;

--
-- Name: FUNCTION fn_nome_parece_ter_endereco_colado(p_nome text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_nome_parece_ter_endereco_colado(p_nome text) TO authenticated;

--
-- Name: FUNCTION fn_nome_tem_sufixo_societario(p_nome text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_nome_tem_sufixo_societario(p_nome text) TO authenticated;

--
-- Name: FUNCTION fn_operacao_lotes(p_dias integer, p_limite integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_operacao_lotes(p_dias integer, p_limite integer) TO authenticated;

--
-- Name: FUNCTION fn_operacao_resumo(p_dias integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_operacao_resumo(p_dias integer) TO authenticated;

--
-- Name: FUNCTION fn_papel_do_rotulo_no_caso(p_caso_id uuid, p_rotulo_norm text, p_secao_canonica text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_papel_do_rotulo_no_caso(p_caso_id uuid, p_rotulo_norm text, p_secao_canonica text) TO authenticated;

--
-- Name: FUNCTION fn_papel_linha(p_chave text, p_tipo_taxonomia text, p_unidade text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_papel_linha(p_chave text, p_tipo_taxonomia text, p_unidade text) TO authenticated;

--
-- Name: FUNCTION fn_papel_prioridade(p_papel text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_papel_prioridade(p_papel text) TO authenticated;

--
-- Name: FUNCTION fn_pendencia_entidade_ambigua(p_caso_id uuid, p_documento_id uuid, p_entidade_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_pendencia_entidade_ambigua(p_caso_id uuid, p_documento_id uuid, p_entidade_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_perimetro_definir_escopo(p_caso_id uuid, p_entidade_id uuid, p_escopo text, p_desde date, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_perimetro_definir_escopo(p_caso_id uuid, p_entidade_id uuid, p_escopo text, p_desde date, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_perimetro_encerrar_escopo(p_caso_id uuid, p_entidade_id uuid, p_escopo text, p_ate date, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_perimetro_encerrar_escopo(p_caso_id uuid, p_entidade_id uuid, p_escopo text, p_ate date, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_perimetro_situacao(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_perimetro_situacao(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_perimetro_veredito(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_perimetro_veredito(p_caso_id uuid) TO authenticated;

--
-- Name: TABLE entidade; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.entidade TO anon;
GRANT ALL ON TABLE public.entidade TO authenticated;
GRANT ALL ON TABLE public.entidade TO service_role;

--
-- Name: FUNCTION fn_perimetro_vigente(p_caso_id uuid, p_escopo text, p_data date); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_perimetro_vigente(p_caso_id uuid, p_escopo text, p_data date) TO authenticated;

--
-- Name: FUNCTION fn_periodo_e_parcial(p_coluna text, p_tipo_documento text, p_periodo_tipo text, p_referencia text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_periodo_e_parcial(p_coluna text, p_tipo_documento text, p_periodo_tipo text, p_referencia text) TO authenticated;

--
-- Name: FUNCTION fn_periodo_por_extenso(p_tipo text, p_referencia text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_periodo_por_extenso(p_tipo text, p_referencia text) TO authenticated;

--
-- Name: FUNCTION fn_periodos_compativeis_array(p_caso_id uuid, p_periodo_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_periodos_compativeis_array(p_caso_id uuid, p_periodo_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_pode_renomear_por_cnpj(p_atual text, p_novo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_pode_renomear_por_cnpj(p_atual text, p_novo text) TO authenticated;

--
-- Name: FUNCTION fn_premissa_valores_sugeridos(p_codigo text, p_ano_inicial integer, p_anos integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_premissa_valores_sugeridos(p_codigo text, p_ano_inicial integer, p_anos integer) TO authenticated;

--
-- Name: TABLE premissa_catalogo; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.premissa_catalogo TO anon;
GRANT ALL ON TABLE public.premissa_catalogo TO authenticated;
GRANT ALL ON TABLE public.premissa_catalogo TO service_role;

--
-- Name: FUNCTION fn_premissas_sugeridas(p_setor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_premissas_sugeridas(p_setor text) TO authenticated;

--
-- Name: FUNCTION fn_radicais_rotulo(p_chave text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_radicais_rotulo(p_chave text) TO authenticated;

--
-- Name: FUNCTION fn_reabrir_caso(p_caso_id uuid, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reabrir_caso(p_caso_id uuid, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_reavaliar_guardas_extracao(p_documento_versao_id uuid, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reavaliar_guardas_extracao(p_documento_versao_id uuid, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_reconciliar_arvore(p_documento_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reconciliar_arvore(p_documento_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_reconciliar_caixa_bp_fluxo(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reconciliar_caixa_bp_fluxo(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric) TO authenticated;

--
-- Name: FUNCTION fn_reconciliar_caso(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reconciliar_caso(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_reconciliar_chaves_do_documento(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reconciliar_chaves_do_documento(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text) TO authenticated;

--
-- Name: FUNCTION fn_reconciliar_despfin_dre_vs_divida(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reconciliar_despfin_dre_vs_divida(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric) TO authenticated;

--
-- Name: FUNCTION fn_reconciliar_intragrupo(p_caso_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reconciliar_intragrupo(p_caso_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric) TO authenticated;

--
-- Name: FUNCTION fn_reconciliar_mutuos(p_caso_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reconciliar_mutuos(p_caso_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric) TO authenticated;

--
-- Name: FUNCTION fn_reconciliar_por_documento(p_documento_id uuid, p_escopo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reconciliar_por_documento(p_documento_id uuid, p_escopo text) TO authenticated;

--
-- Name: FUNCTION fn_reconciliar_receita_dre_vs_faturamento(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reconciliar_receita_dre_vs_faturamento(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric, p_tolerancia_pct numeric) TO authenticated;

--
-- Name: FUNCTION fn_reconciliar_versoes_do_periodo(p_caso_id uuid, p_entidade_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reconciliar_versoes_do_periodo(p_caso_id uuid, p_entidade_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_reconferir_caso(p_caso_id uuid, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reconferir_caso(p_caso_id uuid, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_registrar_campos_extraidos(p_documento_versao_id uuid, p_campos jsonb, p_nivel public.nivel_autonomia, p_falha_motivo text, p_tem_dado_financeiro boolean); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_registrar_campos_extraidos(p_documento_versao_id uuid, p_campos jsonb, p_nivel public.nivel_autonomia, p_falha_motivo text, p_tem_dado_financeiro boolean) TO authenticated;

--
-- Name: FUNCTION fn_registrar_classe_override(p_campo_extraido_id uuid, p_classe_final text, p_autor text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_registrar_classe_override(p_campo_extraido_id uuid, p_classe_final text, p_autor text, p_motivo text) TO authenticated;

--
-- Name: FUNCTION fn_registrar_falha_execucao(p_caso_id uuid, p_caso_nome text, p_etapa text, p_mensagem text, p_detalhe jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_registrar_falha_execucao(p_caso_id uuid, p_caso_nome text, p_etapa text, p_mensagem text, p_detalhe jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.fn_registrar_falha_execucao(p_caso_id uuid, p_caso_nome text, p_etapa text, p_mensagem text, p_detalhe jsonb) TO service_role;

--
-- Name: FUNCTION fn_registrar_fatos(p_documento_versao_id uuid, p_fatos jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_registrar_fatos(p_documento_versao_id uuid, p_fatos jsonb) TO authenticated;

--
-- Name: FUNCTION fn_registrar_pergunta_acao(p_caso_id uuid, p_codigo text, p_acao text, p_texto text, p_autor text, p_entidade_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_registrar_pergunta_acao(p_caso_id uuid, p_codigo text, p_acao text, p_texto text, p_autor text, p_entidade_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_registrar_reconciliacao(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text, p_classe text, p_documento_id uuid, p_fonte_a jsonb, p_fonte_b jsonb, p_resultado text, p_divergencia_abs numeric, p_divergencia_pct numeric, p_materialidade jsonb, p_descricao text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_registrar_reconciliacao(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text, p_classe text, p_documento_id uuid, p_fonte_a jsonb, p_fonte_b jsonb, p_resultado text, p_divergencia_abs numeric, p_divergencia_pct numeric, p_materialidade jsonb, p_descricao text) TO authenticated;

--
-- Name: FUNCTION fn_registrar_transcricao_humana(p_documento_id uuid, p_linhas jsonb, p_autor text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_registrar_transcricao_humana(p_documento_id uuid, p_linhas jsonb, p_autor text, p_motivo text) TO authenticated;

--
-- Name: FUNCTION fn_registrar_uso_lote(p_caso_id uuid, p_execucao_ref text, p_resumo jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_registrar_uso_lote(p_caso_id uuid, p_execucao_ref text, p_resumo jsonb) TO authenticated;

--
-- Name: FUNCTION fn_resolver_linha_exigida_superada(p_tipos text[], p_ator text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.fn_resolver_linha_exigida_superada(p_tipos text[], p_ator text) FROM PUBLIC;

--
-- Name: FUNCTION fn_resumo_anexar(p_arquivo uuid, p_registros jsonb, p_grupos jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_resumo_anexar(p_arquivo uuid, p_registros jsonb, p_grupos jsonb) TO authenticated;

--
-- Name: FUNCTION fn_resumo_concluir(p_arquivo uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_resumo_concluir(p_arquivo uuid) TO authenticated;

--
-- Name: FUNCTION fn_resumo_iniciar(p_caso uuid, p_documento uuid, p_envelope jsonb, p_cabecalho jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_resumo_iniciar(p_caso uuid, p_documento uuid, p_envelope jsonb, p_cabecalho jsonb) TO authenticated;

--
-- Name: FUNCTION fn_revisar_documento(p_documento_id uuid, p_autor text, p_novo_tipo_taxonomia text, p_nova_entidade_nome text, p_novo_periodo_tipo text, p_novo_periodo_ref text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_revisar_documento(p_documento_id uuid, p_autor text, p_novo_tipo_taxonomia text, p_nova_entidade_nome text, p_novo_periodo_tipo text, p_novo_periodo_ref text, p_motivo text) TO authenticated;

--
-- Name: FUNCTION fn_rotulo_contido(p_curto text, p_longo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_rotulo_contido(p_curto text, p_longo text) TO authenticated;

--
-- Name: FUNCTION fn_rotulo_estrutural(p_chave text, p_tokens_exigidos text[]); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_rotulo_estrutural(p_chave text, p_tokens_exigidos text[]) TO authenticated;

--
-- Name: FUNCTION fn_saldo_mutuos_do_documento(p_linhas jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_saldo_mutuos_do_documento(p_linhas jsonb) TO authenticated;

--
-- Name: FUNCTION fn_saldo_mutuos_linhas(p_linhas jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_saldo_mutuos_linhas(p_linhas jsonb) TO authenticated;

--
-- Name: FUNCTION fn_saldo_mutuos_texto(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_saldo_mutuos_texto(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_sazonalidade_do_caso(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_sazonalidade_do_caso(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_secao_canonica_da_secao_bruta(p_secao text, p_tipo_documento text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_secao_canonica_da_secao_bruta(p_secao text, p_tipo_documento text) TO authenticated;

--
-- Name: FUNCTION fn_secao_e_de_resultado(p_secao text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_secao_e_de_resultado(p_secao text) TO authenticated;

--
-- Name: FUNCTION fn_sem_codigo_de_conta(p_rotulo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_sem_codigo_de_conta(p_rotulo text) TO authenticated;

--
-- Name: FUNCTION fn_somar_faturamento_ano(p_documento_versao_id uuid, p_ano4 text, p_ano2 text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_somar_faturamento_ano(p_documento_versao_id uuid, p_ano4 text, p_ano2 text) TO authenticated;

--
-- Name: FUNCTION fn_sugerir_perguntas(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_sugerir_perguntas(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_tem_palavra_longa(p_chave text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_tem_palavra_longa(p_chave text) TO authenticated;

--
-- Name: FUNCTION fn_teto_ressalvas(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_teto_ressalvas() TO authenticated;

--
-- Name: FUNCTION fn_texto_nomeia_mutuo(p_texto text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_texto_nomeia_mutuo(p_texto text) TO authenticated;

--
-- Name: FUNCTION fn_tokens_estruturais(p_chave text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_tokens_estruturais(p_chave text) TO authenticated;

--
-- Name: FUNCTION fn_upsert_caso(p_nome text, p_ator text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_upsert_caso(p_nome text, p_ator text) TO authenticated;

--
-- Name: TABLE campo_extraido; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.campo_extraido TO anon;
GRANT ALL ON TABLE public.campo_extraido TO authenticated;
GRANT ALL ON TABLE public.campo_extraido TO service_role;

--
-- Name: FUNCTION fn_valor_estrutural_col(p_documento_versao_id uuid, p_tokens text[], p_entidade_coluna text, p_periodo_coluna text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_valor_estrutural_col(p_documento_versao_id uuid, p_tokens text[], p_entidade_coluna text, p_periodo_coluna text) TO authenticated;

--
-- Name: FUNCTION fn_valor_pt_br(p_valor numeric, p_unidade text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_valor_pt_br(p_valor numeric, p_unidade text) TO authenticated;

--
-- Name: FUNCTION fn_valores_por_ano(p_caso_id uuid, p_entidade text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_valores_por_ano(p_caso_id uuid, p_entidade text) TO authenticated;

--
-- Name: FUNCTION fn_veredito_producao(p_estagio text, p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_veredito_producao(p_estagio text, p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_versao_com_extracao(p_documento_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_versao_com_extracao(p_documento_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_vincular_linha_premissa(p_caso_id uuid, p_secao_canonica text, p_rotulo text, p_entidade text, p_premissa text, p_autor text, p_sazonalidade text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_vincular_linha_premissa(p_caso_id uuid, p_secao_canonica text, p_rotulo text, p_entidade text, p_premissa text, p_autor text, p_sazonalidade text) TO authenticated;

--
-- Name: TABLE arquivo_oficial; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.arquivo_oficial TO anon;
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,UPDATE ON TABLE public.arquivo_oficial TO authenticated;
GRANT ALL ON TABLE public.arquivo_oficial TO service_role;

--
-- Name: TABLE arquivo_oficial_lancamento_mes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.arquivo_oficial_lancamento_mes TO anon;
GRANT ALL ON TABLE public.arquivo_oficial_lancamento_mes TO authenticated;
GRANT ALL ON TABLE public.arquivo_oficial_lancamento_mes TO service_role;

--
-- Name: TABLE arquivo_oficial_registro; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.arquivo_oficial_registro TO anon;
GRANT ALL ON TABLE public.arquivo_oficial_registro TO authenticated;
GRANT ALL ON TABLE public.arquivo_oficial_registro TO service_role;

--
-- Name: SEQUENCE arquivo_oficial_seq_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.arquivo_oficial_seq_seq TO anon;
GRANT ALL ON SEQUENCE public.arquivo_oficial_seq_seq TO authenticated;
GRANT ALL ON SEQUENCE public.arquivo_oficial_seq_seq TO service_role;

--
-- Name: TABLE campo_classe_override; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.campo_classe_override TO anon;
GRANT ALL ON TABLE public.campo_classe_override TO authenticated;
GRANT ALL ON TABLE public.campo_classe_override TO service_role;

--
-- Name: TABLE campo_classe_sugerida; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.campo_classe_sugerida TO anon;
GRANT ALL ON TABLE public.campo_classe_sugerida TO authenticated;
GRANT ALL ON TABLE public.campo_classe_sugerida TO service_role;

--
-- Name: TABLE caso; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.caso TO anon;
GRANT ALL ON TABLE public.caso TO authenticated;
GRANT ALL ON TABLE public.caso TO service_role;

--
-- Name: TABLE caso_apresentacao_campo; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.caso_apresentacao_campo TO anon;
GRANT ALL ON TABLE public.caso_apresentacao_campo TO authenticated;
GRANT ALL ON TABLE public.caso_apresentacao_campo TO service_role;

--
-- Name: TABLE caso_linha_premissa; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.caso_linha_premissa TO anon;
GRANT ALL ON TABLE public.caso_linha_premissa TO authenticated;
GRANT ALL ON TABLE public.caso_linha_premissa TO service_role;

--
-- Name: TABLE caso_modelagem; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.caso_modelagem TO anon;
GRANT ALL ON TABLE public.caso_modelagem TO authenticated;
GRANT ALL ON TABLE public.caso_modelagem TO service_role;

--
-- Name: TABLE caso_pergunta; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.caso_pergunta TO anon;
GRANT ALL ON TABLE public.caso_pergunta TO authenticated;
GRANT ALL ON TABLE public.caso_pergunta TO service_role;

--
-- Name: TABLE caso_premissa; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.caso_premissa TO anon;
GRANT ALL ON TABLE public.caso_premissa TO authenticated;
GRANT ALL ON TABLE public.caso_premissa TO service_role;

--
-- Name: TABLE checklist_item_status; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.checklist_item_status TO anon;
GRANT ALL ON TABLE public.checklist_item_status TO authenticated;
GRANT ALL ON TABLE public.checklist_item_status TO service_role;

--
-- Name: TABLE classe_contabil_catalogo; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.classe_contabil_catalogo TO anon;
GRANT ALL ON TABLE public.classe_contabil_catalogo TO authenticated;
GRANT ALL ON TABLE public.classe_contabil_catalogo TO service_role;

--
-- Name: TABLE controlador; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.controlador TO anon;
GRANT ALL ON TABLE public.controlador TO authenticated;
GRANT ALL ON TABLE public.controlador TO service_role;

--
-- Name: TABLE decisao; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.decisao TO anon;
GRANT ALL ON TABLE public.decisao TO authenticated;
GRANT ALL ON TABLE public.decisao TO service_role;

--
-- Name: TABLE documento; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.documento TO anon;
GRANT ALL ON TABLE public.documento TO authenticated;
GRANT ALL ON TABLE public.documento TO service_role;

--
-- Name: TABLE documento_fato; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.documento_fato TO anon;
GRANT ALL ON TABLE public.documento_fato TO authenticated;
GRANT ALL ON TABLE public.documento_fato TO service_role;

--
-- Name: TABLE documento_versao; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.documento_versao TO anon;
GRANT ALL ON TABLE public.documento_versao TO authenticated;
GRANT ALL ON TABLE public.documento_versao TO service_role;

--
-- Name: TABLE entidade_controlador; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.entidade_controlador TO anon;
GRANT ALL ON TABLE public.entidade_controlador TO authenticated;
GRANT ALL ON TABLE public.entidade_controlador TO service_role;

--
-- Name: TABLE estagio_autonomia; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.estagio_autonomia TO anon;
GRANT ALL ON TABLE public.estagio_autonomia TO authenticated;
GRANT ALL ON TABLE public.estagio_autonomia TO service_role;

--
-- Name: TABLE evento_auditoria; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.evento_auditoria TO anon;
GRANT ALL ON TABLE public.evento_auditoria TO authenticated;
GRANT ALL ON TABLE public.evento_auditoria TO service_role;

--
-- Name: TABLE execucao_falha; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.execucao_falha TO anon;
GRANT ALL ON TABLE public.execucao_falha TO authenticated;
GRANT ALL ON TABLE public.execucao_falha TO service_role;

--
-- Name: TABLE fato_tipo_catalogo; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.fato_tipo_catalogo TO anon;
GRANT ALL ON TABLE public.fato_tipo_catalogo TO authenticated;
GRANT ALL ON TABLE public.fato_tipo_catalogo TO service_role;

--
-- Name: TABLE golden_campo; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.golden_campo TO anon;
GRANT ALL ON TABLE public.golden_campo TO authenticated;
GRANT ALL ON TABLE public.golden_campo TO service_role;

--
-- Name: TABLE golden_criterio; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.golden_criterio TO anon;
GRANT ALL ON TABLE public.golden_criterio TO authenticated;
GRANT ALL ON TABLE public.golden_criterio TO service_role;

--
-- Name: TABLE golden_documento; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.golden_documento TO anon;
GRANT ALL ON TABLE public.golden_documento TO authenticated;
GRANT ALL ON TABLE public.golden_documento TO service_role;

--
-- Name: TABLE golden_rodada; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.golden_rodada TO anon;
GRANT ALL ON TABLE public.golden_rodada TO authenticated;
GRANT ALL ON TABLE public.golden_rodada TO service_role;

--
-- Name: TABLE golden_rotulo; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.golden_rotulo TO anon;
GRANT ALL ON TABLE public.golden_rotulo TO authenticated;
GRANT ALL ON TABLE public.golden_rotulo TO service_role;

--
-- Name: TABLE indice_macro_expectativa; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.indice_macro_expectativa TO anon;
GRANT ALL ON TABLE public.indice_macro_expectativa TO authenticated;
GRANT ALL ON TABLE public.indice_macro_expectativa TO service_role;

--
-- Name: TABLE indice_macro_obs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.indice_macro_obs TO anon;
GRANT ALL ON TABLE public.indice_macro_obs TO authenticated;
GRANT ALL ON TABLE public.indice_macro_obs TO service_role;

--
-- Name: TABLE indice_macro_serie; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.indice_macro_serie TO anon;
GRANT ALL ON TABLE public.indice_macro_serie TO authenticated;
GRANT ALL ON TABLE public.indice_macro_serie TO service_role;

--
-- Name: TABLE instalacao_cobertura; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.instalacao_cobertura TO anon;
GRANT ALL ON TABLE public.instalacao_cobertura TO authenticated;
GRANT ALL ON TABLE public.instalacao_cobertura TO service_role;

--
-- Name: TABLE instalacao_requisito; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.instalacao_requisito TO anon;
GRANT ALL ON TABLE public.instalacao_requisito TO authenticated;
GRANT ALL ON TABLE public.instalacao_requisito TO service_role;

--
-- Name: TABLE instalacao_sonda_cobertura_de_tipos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.instalacao_sonda_cobertura_de_tipos TO anon;
GRANT ALL ON TABLE public.instalacao_sonda_cobertura_de_tipos TO authenticated;
GRANT ALL ON TABLE public.instalacao_sonda_cobertura_de_tipos TO service_role;

--
-- Name: TABLE instalacao_sonda_combinado_estrutural; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.instalacao_sonda_combinado_estrutural TO anon;
GRANT ALL ON TABLE public.instalacao_sonda_combinado_estrutural TO authenticated;
GRANT ALL ON TABLE public.instalacao_sonda_combinado_estrutural TO service_role;

--
-- Name: TABLE instalacao_sonda_entidade_balcao_ambiguo; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.instalacao_sonda_entidade_balcao_ambiguo TO anon;
GRANT ALL ON TABLE public.instalacao_sonda_entidade_balcao_ambiguo TO authenticated;
GRANT ALL ON TABLE public.instalacao_sonda_entidade_balcao_ambiguo TO service_role;

--
-- Name: TABLE taxonomia_linha_exigida; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.taxonomia_linha_exigida TO anon;
GRANT ALL ON TABLE public.taxonomia_linha_exigida TO authenticated;
GRANT ALL ON TABLE public.taxonomia_linha_exigida TO service_role;

--
-- Name: TABLE taxonomia_linha_localizador; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.taxonomia_linha_localizador TO anon;
GRANT ALL ON TABLE public.taxonomia_linha_localizador TO authenticated;
GRANT ALL ON TABLE public.taxonomia_linha_localizador TO service_role;

--
-- Name: TABLE instalacao_sonda_exigencias_0187; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.instalacao_sonda_exigencias_0187 TO anon;
GRANT ALL ON TABLE public.instalacao_sonda_exigencias_0187 TO authenticated;
GRANT ALL ON TABLE public.instalacao_sonda_exigencias_0187 TO service_role;

--
-- Name: TABLE taxonomia_linha_alternativa; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.taxonomia_linha_alternativa TO anon;
GRANT ALL ON TABLE public.taxonomia_linha_alternativa TO authenticated;
GRANT ALL ON TABLE public.taxonomia_linha_alternativa TO service_role;

--
-- Name: TABLE instalacao_sonda_exigencias_0188; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.instalacao_sonda_exigencias_0188 TO anon;
GRANT ALL ON TABLE public.instalacao_sonda_exigencias_0188 TO authenticated;
GRANT ALL ON TABLE public.instalacao_sonda_exigencias_0188 TO service_role;

--
-- Name: TABLE instalacao_sonda_modelagem_pronta; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.instalacao_sonda_modelagem_pronta TO anon;
GRANT ALL ON TABLE public.instalacao_sonda_modelagem_pronta TO authenticated;
GRANT ALL ON TABLE public.instalacao_sonda_modelagem_pronta TO service_role;

--
-- Name: TABLE instalacao_sonda_modelagem_versao_vigente; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.instalacao_sonda_modelagem_versao_vigente TO anon;
GRANT ALL ON TABLE public.instalacao_sonda_modelagem_versao_vigente TO authenticated;
GRANT ALL ON TABLE public.instalacao_sonda_modelagem_versao_vigente TO service_role;

--
-- Name: TABLE instalacao_sonda_passivo_bare; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.instalacao_sonda_passivo_bare TO anon;
GRANT ALL ON TABLE public.instalacao_sonda_passivo_bare TO authenticated;
GRANT ALL ON TABLE public.instalacao_sonda_passivo_bare TO service_role;

--
-- Name: TABLE instalacao_sonda_rotulo_contraditorio; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.instalacao_sonda_rotulo_contraditorio TO anon;
GRANT ALL ON TABLE public.instalacao_sonda_rotulo_contraditorio TO authenticated;
GRANT ALL ON TABLE public.instalacao_sonda_rotulo_contraditorio TO service_role;

--
-- Name: TABLE instalacao_sonda_saldo_mutuos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.instalacao_sonda_saldo_mutuos TO anon;
GRANT ALL ON TABLE public.instalacao_sonda_saldo_mutuos TO authenticated;
GRANT ALL ON TABLE public.instalacao_sonda_saldo_mutuos TO service_role;

--
-- Name: TABLE lote_execucao; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.lote_execucao TO anon;
GRANT ALL ON TABLE public.lote_execucao TO authenticated;
GRANT ALL ON TABLE public.lote_execucao TO service_role;

--
-- Name: TABLE pendencia; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pendencia TO anon;
GRANT ALL ON TABLE public.pendencia TO authenticated;
GRANT ALL ON TABLE public.pendencia TO service_role;

--
-- Name: TABLE pergunta_catalogo; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pergunta_catalogo TO anon;
GRANT ALL ON TABLE public.pergunta_catalogo TO authenticated;
GRANT ALL ON TABLE public.pergunta_catalogo TO service_role;

--
-- Name: TABLE perimetro; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.perimetro TO anon;
GRANT ALL ON TABLE public.perimetro TO authenticated;
GRANT ALL ON TABLE public.perimetro TO service_role;

--
-- Name: TABLE periodo; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.periodo TO anon;
GRANT ALL ON TABLE public.periodo TO authenticated;
GRANT ALL ON TABLE public.periodo TO service_role;

--
-- Name: TABLE reconciliacao; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.reconciliacao TO anon;
GRANT ALL ON TABLE public.reconciliacao TO authenticated;
GRANT ALL ON TABLE public.reconciliacao TO service_role;

--
-- Name: TABLE rubrica_classe; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.rubrica_classe TO anon;
GRANT ALL ON TABLE public.rubrica_classe TO authenticated;
GRANT ALL ON TABLE public.rubrica_classe TO service_role;

--
-- Name: TABLE taxonomia_tipo_cobertura; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.taxonomia_tipo_cobertura TO anon;
GRANT ALL ON TABLE public.taxonomia_tipo_cobertura TO authenticated;
GRANT ALL ON TABLE public.taxonomia_tipo_cobertura TO service_role;

--
-- Name: TABLE taxonomia_tipo_documento; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.taxonomia_tipo_documento TO anon;
GRANT ALL ON TABLE public.taxonomia_tipo_documento TO authenticated;
GRANT ALL ON TABLE public.taxonomia_tipo_documento TO service_role;

--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;

--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;

--
--

