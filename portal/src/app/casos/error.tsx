"use client";

import { PainelDeErro } from "@/components/painel-de-erro";

// FRONTEIRA DE ERRO DE TODAS AS TELAS DE `casos`.
//
// QUEM CAI AQUI, e não em `[id]/error.tsx`: o que lança no próprio
// `[id]/layout.tsx` — e o menu ⋯ (Fechar/Reabrir/Excluir) mora lá. Um
// `error.tsx` embrulha a PÁGINA do segmento, nunca o layout do mesmo segmento;
// por isso a recusa de Fechar/Excluir (Server Action que lança) chega neste
// arquivo, com a barra e o cabeçalho do portal preservados, em vez da página de
// erro padrão do Next.
export default function ErroDeCasos({
  error, reset,
}: Readonly<{
  error: Error & { digest?: string };
  reset: () => void;
}>) {
  return (
    <PainelDeErro
      titulo="Não foi possível concluir esta ação"
      orientacao="A ação não foi confirmada. Confira o estado do mandato na lista antes de repetir; se continuar falhando, envie o identificador dos detalhes técnicos a quem mantém o portal."
      error={error} reset={reset}
      voltarHref="/casos" voltarRotulo="Voltar ao início"
    />
  );
}
