import { createClient } from "@/lib/supabase/server";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { AlocarPessoa, MandatoAlocado } from "@/components/equipe-forms";
import { ROTULO_DO_PAPEL, type Permissoes } from "@/lib/acesso";
import { MENSAGEM_FALTA_ATUALIZAR_O_BANCO, equipeDoMandato, textoDaFalhaDaEquipe } from "@/lib/equipe";
import { lerEquipe } from "@/lib/supabase/equipe";

// EQUIPE DO MANDATO — quem trabalha aqui, na Visão geral. Quem vê a lista é o Sócio: para os demais
// papéis a RLS devolve só a PRÓPRIA linha de `alocacao` (alocacao_read), e mostrar "1 pessoa alocada"
// seria uma afirmação sobre a equipe que o banco não deixou ninguém medir. Eles recebem uma frase com
// o próprio papel. Alocar e retirar passam pelas funções do banco (só Sócio); ver `equipe/actions.ts`.
// E-mail: vem de `fn_membros_da_equipe` (0216). Sem ela a tela cai no modo antigo, diz que falta a
// atualização do banco e mostra o código curto (ver `lib/equipe.ts`).
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
  const [claimsRes, lida] = await Promise.all([supabase.auth.getClaims(), lerEquipe(supabase, casoId)]);
  if (lida.estado === "falha") {
    return (
      <section className="space-y-2" aria-label="Equipe do mandato">
        {titulo}
        <div className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          <p>{textoDaFalhaDaEquipe(lida.code)} A equipe deste mandato não foi carregada, então a tela não afirma quem está alocado.</p>
          <DetalhesTecnicos><p>{lida.message}</p></DetalhesTecnicos>
        </div>
      </section>
    );
  }

  const claims = claimsRes.data?.claims;
  const eu = claims?.sub ? { id: claims.sub as string, email: (claims.email as string | undefined) ?? null } : null;
  const equipe = equipeDoMandato(lida.membros, casoId, eu);

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
      {lida.incompleta && (
        <p role="status" className="text-xs text-alerta-900">
          Parte da equipe não terminou de ser lida: a lista acima pode estar incompleta.
        </p>
      )}
      {lida.modo === "antigo" && (
        <p role="note" className="text-xs text-alerta-900">{MENSAGEM_FALTA_ATUALIZAR_O_BANCO}</p>
      )}
      <p className="text-xs text-tinta-500">Papéis e a visão de toda a equipe ficam em Administração › Equipe.</p>
    </section>
  );
}
