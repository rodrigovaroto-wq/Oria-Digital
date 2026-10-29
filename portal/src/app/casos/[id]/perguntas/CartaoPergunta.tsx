// UMA PERGUNTA SUGERIDA, COMO ELA APARECE NA TELA.
//
// A ORDEM DO CARTÃO É A ORDEM DE QUEM USA: primeiro o TEXTO PRONTO (é o que vai
// ser copiado e colado num e-mail), depois o botão de copiar e o registro do que
// se fez, e só então o porquê — motivo, risco, impacto e a origem da pergunta.
// A versão que começa pelo motivo obriga a ler três parágrafos internos antes de
// chegar à única coisa que sai da casa.
//
// ELE NÃO É COMPONENTE DE CLIENTE. Os dois botões de registro são formulários
// com server action — funcionam sem JavaScript, e é o servidor que fala com o
// banco. Só o copiar precisa do navegador, e é ele, sozinho, que é "use client".
import { BotaoCopiar } from "@/components/botao-copiar";
import {
  chaveDaSugestao,
  chipDaPrioridade,
  dataCurta,
  motivoDoDisparo,
  rotuloDaPrioridade,
  type AcaoDePergunta,
  type PerguntaSugerida,
} from "@/lib/perguntas";
import { registrarAcaoDaPergunta } from "./actions";
import { FormDeAcao } from "@/components/form-de-acao";

import { ZonaDeEscrita } from "@/components/acesso-na-tela";
import { CaixaDeSelecao } from "./SelecaoDePerguntas";

export function CartaoPergunta({
  casoId,
  p,
  acoes,
  selecionavel = false,
  somenteLeitura = false,
}: {
  casoId: string;
  p: PerguntaSugerida;
  /** o que já se registrou sobre ESTE par (pergunta, empresa), da mais recente à mais antiga */
  acoes: AcaoDePergunta[];
  /** pendente: ganha a caixa de seleção do lote (as já tratadas se decidem uma a uma, aqui no cartão) */
  selecionavel?: boolean;
  /** Papel sem escrita neste mandato: os dois registros (enviada, descartada) ficam desabilitados; copiar continua. */
  somenteLeitura?: boolean;
}) {
  const registrar = registrarAcaoDaPergunta.bind(null, casoId);
  const ultimoEnvio = acoes.find((a) => a.acao === "enviada");
  const ultimoDescarte = acoes.find((a) => a.acao === "descartada");
  // `ja_enviada` VEM DO BANCO e é quem manda: é a mesma expressão que a 0120
  // usa, casando por (caso, código, empresa). O que a tela acrescenta é só o
  // quem/quando, que a função não devolve.
  const enviada = p.ja_enviada;
  // Descartada DEPOIS do último envio é um caso real: perguntei, o cliente não
  // respondeu, decidi tocar sem a resposta. Quem manda é a ação mais recente.
  const descartadaAgora =
    !!ultimoDescarte && (!ultimoEnvio || ultimoDescarte.criado_em > ultimoEnvio.criado_em);

  return (
    <li className={`carta p-4 ${enviada || descartadaAgora ? "opacity-90" : ""}`}>
      <div className="flex flex-wrap items-center gap-2">
        {selecionavel && (
          <CaixaDeSelecao chave={chaveDaSugestao(p.codigo, p.entidade_id)} titulo={p.titulo} />
        )}
        <span className={`chip ${chipDaPrioridade(p.prioridade)}`}>
          {p.prioridade} · {rotuloDaPrioridade(p.prioridade)}
        </span>
        <span className="text-sm font-semibold text-tinta-900">{p.titulo}</span>
        {/* A EMPRESA. Num grupo de oito balanços a mesma pergunta aparece oito
            vezes, uma por empresa que não satisfaz — sem o nome aqui, as oito
            são visualmente idênticas. */}
        {p.entidade && (
          <span className="chip bg-tinta-100 text-tinta-700">{p.entidade}</span>
        )}
        {enviada && (
          <span className="chip bg-ok-100 text-ok-800">já enviada</span>
        )}
        {descartadaAgora && (
          <span className="chip bg-tinta-200 text-tinta-600">descartada</span>
        )}
        <span className="ml-auto text-xs text-tinta-400" title="código da pergunta no catálogo">
          catálogo · {p.codigo}
        </span>
      </div>

      {/* O TEXTO QUE VAI AO CLIENTE. Fundo próprio e `whitespace-pre-wrap`: é
          uma citação do que será enviado, não um parágrafo da interface. */}
      <p className="valor-sensivel mt-2.5 rounded-md border border-tinta-200 bg-tinta-50 px-3 py-2.5 text-sm
                    whitespace-pre-wrap text-tinta-900">
        {p.pergunta}
      </p>

      <div className="mt-2.5 flex flex-wrap items-center gap-2">
        <BotaoCopiar texto={p.pergunta} />
        <ZonaDeEscrita pode={!somenteLeitura} className="flex flex-wrap items-center gap-2">

        {/* REGISTRAR O ENVIO. O texto exato da tela vai no campo oculto: é ele
            que a 0120 congela, e é ele que responde "o que exatamente foi
            perguntado a este cliente?" seis meses depois. */}
        <FormDeAcao action={registrar}>
          <input type="hidden" name="codigo" value={p.codigo} />
          <input type="hidden" name="entidade_id" value={p.entidade_id ?? ""} />
          <input type="hidden" name="acao" value="enviada" />
          <input type="hidden" name="texto" value={p.pergunta} />
          <button
            type="submit"
            className="rounded-md border border-ok-200 bg-ok-50 px-2.5 py-1.5 text-xs
                       font-semibold text-ok-800 transition-colors hover:bg-ok-100"
          >
            {enviada ? "Registrar novo envio" : "Marcar como enviada"}
          </button>
        </FormDeAcao>

        <FormDeAcao action={registrar}>
          <input type="hidden" name="codigo" value={p.codigo} />
          <input type="hidden" name="entidade_id" value={p.entidade_id ?? ""} />
          <input type="hidden" name="acao" value="descartada" />
          <input type="hidden" name="texto" value={p.pergunta} />
          <button
            type="submit"
            className="rounded-md border border-tinta-200 bg-folha px-2.5 py-1.5 text-xs
                       font-medium text-tinta-600 transition-colors hover:bg-tinta-50"
          >
            Não vou perguntar
          </button>
        </FormDeAcao>
        </ZonaDeEscrita>
      </div>

      {/* O QUE CADA BOTÃO FAZ. Estava só em title= (some no celular, passa
          despercebido no desktop); quem decide precisa ler antes de clicar. */}
      <ul className="mt-2 space-y-0.5 text-xs text-tinta-500">
        <li>
          <span className="font-medium text-tinta-700">{enviada ? "Registrar novo envio" : "Marcar como enviada"}:</span>{" "}
          registra que esta pergunta foi enviada ao cliente, com o texto exato acima. O registro
          não pode ser apagado, e enviar de novo cria outro registro.
        </li>
        <li>
          <span className="font-medium text-tinta-700">Não vou perguntar:</span>{" "}
          registra que esta pergunta NÃO será feita — a sugestão continua na lista, com o rótulo.
          Serve para dizer à equipe que alguém já olhou e decidiu não perguntar.
        </li>
      </ul>

      {/* QUEM E QUANDO. Sem isto, "já enviada" não diz se foi hoje ou em março,
          nem por quem — e é a diferença entre cobrar o cliente e perguntar duas
          vezes a mesma coisa. */}
      {acoes.length > 0 && (
        <ul className="mt-2 space-y-0.5 text-xs text-tinta-500">
          {acoes.slice(0, 3).map((a) => (
            <li key={a.id}>
              {a.acao === "enviada" ? "enviada" : "descartada"} por{" "}
              <span className="text-tinta-700">{a.autor}</span> em {dataCurta(a.criado_em)}
            </li>
          ))}
          {acoes.length > 3 && (
            <li className="text-tinta-400">e mais {acoes.length - 3} registro(s)</li>
          )}
        </ul>
      )}

      {/* O PORQUÊ, recolhido. Motivo, risco e impacto são o que sustenta a
          pergunta numa reunião — e são três parágrafos que ninguém quer ler
          toda vez que abre a lista para copiar um texto. */}
      <details className="group mt-2.5">
        <summary className="cursor-pointer list-none text-xs font-medium text-acento-600
                            hover:text-acento-700">
          <span className="group-open:hidden">Por que perguntar isso</span>
          <span className="hidden group-open:inline">Recolher</span>
        </summary>
        <div className="mt-2 space-y-2 border-l-2 border-tinta-100 pl-3 text-xs text-tinta-600">
          <p>
            <span className="font-semibold text-tinta-800">O que disparou: </span>
            {motivoDoDisparo(p.gatilho)}
          </p>
          <p>
            <span className="font-semibold text-tinta-800">Motivo: </span>
            <span className="valor-sensivel">{p.motivo}</span>
          </p>
          <p>
            <span className="font-semibold text-tinta-800">Risco: </span>
            <span className="valor-sensivel">{p.risco}</span>
          </p>
          <p>
            <span className="font-semibold text-tinta-800">Impacto: </span>
            <span className="valor-sensivel">{p.impacto}</span>
          </p>
          <p className="text-tinta-400">Fonte: {p.fonte}</p>
        </div>
      </details>
    </li>
  );
}
