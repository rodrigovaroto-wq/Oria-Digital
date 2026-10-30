"use client";

import { useActionState } from "react";
import { alocar, definirPapel, desalocar, type ResultadoEquipe } from "@/app/administracao/equipe/actions";
import { PAPEIS, ROTULO_DO_PAPEL, type Papel } from "@/lib/acesso";

// OS FORMULÁRIOS DA EQUIPE (só o Sócio os vê; o banco recusa os demais mesmo assim). Cada um é uma
// `useActionState` sobre a ação de `administracao/equipe/actions.ts`, e o resultado aparece AO LADO do
// botão — inclusive a recusa do banco, que é uma resposta esperada ("não deixa tirar o último Sócio").
const CAMPO = "rounded-md border border-tinta-200 bg-folha px-2.5 py-1.5 text-sm text-tinta-900";

function Resultado({ r }: Readonly<{ r: ResultadoEquipe }>) {
  if (!r) return null;
  return (
    <span role="status" className={`text-xs ${r.tom === "ok" ? "text-ok-800" : "font-medium text-risco-800"}`}>
      {r.texto}
    </span>
  );
}

export function SeletorDePapel({
  usuarioId, papel, motivoTravado,
}: Readonly<{ usuarioId: string; papel: Papel; motivoTravado: string | null }>) {
  const [r, acao, pendente] = useActionState<ResultadoEquipe, FormData>(definirPapel, null);
  const travado = motivoTravado !== null;
  return (
    <form action={acao} className="flex flex-wrap items-center gap-2">
      <input type="hidden" name="usuario_id" value={usuarioId} />
      <select name="papel" defaultValue={papel} disabled={travado || pendente} aria-label="Papel" className={CAMPO}>
        {PAPEIS.map((p) => <option key={p} value={p}>{ROTULO_DO_PAPEL[p]}</option>)}
        <option value="nenhum">Retirar o acesso</option>
      </select>
      <button type="submit" className="btn-secundario" disabled={travado || pendente}>
        {pendente ? "Salvando…" : "Salvar"}
      </button>
      {motivoTravado && <span className="text-xs text-tinta-600">{motivoTravado}</span>}
      <Resultado r={r} />
    </form>
  );
}

/** O chip de um mandato alocado, com o botão de retirar. */
export function MandatoAlocado({
  casoId, usuarioId, nome,
}: Readonly<{ casoId: string; usuarioId: string; nome: string }>) {
  const [r, acao, pendente] = useActionState<ResultadoEquipe, FormData>(desalocar, null);
  return (
    <form action={acao} className="inline-flex flex-wrap items-center gap-1.5">
      <input type="hidden" name="caso_id" value={casoId} />
      <input type="hidden" name="usuario_id" value={usuarioId} />
      <span className="chip bg-tinta-100 text-tinta-800">
        {nome}
        <button
          type="submit"
          disabled={pendente}
          aria-label={`Retirar a alocação em ${nome}`}
          className="ml-1.5 rounded px-1 text-tinta-500 hover:bg-tinta-200 hover:text-tinta-900"
        >
          ✕
        </button>
      </span>
      <Resultado r={r} />
    </form>
  );
}

/** Aloca UMA pessoa (fixa) em um mandato escolhido — a linha da tela de equipe. */
export function AlocarEmMandato({
  usuarioId, mandatos,
}: Readonly<{ usuarioId: string; mandatos: Array<{ id: string; nome: string; fechado: boolean }> }>) {
  const [r, acao, pendente] = useActionState<ResultadoEquipe, FormData>(alocar, null);
  if (mandatos.length === 0) return <p className="text-xs text-tinta-500">Já está em todos os mandatos.</p>;
  return (
    <form action={acao} className="flex flex-wrap items-center gap-2">
      <input type="hidden" name="usuario_id" value={usuarioId} />
      <select name="caso_id" defaultValue="" aria-label="Alocar em mandato" required className={`${CAMPO} max-w-[16rem]`}>
        <option value="" disabled>Alocar em…</option>
        {mandatos.map((m) => <option key={m.id} value={m.id}>{m.nome}{m.fechado ? " (fechado)" : ""}</option>)}
      </select>
      <button type="submit" className="btn-secundario" disabled={pendente}>{pendente ? "Alocando…" : "Alocar"}</button>
      <Resultado r={r} />
    </form>
  );
}

/** Aloca UMA pessoa escolhida em um mandato fixo — o bloco "Equipe do mandato". */
export function AlocarPessoa({
  casoId, pessoas,
}: Readonly<{ casoId: string; pessoas: Array<{ usuario_id: string; rotulo: string; papel: Papel }> }>) {
  const [r, acao, pendente] = useActionState<ResultadoEquipe, FormData>(alocar, null);
  if (pessoas.length === 0) return null;
  return (
    <form action={acao} className="flex flex-wrap items-center gap-2">
      <input type="hidden" name="caso_id" value={casoId} />
      <select name="usuario_id" defaultValue="" aria-label="Alocar pessoa" required className={`${CAMPO} max-w-[18rem]`}>
        <option value="" disabled>Alocar alguém…</option>
        {pessoas.map((p) => <option key={p.usuario_id} value={p.usuario_id}>{p.rotulo} — {ROTULO_DO_PAPEL[p.papel]}</option>)}
      </select>
      <button type="submit" className="btn-secundario" disabled={pendente}>{pendente ? "Alocando…" : "Alocar"}</button>
      <Resultado r={r} />
    </form>
  );
}

/** Dá papel a UMA pessoa da lista "Aguardando liberação" (o id vai escondido: ninguém cola UUID). */
export function LiberarMembro({ usuarioId, rotulo }: Readonly<{ usuarioId: string; rotulo: string }>) {
  const [r, acao, pendente] = useActionState<ResultadoEquipe, FormData>(definirPapel, null);
  return (
    <form action={acao} className="flex flex-wrap items-center gap-2">
      <input type="hidden" name="usuario_id" value={usuarioId} />
      <select name="papel" defaultValue="leitura" aria-label={`Papel de ${rotulo}`} className={CAMPO}>
        {PAPEIS.map((p) => <option key={p} value={p}>{ROTULO_DO_PAPEL[p]}</option>)}
      </select>
      <button type="submit" className="btn-secundario" disabled={pendente}>{pendente ? "Liberando…" : "Definir papel"}</button>
      <Resultado r={r} />
    </form>
  );
}

/**
 * Dá papel a quem existe no Auth e AINDA NÃO tem, pelo código completo (UUID de Authentication › Users).
 * É o MODO ANTIGO: só aparece quando o banco não tem `fn_membros_da_equipe` e, portanto, a lista
 * "Aguardando liberação" não pode ser mostrada. Com a função, `LiberarMembro` a substitui.
 */
export function LiberarPorCodigo() {
  const [r, acao, pendente] = useActionState<ResultadoEquipe, FormData>(definirPapel, null);
  return (
    <form action={acao} className="flex flex-wrap items-end gap-2">
      <label className="flex flex-col gap-1 text-xs text-tinta-600">
        <span>Código do usuário (UUID)</span>
        <input
          name="usuario_id" required spellCheck={false} autoComplete="off" placeholder="00000000-0000-0000-0000-000000000000"
          className={`${CAMPO} w-80 max-w-full font-dado`}
        />
      </label>
      <label className="flex flex-col gap-1 text-xs text-tinta-600">
        <span>Papel</span>
        <select name="papel" defaultValue="leitura" className={CAMPO}>
          {PAPEIS.map((p) => <option key={p} value={p}>{ROTULO_DO_PAPEL[p]}</option>)}
        </select>
      </label>
      <button type="submit" className="btn-secundario" disabled={pendente}>{pendente ? "Liberando…" : "Liberar acesso"}</button>
      <Resultado r={r} />
    </form>
  );
}
