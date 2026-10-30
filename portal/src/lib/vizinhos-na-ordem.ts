// O "← anterior / próximo →" DO PAINEL DE DOCUMENTO segue a ORDEM QUE A LISTA MOSTRA (filtro e
// ordenação já aplicados), não a ordem do banco: quem confere 41 documentos de um filtro
// ("sem linha", um tipo) quer o próximo DAQUELA lista. A lista passa os ids na ordem; aqui só se
// acha o vizinho — nenhuma consulta nova (cota de egress apertada, PRODUCT.md).
//
// AUSÊNCIA NÃO É DADO (regra 1): documento que não está na ordem (o filtro mudou, ou a ordem não
// chegou) devolve `null` — NUNCA "primeiro da lista" nem "sem vizinhos". Nas pontas, o vizinho é
// `null` com `posicao`/`total` verdadeiros: a tela diz "último da lista filtrada" em vez de
// girar para o começo.
export type Vizinhos = {
  /** 1-based, como o analista conta. */
  posicao: number;
  total: number;
  anterior: string | null;
  proximo: string | null;
};

export function vizinhosNaOrdem(ids: readonly string[], atual: string): Vizinhos | null {
  const i = ids.indexOf(atual);
  if (i < 0) return null;
  return {
    posicao: i + 1,
    total: ids.length,
    anterior: i > 0 ? ids[i - 1] : null,
    proximo: i < ids.length - 1 ? ids[i + 1] : null,
  };
}
