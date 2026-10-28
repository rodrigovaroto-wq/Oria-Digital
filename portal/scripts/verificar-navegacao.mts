// A SUÍTE DA NAVEGAÇÃO DO MANDATO — a barra de etapas, "Meus × Todos" e a tela de membros (27/10/2026).
//
// POR QUE ELA EXISTE. Três defeitos silenciosos moram aqui, e nenhum quebra o build:
//   a. uma subpágina nova do mandato sem etapa na barra (a tela existe e ninguém sabe onde ela está);
//   b. "Membros"/"Todos" aparecendo para quem não é administrador (o link vaza; a recusa do banco chega depois);
//   c. mandato sem membro aparecendo como "0 membros" quando a contagem NÃO foi conferida (regra 1), ou
//      não aparecendo destacado quando foi conferida e deu zero.
// E a recusa 42501 do banco chegando ao analista como código cru em vez de frase.
//
// LIMITE, dito: não há banco nem login aqui. A suíte afirma as DECISÕES (lib/etapas.ts, lib/membros.ts) e
// exercita `executarMembro` com um cliente rpc falso — não prova o desenho do React nem a RLS real.
// O que liga as decisões às telas é conferido por varredura do disco (item 2) e pelo build.
import { etapasDoMandato, etapaAtiva } from "../src/lib/etapas.ts";
import {
  executarMembro, fraseDoErroDeMembro, origemDoMembro, visaoDaLista, mandatosMeus,
  resumoDeMembros, situacaoDeMembros, FALTA_EMAIL, idCurto,
} from "../src/lib/membros.ts";
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, relative, sep } from "node:path";

let ok = 0;
const falhas: string[] = [];
function checar(condicao: boolean, o_que: string) {
  if (condicao) { ok += 1; return; }
  falhas.push(o_que);
}

const ID = "11111111-1111-1111-1111-111111111111";
const USUARIO = "22222222-2222-2222-2222-222222222222";

// 1. A barra: quais etapas, para quem.
const comoAdmin = etapasDoMandato(ID, `/casos/${ID}`, true);
const comoAnalista = etapasDoMandato(ID, `/casos/${ID}`, false);
checar(comoAdmin.map((e) => e.rotulo).join("|") ===
  "Visão geral|Documentos|Perímetro|Revisão|Perguntas|Modelagem|Apresentação|Membros|Consultas externas",
  `etapas do administrador fora do combinado: ${comoAdmin.map((e) => e.rotulo).join("|")}`);
checar(!comoAnalista.some((e) => e.chave === "membros"), "a etapa Membros apareceu para quem não é administrador");
checar(comoAnalista.length === comoAdmin.length - 1, "o não administrador deve perder SÓ a etapa Membros");
const consultas = comoAdmin.find((e) => e.chave === "consultas");
checar(!!consultas && consultas.emConstrucao && consultas.href === undefined && !consultas.ativa,
  "Consultas externas tem de ser desabilitada, sem destino e dita 'em construção' (nunca uma tela vazia que parece sem achado)");
checar(comoAdmin.filter((e) => e.href).every((e) => e.href!.startsWith(`/casos/${ID}`)), "etapa aponta para fora do mandato");

// 2. A barra está em TODA rota do mandato, e marca UMA etapa ativa. Varre as páginas que existem no disco:
// subpágina nova sem etapa reprova aqui (nenhuma etapa ativa = o usuário não sabe onde está).
const RAIZ = new URL("../src/app/casos/[id]/", import.meta.url).pathname;
function paginas(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((d) =>
    d.isDirectory() ? paginas(join(dir, d.name)) : d.name === "page.tsx" ? [join(dir, d.name)] : []);
}
const rotas = paginas(RAIZ).map((p) => {
  const rel = relative(RAIZ, p).split(sep).slice(0, -1).join("/").replace(/\[docId\]/g, "22222222");
  return rel ? `/casos/${ID}/${rel}` : `/casos/${ID}`;
});
checar(rotas.length >= 8, `a varredura achou só ${rotas.length} páginas do mandato — o caminho do diretório mudou`);
checar(existsSync(join(RAIZ, "layout.tsx")), "falta app/casos/[id]/layout.tsx — sem ele a barra não aparece em rota nenhuma");
const layout = existsSync(join(RAIZ, "layout.tsx")) ? readFileSync(join(RAIZ, "layout.tsx"), "utf8") : "";
checar(/<EtapasDoMandato[^>]*\bid=/.test(layout) && layout.includes("{children}"), "o layout do mandato não desenha a barra em volta das páginas");
for (const rota of rotas) {
  const ativas = etapasDoMandato(ID, rota, true).filter((e) => e.ativa);
  checar(ativas.length === 1, `a rota ${rota} marca ${ativas.length} etapas ativas (esperado 1)`);
}
const casoDe = (rota: string, chave: string) => etapaAtiva(rota, ID) === chave;
checar(casoDe(`/casos/${ID}`, "visao"), "a raiz do mandato não marca Visão geral");
checar(casoDe(`/casos/${ID}/adicionar`, "documentos") && casoDe(`/casos/${ID}/documentos/abc`, "documentos"),
  "adicionar e a tela de um documento têm de marcar Documentos");
checar(etapaAtiva(`/casos/${ID}/modelagem`, ID) === "modelagem" && etapaAtiva(`/casos/${ID}/apresentacao`, ID) === "apresentacao",
  "modelagem e apresentação não podem marcar a mesma etapa");
checar(etapaAtiva(`/casos/OUTRO/modelagem`, ID) === null, "rota de OUTRO mandato marcou etapa deste");
checar(etapaAtiva(`/casos/${ID}/coisa-nova`, ID) === null, "segmento desconhecido não pode marcar etapa nenhuma");
checar(etapasDoMandato(ID, `/casos/${ID}/perimetro`, false).find((e) => e.ativa)?.chave === "perimetro", "a etapa ativa não segue a rota");

// 3. "Todos" só para administrador.
checar(visaoDaLista("todos", true) === "todos", "o administrador não alcança a visão Todos");
checar(visaoDaLista("todos", false) === "meus", "?visao=todos de quem não é administrador foi obedecido");
checar(visaoDaLista(undefined, true) === "meus" && visaoDaLista("lixo", true) === "meus", "o padrão da lista tem de ser Meus mandatos");

// 4. Meus mandatos = caso_membro do usuário; falha de leitura não filtra nem finge.
const casos = [{ id: "a" }, { id: "b" }, { id: "c" }];
checar(mandatosMeus(casos, new Set(["a", "c"])).map((c) => c.id).join() === "a,c", "Meus mandatos não filtra pelas linhas do usuário");
checar(mandatosMeus(casos, new Set()).length === 0, "usuário sem pertinência tem de ver lista vazia, não todos");
checar(mandatosMeus(casos, null).length === 3, "leitura de pertinência falha: a lista não pode ser inventada vazia");

// 5. Mandato sem membro: destacado quando CONFERIDO; "não conferido" quando não deu para ler.
const conferido = resumoDeMembros([{ caso_id: "a" }, { caso_id: "a" }, { caso_id: "c" }]);
checar(situacaoDeMembros(conferido, "b").situacao === "sem_membro", "mandato sem linha em caso_membro não foi marcado sem membro");
checar(situacaoDeMembros(conferido, "a").quantos === 2 && situacaoDeMembros(conferido, "a").situacao === "com_membros", "contagem de membros errada");
const naoLido = resumoDeMembros(null);
checar(situacaoDeMembros(naoLido, "b").situacao === "nao_conferido" && situacaoDeMembros(naoLido, "b").quantos === null,
  "contagem não lida virou número ('0 membros') — ausência apresentada como dado");
checar(situacaoDeMembros(resumoDeMembros([]), "b").situacao === "sem_membro", "tabela lida e vazia: todo mandato está sem membro");

// 6. A tela de membros: a recusa 42501 vira frase; o resto não some nem vira sucesso.
type Resp = { data: unknown; error: { code?: string; message?: string } | null };
const chamadas: Array<{ fn: string; args: Record<string, unknown> }> = [];
const falso = (r: Resp) => ({ rpc: (fn: string, args: Record<string, unknown>) => { chamadas.push({ fn, args }); return Promise.resolve(r); } });
const form = (v: string) => { const f = new FormData(); f.set("usuario", v); return f; };
const recusa = { data: null, error: { code: "42501", message: "fn_membro_adicionar: só o administrador atribui membros a um mandato" } };
const rAdd = await executarMembro(falso(recusa), "adicionar", ID, form(USUARIO));
checar(rAdd?.tom === "erro" && rAdd.texto.includes("administrador") && !rAdd.texto.includes("42501") && !rAdd.texto.includes("fn_membro"),
  `recusa 42501 ao adicionar não virou frase humana: ${rAdd?.texto}`);
const rRem = await executarMembro(falso(recusa), "remover", ID, form(USUARIO));
checar(rRem?.tom === "erro" && rRem.texto.includes("retirar") && rRem.texto.includes("Nada foi alterado"), `recusa 42501 ao remover: ${rRem?.texto}`);
checar(fraseDoErroDeMembro({ code: "42501" }, "adicionar") !== fraseDoErroDeMembro({ code: "42501" }, "remover"), "as duas recusas têm a mesma frase");
const rOutro = await executarMembro(falso({ data: null, error: { code: "XX000", message: "boom" } }), "adicionar", ID, form(USUARIO));
checar(rOutro?.tom === "erro" && rOutro.texto.includes("boom"), "erro desconhecido do banco sumiu em vez de aparecer");
const rFk = await executarMembro(falso({ data: null, error: { code: "23503", message: "fk" } }), "adicionar", ID, form(USUARIO));
checar(rFk?.tom === "erro" && !rFk.texto.includes("23503"), "FK inexistente deve virar frase");
chamadas.length = 0;
const rOk = await executarMembro(falso({ data: true, error: null }), "adicionar", ID, form(USUARIO));
checar(rOk?.tom === "ok" && chamadas[0]?.fn === "fn_membro_adicionar" && chamadas[0]?.args.p_caso === ID && chamadas[0]?.args.p_usuario === USUARIO,
  "adicionar não chamou fn_membro_adicionar com caso e usuário");
const rRemOk = await executarMembro(falso({ data: true, error: null }), "remover", ID, form(USUARIO));
checar(rRemOk?.tom === "ok" && chamadas[1]?.fn === "fn_membro_remover", "remover não chamou fn_membro_remover");
const rJa = await executarMembro(falso({ data: false, error: null }), "adicionar", ID, form(USUARIO));
checar(rJa?.tom === "ok" && rJa.texto.includes("já era") && !rJa.texto.includes("adicionado"), "false do banco (já era membro) virou 'adicionado'");
chamadas.length = 0;
const rMail = await executarMembro(falso({ data: true, error: null }), "adicionar", ID, form("ana@oria.com"));
checar(rMail?.tom === "erro" && rMail.texto.includes("fn_membros_do_caso") && chamadas.length === 0,
  "e-mail foi aceito (ou não explicou a falta da função) — o banco não resolve e-mail em usuário");
const rLixo = await executarMembro(falso({ data: true, error: null }), "adicionar", ID, form("123"));
checar(rLixo?.tom === "erro" && chamadas.length === 0, "identificador que não é uuid chegou ao banco");
const rVazio = await executarMembro(falso({ data: true, error: null }), "adicionar", ID, form("  "));
checar(rVazio?.tom === "erro" && chamadas.length === 0, "identificador vazio chegou ao banco");

// 7. Origem e identificador: `por` desconhecido aparece cru; a falta de e-mail é dita.
checar(origemDoMembro("criador").includes("criou"), "origem 'criador' sem frase");
checar(origemDoMembro("migracao:0215").includes("migração"), "origem da migração sem frase");
checar(origemDoMembro(`usuario:${USUARIO}`).includes(idCurto(USUARIO)) && !origemDoMembro(`usuario:${USUARIO}`).includes(USUARIO), "origem usuario:<id> deve mostrar o id curto");
checar(origemDoMembro("origem_nova_da_0300") === "origem_nova_da_0300", "origem desconhecida sumiu em vez de aparecer crua");
checar(FALTA_EMAIL.includes("fn_membros_do_caso"), "a tela perdeu o aviso do que falta no banco");

// 8. A página de membros se recusa sozinha a quem não é administrador (esconder o link não é controle).
const paginaMembros = readFileSync(join(RAIZ, "membros/page.tsx"), "utf8");
checar(/fn_eh_admin[\s\S]{0,200}notFound\(\)/.test(paginaMembros), "a página de membros não recusa (404) quem não é administrador");
const acoes = readFileSync(join(RAIZ, "membros/actions.ts"), "utf8");
checar(!/service_role|SERVICE_ROLE/.test(acoes), "a action de membros usa service role — quem escreve é o usuário logado");

if (falhas.length) {
  console.error(`${falhas.length} falha(s):`);
  for (const f of falhas) console.error(`  ✗ ${f}`);
  console.error(`${ok} verificações OK / ${falhas.length} falhas`);
  process.exit(1);
}
console.log(`${ok} verificações OK / 0 falhas`);
console.log("NAVEGAÇÃO OK — a barra marca uma etapa em toda rota do mandato, Membros e Todos só para administrador, sem membro só quando conferido, 42501 em frase");
