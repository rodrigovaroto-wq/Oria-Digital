// GERA O .XLSX DO EXPORT A PARTIR DE UM POSTGRES LOCAL — sem Supabase, sem rede,
// sem Vercel e sem gastar um token.
//
// POR QUE EXISTE. O export completo só podia ser exercitado em produção: a rota
// `/casos/[id]/export` depende do cliente Supabase, e um defeito nela aparecia
// como HTTP 500 numa aba do navegador, com o stack trace preso no log da Vercel.
// Foi assim que a âncora duplicada de `Obrigações Tributárias` (PR #100) chegou
// ao dono: uma página em branco. Com este script o mesmo defeito aparece como
// stack trace no terminal, em dois segundos.
//
// O QUE ELE REPLICA: exatamente as consultas da rota, na mesma ordem, montando o
// mesmo `ConfigModelagem` e a mesma `EntradaModeloInstitucional`, e chamando o
// MESMO `buildExportWorkbook`. Se este script gera e a rota não, a diferença é de
// AMBIENTE (RLS, permissão, timeout), não de lógica de planilha.
//
// COMO USAR:
//
//   # 1. banco local com as migrations e a fixture do caso real
//   TEST_DB=tdf_v35 PGDATABASE=postgres Supabase/test/run.sh
//   psql -d tdf_v35 -f Supabase/test/fixture_modelagem_v35.sql        # devolve o caso_id
//   # 2. configurar a modelagem (troque o v_caso no topo do arquivo)
//   psql -d tdf_v35 -f Supabase/roteiro_modelagem_v35.sql
//   # 3. gerar o arquivo
//   DB=tdf_v35 ./portal/node_modules/.bin/tsx portal/scripts/gerar-export-do-banco.mts <caso_id> /tmp/saida.xlsx
//
// A data é FIXA (2026-08-05), como em todo gerador deste repositório: `new Date()`
// aqui faria o arquivo mudar sozinho e um diff de bytes acusar mudança onde não
// houve.
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildExportWorkbook, finalizarBufferDoExport, type DocumentoParaExport, type ConfigModelagem } from "../src/lib/export.ts";
import type { EntradaModeloInstitucional, LinhaModelo } from "../src/lib/modelo-institucional.ts";
import type { CampoExtraido } from "../src/lib/types.ts";
import { casarVinculosComLinhas, seriesPorLinha, serieDaLinha } from "../src/lib/modelagem-linha.ts";

const DB = process.env.DB ?? "tdf_v35";
const CASO = process.argv[2];
if (!CASO) throw new Error("uso: repro-export.mts <caso_id>");
// O `caso_id` entra CRU em várias das consultas abaixo, por interpolação de texto.
// Isto aqui é ferramenta local de repro e o argumento vem do teclado do dono, então
// o risco prático é baixo — mas "baixo" não é "nenhum", e um id com aspa simples
// vira SQL arbitrário rodando como o dono do banco. Um caso é sempre um UUID
// (`caso.id` é `uuid` desde a 0001), então exigir o formato fecha o buraco inteiro
// sem trocar o jeito de escrever as consultas.
if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(CASO)) {
  throw new Error(`caso_id "${CASO}" não é um UUID — é assim que caso.id é gravado desde a 0001.`);
}

// `psql` é resolvido só nestes diretórios do sistema (sonar typescript:S4036):
// sem isto, `execFileSync` busca no `PATH` herdado do processo, e um `psql`
// plantado ANTES no `PATH` (variável de ambiente, não arquivo — nada que a
// validação do `caso_id` acima alcance) rodaria no lugar do binário real,
// com o mesmo acesso ao banco que este script já tem.
//
// A lista fixa NÃO cobre todo layout legítimo: falta o Homebrew
// (`/opt/homebrew/bin`) e falta `/usr/lib/postgresql/16/bin`, que é o próprio
// layout que o `CLAUDE.md` deste repositório manda usar para subir o Postgres
// de teste. Isso por si só falharia alto (ENOENT) e seria inofensivo — o caso
// ruim é o SILENCIOSO: numa máquina onde o dev tem os dois `psql` instalados
// (o do sistema em `/usr/bin` e um mais novo só em `/usr/lib/postgresql/16/bin`),
// a lista fixa acerta o mais VELHO sem avisar, e este script gera o artefato
// de conformidade que o dono usa para decidir se um bug é de ambiente ou de
// lógica de planilha. `PSQL_DIRS_SEGUROS` permite um override explícito
// quando a lista padrão não serve, e o binário resolvido é sempre impresso —
// nunca em silêncio.
const DIRS_PSQL_SEGUROS = process.env.PSQL_DIRS_SEGUROS
  ?? "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:/usr/lib/postgresql/16/bin";

function psqlResolvido(): string {
  for (const dir of DIRS_PSQL_SEGUROS.split(":")) {
    const candidato = join(dir, "psql");
    if (existsSync(candidato)) return candidato;
  }
  // Nenhum achado: deixa o `execFileSync` abaixo falhar com ENOENT, que já é o
  // caso "falha alto" desejado — não há binário a anunciar.
  return "psql";
}
const PSQL_BIN = psqlResolvido();
console.error(`[gerar-export-do-banco] psql resolvido: ${PSQL_BIN}`);

function q<T>(sql: string): T[] {
  const out = execFileSync(PSQL_BIN, ["-d", DB, "-tAc",
    `select coalesce(json_agg(t), '[]'::json)::text from (${sql}) t`],
    {
      encoding: "utf8",
      env: { ...process.env, PATH: DIRS_PSQL_SEGUROS },
      // O PADRÃO DO NODE É 1 MB, E ELE NÃO CHEGA PARA MANDATO GRANDE.
      //
      // MEDIDO em 17/09/2026 com o caso "AMO teste 00": a consulta de
      // `campo_extraido` (7.670 linhas) devolve ~2 MB de JSON, e
      // `execFileSync` estourou o buffer — o `JSON.parse` abaixo recebia a
      // string CORTADA no meio e morria com erro de sintaxe, que não diz
      // nada sobre a causa real. Ferramenta de repro que só funciona em caso
      // pequeno é ferramenta que falta justamente quando é mais necessária:
      // o caso grande é onde o defeito de layout aparece.
      maxBuffer: 512 * 1024 * 1024,
    });
  return JSON.parse(out.trim()) as T[];
}

const caso = q<{ id: string; nome: string; produto: string }>(
  `select id, nome, produto from caso where id = '${CASO}'`)[0];

const documentos = q<DocumentoParaExport>(`
  select d.id, d.tipo_taxonomia,
         json_build_object('razao_social', e.razao_social) as entidade,
         json_build_object('tipo', p.tipo, 'referencia', p.referencia) as periodo,
         (select coalesce(json_agg(json_build_object('id', dv.id, 'nome_original', dv.nome_original,
                                                     'n_versao', dv.n_versao)), '[]'::json)
            from documento_versao dv where dv.documento_id = d.id) as documento_versao
  from documento d
  left join entidade e on e.id = d.entidade_id
  left join periodo  p on p.id = d.periodo_id
  where d.caso_id = '${CASO}'`);

const versaoIds = documentos.flatMap((d) => (d.documento_versao ?? []).map((v) => v.id));
const campos = versaoIds.length ? q<CampoExtraido>(`
  select ce.id, ce.documento_versao_id, ce.secao, ce.secao_canonica, ce.entidade_coluna,
         ce.periodo_coluna, ce.chave, ce.valor_texto, ce.valor_num, ce.unidade, ce.confianca,
         ce.origem_pagina, ce.ordem, ce.status_aceite, ce.aceito_por, ce.aceito_em
  from campo_extraido ce
  where ce.documento_versao_id in (${versaoIds.map((v) => `'${v}'`).join(",")})
  order by ce.documento_versao_id, ce.ordem nulls last`) : [];

const par = q<{ entidade: string | null; ultimo_exercicio_real: number | null;
  anos_projetados: number; setor: string | null }>(
  `select entidade, ultimo_exercicio_real, anos_projetados, setor
   from caso_modelagem where caso_id = '${CASO}'`)[0] ?? null;

const premissas = q<{ codigo: string; nome: string; formula: string; unidade: string | null;
  natureza: string; origem: string | null; valores: Record<string, number> }>(`
  select cp.premissa_codigo as codigo, pc.nome, pc.formula::text as formula, pc.unidade,
         pc.natureza::text as natureza, cp.origem, cp.valores
  from caso_premissa cp join premissa_catalogo pc on pc.codigo = cp.premissa_codigo
  where cp.caso_id = '${CASO}' and cp.ativo`);

const vinculos = q<{ rotulo_norm: string; secao_canonica: string | null;
  premissa_codigo: string | null; sazonalidade_codigo: string | null }>(
  `select rotulo_norm, secao_canonica, premissa_codigo, sazonalidade_codigo
   from caso_linha_premissa where caso_id = '${CASO}'`);

const linhasRpc = q<{ secao_canonica: string | null; chave: string; rotulo_norm: string;
  valor_ultimo: number | null; papel: LinhaModelo["papel"]; unidade: string | null;
  moeda: string | null; documentos: string[] | null }>(
  `select * from fn_linhas_para_modelagem('${CASO}')`);

const curva = q<{ mes: number; fracao: number }>(
  `select mes, fracao from fn_sazonalidade_do_caso('${CASO}') order by mes`)
  .map((x) => Number(x.fracao));

const modelagemConfig: ConfigModelagem = {
  entidade: par?.entidade ?? null,
  sazonalidade: curva.length === 12 ? curva : undefined,
  ultimoExercicioReal: par?.ultimo_exercicio_real ?? null,
  anosProjetados: par?.anos_projetados ?? 5,
  premissas,
  linhas: casarVinculosComLinhas(vinculos, linhasRpc),
};

let modeloInstitucional: EntradaModeloInstitucional | undefined;
const entidadeModelada = par?.entidade?.trim() || null;
const ultimoReal = par?.ultimo_exercicio_real ?? null;
if (entidadeModelada && ultimoReal) {
  // `secao_canonica` VEM JUNTO e não é enfeite: a identidade da linha é o PAR
  // (seção, rótulo) — ver o comentário da rota. Sem ela, rótulo repetido entre
  // seções faz uma linha receber a série da outra.
  const valores = q<{ rotulo_norm: string; secao_canonica: string | null; ano: number; valor: number }>(
    `select rotulo_norm, secao_canonica, ano, valor from fn_valores_por_ano('${CASO}', '${entidadeModelada.replace(/'/g, "''")}')`);
  const anosHistoricos = [...new Set(valores.map((v) => v.ano))]
    .filter((a) => a <= ultimoReal).sort((a, b) => a - b);
  const nProj = par?.anos_projetados ?? 5;
  const anosProjetados = Array.from({ length: nProj }, (_, i) => ultimoReal + 1 + i);
  const series = seriesPorLinha(valores, anosHistoricos);
  const linhasModelo: LinhaModelo[] = linhasRpc.map((l) => ({
    secao_canonica: l.secao_canonica, chave: l.chave, rotulo_norm: l.rotulo_norm,
    papel: l.papel, unidade: l.unidade, moeda: l.moeda, documentos: l.documentos,
    valores: serieDaLinha(series, l.secao_canonica, l.rotulo_norm),
  }));
  const contagem = new Map<string, number>();
  for (const l of linhasModelo) if (l.unidade) contagem.set(l.unidade, (contagem.get(l.unidade) ?? 0) + 1);
  const unidadeDominante = [...contagem.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  modeloInstitucional = {
    caso: { nome: caso.nome, produto: caso.produto },
    agora: new Date("2026-08-05T12:00:00Z"),
    entidade: entidadeModelada,
    setor: par?.setor ?? null,
    anosHistoricos, anosProjetados,
    stressPct: 0.2, caixaMinimo: 0, aliquotaTributos: 0.34,
    linhas: linhasModelo,
    premissas,
    vinculos: vinculos.map((v) => ({
      rotulo_norm: v.rotulo_norm, premissa_codigo: v.premissa_codigo,
      sazonalidade_codigo: v.sazonalidade_codigo,
    })),
    macro: [],
    unidade: unidadeDominante === "milhar" ? "R$ mil"
      : unidadeDominante === "unidade" ? "R$" : (unidadeDominante ?? "R$"),
  };
}

console.log(`caso=${caso.nome} · documentos=${documentos.length} · campos=${campos.length}`
  + ` · premissas=${premissas.length} · vínculos=${vinculos.length}`
  + ` · linhas modelo=${linhasRpc.length} · curva=${curva.length}`
  + ` · modeloInstitucional=${modeloInstitucional ? "SIM" : "não"}`);

// MODO=dados gera o outro botão do portal (as abas de dado cru, sem modelo) —
// é o arquivo em que "nenhuma linha extraída pode faltar" se mede.
const modo = (process.env.MODO === "dados" ? "dados" : "completo") as "dados" | "completo";
const wb = buildExportWorkbook({
  caso, documentos, campos, modo, modelagemConfig, modeloInstitucional,
});
// Sem caminho explícito no argv, o padrão NÃO é um nome fixo dentro de /tmp
// (sonar typescript:S5443): `/tmp/v35-completo.xlsx` é previsível e o diretório
// é gravável por qualquer processo da máquina — outro processo local podia
// plantar um symlink nesse nome antes de rodar, ou ler o export (que carrega
// dado financeiro do caso) assim que ele é escrito. `mkdtempSync` cria um
// diretório com nome IMPREVISÍVEL e modo 0700 (só o dono lê/escreve) — mesma
// pasta-base do sistema, mas sem nome adivinhável nem permissão aberta.
const saida = process.argv[3]
  ?? join(mkdtempSync(join(tmpdir(), "gerar-export-do-banco-")), "v35-completo.xlsx");
// O MESMO caminho de saída da rota — sem isto, o arquivo que eu meço localmente
// não tem gráfico nem nota ampliada, e a medição mente sobre o entregável.
const { writeFile } = await import("node:fs/promises");
await writeFile(saida, await finalizarBufferDoExport(wb));
console.log(`OK — escrito ${saida}`);
// APRESENTACAO=<arquivo.pptx>: o deck de crédito pelo MESMO caminho da rota `?modo=apresentacao`
// (entrada do modelo COM os subtotais informados → base → deck). É o que permite testar a
// apresentação contra os mandatos do banco local sem subir o portal.
if (process.env.APRESENTACAO) {
  const { entradaDoModeloDoWorkbook } = await import("../src/lib/export.ts");
  const { montarBaseCredito } = await import("../src/lib/apresentacao/montar-base.ts");
  const { construirDeckCredito } = await import("../src/lib/apresentacao/deck-credito.ts");
  const ent = entradaDoModeloDoWorkbook(wb);
  if (!ent) throw new Error("o workbook não montou o modelo institucional: falta entidade ou último exercício real");
  const { informacaoDoKit, perimetroDoCaso } = await import("../src/lib/apresentacao/montar-base.ts");
  const kit = q<{ codigo: string; documento: string }>(
    "select codigo, documento from taxonomia_tipo_documento where obrigatoriedade = 'obrigatorio' order by codigo");
  // Mesma pergunta da rota ao banco (fn_documento_serve_como), aqui em SQL direto.
  const atendidos = new Set(q<{ codigo: string }>(`select t.codigo from taxonomia_tipo_documento t
    where t.obrigatoriedade = 'obrigatorio' and exists (select 1 from documento d where d.caso_id = '${CASO}'
      and (d.tipo_taxonomia = t.codigo or fn_documento_serve_como(d.id, t.codigo)))`).map((r) => r.codigo));
  const semConteudo = new Set(q<{ tipo_taxonomia: string }>(`select tipo_taxonomia from checklist_item_status
    where caso_id = '${CASO}' and status = 'recebido_nao_valido'`).map((r) => r.tipo_taxonomia));
  const entidades = q<{ razao_social: string; cnpj: string | null; papel_no_grupo: string | null }>(
    `select razao_social, cnpj, papel_no_grupo from entidade where caso_id = '${CASO}'`);
  const { deck } = construirDeckCredito(montarBaseCredito(ent, documentos, [], {
    informacao: informacaoDoKit(kit, atendidos, semConteudo),
    perimetro: perimetroDoCaso(entidades, documentos, ent.entidade ?? ""),
    projecao: (await import("../src/lib/apresentacao/projecao.ts")).projecaoDoModelo(wb, ent),
  }), new Date());
  await writeFile(process.env.APRESENTACAO, await deck.gerar());
  console.log(`OK — apresentação escrita em ${process.env.APRESENTACAO}`);
}
console.log(`abas: ${wb.worksheets.map((w) => w.name).join(" · ")}`);
