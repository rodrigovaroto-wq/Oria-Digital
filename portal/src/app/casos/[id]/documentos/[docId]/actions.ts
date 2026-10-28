"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { lerPlanilhaTranscricao } from "@/lib/transcricao";

// Chama fn_aceitar_extracao (Supabase/migrations/0011_aceite_export_e4.sql) — o
// Portão 2 mínimo do E4 (Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md): humano aceita TODAS as linhas
// extraídas desta versão de documento de uma vez. Sem isso, nenhuma linha
// entra no export como fato (fica "pendente" — anti-ancoragem). A lógica
// (decisao + evento_auditoria) roda no Postgres, não aqui.
export async function aceitarExtracao(casoId: string, docId: string, formData: FormData) {
  const supabase = await createClient();

  const documentoVersaoId = String(formData.get("documento_versao_id") || "");
  const motivo = String(formData.get("motivo") || "").trim() || null;

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data, error } = await supabase.rpc("fn_aceitar_extracao", {
    p_documento_versao_id: documentoVersaoId,
    p_autor: user?.email ?? "portal:desconhecido",
    p_motivo: motivo,
  });

  if (error) {
    throw new Error(`Falha ao aceitar extração: ${error.message}`);
  }

  // RECUSA (Supabase/migrations/0036): a função devolve `recusado: true` quando a versão
  // não tem NENHUMA linha extraída — aceitar ali gravaria uma aprovação formal de
  // nada numa tabela append-only. A recusa vem no payload, e não como erro de
  // Postgres, porque exceção em plpgsql desfaria o registro da própria tentativa
  // em `evento_auditoria` (ver o comentário na migration).
  //
  // Ler este campo é OBRIGATÓRIO aqui: sem isto, o `error` nulo faria a recusa
  // passar por sucesso e a tela recarregaria como se algo tivesse sido aceito —
  // trocar um "aceite de nada" por um "sucesso de nada" não seria correção
  // nenhuma.
  const resultado = data as { recusado?: boolean; motivo_recusa?: string } | null;
  if (resultado?.recusado) {
    throw new Error(resultado.motivo_recusa ?? "Aceite recusado: versão sem linhas extraídas.");
  }

  revalidatePath(`/casos/${casoId}/documentos/${docId}`);
  revalidatePath(`/casos/${casoId}`);
}

// Chama fn_registrar_classe_override (Supabase/migrations/0128) — a decisão HUMANA sobre
// a classe contábil de uma linha.
//
// POR QUE ESTA AÇÃO EXISTE, E POR QUE ELA É O PRODUTO DA 0128. A classificação
// contábil roda em N0: ela sugere e não decide nada. Sem um lugar onde o humano
// discorde, a sugestão fica sendo um número que ninguém confirmou nem derrubou — e
// é justamente a DISCORDÂNCIA que o Arquitetura do Sistema/2 Especificação/05 chama de "sinal de calibração", o dado
// que a F4 consome. Uma classificação em sombra sem tela de override não gera
// sinal nenhum; ela só ocupa espaço no banco.
//
// APPEND-ONLY: reclassificar é linha nova em campo_classe_override, e a sequência
// é o histórico. Não há como apagar uma decisão.
export async function registrarClasseContabil(
  casoId: string,
  docId: string,
  formData: FormData,
) {
  const supabase = await createClient();

  const campoId = String(formData.get("campo_extraido_id") || "");
  const classe = String(formData.get("classe") || "");
  const motivo = String(formData.get("motivo") || "").trim() || null;

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data, error } = await supabase.rpc("fn_registrar_classe_override", {
    p_campo_extraido_id: campoId,
    p_classe_final: classe,
    p_autor: user?.email ?? "portal:desconhecido",
    p_motivo: motivo,
  });

  if (error) {
    throw new Error(`Falha ao registrar a classe contábil: ${error.message}`);
  }

  // RECUSA RETORNADA, não exceção — mesmo padrão do aceite acima, e ler este campo
  // é igualmente obrigatório. A 0128 recusa rótulo fora do catálogo (a taxonomia do
  // Arquitetura do Sistema/2 Especificação/05 é FECHADA) e override sem autor; nos dois casos `error` vem nulo, e sem
  // esta leitura a tela recarregaria como se a classificação tivesse sido gravada.
  const resultado = data as { recusado?: boolean; motivo_recusa?: string } | null;
  if (resultado?.recusado) {
    throw new Error(resultado.motivo_recusa ?? "Classificação recusada.");
  }

  revalidatePath(`/casos/${casoId}/documentos/${docId}`);
}

// Chama fn_registrar_transcricao_humana (Supabase/migrations/0129) — a SAÍDA do gate de
// captura (fechamento #2 do Arquitetura do Sistema/1 Visão e Doutrina/01), a partir da planilha preenchida.
//
// POR QUE ESTA AÇÃO É O QUE FECHA A 0129. A função no banco existia e nada a
// chamava: sem planilha e sem importação, o gate continuava sendo o dead-end de
// pendência infinita que o Arquitetura do Sistema/1 Visão e Doutrina/01 nomeia — "arquivo ilegível" abria pendência e
// não havia caminho nenhum para sair dela a não ser o cliente reenviar um arquivo
// melhor, que às vezes não existe.
//
// A GUARDA DE DOCUMENTO RODA AQUI, ANTES DO BANCO. `lerPlanilhaTranscricao` confere
// o id gravado na planilha contra o documento desta tela e RECUSA quando divergem.
// Isso não é redundância com o banco: o banco não tem como saber que a planilha foi
// gerada para outro documento — para ele chegariam linhas plausíveis, e ele as
// gravaria aceitas, com o nome de quem enviou. Um número errado com autor é o pior
// tipo de número errado, porque ninguém volta a desconfiar dele.
//
// E POR QUE ESTA AÇÃO DEVOLVE A RECUSA EM VEZ DE LANÇAR, ao contrário das duas
// acima. Não é inconsistência: é a mesma doutrina de recusa retornada da casa,
// aplicada uma camada acima, e aqui ela é OBRIGATÓRIA por um motivo mecânico. O
// Next redige a mensagem de erro de server action em produção — quem recebesse um
// throw veria um digest opaco no lugar de "esta planilha foi gerada para OUTRO
// documento". Nas outras ações a recusa é rara e o texto é secundário; aqui o texto
// É o produto: ele diz à pessoa exatamente o que fazer com o arquivo que ela tem na
// mão. Lançar destruiria justamente a parte útil.
export type ResultadoImportacao =
  | { ok: true; linhas: number; n_versao: number; pendencia_resolvida: boolean }
  | { ok: false; erro: string };

export async function importarTranscricao(
  casoId: string,
  docId: string,
  formData: FormData,
): Promise<ResultadoImportacao> {
  const supabase = await createClient();

  const arquivo = formData.get("planilha");
  const motivo = String(formData.get("motivo") || "").trim() || null;

  if (!(arquivo instanceof File) || arquivo.size === 0) {
    return { ok: false, erro: "Selecione a planilha preenchida (.xlsx) antes de importar." };
  }

  const leitura = await lerPlanilhaTranscricao(await arquivo.arrayBuffer(), docId);
  if (!leitura.ok) {
    return { ok: false, erro: leitura.erro };
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  // AUTOR: a 0129 recusa transcrição sem autor, e o motivo está escrito lá — o
  // número passa a valer como fato e a única coisa que o sustenta é quem o digitou.
  // Aqui isso quer dizer que um usuário sem e-mail na sessão NÃO transcreve: o
  // "portal:desconhecido" que serve para um aceite (onde há uma extração de máquina
  // por baixo) não serve para uma linha cujo único lastro é a pessoa.
  const autor = user?.email ?? null;
  if (!autor) {
    return {
      ok: false,
      erro:
        "Não identifiquei quem está transcrevendo. Transcrição sem autor não é " +
        "transcrição: o número passa a valer como fato na base e a única coisa que o " +
        "sustenta é quem o digitou. Entre novamente na sessão e repita a importação.",
    };
  }

  const { data, error } = await supabase.rpc("fn_registrar_transcricao_humana", {
    p_documento_id: docId,
    p_linhas: leitura.linhas,
    p_autor: autor,
    p_motivo: motivo,
  });

  if (error) {
    return { ok: false, erro: `Falha ao gravar a transcrição: ${error.message}` };
  }

  // RECUSA RETORNADA pelo banco — ler este campo é obrigatório, como nas duas ações
  // acima. A 0129 recusa documento inexistente, documento sem nenhuma versão
  // (transcrição é leitura nova de arquivo que já está aqui, não porta de entrada de
  // arquivo) e lista vazia. Sem esta leitura, `error` nulo faria a recusa passar por
  // sucesso e a tela diria "N linhas gravadas" sem nenhuma linha gravada.
  const resultado = data as {
    recusado?: boolean;
    motivo_recusa?: string;
    linhas?: number;
    n_versao?: number;
    pendencia_resolvida?: string | null;
  } | null;
  if (resultado?.recusado) {
    return { ok: false, erro: resultado.motivo_recusa ?? "Transcrição recusada." };
  }

  // A transcrição cria uma VERSÃO NOVA do documento (doutrina da 0026) e recomputa a
  // completude do caso — então as duas telas mudam, não só esta.
  revalidatePath(`/casos/${casoId}/documentos/${docId}`);
  // A LISTA fica montada por baixo do painel e mostra "linhas" por documento: transcrever leva
  // "nenhuma" a N (e tira o documento do filtro "sem linha"). Sem isto a lista atrás do painel
  // continuaria dizendo "nenhuma" até o F5.
  revalidatePath(`/casos/${casoId}/documentos`);
  revalidatePath(`/casos/${casoId}`);

  return {
    ok: true,
    linhas: resultado?.linhas ?? leitura.linhas.length,
    n_versao: resultado?.n_versao ?? 0,
    pendencia_resolvida: resultado?.pendencia_resolvida != null,
  };
}
