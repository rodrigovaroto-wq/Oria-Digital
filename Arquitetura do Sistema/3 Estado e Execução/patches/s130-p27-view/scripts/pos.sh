# O USUÁRIO PADRÃO DOS TESTES É UM SÓCIO (0216). Depois da 0216 `authenticated` sem papel não lê nada, e ~14 suítes antigas
# fazem `set role authenticated` só para provar GRANT/policy de escrita da F1 — nenhuma delas fala de papel. Em vez de editar
# todas, a sessão nasce com o JWT de um Sócio de teste (`alter database ... set request.jwt.claims`: vale para toda conexão
# nova a este banco). `acesso_por_caso.test.sql` troca o JWT por `set_config` para provar os outros papéis. Isto vem DEPOIS
# das migrations de propósito: o bootstrap da 0216 não pode ter visto este usuário (em produção, vê os reais).
psql -q -v ON_ERROR_STOP=1 -d "$DB" -c "
  insert into auth.users(id, email) values ('00000000-0000-0000-0000-00000000a001', 'socio.padrao@teste.local');
  insert into membro(usuario_id, papel) values ('00000000-0000-0000-0000-00000000a001', 'socio');
  alter database $DB set request.jwt.claims to '{\"sub\":\"00000000-0000-0000-0000-00000000a001\",\"role\":\"authenticated\"}';"

