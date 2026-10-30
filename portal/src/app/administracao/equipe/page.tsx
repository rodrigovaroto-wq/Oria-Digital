import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import { lerAcesso } from "@/lib/supabase/acesso";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { EtiquetaDoPapel } from "@/components/acesso-na-tela";
import { AlocarEmMandato, LiberarMembro, LiberarPorCodigo, MandatoAlocado, SeletorDePapel } from "@/components/equipe-forms";
import { MOTIVO_SEM_PAPEL, O_QUE_O_PAPEL_FAZ, PAPEIS, ROTULO_DO_PAPEL } from "@/lib/acesso";
import {
  MENSAGEM_FALTA_ATUALIZAR_O_BANCO, aguardandoLiberacao, linhasDaEquipe, textoDaFalhaDaEquipe, type CasoDaEquipe,
} from "@/lib/equipe";
import { lerEquipe } from "@/lib/supabase/equipe";

// EQUIPE — quem tem papel e em quais mandatos está alocado. Só o Sócio gere (0216).
//
// POR QUE A ABA SOME PARA QUEM NÃO É SÓCIO, em vez de aparecer em modo leitura. A RLS deixa cada
// pessoa ler só a PRÓPRIA linha de `membro` e de `alocacao` (membro_read / alocacao_read: "cada um lê o
// próprio; Sócio lê todos"): uma "lista da equipe" de Analista teria uma linha — ele mesmo — e
// pareceria dizer que a equipe é uma pessoa só (regra 1). Quem chega ao endereço direto vê esta
// explicação com o próprio papel, não uma lista truncada.
//
// DE ONDE VEM O E-MAIL: `auth.users` não é legível pelo PostgREST, então a lista vem de
// `fn_membros_da_equipe` (0216, só Sócio): todos os usuários do Auth, com e-mail e papel (nulo = ainda
// não liberado → seção "Aguardando liberação"). Banco sem a função: a tela DIZ que falta a atualização
// e segue no modo antigo (só quem tem papel, pelo código; formulário por UUID). Ver `lib/equipe.ts`.
export const dynamic = "force-dynamic";

export default async function EquipePage() {
  const acesso = await lerAcesso();

  if (acesso.estado === "ok" && acesso.papel !== "socio") {
    return (
      <div className="space-y-3">
        <h1 className="text-lg font-semibold text-tinta-900">Equipe</h1>
        <p role="note" className="rounded-lg border border-tinta-200 bg-tinta-50 px-3 py-2 text-sm text-tinta-700">
          {acesso.papel === null
            ? MOTIVO_SEM_PAPEL
            : `Gerir a equipe é reservado a Sócio (seu papel: ${ROTULO_DO_PAPEL[acesso.papel]}). Para mudar seu papel ou sua alocação em um mandato, peça a um Sócio.`}
        </p>
      </div>
    );
  }

  const supabase = await createClient();
  const [claimsRes, equipeRes, casosRes] = await Promise.all([
    supabase.auth.getClaims(),
    lerEquipe(supabase),
    paginar<CasoDaEquipe>((de, ate) =>
      supabase.from("caso").select("id, nome, fechado_em")
        .order("criado_em", { ascending: false }).order("id", { ascending: true }).range(de, ate)),
  ]);

  // Falha de leitura NÃO é "equipe vazia": sem esta tela dizer, "Sem membros" seria falso.
  const falhaEquipe = equipeRes.estado === "falha" ? equipeRes : null;
  const falha = falhaEquipe?.message ?? casosRes.error?.message ?? null;
  const incompleta = casosRes.truncado || (equipeRes.estado === "ok" && equipeRes.incompleta);
  const claims = claimsRes.data?.claims;
  const eu = claims?.sub ? { id: claims.sub as string, email: (claims.email as string | undefined) ?? null } : null;

  const modoAntigo = equipeRes.estado === "ok" && equipeRes.modo === "antigo";
  const membros = equipeRes.estado === "ok" ? equipeRes.membros : [];
  const linhas = falha ? [] : linhasDaEquipe(membros, casosRes.data, eu);
  const aguardando = falha || modoAntigo ? [] : aguardandoLiberacao(membros, eu);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-lg font-semibold text-tinta-900">Equipe</h1>
        <p className="mt-1 max-w-3xl text-sm text-tinta-500">
          Quem entra no portal e o que cada pessoa vê. As mudanças valem na hora e ficam na trilha.
        </p>
        <ul className="mt-2 space-y-0.5 text-xs text-tinta-600">
          {PAPEIS.map((p) => (
            <li key={p}><strong className="font-medium text-tinta-800">{ROTULO_DO_PAPEL[p]}</strong> — {O_QUE_O_PAPEL_FAZ[p]}.</li>
          ))}
        </ul>
      </div>

      {acesso.estado === "falha" && (
        <p role="status" className="rounded-lg border border-alerta-200 bg-alerta-50 px-3 py-2 text-sm text-alerta-900">
          Não foi possível conferir o seu papel agora. A tela abre mesmo assim, e o sistema recusa
          qualquer mudança que não seja de Sócio.
        </p>
      )}

      {falha && (
        <div className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          <p>{falhaEquipe ? textoDaFalhaDaEquipe(falhaEquipe.code) : "Não foi possível ler os mandatos agora, então esta tela não afirma onde cada pessoa está alocada. Recarregue a página; se continuar, avise o administrador do sistema."}</p>
          <DetalhesTecnicos><p>{falha}</p></DetalhesTecnicos>
        </div>
      )}
      {!falha && incompleta && (
        <p role="status" className="rounded-lg border border-alerta-200 bg-alerta-50 px-3 py-2 text-sm text-alerta-900">
          Parte da equipe, das alocações ou dos mandatos não terminou de ser lida: a lista abaixo pode estar incompleta.
        </p>
      )}

      {modoAntigo && (
        <p role="note" className="rounded-lg border border-alerta-200 bg-alerta-50 px-3 py-2 text-sm text-alerta-900">
          {MENSAGEM_FALTA_ATUALIZAR_O_BANCO}
        </p>
      )}

      {!falha && (
        linhas.length === 0 ? (
          <p className="carta p-4 text-sm text-tinta-700">
            O banco não devolveu nenhum membro. Sem Sócio, ninguém acessa nada: avise o administrador do sistema.
          </p>
        ) : (
          <ul className="carta divide-y divide-tinta-100">
            {linhas.map((l) => (
              <li key={l.usuario_id} className="space-y-3 p-4">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-sm font-semibold text-tinta-900">{l.pessoa.rotulo}</span>
                  {l.pessoa.voce && <span className="chip bg-ok-100 text-ok-800">você</span>}
                  <EtiquetaDoPapel papel={l.papel} />
                  {!l.pessoa.temEmail && <span className="font-dado text-xs text-tinta-500">{l.usuario_id}</span>}
                </div>
                <SeletorDePapel
                  usuarioId={l.usuario_id}
                  papel={l.papel}
                  motivoTravado={l.unicoSocio ? "É o único Sócio: o portal não pode ficar sem um." : null}
                />
                {l.veTodos ? (
                  <p className="text-xs text-tinta-600">Vê e altera todos os mandatos; não precisa de alocação.</p>
                ) : (
                  <div className="space-y-2">
                    <p className="text-xs font-medium text-tinta-700">
                      {l.alocados.length === 0 && l.alocadosNaoLidos === 0
                        ? "Não está alocado em nenhum mandato — não vê nenhum."
                        : `Alocado em ${l.alocados.length + l.alocadosNaoLidos} ${l.alocados.length + l.alocadosNaoLidos === 1 ? "mandato" : "mandatos"}:`}
                    </p>
                    {l.alocados.length > 0 && (
                      <div className="flex flex-wrap gap-2">
                        {l.alocados.map((c) => (
                          <MandatoAlocado key={c.id} casoId={c.id} usuarioId={l.usuario_id} nome={c.nome} />
                        ))}
                      </div>
                    )}
                    {l.alocadosNaoLidos > 0 && (
                      <p className="text-xs text-alerta-900">
                        {l.alocadosNaoLidos} {l.alocadosNaoLidos === 1 ? "alocação aponta" : "alocações apontam"} para mandato que não foi lido agora.
                      </p>
                    )}
                    <AlocarEmMandato
                      usuarioId={l.usuario_id}
                      mandatos={l.alocaveis.map((c) => ({ id: c.id, nome: c.nome, fechado: c.fechado_em !== null }))}
                    />
                  </div>
                )}
              </li>
            ))}
          </ul>
        )
      )}

      {!falha && !modoAntigo && (
        <section className="space-y-2" aria-label="Aguardando liberação">
          <h2 className="titulo-secao">Aguardando liberação</h2>
          <p className="max-w-3xl text-xs text-tinta-500">
            Já entraram no portal e ainda não têm papel: não veem nada até um Sócio definir. Analista e
            Leitura também precisam ser alocados nos mandatos, na lista acima.
          </p>
          {aguardando.length === 0 ? (
            <p className="carta p-4 text-sm text-tinta-700">Ninguém aguardando: todos os usuários do portal já têm papel.</p>
          ) : (
            <ul className="carta divide-y divide-tinta-100">
              {aguardando.map((p) => (
                <li key={p.usuario_id} className="space-y-2 p-4">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="text-sm font-semibold text-tinta-900">{p.pessoa.rotulo}</span>
                    {p.pessoa.voce && <span className="chip bg-ok-100 text-ok-800">você</span>}
                    {!p.pessoa.temEmail && <span className="font-dado text-xs text-tinta-500">{p.usuario_id}</span>}
                    {p.criado_em && <span className="text-xs text-tinta-500">entrou em {new Date(p.criado_em).toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" })}</span>}
                  </div>
                  <LiberarMembro usuarioId={p.usuario_id} rotulo={p.pessoa.rotulo} />
                  {p.alocacoesGuardadas > 0 && (
                    <p className="text-xs text-alerta-900">
                      {p.alocacoesGuardadas} {p.alocacoesGuardadas === 1 ? "alocação guardada" : "alocações guardadas"} de quando tinha papel: sem efeito até o papel voltar.
                    </p>
                  )}
                </li>
              ))}
            </ul>
          )}
        </section>
      )}

      {!falha && modoAntigo && (
        <section className="space-y-2">
          <h2 className="titulo-secao">Liberar acesso a quem ainda não tem papel</h2>
          <p className="max-w-3xl text-xs text-tinta-500">
            Sem a atualização do banco esta tela não lista quem espera liberação. Cole o código do usuário
            (Authentication › Users) e escolha o papel; Analista e Leitura ainda precisam ser alocados nos mandatos.
          </p>
          <LiberarPorCodigo />
        </section>
      )}
    </div>
  );
}
