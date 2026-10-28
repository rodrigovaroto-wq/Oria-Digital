"use client";

import { useActionState, useState } from "react";
import { aplicarEmLote, type Resultado } from "./actions";
import { linhaSuja, type EscolhaLinha } from "@/lib/modelagem-lote";

// A SEÇÃO 3 DA MODELAGEM, COM ESTADO PRÓPRIO — e por que ela precisou virar
// componente de cliente.
//
// O RELATO DO DONO, na terceira rodada: "a seção 3 fecha do nada ENQUANTO eu
// estou editando". Não era mais o clique em "aplicar em lote" — era no meio da
// edição, sem submeter nada.
//
// A CAUSA: a página inteira era Server Component e os ~203 seletores de linha
// eram NÃO CONTROLADOS (`defaultValue`). Nesse arranjo, qualquer re-render vindo
// do servidor troca o DOM e leva junto tudo o que estava escolhido e ainda não
// foi salvo — e o scroll volta ao topo. Re-render do servidor acontece muito mais
// do que se imagina: o `revalidatePath` de QUALQUER ação da tela (ativar uma
// premissa no passo 2, por exemplo), o `redirect` que eu mesmo tinha introduzido
// para mostrar o aviso, e o próprio App Router, que rebusca o payload do servidor
// ao reganhar foco na janela ou ao voltar pelo histórico. Trocar de aba e voltar
// bastava.
//
// O CONSERTO, e ele é estrutural, não cosmético:
//
//   • a escolha de cada linha vive em ESTADO DE REACT aqui dentro (`escolhas`),
//     não no DOM. Re-render do servidor atualiza os dados ao redor e o estado
//     local permanece, porque o componente continua na mesma posição da árvore;
//   • as ações não navegam mais: `useActionState` recebe o resultado e a mensagem
//     aparece DENTRO desta seção, ao lado do botão que foi clicado;
//   • `key` estável por seção, para o React nunca remontar o bloco;
//   • a seção não tem, e não deve ganhar, nenhum mecanismo de recolher. Se um dia
//     alguém quiser um `<details>` aqui, o motivo desta linha é: o dono pediu
//     explicitamente que ela fique fixa, e "fechou sozinha" já custou duas
//     rodadas de teste.
//
// FASE 2 (item 21): O ESTADO SUBIU PARA `EditorLinhas.tsx`, e o SALVAR TAMBÉM.
// Havia dois botões "salvar esta seção" por seção (cabeçalho e rodapé) e o aviso de
// "não salvas" por seção; agora as escolhas de TODAS as seções vivem no editor, que
// tem UMA barra de salvamento. Esta seção ficou controlada: recebe `escolhas`/`gravado`
// e avisa `onMudar`. O "aplicar em lote" continua aqui, por seção, porque ele é uma ação
// DA SEÇÃO (grava no banco na hora), não um rascunho a salvar.

export interface LinhaDaSecao {
  chave: string;
  rotulo_norm: string;
  entidade: string | null;
  valor_ultimo: number;
  n_ocorrencias: number;
  papel: "conta" | "subtotal" | "derivado" | "serie_mensal";
  unidade: string | null;
  moeda: string | null;
  documentos: string[] | null;
  sobreposicao_suspeita: boolean;
}

export interface OpcaoPremissa {
  codigo: string;
  nome: string;
}

export const PAPEL_INFO: Record<string, { rotulo: string; curto: string; explica: string; cor: string }> = {
  subtotal: {
    rotulo: "subtotal",
    curto: "soma dos componentes projetados; não recebe premissa",
    explica: "sai no Excel como a SOMA dos componentes projetados — se move sozinho, e por isso "
      + "não recebe premissa (projetá-lo contaria o mesmo dinheiro duas vezes)",
    cor: "bg-info-100 text-info-800",
  },
  serie_mensal: {
    rotulo: "série mensal",
    curto: "alimenta a curva de sazonalidade; não é conta a projetar",
    explica: "alimenta a curva de sazonalidade, derivada do próprio histórico do caso — não é uma "
      + "conta a projetar",
    cor: "bg-serie-100 text-serie-800",
  },
  derivado: {
    rotulo: "derivado",
    curto: "indicador gerencial; projetá-lo divergiria das contas que o compõem",
    explica: "indicador gerencial (resultado de outras contas, não dinheiro) — projetá-lo o faria "
      + "divergir das linhas que o compõem",
    cor: "bg-tinta-200 text-tinta-600",
  },
};

/** O aviso de sobreposição, em texto visível (antes só no `title` do chip). */
export const SOBREPOSICAO_CURTO =
  "Outra linha desta seção tem o mesmo valor e um rótulo mais grosso: projetar as duas dobra a conta. Escolha uma.";

const fmt = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });

const escala = (l: LinhaDaSecao) =>
  [l.unidade === "milhar" ? "R$ mil" : l.unidade === "unidade" ? "R$" : l.unidade,
    l.moeda && l.moeda !== "BRL" ? l.moeda : null].filter(Boolean).join(" ");

export function Aviso({ r }: { r: Resultado }) {
  if (!r) return null;
  return (
    <span
      role="status"
      className={`rounded px-2 py-0.5 text-xs ${
        r.tom === "ok" ? "bg-ok-100 text-ok-900" : "bg-alerta-100 text-alerta-900"
      }`}
    >
      {r.texto}
    </span>
  );
}

export function SecaoLinhas({
  casoId, secao, rotulo, linhas, ativas, sazonais, escolhas, gravado, onMudar, onLoteAplicado,
}: {
  casoId: string;
  /** chave canônica — é o que vai ao banco */
  secao: string;
  /** o nome em português — é o que aparece na tela */
  rotulo: string;
  linhas: LinhaDaSecao[];
  ativas: OpcaoPremissa[];
  sazonais: OpcaoPremissa[];
  /** o que está na tela (rascunho), por rotulo_norm — vem do editor */
  escolhas: Record<string, EscolhaLinha>;
  /** o que o banco tem, por rotulo_norm — base do "só manda o que mudou" */
  gravado: Record<string, EscolhaLinha>;
  onMudar: (rotuloNorm: string, campo: "premissa" | "sazonalidade", valor: string) => void;
  /** o lote é do BANCO: avisa o editor para refletir o que ele gravou */
  onLoteAplicado: (premissa: string) => void;
}) {
  const semSecao = secao === "(sem seção canônica)";
  const contas = linhas.filter((l) => l.papel === "conta");
  const [premissaDoLote, setPremissaDoLote] = useState("");

  const [rLote, actLote, aplicando] = useActionState(
    async (prev: Resultado, fd: FormData) => {
      const r = await aplicarEmLote(casoId, prev, fd);
      if (r?.tom === "ok") onLoteAplicado(String(fd.get("premissa") ?? ""));
      return r;
    }, null as Resultado);

  const vazio: EscolhaLinha = { premissa: "", sazonalidade: "" };
  const pendentes = contas.filter((l) => linhaSuja(escolhas[l.rotulo_norm], gravado[l.rotulo_norm])).length;

  return (
    <div>
      <div className="mb-1 flex flex-wrap items-center gap-2">
        <h3 className="text-xs font-semibold uppercase text-tinta-500">
          {rotulo}{" "}
          <span className="font-normal">
            ({contas.length} conta(s)
            {linhas.length !== contas.length && ` + ${linhas.length - contas.length} não projetável(is)`})
          </span>
        </h3>
        {/* Só o CONTADOR da seção: o salvar é um só, na barra de baixo. */}
        {pendentes > 0 && (
          <span className="chip bg-alerta-100 text-alerta-900">{pendentes} não salva(s)</span>
        )}
        {!semSecao && contas.length > 0 && (
          <form action={actLote} className="flex items-center gap-1">
            <input type="hidden" name="secao_canonica" value={secao} />
            <select
              name="premissa" required value={premissaDoLote}
              aria-label={`Aplicar em lote nesta seção (${rotulo})`}
              onChange={(e) => setPremissaDoLote(e.target.value)}
              className="rounded border border-tinta-200 px-1 py-0.5 text-xs"
            >
              <option value="" disabled>aplicar em lote…</option>
              {ativas.map((a) => <option key={a.codigo} value={a.codigo}>{a.nome}</option>)}
            </select>
            <button
              type="submit" disabled={aplicando}
              className="rounded border border-tinta-200 px-2 py-0.5 text-xs hover:bg-tinta-100 disabled:opacity-50"
            >
              {aplicando ? "aplicando…" : `aplicar às ${contas.length} conta(s)`}
            </button>
            <Aviso r={rLote} />
          </form>
        )}
      </div>

      <div className="overflow-x-auto rounded border border-tinta-200">
        <table className="w-full text-left text-sm">
          {/* CABEÇALHO GRUDADO: numa seção de 60 linhas, rolar até a conta que
              se quer ajustar deixava as três colunas sem nome — e "premissa que
              dirige" e "sazonalidade" são dois seletores parecidos lado a lado.
              Escolher no seletor errado não dá erro nenhum, só projeta diferente. */}
          <thead className="sticky top-0 z-10 bg-tinta-50 text-xs uppercase text-tinta-500 shadow-[0_1px_0_var(--color-tinta-200)]">
            <tr>
              <th className="px-2 py-1">Linha</th>
              <th className="px-2 py-1 text-right">Último real</th>
              <th className="px-2 py-1">Premissa que dirige</th>
              <th className="px-2 py-1">Sazonalidade</th>
            </tr>
          </thead>
          <tbody>
            {linhas.map((l) => {
              const info = PAPEL_INFO[l.papel];
              const e = escolhas[l.rotulo_norm] ?? vazio;
              const g = gravado[l.rotulo_norm] ?? vazio;
              const sujo = linhaSuja(e, g);
              return (
                <tr
                  key={l.rotulo_norm}
                  className={`border-t border-tinta-100 align-top ${sujo ? "bg-alerta-50" : ""}`}
                >
                  <td className="px-2 py-1">
                    <span className={l.papel === "conta" ? "" : "text-tinta-500"}>{l.chave}</span>
                    {info && (
                      <span className={`ml-1 rounded px-1 text-[10px] ${info.cor}`} title={info.explica}>
                        {info.rotulo}
                      </span>
                    )}
                    {l.sobreposicao_suspeita && (
                      <span className="ml-1 rounded bg-alerta-100 px-1 text-[10px] text-alerta-800">
                        possível sobreposição
                      </span>
                    )}
                    {l.sobreposicao_suspeita && (
                      <span className="block text-[11px] text-alerta-900">
                        {SOBREPOSICAO_CURTO}
                      </span>
                    )}
                    <span className="block text-[10px] text-tinta-500">
                      {(l.documentos ?? []).join(" · ")}
                      {l.n_ocorrencias > 1 && ` · ${l.n_ocorrencias} ocorrências`}
                    </span>
                  </td>
                  <td className="px-2 py-1 text-right tabular-nums text-tinta-600">
                    {fmt.format(l.valor_ultimo)}
                    <span className="block text-[10px] text-tinta-500">{escala(l)}</span>
                  </td>
                  {l.papel === "conta" ? (
                    <>
                      <td className="px-2 py-1">
                        <select
                          value={e.premissa}
                          aria-label={`Premissa que dirige: ${l.chave}`}
                          onChange={(ev) => onMudar(l.rotulo_norm, "premissa", ev.target.value)}
                          className="rounded border border-tinta-200 px-1 py-0.5 text-xs"
                        >
                          <option value="">(não projetar)</option>
                          {ativas.map((a) => <option key={a.codigo} value={a.codigo}>{a.nome}</option>)}
                        </select>
                      </td>
                      <td className="px-2 py-1">
                        <select
                          value={e.sazonalidade}
                          aria-label={`Sazonalidade: ${l.chave}`}
                          onChange={(ev) => onMudar(l.rotulo_norm, "sazonalidade", ev.target.value)}
                          className="rounded border border-tinta-200 px-1 py-0.5 text-xs"
                          disabled={sazonais.length === 0}
                        >
                          <option value="">(sem sazonalidade)</option>
                          {sazonais.map((a) => <option key={a.codigo} value={a.codigo}>{a.nome}</option>)}
                        </select>
                      </td>
                    </>
                  ) : (
                    // Sem seletor, com o DESTINO escrito: se a linha simplesmente
                    // não tivesse controle, o analista procuraria o defeito na tela.
                    <td colSpan={2} className="px-2 py-1 text-xs text-tinta-500">
                      {info?.explica}
                    </td>
                  )}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
