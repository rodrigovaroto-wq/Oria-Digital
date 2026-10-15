"use client";

import { useActionState } from "react";
import type { ResultadoPerimetro } from "./actions";
import { CAMPO } from "./Formulario";
import { PARENTESCOS, rotuloDoParentesco } from "@/lib/perimetro";

export type Socio = { id: string; nome: string; documento: string | null };
export type VinculoVigente = { id: string; controlador_a: string; controlador_b: string; parentesco: string; fonte: string; declarado_por: string };
type Acao = (anterior: ResultadoPerimetro, form: FormData) => Promise<ResultadoPerimetro>;

function Saida({ r }: Readonly<{ r: ResultadoPerimetro }>) {
  return r ? <output className={`basis-full text-sm ${r.tom === "ok" ? "text-ok-800" : "text-risco-800"}`}>{r.texto}</output> : null;
}

function Encerrar({ v, acao: encerrar }: Readonly<{ v: VinculoVigente; acao: Acao }>) {
  const [r, acao, pendente] = useActionState<ResultadoPerimetro, FormData>(encerrar, null);
  return (
    <form action={acao} className="flex flex-wrap items-end gap-2">
      <input type="hidden" name="vinculo_id" value={v.id} />
      <label className="block text-xs text-tinta-500">Motivo para encerrar
        <input name="motivo" className={`${CAMPO} block w-56`} />
      </label>
      <button type="submit" className="btn-discreto" disabled={pendente}>{pendente ? "Encerrando…" : "Encerrar vínculo"}</button>
      <Saida r={r} />
    </form>
  );
}

export function SecaoParentesco({ socios, vinculos, vincular, desvincular }: Readonly<{
  socios: Socio[]; vinculos: VinculoVigente[]; vincular: Acao; desvincular: Acao;
}>) {
  const [r, acao, pendente] = useActionState<ResultadoPerimetro, FormData>(vincular, null);
  const nome = (id: string) => socios.find((s) => s.id === id)?.nome ?? id;
  return (
    <section className="carta space-y-4 p-5">
      <h2 className="font-titulo text-xl font-medium text-tinta-900">Sócios e parentesco</h2>
      <p className="text-sm text-tinta-600">
        Parentesco só vale declarado, com a fonte — nunca por sobrenome. Cônjuge, linha reta até 2º grau e irmão unem os
        sócios num mesmo bloco de controle; tio, primo e cunhado ficam de fora. O fecho é transitivo: A–B e B–C juntam A e C.
      </p>
      {socios.length === 0 ? (
        <p className="text-sm text-tinta-600">Nenhum sócio pessoa física registrado neste mandato. Registre-os no cartão da empresa.</p>
      ) : (
        <ul className="space-y-0.5 text-sm text-tinta-800">
          {socios.map((s) => <li key={s.id}>{s.nome}{s.documento ? <span className="text-tinta-500"> ({s.documento})</span> : ""}</li>)}
        </ul>
      )}
      <div className="space-y-3">
        <p className="titulo-secao">Vínculos vigentes</p>
        {vinculos.length === 0 && <p className="text-sm text-tinta-600">Nenhum parentesco declarado: os grupos só se juntam por sócio em comum.</p>}
        {vinculos.map((v) => (
          <div key={v.id} className="space-y-2 rounded border border-tinta-100 p-3">
            <p className="text-sm text-tinta-800">
              {nome(v.controlador_a)} e {nome(v.controlador_b)} — {rotuloDoParentesco(v.parentesco)}
              <span className="text-tinta-500"> · fonte: {v.fonte} · declarado por {v.declarado_por}</span>
            </p>
            <Encerrar v={v} acao={desvincular} />
          </div>
        ))}
      </div>
      {socios.length >= 2 && (
        <form action={acao} className="flex flex-wrap items-end gap-2">
          <label className="block text-xs text-tinta-500">Sócio
            <select name="controlador_a" defaultValue="" className={`${CAMPO} block`}>
              <option value="" disabled>Escolha</option>
              {socios.map((s) => <option key={s.id} value={s.id}>{s.nome}</option>)}
            </select>
          </label>
          <label className="block text-xs text-tinta-500">É … de
            <select name="parentesco" defaultValue="" className={`${CAMPO} block`}>
              <option value="" disabled>Parentesco</option>
              {PARENTESCOS.map((p) => <option key={p.valor} value={p.valor}>{p.rotulo}</option>)}
            </select>
          </label>
          <label className="block text-xs text-tinta-500">Sócio
            <select name="controlador_b" defaultValue="" className={`${CAMPO} block`}>
              <option value="" disabled>Escolha</option>
              {socios.map((s) => <option key={s.id} value={s.id}>{s.nome}</option>)}
            </select>
          </label>
          <label className="block text-xs text-tinta-500">Fonte (obrigatória)
            <input name="fonte" list="fontes-parentesco" placeholder="contrato social" className={`${CAMPO} block w-56`} />
            <datalist id="fontes-parentesco"><option value="contrato social" /><option value="declaração do cliente" /></datalist>
          </label>
          <button type="submit" className="btn-secundario" disabled={pendente}>{pendente ? "Gravando…" : "Declarar parentesco"}</button>
          <Saida r={r} />
        </form>
      )}
    </section>
  );
}
