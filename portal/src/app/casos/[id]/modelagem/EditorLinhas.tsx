"use client";

import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { useRouter } from "next/navigation";
import { salvarSecao } from "./actions";
import {
  Aviso, PAPEL_INFO, SecaoLinhas, SOBREPOSICAO_CURTO,
  type LinhaDaSecao, type OpcaoPremissa,
} from "./SecaoLinhas";
import {
  EVENTO_CONFIRMAR_SAIDA, definirPendentes,
} from "@/lib/alteracoes-pendentes";
import {
  escolhasVisiveis, formDataDoLote, lotesPendentes, podarEdicoes, registrarEdicao,
  resumirSalvamento, totalPendente,
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
  const router = useRouter();
  // SÓ as edições do analista vivem no estado. O "gravado" é o que o SERVIDOR mandou (as props,
  // renovadas pelo `revalidatePath` de cada ação): ver `modelagem-lote.ts`. Linha que o estado
  // não conhece (a busca por rótulo traz outro recorte) lê do servidor, nos dois lados.
  const [edicoes, setEdicoes] = useState<EscolhasPorSecao>({});
  const [vistas, setVistas] = useState(secoes);
  const [salvando, setSalvando] = useState(false);
  const [resumo, setResumo] = useState<ResumoDoSalvamento | null>(null);
  const [confirmaDescarte, setConfirmaDescarte] = useState(false);
  const [saida, setSaida] = useState<string | null>(null);

  const gravadoAgora = fotografia(secoes);
  // Servidor mudou (salvou, ou a premissa foi removida no passo 2): a edição que ele alcançou
  // ou ultrapassou deixa de existir — senão o valor velho voltaria como "não salvo".
  if (vistas !== secoes) {
    setVistas(secoes);
    setEdicoes((e) => podarEdicoes(e, gravadoAgora));
  }
  const escolhasAgora = escolhasVisiveis(gravadoAgora, edicoes);

  const lotes = lotesPendentes(secoes, escolhasAgora, gravadoAgora);
  const total = totalPendente(lotes);

  // Sair da tela com escolha pendente é a maneira mais fácil de perder trabalho aqui.
  // `beforeunload` cobre fechar/recarregar; a navegação do app (links, ⌘K) passa pela guarda
  // abaixo, que abre o diálogo de confirmação.
  useEffect(() => {
    definirPendentes(total);
    if (total === 0) return;
    const aviso = (ev: BeforeUnloadEvent) => { ev.preventDefault(); };
    window.addEventListener("beforeunload", aviso);
    return () => { window.removeEventListener("beforeunload", aviso); definirPendentes(0); };
  }, [total]);

  useEffect(() => {
    if (total === 0) return;
    const aoClicar = (ev: MouseEvent) => {
      if (ev.defaultPrevented || ev.button !== 0 || ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
      const a = (ev.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
      if (!a || (a.target && a.target !== "_self") || a.hasAttribute("download")) return;
      const u = new URL(a.href, window.location.href);
      if (u.origin !== window.location.origin) return;
      if (u.pathname === window.location.pathname && u.search === window.location.search) return;
      ev.preventDefault();
      ev.stopPropagation();
      setSaida(u.pathname + u.search + u.hash);
    };
    const aoPedir = (ev: Event) => setSaida((ev as CustomEvent<{ href: string }>).detail.href);
    document.addEventListener("click", aoClicar, true);
    window.addEventListener(EVENTO_CONFIRMAR_SAIDA, aoPedir);
    return () => {
      document.removeEventListener("click", aoClicar, true);
      window.removeEventListener(EVENTO_CONFIRMAR_SAIDA, aoPedir);
    };
  }, [total]);

  useEffect(() => {
    if (saida === null) return;
    const aoTeclar = (e: KeyboardEvent) => { if (e.key === "Escape") setSaida(null); };
    document.addEventListener("keydown", aoTeclar);
    return () => document.removeEventListener("keydown", aoTeclar);
  }, [saida]);

  const mudar = (secao: string, rotulo: string, campo: "premissa" | "sazonalidade", valor: string) => {
    setResumo(null);
    setConfirmaDescarte(false);
    setEdicoes((e) => registrarEdicao(e, gravadoAgora, escolhasAgora, secao, rotulo, campo, valor));
  };

  // O LOTE (aplicar a todas as contas) é do BANCO e ele grava `sazonalidade = null` em cada conta
  // (`fn_aplicar_premissa_em_lote` sem `p_sazonalidade`, 0100:222). O servidor devolve isso nas
  // props (a ação revalida); aqui só se mantém a sazonalidade que o analista tinha na tela, que
  // diante do banco passa a ser NÃO SALVA, que é o que ela é. Até a atualização chegar, a
  // premissa nova já aparece, e a poda tira a edição quando o servidor a alcança.
  const loteAplicado = (s: SecaoDoEditor, premissa: string) => {
    const contas = s.linhas.filter((l) => l.papel === "conta");
    setResumo(null);
    setEdicoes((e) => ({
      ...e,
      [s.secao]: {
        ...e[s.secao],
        ...Object.fromEntries(contas.map((l) => [l.rotulo_norm, {
          premissa, sazonalidade: escolhasAgora[s.secao]?.[l.rotulo_norm]?.sazonalidade ?? "",
        }])),
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
    // Nada a "promover": a ação revalidou e as props trazem o que o banco TEM. Linha gravada em
    // seção que falhou em outra linha fica limpa; só a recusada continua suja.
    setResumo(res);
    setSalvando(false);
  };

  const descartar = () => {
    if (!confirmaDescarte) { setConfirmaDescarte(true); return; }
    setEdicoes({});   // sem edição, a tela mostra o que o SERVIDOR tem
    setConfirmaDescarte(false);
    setResumo(null);
  };

  const secoesComPendencia = lotes.length;
  const sairAgora = () => {
    const destino = saida;
    setSaida(null);
    definirPendentes(0);
    if (destino) router.push(destino);
  };

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

      {saida !== null && createPortal(
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-tinta-900/50 p-4">
          <div
            role="alertdialog" aria-modal="true" aria-label="Alterações não salvas"
            className="w-full max-w-md rounded-lg border border-tinta-200 bg-folha p-4 text-sm shadow-xl"
          >
            <p className="font-medium text-tinta-900">
              {total} {total === 1 ? "alteração não salva" : "alterações não salvas"} nesta tela.
            </p>
            <p className="mt-1 text-tinta-600">Se sair agora, elas se perdem — nada foi enviado ao banco.</p>
            <div className="mt-3 flex justify-end gap-2">
              <button type="button" autoFocus onClick={() => setSaida(null)} className="btn-primario">
                Ficar e salvar
              </button>
              <button
                type="button" onClick={sairAgora}
                className="rounded border border-tinta-200 px-2 py-1 text-xs hover:bg-tinta-100"
              >
                Sair sem salvar
              </button>
            </div>
          </div>
        </div>,
        document.body,
      )}
    </div>
  );
}
