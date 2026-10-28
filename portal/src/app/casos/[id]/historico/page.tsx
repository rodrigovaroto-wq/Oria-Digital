import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { cursorValido, funcaoAusente, type EventoDoHistorico } from "@/lib/historico-do-mandato";
import { LinhaDoTempo } from "./linha-do-tempo";

// O HISTÓRICO DO MANDATO (0215, `fn_historico_do_caso`): quem fez o quê e quando, do mais novo ao mais
// velho. Não é aba: alcança-se pelo menu ⋯ do mandato.
//
// PÁGINA DE 100, PEDINDO 101. O 101º só existe para saber se há mais antigos: sem ele, uma página
// cheia de exatamente 100 diria "carregar mais" para uma página vazia. O cursor é o `em` do último
// mostrado, TEXTO como o banco devolveu (microssegundos incluídos — passar por Date os perderia e a
// próxima página repetiria ou pularia o evento da borda). TETO CONHECIDO da 0215: dois eventos no
// MESMO instante exato podem cair um em cada página e o segundo se perder.
const POR_PAGINA = 100;

export default async function HistoricoDoMandatoPage({
  params, searchParams,
}: Readonly<{ params: Promise<{ id: string }>; searchParams: Promise<{ antes?: string | string[] }> }>) {
  const { id } = await params;
  const sp = await searchParams;
  const antesBruto = Array.isArray(sp.antes) ? sp.antes[0] : sp.antes;
  const cursorRecusado = antesBruto !== undefined && !cursorValido(antesBruto);

  let eventos: EventoDoHistorico[] = [];
  let erro: { code?: string | null; message: string } | null = null;
  if (!cursorRecusado) {
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("fn_historico_do_caso", {
      p_caso_id: id, p_limite: POR_PAGINA + 1, p_antes: antesBruto ?? null,
    });
    if (error) erro = error;
    else eventos = (data ?? []) as EventoDoHistorico[];
  }

  const haMais = eventos.length > POR_PAGINA;
  const pagina = eventos.slice(0, POR_PAGINA);
  const proximo = pagina.length > 0 ? pagina[pagina.length - 1].em : null;

  return (
    <div className="mx-auto max-w-3xl space-y-6 py-2">
      <header>
        <h1 className="font-titulo text-xl font-medium text-tinta-900">Histórico do mandato</h1>
        <p className="mt-1 text-sm text-tinta-700">O que mudou neste mandato e quem fez, do mais recente ao mais antigo.</p>
      </header>

      {/* NOTA FIXA, à vista (não em title=): o que este histórico NÃO tem. Lista da 0215. */}
      <aside className="rounded-md border border-tinta-200 bg-tinta-50 p-4 text-sm text-tinta-800" aria-label="O que o histórico não registra">
        <p className="font-medium">O que este histórico não mostra</p>
        <ul className="mt-1 list-disc space-y-0.5 pl-5">
          <li>Exportações do book: não há registro de quem exportou o quê nem quando.</li>
          <li>Quem enviou cada documento: o sistema guarda a data de recebimento, não o remetente.</li>
          <li>Recusas (aceite, aprovação ou premissa recusados): são tentativas que não mudaram nada.</li>
          <li>Mudanças do ajuste de rigor do sistema (são globais, não deste mandato) e pendências abertas pelo sistema (só a decisão sobre elas aparece).</li>
          <li>Registros de controlador de um grupo e vínculos familiares.</li>
        </ul>
        <p className="mt-2 text-xs text-tinta-600">Ausência neste histórico não prova que algo não aconteceu.</p>
      </aside>

      {cursorRecusado && (
        <div role="alert" className="rounded-md border border-risco-300 bg-risco-50 p-4 text-sm text-risco-900">
          O ponto de partida pedido na página não é uma data válida, então nenhum evento foi lido.{" "}
          <Link href={`/casos/${id}/historico`} className="underline">Voltar ao mais recente</Link>
        </div>
      )}

      {erro && (
        <div role="alert" className="rounded-md border border-risco-300 bg-risco-50 p-4 text-sm text-risco-900">
          {funcaoAusente(erro) ? (
            <>
              <p className="font-medium">O histórico precisa de uma atualização do banco que ainda não foi aplicada.</p>
              <p className="mt-1">Nada foi perdido: o resto do mandato segue funcionando. Peça a quem cuida do sistema para aplicar a atualização.</p>
              <DetalhesTecnicos>
                <p>Migration 0215 (Supabase/migrations/0215_o_historico_que_so_o_banco_sabia.sql): função fn_historico_do_caso.</p>
                <p>{erro.code}: {erro.message}</p>
              </DetalhesTecnicos>
            </>
          ) : (
            <>
              <p className="font-medium">Não foi possível ler o histórico agora.</p>
              <p className="mt-1">Isso não quer dizer que o mandato não tenha eventos. Recarregue a página; se persistir, avise quem cuida do sistema.</p>
              <DetalhesTecnicos>
                <p>{erro.code ? `${erro.code}: ` : ""}{erro.message}</p>
              </DetalhesTecnicos>
            </>
          )}
        </div>
      )}

      {!erro && !cursorRecusado && (
        <>
          {antesBruto && (
            <p className="text-sm">
              <Link href={`/casos/${id}/historico`} className="underline">← Voltar aos mais recentes</Link>
            </p>
          )}
          {pagina.length === 0 ? (
            <p className="text-sm text-tinta-700">
              {antesBruto
                ? "Não há eventos mais antigos que este ponto."
                : "Nenhum evento registrado para este mandato, dentro do que o histórico cobre (veja a nota acima)."}
            </p>
          ) : (
            <LinhaDoTempo casoId={id} eventos={pagina} />
          )}
          {pagina.length > 0 && (haMais && proximo ? (
            <p>
              <Link href={`/casos/${id}/historico?antes=${encodeURIComponent(proximo)}`} className="btn-secundario">
                Carregar mais antigos
              </Link>
            </p>
          ) : (
            <p className="text-sm text-tinta-600">Fim do histórico: não há eventos mais antigos.</p>
          ))}
        </>
      )}
    </div>
  );
}
