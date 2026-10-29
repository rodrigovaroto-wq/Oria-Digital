import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { lerPermissoes } from "@/lib/supabase/acesso";
import { escopoDaLista, textoDeNenhumMandato } from "@/lib/acesso";
import { paginar } from "@/lib/supabase/paginar";
import type { Caso } from "@/lib/types";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";
import { humanizar } from "@/lib/rotulos";
import { ETAPAS_DO_MANDATO, etapaDoMandato } from "@/lib/etapa-do-mandato";
import { padraoDeBusca } from "@/lib/painel";
import { MenuDoMandato } from "../[id]/menu-do-mandato";

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
// FORMATO (REDESENHO_DO_PORTAL item 12): TABELA, com abas Ativos/Fechados e busca
// por nome (`?aba=`, `?q=`, tudo no servidor). Colunas: Mandato, Produto, Etapa,
// Pendências, Aberto em e o menu "⋯". NÃO há coluna "Responsável": `caso` não
// guarda responsável, e coluna inventada seria ausência apresentada como dado.
// As contagens das abas são sobre o resultado da busca (a lista e o número saem
// do mesmo conjunto). O que a tabela não cabe — quantos documentos chegaram —
// continua na tela do mandato.
//
// A DESCRIÇÃO ERA DERIVADA, não digitada. Um campo livre a mais é um campo que
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
  searchParams: Promise<{ aba?: string | string[]; q?: string | string[] }>;
}) {
  const { aba: abaBruta, q: qBruto } = await searchParams;
  const aba = (Array.isArray(abaBruta) ? abaBruta[0] : abaBruta) === "fechados" ? "fechados" : "ativos";
  const padrao = padraoDeBusca(qBruto);
  const termo = padrao === null ? "" : (Array.isArray(qBruto) ? qBruto[0] : qBruto)!.trim().slice(0, 80);

  const supabase = await createClient();
  // O papel (memoizado na requisição) decide o que "nenhum mandato" quer dizer: a RLS devolve VAZIO,
  // não erro, para quem não está alocado — e só o Sócio vê a mesa inteira.
  const perm = await lerPermissoes();
  const soAlocados = escopoDaLista(perm.papel) === "alocados";

  const { data, error } = await paginar<Caso>((de, ate) => {
    let q = supabase
      .from("caso")
      .select("id, nome, produto, status, criado_em, fechado_em, motivo_fechamento");
    if (padrao) q = q.ilike("nome", padrao);
    return q
      .order("criado_em", { ascending: false })
      .order("id", { ascending: true })
      .range(de, ate);
  });

  const casos = data;

  // UMA consulta de pendências para todos os mandatos, não uma por linha. A
  // contagem de documentos saiu: a tabela não a mostra mais, e era uma consulta
  // inteira só para uma frase.
  const ids = casos.map((c) => c.id);
  const pendRes = ids.length
    ? await paginar<{ id: string; caso_id: string; severidade: string }>((de, ate) =>
        supabase
          .from("pendencia")
          .select("id, caso_id, severidade")
          .in("caso_id", ids)
          .in("estado", ["aberta", "em_correcao_interna", "reenviada_ao_cliente"])
          .order("id", { ascending: true })
          .range(de, ate))
    : { data: [] as Array<{ id: string; caso_id: string; severidade: string }>, error: null, truncado: false };

  const pendPorCaso = new Map<string, { total: number; bloqueantes: number }>();
  for (const p of pendRes.data) {
    const atual = pendPorCaso.get(p.caso_id) ?? { total: 0, bloqueantes: 0 };
    atual.total += 1;
    if (p.severidade === "bloqueante") atual.bloqueantes += 1;
    pendPorCaso.set(p.caso_id, atual);
  }
  // Sem a leitura, "0 pendências" seria ausência apresentada como dado.
  const pendLida = !pendRes.error && !pendRes.truncado;

  const ativos = casos.filter((c) => !c.fechado_em);
  const fechados = casos.filter((c) => c.fechado_em);
  const lista = aba === "fechados" ? fechados : ativos;

  const href = (a: "ativos" | "fechados") => {
    const q = new URLSearchParams();
    if (a === "fechados") q.set("aba", a);
    if (termo) q.set("q", termo);
    const t = q.toString();
    return t ? `/casos/todos?${t}` : "/casos/todos";
  };

  const Linha = ({ caso }: { caso: Caso }) => {
    const fechado = Boolean(caso.fechado_em);
    const pend = pendPorCaso.get(caso.id);
    const etapa = ETAPAS_DO_MANDATO[etapaDoMandato(caso.status)];
    return (
      <tr className={`relative block px-4 py-3 transition-colors hover:bg-tinta-50 md:table-row md:p-0 ${fechado ? "opacity-75" : ""}`}>
        <td className="block pr-10 md:table-cell md:px-4 md:py-3 md:pr-4">
          {/* Linha inteira clicável: o link se estende sobre a linha (after:inset-0)
              e o menu "⋯" fica acima dele (z-10). */}
          <Link
            href={`/casos/${caso.id}`}
            className="block truncate text-sm font-semibold text-tinta-900 after:absolute after:inset-0"
          >
            {caso.nome}
          </Link>
          {fechado && (
            <p className="mt-0.5 text-[11px] text-tinta-500">
              {`Fechado${dataCurta(caso.fechado_em) ? ` em ${dataCurta(caso.fechado_em)}` : ""}${
                caso.motivo_fechamento ? ` — ${caso.motivo_fechamento}` : ""
              }. Nada foi apagado.`}
            </p>
          )}
        </td>
        <td className="mt-1 inline-block pr-3 text-xs text-tinta-500 md:table-cell md:px-4 md:py-3 md:text-sm md:text-tinta-700">
          {humanizar(caso.produto)}
        </td>
        <td className="inline-block pr-3 md:table-cell md:px-4 md:py-3">
          {/* Duas perguntas, dois rótulos: onde o trabalho está (etapa, em
              palavras) e o estado do gate (chip). */}
          <span className="text-xs text-tinta-700 md:text-sm">{etapa}</span>{" "}
          <span className={`chip ${CASO_STATUS_COLOR[caso.status]}`}>{CASO_STATUS_LABEL[caso.status]}</span>
        </td>
        <td className="inline-block pr-3 text-xs md:table-cell md:px-4 md:py-3 md:text-sm">
          {!pendLida ? (
            <span className="text-tinta-400" title="leitura das pendências indisponível agora">—</span>
          ) : pend?.total ? (
            <span className="tabular-nums text-tinta-700">
              {pend.total} {pend.total === 1 ? "pendência" : "pendências"}
              {pend.bloqueantes > 0 && (
                <span className="chip ml-1.5 bg-risco-100 text-risco-800">
                  {pend.bloqueantes} {pend.bloqueantes === 1 ? "trava" : "travam"}
                </span>
              )}
            </span>
          ) : (
            <span className="text-tinta-500">nenhuma</span>
          )}
        </td>
        <td className="inline-block text-xs text-tinta-500 md:table-cell md:px-4 md:py-3 md:text-sm md:text-tinta-700">
          <span className="md:hidden">aberto em </span>
          {dataCurta(caso.criado_em)}
        </td>
        {/* O menu reusa o do cabeçalho do mandato: os diálogos de fechar/excluir
            moram dentro do painel escondido, que nunca é desmontado. */}
        {/* No celular cada td é `absolute z-10`, ou seja, um contexto de empilhamento
            próprio: o menu aberto da linha N (z-20, dentro do td) ficava sob o "⋯" da
            linha N+1. O td que contém o botão expandido sobe para z-30. */}
        <td className="absolute right-2 top-2 z-10 has-[[aria-expanded=true]]:z-30 md:static md:table-cell md:px-3 md:py-3 md:text-right">
          <MenuDoMandato casoId={caso.id} nome={caso.nome} fechado={fechado} reservado={perm.reservadoAoSocio} />
        </td>
      </tr>
    );
  };

  const aba_ = (a: "ativos" | "fechados", rotulo: string, n: number) => (
    <Link
      key={a}
      href={href(a)}
      aria-current={aba === a ? "page" : undefined}
      className={`border-b-2 px-3 py-2 text-sm font-medium transition-colors ${
        aba === a
          ? "border-tinta-900 text-tinta-900"
          : "border-transparent text-tinta-500 hover:text-tinta-800"
      }`}
    >
      {rotulo} <span className="tabular-nums">({n})</span>
    </Link>
  );

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-tinta-900">Mandatos</h1>
          <p className="mt-0.5 text-sm text-tinta-500">
            {casos.length === 0 && !termo
              ? `${soAlocados ? textoDeNenhumMandato(perm.papel) : textoDeNenhumMandato(perm.papel, "aberto")}.`
              : termo
                ? `${casos.length} ${casos.length === 1 ? "resultado" : "resultados"} para “${termo}”`
                : soAlocados
                  ? "Os mandatos em que você está alocado, incluindo o que já saiu da mesa."
                  : "O que existe, incluindo o que já saiu da mesa."}
          </p>
        </div>
        {/* GET puro: a busca é um link que se pode copiar. `aba` segue junto. */}
        <form action="/casos/todos" method="get" role="search" className="flex items-center gap-2">
          {aba === "fechados" && <input type="hidden" name="aba" value="fechados" />}
          <input
            type="search"
            name="q"
            defaultValue={termo}
            maxLength={80}
            placeholder="Buscar pelo nome"
            aria-label="Buscar mandato pelo nome"
            className="w-48 rounded-md border border-tinta-200 bg-folha px-3 py-1.5 text-sm text-tinta-900 placeholder:text-tinta-400 sm:w-64"
          />
          <button type="submit" className="btn-secundario">Buscar</button>
          {termo && (
            <Link href={aba === "fechados" ? "/casos/todos?aba=fechados" : "/casos/todos"} className="btn-discreto">
              Limpar
            </Link>
          )}
        </form>
      </div>

      {error && (
        <p className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          Não foi possível carregar os mandatos: {error.message}
        </p>
      )}
      {!error && pendRes.error && (
        <p className="rounded-lg border border-alerta-200 bg-alerta-50 p-3 text-sm text-alerta-900">
          As pendências não puderam ser lidas agora; a coluna Pendências mostra traço, não zero.
        </p>
      )}

      {!error && casos.length === 0 && !termo && escopoDaLista(perm.papel) === "indefinido" ? (
        <div className="carta flex flex-col items-center gap-3 px-6 py-12 text-center">
          <p className="text-sm font-medium text-tinta-900">{textoDeNenhumMandato(perm.papel)}</p>
          <p className="max-w-md text-sm text-tinta-500">
            Não foi possível conferir o seu papel, então a lista pode estar recortada ao seu acesso: não dá
            para dizer que não existe mandato. Recarregue a página.
          </p>
        </div>
      ) : !error && casos.length === 0 && !termo && soAlocados ? (
        <div className="carta flex flex-col items-center gap-3 px-6 py-12 text-center">
          <p className="text-sm font-medium text-tinta-900">Você ainda não está alocado em nenhum mandato</p>
          <p className="max-w-md text-sm text-tinta-500">
            Com o papel de {perm.papel === "leitura" ? "Leitura" : "Analista"} você só vê os mandatos em que um
            Sócio alocou você — o que não aparece aqui pode existir. Peça a alocação a um Sócio
            {perm.criarMandato.pode ? <>, ou abra um mandato seu em <strong className="font-medium text-tinta-700">Novo mandato</strong></> : ""}.
          </p>
        </div>
      ) : !error && casos.length === 0 && !termo ? (
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
          <nav aria-label="Mandatos" className="flex gap-1 border-b border-tinta-200">
            {aba_("ativos", "Ativos", ativos.length)}
            {aba_("fechados", "Fechados", fechados.length)}
          </nav>

          {aba === "fechados" && fechados.length > 0 && (
            <p className="text-xs text-tinta-500">
              Saíram da mesa — o dado continua aqui, e reabrir é um clique no menu ⋯.
            </p>
          )}

          {lista.length === 0 ? (
            <div className="carta px-6 py-10 text-center text-sm text-tinta-500">
              {termo
                ? `Nenhum mandato ${aba === "fechados" ? "fechado" : "ativo"} com “${termo}” no nome.`
                : aba === "fechados"
                  ? "Nenhum mandato fechado."
                  : "Nenhum mandato ativo."}
            </div>
          ) : (
            // Sem `overflow` no contêiner: ele cortaria o menu "⋯", que abre para
            // baixo da linha. No celular a tabela vira linhas empilhadas (sem
            // rolagem horizontal); a partir de md é tabela de verdade.
            <div className="carta">
              <table className="block w-full md:table">
                <thead className="hidden md:table-header-group">
                  <tr className="border-b border-tinta-100 text-left text-[11px] font-semibold uppercase tracking-wide text-tinta-500">
                    <th scope="col" className="px-4 py-2.5">Mandato</th>
                    <th scope="col" className="px-4 py-2.5">Produto</th>
                    <th scope="col" className="px-4 py-2.5">Etapa</th>
                    <th scope="col" className="px-4 py-2.5">Pendências</th>
                    <th scope="col" className="px-4 py-2.5">Aberto em</th>
                    <th scope="col" className="px-3 py-2.5"><span className="sr-only">Ações</span></th>
                  </tr>
                </thead>
                <tbody className="block divide-y divide-tinta-100 md:table-row-group">
                  {lista.map((caso) => (
                    <Linha key={caso.id} caso={caso} />
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </div>
  );
}
