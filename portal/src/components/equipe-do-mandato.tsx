import { createClient } from "@/lib/supabase/server";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { AlocarPessoa, MandatoAlocado } from "@/components/equipe-forms";
import { ROTULO_DO_PAPEL, ehPapel, type Permissoes } from "@/lib/acesso";
import { equipeDoMandato, type Alocacao, type Membro } from "@/lib/equipe";

// EQUIPE DO MANDATO — quem trabalha aqui, na Visão geral. Quem vê a lista é o Sócio: para os demais
// papéis a RLS devolve só a PRÓPRIA linha de `alocacao` (alocacao_read), e mostrar "1 pessoa alocada"
// seria uma afirmação sobre a equipe que o banco não deixou ninguém medir. Eles recebem uma frase com
// o próprio papel. Alocar e retirar passam pelas funções do banco (só Sócio); ver `equipe/actions.ts`.
// E-mail: o banco não o expõe (ver `lib/equipe.ts`), então as pessoas aparecem pelo código curto.
export async function EquipeDoMandato({ casoId, permissoes }: Readonly<{ casoId: string; permissoes: Permissoes }>) {
  const titulo = <h2 className="titulo-secao">Equipe do mandato</h2>;

  if (!permissoes.conferido) {
    return (
      <section className="space-y-2" aria-label="Equipe do mandato">
        {titulo}
        <p className="text-sm text-tinta-600">Não foi possível conferir o seu papel agora, então a equipe do mandato não foi carregada.</p>
      </section>
    );
  }
  if (permissoes.papel !== "socio") {
    return (
      <section className="space-y-2" aria-label="Equipe do mandato">
        {titulo}
        <p className="text-sm text-tinta-600">
          Você acessa este mandato como <strong className="font-medium text-tinta-800">{permissoes.papel ? ROTULO_DO_PAPEL[permissoes.papel] : "—"}</strong>.
          A lista de quem mais trabalha nele é vista só por Sócios, que também alocam e retiram pessoas.
        </p>
      </section>
    );
  }

  const supabase = await createClient();
  const [claimsRes, membrosRes, alocacoesRes] = await Promise.all([
    supabase.auth.getClaims(),
    supabase.from("membro").select("usuario_id, papel"),
    supabase.from("alocacao").select("caso_id, usuario_id").eq("caso_id", casoId),
  ]);
  const falha = membrosRes.error ?? alocacoesRes.error;
  if (falha) {
    return (
      <section className="space-y-2" aria-label="Equipe do mandato">
        {titulo}
        <div className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          <p>Não foi possível ler a equipe deste mandato agora, então a tela não afirma quem está alocado.</p>
          <DetalhesTecnicos><p>{falha.message}</p></DetalhesTecnicos>
        </div>
      </section>
    );
  }

  const claims = claimsRes.data?.claims;
  const eu = claims?.sub ? { id: claims.sub as string, email: (claims.email as string | undefined) ?? null } : null;
  const membros = ((membrosRes.data as Array<{ usuario_id: string; papel: unknown }> | null) ?? [])
    .filter((m): m is Membro => ehPapel(m.papel));
  const equipe = equipeDoMandato(membros, (alocacoesRes.data as Alocacao[] | null) ?? [], eu);

  return (
    <section className="space-y-3" aria-label="Equipe do mandato">
      <div className="flex flex-wrap items-baseline justify-between gap-3">
        {titulo}
        <p className="text-xs text-tinta-500">
          {equipe.socios} {equipe.socios === 1 ? "Sócio vê" : "Sócios veem"} este mandato sem alocação.
        </p>
      </div>
      {equipe.alocados.length === 0 ? (
        <p className="text-sm text-tinta-700">
          Nenhum Analista nem Leitura está alocado neste mandato — só os Sócios o veem.
        </p>
      ) : (
        <div className="flex flex-wrap gap-2">
          {equipe.alocados.map((p) => (
            <MandatoAlocado
              key={p.usuario_id} casoId={casoId} usuarioId={p.usuario_id}
              nome={`${p.pessoa.rotulo} · ${ROTULO_DO_PAPEL[p.papel]}`}
            />
          ))}
        </div>
      )}
      {equipe.semPapel > 0 && (
        <p className="text-xs text-alerta-900">
          {equipe.semPapel} {equipe.semPapel === 1 ? "alocação é de usuário" : "alocações são de usuários"} sem papel hoje —
          não {equipe.semPapel === 1 ? "vale" : "valem"} até um Sócio devolver o papel.
        </p>
      )}
      <AlocarPessoa
        casoId={casoId}
        pessoas={equipe.alocaveis.map((p) => ({ usuario_id: p.usuario_id, rotulo: p.pessoa.rotulo, papel: p.papel }))}
      />
      <p className="text-xs text-tinta-500">
        Papéis e a visão de toda a equipe ficam em Administração › Equipe. O e-mail das pessoas ainda não
        é lido do banco: aparece o código do usuário.
      </p>
    </section>
  );
}
