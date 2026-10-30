import Link from "next/link";
import { NovoMandatoPasso1 } from "@/components/novo-mandato-passo1";
import { TOTAL_DE_PASSOS, textoDoPasso } from "@/lib/passo-do-mandato";
import { MarcaOria } from "@/components/marca-oria";
import { lerPermissoes } from "@/lib/supabase/acesso";
import { FaixaDeAcesso } from "@/components/acesso-na-tela";

// A TELA DE ABRIR MANDATO É A PRIMEIRA COISA QUE ALGUÉM FAZ NO PRODUTO, e ela
// era um formulário estreito (`max-w-2xl`) encostado à esquerda, com um título
// pequeno e um link de voltar em cima. Parecia um passo secundário de outra
// tela.
//
// Agora ela OCUPA A TELA: sem a barra lateral competindo, com o que vai
// acontecer escrito ao lado do formulário. As três etapas não são decoração —
// elas respondem à pergunta que trava quem sobe 38 arquivos pela primeira vez
// ("e agora, o que o sistema faz com isso?"), e é a mesma resposta que o rodapé
// dá em uma linha: nada vira fato sem alguém aceitar.
export default async function NovoMandatoPage() {
  // Leitura não abre mandato (o banco recusa o INSERT): o botão some da barra e quem chega pelo
  // endereço lê o motivo, em vez de preencher um formulário que falharia no fim.
  const { criarMandato } = await lerPermissoes();
  if (!criarMandato.pode) {
    return (
      <div className="mx-auto max-w-xl space-y-4 py-8">
        <h1 className="font-titulo text-2xl font-medium text-tinta-900">Novo mandato</h1>
        <FaixaDeAcesso liberacao={criarMandato} />
        <Link href="/casos/todos" className="btn-secundario">Voltar aos mandatos</Link>
      </div>
    );
  }
  return (
    <div>
      <div className="mx-auto grid gap-10 py-2 lg:grid-cols-[1.15fr_1fr] lg:py-6">
        {/* COLUNA DA AÇÃO */}
        <div className="order-2 lg:order-1">
          <Link
            href="/casos/todos"
            className="text-sm text-tinta-500 transition-colors hover:text-tinta-900"
          >
            ← Voltar aos mandatos
          </Link>
          <p className="mt-3 text-xs font-semibold uppercase tracking-wide text-acento-700">
            {textoDoPasso({ passo: 1, total: TOTAL_DE_PASSOS })} · Dados do mandato
          </p>
          <h1 className="mt-1 font-titulo text-3xl font-medium tracking-tight text-tinta-900">
            Novo mandato
          </h1>
          <p className="mt-1.5 max-w-lg text-sm text-tinta-600">
            Dê um nome ao mandato. No próximo passo você sobe os arquivos brutos como o cliente enviou —
            nomes bagunçados, PDF escaneado e planilha exportada do ERP inclusive — ou deixa para depois.
          </p>

          <div className="mt-6">
            <NovoMandatoPasso1 />
          </div>
        </div>

        {/* COLUNA DO CONTEXTO */}
        <aside className="order-1 lg:order-2">
          <div className="carta p-6">
            <div className="flex items-center gap-3 border-b border-tinta-100 pb-4">
              <MarcaOria variante="sextante" className="h-10 w-10" />
              <div>
                <p className="text-sm font-semibold text-tinta-900">O que acontece depois</p>
                <p className="text-xs text-tinta-500">em geral entre 5 e 25 minutos</p>
              </div>
            </div>

            <ol className="mt-4 space-y-4">
              {[
                {
                  n: "1",
                  t: "Cada arquivo é identificado",
                  d: "Pelo nome quando ele basta; lendo o conteúdo quando não basta. Documento que ficar em dúvida vai para a fila de revisão em vez de ser adivinhado.",
                },
                {
                  n: "2",
                  t: "As linhas financeiras são extraídas",
                  d: "Conta, valor, período e entidade, com a origem preservada. Documento grande é fatiado para caber inteiro, e o que voltar pela metade abre pendência.",
                },
                {
                  n: "3",
                  t: "Os números são conferidos entre si",
                  d: "O balanço tem de fechar, o caixa do balanço bater com o do fluxo, e conta contada duas vezes é denunciada. O que não fecha aparece com os dois números.",
                },
              ].map((p) => (
                <li key={p.n} className="flex gap-3">
                  <span
                    aria-hidden
                    className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full
                               bg-acento-50 text-xs font-semibold text-acento-700"
                  >
                    {p.n}
                  </span>
                  <div>
                    <p className="text-sm font-medium text-tinta-900">{p.t}</p>
                    <p className="mt-0.5 text-xs leading-relaxed text-tinta-500">{p.d}</p>
                  </div>
                </li>
              ))}
            </ol>

            <p className="mt-5 rounded-lg bg-tinta-50 px-3 py-2.5 text-xs leading-relaxed text-tinta-600">
              Nada disso vira fato sozinho: o que o sistema extrai é <strong>sugestão</strong> até
              alguém aceitar, e o mandato só é aprovado quando não sobra pendência bloqueante.
            </p>
          </div>
        </aside>
      </div>
    </div>
  );
}
