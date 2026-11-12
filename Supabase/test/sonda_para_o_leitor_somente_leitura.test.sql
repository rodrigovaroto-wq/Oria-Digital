-- A SONDA TEM DE SER LEGÍVEL PARA O LEITOR SÓ-LEITURA DA API (`supabase_read_only_user`).
--
-- O DEFEITO (medido em produção em 11/11/2026, logo depois de aplicar a 0242): `select ... from fn_instalacao_conferir()` pela API de gerenciamento falhou INTEIRA com
-- "permission denied for function fn_conta_canonica_orfas" — a view da sonda chama a função com o privilégio de quem LÊ, e esse papel não tinha o EXECUTE. Nenhum teste local acusou: o papel
-- não existia quando o run.sh aplicava as migrations, então o bloco `if exists (select 1 from pg_roles ...)` de grant nunca executava. O run.sh agora cria o papel ANTES das migrations (nologin,
-- bypassrls, membro de pg_read_all_data e pg_monitor: o que produção tem) e este teste roda a sonda COMO ele.
--
-- COMPORTAMENTO (regra 3): como o leitor, a sonda roda inteira e dá a MESMA resposta que dá ao dono (mesmos requisitos, mesmos ausentes) — nenhum requisito ausente por permissão. Cada função que
-- as views da sonda chamam (diretas e transitivas) é executável por ele.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2), 12/11/2026: com `revoke execute on function fn_conta_canonica_orfas() from supabase_read_only_user` no banco montado, 4 dos 6 asserts reprovam, com a mesma
-- mensagem do defeito de produção ("permission denied for function fn_conta_canonica_orfas"; o leitor vê -1 de 386 requisitos). Religado: 0 de 6. Quem acrescentar view à sonda que chame função
-- acrescenta a função à lista abaixo e o grant condicional na migration (como 0233, 0234 e 0242).

\set ON_ERROR_STOP on

begin;
create temp sequence _execucoes_leitor;
create temp sequence _falhas_leitor;
create or replace function pg_temp.teste_assert_leitor(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  perform nextval('pg_temp._execucoes_leitor');
  if coalesce(p_ok, false) then raise notice 'ok    %', p_nome;
  else raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, ''); perform nextval('pg_temp._falhas_leitor'); end if;
end $$;

do $$
declare
  v_dono int; v_dono_aus text; v_leitor int := -1; v_leitor_aus text; v_erro text; v_priv text;
begin
  perform pg_temp.teste_assert_leitor(exists (select 1 from pg_roles where rolname = 'supabase_read_only_user' and rolbypassrls and not rolcanlogin and not rolsuper)
      and pg_has_role('supabase_read_only_user', 'pg_read_all_data', 'member') and pg_has_role('supabase_read_only_user', 'pg_monitor', 'member'),
    'arranjo: o papel existe como em produção (bypassrls, membro de pg_read_all_data e pg_monitor)');
  select count(*), string_agg(chave, ',' order by chave) filter (where not presente) into v_dono, v_dono_aus from fn_instalacao_conferir();

  begin
    execute 'set local role supabase_read_only_user';
    select count(*), string_agg(chave, ',' order by chave) filter (where not presente) into v_leitor, v_leitor_aus from fn_instalacao_conferir();
  exception when others then v_erro := sqlerrm;
  end;
  execute 'reset role';
  perform pg_temp.teste_assert_leitor(v_erro is null, 'o leitor só-leitura roda fn_instalacao_conferir() inteira, sem permission denied', v_erro);
  perform pg_temp.teste_assert_leitor(v_dono > 300 and v_leitor = v_dono, 'e vê o catálogo inteiro (os mesmos requisitos que o dono)', v_leitor || ' x ' || v_dono);
  perform pg_temp.teste_assert_leitor(v_leitor_aus is not distinct from v_dono_aus, 'e os mesmos ausentes: nenhum requisito some ou aparece por permissão', coalesce(v_leitor_aus, '-') || ' x ' || coalesce(v_dono_aus, '-'));

  select string_agg(f, ', ') into v_priv from unnest(array['fn_conta_canonica_orfas()', 'fn_tipo_gera_fato(text)', 'fn_linha_vira_fato(text,text,text,numeric)', 'fn_papel_linha(text,text,text)']) f
   where not has_function_privilege('supabase_read_only_user', f::regprocedure, 'execute');
  perform pg_temp.teste_assert_leitor(v_priv is null, 'o leitor executa as funções que as views da sonda chamam (a 0242 e a 0243, e a transitiva)', v_priv);
  perform pg_temp.teste_assert_leitor((select count(*) from fn_instalacao_conferir() where migration in ('0242', '0243')) >= 27, 'a sonda do dono vê os requisitos da 0242 e da 0243 (o que o leitor lê não é vazio)');
  raise notice 'sonda_leitor: % asserts executados, % reprovados', (select last_value from pg_temp._execucoes_leitor), (select case when is_called then last_value else 0 end from pg_temp._falhas_leitor);
  if (select is_called from pg_temp._falhas_leitor) and coalesce(current_setting('leitor.medindo', true), '') <> 'on' then
    raise exception 'FALHOU: a sonda não é legível para o leitor só-leitura';
  end if;
end $$;
rollback;
