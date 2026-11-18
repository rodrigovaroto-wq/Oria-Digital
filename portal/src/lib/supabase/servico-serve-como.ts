import type { ServicoDocumentoServeComo } from "@/lib/kit-basico";
import type { ChamaRpc } from "@/lib/kit-do-caso";
import type { createClient } from "./server";

type Supabase = Awaited<ReturnType<typeof createClient>>;

/** Função AUSENTE: PGRST202 no PostgREST, 42883 no Postgres. */
const funcaoAusente = (e: { code?: string }) => e.code === "PGRST202" || e.code === "42883";

/**
 * A porta de `itensDoKitBasicoAtendidos` para o banco.
 *
 * UMA função, não duas cópias: a visão geral (KPI do Kit Básico e Próximo passo), a aba
 * Documentos (a grade do Kit) e o export da apresentação precisam da MESMA resposta, e a regra de
 * "este documento serve como COMBINADO" mora no banco (0157) — duplicá-la aqui seria a segunda
 * implementação que `verificar-kit-basico.mts` existe para impedir.
 *
 * EM LOTE (0276): `fn_algum_documento_serve_como(p_documento_ids, p_tipo_taxonomia)` responde por
 * todos os documentos numa ida (230 RPCs, 4,7 s -> 2 RPCs, 0,45 s no mandato de 115 documentos).
 * Banco sem a 0276 (o dono aplica migration à mão) cai no laço por documento da 0157 — mais lento,
 * mesma resposta. Banco sem a 0157 também: só o rótulo conta, a resposta de ANTES da 0157.
 *
 * TOLERANTE SÓ À FUNÇÃO AUSENTE. Qualquer outra falha LANÇA: falha não é "não atende" (timeout
 * virava "item faltante" e o Próximo passo mandava pedir ao cliente o que ele já enviou — revisão
 * do PR #265). Quem chama trata o lançamento como Kit NÃO LIDO.
 */
export function servicoDocumentoServeComo(supabase: Supabase): ServicoDocumentoServeComo {
  return async (documentoIds, tipoTaxonomia) => {
    const lote = await supabase.rpc("fn_algum_documento_serve_como", {
      p_documento_ids: documentoIds,
      p_tipo_taxonomia: tipoTaxonomia,
    });
    if (!lote.error) return lote.data === true;
    if (!funcaoAusente(lote.error)) throw new Error(`fn_algum_documento_serve_como falhou: ${lote.error.message}`);

    // Sem a 0276: o laço por documento (0157).
    const respostas = await Promise.all(documentoIds.map(async (id) => {
      const { data, error } = await supabase.rpc("fn_documento_serve_como", {
        p_documento_id: id,
        p_tipo_taxonomia: tipoTaxonomia,
      });
      if (error) {
        if (funcaoAusente(error)) return false; // sem a 0157: só o rótulo conta
        throw new Error(`fn_documento_serve_como falhou: ${error.message}`);
      }
      return data === true;
    }));
    return respostas.some(Boolean);
  };
}

/** A porta de `lerKitDoCaso` para `fn_kit_do_caso`: o mesmo cliente das telas, sem tratar erro (quem lê trata). */
export function chamaRpc(supabase: Supabase): ChamaRpc {
  return (nome, args) => supabase.rpc(nome, args);
}
