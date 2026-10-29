// A EQUIPE, como a tela a enxerga: todos os usuários do Auth, quem tem papel, em quais mandatos está
// alocado, e quem ainda pode ser alocado onde. Lógica pura sobre o que o banco devolveu.
//
// DE ONDE VEM O E-MAIL: `auth.users` não é legível pelo PostgREST, então a fonte é
// `fn_membros_da_equipe()` (0216, só Sócio): (usuario_id, email, papel, criado_em, alocacoes[]) de TODOS
// os usuários, inclusive os sem papel — os que esperam liberação. Sem essa função (banco sem a 0216
// atual: 42883 do Postgres, PGRST202 do PostgREST) a tela cai no MODO ANTIGO, lendo `membro` e
// `alocacao`: só quem já tem papel, pelo código curto, e só o e-mail de quem está logado. O modo antigo
// é DITO na tela (`MENSAGEM_FALTA_ATUALIZAR_O_BANCO`); chutar um nome a partir do código seria
// apresentar ausência como dado (regra 1). Falha de leitura NUNCA vira "equipe vazia".
import { PAPEIS, ehPapel, type Papel } from "./acesso.ts";
import { funcaoAusente } from "./historico-do-mandato.ts";

export type Membro = { usuario_id: string; papel: Papel };
export type Alocacao = { caso_id: string; usuario_id: string };
/** Uma linha de `fn_membros_da_equipe`. `papel` nulo = existe no Auth e não tem acesso; `email` nulo = o Auth não tem e-mail (login por telefone). */
export type MembroDaEquipe = {
  usuario_id: string;
  email: string | null;
  papel: Papel | null;
  criado_em: string | null;
  alocacoes: string[];
};
export type CasoDaEquipe = { id: string; nome: string; fechado_em: string | null };
export type Eu = { id: string; email: string | null } | null;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** A fronteira de confiança: o que chega de um formulário vira `uuid` do Postgres só se tiver a forma dele. */
export function ehUuid(v: unknown): v is string {
  return typeof v === "string" && UUID.test(v.trim());
}

export function idCurto(id: string): string {
  return id.slice(0, 8);
}

export const MENSAGEM_FALTA_ATUALIZAR_O_BANCO =
  "Falta uma atualização do banco (a migration 0216 atual, que cria fn_membros_da_equipe). Até ela ser aplicada, esta tela mostra só quem já tem papel, pelo código do usuário — o e-mail só aparece para o seu próprio — e não lista quem ainda espera liberação.";

export type LeituraDaEquipe =
  | { estado: "ok"; membros: MembroDaEquipe[]; ignorados: number }
  /** A função não existe neste banco: a tela segue no modo antigo e diz por quê. */
  | { estado: "ausente" }
  | { estado: "falha"; code: string | null; message: string };

/**
 * A resposta de `fn_membros_da_equipe` em três estados distintos. Linha que não tem a forma esperada
 * (uuid inválido, papel fora do vocabulário) é CONTADA em `ignorados`, não descartada em silêncio: a
 * tela avisa que a lista pode estar incompleta. Resposta que não é lista, sem erro, é falha — nunca
 * "equipe vazia".
 */
export function interpretarMembros(
  res: { data: unknown; error: { code?: string | null; message?: string | null } | null },
): LeituraDaEquipe {
  if (res.error) {
    if (funcaoAusente(res.error)) return { estado: "ausente" };
    return { estado: "falha", code: res.error.code ?? null, message: res.error.message ?? "erro sem mensagem" };
  }
  if (!Array.isArray(res.data)) {
    return { estado: "falha", code: null, message: "o banco não devolveu uma lista de membros" };
  }
  const membros: MembroDaEquipe[] = [];
  let ignorados = 0;
  for (const l of res.data as Array<Record<string, unknown>>) {
    const papel = l?.papel ?? null;
    if (!ehUuid(l?.usuario_id) || (papel !== null && !ehPapel(papel))) { ignorados += 1; continue; }
    membros.push({
      usuario_id: l.usuario_id,
      email: typeof l.email === "string" && l.email.trim() !== "" ? l.email : null,
      papel: papel as Papel | null,
      criado_em: typeof l.criado_em === "string" ? l.criado_em : null,
      alocacoes: Array.isArray(l.alocacoes) ? l.alocacoes.filter((x): x is string => typeof x === "string") : [],
    });
  }
  return { estado: "ok", membros, ignorados };
}

/**
 * O MODO ANTIGO como `MembroDaEquipe`, para a tela ter um só caminho. Sem e-mail (só o do usuário logado,
 * que `pessoaDoUsuario` completa). Quem tem alocação e não tem papel entra com `papel: null` — é o que
 * `equipeDoMandato` conta como "alocação sem papel".
 */
export function membrosDoModoAntigo(membros: Membro[], alocacoes: Alocacao[]): MembroDaEquipe[] {
  const ids = new Set([...membros.map((m) => m.usuario_id), ...alocacoes.map((a) => a.usuario_id)]);
  const papelDe = new Map(membros.map((m) => [m.usuario_id, m.papel] as const));
  return [...ids].map((id) => ({
    usuario_id: id,
    email: null,
    papel: papelDe.get(id) ?? null,
    criado_em: null,
    alocacoes: alocacoes.filter((a) => a.usuario_id === id).map((a) => a.caso_id),
  }));
}

/** O texto de uma falha de leitura da equipe: o motivo humano em cima, o técnico em `DetalhesTecnicos`. */
export function textoDaFalhaDaEquipe(code: string | null): string {
  if (code === "42501") return "Ver a equipe é reservado a Sócio, e o banco não reconheceu o seu papel como Sócio. Peça a um Sócio para conferir.";
  return "Não foi possível ler a equipe agora, então esta tela não afirma quem tem acesso. Recarregue a página; se continuar, avise o administrador do sistema.";
}

export type Pessoa = { rotulo: string; voce: boolean; temEmail: boolean };

/** O e-mail do banco, ou — no modo antigo — o de quem está logado; sem nenhum dos dois, o código curto (e a tela diz por quê). */
export function pessoaDoUsuario(id: string, eu: Eu, email: string | null = null): Pessoa {
  const voce = !!eu && eu.id.toLowerCase() === id.toLowerCase();
  const mail = email ?? (voce ? eu?.email ?? null : null);
  return mail
    ? { rotulo: mail, voce, temEmail: true }
    : { rotulo: `usuário ${idCurto(id)}`, voce, temEmail: false };
}

export type LinhaDaEquipe = {
  usuario_id: string;
  papel: Papel;
  pessoa: Pessoa;
  /** Sócio não tem alocação: vê todos. */
  veTodos: boolean;
  alocados: CasoDaEquipe[];
  /** Mandatos em que ele ainda pode ser alocado (vazio para o Sócio). */
  alocaveis: CasoDaEquipe[];
  /** Alocações cujo mandato não veio na leitura — contadas, não escondidas. */
  alocadosNaoLidos: number;
  /** O banco recusa tirar o último Sócio (trg_membro_ultimo_socio); a tela avisa antes do clique. */
  unicoSocio: boolean;
};

const ORDEM_DO_PAPEL = new Map(PAPEIS.map((p, i) => [p, i] as const));

function porNome(a: CasoDaEquipe, b: CasoDaEquipe): number {
  return a.nome.localeCompare(b.nome, "pt-BR");
}

/** Quem TEM papel. Quem não tem vai para `aguardandoLiberacao`. */
export function linhasDaEquipe(membros: MembroDaEquipe[], casos: CasoDaEquipe[], eu: Eu): LinhaDaEquipe[] {
  const casoPorId = new Map(casos.map((c) => [c.id, c] as const));
  const socios = membros.filter((m) => m.papel === "socio").length;
  return membros
    .flatMap((m): LinhaDaEquipe[] => {
      if (m.papel === null) return [];
      const alocadosIds = new Set(m.alocacoes);
      const alocados = [...alocadosIds].flatMap((id) => {
        const c = casoPorId.get(id);
        return c ? [c] : [];
      }).sort(porNome);
      const veTodos = m.papel === "socio";
      return [{
        usuario_id: m.usuario_id,
        papel: m.papel,
        pessoa: pessoaDoUsuario(m.usuario_id, eu, m.email),
        veTodos,
        alocados,
        alocaveis: veTodos ? [] : casos.filter((c) => !alocadosIds.has(c.id)).sort(porNome),
        alocadosNaoLidos: alocadosIds.size - alocados.length,
        unicoSocio: m.papel === "socio" && socios === 1,
      }];
    })
    .sort((a, b) =>
      (ORDEM_DO_PAPEL.get(a.papel) ?? 9) - (ORDEM_DO_PAPEL.get(b.papel) ?? 9)
      || Number(b.pessoa.voce) - Number(a.pessoa.voce)
      || a.pessoa.rotulo.localeCompare(b.pessoa.rotulo, "pt-BR")
      || a.usuario_id.localeCompare(b.usuario_id));
}

export type PessoaAguardando = { usuario_id: string; pessoa: Pessoa; criado_em: string | null; alocacoesGuardadas: number };

/** Existem no Auth e não têm papel: não veem nada até um Sócio liberar. Mais recentes primeiro (quem acabou de entrar). */
export function aguardandoLiberacao(membros: MembroDaEquipe[], eu: Eu): PessoaAguardando[] {
  return membros
    .filter((m) => m.papel === null)
    .map((m) => ({
      usuario_id: m.usuario_id,
      pessoa: pessoaDoUsuario(m.usuario_id, eu, m.email),
      criado_em: m.criado_em,
      alocacoesGuardadas: m.alocacoes.length,
    }))
    .sort((a, b) => (b.criado_em ?? "").localeCompare(a.criado_em ?? "")
      || a.pessoa.rotulo.localeCompare(b.pessoa.rotulo, "pt-BR"));
}

export type EquipeDoMandato = {
  /** Analista e Leitura alocados neste mandato (Sócio vê todos e não entra aqui). */
  alocados: Array<{ usuario_id: string; papel: Papel; pessoa: Pessoa }>;
  /** Quem tem papel de Analista ou Leitura e ainda não está alocado. */
  alocaveis: Array<{ usuario_id: string; papel: Papel; pessoa: Pessoa }>;
  /** Alocações de usuário sem papel hoje: não valem (a 0216 ignora alocação de quem perdeu o papel). */
  semPapel: number;
  socios: number;
};

export function equipeDoMandato(membros: MembroDaEquipe[], casoId: string, eu: Eu): EquipeDoMandato {
  const dePessoa = (m: MembroDaEquipe & { papel: Papel }) =>
    ({ usuario_id: m.usuario_id, papel: m.papel, pessoa: pessoaDoUsuario(m.usuario_id, eu, m.email) });
  const ordenar = <T extends { papel: Papel; pessoa: Pessoa; usuario_id: string }>(l: T[]) =>
    l.sort((a, b) => (ORDEM_DO_PAPEL.get(a.papel) ?? 9) - (ORDEM_DO_PAPEL.get(b.papel) ?? 9)
      || a.pessoa.rotulo.localeCompare(b.pessoa.rotulo, "pt-BR") || a.usuario_id.localeCompare(b.usuario_id));
  const trabalham = membros.filter((m): m is MembroDaEquipe & { papel: Papel } => m.papel !== null && m.papel !== "socio");
  const aqui = (m: MembroDaEquipe) => m.alocacoes.includes(casoId);
  return {
    alocados: ordenar(trabalham.filter(aqui).map(dePessoa)),
    alocaveis: ordenar(trabalham.filter((m) => !aqui(m)).map(dePessoa)),
    semPapel: membros.filter((m) => m.papel === null && aqui(m)).length,
    socios: membros.filter((m) => m.papel === "socio").length,
  };
}
