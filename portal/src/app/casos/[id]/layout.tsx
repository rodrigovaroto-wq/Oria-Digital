import { createClient } from "@/lib/supabase/server";
import { EtapasDoMandato } from "@/components/etapas-do-mandato";

// O LAYOUT DO MANDATO: a barra de etapas aparece em toda rota de `/casos/[id]/*`, e as páginas não
// repetem os botões que ela substitui. Layout não reexecuta entre rotas filhas, então aqui só entra
// o que vale para a sessão inteira (quem é o usuário) — contagem de pendência ou de perguntas ficaria
// velha na primeira ação, por isso não há número na barra.
//
// `fn_eh_admin` falhando (banco sem a 0215) NÃO vira "é administrador": sem resposta, sem a etapa
// Membros. Esconder o link não é o controle — a página e as funções do banco recusam sozinhas.
export default async function MandatoLayout({
  children, params,
}: { children: React.ReactNode; params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const { data } = await supabase.rpc("fn_eh_admin");
  return (
    <>
      <EtapasDoMandato id={id} ehAdmin={data === true} />
      {children}
    </>
  );
}
