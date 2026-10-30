"use client";

import { useCallback, useEffect, useId, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { IconeSino } from "@/components/icones";
import { createClient } from "@/lib/supabase/client";
import { armazem } from "@/lib/casco";
import {
  JANELA_DOS_AVISOS_DIAS, TETO_DOS_AVISOS, contarNaoVistos, gravarVistos, lerVistos, montarAvisos,
  nomeDoSino, pedeAtencao, unirVistos, vistosEfetivos, type Aviso, type FalhaLida, type LoteLido,
} from "@/lib/avisos-de-processamento";

// O SINO DA BARRA SUPERIOR — avisa que lote de ingestão terminou, falhou ou está demorando. Regras (que
// estado o banco permite afirmar, o que é "visto") em `lib/avisos-de-processamento.ts`.
//
// ONDE FICA NO CELULAR: no CABEÇALHO, não no "Mais". O contador só serve se for visto sem um
// toque a mais, e o "Mais" é uma folha que esconde o que carrega; o cabeçalho já leva Busca,
// Discrição e Conta em 375px. O alvo é de 40px no celular (36px em tela larga).
//
// QUANDO LÊ (sem polling agressivo): ao montar, ao navegar (muda o caminho), ao abrir o menu, e a
// cada 60s SÓ com a aba visível. Uma consulta por vez; resposta velha não sobrescreve a nova.
//
// LEITURA QUE FALHA NÃO VIRA "NENHUM AVISO": o estado `erro` mostra "não foi possível ver os
// avisos" no menu e tira o contador (um número sobre dado que não veio seria dado inventado).

const A_CADA_MS = 60_000;
const DIA_MS = 86_400_000;

const dataHora = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit",
});

type Estado = { fase: "carregando" } | { fase: "erro" } | { fase: "ok"; avisos: Aviso[] };

export function AvisosDeProcessamento() {
  const caminho = usePathname();
  const idMenu = useId();
  const raiz = useRef<HTMLDivElement>(null);
  const painel = useRef<HTMLDivElement>(null);
  const emVoo = useRef(0);
  // Chaves marcadas nesta página cuja gravação o navegador RECUSOU: o recarregar de 60 s relê o
  // armazém, que não as tem, e sem esta memória o aviso voltava a "Novo" sozinho.
  const naoGravados = useRef<string[]>([]);
  const [aberto, setAberto] = useState(false);
  const [estado, setEstado] = useState<Estado>({ fase: "carregando" });
  // `null` = o navegador não guarda o visto (janela privada): a tela diz, e todos contam como novos.
  const [vistos, setVistos] = useState<string[] | null>([]);
  const [gravou, setGravou] = useState(true);

  const carregar = useCallback(async () => {
    const minha = ++emVoo.current;
    let proximo: Estado;
    try {
      const sb = createClient();
      const agora = Date.now();
      const desde = new Date(agora - JANELA_DOS_AVISOS_DIAS * DIA_MS).toISOString();
      const [lotes, falhas, naoLidas] = await Promise.all([
        sb.from("lote_execucao")
          .select("id, execucao_ref, caso_id, criado_em, fechado_em, documentos, documentos_planejados, documentos_com_falha, caso(nome)")
          .gte("criado_em", desde).order("criado_em", { ascending: false }).limit(TETO_DOS_AVISOS),
        sb.from("execucao_falha")
          .select("id, caso_id, caso_nome, etapa, mensagem, detalhe, criado_em, caso(nome)")
          .gte("criado_em", desde).order("criado_em", { ascending: false }).limit(TETO_DOS_AVISOS),
        // Documento registrado cuja extração NUNCA foi chamada (0112): `documentos_com_falha` não o vê.
        // Teto de 1000 linhas do PostgREST: acima disso a contagem por caso é piso, e o aviso diz "N".
        sb.from("pendencia")
          .select("caso_id")
          .eq("tipo", "documento_nao_extraido").neq("estado", "resolvida").limit(1000),
      ]);
      const naoLidosPorCaso: Record<string, number> = {};
      for (const p of (naoLidas.data ?? []) as { caso_id: string }[]) naoLidosPorCaso[p.caso_id] = (naoLidosPorCaso[p.caso_id] ?? 0) + 1;
      proximo = lotes.error || falhas.error || naoLidas.error
        ? { fase: "erro" }
        : {
            fase: "ok",
            avisos: montarAvisos(
              (lotes.data ?? []) as unknown as LoteLido[], (falhas.data ?? []) as unknown as FalhaLida[], agora, naoLidosPorCaso,
            ),
          };
    } catch {
      proximo = { fase: "erro" };
    }
    if (minha !== emVoo.current) return;
    setVistos(vistosEfetivos(lerVistos(armazem()), naoGravados.current));
    setEstado(proximo);
  }, []);

  // Ao montar e a cada navegação.
  useEffect(() => { void carregar(); }, [carregar, caminho]);

  // A cada 60s, só com a aba visível.
  useEffect(() => {
    const id = setInterval(() => {
      if (document.visibilityState === "visible") void carregar();
    }, A_CADA_MS);
    return () => clearInterval(id);
  }, [carregar]);

  // Esc fecha e devolve o foco ao botão; sair do menu com Tab ou clicar fora também fecha.
  useEffect(() => {
    if (!aberto) return;
    painel.current?.focus();
    const aoTeclar = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      setAberto(false);
      raiz.current?.querySelector("button")?.focus();
    };
    const aoClicar = (e: MouseEvent) => {
      if (raiz.current && !raiz.current.contains(e.target as Node)) setAberto(false);
    };
    document.addEventListener("keydown", aoTeclar);
    document.addEventListener("mousedown", aoClicar);
    return () => {
      document.removeEventListener("keydown", aoTeclar);
      document.removeEventListener("mousedown", aoClicar);
    };
  }, [aberto]);

  const avisos = estado.fase === "ok" ? estado.avisos : [];
  const naoVistos = estado.fase === "ok" ? contarNaoVistos(avisos, vistos) : 0;
  const foiVisto = (a: Aviso) => vistos != null && vistos.includes(a.chave);

  const marcar = (chaves: string[]) => {
    const lidos = lerVistos(armazem());
    const novos = unirVistos(lidos ?? vistos ?? [], chaves);
    const gravado = gravarVistos(armazem(), novos);
    naoGravados.current = gravado ? [] : unirVistos(naoGravados.current, chaves);
    setGravou(gravado);
    setVistos(novos);
  };

  const alternar = () => {
    if (!aberto) void carregar();
    setAberto((v) => !v);
  };

  return (
    <div
      ref={raiz}
      className="relative"
      onBlur={(e) => {
        if (aberto && !raiz.current?.contains(e.relatedTarget as Node | null) && e.relatedTarget) setAberto(false);
      }}
    >
      <button
        type="button"
        onClick={alternar}
        aria-expanded={aberto}
        aria-controls={idMenu}
        aria-label={nomeDoSino(estado.fase, naoVistos)}
        title="Avisos de processamento"
        className="relative flex h-10 w-10 items-center justify-center rounded-full text-vidro-suave transition-colors hover:bg-white/10 hover:text-vidro-texto sm:h-9 sm:w-9"
      >
        <IconeSino tamanho={18} />
        {estado.fase === "ok" && naoVistos > 0 && (
          <span
            aria-hidden
            className="absolute right-0.5 top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-vidro-texto px-1 text-[10px] font-semibold leading-none text-vidro-tinta"
          >
            {naoVistos > 9 ? "9+" : naoVistos}
          </span>
        )}
      </button>

      {aberto && (
        <div
          id={idMenu}
          ref={painel}
          tabIndex={-1}
          role="region"
          aria-label="Avisos de processamento"
          className="vidro-claro absolute right-0 top-full z-20 mt-2 w-80 max-w-[calc(100vw-2rem)] rounded-lg border border-tinta-200 bg-folha p-1.5 shadow-lg outline-none"
        >
          <div className="flex items-center justify-between gap-2 px-2.5 py-2">
            <p className="text-xs font-semibold uppercase tracking-wider text-tinta-500">Avisos</p>
            {estado.fase === "ok" && naoVistos > 0 && (
              <button
                type="button"
                onClick={() => marcar(avisos.map((a) => a.chave))}
                className="rounded-md px-2 py-1 text-xs font-medium text-tinta-700 hover:bg-tinta-50 hover:text-tinta-900"
              >
                Marcar todos como vistos
              </button>
            )}
          </div>

          {estado.fase === "carregando" && <p role="status" className="px-2.5 py-3 text-sm text-tinta-500">Carregando avisos…</p>}
          {estado.fase === "erro" && (
            <p role="status" className="px-2.5 py-3 text-sm text-tinta-700">
              Não foi possível ver os avisos. Tente abrir o menu de novo; os lotes continuam sendo
              processados normalmente.
            </p>
          )}
          {estado.fase === "ok" && avisos.length === 0 && (
            <p className="px-2.5 py-3 text-sm text-tinta-600">
              Nenhum lote terminou, falhou ou está demorando nos últimos {JANELA_DOS_AVISOS_DIAS} dias.
            </p>
          )}
          {estado.fase === "ok" && avisos.length > 0 && (
            <ul className="max-h-[60dvh] space-y-0.5 overflow-y-auto">
              {avisos.map((a) => {
                const novo = !foiVisto(a);
                const corpo = (
                  <>
                    <span className="flex items-center gap-2">
                      {novo && <span className="rounded bg-tinta-900 px-1 text-[10px] font-semibold uppercase text-papel">Novo</span>}
                      <span className={`text-sm ${novo ? "font-semibold" : "font-medium"} text-tinta-900`}>{a.rotulo}</span>
                      {pedeAtencao(a.tipo) && <span className="text-[11px] font-semibold uppercase text-tinta-700">Atenção</span>}
                    </span>
                    <span className="block truncate text-xs text-tinta-600">{a.casoNome ?? "Mandato não identificado"}</span>
                    {a.detalhe && <span className="block text-xs text-tinta-600">{a.detalhe}</span>}
                    <span className="block text-[11px] text-tinta-500">{dataHora.format(new Date(a.quando))}</span>
                  </>
                );
                const classe = "block rounded-md px-2.5 py-2 hover:bg-tinta-50";
                return (
                  <li key={a.chave}>
                    {a.casoId ? (
                      <Link
                        href={`/casos/${a.casoId}`}
                        className={classe}
                        onClick={() => { marcar([a.chave]); setAberto(false); }}
                      >
                        {corpo}
                      </Link>
                    ) : (
                      <div className={classe}>{corpo}</div>
                    )}
                  </li>
                );
              })}
            </ul>
          )}

          <p className="border-t border-tinta-200 px-2.5 pb-1.5 pt-2 text-[11px] text-tinta-500">
            Avisos marcados como vistos neste navegador. Em outro computador, ou com o histórico
            apagado, eles voltam como novos. Janela de {JANELA_DOS_AVISOS_DIAS} dias, até {TETO_DOS_AVISOS} avisos.
            {vistos == null && " Este navegador não permite guardar o que foi visto: todos contam como novos."}
            {!gravou && vistos != null && " Não foi possível guardar o visto: vale só enquanto esta página ficar aberta; ao recarregar, volta como novo."}
          </p>
        </div>
      )}
    </div>
  );
}
