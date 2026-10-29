// A EQUIPE, como a tela a enxerga: quem tem papel, em quais mandatos está alocado, e quem ainda
// pode ser alocado onde. Lógica pura sobre as linhas que `membro`, `alocacao` e `caso` devolveram —
// a RLS decide o que cada pessoa lê, e só o Sócio lê as linhas dos outros (membro_read /
// alocacao_read: "cada um lê o próprio; Sócio lê todos").
//
// O QUE ESTA TELA NÃO SABE: o e-MAIL de ninguém além do de quem está logado. `auth.users` não é
// legível pelo PostgREST e a 0216 não expõe e-mail por função nem por visão (conferido em
// 29/10/2026: `grep -n email Supabase/migrations/0216*.sql` só acha o comentário do bootstrap). A
// tela mostra o código curto do usuário e DIZ que falta `fn_membros_da_equipe`; chutar um nome
// a partir do código seria apresentar ausência como dado (regra 1). Quem existe no Auth e ainda não
// tem papel também não aparece — não há linha em `membro` para ler.
import { PAPEIS, type Papel } from "./acesso.ts";

export type Membro = { usuario_id: string; papel: Papel };
export type Alocacao = { caso_id: string; usuario_id: string };
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

export type Pessoa = { rotulo: string; voce: boolean; temEmail: boolean };

/** Só o e-mail de quem está logado é conhecido; os demais aparecem pelo código curto, e a tela diz por quê. */
export function pessoaDoUsuario(id: string, eu: Eu): Pessoa {
  if (eu && eu.id.toLowerCase() === id.toLowerCase()) {
    return eu.email
      ? { rotulo: eu.email, voce: true, temEmail: true }
      : { rotulo: `usuário ${idCurto(id)}`, voce: true, temEmail: false };
  }
  return { rotulo: `usuário ${idCurto(id)}`, voce: false, temEmail: false };
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

export function linhasDaEquipe(
  membros: Membro[], alocacoes: Alocacao[], casos: CasoDaEquipe[], eu: Eu,
): LinhaDaEquipe[] {
  const casoPorId = new Map(casos.map((c) => [c.id, c] as const));
  const socios = membros.filter((m) => m.papel === "socio").length;
  return membros
    .map((m): LinhaDaEquipe => {
      const meus = alocacoes.filter((a) => a.usuario_id === m.usuario_id);
      const alocadosIds = new Set(meus.map((a) => a.caso_id));
      const alocados = meus.flatMap((a) => {
        const c = casoPorId.get(a.caso_id);
        return c ? [c] : [];
      }).sort(porNome);
      const veTodos = m.papel === "socio";
      return {
        usuario_id: m.usuario_id,
        papel: m.papel,
        pessoa: pessoaDoUsuario(m.usuario_id, eu),
        veTodos,
        alocados,
        alocaveis: veTodos ? [] : casos.filter((c) => !alocadosIds.has(c.id)).sort(porNome),
        alocadosNaoLidos: meus.length - alocados.length,
        unicoSocio: m.papel === "socio" && socios === 1,
      };
    })
    .sort((a, b) =>
      (ORDEM_DO_PAPEL.get(a.papel) ?? 9) - (ORDEM_DO_PAPEL.get(b.papel) ?? 9)
      || Number(b.pessoa.voce) - Number(a.pessoa.voce)
      || a.usuario_id.localeCompare(b.usuario_id));
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

export function equipeDoMandato(
  membros: Membro[], alocacoesDoMandato: Alocacao[], eu: Eu,
): EquipeDoMandato {
  const papelPorUsuario = new Map(membros.map((m) => [m.usuario_id, m.papel] as const));
  const alocadosIds = new Set(alocacoesDoMandato.map((a) => a.usuario_id));
  const dePessoa = (m: Membro) => ({ usuario_id: m.usuario_id, papel: m.papel, pessoa: pessoaDoUsuario(m.usuario_id, eu) });
  const ordenar = <T extends { papel: Papel; usuario_id: string }>(l: T[]) =>
    l.sort((a, b) => (ORDEM_DO_PAPEL.get(a.papel) ?? 9) - (ORDEM_DO_PAPEL.get(b.papel) ?? 9) || a.usuario_id.localeCompare(b.usuario_id));
  const trabalham = membros.filter((m) => m.papel !== "socio");
  return {
    alocados: ordenar(trabalham.filter((m) => alocadosIds.has(m.usuario_id)).map(dePessoa)),
    alocaveis: ordenar(trabalham.filter((m) => !alocadosIds.has(m.usuario_id)).map(dePessoa)),
    semPapel: alocacoesDoMandato.filter((a) => !papelPorUsuario.has(a.usuario_id)).length,
    socios: membros.filter((m) => m.papel === "socio").length,
  };
}
