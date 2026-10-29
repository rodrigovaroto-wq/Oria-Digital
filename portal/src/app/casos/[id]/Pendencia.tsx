// COMO UMA PENDÊNCIA APARECE NA TELA.
//
// POR QUE VIROU COMPONENTE. As mensagens de pendência são geradas no banco (é lá que
// a medição acontece) e chegam como UM parágrafo com vários fatos emendados por `;`,
// citando coluna, entidade e período no vocabulário interno. Antes cada seção da tela
// jogava esse texto inteiro num `<li>`, e o resultado era um bloco de seis linhas em
// que o fato principal — o que está errado e onde — ficava no meio.
//
// O pedido do dono (07/08/2026): um fato por linha, com travessão; e a tela tem de
// dizer EM QUAL ARQUIVO está o problema.
//
// SOBRE "EM QUAL LINHA". O sistema não guarda número de linha do PDF — o extrator
// devolve conta, coluna e valor, não coordenada de página. O que existe, e é o que
// serve para achar o erro no original, é o RÓTULO da conta e a COLUNA (período /
// entidade). Então é isso que fica em destaque: os rótulos citados pela mensagem
// aparecem como uma lista à parte, que é a "linha" no sentido de quem vai conferir.
// Inventar número de linha seria dar precisão falsa a quem precisa procurar.
//
// E POR QUE ELA GANHOU UM BOTÃO (07/08/2026). O portal só sabia dizer sim: a
// única ação do Portão 2 era *aprovar*, que é exatamente o que a regra proíbe
// enquanto houver pendência bloqueante viva. Quem olhava um caso travado por uma
// pendência que NÃO PROCEDE — o motor errou, a conta está no outro documento —
// não tinha o que fazer na tela. `Arquitetura do Sistema/2 Especificação/f0/04` prevê esse caminho desde a F0
// (`rejeitada`); faltava código e faltava botão.
import Link from "next/link";
import { partesDaDescricao, rotuloDaPendencia, rotulosCitados, semALista, suavizarMensagem } from "@/lib/rotulos";
import { rotuloDeTipoConhecido } from "@/lib/export";
import { BOTOES_DECISAO, ROTULO_POR_ESTADO, rotuloDoEstado } from "@/lib/pendencia";
import { decidirPendencia } from "./actions";
import { FormDeAcao } from "@/components/form-de-acao";

export interface PendenciaNaTela {
  id: string;
  tipo: string;
  descricao: string | null;
  documento_id: string | null;
  severidade?: string;
  /** estado de Arquitetura do Sistema/2 Especificação/f0/04: `aberta`, um dos dois de tratamento, ou um dos decididos */
  estado?: string;
}

export function ItemPendencia({
  p, arquivo, tom, casoId,
}: {
  p: PendenciaNaTela;
  /** nome do arquivo de origem, quando a pendência aponta para um documento */
  arquivo: string | null;
  tom: "amber" | "red";
  /** quando informado, o item ganha a ação de declarar a pendência improcedente */
  casoId?: string;
}) {
  const cores = tom === "red"
    ? { caixa: "border-risco-200 bg-risco-50 text-risco-900", chip: "bg-risco-100 text-risco-800", fraco: "text-risco-700" }
    : { caixa: "border-alerta-200 bg-alerta-50 text-alerta-900", chip: "bg-alerta-100 text-alerta-800", fraco: "text-alerta-700" };

  // O CÓDIGO DA TAXONOMIA VIRA O NOME DO DOCUMENTO. A mensagem do banco diz
  // "Item obrigatório do Kit Básico ausente: COMBINADO" — `COMBINADO` é a chave
  // primária da taxonomia, não o nome de nada que o cliente reconheça. A tela já
  // sabe traduzir (`formatarTipoTaxonomia`); faltava aplicar aqui.
  const bruto = (p.descricao ?? "Sem descrição.").replace(
    /\b([A-Z][A-Z0-9_]{3,})\b/g,
    (m) => rotuloDeTipoConhecido(m) ?? m,
  );
  const rotulos = rotulosCitados(bruto);
  const partes = partesDaDescricao(suavizarMensagem(semALista(bruto)));

  return (
    <li className={`rounded-lg border px-3.5 py-3 text-sm ${cores.caixa}`}>
      <div className="mb-1 flex flex-wrap items-center gap-2">
        <span className={`chip ${cores.chip}`}>{rotuloDaPendencia(p.tipo)}</span>
        {/* O ARQUIVO, quando se sabe qual é. "Sem arquivo específico" não é falha:
            divergência entre documentos é do CASO, não de um deles — e dizer isso é
            melhor que deixar o espaço vazio, que se lê como informação perdida. */}
        <span className={`text-xs ${cores.fraco}`}>
          {arquivo ? `Arquivo: ${arquivo}` : "Vale para o caso, não para um arquivo específico"}
        </span>
        {/* O ANDAMENTO, quando alguém já mexeu. Sem isto, uma pendência que já foi
            pedida ao cliente é visualmente idêntica a uma que ninguém tocou — e o
            resultado é pedir duas vezes. */}
        {p.estado && p.estado !== "aberta" && (
          <span className={`chip ${ROTULO_POR_ESTADO[p.estado]?.chip ?? "bg-tinta-200 text-tinta-600"}`}>
            {ROTULO_POR_ESTADO[p.estado]?.rotulo ?? rotuloDoEstado(p.estado)}
          </span>
        )}
      </div>

      {/* UM FATO POR LINHA, com travessão. A primeira parte é a frase principal e
          vem sem marcador; as demais são qualificações dela. */}
      <p className="valor-sensivel font-medium">{partes[0]}</p>
      {partes.length > 1 && (
        <ul className="mt-1 space-y-0.5">
          {partes.slice(1).map((parte, i) => (
            <li key={i} className="flex gap-1.5">
              <span aria-hidden className={cores.fraco}>—</span>
              <span className="valor-sensivel">{parte}</span>
            </li>
          ))}
        </ul>
      )}

      {rotulos.length > 0 && (
        <div className="mt-1.5">
          <p className={`text-xs font-medium ${cores.fraco}`}>
            Onde conferir no arquivo — {rotulos.length === 1 ? "esta linha" : `estas ${rotulos.length} linhas`}:
          </p>
          <ul className="mt-0.5 flex flex-wrap gap-1">
            {rotulos.map((r) => (
              <li key={r} className={`chip ${cores.chip}`}>{r}</li>
            ))}
          </ul>
        </div>
      )}

      {/* OS TRÊS BOTÕES (0109). Sem formulário: nem motivo, nem data.
          Pedido do dono — o clique registra a decisão e o rótulo colorido passa
          a aparecer no topo do item.

          FICAM VISÍVEIS, sem `<details>`. A versão anterior escondia a ação
          atrás de um clique a mais, de propósito, para que declarar improcedente
          não fosse o caminho mais curto. Com três botões e nenhum campo, esse
          cuidado vira só atrito: a decisão agora É a interface. */}
      {casoId && (
        <div className="mt-2 flex flex-wrap items-start gap-x-4 gap-y-2 border-t border-folha/40 pt-2">
          {/* O EFEITO FICA À VISTA, embaixo de cada botão (fase 2). Ele morava só no
              `title=`, que não existe no toque e some antes de ser lido: quem clicava
              em "Prosseguir sem resolução" descobria o que tinha feito DEPOIS. */}
          {BOTOES_DECISAO.map((b) => (
            <FormDeAcao key={b.decisao} action={decidirPendencia.bind(null, casoId, p.id, b.decisao)} className="max-w-[15rem]">
              <button
                type="submit"
                className={`rounded-md border px-2.5 py-1.5 text-xs font-semibold transition-colors ${b.classe}`}
              >
                {b.rotulo}
              </button>
              <p className={`mt-1 text-xs leading-snug ${cores.fraco}`}>{b.efeito}</p>
            </FormDeAcao>
          ))}
          {/* A PONTE PARA A ABA DAS PERGUNTAS (0120), e só depois de "Contatar o
              Cliente" ter sido clicado.

              O botão rotula a pendência — ele não escreve o e-mail. Quem
              acabou de dizer "vou falar com o cliente" está exatamente no
              momento em que precisa do texto pronto, e sem esta linha não há
              nada na tela que diga que ele existe.

              É UM LINK, não a pergunta embutida aqui: a lista de pendências é
              decisão sobre problema medido, e a aba é o que ainda não foi
              perguntado. As duas continuam separadas — o que se acrescenta é o
              caminho de uma para a outra. */}
          {p.estado === "reenviada_ao_cliente" && (
            <Link
              href={`/casos/${casoId}/perguntas`}
              className={`text-xs font-medium underline-offset-2 hover:underline ${cores.fraco}`}
            >
              ver a pergunta pronta para o cliente
            </Link>
          )}
        </div>
      )}
    </li>
  );
}
