"use client";

import { createPortal } from "react-dom";
import { useState } from "react";
import { fecharCaso, reabrirCaso } from "@/app/casos/[id]/actions";

// FECHAR É A AÇÃO DO DIA A DIA; excluir é a exceção.
//
// POR QUE ELE FICA AO LADO DO "EXCLUIR", e não em outro canto: quem chega com a
// intenção de "tirar este mandato da minha frente" vai procurar o botão
// vermelho. Ter o fechar do lado — com a frase que diz que nada se perde — é o
// que impede que a intenção certa seja resolvida pela ação errada. É a mesma
// razão de o `excluir` continuar existindo: esconder a ação destrutiva empurra
// quem precisa dela para editar a tabela por fora, sem trilha.
//
// O MOTIVO É OPCIONAL. Campo obrigatório em ação reversível vira "asdf": quem
// tem motivo escreve, quem não tem clica. E, ao contrário da exclusão, aqui não
// há o que reconstituir — o mandato inteiro continua lá para ser consultado.
export function FecharMandato({
  casoId,
  nome,
  fechado,
}: {
  casoId: string;
  nome: string;
  fechado: boolean;
}) {
  const [aberto, setAberto] = useState(false);
  const [enviando, setEnviando] = useState(false);

  if (fechado) {
    return (
      <form
        action={async () => {
          setEnviando(true);
          await reabrirCaso(casoId);
          setEnviando(false);
        }}
      >
        <button
          type="submit"
          disabled={enviando}
          className="rounded-md border border-tinta-200 bg-folha px-2.5 py-1 text-xs font-medium
                     text-tinta-700 transition-colors hover:border-acento-600 hover:text-acento-700
                     disabled:opacity-50"
        >
          {enviando ? "Reabrindo…" : "Reabrir"}
        </button>
      </form>
    );
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setAberto(true)}
        title="Fechar este mandato (o dado continua guardado)"
        className="rounded-md border border-tinta-200 bg-folha px-2.5 py-1 text-xs font-medium
                   text-tinta-700 transition-colors hover:border-tinta-400 hover:bg-tinta-50"
      >
        Fechar
      </button>

      {/* O DIÁLOGO VAI PARA O <body> (portal). Dentro da página ele herdava os
          contêineres dela: uma linha semitransparente da tabela de Mandatos ou
          qualquer ancestral com filtro o prendiam, e ele aparecia fora da tela ou
          por baixo das linhas seguintes (revisão do PR #265). No <body>, `fixed`
          volta a ser a janela. Só monta depois do clique, então `document` existe. */}
      {aberto && createPortal(
        <div
          role="dialog"
          aria-modal
          aria-label="Fechar mandato"
          className="fixed inset-0 z-50 flex items-center justify-center bg-fundo-reserva/40 p-4"
        >
          <div className="w-full max-w-md rounded-xl border border-tinta-200 bg-folha p-5 shadow-xl">
            <h2 className="text-sm font-semibold text-tinta-900">Fechar “{nome}”?</h2>
            <p className="mt-1.5 text-sm text-tinta-600">
              O mandato sai da lista de ativos e da barra lateral. <strong>Nada é apagado</strong> —
              documentos, linhas extraídas, pendências e a trilha continuam disponíveis, e você pode
              reabrir a qualquer momento.
            </p>

            <form
              action={async (formData: FormData) => {
                setEnviando(true);
                await fecharCaso(casoId, formData);
                setEnviando(false);
                setAberto(false);
              }}
              className="mt-4 space-y-3"
            >
              <div>
                <label htmlFor={`motivo-${casoId}`} className="block text-xs font-medium text-tinta-600">
                  Motivo (opcional)
                </label>
                <input
                  id={`motivo-${casoId}`}
                  name="motivo"
                  type="text"
                  placeholder="ex.: operação não aconteceu"
                  className="mt-1 w-full rounded-md border border-tinta-200 px-2.5 py-1.5 text-sm
                             placeholder:text-tinta-400"
                />
              </div>
              <div className="flex items-center justify-end gap-2">
                <button
                  type="button"
                  onClick={() => setAberto(false)}
                  className="btn-secundario"
                  disabled={enviando}
                >
                  Cancelar
                </button>
                <button type="submit" className="btn-primario" disabled={enviando}>
                  {enviando ? "Fechando…" : "Fechar mandato"}
                </button>
              </div>
            </form>
          </div>
        </div>
        , document.body)}
    </>
  );
}
