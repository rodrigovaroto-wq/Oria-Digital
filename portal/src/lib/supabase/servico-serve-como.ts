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
 * TOLERANTE SÓ À FUNÇÃO AUSENTE: o dono aplica migrations à mão, e um banco sem a
 * 0157 é estado normal. Sem a função, a resposta é a de ANTES da 0157 — só o rótulo
 * conta. Qualquer outra falha lança (ver abaixo): falha não é "não atende".
 */
export function servicoDocumentoServeComo(supabase: Supabase): ServicoDocumentoServeComo {
  return async (documentoId, tipoTaxonomia) => {
    const { data, error } = await supabase.rpc("fn_documento_serve_como", {
      p_documento_id: documentoId,
      p_tipo_taxonomia: tipoTaxonomia,
    });
    if (error) {
      // Função AUSENTE (banco sem a 0157: PGRST202 no PostgREST, 42883 no Postgres) é
      // estado normal — volta à regra de antes, só o rótulo. QUALQUER OUTRO erro
      // (timeout, 5xx) LANÇA: devolver `false` transformava uma falha de leitura em
      // "item faltante", e o Próximo passo mandava pedir ao cliente o que ele já
      // enviou (revisão do PR #265). Quem chama trata o lançamento como leitura falha.
      if (error.code === "PGRST202" || error.code === "42883") return false;
      throw new Error(`fn_documento_serve_como falhou: ${error.message}`);
    }
    return data === true;
  };
}
