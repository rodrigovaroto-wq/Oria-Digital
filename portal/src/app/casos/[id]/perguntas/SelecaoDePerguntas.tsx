"use client";

// A SELEÇÃO EM LOTE DAS PERGUNTAS. Na prática o analista manda ao cliente UMA lista, não onze
// mensagens — então a tela deixa marcar várias, copiar, montar o rascunho de e-mail e registrar
// o envio de uma vez. O sistema continua sem enviar nada, e nada é marcado como enviado sem o
// clique explícito em "Marcar como enviadas".
//
// SÓ AS PENDENTES SÃO SELECIONÁVEIS (as já tratadas não têm caixa): registrar de novo uma
// pergunta já enviada é decisão individual, no cartão. Default: nenhuma selecionada.
import { createContext, useContext, useEffect, useRef, useState, useTransition } from "react";
import { BotaoCopiar } from "@/components/botao-copiar";
import { listaNumerada, perguntasForaDoTexto, resumoDoLote, textoDoItem } from "@/lib/email-ao-cliente";
import { EmailAoClienteDialogo } from "./EmailAoClienteDialogo";
import { registrarAcaoSemExcecao } from "./actions";

export interface PendenteSelecionavel {
  chave: string;
  codigo: string;
  prioridade: number;
  entidade: string | null;
  entidade_id: string | null;
  pergunta: string;
}

interface Ctx {
  pendentes: PendenteSelecionavel[];
  marcadas: Set<string>;
  alternar: (chave: string) => void;
  definir: (chaves: string[], marcar: boolean) => void;
}

const Selecao = createContext<Ctx | null>(null);

export function ProvedorDeSelecao({
  casoId, mandato, pendentes, children,
}: Readonly<{
  casoId: string;
  mandato: string;
  pendentes: PendenteSelecionavel[];
  children: React.ReactNode;
}>) {
  const [marcadas, setMarcadas] = useState<Set<string>>(new Set());
  const [dialogo, setDialogo] = useState(false);
  const [aviso, setAviso] = useState<{ texto: string; erro: boolean } | null>(null);
  const [ocupado, iniciar] = useTransition();

  // Só vale o que ainda é pendente: depois do registro a pergunta sai da lista e some da seleção.
  const vivas = new Set(pendentes.map((p) => p.chave));
  const efetivas = new Set([...marcadas].filter((c) => vivas.has(c)));
  const escolhidas = pendentes.filter((p) => efetivas.has(p.chave));

  const alternar = (chave: string) =>
    setMarcadas((m) => {
      const n = new Set(m);
      if (n.has(chave)) n.delete(chave);
      else n.add(chave);
      return n;
    });
  const definir = (chaves: string[], marcar: boolean) =>
    setMarcadas((m) => {
      const n = new Set(m);
      for (const c of chaves) {
        if (marcar) n.add(c);
        else n.delete(c);
      }
      return n;
    });

  // SEQUENCIAL, uma chamada por pergunta, a MESMA ação dos cartões. O que se congela em
  // `texto_enviado` (imutável, 0213) é o ITEM da pergunta (`textoDoItem`, o que o Copiar e o
  // e-mail escrevem depois de "N. "), tanto na barra quanto no diálogo — e não o e-mail inteiro
  // repetido em cada uma. Vindo do diálogo, só se registra a pergunta cujo item AINDA está no texto
  // editado: tirá-la do e-mail e mesmo assim marcá-la "enviada" afirmaria um envio que não houve.
  const registrar = (textoEditado?: string) => {
    const foraDoTexto = textoEditado === undefined ? [] : perguntasForaDoTexto(escolhidas, textoEditado);
    const fora = new Set(foraDoTexto.map((p) => p.chave));
    const alvo = escolhidas.filter((p) => !fora.has(p.chave));
    const nomeDe = (p: PendenteSelecionavel) => `${p.codigo}${p.entidade ? ` (${p.entidade})` : ""}`;
    iniciar(async () => {
      let ok = 0;
      const falhas: string[] = [];
      const registradas = new Set<string>();
      for (const p of alvo) {
        const fd = new FormData();
        fd.set("codigo", p.codigo);
        fd.set("entidade_id", p.entidade_id ?? "");
        fd.set("acao", "enviada");
        fd.set("texto", textoDoItem(p));
        const r = await registrarAcaoSemExcecao(casoId, fd);
        if (r.ok) {
          ok += 1;
          registradas.add(p.chave);
        } else {
          falhas.push(`${nomeDe(p)}: ${r.erro}`);
        }
      }
      // As que falharam (ou ficaram fora do texto) continuam marcadas, para tentar de novo sem remarcar.
      setMarcadas((m) => new Set([...m].filter((c) => !registradas.has(c))));
      const sujo = falhas.length > 0 || foraDoTexto.length > 0;
      setAviso({ texto: resumoDoLote(ok, falhas, foraDoTexto.map(nomeDe)), erro: sujo });
      if (!sujo) setDialogo(false);
    });
  };

  // FOCO. Ao registrar tudo, as perguntas saem de `pendentes`, o botão que abriu o diálogo some e
  // o foco cairia no <body>. Devolve-o à barra (que fica, com o aviso) quando nada o tem.
  const barra = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (dialogo || !aviso) return;
    const a = document.activeElement;
    if (!a || a === document.body) barra.current?.focus();
  }, [dialogo, aviso]);

  return (
    <Selecao.Provider value={{ pendentes, marcadas: efetivas, alternar, definir }}>
      {children}
      {(escolhidas.length > 0 || aviso) && (
        <div
          ref={barra}
          tabIndex={-1}
          className="sticky bottom-3 z-10 rounded-lg border border-tinta-200 bg-folha p-3 shadow-lg outline-none"
          role="region"
          aria-label="Ações sobre as perguntas selecionadas"
        >
          <div className="flex flex-wrap items-center gap-2">
            {escolhidas.length > 0 && (
              <>
                <span className="text-sm font-semibold text-tinta-900">
                  {escolhidas.length} {escolhidas.length === 1 ? "selecionada" : "selecionadas"}
                </span>
                <BotaoCopiar texto={listaNumerada(escolhidas)} rotulo="Copiar" />
                <button type="button" className="btn-secundario" onClick={() => setDialogo(true)}>
                  Gerar e-mail
                </button>
                <button
                  type="button"
                  className="btn-secundario"
                  disabled={ocupado}
                  onClick={() => registrar()}
                  title="Registra o envio de cada pergunta selecionada, com o texto exato de cada uma. O registro não pode ser apagado."
                >
                  {ocupado ? "Registrando…" : "Marcar como enviadas"}
                </button>
                <button
                  type="button"
                  className="text-xs font-medium text-tinta-500 hover:text-tinta-700"
                  onClick={() => definir(escolhidas.map((p) => p.chave), false)}
                >
                  Limpar seleção
                </button>
              </>
            )}
          </div>
          {aviso && (
            <p
              role="status"
              className={`mt-2 text-xs ${aviso.erro ? "font-medium text-risco-700" : "text-ok-700"}`}
            >
              {aviso.texto}
            </p>
          )}
        </div>
      )}
      {dialogo && escolhidas.length > 0 && (
        <EmailAoClienteDialogo
          mandato={mandato}
          perguntas={escolhidas}
          ocupado={ocupado}
          aviso={aviso}
          onFechar={() => setDialogo(false)}
          onRegistrar={registrar}
        />
      )}
    </Selecao.Provider>
  );
}

/** A caixa de um cartão pendente. */
export function CaixaDeSelecao({ chave, titulo }: Readonly<{ chave: string; titulo: string }>) {
  const ctx = useContext(Selecao);
  if (!ctx) return null;
  return (
    <input
      type="checkbox"
      className="h-4 w-4 shrink-0 accent-acento-600"
      checked={ctx.marcadas.has(chave)}
      onChange={() => ctx.alternar(chave)}
      aria-label={`Selecionar: ${titulo}`}
    />
  );
}

/** "Selecionar todas" — de uma prioridade (`prioridade`) ou da lista inteira (omitida). */
export function SelecionarTodas({
  prioridade, rotulo,
}: Readonly<{ prioridade?: number; rotulo: string }>) {
  const ctx = useContext(Selecao);
  if (!ctx) return null;
  const alvo = ctx.pendentes.filter((p) => prioridade === undefined || p.prioridade === prioridade);
  if (alvo.length === 0) return null;
  const todas = alvo.every((p) => ctx.marcadas.has(p.chave));
  return (
    <button
      type="button"
      className="text-xs font-medium text-acento-600 hover:text-acento-700 hover:underline"
      onClick={() => ctx.definir(alvo.map((p) => p.chave), !todas)}
    >
      {todas ? "Desmarcar" : "Selecionar"} {rotulo} ({alvo.length})
    </button>
  );
}
