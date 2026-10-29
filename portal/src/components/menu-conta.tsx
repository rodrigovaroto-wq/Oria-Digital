"use client";

import { useEffect, useId, useRef, useState } from "react";
import { IconeChevronBaixo, IconeConta, IconeSair } from "@/components/icones";
import {
  CONSULTA_TEMA_ESCURO, aplicarTema, gravarPreferenciaDeTema, lerPreferenciaDeTema,
  type PreferenciaDeTema,
} from "@/lib/casco";

const OPCOES_DE_TEMA: ReadonlyArray<{ valor: PreferenciaDeTema; rotulo: string }> = [
  { valor: "claro", rotulo: "Claro" },
  { valor: "escuro", rotulo: "Escuro" },
  { valor: "sistema", rotulo: "Sistema" },
];

// A CONTA NO CABEÇALHO. O e-mail inteiro e o "Sair" ficavam expostos em toda
// tela, com o mesmo peso de um link de navegação, e o e-mail some abaixo de 640px
// (`hidden sm:inline`) — em celular não havia nem como saber quem estava logado.
// Agora o cabeçalho mostra só as iniciais; o e-mail completo e o "Sair" moram num
// menu que abre sob demanda.
//
// `logout` chega como prop (a server action fica em `app/login/actions.ts` e o
// layout, que é servidor, a importa): assim este componente de cliente não
// precisa conhecer o módulo do servidor.

/** Iniciais da parte local do e-mail: "rodrigo.varoto@x" → "RV"; "ana@x" → "A". */
export function iniciaisDoEmail(email: string): string {
  const local = email.split("@")[0] ?? "";
  const partes = local.split(/[._\-+\s]+/).filter(Boolean);
  if (partes.length === 0) return "";
  const letras = partes.length === 1 ? partes[0].slice(0, 1) : partes[0][0] + (partes.at(-1) ?? "")[0];
  return letras.toLocaleUpperCase("pt-BR");
}

export function MenuConta({
  email,
  sair,
}: Readonly<{
  email: string;
  sair: (formData: FormData) => void | Promise<void>;
}>) {
  const [aberto, setAberto] = useState(false);
  const raiz = useRef<HTMLDivElement>(null);
  const idMenu = useId();
  const iniciais = iniciaisDoEmail(email);
  // A escolha guardada, lida uma vez. Só é DESENHADA com o menu aberto (depois da hidratação),
  // então ler o localStorage aqui não diverge do HTML do servidor; no servidor vale "sistema".
  const [tema, setTema] = useState<PreferenciaDeTema>(() =>
    typeof window === "undefined" ? "sistema" : lerPreferenciaDeTema(window.localStorage));

  useEffect(() => {
    // Em "Sistema" o tema segue o aparelho AO VIVO (o escuro ao anoitecer): este ouvinte vive
    // no menu, que está sempre montado, e não no seletor, que só existe com o menu aberto.
    const consulta = window.matchMedia(CONSULTA_TEMA_ESCURO);
    const aoMudar = () => {
      if (lerPreferenciaDeTema(window.localStorage) === "sistema") {
        aplicarTema(document.documentElement, "sistema", consulta.matches);
      }
    };
    consulta.addEventListener("change", aoMudar);
    return () => consulta.removeEventListener("change", aoMudar);
  }, []);

  function escolherTema(preferencia: PreferenciaDeTema) {
    setTema(preferencia);
    // Se o navegador recusar a gravação, o tema vale até recarregar — o atributo é aplicado igual.
    gravarPreferenciaDeTema(window.localStorage, preferencia);
    aplicarTema(document.documentElement, preferencia, window.matchMedia(CONSULTA_TEMA_ESCURO).matches);
  }

  // FECHA COM ESC E COM CLIQUE FORA. Os dois ouvintes só existem enquanto o menu
  // está aberto — o resto do tempo a página não paga por eles. Esc devolve o foco
  // ao botão: sem isso, quem navega por teclado cai no <body> e perde o lugar.
  useEffect(() => {
    if (!aberto) return;
    const aoTeclar = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setAberto(false);
        raiz.current?.querySelector("button")?.focus();
      }
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

  return (
    <div ref={raiz} className="relative ml-auto">
      <button
        type="button"
        onClick={() => setAberto((v) => !v)}
        aria-expanded={aberto}
        aria-haspopup="true"
        aria-controls={idMenu}
        aria-label={email ? `Conta de ${email}` : "Conta"}
        title={email || "Conta"}
        className="flex items-center gap-1.5 rounded-full py-1 pl-1 pr-2 text-vidro-suave transition-colors hover:bg-white/10 hover:text-vidro-texto"
      >
        <span className="flex h-7 w-7 items-center justify-center rounded-full bg-vidro-texto text-[11px] font-semibold text-vidro-tinta">
          {iniciais || <IconeConta tamanho={16} />}
        </span>
        <IconeChevronBaixo tamanho={14} className={`transition-transform ${aberto ? "rotate-180" : ""}`} />
      </button>

      {aberto && (
        <div
          id={idMenu}
          // O MENU É SUPERFÍCIE DE CONTEÚDO (`bg-folha`), não vidro: dentro do casco escuro ele é
          // creme no tema claro e escuro no tema escuro, pelos tokens — é texto de e-mail e uma
          // ação destrutiva-adjacente ("Sair"), e legibilidade vale mais do que coerência de
          // vidro. `vidro-claro` devolve o anel de foco de conteúdo (acento-600 do tema).
          className="vidro-claro absolute right-0 top-full z-20 mt-2 w-64 rounded-lg border border-tinta-200 bg-folha p-1.5 shadow-lg"
        >
          {email && (
            <p className="truncate px-2.5 py-2 text-xs text-tinta-500" title={email}>
              {email}
            </p>
          )}
          <div className="border-t border-tinta-100 px-2.5 py-2">
            <p id={`${idMenu}-tema`} className="mb-1.5 text-xs text-tinta-500">Aparência</p>
            <div role="group" aria-labelledby={`${idMenu}-tema`} className="flex gap-1 rounded-md bg-tinta-50 p-0.5">
              {OPCOES_DE_TEMA.map((o) => (
                <button
                  key={o.valor}
                  type="button"
                  aria-pressed={tema === o.valor}
                  onClick={() => escolherTema(o.valor)}
                  className={`flex-1 rounded px-2 py-1 text-xs font-medium transition-colors ${
                    tema === o.valor ? "bg-folha text-tinta-900 shadow-sm" : "text-tinta-600 hover:text-tinta-900"
                  }`}
                >
                  {o.rotulo}
                </button>
              ))}
            </div>
          </div>
          <form action={sair} className="border-t border-tinta-100 pt-1">
            <button
              type="submit"
              className="flex w-full items-center gap-2 rounded-md px-2.5 py-2 text-sm font-medium text-tinta-700 transition-colors hover:bg-tinta-50 hover:text-tinta-900"
            >
              <IconeSair />
              Sair
            </button>
          </form>
        </div>
      )}
    </div>
  );
}
