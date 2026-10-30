import CasosLayout from "@/app/casos/layout";
import { lerAcesso } from "@/lib/supabase/acesso";
import { createClient } from "@/lib/supabase/server";
import { AVISO_TOTAIS_RECORTADOS, decidirAdministracao, ROTULO_DO_PAPEL } from "@/lib/acesso";
import { AbasDaAdministracao } from "./abas-da-administracao";

// A Administração é GLOBAL (o dial e o custo valem para a mesa inteira, não para um
// mandato), por isso mora em `/administracao` e não em `/casos/...`. Usa a MESMA
// moldura dos mandatos — um segundo cabeçalho sairia de sincronia na primeira mudança —
// e põe as abas dentro dela.
// Se o papel não pôde ser lido, pergunta-se `fn_eh_socio()`; se ela também falhar a área abre COM uma faixa
// dizendo que os totais podem estar recortados (fechar por soluço de rede trancaria o Sócio fora do próprio
// portal; abrir calado entregaria somas parciais como o todo).
export default async function AdministracaoLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const acesso = await lerAcesso();
  // A ADMINISTRAÇÃO INTEIRA É DO SÓCIO. Custos, concordância da classificação, cobertura do golden set e a
  // trilha do dial somam TODOS os mandatos, e a RLS por mandato (0216) entrega a quem só vê os alocados um
  // recorte que parece total: custo "total" só dos alocados, golden zerado, trilha do dial vazia. Número
  // parcial com cara de total é ausência apresentada como dado (regra 1) — então a área fecha, e diz por quê.
  let ehSocio: boolean | null = null;
  if (acesso.estado === "falha") {
    try {
      const r = await (await createClient()).rpc("fn_eh_socio");
      ehSocio = r.error || typeof r.data !== "boolean" ? null : r.data;
    } catch {
      ehSocio = null;
    }
  }
  const decisao = decidirAdministracao(acesso, ehSocio);
  if (decisao === "fechada") {
    const papel = acesso.estado === "ok" && acesso.papel ? ROTULO_DO_PAPEL[acesso.papel] : null;
    return (
      <CasosLayout>
        <div className="mx-auto max-w-xl py-12 text-center">
          <h1 className="font-titulo text-2xl font-medium text-tinta-900">Esta área é dos Sócios</h1>
          <p className="mt-2 text-sm text-tinta-600">
            Qualidade da automação, custos e equipe somam todos os mandatos da casa; com o seu acesso
            {papel ? ` (${papel})` : ""} você veria só uma parte deles, e um total parcial seria enganoso.
            Peça a um Sócio o que precisar daqui.
          </p>
        </div>
      </CasosLayout>
    );
  }
  return (
    <CasosLayout>
      <div className="space-y-6">
        {decisao === "liberada_sem_confirmar" && (
          <p role="status" className="rounded-lg border border-alerta-200 bg-alerta-50 px-3 py-2 text-sm text-alerta-900">
            {AVISO_TOTAIS_RECORTADOS}
          </p>
        )}
        <AbasDaAdministracao />
        {children}
      </div>
    </CasosLayout>
  );
}
