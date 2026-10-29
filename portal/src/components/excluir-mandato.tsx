"use client";

import { createPortal } from "react-dom";
import { useEffect, useRef, useState } from "react";
import { excluirCaso } from "@/app/casos/[id]/actions";

// O BOTÃO DE EXCLUIR O MANDATO, com a confirmação que o dono pediu.
//
// POR QUE É UM COMPONENTE DE CLIENTE. A confirmação tem de acontecer ANTES da
// requisição sair: uma server action não tem como perguntar "tem certeza?" no
// meio do caminho — quando ela roda, a decisão já foi tomada. Então o diálogo
// vive aqui, e o servidor cuida do resto (trilha e contagem do que se perdeu,
// em `fn_excluir_caso`).
//
// POR QUE NÃO `window.confirm`. Ele funcionaria e é uma linha — mas o texto de
// um `confirm` nativo aparece com o domínio do site em cima ("tratamento-dados…
// diz:"), sem formatação e sem hierarquia. Para uma ação que apaga o mandato
// inteiro, o aviso precisa ser lido, e um diálogo próprio é o que permite pôr o
// nome do caso e a consequência em destaque.
//
// O BOTÃO É PEQUENO E DISCRETO de propósito, e o de CONFIRMAR é o vermelho. A
// ação destrutiva não deve competir em atenção com o trabalho normal da tela;
// ela deve ser encontrável por quem a procura, e não esbarrável por quem não.
export function ExcluirMandato({ casoId, nome }: { casoId: string; nome: string }) {
  const [aberto, setAberto] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const cancelarRef = useRef<HTMLButtonElement>(null);

  // ESC fecha o diálogo mesmo com o foco fora dele. O `onKeyDown` no overlay
  // NUNCA disparava: ao abrir, o foco continuava no botão "Excluir" que abriu
  // o diálogo (irmão do overlay, não ancestral dele), e keydown só propaga por
  // ancestrais — o overlay nunca recebia o evento. Por isso o listener vai no
  // `document`, dentro do efeito que só existe enquanto `aberto` é verdadeiro
  // (cleanup remove ao fechar, senão cada abertura empilha mais um listener).
  // Movemos também o foco para dentro do diálogo (autoFocus em "Cancelar"),
  // que é o passo que faltava para navegação só por teclado: sem ele o Tab
  // ainda começava fora do diálogo.
  useEffect(() => {
    if (!aberto) return;
    const aoTeclar = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !enviando) setAberto(false);
    };
    document.addEventListener("keydown", aoTeclar);
    return () => document.removeEventListener("keydown", aoTeclar);
  }, [aberto, enviando]);

  return (
    <>
      <button
        type="button"
        onClick={() => setAberto(true)}
        title="Excluir este mandato"
        aria-label="Excluir este mandato"
        className="rounded border border-tinta-200 px-2 py-1.5 text-xs font-medium text-tinta-500 hover:border-risco-300 hover:bg-risco-50 hover:text-risco-700"
      >
        Excluir
      </button>

      {/* O DIÁLOGO VAI PARA O <body> (portal). Dentro da página ele herdava os
          contêineres dela: uma linha semitransparente da tabela de Mandatos ou
          qualquer ancestral com filtro o prendiam, e ele aparecia fora da tela ou
          por baixo das linhas seguintes (revisão do PR #265). No <body>, `fixed`
          volta a ser a janela. Só monta depois do clique, então `document` existe. */}
      {aberto && createPortal(
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-fundo-reserva/50 p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="titulo-excluir"
          // Clicar fora fecha — mas só no fundo, não no cartão (senão qualquer
          // clique dentro do diálogo o fecharia no meio da leitura).
          onClick={(e) => { if (e.target === e.currentTarget && !enviando) setAberto(false); }}
        >
          <div className="w-full max-w-md rounded-lg border border-tinta-200 bg-folha p-5 shadow-xl">
            <h2 id="titulo-excluir" className="text-base font-semibold text-tinta-900">
              Após a exclusão todos os dados serão perdidos, você tem certeza que deseja excluir
              esse mandato?
            </h2>
            {/* O NOME DO CASO. Com vários mandatos abertos em abas diferentes, é
                o que impede excluir o certo achando que é o outro. */}
            <p className="mt-2 text-sm text-tinta-600">
              Mandato: <strong className="text-tinta-900">{nome}</strong>
            </p>
            <p className="mt-1 text-sm text-tinta-600">
              Serão apagados os documentos recebidos, as linhas extraídas, as pendências e a
              modelagem deste mandato. Não há como desfazer.
            </p>

            <div className="mt-5 flex justify-end gap-2">
              <button
                type="button"
                ref={cancelarRef}
                autoFocus
                disabled={enviando}
                onClick={() => setAberto(false)}
                className="rounded border border-tinta-200 bg-folha px-3 py-1.5 text-sm font-medium text-tinta-600 hover:bg-tinta-50 disabled:opacity-50"
              >
                Cancelar
              </button>
              <form
                action={async () => {
                  // O estado de envio existe porque a exclusão de um mandato
                  // grande leva alguns segundos (cascade sobre campo_extraido), e
                  // um botão que não responde convida ao segundo clique.
                  setEnviando(true);
                  try {
                    await excluirCaso(casoId);
                  } finally {
                    setEnviando(false);
                  }
                }}
              >
                <button
                  type="submit"
                  disabled={enviando}
                  className="rounded bg-risco-600 px-3 py-1.5 text-sm font-semibold text-papel hover:bg-risco-700 disabled:opacity-50"
                >
                  {enviando ? "Excluindo…" : "Excluir mandato"}
                </button>
              </form>
            </div>
          </div>
        </div>
        , document.body)}
    </>
  );
}
