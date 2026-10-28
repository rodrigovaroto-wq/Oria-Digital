/**
 * Verificação do Kit Básico satisfeito por ESTRUTURA (Supabase/migrations/0157)
 * (roda com `./node_modules/.bin/tsx scripts/verificar-kit-basico.mts`).
 *
 * O DEFEITO, medido no lote real 7377 (mandato "teste Canastra", 02/09): dois
 * documentos COMBINADO (8 empresas na planilha, confiança 1,0) foram
 * rotulados BALANCO pelo classificador. A 0157 fez `fn_recomputar_completude`
 * passo (1) parar de perguntar só ao rótulo — `fn_documento_serve_como`
 * também aceita, SÓ para o código COMBINADO, um documento estruturalmente
 * combinado (`fn_documento_de_varias_empresas`, 0155). A pendência
 * `item_faltante: COMBINADO` se resolve sozinha e o Portão 1 abre
 * (`portao1_ok = true`).
 *
 * A TELA (`casos/[id]/page.tsx`) tinha a SUA PRÓPRIA implementação da regra
 * antiga — `tipo_taxonomia === codigo` — e por isso continuava desenhando
 * COMBINADO em cinza, "não recebido", com o tile de topo em 7/8 e `detalhe`
 * nulo, mesmo com o Portão 1 já aberto. Duas telas da MESMA verdade
 * discordando, sem nenhum sinal de erro: é a lente central deste projeto.
 *
 * O invariante que este arquivo prova, em COMPORTAMENTO — nunca em mecanismo
 * (nunca reimplementa `fn_documento_de_varias_empresas` aqui; o "banco" do
 * teste é um dublê que só devolve o que o SQL devolveria, pelo contrato
 * documento×tipo):
 *
 *  1. Um documento estruturalmente COMBINADO, rotulado BALANCO, faz o item
 *     COMBINADO do Kit Básico aparecer ATENDIDO na tela — a mesma resposta
 *     que abriu o Portão 1. Sem a correção, este assert falha: a tela
 *     continua achando que falta.
 *  2. Um documento de UMA empresa só, rotulado BALANCO, NÃO atende o item
 *     COMBINADO — a exceção não é "documento chegou", é "documento serve".
 *  3. O caminho comum (rótulo bate) não faz NENHUMA chamada ao banco — a
 *     correção não pode trocar uma tela rápida por uma tela lenta para o caso
 *     que já funcionava.
 *  4. Um banco sem a 0157 (a função responde erro) faz a tela voltar ao
 *     comportamento de ANTES da 0157 — só o rótulo conta — nunca inventa
 *     "atendido" por conta própria.
 *  5. O "Próximo passo" da Visão geral (`lib/proximo-passo.ts`) obedece à prioridade
 *     e nunca chuta: pendência que trava vence tudo; leitura que falhou diz "não dá
 *     para determinar" em vez de mandar aprovar; aprovado com modelo montado leva a
 *     Entregáveis. Mora neste script porque o CI já o roda — um script novo exigiria
 *     linha no `suites.yml` E no CLAUDE.md (o espelho reprova a divergência).
 *  6. O "← anterior / próximo →" do painel de documento segue a ORDEM DA LISTA FILTRADA
 *     (`lib/vizinhos-na-ordem.ts`), nunca gira nas pontas e nunca finge posição para um
 *     documento que não está na ordem.
 */

import { itensDoKitBasicoAtendidos, type ServicoDocumentoServeComo } from "../src/lib/kit-basico.ts";
import { proximoPasso, type EntradaProximoPasso } from "../src/lib/proximo-passo.ts";
import { vizinhosNaOrdem } from "../src/lib/vizinhos-na-ordem.ts";
import type { Documento, TaxonomiaTipoDocumento } from "../src/lib/types.ts";

let falhas = 0;
let passou = 0;

// O Sonar cobra `typescript:S2301` nesta assinatura ("não decida ação por
// parâmetro booleano"). Fica como está DE PROPÓSITO: é a mesma assinatura,
// caractere por caractere, de `verificar-premissas-do-realizado.mts:37`, e
// partir um helper de assert em dois métodos deixaria cada teste daqui menos
// legível para satisfazer uma regra escrita para código de produção.
function ok(cond: boolean, nome: string, detalhe?: string) {
  if (cond) {
    passou += 1;
    console.log(`  ok    ${nome}`);
  } else {
    falhas += 1;
    const sufixo = detalhe ? " — " + detalhe : "";
    console.error(`  FALHOU: ${nome}${sufixo}`);
  }
}

const kitBasico: Pick<TaxonomiaTipoDocumento, "codigo">[] = [
  { codigo: "BALANCO" },
  { codigo: "DRE" },
  { codigo: "COMBINADO" },
];

function documento(id: string, tipo_taxonomia: string | null): Pick<Documento, "id" | "tipo_taxonomia"> {
  return { id, tipo_taxonomia };
}

// O "banco" do teste: um dublê que responde exatamente o que
// `fn_documento_serve_como` responderia, pelo CONTRATO (documento × tipo) —
// nunca reimplementa `fn_documento_de_varias_empresas` em TypeScript. Cada
// entrada é um fato medido do lote 7377, não uma regra derivada.
function bancoComEstrutura(estruturais: Set<string>): ServicoDocumentoServeComo {
  return async (documentoId, tipoTaxonomia) => {
    if (tipoTaxonomia === "COMBINADO" && estruturais.has(documentoId)) return true;
    return false;
  };
}

const bancoSemChamadaEsperada: ServicoDocumentoServeComo = async () => {
  throw new Error("o rótulo já resolvia — a chamada ao banco não deveria ter acontecido");
};

const bancoSem0157: ServicoDocumentoServeComo = async () => {
  // `page.tsx` trata erro de RPC como "não sei" — nunca "sim" por invenção.
  // O dublê aqui já representa esse tratamento (o `error` virou `false` antes
  // de chegar à função), então simular apenas devolve `false`.
  return false;
};

// SEM `async function principal()` embrulhando: `.mts` é módulo ESM e aceita
// top-level await. Os irmãos (verificar-export, verificar-transcricao) também
// rodam no topo — e o Sonar cobra isto em typescript:S7785.
console.log("--- 1. documento estruturalmente COMBINADO, rotulado BALANCO: item aparece atendido ---");
{
  const documentos = [
    documento("doc-13", "BALANCO"), // 13_Balanco_COMBINADO_Grupo_Canastra_2025.pdf, 8 empresas, medido no 7377
    documento("doc-14", "BALANCO"), // 14_Balanco_COMBINADO_Grupo_Canastra_2024.pdf, 8 empresas
  ];
  const banco = bancoComEstrutura(new Set(["doc-13", "doc-14"]));
  const atendidos = await itensDoKitBasicoAtendidos(kitBasico, documentos, banco);
  ok(atendidos.has("COMBINADO"),
    "COMBINADO aparece atendido quando um documento é estruturalmente combinado");
  ok(!atendidos.has("DRE"), "DRE continua faltante — nada nesta rodada satisfaz DRE");
}

console.log("--- 2. o MESMO rótulo, mas UMA empresa só nas colunas: item continua faltante ---");
{
  const documentos = [documento("doc-alfa", "BALANCO")]; // uma empresa: fn_documento_de_varias_empresas = false
  const banco = bancoComEstrutura(new Set()); // nenhum documento é estrutural
  const atendidos = await itensDoKitBasicoAtendidos(kitBasico, documentos, banco);
  ok(!atendidos.has("COMBINADO"),
    "documento de uma empresa só NÃO satisfaz COMBINADO — a exceção é de estrutura, não de chegada");
}

console.log("--- 3. rótulo bate: zero chamada ao banco (o caminho comum não fica mais lento) ---");
{
  // SÓ os dois itens que o rótulo já resolve — DRE ficaria de fora do kit
  // real e chamaria o dublê que lança, o que provaria outra coisa.
  const kitResolvidoPeloRotulo: Pick<TaxonomiaTipoDocumento, "codigo">[] = [
    { codigo: "BALANCO" },
    { codigo: "COMBINADO" },
  ];
  const documentos = [documento("doc-c1", "COMBINADO"), documento("doc-b1", "BALANCO")];
  const atendidos = await itensDoKitBasicoAtendidos(
    kitResolvidoPeloRotulo, documentos, bancoSemChamadaEsperada,
  );
  ok(atendidos.has("COMBINADO") && atendidos.has("BALANCO"),
    "os dois itens já resolvidos pelo rótulo aparecem atendidos sem perguntar ao banco");
}

console.log("--- 4. banco sem a 0157 (RPC devolve erro, tratado como `false` por page.tsx) ---");
{
  const documentos = [documento("doc-13", "BALANCO")];
  const atendidos = await itensDoKitBasicoAtendidos(kitBasico, documentos, bancoSem0157);
  ok(!atendidos.has("COMBINADO"),
    "sem a 0157 aplicada, COMBINADO continua faltante — o mesmo comportamento de ANTES da migration, "
    + "nunca 'atendido' inventado pelo portal");
}

// Tudo "certo" por padrão; cada caso muda SÓ o que o caso afirma. O padrão é o caso aprovado
// com modelo montado — o último degrau —, para que cada degrau acima seja provado por uma
// entrada que o faria cair no de baixo se a prioridade estivesse errada.
const limpo: EntradaProximoPasso = {
  bloqueantesAbertas: 0, revisoesAbertas: 0, kitFaltantes: 0,
  aprovavel: true, aprovado: true, modeloMontado: true,
};
const passoDe = (e: Partial<EntradaProximoPasso>) => proximoPasso({ ...limpo, ...e });

console.log("--- 5. Próximo passo: prioridade, e leitura que falhou nunca vira um passo ---");
{
  // 5a. pendência que trava vence TUDO, inclusive o que também estaria pendente.
  const tudoPendente = { revisoesAbertas: 3, kitFaltantes: 2, aprovavel: false, aprovado: false, modeloMontado: false };
  const a = passoDe({ ...tudoPendente, bloqueantesAbertas: 2 });
  ok(a.passo === "decidir" && a.href === "/pendencias",
    "com pendência bloqueante aberta, o passo é decidir pendências, mesmo com revisão, kit e modelo pendentes");
  ok(a.titulo === "Decidir 2 pendências que travam a aprovação", "o título diz quantas travam", a.titulo);
  ok(passoDe({ bloqueantesAbertas: 1 }).titulo === "Decidir 1 pendência que trava a aprovação",
    "singular quando é uma só");
  // Mesmo aprovado: bloqueante nova reabre o trabalho de decidir.
  ok(passoDe({ bloqueantesAbertas: 1, aprovado: true }).passo === "decidir",
    "um caso já aprovado com pendência bloqueante nova volta a ser 'decidir'");
  // Leitura posterior falha, mas a resposta já é conhecida: não se esconde um bloqueio atrás dela.
  ok(passoDe({ bloqueantesAbertas: 2, revisoesAbertas: null, kitFaltantes: null, aprovavel: null, modeloMontado: null }).passo === "decidir",
    "leitura que falhou DEPOIS do passo decisivo não esconde o bloqueio");

  // 5b. a ordem dos degraus seguintes.
  const r = passoDe({ revisoesAbertas: 4, kitFaltantes: 2, aprovavel: false, aprovado: false });
  ok(r.passo === "confirmar" && r.href === "/pendencias?filtro=confirmar",
    "sem bloqueio, documento a confirmar vem antes do Kit Básico");
  const k = passoDe({ kitFaltantes: 2, aprovavel: false, aprovado: false });
  ok(k.passo === "pedir" && k.href === "/perguntas" && k.titulo === "Pedir 2 documentos ao cliente",
    "Kit Básico incompleto manda pedir os documentos ao cliente", k.titulo);
  ok(passoDe({ kitFaltantes: 1, aprovavel: false, aprovado: false }).titulo === "Pedir 1 documento ao cliente", "singular no kit");
  // O kit só manda pedir ENQUANTO o portão não aceita o mandato: item faltante decidido
  // ("prosseguir sem resolução") deixa kitFaltantes > 0 para sempre, e o banner não pode
  // ficar preso em "pedir" (revisão do PR #265).
  ok(passoDe({ kitFaltantes: 1, aprovavel: true, aprovado: false }).passo === "aprovar",
    "kit com item faltante, mas o portão já aceita: o passo é aprovar, não pedir");
  ok(passoDe({ kitFaltantes: 1 }).passo === "entregaveis",
    "kit com item faltante num mandato aprovado e modelado: Entregáveis, não 'pedir' para sempre");
  ok(passoDe({ kitFaltantes: 1, modeloMontado: false }).passo === "modelar",
    "kit com item faltante num mandato aprovado sem modelo: Modelagem");
  const ap = passoDe({ aprovavel: true, aprovado: false });
  ok(ap.passo === "aprovar" && ap.href === "#aprovacao",
    "aprovável e ainda não aprovado: aprovar, ancorado no cartão de aprovação");
  const naoAp = passoDe({ aprovavel: false, aprovado: false });
  ok(naoAp.passo === "ver_aprovacao", "portão fechado sem causa conhecida: não manda aprovar, manda ver os motivos");
  ok(passoDe({ modeloMontado: false }).passo === "modelar" && passoDe({ modeloMontado: false }).href === "/modelagem",
    "aprovado e modelo não montado: Modelagem");

  // 5c. aprovado + modelo montado → Entregáveis.
  const e = passoDe({});
  ok(e.passo === "entregaveis" && e.href === "/entregaveis",
    "aprovado com o modelo montado leva a Entregáveis");
}

console.log("--- 5b. Próximo passo: leitura que falhou diz que não dá para determinar ---");
{
  const campos: Array<keyof EntradaProximoPasso> = ["bloqueantesAbertas", "revisoesAbertas", "kitFaltantes"];
  for (const c of campos) {
    // Num caso ainda NÃO aprovável, onde cada uma dessas leituras ainda decide algo.
    const p = passoDe({ [c]: null, aprovavel: false, aprovado: false });
    ok(p.passo === "indeterminado" && p.acao === null && p.href === null,
      `${c} ilegível (null) → "não dá para determinar", sem botão — nunca o próximo degrau`, p.titulo);
  }
  const ap = passoDe({ aprovavel: null, aprovado: false });
  ok(ap.passo === "indeterminado", "avaliação do portão que não respondeu NÃO vira 'aprovar'", ap.titulo);
  ok(passoDe({ kitFaltantes: null }).passo === "entregaveis",
    "kit ilegível num mandato JÁ aprovado não trava a resposta: o kit não decide mais nada ali");
  const m = passoDe({ modeloMontado: null });
  ok(m.passo === "indeterminado", "configuração do modelo ilegível NÃO vira 'Entregáveis'", m.titulo);
  ok(/não dá para determinar/i.test(passoDe({ bloqueantesAbertas: null }).titulo),
    "a frase diz com todas as letras que não dá para determinar");
}

console.log("--- 6. Painel de documento: anterior/próximo na ordem da lista filtrada ---");
{
  // A ordem é a que a lista MOSTRA (aqui, um filtro que pulou "d2" e "d4"): o vizinho de "d3" é "d5",
  // não o "d4" que o banco teria na ordem completa.
  const filtrada = ["d1", "d3", "d5"];
  const meio = vizinhosNaOrdem(filtrada, "d3");
  ok(meio?.anterior === "d1" && meio?.proximo === "d5" && meio?.posicao === 2 && meio?.total === 3,
    "no meio: anterior e próximo são os da lista FILTRADA, posição 2 de 3", JSON.stringify(meio));
  const primeiro = vizinhosNaOrdem(filtrada, "d1");
  ok(primeiro?.anterior === null && primeiro?.proximo === "d3" && primeiro?.posicao === 1,
    "primeiro: sem anterior (não gira para o último)", JSON.stringify(primeiro));
  const ultimo = vizinhosNaOrdem(filtrada, "d5");
  ok(ultimo?.proximo === null && ultimo?.anterior === "d3" && ultimo?.posicao === 3,
    "último: sem próximo (não gira para o primeiro)", JSON.stringify(ultimo));
  ok(vizinhosNaOrdem(filtrada, "d2") === null,
    "documento fora da ordem (saiu do filtro) → null, não 'primeiro' nem posição inventada");
  ok(vizinhosNaOrdem([], "d1") === null, "ordem vazia → null");
  const unico = vizinhosNaOrdem(["d1"], "d1");
  ok(unico?.anterior === null && unico?.proximo === null && unico?.total === 1,
    "lista de um documento: sem vizinhos, total 1");
}

console.log(`\n${passou} asserts passaram, ${falhas} falharam`);
if (falhas > 0) process.exit(1);
console.log("KIT BÁSICO OK — a tela pergunta ao banco, nunca rederiva a regra do COMBINADO estrutural");
