import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import { vereditoDoLote } from "@/lib/espera-do-lote";
import { MENSAGEM_NOME_DUPLICADO } from "@/lib/acesso";

// Consultado pelo portal (polling) depois de um upload, pra saber quando os
// arquivos enviados já passaram pela classificação E pela extração — não tem
// nenhum "flag de concluído" único no schema, então isto combina dois sinais:
//   1. `documento` criado para o caso (classificação terminou) desde o envio.
//   2. `evento_auditoria` do tipo `extracao_sombra` referenciando aquele
//      documento_versao (extração TENTOU rodar — sucesso ou falha; sempre
//      gravado por fn_registrar_campos_extraidos, ver Supabase/migrations/0016).
// "Pronto" aqui significa "o pipeline terminou de tentar", não "sem erros" —
// pendências (se houver) continuam visíveis no dashboard do caso como sempre.
export const runtime = "nodejs";

type Supabase = Awaited<ReturnType<typeof createClient>>;

/** Quantas versões distintas aparecem numa tabela que aponta para elas. */
async function quantosRenderam(
  supabase: Supabase, tabela: "campo_extraido" | "documento_fato", versaoIds: string[],
): Promise<number | null> {
  const { data, error } = await paginar<{ documento_versao_id: string }>((de, ate) =>
    supabase
      .from(tabela)
      .select("documento_versao_id")
      .in("documento_versao_id", versaoIds)
      .order("id", { ascending: true })
      .range(de, ate),
  );
  // ERRO AQUI NÃO DERRUBA O `pronto`. O lote terminou de verdade, e trocar essa
  // notícia por uma tela de erro porque a CONFERÊNCIA falhou seria pior que não
  // conferir. `null` diz "não sei", e quem lê trata diferente de zero.
  if (error) return null;
  return new Set(data.map((d) => d.documento_versao_id)).size;
}

/**
 * O que o lote de fato PRODUZIU — a diferença entre "tentou" e "conseguiu".
 *
 * Um lote em que TODA leitura falhou emite exatamente os mesmos eventos de
 * `extracao_sombra` de um lote perfeito, e a tela dizia "pronto" para os dois.
 *
 * OS FATOS CONTAM COMO CONTEÚDO, e ignorá-los acusaria o lote que funcionou:
 * medido no smoke test de 27/08, as Notas Explicativas e o Parecer do Auditor
 * renderam ZERO linhas e NOVE fatos materiais — que é o resultado certo, porque
 * esses documentos dizem as coisas em texto, não em tabela.
 */
async function conteudoDoLote(supabase: Supabase, versaoIds: string[]) {
  if (versaoIds.length === 0) return { comLinhas: null, comFatos: null };
  const [comLinhas, comFatos] = await Promise.all([
    quantosRenderam(supabase, "campo_extraido", versaoIds),
    quantosRenderam(supabase, "documento_fato", versaoIds),
  ]);
  return { comLinhas, comFatos };
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const casoNome = searchParams.get("caso")?.trim();
  const desde = searchParams.get("desde");
  const esperados = Number(searchParams.get("esperados") ?? "0");

  if (!casoNome || !desde || !Number.isFinite(esperados) || esperados <= 0) {
    return NextResponse.json({ error: "Parâmetros inválidos (caso, desde, esperados)." }, { status: 400 });
  }

  const supabase = await createClient();

  // A FALHA VEM PRIMEIRO, e vem antes de qualquer contagem de progresso.
  //
  // Esta rota deduz "está processando" da AUSÊNCIA de documentos — e falha
  // produz a mesma ausência. Foi assim que 35 documentos recusados pelo
  // orçamento viraram um "aguarde" eterno: o pipeline tinha morrido dois minutos
  // antes e a tela seguia calma. Perguntar pela falha ANTES de contar progresso é
  // o que faz os dois estados deixarem de ter a mesma aparência.
  const { data: falhas } = await supabase.rpc("fn_falhas_abertas", {
    p_caso_nome: casoNome,
    p_desde: desde,
  });
  const falha = (falhas as Array<{ id: string; etapa: string; mensagem: string }> | null)?.[0];
  if (falha) {
    return NextResponse.json({
      classificados: 0, processados: 0, esperados, pronto: false, comLinhas: null, comFatos: null,
      falha: { id: falha.id, etapa: falha.etapa, mensagem: falha.mensagem },
    });
  }

  // `limit(2)` e não a leitura de uma linha só: com dois mandatos de mesmo nome (não há UNIQUE) o PostgREST
  // devolvia erro e o Sócio via 500. Duplicidade é dita, não vira "aguarde" nem erro opaco.
  const { data: casos, error: casoErr } = await supabase
    .from("caso")
    .select("id")
    .eq("nome", casoNome)
    .limit(2);

  if (casoErr) {
    return NextResponse.json({ error: casoErr.message }, { status: 500 });
  }
  if ((casos?.length ?? 0) > 1) {
    return NextResponse.json({ error: MENSAGEM_NOME_DUPLICADO }, { status: 409 });
  }
  const caso = casos?.[0] ?? null;
  if (!caso) {
    // Ainda nem o `caso` foi criado — normal logo após o envio.
    return NextResponse.json({ classificados: 0, processados: 0, esperados, pronto: false });
  }

  // PAGINADO: estes dois são CONTADORES DE PROGRESSO da ingestão, e o teto do
  // PostgREST (1000 por consulta, silencioso) faria a barra parar em mil
  // documentos e o lote parecer travado quando está andando.
  const { data: documentos, error: docErr } = await paginar<{ id: string; documento_versao: { id: string }[] }>(
    (de, ate) =>
      supabase
        .from("documento")
        .select("id, documento_versao(id)")
        .eq("caso_id", caso.id)
        .gte("criado_em", desde)
        .order("id", { ascending: true })
        .range(de, ate),
  );

  if (docErr) {
    return NextResponse.json({ error: docErr.message }, { status: 500 });
  }

  const docs = documentos;
  const classificados = docs.length;
  const versaoIds = docs.flatMap((d) => (d.documento_versao ?? []).map((v) => v.id));

  let processados = 0;
  if (versaoIds.length > 0) {
    const refs = versaoIds.map((id) => `documento_versao:${id}`);
    const { data: eventos, error: evtErr } = await paginar<{ entidade_ref: string }>((de, ate) =>
      supabase
        .from("evento_auditoria")
        .select("entidade_ref")
        .eq("acao", "extracao_sombra")
        .gte("criado_em", desde)
        .in("entidade_ref", refs)
        .order("id", { ascending: true })
        .range(de, ate),
    );

    if (evtErr) {
      return NextResponse.json({ error: evtErr.message }, { status: 500 });
    }
    processados = new Set(eventos.map((e) => e.entidade_ref)).size;
  }

  // O LOTE FECHOU? — a pergunta que faltava, e sem ela a tela dizia "Tudo pronto"
  // sobre uma execução MORTA.
  //
  // ACHADO COM O DONO NA TELA, 27/08/2026. A execução morreu no primeiro nó
  // (`Upload Storage`, habilitado por engano com a credencial `REPLACE`) e o
  // portal reportou sucesso. Nenhuma peça mentiu sozinha:
  //
  //   • o registro de falha depende do **Error Workflow** do n8n, que é passo
  //     MANUAL de configuração e não está ligado (conferido: `settings` do
  //     workflow vivo não tem `errorWorkflow`) — então `fn_falhas_abertas` não
  //     tinha o que devolver;
  //   • e os contadores foram satisfeitos assim mesmo, porque `Upload Storage` é
  //     ramo LATERAL: o irmão (`Extrair Texto` → … → `Registrar Documento`)
  //     rodou inteiro e gravou os documentos e os eventos de extração.
  //
  // Deduzir "terminou bem" de contadores é deduzir de um sintoma que a morte
  // também produz. O sinal que não depende de configuração nenhuma é o FIM do
  // workflow: ele termina em `Gravar Uso do Lote` → `Conferir Lote`, e um lote
  // que fecha deixa linha em `lote_execucao`. Medido: a v47 e a v48 deixaram
  // (38 documentos, 2.460 e 2.485 linhas); as duas execuções que morreram no
  // smoke test não deixaram nenhuma.
  const { data: lotes, error: loteErr } = await supabase
    .from("lote_execucao")
    .select("id")
    .eq("caso_id", caso.id)
    .gte("criado_em", desde)
    .limit(1);

  // ERRO NA CONSULTA NÃO VIRA FALHA DO LOTE. `null` é "não sei", e "não sei" não
  // pode acusar uma execução que está viva — é a mesma regra que o `comLinhas`
  // já aplica logo abaixo.
  const loteFechou = loteErr ? null : (lotes?.length ?? 0) > 0;

  const veredito = vereditoDoLote({
    classificados, processados, esperados, loteFechou,
    desdeMs: Date.parse(desde), agoraMs: Date.now(),
  });
  const pronto = veredito.estado === "pronto";

  if (veredito.estado === "nao_fechou") {
    return NextResponse.json({
      classificados, processados, esperados, pronto: false, comLinhas: null, comFatos: null,
      casoId: caso.id,
      falha: {
        id: null,
        etapa: "lote_nao_fechou",
        mensagem:
          `O lote não fechou: os ${processados} documento(s) foram lidos, mas o processamento não `
          + "chegou ao fim (nenhum registro de encerramento do lote foi gravado). "
          + "Causa mais comum: um nó do fluxo morreu depois da extração. "
          + `Mandato: "${casoNome}". Envio: ${desde}.`,
      },
    });
  }

  // TERMINOU E NÃO TROUXE NADA — o estado que passava por SUCESSO.
  //
  // `pronto` mede que o pipeline TENTOU ler cada arquivo, e é cego para o que
  // ele produziu (ver `quantosRenderam`). SÓ QUANDO `pronto`, e a condição é o
  // que torna isto barato: são duas consultas a mais no ÚLTIMO polling, não a
  // cada 8 segundos durante 20 minutos.
  const { comLinhas, comFatos } = pronto
    ? await conteudoDoLote(supabase, versaoIds)
    : { comLinhas: null, comFatos: null };

  return NextResponse.json({ classificados, processados, esperados, pronto, comLinhas, comFatos, casoId: caso.id });
}
