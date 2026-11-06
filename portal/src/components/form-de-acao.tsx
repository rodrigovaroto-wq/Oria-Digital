"use client";

import { useActionState, useState, type FormEvent, type ReactNode } from "react";
import type { ResultadoDaAcao } from "@/lib/acesso";

// O FORMULÁRIO DE UMA AÇÃO DE CLIQUE QUE PODE SER RECUSADA. A server action devolve `{ erro }` (e não
// lança: em produção o Next redige a mensagem de um erro lançado) e este componente a escreve ao lado
// do botão. Sem ele, `<form action={serverAction}>` descarta o valor devolvido e a recusa do banco —
// "Seu papel não permite esta ação", "aprovação bloqueada" — passa por clique que não fez nada.
// `role="alert"` anuncia a frase ao leitor de tela quando ela aparece.
//
// COM `confirmacao`, o primeiro envio só abre a pergunta; o "sim" dela é que envia (P16: a vistoria de
// 04/11 mediu decisões que travam a aprovação sendo gravadas num toque, sem nada perguntar).
export function FormDeAcao({
  action, children, className, confirmacao,
}: Readonly<{
  action: (formData: FormData) => Promise<ResultadoDaAcao>;
  children: ReactNode;
  className?: string;
  confirmacao?: { pergunta: string; efeito?: string; sim: string };
}>) {
  const [pedindo, setPedindo] = useState(false);
  const [estado, formAction] = useActionState<ResultadoDaAcao, FormData>(
    async (_anterior, formData) => {
      setPedindo(false);
      return action(formData);
    },
    undefined,
  );
  const aoEnviar = (e: FormEvent<HTMLFormElement>) => {
    if (confirmacao && !pedindo) {
      e.preventDefault();
      setPedindo(true);
    }
  };
  return (
    <form action={formAction} onSubmit={aoEnviar} className={className}>
      {children}
      {confirmacao && pedindo && (
        <PedidoDeConfirmacao {...confirmacao} cancelar={() => setPedindo(false)} />
      )}
      {estado?.erro && (
        <p role="alert" className="mt-1 w-full text-xs font-medium text-risco-700">{estado.erro}</p>
      )}
    </form>
  );
}

/** A pergunta antes de gravar: o "sim" é um `submit` do MESMO formulário; "Cancelar" só fecha. */
export function PedidoDeConfirmacao({
  pergunta, efeito, sim, cancelar,
}: Readonly<{ pergunta: string; efeito?: string; sim: string; cancelar: () => void }>) {
  return (
    <div role="alertdialog" aria-label={pergunta} className="mt-2 w-full rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-900">
      <p className="font-semibold">{pergunta}</p>
      {efeito && <p className="mt-1">{efeito}</p>}
      <div className="mt-2 flex flex-wrap gap-2">
        {/* autoFocus: quem abriu a pergunta pelo teclado cai no "sim" e não no fim da página */}
        <button type="submit" autoFocus className="rounded-md bg-risco-700 px-3 py-1.5 text-sm font-semibold text-papel hover:bg-risco-800">
          {sim}
        </button>
        <button type="button" onClick={cancelar} className="btn-secundario">Cancelar</button>
      </div>
    </div>
  );
}
