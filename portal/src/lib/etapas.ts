// AS ETAPAS DO MANDATO — a barra que aparece em TODA rota de `/casos/[id]/*` (decisão do dono, 27/10/2026).
//
// Antes a tela do mandato (846 linhas) ligava as subpáginas por botões soltos; quem entrava em
// Perímetro não via onde estava nem como chegar à Modelagem sem voltar. Aqui moram as DUAS perguntas
// que a barra responde, sem React, para a suíte poder afirmar o comportamento: quais etapas existem
// para ESTE usuário, e qual delas a rota atual marca como ativa.
//
// "Membros" só existe para administrador (fn_eh_admin, 0215): quem não é administrador não recebe
// nem o link — e a página ainda se recusa sozinha, porque esconder o link não é controle de acesso.
//
// "Consultas externas" é a etapa da 0217, que ainda não existe. Ela aparece DESABILITADA e dizendo
// "em construção" — nunca como link para uma tela vazia, que pareceria "consultei e não achei nada"
// (regra 7). Quando a 0217 chegar, vira `href` e sai de `emConstrucao`.

export type ChaveDeEtapa =
  | "visao" | "documentos" | "perimetro" | "revisao" | "perguntas"
  | "modelagem" | "apresentacao" | "membros" | "consultas";

export interface Etapa {
  chave: ChaveDeEtapa;
  rotulo: string;
  /** Ausente quando a etapa ainda não existe: não há para onde ir. */
  href?: string;
  ativa: boolean;
  emConstrucao: boolean;
}

// O primeiro segmento depois de `/casos/<id>/` decide a etapa. `documentos/[docId]` (a tela de um
// documento) e `adicionar` (o envio) são as duas faces de "Documentos".
const SEGMENTO_PARA_ETAPA: Record<string, ChaveDeEtapa> = {
  adicionar: "documentos",
  documentos: "documentos",
  perimetro: "perimetro",
  revisao: "revisao",
  perguntas: "perguntas",
  modelagem: "modelagem",
  apresentacao: "apresentacao",
  membros: "membros",
};

/** A etapa que a rota marca, ou `null` se o caminho não é do mandato `id` (ou é uma subrota sem etapa). */
export function etapaAtiva(caminho: string, id: string): ChaveDeEtapa | null {
  const base = `/casos/${id}`;
  if (caminho === base || caminho === `${base}/`) return "visao";
  if (!caminho.startsWith(`${base}/`)) return null;
  const segmento = caminho.slice(base.length + 1).split("/")[0];
  return SEGMENTO_PARA_ETAPA[segmento] ?? null;
}

export function etapasDoMandato(id: string, caminho: string, ehAdmin: boolean): Etapa[] {
  const atual = etapaAtiva(caminho, id);
  const e = (chave: ChaveDeEtapa, rotulo: string, href: string): Etapa =>
    ({ chave, rotulo, href, ativa: atual === chave, emConstrucao: false });
  const lista: Etapa[] = [
    e("visao", "Visão geral", `/casos/${id}`),
    e("documentos", "Documentos", `/casos/${id}/adicionar`),
    e("perimetro", "Perímetro", `/casos/${id}/perimetro`),
    e("revisao", "Revisão", `/casos/${id}/revisao`),
    e("perguntas", "Perguntas", `/casos/${id}/perguntas`),
    e("modelagem", "Modelagem", `/casos/${id}/modelagem`),
    e("apresentacao", "Apresentação", `/casos/${id}/apresentacao`),
  ];
  if (ehAdmin) lista.push(e("membros", "Membros", `/casos/${id}/membros`));
  lista.push({ chave: "consultas", rotulo: "Consultas externas", ativa: false, emConstrucao: true });
  return lista;
}
