// O Kit Básico satisfeito, perguntando ao BANCO — nunca rederivado aqui.
//
// O DEFEITO (revisão de 02/09, lote 7377): a tela de um caso decidia sozinha,
// em `casos/[id]/page.tsx`, se um item do Kit Básico estava presente
// comparando `documento.tipo_taxonomia === item.codigo`. Essa é a MESMA regra
// que `fn_recomputar_completude` passo (1) usava até a migration
// `Supabase/migrations/0157_o_combinado_que_travava_o_kit_basico.sql` — e a
// 0157 substituiu exatamente essa regra no banco por
// `fn_documento_serve_como(documento_id, tipo_taxonomia)`, que também aceita
// um documento ESTRUTURALMENTE combinado (`fn_documento_de_varias_empresas`,
// 0155) ainda que o classificador o tenha rotulado de outra coisa.
//
// Sem este arquivo, a tela continuava com a implementação ANTIGA da regra —
// uma SEGUNDA implementação, divergente da nova — e por isso, no lote 7377,
// o Portão 1 abria (`portao1_ok = true`, a pendência `item_faltante` se
// resolvia sozinha) e a grade do Kit Básico continuava desenhando COMBINADO
// em cinza, "não recebido", como se a pendência ainda existisse. Duas telas
// da mesma verdade discordando, sem nenhum sinal de erro.
//
// A CORREÇÃO não reimplementa `fn_documento_de_varias_empresas` em
// TypeScript — isso SERIA uma segunda regra, só que mais nova. Em vez disso,
// pergunta ao banco, documento por documento, via a mesma função que o passo
// (1) usa: `fn_documento_serve_como`. E só pergunta pelos itens que o rótulo
// sozinho NÃO resolveu — no caminho comum (nenhuma exceção estrutural em
// jogo) o número de perguntas extras é zero.

import type { Documento, TaxonomiaTipoDocumento } from "./types";

/**
 * A única porta de saída para o banco. No portal é
 * `supabase.rpc("fn_algum_documento_serve_como", { p_documento_ids, p_tipo_taxonomia })`
 * (0276, bool_or de `fn_documento_serve_como` sobre o array): UMA ida por item do Kit em vez de
 * uma por documento — 2 itens x 115 documentos eram 230 RPCs, 4,7 s medidos; em lote são 2 RPCs,
 * 0,45 s. Em teste é um dublê que devolve o que o SQL devolveria — para o invariante travar no
 * COMPORTAMENTO (a tela concorda com o Portão 1) e não em como a exceção é calculada.
 *
 * Contrato de falha: lança. Quem chama trata o lançamento como Kit NÃO LIDO, nunca como "não atende".
 */
export type ServicoDocumentoServeComo = (
  documentoIds: string[],
  tipoTaxonomia: string,
) => Promise<boolean>;

/**
 * Os códigos do Kit Básico satisfeitos por ALGUM documento do caso — pelo
 * rótulo (`tipo_taxonomia === codigo`, resolvido aqui sem chamada nenhuma,
 * porque é comparação de dado e não regra de negócio) OU pela estrutura, que
 * só o banco sabe responder (`servico`).
 *
 * Não filtra por conteúdo extraído (`checklist_item_status`) — isso é uma
 * pergunta diferente (passo 2/2b de `fn_recomputar_completude`) e continua
 * fora daqui, como já era antes desta correção.
 */
export async function itensDoKitBasicoAtendidos(
  kitBasico: ReadonlyArray<Pick<TaxonomiaTipoDocumento, "codigo">>,
  documentos: ReadonlyArray<Pick<Documento, "id" | "tipo_taxonomia">>,
  servico: ServicoDocumentoServeComo,
): Promise<Set<string>> {
  const porRotulo = new Set(
    documentos.map((d) => d.tipo_taxonomia).filter((t): t is string => Boolean(t)),
  );
  const atendidos = new Set(porRotulo);

  // Sem documento não há o que perguntar (e o banco responderia false de qualquer jeito).
  const ids = documentos.map((d) => d.id);
  if (ids.length === 0) return atendidos;

  await Promise.all(
    kitBasico
      .filter((item) => !porRotulo.has(item.codigo))
      .map(async (item) => {
        if (await servico(ids, item.codigo)) atendidos.add(item.codigo);
      }),
  );

  return atendidos;
}
