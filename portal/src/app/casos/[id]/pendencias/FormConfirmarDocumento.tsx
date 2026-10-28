import { formatarTipoTaxonomia } from "@/lib/export";
import { revisarDocumento } from "./actions";
import type { TaxonomiaTipoDocumento } from "@/lib/types";

// O CARTÃO DE CONFIRMAÇÃO DE DOCUMENTO — movido de `revisao/page.tsx` (a aba "Revisão"
// virou o filtro "Confirmar documento" de Pendências). O formulário e a action são os
// mesmos; só mudou o endereço.
const PENDENCIA_TIPO_LABEL: Record<string, string> = {
  classificacao_pendente: "classificação incerta",
  tipo_incorreto: "tipo pode estar incorreto",
  entidade_incorreta: "entidade pode estar incorreta",
  periodo_incorreto: "período pode estar incorreto",
};

export interface DocumentoParaConfirmar {
  id: string;
  tipo_taxonomia: string | null;
  confianca: number | null;
  fonte: string | null;
  entidade: { razao_social: string } | null;
  periodo: { tipo: string; referencia: string } | null;
}

export function CartaoConfirmarDocumento({
  casoId, p, doc, nomeArquivo, taxonomia,
}: Readonly<{
  casoId: string;
  p: { id: string; tipo: string; descricao: string | null };
  doc: DocumentoParaConfirmar;
  nomeArquivo: string;
  taxonomia: TaxonomiaTipoDocumento[];
}>) {
  const revisarAction = revisarDocumento.bind(null, casoId);
  const idBase = `confirmar-${p.id}`;
  return (
    <li className="carta p-4">
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

      {/* Cada rótulo aponta para o seu campo (Sonar S6853): o leitor de tela anuncia
          "Tipo de documento" ao entrar no select. Vários cartões na mesma página, então
          o id leva o da pendência. */}
      <form action={revisarAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <input type="hidden" name="documento_id" value={doc.id} />

        <div>
          <label htmlFor={`${idBase}-tipo`} className="block text-xs font-medium text-tinta-600">Tipo de documento</label>
          <select
            id={`${idBase}-tipo`}
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
          <label htmlFor={`${idBase}-entidade`} className="block text-xs font-medium text-tinta-600">Entidade</label>
          <input
            id={`${idBase}-entidade`}
            type="text"
            name="nova_entidade_nome"
            defaultValue={doc.entidade?.razao_social ?? ""}
            placeholder="Razão social"
            className="mt-1 w-full rounded-md border border-tinta-200 px-2.5 py-1.5 text-sm"
          />
        </div>

        <div>
          <label htmlFor={`${idBase}-periodo`} className="block text-xs font-medium text-tinta-600">Período</label>
          <select
            id={`${idBase}-periodo`}
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
          <label htmlFor={`${idBase}-referencia`} className="block text-xs font-medium text-tinta-600">Referência do período</label>
          <input
            id={`${idBase}-referencia`}
            type="text"
            name="novo_periodo_ref"
            defaultValue={doc.periodo?.referencia ?? ""}
            placeholder="ex.: 12M25, 2025"
            className="mt-1 w-full rounded-md border border-tinta-200 px-2.5 py-1.5 text-sm"
          />
        </div>

        <div className="sm:col-span-2">
          <label htmlFor={`${idBase}-motivo`} className="block text-xs font-medium text-tinta-600">Observação (opcional)</label>
          <textarea
            id={`${idBase}-motivo`}
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
}
