"use client";

import Link from "next/link";

// O CORPO ÚNICO DAS FRONTEIRAS DE ERRO (`error.tsx` de casos, do mandato e da
// modelagem). Antes de 06 só a modelagem tinha fronteira; o resto caía na página
// de erro padrão do Next, sem a marca e sem caminho de volta — e uma ação de
// Fechar/Excluir recusada (Server Action que lança) era um desses casos.
//
// O TEXTO TÉCNICO NUNCA FICA NO CORPO. Em produção o Next redige `error.message`
// do servidor (vem genérico) e o que acha a linha no log é o `digest`; quem lê o
// corpo é o analista, que precisa saber o que fazer, não o nome da exceção. Fica
// num <details> fechado para quem for abrir chamado.
//
// NÃO AFIRMA SUCESSO NEM ESCONDE A FALHA (regra 1): o título diz que NÃO
// concluiu, e a frase seguinte diz o que verificar antes de repetir — porque
// numa ação com efeito (excluir, fechar) "tentar de novo" sem conferir o estado
// pode repetir algo que já tinha valido.
export function PainelDeErro({
  titulo, orientacao, error, reset, voltarHref, voltarRotulo,
}: Readonly<{
  titulo: string;
  orientacao: string;
  error: Error & { digest?: string };
  reset: () => void;
  voltarHref: string;
  voltarRotulo: string;
}>) {
  return (
    <div className="mx-auto max-w-2xl py-6">
      <div role="alert" className="rounded-md border border-risco-300 bg-risco-50 p-5">
        <h2 className="font-titulo text-lg font-medium text-risco-900">{titulo}</h2>
        <p className="mt-2 text-sm text-risco-900">{orientacao}</p>
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <button type="button" onClick={reset} className="btn-primario">
            Tentar de novo
          </button>
          <Link href={voltarHref} className="btn-secundario">{voltarRotulo}</Link>
        </div>
        <details className="mt-4 text-xs text-risco-900">
          <summary className="cursor-pointer text-risco-800">Detalhes técnicos</summary>
          <div className="mt-2 space-y-1 rounded bg-folha p-3 font-mono">
            {error.message && <p className="break-words">{error.message}</p>}
            {error.digest && <p>identificador da ocorrência: {error.digest}</p>}
            {!error.message && !error.digest && <p>Sem detalhe disponível.</p>}
          </div>
        </details>
      </div>
    </div>
  );
}
