import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { CartaoEntidade, type EntidadeSituacao } from "./CartaoEntidade";
import {
  confirmarEscopo, definirForma, definirPapel, definirParticipacao, encerrarEscopo,
  registrarControlador, vincularControlador, type AcoesPerimetro,
} from "./actions";
import { rotuloDoAceite, tituloDoVeredito } from "@/lib/perimetro";

// O PERÍMETRO DO MANDATO: quem entra no combinado, com que papel, controlado por quem.
//
// A regra do que falta mora no banco (`fn_perimetro_situacao`/`fn_perimetro_veredito`, 0208): esta tela
// lê e traduz, não recalcula. O aceite financeiro NUNCA some: sem combinado do cliente para comparar, o
// perímetro cadastrado pode incluir ou excluir uma empresa que o cliente trata diferente (regra 1).
type Veredito = {
  entidades: number; prontas: number; fantasmas: number; fechado: boolean; fechado_motivo: string;
  grupos: Array<{ grupo_id: string; quantas: number; entidades: Array<{ entidade_id: string; razao_social: string }> }>;
  aceite_financeiro: string; aceite_motivo: string;
};

export default async function PerimetroPage({ params }: Readonly<{ params: Promise<{ id: string }> }>) {
  const { id } = await params;
  const supabase = await createClient();
  const [casoRes, vereditoRes, situacaoRes, controladoresRes] = await Promise.all([
    supabase.from("caso").select("nome").eq("id", id).single(),
    supabase.rpc("fn_perimetro_veredito", { p_caso_id: id }),
    supabase.rpc("fn_perimetro_situacao", { p_caso_id: id }),
    supabase.from("controlador").select("id, nome").eq("caso_id", id).order("nome"),
  ]);
  const veredito = ((vereditoRes.data ?? [])[0] ?? null) as Veredito | null;
  const situacao = (situacaoRes.data ?? []) as EntidadeSituacao[];
  const reais = situacao.filter((s) => !s.fantasma);
  const fantasmas = situacao.filter((s) => s.fantasma);
  const existentes = (controladoresRes.data ?? []) as Array<{ id: string; nome: string }>;
  const hoje = new Date().toISOString().slice(0, 10);
  // Amarradas AQUI, no servidor: o id do caso não passa pelo navegador como dado editável.
  const acoes: AcoesPerimetro = {
    papel: definirPapel.bind(null, id), forma: definirForma.bind(null, id),
    participacao: definirParticipacao.bind(null, id), controlador: registrarControlador.bind(null, id),
    vinculo: vincularControlador.bind(null, id), escopoDefinir: confirmarEscopo.bind(null, id),
    escopoEncerrar: encerrarEscopo.bind(null, id),
  };
  const todas = reais.map((s) => ({ entidade_id: s.entidade_id, razao_social: s.razao_social }));
  const falhaLeitura = vereditoRes.error ?? situacaoRes.error;
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="font-titulo text-2xl font-medium tracking-tight text-tinta-900">
            Perímetro{casoRes.data?.nome ? ` — ${casoRes.data.nome}` : ""}
          </h1>
          <p className="mt-0.5 text-sm text-tinta-500">Quem entra no combinado, com que papel e controlado por quem.</p>
        </div>
        <Link href={`/casos/${id}`} className="btn-secundario">Voltar ao mandato</Link>
      </div>

      {falhaLeitura && (
        <output className="carta block p-4 text-sm text-risco-800">
          Não foi possível ler o perímetro ({falhaLeitura.message}). Se a função não existe, a migration 0208 ainda não foi
          aplicada: a tela não mostra o perímetro como fechado nem como aberto, ela não sabe.
        </output>
      )}

      {veredito && (
        <section className="carta space-y-3 p-5">
          <h2 className="font-titulo text-xl font-medium text-tinta-900">{tituloDoVeredito(veredito)}</h2>
          <p className="text-sm text-tinta-700">{veredito.fechado_motivo}</p>
          {veredito.fantasmas > 0 && (
            <p className="text-sm text-risco-800">
              {veredito.fantasmas} entidade(s) fantasma à parte, no fim da página: não contam como empresas.
            </p>
          )}
          {veredito.grupos.length > 0 && (
            <div>
              <p className="titulo-secao">Grupos por controle comum</p>
              <ul className="mt-1 space-y-1 text-sm text-tinta-800">
                {veredito.grupos.map((g) => (
                  <li key={g.grupo_id}>{g.quantas} empresas: {g.entidades.map((x) => x.razao_social).join(", ")}</li>
                ))}
              </ul>
            </div>
          )}
          {/* SEMPRE visível: "não verificado" não é "ok", e some-lo faria o perímetro parecer conferido. */}
          <div className="rounded border border-alerta-200 bg-alerta-50 p-3 text-sm text-alerta-900">
            <p className="font-medium">Aceite financeiro: {rotuloDoAceite(veredito.aceite_financeiro)}</p>
            <p className="mt-1">{veredito.aceite_motivo}</p>
          </div>
        </section>
      )}

      {reais.map((e) => (
        <CartaoEntidade key={e.entidade_id} e={e} todas={todas} existentes={existentes} hoje={hoje} acoes={acoes} casoId={id} />
      ))}

      {fantasmas.length > 0 && (
        <>
          <h2 className="titulo-secao">Entidades fantasma ({fantasmas.length})</h2>
          {fantasmas.map((e) => (
            <CartaoEntidade key={e.entidade_id} e={e} todas={todas} existentes={existentes} hoje={hoje} acoes={acoes} casoId={id} />
          ))}
        </>
      )}
    </div>
  );
}
