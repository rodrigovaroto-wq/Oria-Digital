import CasosLayout from "@/app/casos/layout";
import { lerAcesso } from "@/lib/supabase/acesso";
import { administracaoLiberada, ROTULO_DO_PAPEL } from "@/lib/acesso";
import { AbasDaAdministracao } from "./abas-da-administracao";

// A Administração é GLOBAL (o dial e o custo valem para a mesa inteira, não para um
// mandato), por isso mora em `/administracao` e não em `/casos/...`. Usa a MESMA
// moldura dos mandatos — um segundo cabeçalho sairia de sincronia na primeira mudança —
// e põe as abas dentro dela.
// Se o papel não pôde ser lido a área abre (o banco ainda recorta): fechar por falha de leitura
// trancaria o Sócio fora do próprio portal.
export default async function AdministracaoLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const acesso = await lerAcesso();
  // A ADMINISTRAÇÃO INTEIRA É DO SÓCIO. Custos, concordância da classificação, cobertura do golden set e a
  // trilha do dial somam TODOS os mandatos, e a RLS por mandato (0216) entrega a quem só vê os alocados um
  // recorte que parece total: custo "total" só dos alocados, golden zerado, trilha do dial vazia. Número
  // parcial com cara de total é ausência apresentada como dado (regra 1) — então a área fecha, e diz por quê.
  if (!administracaoLiberada(acesso)) {
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
        <AbasDaAdministracao />
        {children}
      </div>
    </CasosLayout>
  );
}
