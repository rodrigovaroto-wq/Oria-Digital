"use client";

// O RASCUNHO DE E-MAIL AO CLIENTE. Texto simples e editável; nada sai daqui sozinho. "Abrir no
// e-mail" só abre o cliente de e-mail do analista com o texto preenchido — quem envia é ele.
// Vai para o <body> (portal), como os demais painéis, para não herdar filtro/transform do pai.
import { createPortal } from "react-dom";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { BotaoCopiar } from "@/components/botao-copiar";
import { assuntoDoEmail, linkMailto, montarEmailAoCliente } from "@/lib/email-ao-cliente";
import type { PendenteSelecionavel } from "./SelecaoDePerguntas";

const FOCAVEIS = 'a[href], button:not([disabled]), input:not([disabled]), textarea:not([disabled])';

export function EmailAoClienteDialogo({
  mandato, perguntas, ocupado, aviso, onFechar, onRegistrar,
}: Readonly<{
  mandato: string;
  perguntas: PendenteSelecionavel[];
  ocupado: boolean;
  aviso: { texto: string; erro: boolean } | null;
  onFechar: () => void;
  onRegistrar: (textoEnviado: string) => void;
}>) {
  const montado = useSyncExternalStore(() => () => {}, () => true, () => false);
  const [textoInicial] = useState(() => montarEmailAoCliente(perguntas, mandato));
  const [texto, setTexto] = useState(textoInicial);
  // Quantas perguntas o rascunho foi montado com: depois de uma falha parcial `perguntas` encolhe
  // (as registradas saem da lista) mas o texto editado continua listando todas.
  const [nNoTexto] = useState(perguntas.length);
  const [longo, setLongo] = useState(false);
  const caixa = useRef<HTMLDivElement>(null);
  const area = useRef<HTMLTextAreaElement>(null);
  // O pai passa uma função nova a cada render; como dependência do efeito ela re-focaria o campo
  // a cada atualização (o registro em lote re-renderiza o pai), então vai por ref.
  const fecharRef = useRef(onFechar);
  // Fechar (Esc, fundo, ✕) joga fora o texto editado — e o analista pode ter gasto minutos nele.
  // Só pergunta quando há edição; o fechamento por sucesso do registro vem do pai e não passa aqui.
  const textoRef = useRef(texto);
  useEffect(() => {
    fecharRef.current = onFechar;
    textoRef.current = texto;
  });
  const pedirFechar = () => {
    if (textoRef.current === textoInicial) { fecharRef.current(); return; }
    if (window.confirm("Descartar o texto editado do e-mail? Ele não será guardado.")) fecharRef.current();
  };
  const pedirFecharRef = useRef(pedirFechar);
  useEffect(() => { pedirFecharRef.current = pedirFechar; });

  useEffect(() => {
    if (!montado) return;
    const anterior = document.activeElement as HTMLElement | null;
    area.current?.focus();
    const rolagem = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const aoTeclar = (e: KeyboardEvent) => {
      // Com a busca global (⌘K) aberta por cima, o teclado é dela: sem isto um Esc fechava os dois
      // e o Tab daqui puxava o foco para fora da busca.
      if (document.querySelector("[data-busca-global]")) return;
      if (e.key === "Escape") {
        e.preventDefault();
        pedirFecharRef.current();
      } else if (e.key === "Tab" && caixa.current) {
        const foc = Array.from(caixa.current.querySelectorAll<HTMLElement>(FOCAVEIS));
        if (foc.length === 0) return;
        const i = foc.indexOf(document.activeElement as HTMLElement);
        const prox = e.shiftKey ? (i <= 0 ? foc.length - 1 : i - 1) : (i === foc.length - 1 ? 0 : i + 1);
        e.preventDefault();
        foc[prox].focus();
      }
    };
    document.addEventListener("keydown", aoTeclar);
    return () => {
      document.removeEventListener("keydown", aoTeclar);
      document.body.style.overflow = rolagem;
      anterior?.focus();
    };
  }, [montado]);

  if (!montado) return null;

  const abrirNoEmail = () => {
    const url = linkMailto(assuntoDoEmail(mandato), texto);
    if (!url) {
      setLongo(true);
      return;
    }
    setLongo(false);
    window.location.href = url;
  };

  return createPortal(
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-tinta-900/40 p-4">
      {/* O fundo clicável é um botão nativo atrás do painel (fora da ordem de Tab), como na busca
          global; o clique passa pela mesma confirmação de descarte do Esc e do ✕. */}
      <button
        type="button" aria-label="Fechar e-mail" tabIndex={-1} onClick={pedirFechar}
        className="absolute inset-0 h-full w-full cursor-default"
      />
      <div
        ref={caixa}
        role="dialog"
        aria-modal="true"
        aria-labelledby="titulo-email-cliente"
        className="relative flex max-h-full w-[min(720px,100%)] flex-col rounded-lg border border-tinta-200 bg-folha shadow-xl"
      >
        <div className="flex items-start justify-between gap-3 border-b border-tinta-200 px-4 py-3">
          <div>
            <h2 id="titulo-email-cliente" className="text-sm font-semibold text-tinta-900">
              E-mail ao cliente
            </h2>
            <p className="mt-0.5 text-xs text-tinta-500">
              Rascunho com {nNoTexto} {nNoTexto === 1 ? "pergunta" : "perguntas"}
              {perguntas.length < nNoTexto && ` (${perguntas.length} ainda sem registro de envio)`}. Edite
              à vontade. O sistema não envia nada: copie ou abra no seu e-mail, e depois registre o envio.
            </p>
          </div>
          <button type="button" onClick={pedirFechar} aria-label="Fechar" className="btn-secundario">✕</button>
        </div>
        <div className="flex-1 overflow-y-auto px-4 py-3">
          <label htmlFor="texto-email-cliente" className="sr-only">Texto do e-mail</label>
          <textarea
            id="texto-email-cliente"
            ref={area}
            value={texto}
            onChange={(e) => setTexto(e.target.value)}
            rows={18}
            className="w-full rounded-md border border-tinta-200 bg-folha p-3 font-mono text-sm text-tinta-900"
          />
          <p className="mt-1 text-xs text-tinta-500">
            Assunto: {assuntoDoEmail(mandato)}. Troque &ldquo;[nome]&rdquo; pela sua assinatura.
          </p>
          {longo && (
            <p role="status" className="mt-2 text-xs font-medium text-alerta-900">
              O texto é longo para abrir direto; use Copiar.
            </p>
          )}
          {aviso && (
            <p role="status" className={`mt-2 text-xs ${aviso.erro ? "font-medium text-risco-700" : "text-ok-700"}`}>
              {aviso.texto}
            </p>
          )}
        </div>
        <div className="flex flex-wrap items-center gap-2 border-t border-tinta-200 px-4 py-3">
          <BotaoCopiar texto={texto} rotulo="Copiar texto" />
          <button type="button" className="btn-secundario" onClick={abrirNoEmail}>
            Abrir no e-mail
          </button>
          <span className="flex-1" />
          <button
            type="button"
            className="btn-secundario"
            disabled={ocupado}
            onClick={() => onRegistrar(texto)}
            title="Registra o envio de cada pergunta selecionada, congelando este texto como o que foi enviado."
          >
            {ocupado ? "Registrando…" : "Marcar como enviadas"}
          </button>
        </div>
      </div>
    </div>,
    document.body,
  );
}
