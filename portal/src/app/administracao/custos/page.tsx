import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { agregarCustos, formatarUsd, motivoDaAusencia, type LoteDeCusto, type SomaDeCusto } from "@/lib/custos";

// Custos — SOMENTE LEITURA. Por que o custo mora na Administração e não no Início:
// não é argumento comercial, é controle de quem opera (decisão do dono, 28/10/2026).
//
// UMA consulta, colunas nomeadas, em `lote_execucao` (uma linha por execução de
// ingestão — cresce com o uso, não com o tamanho dos documentos; a cota de egress do
// Supabase é apertada). Cobre o período E o total de cada mandato com a mesma leitura.
// A conta e as regras de ausência estão em `lib/custos.ts`.

const PERIODOS = [
  { id: "30", rotulo: "Últimos 30 dias", dias: 30 },
  { id: "90", rotulo: "Últimos 90 dias", dias: 90 },
  { id: "tudo", rotulo: "Desde o início", dias: null },
] as const;

function dataCurta(iso: string | null) {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("pt-BR", { dateStyle: "short" });
}

function Valor({ s, campo }: Readonly<{ s: SomaDeCusto; campo: "custoUsd" | "custoPorDocumentoUsd" }>) {
  const txt = formatarUsd(s[campo]);
  if (txt) return <span className="tabular-nums">{txt}</span>;
  // Ausência com o motivo, nunca "US$ 0,00".
  return (
    <span className="text-xs text-tinta-500">
      {motivoDaAusencia(s, campo)}
    </span>
  );
}

export default async function CustosPage({
  searchParams,
}: Readonly<{ searchParams: Promise<{ periodo?: string }> }>) {
  const { periodo: pedido } = await searchParams;
  const periodo = PERIODOS.find((p) => p.id === pedido) ?? PERIODOS[0];
  const supabase = await createClient();

  const lotesRes = await paginar<LoteDeCusto>((de, ate) =>
    supabase
      .from("lote_execucao")
      .select("id, caso_id, criado_em, documentos, custo_total_usd")
      .order("id", { ascending: true })
      .range(de, ate),
  );

  if (lotesRes.error) {
    return (
      <div className="space-y-4">
        <Titulo />
        <div className="rounded border border-risco-300 bg-risco-50 p-3 text-sm text-risco-700">
          <p>
            Não foi possível ler os custos agora. Esta tela não mostra nenhum valor, porque um
            total parcial pareceria o custo inteiro. Tente de novo em instantes; se persistir, avise
            o administrador do sistema.
          </p>
          <DetalhesTecnicos>
            <p>{lotesRes.error.message}</p>
          </DetalhesTecnicos>
        </div>
      </div>
    );
  }

  const agregado = agregarCustos(lotesRes.data, new Date(), periodo.dias);
  const ids = agregado.porMandato.map((m) => m.casoId);
  const nomesRes = ids.length
    ? await supabase.from("caso").select("id, nome").in("id", ids)
    : { data: [] as { id: string; nome: string }[], error: null };
  const nomes = new Map(((nomesRes.data as { id: string; nome: string }[] | null) ?? []).map((c) => [c.id, c.nome]));
  const { periodo: p, total: t } = agregado;

  return (
    <div className="space-y-6">
      <Titulo />

      <nav aria-label="Período" className="flex flex-wrap gap-2 text-sm">
        {PERIODOS.map((o) => (
          <Link
            key={o.id}
            href={`/administracao/custos?periodo=${o.id}`}
            aria-current={o.id === periodo.id ? "page" : undefined}
            className={`rounded-full border px-3 py-1 ${
              o.id === periodo.id
                ? "border-acento-600 bg-acento-50 font-semibold text-tinta-900"
                : "border-tinta-200 text-tinta-600 hover:border-tinta-300"
            }`}
          >
            {o.rotulo}
          </Link>
        ))}
      </nav>

      {lotesRes.truncado && (
        <p className="rounded border border-alerta-300 bg-alerta-50 p-3 text-sm text-alerta-900">
          A leitura parou no limite de segurança: os valores abaixo são parciais e não devem ser
          tomados como o custo total.
        </p>
      )}

      {t.lotes === 0 ? (
        <p className="rounded border border-tinta-200 p-4 text-sm text-tinta-600">
          Nenhuma execução de ingestão registrada ainda. Sem execução não há custo a mostrar — isto
          não significa custo zero.
        </p>
      ) : (
        <>
          <dl className="grid gap-3 sm:grid-cols-3">
            <div className="rounded border border-tinta-200 p-4">
              <dt className="text-xs uppercase text-tinta-500">Custo de IA — {periodo.rotulo.toLowerCase()}</dt>
              <dd className="mt-1 text-xl font-semibold text-tinta-900"><Valor s={p} campo="custoUsd" /></dd>
            </div>
            <div className="rounded border border-tinta-200 p-4">
              <dt className="text-xs uppercase text-tinta-500">Custo por documento</dt>
              <dd className="mt-1 text-xl font-semibold text-tinta-900"><Valor s={p} campo="custoPorDocumentoUsd" /></dd>
            </div>
            <div className="rounded border border-tinta-200 p-4">
              <dt className="text-xs uppercase text-tinta-500">Execuções no período</dt>
              <dd className="mt-1 text-xl font-semibold text-tinta-900 tabular-nums">{p.lotes}</dd>
            </div>
          </dl>

          {p.semCusto > 0 && (
            <p className="rounded border border-alerta-300 bg-alerta-50 p-3 text-sm text-alerta-900">
              {p.semCusto} de {p.lotes} {p.lotes === 1 ? "execução" : "execuções"} no período não
              registrou custo. Elas ficam fora da soma, então o valor acima é um piso — o gasto real
              é pelo menos esse, possivelmente maior.
            </p>
          )}

          <div className="overflow-x-auto rounded border border-tinta-200">
            <table className="w-full text-sm">
              <thead className="bg-tinta-50 text-left text-xs uppercase text-tinta-500">
                <tr>
                  <th className="px-4 py-2 font-medium">Mandato</th>
                  <th className="px-4 py-2 font-medium">No período</th>
                  <th className="px-4 py-2 font-medium">Por documento</th>
                  <th className="px-4 py-2 font-medium">Desde o início</th>
                  <th className="px-4 py-2 font-medium">Última execução</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-tinta-100">
                {agregado.porMandato.map((m) => (
                  <tr key={m.casoId}>
                    <td className="px-4 py-2 text-tinta-900">
                      {nomes.has(m.casoId) ? (
                        <Link href={`/casos/${m.casoId}`} className="hover:underline">{nomes.get(m.casoId)}</Link>
                      ) : (
                        <span className="text-tinta-500">Mandato sem nome legível</span>
                      )}
                    </td>
                    <td className="px-4 py-2">
                      <Valor s={m.periodo} campo="custoUsd" />
                      {m.periodo.semCusto > 0 && m.periodo.custoUsd !== null && (
                        <span className="ml-1 text-xs text-alerta-900">(piso)</span>
                      )}
                    </td>
                    <td className="px-4 py-2"><Valor s={m.periodo} campo="custoPorDocumentoUsd" /></td>
                    <td className="px-4 py-2">
                      <Valor s={m.total} campo="custoUsd" />
                      {m.total.semCusto > 0 && m.total.custoUsd !== null && (
                        <span className="ml-1 text-xs text-alerta-900">(piso)</span>
                      )}
                    </td>
                    <td className="px-4 py-2 text-tinta-600">{dataCurta(m.total.ultimoEm)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <p className="text-xs text-tinta-500">
            Soma dos mandatos existentes desde o início: <Valor s={t} campo="custoUsd" />
            {t.semCusto > 0 && ` (piso: ${t.semCusto} de ${t.lotes} execuções sem custo registrado)`}.
          </p>
          <p className="text-xs text-tinta-500">
            Mandato excluído leva suas execuções junto (o registro de custo é apagado com ele): o gasto
            de um mandato que já não existe não entra nesta soma e não pode ser recuperado por esta tela.
          </p>
        </>
      )}

      <DetalhesTecnicos prosa>
        <p>
          O valor é o custo de IA da leitura dos documentos, em dólar, como cada execução de
          ingestão o registrou (tabela lote_execucao, via fn_registrar_uso_lote). Não há conversão
          para real porque o banco não guarda taxa de câmbio, e uma taxa escolhida aqui pareceria
          medida. Não entram nesta tela: custo de hospedagem, de banco e de outras ferramentas — o
          sistema não mede isso. O alerta de execução que custou bem mais que o previsto é decidido
          no banco (fn_operacao_lotes) e não é repetido aqui.
        </p>
      </DetalhesTecnicos>
    </div>
  );
}

function Titulo() {
  return (
    <div>
      <h1 className="text-lg font-semibold text-tinta-900">Custos</h1>
      <p className="mt-1 text-sm text-tinta-500">
        Quanto a leitura dos documentos por IA custou, por mandato e no período. Esta tela só
        mostra o que as execuções registraram.
      </p>
    </div>
  );
}
