import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS, type Caso } from "@/lib/types";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";
import { humanizar } from "@/lib/rotulos";
import { ETAPAS_DO_MANDATO, etapaDoMandato } from "@/lib/etapa-do-mandato";
import { IconeCheck } from "@/components/icones";
import { AbasDoMandato, type AbaDoMandato } from "./abas-do-mandato";
import { MenuDoMandato } from "./menu-do-mandato";

// O CABEÇALHO E AS ABAS DO MANDATO, uma vez só para toda tela de /casos/[id].
// Cada tela repetia o nome do mandato no próprio H1 e um "← Voltar" diferente;
// aqui moram o nome, o estado, a régua de etapas e a navegação.
//
// ESTE LAYOUT RODA EM TODA TROCA DE ABA, então as consultas são mínimas: colunas
// nomeadas, e os três números (documentos, revisão, perguntas) são `head: true`
// — só a contagem, nenhuma linha (a cota de egress do Supabase é apertada, ver
// PRODUCT.md). O layout não revalida ao navegar entre abas do mesmo segmento,
// então o custo real é por visita ao mandato, não por clique.
//
// CONTAGEM QUE FALHA SAI SEM NÚMERO, nunca "0" (regra 1): "0 perguntas" diria
// "não há o que perguntar", e o que se sabe é só que a consulta não respondeu.
export default async function MandatoLayout({
  children,
  params,
}: Readonly<{
  children: React.ReactNode;
  params: Promise<{ id: string }>;
}>) {
  const { id } = await params;
  const supabase = await createClient();

  const [casoRes, documentosRes, revisaoRes] = await Promise.all([
    supabase.from("caso").select("id, nome, produto, status, criado_em, fechado_em").eq("id", id).single(),
    supabase.from("documento").select("id", { head: true, count: "exact" }).eq("caso_id", id),
    // Pendência de diagnóstico revisável que ainda está na fila da tela de
    // Revisão. O nome é "Revisão" e não
    // "Pendências" porque só cobre revisão de documento — a aba de Pendências
    // unificada ainda não existe, e um número parcial no lugar do total seria
    // apresentar ausência como dado.
    supabase
      .from("pendencia")
      .select("id", { head: true, count: "exact" })
      .eq("caso_id", id)
      .in("tipo", PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS)
      // O MESMO filtro da tela `/revisao` (`estado = 'aberta'`), e não o da
      // faixa "Revisar agora" (que soma `em_correcao_interna` e
      // `reenviada_ao_cliente`): o número da aba promete quantos cartões a aba
      // mostra. Com o filtro da faixa, a aba diria "3" e a tela abriria com 1.
      .eq("estado", "aberta"),
  ]);

  // NÃO ENCONTRADO ≠ NÃO CONSEGUI LER. `.single()` sem linha volta PGRST116:
  // aí o mandato não existe (ou foi excluído) e `notFound()` diz isso. Qualquer
  // outro erro (timeout, 5xx) LANÇA, e cai na fronteira de erro com "Tentar de
  // novo" — antes, um timeout dizia "ele pode ter sido excluído" (revisão do
  // PR #265: falha de leitura apresentada como ausência).
  if (casoRes.error && casoRes.error.code !== "PGRST116") {
    throw new Error(`Leitura do mandato falhou: ${casoRes.error.message}`);
  }
  if (!casoRes.data) notFound();
  const caso = casoRes.data as Caso;
  const fechado = Boolean(caso.fechado_em);
  const etapa = etapaDoMandato(caso.status);

  const nDocumentos = documentosRes.error ? null : documentosRes.count;
  const abas: AbaDoMandato[] = [
    { rotulo: "Visão geral", sufixo: "", contagem: null },
    { rotulo: "Revisão", sufixo: "/revisao", contagem: revisaoRes.error ? null : revisaoRes.count },
    // SEM NÚMERO, de propósito. A tela conta "perguntas a fazer" excluindo as
    // `ja_enviada` E as que têm ação registrada (enviada/descartada) em outra
    // tabela; a contagem crua de `fn_sugerir_perguntas` incluía as já tratadas
    // (7 na aba, "2 perguntas a fazer" na tela). Reproduzir a conta aqui seria
    // ler a lista inteira a cada aba; um número que mente é pior que nenhum.
    { rotulo: "Perguntas ao cliente", sufixo: "/perguntas", contagem: null },
    { rotulo: "Grupo econômico", sufixo: "/perimetro", contagem: null },
    { rotulo: "Modelagem", sufixo: "/modelagem", contagem: null },
    // Os três arquivos do mandato (base de dados, modelo, apresentação) moram aqui. Antes eram 6
    // links em 3 telas (contados nos `href` do código anterior: 1 na visão geral, 4 na Modelagem
    // — incluindo "Campos da apresentação" —, 1 na Apresentação), sem dizer qual estava liberado.
    { rotulo: "Entregáveis", sufixo: "/entregaveis", contagem: null },
  ];

  const aberto = new Date(caso.criado_em).toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" });

  return (
    <div className="space-y-6">
      <header className="space-y-4">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2.5">
              <h1 className="font-titulo text-2xl font-medium tracking-tight text-tinta-900">{caso.nome}</h1>
              <span className={`chip ${CASO_STATUS_COLOR[caso.status]}`}>{CASO_STATUS_LABEL[caso.status]}</span>
              {fechado && (
                <span className="chip bg-tinta-100 text-tinta-600" title="Fora da lista de ativos; nada foi apagado.">
                  Fechado
                </span>
              )}
            </div>
            {/* O produto em português: o banco guarda `reestruturacao`. */}
            <p className="mt-0.5 text-sm text-tinta-500">
              {humanizar(caso.produto)} · aberto em {aberto}
              {nDocumentos !== null && ` · ${nDocumentos} ${nDocumentos === 1 ? "documento" : "documentos"}`}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Link href={`/casos/${id}/adicionar`} className="btn-secundario">
              Adicionar arquivos
            </Link>
            <MenuDoMandato casoId={id} nome={caso.nome} fechado={fechado} />
          </div>
        </div>

        {/* A RÉGUA diz a etapa EM TEXTO (e `aria-current="step"`), não só pela
            cor: quem projeta a tela numa reunião ou não distingue o terracota
            do cinza lê "Etapa atual" no passo. Aproximação do `status`, ver
            `lib/etapa-do-mandato.ts`. */}
        <ol aria-label="Etapa do mandato" className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
          {ETAPAS_DO_MANDATO.map((nome, i) => {
            const feita = i < etapa;
            const atual = i === etapa;
            let tom = "bg-tinta-100 text-tinta-500";
            if (atual) tom = "bg-acento-600 font-semibold text-papel";
            else if (feita) tom = "bg-ok-100 text-ok-800";
            return (
              <li
                key={nome}
                aria-current={atual ? "step" : undefined}
                className={`flex items-center gap-1.5 rounded-full px-2.5 py-1 ${tom}`}
              >
                {feita && <IconeCheck tamanho={12} />}
                <span>{nome}</span>
                {atual && <span className="font-normal opacity-90">· etapa atual</span>}
                {feita && <span className="sr-only">(concluída)</span>}
              </li>
            );
          })}
        </ol>
      </header>

      <AbasDoMandato casoId={id} abas={abas} />

      {children}
    </div>
  );
}
