"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { FORMAS, PAPEIS, lerPercentual } from "@/lib/perimetro";

// AS ESCRITAS DO PERÍMETRO (0179–0183, 0209). Cada uma chama a função do banco e DEVOLVE o resultado
// como objeto — nunca exceção nem redirect, para a mensagem do banco chegar ao analista (as exceções
// delas são em português e dizem o que fazer: "registre os controladores primeiro", "criaria um CICLO").
//
// O `casoId` é AMARRADO no servidor (`.bind` na página); a entidade vem do formulário, então cada ação
// confere que ela pertence ao caso antes de gravar — um POST com uuid de outro mandato não escreve nele.
//
// NÃO há service role aqui: a escrita é a do usuário logado. Enquanto a 0210 não estiver aplicada, gravar
// escopo e registrar controlador falham por RLS (42501) e a mensagem do banco aparece na tela, como está.
export type ResultadoPerimetro = { tom: "ok" | "erro"; texto: string } | null;
type Acao = (anterior: ResultadoPerimetro, form: FormData) => Promise<ResultadoPerimetro>;
export type AcoesPerimetro = {
  papel: Acao; forma: Acao; participacao: Acao; controlador: Acao; vinculo: Acao; escopoDefinir: Acao; escopoEncerrar: Acao;
};

const erro = (texto: string): ResultadoPerimetro => ({ tom: "erro", texto });
const texto = (f: FormData, k: string) => (typeof f.get(k) === "string" ? (f.get(k) as string).trim() : "");

async function rodar(
  casoId: string, form: FormData,
  chamar: (a: { entidadeId: string; autor: string }) => { fn: string; args: Record<string, unknown> } | ResultadoPerimetro,
  sucesso: string,
): Promise<ResultadoPerimetro> {
  const supabase = await createClient();
  const entidadeId = texto(form, "entidade_id");
  const dono = await supabase.from("entidade").select("caso_id").eq("id", entidadeId).maybeSingle();
  if (dono.error) return erro(`Não foi possível conferir a empresa: ${dono.error.message}`);
  if (dono.data?.caso_id !== casoId) return erro("Empresa não encontrada neste mandato — nada foi gravado.");
  const { data: { user } } = await supabase.auth.getUser();
  const autor = user?.email ?? "portal:desconhecido";
  const pedido = chamar({ entidadeId, autor });
  if (pedido && "tom" in pedido) return pedido;
  if (!pedido) return erro("Pedido inválido.");
  const { error } = await supabase.rpc(pedido.fn, pedido.args);
  if (error) return erro(error.message);
  revalidatePath(`/casos/${casoId}/perimetro`);
  return { tom: "ok", texto: sucesso };
}

const dataValida = (s: string) => /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s));

export async function definirPapel(casoId: string, _a: ResultadoPerimetro, form: FormData) {
  const papel = texto(form, "papel");
  if (!PAPEIS.some((p) => p.valor === papel)) return erro("Escolha um papel da lista.");
  return rodar(casoId, form, ({ entidadeId, autor }) => ({
    fn: "fn_entidade_definir_papel_no_grupo", args: { p_entidade_id: entidadeId, p_papel: papel, p_autor: autor },
  }), "Papel gravado.");
}

export async function definirForma(casoId: string, _a: ResultadoPerimetro, form: FormData) {
  const forma = texto(form, "forma");
  if (!FORMAS.some((f) => f.valor === forma)) return erro("Escolha uma forma de controle da lista.");
  return rodar(casoId, form, ({ entidadeId, autor }) => ({
    fn: "fn_entidade_definir_forma_de_controle", args: { p_entidade_id: entidadeId, p_forma: forma, p_autor: autor },
  }), "Forma de controle gravada.");
}

export async function definirParticipacao(casoId: string, _a: ResultadoPerimetro, form: FormData) {
  const controladora = texto(form, "controladora_id");
  const pct = lerPercentual(texto(form, "percentual"));
  if (Number.isNaN(pct)) return erro("Percentual inválido: use só número, por exemplo 51 ou 12,5.");
  // Sem controladora o banco exige percentual nulo; a tela não deixa chegar lá com um valor órfão.
  if (!controladora && pct !== null) return erro("Há percentual sem controladora: escolha a controladora ou apague o percentual.");
  return rodar(casoId, form, ({ entidadeId, autor }) => ({
    fn: "fn_entidade_definir_participacao",
    args: { p_entidade_id: entidadeId, p_controladora_id: controladora || null, p_percentual: pct, p_autor: autor },
  }), controladora ? "Controladora gravada." : "Controladora removida.");
}

// Registrar o controlador e vinculá-lo são DUAS chamadas; se a segunda falha o controlador já existe no
// caso (a mensagem diz isso) e o formulário "vincular existente" resolve sem recadastrar.
export async function registrarControlador(casoId: string, _a: ResultadoPerimetro, form: FormData) {
  const nome = texto(form, "nome");
  const tipo = texto(form, "tipo_pessoa");
  const pct = lerPercentual(texto(form, "percentual"));
  if (!nome) return erro("Informe o nome do sócio/controlador.");
  if (tipo !== "fisica" && tipo !== "juridica") return erro("Diga se é pessoa física ou jurídica.");
  if (Number.isNaN(pct)) return erro("Percentual inválido: use só número, por exemplo 51 ou 12,5.");
  const supabase = await createClient();
  const dono = await supabase.from("entidade").select("caso_id").eq("id", texto(form, "entidade_id")).maybeSingle();
  if (dono.error) return erro(`Não foi possível conferir a empresa: ${dono.error.message}`);
  if (dono.data?.caso_id !== casoId) return erro("Empresa não encontrada neste mandato — nada foi gravado.");
  const { data: { user } } = await supabase.auth.getUser();
  const autor = user?.email ?? "portal:desconhecido";
  const novo = await supabase.rpc("fn_controlador_registrar", {
    p_caso_id: casoId, p_nome: nome, p_documento: texto(form, "documento") || null, p_tipo_pessoa: tipo, p_autor: autor,
  });
  if (novo.error) return erro(novo.error.message);
  const liga = await supabase.rpc("fn_entidade_definir_controlador", {
    p_entidade_id: texto(form, "entidade_id"), p_controlador_id: novo.data, p_percentual: pct, p_autor: autor,
  });
  revalidatePath(`/casos/${casoId}/perimetro`);
  if (liga.error) return erro(`O controlador "${nome}" foi registrado, mas o vínculo com a empresa falhou: ${liga.error.message}`);
  return { tom: "ok", texto: `${nome} registrado e vinculado.` } satisfies ResultadoPerimetro;
}

export async function vincularControlador(casoId: string, _a: ResultadoPerimetro, form: FormData) {
  const controlador = texto(form, "controlador_id");
  const pct = lerPercentual(texto(form, "percentual"));
  if (!controlador) return erro("Escolha o controlador.");
  if (Number.isNaN(pct)) return erro("Percentual inválido: use só número, por exemplo 51 ou 12,5.");
  return rodar(casoId, form, ({ entidadeId, autor }) => ({
    fn: "fn_entidade_definir_controlador",
    args: { p_entidade_id: entidadeId, p_controlador_id: controlador, p_percentual: pct, p_autor: autor },
  }), "Vínculo gravado.");
}

export async function confirmarEscopo(casoId: string, _a: ResultadoPerimetro, form: FormData) {
  const escopo = texto(form, "escopo");
  const desde = texto(form, "data");
  if (!escopo) return erro("Informe o escopo.");
  if (!dataValida(desde)) return erro("Informe a data de início (desde quando a empresa está neste escopo).");
  return rodar(casoId, form, ({ entidadeId, autor }) => ({
    fn: "fn_perimetro_definir_escopo",
    args: { p_caso_id: casoId, p_entidade_id: entidadeId, p_escopo: escopo, p_desde: desde, p_autor: autor },
  }), `Escopo "${escopo}" gravado desde ${desde}.`);
}

export async function encerrarEscopo(casoId: string, _a: ResultadoPerimetro, form: FormData) {
  const escopo = texto(form, "escopo");
  const ate = texto(form, "data");
  if (!escopo) return erro("Informe o escopo.");
  if (!dataValida(ate)) return erro("Informe o último dia em que a empresa ainda está no escopo.");
  return rodar(casoId, form, ({ entidadeId, autor }) => ({
    fn: "fn_perimetro_encerrar_escopo",
    args: { p_caso_id: casoId, p_entidade_id: entidadeId, p_escopo: escopo, p_ate: ate, p_autor: autor },
  }), `Escopo "${escopo}" encerrado em ${ate}.`);
}
