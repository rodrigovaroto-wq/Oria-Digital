import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import {
  PRIORIDADE,
  chaveDaSugestao,
  dataCurta,
  rotuloDaPrioridade,
  type AcaoDePergunta,
  type PerguntaSugerida,
} from "@/lib/perguntas";
import { CartaoPergunta } from "./CartaoPergunta";
import { ProvedorDeSelecao, SelecionarTodas, type PendenteSelecionavel } from "./SelecaoDePerguntas";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";

// A ABA DAS PERGUNTAS AO CLIENTE.
//
// O motor é a `0120` — `fn_sugerir_perguntas(caso)` devolve a pergunta pronta,
// com motivo, risco, impacto, os marcadores resolvidos e o nome da empresa. Até
// aqui NENHUMA tela o chamava: a única forma de ver uma sugestão era rodar a
// função no SQL Editor. Esta é a tela que faltava para a 0120 existir para quem
// usa o produto.
//
// ELA É UMA ABA À PARTE, e não um pedaço da fila de pendências (decisão do dono,
// 18/08/2026): o que está aqui é o que AINDA NÃO FOI PERGUNTADO a ninguém.
// Pendência é decisão sobre problema medido; sugestão é rascunho de conversa.
// Numa lista só, a segunda herdaria a aparência de tarefa concluída da primeira.

/**
 * O banco pode estar sem a 0120 aplicada — merge não é apply, e o dono aplica as
 * migrations à mão (Supabase/README.md). Nesse caso o PostgREST responde "não achei a
 * função", que é uma frase de banco, não de produto. A tela precisa dizer o que
 * fazer, e não pode quebrar: o resto do mandato continua funcionando sem esta
 * aba.
 */
function pareceMigrationAusente(mensagem: string | undefined): boolean {
  if (!mensagem) return false;
  const m = mensagem.toLowerCase();
  return m.includes("schema cache")
    || m.includes("does not exist")
    || m.includes("could not find")
    || m.includes("não existe");
}

export default async function PerguntasAoClientePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const [casoRes, sugestoesRes, acoesRes, catalogoRes] = await Promise.all([
    supabase.from("caso").select("id, nome, status").eq("id", id).single(),
    // PAGINADA, como toda lista deste portal: o PostgREST corta em 1000 linhas
    // em silêncio, e isso vale para função que devolve tabela como vale para
    // consulta. Não é hipótese distante — a sugestão é uma por (pergunta ×
    // empresa que não satisfaz) desde a 0119, então um grupo com dezenas de
    // empresas multiplica o catálogo por dezenas.
    //
    // A ORDEM É TOTAL E ESTÁVEL (prioridade, código, empresa) porque sem
    // desempate duas páginas podem repetir uma linha e omitir outra — pior que
    // truncar, porque o total continua plausível. `entidade_id` é o desempate
    // final: o par (código, empresa) é único na saída da função.
    paginar<PerguntaSugerida>((de, ate) =>
      supabase
        .rpc("fn_sugerir_perguntas", { p_caso_id: id })
        .order("prioridade", { ascending: true })
        .order("codigo", { ascending: true })
        .order("entidade_id", { ascending: true, nullsFirst: true })
        .range(de, ate),
    ),
    // O QUE JÁ SE FEZ com cada sugestão. `fn_sugerir_perguntas` devolve
    // `ja_enviada` (booleano) e nada mais; quem/quando/descartada mora aqui.
    paginar<AcaoDePergunta>((de, ate) =>
      supabase
        .from("caso_pergunta")
        .select(
          `id, pergunta_codigo, entidade_id, acao, texto_enviado, autor, criado_em,
           entidade:entidade_id(razao_social)`,
        )
        .eq("caso_id", id)
        .order("criado_em", { ascending: false })
        .order("id", { ascending: true })
        .range(de, ate),
    ),
    // O CATÁLOGO INTEIRO — são poucas dezenas de linhas e ele não cresce com a
    // mesa, então fica sem paginação, como a taxonomia e os índices macro.
    // Serve a duas coisas: separar "nada disparou neste mandato" de "não há
    // pergunta cadastrada" (dois estados que a lista vazia confunde), e dar
    // TÍTULO às perguntas do histórico que saíram da lista de sugestões.
    supabase.from("pergunta_catalogo").select("codigo, titulo, ativo"),
  ]);

  if (casoRes.error || !casoRes.data) {
    notFound();
  }

  const semMigration =
    pareceMigrationAusente(sugestoesRes.error?.message)
    || pareceMigrationAusente(acoesRes.error?.message);

  const sugestoes = sugestoesRes.data;
  const acoes = acoesRes.data;
  const catalogo = (catalogoRes.data as Array<{ codigo: string; titulo: string; ativo: boolean }> | null) ?? [];
  const catalogoAtivo = catalogoRes.error ? null : catalogo.filter((c) => c.ativo).length;
  const tituloDoCodigo = new Map(catalogo.map((c) => [c.codigo, c.titulo]));

  // As ações agrupadas pelo par (pergunta, empresa) — a mesma chave que o
  // `ja_enviada` do banco usa. Já vêm da mais recente para a mais antiga.
  const acoesPorChave = new Map<string, AcaoDePergunta[]>();
  for (const a of acoes) {
    const chave = chaveDaSugestao(a.pergunta_codigo, a.entidade_id);
    const lista = acoesPorChave.get(chave);
    if (lista) lista.push(a);
    else acoesPorChave.set(chave, [a]);
  }

  const foiTratada = (p: PerguntaSugerida) =>
    p.ja_enviada || (acoesPorChave.get(chaveDaSugestao(p.codigo, p.entidade_id))?.length ?? 0) > 0;

  const pendentes = sugestoes.filter((p) => !foiTratada(p));
  const selecionaveis: PendenteSelecionavel[] = pendentes.map((p) => ({
    chave: chaveDaSugestao(p.codigo, p.entidade_id),
    codigo: p.codigo,
    prioridade: p.prioridade,
    entidade: p.entidade,
    entidade_id: p.entidade_id,
    pergunta: p.pergunta,
  }));
  const enviadas = sugestoes.filter((p) => p.ja_enviada).length;

  // O QUE JÁ SE PERGUNTOU E NÃO É MAIS SUGERIDO. Uma pergunta some da lista
  // quando o gatilho para de valer — e o caso mais comum é o melhor possível: o
  // cliente respondeu, o documento chegou, a linha exigida apareceu. Se a
  // trilha sumisse junto, o portal deixaria de responder "o que já perguntamos a
  // este cliente?" exatamente nos casos que deram certo.
  const chavesSugeridas = new Set(sugestoes.map((p) => chaveDaSugestao(p.codigo, p.entidade_id)));
  const historicoForaDaLista = acoes.filter(
    (a) => !chavesSugeridas.has(chaveDaSugestao(a.pergunta_codigo, a.entidade_id)),
  );

  // POR PRIORIDADE, e dentro dela o que ainda não foi tratado primeiro — a
  // mesma regra da fila de pendências: quem abre a tela quer ver o que falta
  // fazer, e o que já foi feito continua visível logo abaixo.
  const prioridades = [...new Set(sugestoes.map((p) => p.prioridade))].sort((a, b) => a - b);
  const porPrioridade = prioridades.map((n) => ({
    prioridade: n,
    itens: sugestoes
      .filter((p) => p.prioridade === n)
      .sort((a, b) => Number(foiTratada(a)) - Number(foiTratada(b))),
  }));

  return (
    <ProvedorDeSelecao casoId={id} mandato={casoRes.data.nome} pendentes={selecionaveis}>
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="text-lg font-semibold text-tinta-900">Perguntas ao cliente</h1>
          {/* A FRASE MAIS IMPORTANTE DA TELA. Sem ela, uma lista de perguntas
              prontas com um botão verde parece uma caixa de saída — e a primeira
              coisa que alguém vai supor é que o sistema mandou. Ele não manda:
              não há canal, não há e-mail, não há automação. */}
          <p className="mt-1 max-w-3xl text-sm text-tinta-500">
            Perguntas prontas para fazer ao cliente, a partir do que o sistema encontrou (e do que não encontrou) nos documentos.
            <strong className="font-medium text-tinta-700"> O sistema não envia nada</strong>: copie
            o texto, mande pelo seu canal com o cliente e registre aqui o que enviou. O que está sem
            marca ainda não foi perguntado a ninguém.
          </p>
        </div>
        <div className="shrink-0 text-right">
          {/* SEM O DADO, UM TRAÇO — nunca zero. "0 perguntas a fazer" é uma
              afirmação sobre o mandato, e quando a leitura falhou não é isso que
              se sabe. É a mesma regra do painel, que já pagou o preço de
              imprimir um número plausível vindo de leitura incompleta. */}
          <p className="indicador-valor">
            {sugestoesRes.error ? "—" : pendentes.length}
          </p>
          <p className="indicador-rotulo">
            {pendentes.length === 1 ? "pergunta a fazer" : "perguntas a fazer"}
          </p>
          {enviadas > 0 && (
            <p className="mt-1 text-xs font-medium text-ok-700">
              {enviadas} {enviadas === 1 ? "já registrada como enviada" : "já registradas como enviadas"}
            </p>
          )}
        </div>
      </div>

      {semMigration && (
        <div className="rounded-lg border border-alerta-200 bg-alerta-50 p-4 text-sm text-alerta-900">
          <p className="font-semibold">As sugestões de pergunta não estão disponíveis neste ambiente.</p>
          <p className="mt-1">
            Esta aba ainda não está habilitada aqui. Avise o administrador do sistema. O restante
            do mandato continua funcionando normalmente.
          </p>
          <DetalhesTecnicos>
            <p>Falta aplicar a migration 0120_banco_de_perguntas.sql (catálogo e fn_sugerir_perguntas).
              Merge não é apply: rode as migrations pendentes conforme Supabase/README.md e recarregue.</p>
            <p>Resposta do banco: {sugestoesRes.error?.message ?? acoesRes.error?.message}</p>
          </DetalhesTecnicos>
        </div>
      )}

      {!semMigration && (sugestoesRes.error || acoesRes.error) && (
        <div className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          <p>
            Não foi possível carregar as sugestões. Tente de novo em instantes; se persistir, avise
            o administrador do sistema.
          </p>
          <DetalhesTecnicos>
            <p>{sugestoesRes.error?.message ?? acoesRes.error?.message}</p>
          </DetalhesTecnicos>
        </div>
      )}

      {(sugestoesRes.truncado || acoesRes.truncado) && (
        <div className="rounded-lg border border-alerta-200 bg-alerta-50 p-3 text-sm text-alerta-900">
          <p>
            Há perguntas demais para esta tela mostrar de uma vez, e a lista pode estar incompleta.
            Peça ao administrador do sistema a lista completa deste mandato.
          </p>
          <DetalhesTecnicos>
            <p>select * from fn_sugerir_perguntas(&#39;{id}&#39;)</p>
          </DetalhesTecnicos>
        </div>
      )}

      {!semMigration && sugestoes.length === 0 && !sugestoesRes.error && (
        <div className="carta px-6 py-12 text-center">
          <p className="text-sm font-medium text-tinta-900">Nenhuma pergunta sugerida</p>
          <p className="mx-auto mt-1 max-w-xl text-sm text-tinta-500">
            {catalogoAtivo === 0
              ? "O catálogo de perguntas está vazio neste ambiente, então nada pode ser sugerido. "
              + "Avise o administrador do sistema."
              : "As perguntas nascem do que a extração encontrou: falta de uma linha exigida numa "
                + "empresa, ou contexto que vale para todo mandato com dado extraído. Enquanto "
                + "este mandato não tiver linhas extraídas, não há o que perguntar."}
          </p>
        </div>
      )}

      {selecionaveis.length > 0 && (
        <div className="flex flex-wrap items-center gap-3">
          <SelecionarTodas rotulo="todas as pendentes" />
          <span className="text-xs text-tinta-500">
            Marque as perguntas que vão na mesma mensagem ao cliente; a barra de ações aparece
            quando houver ao menos uma.
          </span>
        </div>
      )}

      {porPrioridade.map(({ prioridade, itens }) => (
        <section key={prioridade}>
          <div className="mb-2 flex flex-wrap items-baseline justify-between gap-3">
            <h2 className="titulo-secao">
              Prioridade {prioridade} &middot; {rotuloDaPrioridade(prioridade)}
            </h2>
            <SelecionarTodas prioridade={prioridade} rotulo="todas desta prioridade" />
            <p className="text-xs text-tinta-500">
              {PRIORIDADE[prioridade]?.explicacao ?? `${itens.length} pergunta(s)`}
            </p>
          </div>
          <ul className="space-y-3">
            {itens.map((p) => (
              <CartaoPergunta
                key={chaveDaSugestao(p.codigo, p.entidade_id)}
                casoId={id}
                p={p}
                acoes={acoesPorChave.get(chaveDaSugestao(p.codigo, p.entidade_id)) ?? []}
                selecionavel={!foiTratada(p)}
              />
            ))}
          </ul>
        </section>
      ))}

      {historicoForaDaLista.length > 0 && (
        <section>
          <div className="mb-2 flex flex-wrap items-baseline justify-between gap-3">
            <h2 className="titulo-secao">Já perguntado, e não mais sugerido</h2>
            <p className="text-xs text-tinta-500">
              {historicoForaDaLista.length} {historicoForaDaLista.length === 1 ? "registro" : "registros"}
            </p>
          </div>
          <p className="mb-2.5 text-xs text-tinta-500">
            O gatilho destas perguntas deixou de valer — normalmente porque o cliente respondeu e o
            documento chegou. O registro fica: é o que responde &ldquo;o que já perguntamos a este
            cliente?&rdquo;.
          </p>
          <ul className="carta divide-y divide-tinta-100 text-sm">
            {historicoForaDaLista.map((a) => (
              <li key={a.id} className="px-3.5 py-2.5">
                <div className="flex flex-wrap items-center gap-2">
                  <span
                    className={`chip ${a.acao === "enviada"
                      ? "bg-ok-100 text-ok-800"
                      : "bg-tinta-200 text-tinta-600"}`}
                  >
                    {a.acao === "enviada" ? "enviada" : "descartada"}
                  </span>
                  <span className="font-medium text-tinta-900">
                    {tituloDoCodigo.get(a.pergunta_codigo) ?? a.pergunta_codigo}
                  </span>
                  {a.entidade?.razao_social && (
                    <span className="chip bg-tinta-100 text-tinta-700">{a.entidade.razao_social}</span>
                  )}
                  <span className="ml-auto text-xs text-tinta-500">
                    {a.autor} &middot; {dataCurta(a.criado_em)}
                  </span>
                </div>
                {/* O TEXTO CONGELADO, quando houve envio. É a razão de a 0120
                    exigi-lo: o template muda, o que foi perguntado não. */}
                {a.texto_enviado && (
                  <p className="valor-sensivel mt-1.5 whitespace-pre-wrap text-xs text-tinta-600">{a.texto_enviado}</p>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* O TAMANHO DO CATÁLOGO, no rodapé. Ele responde a pergunta que a lista
          não responde: "só isso?". A 0120 seedou 11 das 36 perguntas da entrega
          — as outras 25 pedem espécies de gatilho que ainda não existem, e isso
          está declarado na própria migration. */}
      {!semMigration && catalogoAtivo !== null && catalogoAtivo > 0 && (
        <div className="text-xs text-tinta-400">
          <p>
            O catálogo tem {catalogoAtivo} pergunta(s) ativa(s). Aparecem acima apenas as que este
            mandato dispara; as demais perguntas da entrega ainda não têm gatilho no sistema.
          </p>
          <DetalhesTecnicos className="mt-1">
            <p>Gatilhos ainda inexistentes declarados em Supabase/migrations/0120_banco_de_perguntas.sql</p>
          </DetalhesTecnicos>
        </div>
      )}
    </div>
    </ProvedorDeSelecao>
  );
}
