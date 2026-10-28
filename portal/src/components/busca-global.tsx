"use client";

import { createPortal } from "react-dom";
import { useCallback, useEffect, useId, useRef, useState, useSyncExternalStore } from "react";
import { useRouter } from "next/navigation";
import { IconeBusca } from "@/components/icones";
import {
  ROTULO_DO_GRUPO, acoesDoTermo, termoDaBusca, type ResultadoDeBusca,
} from "@/lib/busca-global";

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
type Resposta = { termo: string; resultados: ResultadoDeBusca[] } | { termo: string; erro: string };

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

  // ⌘K / Ctrl+K abre de qualquer tela (e fecha, se já aberto).
  useEffect(() => {
    const aoTeclar = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setAberto((v) => !v);
      }
    };
    document.addEventListener("keydown", aoTeclar);
    return () => document.removeEventListener("keydown", aoTeclar);
  }, []);

  const fechar = useCallback(() => {
    setAberto(false);
    setQ("");
    setResposta(null);
    setIndice(0);
    gatilho.current?.focus();
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
          | { resultados?: ResultadoDeBusca[]; erro?: string } | null;
        if (!r.ok || !j || !Array.isArray(j.resultados)) {
          setResposta({ termo, erro: j?.erro ?? "A busca falhou. Tente de novo." });
        } else {
          setResposta({ termo, resultados: j.resultados });
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
  const achados = respondeu && "resultados" in resposta ? resposta.resultados : [];
  const buscando = termo !== null && !respondeu;
  const itens = [...acoesDoTermo(termo), ...achados];
  const ativo = Math.min(indice, Math.max(itens.length - 1, 0));
  const idOpcao = (i: number) => `${idLista}-op-${i}`;

  const ir = (item: ResultadoDeBusca) => {
    fechar();
    router.push(item.href);
  };

  // Esc fecha; Tab é PRENDIDO no painel (o foco volta ao primeiro/último focável).
  const aoTeclarNoPainel = (e: React.KeyboardEvent) => {
    if (e.key === "Escape") { e.preventDefault(); fechar(); return; }
    if (e.key === "Tab") {
      const foc = Array.from(painel.current?.querySelectorAll<HTMLElement>("input, button:not([disabled])") ?? []);
      if (foc.length === 0) return;
      const i = foc.indexOf(document.activeElement as HTMLElement);
      const prox = e.shiftKey ? (i <= 0 ? foc.length - 1 : i - 1) : (i === foc.length - 1 ? 0 : i + 1);
      e.preventDefault();
      foc[prox].focus();
    }
  };

  const aoTeclarNoCampo = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      if (itens.length === 0) return;
      setIndice((ativo + (e.key === "ArrowDown" ? 1 : itens.length - 1)) % itens.length);
    } else if (e.key === "Enter" && itens[ativo]) {
      e.preventDefault();
      ir(itens[ativo]);
    }
  };

  // Rolagem do item ativo para dentro da vista.
  useEffect(() => {
    if (aberto) document.getElementById(idOpcao(ativo))?.scrollIntoView({ block: "nearest" });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ativo, aberto, itens.length]);

  let ultimoGrupo: string | null = null;

  return (
    <>
      <button
        ref={gatilho}
        type="button"
        onClick={() => setAberto(true)}
        aria-haspopup="dialog"
        aria-keyshortcuts="Control+K Meta+K"
        className="flex items-center gap-2 rounded-full py-1.5 pl-2.5 pr-2 text-sm text-vidro-suave transition-colors hover:bg-white/10 hover:text-vidro-texto"
      >
        <IconeBusca tamanho={16} />
        <span>Buscar</span>
        <kbd className="hidden rounded border border-white/20 px-1.5 text-[11px] font-sans sm:inline">
          {mac ? "⌘K" : "Ctrl K"}
        </kbd>
      </button>

      {aberto && createPortal(
        <div
          className="fixed inset-0 z-50 flex items-start justify-center bg-tinta-900/50 p-4 pt-[12vh]"
          onMouseDown={(e) => { if (e.target === e.currentTarget) fechar(); }}
        >
          <div
            ref={painel}
            role="dialog"
            aria-modal="true"
            aria-label="Busca global"
            onKeyDown={aoTeclarNoPainel}
            className="flex max-h-[70vh] w-full max-w-xl flex-col overflow-hidden rounded-lg border border-tinta-200 bg-folha shadow-xl"
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
                ultimoGrupo = item.grupo;
                return (
                  <li key={item.chave} role="presentation">
                    {cabecalho && (
                      <p className="px-2.5 pb-1 pt-2 text-[11px] font-semibold uppercase tracking-wide text-tinta-500">
                        {ROTULO_DO_GRUPO[item.grupo]}
                      </p>
                    )}
                    <div
                      id={idOpcao(i)}
                      role="option"
                      aria-selected={i === ativo}
                      onMouseMove={() => setIndice(i)}
                      onClick={() => ir(item)}
                      className={`flex cursor-pointer items-baseline gap-2 rounded-md px-2.5 py-2 text-sm ${
                        i === ativo ? "bg-tinta-100 text-tinta-900 outline outline-2 -outline-offset-2 outline-tinta-700" : "text-tinta-700"
                      }`}
                    >
                      <span className="min-w-0 truncate font-medium">{item.rotulo}</span>
                      {item.fechado && (
                        <span className="shrink-0 rounded border border-tinta-300 px-1.5 text-[11px] text-tinta-600">Fechado</span>
                      )}
                      {item.detalhe && <span className="ml-auto min-w-0 truncate text-xs text-tinta-500">{item.detalhe}</span>}
                    </div>
                  </li>
                );
              })}
            </ul>

            <div className="border-t border-tinta-200 px-3 py-2 text-xs text-tinta-600" aria-live="polite">
              {termo === null && "Digite ao menos 2 caracteres para buscar."}
              {buscando && "Buscando…"}
              {erro !== null && (
                <span role="alert" className="flex items-center justify-between gap-2 text-risco-700">
                  <span>{erro}</span>
                  <button
                    type="button"
                    onClick={() => { setResposta(null); setTentativa((n) => n + 1); }}
                    className="rounded border border-risco-300 px-2 py-0.5 font-medium hover:bg-risco-50"
                  >
                    Tentar de novo
                  </button>
                </span>
              )}
              {respondeu && erro === null && achados.length === 0 && `Nada encontrado para “${termo}”`}
              {respondeu && erro === null && achados.length > 0 && `${achados.length} resultado${achados.length > 1 ? "s" : ""}`}
            </div>
          </div>
        </div>,
        document.body,
      )}
    </>
  );
}
