import ExcelJS from "exceljs";
import JSZip from "jszip";
import type { CampoExtraido } from "./types";
import {
  ANALISE_HEADER_FILL, CHAVE_SEP, DIVERGENCIA_FILL, HEADER_FILL, PCT_FMT,
  RATIO_FMT, THIN_TOP_BORDER, VALOR_NUM_FMT, comoNota, compararCodigo,
} from "./export-estilo";
import {
  classificarConta,
  classificarDemonstracao,
  familiaDeclarada,
  ehSecaoDeNotaExplicativa,
  secoesDe,
  ancorasDe,
  agruparPorChaveNormalizada,
  normalizar,
  ehNomeDeAgrupamento,
  ESTRUTURA_POR_TIPO,
  BALANCO_OUTLINE,
  type EstruturaDemonstracao,
  type FamiliaDemonstracao,
} from "./statement-templates";
import {
  ABA_MACRO, ABA_MACRO_DADOS, ABA_MODELAGEM, ANOS_PROJETADOS,
  construirAbaMacro, construirAbaMacroSemDado,
  type ConfigModelagem,
  construirAbaModelagem,
  type MacroParaExport,
} from "./export-modelagem";
import { injetarGraficosNoBuffer, type EspecGrafico } from "./xlsx-graficos";
import {
  ABAS_MODELO, construirModeloInstitucional, naturezaDaSubsecao, type EntradaModeloInstitucional,
  type NaturezaDeCiclo,
} from "./modelo-institucional";
// Reexportados para o `route.ts` seguir importando tudo de "@/lib/export": o
// corte da sessão 20 é interno ao lib, e não é motivo para mexer no chamador.
export type { MacroAnual, MacroExpectativa, MacroParaExport, RefsMacro } from "./export-modelagem";

// Modo B do output (Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md): export sob demanda. Princípio
// inegociável da spec: "Dado sem aceite não é entregue como fato — no
// máximo aparece como sugestão pendente de revisão, visualmente distinta."
// Por isso TODAS as linhas aparecem (aceitas e pendentes), mas com
// status/estilo bem distintos — nada aqui vira fato silenciosamente.
//
// Balanço/Balancete/DRE/Fluxo de Caixa/Combinado saem CLASSIFICADOS por
// SEÇÃO (statement-templates.ts) — não por um template de ~15 nomes de
// conta fixos. Cada empresa nomeia as contas do jeito dela; o que é
// universal é a SEÇÃO (Ativo Circulante, Despesas Operacionais, Atividades
// de Investimento, etc.). Cada conta aparece com o rótulo ORIGINAL da
// empresa, dentro da seção certa — nada é forçado a um nome canônico, e
// nada some: o que não é classificável com segurança cai num bloco
// explícito "Contas Não Classificadas". Faturamento/Dívida/Fluxo Projetado
// continuam em listagem simples (já são, por natureza, uma série/tabela).
// O export NÃO modela nem projeta (fora do escopo, mesma spec) — nenhum
// subtotal/total é calculado por soma; só aparece se o próprio documento
// já trouxer aquela linha extraída.
//
// Função pura (sem Supabase/Next.js) para ser testável isoladamente — a rota
// (`app/casos/[id]/export/route.ts`) só busca os dados e chama esta função.

// Padroniza o período (periodo.tipo + periodo.referencia — convenções livres
// vindas da extração: "12M25", "1T25", "L24M", "23,24,25", datas ISO/BR,
// texto livre) num modelo pronto de "períodos e intervalos", sem jargão
// técnico ("multi", "data-base") nem convenções cifradas na tela. Pedido do
// dono (sessão 7 cont.¹⁵): "simplificar e deixar mais objetiva a escrita de
// período". Nunca lança — o que não reconhece, devolve como veio (nunca pior
// que o comportamento anterior).
function anoDe4Digitos(anoTexto: string): string {
  if (anoTexto.length === 4) return anoTexto;
  const n = Number(anoTexto);
  return String(n <= 79 ? 2000 + n : 1900 + n);
}

function formatarDataBR(ref: string): string {
  const iso = ref.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  return iso ? `${iso[3]}/${iso[2]}/${iso[1]}` : ref;
}

const MESES_ABREV = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"];
const MES_POR_NOME: Record<string, number> = {
  jan: 1, fev: 2, mar: 3, abr: 4, mai: 5, jun: 6, jul: 7, ago: 8, set: 9, out: 10, nov: 11, dez: 12,
  janeiro: 1, fevereiro: 2, marco: 3, abril: 4, maio: 5, junho: 6, julho: 7, agosto: 8,
  setembro: 9, outubro: 10, novembro: 11, dezembro: 12,
};
function mesAno(mes: number, anoTexto: string): string {
  return `${MESES_ABREV[mes - 1]}/${anoDe4Digitos(anoTexto)}`;
}

// Padroniza o período num modelo pronto e objetivo, tolerante às MUITAS notações
// que a extração produz entre contratos diferentes (cada demonstração escreve o
// período de um jeito). Robusto contra os mis-parses reais achados na auditoria:
// "02,25" NÃO é o intervalo "2002–2025" e sim Fev/2025 (mês,ano); semestre,
// mês abreviado, MM/AAAA e ISO (mesmo sem tipo=data-base) são reconhecidos. O
// que não reconhece volta como veio (nunca pior que antes).
export function formatarPeriodo(tipo: string | null, referencia: string | null): string {
  const ref = (referencia ?? "").trim();
  const t = (tipo ?? "").trim();
  if (!ref) return "—";
  const low = ref.toLowerCase();

  const ultimosMeses = ref.match(/^L(\d+)M$/i);
  if (ultimosMeses) return `Últimos ${ultimosMeses[1]} meses`;

  const anoFiscal = ref.match(/^(\d{1,2})M(\d{2,4})$/i);
  if (anoFiscal) {
    const nMeses = Number(anoFiscal[1]);
    const ano = anoDe4Digitos(anoFiscal[2]);
    return nMeses === 12 ? ano : `${nMeses} meses/${ano}`;
  }

  const trimestre = ref.match(/^(\d)T(\d{2,4})$/i);
  if (trimestre) return `${trimestre[1]}º Tri/${anoDe4Digitos(trimestre[2])}`;
  const semestre = ref.match(/^(\d)S(\d{2,4})$/i);
  if (semestre) return `${semestre[1]}º Sem/${anoDe4Digitos(semestre[2])}`;

  // Datas: ISO (independente do tipo) e BR já legível
  const iso = ref.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (iso) return `${iso[3]}/${iso[2]}/${iso[1]}`;
  if (/^\d{2}\/\d{2}\/\d{2,4}$/.test(ref)) return ref;

  // Mês por nome/abreviação + ano: "jan/25", "dez-24", "fevereiro/2025"
  const mesNome = /^([a-zç]{3,9})[/\-. ](\d{2,4})$/.exec(low);
  if (mesNome && MES_POR_NOME[mesNome[1]] != null) return mesAno(MES_POR_NOME[mesNome[1]], mesNome[2]);

  // MM/AAAA ou MM-AAAA (mês numérico + ano de 4 dígitos): "02/2025", "12/2025"
  const mmAno = /^(\d{1,2})[/-](\d{4})$/.exec(ref);
  if (mmAno && Number(mmAno[1]) >= 1 && Number(mmAno[1]) <= 12) return mesAno(Number(mmAno[1]), mmAno[2]);

  if (t === "data-base") return formatarDataBR(ref);

  if (t === "multi" || /,/.test(ref)) {
    const toks = ref.split(",").map((p) => p.trim()).filter(Boolean);
    // "MM,AAAA"/"MM,AA" = MÊS,ANO — não um intervalo de exercícios (o mis-parse
    // "2002–2025"/"2012–2024" da auditoria). Dois sinais desambiguam:
    //   (a) mês com zero à esquerda ("02,25" → Fev/2025);
    //   (b) mês 1–12 seguido de ano de 4 dígitos ("12,2024" → Dez/2024) — uma
    //       lista de exercícios seria escrita com a MESMA largura nos dois
    //       tokens ("2012,2024" ou "12,24"), não misturada.
    // Sobra ambíguo só "NN,NN" sem zero à esquerda ("11,12"), que continua
    // tratado como exercícios (2011–2012) — a convenção do sistema para lista
    // de anos é justamente 2 dígitos (ver notação canônica em N8N/lib/extract).
    if (toks.length === 2) {
      const mes = Number(toks[0]);
      const mesComZero = /^0[1-9]$/.test(toks[0]);
      const anoCheio = /^\d{4}$/.test(toks[1]);
      if ((mesComZero && /^\d{2,4}$/.test(toks[1])) || (anoCheio && mes >= 1 && mes <= 12)) {
        return mesAno(mes, toks[1]);
      }
    }
    // Caso geral: lista de exercícios (anos).
    if (toks.every((p) => /^\d{1,4}$/.test(p))) {
      const anos = toks.map((p) => anoDe4Digitos(p));
      if (anos.length === 1) return anos[0];
      if (anos.length === 2) return `${anos[0]}–${anos[1]}`;
      return anos.join(", ");
    }
    return toks.join(", ");
  }

  if (/^\d{4}$/.test(ref)) return ref;
  if (/^\d{2}$/.test(ref)) return anoDe4Digitos(ref);

  return ref; // texto livre já descritivo (ex.: "Jan/2024 a Dez/2025") — mantém como veio
}

// Colunas de uma demonstração COMBINADA que NÃO são entidades: a de
// "Eliminações"/"Ajustes" (lançamentos que anulam saldos recíprocos) e a de
// "Combinado"/"Consolidado"/"Total" (o resultado da soma). A extração as trata
// como mais uma coluna de empresa — correto do ponto de vista do documento, mas
// no export elas não podem ser lidas como entidade: a de total DUPLICA o que as
// demais já dizem, e AV%/Δ% sobre uma coluna de ajuste é ruído. Achado no teste
// v24: a aba Combinado saiu com "Eliminações" e "Combinado" como se fossem duas
// empresas do grupo. Aqui elas continuam no export (nada se perde), mas ficam
// no FIM, rotuladas pelo que são, e sem análise vertical/horizontal.
const RE_COLUNA_AJUSTE = /^(elimina|ajuste|eliminacao)/;
const RE_COLUNA_TOTAL = /^(combinad|consolidad|total|soma)/;
export function tipoColunaNaoEntidade(entidade: string): "ajuste" | "total" | null {
  const t = normalizar(entidade);
  if (RE_COLUNA_AJUSTE.test(t)) return "ajuste";
  if (RE_COLUNA_TOTAL.test(t)) return "total";
  return null;
}

// Chave CRONOLÓGICA de um período já formatado (saída de `formatarPeriodo`).
// As colunas do export eram ordenadas por `localeCompare` do rótulo, o que é
// alfabético: "Nov/2024" vinha antes de "Out/2024" e "Dez/2024" antes de
// "Jan/2024" — além de bagunçar a leitura, isso fazia a coluna Δ% (que compara
// períodos ADJACENTES da mesma entidade) casar o par errado, reportando uma
// variação entre meses que não se sucedem. Deriva (ano, mês, dia) do rótulo;
// períodos que agregam vários exercícios entram no nível do ANO (mês 0, antes
// dos meses daquele ano) e rótulos sem âncora temporal ("Últimos 24 meses",
// texto livre) vão para o fim — nunca no meio da série.
const MES_NUM: Record<string, number> = {
  jan: 1, fev: 2, mar: 3, abr: 4, mai: 5, jun: 6, jul: 7, ago: 8, set: 9, out: 10, nov: 11, dez: 12,
};
export const CRONO_SEM_ANCORA = Number.MAX_SAFE_INTEGER;

export function chaveCronologicaPeriodo(periodoFormatado: string): number {
  const p = (periodoFormatado ?? "").trim();
  if (!p || p === "—") return CRONO_SEM_ANCORA;
  const chave = (ano: number, mes = 0, dia = 0) => ano * 10000 + mes * 100 + dia;

  const data = p.match(/^(\d{2})\/(\d{2})\/(\d{4})$/); // 15/01/2025
  if (data) return chave(Number(data[3]), Number(data[2]), Number(data[1]));

  const mesAbrev = p.match(/^([A-Za-zç]{3})\/(\d{4})$/); // Fev/2025
  if (mesAbrev) {
    const m = MES_NUM[mesAbrev[1].toLowerCase()];
    if (m) return chave(Number(mesAbrev[2]), m);
  }

  const tri = p.match(/^([1-4])º Tri\/(\d{4})$/); // 1º Tri/2025 → início do trimestre
  if (tri) return chave(Number(tri[2]), (Number(tri[1]) - 1) * 3 + 1);

  const sem = p.match(/^([12])º Sem\/(\d{4})$/); // 2º Sem/2024 → início do semestre
  if (sem) return chave(Number(sem[2]), Number(sem[1]) === 1 ? 1 : 7);

  const nMeses = p.match(/^(\d{1,2}) meses\/(\d{4})$/); // 9 meses/2024 (YTD)
  if (nMeses) return chave(Number(nMeses[2]), Number(nMeses[1]));

  if (/^\d{4}$/.test(p)) return chave(Number(p)); // exercício completo

  // Agregados de vários exercícios ("2024–2025", "2023, 2024, 2025"): entram no
  // nível do ano pelo PRIMEIRO exercício da série (ordenação determinística).
  const anos = p.match(/\b(19|20)\d{2}\b/g);
  if (anos && anos.length > 0) return chave(Number(anos[0]));

  return CRONO_SEM_ANCORA; // "Últimos 24 meses", texto livre — sempre por último
}

// ---------------------------------------------------------------------------
// CONSOLIDAÇÃO DE COLUNA (achado do teste v27, medido no export do dono)
//
// O grupo Vertentes tem 5 empresas e o Balanço saiu com 15 colunas de entidade:
// cada empresa aparecia DUAS vezes, porque chega por dois caminhos com grafias
// diferentes —
//   • pelo documento COMBINADO, via `entidade_coluna`: "Componentes", "Metalúrgica";
//   • pelo balanço INDIVIDUAL, via razão social: "VERTENTES COMPONENTES AUTOMOTIVOS LTDA.".
// O mesmo vale para o período: o combinado declara "2025" e o individual
// "31/12/2025" — o mesmo exercício escrito de dois jeitos.
//
// Isso não é cosmético. Uma aba de modelagem que some as colunas do grupo conta
// cada empresa DUAS VEZES e fecha errado em silêncio. Consolidar é pré-requisito
// de qualquer análise em cima, e é o mesmo princípio que a `0022` já aplica no
// Postgres para período (comparar por CONJUNTO DE ANOS, não pelo rótulo).
//
// Critério deliberadamente CONSERVADOR — um falso casamento aqui FUNDE duas
// empresas diferentes, que é bem pior que deixar duas colunas: o apelido só é
// promovido à razão social quando TODAS as suas palavras significativas casam
// (por prefixo, para "Part." achar "Participações") com UMA ÚNICA razão social
// conhecida do caso. Zero candidatos ou dois, fica como está.
// ---------------------------------------------------------------------------
// Só FORMA JURÍDICA e conectivo entram aqui. Palavras de ramo ("Participações",
// "Comércio", "Serviços", "Logística") NÃO são ruído: são exatamente o que
// distingue duas empresas do mesmo grupo, que costumam repetir o sobrenome
// ("Vertentes Participações" × "Vertentes Componentes"). Tratá-las como vazias
// fazia "Vertentes Part." perder o casamento com "VERTENTES PARTICIPAÇÕES S.A."
// e, pior, deixaria "Alfa Comércio" e "Alfa Serviços" indistinguíveis.
const PALAVRAS_VAZIAS_ENTIDADE = new Set([
  "ltda", "sa", "s", "a", "me", "epp", "eireli", "cia", "companhia",
  "do", "da", "de", "e", "dos", "das",
]);

function tokensEntidade(nome: string): string[] {
  return normalizar(nome)
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length > 1 && !PALAVRAS_VAZIAS_ENTIDADE.has(t));
}

/**
 * Mapa apelido → razão social, a partir das razões sociais conhecidas do caso.
 * `razoesSociais` são os nomes vindos do registro de entidade (documento
 * individual); `apelidos` são os rótulos de coluna do documento combinado.
 */
export function consolidarNomesDeEntidade(
  razoesSociais: string[],
  apelidos: string[],
): Map<string, string> {
  const canonico = new Map<string, string>();
  const conhecidas = [...new Set(razoesSociais)]
    .filter((r) => r && !tipoColunaNaoEntidade(r))
    .map((r) => ({ nome: r, tokens: tokensEntidade(r) }))
    .filter((r) => r.tokens.length > 0);

  for (const apelido of new Set(apelidos)) {
    if (!apelido || tipoColunaNaoEntidade(apelido)) continue;
    const tokens = tokensEntidade(apelido);
    if (tokens.length === 0) continue;
    // "Part." casa "Participações" por PREFIXO: o combinado abrevia a coluna
    // para caber no papel, e exigir a palavra inteira perderia o casamento.
    const casam = conhecidas.filter(
      (r) => r.nome !== apelido
        && tokens.every((t) => r.tokens.some((rt) => rt.startsWith(t) || t.startsWith(rt))),
    );
    if (casam.length === 1) canonico.set(apelido, casam[0].nome);
  }
  return canonico;
}

/**
 * Rótulo de período consolidado. Dois rótulos que descrevem o MESMO exercício
 * ("2025" e "31/12/2025") viram colunas distintas só por causa da grafia; aqui
 * a data-base de 31/12 colapsa no exercício, que é como um modelo lê a coluna.
 * Só 31/12 — qualquer outra data-base é uma posição no meio do ano e continua
 * uma coluna própria (não é o exercício fechado).
 */
export function periodoConsolidado(periodoFormatado: string): string {
  const fim = (periodoFormatado ?? "").trim().match(/^31\/12\/((?:19|20)\d{2})$/);
  return fim ? fim[1] : periodoFormatado;
}

/**
 * A ENTIDADE E O PERÍODO EFETIVOS DE UMA LINHA — a regra, num lugar só.
 *
 * Uma linha extraída não pertence necessariamente à entidade nem ao período do
 * DOCUMENTO. Duas migrations abriram essa distinção, e ignorar qualquer uma delas
 * perde dado sem avisar:
 *
 *  • `entidade_coluna` (0014) — o balanço combinado traz várias colunas de
 *    empresa. A entidade da LINHA é a da coluna, não a principal do documento; e o
 *    apelido da coluna ("Componentes") é promovido à razão social quando o caso
 *    conhece uma só que case (`consolidarNomesDeEntidade`), senão a mesma empresa
 *    fica em duas colunas e qualquer soma do grupo a conta duas vezes.
 *  • `periodo_coluna` (0017) — o balanço comparativo traz 2023 e 2024 lado a lado.
 *    O período da LINHA é o da coluna; colapsá-los no período único do documento
 *    perde um exercício inteiro. Vem CRU da extração ("2024", "31/12/2024") e
 *    precisa passar por `formatarPeriodo` + `periodoConsolidado`, senão o MESMO
 *    exercício aparece em dois rótulos diferentes.
 *
 * POR QUE É UMA FUNÇÃO EXPORTADA, e não a linha solta que era. Esta regra vivia
 * dentro do laço do `buildExportWorkbook`, e enquanto o arquivo era o único a
 * precisar dela isso era suficiente. A tela do Modo A (`Arquitetura do Sistema/2 Especificação/f0/07`) responde à mesma
 * pergunta — "de qual empresa e de qual período é este número" —, e uma segunda
 * implementação dela seria duas respostas para a mesma pergunta em duas telas: o
 * defeito que este código já pagou caro para nomear em outros lugares. Uma regra,
 * dois leitores.
 */
export function entidadePeriodoDaLinha(
  campo: Pick<CampoExtraido, "entidade_coluna" | "periodo_coluna">,
  contexto: { entidade: string; periodo: string },
  nomeCanonico: Map<string, string>,
): { entidade: string; periodo: string } {
  const entidadeBruta = campo.entidade_coluna || contexto.entidade;
  return {
    entidade: nomeCanonico.get(entidadeBruta) ?? entidadeBruta,
    periodo: periodoConsolidado(
      campo.periodo_coluna ? formatarPeriodo(null, campo.periodo_coluna) : contexto.periodo,
    ),
  };
}

// Comparador de coluna: entidade (alfabética) → período (CRONOLÓGICO) → rótulo
// como desempate estável para períodos sem âncora temporal.
function compararColunas(
  a: { entidade: string; periodo: string },
  b: { entidade: string; periodo: string },
): number {
  // Entidades reais primeiro; depois a coluna de eliminações; o total por último
  // (é a leitura natural de um mapa de combinação).
  const ordem = (e: string) => {
    const t = tipoColunaNaoEntidade(e);
    return t === "ajuste" ? 1 : t === "total" ? 2 : 0;
  };
  return (
    ordem(a.entidade) - ordem(b.entidade)
    || a.entidade.localeCompare(b.entidade)
    || chaveCronologicaPeriodo(a.periodo) - chaveCronologicaPeriodo(b.periodo)
    || a.periodo.localeCompare(b.periodo)
  );
}

// tipo_taxonomia → nome da aba (ordem de prioridade travada em Arquitetura do Sistema/2 Especificação/f0/07;
// Balancete/Combinado entram na mesma família estrutural do Balanço).
//
// MUTUOS e FAT_INTRAGRUPO são categoria "Intragrupo" na própria taxonomia
// (Supabase/migrations/0002) — mútuo entre empresas do grupo não é DÍVIDA externa
// (banco/financiamento, como MAPA_DIVIDA/CONTRATO_DIVIDA); misturar as duas
// na mesma aba "Dívida" era uma classificação sem sentido contábil (achado em
// produção, sessão 7 cont.¹⁴). CONTRATO_SOCIAL (Societário/Legal) também
// ganhou aba própria em vez de cair no genérico "Outros" junto com dado
// tabular não relacionado.
// DMPL/DVA têm renderização própria (nem grade classificada, nem listagem
// simples) — nomeadas para o roteamento não depender de string solta.
// A aba do espelho 1:1 do banco. Nome com "linha a linha" de propósito: é o que
// distingue, para quem abre o arquivo, o dado CRU do dado lido pelas abas
// classificadas.
export type { ConfigModelagem } from "./export-modelagem";

export const ABA_DADOS = "Dados (linha a linha)";
const ABA_DMPL = "DMPL";
const ABA_DVA = "DVA";

export const ABA_POR_TIPO: Record<string, string> = {
  BALANCO: "Balanço",
  DRE: "DRE",
  FLUXO_CAIXA: "Fluxo de Caixa",
  COMBINADO: "Combinado",
  BALANCETE: "Balancete",
  FATURAMENTO_24M: "Faturamento",
  MAPA_DIVIDA: "Dívida",
  CONTRATO_DIVIDA: "Dívida",
  MUTUOS: "Intragrupo",
  FAT_INTRAGRUPO: "Intragrupo",
  CONTRATO_SOCIAL: "Societário",
  FLUXO_PROJETADO: "Fluxo Projetado",
  DMPL: ABA_DMPL,
  DVA: ABA_DVA,
};
export const ORDEM_ABAS = [
  "Balanço",
  "DRE",
  "Fluxo de Caixa",
  // Depois das três demonstrações principais e antes do Combinado/Balancete:
  // é a ordem em que uma demonstração contábil publicada apresenta o conjunto
  // (BP, DRE, DFC, DMPL, DVA — Lei 6.404/76 art. 176).
  ABA_DMPL,
  ABA_DVA,
  "Combinado",
  "Balancete",
  "Faturamento",
  "Dívida",
  "Intragrupo",
  "Societário",
  "Fluxo Projetado",
  "Outros",
];
const ESTRUTURA_POR_ABA = new Map<string, EstruturaDemonstracao>(
  Object.entries(ESTRUTURA_POR_TIPO).map(([tipo, estrutura]) => [ABA_POR_TIPO[tipo], estrutura]),
);

// tipo_taxonomia (código interno da classificação) → rótulo natural pra
// tela (dashboard, planilha do documento, fila de revisão). Pedido do dono
// (sessão 7 cont.¹⁶): nada de código cru ("FATURAMENTO_24M") na interface —
// escrita natural, do mesmo jeito que um analista falaria. Distinto de
// ABA_POR_TIPO (que agrupa MUTUOS/FAT_INTRAGRUPO numa aba só "Intragrupo" e
// MAPA_DIVIDA/CONTRATO_DIVIDA em "Dívida") — aqui cada tipo tem o próprio
// rótulo, mesmo que dois deles caiam na mesma aba do export.
const TIPO_TAXONOMIA_LABEL: Record<string, string> = {
  BALANCO: "Balanço",
  DRE: "DRE",
  FLUXO_CAIXA: "Fluxo de Caixa",
  COMBINADO: "Demonstrações Combinadas",
  BALANCETE: "Balancete",
  FATURAMENTO_24M: "Faturamento em 24 meses",
  MAPA_DIVIDA: "Mapa da Dívida",
  CONTRATO_DIVIDA: "Contrato de Dívida",
  MUTUOS: "Mútuos",
  FAT_INTRAGRUPO: "Faturamento Intragrupo",
  CONTRATO_SOCIAL: "Contrato Social",
  FLUXO_PROJETADO: "Fluxo Projetado",
  DMPL: "Mutações do Patrimônio Líquido",
  DVA: "Demonstração do Valor Adicionado",
  // O RESTO DA TAXONOMIA. Sem estes, o fallback devolvia o código
  // "humanizado" sem acento — a tela mostrava "Certidoes", "Razao",
  // "Contingencias". Erro de português na coluna que o cliente lê primeiro é o
  // tipo de detalhe que desqualifica um produto inteiro.
  RAZAO: "Livro Razão",
  CERTIDOES: "Certidões",
  ORGANOGRAMA: "Organograma Societário",
  NOTAS_EXPL: "Notas Explicativas",
  DF_AUDITADA: "Demonstrações Auditadas",
  AGING_AR: "Aging de Recebíveis",
  AGING_AP: "Aging de Pagáveis",
  ESTOQUE: "Posição de Estoques",
  SITUACAO_FISCAL: "Situação Fiscal e Parcelamentos",
  CONTINGENCIAS: "Contingências e Processos",
  EXTRATO_BANCARIO: "Extratos Bancários",
  HEADCOUNT: "Folha de Pagamento",
  APLIC_FINANC: "Aplicações Financeiras",
  DEBITOS_TRIB: "Débitos Tributários",
  GARANTIAS: "Garantias Prestadas",
  AVAIS_FIANCAS: "Avais e Fianças",
  CONTRATOS_COM: "Contratos Comerciais",
  CONTRATOS_IC: "Contratos Intercompany",
  DOCS_SOCIOS: "Documentos dos Sócios",
  PLANO_NEGOCIOS: "Plano de Negócios",
  PREMISSAS: "Premissas das Projeções",
  SPED: "Obrigações Acessórias (SPED)",
};

// Tipos ainda sem rótulo explícito (fora do Kit Básico + Variáveis já
// mapeados acima) caem num fallback genérico — "EXTRATO_BANCARIO" vira
// "Extrato Bancario" em vez do código cru — nunca pior que antes, e já seguem
// a mesma linha de escrita natural quando entrar um tipo novo.
/**
 * O rótulo de um código de taxonomia, ou `null` quando a string não é um código
 * conhecido. Existe para o caso em que o texto é uma FRASE e não um código: a
 * descrição de pendência vem do banco com "COMBINADO" no meio, mas também com
 * "ICMS", "PIS", "CNPJ" e "MESMA" — e traduzir por semelhança de formato
 * (palavra em caixa alta) transformaria "ICMS" em "Icms".
 */
export function rotuloDeTipoConhecido(codigo: string): string | null {
  return TIPO_TAXONOMIA_LABEL[codigo] ?? null;
}

export function formatarTipoTaxonomia(codigo: string | null): string {
  if (!codigo) return "Não classificado";
  const label = TIPO_TAXONOMIA_LABEL[codigo];
  if (label) return label;
  return codigo
    .toLowerCase()
    .split("_")
    .map((palavra) => palavra.charAt(0).toUpperCase() + palavra.slice(1))
    .join(" ");
}

// Família da demonstração → aba PADRÃO para onde vai uma linha que pertence a
// essa família mas foi extraída de um documento de OUTRO tipo (um PDF de
// "Demonstrações Contábeis" completo traz Balanço + DRE + Fluxo de Caixa
// juntos). Balancete/Combinado (também família "balanco") mantêm as próprias
// abas quando o documento é desse tipo — só o que "vaza" de um documento
// composto para uma família diferente é redirecionado para estas abas.
const ABA_PADRAO_POR_ESTRUTURA: Record<FamiliaDemonstracao, string> = {
  balanco: "Balanço",
  dre: "DRE",
  fluxo_caixa: "Fluxo de Caixa",
  dmpl: "DMPL",
  dva: "DVA",
};

// Tipo cujo documento é, por definição, o CONJUNTO das demonstrações num arquivo
// só: "Demonstrações financeiras auditadas completas (+ notas)"
// (`Supabase/migrations/0002`). É a forma mais comum de entrega num mandato real — o
// cliente manda o PDF auditado do exercício, não um arquivo por demonstração.
//
// Ele não pode ter aba própria em `ABA_POR_TIPO` (que aba seria? o arquivo é
// Balanço E DRE E DFC E DMPL), e por não ter caía em "Outros": o roteamento por
// linha só rodava para documento de tipo ESTRUTURADO, então a DF auditada inteira
// saía como listagem crua — sem template, sem total de seção, sem AV%/Δ%, sem
// indicadores, e a aba Modelagem (que lê das abas de demonstração) saía ZERADA.
// Aqui o tipo declara "sou composto" e cada linha vai para a aba da SUA
// demonstração, do mesmo jeito que já acontecia com a DMPL embutida num Balanço.
//
// Por que só este tipo, e não todo o balde "Outros": aging de recebíveis, posição
// de estoques, extrato bancário, razão e notas explicativas DETALHAM o que o
// balanço já traz consolidado. Roteá-los para o Balanço somaria o detalhe junto
// com o total — a dupla contagem que o export levou três rodadas para eliminar.
const TIPOS_DOCUMENTO_COMPOSTO = new Set(["DF_AUDITADA"]);

// Demonstrações que a entrega sempre mostra, com dado ou sem. São as três que o
// Kit Básico cobra como obrigatórias e para as quais o modelo aponta.
const ABAS_SEMPRE_PRESENTES = new Set(["Balanço", "DRE", "Fluxo de Caixa"]);

/**
 * Aba de demonstração SEM dado — e dizendo por quê.
 *
 * Distingue os dois casos, que pedem ações opostas do dono:
 *   • documento ENTREGUE e sem linha extraída → é falha do pipeline (no v28, rate
 *     limit da OpenAI): reprocessar o arquivo resolve, e a fila já tem a pendência;
 *   • nenhum documento daquela demonstração → é cobrança de documento, e quem
 *     cobra é o checklist do Kit Básico. Não há nada a reprocessar.
 *
 * Nada é inventado aqui (Arquitetura do Sistema/2 Especificação/f0/07): sem linha extraída não há o que o template
 * ordene. O que a aba entrega é a informação de que falta — que antes o arquivo
 * não dava de jeito nenhum.
 */
function construirAbaSemDado(
  workbook: ExcelJS.Workbook,
  aba: string,
  documentos: DocumentoParaExport[],
): void {
  const tiposDaAba = Object.entries(ABA_POR_TIPO).filter(([, nome]) => nome === aba).map(([tipo]) => tipo);
  const arquivos = [
    ...new Set(
      documentos
        .filter((d) => d.tipo_taxonomia && tiposDaAba.includes(d.tipo_taxonomia))
        .flatMap((d) => (d.documento_versao ?? []).map((v) => v.nome_original ?? "(sem nome)")),
    ),
  ];
  const ws = workbook.addWorksheet(aba);
  ws.columns = [{ width: 42 }, { width: 88 }];
  ws.addRow([`${aba} — sem dado nesta entrega`]).font = { bold: true, size: 12 };
  ws.addRow(
    arquivos.length > 0
      ? ["Documento entregue, extração sem linha",
        `${arquivos.join("; ")}. O arquivo chegou e foi classificado, mas a extração não gravou `
        + "nenhuma linha — a falha abre pendência própria na fila de revisão do mandato. "
        + "Reprocessar o arquivo preenche esta aba."]
      : ["Nenhum documento desta demonstração",
        "O mandato ainda não tem documento classificado nesta demonstração. Quem cobra isso é o "
        + "checklist do Kit Básico; esta aba existe para a ausência ficar visível na entrega."],
  );
  ws.getRow(2).alignment = { wrapText: true, vertical: "top" };
  ws.getRow(2).height = 42;
  ws.addRow([]);
  const nota = ws.addRow(["", "Nada é preenchido por conta própria: o template ordena o que o documento "
    + "trouxe (Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md). Sem linha extraída, não há o que ordenar."]);
  nota.alignment = { wrapText: true, vertical: "top" };
  nota.font = { italic: true, size: 9 };
}

export interface DocumentoParaExport {
  id: string;
  tipo_taxonomia: string | null;
  entidade: { razao_social: string } | null;
  periodo: { tipo: string; referencia: string } | null;
  documento_versao: Array<{ id: string; nome_original: string | null; n_versao?: number | null }> | null;
}

/**
 * Versões VIGENTES por documento — reextração SUBSTITUI, não acumula.
 *
 * Reextrair é a única forma de um documento já processado pegar prompt/taxonomia
 * novos (migration e prompt só valem para extração NOVA), e o dono precisa disso
 * para a DMPL da `0024`. Mas o export lia TODAS as versões de cada documento, e
 * duas extrações do mesmo arquivo não produzem as mesmas linhas — é o ponto de
 * mudar o prompt. Medido: com o rótulo renomeado entre as duas extrações, a
 * conta aparece DUAS vezes e a soma da seção somou as duas (1.000 + 1.500 =
 * 2.500 onde o documento diz 1.500). A dupla contagem de sempre, por um caminho
 * novo — e o pior tipo: o dono não pode nem desconfiar, porque as duas linhas têm
 * proveniência legítima.
 *
 * **A mais recente COM DADO manda.** Não é "a mais recente", e a diferença é uma
 * proteção real: uma reextração pode falhar (truncamento/rate limit gravam
 * `extracao_falhou` com ZERO linhas, `Supabase/migrations/0016`). Se a vigência fosse
 * cega ao dado, essa falha APAGARIA do book tudo o que a versão anterior tinha
 * extraído com sucesso — trocar dupla contagem por perda silenciosa de dado não
 * é conserto.
 *
 * Empate (mesma `n_versao`, ou nenhuma informada) mantém as duas: sem ordem
 * declarada não há como saber qual é a nova, e escolher por chute é pior que o
 * comportamento antigo.
 */
export function versoesVigentes(documentos: DocumentoParaExport[], campos: CampoExtraido[]): Set<string> {
  const comDado = new Set(campos.map((c) => c.documento_versao_id));
  const vigentes = new Set<string>();
  for (const doc of documentos) {
    const versoes = doc.documento_versao ?? [];
    if (versoes.length <= 1) {
      for (const v of versoes) vigentes.add(v.id);
      continue;
    }
    const n = (v: { n_versao?: number | null }) => v.n_versao ?? 1;
    // Grupos por n_versao, do mais novo para o mais antigo.
    const grupos: Array<typeof versoes> = [];
    for (const v of [...versoes].sort((a, b) => n(b) - n(a))) {
      const ultimo = grupos[grupos.length - 1];
      if (ultimo && n(ultimo[0]) === n(v)) ultimo.push(v);
      else grupos.push([v]);
    }
    const vigente = grupos.find((g) => g.some((v) => comDado.has(v.id))) ?? grupos[0];
    for (const v of vigente) vigentes.add(v.id);
  }
  return vigentes;
}

interface ContextoVersao {
  entidade: string;
  periodo: string;
  tipoTaxonomia: string | null;
  nomeArquivo: string;
}

interface Coluna {
  key: string;
  entidade: string;
  periodo: string;
}

export function nomeArquivoSanitizado(nomeCaso: string) {
  return nomeCaso
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // remove acentos (marcas de combinação) após NFD
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

function formatarStatus(status: string) {
  return status === "aceito" ? "ACEITO" : status === "com_ressalva" ? "COM RESSALVA" : "PENDENTE";
}

// Em empate (mais de um campo casando no mesmo lugar), prefere maior
// confiança e rótulo mais curto (mais específico) — mesmo critério de
// `fn_valor_conceito` (Supabase/migrations/0009).
// ---------------------------------------------------------------------------
// ESCALA (milhar/milhão/unidade) — o defeito mais caro que este arquivo tinha.
//
// `campo.unidade` existia, era lido e NUNCA era usado como fator. Cada célula
// gravava `campo.valor_num` cru, então um Balanço em MILHAR somado a um Balancete
// em UNIDADE na mesma coluna dava erro de ~496x — medido, não estimado:
//
//     ATIVO                      27.928.400   <- deveria ser 56.300 (em milhar)
//     Ativo Circulante  =SUM(...) 27.928.400
//       Disponibilidades              500     (milhar)
//       Duplicatas a receber       27.900     (milhar)
//       Clientes nacionais     27.900.000     (unidade)
//
// E sem NENHUMA marca de divergência: a linha de conferência só compara contra o
// total informado pelo documento, e aqui não havia total. AV%, Δ% e todos os
// indicadores de liquidez/endividamento herdavam o número corrompido.
//
// O banco já resolvia isso e o portal não usava: `fn_fator_escala` /
// `fn_valor_em_base` (0023) convertem antes de comparar, e é por isso que a
// reconciliação acertava enquanto o book mentia.
//
// A correção é feita no LIMITE DE NORMALIZAÇÃO (uma vez, logo depois de filtrar as
// versões vigentes) e não em cada ponto de escrita. Isso é deliberado: convertendo
// os valores na entrada, TODO consumidor a jusante — células, `SUM`, detecção de
// subtotal, AV%/Δ%, indicadores, linha de conferência, aba Modelagem — passa a
// estar correto sem precisar ser tocado. Corrigir célula por célula deixaria de
// fora exatamente os consumidores que ninguém lembra.
const FATOR_ESCALA: Record<string, number> = { unidade: 1, milhar: 1_000, milhao: 1_000_000 };

// Como a escala é escrita para humano. Vai no cabeçalho de cada aba de valores:
// planilha financeira sem escala declarada é planilha que alguém vai ler errado.
export const ROTULO_ESCALA: Record<string, string> = {
  unidade: "R$",
  milhar: "R$ mil",
  milhao: "R$ milhões",
};

export interface EscalaDoExport {
  alvo: string;                       // escala em que TODO valor do book está
  converteu: number;                  // quantos campos foram convertidos
  semDeclaracao: number;              // quantos não declaravam escala
  escalasEncontradas: string[];        // o que apareceu nos documentos
}

// A escala do book é a PREDOMINANTE entre as declaradas. Não é média nem "a
// primeira": é a que mais linhas declaram, porque converter a minoria produz
// menos ruído de leitura. Sem nenhuma escala declarada → 'unidade', que preserva
// os números exatamente como estão hoje.
export function escolherEscalaAlvo(campos: CampoExtraido[]): string {
  const contagem = new Map<string, number>();
  for (const c of campos) {
    if (c.unidade && FATOR_ESCALA[c.unidade] != null) {
      contagem.set(c.unidade, (contagem.get(c.unidade) ?? 0) + 1);
    }
  }
  if (contagem.size === 0) return "unidade";
  return [...contagem.entries()].sort((a, b) => b[1] - a[1] || FATOR_ESCALA[b[0]] - FATOR_ESCALA[a[0]])[0][0];
}

// Converte todo valor para a escala alvo. Campo sem escala declarada é deixado
// COMO ESTÁ e contado em `semDeclaracao`: assumir 'unidade' para ele seria
// inventar um fator de 1000x justamente onde não se sabe — e o comentário da
// fonte de `normalizarUnidade` já diz que "errar em 1000x é pior que não saber".
// A nota de proveniência da célula declara essa suposição, uma por uma.
export function normalizarEscala(
  campos: CampoExtraido[],
  alvo: string,
): { campos: CampoExtraido[]; escala: EscalaDoExport } {
  const fatorAlvo = FATOR_ESCALA[alvo] ?? 1;
  let converteu = 0;
  let semDeclaracao = 0;
  const encontradas = new Set<string>();

  const saida = campos.map((c) => {
    if (!c.unidade || FATOR_ESCALA[c.unidade] == null) {
      semDeclaracao += 1;
      return c;
    }
    encontradas.add(c.unidade);
    if (c.unidade === alvo || c.valor_num == null) return { ...c, unidade: alvo, unidade_original: c.unidade };
    const fator = FATOR_ESCALA[c.unidade] / fatorAlvo;
    converteu += 1;
    return { ...c, valor_num: c.valor_num * fator, unidade: alvo, unidade_original: c.unidade };
  });

  return {
    campos: saida,
    // `c.unidade` é chave de enum validada contra `FATOR_ESCALA`
    // (`unidade`|`milhar`|`milhao`), não texto humano — o rótulo lido por
    // gente nasce depois, em `ROTULO_ESCALA[e]` (ver uso de
    // `escala.escalasEncontradas`). Sem acento na chave, comparador de código
    // basta e a ordem fica determinística sem depender de locale (sonar
    // typescript:S2871).
    escala: { alvo, converteu, semDeclaracao, escalasEncontradas: [...encontradas].sort(compararCodigo) },
  };
}

function melhorCampo(campos: CampoExtraido[]): CampoExtraido {
  return [...campos].sort((a, b) => (b.confianca ?? 0) - (a.confianca ?? 0) || a.chave.length - b.chave.length)[0];
}

function notaProveniencia(campo: CampoExtraido, ctx: ContextoVersao) {
  const linhas = [
    `Rótulo original: "${campo.chave}"`,
    campo.entidade_coluna ? `Coluna de origem no documento: ${campo.entidade_coluna}` : null,
    `Arquivo: ${ctx.nomeArquivo}`,
    // Escala: informação de AUDITORIA, não detalhe. Antes desta linha as abas
    // classificadas não mostravam a escala nem no hover, então um número
    // convertido era indistinguível de um número original — e um número SEM
    // escala declarada era indistinguível de um que declarava a escala do book.
    campo.unidade_original && campo.unidade_original !== campo.unidade
      ? `Escala: convertido de ${ROTULO_ESCALA[campo.unidade_original] ?? campo.unidade_original} para ${ROTULO_ESCALA[campo.unidade ?? ""] ?? campo.unidade}`
      : campo.unidade
        ? `Escala: ${ROTULO_ESCALA[campo.unidade] ?? campo.unidade}`
        : `Escala: NÃO declarada no documento — valor usado como está, sem conversão`,
    campo.origem_pagina != null ? `Página: ${campo.origem_pagina}` : null,
    campo.confianca != null ? `Confiança da extração: ${Math.round(campo.confianca * 100)}%` : null,
    `Status: ${formatarStatus(campo.status_aceite)}`,
    campo.status_aceite === "aceito" && campo.aceito_por ? `Aceito por: ${campo.aceito_por}` : null,
  ].filter(Boolean);
  return linhas.join("\n");
}

const PENDENTE_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFFF3CD" } };
const SECAO_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF3F4F6" } };
const NAO_CLASSIFICADO_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF3E8FF" } };
const DOUBLE_TOP_BORDER: Partial<ExcelJS.Borders> = { top: { style: "double" } };

interface GrupoConta {
  label: string;
  porColuna: Map<string, CampoExtraido[]>; // colKey → campos casados ali (melhorCampo escolhe 1)
}

function novoGrupo(label: string): GrupoConta {
  return { label, porColuna: new Map() };
}

function adicionarAoGrupo(grupo: GrupoConta, colKey: string, campo: CampoExtraido) {
  if (!grupo.porColuna.has(colKey)) grupo.porColuna.set(colKey, []);
  grupo.porColuna.get(colKey)!.push(campo);
}

// Escreve uma linha de conta (rótulo + valor por coluna + nota de
// proveniência + estilo pendente/total) numa `sheet` já criada. `valuePos[i]`
// = posição (número da coluna Excel) onde a coluna de valor `i` é escrita — as
// colunas de valor NÃO são mais contíguas (intercalam AV%/Δ%), então tudo é
// endereçado pelo plano de colunas, não por `i + 2`.
function escreverLinhaConta(
  sheet: ExcelJS.Worksheet,
  rowIndex: number,
  label: string,
  nivel: number,
  colunas: Coluna[],
  valuePos: number[],
  grupo: GrupoConta,
  opts: { negrito?: boolean; borda?: "simples" | "dupla" },
  contextoPorVersao: Map<string, ContextoVersao>,
) {
  const row = sheet.getRow(rowIndex);
  row.getCell(1).value = label;
  row.getCell(1).alignment = { indent: nivel };
  if (opts.negrito) row.font = { bold: true };

  colunas.forEach((col, i) => {
    const cell = row.getCell(valuePos[i]);
    if (opts.borda === "simples") cell.border = THIN_TOP_BORDER;
    if (opts.borda === "dupla") cell.border = DOUBLE_TOP_BORDER;
    const candidatos = grupo.porColuna.get(col.key);
    if (!candidatos || candidatos.length === 0) return;
    const campo = melhorCampo(candidatos);
    cell.value = campo.valor_num ?? campo.valor_texto ?? null;
    if (typeof cell.value === "number") cell.numFmt = VALOR_NUM_FMT;
    if (campo.status_aceite !== "aceito") {
      cell.fill = PENDENTE_FILL;
      cell.font = { ...(row.font ?? {}), italic: true };
    }
    const ctx = contextoPorVersao.get(campo.documento_versao_id);
    if (ctx) {
      cell.note = comoNota(notaProveniencia(campo, ctx));
    }
  });
}

const MARGEM_FONT: Partial<ExcelJS.Font> = { italic: true, size: 9, color: { argb: "FF2563EB" } };
// Âncora da DRE → rótulo da linha de margem (% da Receita Líquida).
const MARGEM_LABEL: Record<string, string> = {
  lucro_bruto: "Margem Bruta %",
  resultado_operacional: "Margem Operacional %",
  lucro_liquido: "Margem Líquida %",
};

// ----- Camada analítica (Arquitetura do Sistema/2 Especificação/f0/08): análise vertical / horizontal / indicadores.
// Colunas AV% (análise vertical, common-size) e Δ% (análise horizontal, entre
// períodos comparáveis da mesma entidade) são FÓRMULAS transparentes sobre o
// dado já extraído — não projetam nem inventam número. Estilo discreto
// (cinza-azulado, menor) para não competir com os valores.
const SUBTOTAL_INFO_FONT: Partial<ExcelJS.Font> = { italic: true, size: 8, color: { argb: "FF7C3AED" } };
const ANALISE_FONT: Partial<ExcelJS.Font> = { italic: true, size: 9, color: { argb: "FF64748B" } };
const AV_FMT = "0.0%";
const DELTA_FMT = "+0.0%;-0.0%;0.0%";
const INDICADOR_TITULO_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFE0E7FF" } };
const INDICADOR_LABEL_FONT: Partial<ExcelJS.Font> = { size: 10, color: { argb: "FF1E293B" } };

// Plano de colunas do relatório: as colunas de VALOR (entidade×período) não são
// mais contíguas — cada uma pode ser seguida de sua AV% e, quando comparável ao
// período anterior da MESMA entidade, de uma Δ%. Centraliza o mapeamento
// "índice da coluna de valor → coluna Excel real" para que todas as fórmulas
// (subtotais, margens, indicadores) refiram a célula certa.
interface PlanoColunas {
  valuePos: number[]; // i (coluna de valor) → nº da coluna Excel
  avPos: Array<number | null>; // i → coluna Excel da AV% (null quando não se aplica, ex.: Fluxo)
  deltas: Array<{ pos: number; atual: number; anterior: number }>; // colunas Δ%
  ultimaColuna: number;
}

function planejarColunas(colunas: Coluna[], comAV: boolean): PlanoColunas {
  const valuePos: number[] = [];
  const avPos: Array<number | null> = [];
  const deltas: Array<{ pos: number; atual: number; anterior: number }> = [];
  let col = 2; // coluna 1 = rótulo da conta
  colunas.forEach((coluna, i) => {
    const naoEntidade = tipoColunaNaoEntidade(coluna.entidade) != null;
    valuePos[i] = col++;
    // AV% não se aplica a coluna de ajuste/total (ver tipoColunaNaoEntidade).
    avPos[i] = comAV && !naoEntidade ? col++ : null;
    // Δ% só entre períodos DIFERENTES da MESMA entidade, adjacentes na ordenação
    // (as colunas vêm ordenadas por entidade e depois período).
    if (!naoEntidade && i > 0 && colunas[i - 1].entidade === coluna.entidade
        && colunas[i - 1].periodo !== coluna.periodo
        && tipoColunaNaoEntidade(colunas[i - 1].entidade) == null) {
      deltas.push({ pos: col++, atual: i, anterior: i - 1 });
    }
  });
  return { valuePos, avPos, deltas, ultimaColuna: col - 1 };
}

// valor_num "melhor" de um grupo de conta numa coluna (para conferir a soma em
// JS contra o total que o documento trouxe — a célula em si leva a FÓRMULA).
function valorNumDoGrupo(grupo: GrupoConta, colKey: string): number | null {
  const c = grupo.porColuna.get(colKey);
  if (!c || c.length === 0) return null;
  const campo = melhorCampo(c);
  return typeof campo.valor_num === "number" ? campo.valor_num : null;
}

// Uma linha extraída é o SUBTOTAL de um agrupamento do próprio documento (e não
// uma conta)? Demonstrações reais são hierárquicas: sob "Ativo Circulante" vêm
// os agrupamentos "Disponível", "Contas a Receber", "Estoques"… cada um com o
// PRÓPRIO subtotal impresso, seguido das contas que o compõem. Sem reconhecer
// isso, o subtotal entra no bucket como se fosse conta e o `SUM` da seção soma
// o subtotal MAIS os seus componentes — dobrando tudo. Achado com dado real
// (book Vertentes): `SUM` do Ativo Circulante deu 137.865 contra 67.878
// informados = 2,03x, contaminando também AV% e todos os indicadores.
//
// A `ancoraBalanco` de statement-templates.ts só reconhece total quando o
// rótulo tem "total"/"soma" ou é feito só de palavras estruturais — não cobre
// "Disponível"/"Estoques", que são nomes de agrupamento comuns. Aqui a detecção
// é ESTRUTURAL, a partir do próprio documento, por dois sinais independentes:
//
//   (A) o rótulo da linha é IGUAL ao nome de seção (`secao`) que outras linhas
//       do mesmo documento declaram — ou seja, o documento diz que aquele nome
//       é um agrupamento, e esta linha é o total dele;
//   (B) o valor da linha é IGUAL à soma das OUTRAS linhas que compartilham a
//       mesma `secao`, em TODAS as colunas com dado — coincidência estatística
//       praticamente impossível em documento multi-coluna.
//
// Nada é descartado: a linha continua visível (marcada como subtotal informado),
// só sai da SOMA. Sem `secao` anotada, nenhum dos sinais dispara e o
// comportamento é o de antes (conservador).
/**
 * Subtotal reconhecido pela ORDEM em que o documento imprime as linhas.
 *
 * Modo de falha que isto conserta (teste v28, VT Logística): a seção saiu com
 * Ativo Circulante 7.254 onde o documento diz 3.961, porque "Contas a Receber"
 * (3.293) foi somada JUNTO com "Fretes a receber" (3.562) e "(-) PECLD" (−269),
 * que são os seus componentes. As duas detecções estruturais existentes não
 * pegam esse caso: uma exige que alguma linha declare `secao` com o nome do
 * subtotal (a extração daquele arquivo anotou a seção de TOPO em todas), e a
 * outra exige que o valor bata com a soma dos irmãos da MESMA seção (ali os
 * irmãos são o circulante inteiro). E o documento não trouxe linha de total,
 * então nem a conferência acusava — o número errado não tinha como ser visto.
 *
 * O sinal que sobra é o que toda demonstração publicada dá: o subtotal vem
 * impresso IMEDIATAMENTE ANTES dos seus componentes.
 *
 * Critério deliberadamente ESTREITO — um falso positivo aqui tira da soma uma
 * conta legítima, que é pior que o defeito original:
 *   • exige `ordem` nas linhas (extração antiga não tem: nada acontece);
 *   • exige pelo menos DOIS componentes seguidos (um só é ambíguo — pode ser
 *     reclassificação, arredondamento ou simplesmente coincidência);
 *   • exige casamento EXATO (1 centavo) da soma, na MESMA coluna;
 *   • só dentro da mesma `secao` declarada, e para valor não nulo;
 *   • a varredura para no primeiro casamento, e retoma DEPOIS do último
 *     componente consumido — assim uma cascata de subtotais não se sobrepõe.
 */
function detectarSubtotaisPorOrdem(
  camposDaAba: Array<{ campo: CampoExtraido; colKey: string }>,
): Set<string> {
  const subtotais = new Set<string>();
  // Agrupa por (versão do documento × coluna × seção): a sequência impressa só
  // faz sentido dentro do mesmo documento e da mesma coluna de valor.
  const grupos = new Map<string, CampoExtraido[]>();
  for (const { campo, colKey } of camposDaAba) {
    if (campo.ordem == null) continue;
    const k = `${campo.documento_versao_id}${CHAVE_SEP}${colKey}${CHAVE_SEP}${normalizar(campo.secao ?? "")}`;
    if (!grupos.has(k)) grupos.set(k, []);
    grupos.get(k)!.push(campo);
  }

  for (const todas of grupos.values()) {
    todas.sort((a, b) => (a.ordem ?? 0) - (b.ordem ?? 0));
    // OCORRÊNCIA REPETIDA DO MESMO RÓTULO NÃO É OUTRA LINHA DO DOCUMENTO.
    //
    // Este detector lê a SEQUÊNCIA IMPRESSA: um subtotal seguido dos seus
    // componentes. Ele só funciona se a sequência for a do documento — e a
    // extração real repete rótulo dentro do mesmo documento o tempo todo: é o que
    // um comparativo produz quando `periodo_coluna` não vem preenchido (as duas
    // colunas viram duas linhas com o mesmo rótulo), e o v35 traz cada conta
    // duplicada exatamente assim.
    //
    // COM AS REPETIÇÕES DENTRO, o detector errava dos DOIS lados:
    //
    //   • FALSO POSITIVO — a segunda ocorrência do próprio candidato tem o mesmo
    //     valor dele, então "a soma dos seguintes bate com o candidato" com um
    //     componente só. Medido no v35: a DESPESA "Provisão para contingências
    //     trabalhistas e cíveis" (−1.900) e "Imposto de renda e contribuição
    //     social - corrente" (−420) foram declaradas subtotais e SUMIRAM do
    //     modelo institucional — SG&A 1.900 menor, EBIT 1.900 maior, sem aviso;
    //   • FALSO NEGATIVO — os componentes de um subtotal DE VERDADE também vêm
    //     duplicados, e a soma deles dá o dobro. O acerto de antes vinha da
    //     coincidência do falso positivo (o candidato casava com a própria
    //     cópia), não da estrutura.
    //
    // Colapsar as repetições ANTES de olhar a sequência resolve os dois: fica uma
    // linha por rótulo, na posição em que ela aparece primeiro (a posição
    // impressa). Isto é uma visão LOCAL do detector — não muda o que o arquivo
    // publica, que continua trazendo cada ocorrência na aba `Dados (linha a
    // linha)`.
    const vistos = new Set<string>();
    const linhas = todas.filter((c) => {
      const k = normalizar(c.chave);
      if (vistos.has(k)) return false;
      vistos.add(k);
      return true;
    });
    if (linhas.length < 3) continue; // subtotal + 2 componentes é o mínimo
    // O grupo é (versão × coluna × `secao`), e `secao` nula forma UM grupo com todas as linhas sem
    // seção do documento (medido no Krauspenhar: ordens 13, 22 e 23 juntas). Por isso o total da
    // seção é reconhecido pelo nome da seção DO CANDIDATO (`secao` ou `secao_canonica`
    // humanizada), lido no rótulo da linha seguinte — que pode vir com `secao` e
    // `secao_canonica` nulas, e com ou sem "Total d[oa]".
    const ehTotalDaSecaoDe = (cand: CampoExtraido, c: CampoExtraido) => {
      const n = normalizar(c.chave).replace(/^total (?:d[oa] )?/, "");
      return [cand.secao ?? "", (cand.secao_canonica ?? "").replace(/_/g, " ")]
        .map(normalizar).some((nome) => nome !== "" && nome === n);
    };
    let i = 0;
    while (i < linhas.length) {
      const candidato = linhas[i];
      const valor = candidato.valor_num;
      if (valor == null || valor === 0) { i++; continue; }
      // Quantos componentes seguidos bastam para caracterizar o subtotal:
      //   • 1, quando o rótulo já É nome de agrupamento contábil ("Contas a
      //     Receber", "Obrigações Tributárias") — aí há DOIS sinais
      //     independentes, e um componente só é suficiente;
      //   • 2, quando o rótulo não diz nada — só a aritmética sustenta, e uma
      //     coincidência de dois valores consecutivos é bem menos provável.
      // Sem o caso de 1 componente, "Outros Créditos 340" seguido de
      // "Adiantamentos diversos 340" (teste v29) ficava fora e mantinha 340 de
      // dupla contagem.
      const minComponentes = ehNomeDeAgrupamento(candidato.chave) ? 1 : 2;
      let acumulado = 0;
      let casouEm = -1;
      for (let j = i + 1; j < linhas.length; j++) {
        const v = linhas[j].valor_num;
        if (v == null) break;
        // O TOTAL DA PRÓPRIA SEÇÃO NÃO É COMPONENTE DE NINGUÉM DA SEÇÃO. Seção com UMA conta só
        // imprime a conta e, logo abaixo, o total dela com o MESMO valor — e com um nome de
        // agrupamento no rótulo (1 componente basta) a conta virava "subtotal do próprio total".
        // Medido no Krauspenhar (caso 33b58a89): "Empréstimos e financiamentos - longo prazo"
        // (4,18 mi em 2024, 9,54 mi em 2025), única conta do passivo não circulante, saía do
        // modelo nos DOIS anos; a "Dívida de longo prazo" ficava 0 e o valor só reaparecia como
        // resíduo de reconciliação (6 células de 8% a 11% do ativo).
        if (ehTotalDaSecaoDe(candidato, linhas[j])) break;
        acumulado += v;
        if (j - i >= minComponentes && Math.abs(acumulado - valor) < 0.01) { casouEm = j; break; }
      }
      if (casouEm > 0) {
        subtotais.add(candidato.id);
        i = casouEm + 1; // retoma depois dos componentes consumidos
      } else {
        i++;
      }
    }
  }
  return subtotais;
}

function detectarSubtotaisInformados(
  camposDaAba: Array<{ campo: CampoExtraido; colKey: string }>,
): Set<string> {
  const subtotais = new Set<string>();
  const secoesDeclaradas = new Set<string>();
  for (const { campo } of camposDaAba) {
    const s = normalizar(campo.secao ?? "");
    if (s) secoesDeclaradas.add(s);
  }

  // (A) rótulo == nome de um agrupamento declarado pelo documento.
  for (const { campo, colKey } of camposDaAba) {
    const chaveNorm = normalizar(campo.chave);
    if (!chaveNorm || !secoesDeclaradas.has(chaveNorm)) continue;
    // exige que o agrupamento tenha MEMBROS (linhas cuja secao é esse nome e
    // cujo rótulo é diferente) — senão não há nada que este total duplique.
    //
    // OS MEMBROS TÊM DE SER DO MESMO DOCUMENTO E DA MESMA COLUNA da ocorrência. Olhar a
    // aba inteira fazia um documento declarar o agrupamento e marcar como subtotal a
    // conta HOMÔNIMA de outro documento. Medido no Krauspenhar (caso 33b58a89):
    // "Venda de peças e lubrificantes" é o agrupamento das "Peças GTS/Massey…" no
    // balancete de 2026 e é CONTA na DRE de 2025 (36,19 mi); marcada como subtotal, saía
    // da soma do modelo em todos os anos (receita bruta 2025: 77,19 mi contra 113,38 mi).
    const temMembros = camposDaAba.some(
      ({ campo: c, colKey: ck }) => c.documento_versao_id === campo.documento_versao_id && ck === colKey
        && normalizar(c.secao ?? "") === chaveNorm && normalizar(c.chave) !== chaveNorm,
    );
    if (temMembros) subtotais.add(campo.id);
  }

  // (B) valor == soma dos irmãos da mesma seção, em todas as colunas com dado.
  const porSecao = new Map<string, Array<{ campo: CampoExtraido; colKey: string }>>();
  for (const item of camposDaAba) {
    const s = normalizar(item.campo.secao ?? "");
    if (!s) continue;
    if (!porSecao.has(s)) porSecao.set(s, []);
    porSecao.get(s)!.push(item);
  }
  for (const itens of porSecao.values()) {
    const porChave = new Map<string, Array<{ campo: CampoExtraido; colKey: string }>>();
    for (const it of itens) {
      const k = normalizar(it.campo.chave);
      if (!porChave.has(k)) porChave.set(k, []);
      porChave.get(k)!.push(it);
    }
    if (porChave.size < 3) continue; // precisa de >=2 componentes + o subtotal
    for (const [chaveCandidata, ocorrencias] of porChave) {
      let colunasConferidas = 0;
      let bate = true;
      const colunas = new Set(ocorrencias.map((o) => o.colKey));
      for (const colKey of colunas) {
        const cand = ocorrencias.find((o) => o.colKey === colKey)?.campo.valor_num;
        if (typeof cand !== "number") continue;
        let soma = 0;
        let n = 0;
        for (const [k, occ] of porChave) {
          if (k === chaveCandidata) continue;
          const v = occ.find((o) => o.colKey === colKey)?.campo.valor_num;
          if (typeof v === "number") { soma += v; n++; }
        }
        if (n < 2) continue;
        colunasConferidas++;
        if (Math.abs(soma - cand) > Math.max(0.01, Math.abs(cand) * 0.005)) { bate = false; break; }
      }
      if (bate && colunasConferidas > 0) {
        for (const o of ocorrencias) subtotais.add(o.campo.id);
      }
    }
  }
  return subtotais;
}

/**
 * Os rótulos que a ESTRUTURA do documento denuncia como subtotal, para o MODELO
 * INSTITUCIONAL usar a mesma verdade que as abas analíticas.
 *
 * POR QUE ISTO EXISTE. As duas detecções acima rodam por aba e devolvem ids de
 * campo, que servem para a aba marcar "↳ subtotal informado" e tirar a linha do
 * `SUM`. O modelo institucional consome LINHAS agregadas por rótulo
 * (`fn_linhas_para_modelagem`), cujo `papel` vem de lista fechada de rótulos — que
 * por construção não reconhece "Obrigações Tributárias", "Provisões", "Capital
 * Social", "Reservas", "Disponível", "Contas a Receber". Resultado medido no
 * arquivo entregue ao dono (v35, 06/08/2026): a aba `Balanço` mostrava o ativo
 * certo (95.780 informados) e o `Balance Sheet` do modelo, no MESMO arquivo,
 * mostrava 195.090 — o subtotal somado junto com os componentes dele.
 *
 * Uma detecção, dois consumidores. Duplicar a regra aqui seria garantir que as
 * duas abas do mesmo arquivo voltem a discordar.
 *
 * FILTRA PELA ENTIDADE MODELADA de propósito: o mesmo rótulo pode ser subtotal no
 * documento de uma empresa do grupo e conta-folha no de outra (é o caso (b) do
 * comentário do invariante nº 6). Tirar da soma do modelo de B um subtotal que só
 * existe em A seria um falso positivo — e falso positivo aqui ESCONDE conta, que é
 * pior que o defeito que se está corrigindo.
 *
 * E A CHAVE INCLUI A SEÇÃO, pelo mesmo motivo, dentro da mesma empresa. MEDIDO no
 * caso v35 com a primeira versão desta função, que devolvia rótulo solto: o
 * balanço imprime "Provisão para contingências trabalhistas e cíveis" como
 * subtotal do grupo de provisões, e a DRE tem uma DESPESA com o mesmo nome
 * (−1.900). Excluir por rótulo tirava as duas, o SG&A saía 1.900 menor e o EBIT
 * 1.900 maior — trocando uma dupla contagem por uma conta escondida. O mesmo
 * aconteceu com "Imposto de renda e contribuição social - corrente".
 *
 * O par devolvido é `secao_canonica||rotulo`, ambos normalizados, e ganha um terceiro
 * campo `||ano` quando o subtotal vale só naquele exercício (ver o fim da função).
 */
export function rotulosDeSubtotalInformado(
  camposPorAba: Map<string, Array<{ campo: CampoExtraido; colKey: string }>>,
  entidade: string | null,
  /** O exercício do DOCUMENTO de onde veio o campo (`null` quando não se lê um ano só). Serve
   * só à coluna de exercício ilegível: ver o fim da função. */
  anoDoDocumento?: (campo: CampoExtraido) => string | null,
): string[] {
  const alvo = entidade ? normalizar(entidade) : null;
  const rotulos = new Set<string>();
  // O rótulo que ALGUMA aba marcou como subtotal numa coluna de exercício ilegível (com o ano
  // do documento de cada coluna, quando se lê), e os exercícios legíveis que o mesmo
  // (seção, rótulo) tem em QUALQUER aba — ver o fim da função.
  const ilegiveisMarcados = new Map<string, Array<string | null>>();
  const anosLegiveis = new Map<string, Set<string>>();
  for (const [aba, itens] of camposPorAba) {
    if (!ESTRUTURA_POR_ABA.has(aba)) continue;
    // DETECTA SOBRE A ABA INTEIRA e só DEPOIS filtra pela entidade. A ordem
    // importa: os dois detectores olham a SEQUÊNCIA impressa e a soma dos irmãos
    // de seção, então mudar o conjunto de entrada muda o veredito. Filtrar antes
    // fazia esta função discordar da aba analítica do mesmo arquivo — medido no
    // v35: com a entrada reduzida, uma despesa da DRE virava "subtotal" por
    // coincidência de soma que não existe quando a aba é vista inteira. A aba e o
    // modelo têm de receber o MESMO veredito; a entidade decide apenas QUAIS
    // vereditos se aplicam às linhas do modelo.
    // `idsFortes` = regras (A) e (B), que olham a estrutura declarada e a soma dos irmãos
    // EM CADA COLUNA; `PorOrdem` é a única que decide por coincidência de soma numa célula.
    // Os exercícios legíveis de cada (seção, rótulo) valem MESMO quando a aba não tem
    // subtotal nenhum — é justamente a aba "limpa" (os Balanços) que o veredito ilegível de
    // outra aba não pode apagar.
    for (const { campo, colKey } of itens) {
      if (alvo !== null && normalizar(colKey.split(CHAVE_SEP)[0] ?? "") !== alvo) continue;
      if (typeof campo.valor_num !== "number") continue;
      const ano = anoDaColuna(colKey);
      if (ano === null) continue;
      const k = `${normalizar(campo.secao_canonica ?? "")}||${normalizar(campo.chave)}`;
      if (!anosLegiveis.has(k)) anosLegiveis.set(k, new Set());
      anosLegiveis.get(k)!.add(ano);
    }
    const idsFortes = detectarSubtotaisInformados(itens);
    const ids = new Set([...idsFortes, ...detectarSubtotaisPorOrdem(itens)]);
    if (ids.size === 0) continue;
    // O VEREDITO É POR RÓTULO, MAS A DETECÇÃO É POR CÉLULA — e a diferença
    // apagava conta de verdade.
    //
    // MEDIDO no book: `detectarSubtotaisPorOrdem` marcou "Matérias-primas e
    // insumos" na coluna de 2024 (12.400), porque ali as linhas seguintes
    // somavam por COINCIDÊNCIA o valor dela. O rótulo entrava no conjunto sem a
    // coluna, e com isso a conta sumia do modelo em TODAS as colunas e em todas
    // as empresas do grupo: em 2025 o bloco `ativo_circulante` ficava com 16
    // linhas somando 36.240 onde o documento tem 17 somando 45.440 — os 9.200
    // dela. Uma coincidência num exercício apagava a conta no outro.
    //
    // A REGRA PASSA A SER: subtotal em UMA coluna não basta; tem de ser subtotal
    // em TODAS as ocorrências com valor. É o que `detectarSubtotaisInformados`
    // (B) já exigia — ele confere a soma dos irmãos em cada coluna e desiste ao
    // primeiro desacordo. `PorOrdem` era o único que decidia por uma célula.
    //
    // E ISSO NÃO ENFRAQUECE O CABEÇALHO DE GRUPO DE VERDADE, que é o que o
    // conjunto existe para pegar: "Estoques" é nome de seção declarada pelo
    // documento e cai na regra (A), estrutural, que não depende de aritmética
    // nenhuma e marca todas as ocorrências de uma vez. Quem passa a precisar de
    // acordo entre colunas é só a detecção que se apoia SÓ em soma — que é
    // exatamente a que produz coincidência.
    // O acordo é por COLUNA, não por ocorrência — e a diferença é o caso do
    // rótulo REPETIDO. Um comparativo sem `periodo_coluna` traz a mesma conta
    // duas vezes na mesma coluna, e `detectarSubtotaisPorOrdem` colapsa as
    // repetições de propósito (o comentário dele explica por quê), marcando só a
    // primeira. Exigir "todas as ocorrências marcadas" reprovava o subtotal de
    // verdade nesse caso e devolvia a dupla contagem — foi o assert (0109d) que
    // pegou. Uma coluna conta como marcada quando QUALQUER ocorrência dela foi.
    const porRotulo = new Map<string, Map<string, boolean>>();
    const fortePorRotulo = new Map<string, Set<string>>(); // colunas marcadas por (A)/(B)
    const anoDocPorColuna = new Map<string, Map<string, string | null>>(); // k → coluna → ano do documento
    for (const { campo, colKey } of itens) {
      if (alvo !== null && normalizar(colKey.split(CHAVE_SEP)[0] ?? "") !== alvo) continue;
      if (typeof campo.valor_num !== "number") continue;
      const k = `${normalizar(campo.secao_canonica ?? "")}||${normalizar(campo.chave)}`;
      if (!porRotulo.has(k)) porRotulo.set(k, new Map());
      const cols = porRotulo.get(k)!;
      cols.set(colKey, (cols.get(colKey) ?? false) || ids.has(campo.id));
      if (anoDoDocumento) {
        if (!anoDocPorColuna.has(k)) anoDocPorColuna.set(k, new Map());
        const m = anoDocPorColuna.get(k)!;
        const a = anoDoDocumento(campo);
        // dois documentos com anos diferentes na mesma coluna: o ano deixa de ser derivável
        m.set(colKey, m.has(colKey) && m.get(colKey) !== a ? null : a);
      }
      if (idsFortes.has(campo.id)) {
        if (!fortePorRotulo.has(k)) fortePorRotulo.set(k, new Set());
        fortePorRotulo.get(k)!.add(colKey);
      }
    }
    // O VEREDITO É POR EXERCÍCIO.
    //
    // O DEFEITO (Krauspenhar, caso 33b58a89): "Venda de peças e lubrificantes" é CONTA
    // na DRE 2025 (36,19 mi) e NOME DE AGRUPAMENTO, com filhas ("Peças GTS", "Peças
    // Massey"…), no balancete de 2026. O veredito saía por (seção, rótulo) sem exercício:
    // o modelo tirava a linha da soma em TODOS os anos, a receita bruta de 2025 saía
    // 77,19 mi contra 113,38 mi da DRE e os 36,19 mi viravam "reconciliação", constante na
    // projeção. Falso positivo aqui ESCONDE conta (ver acima).
    //
    // A REGRA: a chave devolvida é `seção||rótulo||ano`, e o rótulo só sai da soma NOS
    // EXERCÍCIOS em que ele é subtotal. Uma coluna conta como subtotal quando (A)/(B) — as
    // regras estruturais, que conferem a estrutura declarada e a soma dos irmãos por coluna
    // — a marcam; uma marca que só a coincidência de soma por ordem deu (a célula de 2024
    // do assert 38) continua exigindo o acordo de TODAS as colunas da aba, como antes.
    // Coluna de exercício ilegível (texto livre, vários anos) cai no comportamento antigo:
    // `seção||rótulo` em todos os anos, se todas as colunas da aba marcam.
    for (const [k, cols] of porRotulo) {
      if (cols.size === 0) continue;
      const todasMarcam = [...cols.values()].every(Boolean);
      const fortes = fortePorRotulo.get(k) ?? new Set<string>();
      const efetiva = (colKey: string) => fortes.has(colKey) || (todasMarcam && cols.get(colKey) === true);
      const anos = new Map<string, boolean[]>();
      const anosDocIlegiveis: Array<string | null> = [];
      for (const colKey of cols.keys()) {
        const ano = anoDaColuna(colKey);
        if (ano === null) { anosDocIlegiveis.push(anoDocPorColuna.get(k)?.get(colKey) ?? null); continue; }
        if (!anos.has(ano)) anos.set(ano, []);
        anos.get(ano)!.push(efetiva(colKey));
      }
      // SEM `continue`: as colunas LEGÍVEIS da mesma aba que tem uma ilegível continuam dando o
      // veredito do seu próprio exercício. O `continue` que havia aqui descartava "2024" só
      // porque "jan–jun/25" estava ao lado, e o cabeçalho de grupo declarado nas duas colunas
      // voltava a somar com as filhas (medido: AC operacional 1.500 -> 2.000).
      if (anosDocIlegiveis.length > 0 && todasMarcam) {
        ilegiveisMarcados.set(k, [...(ilegiveisMarcados.get(k) ?? []), ...anosDocIlegiveis]);
      }
      for (const [ano, marcas] of anos) if (marcas.every(Boolean)) rotulos.add(`${k}||${ano}`);
    }
  }
  // COLUNA DE EXERCÍCIO ILEGÍVEL: o veredito sem ano vale para TODOS os exercícios, então só
  // pode sair quando todo exercício legível do mesmo (seção, rótulo) — em QUALQUER aba, a
  // própria inclusive — já foi julgado subtotal. O laço acima julga uma aba por vez: o
  // balancete (aba Combinado, período "jan–ago/26") declara "Estoques" agrupamento e, sendo a
  // única coluna DAQUELA aba, "todas marcam"; o veredito sem ano tirava a conta também dos
  // Balanços de 2024 e 2025 (aba Balanço), onde ela é folha. Medido no Krauspenhar (caso
  // 33b58a89): resíduo de 53,92 mi (2024) e 43,57 mi (2025), 43% do ativo.
  // Havendo exercício legível onde o rótulo é CONTA, o veredito sem ano não sai. Mas o ano do
  // DOCUMENTO do balancete costuma ser legível (referência "2026" ainda que a coluna diga
  // "jan–ago/26"): então o veredito sai SÓ para esse ano, a menos que ele mesmo seja um
  // exercício legível em que o rótulo é conta (aí o balancete e o balanço disputam o ano e
  // nada se decide por aqui). Sem ano derivável, o rótulo fica na soma e o excesso, se houver,
  // tem de aparecer na reconciliação do modelo — nunca por uma conta vizinha sumir calada.
  for (const [k, anosDoc] of ilegiveisMarcados) {
    const legiveis = anosLegiveis.get(k) ?? new Set<string>();
    const contaEmAlgumAno = (a: string) => legiveis.has(a) && !rotulos.has(`${k}||${a}`);
    if (![...legiveis].some(contaEmAlgumAno)) { rotulos.add(k); continue; }
    for (const a of anosDoc) if (a !== null && !contaEmAlgumAno(a)) rotulos.add(`${k}||${a}`);
  }
  return [...rotulos];
}

/** O exercício de uma coluna `entidade<SEP>período`, ou `null` quando o período não
 * deixa ler UM ano só (texto livre, intervalo de vários anos). `null` nunca vira um
 * ano chutado: quem recebe cai na regra antiga, por rótulo. */
function anoDaColuna(colKey: string): string | null {
  const periodo = colKey.includes(CHAVE_SEP) ? colKey.split(CHAVE_SEP).slice(1).join(CHAVE_SEP) : colKey;
  const anos = new Set(periodo.match(/\b(?:19|20)\d{2}\b/g) ?? []);
  return anos.size === 1 ? [...anos][0] : null;
}

// ----- Aba classificada por seção (Balanço/Balancete/DRE/Fluxo/Combinado) --
// Totais/subtotais NÃO são valores estáticos: são FÓRMULAS Excel (=SUM(...)),
// transparentes e recalculáveis, colocadas NO cabeçalho de cada seção/grupo
// (Arquitetura do Sistema/2 Especificação/f0/07 evoluído nesta sessão — pedido do dono). O total que o PRÓPRIO
// documento trouxe (quando existe) aparece numa linha de conferência logo
// abaixo; se a soma calculada divergir do informado, ambos são sinalizados
// (anti-ancoragem: nada que o documento disse é perdido, e divergência vira
// sinal visível — uma checagem de reconciliação embutida).
// Valores NUMÉRICOS por rótulo e coluna, do jeito que a aba os apresenta —
// informado quando o documento informou, soma quando não. É o que a aba
// Modelagem consome para NÃO precisar buscar nada em outra aba por fórmula
// (Etapa 3 do plano do dono).
//
// POR QUE VEM DAQUI e não é recalculado na Modelagem: seriam duas
// implementações da mesma regra ("o total informado manda sobre a soma",
// "subtotal de agrupamento fica fora do SUM", escala normalizada), e elas
// divergiriam. O número que a Modelagem usa passa a ser, por construção, o
// MESMO que a aba mostra.
export type ValoresDaAba = Map<string, Map<string, number>>;

function construirAbaClassificada(
  workbook: ExcelJS.Workbook,
  nomeAba: string,
  estrutura: EstruturaDemonstracao,
  colunas: Coluna[],
  camposDaAba: Array<{ campo: CampoExtraido; colKey: string }>,
  contextoPorVersao: Map<string, ContextoVersao>,
): ValoresDaAba {
  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", xSplit: 1, ySplit: 1 }] });
  // AV% (análise vertical) só faz sentido onde há uma base natural (Ativo Total
  // no Balanço; Receita Líquida na DRE). No Fluxo de Caixa não há base — só Δ%.
  const comAV = estrutura !== "fluxo_caixa";
  const plano = planejarColunas(colunas, comAV);
  const colLetra = (i: number) => sheet.getColumn(plano.valuePos[i]).letter;

  sheet.getColumn(1).width = 46;
  plano.valuePos.forEach((pos) => {
    sheet.getColumn(pos).width = 18;
  });
  plano.avPos.forEach((pos) => {
    if (pos != null) sheet.getColumn(pos).width = 8;
  });
  plano.deltas.forEach((d) => {
    sheet.getColumn(d.pos).width = 12;
  });

  // ----- MOEDA POR COLUNA (Supabase/migrations/0035) -------------------------------
  // Até a 0035 a moeda era extraída e DESCARTADA, e uma linha em USD entrava na
  // mesma soma que uma em BRL sem nenhuma marca: erro pelo câmbio inteiro (~5x),
  // num arquivo que fecha. Agora a moeda chega por linha, e a aba precisa fazer
  // duas coisas com ela — DIZER qual é, e RECUSAR somar o que não é somável.
  //
  // Silencioso de propósito no caso normal: book inteiro em BRL não ganha "(BRL)"
  // em cada cabeçalho, porque rótulo redundante em toda coluna é ruído que ensina
  // a não ler o cabeçalho. A moeda aparece quando ela DISCRIMINA: mais de uma
  // moeda no mesmo arquivo, ou coluna que mistura moedas dentro de si.
  const moedasPorColuna = new Map<string, Set<string>>();
  for (const { campo, colKey } of camposDaAba) {
    const m = campo.moeda?.trim().toUpperCase();
    if (!m) continue; // null = desconhecida; ausência não é uma moeda
    if (!moedasPorColuna.has(colKey)) moedasPorColuna.set(colKey, new Set());
    moedasPorColuna.get(colKey)!.add(m);
  }
  const moedasDaAba = new Set([...moedasPorColuna.values()].flatMap((s) => [...s]));
  const abaMultiMoeda = moedasDaAba.size > 1;
  // Coluna que mistura moedas DENTRO de si é o caso grave: o SUM dela somaria
  // grandezas diferentes célula a célula, e nenhuma inspeção visual pega isso.
  const colunasMistas = new Set(
    [...moedasPorColuna.entries()].filter(([, s]) => s.size > 1).map(([k]) => k),
  );
  const moedaDaColuna = (colKey: string): string | null => {
    const s = moedasPorColuna.get(colKey);
    return s && s.size === 1 ? [...s][0] : null;
  };

  // A RECUSA DE SOMAR, num lugar só.
  //
  // Doutrina do projeto (Arquitetura do Sistema/2 Especificação/04, e o comentário da dupla contagem acima): o
  // export NÃO conserta sozinho — ele mostra as leituras e nomeia o problema. Mas
  // "não consertar" nunca quis dizer "emitir um número errado": uma coluna que
  // mistura BRL e USD não tem soma correta possível, e um `SUM` ali produziria um
  // total que parece bom e está errado pelo câmbio. Então a célula recebe o
  // MOTIVO em vez do número, e a nota diz o que fazer.
  //
  // Só a soma é recusada. Os valores individuais continuam todos na planilha,
  // cada um com a sua moeda no cabeçalho — nada é escondido nem descartado.
  // Devolve `true` quando RECUSOU. Quem chama usa isso para não escrever, em
  // cima da recusa, uma nota que fala de um número que não existe — a nota do
  // "sem total informado" apagava esta e o analista perdia o motivo real.
  const escreverSomaOuRecusa = (
    cell: ExcelJS.Cell, colKey: string, formula: string,
  ): boolean => {
    if (colunasMistas.has(colKey)) {
      // localeCompare('pt-BR'): lista de moedas para nota lida por humano
      // (sonar typescript:S2871 — `.sort()` puro é ordem de código UTF-16).
      const moedas = [...moedasPorColuna.get(colKey)!].sort((a, b) => a.localeCompare(b, "pt-BR")).join(" + ");
      cell.value = "⚠ não somável";
      cell.note = comoNota(
        `Esta coluna traz linhas em MOEDAS DIFERENTES (${moedas}), então nenhuma soma daqui `
        + "seria correta: somar dólar com real erra pelo câmbio inteiro, e o total pareceria "
        + "perfeitamente normal. O total foi OMITIDO de propósito — os valores individuais "
        + "continuam todos abaixo, com a moeda de cada um. Para ter um total, separe o "
        + "documento por moeda ou defina a taxa de conversão e a data-base com o analista.",
      );
      cell.font = { bold: true, color: { argb: "FFB91C1C" } };
      return true;
    }
    cell.value = { formula } as ExcelJS.CellFormulaValue;
    cell.numFmt = VALOR_NUM_FMT;
    return false;
  };

  const headerRow = sheet.getRow(1);
  headerRow.getCell(1).value = "Conta";
  colunas.forEach((col, i) => {
    const cell = headerRow.getCell(plano.valuePos[i]);
    const tipoCol = tipoColunaNaoEntidade(col.entidade);
    const sufixoMoeda = colunasMistas.has(col.key)
      // localeCompare('pt-BR'): mesmo motivo do sufixo de nota acima — texto
      // para humano ler no cabeçalho da coluna (sonar typescript:S2871).
      ? ` (⚠ MOEDAS MISTURADAS: ${[...moedasPorColuna.get(col.key)!].sort((a, b) => a.localeCompare(b, "pt-BR")).join(" + ")} — não somável)`
      : abaMultiMoeda && moedaDaColuna(col.key) ? ` (${moedaDaColuna(col.key)})` : "";
    const sufixo = (tipoCol === "ajuste" ? " (ajuste — não é entidade)"
      : tipoCol === "total" ? " (total do documento — não somar com as demais)" : "")
      + sufixoMoeda;
    cell.value = `${col.entidade} — ${col.periodo}${sufixo}`;
    cell.fill = tipoCol ? ANALISE_HEADER_FILL : HEADER_FILL;
    const av = plano.avPos[i];
    if (av != null) {
      const avCell = headerRow.getCell(av);
      avCell.value = "AV%";
      avCell.fill = ANALISE_HEADER_FILL;
    }
  });
  plano.deltas.forEach((d) => {
    const cell = headerRow.getCell(d.pos);
    cell.value = `Δ% ${colunas[d.anterior].periodo}→${colunas[d.atual].periodo}`;
    cell.fill = ANALISE_HEADER_FILL;
  });
  headerRow.getCell(1).fill = HEADER_FILL;
  headerRow.font = { bold: true };
  headerRow.alignment = { wrapText: true, vertical: "middle" };

  // Classifica cada campo: conta numa seção (bucket), âncora (total que o doc
  // trouxe, por chave de nó), ou não classificado.
  const contasPorSecao = new Map<string, Map<string, GrupoConta>>();
  const valoresPorAncora = new Map<string, GrupoConta>();
  const naoClassificados = new Map<string, GrupoConta>();
  // OCORRÊNCIA da linha dentro do documento, por rótulo.
  //
  // O defeito que isto corrige: agrupar só por rótulo normalizado fazia duas
  // linhas com o MESMO rótulo no mesmo documento virarem UM grupo, e
  // `valorNumDoGrupo` mostrava só a de maior confiança (`melhorCampo`). Num
  // balancete com dois "Outros", duas "Diversos", ou "Fornecedores" repetido em
  // subgrupos diferentes, **linhas desapareciam do arquivo sem aviso** — e a soma
  // da seção saía menor que o documento, o que é a pior versão do problema porque
  // o total parece consistente com o que está visível.
  //
  // A ocorrência é o rank por `ordem` (Supabase/migrations/0027) DENTRO de cada versão
  // e rótulo. Por que dentro da VERSÃO e não do lote: num documento comparativo
  // (2025 | 2024) o mesmo rótulo repetido aparece uma vez por bloco de leitura, e
  // o rank calculado por versão faz a 1ª ocorrência de uma coluna alinhar com a
  // 1ª da outra — que é o alinhamento entidade×período que o agrupamento por
  // rótulo existe para garantir. Rótulo que aparece uma única vez (a esmagadora
  // maioria) tem rank 1 e se comporta exatamente como antes.
  const ocorrenciaDoCampo = new Map<string, number>();
  {
    // A chave leva a COLUNA. O rank existe para dois "Outros" do mesmo balancete
    // não colapsarem numa linha só — e isso só acontece quando os dois disputam a
    // MESMA célula, ou seja, a mesma coluna. Duas ocorrências do mesmo rótulo em
    // colunas diferentes (2025 e 2024) são a mesma conta vista em dois
    // exercícios, e têm de ficar na mesma linha.
    //
    // Sem a coluna na chave, o rank ia 1, 2, 3 para os três exercícios da mesma
    // conta e o export os separava em três linhas — foi o que a rodada v46
    // entregou: "Caixa e bancos conta movimento" em três linhas, cada uma com
    // duas colunas vazias. O comentário deste bloco já dizia que a intenção era
    // "a 1ª ocorrência de uma coluna alinhar com a 1ª da outra"; faltava a
    // coluna na chave para que fosse isso mesmo que acontecesse.
    const porVersaoERotulo = new Map<string, CampoExtraido[]>();
    for (const { campo, colKey } of camposDaAba) {
      const k = `${campo.documento_versao_id}${CHAVE_SEP}${colKey}${CHAVE_SEP}${normalizar(campo.chave)}`;
      if (!porVersaoERotulo.has(k)) porVersaoERotulo.set(k, []);
      porVersaoERotulo.get(k)!.push(campo);
    }
    for (const lista of porVersaoERotulo.values()) {
      if (lista.length === 1) { ocorrenciaDoCampo.set(lista[0].id, 1); continue; }
      // Empate de `ordem` (extração antiga, sem o campo) cai no id para a ordem
      // ser estável entre exportações — arquivo que muda de forma sozinho é o
      // problema que os geradores deste repo já combatem.
      const ordenada = [...lista].sort((a, b) => (a.ordem ?? 0) - (b.ordem ?? 0) || a.id.localeCompare(b.id));
      // Dentro de UMA coluna, cada ocorrência do rótulo é uma linha diferente do
      // documento — é o caso dos dois "Outros" do balancete, e o rank por posição
      // é o que os mantém separados, na ordem de leitura.
      ordenada.forEach((c, i) => ocorrenciaDoCampo.set(c.id, i + 1));
    }
  }

  const bucket = (mapa: Map<string, GrupoConta>, campo: CampoExtraido, colKey: string) => {
    // normalizar() (acento/espaço) para que "Salários" e "Salarios", ou
    // "Duplicatas  a Receber" e "Duplicatas a Receber" (deriva de grafia entre
    // períodos/entidades da mesma empresa), caiam na MESMA linha em vez de
    // gerar dois grupos que quebram o alinhamento entidade×período.
    //
    // …e a OCORRÊNCIA entra na chave, para rótulo repetido não colapsar (acima).
    const ocorrencia = ocorrenciaDoCampo.get(campo.id) ?? 1;
    const chaveNorm = ocorrencia > 1
      ? `${normalizar(campo.chave)}${CHAVE_SEP}#${ocorrencia}`
      : normalizar(campo.chave);
    if (!mapa.has(chaveNorm)) mapa.set(chaveNorm, novoGrupo(campo.chave));
    adicionarAoGrupo(mapa.get(chaveNorm)!, colKey, campo);
  };
  // Subtotais de agrupamento que o documento trouxe (ver
  // `detectarSubtotaisInformados`): ficam FORA da soma da seção — senão o
  // `SUM` conta o subtotal e os seus componentes, dobrando o total.
  // Duas detecções, união dos resultados: a estrutural (rótulo == agrupamento
  // declarado, ou valor == soma dos irmãos) e a por ORDEM DE IMPRESSÃO, que é a
  // única que pega o caso em que a extração anotou a seção de topo em todas as
  // linhas e o documento não trouxe linha de total.
  const idsSubtotal = new Set([
    ...detectarSubtotaisInformados(camposDaAba),
    ...detectarSubtotaisPorOrdem(camposDaAba),
  ]);
  const subtotaisInformados = new Map<string, Map<string, GrupoConta>>(); // secaoKey → grupos

  // Classificação de cada linha, em DOIS passes.
  //
  // Passe 1: a regra de sempre (âncora / seção / palavra-chave / sugestão da IA).
  //
  // Passe 2 — CONSENSO DE IRMÃOS: demonstrações reais são hierárquicas, e a
  // `secao` que a IA anota costuma ser o nome da SUBSEÇÃO ("Estoques",
  // "Disponível", "Outras Obrigações"), que não carrega sinal de Ativo/Passivo.
  // Resultado (achado no teste v24): uma conta com vocabulário fora das listas
  // — "(-) PECLD", "Produtos em elaboração" — caía em "Contas Não
  // Classificadas" mesmo estando declaradamente sob "Estoques", e a soma da
  // seção ficava furada. Aqui a linha herda a seção dos IRMÃOS: se as outras
  // linhas do MESMO agrupamento foram classificadas, e de forma unânime, esta
  // vai para o mesmo lugar. É como um humano lê a demonstração ("está sob
  // Estoques, e o resto de Estoques é Ativo Circulante"), não depende de
  // vocabulário novo, e permanece conservador: sem irmãos classificados ou com
  // irmãos divergentes, a linha continua em "Não Classificadas".
  type Item = { campo: CampoExtraido; colKey: string };
  const classificado = new Map<string, { secaoKey: string | null; ancoraKey: string | null }>();
  const semClassificacao: Item[] = [];
  for (const item of camposDaAba) {
    const { campo } = item;
    if (campo.valor_num == null && campo.valor_texto == null) continue;
    const r = classificarConta(estrutura, campo.secao, campo.chave, campo.secao_canonica);
    classificado.set(campo.id, r);
    if (!r.secaoKey && !r.ancoraKey) semClassificacao.push(item);
  }
  if (semClassificacao.length > 0) {
    const consensoPorSecao = new Map<string, Set<string>>();
    for (const { campo } of camposDaAba) {
      const sec = normalizar(campo.secao ?? "");
      const r = classificado.get(campo.id);
      if (!sec || !r?.secaoKey) continue;
      if (!consensoPorSecao.has(sec)) consensoPorSecao.set(sec, new Set());
      consensoPorSecao.get(sec)!.add(r.secaoKey);
    }
    for (const { campo } of semClassificacao) {
      const sec = normalizar(campo.secao ?? "");
      const candidatas = sec ? consensoPorSecao.get(sec) : undefined;
      if (candidatas && candidatas.size === 1) {
        classificado.set(campo.id, { secaoKey: [...candidatas][0], ancoraKey: null });
      }
    }
  }

  for (const { campo, colKey } of camposDaAba) {
    if (campo.valor_num == null && campo.valor_texto == null) continue;
    const { secaoKey, ancoraKey } = classificado.get(campo.id) ?? { secaoKey: null, ancoraKey: null };
    if (ancoraKey) {
      if (!valoresPorAncora.has(ancoraKey)) valoresPorAncora.set(ancoraKey, novoGrupo(campo.chave));
      adicionarAoGrupo(valoresPorAncora.get(ancoraKey)!, colKey, campo);
    } else if (secaoKey && idsSubtotal.has(campo.id)) {
      if (!subtotaisInformados.has(secaoKey)) subtotaisInformados.set(secaoKey, new Map());
      bucket(subtotaisInformados.get(secaoKey)!, campo, colKey);
    } else if (secaoKey) {
      if (!contasPorSecao.has(secaoKey)) contasPorSecao.set(secaoKey, new Map());
      bucket(contasPorSecao.get(secaoKey)!, campo, colKey);
    } else {
      bucket(naoClassificados, campo, colKey);
    }
  }

  let rowIndex = 2;
  // Linhas monetárias elegíveis a AV%/Δ% (contas + subtotais + âncoras);
  // exclui cabeçalhos de seção sem valor, linhas de conferência e margens.
  const linhasValor = new Set<number>();
  // Balanço: nó da estrutura → linha do seu subtotal (para os indicadores).
  const noRow = new Map<string, number>();
  // …e o VALOR do nó por coluna, para os indicadores só emitirem índice que
  // realmente resolve (fórmula existir não basta: os insumos podem estar
  // vazios ou o denominador zerado, e o índice sairia como linha vazia).
  const noValor = new Map<string, Map<string, number>>();
  let baseTotalRow: number | null = null; // base da AV% (Ativo Total / Receita Líquida)

  // Coletor dos valores por rótulo — ver `ValoresDaAba`.
  const valoresDaAba: ValoresDaAba = new Map();
  const registrarValores = (rotulo: string, valores: Map<string, number>) => {
    if (valores.size === 0) return;
    const alvo = valoresDaAba.get(rotulo) ?? new Map<string, number>();
    for (const [k, v] of valores) alvo.set(k, v);
    valoresDaAba.set(rotulo, alvo);
  };

  const escrever = (label: string, nivel: number, grupo: GrupoConta, opts: { negrito?: boolean; borda?: "simples" | "dupla" } = {}) => {
    const r = rowIndex++;
    escreverLinhaConta(sheet, r, label, nivel, colunas, plano.valuePos, grupo, opts, contextoPorVersao);
    linhasValor.add(r);
    return r;
  };

  // Subtotais de agrupamento que o documento trouxe: emitidos DEPOIS do range
  // do SUM (portanto fora da soma) e com estilo próprio, para o analista ver o
  // que o documento declarou sem que isso dobre o total.
  const escreverSubtotaisInformados = (secaoKey: string, nivel: number) => {
    const grupos = subtotaisInformados.get(secaoKey);
    if (!grupos) return;
    for (const g of grupos.values()) {
      const r = rowIndex++;
      const row = sheet.getRow(r);
      row.getCell(1).value = `↳ subtotal informado: ${g.label}`;
      row.getCell(1).alignment = { indent: nivel + 1 };
      row.getCell(1).font = SUBTOTAL_INFO_FONT;
      row.getCell(1).note = comoNota(
        "Subtotal de agrupamento trazido pelo próprio documento. Fica FORA da soma da seção de "
        + "propósito: somá-lo junto com as contas que ele agrega dobraria o total.",
      );
      colunas.forEach((col, i) => {
        const cell = row.getCell(plano.valuePos[i]);
        const v = valorNumDoGrupo(g, col.key);
        if (v == null) return;
        cell.value = v;
        cell.numFmt = VALOR_NUM_FMT;
        cell.font = SUBTOTAL_INFO_FONT;
      });
      linhasValor.add(r);
    }
  };

  // Células de cabeçalho a pintar DEPOIS que toda a aba foi emitida. Cabeçalho
  // de seção é linha reservada e preenchida no fim, com `row.fill = …`, que no
  // ExcelJS repinta a linha inteira: qualquer destaque aplicado antes disso é
  // silenciosamente apagado. Adiar é a única forma de o destaque sobreviver.
  const pintarNoFim: Array<[number, number]> = [];

  // Linha de conferência: o total que o DOCUMENTO trouxe (extraído), logo
  // abaixo do cabeçalho. Se divergir do subtotal calculado, pinta ambas as
  // células e anota o motivo (checagem de reconciliação embutida).
  // Devolve o índice da linha, para o cabeçalho poder apontar para ela.
  const escreverConferenciaExtraido = (nivel: number, ancoraKey: string, cabecalhoIdx: number, subtotalNum: Map<string, number>): number | null => {
    const grupo = valoresPorAncora.get(ancoraKey);
    if (!grupo) return null;
    const idx = rowIndex++;
    const row = sheet.getRow(idx);
    row.getCell(1).value = "↳ total informado no documento";
    row.getCell(1).alignment = { indent: nivel + 1 };
    row.getCell(1).font = { italic: true, size: 9, color: { argb: "FF6B7280" } };
    colunas.forEach((col, i) => {
      const cell = row.getCell(plano.valuePos[i]);
      const vExtraido = valorNumDoGrupo(grupo, col.key);
      if (vExtraido == null) return;
      cell.value = vExtraido;
      cell.numFmt = VALOR_NUM_FMT;
      cell.font = { italic: true, size: 9, color: { argb: "FF6B7280" } };
      const vCalc = subtotalNum.get(col.key);
      if (vCalc != null && Math.abs(vCalc - vExtraido) > Math.max(0.01, Math.abs(vExtraido) * 0.005)) {
        cell.fill = DIVERGENCIA_FILL;
        cell.note = comoNota(
          `Divergência: soma das contas listadas = ${vCalc.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}, `
          + `informado no documento = ${vExtraido.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}. `
          + `Duas causas possíveis, e elas pedem conferências diferentes. (1) O documento imprime `
          + `subtotais intermediários (ex.: "Disponível" acima de "Caixa e bancos" + "Aplicações") e a `
          + `soma conta o subtotal E os seus componentes — aí o informado é o certo. (2) Uma conta desta `
          + `seção foi classificada em OUTRA seção: o informado a inclui, a soma listada não, e o TOTAL `
          + `DO GRUPO passa a contá-la duas vezes. Achado real no teste v33: "Ferramental e moldes" `
          + `(3.600) caiu em "Outros Ativos Não Circulantes" enquanto o total do Imobilizado já a `
          + `continha. Se a diferença bater com uma conta que aparece em outra seção, é o caso (2).`,
        );
        // Sinaliza também a célula do CABEÇALHO — quem lê só a linha do total
        // precisa ver que ela está sob suspeita, sem rolar até a conferência.
        //
        // ADIADA DE PROPÓSITO, e é correção de um defeito medido nesta sessão:
        // esta linha existia aqui e NÃO PINTAVA NADA. O cabeçalho é uma linha
        // RESERVADA (`cabIdx = rowIndex++`) e só é preenchida depois que as
        // contas e as conferências foram escritas — e o preenchimento faz
        // `row.fill = fill`, que no ExcelJS repinta a linha INTEIRA e apagava
        // este destaque. Medido no arranjo do v33: o Imobilizado divergia
        // 1.990 × 5.590 e o cabeçalho dele saía com o cinza normal de seção.
        pintarNoFim.push([cabecalhoIdx, plano.valuePos[i]]);
      }
    });
    return idx;
  };

  // Linha "soma das contas listadas": a fórmula =SUM(range) sai do cabeçalho e
  // vem para cá quando o documento informou o total da seção.
  //
  // Por quê: demonstração real é hierárquica e imprime subtotais de subseção.
  // Somar as contas listadas conta o subtotal E os seus componentes — dobra o
  // total. Detectar o subtotal pela estrutura (`detectarSubtotaisInformados`)
  // resolve quando a IA anota a SUBSEÇÃO em `secao`; quando ela anota a seção de
  // topo, o subtotal impresso passa e a soma sai 2x (achado no teste v25: 36 de
  // 44 somas do Balanço divergiam, várias exatamente 2,00x).
  //
  // Então o número da seção deixa de depender de acertarmos a hierarquia: quando
  // o documento diz quanto é, o cabeçalho aponta para o que ele disse, e a nossa
  // soma vira uma LINHA DE CHECAGEM ao lado. Nada é escondido — a divergência
  // fica visível e pintada, que é o sinal útil — e AV%, Δ% e indicadores passam a
  // usar o número autoritativo em vez de um que pode estar dobrado.
  const escreverSomaCalculada = (nivel: number, rotulo: string, formulaDaColuna: (i: number) => string) => {
    const idx = rowIndex++;
    const row = sheet.getRow(idx);
    row.getCell(1).value = `↳ ${rotulo} (checagem)`;
    row.getCell(1).alignment = { indent: nivel + 1 };
    row.getCell(1).font = { italic: true, size: 9, color: { argb: "FF6B7280" } };
    row.getCell(1).note = comoNota(
      "Soma calculada por nós, para conferir contra o total que o documento informou (linha acima). "
      + "Quando as duas divergem, quase sempre é porque o documento traz subtotais intermediários, "
      + "que a soma conta duas vezes — por isso o valor da seção segue o informado, não esta soma.",
    );
    colunas.forEach((col, i) => {
      const cell = row.getCell(plano.valuePos[i]);
      cell.value = { formula: formulaDaColuna(i) } as ExcelJS.CellFormulaValue;
      cell.numFmt = VALOR_NUM_FMT;
      cell.font = { italic: true, size: 9, color: { argb: "FF6B7280" } };
    });
    return idx;
  };

  if (estrutura === "balanco") {
    const outline = new Map(BALANCO_OUTLINE.map((n) => [n.key, n]));

    // ---- DUPLA CONTAGEM NO TOTAL DO GRUPO ----------------------------------
    //
    // O DEFEITO, com o número do teste v33. No Balanço da Componentes o
    // Imobilizado é 14.200 + 3.600 + 890 − 13.100 = 5.590, e o documento
    // IMPRIME esse 5.590. A extração anotou "Ferramental e moldes" (3.600) com
    // a seção de TOPO ("Ativo Não Circulante") em vez da subseção, então a
    // conta caiu em "Outros Ativos Não Circulantes" — uma seção IRMÃ do
    // Imobilizado. Resultado: o total do Imobilizado (que já a contém) entra
    // inteiro no grupo, e o Ferramental entra DE NOVO pela seção irmã. O Ativo
    // Não Circulante fica 3.600 maior, e nada acusava.
    //
    // POR QUE A DIVERGÊNCIA QUE JÁ EXISTIA NÃO BASTAVA. Cada seção já compara
    // "total informado" × "soma das contas listadas". No arranjo acima, o
    // Imobilizado acusa (1.990 × 5.590) — mas essa divergência tem DUAS causas
    // possíveis (subtotal intermediário contado duas vezes, ou conta exilada
    // numa seção irmã), e a nota pedia ao humano que fizesse o casamento.
    // Ninguém faz esse casamento à mão em 44 seções. Pior: quando o grupo NÃO
    // tem total informado, o cabeçalho dele é a SOMA dos filhos — o número sai
    // inflado e não existe nenhuma linha para comparar.
    //
    // O SINAL, que não depende do grupo ter total informado: uma seção-folha
    // cujo total informado EXCEDE a soma das suas próprias contas em D, e uma
    // seção IRMÃ que tem uma conta valendo exatamente D. É a assinatura de uma
    // conta que ficou do lado de fora da seção que a soma por dentro.
    //
    // NÃO CORRIGE SOZINHO — e isso é doutrina (Arquitetura do Sistema/2 Especificação/04), não cautela. As duas
    // leituras vão para a planilha nomeadas, e quem decide é quem audita:
    // reclassificar automaticamente uma conta com base numa coincidência de
    // valor moveria dinheiro de seção sem que ninguém tivesse visto.
    const folhasSob = (chave: string): string[] => {
      const n = outline.get(chave);
      if (!n) return [];
      return n.folha ? [chave] : (n.filhos ?? []).flatMap(folhasSob);
    };
    const somaDasContas = (secaoKey: string, colKey: string): number | null => {
      const grupos = contasPorSecao.get(secaoKey);
      if (!grupos) return null;
      let total = 0;
      let achou = false;
      for (const g of grupos.values()) {
        const v = valorNumDoGrupo(g, colKey);
        if (v != null) { total += v; achou = true; }
      }
      return achou ? total : null;
    };
    type Suspeita = {
      colKey: string; folhaLabel: string; informado: number; soma: number; diff: number;
      contaLabel: string; contaSecaoLabel: string; contaValor: number;
    };
    const suspeitasDoGrupo = (no: (typeof BALANCO_OUTLINE)[number]): Suspeita[] => {
      const achados: Suspeita[] = [];
      // Só olha pares que estão em FILHOS DIFERENTES deste nó. Sem isso, o
      // "ATIVO" reportaria de novo o que o "Ativo Não Circulante" já reportou
      // — o mesmo achado duas vezes ensina o leitor a ignorar o aviso.
      const porFilho = (no.filhos ?? []).map((f) => folhasSob(f));
      for (let a = 0; a < porFilho.length; a++) {
        for (const folha of porFilho[a]) {
          const ancora = valoresPorAncora.get(folha);
          if (!ancora) continue;
          const labelFolha = outline.get(folha)?.label ?? folha;
          for (const col of colunas) {
            const informado = valorNumDoGrupo(ancora, col.key);
            if (informado == null) continue;
            const soma = somaDasContas(folha, col.key);
            if (soma == null) continue;
            const diff = informado - soma;
            const tol = Math.max(0.01, Math.abs(informado) * 0.005);
            if (diff <= tol) continue;   // informado ≤ soma: outro problema, não este
            for (let b = 0; b < porFilho.length; b++) {
              if (b === a) continue;
              for (const irma of porFilho[b]) {
                for (const g of contasPorSecao.get(irma)?.values() ?? []) {
                  const v = valorNumDoGrupo(g, col.key);
                  if (v == null) continue;
                  if (Math.abs(v - diff) > tol) continue;
                  achados.push({
                    colKey: col.key, folhaLabel: labelFolha, informado, soma, diff,
                    contaLabel: g.label, contaValor: v,
                    contaSecaoLabel: outline.get(irma)?.label ?? irma,
                  });
                }
              }
            }
          }
        }
      }
      return achados;
    };
    const escreverSuspeitasDuplaContagem = (
      no: (typeof BALANCO_OUTLINE)[number], nivel: number, cabecalhoIdx: number,
    ) => {
      const achados = suspeitasDoGrupo(no);
      if (achados.length === 0) return;
      // Uma linha por conta suspeita (a mesma conta pode bater em várias
      // colunas/exercícios; o aviso é sobre a CONTA, não sobre a célula).
      const porConta = new Map<string, Suspeita[]>();
      for (const s of achados) {
        const k = `${s.contaSecaoLabel}\u0000${s.contaLabel}\u0000${s.folhaLabel}`;
        if (!porConta.has(k)) porConta.set(k, []);
        porConta.get(k)!.push(s);
      }
      for (const grupo of porConta.values()) {
        const s0 = grupo[0];
        const idx = rowIndex++;
        const row = sheet.getRow(idx);
        row.getCell(1).value =
          `⚠ possível DUPLA CONTAGEM: "${s0.contaLabel}" está em ${s0.contaSecaoLabel}, e o total `
          + `informado de ${s0.folhaLabel} parece já incluí-la — ${no.label} pode estar contando-a duas vezes`;
        row.getCell(1).alignment = { indent: nivel + 1, wrapText: true, vertical: "top" };
        row.getCell(1).font = { bold: true, size: 9, color: { argb: "FF991B1B" } };
        row.getCell(1).fill = DIVERGENCIA_FILL;
        row.getCell(1).note = comoNota(
          `AS DUAS LEITURAS, para você escolher — o export NÃO escolhe.\n\n`
          + `LEITURA A (o documento está certo e a classificação errou): "${s0.contaLabel}" pertence a `
          + `${s0.folhaLabel}. O total informado de ${s0.folhaLabel} já a inclui, e a conta aparecer em `
          + `${s0.contaSecaoLabel} faz ${no.label} somá-la de novo. Nesse caso ${no.label} está `
          + `INFLADO no valor dela e a correção é reclassificar a conta.\n\n`
          + `LEITURA B (a coincidência é coincidência): a diferença de ${s0.folhaLabel} vem de outra `
          + `causa — subtotal intermediário, conta não extraída, arredondamento — e "${s0.contaLabel}" `
          + `está no lugar certo. Nesse caso não há nada a corrigir aqui.\n\n`
          + `O QUE FOI MEDIDO: total informado de ${s0.folhaLabel} = `
          + `${s0.informado.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}; `
          + `soma das contas listadas nele = `
          + `${s0.soma.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}; `
          + `diferença = `
          + `${s0.diff.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}, `
          + `que é exatamente o valor de "${s0.contaLabel}" em ${s0.contaSecaoLabel}.\n\n`
          + `ACHADO REAL (teste v33): "Ferramental e moldes" (3.600) caiu em "Outros Ativos Não `
          + `Circulantes" enquanto o Imobilizado informado (5.590) já a continha — o Ativo Não `
          + `Circulante saiu 3.600 maior e nada acusava.`,
        );
        // Pinta a coluna/exercício onde bateu, e o cabeçalho do grupo: quem lê a
        // linha do total precisa ver que ela está sob suspeita, sem depender de
        // ter rolado até aqui.
        for (const s of grupo) {
          const i = colunas.findIndex((c) => c.key === s.colKey);
          if (i < 0) continue;
          const cell = row.getCell(plano.valuePos[i]);
          cell.value = s.diff;
          cell.numFmt = VALOR_NUM_FMT;
          cell.fill = DIVERGENCIA_FILL;
          cell.font = { bold: true, size: 9, color: { argb: "FF991B1B" } };
          pintarNoFim.push([cabecalhoIdx, plano.valuePos[i]]);
        }
      }
    };

    // Emite um nó (recursivo): cabeçalho com fórmula (soma das contas-folha ou
    // dos subtotais dos filhos), contas indentadas, conferência do extraído.
    // Retorna { idx, subtotalNum } para o pai somar.
    const emitirNo = (chave: string): { idx: number; subtotalNum: Map<string, number> } | null => {
      const no = outline.get(chave)!;
      const fill = no.papel === "subsecao" ? SECAO_FILL : HEADER_FILL;
      const subtotalNum = new Map<string, number>();

      if (no.folha) {
        const contas = [...(contasPorSecao.get(no.key)?.values() ?? [])];
        const temAncora = valoresPorAncora.has(no.key);
        // Seção SEM NENHUM DADO não é emitida — em nenhum nível. O template
        // canônico (CPC 26 / art. 178) existe para ORDENAR o que o documento
        // trouxe, não para impor linhas que o documento não tem: antes, uma
        // empresa sem Realizável LP nem Intangível ganhava linhas de subgrupo em
        // branco, e uma sem Passivo Não Circulante ganhava um "0" que nós
        // inventamos (o documento não disse zero — não disse nada).
        if (contas.length === 0 && !temAncora) return null;
        // reserva o cabeçalho; escreve as contas; depois preenche a fórmula.
        const cabIdx = rowIndex++;
        const primeira = rowIndex;
        for (const conta of contas) {
          escrever(conta.label, no.nivel + 1, conta);
          colunas.forEach((col) => {
            const v = valorNumDoGrupo(conta, col.key);
            if (v != null) subtotalNum.set(col.key, (subtotalNum.get(col.key) ?? 0) + v);
          });
        }
        const ultima = rowIndex - 1;
        const temContas = ultima >= primeira;
        escreverSubtotaisInformados(no.key, no.nivel + 1);
        // Quando o documento informou o total desta seção, ELE é o número da
        // seção; a nossa soma vai para uma linha de checagem logo abaixo (ver
        // `escreverSomaCalculada`). Isso torna o total, a AV%, o Δ% e os
        // indicadores imunes a subtotal de subseção contado duas vezes.
        const informadoIdx = temAncora
          ? escreverConferenciaExtraido(no.nivel, no.key, cabIdx, temContas ? subtotalNum : new Map())
          : null;
        if (temAncora && temContas && informadoIdx != null) {
          escreverSomaCalculada(no.nivel, "soma das contas listadas",
            (i) => `SUM(${colLetra(i)}${primeira}:${colLetra(i)}${ultima})`);
        }
        const grupoAncora = temAncora ? valoresPorAncora.get(no.key)! : null;
        const row = sheet.getRow(cabIdx);
        row.getCell(1).value = no.label;
        row.getCell(1).alignment = { indent: no.nivel };
        row.font = { bold: true };
        row.fill = fill;
        colunas.forEach((col, i) => {
          const cell = row.getCell(plano.valuePos[i]);
          cell.font = { bold: true };
          const vInformado = grupoAncora ? valorNumDoGrupo(grupoAncora, col.key) : null;
          if (vInformado != null && informadoIdx != null) {
            // O documento disse quanto é: o cabeçalho APONTA para a célula do
            // valor extraído (fórmula, não valor colado — a planilha continua
            // viva e a proveniência fica a um clique).
            cell.value = { formula: `${colLetra(i)}${informadoIdx}` } as ExcelJS.CellFormulaValue;
            cell.numFmt = VALOR_NUM_FMT;
            subtotalNum.set(col.key, vInformado);
          } else if (temContas) {
            // O documento não trouxe o total desta coluna: soma as contas-folha.
            const recusou = escreverSomaOuRecusa(cell, col.key, `SUM(${colLetra(i)}${primeira}:${colLetra(i)}${ultima})`);
            // …e ISSO PRECISA APARECER. Sem total informado não existe checagem:
            // se o documento imprime subtotal de agrupamento e a extração anotou
            // a seção de TOPO em `secao` (em vez da subseção), a soma conta o
            // subtotal E os componentes, e ninguém tem contra o que comparar.
            // Aconteceu no teste v28: a VT Logística saiu com Ativo Circulante
            // 7.254 onde o documento diz 3.961 — "Contas a Receber" (3.293)
            // somada junto com "Fretes a receber" (3.562) e "(-) PECLD" (−269),
            // que são os componentes dela. Marcar não conserta o número; impede
            // que ele passe por conferido.
            cell.font = { bold: true, italic: true };
            // A recusa por moeda misturada já explicou a célula; sobrescrever a
            // nota aqui trocaria o motivo REAL por um aviso sobre um número que
            // nem foi emitido.
            if (!recusou) cell.note = comoNota(
              `Sem total informado no documento para esta coluna: o número é a NOSSA soma das contas `
              + `listadas (${no.label}), não um valor que o documento tenha impresso. `
              + `Se o original traz subtotais de agrupamento (ex.: "Contas a Receber" acima das duplicatas), `
              + `confira dupla contagem antes de usar — a soma pode incluir o subtotal E os componentes dele.`,
            );
          }
        });
        noRow.set(no.key, cabIdx);
        noValor.set(no.key, new Map(subtotalNum));
        registrarValores(no.label, subtotalNum);
        linhasValor.add(cabIdx);
        return { idx: cabIdx, subtotalNum };
      }

      // nó pai: cabeçalho reservado, emite filhos (pula os vazios), soma os
      // cabeçalhos deles.
      const cabIdx = rowIndex++;
      const filhosIdx: number[] = [];
      for (const filho of no.filhos ?? []) {
        const r = emitirNo(filho);
        if (!r) continue;
        filhosIdx.push(r.idx);
        colunas.forEach((col) => {
          const v = r.subtotalNum.get(col.key);
          if (v != null) subtotalNum.set(col.key, (subtotalNum.get(col.key) ?? 0) + v);
        });
      }
      // Grupo sem nenhum filho com dado e sem total informado: não existe neste
      // documento. Devolve a linha reservada ao pool e não emite nada.
      const temAncoraPai = valoresPorAncora.has(no.key);
      if (filhosIdx.length === 0 && !temAncoraPai) {
        if (cabIdx === rowIndex - 1) rowIndex--; // nada foi escrito depois: reaproveita
        return null;
      }
      // Mesma regra do nó folha: o total que o documento informou manda, e a
      // soma dos filhos vira linha de checagem.
      const informadoPaiIdx = temAncoraPai
        ? escreverConferenciaExtraido(no.nivel, no.key, cabIdx, subtotalNum)
        : null;
      if (temAncoraPai && filhosIdx.length && informadoPaiIdx != null) {
        escreverSomaCalculada(no.nivel, "soma das seções acima",
          (i) => filhosIdx.map((r) => `${colLetra(i)}${r}`).join("+"));
      }
      // Depois das linhas de conferência e ANTES de preencher o cabeçalho: o
      // aviso precisa existir mesmo quando o grupo NÃO tem total informado —
      // que é justamente o caso em que o cabeçalho vira a soma dos filhos e o
      // número sai inflado sem nada para comparar.
      escreverSuspeitasDuplaContagem(no, no.nivel, cabIdx);
      const grupoAncoraPai = temAncoraPai ? valoresPorAncora.get(no.key)! : null;
      const row = sheet.getRow(cabIdx);
      row.getCell(1).value = no.label;
      row.getCell(1).alignment = { indent: no.nivel };
      row.font = { bold: true };
      row.fill = fill;
      const dupla = no.papel === "grupo";
      colunas.forEach((col, i) => {
        const cell = row.getCell(plano.valuePos[i]);
        cell.font = { bold: true };
        const vInformado = grupoAncoraPai ? valorNumDoGrupo(grupoAncoraPai, col.key) : null;
        if (vInformado != null && informadoPaiIdx != null) {
          cell.value = { formula: `${colLetra(i)}${informadoPaiIdx}` } as ExcelJS.CellFormulaValue;
          cell.numFmt = VALOR_NUM_FMT;
          subtotalNum.set(col.key, vInformado);
        } else if (filhosIdx.length) {
          cell.value = { formula: filhosIdx.map((r) => `${colLetra(i)}${r}`).join("+") } as ExcelJS.CellFormulaValue;
          cell.numFmt = VALOR_NUM_FMT;
        }
        if (dupla) cell.border = DOUBLE_TOP_BORDER;
      });
      noRow.set(no.key, cabIdx);
      noValor.set(no.key, new Map(subtotalNum));
      registrarValores(no.label, subtotalNum);
      linhasValor.add(cabIdx);
      return { idx: cabIdx, subtotalNum };
    };

    for (const raiz of BALANCO_OUTLINE.filter((n) => n.nivel === 0)) emitirNo(raiz.key);
    baseTotalRow = noRow.get("ATIVO") ?? null;
  } else {
    // Layout sequencial (DRE / Fluxo de Caixa): seção → contas → subtotal
    // (âncora). Subtotal é FÓRMULA: DRE é cascata cumulativa (cada subtotal =
    // soma de TODAS as contas da demonstração até ali — deduções/custos/
    // despesas entram negativos, então a soma corrida dá o resultado); Fluxo
    // é soma da própria seção, com variação/saldo final derivados.
    const secoes = secoesDe(estrutura);
    const ancoras = ancorasDe(estrutura);
    const idxAncora = new Map<string, number>();
    const subtotalAncora = new Map<string, Map<string, number>>();
    let dreAncoraAnteriorIdx: number | null = null; // DRE: célula do subtotal anterior (cascata)
    const dreAcumulado = new Map<string, number>(); // DRE: subtotal numérico corrido

    for (const secao of secoes) {
      const contas = [...(contasPorSecao.get(secao.key)?.values() ?? [])];
      const temSubtotalInformado = (subtotaisInformados.get(secao.key)?.size ?? 0) > 0;
      // Seção que o documento não tem: não é emitida. O template canônico ordena
      // o que existe, não impõe blocos vazios.
      if (contas.length === 0 && !temSubtotalInformado) continue;

      // O cabeçalho da seção CARREGA O SUBTOTAL DA SEÇÃO, não só o rótulo.
      // Antes era linha só de texto — 8 linhas 100% vazias entre DRE e Fluxo de
      // Caixa ("Custos", "Despesas Operacionais", "Atividades Operacionais"…).
      // E o número é o que uma DRE real imprime: o total de custos e o total de
      // despesas operacionais são leitura de primeira ordem, distinta da cascata
      // acumulada que a âncora abaixo mostra.
      const cabIdx = rowIndex++;
      const primeira = rowIndex;
      const somaSecao = new Map<string, number>();
      for (const conta of contas) {
        escrever(conta.label, 1, conta);
        colunas.forEach((col) => {
          const v = valorNumDoGrupo(conta, col.key);
          if (v != null) somaSecao.set(col.key, (somaSecao.get(col.key) ?? 0) + v);
        });
      }
      const ultima = rowIndex - 1;
      escreverSubtotaisInformados(secao.key, 1);

      const hdr = sheet.getRow(cabIdx);
      hdr.getCell(1).value = secao.label;
      hdr.getCell(1).alignment = { indent: 0 };
      hdr.font = { bold: true };
      hdr.fill = SECAO_FILL;
      if (ultima >= primeira) {
        hdr.getCell(1).note = comoNota(
          "Total desta seção — soma das contas listadas abaixo. Não confundir com a linha de "
          + "resultado que vem depois: na DRE ela é cumulativa (traz o resultado acumulado até "
          + "ali), esta é só do bloco.",
        );
        colunas.forEach((col, i) => {
          if (somaSecao.get(col.key) == null) return;
          const cell = hdr.getCell(plano.valuePos[i]);
          escreverSomaOuRecusa(cell, col.key, `SUM(${colLetra(i)}${primeira}:${colLetra(i)}${ultima})`);
          cell.font = { bold: true };
        });
        linhasValor.add(cabIdx);
      }
      const ancoraSecao = ancoras.find((a) => "aposSecao" in a && (a as { aposSecao: string }).aposSecao === secao.key);
      if (ancoraSecao) {
        const idx = rowIndex++;
        const subtotalNum = new Map<string, number>();
        const row = sheet.getRow(idx);
        row.getCell(1).value = ancoraSecao.label;
        row.getCell(1).font = { bold: true };
        colunas.forEach((col, i) => {
          const cell = row.getCell(plano.valuePos[i]);
          cell.font = { bold: true };
          cell.border = THIN_TOP_BORDER;
          let formula: string | null = null;
          const somaSecaoFormula = ultima >= primeira ? `SUM(${colLetra(i)}${primeira}:${colLetra(i)}${ultima})` : null;
          if (estrutura === "dre") {
            // CASCATA: subtotal = subtotal anterior + soma das contas DESTA
            // seção (deduções/custos/despesas entram negativos). Referencia a
            // célula da âncora anterior — nunca re-soma linhas de subtotal já
            // escritas (evita dupla contagem).
            const prev = dreAncoraAnteriorIdx != null ? `${colLetra(i)}${dreAncoraAnteriorIdx}` : null;
            formula = prev && somaSecaoFormula ? `${prev}+${somaSecaoFormula}` : (prev ?? somaSecaoFormula);
            const acc = (dreAcumulado.get(col.key) ?? 0) + (somaSecao.get(col.key) ?? 0);
            dreAcumulado.set(col.key, acc);
            subtotalNum.set(col.key, acc);
          } else {
            // Fluxo: soma da própria seção
            formula = somaSecaoFormula;
            subtotalNum.set(col.key, somaSecao.get(col.key) ?? 0);
          }
          if (formula) {
            escreverSomaOuRecusa(cell, col.key, formula);
          }
        });
        idxAncora.set(ancoraSecao.key, idx);
        subtotalAncora.set(ancoraSecao.key, subtotalNum);
        registrarValores(ancoraSecao.label, subtotalNum);
        linhasValor.add(idx);
        if (estrutura === "dre") dreAncoraAnteriorIdx = idx;
        if (valoresPorAncora.has(ancoraSecao.key)) escreverConferenciaExtraido(0, ancoraSecao.key, idx, subtotalNum);

        // Linha analítica de MARGEM (% da Receita Líquida) — estilo FP&A
        // (referência DelendSummary): Margem Bruta / Operacional / Líquida.
        // Fórmula por coluna (IFERROR evita divisão por zero); não projeta
        // nada, só divide dois valores já extraídos. EBITDA fica de fora aqui
        // porque a DRE não traz Depreciação/Amortização como linha isolada
        // (viria das notas/Fluxo) — não inventamos.
        const rlIdx = idxAncora.get("receita_liquida");
        if (estrutura === "dre" && rlIdx && ancoraSecao.key in MARGEM_LABEL) {
          const mIdx = rowIndex++;
          const mrow = sheet.getRow(mIdx);
          mrow.getCell(1).value = MARGEM_LABEL[ancoraSecao.key];
          mrow.getCell(1).alignment = { indent: 1 };
          mrow.getCell(1).font = MARGEM_FONT;
          colunas.forEach((col, i) => {
            const cell = mrow.getCell(plano.valuePos[i]);
            cell.value = { formula: `IFERROR(${colLetra(i)}${idx}/${colLetra(i)}${rlIdx},"")` } as ExcelJS.CellFormulaValue;
            cell.numFmt = "0.0%";
            cell.font = MARGEM_FONT;
          });
        }
      }
    }
    if (estrutura === "dre") baseTotalRow = idxAncora.get("receita_liquida") ?? null;

    // Âncoras "livres" (não presas a uma seção): Fluxo de Caixa —
    // variação líquida = soma dos 3 caixas líquidos; saldo final = saldo
    // inicial + variação; saldo inicial = só o que o documento trouxer.
    for (const ancora of ancoras) {
      if ("aposSecao" in ancora) continue;
      const idx = rowIndex++;
      const row = sheet.getRow(idx);
      row.getCell(1).value = ancora.label;
      row.getCell(1).font = { bold: true };
      const subtotalNum = new Map<string, number>();
      colunas.forEach((col, i) => {
        const cell = row.getCell(plano.valuePos[i]);
        cell.font = { bold: true };
        cell.border = THIN_TOP_BORDER;
        let formula: string | null = null;
        const cel = (k: string) => (idxAncora.has(k) ? `${colLetra(i)}${idxAncora.get(k)}` : null);
        if (ancora.key === "variacao_liquida_caixa") {
          const partes = ["caixa_operacional", "caixa_investimento", "caixa_financiamento"].map(cel).filter(Boolean);
          if (partes.length) formula = partes.join("+");
        } else if (ancora.key === "saldo_final_caixa") {
          const ini = cel("saldo_inicial_caixa");
          const varc = cel("variacao_liquida_caixa");
          if (ini && varc) formula = `${ini}+${varc}`;
        }
        if (formula) {
          cell.value = { formula } as ExcelJS.CellFormulaValue;
          cell.numFmt = VALOR_NUM_FMT;
          // …e o NÚMERO equivalente, para a Modelagem. A fórmula fica na aba;
          // o valor vai para a base do modelo.
          const somaDe = (k: string) => subtotalAncora.get(k)?.get(col.key);
          const n = ancora.key === "variacao_liquida_caixa"
            ? ["caixa_operacional", "caixa_investimento", "caixa_financiamento"]
              .map(somaDe).filter((x): x is number => x != null)
              .reduce((a, b) => a + b, 0)
            : (somaDe("saldo_inicial_caixa") ?? 0) + (somaDe("variacao_liquida_caixa") ?? 0);
          subtotalNum.set(col.key, n);
        } else {
          // saldo inicial (ou sem fórmula possível): usa o valor extraído
          const grupo = valoresPorAncora.get(ancora.key);
          const v = grupo ? valorNumDoGrupo(grupo, col.key) : null;
          if (v != null) {
            cell.value = v;
            cell.numFmt = VALOR_NUM_FMT;
            // O `subtotalNum` das âncoras LIVRES só era preenchido no ramo da
            // fórmula. O "Saldo Inicial de Caixa" cai justamente no outro ramo
            // (é valor extraído, não derivado) — e é uma das linhas que a
            // Modelagem lê. Sem isto ela receberia a âncora vazia.
            subtotalNum.set(col.key, v);
          }
        }
      });
      idxAncora.set(ancora.key, idx);
      subtotalAncora.set(ancora.key, subtotalNum);
      registrarValores(ancora.label, subtotalNum);
      linhasValor.add(idx);
    }
  }

  // ----- Contas Não Classificadas: nada desaparece silenciosamente. -----
  // O título carrega o TOTAL do bloco por coluna. Deixa de ser linha vazia e
  // passa a responder a pergunta que o analista faz primeiro: "quanto de valor
  // está fora das seções?" — se for material, a planilha ainda não está pronta
  // para virar modelo.
  if (naoClassificados.size > 0) {
    rowIndex++; // linha em branco
    const tituloIdx = rowIndex++;
    const primeiraNC = rowIndex;
    for (const conta of naoClassificados.values()) escrever(conta.label, 1, conta);
    const ultimaNC = rowIndex - 1;
    const tituloRow = sheet.getRow(tituloIdx);
    tituloRow.getCell(1).value = "Contas Não Classificadas (revisar manualmente)";
    tituloRow.font = { bold: true, italic: true };
    tituloRow.fill = NAO_CLASSIFICADO_FILL;
    tituloRow.getCell(1).note = comoNota(
      "Contas que o classificador não colocou numa seção com segurança. O valor ao lado é o total "
      + "do bloco: quanto maior, menos a planilha está pronta para virar modelo. Nada foi "
      + "descartado — cada conta aparece abaixo com o rótulo original.",
    );
    if (ultimaNC >= primeiraNC) {
      colunas.forEach((col, i) => {
        let tem = false;
        for (const conta of naoClassificados.values()) {
          if (valorNumDoGrupo(conta, col.key) != null) { tem = true; break; }
        }
        if (!tem) return;
        const cell = tituloRow.getCell(plano.valuePos[i]);
        escreverSomaOuRecusa(cell, col.key, `SUM(${colLetra(i)}${primeiraNC}:${colLetra(i)}${ultimaNC})`);
        cell.font = { bold: true, italic: true };
      });
    }
  }

  // Destaques de cabeçalho, agora que nenhum `row.fill = …` vem depois para
  // apagá-los. Ver `pintarNoFim`: enquanto isto era feito na hora, a marca de
  // divergência no cabeçalho da seção era escrita e imediatamente perdida.
  for (const [r, c] of pintarNoFim) sheet.getRow(r).getCell(c).fill = DIVERGENCIA_FILL;

  // ----- Camada analítica (Arquitetura do Sistema/2 Especificação/f0/08): AV% (common-size) e Δ% (tendência). -----
  // Fórmulas transparentes sobre as MESMAS células de valor já escritas — não
  // inventam nada; a linha subjacente segue pendente/âmbar até o aceite.
  preencherAnaliseVerticalHorizontal(sheet, plano, [...linhasValor], baseTotalRow);

  // ----- Indicadores de liquidez/estrutura (Balanço) — Arquitetura do Sistema/2 Especificação/f0/08. -----
  if (estrutura === "balanco") {
    escreverIndicadoresBalanco(sheet, plano, colunas, noRow, noValor, () => rowIndex++);
  }
  return valoresDaAba;
}

// AV% e Δ% para todas as linhas monetárias. AV% = valor ÷ base (Ativo Total ou
// Receita Líquida); Δ% = (período atual − anterior) ÷ anterior. Só escreve onde
// a(s) célula(s) de valor referida(s) têm conteúdo — nunca força um % órfão.
function preencherAnaliseVerticalHorizontal(
  sheet: ExcelJS.Worksheet,
  plano: PlanoColunas,
  linhas: number[],
  baseTotalRow: number | null,
) {
  const temValor = (r: number, pos: number) => {
    const v = sheet.getRow(r).getCell(pos).value;
    return v != null && v !== "";
  };
  for (const r of linhas) {
    // Análise vertical
    if (baseTotalRow != null) {
      plano.valuePos.forEach((vp, i) => {
        const av = plano.avPos[i];
        if (av == null || !temValor(r, vp)) return;
        const L = sheet.getColumn(vp).letter;
        const cell = sheet.getRow(r).getCell(av);
        cell.value = { formula: `IFERROR(${L}${r}/${L}${baseTotalRow},"")` } as ExcelJS.CellFormulaValue;
        cell.numFmt = AV_FMT;
        cell.font = ANALISE_FONT;
      });
    }
    // Análise horizontal
    for (const d of plano.deltas) {
      const posAt = plano.valuePos[d.atual];
      const posAn = plano.valuePos[d.anterior];
      if (!temValor(r, posAt) || !temValor(r, posAn)) continue;
      const Lat = sheet.getColumn(posAt).letter;
      const Lan = sheet.getColumn(posAn).letter;
      const cell = sheet.getRow(r).getCell(d.pos);
      cell.value = { formula: `IFERROR((${Lat}${r}-${Lan}${r})/${Lan}${r},"")` } as ExcelJS.CellFormulaValue;
      cell.numFmt = DELTA_FMT;
      cell.font = ANALISE_FONT;
    }
  }
}

// Bloco de indicadores de liquidez e estrutura de capital ao pé do Balanço
// (Matarazzo/Assaf Neto; CFI credit analysis — Arquitetura do Sistema/2 Especificação/f0/08). Cada indicador é uma
// FÓRMULA por coluna referenciando as linhas de subtotal do próprio Balanço
// (via `noRow`), com IFERROR: se o insumo não existe, a célula fica vazia —
// nunca estimamos. Índices que exigem detalhamento de conta ainda não isolado
// (liquidez seca/imediata, cobertura de juros, dívida líquida, ciclo de caixa,
// ROA/ROE, Altman Z'') ficam de fora por ora — ver Arquitetura do Sistema/2 Especificação/f0/08.
function escreverIndicadoresBalanco(
  sheet: ExcelJS.Worksheet,
  plano: PlanoColunas,
  colunas: Coluna[],
  noRow: Map<string, number>,
  noValor: Map<string, Map<string, number>>,
  proximaLinha: () => number,
) {
  const AC = noRow.get("ativo_circulante");
  const ATV = noRow.get("ATIVO");
  const PC = noRow.get("passivo_circulante");
  const PNC = noRow.get("passivo_nao_circulante");
  const PL = noRow.get("patrimonio_liquido");
  const RLP = noRow.get("realizavel_lp");
  const IMOB = noRow.get("imobilizado");
  const INV = noRow.get("investimentos");
  const INT = noRow.get("intangivel");
  // Sem as âncoras estruturais mínimas não há o que calcular.
  if (AC == null || ATV == null || PC == null || PNC == null || PL == null) return;

  const cel = (i: number, row: number | undefined) => (row == null ? null : `${sheet.getColumn(plano.valuePos[i]).letter}${row}`);
  // Valor de um nó na coluna i (null quando o nó não existe ou a coluna está
  // vazia) — é com isso que decidimos se o índice resolve de verdade.
  const val = (i: number, chave: string): number | null => {
    const v = noValor.get(chave)?.get(colunas[i].key);
    return typeof v === "number" ? v : null;
  };
  const soma = (i: number, chaves: string[]): number | null => {
    let t: number | null = null;
    for (const c of chaves) {
      const v = val(i, c);
      if (v != null) t = (t ?? 0) + v;
    }
    return t;
  };
  // Um índice só é emitido se, em ALGUMA coluna, numerador e denominador
  // existem e o denominador não é zero.
  const razaoResolve = (i: number, num: string[], den: string[]): boolean => {
    const n = soma(i, num);
    const d = soma(i, den);
    return n != null && d != null && d !== 0;
  };

  const indicadores: Array<{
    label: string; fmt: string;
    formula: (i: number) => string | null;
    resolve: (i: number) => boolean;
  }> = [
    {
      label: "Liquidez Corrente (AC ÷ PC)", fmt: RATIO_FMT,
      formula: (i) => `${cel(i, AC)}/${cel(i, PC)}`,
      resolve: (i) => razaoResolve(i, ["ativo_circulante"], ["passivo_circulante"]),
    },
    {
      label: "Liquidez Geral ((AC + Realizável LP) ÷ (PC + PNC))",
      fmt: RATIO_FMT,
      formula: (i) => {
        const ac = cel(i, AC)!;
        const rlp = cel(i, RLP);
        const num = rlp ? `(${ac}+${rlp})` : ac;
        return `${num}/(${cel(i, PC)}+${cel(i, PNC)})`;
      },
      resolve: (i) => razaoResolve(i, ["ativo_circulante", "realizavel_lp"], ["passivo_circulante", "passivo_nao_circulante"]),
    },
    {
      label: "Endividamento Geral ((PC + PNC) ÷ Ativo Total)", fmt: PCT_FMT,
      formula: (i) => `(${cel(i, PC)}+${cel(i, PNC)})/${cel(i, ATV)}`,
      resolve: (i) => razaoResolve(i, ["passivo_circulante", "passivo_nao_circulante"], ["ATIVO"]),
    },
    {
      label: "Composição do Endividamento (PC ÷ (PC + PNC))", fmt: PCT_FMT,
      formula: (i) => `${cel(i, PC)}/(${cel(i, PC)}+${cel(i, PNC)})`,
      resolve: (i) => razaoResolve(i, ["passivo_circulante"], ["passivo_circulante", "passivo_nao_circulante"]),
    },
    {
      label: "Participação de Capital de Terceiros ((PC + PNC) ÷ PL)", fmt: PCT_FMT,
      formula: (i) => `(${cel(i, PC)}+${cel(i, PNC)})/${cel(i, PL)}`,
      resolve: (i) => razaoResolve(i, ["passivo_circulante", "passivo_nao_circulante"], ["patrimonio_liquido"]),
    },
    {
      label: "Imobilização do PL ((Imob. + Invest. + Intang.) ÷ PL)",
      fmt: PCT_FMT,
      formula: (i) => {
        const partes = [cel(i, IMOB), cel(i, INV), cel(i, INT)].filter(Boolean);
        if (partes.length === 0) return null;
        return `(${partes.join("+")})/${cel(i, PL)}`;
      },
      resolve: (i) => razaoResolve(i, ["imobilizado", "investimentos", "intangivel"], ["patrimonio_liquido"]),
    },
  ];

  // Só indicadores que TÊM fórmula em pelo menos uma coluna. Um índice cujos
  // insumos não existem na extração (ex.: Imobilização do PL num combinado que
  // não detalha Imobilizado) sairia como linha 100% vazia — e linha vazia numa
  // planilha de entrega parece defeito, não parece "insumo indisponível".
  const comValor = indicadores.filter((ind) =>
    colunas.some((_, i) => ind.formula(i) != null && ind.resolve(i)));
  if (comValor.length === 0) return;

  // Sem linha de título própria (era a última linha 100% vazia do Balanço): o
  // bloco é aberto pela borda dupla e pela nota no primeiro índice. Os rótulos
  // já explicitam a fórmula de cada um, então nada se perde.
  const NOTA_BLOCO = comoNota(
    "Início do bloco de INDICADORES DE LIQUIDEZ E ESTRUTURA: índices calculados por fórmula sobre os "
    + "subtotais extraídos deste Balanço (Matarazzo/Assaf Neto; Arquitetura do Sistema/2 Especificação/f0/08). Não são linhas do documento. "
    + "Célula vazia = insumo não disponível na extração (nunca estimado). Índices que exigem "
    + "detalhamento de conta ainda não isolado (liquidez seca/imediata, cobertura de juros, dívida "
    + "líquida/EBITDA, ciclo de caixa, ROA/ROE, Altman Z'') ficam de fora desta versão — ver Arquitetura do Sistema/2 Especificação/f0/08. "
    + "Valores derivados de linhas ainda PENDENTES seguem pendentes até o aceite humano.",
  );

  proximaLinha(); // linha em branco separando do balanço
  comValor.forEach((ind, ordem) => {
    const r = proximaLinha();
    const row = sheet.getRow(r);
    row.getCell(1).value = ind.label;
    row.getCell(1).font = INDICADOR_LABEL_FONT;
    if (ordem === 0) {
      row.getCell(1).font = { ...INDICADOR_LABEL_FONT, bold: true };
      row.getCell(1).fill = INDICADOR_TITULO_FILL;
      row.getCell(1).note = NOTA_BLOCO;
      row.getCell(1).border = DOUBLE_TOP_BORDER;
    }
    colunas.forEach((_, i) => {
      const f = ind.formula(i);
      if (!f) return;
      const cell = row.getCell(plano.valuePos[i]);
      cell.value = { formula: `IFERROR(${f},"")` } as ExcelJS.CellFormulaValue;
      cell.numFmt = ind.fmt;
      if (ordem === 0) cell.border = DOUBLE_TOP_BORDER;
    });
  });
}

// ----- Aba simples (Faturamento/Dívida/Fluxo Projetado/Outros) -------------
// Já são, por natureza, uma série/tabela — não uma demonstração de blocos.
interface LinhaSimples {
  entidade: string;
  periodo: string;
  secao: string;
  chave: string;
  valorTexto: string | null;
  valorNum: number | null;
  unidade: string | null;
  pagina: number | null;
  confianca: number | null;
  statusAceite: string;
  aceitoPor: string | null;
  aceitoEm: string | null;
  arquivoOrigem: string;
}

// Nota de proveniência da linha simples (mesmo espírito de `notaProveniencia`,
// para os campos que a v20 pediu pra tirar da grade — seção/página/unidade/
// confiança/aceito por/aceito em/arquivo continuam rastreáveis, só saem de
// coluna própria pra virar um comentário no rótulo).
function notaProvenienciaSimples(linha: LinhaSimples): string {
  const partes = [
    linha.secao !== "(sem seção)" ? `Seção: ${linha.secao}` : null,
    `Arquivo: ${linha.arquivoOrigem}`,
    linha.pagina != null ? `Página: ${linha.pagina}` : null,
    linha.unidade ? `Unidade: ${linha.unidade}` : null,
    linha.confianca != null ? `Confiança da extração: ${Math.round(linha.confianca * 100)}%` : null,
    `Status: ${formatarStatus(linha.statusAceite)}`,
    linha.statusAceite === "aceito" && linha.aceitoPor ? `Aceito por: ${linha.aceitoPor}` : null,
    linha.aceitoEm ? `Aceito em: ${new Date(linha.aceitoEm).toLocaleString("pt-BR")}` : null,
  ].filter(Boolean);
  return partes.join("\n");
}

// Colunas reduzidas ao essencial (pedido do dono, sessão 7 cont.¹⁴): a
// listagem simples (Faturamento, Dívida, Intragrupo, Societário, ...) tinha 13
// colunas — a maioria delas técnica/de rastreabilidade (seção, página,
// unidade, confiança, aceito por/em, arquivo, versão da taxonomia), poluindo
// a leitura de quem só quer ver conta × valor. Essas informações não somem —
// viram um comentário (`cell.note`) no rótulo, visível ao passar o mouse.
function construirAbaSimples(workbook: ExcelJS.Workbook, nomeAba: string, linhas: LinhaSimples[]) {
  linhas.sort((a, b) => compararColunas(a, b) || a.secao.localeCompare(b.secao));

  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", ySplit: 1 }] });
  sheet.columns = [
    { header: "Entidade", key: "entidade", width: 26 },
    { header: "Período", key: "periodo", width: 14 },
    { header: "Rótulo", key: "chave", width: 38 },
    { header: "Valor", key: "valorNum", width: 16 },
    { header: "Status", key: "statusAceite", width: 12 },
  ];
  sheet.getRow(1).font = { bold: true };
  sheet.getRow(1).fill = HEADER_FILL;

  for (const linha of linhas) {
    const row = sheet.addRow({
      entidade: linha.entidade,
      periodo: linha.periodo,
      chave: linha.chave,
      valorNum: linha.valorNum ?? linha.valorTexto ?? null,
      statusAceite: formatarStatus(linha.statusAceite),
    });
    row.getCell("chave").note = comoNota(notaProvenienciaSimples(linha));
    if (typeof row.getCell("valorNum").value === "number") row.getCell("valorNum").numFmt = VALOR_NUM_FMT;
    if (/total/i.test(linha.chave)) row.font = { bold: true };
    if (linha.statusAceite !== "aceito") {
      row.eachCell((cell) => {
        cell.fill = PENDENTE_FILL;
      });
      row.font = { ...row.font, italic: true };
    }
  }
}

// ---------------------------------------------------------------------------
// DMPL e DVA (Supabase/migrations/0024). As duas são demonstrações inteiras, mas
// nenhuma passa pelo `construirAbaClassificada`: aquele caminho existe para
// template de seções + subtotal em FÓRMULA (Balanço/DRE/Fluxo), e nem a DMPL
// nem a DVA têm um template nosso. Aqui vale o princípio travado na sessão 10:
// o que sai é o que o documento trouxe, na ordem em que ele trouxe — nenhuma
// linha imposta, nenhum subtotal calculado por nós (anti-ancoragem, Arquitetura do Sistema/2 Especificação/f0/07).
// Por construção, então, toda linha destas abas nasce de uma linha extraída:
// não existe aqui a classe de defeito que o invariante 8 persegue nas abas com
// template (linha em branco emitida às cegas).
// ---------------------------------------------------------------------------
interface RegistroDemonstracao {
  campo: CampoExtraido;
  ctx: ContextoVersao;
  entidade: string;
  periodo: string;
}

const MOVIMENTO_SEM_ROTULO = "(movimento não informado)";
const SECAO_SEM_ROTULO = "(sem seção informada)";

// Chave estável para alinhar o MESMO rótulo escrito com grafias diferentes
// (plural, acento, caixa) sem forçar nome canônico — o rótulo exibido é sempre
// o primeiro que apareceu, como no resto do export.
function ordemPorPrimeiraAparicao() {
  const ordem = new Map<string, string>(); // chave normalizada → rótulo exibido
  return {
    registrar(rotulo: string) {
      const k = normalizar(rotulo);
      if (!ordem.has(k)) ordem.set(k, rotulo);
      return k;
    },
    lista(): Array<[string, string]> {
      return [...ordem.entries()];
    },
  };
}

// A DMPL é uma MATRIZ: as linhas são MOVIMENTOS do exercício ("SALDOS EM 31 DE
// DEZEMBRO DE 2024", "Prejuízo líquido do exercício") e as colunas são
// COMPONENTES do PL ("Capital social", "Reserva legal", "Prejuízos acumulados",
// "Total"). Achatá-la numa listagem perderia justamente a leitura que a
// demonstração existe para dar (como cada componente do PL se moveu), então a
// aba reconstrói a matriz: um bloco por entidade×período, cabeçalho com os
// componentes, uma linha por movimento. `secao` = movimento e `chave` =
// componente é o contrato que o prompt de extração pede (N8N/lib/extract.mjs).
function construirAbaDMPL(workbook: ExcelJS.Workbook, nomeAba: string, registros: RegistroDemonstracao[]) {
  const blocos = new Map<string, { entidade: string; periodo: string; registros: RegistroDemonstracao[] }>();
  for (const reg of registros) {
    const key = `${reg.entidade}${CHAVE_SEP}${reg.periodo}`;
    if (!blocos.has(key)) blocos.set(key, { entidade: reg.entidade, periodo: reg.periodo, registros: [] });
    blocos.get(key)!.registros.push(reg);
  }

  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", ySplit: 1 }] });
  let larguraMax = 0;

  for (const bloco of [...blocos.values()].sort(compararColunas)) {
    const componentes = ordemPorPrimeiraAparicao();
    const movimentos = ordemPorPrimeiraAparicao();
    const celulas = new Map<string, RegistroDemonstracao[]>();
    for (const reg of bloco.registros) {
      const comp = componentes.registrar(reg.campo.chave);
      const mov = movimentos.registrar(reg.campo.secao ?? MOVIMENTO_SEM_ROTULO);
      const k = `${mov}${CHAVE_SEP}${comp}`;
      if (!celulas.has(k)) celulas.set(k, []);
      celulas.get(k)!.push(reg);
    }

    const colunasComp = componentes.lista();
    larguraMax = Math.max(larguraMax, colunasComp.length + 1);

    // O título do bloco vive na MESMA linha do cabeçalho dos componentes (em
    // vez de uma linha só de título): uma linha com rótulo e nenhum valor é
    // exatamente o que o invariante 8 chama de linha vazia.
    const header = sheet.addRow([
      `Movimento — ${bloco.entidade} (${bloco.periodo})`,
      ...colunasComp.map(([, label]) => label),
    ]);
    header.font = { bold: true };
    header.eachCell((cell) => {
      cell.fill = HEADER_FILL;
      cell.alignment = { wrapText: true, vertical: "bottom" };
    });

    for (const [movKey, movLabel] of movimentos.lista()) {
      const row = sheet.addRow([movLabel]);
      let algumPendente = false;
      colunasComp.forEach(([compKey], i) => {
        const candidatos = celulas.get(`${movKey}${CHAVE_SEP}${compKey}`);
        if (!candidatos || candidatos.length === 0) return;
        const melhor = melhorCampo(candidatos.map((r) => r.campo));
        const { ctx } = candidatos.find((r) => r.campo === melhor)!;
        const cell = row.getCell(i + 2);
        cell.value = melhor.valor_num ?? melhor.valor_texto ?? null;
        if (typeof cell.value === "number") cell.numFmt = VALOR_NUM_FMT;
        cell.note = comoNota(notaProveniencia(melhor, ctx));
        if (melhor.status_aceite !== "aceito") {
          cell.fill = PENDENTE_FILL;
          algumPendente = true;
        }
      });
      // Saldo de abertura/fechamento é a moldura da demonstração — negrito e
      // filete, como sai no PDF publicado.
      if (/\bsaldos?\b/i.test(movLabel)) {
        row.font = { bold: true };
        row.eachCell((cell) => {
          cell.border = THIN_TOP_BORDER;
        });
      }
      if (algumPendente) row.font = { ...row.font, italic: true };
    }

    sheet.addRow([]); // respiro entre blocos (sem rótulo — o invariante 8 pula)
  }

  sheet.getColumn(1).width = 46;
  for (let c = 2; c <= Math.max(larguraMax, 2); c++) sheet.getColumn(c).width = 20;
}

// A DVA (CPC 09) é uma cascata de seções — geração do valor adicionado e sua
// distribuição. Não escrevemos um template dela: a demonstração é padronizada
// pelo CPC, mas não temos nenhum arquivo real para validar um, e um template
// errado ordenaria o dado errado em silêncio. A aba apresenta o que o documento
// trouxe, na ordem dele, com a seção declarada numa coluna própria — e as
// colunas de valor são entidade×período, como nas demais demonstrações.
function construirAbaDocumental(workbook: ExcelJS.Workbook, nomeAba: string, registros: RegistroDemonstracao[]) {
  const colunas = new Map<string, Coluna>();
  for (const reg of registros) {
    const key = `${reg.entidade}${CHAVE_SEP}${reg.periodo}`;
    if (!colunas.has(key)) colunas.set(key, { key, entidade: reg.entidade, periodo: reg.periodo });
  }
  const ordemColunas = [...colunas.values()].sort(compararColunas);
  const posColuna = new Map(ordemColunas.map((c, i) => [c.key, i + 3]));

  const secoes = ordemPorPrimeiraAparicao();
  const linhas = new Map<string, { secaoLabel: string; rotulo: string; porColuna: Map<string, RegistroDemonstracao[]> }>();
  for (const reg of registros) {
    const secaoKey = secoes.registrar(reg.campo.secao ?? SECAO_SEM_ROTULO);
    const k = `${secaoKey}${CHAVE_SEP}${normalizar(reg.campo.chave)}`;
    if (!linhas.has(k)) {
      linhas.set(k, {
        secaoLabel: reg.campo.secao ?? SECAO_SEM_ROTULO,
        rotulo: reg.campo.chave,
        porColuna: new Map(),
      });
    }
    const alvo = linhas.get(k)!;
    const colKey = `${reg.entidade}${CHAVE_SEP}${reg.periodo}`;
    if (!alvo.porColuna.has(colKey)) alvo.porColuna.set(colKey, []);
    alvo.porColuna.get(colKey)!.push(reg);
  }

  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", ySplit: 1, xSplit: 2 }] });
  sheet.columns = [
    { header: "Rótulo", width: 46 },
    { header: "Seção declarada no documento", width: 32 },
    ...ordemColunas.map((c) => ({ header: `${c.entidade} — ${c.periodo}`, width: 20 })),
  ];
  sheet.getRow(1).font = { bold: true };
  sheet.getRow(1).eachCell((cell) => {
    cell.fill = HEADER_FILL;
    cell.alignment = { wrapText: true, vertical: "bottom" };
  });

  for (const linha of linhas.values()) {
    const row = sheet.addRow([linha.rotulo, linha.secaoLabel]);
    let algumPendente = false;
    for (const [colKey, regs] of linha.porColuna) {
      const pos = posColuna.get(colKey);
      if (!pos) continue;
      const melhor = melhorCampo(regs.map((r) => r.campo));
      const reg = regs.find((r) => r.campo === melhor)!;
      const cell = row.getCell(pos);
      cell.value = melhor.valor_num ?? melhor.valor_texto ?? null;
      if (typeof cell.value === "number") cell.numFmt = VALOR_NUM_FMT;
      cell.note = comoNota(notaProveniencia(melhor, reg.ctx));
      if (melhor.status_aceite !== "aceito") {
        cell.fill = PENDENTE_FILL;
        algumPendente = true;
      }
    }
    row.getCell(2).font = { size: 9, color: { argb: "FF64748B" } };
    if (/total|valor adicionado/i.test(linha.rotulo)) row.font = { bold: true };
    if (algumPendente) row.font = { ...row.font, italic: true };
  }
}

/**
 * O ROTEAMENTO DAS LINHAS EXTRAÍDAS PARA AS ABAS — o passo que o export e a tela de Modelagem
 * têm de compartilhar. Versão vigente, escala única, entidade consolidada, aba por linha e
 * coluna por (entidade × período): é daqui que sai o `camposPorAba` sobre o qual a detecção de
 * subtotal (`rotulosDeSubtotalInformado`) decide o que é conta e o que é total de grupo.
 *
 * POR QUE ISTO SAIU DE DENTRO DE `buildExportWorkbook`. As sugestões do realizado da tela de
 * Modelagem somavam as linhas do banco por seção e não tinham como saber a hierarquia: a DRE e o
 * balanço do documento trazem o total do grupo e as filhas na mesma seção, e só a ORDEM impressa
 * (campo.ordem) separa uma coisa da outra. Medido em produção (Fw Valtra, 2025): PMR 120 dias
 * onde o documento dá ~40, SG&A 34,9% onde dá 17,9%. Duas implementações da mesma classificação
 * divergem sem erro nenhum; agora há UMA, e o export e a tela a chamam.
 */
export function rotearCamposPorAba(
  documentos: DocumentoParaExport[],
  camposDeTodasAsVersoes: CampoExtraido[],
) {
  // Mapa documento_versao_id → contexto (entidade/período/tipo/arquivo) —
  // permite juntar campo_extraido (que só sabe a versão) com o resto. Só as
  // versões VIGENTES entram: reextração substitui, não acumula (ver
  // `versoesVigentes`).
  const vigentes = versoesVigentes(documentos, camposDeTodasAsVersoes);
  const contextoPorVersao = new Map<string, ContextoVersao>();
  for (const doc of documentos) {
    for (const versao of doc.documento_versao ?? []) {
      if (!vigentes.has(versao.id)) continue;
      contextoPorVersao.set(versao.id, {
        entidade: doc.entidade?.razao_social ?? "(sem entidade)",
        periodo: doc.periodo ? formatarPeriodo(doc.periodo.tipo, doc.periodo.referencia) : "(sem período)",
        tipoTaxonomia: doc.tipo_taxonomia,
        nomeArquivo: versao.nome_original ?? "(sem nome)",
      });
    }
  }
  // Daqui para baixo, `campos` é só o da versão vigente — inclusive nas contagens
  // do Resumo, que senão anunciariam linhas que a planilha não mostra.
  const camposVigentes = camposDeTodasAsVersoes.filter((c) => contextoPorVersao.has(c.documento_versao_id));
  const camposDeVersaoSubstituida = camposDeTodasAsVersoes.length - camposVigentes.length;

  // ESCALA: converte tudo para uma escala só, ANTES de qualquer soma. Ver o
  // comentário de `normalizarEscala`. Daqui para baixo, todo `valor_num` está na
  // mesma escala — que é o que torna `SUM`, AV%, indicadores e a Modelagem
  // corretos sem que nenhum deles precise saber que escala existe.
  const escalaAlvo = escolherEscalaAlvo(camposVigentes);
  const { campos, escala } = normalizarEscala(camposVigentes, escalaAlvo);

  // Consolidação de coluna (teste v27): o apelido que o documento combinado usa
  // na coluna ("Componentes") e a razão social do documento individual
  // ("VERTENTES COMPONENTES AUTOMOTIVOS LTDA.") são a MESMA empresa e precisam
  // virar UMA coluna — senão qualquer soma do grupo conta cada empresa 2x.
  const apelidosDeColuna = campos.map((c) => c.entidade_coluna).filter((x): x is string => !!x);
  const razoesSociais = [...contextoPorVersao.values()].map((c) => c.entidade);
  const nomeCanonico = consolidarNomesDeEntidade(razoesSociais, apelidosDeColuna);

  // Quais versões são documento COMPOSTO — várias demonstrações no mesmo arquivo
  // sem aba estruturada própria. Duas portas, e a diferença entre elas é o que
  // impede este roteamento de virar dupla contagem:
  //
  //  (a) o TIPO declara o conjunto (`TIPOS_DOCUMENTO_COMPOSTO`): basta isso. Seja
  //      o que o arquivo contiver, suas linhas são de demonstração e cada uma tem
  //      aba canônica — inclusive quando a DF auditada traz só o balanço.
  //  (b) o documento AINDA NÃO TEM TIPO (nome de arquivo que a taxonomia não
  //      reconhece, aguardando a fila de revisão): aí exige-se evidência DECLARADA
  //      de mais de uma demonstração — linhas com `secao_canonica` de duas
  //      famílias diferentes. É o sinal que separa "Demonstrações Contábeis
  //      2025.pdf" (BP + DRE + DFC juntos) de um aging de recebíveis, que é
  //      homogêneo e cujo lugar continua sendo a listagem documental. Sem essa
  //      exigência, o aging entraria no Balanço somando o detalhe DEBAIXO do total
  //      que o BP já informa.
  const versoesCompostas = new Set<string>();
  {
    const familiasDeclaradasPorVersao = new Map<string, Set<FamiliaDemonstracao>>();
    for (const campo of campos) {
      const ctx = contextoPorVersao.get(campo.documento_versao_id);
      if (!ctx) continue;
      const abaDoc = (ctx.tipoTaxonomia && ABA_POR_TIPO[ctx.tipoTaxonomia]) || "Outros";
      // Documento que já tem aba própria (estruturada, DMPL/DVA ou de série) não
      // é tocado: seu roteamento é o que sempre foi.
      if (abaDoc !== "Outros") continue;
      if (ctx.tipoTaxonomia) {
        if (TIPOS_DOCUMENTO_COMPOSTO.has(ctx.tipoTaxonomia)) versoesCompostas.add(campo.documento_versao_id);
        continue;
      }
      const familia = familiaDeclarada(campo.secao_canonica);
      if (!familia || ehSecaoDeNotaExplicativa(campo.secao)) continue;
      if (!familiasDeclaradasPorVersao.has(campo.documento_versao_id)) {
        familiasDeclaradasPorVersao.set(campo.documento_versao_id, new Set());
      }
      familiasDeclaradasPorVersao.get(campo.documento_versao_id)!.add(familia);
    }
    for (const [versaoId, familias] of familiasDeclaradasPorVersao) {
      if (familias.size >= 2) versoesCompostas.add(versaoId);
    }
  }

  // Num documento composto NÃO existe uma estrutura "própria" para desambiguar a
  // linha — e é justamente ela que o roteamento por linha usava para resolver a
  // ambiguidade legítima entre demonstrações. "Prejuízo líquido do exercício" é
  // âncora da DRE (linha de fechamento) E do Fluxo indireto (ponto de partida);
  // "Caixa e equivalentes" é conta do Balanço E saldo da DFC. Sem estrutura, o
  // fallback determinístico tenta Fluxo primeiro e a DRE inteira ia para a aba
  // errada — a primeira versão desta fatia fez exatamente isso, e a cascata saiu
  // com Lucro Bruto 10.820 onde o documento diz 5.280.
  //
  // Quem desempata é o próprio documento: um PDF auditado IMPRIME os blocos
  // ("CUSTO DOS PRODUTOS VENDIDOS", "FLUXO DE CAIXA DAS ATIVIDADES OPERACIONAIS")
  // e a extração traz esse cabeçalho em `secao`. A seção decide por VOTO das suas
  // linhas, e a linha ambígua vai com o bloco em que o documento a imprimiu — a
  // mesma doutrina que o resto do export já segue ("a seção declarada manda").
  const familiaPorSecaoComposta = new Map<string, FamiliaDemonstracao>();
  if (versoesCompostas.size > 0) {
    const chaveSecao = (campo: CampoExtraido) =>
      `${campo.documento_versao_id}${CHAVE_SEP}${normalizar(campo.secao ?? "")}`;
    // Voto DECLARADO (a IA disse a que demonstração a linha pertence) vale mais
    // que voto INFERIDO por palavra-chave — a seção só é decidida pelo segundo
    // quando nenhuma linha dela foi declarada.
    const votos = new Map<string, { declarados: Map<string, number>; inferidos: Map<string, number> }>();
    for (const campo of campos) {
      if (!versoesCompostas.has(campo.documento_versao_id)) continue;
      if (!campo.secao || ehSecaoDeNotaExplicativa(campo.secao)) continue;
      const k = chaveSecao(campo);
      if (!votos.has(k)) votos.set(k, { declarados: new Map(), inferidos: new Map() });
      const urna = votos.get(k)!;
      const declarada = familiaDeclarada(campo.secao_canonica);
      const inferida = declarada ? null : classificarDemonstracao(campo.secao, campo.chave, null, null);
      const alvo = declarada ? urna.declarados : urna.inferidos;
      const familia = declarada ?? inferida;
      if (familia) alvo.set(familia, (alvo.get(familia) ?? 0) + 1);
    }
    // Empate: mantém a ordem de preferência do fallback determinístico
    // (`classificarDemonstracao`) — Fluxo e DRE têm sinais específicos, Balanço
    // casa "caixa" de forma gulosa. DMPL/DVA vêm antes porque só chegam aqui
    // declaradas, e declaração não é palpite.
    const DESEMPATE: FamiliaDemonstracao[] = ["dmpl", "dva", "fluxo_caixa", "dre", "balanco"];
    for (const [k, urna] of votos) {
      const urnaValida = urna.declarados.size > 0 ? urna.declarados : urna.inferidos;
      let vencedora: FamiliaDemonstracao | null = null;
      let maisVotos = 0;
      for (const familia of DESEMPATE) {
        const n = urnaValida.get(familia) ?? 0;
        if (n > maisVotos) { maisVotos = n; vencedora = familia; }
      }
      if (vencedora) familiaPorSecaoComposta.set(k, vencedora);
    }
  }

  // Agrupa por aba → coluna (entidade×período) → campos daquela coluna.
  const colunasPorAba = new Map<string, Map<string, Coluna>>();
  const camposPorAba = new Map<string, Array<{ campo: CampoExtraido; colKey: string }>>();
  const linhasSimplesPorAba = new Map<string, LinhaSimples[]>();
  // DMPL/DVA (0024): nem grade classificada (não têm template) nem listagem
  // simples (perderiam a leitura da demonstração) — ver construirAbaDMPL /
  // construirAbaDocumental.
  const registrosPorAba = new Map<string, RegistroDemonstracao[]>();

  for (const campo of campos) {
    const ctx = contextoPorVersao.get(campo.documento_versao_id);
    if (!ctx) continue;
    const abaDoc = (ctx.tipoTaxonomia && ABA_POR_TIPO[ctx.tipoTaxonomia]) || "Outros";
    const estruturaDoc = ESTRUTURA_POR_ABA.get(abaDoc);

    // Roteamento por LINHA (não por tipo do documento): um PDF de
    // "Demonstrações Contábeis" traz Balanço + DRE + Fluxo de Caixa no mesmo
    // arquivo, mas é UM documento de um tipo só. Se a linha pertence a uma
    // demonstração diferente da do documento, ela vai para a aba canônica
    // daquela demonstração — em vez de empilhar tudo na aba do tipo do
    // documento (o que fazia a DRE cair em "Não Classificadas" e as linhas de
    // Fluxo de Caixa vazarem para dentro do Ativo). Só reroteia entre abas
    // ESTRUTURADAS (Balanço/DRE/Fluxo); abas de série (Faturamento/Dívida/…)
    // não são tocadas. Continua N1: a linha segue pendente/âmbar até o aceite.
    let aba = abaDoc;
    if (estruturaDoc) {
      const familiaLinha = classificarDemonstracao(campo.secao, campo.chave, campo.secao_canonica, estruturaDoc);
      if (familiaLinha && familiaLinha !== estruturaDoc) {
        aba = ABA_PADRAO_POR_ESTRUTURA[familiaLinha];
      }
    } else if (versoesCompostas.has(campo.documento_versao_id) && !ehSecaoDeNotaExplicativa(campo.secao)) {
      // Documento composto (DF auditada / conjunto ainda sem tipo): não há
      // estrutura "própria" para preferir, então a ordem de evidência é o que a IA
      // declarou PARA ESTA LINHA → o bloco em que o documento a imprimiu (voto da
      // seção) → palavra-chave. Sem nenhum sinal, a linha fica onde estava
      // (listagem documental): conservador, nada desaparece.
      const familiaLinha =
        familiaDeclarada(campo.secao_canonica)
        ?? (campo.secao
          ? familiaPorSecaoComposta.get(`${campo.documento_versao_id}${CHAVE_SEP}${normalizar(campo.secao)}`)
          : undefined)
        ?? classificarDemonstracao(campo.secao, campo.chave, campo.secao_canonica, null);
      if (familiaLinha) aba = ABA_PADRAO_POR_ESTRUTURA[familiaLinha];
    }
    // Documento multi-entidade (Supabase/migrations/0014): quando a linha traz
    // `entidade_coluna` (ex.: "Certsys Tecn" num balanço combinado com várias
    // colunas de empresa), a coluna do export é a ENTIDADE DA LINHA, não a
    // entidade principal do documento — é o que separa "Certsys Tecn"/"Part"/
    // "Com"/"Total" em colunas próprias no lugar de forçar tudo numa coluna só.
    // …e o apelido dessa coluna é promovido à razão social quando o caso conhece
    // uma só que case (`consolidarNomesDeEntidade`) — sem isso a mesma empresa
    // fica em duas colunas, uma por grafia (teste v27).
    const { entidade: entidadeColuna, periodo: periodoColuna } =
      entidadePeriodoDaLinha(campo, ctx, nomeCanonico);
    // Documento comparativo (Supabase/migrations/0017): quando a linha traz
    // `periodo_coluna` (ex.: "2023"/"2024" num balanço 2023×2024), o período da
    // COLUNA do export é o da linha, não o período único do documento — é o que
    // separa os anos em colunas próprias em vez de colapsá-los num só (perda de
    // dado). Ortogonal a entidade_coluna: a coluna final é entidade × período.
    // `periodo_coluna` vem CRU da extração ("2024", "31/12/2024") enquanto
    // `ctx.periodo` já passou por `formatarPeriodo` — sem normalizar os dois do
    // mesmo jeito, o MESMO período aparecia em duas colunas distintas ("2024" e
    // "2024" formatado de outra fonte) e os rótulos saíam inconsistentes na
    // mesma aba. Formatar aqui colapsa a coluna e alinha a escrita.
    // `periodoConsolidado` fecha o mesmo buraco do lado do período: o combinado
    // declara "2025" e o balanço individual "31/12/2025" — o mesmo exercício em
    // duas colunas (teste v27).

    // Separador improvável na chave: com espaço simples, entidade "A B" +
    // período "C" colidia com entidade "A" + período "B C" (colunas de
    // entidade×período diferentes fundidas numa só).
    const colKey = `${entidadeColuna}${CHAVE_SEP}${periodoColuna}`;
    const estrutura = ESTRUTURA_POR_ABA.get(aba);

    if (aba === ABA_DMPL || aba === ABA_DVA) {
      if (!registrosPorAba.has(aba)) registrosPorAba.set(aba, []);
      registrosPorAba.get(aba)!.push({ campo, ctx, entidade: entidadeColuna, periodo: periodoColuna });
    } else if (estrutura) {
      if (!colunasPorAba.has(aba)) colunasPorAba.set(aba, new Map());
      colunasPorAba.get(aba)!.set(colKey, { key: colKey, entidade: entidadeColuna, periodo: periodoColuna });
      if (!camposPorAba.has(aba)) camposPorAba.set(aba, []);
      camposPorAba.get(aba)!.push({ campo, colKey });
    } else {
      if (!linhasSimplesPorAba.has(aba)) linhasSimplesPorAba.set(aba, []);
      linhasSimplesPorAba.get(aba)!.push({
        entidade: entidadeColuna,
        periodo: periodoColuna,
        secao: campo.secao ?? "(sem seção)",
        chave: campo.chave,
        valorTexto: campo.valor_texto,
        valorNum: campo.valor_num,
        unidade: campo.unidade,
        pagina: campo.origem_pagina,
        confianca: campo.confianca,
        statusAceite: campo.status_aceite,
        aceitoPor: campo.aceito_por,
        aceitoEm: campo.aceito_em,
        arquivoOrigem: ctx.nomeArquivo,
      });
    }
  }

  return {
    vigentes, contextoPorVersao, camposDeVersaoSubstituida, escala, campos,
    colunasPorAba, camposPorAba, linhasSimplesPorAba, registrosPorAba,
  };
}

/**
 * O que a ESTRUTURA do documento diz sobre as contas, para a ENTIDADE dada — o mesmo veredito que
 * o export injeta no modelo institucional: os subtotais (`subtotaisInformados`) e a natureza que a
 * subseção bruta dá à conta (`naturezaPorLinha`, ver `naturezaDaSubsecao`).
 */
export function estruturaDoCaso(
  documentos: DocumentoParaExport[],
  campos: CampoExtraido[],
  entidade: string | null,
): Pick<EntradaModeloInstitucional, "subtotaisInformados" | "naturezaPorLinha"> {
  return estruturaDoRoteamento(rotearCamposPorAba(documentos, campos), entidade);
}

function estruturaDoRoteamento(
  r: Pick<ReturnType<typeof rotearCamposPorAba>, "camposPorAba" | "contextoPorVersao">,
  entidade: string | null,
): Pick<EntradaModeloInstitucional, "subtotaisInformados" | "naturezaPorLinha"> {
  return {
    subtotaisInformados: subtotaisDoRoteamento(r, entidade),
    naturezaPorLinha: naturezasDasSubsecoes(r.camposPorAba, entidade),
  };
}

/**
 * A natureza (estoque, cliente, fornecedor, dívida) que a SUBSEÇÃO bruta dá a cada conta, por
 * (seção canônica, rótulo). Conta cujas ocorrências discordam entre si (subseções com naturezas
 * diferentes em documentos ou exercícios diferentes) não herda nada: herdar a de uma delas seria
 * escolher no escuro. A decisão de usar ou não (o rótulo manda) é de `contexto()`.
 */
function naturezasDasSubsecoes(
  camposPorAba: Map<string, Array<{ campo: CampoExtraido; colKey: string }>>,
  entidade: string | null,
): Record<string, NaturezaDeCiclo> {
  const alvo = entidade ? normalizar(entidade) : null;
  const achadas = new Map<string, NaturezaDeCiclo | null>();
  for (const [aba, itens] of camposPorAba) {
    if (!ESTRUTURA_POR_ABA.has(aba)) continue;
    for (const { campo, colKey } of itens) {
      if (alvo !== null && normalizar(colKey.split(CHAVE_SEP)[0] ?? "") !== alvo) continue;
      if (typeof campo.valor_num !== "number") continue;
      const k = `${normalizar(campo.secao_canonica ?? "")}||${normalizar(campo.chave)}`;
      const n = naturezaDaSubsecao(campo.secao);
      achadas.set(k, achadas.has(k) && achadas.get(k) !== n ? null : n);
    }
  }
  const out: Record<string, NaturezaDeCiclo> = {};
  for (const [k, n] of achadas) if (n) out[k] = n;
  return out;
}

function subtotaisDoRoteamento(
  r: Pick<ReturnType<typeof rotearCamposPorAba>, "camposPorAba" | "contextoPorVersao">,
  entidade: string | null,
): string[] {
  return rotulosDeSubtotalInformado(
    r.camposPorAba, entidade,
    (c) => {
      const p = r.contextoPorVersao.get(c.documento_versao_id)?.periodo;
      return p ? anoDaColuna(p) : null;
    },
  );
}


export function buildExportWorkbook({
  caso,
  documentos,
  campos: camposDeTodasAsVersoes,
  macro,
  macroErro,
  causasDeFalha,
  agora = new Date(),
  // MODO DO EXPORT (decisão do dono): "dados" entrega só as abas de dado — é o
  // insumo de conferência da ingestão, e existe desde a ingestão, mesmo com
  // pendência aberta. "completo" acrescenta a Modelagem projetada.
  //
  // Por que um parâmetro e não dois construtores: as abas de dado têm de ser
  // BIT A BIT as mesmas nos dois arquivos. Dois caminhos de construção divergem
  // — e a divergência apareceria como "o número do completo não bate com o de
  // dados", que é a pior conversa possível com um analista.
  modo = "completo",
  // Fase 7.4 — a configuração de modelagem do caso (0038/0039), vinda do portal.
  // Ausente = arquivo como sempre saiu: só o esqueleto agregado. É o fallback de
  // todo caso que ainda não passou pela seção Modelagem, e é o que garante que
  // esta fase não tire modelo de ninguém.
  modelagemConfig,
  // Fase 9 — o MODELO INSTITUCIONAL (14 abas), reconstruído do "Modelo Base" do
  // dono. Ausente = arquivo como antes; presente = as 14 abas entram no modo
  // completo.
  //
  // Por que conviver com a aba `Modelagem` agregada em vez de substituí-la já: a
  // agregada é o único caminho com validação ao vivo até aqui, e trocar os dois no
  // mesmo passo tiraria a referência de comparação exatamente na rodada em que ela
  // é mais necessária. A remoção é decisão do dono, depois de comparar os dois.
  modeloInstitucional,
}: {
  caso: { nome: string; produto: string };
  documentos: DocumentoParaExport[];
  campos: CampoExtraido[];
  // Índices macro (Supabase/migrations/0025). Opcional: sem eles o export sai como
  // sempre saiu, só sem a aba Macro e com as premissas macro zeradas.
  macro?: MacroParaExport;
  // Mensagem da consulta/RPC que FALHOU ao buscar macro (permissão, RLS, rede) —
  // distinta de "consultou e não achou nada". Confundir as duas é o próprio
  // defeito que motivou este parâmetro (0028): a base tinha dado, a consulta do
  // portal falhava por autorização, e a aba saía dizendo "sem dado coletado"
  // como se a coleta nunca tivesse rodado. Ver `route.ts` (chamador).
  macroErro?: string;
  // Causas DISTINTAS das falhas de extração abertas no caso (texto das pendências
  // `extracao_falhou`). Listar o arquivo que falhou sem dizer POR QUE deixa o
  // dono com meia informação: no v30 os 14 nomes estavam no Resumo e a causa
  // ficava só na fila de revisão, em outra tela.
  causasDeFalha?: string[];
  agora?: Date;
  modo?: "dados" | "completo";
  modelagemConfig?: ConfigModelagem;
  modeloInstitucional?: EntradaModeloInstitucional;
}): ExcelJS.Workbook {

  const {
    vigentes, contextoPorVersao, camposDeVersaoSubstituida, escala, campos,
    colunasPorAba, camposPorAba, linhasSimplesPorAba, registrosPorAba,
  } = rotearCamposPorAba(documentos, camposDeTodasAsVersoes);

  const workbook = new ExcelJS.Workbook();
  // RECALCULAR AO ABRIR — para o arquivo INTEIRO, e não só quando há modelo.
  //
  // O QUE ACONTECIA. Este export escreve fórmula e NÃO escreve valor em cache:
  // todo total de seção das abas classificadas (Balanço, DRE, Fluxo, Combinado,
  // Balancete…) é um `=SUM(...)` transparente, de propósito. Sem
  // `fullCalcOnLoad` o Excel abre essas células VAZIAS até alguém apertar F9 — e
  // vazio, num total, se lê como zero.
  //
  // A flag existia, mas era ligada dentro do modelo institucional
  // (`construirModeloInstitucional`), que só roda no export COMPLETO e só quando
  // o mandato configurou a modelagem. Ou seja: o arquivo do botão **Exportar
  // dados** — o que serve justamente para CONFERIR a extração, linha a linha —
  // saía sem a flag, e com ele todo export de mandato que ainda não modelou.
  // Medido nos dois arquivos: `xl/workbook.xml` do completo trazia
  // `fullCalcOnLoad="1"`, o de dados não trazia nada.
  //
  // Aqui ela passa a ser propriedade do ARQUIVO, que é onde o fato mora: se há
  // fórmula sem cache, o arquivo tem de pedir recálculo. O modelo continua
  // ligando a dele (é idempotente) para quem construir o modelo sozinho.
  workbook.calcProperties = { ...(workbook.calcProperties ?? {}), fullCalcOnLoad: true };
  workbook.creator = "Oria — Tratamento de Dados Financeiros";
  workbook.created = agora;

  // ----- Aba Resumo (metadados do snapshot) -----
  // Pedido do dono (sessão 7 cont.¹⁵): tipo/versão de taxonomia é detalhe
  // interno de classificação, não algo que o time de análise precisa ver na
  // planilha — some daqui (e de toda nota/aviso) mas continua orientando o
  // roteamento por aba internamente (`tipo_taxonomia`/`ABA_POR_TIPO`).
  const resumo = workbook.addWorksheet("Resumo");
  const totalLinhas = campos.length;
  const totalAceitas = campos.filter((c) => c.status_aceite === "aceito").length;
  resumo.columns = [{ width: 32 }, { width: 60 }];
  const linhasResumo: Array<[string, string | number]> = [
    ["Caso", caso.nome],
    ["Produto", caso.produto],
    ["Gerado em", agora.toLocaleString("pt-BR")],
    ["Linhas totais extraídas", totalLinhas],
    ["Linhas aceitas (fato)", totalAceitas],
    ["Linhas pendentes (sugestão, revisar)", totalLinhas - totalAceitas],
    // ESCALA: a informação mais importante do Resumo depois do nome do caso.
    // Toda aba de valores está NESTA escala — o export converte na entrada
    // (`normalizarEscala`) justamente para que exista uma resposta única aqui.
    // Antes desta linha o book não declarava escala em lugar nenhum, e valores em
    // escalas diferentes eram somados crus: erro de ~496x sem nenhuma marca.
    ["Escala dos valores", `${ROTULO_ESCALA[escala.alvo] ?? escala.alvo} — vale para TODAS as abas de valores`],
  ];
  // Só aparece quando houve conversão de verdade: linha que diz "0 convertidos"
  // é ruído, e ruído no Resumo treina o leitor a não ler o Resumo.
  if (escala.converteu > 0) {
    linhasResumo.push([
      "↳ valores convertidos de escala",
      `${escala.converteu} linha(s) vinham em ${escala.escalasEncontradas
        .filter((e) => e !== escala.alvo)
        .map((e) => ROTULO_ESCALA[e] ?? e)
        .join(", ")} e foram convertidas. A nota de cada célula diz a escala de origem.`,
    ]);
  }
  // E o que NÃO deu para converter, que é o que o leitor precisa conferir à mão.
  if (escala.semDeclaracao > 0) {
    linhasResumo.push([
      "↳ linhas sem escala declarada",
      `${escala.semDeclaracao} — o documento não disse a escala, então o valor entrou COMO ESTÁ, sem conversão. ` +
        `Assumir uma escala aqui seria inventar um fator de 1.000x onde não se sabe.`,
    ]);
  }
  // Reextração é substituição, e substituição não pode ser silenciosa: quem abre
  // o book tem de saber que existe extração anterior deste mesmo arquivo fora da
  // planilha (ela continua no banco, com proveniência, para auditoria).
  if (camposDeVersaoSubstituida > 0) {
    linhasResumo.push([
      "Linhas de versão substituída (fora deste export)",
      `${camposDeVersaoSubstituida} — o arquivo foi reextraído; só a extração mais recente com dado entra na planilha`,
    ]);
  }
  // Documento que chegou e não produziu NENHUMA linha. No v28 foram dois (a DRE da
  // Metalúrgica e o Balanço da SPE, os dois por rate limit da OpenAI) e o arquivo
  // não dizia uma palavra sobre isso: a DRE simplesmente não tinha aba, e a SPE
  // simplesmente não tinha coluna no Balanço. Contar quantas linhas foram
  // extraídas sem contar quantos documentos ficaram de fora é meia informação.
  const arquivosSemLinha = documentos
    .flatMap((d) => (d.documento_versao ?? [])
      .filter((v) => vigentes.has(v.id) && !campos.some((c) => c.documento_versao_id === v.id))
      .map((v) => v.nome_original ?? "(sem nome)"));
  if (arquivosSemLinha.length > 0) {
    linhasResumo.push([
      "Documentos SEM linha extraída",
      `${arquivosSemLinha.length} de ${documentos.length}: ${arquivosSemLinha.join("; ")} `
      + "— chegaram e foram classificados, mas a extração não gravou nada (a falha abre pendência na "
      + "fila de revisão). Onde faltou entidade/demonstração nas abas, é por isso.",
    ]);
    // …e a CAUSA junto. Quando as 14 falhas têm a MESMA causa (foi o caso do
    // v30), aparece uma linha só: repetir o mesmo motivo por arquivo esconderia
    // justamente o que a repetição significa — o problema é da conta/API, não
    // dos documentos.
    for (const causa of causasDeFalha ?? []) {
      linhasResumo.push(["↳ causa registrada", causa]);
    }
  }
  resumo.addRows([
    ...linhasResumo,
    [""],
    [
      "Aviso",
      "Este export NÃO é modelagem financeira e não projeta nada — é dado curado e rastreável " +
        "para o time de análise trabalhar em cima (Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md). Linhas marcadas " +
        "PENDENTE ainda não passaram por aceite humano — não são fato, são sugestão a revisar " +
        "antes de entrar no modelo. Quando um mesmo arquivo traz várias demonstrações juntas " +
        "(ex.: Balanço + DRE + Fluxo de Caixa no mesmo PDF), cada linha é encaminhada para a aba " +
        "da demonstração a que pertence — não fica tudo na aba do tipo do documento. " +
        "Balanço/Balancete/DRE/Fluxo de Caixa/Combinado classificam cada conta extraída por SEÇÃO " +
        "(Ativo Circulante, Despesas Operacionais, etc.), mantendo o rótulo original de cada " +
        "empresa — nenhum subtotal é calculado por nós, só aparece se o próprio documento já " +
        "trouxer aquela linha. Contas que não foi possível classificar com segurança aparecem em " +
        "\"Contas Não Classificadas\", ao final de cada aba — revisar manualmente.",
    ],
  ]);
  resumo.getRow(1).font = { bold: true };
  // A linha do Aviso muda de posição quando existe versão substituída — achar por
  // rótulo em vez de fixar "B9", que era uma referência a estourar no primeiro
  // item novo do Resumo.
  for (let r = 1; r <= resumo.rowCount; r++) {
    if (String(resumo.getRow(r).getCell(1).value ?? "") === "Aviso") {
      resumo.getRow(r).getCell(2).alignment = { wrapText: true };
    }
  }


  // ---- ABA "Dados (linha a linha)" ----------------------------------------
  // O ESPELHO 1:1 do banco, sem template, sem agregação, sem fórmula.
  //
  // POR QUE ELA EXISTE: as abas classificadas são uma LEITURA das linhas —
  // agrupam por seção, escolhem um valor por rótulo × coluna, calculam soma.
  // Isso é o que as torna úteis para analisar e é também o que as torna
  // insuficientes para conferir: não há como olhar uma aba de Balanço e saber se
  // aquilo é tudo o que a extração trouxe. Esta aba responde a essa pergunta —
  // uma linha de Excel por linha de `campo_extraido`, na ordem do documento, com
  // a proveniência inteira ao lado.
  //
  // É o insumo de conferência ("cada valor, cada tópico") e é o que permite
  // auditar o resto do arquivo contra o banco sem abrir o Supabase.
  {
    const ws = workbook.addWorksheet(ABA_DADOS, { views: [{ state: "frozen", ySplit: 1 }] });
    ws.columns = [
      { header: "Arquivo", width: 34 },
      { header: "Tipo", width: 16 },
      { header: "Entidade (documento)", width: 30 },
      { header: "Período (documento)", width: 16 },
      { header: "Pág.", width: 6 },
      { header: "Ordem", width: 7 },
      { header: "Seção (do documento)", width: 26 },
      { header: "Seção canônica (IA)", width: 22 },
      { header: "Entidade da coluna", width: 24 },
      { header: "Período da coluna", width: 16 },
      { header: "Rótulo", width: 46 },
      { header: "Valor (texto)", width: 18 },
      { header: "Valor", width: 16 },
      { header: "Escala", width: 12 },
      { header: "Escala original", width: 14 },
      { header: "Moeda", width: 8 },
      { header: "Confiança", width: 10 },
      { header: "Aceite", width: 12 },
    ];
    ws.getRow(1).font = { bold: true };
    ws.getRow(1).fill = HEADER_FILL;
    ws.getRow(1).alignment = { wrapText: true, vertical: "middle" };

    // ORDEM: por arquivo, e dentro do arquivo pela `ordem` da linha no documento
    // (Supabase/migrations/0027). É a ordem de leitura do original — é o que permite
    // conferir de cima para baixo com o PDF ao lado.
    const ordenados = [...campos].sort((a, b) => {
      const ca = contextoPorVersao.get(a.documento_versao_id);
      const cb = contextoPorVersao.get(b.documento_versao_id);
      const na = ca?.nomeArquivo ?? "";
      const nb = cb?.nomeArquivo ?? "";
      if (na !== nb) return na.localeCompare(nb, "pt-BR");
      return (a.ordem ?? 0) - (b.ordem ?? 0);
    });

    for (const campo of ordenados) {
      const ctx = contextoPorVersao.get(campo.documento_versao_id);
      const row = ws.addRow([
        ctx?.nomeArquivo ?? "(arquivo desconhecido)",
        ctx?.tipoTaxonomia ?? "(sem tipo)",
        ctx?.entidade ?? "",
        ctx?.periodo ?? "",
        campo.origem_pagina ?? null,
        campo.ordem ?? null,
        campo.secao ?? "",
        campo.secao_canonica ?? "",
        campo.entidade_coluna ?? "",
        campo.periodo_coluna ?? "",
        campo.chave,
        campo.valor_texto ?? "",
        campo.valor_num ?? null,
        campo.unidade ? (ROTULO_ESCALA[campo.unidade] ?? campo.unidade) : "",
        campo.unidade_original ? (ROTULO_ESCALA[campo.unidade_original] ?? campo.unidade_original) : "",
        campo.moeda ?? "",
        campo.confianca ?? null,
        campo.status_aceite,
      ]);
      row.getCell(13).numFmt = VALOR_NUM_FMT;
      row.getCell(17).numFmt = "0.00";
      // Linha ainda PENDENTE de aceite fica visualmente distinta: nesta aba, mais
      // que em qualquer outra, é importante não confundir sugestão com fato.
      if (campo.status_aceite !== "aceito") {
        row.font = { italic: true, color: { argb: "FF92400E" } };
      }
    }

    if (ordenados.length === 0) {
      ws.addRow(["Nenhuma linha extraída neste caso — ver a aba Resumo para a causa."]);
    }
    ws.autoFilter = { from: { row: 1, column: 1 }, to: { row: 1, column: 18 } };
  }

  // Números por aba → rótulo → coluna, para a Modelagem não depender de
  // fórmula entre abas (Etapa 3).
  const baseModelagem = new Map<string, ValoresDaAba>();
  for (const aba of ORDEM_ABAS) {
    const estrutura = ESTRUTURA_POR_ABA.get(aba);
    if (aba === ABA_DMPL || aba === ABA_DVA) {
      const registros = registrosPorAba.get(aba);
      if (!registros || registros.length === 0) continue;
      if (aba === ABA_DMPL) construirAbaDMPL(workbook, aba, registros);
      else construirAbaDocumental(workbook, aba, registros);
    } else if (estrutura) {
      const colunas = [...(colunasPorAba.get(aba)?.values() ?? [])].sort(compararColunas);
      if (colunas.length === 0) {
        // As três demonstrações PRINCIPAIS existem SEMPRE, mesmo sem dado — com o
        // motivo escrito dentro da aba, e na posição certa da ordem canônica. No
        // teste v28 a extração da DRE falhou por rate limit (429) da OpenAI e a
        // aba simplesmente NÃO EXISTIU no arquivo: o dono abriu o book, não achou
        // a DRE e não tinha como saber se o problema era o documento, a extração
        // ou o export. Aba ausente é buraco silencioso; aba presente dizendo "o
        // documento veio e a extração falhou" é item de trabalho.
        if (ABAS_SEMPRE_PRESENTES.has(aba)) construirAbaSemDado(workbook, aba, documentos);
        continue;
      }
      // A aba devolve os NÚMEROS que ela mostra. É o insumo da Etapa 3: a
      // Modelagem passa a receber valor bruto em vez de buscar por fórmula.
      baseModelagem.set(aba, construirAbaClassificada(
        workbook,
        aba,
        estrutura,
        colunas,
        camposPorAba.get(aba) ?? [],
        contextoPorVersao,
      ));
    } else {
      const linhas = linhasSimplesPorAba.get(aba);
      if (!linhas || linhas.length === 0) continue;
      construirAbaSimples(workbook, aba, linhas);
    }
  }


  // No modo "dados" o arquivo termina aqui: sem Modelagem, sem reordenação de
  // abas. Retorno antecipado em vez de `if` gigante em volta de 200 linhas — e o
  // `Resumo` continua sendo a primeira aba, que é onde se começa a conferir.
  //
  // A MACRO ENTRA MESMO NO MODO DADOS: índices do BCB/IBGE são DADO coletado, não
  // modelagem. Quem confere a ingestão precisa poder ver o que a coleta trouxe —
  // e foi assim que "não veio os dados macro" custou meia hora de investigação no
  // v28, com a aba simplesmente ausente. Aqui ela é construída em qualquer modo,
  // inclusive a versão "sem dado", que diz por que está vazia.
  if (modo === "dados") {
    if (macro) construirAbaMacro(workbook, macro, macroErro);
    else construirAbaMacroSemDado(workbook, macroErro);
    return workbook;
  }

  // ----- Aba Modelagem + ocultação das abas de dado cru ---------------------
  // Pedido do dono (v27): "depois de carregar e tratar, oculte as abas dos
  // dados crus e mantenha apenas o que for prático para a modelagem" — é a
  // mesma disciplina do modelo de referência, que deixa visíveis o Summary e os
  // drivers e esconde as abas de backup.
  //
  // OCULTAR, nunca remover: as abas continuam no arquivo e as fórmulas do
  // modelo seguem apontando para elas. É o que mantém a proveniência (e o
  // princípio de Arquitetura do Sistema/2 Especificação/f0/07: o dado curado e rastreável não some da entrega).
  const entidadesConhecidas = new Map<string, number>();
  const anos = new Set<number>();
  for (const [aba, colunas] of colunasPorAba) {
    if (!ESTRUTURA_POR_ABA.has(aba)) continue;
    for (const c of colunas.values()) {
      if (tipoColunaNaoEntidade(c.entidade)) continue;
      entidadesConhecidas.set(c.entidade, (entidadesConhecidas.get(c.entidade) ?? 0) + 1);
      const ano = Number((c.periodo.match(/\b(19|20)\d{2}\b/) ?? [])[0]);
      if (ano) anos.add(ano);
    }
  }
  if (entidadesConhecidas.size > 0) {
    // Entidade sugerida = a que tem mais colunas de demonstração no caso (a
    // mais bem documentada). É só o VALOR INICIAL de uma célula de input.
    const ordenadas = [...entidadesConhecidas.entries()]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
    const entidadeSugerida = ordenadas[0][0];
    // A lista suspensa da célula de entidade. Vírgula é o separador da lista
    // inline do Excel, então uma razão social que a contenha quebraria a
    // validação — essas ficam de fora da lista (o campo segue digitável).
    const entidadesDisponiveis = ordenadas.map(([e]) => e).filter((e) => !e.includes(","));
    const anosHistoricos = [...anos].sort((a, b) => a - b);
    // A aba Macro entra ANTES da Modelagem: o modelo referencia as linhas do
    // Focus por endereço, então elas precisam existir.
    const refsMacro = macro ? construirAbaMacro(workbook, macro, macroErro) : null;
    // Sem índice coletado a aba Macro também EXISTE, dizendo o que falta. No teste
    // v28 ela não existiu e o dono leu isso como "os índices não vieram com os
    // dados" — sem ter como distinguir "coleta não rodou" de "defeito no export".
    // A causa real ali: a `0025` não estava aplicada no projeto certo (foi aplicada
    // no banco errado e revertida), então não havia índice nenhum na base.
    // A aba de "sem dado" só cobre a falha TOTAL. Quando a consulta falha em
    // PARTE — o caso concreto: os índices vêm, mas a consulta de NOMES das
    // séries não —, a aba Macro é montada normalmente, exibe códigos crus no
    // lugar dos nomes, e o erro morria num `console.error` que ninguém lê. Um
    // arquivo degradado que não declara a degradação é pior que um que falha.
    if (!refsMacro) construirAbaMacroSemDado(workbook, macroErro);
    construirAbaModelagem(
      workbook, caso,
      // A entidade e o corte ESCOLHIDOS no portal mandam sobre os sugeridos pelo
      // conteúdo. Foi para isso que a escolha saiu da planilha: o arquivo sai
      // parametrizado com a decisão registrada, não com o palpite do gerador.
      modelagemConfig?.entidade ?? entidadeSugerida,
      entidadesDisponiveis, anosHistoricos,
      modelagemConfig?.anosProjetados ?? ANOS_PROJETADOS,
      refsMacro, baseModelagem, macro, modelagemConfig,
    );

    // O MODELO INSTITUCIONAL. Só no modo completo: ele projeta, e projetar é o que
    // o modo "dados" deliberadamente não faz.
    // `anosHistoricos.length > 0` entrou aqui junto com a recusa nomeada de
    // `construirModeloInstitucional`: sem realizado o modelo não tem de onde
    // projetar, e antes disso o export inteiro MORRIA com "ano null fora do
    // horizonte" — o analista não recebia arquivo nenhum. Agora ele recebe as abas
    // de dado e uma explicação de por que a modelagem não veio.
    const semRealizado = modeloInstitucional != null
      && modeloInstitucional.anosProjetados.length > 0
      && modeloInstitucional.anosHistoricos.length === 0;
    if (semRealizado) {
      const ws = workbook.addWorksheet("Modelagem não montada");
      ws.columns = [{ width: 40 }, { width: 96 }];
      ws.addRow(["Modelagem — não montada"]).font = { bold: true, size: 12 };
      ws.addRows([
        ["Por quê",
          "Nenhum exercício tem valor NUMÉRICO. O modelo projeta a partir do realizado, e não há "
          + "realizado para ler: as linhas extraídas chegaram sem valor numérico."],
        ["O que costuma ser",
          "Extração que devolveu o TEXTO do valor e não o número — PDF de baixa qualidade, coluna "
          + "que a leitura não alcançou, ou escala que o documento não declarou. As abas de dado "
          + "deste arquivo mostram o que chegou, linha a linha."],
        ["O que fazer",
          "Confira as abas de dado e a fila de revisão. Se o valor está lá como texto, é caso de "
          + "reextrair o documento — não de projetar. Projetar sem realizado inventaria a série "
          + "inteira."],
      ]);
      for (let r = 2; r <= ws.rowCount; r++) {
        ws.getRow(r).alignment = { wrapText: true, vertical: "top" };
        ws.getRow(r).height = 56;
      }
    }
    if (modeloInstitucional && modeloInstitucional.anosProjetados.length > 0 && !semRealizado) {
      // A MESMA detecção de subtotal das abas analíticas, injetada no modelo. Sem
      // isto o `Balance Sheet` soma o subtotal informado E os componentes dele, e
      // sai 2x o documento (medido: 195.090 contra 95.780 no arquivo do v35).
      const entradaDoModelo: EntradaModeloInstitucional = {
        ...modeloInstitucional,
        ...estruturaDoRoteamento({ camposPorAba, contextoPorVersao }, modeloInstitucional.entidade),
      };
      // Os gráficos do `Output` não podem ser escritos pelo ExcelJS (ele não tem
      // API de gráfico). A especificação volta daqui e viaja PRESA AO WORKBOOK
      // até o pós-processamento do buffer — ver `finalizarBufferDoExport`.
      const graficos = construirModeloInstitucional(workbook, entradaDoModelo);
      (workbook as unknown as { __graficosDoModelo?: EspecGrafico[] }).__graficosDoModelo = graficos;
      // A apresentação de crédito (`lib/apresentacao/`) lê o realizado desta MESMA entrada, já com
      // os subtotais informados: sem eles o cabeçalho de grupo soma com as filhas — medido no book
      // Vertentes, "Clientes" de 2024 saía 62.020 num ativo circulante de 67.878.
      (workbook as unknown as { __entradaDoModelo?: EntradaModeloInstitucional }).__entradaDoModelo = entradaDoModelo;
    }

    // A Modelagem é a primeira aba: é por onde o arquivo deve abrir.
    const modelagem = workbook.getWorksheet(ABA_MODELAGEM);
    if (modelagem) {
      workbook.views = [{
        activeTab: modelagem.id - 1, firstSheet: 0, visibility: "visible",
        x: 0, y: 0, width: 10000, height: 20000,
      }];
    }
  } else {
    // NENHUMA entidade reconhecida nas abas de demonstração. Sem entidade não
    // dá para montar a Modelagem (o modelo inteiro pende de uma célula de
    // entidade) nem faz sentido montar a Macro — mas até aqui o arquivo saía
    // simplesmente SEM as duas abas, e uma aba que não existe não diz por quê.
    // No v28 foi assim que "não veio os dados macro" virou meia hora de
    // investigação: o dono não tinha como distinguir "o export não montou"
    // de "a coleta não rodou".
    const ws = workbook.addWorksheet(ABA_MODELAGEM);
    ws.columns = [{ width: 40 }, { width: 96 }];
    ws.addRow(["Modelagem e índices macro — não montados"]).font = { bold: true, size: 12 };
    ws.addRows([
      ["Por quê",
        "Nenhuma das linhas extraídas tem ENTIDADE reconhecida (razão social na coluna das abas de "
        + "demonstração). O modelo é recalculado a partir de uma célula de entidade — sem nenhuma "
        + "para escolher, ele não teria de onde ler número nenhum, e a aba Macro sozinha não "
        + "projetaria nada."],
      ["O que costuma ser",
        "Documentos que chegaram e não produziram linha (ver a aba Resumo: 'Documentos SEM linha "
        + "extraída' e a causa registrada), ou extração que gravou linhas sem identificar a empresa "
        + "— o diagnóstico da IA e o nome do arquivo são as duas fontes de entidade."],
      ["O que fazer",
        "Confira a aba Resumo e a fila de revisão do portal. Depois de aceitar/corrigir a entidade "
        + "de pelo menos um documento, exporte de novo: a Modelagem e a Macro voltam sozinhas."],
      ...(macroErro
        ? [["Nota sobre os índices macro",
            `A consulta dos índices também falhou: "${macroErro}". São problemas independentes — `
            + "este arquivo não montaria a Modelagem mesmo com o macro em ordem."] as [string, string]]
        : []),
    ]);
    for (let r = 2; r <= ws.rowCount; r++) {
      ws.getRow(r).alignment = { wrapText: true, vertical: "top" };
      ws.getRow(r).height = 56;
    }
  }

  // ----- AS ABAS DE DADO SAEM DO EXPORT DE MODELAGEM ------------------------
  //
  // Decisão do dono (07/08/2026): "remova as abas de dados financeiros que não têm
  // relação com a modelagem — todas as que já estão no export da Etapa 1". São dois
  // arquivos com dois propósitos, e o botão de cada um está na tela: *Exportar dados
  // financeiros* (`?modo=dados`) entrega a conferência da ingestão, *Exportar
  // modelagem* entrega o que vai a comitê. Antes o segundo continha o primeiro
  // inteiro: 29 abas, das quais 12 eram dado cru repetido.
  //
  // REMOVER SÓ É SEGURO PORQUE FOI MEDIDO. Aba referenciada que some vira `#REF!` em
  // toda fórmula que apontava para ela — o defeito que o `auditar-xlsx.mts` caça.
  // Medição no arquivo entregue em 07/08 (o mapa de referências cruzadas das 12.244
  // fórmulas): as 14 abas do modelo referenciam APENAS umas às outras — `Anual`,
  // `Premissas`, `Considerações`, `Output` e as demonstrações do próprio modelo. Zero
  // referências às abas de dado. A `Modelagem` não referencia ninguém (recebe VALOR,
  // não fórmula), e a `Macro` referencia só a `Macro (dados)`.
  //
  // O QUE FICA, e por quê: as 14 do modelo (é o produto), a `Modelagem` (é a decisão
  // registrada — entidade, corte, premissas) e o par `Macro`/`Macro (dados)`. O par
  // macro está no export da Etapa 1, mas NÃO é dado financeiro da empresa: é o índice
  // que dirige a projeção, e agora que as premissas são editáveis dentro do Excel,
  // tirá-lo deixaria o arquivo sem a fonte do que ele projeta.
  //
  // A regra é por LISTA DO QUE FICA, não do que sai: aba de dado nova (tipo
  // documental novo) já nasce fora do arquivo de modelagem, sem ninguém lembrar de
  // atualizar lista nenhuma.
  {
    const modeloMontado = ABAS_MODELO.every((a) => workbook.getWorksheet(a));
    // GUARDA: sem o modelo montado não há o que separar, e remover as abas de dado
    // deixaria um arquivo com a `Modelagem` explicando por que está vazia — pior que
    // o arquivo grande. Só se separa quando existe o produto que justifica a
    // separação.
    if (modeloMontado) {
      const fica = new Set<string>([...ABAS_MODELO, ABA_MODELAGEM, ABA_MACRO, ABA_MACRO_DADOS]);
      for (const ws of [...workbook.worksheets]) {
        if (!fica.has(ws.name)) workbook.removeWorksheet(ws.id);
      }
    }
  }

  // ----- ETAPA 4, resolvida: Modelagem PRIMEIRO, nada oculto ----------------
  //
  // Havia uma contradição registrada entre duas decisões suas, e o §7.2 do
  // material de Onboarding a nomeia: a Etapa 4 pedia "todas as abas geradas, com
  // as auxiliares OCULTAS", e no teste v28 você pediu o contrário — "quero todas
  // as abas juntas" — porque **aba oculta foi lida como dado ausente** por quem
  // recebeu o arquivo.
  //
  // As duas queriam a mesma coisa por caminhos opostos: que a Modelagem seja o
  // que se vê ao abrir, sem que o resto pareça inexistente. Dá para ter as duas
  // com ORDEM em vez de visibilidade — a Modelagem vem primeiro na barra de abas
  // e é a aba ativa; as auxiliares seguem atrás, visíveis.
  //
  // Por que a ordem resolve e o `hidden` não resolvia: quem recebe o arquivo não
  // sabe que existem abas escondidas. "Reexibir" só é um clique para quem sabe
  // que há o que reexibir — para todos os outros, o dado simplesmente não está
  // lá. Ordem não tem esse problema: tudo é visível, e a primeira aba é a que
  // importa.
  //
  // A GUARDA de antes continua valendo em espírito: se a Modelagem não existir,
  // não se mexe em nada (não há o que promover, e reordenar por reordenar só
  // embaralharia o arquivo).
  {
    const modelagem = workbook.getWorksheet(ABA_MODELAGEM);
    if (modelagem) {
      // Nenhuma aba oculta. `visible` é reafirmado de propósito: um `.xlsx`
      // gerado por versão anterior deste código podia trazer `hidden` gravado,
      // e o estado explícito aqui é o que garante que ninguém receba um arquivo
      // meio-oculto se o export rodar sobre um workbook reaproveitado.
      for (const ws of workbook.worksheets) ws.state = "visible";

      // A ORDEM das abas no ExcelJS é `orderNo`, não a posição num array:
      // `workbook.worksheets` é um GETTER que devolve `_worksheets.slice(1)
      // .sort(orderNo)`. A primeira versão disto fazia splice no resultado do
      // getter — ou seja, mexia num array descartável e não mudava nada no
      // arquivo. O assert (11) pegou (`modelagem=9` depois de "mover para 0"),
      // que é exatamente o tipo de mudança que passa por feita sem ser.
      //
      // `addWorksheet` numera de 1 em diante, então 0 põe a Modelagem à frente
      // de todas sem tocar no `orderNo` de ninguém — e `id`/nome não mudam,
      // logo nada que referencie aba por nome quebra.
      // `orderNo` é real no runtime do ExcelJS mas não está nos tipos publicados
      // (@types embutido do pacote) — daí o cast pontual, com o motivo escrito
      // para ninguém "limpar" isto achando que é gambiarra.
      (modelagem as unknown as { orderNo: number }).orderNo = 0;

      workbook.views = [{
        // Aba ativa = a Modelagem, agora na primeira posição. `firstSheet: 0`
        // garante que a barra de abas também comece nela.
        activeTab: 0, firstSheet: 0, visibility: "visible",
        x: 0, y: 0, width: 10000, height: 20000,
      }];
    }
  }

  return workbook;
}


// ExcelJS grava a caixa de toda nota (`cell.note`) com um tamanho FIXO no XML
// VML (`width:97.8pt;height:59.1pt`, ~130×80px) — hardcoded no próprio
// pacote (`lib/xlsx/xform/comment/vml-shape-xform.js`), sem parâmetro público
// pra mudar (conferido lendo o fonte, não só o `.d.ts`). É por isso que
// anotações com texto de várias linhas apareciam cortadas ao abrir (pedido do
// dono, sessão 7 cont.¹⁵). Sem editar `node_modules`, o único jeito é
// pós-processar o .xlsx já gerado: ele é um .zip, então abrimos com JSZip
// (já vem como dependência transitiva do próprio exceljs), achamos as partes
// `xl/drawings/vmlDrawing*.vml` e trocamos a string de tamanho fixo por uma
// caixa bem maior, igual para toda nota do workbook (o hardcode do exceljs
// já é idêntico em todas — troca segura por string).
const NOTA_BOX_ANTIGA = "width:97.8pt;height:59.1pt";
const NOTA_BOX_NOVA = "width:340pt;height:170pt";

/** A entrada do modelo institucional COM os subtotais informados, se o workbook montou o modelo. */
export function entradaDoModeloDoWorkbook(workbook: ExcelJS.Workbook): EntradaModeloInstitucional | undefined {
  return (workbook as unknown as { __entradaDoModelo?: EntradaModeloInstitucional }).__entradaDoModelo;
}

/**
 * O ÚNICO CAMINHO DE SAÍDA DO .XLSX ENTREGUE — e ele existe porque duas coisas
 * que o arquivo precisa ter não podem ser escritas pelo ExcelJS:
 *
 *   1. a caixa de nota ampliada (o tamanho é hardcode do pacote);
 *   2. os GRÁFICOS do `Output` (não há API de gráfico no ExcelJS).
 *
 * Antes, a rota chamava `ampliarNotasNoBuffer` e o script de iteração local
 * chamava `writeFile` direto — então o arquivo que o dono recebia e o arquivo que
 * eu media localmente eram DIFERENTES, e a diferença era invisível. Agora as duas
 * pontas chamam esta função, que é a única que sabe montar o entregável.
 */
export async function finalizarBufferDoExport(workbook: ExcelJS.Workbook): Promise<Buffer> {
  const graficos = (workbook as unknown as { __graficosDoModelo?: EspecGrafico[] }).__graficosDoModelo ?? [];
  const comNotas = await ampliarNotasNoBuffer(await workbook.xlsx.writeBuffer());
  return graficos.length > 0 ? injetarGraficosNoBuffer(comNotas, graficos) : comNotas;
}

export async function ampliarNotasNoBuffer(buffer: Buffer | ArrayBuffer): Promise<Buffer> {
  const zip = await JSZip.loadAsync(buffer);
  const vmlPaths = Object.keys(zip.files).filter((p) => /^xl\/drawings\/vmlDrawing\d+\.vml$/.test(p));
  for (const path of vmlPaths) {
    const xml = await zip.file(path)!.async("string");
    if (!xml.includes(NOTA_BOX_ANTIGA)) continue;
    zip.file(path, xml.split(NOTA_BOX_ANTIGA).join(NOTA_BOX_NOVA));
  }
  // COMPRESSÃO EXPLÍCITA. O default do JSZip é `STORE` (sem compressão), e o
  // ExcelJS grava com DEFLATE — então este pós-processamento inflava o arquivo
  // entregue de ~0,3 MB para ~4,3 MB (medido nesta sessão) sem mudar uma célula.
  // O dono baixava um .xlsx 14× maior por causa da regravação do zip.
  return zip.generateAsync({ type: "nodebuffer", compression: "DEFLATE", compressionOptions: { level: 6 } });
}

// Reexportado para eventuais consumidores que só precisem agrupar por conta
// (ex.: uma futura tela de revisão por seção no portal).
export { agruparPorChaveNormalizada };
