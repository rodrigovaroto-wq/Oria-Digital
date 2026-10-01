import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import { SecaoLinhas } from "./SecaoLinhas";
import { FormParametros, FormPremissa } from "./FormsTopo";
import { SugestoesDoRealizado } from "./SugestoesDoRealizado";
import { sugerirDoRealizado } from "@/lib/premissas-do-realizado";
import { chaveDaLinha, vinculoPorLinha } from "@/lib/modelagem-linha";
import { portaoFechado, portaoNaoConferido, textoChipModelagem, textoTituloConferenciaModelagem, veredictoDoPortao } from "@/lib/modelagem-cobertura";
import { humanizar, rotuloDaSecao } from "@/lib/rotulos";

// A seção MODELAGEM do mandato (pedido do dono, Fase 7.3; revisada na Fase 8
// depois da rodada real do Teste v35).
//
// É aqui que "cada caso é um caso" vira operação: o analista escolhe as premissas
// que valem para ESTE mandato e diz ONDE cada uma entra na projeção.
//
// O QUE A RODADA REAL MUDOU NESTA TELA. Ela listava as 236 linhas do caso como se
// todas fossem conta projetável, e três coisas saíam erradas por isso:
//   • `Ativo Circulante 67.878` aparecia entre os 32 componentes dela, e um clique
//     em "aplicar a todas" projetava o total E as partes — dupla contagem, que não
//     parece erro no arquivo: parece um número maior;
//   • os 12 `Faturamento Janeiro…Dezembro` entravam como 12 contas, quando são o
//     insumo da curva de sazonalidade;
//   • `(-) Depreciação acumulada` aparecia POSITIVA e nada dizia a unidade, então
//     `TOTAL — saldo devedor 51.300.000` (reais) ficava ao lado de `Passivo
//     Circulante 92.539` (milhares) sem aviso.
// Agora cada linha traz PAPEL, sinal, unidade/moeda e documento de origem, e só
// `conta` recebe premissa. A regra mora no banco (0042) — aqui é a apresentação
// dela: se esta tela mentisse, o banco recusaria de todo jeito.
//
// Nada de regra de projeção vive aqui: tudo é `rpc` para as funções da 0038/0042.

interface PremissaCatalogo {
  codigo: string;
  nome: string;
  natureza: string;
  formula: string;
  unidade: string | null;
  aplica_em: string[];
  setores: string[];
  descricao: string | null;
}

interface CasoPremissa {
  premissa_codigo: string;
  valores: Record<string, number>;
  origem: string | null;
}

interface LinhaDoCaso {
  secao_canonica: string | null;
  chave: string;
  rotulo_norm: string;
  entidade: string | null;
  valor_ultimo: number;
  n_ocorrencias: number;
  papel: "conta" | "subtotal" | "derivado" | "serie_mensal";
  unidade: string | null;
  moeda: string | null;
  documentos: string[] | null;
  sobreposicao_suspeita: boolean;
}

interface LinhaVinculo {
  secao_canonica: string | null;
  rotulo_norm: string;
  entidade: string | null;
  premissa_codigo: string | null;
  sazonalidade_codigo: string | null;
}

const SETORES = [
  ["industria", "Indústria / metalurgia"], ["varejo", "Varejo"], ["servicos", "Serviços"],
  ["agro", "Agro"], ["construcao", "Construção / incorporação"], ["logistica", "Logística / transporte"],
  ["saude", "Saúde"], ["energia", "Energia"], ["tecnologia", "Tecnologia"],
  ["alimentos", "Alimentos e bebidas"], ["educacao", "Educação"], ["mineracao", "Mineração"],
  ["papel_celulose", "Papel e celulose"], ["quimica", "Química / petroquímica"],
  ["textil", "Têxtil / vestuário"], ["automotivo", "Automotivo / autopeças"],
  ["farma", "Farma / distribuição"], ["telecom", "Telecom"], ["hotelaria", "Hotelaria / turismo"],
  ["imobiliario", "Imobiliário (renda)"],
];

const NATUREZA_LABEL: Record<string, string> = {
  macro: "Macro", receita: "Receita", custo: "Custo", despesa: "Despesa",
  giro: "Capital de giro", investimento: "Investimento", divida: "Dívida",
  tributo: "Tributos", socios: "Sócios", sazonalidade: "Sazonalidade",
  operacional: "Driver operacional",
};

// O que cada papel significa PARA O ARQUIVO. O texto é o destino da linha, não uma
// etiqueta: quem lê precisa entender por que aquela linha não tem seletor, senão
// procura o defeito na tela.
const PAPEL_INFO: Record<string, { rotulo: string; explica: string; cor: string }> = {
  subtotal: {
    rotulo: "subtotal",
    explica: "sai no Excel como a SOMA dos componentes projetados — se move sozinho, e por isso "
      + "não recebe premissa (projetá-lo contaria o mesmo dinheiro duas vezes)",
    cor: "bg-info-100 text-info-800",
  },
  serie_mensal: {
    rotulo: "série mensal",
    explica: "alimenta a curva de sazonalidade, derivada do próprio histórico do caso — não é uma "
      + "conta a projetar",
    cor: "bg-serie-100 text-serie-800",
  },
  derivado: {
    rotulo: "derivado",
    explica: "indicador gerencial (resultado de outras contas, não dinheiro) — projetá-lo o faria "
      + "divergir das linhas que o compõem",
    cor: "bg-tinta-200 text-tinta-600",
  },
};

const MESES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

// CRONÔMETRO DE CHAMADA, em escopo de MÓDULO e não dentro do componente.
//
// Fica aqui por causa do `react-hooks/purity` do eslint, que reprova `Date.now()`
// no corpo de um componente — e reprova com razão no caso geral: leitura de relógio
// em render de componente cliente quebra a idempotência que o React assume. Esta é
// uma página `async` de servidor, que roda uma vez por requisição, e o relógio mede
// I/O que já aconteceu. Em escopo de módulo a regra não se aplica e a intenção fica
// explícita, em vez de silenciada com um `eslint-disable` que esconderia o motivo.
async function medir<T>(p: PromiseLike<T>): Promise<[T, number]> {
  const t0 = Date.now();
  const r = await p;
  return [r, Date.now() - t0];
}

export default async function ModelagemPage({
  params, searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ q?: string }>;
}) {
  const { id } = await params;
  const { q } = await searchParams;
  const busca = (q ?? "").trim();
  const supabase = await createClient();

  const casoRes = await supabase.from("caso").select("id, nome, produto, status").eq("id", id).single();
  if (casoRes.error || !casoRes.data) notFound();
  const caso = casoRes.data;

  // Colunas nomeadas, nunca `*`: o tipo logo abaixo já declara exatamente o que
  // esta tela lê, e `*` traz também `atualizado_por`/`atualizado_em`, que ninguém
  // aqui usa. É a mesma disciplina que o clipping passou a seguir depois do
  // egresso de agosto/2026 — a cota é da organização e os dois projetos a dividem.
  const paramRes = await supabase
    .from("caso_modelagem")
    .select("entidade, ultimo_exercicio_real, indice_macro, setor, anos_projetados")
    .eq("caso_id", id).maybeSingle();
  const parametros = paramRes.data as {
    entidade: string | null; ultimo_exercicio_real: number | null;
    indice_macro: string | null; setor: string | null; anos_projetados: number;
  } | null;

  // O catálogo vem FILTRADO pelo setor — é a sugestão da 0038. Sem setor
  // definido, vem só a base comum, que é a resposta correta para "ainda não sei
  // o setor" (e não uma lista de 90 premissas para escolher no escuro).
  // CADA CHAMADA VOLTA CRONOMETRADA, e o tempo aparece na caixa de erro.
  //
  // POR QUE ISSO É DIAGNÓSTICO E NÃO ENFEITE. Quando a resposta é `canceling
  // statement due to statement timeout`, o tempo decorrido É O TETO que o
  // servidor aplica — a consulta foi cortada nele. Sem o número, "estourou o
  // tempo" não diz QUAL tempo, e 8 s (o default do Supabase, contra o qual a
  // 0101 foi dimensionada) e 3 s (um projeto configurado mais apertado) produzem
  // exatamente a mesma mensagem. Foi essa ambiguidade que fez a rodada da 0101
  // custar idas e vindas: a tela relatava o sintoma sem a única grandeza capaz de
  // distinguir "a função está lenta" de "o teto é mais baixo do que supomos".
  //
  // O cronômetro fica FORA do `Promise.all` de propósito: as oito chamadas são
  // concorrentes, então o que interessa é o tempo de parede de cada uma sob a
  // concorrência real da página, não um tempo isolado que ninguém experimenta.
  const [
    [sugeridasRes, msSugeridas], [ativasRes, msAtivas], [vinculosRes, msVinculos],
    [confRes, msConf], [camposRes, msCampos], [sazRes, msSaz], [docsRes, msDocs],
    [portaoRes, msPortao],
  ] = await Promise.all([
    medir(supabase.rpc("fn_premissas_sugeridas", { p_setor: parametros?.setor ?? null })),
    medir(supabase.from("caso_premissa").select("premissa_codigo, valores, origem")
      .eq("caso_id", id).eq("ativo", true)),
    // PAGINADA: é um vínculo por LINHA do mandato, então cresce com o book —
    // e é ela que diz como cada conta projeta. Truncada, a tela mostraria
    // contas "sem premissa" que já têm uma, e o analista escolheria de novo.
    medir(paginar<{ secao_canonica: string | null; rotulo_norm: string; entidade: string | null;
                    premissa_codigo: string | null; sazonalidade_codigo: string | null }>(
      (de, ate) => supabase.from("caso_linha_premissa")
        .select("secao_canonica, rotulo_norm, entidade, premissa_codigo, sazonalidade_codigo")
        .eq("caso_id", id)
        .order("rotulo_norm", { ascending: true })
        .order("secao_canonica", { ascending: true, nullsFirst: true })
        .range(de, ate))),
    medir(supabase.rpc("fn_conferir_modelagem", { p_caso_id: id })),
    // As linhas do caso — por FUNÇÃO (0039/0042), não por consulta direta.
    //
    // `campo_extraido` não tem `caso_id`: o vínculo é `campo_extraido →
    // documento_versao → documento`. A primeira versão desta tela consultava a
    // tabela direto e, com a RLS aberta a qualquer autenticado, trazia as linhas
    // de TODOS os mandatos. O escopo por caso vive em UM lugar, coberto por teste.
    //
    // PAGINADA pelo mesmo motivo do export: é uma linha por (seção, rótulo)
    // do mandato inteiro, e é o conteúdo da seção 3 desta tela. A ordem
    // (seção, rótulo) é a que a própria função declara — e é total, porque é
    // exatamente por esse par que ela agrupa.
    medir(paginar<LinhaDoCaso>((de, ate) =>
      supabase.rpc("fn_linhas_para_modelagem", { p_caso_id: id })
        .order("secao_canonica", { ascending: true, nullsFirst: false })
        .order("rotulo_norm", { ascending: true })
        .range(de, ate))),
    // A curva de sazonalidade é DERIVADA do faturamento mensal do caso (0040):
    // ninguém digita 12 percentuais que o documento já afirma.
    medir(supabase.rpc("fn_sazonalidade_do_caso", { p_caso_id: id })),
    // Só para SUGERIR entidade e último exercício no passo 1 (ver abaixo).
    medir(paginar<{ tipo_taxonomia: string | null; entidade: { razao_social: string } | null; periodo: { referencia: string } | null }>(
      (de, ate) => supabase.from("documento")
        .select("tipo_taxonomia, entidade(razao_social), periodo(referencia)")
        .eq("caso_id", id).order("id", { ascending: true }).range(de, ate))),
    // O PORTÃO 2 — a mesma avaliação que `/casos/[id]/export` usa para recusar
    // o export de modelagem. Sem ela a tela dizia "pronto" e o clique devolvia
    // 409 (ver `PortaoDoExport` em lib/modelagem-cobertura.ts).
    medir(supabase.rpc("fn_avaliar_portao2", { p_caso_id: id })),
  ]);

  // ---------------------------------------------------------------------------
  // ERRO DE RPC NUNCA MAIS VIRA "LISTA VAZIA".
  //
  // Todas as chamadas acima (eram sete; a oitava, do Portão 2, entrou em 30/09/2026) terminavam em `?? []`, e o `.error` de nenhuma
  // era lido. O efeito apareceu em produção do jeito mais enganoso possível: a
  // seção 3 anunciou "Este caso ainda não tem linha extraída com valor" num caso
  // com 203 linhas, porque `fn_linhas_para_modelagem` tinha FALHADO e a falha foi
  // convertida em lista vazia. O analista lê isso como "o caso está vazio" e vai
  // procurar o problema na extração, que está intacta.
  //
  // Causa provável quando isso acontece logo depois de aplicar uma migration: o
  // PostgREST guarda um CACHE do schema, e função criada/derrubada só passa a
  // existir para ele depois de `notify pgrst, 'reload schema';`. Até lá a chamada
  // volta "function not found" — que é um erro, não um caso sem dado.
  //
  // A distinção que a tela precisa fazer, e agora faz: "não há linha" é uma
  // resposta; "não consegui perguntar" é outra.
  // ---------------------------------------------------------------------------
  const chamadas = ([
    ["premissas sugeridas (fn_premissas_sugeridas)", sugeridasRes.error, msSugeridas],
    ["premissas ativas (caso_premissa)", ativasRes.error, msAtivas],
    ["vínculos de linha (caso_linha_premissa)", vinculosRes.error, msVinculos],
    ["conferência (fn_conferir_modelagem)", confRes.error, msConf],
    ["linhas do caso (fn_linhas_para_modelagem)", camposRes.error, msCampos],
    ["curva de sazonalidade (fn_sazonalidade_do_caso)", sazRes.error, msSaz],
    ["documentos do caso", docsRes.error, msDocs],
    ["Portão 2 (fn_avaliar_portao2)", portaoRes.error, msPortao],
  ] as const);

  // O tempo entra na linha da falha. Num cancelamento por tempo ele é o TETO do
  // servidor, que é a grandeza que faltava para saber contra o que a tela está
  // lutando (ver o comentário do `medir`).
  const falhas = chamadas
    .filter(([, e]) => e)
    .map(([nome, e, ms]) => `${nome}: ${e!.message} [${ms} ms]`);

  // E os tempos de QUEM DEU CERTO também, porque é a linha de base que dá sentido
  // ao número da falha: se as cinco chamadas leves voltam em 80 ms e as duas
  // pesadas são cortadas em 8.000 ms, o servidor está saudável e as duas funções
  // é que não couberam. Se TUDO estiver lento, o problema é a instância, e nenhuma
  // otimização de SQL vai resolver.
  const tempos = chamadas
    .map(([nome, e, ms]) => `${nome.replace(/ \(.*\)$/, "")} ${ms} ms${e ? " (falhou)" : ""}`)
    .join(" · ");

  const sugeridas = (sugeridasRes.data as PremissaCatalogo[] | null) ?? [];
  const ativas = (ativasRes.data as CasoPremissa[] | null) ?? [];
  const vinculos = (vinculosRes.data as LinhaVinculo[] | null) ?? [];
  // `null` = NÃO CONFERIDO (RPC falhou ou não devolveu nada): nunca "aberto" — ver
  // `portaoNaoConferido` em lib/modelagem-cobertura.ts.
  // A MESMA regra da rota do export (`veredictoDoPortao`): erro, resposta ausente ou sem
  // `elegivel` booleano é NÃO CONFERIDO.
  const { portao } = veredictoDoPortao(portaoRes);
  const exportTravado = portaoFechado(portao);
  const portaoNaoConf = portaoNaoConferido(portao);
  const conf = confRes.data as {
    premissas_ativas: number; premissas_sem_valor: string[];
    // 0134: informação, não bloqueio — curva mensal ativa num caso sem documento
    // mensal de onde derivá-la.
    sazonalidade_sem_curva?: string[];
    linhas_do_caso: number; linhas_com_premissa: number; linhas_sem_premissa: number;
    linhas_nao_projetaveis: Record<string, number>;
    vinculos_orfaos: string[]; pronto: boolean;
    // 0158: fração de linhas projetáveis com premissa (0 a 1). Opcional: um
    // banco sem a 0158 aplicada devolve o objeto SEM esta chave (então
    // `conf.fracao_linhas_com_premissa` chega `undefined`), e a própria 0158
    // publica `null` quando `linhas_do_caso` é zero (zero coberto de zero
    // possível não é a mesma coisa que zero coberto de 480 — regra 1 do
    // CLAUDE.md). Nos dois casos a tela NÃO pode inventar 0% — mesma
    // convenção de `perguntasSugeridas` em `casos/[id]/page.tsx:277`.
    fracao_linhas_com_premissa?: number | null;
  } | null;
  const curva = (sazRes.data as { mes: number; fracao: number; n_observacoes: number }[] | null) ?? [];

  const ativasPorCodigo = new Map(ativas.map((a) => [a.premissa_codigo, a]));
  // Indexado pelo PAR (seção, rótulo) — ver `lib/modelagem-linha.ts`. Com a chave
  // só no rótulo, vincular `Empréstimos e Financiamentos` no passivo circulante
  // fazia a linha homônima do NÃO circulante aparecer preenchida sozinha, e o
  // valor herdado virava o `orig` daquela seção: no salvamento seguinte ele ia ao
  // banco como escolha do analista.
  const vinculoDaLinha = vinculoPorLinha(vinculos);
  const nomeDaPremissa = new Map(sugeridas.map((p) => [p.codigo, p.nome]));

  // SUGESTÃO de entidade e de último exercício, a partir do que o caso já tem.
  // No v35 os dois campos ficaram VAZIOS enquanto o banco sabia as duas coisas —
  // e campo vazio num parâmetro que dirige todo o modelo é convite a esquecer.
  // É sugestão, não imposição: entra como `defaultValue` e o analista sobrescreve.
  const docs = (docsRes.data as {
    entidade: { razao_social: string } | { razao_social: string }[] | null;
    periodo: { referencia: string } | { referencia: string }[] | null;
  }[] | null) ?? [];
  const um = <T,>(x: T | T[] | null): T | null => (Array.isArray(x) ? x[0] ?? null : x);
  const contagemEntidade = new Map<string, number>();
  let anoMaisRecente = 0;
  for (const d of docs) {
    const razao = um(d.entidade)?.razao_social;
    if (razao) contagemEntidade.set(razao, (contagemEntidade.get(razao) ?? 0) + 1);
    for (const m of (um(d.periodo)?.referencia ?? "").matchAll(/\d{4}/g)) {
      anoMaisRecente = Math.max(anoMaisRecente, Number(m[0]));
    }
  }
  const entidadeSugerida = [...contagemEntidade.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? "";
  const anoSugerido = anoMaisRecente || new Date().getFullYear() - 1;

  // Anos a projetar: do último exercício real + 1 em diante. É o horizonte que as
  // premissas precisam cobrir, e é derivado dos parâmetros — não digitado duas vezes.
  const ultimoReal = parametros?.ultimo_exercicio_real ?? anoSugerido;
  const nAnos = parametros?.anos_projetados ?? 5;
  const anos = Array.from({ length: nAnos }, (_, i) => ultimoReal + 1 + i);

  // AS OITO QUE O PRÓPRIO CASO RESPONDE. Derivadas das mesmas linhas que a seção
  // 3 lista, com os mesmos classificadores que o modelo usa para projetar — a
  // ponta que mede e a ponta que aplica precisam concordar sobre o que é cliente,
  // estoque e fornecedor, senão o dia sugerido não reproduz o saldo de onde saiu.
  // AS OITO SAEM DE `fn_linhas_do_realizado` (0150), NÃO DA LISTA DA TELA.
  //
  // A lista (`camposRes`) agrupa por rótulo, traz UM número por linha e não
  // filtra entidade — ela existe para o analista escolher premissa, e serve bem
  // para isso. Somar as razões a partir dela foi o que gravou, no Canastra,
  // `PMR = 348,6 dias` e `CUSTO_VARIAVEL = 287,7% da receita`: entrava a abertura
  // analítica por cima da conta que ela abre, o total da DRE junto das próprias
  // componentes, e as oito empresas do grupo num modelo que projeta uma.
  //
  // A função nova responde a outra pergunta — "quanto esta empresa, neste
  // exercício, teve de cada coisa" — e é ela que a média histórica precisa.
  const realizadoRes = await medir(supabase.rpc("fn_linhas_do_realizado", {
    p_caso_id: id,
    p_entidade: parametros?.entidade ?? null,
  }));
  const sugestoes = sugerirDoRealizado((realizadoRes[0].data ?? []) as Parameters<typeof sugerirDoRealizado>[0]);

  // Linhas do caso agrupadas por seção canônica — é a unidade do aplicar-em-lote.
  // A função já devolve UMA linha por (seção, rótulo normalizado): o agrupamento
  // por rótulo é dela, não daqui, para a tela e o lote concordarem sobre o que é
  // "uma linha".
  const todasLinhas = camposRes.data;
  const alvo = busca.toLowerCase();
  const linhasPorSecao = new Map<string, LinhaDoCaso[]>();
  for (const c of todasLinhas) {
    if (alvo && !c.chave.toLowerCase().includes(alvo)) continue;
    const secao = c.secao_canonica ?? "(sem seção canônica)";
    if (!linhasPorSecao.has(secao)) linhasPorSecao.set(secao, []);
    linhasPorSecao.get(secao)!.push(c);
  }

  const porNatureza = new Map<string, PremissaCatalogo[]>();
  for (const p of sugeridas) {
    if (!porNatureza.has(p.natureza)) porNatureza.set(p.natureza, []);
    porNatureza.get(p.natureza)!.push(p);
  }

  const premissasSazonais = ativas.filter((a) => a.premissa_codigo.includes("SAZON")
    || a.premissa_codigo === "CRONOGRAMA_FISICO" || a.premissa_codigo === "PARADA_MANUTENCAO");

  // OS TRÊS PASSOS, COM O QUE JÁ ESTÁ FEITO EM CADA UM. A tela tem três seções
  // longas empilhadas e nenhuma delas cabe na dobra: sem isto, saber "em que pé
  // estou" exigia rolar as três e somar de cabeça. O número ao lado do passo é o
  // estado dele, não decoração.
  const passos = [
    {
      id: "parametros",
      titulo: "Parâmetros",
      feito: !!parametros?.entidade && !!parametros?.ultimo_exercicio_real,
      nota: parametros?.entidade
        ? `${parametros.entidade} · ${anos[0]}–${anos[anos.length - 1]}`
        : "entidade e exercício ainda sugeridos",
    },
    {
      id: "premissas",
      titulo: "Premissas",
      feito: ativas.length > 0 && !conf?.premissas_sem_valor?.length,
      nota: ativas.length === 0
        ? "nenhuma ativa"
        : `${ativas.length} ativa(s)` +
          (conf?.premissas_sem_valor?.length ? ` · ${conf.premissas_sem_valor.length} sem valor` : ""),
    },
    {
      id: "linhas",
      titulo: "Linhas × premissas",
      feito: !!conf && conf.linhas_sem_premissa === 0 && conf.linhas_do_caso > 0,
      nota: conf
        ? `${conf.linhas_com_premissa} de ${conf.linhas_do_caso} contas com premissa`
        : `${todasLinhas.length} linhas`,
    },
  ];

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0">
          <Link href={`/casos/${id}`} className="text-sm text-tinta-500 hover:underline">
            ← {caso.nome}
          </Link>
          <div className="mt-0.5 flex flex-wrap items-center gap-2.5">
            <h1 className="text-xl font-semibold text-tinta-900">Modelagem</h1>
            {conf && (
              <span className={`chip ${conf.pronto ? "bg-ok-100 text-ok-800" : "bg-alerta-100 text-alerta-900"}`}>
                {/* 0158: "pronto" sozinho pintava o mesmo verde para 23 de 480
                    linhas cobertas e para 480 de 480 — a fração vem junto
                    sempre que o banco a mede, para os dois deixarem de parecer
                    o mesmo caso. Lógica em `lib/modelagem-cobertura.ts`, para
                    o invariante medir COMPORTAMENTO sem reimplementar JSX. */}
                {textoChipModelagem(conf, portao)}
              </span>
            )}
          </div>
          <p className="mt-0.5 text-sm text-tinta-500">
            Escolha as premissas deste mandato e diga onde cada uma entra na projeção.
          </p>
        </div>
        {/* OS DOIS EXPORTS, LADO A LADO (decisão do dono, 07/08/2026). Eram um só,
            e o "completo" trazia as 12 abas de dado cru junto com o modelo — 29
            abas para quem só queria o que vai a comitê. Agora são dois arquivos
            com dois propósitos, e o nome de cada botão diz qual é o seu:
            "modelagem" entrega as 14 abas do modelo; "dados financeiros" entrega
            a conferência da ingestão, linha a linha. O de dados vem primeiro por
            ser o que se usa ANTES de modelar. */}
        {/* AS DUAS AÇÕES, COM PESOS DIFERENTES. Eram dois botões de peso igual, e
            a tela não dizia qual é o produto DELA: o export de modelagem. O de
            dados continua aqui (é o que se usa para conferir antes de modelar),
            mas como ação secundária — a mesma hierarquia da tela do mandato. */}
        <div className="flex shrink-0 flex-wrap items-center gap-2">
          <a
            href={`/casos/${id}/export?modo=dados`}
            className="btn-secundario"
            title="As abas de dado, linha a linha, como saíram da extração. Serve para conferir contra os documentos — não projeta nada."
          >
            Exportar dados
          </a>
          {/* Com o Portão 2 fechado a rota recusa com 409 e o navegador mostraria
              um JSON cru: o botão leva à tela do mandato, onde as pendências
              bloqueantes se decidem, e diz por quê. */}
          {portaoNaoConf ? (
            <div className="flex flex-col items-end gap-1">
              <button type="button" className="btn-primario" disabled>
                Exportar modelagem — Portão 2 não conferido
              </button>
              <p role="status" className="max-w-xs text-right text-xs text-alerta-900">
                Não foi possível conferir o Portão 2 (a consulta falhou ou não devolveu veredito); o
                export de modelagem fica desabilitado até a conferência responder. Recarregue a
                página; se persistir, o motivo está na faixa de consultas com erro.
              </p>
            </div>
          ) : exportTravado ? (
            <Link
              href={`/casos/${id}`}
              className="btn-primario"
              title={`O export de modelagem está travado pelo Portão 2: ${(portao?.motivos ?? []).join("; ")}. Decida as pendências na tela do mandato.`}
            >
              Exportar modelagem — decidir pendências antes
            </Link>
          ) : (
            <a
              href={`/casos/${id}/export`}
              className="btn-primario"
              title="As 14 abas do modelo institucional, projetadas e editáveis dentro do Excel, mais a Modelagem e os índices macro. Sem as abas de dado cru."
            >
              Exportar modelagem
            </a>
          )}
        </div>
      </div>

      {/* A TRILHA DOS TRÊS PASSOS. Ela é navegação e estado ao mesmo tempo: leva
          direto à seção (a página é longa demais para rolagem cega) e diz o que
          falta em cada uma sem obrigar a abrir. */}
      <nav aria-label="Passos da modelagem" className="carta flex flex-wrap divide-x divide-tinta-100">
        {passos.map((p, i) => (
          <a
            key={p.id}
            href={`#${p.id}`}
            className="flex min-w-52 flex-1 items-start gap-3 px-4 py-3 transition-colors hover:bg-tinta-50"
          >
            <span
              aria-hidden
              className={`mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[11px] font-semibold ${
                p.feito ? "bg-ok-600 text-papel" : "bg-tinta-200 text-tinta-600"
              }`}
            >
              {p.feito ? "✓" : i + 1}
            </span>
            <span className="min-w-0">
              <span className="block text-sm font-medium text-tinta-900">{p.titulo}</span>
              <span className="block truncate text-xs text-tinta-500">{p.nota}</span>
            </span>
          </a>
        ))}
      </nav>

      {/* CONSULTA QUE FALHOU aparece ANTES de tudo, e nomeada. Enquanto isto não
          existia, uma RPC quebrada saía da tela como "este caso não tem linha". */}
      {falhas.length > 0 && (
        <section className="rounded-lg border border-risco-300 bg-risco-50 p-3 text-sm text-risco-900">
          <p className="font-semibold">
            {falhas.length} consulta(s) ao banco FALHARAM — o que está faltando nesta tela é efeito
            disso, não é o caso estar vazio.
          </p>
          <ul className="mt-1 list-disc pl-5 text-xs">
            {falhas.map((f) => <li key={f} className="font-mono">{f}</li>)}
          </ul>
          {/* A ORIENTAÇÃO SEGUE O ERRO, não o palpite mais comum.

              Esta caixa nasceu (PR #89) dando SEMPRE o conselho do cache de schema do
              PostgREST — que é o certo para "function not found" e o ERRADO para
              consulta cancelada. E foi com um `statement timeout` na tela que o
              conselho apareceu em produção: mandava recarregar o cache de schema
              quando a função existia, era encontrada, e só não tinha terminado em 8 s.
              Orientação errada num painel de diagnóstico é pior que orientação
              nenhuma: manda o analista consertar o que não está quebrado e confirma
              a impressão de que o PR não funcionou. */}
          {falhas.some((f) => /statement timeout|canceling statement/i.test(f)) ? (
            <p className="mt-2 text-xs">
              <strong>A consulta foi CANCELADA por tempo</strong> (o Supabase corta em 8 s), não é
              função faltando nem caso vazio — recarregar o cache de schema não resolve isto. Se as
              migrations <code className="font-mono">0101</code> e <code className="font-mono">0102</code>{" "}
              ainda não foram aplicadas neste banco, é isso: elas existirem no GitHub não as coloca
              no Supabase. Para confirmar sem adivinhar, rode no SQL Editor{" "}
              <code className="font-mono">select jsonb_pretty(fn_diagnostico_modelagem(&apos;{id}&apos;));</code>{" "}
              e olhe <code className="font-mono">correcoes_instaladas</code>. O diagnóstico completo
              de ambiente está em <code className="font-mono">Supabase/diagnostico_modelagem.sql</code>.
            </p>
          ) : (
            <p className="mt-2 text-xs">
              Se isto começou logo depois de aplicar uma migration, é quase certo que seja o cache de
              schema do PostgREST: rode <code className="font-mono">notify pgrst, &apos;reload schema&apos;;</code>{" "}
              no SQL Editor do Supabase e recarregue. Função recém-criada só existe para a API depois
              disso.
            </p>
          )}
          {/* A linha de base: o tempo das SETE chamadas, inclusive as que deram
              certo. É o que separa "duas funções não couberam" de "a instância
              inteira está lenta" — e a segunda não se resolve com SQL. */}
          <p className="mt-2 font-mono text-[10px] text-risco-800">{tempos}</p>
        </section>
      )}

      {/* 4. CONFERÊNCIA — no TOPO, não no fim. É o que o analista precisa saber
          antes de mexer em qualquer coisa: quantas linhas ficariam de fora e qual
          premissa está sem valor. Pôr isso no rodapé seria pôr o resultado depois
          da decisão. */}
      {conf && (
        <section
          className={`rounded-lg border p-3 text-sm ${
            conf.pronto ? "border-ok-300 bg-ok-50" : "border-alerta-300 bg-alerta-50"
          }`}
        >
          <p className={`font-medium ${conf.pronto ? "text-ok-900" : "text-alerta-900"}`}>
            {/* Mesma fração do chip, aqui por extenso — o par absoluto
                (`linhas_com_premissa` de `linhas_do_caso`) já vem no item
                logo abaixo, porque porcentagem sozinha esconde a ordem de
                grandeza: 2 de 3 e 400 de 600 são os mesmos 67%. */}
            {textoTituloConferenciaModelagem(conf, portao)}
          </p>
          <ul className="mt-1 space-y-0.5 text-tinta-600">
            <li>
              {conf.linhas_com_premissa} de {conf.linhas_do_caso} <strong>contas projetáveis</strong>{" "}
              com premissa — <strong>{conf.linhas_sem_premissa} sem premissa</strong>, que não serão
              projetadas (o arquivo mostra cada uma como não projetada, nunca projetada por padrão).
            </li>
            {/* O que NÃO é projetável fica nomeado, em vez de desaparecer da conta:
                no v35 a tela dizia "0 de 236" e o alvo real era bem menor. */}
            {conf.linhas_nao_projetaveis && Object.keys(conf.linhas_nao_projetaveis).length > 0 && (
              <li className="text-tinta-600">
                Fora da conta por natureza da linha:{" "}
                {Object.entries(conf.linhas_nao_projetaveis)
                  .map(([p, n]) => `${n} ${PAPEL_INFO[p]?.rotulo ?? p}`)
                  .join(", ")}{" "}
                — subtotal sai como soma dos componentes, série mensal alimenta a sazonalidade e
                indicador derivado não se projeta.
              </li>
            )}
            <li>{conf.premissas_ativas} premissa(s) ativa(s) neste caso.</li>
            {conf.premissas_sem_valor?.length > 0 && (
              <li className="text-alerta-900">
                <strong>Sem valor preenchido:</strong> {conf.premissas_sem_valor.join(", ")} — premissa
                ativa sem valor projetaria com zero, então ela impede o &quot;pronto&quot;. Premissa
                macro puxa o Focus sozinha ao ser ativada sem valor; se ficou vazia, é porque o Focus
                não publica expectativa para esses anos.
              </li>
            )}
            {(conf.sazonalidade_sem_curva?.length ?? 0) > 0 && (
              <li className="text-tinta-600">
                <strong>Sazonalidade sem curva para derivar:</strong>{" "}
                {conf.sazonalidade_sem_curva!.join(", ")} — a curva mensal NÃO é digitada: ela sai do
                documento mensal do caso (rótulos &quot;jan/2024&quot;), e este caso ainda não tem um.
                As linhas vinculadas ficam com o valor anual rateado liso pelos doze meses.{" "}
                <strong>Não impede o &quot;pronto&quot;</strong>: o número ANUAL continua certo, só a
                distribuição dentro do ano fica sem forma.
              </li>
            )}
            {conf.vinculos_orfaos?.length > 0 && (
              <li className="text-alerta-900">
                <strong>Configuração apontando para linha que não existe:</strong>{" "}
                {conf.vinculos_orfaos.join(", ")} — o documento não chegou, ou foi reextraído com
                outro rótulo.
              </li>
            )}
          </ul>
        </section>
      )}

      {/* 1. PARÂMETROS — as três células que saíram do topo da aba Modelagem. */}
      <section id="parametros" className="carta scroll-mt-20 p-4">
        <h2 className="titulo-secao">1 · Parâmetros do mandato</h2>
        {/* O TEXTO DE APOIO ENCOLHEU, e o que saiu dele não se perdeu: virou
            comentário. A tela tinha quatro parágrafos de explicação antes do
            primeiro campo, e explicação que ninguém lê é ruído que empurra o
            trabalho para baixo da dobra. O que ficou é o que muda o que a pessoa
            faz agora: que os valores são SUGESTÕES a conferir.
            O resto continua valendo e mora aqui: o Excel sai parametrizado com o
            que for escolhido, o setor só SUGERE as premissas do passo 2, e o
            horizonte de projeção é derivado do último exercício realizado. */}
        <p className="mb-3 mt-1 text-xs text-tinta-500">
          Entidade e último exercício vêm <strong>sugeridos</strong> pelos documentos deste caso —
          confira antes de salvar. O Excel sai parametrizado com o que estiver aqui.
        </p>
        <FormParametros casoId={id}>
          <label className="text-sm">
            <span className="text-tinta-600">Entidade modelada</span>
            <input
              type="text" name="entidade" defaultValue={parametros?.entidade ?? entidadeSugerida}
              placeholder="razão social como aparece nas abas de dados"
              className="mt-1 w-full rounded border border-tinta-200 px-2 py-1"
            />
          </label>
          <label className="text-sm">
            <span className="text-tinta-600">Último exercício realizado</span>
            <input
              type="number" name="ultimo_exercicio_real"
              defaultValue={parametros?.ultimo_exercicio_real ?? anoSugerido}
              className="mt-1 w-full rounded border border-tinta-200 px-2 py-1"
            />
          </label>
          <label className="text-sm">
            <span className="text-tinta-600">Índice macro que dirige a projeção</span>
            <select
              name="indice_macro" defaultValue={parametros?.indice_macro ?? "IPCA"}
              className="mt-1 w-full rounded border border-tinta-200 px-2 py-1"
            >
              {["IPCA", "IGPM", "INCC", "SELIC", "CAMBIO_USD", "PIB"].map((s) => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
          </label>
          <label className="text-sm">
            <span className="text-tinta-600">Setor do mandato</span>
            <select
              name="setor" defaultValue={parametros?.setor ?? ""}
              className="mt-1 w-full rounded border border-tinta-200 px-2 py-1"
            >
              <option value="">(ainda não definido — sugere só a base comum)</option>
              {SETORES.map(([v, label]) => <option key={v} value={v}>{label}</option>)}
            </select>
          </label>
          <label className="text-sm">
            <span className="text-tinta-600">Anos projetados</span>
            <input
              type="number" name="anos_projetados" min={1} max={10}
              defaultValue={parametros?.anos_projetados ?? 5}
              className="mt-1 w-full rounded border border-tinta-200 px-2 py-1"
            />
            {/* O horizonte que estes dois campos PRODUZEM, escrito por extenso.
                "5 anos" a partir de "2025" é uma conta que o analista fazia de
                cabeça enquanto preenchia premissa — e errar o ano de corte move
                a projeção inteira sem gerar um único aviso. */}
            <span className="mt-1 block text-xs tabular-nums text-tinta-500">
              {anos.join(" · ")}
            </span>
          </label>
        </FormParametros>
      </section>

      {/* 2. PREMISSAS DO CASO */}
      <section id="premissas" className="carta scroll-mt-20 p-4">
        <h2 className="titulo-secao">
          2 · Premissas deste caso
          {parametros?.setor && (
            <span className="ml-2 font-normal text-tinta-500">
              — sugeridas para {SETORES.find(([v]) => v === parametros.setor)?.[1] ?? humanizar(parametros.setor)}
            </span>
          )}
        </h2>
        {/* Duas regras ficam na tela porque mudam o que se digita; o resto virou
            comentário. As que ficaram: ano vazio NÃO vira zero (projetar com zero
            é o erro que não se denuncia), e premissa macro sem valor puxa o Focus
            sozinha. O que saiu: que o setor sugere sem restringir — isso o próprio
            cabeçalho da seção já diz, com o nome do setor ao lado. */}
        <p className="mb-3 mt-1 text-xs text-tinta-500">
          Ano em branco fica <strong>em branco</strong>, não vira zero. Premissa{" "}
          <strong>macro</strong> ativada sem valor puxa a expectativa do Focus que está no banco.
        </p>

        {/* A CURVA DE SAZONALIDADE não é digitada: ela é derivada do faturamento
            mensal que o próprio mandato entregou (0040). Mostrá-la aqui é o que
            permite ao analista discordar dela — e, quando ela não existe, saber
            por quê antes de abrir o arquivo. */}
        <div className="mb-4 rounded border border-tinta-200 bg-tinta-50 p-2 text-xs">
          <p className="font-medium text-tinta-600">Curva de sazonalidade deste caso</p>
          {curva.length === 12 ? (
            <>
              <div className="mt-1 flex flex-wrap gap-1">
                {curva.map((c) => (
                  <span key={c.mes} className="rounded bg-folha px-1.5 py-0.5 tabular-nums text-tinta-600">
                    {MESES[c.mes - 1]} {(c.fracao * 100).toFixed(1)}%
                  </span>
                ))}
              </div>
              <p className="mt-1 text-tinta-500">
                Derivada do faturamento mensal do próprio caso — nada digitado. É ela que reparte o
                valor anual das linhas com sazonalidade vinculada.
              </p>
            </>
          ) : (
            <p className="mt-1 text-tinta-600">
              Sem curva: o caso não tem série mensal completa de faturamento (12 meses). As linhas
              ficam <strong>sem distribuição mensal</strong> e o arquivo diz isso — ratear 1/12 seria
              inventar um número que ninguém escolheu, e move caixa de dezembro para março.
            </p>
          )}
        </div>

        {/* CABEÇALHO DE ANOS — o horizonte fica ESCRITO, não insinuado.
            Antes o ano só aparecia como `placeholder` dentro da caixa: texto
            cinza que some no instante em que se digita o primeiro caractere.
            Quem preenchia a terceira caixa de uma premissa não tinha mais como
            saber se estava em 2028 ou 2029 — e premissa no ano errado não dá
            erro nenhum, só projeta diferente. O ano agora é rótulo fixo em cima
            da coluna, alinhado com as caixas, e continua no `placeholder` e no
            `title` para quem navega por teclado. */}
        <div className="flex flex-wrap items-center gap-2 px-2 pb-1 text-xs text-tinta-500">
          <span className="min-w-56 flex-1">
            Horizonte de projeção — <strong className="text-tinta-600">{anos.length} anos</strong>,
            de {anos[0]} a {anos[anos.length - 1]}, derivados do último exercício realizado
            ({ultimoReal}). Mudar em <em>1. Parâmetros do mandato</em>.
          </span>
          {anos.map((ano) => (
            <span key={ano} className="w-16 text-center font-semibold tabular-nums text-tinta-600">
              {ano}
            </span>
          ))}
          {/* Espelha a largura do botão da linha para os anos ficarem sobre as caixas. */}
          <span aria-hidden className="invisible px-2 py-0.5 text-xs">Atualizar</span>
        </div>

        <SugestoesDoRealizado
          casoId={id}
          anos={anos}
          sugestoes={sugestoes}
          ativas={new Set(ativasPorCodigo.keys())}
        />

        <div className="space-y-4">
          {[...porNatureza.entries()].map(([natureza, lista]) => (
            <div key={natureza}>
              <h3 className="mb-1 text-xs font-semibold uppercase text-tinta-500">
                {NATUREZA_LABEL[natureza] ?? humanizar(natureza)}
              </h3>
              <div className="space-y-1">
                {lista.map((p) => {
                  const ativa = ativasPorCodigo.get(p.codigo);
                  return (
                    <FormPremissa key={p.codigo} casoId={id} codigo={p.codigo} ativa={!!ativa}>
                      <span className="min-w-56 flex-1" title={p.descricao ?? undefined}>
                        {p.nome}
                        {p.unidade && <span className="ml-1 text-tinta-500">({p.unidade})</span>}
                        {p.setores.length > 0 && (
                          <span className="ml-1 rounded bg-serie-100 px-1 text-[10px] text-serie-800">
                            setor
                          </span>
                        )}
                        {ativa?.origem === "focus" && (
                          <span className="ml-1 rounded bg-ok-100 px-1 text-[10px] text-ok-800">
                            Focus
                          </span>
                        )}
                      </span>
                      {/* O ANO FICA ESCRITO EM CIMA DA CAIXA, em preto.
                          Ele era o `placeholder` — cinza claro, e some no primeiro
                          caractere digitado. O dono leu isso como "tenho que
                          selecionar o ano em cada premissa", que é justamente o
                          trabalho que a tela existe para não dar: o horizonte já
                          vem dos parâmetros do mandato e é o mesmo para todas.
                          Agora o ano é rótulo fixo, e o `placeholder` passa a
                          dizer a UNIDADE, que é o que a caixa realmente pede. */}
                      {anos.map((ano) => (
                        <label key={ano} className="flex w-16 flex-col items-center">
                          <span className="text-[10px] font-semibold leading-none text-tinta-600 tabular-nums">
                            {ano}
                          </span>
                          <input
                            type="text" name={`valor_${ano}`}
                            defaultValue={ativa?.valores?.[String(ano)] ?? ""}
                            placeholder={p.unidade ?? "valor"}
                            title={`${p.nome} — ${ano}${p.unidade ? ` (${p.unidade})` : ""}`}
                            className="mt-0.5 w-16 rounded border border-tinta-200 px-1 py-0.5 text-right text-xs"
                          />
                        </label>
                      ))}
                    </FormPremissa>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* 3. LINHAS × PREMISSAS */}
      <section id="linhas" className="carta scroll-mt-20 p-4">
        <h2 className="titulo-secao">
          3 · Linhas × premissas
          <span className="ml-2 font-normal normal-case tracking-normal text-tinta-500">
            — {todasLinhas.length} linha(s) no caso
          </span>
        </h2>
        <p className="mb-3 mt-1 text-xs text-tinta-500">
          Comece pelo <strong>aplicar em lote</strong> de cada seção e ajuste as exceções depois.
          Linha sem premissa não é projetada — escolha legítima, que o arquivo declara.
        </p>

        {/* Busca por rótulo: com 236 linhas, achar "Fornecedores nacionais" rolando
            a página é o que faz o analista desistir de ajustar a exceção. */}
        <form method="get" className="mb-3 flex items-center gap-2 text-sm">
          <input
            type="text" name="q" defaultValue={busca} placeholder="filtrar por rótulo…"
            className="w-64 rounded border border-tinta-200 px-2 py-1 text-xs"
          />
          <button type="submit" className="rounded border border-tinta-200 px-2 py-1 text-xs hover:bg-tinta-100">
            filtrar
          </button>
          {busca && (
            <Link href={`/casos/${id}/modelagem`} className="text-xs text-tinta-500 hover:underline">
              limpar filtro ({todasLinhas.length} linhas no total)
            </Link>
          )}
        </form>

        {ativas.length === 0 ? (
          <p className="rounded border border-alerta-300 bg-alerta-50 p-2 text-sm text-alerta-900">
            Ative pelo menos uma premissa no passo 2 antes de vincular linhas. Vincular linha a
            premissa não ativada é recusado no banco, de propósito: a linha sairia
            &quot;projetada&quot; por uma premissa vazia.
          </p>
        ) : (
          <div className="space-y-5">
            {/* Ordena pelo NOME DA SEÇÃO. `sort()` sem comparador converte cada entrada
                em texto — e a entrada é `[secao, linhas]`, então o critério incluía as
                linhas estringadas ("[object Object],[object Object]…"). A ordem saía
                certa por acidente do prefixo, não por decisão. */}
            {[...linhasPorSecao.entries()]
              .sort(([a], [b]) => a.localeCompare(b))
              .map(([secao, linhas]) => (
              <SecaoLinhas
                key={secao}
                casoId={id}
                secao={secao}
                // A CHAVE canônica continua sendo `secao` (é ela que o formulário manda
                // ao banco); o que a tela mostra é o rótulo em português. Misturar os
                // dois foi o defeito: `passivo_nao_circulante` num cabeçalho de seção.
                rotulo={rotuloDaSecao(secao === "(sem seção canônica)" ? null : secao)}
                linhas={linhas}
                ativas={ativas.map((a) => ({
                  codigo: a.premissa_codigo,
                  nome: nomeDaPremissa.get(a.premissa_codigo) ?? a.premissa_codigo,
                }))}
                sazonais={premissasSazonais.map((a) => ({
                  codigo: a.premissa_codigo,
                  nome: nomeDaPremissa.get(a.premissa_codigo) ?? a.premissa_codigo,
                }))}
                vinculos={Object.fromEntries(linhas.map((l) => [l.rotulo_norm, {
                  premissa: vinculoDaLinha.get(chaveDaLinha(l.secao_canonica, l.rotulo_norm))
                    ?.premissa_codigo ?? "",
                  sazonalidade: vinculoDaLinha.get(chaveDaLinha(l.secao_canonica, l.rotulo_norm))
                    ?.sazonalidade_codigo ?? "",
                }]))}
              />
            ))}
            {linhasPorSecao.size === 0 && (
              <p className="text-sm text-tinta-500">
                {busca
                  ? `Nenhuma linha com "${busca}" no rótulo.`
                  : falhas.length > 0
                    // A afirmação só pode ser feita quando a pergunta foi
                    // respondida. Com a consulta falhando, dizer "não tem linha"
                    // é inventar um fato sobre o caso.
                    ? "A consulta das linhas FALHOU (veja o aviso vermelho no topo). Isto NÃO quer dizer que o caso está vazio."
                    : "Este caso ainda não tem linha extraída com valor. Confira a fila de revisão e o export de dados."}
              </p>
            )}
          </div>
        )}
      </section>
    </div>
  );
}
