// A ORIGEM DO NÚMERO, em cor FIXA (item 3 do benchmark: Daloopa azul/preto, DataSnipper V verde).
//
// Três origens, três cores que NÃO são cores de estado (risco/alerta/ok dizem "trava", "confirmar",
// "pronto"; origem é outra pergunta): `lido` = veio do documento (info), `calculado` = o sistema
// derivou de outros números (serie), `conferido` = uma PESSOA aceitou (tinta cheia, sem cor).
//
// `conferido` NÃO TEM DADO HOJE, e a tela diz isso em vez de omitir o slot: o estado "conferido" do item
// do Kit nasce em `fn_kit_do_caso` (migration 0300, ainda não aplicada). Marcar algo como conferido
// sem esse dado seria apresentar ausência como dado (regra 1). Quando a 0300 entrar, `disponivel`
// vira `true` num lugar só e a legenda passa a mostrar o selo cheio.
export type OrigemDoNumero = "lido" | "calculado" | "conferido";

export const ORIGENS: Record<OrigemDoNumero, {
  rotulo: string; ponto: string; texto: string; disponivel: boolean; semDado?: string;
}> = {
  lido: { rotulo: "lido do documento", ponto: "bg-info-500", texto: "text-info-700", disponivel: true },
  calculado: { rotulo: "calculado", ponto: "bg-serie-500", texto: "text-serie-700", disponivel: true },
  conferido: {
    rotulo: "conferido por pessoa", ponto: "bg-tinta-900", texto: "text-tinta-500", disponivel: false,
    semDado: "ainda não medido",
  },
};
