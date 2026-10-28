import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { CAPITULOS_APRESENTACAO } from "@/lib/apresentacao/campos";
import { veredictoDoPortao, type PortaoDoExport } from "@/lib/modelagem-cobertura";
import { FormCapitulo } from "./FormCapitulo";
import { salvarCamposApresentacao } from "./actions";

// ENTREGÁVEIS: os três arquivos do mandato num lugar só, cada um com o seu estado.
//
// POR QUE EXISTE. Os exports estavam espalhados — "Exportar dados" na visão geral e na Modelagem,
// até 4 variantes de botão na Modelagem ("Exportar dados", "Exportar modelagem", "Campos da
// apresentação", "Gerar apresentação de crédito") e "Gerar apresentação" na aba Apresentação: 6
// links em 3 telas para 3 arquivos (contados nos `href` do código anterior: 1 + 4 + 1), e o
// analista não sabia qual era qual nem se estava liberado.
//
// O ESTADO DE CADA CARTÃO vem das MESMAS regras da rota `/export`, não de uma cópia delas:
//   • Base de dados: nunca depende da aprovação (é insumo de conferência; bloqueá-la criaria o
//     impasse de precisar aprovar para poder conferir). Sempre disponível.
//   • Modelo e Apresentação: `fn_avaliar_portao2` lida por `veredictoDoPortao` — a mesma função
//     da Modelagem e da rota. Três estados, nunca dois: aberto, fechado (com motivos) e NÃO
//     CONFERIDO (RPC falhou), que NUNCA mostra o botão (regra 1: desconhecido não é aberto).
//   • A Apresentação ainda exige o modelo montado (a rota devolve 409 sem entidade modelada,
//     último exercício real e anos projetados): essa parte é lida de `caso_modelagem`.
type Estado = "disponivel" | "bloqueado" | "nao_conferido";

const CHIP: Record<Estado, { classe: string; palavra: string }> = {
  disponivel: { classe: "bg-ok-100 text-ok-800", palavra: "Disponível" },
  bloqueado: { classe: "bg-alerta-100 text-alerta-900", palavra: "Bloqueado" },
  nao_conferido: { classe: "bg-tinta-100 text-tinta-600", palavra: "Não conferido" },
};

function Cartao({ titulo, formato, oQueE, estado, children }: Readonly<{
  titulo: string; formato: string; oQueE: string; estado: Estado; children: React.ReactNode;
}>) {
  const chip = CHIP[estado];
  return (
    <section className="carta flex flex-col gap-3 p-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h2 className="text-sm font-semibold text-tinta-900">{titulo}</h2>
          <p className="text-xs text-tinta-500">{formato}</p>
        </div>
        <span className={`chip ${chip.classe}`}>{chip.palavra}</span>
      </div>
      <p className="text-sm text-tinta-700">{oQueE}</p>
      <div className="mt-auto space-y-2 text-sm">{children}</div>
    </section>
  );
}

function Motivos({ portao, id }: Readonly<{ portao: PortaoDoExport | null; id: string }>) {
  const motivos = portao?.motivos ?? [];
  return (
    <div className="space-y-2 text-alerta-900">
      <p>Aguarda a aprovação do mandato{motivos.length ? ":" : "."}</p>
      {motivos.length > 0 && <ul className="list-disc space-y-0.5 pl-5">{motivos.map((m) => <li key={m}>{m}</li>)}</ul>}
      <p>
        Decida as pendências na aba <Link href={`/casos/${id}/pendencias`} className="underline">Pendências</Link>.
      </p>
    </div>
  );
}

function NaoConferido({ id, o }: Readonly<{ id: string; o: string }>) {
  return (
    <output className="block text-alerta-900">
      Não foi possível conferir a aprovação do mandato (a consulta falhou ou não devolveu veredito),
      então o download {o} fica retido — liberar sem saber se a base foi aprovada daria aparência de
      resultado aprovado a número que ninguém aprovou. Recarregue a página; se persistir, avise o
      administrador. A <a href={`/casos/${id}/export?modo=dados`} className="underline">base de dados</a> segue disponível.
    </output>
  );
}

// OS CAMPOS "[a preencher]" DA APRESENTAÇÃO DE CRÉDITO (seção `#campos`, abaixo dos cartões).
//
// Os números do deck vêm do realizado (Modelagem); aqui fica o que só o analista ou a pesquisa
// sabem — títulos dos slides de pesquisa, tendências, sócios, concorrentes, notas do scorecard,
// contatos. Campo em branco continua "[a preencher]" no deck: nada é inventado no lugar.
export default async function EntregaveisPage({ params }: Readonly<{ params: Promise<{ id: string }> }>) {
  const { id } = await params;
  const supabase = await createClient();
  const [camposRes, portaoRes, modeloRes] = await Promise.all([
    supabase.from("caso_apresentacao_campo").select("chave, valor").eq("caso_id", id),
    // A MESMA RPC e a MESMA leitura da Modelagem e da rota `/export`.
    supabase.rpc("fn_avaliar_portao2", { p_caso_id: id }),
    // As três coisas sem as quais a rota recusa a apresentação com 409 (`entradaDoModeloDoWorkbook`).
    supabase.from("caso_modelagem").select("entidade, ultimo_exercicio_real, anos_projetados").eq("caso_id", id).maybeSingle(),
  ]);
  const { estado: estadoPortao, portao } = veredictoDoPortao(portaoRes);
  // Falta de configuração é uma resposta ("não montou o modelo"); erro de leitura é outra ("não sei").
  const modeloLido = !modeloRes.error;
  const m = modeloRes.data as { entidade: string | null; ultimo_exercicio_real: number | null; anos_projetados: number | null } | null;
  const faltaNoModelo = [
    !m?.entidade?.trim() && "a entidade modelada",
    m?.ultimo_exercicio_real == null && "o último exercício real",
    !m?.anos_projetados && "os anos projetados",
  ].filter((x): x is string => typeof x === "string");

  const valores = Object.fromEntries(((camposRes.data ?? []) as Array<{ chave: string; valor: string }>).map((c) => [c.chave, c.valor]));
  // Leitura que falhou NÃO é "0 preenchidos" (regra 1): vira "não lido" e a faixa de erro abaixo explica.
  const preenchidos = camposRes.error ? "não lido" : String(Object.keys(valores).length);
  // Amarrada AQUI, no servidor: o id do caso não passa pelo navegador como dado editável.
  const salvar = salvarCamposApresentacao.bind(null, id);
  const total = CAPITULOS_APRESENTACAO.reduce((t, c) => t + c.campos.length, 0);

  let estadoModelo: Estado = "nao_conferido";
  if (estadoPortao === "aberto") estadoModelo = "disponivel";
  else if (estadoPortao === "fechado") estadoModelo = "bloqueado";
  let estadoApresentacao: Estado = estadoModelo;
  if (estadoPortao === "aberto" && !modeloLido) estadoApresentacao = "nao_conferido";
  else if (estadoPortao === "aberto" && faltaNoModelo.length > 0) estadoApresentacao = "bloqueado";

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-lg font-semibold text-tinta-900">Entregáveis</h1>
        <p className="mt-0.5 text-sm text-tinta-500">
          Os três arquivos deste mandato, cada um com o que precisa estar pronto para sair.
        </p>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Cartao titulo="Base de dados" formato="Excel (.xlsx)" estado="disponivel"
          oQueE="Todas as linhas extraídas, documento a documento, sem modelagem — para conferir contra os originais.">
          <p className="text-tinta-500">Sempre disponível: serve justamente para conferir antes de aprovar.</p>
          <a href={`/casos/${id}/export?modo=dados`} className="btn-secundario">Baixar base de dados</a>
        </Cartao>

        <Cartao titulo="Modelo" formato="Excel (.xlsx)" estado={estadoModelo}
          oQueE="As 14 abas do modelo institucional, projetadas e editáveis em fórmula dentro do Excel, mais a Modelagem e os índices macro. Sem as abas de dado cru.">
          {estadoPortao === "aberto" && (
            <>
              {/* `elegivel` do portão, não o status: o mandato pode estar "Em revisão" e já
                  liberar o modelo. Dizer "aprovação concluída" afirmava uma aprovação que
                  não aconteceu (revisão do PR #265). */}
              <p className="text-tinta-500">O mandato atende às condições de aprovação.</p>
              <a href={`/casos/${id}/export`} className="btn-primario">Baixar modelo</a>
            </>
          )}
          {estadoPortao === "fechado" && <Motivos portao={portao} id={id} />}
          {estadoPortao === "nao_conferido" && <NaoConferido id={id} o="do modelo" />}
        </Cartao>

        <Cartao titulo="Apresentação de crédito" formato="PowerPoint (.pptx)" estado={estadoApresentacao}
          oQueE="O módulo de crédito no padrão visual Oria: base de informação, evolução financeira, capital de giro, comparativo e amarrações. Precisa do modelo pronto — lê o mesmo realizado dele.">
          {estadoPortao === "fechado" && <Motivos portao={portao} id={id} />}
          {estadoPortao === "nao_conferido" && <NaoConferido id={id} o="da apresentação" />}
          {estadoPortao === "aberto" && !modeloLido && (
            <output className="block text-alerta-900">
              Não foi possível ler a configuração do modelo, então o download fica retido até a leitura
              responder. Recarregue a página.
            </output>
          )}
          {estadoPortao === "aberto" && modeloLido && faltaNoModelo.length > 0 && (
            <p className="text-alerta-900">
              O modelo ainda não está montado: falta definir {faltaNoModelo.join(", ")} na{" "}
              <Link href={`/casos/${id}/modelagem`} className="underline">Modelagem</Link>. Sem isso a
              apresentação somaria balanços de empresas diferentes ou trataria balancete parcial como ano fechado.
            </p>
          )}
          {estadoApresentacao === "disponivel" && (
            <>
              <p className="text-tinta-500">
                {camposRes.error ? "Contagem de campos preenchidos indisponível" : `${preenchidos} de ${total} campos preenchidos`}; os que faltam saem “[a preencher]” no deck.
                Se o modelo não tiver exercício com valor numérico, a geração é recusada com o motivo.
              </p>
              <a href={`/casos/${id}/export?modo=apresentacao`} className="btn-primario">Baixar apresentação</a>
            </>
          )}
        </Cartao>
      </div>

      <section id="campos" className="scroll-mt-24 space-y-4">
        <div>
          <h2 className="titulo-secao">Campos da apresentação</h2>
          <p className="mt-0.5 text-sm text-tinta-500">
            O que só o analista sabe e completa a apresentação de crédito. {camposRes.error ? `Contagem de campos preenchidos indisponível (${total} no total)` : `${preenchidos} de ${total} campos preenchidos`}. Os números vêm da Modelagem; em branco, o slide sai “[a preencher]”.
          </p>
        </div>
      {camposRes.error && (
        <output className="carta block p-4 text-sm text-alerta-900">
          <p>
            Não foi possível ler os campos já preenchidos. Enquanto isso, o deck sai com todas as
            lacunas “[a preencher]”. Avise o administrador do sistema.
          </p>
          <DetalhesTecnicos>
            <p>{camposRes.error.message}</p>
            <p>Se a tabela não existe, a migration 0205 ainda não foi aplicada.</p>
          </DetalhesTecnicos>
        </output>
      )}
      {CAPITULOS_APRESENTACAO.map((cap) => <FormCapitulo key={cap.titulo} acao={salvar} capitulo={cap} valores={valores} />)}
      </section>
    </div>
  );
}
