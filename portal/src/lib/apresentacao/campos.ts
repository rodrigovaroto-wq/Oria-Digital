// O CATÁLOGO DOS CAMPOS "[a preencher]" DA APRESENTAÇÃO — a única lista das chaves.
//
// O gerador (`deck-credito.ts`) monta a chave de cada lacuna a partir do rótulo do slide
// ("II.2 · Tendências" → "ii2") mais um sufixo; a tela de preenchimento lê ESTA lista. Duas listas
// soltas divergiriam sem erro: a tela gravaria uma chave que o deck nunca lê, e o analista veria o
// campo salvo e o slide ainda "[a preencher]". Por isso `verificar-apresentacao.mts` preenche
// TODAS as chaves daqui e confere que cada valor aparece no deck (assert 9a).
export interface CampoApresentacao { chave: string; rotulo: string; longo?: boolean }
export interface CapituloApresentacao { titulo: string; campos: CampoApresentacao[] }

const n = (k: number) => Array.from({ length: k }, (_, i) => i + 1);
/** Título (a conclusão do slide) e nota de fonte de um slide de pesquisa/julgamento. */
const cab = (slide: string, nome: string, comFonte = true): CampoApresentacao[] => [
  { chave: `${slide}.titulo`, rotulo: `${nome} — título (a conclusão do slide, até 70 caracteres)` },
  // Slide com número do sistema tem a nota de fonte do sistema: só o título é do analista.
  ...(comFonte ? [{ chave: `${slide}.fonte`, rotulo: `${nome} — fonte` }] : []),
];

export const CAPITULOS_APRESENTACAO: CapituloApresentacao[] = [
  { titulo: "I · Panorama do setor macro", campos: [
    ...cab("i1", "I.1"),
    ...n(4).flatMap((i) => [
      { chave: `i1.kpi${i}`, rotulo: `KPI ${i} — valor (${["tamanho do setor", "crescimento recente", "juro de referência", "crédito ao setor"][i - 1]})` },
      { chave: `i1.kpi${i}.fonte`, rotulo: `KPI ${i} — fonte` },
    ]),
    ...n(3).map((i) => ({ chave: `i1.contexto${i}`, rotulo: `Contexto ${i} (${["demanda e ciclo", "juros e crédito", "regulação e câmbio"][i - 1]})`, longo: true })),
  ] },
  { titulo: "II · Mercado específico", campos: [
    ...cab("ii1", "II.1"), ...cab("ii2", "II.2"),
    ...n(6).map((i) => ({ chave: `ii2.cartao${i}`, rotulo: `Tendência ${i} (${["regulação", "tecnologia", "consolidação", "mercado global", "importação e câmbio", "crédito"][i - 1]})`, longo: true })),
  ] },
  { titulo: "III · Estrutura societária", campos: [
    ...cab("iii1", "III.1"), ...cab("iii2", "III.2"),
    ...n(3).flatMap((i) => [{ chave: `iii2.socio${i}.nome`, rotulo: `Sócio ${i} — nome` },
      { chave: `iii2.socio${i}`, rotulo: `Sócio ${i} — histórico e outras empresas`, longo: true }]),
    { chave: "iii3.avais", rotulo: "Avais cruzados e mútuos entre as empresas do grupo" },
    ...cab("iii4", "III.4"),
    ...n(3).map((i) => ({ chave: `iii4.cartao${i}`, rotulo: ["Concentração de controle", "Força das garantias pessoais", "Alertas e pontos de atenção"][i - 1], longo: true })),
  ] },
  { titulo: "IV · A empresa", campos: [
    ...cab("iv1", "IV.1"), ...cab("iv2", "IV.2", false), ...cab("iv3", "IV.3"), ...cab("iv4", "IV.4"),
    { chave: "iv4.vantagens", rotulo: "Localização — vantagens", longo: true },
    { chave: "iv4.desvantagens", rotulo: "Localização — desvantagens", longo: true },
  ] },
  { titulo: "V · Cadeia de valor", campos: [
    ...cab("v1", "V.1"), ...cab("v3", "V.3", false), ...cab("v4", "V.4"),
    { chave: "v4.funciona", rotulo: "O que funciona", longo: true },
    { chave: "v4.naofunciona", rotulo: "O que não funciona", longo: true },
  ] },
  { titulo: "VI · Cenário competitivo", campos: [
    ...cab("vi1", "VI.1"),
    ...n(4).flatMap((i) => [{ chave: `vi1.concorrente${i}.nome`, rotulo: `Concorrente ${i} — nome` },
      { chave: `vi1.concorrente${i}`, rotulo: `Concorrente ${i} — alcance, ponto forte e ponto fraco`, longo: true }]),
    ...cab("vi2", "VI.2"),
  ] },
  // XIII: com mapa da dívida, credor, saldo, taxa e títulos saem do sistema; vencimento e garantia
  // NÃO vêm no mapa e são do analista, pela ordem da operação no slide XIII.2 (maior saldo primeiro).
  { titulo: "XIII · Endividamento", campos: [
    ...n(12).flatMap((i) => [
      { chave: `xiii2.op${i}.vencimento`, rotulo: `Operação ${i} (ordem do XIII.2) — vencimento` },
      { chave: `xiii2.op${i}.garantia`, rotulo: `Operação ${i} — garantia` },
    ]),
    { chave: "xiii3.ruptura", rotulo: "Primeira ruptura de caixa (data)" },
    { chave: "xiii3.cronograma", rotulo: "Cronograma de amortização dos próximos 24 meses", longo: true },
  ] },
  { titulo: "XV.2 · Alavancas", campos: [
    ...cab("xv2", "XV.2"),
    ...n(6).map((i) => ({ chave: `xv2.alavanca${i}`, rotulo: `Magnitude — ${["alongamento", "redução de custo", "conversão ou capitalização", "desinvestimentos", "giro de capital", "deságio"][i - 1]}` })),
  ] },
  { titulo: "XVI e XVII · Garantias e scorecard", campos: [
    ...(["clientes", "estoques", "imobilizado"] as const).map((k) => ({ chave: `xvi.realizacao.${k}`,
      rotulo: `Realização (%) — ${{ clientes: "recebíveis", estoques: "estoques", imobilizado: "imobilizado tangível" }[k]} (premissa Oria ou laudo)` })),
    { chave: "xvi.recuperacao", rotulo: "Recuperação por classe e aval dos sócios", longo: true },
    ...cab("xvii", "XVII", false),
    ...n(6).flatMap((i) => [
      { chave: `xvii.nota${i}`, rotulo: `Nota ${i} de 1,0 a 10,0 (${["produto, demanda e mercado", "acionistas e gestão", "acesso a crédito e passivo", "rentabilidade", "geração de caixa", "solvência e estrutura de capital"][i - 1]})` },
      { chave: `xvii.justificativa${i}`, rotulo: `Nota ${i} — justificativa` },
    ]),
  ] },
  { titulo: "XVIII · Síntese de crédito", campos: [
    { chave: "xviii.hipotese", rotulo: "Hipótese de solução", longo: true },
    { chave: "xviii.riscos", rotulo: "Riscos e pontos de diligência", longo: true },
  ] },
  { titulo: "SWOT, fatores críticos e próximos passos", campos: [
    ...cab("vii", "SWOT"),
    ...["forcas", "fraquezas", "oportunidades", "ameacas"].map((k, i) => ({ chave: `vii.${k}`, rotulo: ["Forças", "Fraquezas", "Oportunidades", "Ameaças"][i], longo: true })),
    ...cab("viii1", "VIII.1"),
    ...n(5).flatMap((i) => [{ chave: `viii1.fator${i}.titulo`, rotulo: `Fator ${i} — título` },
      { chave: `viii1.fator${i}`, rotulo: `Fator ${i} — descrição`, longo: true }]),
    ...cab("viii2", "VIII.2", false),
  ] },
  { titulo: "Contracapa", campos: n(2).flatMap((i) => (["nome", "telefone", "email"] as const).map((c) => ({
    chave: `contracapa.contato${i}.${c}`, rotulo: `Contato ${i} — ${c === "email" ? "e-mail" : c}` }))) },
];

/**
 * O campo carrega NÚMERO digitado pelo analista (valor, magnitude, percentual, nota, cronograma)?
 * A tela de preenchimento o marca `valor-sensivel`: no modo discrição o analista que digita com
 * cliente ao lado não pode ter o número exposto no campo. Texto corrido de julgamento (contexto,
 * tendências, sócios, SWOT) e as fontes ficam nítidos — borrar tudo tiraria do modo o sentido de
 * "só o que é dinheiro". Decidido por chave e não por campo da tela, porque a chave é o contrato
 * (ver o assert 9a de `verificar-apresentacao.mts`): campo novo sem regra aqui NÃO é borrado, e o
 * assert de `verificar-mensagem-de-falha.mts` (seção 7) lista as chaves cobertas.
 */
export function campoCarregaValor(chave: string): boolean {
  return /^i1\.kpi\d$/.test(chave)            // KPI de mercado (tamanho do setor, juros, crédito)
    || /^xv2\./.test(chave)                     // alavancas: magnitude em R$ (título/fonte entram: o título cita o número)
    || /^xvi\.realizacao\./.test(chave)        // % de realização das garantias
    || chave === "xvi.recuperacao"              // recuperação por classe, em % e R$
    || chave === "xiii3.cronograma"             // amortização dos próximos 24 meses, em R$
    || chave === "xiii3.ruptura"                // data da primeira ruptura de caixa
    || /^xvii\.nota\d$/.test(chave);           // nota 1,0-10,0 do scorecard (a justificativa é texto: nítida)
}

export const CHAVES_APRESENTACAO: ReadonlySet<string> =
  new Set(CAPITULOS_APRESENTACAO.flatMap((c) => c.campos.map((x) => x.chave)));
