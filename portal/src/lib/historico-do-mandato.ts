// O HISTÓRICO DO MANDATO, dito para quem lê (migration 0215, `fn_historico_do_caso`).
//
// A função devolve `tipo` estável, `autor` e `em`; tudo o que é PALAVRA da tela mora aqui,
// porque o cabeçalho da 0215 deixa isso explícito: "a palavra é da tela, o banco só diz que
// não foi pessoa". Lógica pura, sem React nem rede, para a suíte medir.
//
// TIPO DESCONHECIDO NUNCA SOME. A função ganha tipos com o tempo (a própria 0215 diz que passará a
// mostrar exportações no dia em que houver log); um tipo que este mapa não conhece aparece com o
// nome cru e na categoria "Outros", em vez de ser filtrado ou descartado — sumir seria apresentar
// ausência como "não aconteceu" (regra 1).

export interface EventoDoHistorico {
  em: string;
  tipo: string;
  autor: string | null;
  resumo: string;
  documento_id: string | null;
  referencia: unknown;
}

export type CategoriaDoHistorico =
  | "documentos" | "pendencias" | "perguntas" | "modelagem" | "mandato" | "grupo" | "outros";

export const CATEGORIAS_DO_HISTORICO: ReadonlyArray<{ id: CategoriaDoHistorico; rotulo: string }> = [
  { id: "documentos", rotulo: "Documentos" },
  { id: "pendencias", rotulo: "Pendências" },
  { id: "perguntas", rotulo: "Perguntas" },
  { id: "modelagem", rotulo: "Premissas e modelagem" },
  { id: "mandato", rotulo: "Mandato" },
  { id: "grupo", rotulo: "Grupo econômico" },
  { id: "outros", rotulo: "Outros" },
];

// Os tipos que a 0215 emite (conferido contra o texto da migration, não de memória).
const TIPOS: Record<string, { rotulo: string; categoria: CategoriaDoHistorico }> = {
  documento_recebido: { rotulo: "Documento recebido", categoria: "documentos" },
  extracao_aceita: { rotulo: "Extração aceita", categoria: "documentos" },
  documento_revisado: { rotulo: "Documento revisado", categoria: "documentos" },
  transcricao_humana: { rotulo: "Transcrição humana", categoria: "documentos" },
  classe_corrigida: { rotulo: "Classe contábil corrigida", categoria: "documentos" },
  pendencia_decidida: { rotulo: "Pendência decidida", categoria: "pendencias" },
  pergunta_enviada: { rotulo: "Pergunta enviada ao cliente", categoria: "perguntas" },
  pergunta_descartada: { rotulo: "Pergunta descartada", categoria: "perguntas" },
  premissa_ativada: { rotulo: "Premissa ativada", categoria: "modelagem" },
  premissa_removida: { rotulo: "Premissa removida", categoria: "modelagem" },
  premissa_aplicada_em_lote: { rotulo: "Premissa aplicada em lote", categoria: "modelagem" },
  premissa_vinculada_a_linha: { rotulo: "Premissa vinculada a linhas", categoria: "modelagem" },
  modelagem_definida: { rotulo: "Modelagem definida", categoria: "modelagem" },
  apresentacao_preenchida: { rotulo: "Apresentação preenchida", categoria: "modelagem" },
  caso_criado: { rotulo: "Mandato criado", categoria: "mandato" },
  caso_aprovado: { rotulo: "Mandato aprovado", categoria: "mandato" },
  caso_fechado: { rotulo: "Mandato fechado", categoria: "mandato" },
  caso_reaberto: { rotulo: "Mandato reaberto", categoria: "mandato" },
  reconferir_caso: { rotulo: "Mandato reconferido", categoria: "mandato" },
  caso_reconferido: { rotulo: "Mandato reconferido", categoria: "mandato" },
  perimetro_alterado: { rotulo: "Grupo econômico alterado", categoria: "grupo" },
};

/** Rótulo humano; tipo que o mapa não conhece volta CRU (nunca vazio, nunca omitido). */
export function rotuloDoTipo(tipo: string): string {
  return TIPOS[tipo]?.rotulo ?? tipo;
}

export function categoriaDoTipo(tipo: string): CategoriaDoHistorico {
  return TIPOS[tipo]?.categoria ?? "outros";
}

/**
 * QUEM FEZ. A 0215 devolve o autor como foi gravado e NULL quando o ator é `sistema:*` ou `n8n*`
 * ("a palavra é da tela"). Duas exceções que a tela precisa dizer com verdade:
 *  - `documento_recebido` com NULL: quem recebe é o n8n e a tabela `documento` não guarda quem
 *    enviou — NULL aqui é "não registrado", e escrever "Sistema" afirmaria que ninguém enviou.
 *  - `portal:desconhecido`: foi gravado quando a sessão não tinha e-mail; não é uma pessoa nomeada.
 */
export function textoDoAutor(tipo: string, autor: string | null): string {
  if (autor === null || autor.trim() === "") {
    return tipo === "documento_recebido" ? "Não registrado (quem enviou o documento não é guardado)" : "Sistema";
  }
  if (autor === "portal:desconhecido") return "Não identificado (sessão sem e-mail)";
  return autor;
}

const FUSO = "America/Sao_Paulo";

// `en-CA` formata como AAAA-MM-DD: serve de chave de dia ordenável, no fuso do analista.
const CHAVE_DIA = new Intl.DateTimeFormat("en-CA", { timeZone: FUSO, year: "numeric", month: "2-digit", day: "2-digit" });
const HORA = new Intl.DateTimeFormat("pt-BR", { timeZone: FUSO, hour: "2-digit", minute: "2-digit" });
const DIA_POR_EXTENSO = new Intl.DateTimeFormat("pt-BR", {
  timeZone: FUSO, weekday: "long", day: "numeric", month: "long", year: "numeric",
});

/** O dia do evento NO FUSO DE SÃO PAULO (22h do dia 27 em SP já é dia 28 em UTC). */
export function chaveDoDia(iso: string): string {
  return CHAVE_DIA.format(new Date(iso));
}

export function horaDoEvento(iso: string): string {
  return HORA.format(new Date(iso));
}

export interface DiaDoHistorico<T extends { em: string }> {
  chave: string;
  rotulo: string;
  eventos: T[];
}

/** Agrupa por dia preservando a ordem recebida (a função já entrega do mais novo ao mais velho). */
export function agruparPorDia<T extends { em: string }>(eventos: readonly T[]): DiaDoHistorico<T>[] {
  const dias: DiaDoHistorico<T>[] = [];
  for (const e of eventos) {
    const chave = chaveDoDia(e.em);
    const ultimo = dias[dias.length - 1];
    if (ultimo?.chave === chave) ultimo.eventos.push(e);
    else dias.push({ chave, rotulo: DIA_POR_EXTENSO.format(new Date(e.em)), eventos: [e] });
  }
  return dias;
}

/** Função ausente no banco (a 0215 não aplicada): 42883 do Postgres ou PGRST202 do PostgREST. */
export function funcaoAusente(erro: { code?: string | null } | null | undefined): boolean {
  return erro?.code === "42883" || erro?.code === "PGRST202";
}

// O cursor vem da URL (fronteira de confiança) e vai para `p_antes`: só o formato ISO que o
// próprio banco devolve em `em` passa; qualquer outra coisa é recusada, não "corrigida".
const ISO = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}(:?\d{2})?)$/;
export function cursorValido(antes: string | undefined): boolean {
  return antes !== undefined && ISO.test(antes) && !Number.isNaN(Date.parse(antes));
}
