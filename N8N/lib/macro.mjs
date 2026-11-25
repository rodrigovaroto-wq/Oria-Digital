// Índices macroeconômicos — coleta, validação cruzada e composição (F2).
//
// Por que isto existe: a aba de Modelagem projeta exercícios futuros a partir de
// premissas, e as premissas mais comuns de um plano de reestruturação são
// macro — inflação que corrige receita e contratos, juro que define o custo da
// dívida. Hoje o analista digita esses números de memória ou de um print; aqui
// eles passam a vir de fonte oficial, versionada e conferida.
//
// TRÊS DECISÕES DE DESENHO, todas com consequência:
//
// 1. HISTÓRICO **e** EXPECTATIVA. A média dos últimos 3/5/10 anos descreve o
//    passado e serve para calibrar; ela NÃO é previsão. Para projetar, o que o
//    mercado usa é o Focus/BCB (mediana das expectativas por ano-calendário).
//    Trazer só o histórico faria o modelo projetar o retrovisor.
//
// 2. COMPOSIÇÃO GEOMÉTRICA, nunca média aritmética. Taxa se compõe: a média de
//    10% e 4% não é 7,00% e sim 6,95% (√(1,10 × 1,04) − 1). Parece detalhe;
//    num horizonte de 10 anos a diferença vira erro material, e é o tipo de
//    erro que ninguém percebe olhando a planilha.
//
// 3. DUAS FONTES PARA O MESMO NÚMERO. O IPCA é publicado pelo IBGE (que o
//    produz) e espelhado pelo BCB/SGS. Divergência entre os dois significa
//    revisão de série ou coleta furada — exatamente a classe de problema que a
//    reconciliação do sistema já trata. Conferir custa uma requisição a mais e
//    é o que autoriza chamar o dado de "validado".

// Séries do SGS/BCB. `natureza` decide como o valor se agrega no tempo:
//   'taxa'  → variação percentual DO MÊS; o ano acumula por composição.
//   'nivel' → um preço/estoque na data (câmbio); o ano é o valor de fechamento
//             e a variação é entre fechamentos. Somar/compor nível é erro.
export const SERIES_MACRO = [
  { codigo: 'IPCA', sgs: 433, nome: 'IPCA (IBGE)', natureza: 'taxa', unidade: '% a.m.',
    descricao: 'Índice oficial de inflação ao consumidor — corrige contratos e define a meta do BCB.' },
  { codigo: 'IGPM', sgs: 189, nome: 'IGP-M (FGV)', natureza: 'taxa', unidade: '% a.m.',
    descricao: 'Índice geral de preços — usado em aluguéis e contratos de longo prazo.' },
  { codigo: 'INPC', sgs: 188, nome: 'INPC (IBGE)', natureza: 'taxa', unidade: '% a.m.',
    descricao: 'Inflação para faixa de renda mais baixa — referência de reajuste salarial.' },
  { codigo: 'SELIC', sgs: 4390, nome: 'Selic acumulada no mês', natureza: 'taxa', unidade: '% a.m.',
    descricao: 'Juro básico efetivamente acumulado no mês (não a meta anual).' },
  { codigo: 'CDI', sgs: 4391, nome: 'CDI acumulado no mês', natureza: 'taxa', unidade: '% a.m.',
    descricao: 'Referência de custo de dívida bancária e de rendimento de aplicação.' },
  // 3698 (fechamento MENSAL), não 1 (PTAX diária). Duas razões, e a segunda é a
  // que importa: (a) a série diária estoura a janela — o SGS responde 406 para
  // 11 anos de dado diário (medido em 2026-07-29), então a coleta do câmbio
  // falhava; (b) todas as outras séries aqui são mensais, e guardar ~2.800
  // observações diárias no meio delas faria "fechamento do ano" depender de qual
  // foi o último dia útil coletado. Com a mensal, o fechamento do ano é dezembro,
  // que é a convenção que um modelo usa.
  { codigo: 'CAMBIO_USD', sgs: 3698, nome: 'Câmbio R$/US$ (venda, fim de período)', natureza: 'nivel', unidade: 'R$',
    descricao: 'Taxa de câmbio de fechamento do mês — relevante quando há receita, custo ou dívida em dólar.' },
];

export function serieMacro(codigo) {
  return SERIES_MACRO.find((s) => s.codigo === codigo) ?? null;
}

// Indicadores do Focus (Expectativas de Mercado). O nome tem de bater com o
// campo `Indicador` da API — por isso ficam explícitos aqui e não derivados.
export const INDICADORES_FOCUS = [
  { codigo: 'IPCA', indicador: 'IPCA', unidade: '% a.a.' },
  { codigo: 'SELIC', indicador: 'Selic', unidade: '% a.a.' },
  { codigo: 'IGPM', indicador: 'IGP-M', unidade: '% a.a.' },
  { codigo: 'PIB', indicador: 'PIB Total', unidade: '% a.a.' },
  { codigo: 'CAMBIO_USD', indicador: 'Câmbio', unidade: 'R$/US$' },
];

const SGS_BASE = 'https://api.bcb.gov.br/dados/serie/bcdata.sgs';
const FOCUS_BASE = 'https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata/ExpectativasMercadoAnuais';
const SIDRA_BASE = 'https://apisidra.ibge.gov.br/values';

// Janela por DATA, não por "últimos N".
//
// A primeira versão pedia `/dados/ultimos/132` com a justificativa de que seria
// "mais robusto que um intervalo de datas". É o contrário, e medido: o SGS
// responde **HTTP 400** para `ultimos/N` com N acima de ~20 (conferido em
// 2026-07-29 nas séries 433, 4390, 1 e 189 — 20 responde 200, 22 já responde
// 400), enquanto o intervalo de datas devolve 11 anos sem reclamar. Ou seja: a
// coleta falhava em TODAS as séries, e o sintoma que o dono via era a aba Macro
// vazia — não havia como distinguir isso de "workflow não ativado".
//
// `dataFinal` fica de fora de propósito: sem ela o SGS devolve até a última
// observação publicada, então a URL não envelhece nem depende do relógio de quem
// chama. A data inicial é o único parâmetro, e a gravação é idempotente por
// (serie, data_ref, fonte) — reprocessar meses já gravados não duplica nada.
export function urlSgs(codigoSgs, { mesesAtras = 132, hoje = new Date() } = {}) {
  const inicio = new Date(Date.UTC(hoje.getUTCFullYear(), hoje.getUTCMonth() - mesesAtras + 1, 1));
  const dd = String(inicio.getUTCDate()).padStart(2, '0');
  const mm = String(inicio.getUTCMonth() + 1).padStart(2, '0');
  return `${SGS_BASE}.${codigoSgs}/dados?formato=json&dataInicial=${dd}%2F${mm}%2F${inicio.getUTCFullYear()}`;
}

// dd/MM/yyyy (formato do SGS) → ISO. Data inválida devolve null em vez de uma
// data errada: uma observação sem data não pode entrar na série.
function dataSgsParaIso(bruto) {
  const m = String(bruto ?? '').match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  return m ? `${m[3]}-${m[2]}-${m[1]}` : null;
}

// Número em notação BR ou EN → Number. O SGS devolve "0.67" (ponto decimal),
// mas séries antigas e outras fontes usam vírgula; aceitar os dois evita uma
// classe inteira de bug silencioso (o valor vira NaN e some da série).
export function numeroMacro(bruto) {
  if (typeof bruto === 'number') return Number.isFinite(bruto) ? bruto : null;
  const t = String(bruto ?? '').trim();
  if (!t) return null;
  const n = Number(t.includes(',') ? t.replace(/\./g, '').replace(',', '.') : t);
  return Number.isFinite(n) ? n : null;
}

export function parseSgs(json, codigo) {
  if (!Array.isArray(json)) return [];
  return json
    .map((o) => ({
      serie: codigo,
      fonte: 'BCB/SGS',
      data_ref: dataSgsParaIso(o?.data),
      valor: numeroMacro(o?.valor),
    }))
    .filter((o) => o.data_ref && o.valor !== null);
}

// Qual das DUAS medianas do Focus este projeto usa.
//
// O Olinda devolve, para o MESMO (indicador, ano de referência, data de
// coleta), duas linhas com medianas diferentes:
//   • `baseCalculo = 0` — estatísticas sobre as expectativas dos últimos 30
//     dias. Mais respondentes, mais estável. É a base da tabela principal do
//     Boletim Focus.
//   • `baseCalculo = 1` — últimos 5 dias úteis. Reage mais rápido e oscila
//     mais; serve para acompanhar virada de expectativa, não para fixar
//     premissa de um modelo que vai ser auditado.
//
// Sem filtro, `parseFocus` ficava com "a que o servidor devolvesse primeiro"
// (o primeiro `if (!porAno.has(ano))` vence) — isto é, a premissa de inflação
// do modelo mudava conforme a ordem de uma resposta HTTP. Não é erro grande em
// magnitude; é irreprodutível, que numa entrega auditável é pior.
export const FOCUS_BASE_CALCULO = 0;

// `$top` grande o bastante para a coleta mais recente trazer todos os anos de
// horizonte de todos os indicadores. Era 40 aqui e 80 no gerador do workflow —
// duas verdades para o mesmo número, e a do seed truncava antes.
export const FOCUS_TOP = 80;

// Focus: só o boletim MAIS RECENTE interessa (a API devolve o histórico inteiro
// de coletas). `$orderby` decrescente + `$top` resolve sem baixar tudo.
export function urlFocus(indicador, { top = FOCUS_TOP, baseCalculo = FOCUS_BASE_CALCULO } = {}) {
  const filtro = encodeURIComponent(`Indicador eq '${indicador}' and baseCalculo eq ${baseCalculo}`);
  return `${FOCUS_BASE}?$top=${top}&$format=json&$orderby=Data%20desc&$filter=${filtro}`;
}

export function parseFocus(json, codigo) {
  const linhas = Array.isArray(json?.value) ? json.value : [];
  if (linhas.length === 0) return [];
  // Uma coleta traz vários anos de referência; ficamos com a data de coleta mais
  // recente presente na resposta e com um registro por ano.
  const maisRecente = linhas.reduce((a, l) => (l?.Data > a ? l.Data : a), '');
  const porAno = new Map();
  for (const l of linhas) {
    if (l?.Data !== maisRecente) continue;
    // Segunda guarda, e não é redundante: o filtro da URL protege a COLETA, esta
    // protege o PARSE de qualquer resposta que traga as duas bases (um seed
    // antigo, uma chamada à mão, uma mudança de default do Olinda). Sem ela,
    // duas linhas do mesmo ano com medianas diferentes fazem a primeira vencer
    // — e "a primeira" é a ordem de uma resposta HTTP, não uma decisão.
    // `undefined` passa: resposta que não traz o campo é a de antes deste
    // filtro existir, e descartá-la esvaziaria a série em silêncio.
    if (l?.baseCalculo !== undefined && Number(l.baseCalculo) !== FOCUS_BASE_CALCULO) continue;
    const ano = Number(l?.DataReferencia);
    const mediana = numeroMacro(l?.Mediana);
    if (!Number.isInteger(ano) || mediana === null) continue;
    if (!porAno.has(ano)) {
      porAno.set(ano, {
        serie: codigo,
        fonte: 'BCB/Focus',
        ano_ref: ano,
        mediana,
        media: numeroMacro(l?.Media),
        respondentes: Number.isFinite(l?.numeroRespondentes) ? l.numeroRespondentes : null,
        coletado_em: maisRecente,
      });
    }
  }
  return [...porAno.values()].sort((a, b) => a.ano_ref - b.ano_ref);
}

// IBGE/SIDRA — tabela 1737, variável 63 = IPCA variação mensal. É a fonte
// PRIMÁRIA do índice (o BCB espelha); serve de contraprova.
export function urlSidraIpca({ ultimos = 24 } = {}) {
  return `${SIDRA_BASE}/t/1737/n1/all/v/63/p/last%20${ultimos}`;
}

export function parseSidraIpca(json) {
  if (!Array.isArray(json)) return [];
  // A primeira linha do SIDRA é o cabeçalho descritivo, não dado.
  return json
    .slice(1)
    .map((o) => {
      const periodo = String(o?.D3C ?? ''); // "202604"
      const m = periodo.match(/^(\d{4})(\d{2})$/);
      return {
        serie: 'IPCA',
        fonte: 'IBGE/SIDRA',
        data_ref: m ? `${m[1]}-${m[2]}-01` : null,
        valor: numeroMacro(o?.V),
      };
    })
    .filter((o) => o.data_ref && o.valor !== null);
}

// ---------------------------------------------------------------------------
// Validação cruzada. Duas fontes para o MESMO mês do MESMO índice têm de bater;
// divergência é revisão de série ou coleta furada. Tolerância em pontos
// percentuais porque os valores JÁ são percentuais (0,01 p.p. = arredondamento
// de publicação, não discordância).
// ---------------------------------------------------------------------------
export function divergenciasEntreFontes(serieA, serieB, tolerancia = 0.011) {
  const porData = new Map(serieB.map((o) => [o.data_ref, o]));
  const fora = [];
  for (const a of serieA) {
    const b = porData.get(a.data_ref);
    if (!b) continue; // mês só numa fonte não é divergência: é cobertura diferente
    const delta = Math.abs(a.valor - b.valor);
    if (delta > tolerancia) {
      fora.push({
        serie: a.serie, data_ref: a.data_ref, delta,
        fontes: { [a.fonte]: a.valor, [b.fonte]: b.valor },
      });
    }
  }
  return fora;
}

// ---------------------------------------------------------------------------
// Composição. Estas duas funções existem para o TESTE e para o SQL; na planilha
// o mesmo cálculo é refeito em FÓRMULA (regra do dono: o que dá para ser
// fórmula, é fórmula). Ter os dois lados é o que permite provar que a fórmula
// da planilha calcula a coisa certa.
// ---------------------------------------------------------------------------

// Acumula taxas percentuais por composição: [0.5, 0.3] → 0.8015%.
export function acumularTaxas(taxasPercentuais) {
  const fator = taxasPercentuais.reduce((acc, t) => acc * (1 + t / 100), 1);
  return (fator - 1) * 100;
}

// Retorno acumulado de cada ANO-CALENDÁRIO a partir das observações mensais.
// Ano incompleto é devolvido com `meses < 12` — quem consome decide se usa;
// tratá-lo como ano cheio distorceria qualquer média.
export function retornoAnual(observacoes) {
  const porAno = new Map();
  for (const o of observacoes) {
    const ano = Number(String(o.data_ref).slice(0, 4));
    if (!Number.isInteger(ano)) continue;
    if (!porAno.has(ano)) porAno.set(ano, []);
    porAno.get(ano).push(o.valor);
  }
  return [...porAno.entries()]
    .map(([ano, taxas]) => ({ ano, meses: taxas.length, retorno: acumularTaxas(taxas) }))
    .sort((a, b) => a.ano - b.ano);
}

// Média GEOMÉTRICA de retornos anuais — a única correta para taxa. Só considera
// anos completos: incluir um ano de 3 meses como se fosse cheio puxa a média
// para baixo sem que ninguém veja.
export function mediaAnualGeometrica(retornosAnuais, janela) {
  const cheios = retornosAnuais.filter((r) => r.meses === 12);
  if (cheios.length < janela) return null; // sem histórico suficiente: não inventa
  const ultimos = cheios.slice(-janela);
  const fator = ultimos.reduce((acc, r) => acc * (1 + r.retorno / 100), 1);
  return (Math.pow(fator, 1 / janela) - 1) * 100;
}


// ---------------------------------------------------------------------------
// REGISTRO DA CONSULTA (A3, fatia 0): o desfecho CRU de cada chamada HTTP do macro
// vai para fn_registrar_consulta_externa (0303), que é quem classifica.
//
// Por que existe: o macro rodava mensal e nada registrava que rodou — "rodou e
// não achou nada" e "não rodou" tinham a mesma cara (regra 7). E um 500 do BCB com
// neverError chegava como corpo, o Normalizar descartava, e só o throw do "zero
// observação" aparecia, sem dizer QUAL série nem com que status.
//
// Estas funções são EMBUTIDAS nos nós Code pelo gerador (Function.toString), como
// numeroMacro: nó Code do n8n não importa arquivo. Por isso cada uma é
// autocontida (só chama as outras desta seção e numeroMacro, que o gerador
// embute junto) e os comentários aqui dentro NÃO podem ter crase nem dólar-chave
// (fecharia ou interpolaria o template literal do gerador).
//
// Contrato com o nó HTTP: options.response.response = { fullResponse: true,
// neverError: true, responseFormat: 'text', outputPropertyName: <campo> }. Isso entrega UM
// item por chamada com { headers, statusCode, statusMessage, [campo]: texto cru } — sem o
// split do array em N itens e com o corpo exato de que o hash é a prova de leitura.
// ATENÇÃO (defeito achado na revisão): com responseFormat text + fullResponse, o n8n NÃO
// entrega o corpo em "body": entrega em outputPropertyName, cujo default é "data"
// (HttpRequestV3.node.ts, ramo responseFormat text). Por isso o campo é parâmetro desta
// função e o gerador o fixa EXPLÍCITO no nó e o passa a cada nó Ler: um lado sem o outro
// lê null e grava 'falhou' com motivo falso em toda consulta. Chamada que nem respondeu
// (timeout, DNS) chega pelo onError continueRegularOutput como { error }.
// ---------------------------------------------------------------------------

// Desfecho cru -> { http_status, erro, corpo, json }. NUNCA lança.
//   - sem resposta        -> http_status null + erro com o motivo (a função grava falhou)
//   - 2xx vazio/não-JSON  -> http_status 2xx + erro (a função grava falhou)
//   - fora de 2xx         -> http_status real, erro null (a função grava falhou "HTTP 500")
// Um 2xx sem erro tem json parseado: é o único caso em que o chamador pode montar itens.
export function lerRespostaHttp(r, campo) {
  const j = r || {};
  const nomeCorpo = campo || 'data';
  if (j.statusCode === undefined && j.error !== undefined) {
    const e = j.error;
    const msg = typeof e === 'string' ? e : (e && (e.message || e.description)) || JSON.stringify(e);
    return { http_status: null, erro: 'sem resposta HTTP: ' + String(msg).slice(0, 300), corpo: null, json: null };
  }
  const st = Number(j.statusCode);
  if (!Number.isInteger(st)) {
    return { http_status: null, erro: 'a resposta do nó HTTP veio sem statusCode', corpo: null, json: null };
  }
  const corpo = typeof j[nomeCorpo] === 'string' ? j[nomeCorpo] : null;
  if (st < 200 || st > 299) return { http_status: st, erro: null, corpo, json: null };
  if (corpo === null) return { http_status: st, erro: 'HTTP ' + st + ' com corpo que não veio como texto cru', corpo, json: null };
  if (corpo.trim() === '') return { http_status: st, erro: 'HTTP ' + st + ' com corpo vazio', corpo, json: null };
  try {
    return { http_status: st, erro: null, corpo, json: JSON.parse(corpo) };
  } catch (e) {
    return { http_status: st, erro: 'HTTP ' + st + ' com corpo que não é JSON', corpo, json: null };
  }
}

// SGS: uma consulta por SÉRIE chamada. Itens = RESUMO {ultimo_mes, n} (1 fato por
// consulta), não as ~132 observações: estas já vão para indice_macro_obs.
// Zero observação válida num 2xx nunca vira "nada encontrado": o SGS devolve 132
// meses em toda chamada, então zero é resposta inesperada (mesmo critério do throw do Normalizar).
// `opcoes` (A3 fatia 1, juros por modalidade) reusa este mesmo parse do SGS sem duplicá-lo:
// { fonte, itens } troca a fonte do catálogo e monta os itens a partir das observações
// válidas [{ data_ref: 'AAAA-MM-01', valor }]. Sem opcoes o comportamento é o de antes.
export function consultaSgs(resp, serie, opcoes) {
  const op = opcoes || {};
  const l = lerRespostaHttp(resp, op.campo);
  const c = { fonte: op.fonte || 'bcb_sgs', http_status: l.http_status, erro: l.erro, corpo: l.corpo, itens: null, registros_lidos: null };
  if (l.erro !== null || l.http_status < 200 || l.http_status > 299) return { consulta: c, dado: null };
  if (!Array.isArray(l.json)) {
    c.erro = 'HTTP ' + l.http_status + ' com JSON que não é a lista de observações do SGS';
    return { consulta: c, dado: null };
  }
  let n = 0, ultimo = '';
  const validas = [];
  for (const o of l.json) {
    const m = String((o && o.data) || '').match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
    if (m && numeroMacro(o.valor) !== null) {
      n++; const iso = m[3] + '-' + m[2]; if (iso > ultimo) ultimo = iso;
      validas.push({ data_ref: m[3] + '-' + m[2] + '-' + m[1], valor: numeroMacro(o.valor) });
    }
  }
  c.registros_lidos = l.json.length;
  if (n === 0) {
    c.erro = 'HTTP ' + l.http_status + ' sem nenhuma observação válida em ' + l.json.length + ' itens lidos';
    return { consulta: c, dado: null };
  }
  c.itens = typeof op.itens === 'function' ? op.itens(validas) : [{ chave: serie, valor: { ultimo_mes: ultimo, n } }];
  return { consulta: c, dado: l.json };
}

// Focus: uma consulta por INDICADOR chamado. Resumo = {coletado_em, n_anos} da coleta mais recente.
export function consultaFocus(resp, indicador, opcoes) {
  const l = lerRespostaHttp(resp, (opcoes || {}).campo);
  const c = { fonte: 'bcb_focus', http_status: l.http_status, erro: l.erro, corpo: l.corpo, itens: null, registros_lidos: null };
  if (l.erro !== null || l.http_status < 200 || l.http_status > 299) return { consulta: c, dado: null };
  const linhas = l.json && Array.isArray(l.json.value) ? l.json.value : null;
  if (linhas === null) {
    c.erro = 'HTTP ' + l.http_status + ' com JSON sem a lista value do Olinda';
    return { consulta: c, dado: null };
  }
  let recente = '';
  for (const x of linhas) { if (x && x.Data > recente) recente = x.Data; }
  const anos = {};
  for (const x of linhas) {
    if (x && x.Data === recente && Number.isInteger(Number(x.DataReferencia)) && numeroMacro(x.Mediana) !== null) anos[x.DataReferencia] = 1;
  }
  const nAnos = Object.keys(anos).length;
  c.registros_lidos = linhas.length;
  if (nAnos === 0) {
    c.erro = 'HTTP ' + l.http_status + ' sem nenhuma expectativa válida em ' + linhas.length + ' linhas lidas';
    return { consulta: c, dado: null };
  }
  c.itens = [{ chave: indicador, valor: { coletado_em: recente, n_anos: nAnos } }];
  return { consulta: c, dado: l.json };
}

// SIDRA: uma consulta (IPCA). A primeira linha é o cabeçalho descritivo, não dado.
export function consultaSidra(resp, opcoes) {
  const l = lerRespostaHttp(resp, (opcoes || {}).campo);
  const c = { fonte: 'ibge_sidra', http_status: l.http_status, erro: l.erro, corpo: l.corpo, itens: null, registros_lidos: null };
  if (l.erro !== null || l.http_status < 200 || l.http_status > 299) return { consulta: c, dado: null };
  if (!Array.isArray(l.json)) {
    c.erro = 'HTTP ' + l.http_status + ' com JSON que não é a lista do SIDRA';
    return { consulta: c, dado: null };
  }
  let n = 0, ultimo = '';
  for (const o of l.json.slice(1)) {
    const m = String((o && o.D3C) || '').match(/^(\d{4})(\d{2})$/);
    if (m && numeroMacro(o.V) !== null) { n++; const ym = m[1] + '-' + m[2]; if (ym > ultimo) ultimo = ym; }
  }
  c.registros_lidos = l.json.length;
  if (n === 0) {
    c.erro = 'HTTP ' + l.http_status + ' sem nenhum mês válido em ' + l.json.length + ' linhas lidas';
    return { consulta: c, dado: null };
  }
  c.itens = [{ chave: 'IPCA', valor: { ultimo_mes: ultimo, n } }];
  return { consulta: c, dado: l.json };
}

// ---------------------------------------------------------------------------
// A3 fatia 1 — BCB, taxa MÉDIA de juros por modalidade, PJ (SGS, % a.a., mensal).
// Fonte do catálogo: bcb_juros_modalidade. É a média PONDERADA do mercado (decisão do
// dono, 25/11/2026), não a taxa banco a banco da Olinda. NÃO vai para indice_macro_obs: o
// export lista toda série dali na aba Macro do cliente (portal export-modelagem.ts:236),
// e série nova mudaria o arquivo (é a A5). Vai para fato_externo, 1 fato por série-mês.
//
// SUBCONJUNTO (19 de 24 códigos conferidos no CKAN do BCB em 25/11/2026): as 18
// modalidades-FOLHA mais o total PJ (20715) como referência. Ficam de fora os totais que
// são soma de folhas já incluídas: 20718 (livres), 20725 (capital de giro), 20730
// (aquisição de bens), 20733 (arrendamento), 20757 (direcionados). Eles dobrariam linhas
// que o analista recompõe, e o total PJ já dá o nível geral. Se a Fase C quiser um total
// de grupo, a conta fica na leitura, não numa linha a mais por dia.
// ---------------------------------------------------------------------------
export const JUROS_PJ_SGS = [
  { sgs: 20715, nome: 'PJ total (livres + direcionados)' },
  { sgs: 20719, nome: 'Desconto de duplicatas e recebíveis' },
  { sgs: 20720, nome: 'Desconto de cheques' },
  { sgs: 20721, nome: 'Antecipação de faturas de cartão de crédito' },
  { sgs: 20722, nome: 'Capital de giro até 365 dias' },
  { sgs: 20723, nome: 'Capital de giro acima de 365 dias' },
  { sgs: 20724, nome: 'Capital de giro rotativo' },
  { sgs: 20726, nome: 'Conta garantida' },
  { sgs: 20727, nome: 'Cheque especial' },
  { sgs: 20728, nome: 'Aquisição de veículos' },
  { sgs: 20729, nome: 'Aquisição de outros bens' },
  { sgs: 20731, nome: 'Arrendamento mercantil de veículos' },
  { sgs: 20732, nome: 'Arrendamento mercantil de outros bens' },
  { sgs: 20734, nome: 'Vendor' },
  { sgs: 20735, nome: 'Compror' },
  { sgs: 20736, nome: 'Adiantamento sobre contratos de câmbio (ACC)' },
  { sgs: 20737, nome: 'Financiamento a importações' },
  { sgs: 20738, nome: 'Financiamento a exportações' },
  { sgs: 20739, nome: 'Repasse externo' },
];

// JANELA por execução: os 2 últimos meses (o último publicado + a revisão do anterior).
// TETO conhecido: fato_externo é imutável e cresce todo dia (a mesma janela é
// registrada de novo a cada execução), com o banco em 112 MB de 500 MB no plano gratuito.
// Medido pelo gerador: 19 consultas + 38 fatos = 57 linhas/dia. Subir a janela multiplica
// as linhas (3 meses = 76 fatos/dia). O histórico só começa no dia em que o workflow
// passou a rodar; carga de histórico longo é fatia futura, se a Fase C pedir.
export const JANELA_JUROS_MESES = 2;

// O endpoint ultimos/N não depende do relógio de quem gera (o gerador é determinístico).
// O SGS recusa N alto (HTTP 400 acima de ~20, medido em 2026-07-29; ver urlSgs): 2 é seguro.
export function urlSgsUltimos(codigoSgs, n = JANELA_JUROS_MESES) {
  return `${SGS_BASE}.${codigoSgs}/dados/ultimos/${n}?formato=json`;
}

// Itens da consulta: um fato por mês lido. chave 'sgs:<código>'; valor com a data, a taxa
// % a.a. e o nome da série; referencia = código.mês, que identifica o ponto sem a URL.
export function itensJuros(sgs, nome) {
  return function (validas) {
    return validas.map(function (o) {
      return {
        chave: 'sgs:' + sgs,
        valor: { data_ref: o.data_ref, taxa_aa: o.valor, serie: nome },
        referencia: 'sgs.' + sgs + ':' + o.data_ref.slice(0, 7),
      };
    });
  };
}

// ---------------------------------------------------------------------------
// A3 fatia 2 — BCB/SGS (fonte bcb_sgs): atividade, crédito/inadimplência PJ e euro.
// Destino fato_externo (NÃO indice_macro_obs: a aba Macro do cliente é a A5), mesma
// janela e mesmo desenho da fatia 1 (uma consulta por série, na corrente linear).
//
// SÓ ENTRA SÉRIE COM NOME CONFIRMADO POR FONTE DO BCB (regra 1: nunca rotular por suposição):
//  - 24363, 24364, 20540, 21083, 21086: título e conceito lidos no CKAN do BCB (dadosabertos).
//  - 21619: o CKAN não a indexa. Confirmada pelo VALOR contra a API PTAX do próprio BCB
//    (Olinda, CotacaoMoedaDia, EUR, boletim "Fechamento PTAX", cotacaoVenda): 24/11/2026
//    = 6,4260 e 23/11/2026 = 6,5076 nas DUAS fontes, exatos. Quem lê o nome pelo valor deve
//    saber disso: o rótulo vem da identidade de valor, não de um texto de catálogo.
//    (21620, a compra, bate com cotacaoCompra: 6,4248 e 6,5057.)
// FICA FORA: 192 (suposição: INCC % a.m.; responde 0,22 e 0,37 em set/out 2026, mas o CKAN
// não a indexa, a página de metadados do SGS estava fora do ar em 25/11/2026 e nenhuma outra
// fonte do BCB a traz: nome NÃO confirmado) e 7458 (parou em 2025).
//
// UNIDADE e NATUREZA vão em cada fato, para o leitor não adivinhar se compõe: nenhuma
// destas séries compõe nem soma no tempo (compoe: false). 20540 tem unidade NULA de
// propósito: o conceito do BCB diz "saldo em final de período" mas não a unidade, e
// R$ milhões seria suposição. O fato diz isso em vez de afirmar uma unidade.
// ---------------------------------------------------------------------------
export const SGS_EXTRA = [
  { sgs: 24363, nome: 'IBC-Br (Índice de Atividade Econômica do Banco Central)', natureza: 'indice', unidade: 'índice', periodicidade: 'mensal' },
  { sgs: 24364, nome: 'IBC-Br com ajuste sazonal', natureza: 'indice', unidade: 'índice', periodicidade: 'mensal' },
  { sgs: 20540, nome: 'Saldo da carteira de crédito, pessoas jurídicas, total', natureza: 'estoque', unidade: null, periodicidade: 'mensal' },
  { sgs: 21083, nome: 'Inadimplência da carteira de crédito (atraso acima de 90 dias), pessoas jurídicas, total', natureza: 'proporcao', unidade: '% da carteira', periodicidade: 'mensal' },
  { sgs: 21086, nome: 'Inadimplência da carteira de crédito com recursos livres (atraso acima de 90 dias), pessoas jurídicas, total', natureza: 'proporcao', unidade: '% da carteira', periodicidade: 'mensal' },
  { sgs: 21619, nome: 'Euro, PTAX de fechamento, venda', natureza: 'cotacao', unidade: 'R$/EUR', periodicidade: 'diaria' },
];

// JANELA por observação, por periodicidade. Mensal: 2 (o último publicado + a revisão do
// anterior), igual à fatia 1. Diária: 5 observações (~1 semana útil: cobre feriado e um dia
// sem coleta). TETO: fato_externo é imutável e a janela é re-registrada todo dia; medido pelo
// gerador, 5 mensais x 2 + 1 diária x 5 = 15 fatos + 6 consultas = 21 linhas/dia. Histórico
// longo é fatia futura, se a Fase C pedir.
export const JANELA_SGS_EXTRA = { mensal: JANELA_JUROS_MESES, diaria: 5 };

// Itens: um fato por observação. data_ref é a data DA observação: dia 1 do mês nas mensais
// (convenção do SGS) e o dia real na diária; periodicidade diz qual das duas é.
export function itensSgsExtra(sgs, meta) {
  return function (validas) {
    return validas.map(function (o) {
      return {
        chave: 'sgs:' + sgs,
        valor: {
          data_ref: o.data_ref, valor: o.valor, unidade: meta.unidade, natureza: meta.natureza,
          compoe: false, periodicidade: meta.periodicidade, serie: meta.nome,
        },
        referencia: 'sgs.' + sgs + ':' + (meta.periodicidade === 'diaria' ? o.data_ref : o.data_ref.slice(0, 7)),
      };
    });
  };
}

// ---------------------------------------------------------------------------
// A3 fatia 4 — IBGE/SIDRA setorial (fonte ibge_sidra): PIB, indústria, varejo, serviços e
// emprego por setor. Destino fato_externo (NÃO indice_macro_obs: a aba Macro do cliente é a A5),
// mesmo desenho das fatias 1 e 2: uma consulta por série, só registro, na corrente linear
// ANTES de qualquer nó que lance. Tabelas, variáveis e periodicidade conferidas na API de
// metadados do IBGE e chamadas de verdade em 25/11/2026 (HTTP 200). O NOME da série não é
// digitado aqui: vem do D2N que o próprio SIDRA devolve em cada linha (regra 1: nunca rotular
// por suposição). Sem os 4 níveis do SIDRA fixos: a categoria SETORIAL é a ÚLTIMA dimensão Dn
// do cabeçalho (PMC/PMS por atividade têm duas classificações, as outras uma).
//
// JANELA: p/last 2 = o último período + a revisão do anterior (igual à fatia 1). TETO conhecido:
// fato_externo é imutável e a mesma janela é re-registrada todo dia. Medido na resposta real
// de 25/11/2026: 44 + 54 + 2 + 22 + 58 + 22 = 202 fatos + 6 consultas = 208 linhas/dia
// (o teste afirma 202). Com os 209 B médios por linha medidos em produção (pg_column_size), o
// fato desta fonte é maior (categoria e nome da série vão no valor: 357 B só de chave, valor e referência, medidos nas 202 linhas reais; ~400 B com a linha): ~202 x 400 B
// = ~80 KB/dia = ~29 MB/ano de 500 MB (banco em 112 MB). Subir a janela multiplica as linhas
// (3 períodos = 303 fatos/dia). Histórico longo é fatia futura, se a Fase C pedir.
// ---------------------------------------------------------------------------
export const JANELA_SIDRA_SETORIAL = 2;

// AGREGADOS: as categorias que CONTÊM outras categorias da mesma resposta (total, seção, grupo).
// Achado MÉDIO da revisão de 7e2b1f8: no emprego (6323, Mil pessoas, grandeza que SE SOMA) o Total
// vinha junto das componentes sem marca, e a soma de todos os fatos de um período dava o dobro
// (202608: Total 103477; componentes 103439). O fato leva agregado: true|false, e quem soma
// entre categorias soma só agregado false. Origem de cada lista, conferida em 25/11/2026:
//  - 8688, 8882, 6323: a hierarquia do metadado do IBGE (servicodados /agregados/<t>/metadados:
//    categoria seguida de outra de nível maior é pai).
//  - 5932 e 8888: o metadado põe todas no nível 0; a lista vem do nome e da numeração da própria
//    categoria (5932: "Indústria - total", "Serviços - total", "Valor adicionado a preços
//    básicos", "PIB a preços de mercado"; 8888: "1 Indústria geral", "3 Indústrias de
//    transformação", que contém as 3.xx). "Agropecuária - total" NÃO entra: não há subsetor dela.
//  - 8880: uma categoria só.
// TETO: se o IBGE renumerar uma categoria, o código some da lista sem erro e o fato sai com
// agregado false; o teste com a resposta real acusa código da lista ausente da resposta.
//
// ÓTICA (só a 5932). Achado MÉDIO da revisão final do PR #318: lá as folhas (agregado false) NÃO
// formam UMA partição, formam DUAS do mesmo PIB: a da oferta (setores + impostos líquidos) e a da
// demanda (consumo das famílias e do governo, FBCF, exportação e importação). FBCF não é "setor", e
// tratar as duas como uma lista mistura componentes de identidades diferentes. O fato leva otica:
// 'oferta' | 'demanda' | 'ambas' (o PIB, total das duas), SÓ para código das listas abaixo; código
// fora delas (o IBGE renumerou ou acrescentou, ex.: "Variação de estoques") sai com otica NULA, nunca
// com um rótulo por exclusão (regra 1). Nas outras tabelas, otica é nula: há uma partição só.
//
// SOMA ENTRE CATEGORIAS (revisão de 339fee0): só faz sentido em grandeza que se soma. Hoje só a 6323
// (unidade "Mil pessoas"); PIB, PIM, PMC e PMS são TAXAS em % (variação contra o mesmo período do ano
// anterior) e não se somam entre setores: na 5932 real, a soma das folhas da oferta dá 36,6 em 202602
// contra um PIB de 2,0. Quem agrega taxa pondera, e o peso não está aqui. Onde a soma vale, a regra é:
// só agregado false E da mesma otica. E o V da importação é a variação do volume (positivo, 5,5 em
// 202602), não uma parcela com sinal: aplicar sinal negativo inverteria o número.
// Códigos conferidos no metadado do IBGE de 25/11/2026 (todas as 22 categorias no nível 0).
export const SIDRA_SETORIAL = [
  { tabela: 5932, variavel: 6561, classes: '/c11255/all', periodicidade: 'trimestral',
    agregados: ['90691', '90696', '90705', '90707'],
    otica: {
      oferta: ['90687', '90691', '90692', '90693', '90695', '90694', '90696', '90697', '90698', '90699',
        '90700', '90702', '90701', '90703', '90705', '90706'],
      demanda: ['93404', '93405', '93406', '93407', '93408'],
      ambas: ['90707'],
    } },
  { tabela: 8888, variavel: 11602, classes: '/c544/all', periodicidade: 'mensal', agregados: ['129314', '129316'] },
  { tabela: 8880, variavel: 11709, classes: '/c11046/56734', periodicidade: 'mensal', agregados: [] },
  { tabela: 8882, variavel: 11709, classes: '/c11046/56734/c85/all', periodicidade: 'mensal', agregados: ['90672', '2759'] },
  { tabela: 8688, variavel: 11624, classes: '/c11046/56726/c12355/all', periodicidade: 'mensal',
    agregados: ['107071', '106869', '106870', '106874', '31397', '31399', '31421', '106876', '31422', '31426'] },
  // PNAD Contínua: trimestre MÓVEL (o código D3C AAAAMM é o último mês do trimestre).
  { tabela: 6323, variavel: 4090, classes: '/c888/all', periodicidade: 'trimestre_movel', agregados: ['47946'] },
];

export function urlSidraSetorial(s, n = JANELA_SIDRA_SETORIAL) {
  return `${SIDRA_BASE}/t/${s.tabela}/n1/all/v/${s.variavel}/p/last%20${n}${s.classes}`;
}

// Uma consulta por série. A primeira linha do SIDRA é o cabeçalho descritivo, não dado.
// Valor ausente ou sigiloso ("-", "..", "...", "X") NÃO vira fato e nunca vira 0
// (numeroMacro devolve null); as linhas assim são CONTADAS e o número, mais onde
// ocorreram, vai em cada fato da consulta (ausentes_na_consulta, ausentes_em), para o
// leitor saber que a série tem buraco em vez de supor completude. Zero fato num 2xx
// nunca vira "nada encontrado": é erro (falhou), como em consultaSgs.
// O ÚLTIMO MÊS coberto pelo período, AAAA-MM: a chave que compara séries de periodicidades
// diferentes. Achado BAIXO da revisão de 7e2b1f8: "202602" é fevereiro na PIM e o 2º trimestre no
// PIB, e o cruzamento por periodo casava um com o outro. Trimestral (AAAA0T) -> mês 3T; mensal e
// trimestre móvel (o código já é o último mês) -> o próprio mês. Periodicidade desconhecida ou
// código fora do formato -> null (nunca um mês adivinhado).
export function mesFinalSidra(per, periodicidade) {
  const mm = String(per || '').match(/^(\d{4})(\d{2})$/);
  if (!mm) return null;
  if (periodicidade === 'trimestral') {
    const t = Number(mm[2]);
    return t >= 1 && t <= 4 ? mm[1] + '-' + String(t * 3).padStart(2, '0') : null;
  }
  if (periodicidade === 'mensal' || periodicidade === 'trimestre_movel') {
    const mes = Number(mm[2]);
    return mes >= 1 && mes <= 12 ? mm[1] + '-' + mm[2] : null;
  }
  return null;
}

// A ótica do código pelas listas da série; código que nenhuma lista cita -> null (nunca por exclusão).
export function oticaSidra(otica, cod) {
  if (!otica) return null;
  for (const o of ['oferta', 'demanda', 'ambas']) { if ((otica[o] || []).indexOf(cod) >= 0) return o; }
  return null;
}

export function consultaSidraSetorial(resp, meta, opcoes) {
  const m = meta || {};
  const l = lerRespostaHttp(resp, (opcoes || {}).campo);
  // QUAL série caiu vai no erro de TODO caminho de falha (revisão de 7e2b1f8): a fonte ibge_sidra
  // tem 7 consultas por dia com a mesma fonte, falhou não tem fato e, sem o prefixo, o motivo
  // gravado seria só "HTTP 400" (0303, ramo sem erro), sem dizer se caiu o IPCA ou a PMS.
  // Erro informado num 4xx vai pelo ramo "erro informado" da 0303 e não pelo de
  // http_inexistente: aqui não muda nada, porque ibge_sidra é fonte de mercado sem alvo e
  // http_inexistente é nulo; se um dia deixar de ser, este prefixo precisa ser revisto.
  const id = 'SIDRA ' + m.tabela + '/' + m.variavel + ': ';
  const c = { fonte: 'ibge_sidra', http_status: l.http_status, erro: l.erro === null ? null : id + l.erro, corpo: l.corpo, itens: null, registros_lidos: null };
  if (l.erro !== null) return { consulta: c, dado: null };
  if (l.http_status < 200 || l.http_status > 299) { c.erro = id + 'HTTP ' + l.http_status; return { consulta: c, dado: null }; }
  if (!Array.isArray(l.json)) {
    c.erro = id + 'HTTP ' + l.http_status + ' com JSON que não é a lista do SIDRA';
    return { consulta: c, dado: null };
  }
  c.registros_lidos = l.json.length;
  const cab = l.json[0] || {};
  let ultima = 0;
  for (const k of Object.keys(cab)) {
    const mk = k.match(/^D(\d+)C$/);
    if (mk && Number(mk[1]) > ultima) ultima = Number(mk[1]);
  }
  if (ultima < 4) {
    c.erro = id + 'HTTP ' + l.http_status + ' com cabeçalho SIDRA sem dimensão de categoria (D4 em diante) em ' + l.json.length + ' linhas lidas';
    return { consulta: c, dado: null };
  }
  const fatos = [];
  const ausentes = [];
  for (const o of l.json.slice(1)) {
    const per = String((o && o.D3C) || '');
    const cod = String((o && o['D' + ultima + 'C']) || '');
    // As dimensões ENTRE o período (D3) e a categoria (a última) qualificam o número: na PMC e
    // na PMS é o "Tipos de índice" (volume x receita nominal). Sem elas, o fato não dizia que
    // é volume e duas séries da mesma tabela/variável dariam a mesma referência (revisão de
    // 7e2b1f8). Vão no valor, com o nome da dimensão que o próprio SIDRA dá, e na referência.
    const dims = {}; let codDims = '';
    for (let d = 4; d < ultima; d++) {
      dims[String(cab['D' + d + 'N'] || ('D' + d))] = o && o['D' + d + 'N'];
      codDims += String((o && o['D' + d + 'C']) || '') + ':';
    }
    const v = numeroMacro(o && o.V);
    if (v === null || !/^\d{6}$/.test(per) || cod === '') { ausentes.push(cod + ':' + per); continue; }
    fatos.push({
      chave: 'sidra:' + m.tabela + '/' + m.variavel,
      valor: {
        periodo: per, periodo_nome: o.D3N, categoria_codigo: cod, categoria: o['D' + ultima + 'N'], valor: v,
        unidade: o.MN, compoe: false, periodicidade: m.periodicidade, serie: o.D2N, dimensoes: dims,
        agregado: (m.agregados || []).indexOf(cod) >= 0, mes_final: mesFinalSidra(per, m.periodicidade),
        otica: oticaSidra(m.otica, cod),
      },
      referencia: 'sidra.' + m.tabela + '.' + m.variavel + ':' + codDims + cod + ':' + per,
    });
  }
  if (fatos.length === 0) {
    c.erro = id + 'HTTP ' + l.http_status + ' sem nenhum valor numérico em ' + l.json.length + ' linhas lidas (cabeçalho incluído)';
    return { consulta: c, dado: null };
  }
  for (const f of fatos) { f.valor.ausentes_na_consulta = ausentes.length; f.valor.ausentes_em = ausentes; }
  c.itens = fatos;
  return { consulta: c, dado: l.json };
}
