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
import { montarEmailAoCliente, listaNumerada, linkMailto, resumoDoLote, assuntoDoEmail, textoDoItem, perguntasForaDoTexto, type PerguntaParaEmail } from "../src/lib/email-ao-cliente.ts";
import { BOTOES_DECISAO, exigeConfirmacao } from "../src/lib/pendencia.ts";
import { passosDaTrilha } from "../src/components/trilha.tsx";
import { aceiteAutomatico, fraseDoAceiteTotal, falhaDeExtracaoNaTela } from "../src/lib/rotulos.ts";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
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


// 6. O E-MAIL AO CLIENTE (`lib/email-ao-cliente.ts`, perguntas em lote). Texto que sai da casa:
//    só o texto da pergunta (nada interno), numeração contínua, empresas agrupadas, ordem estável
//    e o lote nunca diz "tudo certo" quando algo falhou. Mora aqui porque o CI já roda este script.
{
  const P = (codigo: string, prioridade: number, entidade: string | null, pergunta: string): PerguntaParaEmail =>
    ({ codigo, prioridade, entidade, pergunta, motivo: "MOTIVO-INTERNO", risco: "RISCO-INTERNO" } as PerguntaParaEmail);
  const pergs = [
    P("Q2", 2, "Beta Ltda", "Sobre a Beta Ltda: Enviem o balanço de 2024."),
    P("Q9", 1, null, "Quais as garantias prestadas?"),
    P("Q1", 1, "Alfa S.A.", "Sobre a Alfa S.A.: Enviem a DRE."),
    P("Q3", 3, "Alfa S.A.", "Sobre a Alfa S.A.: Enviem o balancete."),
  ];
  const t = montarEmailAoCliente(pergs, "Projeto X");
  ok(t.startsWith("Prezados,") && t.endsWith("[nome]"), "e-mail: saudação e assinatura-placeholder");
  ok(!/MOTIVO-INTERNO|RISCO-INTERNO|Q1|Q9/.test(t), "e-mail: nenhum campo interno (código, motivo, risco) vaza");
  const numeros = [...t.matchAll(/^(\d+)\. /gm)].map((m) => Number(m[1]));
  ok(numeros.join(",") === "1,2,3,4", "e-mail: numeração contínua 1..N", numeros.join(","));
  ok(t.indexOf("Perguntas gerais:") < t.indexOf("Alfa S.A.:") && t.indexOf("Alfa S.A.:") < t.indexOf("Beta Ltda:"),
    "e-mail: sem empresa primeiro, depois empresas em ordem alfabética");
  ok(!t.includes("Sobre a Alfa S.A.:"), "e-mail: prefixo da 0120 retirado sob o título da empresa");
  ok(t.indexOf("Enviem a DRE") < t.indexOf("Enviem o balancete"), "e-mail: dentro da empresa, por prioridade");
  ok(t === montarEmailAoCliente([...pergs].reverse(), "Projeto X"), "e-mail: independe da ordem de seleção");
  ok(montarEmailAoCliente([], "Projeto X").includes("Prezados,"), "e-mail: lista vazia não quebra");
  ok(!/Alfa S\.A\.:|Perguntas gerais:/.test(listaNumerada([P("Q1", 1, null, "Uma só."), P("Q2", 1, null, "Duas.")])),
    "lista: sem empresa nenhuma, sem título de grupo");
  ok(linkMailto(assuntoDoEmail("Projeto X"), "curto")?.startsWith("mailto:?subject=") === true, "mailto: texto curto abre");
  ok(linkMailto("a", "x".repeat(3000)) === null, "mailto: texto longo devolve null (a tela manda usar Copiar)");
  ok(resumoDoLote(3, []) === "3 registradas como enviadas.", "lote: tudo certo só quando nada falhou", resumoDoLote(3, []));
  const parcial = resumoDoLote(2, ["Q1: recusado"]);
  ok(parcial.startsWith("2 registradas; 1 falhou: Q1") && !parcial.includes("como enviadas"),
    "lote: falha parcial nunca diz que tudo deu certo", parcial);
  // ALTO 2: o que se congela por pergunta é o ITEM dela, o mesmo que o e-mail escreve.
  ok(textoDoItem(pergs[0]) === "Enviem o balanço de 2024." && textoDoItem(pergs[1]) === "Quais as garantias prestadas?",
    "item: sem o prefixo 'Sobre a X: ' da 0120, e sem numeração nem título de grupo");
  ok(pergs.every((p) => t.includes(textoDoItem(p)) && !textoDoItem(p).includes(t.slice(0, 20))),
    "item: cada item aparece no e-mail e NUNCA é o e-mail inteiro");
  ok(perguntasForaDoTexto(pergs, t).length === 0, "fora do texto: e-mail intacto → nenhuma ausente");
  const editado = t.replace("Enviem a DRE.", "Enviem a DRE de 2023.").replace(/^\d+\. Quais as garantias prestadas\?\n\n/m, "");
  ok(perguntasForaDoTexto(pergs, editado).map((p) => p.codigo).join(",") === "Q9,Q1",
    "fora do texto: pergunta apagada E pergunta reescrita são apontadas; as intactas não",
    perguntasForaDoTexto(pergs, editado).map((p) => p.codigo).join(","));
  ok(perguntasForaDoTexto(pergs, t.replace("Enviem o balancete.", "Enviem o\n  balancete.")).length === 0,
    "fora do texto: reformatar quebra de linha/espaço não conta como ausência");
  const comAusente = resumoDoLote(2, [], ["Q9"]);
  ok(comAusente.startsWith("2 registradas; 1 não registrada") && comAusente.includes("Q9") && !comAusente.includes("como enviadas"),
    "lote: pergunta fora do texto editado nunca vira 'tudo certo'", comAusente);
}

// 7. P16 (vistoria P2, ALTA 1): decisão que tira a pendência da fila pergunta antes de gravar.
//    "Prosseguir sem resolução" aceitava pendência que trava a aprovação num toque. Contatar o
//    cliente não tira nada da fila e continua num clique só — confirmar tudo vira ruído.
console.log("\n7. Decisão de pendência que libera o mandato pede confirmação");
ok(exigeConfirmacao("prosseguir"), "prosseguir sem resolução pede confirmação");
ok(exigeConfirmacao("nao_procede"), "não procede pede confirmação");
ok(!exigeConfirmacao("contatar_cliente"), "contatar o cliente grava direto (não libera nada)");
ok(BOTOES_DECISAO.every((b) => !b.confirmacao || (b.confirmacao.pergunta.endsWith("?") && b.confirmacao.sim.length > 0)),
  "toda confirmação traz pergunta e um botão de sim com texto");

// 8. P16 (vistoria P2, ALTA 4): o modo discrição borra, e nada desfaz o borrão.
//    Medido em 04/11: `title={doc.resumo}` num elemento borrado mostrava o texto inteiro ao passar
//    o mouse. O borrão é CSS; o `title` é do navegador e ignora o CSS. A varredura lê o código-fonte
//    porque é ele que a tela renderiza — não há navegador com sessão neste CI.
{
  console.log("\n8. Modo discrição: nada marcado como sensível revela o texto pela dica do mouse");
  const tsx: string[] = [];
  const andar = (d: string) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      const c = join(d, e.name);
      if (e.isDirectory()) andar(c);
      else if (c.endsWith(".tsx")) tsx.push(c);
    }
  };
  andar(new URL("../src", import.meta.url).pathname);
  const vazam: string[] = [];
  for (const f of tsx) {
    for (const tag of readFileSync(f, "utf8").match(/<[A-Za-z][^>]*valor-sensivel[^>]*>/g) ?? []) {
      if (/\stitle=/.test(tag)) vazam.push(`${f.split("/src/")[1]}: ${tag.slice(0, 80)}`);
    }
  }
  ok(tsx.length > 50, "a varredura leu os arquivos da tela (não passou vazia)", String(tsx.length));
  ok(vazam.length === 0, "nenhum elemento sensível carrega title=", vazam.join(" | "));
  // O MESMO VAZAMENTO EM ELEMENTO NÃO MARCADO. Medido em 06/11: `title={email || "Conta"}` no botão
  // da conta (menu-conta.tsx) mostrava o e-mail com o modo ligado e passou pelo portão acima, que só
  // olha `valor-sensivel`. Aqui vale QUALQUER `title={...}` cuja expressão cite dado sensível
  // (e-mail, nome de mandato/entidade/arquivo, resumo), marcado ou não. Heurística por identificador:
  // um nome novo para o mesmo dado (ex. `titular`) escapa — acrescente-o aqui ao criá-lo.
  const SENSIVEL = /(?:^|[^A-Za-z0-9_])(email|nome|nome_[a-z_]+|nomeDo\w*|mandato|resumo|razao_social|entidade|empresa|cliente|arquivo)(?![A-Za-z0-9_])/i;
  const TITLE_EXPR = /\btitle=\{((?:[^{}]|\{[^{}]*\})*)\}/g;
  const vazamExpr: string[] = [];
  let expressoes = 0;
  for (const f of tsx) {
    for (const m of readFileSync(f, "utf8").matchAll(TITLE_EXPR)) {
      expressoes++;
      // `rotuloDoLink(...)` só usa o nome para decidir se é PDF e devolve texto fixo ("Abrir o PDF…").
      if (!/^\s*rotuloDoLink\(/.test(m[1]) && SENSIVEL.test(m[1])) vazamExpr.push(`${f.split("/src/")[1]}: title={${m[1].slice(0, 60)}}`);
    }
  }
  ok(expressoes >= 5, "a varredura de title={…} viu as expressões (não passou vazia)", String(expressoes));
  ok(vazamExpr.length === 0, "nenhum title={…} usa dado sensível, marcado ou não", vazamExpr.join(" | "));
  ok(SENSIVEL.test('email || "Conta"') && SENSIVEL.test("doc.nome_original") && !SENSIVEL.test("info.explica"),
    "o detector reconhece e-mail e nome de arquivo e deixa passar dica neutra");
  const passos = passosDaTrilha("/casos/abc/pendencias", { abc: "Metalúrgica X" });
  ok(passos.some((p) => p.rotulo === "Metalúrgica X" && p.sensivel === true),
    "a trilha marca o nome do mandato como sensível", JSON.stringify(passos));
}

// 9. P16 (vistoria P2, ALTA 3): "Todas as linhas foram aceitas" quando quem aceitou foi a máquina.
//    Medido em 04/11: 283 linhas aceitas, nenhuma por pessoa, e a frase soava como conferência humana.
{
  console.log("\n9. O aceite diz quem aceitou");
  const AUTO = "sistema:auto_aceite (dial N2, limiar 0.95, sem guarda disparada)";
  ok(aceiteAutomatico(AUTO) && !aceiteAutomatico("analista@oria.com") && !aceiteAutomatico(null),
    "autor sistema:* é automático; e-mail e nulo não são");
  const soMaquina = fraseDoAceiteTotal([AUTO, AUTO, AUTO]);
  ok(/AUTOMATICAMENTE/.test(soMaquina) && /nenhuma foi conferida por uma pessoa/.test(soMaquina),
    "tudo automático: a frase diz que nenhuma pessoa conferiu", soMaquina);
  ok(!/dial|limiar|sistema:/.test(soMaquina), "e não publica o jargão do autor gravado", soMaquina);
  const misto = fraseDoAceiteTotal(["ana@oria.com", AUTO, AUTO]);
  ok(misto.includes("1 por uma pessoa") && misto.includes("2 automaticamente"), "misto: conta os dois lados", misto);
  ok(fraseDoAceiteTotal(["ana@oria.com"]).includes("por uma pessoa") && !/AUTOMATICAMENTE/.test(fraseDoAceiteTotal(["ana@oria.com"])),
    "tudo humano: não fala em automático");
}

// 10. P16 (vistoria P2, ALTA 2) + G2 (06/11): extração que falhou mostra a CAUSA em português, o
//     texto técnico inteiro em "Detalhes técnicos" e o que fazer SEGUNDO a causa.
//     Medido em produção em 06/11 (468 pendências abertas): 272 mostravam à vista instrução de
//     engenharia (caminho de arquivo, TPM_CONTA, colchete [http=…] do provedor) porque a heurística
//     era "tem acento → é texto nosso"; e TODA falha mandava abrir/reenviar o arquivo, inclusive
//     chave inválida (220 segmentos) e falta de crédito (87), em que o arquivo está bom.
//     O corpus é REAL (fixtures/falhas-de-extracao-producao.json, regra 4): nada inventado.
{
  console.log("\n10. Extração que falhou: causa à vista, técnico inteiro abaixo, ação pela causa");
  const doBanco = (m: string) => `Extração de "relatorio.pdf" falhou ou veio incompleta (0 par(es) conta×coluna gravado(s)). Motivo: ${m}`;
  const corpus = JSON.parse(readFileSync(new URL("./fixtures/falhas-de-extracao-producao.json", import.meta.url), "utf8")) as
    { motivos: Array<{ motivo: string; n: number; abertas: number }> };
  ok(corpus.motivos.length >= 10, "o corpus de produção foi lido (não passou vazio)", String(corpus.motivos.length));

  const PROIBIDO = /\[http=|provedor=|\[type=|N8N\/|\.mjs|TPM_|RPM_|[A-Z]{2,}_[A-Z]{2,}/;
  const INGLES = /\b(the|your|you|please|try|requests?|exceeded|invalid|authentication|credentials?|billing|quota|limit reached)\b/i;
  const REENVIAR_COMO_CAUSA = /abr[ae] o arquivo|corrompid|protegido por senha|pe[çc]a outro/i;
  for (const { motivo } of corpus.motivos) {
    const f = falhaDeExtracaoNaTela(doBanco(motivo));
    const aVista = [f.frase, ...f.aVista].join(" ");
    const curto = motivo.slice(0, 50);
    ok(!PROIBIDO.test(aVista), `à vista não há caminho, variável nem colchete do provedor: ${curto}`, aVista.slice(0, 200));
    ok(!INGLES.test(aVista), `à vista não há texto em inglês: ${curto}`, aVista.slice(0, 200));
    ok(f.tecnico === motivo, `o texto técnico é o motivo inteiro, sem perda: ${curto}`);
    ok(f.aVista.length > 0 && f.acoes.length > 0, `há causa à vista e ação: ${curto}`);
    // COMPORTAMENTO: motivo que é SÓ falha do provedor (sem nenhum trecho de documento) nunca manda
    // abrir o arquivo como causa e só tem a ação do serviço de IA.
    const soProvedor = /^(bloco \d+: )?(CHAVE|CONTA DO|LIMITE|TETO|Erro da API|Resposta d\S+ OpenAI sem)/.test(motivo)
      && !/INCOMPLETA|não fecha|descartad|colado|truncad/.test(motivo);
    if (soProvedor) {
      ok(!f.acoes.some((a) => REENVIAR_COMO_CAUSA.test(a.texto)) && f.acoes.every((a) => a.tipo === "servico_de_ia"),
        `falha só do provedor: nenhuma ação manda abrir o arquivo como causa: ${curto}`, JSON.stringify(f.acoes.map((a) => a.tipo)));
    }
  }

  // Famílias com resposta específica (cada uma saiu de um motivo real do corpus).
  const acha = (re: RegExp) => corpus.motivos.find((m) => re.test(m.motivo))?.motivo ?? "";
  const chave = falhaDeExtracaoNaTela(doBanco(acha(/CHAVE DO PROVEDOR/)));
  ok(chave.aVista.some((t) => t.includes("Chave do provedor de IA inválida")), "chave: título em português", chave.aVista.join(" "));
  const incompleta = falhaDeExtracaoNaTela(doBanco(acha(/^Extração INCOMPLETA/)));
  ok(/^Extração incompleta: \d+ linha\(s\).*% de cobertura, abaixo do mínimo de 85%\)\.$/.test(incompleta.aVista[0]) && incompleta.acoes[0].tipo === "conferir_na_revisao",
    "incompleta: cobertura à vista e ação de conferir na revisão", incompleta.aVista[0]);
  const vazia = falhaDeExtracaoNaTela(doBanco("a chamada respondeu sem erro, mas não trouxe NENHUMA linha. Causa mais comum: formato que o pipeline ainda não converte em texto."));
  ok(vazia.acoes[0].tipo === "sem_linhas" && vazia.aVista.length === 1, "sem nenhuma linha: ação própria (abrir o arquivo)");
  // 0231: o prefixo é o que `fn_registrar_campos_extraidos` grava (Supabase/migrations/0231_*). Sem a regra,
  // a pendência nova cai em "não foi possível classificar a causa" e o analista não sabe o que fazer.
  const semDado = falhaDeExtracaoNaTela(doBanco("a leitura declarou que este documento não tem dado financeiro, mas o tipo dele (BALANCO) é de documento que traz valores."));
  ok(semDado.acoes.length === 1 && semDado.acoes[0].tipo === "declarado_sem_dado" && semDado.aVista.length === 1,
    "declarado sem dado em tipo financeiro: ação própria (abrir o arquivo e decidir)");
  // As três frases do Agrupar Linhas XLSX que lê todas as abas (N8N/build-workflow.mjs, 3075c8d): cada uma com causa e ação.
  for (const [motivo, acao, frase] of [
    ['Aba "Mapa": Planilha maior que o teto de envio: 2000 de 5000 linhas.', "planilha_cortada", 'A aba "Mapa" é maior'],
    ['A aba "Mapa" NAO foi lida pelo extrator (sheet not found): o que ela contem NAO chegou ao banco nem ao book.', "xlsx_varias_abas", 'A aba "Mapa" não foi lida'],
    ["O arquivo .xlsx tem 3 planilha(s) nos bytes, mas o workbook listou so 2: as 1 restante(s) NAO foram lidas.", "xlsx_varias_abas", "tem 3 abas e só 2"],
  ] as const) {
    const f = falhaDeExtracaoNaTela(doBanco(motivo));
    ok(f.acoes.length === 1 && f.acoes[0].tipo === acao && f.aVista.length === 1 && f.aVista[0].includes(frase), `planilha de várias abas: "${motivo.slice(0, 30)}…" tem causa e ação (${acao})`);
  }
  const truncada = falhaDeExtracaoNaTela(doBanco(acha(/truncada/)));
  ok(truncada.acoes.some((a) => a.tipo === "resposta_truncada") && !truncada.acoes.some((a) => a.reenvio && a.tipo === "resposta_truncada"),
    "resposta truncada não manda reenviar o mesmo arquivo");
  // A armadilha: " | " DENTRO de um rótulo de conta não cria "título".
  const comPipe = falhaDeExtracaoNaTela(doBanco(acha(/GRADE|ARADO/)));
  ok(!comPipe.aVista.some((t) => /PAGO|MATRIZ|GRADE|ARADO/.test(t)), "rótulo com ' | ' não vira causa à vista", comPipe.aVista.join(" || "));
  // TEXTO REAL DO EMISSOR (regra 4: nada inventado). Os motivos abaixo saem das funções do n8n que
  // os gravam, importadas aqui por caminho calculado (o portal não importa N8N/lib no build; o script
  // pode). Cobre as famílias que o corpus de 06/11 não tem.
  const n8n = async (m: string) => await import(new URL(`../../N8N/lib/${m}`, import.meta.url).href);
  const { diagnosticarErroApi, parseExtractionResponse } = await n8n("extract.mjs");
  const { avisoTruncamentoPlanilha } = await n8n("spreadsheet.mjs");
  const porErro = (e: unknown) => falhaDeExtracaoNaTela(doBanco(diagnosticarErroApi(e).motivo));
  const tipos = (f: ReturnType<typeof falhaDeExtracaoNaTela>) => f.acoes.map((a) => a.tipo).join(",");
  const e429 = (code: string, message: string) => ({ httpCode: 429, error: { error: { type: "x", code, message } } });
  const casos: Array<[string, unknown, string]> = [
    ["429 cota diária", e429("rate_limit_exceeded", "Rate limit reached on tokens per day (TPD): Limit 200000"), "servico_de_ia"],
    ["429 sem causa", { httpCode: 429, error: { error: { message: "x" } } }, "servico_de_ia"],
    ["404 modelo", { httpCode: 404, error: { error: { type: "invalid_request_error", code: "model_not_found", message: "The model does not exist" } } }, "servico_de_ia"],
    ["500 servidor", { httpCode: 500, error: { error: { type: "server_error", message: "The server had an error" } } }, "servico_de_ia"],
    // o caso de origem da P16: PDF corrompido devolve 400 invalid_request_error — NÃO é culpa do serviço
    ["400 pedido recusado (PDF corrompido)", { httpCode: 400, error: { error: { type: "invalid_request_error", message: "The document could not be processed" } } }, "chamada_incerta"],
  ];
  for (const [nome, erro, esperado] of casos) {
    const f = porErro(erro);
    ok(tipos(f) === esperado && !PROIBIDO.test(f.aVista.join(" ")) && !INGLES.test(f.aVista.join(" ")),
      `emissor real, ${nome}: ação ${esperado}, nada técnico à vista`, `${tipos(f)} | ${f.aVista.join(" ")}`);
  }
  const recusa = porErro(casos[4][1]);
  ok(/arquivo/.test(recusa.acoes[0].texto) && /serviço/.test(recusa.acoes[0].texto) && !/o arquivo não é o problema/.test(recusa.acoes[0].texto),
    "400 recusado: mostra as duas possibilidades (arquivo ou serviço), não afirma culpa do serviço", recusa.acoes[0].texto);
  const semConteudo = parseExtractionResponse({ choices: [{ message: { content: "" } }] });
  const motivoVazio = String((semConteudo as { falha_motivo?: string; falhaMotivo?: string }).falha_motivo ?? (semConteudo as { falhaMotivo?: string }).falhaMotivo ?? "");
  ok(/sem conte/.test(motivoVazio) && tipos(falhaDeExtracaoNaTela(doBanco(motivoVazio))) === "servico_de_ia",
    "emissor real: resposta sem conteúdo (grafia com acento) é falha do serviço", motivoVazio);
  const aviso = avisoTruncamentoPlanilha(Array.from({ length: 12 }, () => ({ a: 1 })), { maxRows: 5, maxCols: 5 }) ?? "";
  const planilha = falhaDeExtracaoNaTela(doBanco(aviso));
  ok(planilha.acoes.length === 1 && planilha.acoes[0].tipo === "planilha_cortada" && /fatiado/.test(planilha.acoes[0].texto)
    && !/reenvie o mesmo arquivo\./.test(planilha.acoes[0].texto) && planilha.aVista[0].startsWith("Planilha maior que o teto de envio"),
    "emissor real: planilha cortada pede reenvio FATIADO, nunca 'reenvie o mesmo arquivo'", `${aviso} || ${tipos(planilha)}`);
  // Estes emissores moram em strings de nó Code (N8N/build-workflow.mjs ~1180, 1277, 1362-1370,
  // 2011-2029): não dá para importá-los. Texto transcrito do código-fonte; mudou lá, mude aqui.
  const doNo: Array<[string, string, string]> = [
    ["xlsx várias abas", "O arquivo .xlsx tem 3 abas e o extrator nativo leu SO a primeira (120 linha(s)); as outras 2 aba(s) NAO foram lidas e a tabela financeira pode estar em qualquer uma delas. Os nomes das abas nao estao disponiveis (ficam no workbook.xml, comprimido). Abra o arquivo e reenvie a aba certa, ou confirme que a primeira e a unica com dado.", "xlsx_varias_abas"],
    ["extração nativa falhou", "A extracao NATIVA deste arquivo FALHOU no n8n (xlsx): erro. NENHUM dado deste documento chegou ao banco nem ao book -- o que o arquivo contem NAO foi lido. Isto e uma falha do PIPELINE, nao do arquivo: nao registre este documento como ilegivel sem conferir.", "falha_do_sistema"],
    ["recompor conteúdo", "Recompor Conteudo Extraido: nao foi possivel religar esta linha ao documento de origem (itemMatching falhou). Conteudo NAO chegou a extracao.", "falha_do_sistema"],
    ["linha acima do teto", "bloco 2: uma linha sozinha já passa do teto de saída do modelo — não há corte mais fino que a linha, e a resposta deste bloco pode ter vindo cortada", "resposta_truncada"],
    ["JSON inválido", "Resposta do provedor de IA nao veio em JSON valido.", "resposta_invalida"],
    ["limite de tokens", "Resposta do provedor de IA atingiu o limite de tokens de saida; o JSON veio valido, mas o conteudo pode estar incompleto (faltando linhas do fim do documento).", "resposta_truncada"],
    ["sem conteudo (nó inline, sem acento)", "Resposta do provedor de IA (OpenAI) sem conteudo (falha de rede/API).", "servico_de_ia"],
    ["rótulo colado (nó inline, sem acento)", "2 rotulo(s) com numero colado que nao e o valor da linha (a conta foi mantida): \"A | B\"", "conferir_na_revisao"],
  ];
  for (const [nome, texto, esperado] of doNo) {
    const f = falhaDeExtracaoNaTela(doBanco(texto));
    ok(tipos(f) === esperado && f.tecnico === texto && !f.aVista.includes("Há uma causa que não foi possível classificar; o detalhe está em Detalhes técnicos."),
      `emissor do nó, ${nome}: classificado como ${esperado}`, `${tipos(f)} | ${f.aVista.join(" ")}`);
  }
  for (const [nome, texto] of doNo.filter(([, , e]) => e === "xlsx_varias_abas")) {
    ok(!/reenvie o mesmo arquivo\./.test(falhaDeExtracaoNaTela(doBanco(texto)).acoes[0].texto), `${nome}: não manda reenviar o mesmo arquivo`);
  }
  // identidade de linha como o emissor a escreve (`<coluna>=<valor> + …`, aritmetica.mjs:119): nomeia a linha
  const identidade = 'identidade de linha não fecha em "001018 Custo com venda de plantadeira": Janeiro=0 + Fevereiro=5 = 5, mas a coluna "Total" declara 9 — diferença de 4.00 (tolerância de arredondamento: 1). Um dos dois valores está errado, e o book vai sair com essa diferença nesta linha.';
  const idf = falhaDeExtracaoNaTela(doBanco(identidade));
  ok(idf.aVista.length === 1 && idf.aVista[0].includes("001018 Custo com venda de plantadeira") && idf.aVista[0].includes("diferença de 4.00"),
    "identidade de linha no formato real do emissor nomeia a linha", idf.aVista.join(" "));
  // ERRO NA CHAMADA sem status e sem sinal de rede não afirma causa
  const semStatus = falhaDeExtracaoNaTela(doBanco("ERRO NA CHAMADA AO PROVEDOR DE IA: falhou"));
  ok(tipos(semStatus) === "chamada_incerta", "erro de chamada sem status nem sinal de rede não culpa o serviço", tipos(semStatus));

  // O técnico carrega valores e rótulos do cliente: no modo discrição tem de ir num elemento
  // `valor-sensivel` (a vistoria de 06/11 achou-o sem a marca).
  const tela = readFileSync(new URL("../src/app/casos/[id]/Pendencia.tsx", import.meta.url), "utf8");
  ok(/<p className="valor-sensivel">\{falha\.tecnico\}<\/p>/.test(tela), "Detalhes técnicos da falha de extração é marcado como sensível");
  // Causa nova (não reconhecida): não afirma causa (regra 1) e o detalhe segue acessível.
  const nova = falhaDeExtracaoNaTela(doBanco("o disco do servidor encheu"));
  ok(nova.acoes.length === 1 && nova.acoes[0].tipo === "nao_classificada" && /não foi possível classificar/.test(nova.acoes[0].texto)
    && nova.tecnico === "o disco do servidor encheu", "causa desconhecida: não afirma causa e guarda o detalhe", JSON.stringify(nova));
  ok(falhaDeExtracaoNaTela("texto sem motivo").frase === "texto sem motivo" && falhaDeExtracaoNaTela("texto sem motivo").tecnico === null,
    "descrição fora do formato passa inteira, sem inventar motivo");
}

console.log(`\n${passou} asserts passaram, ${falhas} falharam`);
if (falhas > 0) process.exit(1);
console.log("KIT BÁSICO OK — a tela pergunta ao banco, nunca rederiva a regra do COMBINADO estrutural");
