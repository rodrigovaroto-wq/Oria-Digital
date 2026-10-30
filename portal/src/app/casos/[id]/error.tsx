"use client";

import { useParams } from "next/navigation";
import { PainelDeErro } from "@/components/painel-de-erro";

// Fronteira das SUBTELAS do mandato: roda dentro de `[id]/layout.tsx`, então o
// cabeçalho e as abas continuam na tela e o analista troca de aba sem recarregar.
export default function ErroDaTela({
  error, reset,
}: Readonly<{
  error: Error & { digest?: string };
  reset: () => void;
}>) {
  const { id } = useParams<{ id: string }>();
  return (
    <PainelDeErro
      titulo="Esta tela não carregou"
      orientacao="Nada foi alterado no mandato. Tente de novo; se persistir, volte à Visão geral ou envie o identificador dos detalhes técnicos a quem mantém o portal."
      error={error} reset={reset}
      voltarHref={`/casos/${id}`} voltarRotulo="Voltar à Visão geral"
    />
  );
}
