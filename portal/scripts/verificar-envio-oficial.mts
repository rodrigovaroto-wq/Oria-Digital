// A SUÍTE DO ENVIO OFICIAL — o arquivo de leiaute lido no navegador, só o resumo gravado.
//
// POR QUE ELA EXISTE. Em 13/10/2026 o dono decidiu que SPED, CNAB, OFX e XML fiscal
// não vão mais ao n8n (que gasta ~600 MB + ~50x o tamanho do arquivo e cai com 29 MB):
// o `Leitor/lib` os lê no navegador e o portal grava o resumo pelas funções da 0207.
// O que esta suíte trava, e cada item é uma forma de errar que NÃO dá erro nenhum:
//   1. o arquivo oficial é reconhecido pelos BYTES (a extensão mente) e sai do lote
//      que vai ao n8n; zip e PDF continuam indo — um oficial que fosse ao n8n volta
//      a derrubá-lo, um PDF que ficasse no navegador sumiria do mandato;
//   2. a gravação é partida em chamadas de no máximo 5.000 itens SEM perder nem
//      repetir nenhum — um item a menos é um lançamento que não está no balancete;
//   3. o cabeçalho diz `ausente` quando o resumo é ausente, e não inventa conferência;
//   4. NENHUM caminho devolve "completo" sem a resposta `completo` do banco: falha de
//      rede no meio deixa o arquivo em carga e a frase diz isso (regra 7);
//   5. ausência nunca vira zero na frase (OFX não declara contagem; banco que não
//      informou o I155 não "fecha");
//   6. o `caso_id` reusa o mandato existente em vez de duplicá-lo.
//
// OS ARQUIVOS SÃO OS GERADORES DO LEITOR (`Dados de Teste/fontes-oficiais/gerar.mjs`),
// os mesmos que a suíte do Leitor usa, e o leitor que roda aqui é o MESMO que roda no
// navegador. O banco é substituído por um `rpc` de mentira — o contrato (0207) é o
// que se afirma, e o fluxo contra um Postgres com a 0207 é o `Supabase/test`.
import {
  CABECA_BYTES, MAX_ITENS_POR_CHAMADA, detectarPeloArquivo, separarOficiais, destinoDe, partirEmLotes,
  montarCabecalho, gravarResumo, obterCasoId, fluxoComProgresso, descreverContagem, descreverDesfecho,
  achadosDaConferencia, rotuloDoStatus, desfechoEncerra,
  type ChamarRpc, type EnvelopeDoLeitor, type ResumoDoLeitor,
} from "../src/lib/envio-oficial.ts";
import { TETO_POR_ARQUIVO_BYTES } from "../src/lib/limite-de-envio.ts";
import { lerEnvelopeDeBuffer, lerEnvelopeDeFluxo } from "../../Leitor/lib/envelope.mjs";
import {
  gerarSped, gerarCnab240, gerarOfx, gerarXmlFiscal, gerarEcdComLancamentos, gerarZip,
} from "../../Dados de Teste/fontes-oficiais/gerar.mjs";
import { readFileSync } from "node:fs";

let ok = 0;
const falhas: string[] = [];
function checar(condicao: boolean, o_que: string) {
  if (condicao) { ok += 1; return; }
  falhas.push(o_que);
}

// ---------------------------------------------------------------------------
// 1. O QUE É OFICIAL É DECIDIDO PELOS BYTES
// ---------------------------------------------------------------------------
const PDF = Buffer.from("%PDF-1.4\n1 0 obj<<>>endobj\n%%EOF\n");
const ZIP = await gerarZip([{ nome: "a.txt", buf: Buffer.from("oi") }]);
const ECD_GRANDE = gerarEcdComLancamentos({ extras: 1200 }).buf; // > 64 KB: a família sai dos primeiros 64 KB
const LOTE = [
  { nome: "ecd.txt", dados: gerarSped("ECD") },
  // A EXTENSÃO MENTE: um SPED salvo como .pdf é oficial, e um PDF salvo como .txt não é.
  { nome: "balanco-final.pdf", dados: gerarSped("ECF") },
  { nome: "extrato.ret", dados: gerarCnab240() },
  { nome: "extrato.ofx", dados: gerarOfx() },
  { nome: "nota.xml", dados: gerarXmlFiscal("nfe") },
  { nome: "ecd-grande.txt", dados: ECD_GRANDE },
  { nome: "dre.txt", dados: PDF },
  { nome: "documentos.zip", dados: ZIP },
  { nome: "anotacoes.txt", dados: Buffer.from("reuniao de terca: levar o balancete\n") },
];
const itens = await Promise.all(LOTE.map(async (a) => ({
  nome: a.nome, bytes: a.dados.length, deteccao: await detectarPeloArquivo(new Blob([new Uint8Array(a.dados)])),
})));
const { oficiais, aoN8n } = separarOficiais(itens, (i) => i.deteccao);
const nomesOficiais = oficiais.map((i) => i.nome);
const nomesAoN8n = aoN8n.map((i) => i.nome);

checar(ECD_GRANDE.length > CABECA_BYTES, "o ECD grande da suíte deixou de passar de 64 KB: ele não prova mais que a família sai só da cabeça");
checar(nomesOficiais.length === 6 && nomesAoN8n.length === 3,
  `a separação deu ${nomesOficiais.length} oficiais e ${nomesAoN8n.length} para o n8n; o lote tem 6 e 3 (a varredura parou de medir)`);
checar(["ecd.txt", "balanco-final.pdf", "extrato.ret", "extrato.ofx", "nota.xml", "ecd-grande.txt"].every((n) => nomesOficiais.includes(n)),
  `arquivo oficial ficou fora da leitura no navegador: oficiais = ${nomesOficiais.join(", ")}`);
checar(nomesAoN8n.join("|") === "dre.txt|documentos.zip|anotacoes.txt",
  `o que vai ao n8n mudou de conteúdo ou de ordem: ${nomesAoN8n.join(", ")} (PDF, zip e texto seguem como sempre, na ordem original)`);
checar(destinoDe(itens.find((i) => i.nome === "documentos.zip")!.deteccao) === "zip",
  "o zip deixou de ser reconhecido como zip: a tela não consegue dizer que ele segue pelo caminho de sempre");
checar(destinoDe(null) === "extracao" && destinoDe(undefined) === "extracao" && destinoDe({ familia: null, subtipo: null }) === "extracao",
  "arquivo que não pôde ser examinado (null) deixou de seguir o caminho de sempre");
checar(separarOficiais([], () => null).oficiais.length === 0, "lote vazio deixou de separar em dois vazios");

// ---------------------------------------------------------------------------
// 2. A PARTIÇÃO EM CHAMADAS DE NO MÁXIMO 5.000 ITENS
// ---------------------------------------------------------------------------
const seq = (n: number, p: string) => Array.from({ length: n }, (_, i) => `${p}${i}`);
let particoes = 0;
for (const [nr, ng] of [[12000, 7000], [5000, 0], [5001, 0], [0, 5001], [4999, 3], [1, 1], [0, 0], [10000, 10000], [4000, 4000]] as const) {
  const R = seq(nr, "r"), G = seq(ng, "g");
  const partes = partirEmLotes(R, G);
  particoes += 1;
  checar(partes.every((p) => p.registros.length + p.grupos.length <= MAX_ITENS_POR_CHAMADA && p.registros.length + p.grupos.length > 0),
    `partição de ${nr} registros e ${ng} grupos tem parte acima de ${MAX_ITENS_POR_CHAMADA} itens (o banco recusa) ou parte vazia`);
  checar(partes.flatMap((p) => p.registros).join(",") === R.join(",") && partes.flatMap((p) => p.grupos).join(",") === G.join(","),
    `partição de ${nr} registros e ${ng} grupos perdeu, repetiu ou trocou a ordem de itens`);
  checar(partes.length === Math.ceil((nr + ng) / MAX_ITENS_POR_CHAMADA),
    `partição de ${nr} registros e ${ng} grupos fez ${partes.length} chamadas; o mínimo é ${Math.ceil((nr + ng) / MAX_ITENS_POR_CHAMADA)}`);
}
checar(particoes === 9, "a varredura de partições parou de rodar todos os casos");
let lancou = false;
try { partirEmLotes([1], [], 0); } catch { lancou = true; }
checar(lancou, "partirEmLotes aceitou máximo 0: o laço não termina");

// ---------------------------------------------------------------------------
// 3. O CABEÇALHO SAI DO RESUMO
// ---------------------------------------------------------------------------
const lido = (buf: Buffer) => lerEnvelopeDeBuffer(buf, { resumir: true }) as { envelope: EnvelopeDoLeitor; resumo: ResumoDoLeitor };
const ECD = lido(gerarEcdComLancamentos({ desbalanceado: true }).buf);
const OFX = lido(gerarOfx());
const cabEcd = montarCabecalho(ECD.resumo);
const cabOfx = montarCabecalho(OFX.resumo);
checar((ECD.resumo.registros?.length ?? 0) > 0 && (ECD.resumo.lancamentos_por_conta_mes?.length ?? 0) > 0,
  "o ECD da suíte não rendeu registros e grupos: o cabeçalho abaixo seria afirmado sobre vazio");
checar(cabEcd.total_registros === ECD.resumo.registros!.length && cabEcd.total_grupos === ECD.resumo.lancamentos_por_conta_mes!.length,
  "os totais do cabeçalho não são os do resumo (registros e grupos)");
checar(cabEcd.versao === ECD.resumo.versao && cabEcd.hash_sha256 === ECD.envelope.hash_sha256 && !!cabEcd.hash_sha256,
  "o cabeçalho perdeu a versão ou o hash do arquivo");
checar(cabEcd.conferencia !== undefined && cabEcd.descartado !== undefined && !("ausente" in cabEcd),
  "o cabeçalho de resumo presente não leva conferência e descartado, ou leva `ausente`");
checar(OFX.resumo.ausente !== undefined && cabOfx.ausente === OFX.resumo.ausente && cabOfx.total_registros === 0 && cabOfx.total_grupos === 0,
  "o cabeçalho de resumo ausente não diz `ausente` (com o motivo) e totais 0 do contrato");
checar(!("conferencia" in cabOfx) && !("descartado" in cabOfx),
  "o cabeçalho de resumo ausente inventou `conferencia`/`descartado` (chave com valor undefined vira null no JSON)");
checar(Object.values(cabOfx).every((v) => v !== undefined && v !== null),
  "o cabeçalho do OFX leva null/undefined num campo (o JSON o mandaria como null: valor onde há ausência)");

// ---------------------------------------------------------------------------
// 4. A GRAVAÇÃO: iniciar -> anexar -> concluir, e o que cada falha diz
// ---------------------------------------------------------------------------
type Chamada = { fn: string; args: Record<string, unknown> };
function banco(respostas: Record<string, (n: number, args: Record<string, unknown>) => unknown>) {
  const chamadas: Chamada[] = [];
  const contagem: Record<string, number> = {};
  const rpc: ChamarRpc = async (fn, args) => {
    chamadas.push({ fn, args });
    contagem[fn] = (contagem[fn] ?? 0) + 1;
    const r = respostas[fn]?.(contagem[fn], args);
    if (r instanceof Error) throw r;
    if (r && typeof r === "object" && "erro" in (r as object)) return { data: null, error: (r as { erro: { message: string; code?: string } }).erro };
    return { data: r ?? null, error: null };
  };
  return { rpc, chamadas, nomes: () => chamadas.map((c) => c.fn) };
}
const CASO = "11111111-1111-1111-1111-111111111111";
const ID = "aaaaaaaa-0000-0000-0000-000000000000";
const GRANDE: ResumoDoLeitor = {
  versao: "resumo/1", hash_sha256: "ab".repeat(32), conferencia: { lancamentos_desbalanceados: 0 }, descartado: "x",
  registros: seq(12001, "r").map((r) => [1, r]), lancamentos_por_conta_mes: seq(7000, "g").map((g) => ({ conta: g })),
};
const ENV = ECD.envelope;
const iniciarOk = () => ({ id: ID, status: "em_carga", vigente: false, resumo: "em_carga" });
const concluirOk = (extra = {}) => ({ resumo: "completo", registros: 12001, grupos: 7000, i155_nao_fecham: 0, ...extra });

{
  const b = banco({ fn_resumo_iniciar: iniciarOk, fn_resumo_anexar: () => ({}), fn_resumo_concluir: () => concluirOk() });
  const etapas: string[] = [];
  const d = await gravarResumo(b.rpc, CASO, ENV, GRANDE, (p) => etapas.push(p.etapa));
  const anexos = b.chamadas.filter((c) => c.fn === "fn_resumo_anexar");
  checar(b.nomes()[0] === "fn_resumo_iniciar" && b.nomes().at(-1) === "fn_resumo_concluir" && b.nomes().slice(1, -1).every((n) => n === "fn_resumo_anexar"),
    `a ordem das chamadas não é iniciar, anexar..., concluir: ${b.nomes().join(",")}`);
  checar(anexos.length === 4, `12001 registros + 7000 grupos viraram ${anexos.length} chamadas de anexar; o mínimo com 5.000 é 4`);
  checar(anexos.every((c) => (c.args.p_registros as unknown[]).length + (c.args.p_grupos as unknown[]).length <= 5000 && c.args.p_arquivo === ID),
    "uma chamada de anexar passou de 5.000 itens ou não leva o id do arquivo aberto no iniciar");
  checar(anexos.reduce((s, c) => s + (c.args.p_registros as unknown[]).length, 0) === 12001
    && anexos.reduce((s, c) => s + (c.args.p_grupos as unknown[]).length, 0) === 7000,
    "a soma dos itens anexados não é a do resumo");
  const ini = b.chamadas[0].args;
  checar(ini.p_caso === CASO && ini.p_documento === null && ini.p_envelope === ENV
    && JSON.stringify(ini.p_cabecalho) === JSON.stringify(montarCabecalho(GRANDE)),
    "o iniciar não leva caso, documento null, o envelope e o cabeçalho do resumo");
  checar(d.tipo === "completo" && d.registros === 12001 && d.grupos === 7000, "o desfecho completo não repassa o que o banco devolveu");
  checar(etapas[0] === "iniciar" && etapas.includes("anexar") && etapas.at(-1) === "concluir", "o progresso da gravação não passa por iniciar, anexar e concluir");
}
{ // resumo ausente: o banco responde `ausente`, e nada é anexado
  const b = banco({ fn_resumo_iniciar: () => ({ id: ID, status: "lido", vigente: true, resumo: "ausente" }) });
  const d = await gravarResumo(b.rpc, CASO, OFX.envelope, OFX.resumo);
  checar(d.tipo === "ausente" && d.motivo === OFX.resumo.ausente && b.nomes().join() === "fn_resumo_iniciar",
    `resumo ausente chamou ${b.nomes().join(",")}: só o iniciar é chamado, e o motivo é o do leitor`);
  const t = descreverDesfecho(d);
  checar(t.tom === "alerta" && t.texto.includes("nenhum conteúdo dele está no banco"), "a frase do resumo ausente não diz o efeito: o conteúdo não está no banco");
}
{ // reenvio: nada é anexado
  const b = banco({ fn_resumo_iniciar: () => ({ id: ID, status: "lido", vigente: true, resumo: "reenvio" }) });
  const d = await gravarResumo(b.rpc, CASO, ENV, GRANDE);
  checar(d.tipo === "reenvio" && b.nomes().join() === "fn_resumo_iniciar", `reenvio chamou ${b.nomes().join(",")}`);
}
{ // exceção do banco (trilha desligada): a mensagem dele, em português, na tela
  const MSG = "A trilha de arquivos oficiais está desligada neste mandato (caso 1111).";
  const b = banco({ fn_resumo_iniciar: () => ({ erro: { message: MSG, code: "P0001" } }) });
  const d = await gravarResumo(b.rpc, CASO, ENV, GRANDE);
  const t = descreverDesfecho(d);
  checar(d.tipo === "falha" && d.etapa === "iniciar" && d.origem === "banco" && !d.ficouEmCarga, "exceção do banco no iniciar não virou falha de banco, sem carga aberta");
  checar(t.texto.includes(MSG) && !/erro gen[ée]rico|algo deu errado|problema t[ée]cnico/i.test(t.texto),
    `a mensagem do banco não aparece inteira na frase da tela: "${t.texto}"`);
  checar(b.nomes().join() === "fn_resumo_iniciar" && !desfechoEncerra(d), "depois da exceção no iniciar o fluxo seguiu, ou o arquivo saiu da lista de reenvio");
}
{ // falha de rede no meio: o arquivo FICA em carga, e a frase NÃO diz concluído
  const b = banco({ fn_resumo_iniciar: iniciarOk, fn_resumo_anexar: (n) => (n === 2 ? { erro: { message: "TypeError: Failed to fetch" } } : {}), fn_resumo_concluir: () => concluirOk() });
  const d = await gravarResumo(b.rpc, CASO, ENV, GRANDE);
  const t = descreverDesfecho(d);
  checar(d.tipo === "falha" && d.etapa === "anexar" && d.origem === "rede" && d.ficouEmCarga, "falha de rede no anexar não ficou marcada como carga aberta");
  checar(!b.nomes().includes("fn_resumo_concluir"), "depois de uma parte que falhou o fluxo ainda chamou o concluir");
  checar(t.tom === "erro" && /NÃO está concluído/.test(t.texto) && /do zero/.test(t.texto) && !/Gravado por completo/.test(t.texto),
    `a frase da falha no meio não diz "não concluído" e "do zero": "${t.texto}"`);
  checar(!desfechoEncerra(d), "arquivo em carga saiu da lista: o próximo envio não o reenviaria");
}
{ // promessa rejeitada (nem resposta HTTP) conta como rede
  const b = banco({ fn_resumo_iniciar: () => new Error("Network request failed") });
  const d = await gravarResumo(b.rpc, CASO, ENV, GRANDE);
  checar(d.tipo === "falha" && d.origem === "rede" && !d.ficouEmCarga, "promessa rejeitada no iniciar não virou falha de rede");
}
{ // resposta que ninguém prometeu NÃO é sucesso
  const b1 = banco({ fn_resumo_iniciar: iniciarOk, fn_resumo_anexar: () => ({}), fn_resumo_concluir: () => ({ resumo: "talvez" }) });
  const d1 = await gravarResumo(b1.rpc, CASO, ENV, GRANDE);
  checar(d1.tipo === "falha" && d1.origem === "resposta_inesperada" && d1.ficouEmCarga, "concluir com resposta desconhecida virou sucesso");
  const b2 = banco({ fn_resumo_iniciar: () => ({ resumo: "talvez" }) });
  const d2 = await gravarResumo(b2.rpc, CASO, ENV, GRANDE);
  checar(d2.tipo === "falha" && d2.etapa === "iniciar" && d2.origem === "resposta_inesperada", "iniciar com resposta desconhecida virou sucesso");
  const b3 = banco({ fn_resumo_iniciar: iniciarOk, fn_resumo_anexar: () => ({}), fn_resumo_concluir: () => null });
  const d3 = await gravarResumo(b3.rpc, CASO, ENV, GRANDE);
  checar(d3.tipo === "falha" && d3.origem === "resposta_inesperada", "concluir sem corpo virou sucesso");
}
{ // recusado: o motivo do banco, e o efeito
  const b = banco({ fn_resumo_iniciar: iniciarOk, fn_resumo_anexar: () => ({}), fn_resumo_concluir: () => ({ resumo: "recusado", motivo: "registros anexados (10) diferem dos declarados (12)" }) });
  const d = await gravarResumo(b.rpc, CASO, ENV, GRANDE);
  const t = descreverDesfecho(d);
  checar(d.tipo === "recusado" && t.tom === "erro" && t.texto.includes("diferem dos declarados") && /Nada deste arquivo/.test(t.texto) && desfechoEncerra(d),
    `o recusado não mostra o motivo e o efeito: "${t.texto}"`);
}
{ // I155 que não fecham: alerta com o número; I155 não informado NÃO é "fecham"
  const mk = (extra: object) => banco({ fn_resumo_iniciar: iniciarOk, fn_resumo_anexar: () => ({}), fn_resumo_concluir: () => concluirOk(extra) });
  const com = descreverDesfecho(await gravarResumo(mk({ i155_nao_fecham: 3 }).rpc, CASO, ENV, GRANDE));
  checar(com.tom === "alerta" && com.texto.includes("3 saldo(s) I155 não fecham"), `I155 que não fecham não aparece com o número: "${com.texto}"`);
  const zero = descreverDesfecho(await gravarResumo(mk({ i155_nao_fecham: 0 }).rpc, CASO, ENV, GRANDE));
  checar(zero.tom === "ok" && zero.texto.includes("Todos os saldos I155 fecham"), "i155_nao_fecham = 0 medido deixou de dizer que fecham");
  const nada = descreverDesfecho(await gravarResumo(mk({ i155_nao_fecham: undefined }).rpc, CASO, ENV, GRANDE));
  checar(!/fecham/.test(nada.texto.replace("não informou", "")) && nada.texto.includes("não informou a conferência dos saldos"),
    `banco que não informou o I155 virou "fecham" (ausência apresentada como dado): "${nada.texto}"`);
}

// ---------------------------------------------------------------------------
// 5. O CASO_ID: reusa pelo nome, cria só se não existir
// ---------------------------------------------------------------------------
function clienteDeCasos(opts: { existente?: string; erroSelect?: string; erroInsert?: string; erroTrilha?: string }) {
  const log: string[] = [];
  const cliente = {
    from(tabela: string) {
      return {
        select: () => ({
          eq: (_c: string, nome: string) => ({
            order: () => ({
              limit: async () => {
                log.push(`select caso nome=${nome}`);
                return opts.erroSelect
                  ? { data: null, error: { message: opts.erroSelect } }
                  : { data: opts.existente ? [{ id: opts.existente }] : [], error: null };
              },
            }),
          }),
        }),
        insert: (linha: Record<string, unknown>) => {
          log.push(`insert ${tabela} ${JSON.stringify(linha)}`);
          if (tabela === "evento_auditoria") return Promise.resolve({ error: opts.erroTrilha ? { message: opts.erroTrilha } : null });
          return { select: () => ({ single: async () => (opts.erroInsert ? { data: null, error: { message: opts.erroInsert } } : { data: { id: "novo-id" }, error: null }) }) };
        },
      };
    },
  };
  return { cliente: cliente as unknown as Parameters<typeof obterCasoId>[0], log };
}
{
  const a = clienteDeCasos({});
  const r1 = await obterCasoId(a.cliente, "AMO", "id-da-tela");
  checar(r1.id === "id-da-tela" && !r1.criado && a.log.length === 0, "com casoId na tela o portal ainda consultou ou criou mandato");
  const b = clienteDeCasos({ existente: "id-existente" });
  const r2 = await obterCasoId(b.cliente, "AMO");
  checar(r2.id === "id-existente" && !r2.criado && b.log.length === 1, `mandato existente foi duplicado: ${b.log.join(" / ")}`);
  const c = clienteDeCasos({});
  const r3 = await obterCasoId(c.cliente, "AMO");
  checar(r3.id === "novo-id" && r3.criado && c.log.some((l) => l.startsWith("insert caso")) && c.log.some((l) => l.includes("evento_auditoria") && l.includes("caso_criado")),
    `mandato novo não foi criado com o evento caso_criado: ${c.log.join(" / ")}`);
  const d = clienteDeCasos({ erroTrilha: "sem permissão" });
  const warn = console.warn; let avisou = false; console.warn = () => { avisou = true; };
  const r4 = await obterCasoId(d.cliente, "AMO"); console.warn = warn;
  checar(r4.criado && avisou, "falha na trilha do caso novo foi engolida sem aviso no console (ou bloqueou o envio)");
  for (const [opts, trecho] of [[{ erroSelect: "RLS negou" }, "RLS negou"], [{ erroInsert: "violação" }, "violação"]] as const) {
    let msg = "";
    try { await obterCasoId(clienteDeCasos(opts).cliente, "AMO"); } catch (e) { msg = (e as Error).message; }
    checar(msg.includes(trecho) && msg.includes("AMO"), `erro do banco ao resolver o mandato não sobe com a mensagem dele: "${msg}"`);
  }
}

// ---------------------------------------------------------------------------
// 6. O QUE A TELA DIZ DA LEITURA — ausência nunca é zero
// ---------------------------------------------------------------------------
checar(/\d[\d.]* lidas × \d[\d.]* declaradas/.test(descreverContagem(ECD.envelope)),
  `a contagem lida × declarada do SPED não aparece: "${descreverContagem(ECD.envelope)}"`);
const cOfx = descreverContagem(OFX.envelope);
checar(OFX.envelope.controle_tipo === "sem_controle_no_formato" && /não declara/.test(cOfx) && !/declaradas/.test(cOfx),
  `OFX não declara contagem e a frase mostra uma: "${cOfx}"`);
const semDeclarada = descreverContagem({ ...ECD.envelope, controle_declarado: null });
checar(/não traz a contagem declarada/.test(semDeclarada) && !/× 0/.test(semDeclarada), `contagem declarada ausente virou zero: "${semDeclarada}"`);
checar(rotuloDoStatus({ ...ECD.envelope, status: "falhou", detalhe: { motivo: "XPTO" } }).includes("XPTO")
  && rotuloDoStatus({ ...ECD.envelope, status: "controle_divergente" }).includes("não bate")
  && rotuloDoStatus({ ...ECD.envelope, status: "versao_desconhecida", detalhe: { motivo: "v9" } }).includes("v9")
  && rotuloDoStatus({ ...ECD.envelope, status: "lido" }).includes("conferida"),
  "o status do envelope perdeu o motivo do leitor ou um dos quatro rótulos");

const desb = lido(gerarEcdComLancamentos({ desbalanceado: true, valorInvalido: true }).buf);
const limpo = lido(gerarEcdComLancamentos().buf);
const achados = achadosDaConferencia(desb.resumo);
checar(achados.length === 2 && achados.some((a) => /desbalanceado/.test(a)) && achados.some((a) => /inválido/.test(a)),
  `lançamento desbalanceado e valor inválido do ECD real não viraram achados: ${JSON.stringify(achados)}`);
checar(achadosDaConferencia(limpo.resumo).length === 0 && achadosDaConferencia(undefined).length === 0 && achadosDaConferencia(OFX.resumo).length === 0,
  "arquivo sem achado (ou sem conferência) passou a mostrar achado");

// ---------------------------------------------------------------------------
// 7. O PROGRESSO DE LEITURA É O DE BYTES LIDOS, e não muda o resultado
// ---------------------------------------------------------------------------
{
  const buf = new Uint8Array(ECD_GRANDE);
  let i = 0;
  const fluxo = new ReadableStream<Uint8Array>({ pull(c) { if (i >= buf.length) return c.close(); c.enqueue(buf.subarray(i, i + 8192)); i += 8192; } });
  const marcas: number[] = [];
  const r = (await lerEnvelopeDeFluxo(fluxoComProgresso(fluxo, (n) => marcas.push(n)), { resumir: true })) as { envelope: EnvelopeDoLeitor; resumo: ResumoDoLeitor };
  checar(marcas.length > 10 && marcas.every((m, k) => k === 0 || m > marcas[k - 1]), `o progresso não cresce a cada fatia (${marcas.length} marcas)`);
  checar(marcas.at(-1) === buf.length, `o último progresso (${marcas.at(-1)}) não é o tamanho do arquivo (${buf.length}): a barra não chega a 100%`);
  const direto = lido(ECD_GRANDE);
  checar(r.envelope.hash_sha256 === direto.envelope.hash_sha256 && JSON.stringify(r.resumo) === JSON.stringify(direto.resumo),
    "embrulhar o fluxo com o contador mudou o envelope ou o resumo");
}

// ---------------------------------------------------------------------------
// 8. O TETO POR ARQUIVO É O DO N8N (item do mesmo pedido)
// ---------------------------------------------------------------------------
const custo = readFileSync(new URL("../../N8N/lib/custo.mjs", import.meta.url), "utf8");
const doN8n = Number(/export const TETO_BYTES_POR_ARQUIVO = (\d+) \* 1024 \* 1024;/.exec(custo)?.[1]);
checar(Number.isFinite(doN8n) && TETO_POR_ARQUIVO_BYTES === doN8n * 1024 * 1024,
  `o teto por arquivo do portal (${TETO_POR_ARQUIVO_BYTES}) não é o do n8n (${doN8n} MiB): o portal deixaria subir o que o n8n recusa`);
checar(TETO_POR_ARQUIVO_BYTES === 15 * 1024 * 1024, "o teto por arquivo deixou de ser os 15 MiB medidos em 13/10/2026 (29 MB já enchem os 2 GB do n8n)");

// ---------------------------------------------------------------------------
// 9. A TELA USA ISTO — guarda ESTRUTURAL, declarada como tal
// ---------------------------------------------------------------------------
// Os asserts acima provam as funções; uma regressão que deixasse o componente de
// fora (todo arquivo voltando ao n8n) os manteria verdes. Sem navegador, o que dá
// para afirmar é que o componente CHAMA cada peça e na ordem certa. A prova de
// comportamento da tela foi feita num Chromium de verdade, à mão (ver o commit).
const lerFonte = (p: string) => readFileSync(new URL(p, import.meta.url), "utf8");
const TELA = lerFonte("../src/components/upload-form.tsx");
const WORKER = lerFonte("../src/lib/leitor-worker.ts");
const LIMITE = lerFonte("../src/lib/limite-de-envio.ts");
for (const chamada of ["separarOficiais(", "gravarResumo(", "lerNoNavegador(", "obterCasoId(", "detectarPeloArquivo("]) {
  checar(TELA.includes(chamada), `a tela de envio parou de chamar ${chamada}`);
}
checar(TELA.indexOf("separarOficiais(") < TELA.indexOf("planejarEnvio(") && TELA.indexOf("processarOficiais(aLerAqui") < TELA.indexOf("planejarEnvio("),
  "o lote deixou de ser separado (e os oficiais lidos) ANTES de planejar o envio ao n8n");
checar(/planejarEnvio\(\s*aoN8n\.map/.test(TELA), "o plano de envio ao n8n não é calculado só sobre o que sobrou dos oficiais");
checar(WORKER.includes("Leitor/lib/envelope.mjs") && !WORKER.includes("function leitorSped"),
  "o worker não importa o leitor do repositório (ou ganhou uma cópia dele)");
checar(LIMITE.includes('from "../../../N8N/lib/custo.mjs"'), "o teto por arquivo deixou de ser importado de N8N/lib/custo.mjs");

if (falhas.length > 0) {
  console.error(`\n${falhas.length} falha(s):`);
  for (const f of falhas) console.error(`  ✗ ${f}`);
  console.error(`\n${ok} verificações OK / ${falhas.length} falhas`);
  process.exit(1);
}
console.log(`${ok} verificações OK / 0 falhas`);
console.log("ENVIO OFICIAL OK — oficial é lido no navegador, o resto segue para o n8n, e nenhuma falha vira 'concluído'");
