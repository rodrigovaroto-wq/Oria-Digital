// A SUÍTE DA FILA DE REPROCESSO (P7b) — o botão que reenvia o original guardado ao n8n.
//
// O que ela trava, e cada item é um erro que NÃO dá erro nenhum:
//   1. o corpo do pedido: vazio, não-uuid, repetido e acima do teto são recusados (uma lista
//      truncada em silêncio reenviaria menos do que o analista pediu);
//   2. por documento pedido: o que não está na fila, o `sem_original`, o `reaproveitaria`, o motivo
//      desconhecido e o `reprocessavel` sem `arquivo_ref` voltam COM o motivo e não seguem — e o que
//      segue mantém a ordem do pedido;
//   3. a ORDEM da rota (não dá para executá-la aqui: precisa de cookie e do n8n): Form configurado →
//      entrada → papel → token → fila → download → fetch, cada recusa usando o resultado, e o
//      download autenticado (nunca service role).
import { readFileSync } from "node:fs";
import { semComentarios } from "./lib/sem-comentarios.mts";
import {
  TETO_DE_DOCUMENTOS_POR_PEDIDO, FRASE_REAPROVEITARIA, FRASE_SEM_ORIGINAL, decidirPedido, fraseDoBloqueio,
  motivoDoDownload, validarCorpo, nomeParaEnvio, documentosEmLeitura, cortarPeloOrcamento, veredictoDoReprocesso, type ItemDaFila,
} from "../src/lib/fila-de-reprocesso.ts";

let ok = 0;
const falhas: string[] = [];
const checar = (c: boolean, o: string) => { if (c) ok += 1; else falhas.push(o); };

const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const item = (n: number, o: Partial<ItemDaFila> = {}): ItemDaFila => ({
  documento_id: uuid(n), documento_versao_id: uuid(1000 + n), n_versao: 1, nome_original: `doc${n}.pdf`,
  arquivo_ref: `caso/doc${n}.pdf`, tipo_taxonomia: null, falha_aberta_desde: "2026-11-01T00:00:00Z",
  falha_descricao: "a leitura falhou", tem_linha: false, reprocessavel: true, motivo_bloqueio: null, ...o,
});

// 1. O corpo
const bom = validarCorpo({ documentoIds: [uuid(1), uuid(2)] });
checar(bom.ok && bom.documentoIds.length === 2, "corpo válido passa com os ids");
checar(!validarCorpo(null).ok && !validarCorpo({}).ok && !validarCorpo({ documentoIds: [] }).ok && !validarCorpo({ documentoIds: "x" }).ok, "corpo ausente, sem lista ou lista vazia é recusado");
checar(!validarCorpo({ documentoIds: [uuid(1), "nao-e-uuid"] }).ok && !validarCorpo({ documentoIds: [uuid(1), 7] }).ok, "id que não é uuid é recusado");
const rep = validarCorpo({ documentoIds: [uuid(1), uuid(2), uuid(1)] });
checar(!rep.ok && /repete/.test(rep.mensagem), "ids repetidos são recusados com a frase");
const teto = Array.from({ length: TETO_DE_DOCUMENTOS_POR_PEDIDO }, (_, i) => uuid(i + 1));
checar(validarCorpo({ documentoIds: teto }).ok, "exatamente o teto passa");
const acima = validarCorpo({ documentoIds: [...teto, uuid(999)] });
checar(!acima.ok && acima.mensagem.includes(String(TETO_DE_DOCUMENTOS_POR_PEDIDO)), "um acima do teto é recusado dizendo o teto");

// 2. A decisão por documento
const fila = [
  item(1), item(2, { reprocessavel: false, motivo_bloqueio: "sem_original", arquivo_ref: null }),
  item(3, { reprocessavel: false, motivo_bloqueio: "reaproveitaria", tem_linha: true }),
  item(4, { reprocessavel: false, motivo_bloqueio: null }), item(5, { arquivo_ref: null }), item(6),
];
const d = decidirPedido([uuid(6), uuid(1), uuid(2), uuid(3), uuid(4), uuid(5), uuid(77)], fila);
checar(d.seguem.map((i) => i.documento_id).join() === [uuid(6), uuid(1)].join(), "só os reprocessáveis seguem, na ordem do pedido");
const motivo = (n: number) => d.recusados.find((r) => r.documentoId === uuid(n))?.motivo ?? "";
checar(d.recusados.length === 5, "cada pedido que não segue volta recusado (5 de 7)");
checar(motivo(2).includes(FRASE_SEM_ORIGINAL.motivo) && motivo(2).includes("aba Adicionar"), "sem_original: motivo e o que fazer");
checar(motivo(3).includes("reaproveitaria a leitura") && motivo(3).includes("pendência"), "reaproveitaria: motivo e o que fazer");
checar(/não conseguiu dizer/.test(motivo(4)), "bloqueio sem motivo conhecido é dito, não omitido");
checar(motivo(5).includes(FRASE_SEM_ORIGINAL.motivo), "reprocessável sem arquivo_ref não segue");
checar(/não está na fila/.test(motivo(77)), "id fora da fila não segue");
checar(fraseDoBloqueio("sem_original") === FRASE_SEM_ORIGINAL && fraseDoBloqueio("reaproveitaria") === FRASE_REAPROVEITARIA, "as frases da tela são as do motivo");
checar(/baixado/.test(motivoDoDownload("Object not found")) && motivoDoDownload("Object not found").includes("Object not found"), "falha de download diz a causa");

// 2b. Em leitura, nome, orçamento
const emLeit = decidirPedido([uuid(1), uuid(6)], fila, documentosEmLeitura([{ id: "v1", documento_id: uuid(1) }, { id: "v6", documento_id: uuid(6) }], new Set(["v6"])));
checar(emLeit.seguem.map((i) => i.documento_id).join() === uuid(6) && /já está em leitura/.test(emLeit.recusados[0]?.motivo ?? ""), "versão recente sem extração = 'já está em leitura'; a que já tem extração segue");
checar(nomeParaEnvio(item(1, { nome_original: null, arquivo_ref: "caso/abc/balanco.pdf" })) === "balanco.pdf", "nome nulo usa o fim do caminho guardado (com a extensão)");
checar(nomeParaEnvio(item(1, { nome_original: null, arquivo_ref: null })) === `documento-${uuid(1)}`, "sem nome e sem caminho: documento-<id>");
const MB = 1024 * 1024;
const orc = cortarPeloOrcamento([1, 2, 3].map((n) => ({ documentoId: uuid(n), bytes: 1 * MB })));
checar(orc.cabem.length === 2 && orc.recusados.length === 1 && /divida em pedidos menores/.test(orc.recusados[0].motivo), "3 MB a ~US$ 1,48/MB passa do teto de US$ 3: 2 entram, o excedente volta 'divida em pedidos menores'");
checar(cortarPeloOrcamento([{ documentoId: uuid(1), bytes: 100 * 1024 }]).cabem.length === 1, "arquivo pequeno cabe no orçamento");
const vs = (lidas: string[], falha: string | null) => veredictoDoReprocesso([uuid(1), uuid(2)], new Map([[uuid(1), ["a"]], [uuid(2), ["b"]]]), new Set(lidas), falha);
checar(vs(["a", "b"], null).estado === "pronto", "todos com versão nova E extração = pronto");
checar(vs(["a"], null).estado === "lendo" && vs([], null).lidos === 0, "versão sem extração ainda é 'lendo'");
checar(veredictoDoReprocesso([uuid(1)], new Map(), new Set(["a"]), null).estado === "lendo", "sem versão nova do documento nunca é 'lido', mesmo com extração de outra versão");
const rec = vs([], "Orçamento estourado.");
checar(rec.estado === "recusado" && /Orçamento estourado/.test(rec.mensagem ?? "") && /Nada foi lido/.test(rec.mensagem ?? ""), "falha do n8n sem nada lido: mostra a mensagem e diz que NADA foi lido");
checar(/Só 1 de 2/.test(vs(["a"], "x").mensagem ?? ""), "falha com parte lida diz quantos foram lidos");
checar(vs(["a", "b"], "ruído de outro envio").estado === "pronto", "tudo lido vence uma falha de outro envio");

// 3. A ordem da rota
const rota = semComentarios(readFileSync(new URL("../src/app/api/casos/[id]/reprocessar/route.ts", import.meta.url), "utf8"));
const pos = (re: RegExp) => rota.search(re);
const barra = (chamada: string) => new RegExp(`const\\s+(\\w+)\\s*=\\s*await\\s+${chamada}\\([^)]*\\);?\\s*if\\s*\\(\\s*!\\s*\\1\\.ok\\s*\\)\\s*return\\b`).test(rota);
const ordem = [/process\.env\.N8N_INTAKE_FORM_URL/, /validarCorpo\(/, /conferirEnvioAoCaso\(/, /emitirTokenDoEnvio\(/, /fn_fila_de_reprocesso/, /\.download\(/, /\bfetch\(/].map(pos);
checar(ordem.every((p) => p >= 0) && ordem.every((p, i) => i === 0 || ordem[i - 1] < p),
  "rota: Form configurado → entrada → papel → token → fila → download → fetch, nesta ordem");
checar(barra("conferirEnvioAoCaso") && barra("emitirTokenDoEnvio"), "rota: a recusa do papel e a do token usam o resultado (`if (!r.ok) return`)");
checar(!/service_?role|SUPABASE_SERVICE/i.test(rota) && /createClient\(/.test(rota) && /storage\.from\("documentos"\)/.test(rota), "rota: baixa com o cliente autenticado, nunca service role");
checar(pos(/versoesDesde\(/) > pos(/fn_fila_de_reprocesso/) && pos(/versoesDesde\(/) < pos(/\.download\(/) && pos(/cortarPeloOrcamento\(/) > pos(/\.download\(/) && pos(/cortarPeloOrcamento\(/) < pos(/\bfetch\(/) && /nomeParaEnvio\(/.test(rota),
  "rota: confere 'em leitura' antes do download e corta pelo orçamento entre o download e o fetch");
const status = semComentarios(readFileSync(new URL("../src/app/api/casos/[id]/reprocessar/status/route.ts", import.meta.url), "utf8"));
checar(/veredictoDoReprocesso\(/.test(status) && /fn_falhas_abertas/.test(status) && /versoesDesde\(/.test(status), "status: o veredito vem do acompanhamento por documento e da falha do n8n");
const tela = semComentarios(readFileSync(new URL("../src/components/fila-de-reprocesso.tsx", import.meta.url), "utf8"));
checar(/reprocessar\/status/.test(tela) && !/api\/intake\/status/.test(tela) && /const ocupado\s*=[^;]*terminou === null/.test(tela) && !/disabled=\{enviando\}/.test(tela), "tela: acompanha pelo status por documento e desabilita enquanto acompanha");
checar(/export const runtime = "nodejs"/.test(rota), "rota: runtime nodejs");
checar(/decidirPedido\(/.test(rota) && /status:\s*409/.test(rota), "rota: usa decidirPedido e sem reprocessável responde 409 antes do fetch");

if (falhas.length) {
  console.error(`FALHOU: ${falhas.length} de ${ok + falhas.length}`);
  for (const f of falhas) console.error(`  - ${f}`);
  process.exit(1);
}
console.log(`verificar-fila-de-reprocesso: ${ok} asserts, 0 falhas`);
