"use client";

import { useActionState } from "react";
import Link from "next/link";
import { criarMandato, type ResultadoDoPasso1 } from "@/app/casos/novo/actions";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";

// O formulário do passo 1. Só o NOME: é o único dado que o banco guarda hoje na
// criação do caso (`fn_upsert_caso(p_nome)`). Produto e responsável ficam fora
// porque um campo que não grava sugere um dado que o banco não tem (regra 1).
export function NovoMandatoPasso1() {
  const [r, acao, pendente] = useActionState<ResultadoDoPasso1, FormData>(criarMandato, null);
  return (
    <form action={acao} className="space-y-4">
      <div>
        <label htmlFor="mandato" className="mb-1 block text-sm font-medium text-tinta-600">Nome do mandato</label>
        <input
          id="mandato"
          name="mandato"
          type="text"
          required
          autoFocus
          defaultValue={r?.nome ?? ""}
          placeholder="ex.: Reestruturação Grupo X"
          className="w-full rounded border border-tinta-200 px-3 py-2 text-sm"
        />
        <p className="mt-1 text-xs text-tinta-500">
          Use o MESMO nome para enviar arquivos em momentos diferentes e acumulá-los no mesmo mandato (mesmo
          checklist, mesma exportação, mesma reconciliação).
        </p>
      </div>

      {r?.erro && (
        <div role="alert" className="rounded-md border border-risco-300 bg-risco-50 p-4 text-sm text-risco-900">
          <p className="font-medium">{r.erro.titulo}</p>
          <p className="mt-1">{r.erro.explicacao}</p>
          {r.erro.tecnico && <DetalhesTecnicos>{r.erro.tecnico}</DetalhesTecnicos>}
        </div>
      )}

      <div className="flex flex-wrap items-center gap-3">
        <button type="submit" className="btn-primario" disabled={pendente}>
          {pendente ? "Criando…" : "Continuar para os documentos →"}
        </button>
        <Link href="/casos/todos" className="btn-secundario">Cancelar</Link>
      </div>
    </form>
  );
}
