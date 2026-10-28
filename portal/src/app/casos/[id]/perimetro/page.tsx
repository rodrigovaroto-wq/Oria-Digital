import { createClient } from "@/lib/supabase/server";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { CartaoEntidade, type EntidadeSituacao } from "./CartaoEntidade";
import {
  confirmarEscopo, definirForma, definirPapel, definirParticipacao, encerrarEscopo,
  registrarControlador, vincularControlador, vincularFamilia, desvincularFamilia, type AcoesPerimetro,
} from "./actions";
import { Organograma } from "./Organograma";
import { SecaoParentesco, type VinculoVigente } from "./SecaoParentesco";
import { rotuloDoAceite, rotuloDoMotivoDoGrupo, rotuloDoParentesco, tituloDoVeredito } from "@/lib/perimetro";

// O PERÍMETRO DO MANDATO: quem entra no combinado, com que papel, controlado por quem.
//
// A regra do que falta mora no banco (`fn_perimetro_situacao`/`fn_perimetro_veredito`, 0208): esta tela
// lê e traduz, não recalcula. O aceite financeiro NUNCA some: sem combinado do cliente para comparar, o
// perímetro cadastrado pode incluir ou excluir uma empresa que o cliente trata diferente (regra 1).
type Veredito = {
  entidades: number; prontas: number; fantasmas: number; fechado: boolean; fechado_motivo: string;
  grupos: Array<{
    grupo_id: string; quantas: number; entidades: Array<{ entidade_id: string; razao_social: string }>;
    motivo?: string; // ausente num banco sem a 0212: a tela diz "não informado", não assume sócio em comum
    vinculos?: Array<{ vinculo_id: string; parentesco: string; fonte: string; declarado_por: string; controlador_a: string; controlador_b: string }>;
  }>;
  aceite_financeiro: string; aceite_motivo: string;
};

export default async function PerimetroPage({ params }: Readonly<{ params: Promise<{ id: string }> }>) {
  const { id } = await params;
  const supabase = await createClient();
  const [vereditoRes, situacaoRes, controladoresRes, vinculosRes] = await Promise.all([
    supabase.rpc("fn_perimetro_veredito", { p_caso_id: id }),
    supabase.rpc("fn_perimetro_situacao", { p_caso_id: id }),
    supabase.from("controlador").select("id, nome, documento, tipo_pessoa").eq("caso_id", id).order("nome"),
    supabase.from("controlador_vinculo")
      .select("id, controlador_a, controlador_b, parentesco, fonte, declarado_por").eq("caso_id", id).is("encerrado_em", null),
  ]);
  const veredito = ((vereditoRes.data ?? [])[0] ?? null) as Veredito | null;
  const situacao = (situacaoRes.data ?? []) as EntidadeSituacao[];
  const reais = situacao.filter((s) => !s.fantasma);
  const fantasmas = situacao.filter((s) => s.fantasma);
  const controladores = (controladoresRes.data ?? []) as Array<{ id: string; nome: string; documento: string | null; tipo_pessoa: string }>;
  const existentes = controladores.map(({ id: cid, nome }) => ({ id: cid, nome }));
  const socios = controladores.filter((c) => c.tipo_pessoa === "fisica");
  const vinculos = (vinculosRes.data ?? []) as VinculoVigente[];
  const hoje = new Date().toISOString().slice(0, 10);
  // Amarradas AQUI, no servidor: o id do caso não passa pelo navegador como dado editável.
  const acoes: AcoesPerimetro = {
    papel: definirPapel.bind(null, id), forma: definirForma.bind(null, id),
    participacao: definirParticipacao.bind(null, id), controlador: registrarControlador.bind(null, id),
    vinculo: vincularControlador.bind(null, id), escopoDefinir: confirmarEscopo.bind(null, id),
    escopoEncerrar: encerrarEscopo.bind(null, id),
    vincularFamilia: vincularFamilia.bind(null, id), desvincularFamilia: desvincularFamilia.bind(null, id),
  };
  const todas = reais.map((s) => ({ entidade_id: s.entidade_id, razao_social: s.razao_social }));
  const falhaLeitura = vereditoRes.error ?? situacaoRes.error;
  // Sem a 0212 a tabela não existe: o erro aparece, e a seção de parentesco não finge que não há vínculos.
  const falhaVinculos = vinculosRes.error;
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-lg font-semibold text-tinta-900">Grupo econômico</h1>
          <p className="mt-0.5 text-sm text-tinta-500">Quem entra no combinado, com que papel e controlado por quem.</p>
        </div>
      </div>

      {falhaLeitura && (
        <output className="carta block p-4 text-sm text-risco-800">
          <p>
            Não foi possível ler o grupo econômico. A tela não o mostra como fechado nem como aberto,
            porque não sabe. Avise o administrador do sistema.
          </p>
          <DetalhesTecnicos>
            <p>{falhaLeitura.message}</p>
            <p>Se a função não existe, a migration 0208 ainda não foi aplicada.</p>
          </DetalhesTecnicos>
        </output>
      )}

      {veredito && (
        <section className="carta space-y-3 p-5">
          <h2 className="font-titulo text-xl font-medium text-tinta-900">{tituloDoVeredito(veredito)}</h2>
          <p className="text-sm text-tinta-700">{veredito.fechado_motivo}</p>
          {veredito.fantasmas > 0 && (
            <p className="text-sm text-risco-800">
              {veredito.fantasmas} empresa(s) não identificada(s) à parte, no fim da página: não contam como empresas.
            </p>
          )}
          {veredito.grupos.length > 0 && (
            <div>
              <p className="titulo-secao">Grupos por controle comum</p>
              <ul className="mt-1 space-y-1 text-sm text-tinta-800">
                {veredito.grupos.map((g) => (
                  <li key={g.grupo_id} className="space-y-0.5">
                    <p>{g.quantas} empresas: {g.entidades.map((x) => x.razao_social).join(", ")}</p>
                    <p className="text-xs text-tinta-500">{rotuloDoMotivoDoGrupo(g.motivo)}</p>
                    {(g.vinculos ?? []).length > 0 && (
                      <ul className="list-disc pl-5 text-xs text-tinta-600">
                        {(g.vinculos ?? []).map((v) => (
                          <li key={v.vinculo_id}>
                            {v.controlador_a} e {v.controlador_b} — {rotuloDoParentesco(v.parentesco)} (fonte: {v.fonte}; declarado por {v.declarado_por})
                          </li>
                        ))}
                      </ul>
                    )}
                  </li>
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

      {!falhaLeitura && <Organograma entidades={situacao} />}

      {falhaVinculos && (
        <output className="carta block p-4 text-sm text-risco-800">
          <p>
            Não foi possível ler os vínculos familiares. A lista abaixo NÃO afirma que não há
            parentesco declarado. Avise o administrador do sistema.
          </p>
          <DetalhesTecnicos>
            <p>{falhaVinculos.message}</p>
            <p>Se a tabela não existe, a migration 0212 ainda não foi aplicada.</p>
          </DetalhesTecnicos>
        </output>
      )}
      <SecaoParentesco socios={socios} vinculos={vinculos} vincular={acoes.vincularFamilia} desvincular={acoes.desvincularFamilia} />

      {reais.map((e) => (
        <CartaoEntidade key={e.entidade_id} e={e} todas={todas} existentes={existentes} hoje={hoje} acoes={acoes} casoId={id} />
      ))}

      {fantasmas.length > 0 && (
        <>
          <h2 className="titulo-secao">Empresas não identificadas ({fantasmas.length})</h2>
          {fantasmas.map((e) => (
            <CartaoEntidade key={e.entidade_id} e={e} todas={todas} existentes={existentes} hoje={hoje} acoes={acoes} casoId={id} />
          ))}
        </>
      )}
    </div>
  );
}
