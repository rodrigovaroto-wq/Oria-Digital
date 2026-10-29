"use client";

import { createPortal } from "react-dom";
import { Fragment, useCallback, useEffect, useId, useRef, useState, useSyncExternalStore } from "react";
import { useRouter } from "next/navigation";
import { IconeBusca } from "@/components/icones";
import {
  ROTULO_DO_GRUPO, acoesDoTermo, termoDaBusca, LIMITE_POR_GRUPO,
  type GrupoDeBusca, type ResultadoDeBusca,
} from "@/lib/busca-global";
import { interceptarNavegacao } from "@/lib/alteracoes-pendentes";
import { EVENTO_ABRIR_BUSCA } from "@/lib/casco";

// A BUSCA GLOBAL (⌘K / Ctrl+K) na barra de topo.
//
// O DIÁLOGO VAI PARA O <body> (portal), como em `excluir-mandato.tsx`: a barra de
// topo é `vidro-casco` e tem `backdrop-filter`, que vira o bloco de contenção de
// qualquer `fixed` descendente — o painel ficaria preso dentro da barra de 40px.
//
// O ESTADO "BUSCANDO" É DERIVADO, não guardado: a resposta carrega o termo a que
// responde, e `buscando` é "há termo válido e a resposta guardada é de outro termo".
// Assim não há `setState` síncrono em efeito, e uma resposta atrasada de um termo
// antigo nunca é exibida como se fosse do atual (o AbortController já a cancela; o
// `termo` na resposta é o cinto além do suspensório).
//
// FALHA É ESTADO PRÓPRIO: rota que cai mostra a mensagem e "Tentar de novo", nunca
// uma lista vazia — "Nada encontrado" afirmaria uma ausência que ninguém mediu.

const ESPERA_MS = 250;
type Resposta =
  | { termo: string; resultados: ResultadoDeBusca[]; truncados: GrupoDeBusca[] }
  | { termo: string; erro: string; sessaoExpirada?: boolean };

export function BuscaGlobal() {
  const router = useRouter();
  const [aberto, setAberto] = useState(false);
  const [q, setQ] = useState("");
  const [resposta, setResposta] = useState<Resposta | null>(null);
  const [tentativa, setTentativa] = useState(0);
  const [indice, setIndice] = useState(0);
  // `platform` só existe no navegador; o snapshot do servidor é `false` (Ctrl),
  // e o cliente troca para ⌘ depois da hidratação, sem divergência.
  const mac = useSyncExternalStore(
    () => () => {},
    () => /Mac|iPhone|iPad/i.test(navigator.platform),
    () => false,
  );
  const gatilho = useRef<HTMLButtonElement>(null);
  const painel = useRef<HTMLDivElement>(null);
  const idLista = useId();

  const termo = termoDaBusca(q);

  const fechar = useCallback(() => {
    setAberto(false);
    setQ("");
    setResposta(null);
    setIndice(0);
    gatilho.current?.focus();
  }, []);

  // ⌘K / Ctrl+K abre de qualquer tela (e fecha, se já aberto — por `fechar()`, que devolve o
  // foco ao gatilho e limpa o termo e a resposta, como Esc).
  useEffect(() => {
    const aoTeclar = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        if (aberto) fechar(); else setAberto(true);
      }
    };
    document.addEventListener("keydown", aoTeclar);
    return () => document.removeEventListener("keydown", aoTeclar);
  }, [aberto, fechar]);

  // A BARRA INFERIOR DO CELULAR abre a busca por evento (o gatilho dela mora em outro componente,
  // e abaixo de 640px o botão deste cabeçalho some para a função não aparecer duas vezes).
  useEffect(() => {
    const abrir = () => setAberto(true);
    window.addEventListener(EVENTO_ABRIR_BUSCA, abrir);
    return () => window.removeEventListener(EVENTO_ABRIR_BUSCA, abrir);
  }, []);

  // A BUSCA: debounce de 250ms e cancelamento da anterior. Sem termo válido (< 2
  // caracteres) NENHUMA requisição sai.
  useEffect(() => {
    if (!aberto || termo === null) return;
    const ctl = new AbortController();
    const espera = setTimeout(async () => {
      try {
        const r = await fetch(`/api/busca?q=${encodeURIComponent(termo)}`, { signal: ctl.signal });
        const j = (await r.json().catch(() => null)) as
          | { resultados?: ResultadoDeBusca[]; truncados?: GrupoDeBusca[]; erro?: string } | null;
        // Sessão expirada: 401 da rota, ou — se algum proxy ainda redirecionar — resposta que
        // seguiu o redirect e não é JSON (HTML de /login com 200). Nunca "falha genérica".
        if (r.status === 401 || r.redirected || (r.ok && !j)) {
          setResposta({ termo, erro: "Sua sessão expirou — entre de novo.", sessaoExpirada: true });
        } else if (!r.ok || !j || !Array.isArray(j.resultados)) {
          setResposta({ termo, erro: j?.erro ?? "A busca falhou. Tente de novo." });
        } else {
          setResposta({ termo, resultados: j.resultados, truncados: j.truncados ?? [] });
        }
      } catch (e) {
        if ((e as Error).name === "AbortError") return;
        setResposta({ termo, erro: "Sem conexão com o servidor. Tente de novo." });
      }
    }, ESPERA_MS);
    return () => { clearTimeout(espera); ctl.abort(); };
  }, [aberto, termo, tentativa]);

  const respondeu = termo !== null && resposta !== null && resposta.termo === termo;
  const erro = respondeu && "erro" in resposta ? resposta.erro : null;
  const sessaoExpirada = respondeu && "erro" in resposta && resposta.sessaoExpirada === true;
  const achados = respondeu && "resultados" in resposta ? resposta.resultados : [];
  const truncados = respondeu && "truncados" in resposta ? resposta.truncados : [];
  const buscando = termo !== null && !respondeu;
  const itens = [...acoesDoTermo(termo), ...achados];
  const ativo = Math.min(indice, Math.max(itens.length - 1, 0));
  const idOpcao = (i: number) => `${idLista}-op-${i}`;

  const ir = (item: ResultadoDeBusca) => {
    fechar();
    // Com alterações não salvas na tela (Modelagem), o editor pede confirmação em vez de sair.
    if (interceptarNavegacao(item.href)) return;
    router.push(item.href);
  };

  // Esc fecha; Tab é PRENDIDO no painel (o foco volta ao primeiro/último focável). Ouvinte no
  // documento, e não no `div role="dialog"` (elemento não-nativo com ouvinte): o foco vive no
  // combobox, então o teclado sempre passa por aqui. Os botões de fundo/opção têm tabIndex -1.
  useEffect(() => {
    if (!aberto) return;
    const aoTeclarNoPainel = (e: KeyboardEvent) => {
      // stopImmediatePropagation: com um diálogo aberto por baixo (rascunho de e-mail), um Esc
      // fecharia os dois; o diálogo também confere `[data-busca-global]` por causa da ordem dos ouvintes.
      if (e.key === "Escape") { e.preventDefault(); e.stopImmediatePropagation(); fechar(); return; }
      if (e.key === "Tab") {
        const foc = Array.from(painel.current?.querySelectorAll<HTMLElement>(
          'input, button:not([disabled]):not([tabindex="-1"]), a[href]') ?? []);
        if (foc.length === 0) return;
        const i = foc.indexOf(document.activeElement as HTMLElement);
        const prox = e.shiftKey ? (i <= 0 ? foc.length - 1 : i - 1) : (i === foc.length - 1 ? 0 : i + 1);
        e.preventDefault();
        foc[prox].focus();
      }
    };
    document.addEventListener("keydown", aoTeclarNoPainel);
    return () => document.removeEventListener("keydown", aoTeclarNoPainel);
  }, [aberto, fechar]);

  const aoTeclarNoCampo = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      if (itens.length === 0) return;
      setIndice((ativo + (e.key === "ArrowDown" ? 1 : itens.length - 1)) % itens.length);
    } else if (e.key === "Enter") {
      e.preventDefault();
      // Busca em andamento: a lista ainda é só as ações rápidas, e Enter abriria a primeira
      // delas no lugar do resultado que o analista está esperando.
      if (buscando) return;
      if (itens[ativo]) ir(itens[ativo]);
    }
  };

  // Rolagem do item ativo para dentro da vista.
  useEffect(() => {
    if (aberto) document.getElementById(idOpcao(ativo))?.scrollIntoView({ block: "nearest" });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ativo, aberto, itens.length]);

  let ultimoGrupo: GrupoDeBusca | null = null;
  const avisoDeTeto = (g: GrupoDeBusca | null) => g !== null && truncados.includes(g) && (
    <li key={`teto:${g}`} role="presentation" className="px-2.5 pb-1 text-[11px] text-alerta-900">
      Mostrando {LIMITE_POR_GRUPO} em {ROTULO_DO_GRUPO[g]} — pode haver mais; refine a busca.
    </li>
  );

  return (
    <>
      <button
        ref={gatilho}
        type="button"
        onClick={() => setAberto(true)}
        aria-haspopup="dialog"
        aria-keyshortcuts="Control+K Meta+K"
        className="hidden items-center gap-2 rounded-full py-1.5 pl-2.5 pr-2 text-sm text-vidro-suave sm:flex transition-colors hover:bg-white/10 hover:text-vidro-texto"
      >
        <IconeBusca tamanho={16} />
        <span>Buscar</span>
        <kbd className="hidden rounded border border-white/20 px-1.5 text-[11px] font-sans sm:inline">
          {mac ? "⌘K" : "Ctrl K"}
        </kbd>
      </button>

      {aberto && createPortal(
        <div className="fixed inset-0 z-50 flex items-start justify-center bg-fundo-reserva/50 p-4 pt-[12vh]">
          {/* O fundo clicável é um botão nativo atrás do painel (fora da ordem de Tab). */}
          <button
            type="button" aria-label="Fechar busca" tabIndex={-1} onClick={fechar}
            className="absolute inset-0 h-full w-full cursor-default"
          />
          <div
            ref={painel}
            data-busca-global
            role="dialog"
            aria-modal="true"
            aria-label="Busca global"
            className="relative flex max-h-[70vh] w-full max-w-xl flex-col overflow-hidden rounded-lg border border-tinta-200 bg-folha shadow-xl"
          >
            <div className="flex items-center gap-2 border-b border-tinta-200 px-3">
              <IconeBusca tamanho={16} className="text-tinta-500" />
              <input
                autoFocus
                type="text"
                role="combobox"
                aria-expanded="true"
                aria-controls={idLista}
                aria-activedescendant={itens.length ? idOpcao(ativo) : undefined}
                aria-autocomplete="list"
                aria-label="Buscar mandatos, documentos e entidades"
                placeholder="Buscar mandato, documento ou CNPJ…"
                maxLength={60}
                value={q}
                onChange={(e) => { setQ(e.target.value); setIndice(0); }}
                onKeyDown={aoTeclarNoCampo}
                className="w-full bg-transparent py-3 text-sm text-tinta-900 placeholder:text-tinta-500 focus:outline-none"
              />
              <kbd className="rounded border border-tinta-200 px-1.5 text-[11px] text-tinta-500">Esc</kbd>
            </div>

            <ul id={idLista} role="listbox" aria-label="Resultados" className="min-h-0 flex-1 overflow-y-auto p-1.5">
              {itens.map((item, i) => {
                const cabecalho = item.grupo !== ultimoGrupo;
                const aviso = cabecalho ? avisoDeTeto(ultimoGrupo) : null;
                ultimoGrupo = item.grupo;
                return (
                  <Fragment key={item.chave}>
                  {aviso}
                  <li role="presentation">
                    {cabecalho && (
                      <p className="px-2.5 pb-1 pt-2 text-[11px] font-semibold uppercase tracking-wide text-tinta-500">
                        {ROTULO_DO_GRUPO[item.grupo]}
                      </p>
                    )}
                    <button
                      type="button"
                      tabIndex={-1}
                      id={idOpcao(i)}
                      role="option"
                      aria-selected={i === ativo}
                      onMouseMove={() => setIndice(i)}
                      onClick={() => ir(item)}
                      className={`flex w-full cursor-pointer items-baseline gap-2 rounded-md px-2.5 py-2 text-left text-sm ${
                        i === ativo ? "bg-tinta-100 text-tinta-900 outline outline-2 -outline-offset-2 outline-tinta-700" : "text-tinta-700"
                      }`}
                    >
                      <span className="min-w-0 truncate font-medium">{item.rotulo}</span>
                      {item.fechado && (
                        <span className="shrink-0 rounded border border-tinta-300 px-1.5 text-[11px] text-tinta-600">Fechado</span>
                      )}
                      {item.detalhe && <span className="ml-auto min-w-0 truncate text-xs text-tinta-500">{item.detalhe}</span>}
                    </button>
                  </li>
                  </Fragment>
                );
              })}
              {avisoDeTeto(ultimoGrupo)}
            </ul>

            <div className="border-t border-tinta-200 px-3 py-2 text-xs text-tinta-600" aria-live="polite">
              {termo === null && "Digite ao menos 2 caracteres para buscar."}
              {buscando && "Buscando…"}
              {erro !== null && (
                <span role="alert" className="flex items-center justify-between gap-2 text-risco-700">
                  <span>{erro}</span>
                  {sessaoExpirada ? (
                    <a href="/login" className="rounded border border-risco-300 px-2 py-0.5 font-medium hover:bg-risco-50">
                      Entrar de novo
                    </a>
                  ) : (
                  <button
                    type="button"
                    onClick={() => { setResposta(null); setTentativa((n) => n + 1); }}
                    className="rounded border border-risco-300 px-2 py-0.5 font-medium hover:bg-risco-50"
                  >
                    Tentar de novo
                  </button>
                  )}
                </span>
              )}
              {respondeu && erro === null && achados.length === 0 && `Nada encontrado para “${termo}”`}
              {respondeu && erro === null && achados.length > 0 && `${achados.length} resultado${achados.length > 1 ? "s" : ""}${truncados.length > 0 ? " — alguns grupos estão limitados" : ""}`}
            </div>
          </div>
        </div>,
        document.body,
      )}
    </>
  );
}
