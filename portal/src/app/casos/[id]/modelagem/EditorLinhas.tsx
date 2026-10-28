"use client";

import { useEffect, useState } from "react";
import { salvarSecao } from "./actions";
import {
  Aviso, PAPEL_INFO, SecaoLinhas, SOBREPOSICAO_CURTO,
  type LinhaDaSecao, type OpcaoPremissa,
} from "./SecaoLinhas";
import {
  formDataDoLote, lotesPendentes, promoverGravado, resumirSalvamento, totalPendente,
  type EscolhaLinha, type EscolhasPorSecao, type ResultadoDaSecao, type ResumoDoSalvamento,
} from "@/lib/modelagem-lote";

// O EDITOR DA SEÇÃO 3: o estado de TODAS as seções num lugar só, e UM salvamento.
//
// ANTES: cada `SecaoLinhas` tinha o próprio estado e DOIS botões "salvar esta seção" (cabeçalho
// e rodapé). Com 8 a 12 seções, "salvei tudo?" exigia conferir cada uma. AGORA: uma barra
// `sticky bottom-3` — dentro da folha, sem `backdrop-filter` (o `.vidro-folha` não o tem de
// propósito: ver globals.css) — que só existe quando há o que salvar e manda ao banco
// exatamente as linhas que mudaram, seção por seção, na MESMA ação `salvarSecao` de antes.
//
// O ESTADO continua sendo de React e não do DOM, pelo mesmo motivo de sempre (re-render do
// servidor não pode apagar escolha não salva): este componente fica na mesma posição da árvore.
//
// FALHA PARCIAL: as seções vão UMA POR VEZ (cada `salvarSecao` já relata linha recusada), e o
// resumo diz quais salvaram e quais NÃO. A seção que falhou continua "não salva" — a barra
// continua aparecendo com o que falta. Nunca "salvo" se algo falhou (`resumirSalvamento`).

export interface SecaoDoEditor {
  secao: string;
  rotulo: string;
  linhas: LinhaDaSecao[];
  /** rotulo_norm → { premissa, sazonalidade } já gravados */
  vinculos: Record<string, EscolhaLinha>;
}

const fotografia = (secoes: SecaoDoEditor[]): EscolhasPorSecao =>
  Object.fromEntries(secoes.map((s) => [s.secao, Object.fromEntries(
    s.linhas.map((l) => [l.rotulo_norm, {
      premissa: s.vinculos[l.rotulo_norm]?.premissa ?? "",
      sazonalidade: s.vinculos[l.rotulo_norm]?.sazonalidade ?? "",
    }]),
  )]));

export function EditorLinhas({
  casoId, secoes, ativas, sazonais,
}: Readonly<{
  casoId: string;
  secoes: SecaoDoEditor[];
  ativas: OpcaoPremissa[];
  sazonais: OpcaoPremissa[];
}>) {
  const [escolhas, setEscolhas] = useState<EscolhasPorSecao>(() => fotografia(secoes));
  const [gravado, setGravado] = useState<EscolhasPorSecao>(() => fotografia(secoes));
  const [salvando, setSalvando] = useState(false);
  const [resumo, setResumo] = useState<ResumoDoSalvamento | null>(null);
  const [confirmaDescarte, setConfirmaDescarte] = useState(false);

  // Linha que o estado ainda não conhece (a busca por rótulo traz outro recorte da lista) lê do
  // que o servidor mandou, nos DOIS lados — assim não nasce "suja" nem aparece em branco.
  const doServidor = fotografia(secoes);
  const lado = (base: EscolhasPorSecao): EscolhasPorSecao =>
    Object.fromEntries(secoes.map((s) => [s.secao, { ...doServidor[s.secao], ...base[s.secao] }]));
  const escolhasAgora = lado(escolhas);
  const gravadoAgora = lado(gravado);

  const lotes = lotesPendentes(secoes, escolhasAgora, gravadoAgora);
  const total = totalPendente(lotes);

  // Sair da tela com escolha pendente é a maneira mais fácil de perder trabalho aqui.
  useEffect(() => {
    if (total === 0) return;
    const aviso = (ev: BeforeUnloadEvent) => { ev.preventDefault(); };
    window.addEventListener("beforeunload", aviso);
    return () => window.removeEventListener("beforeunload", aviso);
  }, [total]);

  const mudar = (secao: string, rotulo: string, campo: "premissa" | "sazonalidade", valor: string) => {
    setResumo(null);
    setConfirmaDescarte(false);
    setEscolhas((e) => ({
      ...e,
      [secao]: { ...e[secao], [rotulo]: { ...escolhasAgora[secao]?.[rotulo], [campo]: valor } as EscolhaLinha },
    }));
  };

  // O LOTE (aplicar a todas as contas) é do BANCO e ele grava `sazonalidade = null` em cada conta
  // (`fn_aplicar_premissa_em_lote` sem `p_sazonalidade`, 0100:222). A tela refletia o contrário:
  // mantinha a sazonalidade escolhida e a marcava como "gravada". Agora o gravado é o que o banco
  // ficou — premissa nova, sazonalidade vazia — e uma sazonalidade que estava na tela volta a
  // aparecer como NÃO SALVA, que é o que ela é.
  const loteAplicado = (s: SecaoDoEditor, premissa: string) => {
    const contas = s.linhas.filter((l) => l.papel === "conta");
    setResumo(null);
    setEscolhas((e) => ({
      ...e,
      [s.secao]: {
        ...e[s.secao],
        ...Object.fromEntries(contas.map((l) => [l.rotulo_norm, {
          premissa, sazonalidade: escolhasAgora[s.secao]?.[l.rotulo_norm]?.sazonalidade ?? "",
        }])),
      },
    }));
    setGravado((g) => ({
      ...g,
      [s.secao]: {
        ...g[s.secao],
        ...Object.fromEntries(contas.map((l) => [l.rotulo_norm, { premissa, sazonalidade: "" }])),
      },
    }));
  };

  const salvarTudo = async () => {
    if (salvando || lotes.length === 0) return;
    setSalvando(true);
    setResumo(null);
    setConfirmaDescarte(false);
    const feitos: { lote: (typeof lotes)[number]; r: ResultadoDaSecao }[] = [];
    for (const lote of lotes) {
      let r: ResultadoDaSecao;
      try {
        r = (await salvarSecao(casoId, null, formDataDoLote(lote)))
          ?? { tom: "erro", texto: "o servidor não respondeu" };
      } catch (err) {
        r = { tom: "erro", texto: `falha ao falar com o servidor (${err instanceof Error ? err.message : "erro"})` };
      }
      feitos.push({ lote, r });
    }
    const res = resumirSalvamento(feitos);
    setGravado((g) => promoverGravado(g, feitos.filter((f) => res.secoesOk.includes(f.lote.secao)).map((f) => f.lote)));
    setResumo(res);
    setSalvando(false);
  };

  const descartar = () => {
    if (!confirmaDescarte) { setConfirmaDescarte(true); return; }
    setEscolhas(gravadoAgora);
    setConfirmaDescarte(false);
    setResumo(null);
  };

  const secoesComPendencia = lotes.length;

  return (
    <div>
      {/* A LEGENDA, UMA VEZ. O papel de cada linha e a "possível sobreposição" só se
          explicavam num `title` — tooltip que não existe no toque nem no teclado. */}
      <dl className="mb-4 grid gap-x-6 gap-y-1 rounded border border-tinta-200 bg-tinta-50 p-2 text-xs text-tinta-600 sm:grid-cols-2">
        {Object.values(PAPEL_INFO).map((p) => (
          <div key={p.rotulo}>
            <dt className={`mr-1 inline rounded px-1 text-[10px] ${p.cor}`}>{p.rotulo}</dt>
            <dd className="inline">{p.curto}</dd>
          </div>
        ))}
        <div>
          <dt className="mr-1 inline rounded bg-alerta-100 px-1 text-[10px] text-alerta-800">possível sobreposição</dt>
          <dd className="inline">{SOBREPOSICAO_CURTO}</dd>
        </div>
      </dl>

      <div className="space-y-5">
        {secoes.map((s) => (
          <SecaoLinhas
            key={s.secao}
            casoId={casoId}
            secao={s.secao}
            rotulo={s.rotulo}
            linhas={s.linhas}
            ativas={ativas}
            sazonais={sazonais}
            escolhas={escolhasAgora[s.secao] ?? {}}
            gravado={gravadoAgora[s.secao] ?? {}}
            onMudar={(rot, campo, valor) => mudar(s.secao, rot, campo, valor)}
            onLoteAplicado={(p) => loteAplicado(s, p)}
          />
        ))}
      </div>

      {/* A ÚNICA BARRA DE SALVAMENTO. Só existe com o que salvar (ou com o resultado do último
          salvamento, que não pode sumir em silêncio: depois de salvar 30 linhas, "nada na tela"
          é indistinguível de "não salvou"). `z-20`: acima do cabeçalho grudado das tabelas. */}
      {(total > 0 || resumo) && (
        <div
          className="sticky bottom-3 z-20 mt-4 flex flex-wrap items-center gap-2 rounded-lg border border-alerta-300 bg-folha px-3 py-2 text-sm shadow-lg"
        >
          {total > 0 && (
            <span className="font-medium text-alerta-900">
              {total} {total === 1 ? "alteração não salva" : "alterações não salvas"}
              <span className="font-normal text-tinta-500">
                {" "}· {secoesComPendencia} {secoesComPendencia === 1 ? "seção" : "seções"}
              </span>
            </span>
          )}
          {total > 0 && (
            <>
              <button
                type="button" onClick={salvarTudo} disabled={salvando}
                className="btn-primario"
              >
                {salvando ? "salvando…" : "Salvar tudo"}
              </button>
              <button
                type="button" onClick={descartar} disabled={salvando}
                className="rounded border border-tinta-200 px-2 py-1 text-xs hover:bg-tinta-100 disabled:opacity-50"
              >
                {confirmaDescarte ? `Confirmar: descartar ${total}` : "Descartar"}
              </button>
              <span className="text-[11px] text-tinta-500">só as linhas que você mudou vão ao banco</span>
            </>
          )}
          {resumo && (
            <span className="flex items-center gap-2">
              <Aviso r={{ tom: resumo.tom, texto: resumo.texto }} />
              <button
                type="button" onClick={() => setResumo(null)}
                className="text-xs text-tinta-500 underline"
              >
                fechar aviso
              </button>
            </span>
          )}
        </div>
      )}
    </div>
  );
}
