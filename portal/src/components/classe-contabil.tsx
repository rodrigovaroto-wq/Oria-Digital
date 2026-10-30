"use client";

import { useState } from "react";
import { registrarClasseContabil } from "@/app/casos/[id]/documentos/[docId]/actions";

// A CLASSE CONTÁBIL DE UMA LINHA, com a sugestão à vista e o override a um clique.
//
// POR QUE A SUGESTÃO E A DECISÃO FICAM VISÍVEIS AO MESMO TEMPO, e não uma no lugar
// da outra. O `Arquitetura do Sistema/2 Especificação/05` chama a discordância entre humano e máquina de "sinal de
// calibração" — o dado que permite ajustar a REGRA. Se a tela substituísse a
// sugestão pela decisão, o analista perderia de vista do que ele está discordando,
// e a próxima pessoa a abrir a linha não saberia que houve discordância. Aqui a
// sugestão continua escrita ao lado, com a justificativa da regra atrás do
// `title`, e quando as duas divergem isso é dito com palavra, não só com cor.
//
// E A SUGESTÃO NÃO VEM PRÉ-SELECIONADA NO SELETOR. É deliberado, e é
// anti-ancoragem (fechamento #5 do `Arquitetura do Sistema/1 Visão e Doutrina/01`): um seletor que abre já preenchido
// com o palpite da máquina transforma "confirmar" no caminho de menor esforço, e o
// aceite deixa de ser uma decisão para virar um clique de inércia. O analista
// escolhe a classe — inclusive quando ela é a mesma que a máquina sugeriu, e nesse
// caso a concordância medida vale algo, porque ele digitou.
//
// SEM SUGESTÃO, SEM SELETOR. Linha de balanço não é recorrente nem não recorrente:
// a pergunta não se aplica, a 0128 não grava sugestão para ela, e a tela não
// oferece um seletor que convidaria a inventar uma resposta.

type Classe = { codigo: string; nome: string };

export function ClasseContabil({
  casoId,
  docId,
  campoId,
  classes,
  sugestao,
  justificativa,
  override,
  overridePor,
}: {
  casoId: string;
  docId: string;
  campoId: string;
  classes: Classe[];
  sugestao: string | null;
  justificativa: string | null;
  override: string | null;
  overridePor: string | null;
}) {
  const [aberto, setAberto] = useState(false);
  const [enviando, setEnviando] = useState(false);
  // A recusa do banco vem como valor da action (em produção o Next redige o texto de um erro lançado).
  const [erro, setErro] = useState<string | null>(null);

  // A pergunta não se aplica a esta linha.
  if (!sugestao && !override) {
    return <span className="text-xs text-tinta-400">—</span>;
  }

  const nomeDe = (codigo: string | null) =>
    classes.find((c) => c.codigo === codigo)?.nome ?? codigo ?? "—";
  const discordou = override != null && sugestao != null && override !== sugestao;

  return (
    <div className="space-y-1">
      {override ? (
        <>
          <span className="inline-block rounded bg-tinta-900 px-1.5 py-0.5 text-xs font-medium text-papel">
            {nomeDe(override)}
          </span>
          <p className="text-xs text-tinta-500">
            por {overridePor ?? "—"}
            {discordou && (
              <>
                {" · "}
                <span className="text-alerta-800">
                  a regra sugeria {nomeDe(sugestao)}
                </span>
              </>
            )}
          </p>
        </>
      ) : (
        <>
          <span
            className="inline-block rounded border border-dashed border-tinta-300 px-1.5 py-0.5 text-xs text-tinta-600"
          >
            {nomeDe(sugestao)}
          </span>
          {/* A palavra "sugerido" fica escrita. Sem ela, a borda tracejada seria a
              única coisa distinguindo um palpite de uma decisão — e cor e traço
              não carregam significado sozinhos nesta casa. */}
          <p className="text-xs text-tinta-400">sugerido, não confirmado</p>
          {justificativa && (
            <p className="text-xs text-tinta-500">Regra: {justificativa}</p>
          )}
        </>
      )}

      {aberto ? (
        <form
          className="flex flex-wrap items-center gap-1 pt-1"
          action={async (formData) => {
            setEnviando(true);
            setErro(null);
            try {
              const r = await registrarClasseContabil(casoId, docId, formData);
              if (r?.erro) setErro(r.erro);
              else setAberto(false);
            } finally {
              setEnviando(false);
            }
          }}
        >
          <input type="hidden" name="campo_extraido_id" value={campoId} />
          <select
            name="classe"
            required
            defaultValue=""
            aria-label="Classe contábil"
            className="rounded border border-tinta-300 bg-folha px-1 py-0.5 text-xs"
          >
            {/* Vazio e obrigatório: o navegador barra o envio sem escolha, e a
                sugestão da máquina não fica pré-selecionada. */}
            <option value="" disabled>
              escolher…
            </option>
            {classes.map((c) => (
              <option key={c.codigo} value={c.codigo}>
                {c.nome}
              </option>
            ))}
          </select>
          <input
            type="text"
            name="motivo"
            placeholder="motivo (opcional)"
            className="w-40 rounded border border-tinta-300 bg-folha px-1 py-0.5 text-xs"
          />
          <button
            type="submit"
            disabled={enviando}
            className="rounded bg-tinta-900 px-2 py-0.5 text-xs font-medium text-papel disabled:opacity-50"
          >
            {enviando ? "gravando…" : "gravar"}
          </button>
          <button
            type="button"
            onClick={() => setAberto(false)}
            className="px-1 text-xs text-tinta-500 underline"
          >
            cancelar
          </button>
          {erro && <span role="alert" className="w-full text-xs font-medium text-risco-700">{erro}</span>}
        </form>
      ) : (
        <button
          type="button"
          onClick={() => setAberto(true)}
          className="text-xs text-acento-600 underline"
        >
          {override ? "reclassificar" : "classificar"}
        </button>
      )}
    </div>
  );
}
