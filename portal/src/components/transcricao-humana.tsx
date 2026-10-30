"use client";

import { ZonaDeEscrita } from "@/components/acesso-na-tela";
import { useState } from "react";
import {
  importarTranscricao,
  type ResultadoImportacao,
} from "@/app/casos/[id]/documentos/[docId]/actions";

// A SAÍDA DO GATE DE CAPTURA, na tela: baixar a planilha, digitar, reenviar.
//
// QUANDO ESTE BLOCO APARECE. Quando o arquivo não se lê (legibilidade diferente de
// `ok`) ou quando a extração não trouxe linha nenhuma. Nos dois casos o documento
// está parado: o Portão 1 vai cobrá-lo e não há número para dar. Fora desses dois
// casos o bloco NÃO aparece — e isso é deliberado. Transcrição humana grava linha
// aceita sem passar por guarda de extração nenhuma; oferecê-la ao lado de uma
// extração que funcionou seria oferecer um caminho mais curto para "resolver" uma
// divergência incômoda: digitar o número que fecha.
//
// POR QUE O AVISO DE QUE ISTO CRIA UMA VERSÃO NOVA. Quem clica espera "corrigir o
// documento". O que acontece é outra coisa: nasce uma `documento_versao` nova
// (doutrina da 0026), a anterior fica preservada com suas zero linhas contando por
// que houve transcrição, e as linhas digitadas entram JÁ ACEITAS com o nome de quem
// digitou. Isso precisa estar escrito antes do clique, não descoberto depois.

export function TranscricaoHumana({
  casoId,
  docId,
  motivo,
  somenteLeitura = false,
}: {
  casoId: string;
  docId: string;
  /** Papel sem escrita neste mandato: baixar a planilha continua, importar fica desabilitado. */
  somenteLeitura?: boolean;
  /** Por que o bloco está aparecendo — ilegível, ou zero linhas extraídas. */
  motivo: "ilegivel" | "sem_linhas";
}) {
  const [resultado, setResultado] = useState<ResultadoImportacao | null>(null);
  const [enviando, setEnviando] = useState(false);

  return (
    <section className="rounded border border-tinta-300 bg-tinta-50 p-4">
      <h2 className="text-sm font-semibold text-tinta-700">Transcrição humana assistida</h2>
      <p className="mt-1 text-sm text-tinta-600">
        {motivo === "ilegivel"
          ? "Este arquivo não se lê pela máquina. "
          : "A extração não trouxe nenhuma linha deste arquivo. "}
        Se o cliente não tem outra via, o caminho é digitar o que está no papel: baixe a
        planilha, transcreva e reenvie aqui.
      </p>

      {/* O QUE VAI ACONTECER, ANTES DO CLIQUE. Ver o cabeçalho deste arquivo. */}
      <ul className="mt-2 list-disc space-y-0.5 pl-5 text-xs text-tinta-500">
        <li>
          As linhas digitadas entram <strong>já aceitas</strong>, com o seu nome — não passam
          pelas guardas de extração, que existem para pegar alucinação de modelo e não têm o
          que fazer com o que uma pessoa escreveu.
        </li>
        <li>
          Nasce uma <strong>versão nova</strong> deste documento. A versão ilegível fica
          guardada, com suas zero linhas, contando por que houve transcrição.
        </li>
        <li>
          Elas ficam <strong>fora da medição da extração</strong>: acerto de máquina medido
          contra linha digitada por humano não mediria nada.
        </li>
      </ul>

      <div className="mt-3 flex flex-wrap items-center gap-3">
        <a
          href={`/casos/${casoId}/documentos/${docId}/transcricao`}
          className="rounded border border-tinta-300 bg-folha px-3 py-1.5 text-sm font-medium text-tinta-700 hover:bg-tinta-100"
        >
          Baixar planilha
        </a>
        <span className="text-xs text-tinta-500">
          A planilha já vem com as linhas que o sistema vai cobrar deste tipo de documento.
        </span>
      </div>

      <ZonaDeEscrita pode={!somenteLeitura}>
      <form
        className="mt-3 space-y-2 border-t border-tinta-200 pt-3"
        action={async (formData) => {
          setEnviando(true);
          setResultado(null);
          try {
            setResultado(await importarTranscricao(casoId, docId, formData));
          } finally {
            setEnviando(false);
          }
        }}
      >
        <div className="flex flex-wrap items-center gap-2">
          <input
            type="file"
            name="planilha"
            accept=".xlsx"
            required
            aria-label="Planilha preenchida"
            className="text-sm"
          />
          <input
            type="text"
            name="motivo"
            placeholder="Por que houve transcrição (opcional)"
            className="w-64 rounded border border-tinta-300 bg-folha px-2 py-1 text-sm"
          />
          <button
            type="submit"
            disabled={enviando}
            className="rounded bg-tinta-900 px-3 py-1.5 text-sm font-medium text-papel disabled:opacity-50"
          >
            {enviando ? "importando…" : "Importar transcrição"}
          </button>
        </div>
      </form>
      </ZonaDeEscrita>

      {/* A RECUSA É LIDA E MOSTRADA COM PALAVRA. Ela não é ruído de validação: o
          texto diz o que fazer com o arquivo que a pessoa tem na mão — e o caso mais
          importante ("esta planilha é de outro documento") só é evitável se ela ler. */}
      {resultado && !resultado.ok && (
        <p className="mt-3 rounded border border-risco-300 bg-risco-50 px-3 py-2 text-sm text-risco-800">
          {resultado.erro}
        </p>
      )}
      {resultado?.ok && (
        <p className="mt-3 rounded border border-ok-200 bg-ok-50 px-3 py-2 text-sm text-ok-800">
          ✓ {resultado.linhas} linha(s) transcritas na versão {resultado.n_versao}.
          {resultado.pendencia_resolvida
            ? " A pendência de arquivo ilegível foi resolvida com o seu nome."
            : ""}{" "}
          Recarregue a página para ver as linhas.
        </p>
      )}
    </section>
  );
}
