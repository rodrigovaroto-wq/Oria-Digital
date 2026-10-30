"use client";

import { useActionState, type ReactNode } from "react";
import type { ResultadoDaAcao } from "@/lib/acesso";

// O FORMULÁRIO DE UMA AÇÃO DE CLIQUE QUE PODE SER RECUSADA. A server action devolve `{ erro }` (e não
// lança: em produção o Next redige a mensagem de um erro lançado) e este componente a escreve ao lado
// do botão. Sem ele, `<form action={serverAction}>` descarta o valor devolvido e a recusa do banco —
// "Seu papel não permite esta ação", "aprovação bloqueada" — passa por clique que não fez nada.
// `role="alert"` anuncia a frase ao leitor de tela quando ela aparece.
export function FormDeAcao({
  action, children, className,
}: Readonly<{
  action: (formData: FormData) => Promise<ResultadoDaAcao>;
  children: ReactNode;
  className?: string;
}>) {
  const [estado, formAction] = useActionState<ResultadoDaAcao, FormData>(
    async (_anterior, formData) => action(formData),
    undefined,
  );
  return (
    <form action={formAction} className={className}>
      {children}
      {estado?.erro && (
        <p role="alert" className="mt-1 w-full text-xs font-medium text-risco-700">{estado.erro}</p>
      )}
    </form>
  );
}
