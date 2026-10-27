"use client";

import { useParams } from "next/navigation";
import { PainelDeErro } from "@/components/painel-de-erro";

// FRONTEIRA DE ERRO DA TELA DE MODELAGEM.
//
// POR QUE ELA PRECISOU EXISTIR. Sem um `error.tsx` na rota, qualquer exceção
// lançada por uma Server Action derruba a subárvore inteira: na rodada de
// 04/08/2026 o analista clicou em "aplicar em lote" e a seção 3 simplesmente
// desapareceu da página — sem mensagem, sem pista, sem caminho de volta. Ele
// levou o problema para a mesa achando que era a modelagem que estava errada.
//
// As RECUSAS esperadas (subtotal não recebe premissa, premissa não ativa, lote
// vazio) não chegam mais aqui: elas voltam pela URL e viram aviso na própria tela
// (`voltarComAviso`, em actions.ts). O que sobra para esta fronteira é o
// inesperado — a conexão que caiu, a função que não existe no banco porque a
// migration não foi aplicada. Para esses, a única coisa honesta a dizer é que
// falhou, e dar o caminho de volta.
//
// Em produção o Next REDIGE a mensagem de erro do servidor: `error.message` vem
// genérico e o que identifica a ocorrência é o `digest`. Por isso o digest é
// mostrado (nos detalhes técnicos) — é o que permite achar a linha no log da
// Vercel. O visual e o texto foram alinhados aos outros `error.tsx` (item 06).
export default function ErroModelagem({
  error, reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  const { id } = useParams<{ id: string }>();
  return (
    <PainelDeErro
      titulo="A Modelagem não carregou ou falhou ao processar esta ação"
      orientacao="O que já estava salvo continua salvo. Tente de novo — se repetir, avise o administrador do sistema."
      error={error} reset={reset}
      voltarHref={`/casos/${id}`} voltarRotulo="Voltar à Visão geral"
    />
  );
}
