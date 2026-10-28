import { montarOrganograma, rotuloDoPercentual, type EntradaOrg, type NoOrg } from "@/lib/perimetro-organograma";
import { formatarCnpj } from "@/lib/perimetro";

// O PERÍMETRO COMO ORGANOGRAMA — uma VISÃO acima dos cartões (que seguem sendo onde se edita).
// Estrutura em <ul> aninhada com rótulos: o desenho (linhas, centralização) é só CSS em cima dela, e no
// celular (<640px) a mesma lista vira lista indentada. Sem dependência: HTML + Tailwind.
function Cartao({ n, raiz }: Readonly<{ n: NoOrg; raiz?: boolean }>) {
  return (
    <div className="inline-block rounded border border-tinta-200 bg-white px-3 py-2 text-left">
      <p className="text-sm font-medium text-tinta-900">{n.razao_social}</p>
      <p className="font-dado text-xs text-tinta-500">{formatarCnpj(n.cnpj)}</p>
      {!raiz && (
        <p className={`text-xs ${n.percentual === null ? "text-alerta-900" : "text-tinta-700"}`}>
          Participação da controladora: {rotuloDoPercentual(n.percentual)}
        </p>
      )}
      {n.nota && <p className="text-xs text-alerta-900">{n.nota}</p>}
    </div>
  );
}

function Ramo({ n, raiz }: Readonly<{ n: NoOrg; raiz?: boolean }>) {
  return (
    <li className="relative pl-4 sm:pl-0 sm:text-center">
      <Cartao n={n} raiz={raiz} />
      {n.filhos.length > 0 && (
        <ul aria-label={`Controladas por ${n.razao_social}`}
          className="mt-2 space-y-2 border-l border-tinta-200 sm:mt-3 sm:flex sm:flex-wrap sm:items-start sm:justify-center sm:gap-4 sm:space-y-0 sm:border-l-0 sm:border-t sm:pt-3">
          {n.filhos.map((f) => <Ramo key={f.id} n={f} />)}
        </ul>
      )}
    </li>
  );
}

export function Organograma({ entidades }: Readonly<{ entidades: EntradaOrg[] }>) {
  const o = montarOrganograma(entidades);
  if (entidades.length === 0) return null;
  return (
    <section className="carta space-y-4 p-5" aria-label="Organograma do grupo econômico">
      <h2 className="font-titulo text-xl font-medium text-tinta-900">Organograma</h2>
      <p className="text-sm text-tinta-600">
        Desenhado só com o que está registrado nos cartões abaixo. Empresa sem vínculo registrado não é tratada
        como independente: o vínculo é desconhecido.
      </p>
      {o.raizes.length > 0 && (
        <ul aria-label="Controladoras e controladas" className="space-y-4 sm:flex sm:flex-wrap sm:items-start sm:justify-center sm:gap-6 sm:space-y-0">
          {o.raizes.map((r) => <Ramo key={r.id} n={r} raiz />)}
        </ul>
      )}
      {o.controleComum.length > 0 && (
        <div>
          <p className="titulo-secao">Controle comum (sem controladora entre as empresas)</p>
          <ul className="mt-1 space-y-1">{o.controleComum.map((r) => <Ramo key={r.id} n={r} raiz />)}</ul>
        </div>
      )}
      {o.ciclos.map((c) => (
        <div key={c.membros.join("|")} role="status" className="rounded border border-risco-200 bg-risco-50 p-3 text-sm text-risco-900">
          <p className="font-medium">Controle circular: {c.membros.join(" → ")} → {c.membros[0]}.</p>
          <p>Uma empresa não pode controlar a si mesma por outra. Corrija a controladora nos cartões; até lá estas empresas não têm posição na árvore.</p>
          <ul className="mt-2 space-y-1">{c.raizes.map((r) => <Ramo key={r.id} n={r} raiz />)}</ul>
        </div>
      ))}
      {o.semVinculo.length > 0 && (
        <div className="rounded border border-alerta-200 bg-alerta-50 p-3 text-sm text-alerta-900">
          <p className="font-medium">Sem vínculo registrado ({o.semVinculo.length})</p>
          <p>Não se sabe se são controladoras, controladas ou independentes; o grupo pode estar maior ou menor do que o desenhado.</p>
          <ul className="mt-2 space-y-1">
            {o.semVinculo.map((s) => (
              <li key={s.id}><span className="font-medium">{s.razao_social}</span> <span className="font-dado text-xs">({formatarCnpj(s.cnpj)})</span> — {s.nota}</li>
            ))}
          </ul>
        </div>
      )}
      {o.naoIdentificadas.length > 0 && (
        <div className="text-sm text-risco-800">
          <p className="font-medium">Empresa não identificada ({o.naoIdentificadas.length}) — fora da árvore</p>
          <ul className="list-disc pl-5">{o.naoIdentificadas.map((f) => <li key={f.id}>{f.razao_social}</li>)}</ul>
        </div>
      )}
    </section>
  );
}
