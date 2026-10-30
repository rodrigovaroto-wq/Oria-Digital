import { createHmac } from "node:crypto";
import { mensagemAssinada } from "../../../N8N/lib/assinatura-do-envio.mjs";

// O TOKEN QUE O PORTAL ENTREGA AO FORM DO n8n — o defeito e o desenho inteiros estão em
// `N8N/lib/assinatura-do-envio.mjs`; aqui fica só o lado que ASSINA.
//
// Em uma linha: o Form do n8n é público e a URL é a mesma para todo mandato, então o papel que o
// portal confere (0216) não vale nada contra um POST direto. O portal assina
// HMAC-SHA256(segredo, mandato_normalizado|exp|usuario_id) DEPOIS de conferir o papel, e o n8n
// recusa o envio que não traga uma assinatura válida para AQUELE mandato.
//
// Só roda no servidor (`node:crypto`, e o segredo nunca vai ao navegador). A mensagem assinada vem
// da MESMA função que o n8n usa (`mensagemAssinada`, importada, não copiada): duas montagens da
// mesma string divergem sem erro nenhum. O HMAC, ao contrário, é implementado duas vezes de
// propósito — aqui `node:crypto`, lá JS puro (o Code node do n8n não expõe `crypto`) — e a suíte
// exige que o token de um seja aceito pelo outro.

/**
 * 30 MINUTOS. O token é conferido quando o n8n DISPARA, e o Form só dispara quando o POST
 * termina: a janela precisa cobrir o UPLOAD inteiro. O token é emitido por `/api/intake/destino`
 * logo antes de o navegador começar a subir (depois da leitura dos arquivos oficiais). O teto por
 * arquivo é 15 MiB (`TETO_POR_ARQUIVO_BYTES`), então o pior lote razoável — 40 arquivos, ~600 MB —
 * a 5 Mbps de subida leva ~16 min; o lote de 48 arquivos/50 MB do caso AMO levou segundos.
 * 30 min cobre o pior caso com folga e continua curto para um token vazado: ele vale para UM
 * mandato e UM usuário, e o próprio papel pode mudar no banco depois. Reenvio gera token novo
 * (cada clique em Enviar pede `/destino` de novo).
 */
export const VALIDADE_DO_TOKEN_S = 30 * 60;

export const MENSAGEM_ENVIO_DESLIGADO =
  "Envio desligado: falta configurar N8N_INTAKE_SEGREDO nas variáveis de ambiente do portal (Vercel). "
  + "Sem ele o portal não consegue autorizar o envio ao n8n, e por isso nada foi enviado.";

export type TokenDoEnvio =
  | { ok: true; token: string; exp: number }
  | { ok: false; status: 503; mensagem: string };

/**
 * Assina o envio de `usuarioId` ao `mandato`. Segredo ausente (ou só espaços) NUNCA devolve token:
 * o envio sem token é exatamente o que o n8n recusa, e mandá-lo só adiaria a recusa para depois de
 * o analista esperar o upload.
 */
export function assinarEnvio(args: {
  mandato: string;
  usuarioId: string;
  segredo: string | undefined;
  agoraMs?: number;
}): TokenDoEnvio {
  const { mandato, usuarioId, segredo } = args;
  if (!segredo || segredo.trim() === "") return { ok: false, status: 503, mensagem: MENSAGEM_ENVIO_DESLIGADO };
  const exp = Math.floor((args.agoraMs ?? Date.now()) / 1000) + VALIDADE_DO_TOKEN_S;
  const assinatura = createHmac("sha256", segredo)
    .update(mensagemAssinada(mandato, exp, usuarioId), "utf8")
    .digest("hex");
  return { ok: true, token: `v1.${exp}.${usuarioId}.${assinatura}`, exp };
}
