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
  /** Identificador estável e ÚNICO do evento (`<origem>:<id>`): desempate da ordem e metade do cursor. */
  chave: string;
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
  // "Salva", não "preenchida": a tabela guarda só o ÚLTIMO SALVAMENTO de cada campo (a action regrava
  // autor e instante de todos os campos a cada salvamento), então o autor é quem salvou por último,
  // não quem escreveu o conteúdo. `apresentacao_preenchida` (nome antigo, da 0215 antes da correção) foi
  // REMOVIDO do mapa de propósito: nada o emite mais, e o rótulo antigo afirmava autoria do conteúdo.
  // Se alguma linha antiga ainda chegasse com ele, cairia em "Outros" com o nome cru (regra 1: aparece).
  apresentacao_salva: { rotulo: "Apresentação salva (último salvamento do campo)", categoria: "modelagem" },
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

function bandeira(referencia: unknown, nome: "autor_desconhecido" | "automatico"): boolean {
  return typeof referencia === "object" && referencia !== null
    && (referencia as Record<string, unknown>)[nome] === true;
}

/**
 * QUEM FEZ. A 0215 devolve o autor como foi gravado e NULL quando o ator é `sistema:*` ou `n8n*`
 * ("a palavra é da tela"). O NULL tem TRÊS significados, e o banco diz qual em `referencia`:
 *  - `autor_desconhecido = true` (documento_recebido): a tabela `documento` não guarda quem enviou —
 *    "não registrado"; escrever "Sistema" afirmaria que ninguém enviou. Sem a bandeira, o tipo
 *    `documento_recebido` continua valendo como rede (linha de função mais antiga ou `referencia` perdida).
 *  - `automatico = true` (extracao_aceita por auto-aceite): quem aceitou foi o ajuste de rigor do
 *    sistema, uma regra e não uma falha de registro. "Sistema" genérico esconderia que ninguém
 *    revisou aquela extração; o texto cita o nome que a própria tela já usa ("ajuste de rigor").
 *  - nenhum dos dois: o sistema agiu ("Sistema").
 * `portal:desconhecido` foi gravado quando a sessão não tinha e-mail; não é uma pessoa nomeada.
 * Autor gravado vence qualquer bandeira.
 */
export function textoDoAutor(tipo: string, autor: string | null, referencia?: unknown): string {
  if (autor === null || autor.trim() === "") {
    if (bandeira(referencia, "automatico")) return "Automático (ajuste de rigor do sistema, sem revisão de pessoa)";
    if (bandeira(referencia, "autor_desconhecido") || tipo === "documento_recebido") {
      return "Não registrado (quem enviou o documento não é guardado)";
    }
    return "Sistema";
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

// O cursor vem da URL (fronteira de confiança) e vai para `p_antes` e `p_antes_chave`: só o formato ISO
// que o próprio banco devolve em `em` passa; qualquer outra coisa é recusada, não "corrigida".
const ISO = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}(:?\d{2})?)$/;
export function cursorValido(antes: string | undefined): boolean {
  return antes !== undefined && ISO.test(antes) && !Number.isNaN(Date.parse(antes));
}

// `chave` = `<origem>:<id>`, mas parte dela vem de texto gravado (campo da apresentação, e-mail no
// vínculo), então o formato não é fechado: exige não vazia, sem caractere de controle e no máximo 300
// (maior chave medida na 0215: `vinculo:<epoch>:<e-mail>` e `apresentacao:<campo>`, bem abaixo disso).
export const TAMANHO_MAXIMO_DA_CHAVE = 300;
export function chaveDeCursorValida(chave: string | undefined): boolean {
  return chave !== undefined && chave.trim() !== "" && chave.length <= TAMANHO_MAXIMO_DA_CHAVE && !/[\u0000-\u001f\u007f]/.test(chave);
}

export type CursorDoHistorico =
  | { situacao: "inicio" }
  | { situacao: "pagina"; antes: string; chave: string }
  | { situacao: "recusado" };

/**
 * Lê o cursor composto da URL. Os DOIS ou nenhum: sem `chave` válida não se pagina só por `em` — o
 * empate de instante é rotina (a apresentação salva todos os campos com o mesmo `preenchido_em`) e a
 * página só por instante perderia o segundo evento do empate sem avisar. Um sem o outro é recusado.
 */
export function lerCursor(antes: string | undefined, chave: string | undefined): CursorDoHistorico {
  if (antes === undefined && chave === undefined) return { situacao: "inicio" };
  if (antes !== undefined && chave !== undefined && cursorValido(antes) && chaveDeCursorValida(chave)) {
    return { situacao: "pagina", antes, chave };
  }
  return { situacao: "recusado" };
}

/** O link de "Carregar mais antigos": `em` e `chave` da última linha MOSTRADA, `em` como TEXTO do banco. */
export function hrefDosMaisAntigos(casoId: string, ultima: Pick<EventoDoHistorico, "em" | "chave">): string {
  return `/casos/${casoId}/historico?antes=${encodeURIComponent(ultima.em)}&chave=${encodeURIComponent(ultima.chave)}`;
}
