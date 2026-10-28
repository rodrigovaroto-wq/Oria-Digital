"use client";

import { PainelDeErro } from "@/components/painel-de-erro";

// FRONTEIRA DE ERRO DE TODAS AS TELAS DE `casos`.
//
// QUEM CAI AQUI, e não em `[id]/error.tsx`: o que lança no próprio
// `[id]/layout.tsx` — e o menu ⋯ (Fechar/Reabrir/Excluir) mora lá. Um
// `error.tsx` embrulha a PÁGINA do segmento, nunca o layout do mesmo segmento;
// por isso a recusa de Fechar/Excluir (Server Action que lança) chega neste
// arquivo, com a barra e o cabeçalho do portal preservados, em vez da página de
// erro padrão do Next. Ela também embrulha as PÁGINAS `/casos` e
// `/casos/todos`, por isso o texto cobre os dois casos — tela que não carregou
// e ação não confirmada (revisão do PR #265: o texto só falava de ação).
export default function ErroDeCasos({
  error, reset,
}: Readonly<{
  error: Error & { digest?: string };
  reset: () => void;
}>) {
  return (
    <PainelDeErro
      titulo="Algo não deu certo nesta tela"
      orientacao="A tela não carregou, ou a última ação (fechar, reabrir ou excluir um mandato) não foi confirmada. Tente de novo; se você tinha acabado de fazer uma ação, confira o mandato antes de repeti-la. Se continuar falhando, envie o identificador dos detalhes técnicos a quem mantém o portal."
      error={error} reset={reset}
      voltarHref="/casos" voltarRotulo="Voltar ao início"
    />
  );
}
