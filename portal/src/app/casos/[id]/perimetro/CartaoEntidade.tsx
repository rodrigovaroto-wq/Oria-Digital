"use client";

import Link from "next/link";
import { Formulario, CAMPO } from "./Formulario";
import type { AcoesPerimetro } from "./actions";
import { ESCOPO_PADRAO, FORMAS, PAPEIS, formatarCnpj, traduzirFalta } from "@/lib/perimetro";

export type Controlador = { controlador_id: string; nome: string; tipo_pessoa: string; documento: string | null; percentual: number | null };
export type EntidadeSituacao = {
  entidade_id: string; razao_social: string; cnpj: string | null; fantasma: boolean;
  papel_no_grupo: string | null; forma_de_controle: string; controladora_id: string | null;
  percentual_participacao: number | null; escopos_vigentes: string[]; controladores: Controlador[];
  pendencias_abertas: string[]; falta: string[]; pronta: boolean;
};

const Rotulo = ({ t, children }: Readonly<{ t: string; children: React.ReactNode }>) => (
  <label className="block text-xs text-tinta-500">{t}{children}</label>
);

export function CartaoEntidade({ e, todas, existentes, hoje, acoes, casoId }: Readonly<{
  e: EntidadeSituacao; todas: Array<{ entidade_id: string; razao_social: string }>;
  existentes: Array<{ id: string; nome: string }>; hoje: string; acoes: AcoesPerimetro; casoId: string;
}>) {
  const combinado = e.escopos_vigentes.includes(ESCOPO_PADRAO);
  const outrosEscopos = e.escopos_vigentes.filter((s) => s !== ESCOPO_PADRAO);
  const ligados = new Set(e.controladores.map((c) => c.controlador_id));
  return (
    <section className="carta space-y-4 p-5" aria-label={e.razao_social}>
      <header className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h3 className="font-titulo text-lg font-medium text-tinta-900">{e.razao_social}</h3>
          <p className="font-dado text-xs text-tinta-500">{formatarCnpj(e.cnpj)}</p>
        </div>
        <span className={`chip ${e.fantasma ? "bg-risco-100 text-risco-900" : e.pronta ? "bg-ok-100 text-ok-900" : "bg-alerta-100 text-alerta-900"}`}>
          {e.fantasma ? "Entidade fantasma" : e.pronta ? "Pronta" : "Falta algo"}
        </span>
      </header>

      {e.falta.length > 0 && (
        <ul className="list-disc space-y-1 pl-5 text-sm text-alerta-900">
          {e.falta.map((f) => <li key={f}>{traduzirFalta(f)}</li>)}
        </ul>
      )}

      {e.fantasma ? (
        <p className="text-sm text-tinta-600">
          Os documentos atribuídos a este nome ficam fora do book de qualquer empresa real. Funda esta entidade com a empresa
          correta ou descarte-a na <Link className="underline" href={`/casos/${casoId}`}>tela de pendências do mandato</Link>.
          Papel, controle e escopo só fazem sentido depois dessa decisão.
        </p>
      ) : (
        <div className="grid gap-4 md:grid-cols-2">
          <Formulario acao={acoes.papel} entidadeId={e.entidade_id} botao="Gravar papel">
            <Rotulo t="Papel no grupo">
              <select name="papel" defaultValue={e.papel_no_grupo ?? ""} className={`${CAMPO} block`}>
                <option value="" disabled>Não definido</option>
                {PAPEIS.map((p) => <option key={p.valor} value={p.valor}>{p.rotulo}</option>)}
              </select>
            </Rotulo>
          </Formulario>

          <Formulario acao={acoes.forma} entidadeId={e.entidade_id} botao="Gravar forma">
            <Rotulo t="Forma de controle">
              <select name="forma" defaultValue={e.forma_de_controle} className={`${CAMPO} block`}>
                {FORMAS.map((f) => <option key={f.valor} value={f.valor}>{f.rotulo}</option>)}
              </select>
            </Rotulo>
          </Formulario>

          <div className="space-y-2 md:col-span-2">
            <p className="titulo-secao">Escopo</p>
            <p className="text-sm text-tinta-600">
              {e.escopos_vigentes.length === 0
                ? "Sem escopo vigente: o sistema não afirma que esta empresa entra no combinado."
                : `Vigente: ${e.escopos_vigentes.join(", ")}.`}
              {outrosEscopos.length > 0 && " (Escopos além de “combinado” são texto livre no banco.)"}
            </p>
            {combinado ? (
              <Formulario acao={acoes.escopoEncerrar} entidadeId={e.entidade_id} botao="Tirar do combinado">
                <input type="hidden" name="escopo" value={ESCOPO_PADRAO} />
                <Rotulo t="Último dia no combinado">
                  <input type="date" name="data" defaultValue={hoje} className={`${CAMPO} block`} />
                </Rotulo>
              </Formulario>
            ) : (
              <Formulario acao={acoes.escopoDefinir} entidadeId={e.entidade_id} botao="Incluir no combinado">
                <input type="hidden" name="escopo" value={ESCOPO_PADRAO} />
                <Rotulo t="Desde">
                  <input type="date" name="data" defaultValue={hoje} className={`${CAMPO} block`} />
                </Rotulo>
              </Formulario>
            )}
          </div>

          <div className="space-y-2">
            <p className="titulo-secao">Controladora (outra empresa do caso)</p>
            <Formulario acao={acoes.participacao} entidadeId={e.entidade_id} botao="Gravar controladora">
              <Rotulo t="Controladora">
                <select name="controladora_id" defaultValue={e.controladora_id ?? ""} className={`${CAMPO} block`}>
                  <option value="">Nenhuma</option>
                  {todas.filter((t) => t.entidade_id !== e.entidade_id)
                    .map((t) => <option key={t.entidade_id} value={t.entidade_id}>{t.razao_social}</option>)}
                </select>
              </Rotulo>
              <Rotulo t="%">
                <input name="percentual" inputMode="decimal" defaultValue={e.percentual_participacao ?? ""} className={`${CAMPO} block w-20`} />
              </Rotulo>
            </Formulario>
            {e.forma_de_controle === "controlada_por_entidade" && !e.controladora_id && (
              <p className="text-xs text-alerta-900">Forma “controlada por outra empresa” sem controladora escolhida.</p>
            )}
          </div>

          <div className="space-y-2">
            <p className="titulo-secao">Sócios / controladores</p>
            {e.controladores.length === 0 ? (
              <p className="text-sm text-tinta-600">Nenhum registrado.</p>
            ) : (
              <ul className="space-y-0.5 text-sm text-tinta-800">
                {e.controladores.map((c) => (
                  <li key={c.controlador_id}>
                    {c.nome} <span className="text-tinta-500">({c.tipo_pessoa === "fisica" ? "PF" : "PJ"}{c.documento ? ` ${c.documento}` : ""})</span>
                    {" — "}{c.percentual === null ? "percentual não informado" : `${c.percentual}%`}
                  </li>
                ))}
              </ul>
            )}
            <Formulario acao={acoes.controlador} entidadeId={e.entidade_id} botao="Registrar sócio">
              <Rotulo t="Nome"><input name="nome" className={`${CAMPO} block`} /></Rotulo>
              <Rotulo t="CPF/CNPJ (opcional)"><input name="documento" className={`${CAMPO} block w-40`} /></Rotulo>
              <Rotulo t="Tipo">
                <select name="tipo_pessoa" defaultValue="fisica" className={`${CAMPO} block`}>
                  <option value="fisica">Pessoa física</option>
                  <option value="juridica">Pessoa jurídica</option>
                </select>
              </Rotulo>
              <Rotulo t="%"><input name="percentual" inputMode="decimal" className={`${CAMPO} block w-20`} /></Rotulo>
            </Formulario>
            {existentes.some((x) => !ligados.has(x.id)) && (
              <Formulario acao={acoes.vinculo} entidadeId={e.entidade_id} botao="Vincular existente">
                <Rotulo t="Já registrado no caso">
                  <select name="controlador_id" defaultValue="" className={`${CAMPO} block`}>
                    <option value="" disabled>Escolha</option>
                    {existentes.filter((x) => !ligados.has(x.id)).map((x) => <option key={x.id} value={x.id}>{x.nome}</option>)}
                  </select>
                </Rotulo>
                <Rotulo t="%"><input name="percentual" inputMode="decimal" className={`${CAMPO} block w-20`} /></Rotulo>
              </Formulario>
            )}
          </div>
        </div>
      )}
    </section>
  );
}
