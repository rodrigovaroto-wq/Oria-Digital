// A MONTAGEM DO ORGANOGRAMA DO PERÍMETRO — função pura sobre o que `fn_perimetro_situacao` (0208) já devolve.
//
// NÃO recalcula regra de negócio: só arruma `controladora_id` + `percentual_participacao` em árvore. O que ela
// garante é a regra 1 no desenho: parentesco DESCONHECIDO nunca vira "sem controladora" nem 0%.
//   - controladora desconhecida (forma indefinida, controladora não escolhida, ou apontando para empresa não
//     identificada/inexistente) -> grupo "Sem vínculo registrado", com a nota do efeito;
//   - % ausente (null) -> `percentual: null`, que a tela escreve "% não informado"; 0 medido continua 0;
//   - ciclo (A controla B, B controla A, ou empresa que controla a si mesma) -> NÃO some e NÃO entra em laço:
//     aparece num grupo próprio com o aviso. O dado tem uma só `controladora_id` por empresa, então "mais de
//     uma controladora" não é representável hoje; se a função do banco passar a devolver várias, este é o
//     lugar onde isso tem de aparecer como aviso, não como a primeira que vier.
//   - empresa não identificada (fantasma) fica à parte e NUNCA é controladora nem controlada da árvore.

export type EntradaOrg = {
  entidade_id: string; razao_social: string; cnpj: string | null; fantasma: boolean;
  forma_de_controle: string; controladora_id: string | null; percentual_participacao: number | null;
};

export type NoOrg = {
  id: string; razao_social: string; cnpj: string | null;
  percentual: number | null; // da participação NESTA controladora; null = não informado (nunca 0)
  nota?: string; filhos: NoOrg[];
};
export type SemVinculo = { id: string; razao_social: string; cnpj: string | null; nota: string };
export type Organograma = {
  raizes: NoOrg[];                 // controladoras no topo (têm ao menos uma controlada e nenhuma controladora)
  controleComum: NoOrg[];          // sem controladora entre as empresas, por sócio em comum declarado
  semVinculo: SemVinculo[];        // parentesco desconhecido
  ciclos: Array<{ membros: string[]; raizes: NoOrg[] }>;
  naoIdentificadas: Array<{ id: string; razao_social: string }>;
};

const NOTA_SEM_VINCULO = "Sem controladora e sem controle comum registrados: não se sabe se é controladora, controlada ou independente.";

export function montarOrganograma(entradas: EntradaOrg[]): Organograma {
  const reais = entradas.filter((e) => !e.fantasma);
  const porId = new Map(reais.map((e) => [e.entidade_id, e]));
  // pai válido = controladora que é empresa real do caso; qualquer outra coisa é parentesco desconhecido.
  const paiDe = (e: EntradaOrg) => (e.controladora_id && porId.has(e.controladora_id) ? e.controladora_id : null);

  // Ciclo: quem, seguindo o pai, volta a si mesmo. (Inclui auto-referência.)
  const emCiclo = new Set<string>();
  const cicloDe = new Map<string, string[]>();
  for (const e of reais) {
    const caminho: string[] = [];
    let atual: string | null = e.entidade_id;
    while (atual && !caminho.includes(atual)) { caminho.push(atual); const x = porId.get(atual); atual = x ? paiDe(x) : null; }
    if (atual && caminho.indexOf(atual) !== -1) {
      const membros = caminho.slice(caminho.indexOf(atual));
      if (membros.includes(e.entidade_id) && !emCiclo.has(e.entidade_id)) {
        for (const m of membros) { emCiclo.add(m); cicloDe.set(m, membros); }
      }
    }
  }

  // Filhos: arestas pai->filho, exceto a que fecha o ciclo (membro de ciclo apontando para membro do mesmo ciclo).
  const filhosDe = new Map<string, EntradaOrg[]>();
  for (const e of reais) {
    const p = paiDe(e);
    if (!p) continue;
    if (emCiclo.has(e.entidade_id) && emCiclo.has(p) && cicloDe.get(e.entidade_id) === cicloDe.get(p)) continue;
    filhosDe.set(p, [...(filhosDe.get(p) ?? []), e]);
  }
  const no = (e: EntradaOrg, percentual: number | null, nota?: string): NoOrg => ({
    id: e.entidade_id, razao_social: e.razao_social, cnpj: e.cnpj, percentual, ...(nota ? { nota } : {}),
    filhos: (filhosDe.get(e.entidade_id) ?? []).map((f) => no(f, f.percentual_participacao)),
  });
  const notaDaForma = (e: EntradaOrg) =>
    e.forma_de_controle === "controlada_por_entidade" && !paiDe(e) && filhosDe.has(e.entidade_id)
      ? "Marcada como controlada por outra empresa, mas a controladora não foi escolhida." : undefined;

  const out: Organograma = { raizes: [], controleComum: [], semVinculo: [], ciclos: [], naoIdentificadas: [] };
  for (const e of entradas.filter((x) => x.fantasma)) out.naoIdentificadas.push({ id: e.entidade_id, razao_social: e.razao_social });

  for (const e of reais) {
    if (emCiclo.has(e.entidade_id)) continue;
    if (paiDe(e)) continue; // entra como filho
    if (filhosDe.has(e.entidade_id)) { out.raizes.push(no(e, null, notaDaForma(e))); continue; }
    if (e.forma_de_controle === "controle_comum") { out.controleComum.push(no(e, null)); continue; }
    let nota = NOTA_SEM_VINCULO;
    if (e.controladora_id) nota = "A controladora indicada é uma empresa não identificada ou não está no caso: o vínculo não pode ser desenhado.";
    else if (e.forma_de_controle === "controlada_por_entidade") nota = "Marcada como controlada por outra empresa, mas a controladora não foi escolhida.";
    out.semVinculo.push({ id: e.entidade_id, razao_social: e.razao_social, cnpj: e.cnpj, nota });
  }

  const vistos = new Set<string[]>();
  for (const [, membros] of cicloDe) {
    if (vistos.has(membros)) continue;
    vistos.add(membros);
    out.ciclos.push({
      membros: membros.map((m) => porId.get(m)!.razao_social),
      raizes: membros.map((m) => no(porId.get(m)!, null)),
    });
  }
  return out;
}

/** "% não informado" quando ausente; 0 medido é "0%". Vírgula decimal. */
export function rotuloDoPercentual(p: number | null | undefined): string {
  if (p === null || p === undefined || Number.isNaN(p)) return "% não informado";
  return `${String(p).replace(".", ",")}%`;
}

/** Quantas empresas reais a árvore desenhou ou listou: a conta que prova que nenhuma sumiu. */
export function contarNoOrganograma(o: Organograma): number {
  const n = (x: NoOrg): number => 1 + x.filhos.reduce((s, f) => s + n(f), 0);
  return o.raizes.reduce((s, x) => s + n(x), 0) + o.controleComum.reduce((s, x) => s + n(x), 0)
    + o.semVinculo.length + o.ciclos.reduce((s, c) => s + c.raizes.reduce((t, x) => t + n(x), 0), 0);
}
