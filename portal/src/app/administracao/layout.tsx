import CasosLayout from "@/app/casos/layout";
import { AbasDaAdministracao } from "./abas-da-administracao";

// A Administração é GLOBAL (o dial e o custo valem para a mesa inteira, não para um
// mandato), por isso mora em `/administracao` e não em `/casos/...`. Usa a MESMA
// moldura dos mandatos — um segundo cabeçalho sairia de sincronia na primeira mudança —
// e põe as abas dentro dela.
export default function AdministracaoLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <CasosLayout>
      <div className="space-y-6">
        <AbasDaAdministracao />
        {children}
      </div>
    </CasosLayout>
  );
}
