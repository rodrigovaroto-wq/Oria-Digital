import type { ServicoDocumentoServeComo } from "@/lib/kit-basico";
import type { createClient } from "./server";

type Supabase = Awaited<ReturnType<typeof createClient>>;

/**
 * A porta de `itensDoKitBasicoAtendidos` para o banco: `fn_documento_serve_como`.
 *
 * UMA função, não duas cópias: a visão geral (KPI do Kit Básico e Próximo passo) e a aba
 * Documentos (a grade do Kit) precisam da MESMA resposta, e a regra de "este documento
 * serve como COMBINADO" mora no banco (0157) — duplicá-la aqui seria a segunda
 * implementação que `verificar-kit-basico.mts` existe para impedir.
 *
 * TOLERANTE A ERRO: o dono aplica migrations à mão, e um banco sem a 0157 é estado
 * normal, não defeito. Sem a função, a resposta é a de ANTES da 0157 — só o rótulo
 * conta — e nunca "satisfeito" por invenção do portal.
 */
export function servicoDocumentoServeComo(supabase: Supabase): ServicoDocumentoServeComo {
  return async (documentoId, tipoTaxonomia) => {
    const { data, error } = await supabase.rpc("fn_documento_serve_como", {
      p_documento_id: documentoId,
      p_tipo_taxonomia: tipoTaxonomia,
    });
    if (error) return false;
    return data === true;
  };
}
