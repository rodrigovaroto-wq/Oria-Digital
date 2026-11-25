---
id: fase-a-a1-a2-copia-de-seguranca-e-base-externa
tipo: defeito
toca:
  - Supabase/backup/copia-do-banco.sh
  - Supabase/backup/copia-do-storage.py
  - .github/workflows/copia-de-seguranca.yml
  - Supabase/migrations/0303_a_fonte_que_caia_e_parecia_nao_ter_nada.sql
  - Supabase/test/a_fonte_que_caia_e_parecia_nao_ter_nada.test.sql
  - Supabase/test/run.sh
  - Business Plan/06_execucao/FASE_A_FONTES_PUBLICAS.md
prova: Supabase/test/run.sh
ancora: Supabase/migrations/0303_a_fonte_que_caia_e_parecia_nao_ter_nada.sql#consulta_externa_prova_de_leitura
ancora_sha: ef8c209c9100
substitui: []
---

# Fase A: cópia de segurança (A1) e base comum das fontes externas (A2, 0303)

Termos de busca: backup, cópia de segurança, restauração, pg_dump, row_security, RLS, contagem,
extensão, fonte externa, consulta_externa, fato_externo, hash, corpo vazio, falhou, nada encontrado.

**Estado (24/11/2026):** A2 FEITO no código e no teste (migration 0303, ESCRITA, NÃO APLICADA em
produção). A1 CORRIGIR: escrita e medida em Postgres 16 local, NÃO medida contra produção.

## O que surpreende quem chega aqui

- **A cópia pode sair vazia SEM ERRO.** O papel que passa pela RLS lê só as linhas que a policy deixa.
  A contagem roda com `row_security = off`: o Postgres recusa a consulta em vez de filtrá-la, e o
  erro aparece antes de existir cópia (`copia-do-banco.sh`, comentário no topo). Sem essa guarda, a
  cópia e a contagem saem vazias e iguais.
- **`pg_dump -n` não leva `create extension`.** Medido no primeiro teste local: a cópia restaurou,
  as contagens bateram, e a sonda morreu em "function unaccent(text) does not exist". O script
  recria as extensões na versão de produção (`copia-do-banco.sh`, bloco `extensoes.txt`).
- **Restaurar é a prova, não a contagem.** A cópia que nunca foi restaurada tem a mesma aparência
  de cópia boa. O script restaura num Postgres descartável e roda a sonda nas duas pontas.
- **Corpo vazio tem hash.** O sha256 da string vazia é um hash válido. Uma fonte que responde 200
  com corpo vazio (proxy em manutenção) passaria como prova de leitura. Por isso a 0303 exige o hash
  em `encontrado` e em `nada_encontrado`, e não aceita o da string vazia; corpo só com espaço é
  "não li" (`falhou`). Medido: o teste reprova quando essa regra é desligada.
- **Fonte derrubada nunca vira "nada encontrado".** A `consulta_externa` tem quatro estados
  (encontrado, nada_encontrado, falhou, nao_consultado). `falhou` é imutável e exige motivo.

## Números medidos e o que não foi

- **Medido (24/11, banco local Postgres 16):** `Supabase/test/run.sh` completo, saída 0; a 0303 com
  `EXECUCOES=196 FALHAS=0`. Cada regra, desligada, faz o teste reprovar (contagens nas mensagens
  dos commits `3c6a606`, `45ef977` e `a4e813f`).
- **Medido (A1, local):** restaura do zero, as cinco tabelas-chave batem; papel sujeito à RLS
  recusado pelo script; download truncado (9 de 5.000.000 bytes) reprova.
- **NÃO medido:** a cópia contra produção. O workflow só roda depois do merge. A restauração de
  auth e storage reais só se prova na primeira execução. A cota de artefatos do GitHub (500 MB em
  repositório privado no plano Free) depende do tamanho do Storage e não foi medida.
- **Deixado, com nome:** na 0303, o marcador da sonda (1453) aparece nos dois ramos (2xx e 4xx);
  corpo só com BOM/NBSP não é tratado como vazio; 200 com corpo vazio e itens nulo dá 22023 em vez
  de gravar `falhou`; `p_erro` só com `\n` vira motivo ilegível; falta assert do 4xx com corpo de
  espaço. Decisão do dono pendente: manter EXECUTE do `authenticated` na função ou levar a chave
  de serviço à Vercel na A4.
