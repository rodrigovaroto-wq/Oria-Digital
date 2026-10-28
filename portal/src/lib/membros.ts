// QUEM TRABALHA NO MANDATO — a parte da tela de membros e da lista de mandatos que não é React.
// Fica aqui para a suíte (`verificar-navegacao.mts`) afirmar o comportamento sem subir o Next.
//
// FONTE DAS PERGUNTAS: migrations 0215 (caso_membro, administrador, fn_membro_adicionar/_remover) e
// 0216 (RLS por mandato). O `authenticated` NÃO lê `auth.users`: o banco só entrega o id do usuário.
// Por isso a tela mostra o id curto e diz que falta `fn_membros_do_caso(caso)` — ver FALTA_EMAIL.

export const FALTA_EMAIL =
  "O banco ainda não devolve o e-mail dos membros: falta a função fn_membros_do_caso(caso) " +
  "(SECURITY DEFINER, só para membro ou administrador, devolvendo o e-mail). Até lá a lista mostra o " +
  "início do identificador do usuário, e adicionar exige o identificador completo, não o e-mail.";

export interface MembroLinha { usuario_id: string; desde: string | null; por: string }

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const ehUuid = (s: string) => UUID.test(s);
export const idCurto = (uuid: string) => uuid.slice(0, 8);

/** `por` diz de onde veio a linha (0215). Valor desconhecido aparece CRU — nunca some nem vira "criador". */
export function origemDoMembro(por: string): string {
  if (por === "criador") return "criou o mandato";
  if (por === "migracao:0215") return "migração 0215 (acesso inicial de todos)";
  if (por.startsWith("usuario:")) {
    const quem = por.slice("usuario:".length);
    return `atribuído por ${ehUuid(quem) ? idCurto(quem) : quem}`;
  }
  return por;
}

export type OperacaoDeMembro = "adicionar" | "remover";

/** A recusa do banco em português. 42501 é "só o administrador": a frase diz o que aconteceu e o EFEITO. */
export function fraseDoErroDeMembro(
  erro: { code?: string | null; message?: string | null },
  operacao: OperacaoDeMembro,
): string {
  const verbo = operacao === "adicionar" ? "atribuir" : "retirar";
  if (erro.code === "42501") {
    return `Só o administrador pode ${verbo} membros de um mandato, e a sua conta não é administradora. Nada foi alterado.`;
  }
  if (erro.code === "23503") return "Usuário ou mandato não encontrado no banco. Nada foi alterado.";
  return `Não foi possível ${operacao === "adicionar" ? "adicionar" : "remover"} o membro: ${erro.message ?? "erro sem mensagem"}. Nada foi alterado.`;
}

export type ResultadoMembro = { tom: "ok" | "erro"; texto: string } | null;

// O cliente do Supabase reduzido ao que a operação usa: a suíte passa um falso, a action passa o real.
export interface ClienteRpc {
  rpc(fn: string, args: Record<string, unknown>): PromiseLike<{
    data: unknown; error: { code?: string | null; message?: string | null } | null;
  }>;
}

export async function executarMembro(
  supabase: ClienteRpc, operacao: OperacaoDeMembro, casoId: string, form: FormData,
): Promise<ResultadoMembro> {
  const bruto = typeof form.get("usuario") === "string" ? (form.get("usuario") as string).trim() : "";
  if (!bruto) return { tom: "erro", texto: "Informe o identificador do usuário." };
  if (bruto.includes("@")) {
    return {
      tom: "erro",
      texto: "Adicionar por e-mail ainda não é possível: o banco não resolve e-mail em usuário " +
        "(falta fn_membros_do_caso). Informe o identificador (uuid) do usuário. Nada foi alterado.",
    };
  }
  if (!ehUuid(bruto)) return { tom: "erro", texto: "Identificador inválido: esperado um uuid. Nada foi alterado." };
  const { data, error } = await supabase.rpc(
    operacao === "adicionar" ? "fn_membro_adicionar" : "fn_membro_remover",
    { p_caso: casoId, p_usuario: bruto },
  );
  if (error) return { tom: "erro", texto: fraseDoErroDeMembro(error, operacao) };
  // As duas funções devolvem boolean: false = nada mudou (já era / não era membro). Dizer "feito" seria falso.
  if (data !== true) {
    return {
      tom: "ok",
      texto: operacao === "adicionar" ? "Esse usuário já era membro; nada mudou." : "Esse usuário não era membro; nada mudou.",
    };
  }
  return { tom: "ok", texto: operacao === "adicionar" ? "Membro adicionado." : "Membro removido." };
}

// ---- a lista de mandatos: meus × todos ----------------------------------------------------------

export type VisaoDaLista = "meus" | "todos";

/** "Todos" só existe para administrador: o parâmetro de um não administrador é ignorado, não obedecido. */
export function visaoDaLista(parametro: string | undefined, ehAdmin: boolean): VisaoDaLista {
  return ehAdmin && parametro === "todos" ? "todos" : "meus";
}

/** Os mandatos em que o usuário é membro. `meusIds` nulo = a leitura de caso_membro falhou: não filtra (e a tela avisa). */
export function mandatosMeus<T extends { id: string }>(casos: T[], meusIds: Set<string> | null): T[] {
  return meusIds ? casos.filter((c) => meusIds.has(c.id)) : casos;
}

export interface ResumoDeMembros {
  /** Quantidade por caso. `null` = não foi possível conferir (banco sem 0215, erro de leitura): NÃO é zero. */
  porCaso: Map<string, number> | null;
}

export function resumoDeMembros(linhas: Array<{ caso_id: string }> | null): ResumoDeMembros {
  if (!linhas) return { porCaso: null };
  const porCaso = new Map<string, number>();
  for (const l of linhas) porCaso.set(l.caso_id, (porCaso.get(l.caso_id) ?? 0) + 1);
  return { porCaso };
}

/** `"sem_membro"` só quando a contagem foi conferida e deu zero; sem conferência, `"nao_conferido"`. */
export function situacaoDeMembros(resumo: ResumoDeMembros, casoId: string): { situacao: "sem_membro" | "com_membros" | "nao_conferido"; quantos: number | null } {
  if (!resumo.porCaso) return { situacao: "nao_conferido", quantos: null };
  const n = resumo.porCaso.get(casoId) ?? 0;
  return { situacao: n === 0 ? "sem_membro" : "com_membros", quantos: n };
}
