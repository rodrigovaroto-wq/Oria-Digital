"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { DecisaoPendencia } from "@/lib/pendencia";

// Chama fn_aprovar_caso (Supabase/migrations/0037) — o Portão 2 POR CASO, que até a
// 0037 não existia em código: `caso_status` tinha 'aprovado' e nada transicionava
// para lá, e `pendencia.sobrepujavel` era gravado sem nenhum leitor.
//
// A regra vive no Postgres e não é reimplementada aqui — este arquivo só
// encaminha e mostra o resultado. Desde a 0109 ela é UMA: não há bloqueante sem
// decisão. O teto de ressalvas e a lista fechada de `Arquitetura do Sistema/2 Especificação/f0/04` saíram por decisão
// do dono e viraram contagem informativa.
export async function aprovarCaso(casoId: string, formData: FormData) {
  const supabase = await createClient();

  const motivo = String(formData.get("motivo") || "").trim() || null;

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data, error } = await supabase.rpc("fn_aprovar_caso", {
    p_caso_id: casoId,
    p_autor: user?.email ?? "portal:desconhecido",
    p_motivo: motivo,
  });

  if (error) {
    throw new Error(`Falha ao aprovar o caso: ${error.message}`);
  }

  // RECUSA no payload, não como erro de Postgres — mesmo padrão da 0036, e pelo
  // mesmo motivo: exceção em plpgsql desfaria o registro da própria tentativa em
  // `evento_auditoria`, e "alguém tentou aprovar um caso bloqueado" é justamente
  // o que uma trilha de auditoria precisa guardar.
  //
  // Ler este campo é obrigatório: sem isto, `error` nulo faria a recusa passar
  // por sucesso e a tela recarregaria como se o caso tivesse sido aprovado.
  const r = data as { recusado?: boolean; motivo_recusa?: string } | null;
  if (r?.recusado) {
    throw new Error(r.motivo_recusa ?? "Aprovação recusada: o mandato ainda não cumpre as condições de aprovação.");
  }

  revalidatePath(`/casos/${casoId}`);
}

// Chama fn_decidir_pendencia (Supabase/migrations/0109) — os três botões da tela.
//
// Três server actions viraram uma, porque os três cliques são a mesma operação
// com destinos diferentes. A decisão vai no `bind`, não no formulário: não há
// formulário — é um botão, e o que ele faz está no próprio botão.
//
// O que a 0109 tirou daqui (motivo obrigatório, data de expiração, papel sênior,
// teto de 3) está registrado na migration. O que continua: quem clicou e quando,
// em `decisao` e em `evento_auditoria`.
export async function decidirPendencia(
  casoId: string,
  pendenciaId: string,
  decisao: DecisaoPendencia,
) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data, error } = await supabase.rpc("fn_decidir_pendencia", {
    p_pendencia_id: pendenciaId,
    p_autor: user?.email ?? "portal:desconhecido",
    p_decisao: decisao,
  });

  if (error) {
    throw new Error(`Falha ao registrar a decisão: ${error.message}`);
  }
  // RECUSA no payload, não como erro de Postgres — mesmo padrão da 0036/0037.
  // Ler este campo é obrigatório: sem isto, `error` nulo faria a recusa passar
  // por sucesso e a tela recarregaria como se a decisão tivesse sido gravada.
  const r = data as { recusado?: boolean; motivo_recusa?: string } | null;
  if (r?.recusado) {
    throw new Error(r.motivo_recusa ?? "Decisão recusada.");
  }

  revalidatePath(`/casos/${casoId}`);
}

// Chama fn_excluir_caso (Supabase/migrations/0108) — o botão de excluir o mandato.
//
// A confirmação acontece NO NAVEGADOR, antes de chegar aqui (é o `onSubmit` do
// componente): o servidor não tem como perguntar "tem certeza?" no meio de uma
// server action. O que o servidor garante é o resto — que a exclusão deixe
// rastro na trilha e devolva a contagem do que se perdeu.
// FECHAR (0114) É A AÇÃO DO DIA A DIA; excluir é a exceção. As duas moram
// juntas de propósito: quem vai apagar um mandato passa por aqui e vê que existe
// um jeito de tirá-lo da frente sem perder o que a equipe produziu.
export async function fecharCaso(casoId: string, formData?: FormData) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  const motivo = (formData?.get("motivo") as string | null)?.trim() || null;

  const { data, error } = await supabase.rpc("fn_fechar_caso", {
    p_caso_id: casoId,
    p_autor: user?.email ?? "portal:desconhecido",
    p_motivo: motivo,
  });
  if (error) throw new Error(`Falha ao fechar o mandato: ${error.message}`);
  const r = data as { recusado?: boolean; motivo_recusa?: string } | null;
  if (r?.recusado) throw new Error(r.motivo_recusa ?? "Fechamento recusado.");

  revalidatePath("/casos");
  revalidatePath("/casos/todos");
  revalidatePath(`/casos/${casoId}`);
}

export async function reabrirCaso(casoId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  const { data, error } = await supabase.rpc("fn_reabrir_caso", {
    p_caso_id: casoId,
    p_autor: user?.email ?? "portal:desconhecido",
  });
  if (error) throw new Error(`Falha ao reabrir o mandato: ${error.message}`);
  const r = data as { recusado?: boolean; motivo_recusa?: string } | null;
  if (r?.recusado) throw new Error(r.motivo_recusa ?? "Reabertura recusada.");

  revalidatePath("/casos");
  revalidatePath("/casos/todos");
  revalidatePath(`/casos/${casoId}`);
}

export async function excluirCaso(casoId: string) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data, error } = await supabase.rpc("fn_excluir_caso", {
    p_caso_id: casoId,
    p_autor: user?.email ?? "portal:desconhecido",
  });

  if (error) {
    throw new Error(`Falha ao excluir o mandato: ${error.message}`);
  }
  const r = data as { recusado?: boolean; motivo_recusa?: string } | null;
  if (r?.recusado) {
    throw new Error(r.motivo_recusa ?? "Exclusão recusada.");
  }

  // A lista e o painel, não o caso: o caso não existe mais, e
  // `revalidatePath` nele deixaria a navegação apontando para uma página que
  // vai dar 404. Quem excluiu estava NA lista, e é para lá que volta.
  revalidatePath("/casos");
  revalidatePath("/casos/todos");
  redirect("/casos/todos");
}
