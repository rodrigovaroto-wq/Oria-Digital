import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import type { Caso } from "@/lib/types";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";
import { humanizar } from "@/lib/rotulos";
import { FecharMandato } from "@/components/fechar-mandato";
import { ExcluirMandato } from "@/components/excluir-mandato";
import { mandatosMeus, resumoDeMembros, situacaoDeMembros, visaoDaLista } from "@/lib/membros";

// A LISTA COMPLETA DE MANDATOS — o destino do "Mandatos" da barra lateral.
//
// POR QUE ELA SAIU DE `/casos` (18/08). Ela ERA a home, e a home repetia inteira
// a lista que a barra lateral já dá em um clique. Duas telas para a mesma
// pergunta é uma tela a mais para manter e uma decisão a mais para quem abre o
// portal de manhã. Agora `/casos` é o PAINEL — o que precisa de você hoje — e
// esta lista mora em `/casos/todos`, que é onde a navegação leva.
//
// A barra lateral mostra os ATIVOS, para trocar de caso em um clique. Esta tela
// é a outra pergunta: **o que existe**, incluindo o que já saiu da mesa. Por
// isso ela traz o que a barra não cabe — a descrição, os dois status e as ações
// de fim de vida.
//
// E POR QUE NÃO HÁ MAIS BOTÃO DE "NOVO MANDATO" AQUI. Ele está na barra
// lateral, visível ao lado desta tela o tempo todo. Duas portas para a mesma
// ação, a meio palmo uma da outra, não facilitam nada — só obrigam a escolher.
// A regra que saiu disso vale para as duas telas novas: nenhuma função da barra
// se repete no conteúdo.
//
// A DESCRIÇÃO É DERIVADA, não digitada. Um campo livre a mais é um campo que
// ninguém preenche depois da segunda semana, e a linha ficaria vazia justamente
// nos mandatos antigos, que são os que precisam de contexto. Estes três fatos o
// sistema já sabe, e são o que alguém precisa para reconhecer um caso:
// **quantos documentos chegaram, quantas linhas foram extraídas e quantas
// pendências estão em aberto**.

export const dynamic = "force-dynamic";

function dataCurta(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "short", year: "numeric" });
}

export default async function CasosPage({
  searchParams,
}: {
  searchParams: Promise<{ visao?: string }>;
}) {
  const supabase = await createClient();
  const { visao: visaoPedida } = await searchParams;

  // DUAS VISÕES (27/10/2026, 0215/0216): "Meus mandatos" (onde sou membro) e "Todos" (só administrador,
  // com a contagem de membros e o mandato sem membro — que só o administrador enxerga). O parâmetro
  // `?visao=todos` de quem não é administrador é ignorado, e a aba nem aparece. A RLS da 0216 já limita a
  // consulta abaixo aos mandatos do usuário; o filtro por caso_membro cobre o administrador.
  const [adminRes, claimsRes] = await Promise.all([supabase.rpc("fn_eh_admin"), supabase.auth.getClaims()]);
  const ehAdmin = adminRes.data === true;
  const visao = visaoDaLista(visaoPedida, ehAdmin);
  const usuarioId = claimsRes.data?.claims?.sub as string | undefined;

  const { data: todosOsCasos, error } = await paginar<Caso>((de, ate) =>
    supabase
      .from("caso")
      .select("id, nome, produto, status, criado_em, fechado_em")
      .order("criado_em", { ascending: false })
      .order("id", { ascending: true })
      .range(de, ate),
  );

  // Leitura de caso_membro com erro = pertinência NÃO conferida (banco sem a 0215): não filtra e não
  // inventa contagem — a tela avisa, em vez de mostrar "0 membros" ou "meus" = "todos" calado.
  const meusRes = usuarioId
    ? await paginar<{ caso_id: string }>((de, ate) =>
        supabase.from("caso_membro").select("caso_id, usuario_id").eq("usuario_id", usuarioId)
          .order("caso_id", { ascending: true }).range(de, ate))
    : null;
  const meusIds = meusRes && !meusRes.error && !meusRes.truncado
    ? new Set(meusRes.data.map((l) => l.caso_id))
    : null;
  const casosMeus = mandatosMeus(todosOsCasos, meusIds);
  const casos = visao === "todos" ? todosOsCasos : casosMeus;

  const membrosRes = visao === "todos" && todosOsCasos.length
    ? await paginar<{ caso_id: string; usuario_id: string }>((de, ate) =>
        supabase.from("caso_membro").select("caso_id, usuario_id")
          .order("caso_id", { ascending: true }).order("usuario_id", { ascending: true }).range(de, ate))
    : null;
  const membros = visao === "todos"
    ? resumoDeMembros(membrosRes && !membrosRes.error && !membrosRes.truncado ? membrosRes.data : null)
    : null;

  // UMA consulta para todos os mandatos, não uma por linha: a lista com 30 casos
  // faria 90 idas ao banco, e a tela é a primeira que abre no dia.
  const ids = casos.map((c) => c.id);
  const [docsRes, pendRes] = ids.length
    ? await Promise.all([
        paginar<{ id: string; caso_id: string }>((de, ate) =>
          supabase.from("documento").select("id, caso_id").in("caso_id", ids)
            .order("id", { ascending: true }).range(de, ate)),
        paginar<{ id: string; caso_id: string; severidade: string; estado: string }>((de, ate) =>
          supabase
            .from("pendencia")
            .select("id, caso_id, severidade, estado")
            .in("caso_id", ids)
            .in("estado", ["aberta", "em_correcao_interna", "reenviada_ao_cliente"])
            .order("id", { ascending: true })
            .range(de, ate)),
      ])
    : [
        { data: [] as Array<{ id: string; caso_id: string }>, error: null, truncado: false },
        { data: [] as Array<{ id: string; caso_id: string; severidade: string; estado: string }>, error: null, truncado: false },
      ];

  const docsPorCaso = new Map<string, number>();
  for (const d of (docsRes.data as Array<{ caso_id: string }> | null) ?? []) {
    docsPorCaso.set(d.caso_id, (docsPorCaso.get(d.caso_id) ?? 0) + 1);
  }
  const pendPorCaso = new Map<string, { total: number; bloqueantes: number }>();
  for (const p of (pendRes.data as Array<{ caso_id: string; severidade: string }> | null) ?? []) {
    const atual = pendPorCaso.get(p.caso_id) ?? { total: 0, bloqueantes: 0 };
    atual.total += 1;
    if (p.severidade === "bloqueante") atual.bloqueantes += 1;
    pendPorCaso.set(p.caso_id, atual);
  }

  const ativos = casos.filter((c) => !c.fechado_em);
  const fechados = casos.filter((c) => c.fechado_em);

  const descricao = (caso: Caso): string => {
    const docs = docsPorCaso.get(caso.id) ?? 0;
    const pend = pendPorCaso.get(caso.id);
    const partes = [
      humanizar(caso.produto),
      docs === 0 ? "sem documentos" : `${docs} ${docs === 1 ? "documento" : "documentos"}`,
    ];
    if (pend?.total) {
      partes.push(
        pend.bloqueantes > 0
          ? `${pend.total} ${pend.total === 1 ? "pendência" : "pendências"} (${pend.bloqueantes} bloqueia${
              pend.bloqueantes === 1 ? "" : "m"
            })`
          : `${pend.total} ${pend.total === 1 ? "pendência" : "pendências"}`,
      );
    } else if (docs > 0) {
      partes.push("sem pendência");
    }
    if (dataCurta(caso.criado_em)) partes.push(`aberto em ${dataCurta(caso.criado_em)}`);
    return partes.join(" · ");
  };

  // SEM MEMBRO só se diz quando a contagem foi CONFERIDA e deu zero; sem conferência, a linha diz que
  // não foi conferido — nunca "0 membros" (regra 1). O mandato sem membro só o administrador vê.
  const chipDeMembros = (caso: Caso) => {
    if (!membros) return null;
    const { situacao, quantos } = situacaoDeMembros(membros, caso.id);
    if (situacao === "nao_conferido")
      return <span className="chip bg-alerta-100 text-alerta-800" title="A leitura de caso_membro não terminou; a contagem não é conhecida.">membros não conferidos</span>;
    if (situacao === "sem_membro")
      return <span className="chip bg-risco-100 text-risco-800" title="Ninguém trabalha neste mandato; só os administradores o enxergam.">sem membro</span>;
    return <span className="chip bg-tinta-100 text-tinta-600">{quantos} {quantos === 1 ? "membro" : "membros"}</span>;
  };
  const semMembro = (caso: Caso) => membros !== null && situacaoDeMembros(membros, caso.id).situacao === "sem_membro";

  const Linha = ({ caso }: { caso: Caso }) => {
    const fechado = Boolean(caso.fechado_em);
    return (
      <li className={`carta overflow-hidden ${fechado ? "opacity-75" : ""} ${
        semMembro(caso) ? "border-risco-300 ring-1 ring-risco-200" : ""
      }`}>
        <Link
          href={`/casos/${caso.id}`}
          className="flex items-start justify-between gap-4 px-4 py-3.5 transition-colors hover:bg-tinta-50"
        >
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-tinta-900">{caso.nome}</p>
            {/* MENOS DE UMA LINHA, e truncada quando não couber: a lista serve
                para RECONHECER o mandato, não para explicá-lo. */}
            <p className="mt-0.5 truncate text-xs text-tinta-500">{descricao(caso)}</p>
          </div>
          <div className="flex shrink-0 items-center gap-2">
            {/* DOIS RÓTULOS, e eles respondem perguntas diferentes: onde o
                mandato está no trabalho, e se ele ainda está na mesa. */}
            {chipDeMembros(caso)}
            <span className={`chip ${CASO_STATUS_COLOR[caso.status]}`}>
              {CASO_STATUS_LABEL[caso.status]}
            </span>
            <span
              className={`chip ${
                fechado ? "bg-tinta-200 text-tinta-600" : "bg-acento-50 text-acento-700"
              }`}
            >
              {fechado ? "Fechado" : "Ativo"}
            </span>
          </div>
        </Link>

        {/* AS AÇÕES DE FIM DE VIDA ficam no rodapé do item, separadas por uma
            linha: elas não competem com o clique que abre o mandato, e quem as
            procura sabe onde estão. */}
        <div className="flex items-center justify-between gap-3 border-t border-tinta-100 bg-tinta-50/60 px-4 py-2">
          <span className="truncate text-[11px] text-tinta-500">
            {fechado
              ? `Fechado${caso.motivo_fechamento ? ` — ${caso.motivo_fechamento}` : ""}. Nada foi apagado.`
              : "Fechar tira da mesa e preserva tudo; excluir apaga o mandato e o que veio dele."}
          </span>
          <div className="flex shrink-0 items-center gap-2">
            <FecharMandato casoId={caso.id} nome={caso.nome} fechado={fechado} />
            <ExcluirMandato casoId={caso.id} nome={caso.nome} />
          </div>
        </div>
      </li>
    );
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-tinta-900">Mandatos</h1>
          <p className="mt-0.5 text-sm text-tinta-500">
            {casos.length === 0
              ? "Nenhum mandato aberto."
              : `${ativos.length} ${ativos.length === 1 ? "ativo" : "ativos"}` +
                (fechados.length ? ` · ${fechados.length} fechado${fechados.length === 1 ? "" : "s"}` : "")}
          </p>
        </div>
      </div>

      {/* AS DUAS VISÕES. "Todos" só existe para administrador. */}
      <nav aria-label="Visão da lista" className="flex gap-1 border-b border-tinta-200">
        {([
          ["meus", "Meus mandatos", "/casos/todos", meusIds ? casosMeus.length : null],
          ...(ehAdmin ? [["todos", "Todos", "/casos/todos?visao=todos", todosOsCasos.length] as const] : []),
        ] as const).map(([chave, rotulo, href, n]) => (
          <Link key={chave} href={href} aria-current={visao === chave ? "page" : undefined}
                className={`-mb-px border-b-2 px-3 py-2 text-sm ${
                  visao === chave ? "border-acento-600 font-medium text-acento-700"
                                  : "border-transparent text-tinta-600 hover:text-tinta-900"}`}>
            {rotulo}{n !== null && <span className="ml-1.5 text-xs text-tinta-400">{n}</span>}
          </Link>
        ))}
      </nav>

      {visao === "meus" && meusIds === null && (
        <p className="rounded-lg border border-alerta-200 bg-alerta-50 p-3 text-sm text-alerta-900">
          Não foi possível conferir em quais mandatos você é membro; a lista abaixo é a que o banco devolveu, sem filtro.
        </p>
      )}
      {visao === "todos" && membros && membros.porCaso &&
        casos.filter((c) => semMembro(c)).length > 0 && (
        <p className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          <strong className="font-semibold">{casos.filter((c) => semMembro(c)).length}{" "}
          {casos.filter((c) => semMembro(c)).length === 1 ? "mandato sem membro" : "mandatos sem membro"}</strong>
          {" "}— só os administradores os enxergam. Abra o mandato e use a etapa Membros.
        </p>
      )}

      {error && (
        <p className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          Não foi possível carregar os mandatos: {error.message}
        </p>
      )}

      {!error && casos.length === 0 ? (
        <div className="carta flex flex-col items-center gap-3 px-6 py-12 text-center">
          <p className="text-sm font-medium text-tinta-900">Comece subindo os arquivos de um mandato</p>
          <p className="max-w-md text-sm text-tinta-500">
            Abra o primeiro pelo <strong className="font-medium text-tinta-700">Novo mandato</strong>,
            no menu à esquerda. O sistema classifica cada documento, extrai as linhas financeiras e
            aponta o que ficou faltando ou divergente. Você confere e aprova.
          </p>
        </div>
      ) : (
        <>
          <ul className="space-y-3">
            {ativos.map((caso) => (
              <Linha key={caso.id} caso={caso} />
            ))}
          </ul>

          {fechados.length > 0 && (
            <section className="pt-2">
              <div className="mb-2 flex items-baseline justify-between gap-3">
                <h2 className="titulo-secao">Fechados</h2>
                <p className="text-xs text-tinta-500">
                  saíram da mesa — o dado continua aqui, e reabrir é um clique
                </p>
              </div>
              <ul className="space-y-3">
                {fechados.map((caso) => (
                  <Linha key={caso.id} caso={caso} />
                ))}
              </ul>
            </section>
          )}
        </>
      )}
    </div>
  );
}
