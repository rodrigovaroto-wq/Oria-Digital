import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import { lerCamposDasVersoes, lerDocumentosDoCaso, lerValoresPorAno } from "@/lib/leitura-do-caso";
import { veredictoDoPortao } from "@/lib/modelagem-cobertura";
import type { EntradaModeloInstitucional, LinhaModelo } from "@/lib/modelo-institucional";
import {
  buildExportWorkbook, finalizarBufferDoExport, nomeArquivoSanitizado, type ConfigModelagem,
  type MacroAnual, type MacroExpectativa,
} from "@/lib/export";
import {
  casarVinculosComLinhas, historicoDoModelo,
  type LinhaParaCasar, type VinculoParaCasar,
} from "@/lib/modelagem-linha";
// A apresentação de crédito importa em linhas PRÓPRIAS (e não acrescentando nomes às listas de cima):
// outro PR que mexa nas listas de import desta rota não colide com estas linhas.
import { entradaDoModeloDoWorkbook } from "@/lib/export";
import { correnteDoBalancete, informacaoDoKit, linhasDoAnoCorrenteDe, montarBaseCredito, perimetroDoCaso } from "@/lib/apresentacao/montar-base";
import { itensDoKitBasicoAtendidos } from "@/lib/kit-basico";
import { projecaoDoModelo } from "@/lib/apresentacao/projecao";
import { construirDeckCredito, SemDadoParaApresentar } from "@/lib/apresentacao/deck-credito";

// exceljs (usado em lib/export.ts) usa Buffer/streams do Node — precisa do
// runtime Node, não Edge.
export const runtime = "nodejs";

// A ROTA INTEIRA TEM DE TERMINAR EM RESPOSTA, NUNCA EM EXCEÇÃO CRUA.
//
// Toda consulta abaixo já degrada com mensagem em português (RLS, portão 2,
// base vazia — ver os comentários junto de cada uma). O que faltava era a
// MONTAGEM do arquivo: `buildExportWorkbook`/`finalizarBufferDoExport` e a
// modelagem que os alimenta rodam sobre razão social, CNPJ e valor que vieram
// de PDF lido por IA — a mesma superfície que já produziu nome truncado
// colado com endereço (0168) e byte de controle em rótulo (8d378b0). Uma
// exceção nessa etapa nunca chegava a um `NextResponse`: a Vercel encerra a
// função e devolve a página genérica "Esta página não está funcionando /
// HTTP ERROR 500", sem corpo e sem stack — o analista fica sem saber SE o
// caso tem um defeito de dado ou se é a mesma causa de sempre (RLS/portão).
// `console.error` aqui é o MESMO já usado nos ramos abaixo: fica no log
// do servidor (Vercel), não no arquivo — mas para de ser invisível para
// sempre, e a resposta passa a ter um corpo que o navegador consegue mostrar.
export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
  // O CORPO ABAIXO FICA NO NÍVEL DE INDENTAÇÃO ORIGINAL (não +2, dentro do
  // `try`), de propósito: reindentar mudaria o TEXTO de toda linha da função,
  // e isso faz o SonarCloud (que rastreia issue por linha via git blame)
  // reclassificar a complexidade cognitiva já existente desta rota — medida
  // e aceita há muito em `main` (regra `typescript:S3776`, não nova aqui)
  // como se fosse recém-introduzida, derrubando o Quality Gate por um
  // reformate que não muda comportamento nenhum. Achado ao investigar por
  // que o PR #225 ficou vermelho no Sonar sem tocar em nenhuma linha de TS.
  const { id } = await params;
  // MODO (decisão do dono): `?modo=dados` entrega só as abas de dado — insumo de
  // conferência, disponível desde a ingestão. Sem o parâmetro sai o completo, com
  // a Modelagem. Valor desconhecido cai em "completo" em vez de erro: um link
  // datilografado errado não deve deixar o analista sem arquivo.
  const modoPedido = new URL(request.url).searchParams.get("modo");
  const modo = modoPedido === "dados" ? "dados" : "completo";
  // `?modo=apresentacao` é o COMPLETO com outra saída: a apresentação de crédito (.pptx) lê o mesmo
  // realizado que o modelo institucional, então passa pelo mesmo Portão 2 e pela mesma leitura.
  const apresentacao = modoPedido === "apresentacao";
  const supabase = await createClient();

  const [casoRes, documentosRes] = await Promise.all([
    supabase.from("caso").select("id, nome, produto").eq("id", id).single(),
    lerDocumentosDoCaso(supabase, id),
  ]);

  if (casoRes.error || !casoRes.data) {
    return NextResponse.json({ error: "Caso não encontrado." }, { status: 404 });
  }

  const caso = casoRes.data;

  // `.error` das consultas PRINCIPAIS: a 0028 nomeou este defeito ("`?? []` sobre
  // `.data`, sem olhar `.error`") e corrigiu SÓ o ramo macro. Aqui era o pior lugar
  // para ele estar: erro de RLS/permissão/relacionamento no PostgREST produzia um
  // book com "Linhas totais extraídas: 0" e nenhuma mensagem — exatamente o sintoma
  // do teste v14, que a 0016 tentou tornar impossível.
  //
  // E aqui a resposta certa é DIFERENTE da do macro. Macro é opcional: a aba declara
  // "a consulta falhou" e o resto do book segue valendo. Sem `documento` ou
  // `campo_extraido`, o book não tem conteúdo nenhum — entregar um arquivo vazio é
  // pior que não entregar, porque um `.xlsx` que abre parece um resultado.
  if (documentosRes.error) {
    console.error(`[export] consulta de documentos falhou: ${documentosRes.error.message}`, { caso_id: id });
    return NextResponse.json(
      {
        error: "Não foi possível ler os documentos deste caso — o export foi ABORTADO em vez de gerar uma planilha vazia.",
        detalhe: documentosRes.error.message,
        dica: "Causa mais comum: RLS/GRANT (ver Supabase/migrations/0028). O dado pode estar na base; a consulta é que não chegou nele.",
      },
      { status: 500 },
    );
  }
  const documentos = documentosRes.data;

  const versaoIds = documentos.flatMap((doc) => (doc.documento_versao ?? []).map((v) => v.id));
  // PAGINADO, E AQUI ERA O PIOR LUGAR PARA NÃO ESTAR.
  //
  // O PostgREST do Supabase devolve no máximo `db-max-rows` por consulta — 1000
  // por padrão — e corta acima disso EM SILÊNCIO, sem erro. Este é o `.xlsx`
  // que vai a comitê: um mandato com mais de mil linhas extraídas gerava um
  // arquivo faltando linhas, que abre normalmente e parece completo. O book de
  // teste sozinho tem ~3.000 linhas com número.
  //
  // Não dá para trocar por `count` como se fez com o indicador do painel: aqui
  // as LINHAS são o produto. Então lê de mil em mil, na mesma ordem.
  const camposRes = await lerCamposDasVersoes(supabase, versaoIds);

  if (camposRes.error) {
    console.error(`[export] consulta de campos extraídos falhou: ${camposRes.error.message}`, { caso_id: id });
    return NextResponse.json(
      {
        error: "Não foi possível ler as linhas extraídas — o export foi ABORTADO em vez de gerar uma planilha sem números.",
        detalhe: camposRes.error.message,
        dica: "Causa mais comum: RLS/GRANT (ver Supabase/migrations/0028). O dado pode estar na base; a consulta é que não chegou nele.",
      },
      { status: 500 },
    );
  }
  const campos = camposRes.data;

  // POR QUE a extração falhou, e não só QUAIS documentos falharam. No "teste v30"
  // os 14 documentos falharam e o export listava os nomes — a CAUSA (que a
  // pendência já registrava) ficava só na fila de revisão, numa tela diferente.
  // Quem abre o book precisa saber, ali, se o problema é crédito do provedor de IA, cota
  // do dia ou cadência: as três pedem ações diferentes e só uma delas é nossa.
  const falhasRes = await paginar<{ descricao: string | null; documento_id: string | null }>((de, ate) =>
    supabase
      .from("pendencia")
      .select("descricao, documento_id")
      .eq("caso_id", id)
      .eq("tipo", "extracao_falhou")
      .neq("estado", "resolvida")
      .order("id", { ascending: true })
      .range(de, ate),
  );
  // Esta é auxiliar (a lista de causas), então segue a doutrina do macro: declara
  // que não deu para ler, em vez de abortar o book inteiro ou omitir em silêncio.
  if (falhasRes.error) {
    console.error(`[export] consulta de causas de falha falhou: ${falhasRes.error.message}`, { caso_id: id });
  }
  const causasDeFalha = [
    ...(falhasRes.error
      ? [`(não foi possível ler as causas registradas: ${falhasRes.error.message})`]
      : []),
    ...new Set(
      (falhasRes.data)
        .map((p) => p.descricao ?? "")
        // A descrição da pendência é "Extração de 'X.pdf' falhou ... Motivo: <causa>".
        // Só a causa interessa aqui: o nome do arquivo já vai na outra coluna, e
        // repetir 14 vezes o mesmo motivo esconderia o que importa.
        .map((d) => d.split(/Motivo:\s*/)[1]?.trim())
        .filter((c): c is string => !!c),
    ),
  ];

  // Índices macro (Supabase/migrations/0025). São do CASO nenhum — a série é a mesma
  // para todos os mandatos —, por isso vêm à parte e não filtram por caso.
  // Falha aqui NÃO derruba o export: sem macro o arquivo sai como sempre saiu,
  // só sem a aba Macro e com as premissas de inflação/juro zeradas. Um índice
  // indisponível não pode impedir alguém de baixar a planilha do mandato.
  const [anuaisRes, expRes, obsRes] = await Promise.all([
    supabase.rpc("fn_indice_macro_anual", { p_desde_ano: new Date().getFullYear() - 11 }),
    // PAGINADA: cada coleta do Focus acrescenta linhas (série × ano projetado),
    // então esta tabela cresce sozinha com o tempo — e a leitura escolhe a
    // coleta MAIS RECENTE de cada (série, ano). Truncar aqui não deixa o
    // arquivo sem macro: deixa o arquivo com a expectativa ERRADA, que é pior.
    // O desempate por (serie, ano_ref) é o que torna a ordem total — sem ele
    // duas páginas podem repetir e omitir a mesma coleta.
    paginar<MacroExpectativa>((de, ate) =>
      supabase
        .from("indice_macro_expectativa")
        .select("serie, ano_ref, mediana, coletado_em")
        .gte("ano_ref", new Date().getFullYear() - 1)
        .order("coletado_em", { ascending: false })
        .order("serie", { ascending: true })
        .order("ano_ref", { ascending: true })
        .range(de, ate)),
    // AS OBSERVAÇÕES CRUAS, para as séries de NÍVEL.
    //
    // `fn_indice_macro_anual` devolve, para série de nível, a VARIAÇÃO entre o
    // primeiro e o último fechamento do ano — e o modelo institucional tem uma linha
    // de nível ("R$/US$ — final de período") alimentada por ela. O arquivo entregue
    // em 06/08/2026 saiu com câmbio de 24,5 em 2024 e **−10,6** em 2025 ao lado de
    // 5,2 do Focus (que é nível): duas grandezas na mesma linha, e ela converte
    // dívida em moeda estrangeira.
    //
    // O nível de fechamento do ano vem daqui, da própria observação. Sem migration:
    // a tabela já é legível pelo papel `authenticated` (0028).
    //
    // PAGINADA, e esta é a que já estava perto do teto: são seis séries
    // mensais com histórico longo — 920 observações no seed versionado, mais
    // ~72 por ano que passa. Ao cruzar 1000, o PostgREST cortaria **as mais
    // recentes** (a ordem é crescente por data), e a mais recente é exatamente
    // a que dá o nível de fechamento do ano usado na linha de câmbio. O
    // sintoma seria um câmbio velho num arquivo novo, sem erro nenhum.
    paginar<{ serie: string; data_ref: string; valor: number }>((de, ate) =>
      supabase
        .from("indice_macro_obs")
        .select("serie, data_ref, valor")
        .order("data_ref", { ascending: true })
        .order("serie", { ascending: true })
        .range(de, ate)),
  ]);

  // Erro de CONSULTA (RLS sem policy volta 0 linhas sem erro; função sem
  // `grant execute` para `authenticated` volta erro de permissão — os dois
  // aconteceram de fato na `0025`, ver Supabase/migrations/0028) é DIFERENTE de "sem
  // dado coletado", e as duas coisas não podem cair na mesma mensagem — foi
  // exatamente essa confusão que fez o export dizer "sem dado coletado" com a
  // base já povoada. `console.error` fica nos logs da função (Vercel/servidor):
  // não é visível no arquivo, mas para de ser invisível PARA SEMPRE.
  const nomesRes = await supabase.from("indice_macro_serie").select("codigo, nome");
  // NOMEAR a parte que falhou, não só a primeira mensagem. Com `??` em cadeia,
  // uma falha só nos NOMES das séries produzia uma mensagem indistinguível de
  // uma falha nos índices — e as duas degradam o arquivo de formas diferentes
  // (código cru no rótulo × série inteira ausente). Quem for conferir no
  // Supabase precisa saber onde olhar.
  const macroErro = [
    anuaisRes.error && `índices anuais: ${anuaisRes.error.message}`,
    expRes.error && `expectativas do Focus: ${expRes.error.message}`,
    nomesRes.error && `nomes das séries: ${nomesRes.error.message}`,
  ].filter(Boolean).join("; ") || undefined;
  if (macroErro) {
    console.error(`[export] consulta de índices macro falhou: ${macroErro}`, {
      anuais: anuaisRes.error, expectativas: expRes.error, series: nomesRes.error,
    });
  }

  const anuais = (anuaisRes.data as MacroAnual[] | null) ?? [];
  // A API devolve todas as coletas; para o export vale a MAIS RECENTE de cada
  // (série, ano) — e como vem ordenado por coleta decrescente, o primeiro que
  // aparece já é o certo.
  const vistos = new Set<string>();
  const expectativas = ((expRes.data as MacroExpectativa[] | null) ?? []).filter((e) => {
    const k = `${e.serie}/${e.ano_ref}`;
    if (vistos.has(k)) return false;
    vistos.add(k);
    return true;
  });

  const nomes = Object.fromEntries(
    (nomesRes.data ?? []).map((s: { codigo: string; nome: string }) => [s.codigo, s.nome]),
  );

  const macro = anuais.length > 0 || expectativas.length > 0
    ? { anuais, expectativas, nomes }
    : undefined;

  // Natureza por série e nível de fechamento por (série, ano) — os dois insumos que
  // impedem publicar variação numa linha de nível (ver a consulta `obsRes`).
  const naturezaDaSerie = new Map<string, "taxa" | "nivel">();
  for (const a of anuais) {
    if (a.natureza === "nivel" || a.natureza === "taxa") naturezaDaSerie.set(a.serie, a.natureza);
  }
  // As observações vêm ordenadas por data crescente, então a última escrita de cada
  // (série, ano) é o fechamento do ano.
  const nivelDeFechamento = new Map<string, { valor: number; data: string }>();
  if (obsRes.error) {
    console.error(`[export] consulta de observações macro falhou: ${obsRes.error.message}`);
  }
  for (const o of ((obsRes.data as Array<{ serie: string; data_ref: string; valor: number }> | null) ?? [])) {
    const ano = Number(o.data_ref.slice(0, 4));
    if (!Number.isFinite(ano)) continue;
    nivelDeFechamento.set(`${o.serie}|${ano}`, { valor: Number(o.valor), data: o.data_ref });
  }

  // ---- Fase 7.4: a configuração de modelagem e o Portão 2 -------------------
  //
  // O modo COMPLETO carrega um modelo projetado. Entregar isso sobre base que não
  // passou o Portão 2 seria dar aparência de resultado aprovado a número que
  // ninguém aprovou — e a regra do portão é determinística (Arquitetura do Sistema/2 Especificação/f0/04, 0037), então
  // não há julgamento a fazer aqui: pergunta-se e obedece-se.
  //
  // O modo DADOS não passa por aqui de propósito: ele é insumo de CONFERÊNCIA, e
  // conferir é justamente o que se faz antes de aprovar. Bloqueá-lo criaria o
  // impasse de precisar da aprovação para poder conferir.
  let modelagemConfig: ConfigModelagem | undefined;
  let modeloInstitucional: EntradaModeloInstitucional | undefined;
  // O ANO CORRENTE (balancete), para o "resultado atual" da apresentação: o modelo projeta a partir do
  // último exercício FECHADO e descarta o ano em curso; a apresentação o mostra à parte, como parcial.
  let linhasDoAnoCorrente: { ano: number; linhas: LinhaModelo[] } | null = null;
  if (modo === "completo") {
    const portao = await supabase.rpc("fn_avaliar_portao2", { p_caso_id: id });
    const { estado, portao: aval } = veredictoDoPortao(portao);
    // FAIL-CLOSED: se o RPC falhou (ou não devolveu veredito) o Portão 2 é DESCONHECIDO,
    // e desconhecido não é aberto — a MESMA regra da tela (`veredictoDoPortao`). Antes o
    // export seguia sobre base possivelmente não aprovada. Mesma resposta amigável do 409,
    // status 503 por ser falha de conferência. O erro cru fica no log do servidor: a
    // mensagem do Postgres não é para o navegador.
    if (estado === "nao_conferido" || !aval) {
      console.error("[export] Portão 2 não conferido", { caso_id: id, erro: portao.error?.message ?? null });
      return NextResponse.json(
        {
          error: "O export COMPLETO foi recusado: não foi possível conferir o Portão 2.",
          motivos: ["Não foi possível conferir o Portão 2; recarregue a página ou tente mais tarde."],
          dica: "Tente de novo em instantes. \"Exportar dados\" continua disponível para conferir a "
            + "extração — esse modo não depende do portão. O completo carrega modelo projetado, e "
            + "projetar sem saber se a base foi aprovada daria aparência de resultado aprovado.",
        },
        { status: 503 },
      );
    }
    if (aval.elegivel === false) {
      return NextResponse.json(
        {
          error: "O export COMPLETO foi recusado: este caso não passou o Portão 2.",
          motivos: aval.motivos ?? [],
          dica: "Use \"Exportar dados\" para conferir a extração — esse modo não depende do portão. "
            + "O completo carrega modelo projetado, e projetar sobre base não aprovada dá aparência "
            + "de resultado aprovado a número que ninguém aprovou.",
        },
        { status: 409 },
      );
    }

    // A configuração vem em três consultas porque são três coisas distintas:
    // parâmetros do caso, premissas ativas (com o catálogo para saber a fórmula),
    // e o vínculo linha↔premissa. Ausência de qualquer uma NÃO é erro: o arquivo
    // sai com o esqueleto agregado, como sempre saiu.
    const [paramRes, premRes, vincRes, linhasRes, sazoRes] = await Promise.all([
      // Colunas nomeadas, nunca `*` — ver a nota em modelagem/page.tsx. O tipo
      // `par`, logo abaixo, é a lista autoritativa do que o export realmente lê.
      supabase.from("caso_modelagem")
        .select("entidade, ultimo_exercicio_real, anos_projetados, setor")
        .eq("caso_id", id).maybeSingle(),
      supabase.from("caso_premissa")
        .select("premissa_codigo, valores, origem, "
          + "premissa_catalogo!inner(nome, formula, unidade, natureza)")
        .eq("caso_id", id).eq("ativo", true),
      // OS VÍNCULOS e AS LINHAS do modelo, PAGINADOS: os dois crescem com o
      // tamanho do mandato (uma linha por rótulo distinto do book), e são o
      // conteúdo das 14 abas. Truncar aqui produziria um modelo que abre
      // normalmente com contas faltando — o modo de falha mais caro deste
      // sistema. A ordem de `fn_linhas_para_modelagem` (seção, rótulo) é a que
      // a própria função declara, e ela já é TOTAL: a função agrupa por esse
      // par exato.
      paginar<VinculoParaCasar>((de, ate) =>
        supabase.from("caso_linha_premissa")
          .select("rotulo_norm, secao_canonica, premissa_codigo, sazonalidade_codigo")
          .eq("caso_id", id)
          .order("rotulo_norm", { ascending: true })
          .order("secao_canonica", { ascending: true, nullsFirst: true })
          .range(de, ate)),
      paginar<LinhaParaCasar & Record<string, unknown>>((de, ate) =>
        supabase.rpc("fn_linhas_para_modelagem", { p_caso_id: id })
          .order("secao_canonica", { ascending: true, nullsFirst: false })
          .order("rotulo_norm", { ascending: true })
          .range(de, ate)),
      // A curva mensal do caso (0040). Vem vazia quando não há FATURAMENTO_24M —
      // e aí as linhas com sazonalidade ficam sem distribuição mensal, dizendo
      // por quê, em vez de rateio uniforme.
      supabase.rpc("fn_sazonalidade_do_caso", { p_caso_id: id }),
    ]);

    const par = paramRes.data as unknown as {
      entidade: string | null; ultimo_exercicio_real: number | null; anos_projetados: number;
      setor: string | null;
    } | null;
    // O embed do PostgREST vem como ARRAY (ele não assume 1:1 no tipo gerado),
    // então normaliza-se aqui em vez de confiar no formato — um `?.nome` sobre
    // array daria `undefined` silencioso e a premissa apareceria sem nome no
    // arquivo.
    type EmbedCatalogo = {
      nome: string; formula: string; unidade: string | null; natureza?: string;
    };
    const premissas = ((premRes.data ?? []) as unknown as Array<{
      premissa_codigo: string; valores: Record<string, number>;
      origem?: string | null;
      premissa_catalogo: EmbedCatalogo | EmbedCatalogo[] | null;
    }>).map((p) => {
      const cat = Array.isArray(p.premissa_catalogo) ? p.premissa_catalogo[0] : p.premissa_catalogo;
      return {
        codigo: p.premissa_codigo,
        nome: cat?.nome ?? p.premissa_codigo,
        formula: cat?.formula ?? "",
        unidade: cat?.unidade ?? null,
        natureza: cat?.natureza ?? "",
        origem: p.origem ?? null,
        valores: p.valores ?? {},
      };
    });

    // O rótulo EXIBIDO e o valor base vêm de `fn_linhas_para_modelagem` (0039),
    // casados pelo PAR (seção, rótulo normalizado) — a mesma identidade que o
    // índice único de `caso_linha_premissa` usa. Sem a seção, rótulo repetido
    // entre seções (13 no caso do v35: `Empréstimos e Financiamentos`,
    // `Arrendamentos`, `Capital social`…) fazia o vínculo herdar o valor base da
    // OUTRA seção, e a projeção partia do saldo errado sem dar erro nenhum.
    const linhas = casarVinculosComLinhas(
      (vincRes.data ?? []) as unknown as VinculoParaCasar[],
      (linhasRes.data ?? []) as unknown as LinhaParaCasar[],
    );

    if (par || premissas.length > 0 || linhas.length > 0) {
      const curva = ((sazoRes.data ?? []) as unknown as Array<{ mes: number; fracao: number }>)
        .sort((a2, b2) => a2.mes - b2.mes)
        .map((x) => Number(x.fracao));

      modelagemConfig = {
        entidade: par?.entidade ?? null,
        sazonalidade: curva.length === 12 ? curva : undefined,
        ultimoExercicioReal: par?.ultimo_exercicio_real ?? null,
        anosProjetados: par?.anos_projetados ?? 5,
        premissas,
        linhas,
      };
    }

    // ---- Fase 9: o MODELO INSTITUCIONAL --------------------------------------
    //
    // Ele exige DUAS coisas que o modelo agregado não exigia, e as duas são
    // condição de existência e não preferência:
    //
    //   • ENTIDADE MODELADA. Sem ela o modelo somaria o ativo de uma empresa do
    //     grupo com o passivo de outra — foi medido contra o book (0044): "Ativo
    //     Circulante 2024" devolvia o da VT Logística enquanto a Metalúrgica
    //     tinha 17× mais. Balanço que não existe em lugar nenhum, com cara de
    //     balanço.
    //   • ÚLTIMO EXERCÍCIO REAL, para saber onde termina o realizado e começa a
    //     projeção. Adivinhar isso pelo maior ano extraído erraria justamente no
    //     caso em que o cliente mandou um balancete parcial do ano corrente.
    //
    // Faltando qualquer uma, o arquivo sai SEM as 14 abas e o motivo é dito no
    // cabeçalho da resposta — em vez de sair um modelo silenciosamente errado.
    const entidadeModelada = par?.entidade?.trim() || null;
    const ultimoReal = par?.ultimo_exercicio_real ?? null;
    if (entidadeModelada && ultimoReal) {
      // PAGINADA: uma linha por (rótulo × exercício). Com três exercícios, 400
      // rótulos distintos já passam de mil — e o book da Canastra tem 3.034
      // linhas com número. É daqui que sai a SÉRIE HISTÓRICA de cada conta do
      // modelo: cortar aqui não deixa buraco visível, deixa uma conta com menos
      // anos do que ela tem, e a projeção parte de uma base falsa.
      //
      // A ordem da função é (rótulo, ano); a seção entra como desempate final
      // porque o mesmo rótulo existe em seções diferentes (`Empréstimos e
      // Financiamentos` no circulante e no não circulante), e é o trio que a
      // função agrupa — ou seja, o que torna a ordem TOTAL.
      // 0125: a proveniência DA CÉLULA vem na mesma consulta (ver `lerValoresPorAno`).
      const valoresRes = await lerValoresPorAno(supabase, id, entidadeModelada);
      // ERRO DE CONSULTA AQUI NÃO ERA LOGADO EM LUGAR NENHUM — ao contrário de
      // TODA outra consulta desta rota. `paginar` engole o `.error` e devolve
      // `data: []`, então uma falha em `fn_valores_por_ano` (RLS, função ausente
      // por migration não aplicada) saía como Modelo Institucional com as 14
      // abas presentes e TODA série histórica vazia — sem nota, sem log, sem
      // diferença visível de um caso que legitimamente não tem valor nenhum.
      if (valoresRes.error) {
        console.error(`[export] consulta de valores por ano falhou: ${valoresRes.error.message}`, { caso_id: id });
      }
      const valores = valoresRes.data;
      // O histórico (exercícios até o último real, série e proveniência por linha, unidade
      // dominante) sai de `historicoDoModelo` — a MESMA função que a tela de Modelagem usa
      // para sugerir as premissas do realizado. Ver a nota dela.
      const historico = historicoDoModelo(
        (linhasRes.data ?? []) as unknown as Parameters<typeof historicoDoModelo>[0],
        valores, ultimoReal,
      );
      const { anosHistoricos } = historico;
      const nProj = par?.anos_projetados ?? 5;
      const anosProjetados = Array.from({ length: nProj }, (_, i) => ultimoReal + 1 + i);
      const linhasModelo: LinhaModelo[] = historico.linhas;

      // A base macro do modelo: realizado + Focus, com a fonte de cada célula.
      //
      // SÉRIE DE NÍVEL ENTREGA NÍVEL. Para `natureza = 'nivel'` o valor do ano é o
      // ÚLTIMO fechamento observado, não o retorno — e quando não há observação para
      // o ano, a série NÃO entra (o modelo deixa a célula vazia dizendo por quê, em
      // vez de publicar variação numa linha de nível).
      type MacroDoModelo = {
        serie: string; ano: number; valor: number; fonte: string; natureza: "taxa" | "nivel";
        /** meses que o REALIZADO cobre; < 12 não é taxa anual (o modelo recusa na aba Anual) */
        meses?: number;
        /** estruturado: a aba Anual decide a fórmula do CDI por ele, nunca pelo texto de `fonte` */
        origem: "focus" | "realizado";
      };
      // O ano em curso para a apresentação (fica AQUI, longe da leitura do histórico logo acima, para
      // que mudanças naquela leitura não colidam com esta linha).
      linhasDoAnoCorrente = linhasDoAnoCorrenteDe((linhasRes.data ?? []) as unknown as LinhaModelo[], valores, ultimoReal);
      const macroModelo: MacroDoModelo[] = [
        ...anuais.flatMap((a): MacroDoModelo[] => {
          if (a.natureza === "nivel") {
            const nivel = nivelDeFechamento.get(`${a.serie}|${a.ano}`);
            if (nivel === undefined) return [];
            return [{
              serie: a.serie, ano: a.ano, valor: nivel.valor, natureza: "nivel",
              fonte: `realizado — fechamento de ${nivel.data}`, origem: "realizado",
            }];
          }
          return [{
            serie: a.serie, ano: a.ano, valor: Number(a.retorno), natureza: "taxa",
            fonte: `realizado (${a.meses} meses)`, meses: Number(a.meses), origem: "realizado",
          }];
        }),
        ...expectativas.map((e): MacroDoModelo => ({
          serie: e.serie, ano: e.ano_ref, valor: Number(e.mediana),
          // A expectativa do Focus para câmbio é publicada em NÍVEL (R$/US$ de fim de
          // período), e para IPCA/Selic/CDI em taxa — a natureza é da SÉRIE, então ela
          // vem da mesma classificação usada no realizado.
          natureza: naturezaDaSerie.get(e.serie) ?? "taxa",
          fonte: `Focus, coleta ${e.coletado_em}`, origem: "focus",
        })),
      ];

      modeloInstitucional = {
        caso: { nome: caso.nome, produto: caso.produto },
        agora: new Date(),
        entidade: entidadeModelada,
        setor: par?.setor ?? null,
        anosHistoricos, anosProjetados,
        stressPct: 0.2,
        caixaMinimo: 0,
        aliquotaTributos: 0.34,
        linhas: linhasModelo,
        premissas,
        vinculos: ((vincRes.data ?? []) as unknown as Array<{
          rotulo_norm: string; premissa_codigo: string | null; sazonalidade_codigo: string | null;
        }>).map((v) => ({
          rotulo_norm: v.rotulo_norm,
          premissa_codigo: v.premissa_codigo,
          sazonalidade_codigo: v.sazonalidade_codigo,
        })),
        macro: macroModelo,
        unidade: historico.unidade,
      };
    }
  }

  const workbook = buildExportWorkbook({
    caso, documentos, campos, macro, macroErro, causasDeFalha, modo, modelagemConfig,
    modeloInstitucional,
  });
  if (apresentacao) {
    const entradaDoModelo = entradaDoModeloDoWorkbook(workbook);
    if (!entradaDoModelo) {
      return NextResponse.json(
        {
          error: "A apresentação de crédito não foi gerada: este caso ainda não tem o modelo institucional montado.",
          motivos: ["Falta a entidade modelada, o último exercício real ou os anos projetados na tela de Modelagem — ou não há exercício com valor numérico."],
          dica: "A apresentação lê o MESMO realizado do modelo. Sem a entidade, ela somaria o balanço de uma empresa do "
            + "grupo com o de outra; sem o último exercício real, trataria balancete parcial como ano fechado.",
        },
        { status: 409 },
      );
    }
    // Os campos "[a preencher]" já preenchidos (0205). Falha de leitura NÃO derruba o deck — banco
    // sem a 0205, RLS —: ele sai com as lacunas como sempre saiu, e o motivo fica no log.
    const camposRes = await supabase.from("caso_apresentacao_campo").select("chave, valor, fonte").eq("caso_id", id);
    if (camposRes.error) console.error(`[export] campos da apresentação não lidos: ${camposRes.error.message}`, { caso_id: id });
    const camposAp = (camposRes.data ?? []) as Array<{ chave: string; valor: string; fonte: string | null }>;
    // O KIT BÁSICO e o PERÍMETRO (slides IX.2 e III.3). Leitura que falha deixa o slide dizendo que
    // não leu — nunca "nada faltou" nem "empresa única" por omissão.
    const [kitRes, checkRes, entRes] = await Promise.all([
      supabase.from("taxonomia_tipo_documento").select("codigo, documento").eq("obrigatoriedade", "obrigatorio").order("codigo"),
      supabase.from("checklist_item_status").select("tipo_taxonomia, status").eq("caso_id", id),
      supabase.from("entidade").select("razao_social, cnpj, papel_no_grupo").eq("caso_id", id),
    ]);
    let informacao: ReturnType<typeof informacaoDoKit> | undefined;
    if (!kitRes.error && kitRes.data) {
      const kit = kitRes.data as Array<{ codigo: string; documento: string }>;
      const atendidos = await itensDoKitBasicoAtendidos(kit, documentos.map((d) => ({ id: d.id, tipo_taxonomia: d.tipo_taxonomia })),
        async (documentoId, tipo) => {
          const r = await supabase.rpc("fn_documento_serve_como", { p_documento_id: documentoId, p_tipo_taxonomia: tipo });
          return !r.error && r.data === true;
        });
      const semConteudo = new Set(((checkRes.data ?? []) as Array<{ tipo_taxonomia: string; status: string }>)
        .filter((c) => c.status === "recebido_nao_valido").map((c) => c.tipo_taxonomia));
      informacao = informacaoDoKit(kit, atendidos, semConteudo);
    } else console.error(`[export] kit básico não lido: ${kitRes.error?.message}`, { caso_id: id });
    const perimetro = entRes.error ? undefined : perimetroDoCaso(
      (entRes.data ?? []) as Array<{ razao_social: string; cnpj: string | null; papel_no_grupo: string | null }>,
      documentos, entradaDoModelo.entidade ?? "");
    let deck;
    try {
      ({ deck } = construirDeckCredito(montarBaseCredito(entradaDoModelo, documentos, camposAp, { informacao, perimetro, projecao: projecaoDoModelo(workbook, entradaDoModelo),
        corrente: linhasDoAnoCorrente ? correnteDoBalancete(entradaDoModelo, linhasDoAnoCorrente.linhas, linhasDoAnoCorrente.ano, documentos) : null }, campos), new Date()));
    } catch (e) {
      if (!(e instanceof SemDadoParaApresentar)) throw e;
      return NextResponse.json({ error: "A apresentação de crédito não foi gerada.", motivos: [e.message] }, { status: 409 });
    }
    const pptx = await deck.gerar();
    const nomePptx = `${nomeArquivoSanitizado(caso.nome)}-apresentacao-credito-${new Date().toISOString().slice(0, 10)}.pptx`;
    return new NextResponse(pptx as unknown as BodyInit, {
      headers: {
        "Content-Type": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "Content-Disposition": `attachment; filename="${nomePptx}"`,
      },
    });
  }
  const buffer = await finalizarBufferDoExport(workbook);
  // O nome do arquivo DIZ qual dos dois é. Dois arquivos com o mesmo nome na
  // pasta de Downloads, um com modelo e outro sem, é confusão garantida — e a
  // pergunta "qual desses é o completo?" não tem resposta olhando o ícone.
  const sufixo = modo === "dados" ? "dados-financeiros" : "modelagem";
  const filename = `${nomeArquivoSanitizado(caso.nome)}-${sufixo}-${new Date().toISOString().slice(0, 10)}.xlsx`;

  // O TETO DE SEGURANÇA DA LEITURA, quando ele for atingido, SAI DO SILÊNCIO.
  //
  // `paginar` lê até meio milhão de linhas por consulta e, se parar aí, declara
  // (`truncado`). Meio milhão está muito além de qualquer mandato — mas este é o
  // arquivo que vai a comitê, e o defeito que originou toda esta linhagem foi
  // exatamente um corte silencioso numa leitura. Um arquivo incompleto que não
  // se anuncia é pior que um erro: ele abre normalmente e parece completo.
  const truncadas = [
    documentosRes.truncado && "documentos",
    camposRes.truncado && "linhas extraídas",
    falhasRes.truncado && "causas de falha",
    expRes.truncado && "expectativas macro",
    obsRes.truncado && "observações macro",
  ].filter(Boolean) as string[];
  if (truncadas.length > 0) {
    console.error(`[export] leitura interrompida pelo teto de segurança: ${truncadas.join(", ")}`,
      { caso_id: id });
  }

  return new NextResponse(buffer as unknown as BodyInit, {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="${filename}"`,
      ...(truncadas.length > 0
        ? { "X-Oria-Leitura-Truncada": truncadas.join(", ") }
        : {}),
    },
  });
  } catch (e) {
    const { id } = await params;
    const erro = e instanceof Error ? e : new Error(String(e));
    console.error(`[export] falha inesperada ao montar o arquivo: ${erro.stack ?? erro.message}`, { caso_id: id });
    return NextResponse.json(
      {
        error: "O export falhou de um jeito inesperado ao montar o arquivo — não é nenhuma das causas já "
          + "conhecidas (RLS/GRANT, Portão 2, base vazia). O detalhe foi registrado no log do servidor.",
        detalhe: erro.message,
      },
      { status: 500 },
    );
  }
}
