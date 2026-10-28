import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import { PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS, type TaxonomiaTipoDocumento } from "@/lib/types";
import { formatarTipoTaxonomia } from "@/lib/export";
import { revisarDocumento } from "./actions";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";


const PENDENCIA_TIPO_LABEL: Record<string, string> = {
  classificacao_pendente: "classificação incerta",
  tipo_incorreto: "tipo pode estar incorreto",
  entidade_incorreta: "entidade pode estar incorreta",
  periodo_incorreto: "período pode estar incorreto",
};

interface PendenciaComDocumento {
  id: string;
  tipo: string;
  descricao: string | null;
  criada_em: string;
  documento: {
    id: string;
    tipo_taxonomia: string | null;
    confianca: number | null;
    fonte: string | null;
    justificativa: string | null;
    entidade: { razao_social: string } | null;
    periodo: { tipo: string; referencia: string } | null;
    documento_versao: Array<{ nome_original: string | null }> | null;
  } | null;
}

export default async function FilaRevisaoPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const [pendenciasRes, taxonomiaRes] = await Promise.all([
    // Paginada: esta É a fila de trabalho do mandato, e desde a 0119 a cobrança
    // de linha exigida é por ENTIDADE — num grupo econômico o número de
    // pendências multiplica pelo de empresas. O teto do PostgREST corta em
    // silêncio, e uma fila truncada parece uma fila terminada.
    paginar<PendenciaComDocumento>((de, ate) =>
      supabase
        .from("pendencia")
        .select(
          `id, tipo, descricao, criada_em,
           documento:documento_id(
             id, tipo_taxonomia, confianca, fonte, justificativa,
             entidade:entidade_id(razao_social), periodo:periodo_id(tipo, referencia),
             documento_versao(nome_original)
           )`,
        )
        .eq("caso_id", id)
        .in("tipo", PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS)
        .eq("estado", "aberta")
        .order("criada_em", { ascending: true })
        .order("id", { ascending: true })
        .range(de, ate),
    ),
    supabase.from("taxonomia_tipo_documento").select("codigo, categoria, documento, obrigatoriedade").order("codigo"),
  ]);

  const pendencias = pendenciasRes.data;
  const taxonomia = (taxonomiaRes.data as TaxonomiaTipoDocumento[] | null) ?? [];

  const revisarAction = revisarDocumento.bind(null, id);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-lg font-semibold text-tinta-900">Revisão</h1>
        <p className="mt-1 max-w-2xl text-sm text-tinta-500">
          O sistema não teve certeza sobre o tipo, a empresa ou o período destes documentos.
          Confirme ou corrija — nada entra na base sem essa decisão, e a sugestão nunca decide
          sozinha.
        </p>
      </div>

      {pendenciasRes.error && (
        <div className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          Não foi possível carregar a fila de revisão. Tente de novo em instantes; se persistir,
          avise o administrador do sistema.
          <DetalhesTecnicos>
            <p>{pendenciasRes.error.message}</p>
          </DetalhesTecnicos>
        </div>
      )}

      {pendencias.length === 0 && !pendenciasRes.error && (
        <div className="carta px-6 py-12 text-center">
          <p className="text-sm font-medium text-tinta-900">Nada a revisar</p>
          <p className="mt-1 text-sm text-tinta-500">
            Todo documento deste mandato foi classificado com confiança suficiente.
          </p>
        </div>
      )}

      <ul className="space-y-4">
        {pendencias.map((p) => {
          const doc = p.documento;
          if (!doc) return null;
          const nomeArquivo = doc.documento_versao?.[0]?.nome_original ?? "(sem nome)";

          return (
            <li key={p.id} className="carta p-4">
              <div className="mb-3">
                <p className="flex flex-wrap items-center gap-2 text-sm font-medium text-tinta-900">
                  {nomeArquivo}
                  <span className="chip bg-alerta-100 text-alerta-800">
                    {PENDENCIA_TIPO_LABEL[p.tipo] ?? p.tipo}
                  </span>
                </p>
                {/* O QUE O DIAGNÓSTICO ACHOU fica no CORPO, não em "Detalhes
                    técnicos": em `tipo_incorreto`/`entidade_incorreta` a descrição
                    é a única linha que diz "o conteúdo sugere X, o registro diz Y"
                    — o rodapé e os selects mostram o valor REGISTRADO. Escondida,
                    o analista confirmava justamente o valor que o diagnóstico
                    apontou como errado (achado da revisão do PR #265). */}
                {p.descricao && <p className="mt-1 text-sm text-tinta-700">{p.descricao}</p>}
              </div>

              <form action={revisarAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <input type="hidden" name="documento_id" value={doc.id} />

                <div>
                  <label className="block text-xs font-medium text-tinta-600">Tipo de documento</label>
                  <select
                    name="novo_tipo_taxonomia"
                    defaultValue={doc.tipo_taxonomia ?? ""}
                    className="mt-1 w-full rounded-md border border-tinta-200 px-2.5 py-1.5 text-sm"
                  >
                    <option value="">— sem tipo —</option>
                    {taxonomia.map((t) => (
                      <option key={t.codigo} value={t.codigo}>
                        {t.documento}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-medium text-tinta-600">Entidade</label>
                  <input
                    type="text"
                    name="nova_entidade_nome"
                    defaultValue={doc.entidade?.razao_social ?? ""}
                    placeholder="Razão social"
                    className="mt-1 w-full rounded-md border border-tinta-200 px-2.5 py-1.5 text-sm"
                  />
                </div>

                <div>
                  <label className="block text-xs font-medium text-tinta-600">Período</label>
                  <select
                    name="novo_periodo_tipo"
                    defaultValue={doc.periodo?.tipo ?? "anual"}
                    className="mt-1 w-full rounded-md border border-tinta-200 px-2.5 py-1.5 text-sm"
                  >
                    <option value="anual">anual</option>
                    <option value="trimestre">trimestre</option>
                    <option value="multi">vários períodos</option>
                    <option value="data-base">posição numa data</option>
                    <option value="outro">outro</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-medium text-tinta-600">Referência do período</label>
                  <input
                    type="text"
                    name="novo_periodo_ref"
                    defaultValue={doc.periodo?.referencia ?? ""}
                    placeholder="ex.: 12M25, 2025"
                    className="mt-1 w-full rounded-md border border-tinta-200 px-2.5 py-1.5 text-sm"
                  />
                </div>

                <div className="sm:col-span-2">
                  <label className="block text-xs font-medium text-tinta-600">Observação (opcional)</label>
                  <textarea
                    name="motivo"
                    rows={2}
                    placeholder="Por que confirmou ou corrigiu"
                    className="mt-1 w-full rounded-md border border-tinta-200 px-2.5 py-1.5 text-sm"
                  />
                </div>

                <div className="flex flex-wrap items-center justify-between gap-3 border-t border-tinta-100 pt-3 text-xs text-tinta-500 sm:col-span-2">
                  <span>
                    O sistema sugeriu <strong className="text-tinta-700">{formatarTipoTaxonomia(doc.tipo_taxonomia)}</strong>
                    {doc.confianca != null && ` com ${Math.round(doc.confianca * 100)}% de confiança`}
                    {doc.fonte === "nome_arquivo" && ", pelo nome do arquivo"}
                    {doc.fonte === "openai_conteudo" && ", lendo o conteúdo"}
                  </span>
                  <button type="submit" className="btn-primario">
                    Confirmar
                  </button>
                </div>
              </form>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
