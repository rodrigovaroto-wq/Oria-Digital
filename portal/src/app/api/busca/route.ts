import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import {
  LIMITE_POR_GRUPO, agruparResultados, digitosDoCnpj, padraoDoTermo, termoDaBusca,
  type LinhasDaBusca,
} from "@/lib/busca-global";

// BUSCA GLOBAL (⌘K). Cliente autenticado do servidor: a RLS decide o que cada
// pessoa vê, sem service role. Por tecla aceita (>= 2 caracteres, após o debounce
// do cliente): 3 consultas com colunas nomeadas, filtro em ILIKE no Postgres e
// `limit` 6 — (4 se o termo for CNPJ). Nada de polling.
//
// FALHA NUNCA VIRA LISTA VAZIA (regra 1): qualquer consulta com erro derruba a
// resposta inteira em 500 com a mensagem, e a tela mostra o erro — não "Nada
// encontrado", que afirmaria uma ausência que ninguém mediu.
export const dynamic = "force-dynamic";

type Embutido<T> = T | T[] | null;
const um = <T,>(v: Embutido<T>): T | null => (Array.isArray(v) ? (v[0] ?? null) : v);

export async function GET(req: NextRequest) {
  const termo = termoDaBusca(req.nextUrl.searchParams.get("q"));
  if (termo === null) {
    return NextResponse.json({ erro: "Digite ao menos 2 caracteres." }, { status: 400 });
  }

  const supabase = await createClient();
  // Sem sessão a RLS devolveria listas vazias — que pareceriam "nada encontrado".
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims) {
    return NextResponse.json({ erro: "Sessão expirada. Entre de novo." }, { status: 401 });
  }

  const padrao = padraoDoTermo(termo);
  const digitos = digitosDoCnpj(termo);

  const [mandatos, documentos, entidadesNome, entidadesCnpj] = await Promise.all([
    supabase.from("caso").select("id, nome, fechado_em")
      .ilike("nome", padrao).order("criado_em", { ascending: false }).limit(LIMITE_POR_GRUPO),
    supabase.from("documento_versao")
      .select("documento_id, nome_original, documento!inner(caso_id, caso(nome))")
      .ilike("nome_original", padrao).order("criada_em", { ascending: false }).limit(LIMITE_POR_GRUPO),
    // Entidade por razão social; por CNPJ só quando o termo é número (os dígitos
    // não têm curinga a escapar). Termo numérico procura nas duas colunas.
    supabase.from("entidade").select("id, caso_id, razao_social, cnpj, caso(nome)")
      .ilike("razao_social", padrao).limit(LIMITE_POR_GRUPO),
    digitos
      ? supabase.from("entidade").select("id, caso_id, razao_social, cnpj, caso(nome)")
          .ilike("cnpj", `%${digitos}%`).limit(LIMITE_POR_GRUPO)
      : Promise.resolve({ data: [], error: null }),
  ]);

  const erro = mandatos.error ?? documentos.error ?? entidadesNome.error ?? entidadesCnpj.error;
  if (erro) {
    return NextResponse.json({ erro: "A busca não conseguiu consultar o banco." }, { status: 500 });
  }

  type DocRow = {
    documento_id: string; nome_original: string | null;
    documento: Embutido<{ caso_id: string; caso: Embutido<{ nome: string }> }>;
  };
  type EntRow = {
    id: string; caso_id: string; razao_social: string; cnpj: string | null;
    caso: Embutido<{ nome: string }>;
  };

  const linhas: LinhasDaBusca = {
    mandatos: mandatos.data ?? [],
    documentos: ((documentos.data ?? []) as unknown as DocRow[]).flatMap((d) => {
      const doc = um(d.documento);
      return doc ? [{
        documento_id: d.documento_id, caso_id: doc.caso_id,
        nome_original: d.nome_original, caso_nome: um(doc.caso)?.nome ?? null,
      }] : [];
    }),
    entidades: [...(entidadesNome.data ?? []), ...(entidadesCnpj.data ?? [])]
      .map((e) => {
        const r = e as unknown as EntRow;
        return { id: r.id, caso_id: r.caso_id, razao_social: r.razao_social, cnpj: r.cnpj, caso_nome: um(r.caso)?.nome ?? null };
      }),
  };

  return NextResponse.json({ resultados: agruparResultados(linhas) });
}
