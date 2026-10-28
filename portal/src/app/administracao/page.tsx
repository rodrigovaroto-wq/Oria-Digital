import { createClient } from "@/lib/supabase/server";
import { DetalhesTecnicos } from "@/components/detalhes-tecnicos";
import { formatarTipoTaxonomia } from "@/lib/export";

// Painel de autonomia — SOMENTE LEITURA.
//
// POR QUE ESTA TELA EXISTE. `estagio_autonomia` nasce na 0001 com o comentário
// "Nível é estado do sistema, não constante de código (Arquitetura do Sistema/1 Visão e Doutrina/01)" e, até a 0041,
// não tinha um único leitor: `grep -rl estagio_autonomia portal/src n8n` não
// retornava nada. O dial da extração dizia N0 ("roda, registra, NÃO influencia
// decisão") enquanto o código auto-aceitava toda linha com confiança >= 0.95. O
// estado declarado do sistema era invisível, então a divergência podia durar
// meses sem ninguém tropeçar nela. Esta tela é onde ela para de ser invisível.
//
// POR QUE SÓ LEITURA. Subir dial é decisão de doutrina, não de sessão: Arquitetura do Sistema/1 Visão e Doutrina/01
// exige concordância MEDIDA contra golden set, e a mudança é global (afeta todo
// mandato, não o que está aberto). Um botão aqui convidaria a mexer no meio de um
// caso. A mudança se faz por `fn_mudar_dial`, que registra autor e motivo — e é
// ação do dono, como migration e teste ao vivo (CLAUDE.md).

type Dial = {
  estagio: string;
  nivel_atual: "N0" | "N1" | "N2" | "N3";
  teto: "N0" | "N1" | "N2" | "N3";
  limiar_auto_clear: number | null;
  // 0126: a natureza do estágio (Arquitetura do Sistema/1 Visão e Doutrina/01, "regra de teto por natureza") e em que
  // o nível de hoje se apoia. Antes desta migration a tela DEDUZIA a segunda por
  // `estagio.startsWith("extracao")` — heurística de nome, que errava nos dois
  // sentidos: estágio de extração que ganhasse medição continuava recebendo o
  // aviso, e estágio de outro nome que subisse sem medição não recebia nenhum.
  natureza: "deterministico" | "interpretativo";
  base_do_nivel: "nao_se_aplica" | "declarada" | "medida" | "medida_por_veredito";
  auto_promocao: boolean;
  medicao_rodada_id: string | null;
  medicao_em: string | null;
  atualizado_por: string | null;
  atualizado_em: string | null;
};

type EventoDial = {
  ator: string;
  acao: string;
  entidade_ref: string;
  depois: {
    motivo?: string;
    motivo_informado?: string;
    pedido?: string;
    teto?: string;
    sem_medicao_porque?: string;
  } | null;
  criado_em: string;
};

type Rodada = {
  id: string;
  nome: string;
  taxonomia_versao: number;
  congelada_em: string | null;
  criada_em: string;
};

type ConcordanciaCC = {
  com_veredito_humano: number;
  concordaram: number;
  concordancia: number | null;
  sem_veredito_humano: number;
  rubricas_que_mais_erram: { padrao: string; sugeria: string; erros: number }[];
};

type Cobertura = {
  tipo: string;
  granularidade: string;
  n_documentos: number;
  n_dois_rotuladores: number;
  estratos: string[];
  n_minimo: number;
  atinge_minimo: boolean;
};

// Arquitetura do Sistema/1 Visão e Doutrina/01, tabela de níveis. O texto é o da doutrina, palavra por palavra, porque
// é ele que define o que o número significa — reescrever "com minhas palavras"
// aqui abriria espaço para a tela dizer uma coisa e a doutrina outra.
const NIVEL: Record<string, { titulo: string; o_que_faz: string }> = {
  N0: { titulo: "Sombra", o_que_faz: "roda e registra a saída, mas NÃO influencia decisão" },
  N1: { titulo: "Sugestão + revisão 100%", o_que_faz: "a saída é sugestão; humano confirma todo item" },
  N2: { titulo: "Auto-clear + resto p/ humano", o_que_faz: "acima do limiar é autônomo; abaixo vai para humano" },
  N3: { titulo: "Autônomo + auditoria por amostragem", o_que_faz: "roda sozinho; humano audita amostra" },
};

const NOME_ESTAGIO: Record<string, string> = {
  classificacao_doc_checklist: "Classificação documento → checklist",
  validacao_formal: "Validação formal do arquivo",
  completude_portao1: "Completude (Portão 1)",
  extracao_identificadores: "Extração de identificadores (tipo/período/entidade)",
  extracao_linhas_financeiras: "Extração de linhas/tabelas financeiras",
  reconciliacao_classe_a: "Reconciliação Classe A (aritmética)",
  reconciliacao_classe_bc: "Reconciliação Classe B/C (semi/interpretativa)",
  classificacao_contabil: "Classificação contábil (recorrente/EBITDA)",
};

function dataHora(iso: string | null) {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

export default async function QualidadeDaAutomacaoPage() {
  const supabase = await createClient();

  const [{ data: dials, error: erroDial }, { data: eventos }, { data: rodadas }] =
    await Promise.all([
      supabase
        .from("estagio_autonomia")
        .select(
          "estagio, nivel_atual, teto, limiar_auto_clear, natureza, base_do_nivel, auto_promocao, " +
            "medicao_rodada_id, medicao_em, atualizado_por, atualizado_em",
        )
        .order("estagio"),
      supabase
        .from("evento_auditoria")
        .select("ator, acao, entidade_ref, depois, criado_em")
        // `mudanca_dial_sem_medicao` (0126) entra na lista: é o registro de uma
        // subida que o dono assumiu sem medir. Fora dela, ele não apareceria em
        // tela nenhuma — e é o evento que mais precisa ser visto.
        .in("acao", ["mudanca_dial", "mudanca_dial_recusada", "mudanca_dial_sem_medicao"])
        .order("criado_em", { ascending: false })
        .limit(15),
      // Catálogo pequeno e que não cresce com a mesa (uma linha por rodada de
      // calibração), então não pagina — mesma regra das outras listas de catálogo.
      supabase
        .from("golden_rodada")
        .select("id, nome, taxonomia_versao, congelada_em, criada_em")
        .order("criada_em", { ascending: false })
        .limit(10),
    ]);

  const linhas = (dials as Dial[] | null) ?? [];
  const trilha = (eventos as EventoDial[] | null) ?? [];
  const listaRodadas = (rodadas as Rodada[] | null) ?? [];

  // A cobertura é mostrada da rodada CONGELADA mais recente, que é a única que
  // pode autorizar uma subida (0126). Rodada em montagem não decide nada, e
  // mostrar a cobertura dela sugeriria que decide.
  const rodadaVigente = listaRodadas.find((r) => r.congelada_em !== null) ?? null;
  const { data: coberturaBruta } = rodadaVigente
    ? await supabase.rpc("fn_golden_cobertura", { p_rodada: rodadaVigente.id })
    : { data: null };
  const cobertura = (coberturaBruta as Cobertura[] | null) ?? [];

  // A CONCORDÂNCIA DA CLASSIFICAÇÃO CONTÁBIL (0128), e ela mora AQUI por um motivo:
  // é o único estágio do sistema cuja concordância humano-máquina já pode ser
  // medida sem golden set nenhum. O rótulo vem do override que o analista registra
  // na página do documento — o mesmo desenho que a 0126 achou na Classe A, onde o
  // rótulo é o veredito da 0106.
  //
  // Fica ao lado do dial porque é ele que este número governa: o Arquitetura do Sistema/2 Especificação/05 diz que
  // "onde humanos discordam sistematicamente da máquina, ajusta-se regra/threshold
  // (ou não se sobe o dial daquele estágio)".
  const { data: ccBruto } = await supabase.rpc("fn_classe_contabil_concordancia", {
    p_caso_id: null,
  });
  const cc = ccBruto as ConcordanciaCC | null;

  const declarados = linhas.filter((d) => d.base_do_nivel === "declarada");
  const autonomas = linhas.filter(
    (d) => (d.nivel_atual === "N2" || d.nivel_atual === "N3") && d.limiar_auto_clear !== null,
  ).length;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-lg font-semibold text-tinta-900">Qualidade da automação</h1>
        <p className="mt-1 text-sm text-tinta-500">
          Em que etapas o sistema já decide sozinho e em quais uma pessoa ainda revisa tudo.
          Esta tela só mostra: mudar o nível é ação do administrador do sistema.
        </p>
        {/* O RESUMO É CONTA DOS DADOS QUE A PÁGINA JÁ LEU, nunca número inventado.
            "Decide sozinho" = nível N2/N3 COM limiar de auto-aceite: estágio em N2
            sem limiar não auto-aceita nada (ver a coluna do limiar), então contá-lo
            seria afirmar autonomia que não existe. Sem a leitura (erro ou zero
            linhas), a frase NÃO leva número: ausência não vira "0 de 0". */}
        {erroDial || linhas.length === 0 ? (
          <p className="mt-2 text-sm font-medium text-alerta-900">
            Não foi possível ler o nível de automação das etapas agora, então esta tela não afirma
            quantas decidem sozinhas.
          </p>
        ) : (
          <p className="mt-2 text-sm font-medium text-tinta-900">
            Em {autonomas} de {linhas.length} {linhas.length === 1 ? "etapa" : "etapas"} o sistema
            decide sozinho o que tem alta confiança; nas outras, uma pessoa revisa tudo.
            {declarados.length > 0 && (
              <span className="font-normal text-alerta-900">
                {" "}Em {declarados.length}, esse nível é
                decisão de produto, ainda sem concordância medida (abaixo).
              </span>
            )}
          </p>
        )}
        <DetalhesTecnicos prosa>
          <p>
            Mudar o nível é feito por fn_mudar_dial, que grava autor e motivo. A doutrina está em
            Arquitetura do Sistema/1 Visão e Doutrina/01 (níveis N0 a N3, teto por natureza do
            estágio) e em Arquitetura do Sistema/2 Especificação/f0/06 (golden set) e /05
            (classificação contábil).
          </p>
        </DetalhesTecnicos>
      </div>

      {erroDial && (
        <div className="rounded border border-risco-300 bg-risco-50 p-3 text-sm text-risco-700">
          <p>Não foi possível ler os níveis de automação. Avise o administrador do sistema.</p>
          <DetalhesTecnicos>
            <p>{erroDial.message}</p>
          </DetalhesTecnicos>
        </div>
      )}

      <div className="overflow-x-auto rounded border border-tinta-200 bg-folha">
        <table className="w-full text-sm">
          <thead className="bg-tinta-50 text-left text-xs uppercase text-tinta-500">
            <tr>
              <th className="px-4 py-2 font-medium">Estágio</th>
              <th className="px-4 py-2 font-medium">Hoje</th>
              <th className="px-4 py-2 font-medium">Teto</th>
              <th className="px-4 py-2 font-medium">Limiar de auto-clear</th>
              <th className="px-4 py-2 font-medium">Apoia-se em</th>
              <th className="px-4 py-2 font-medium">Última mudança</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-tinta-200">
            {linhas.map((d) => {
              const noTeto = d.nivel_atual === d.teto;
              // Teto N1 é o caso que Arquitetura do Sistema/1 Visão e Doutrina/01 marca com "nunca autônomo": não é um
              // limite provisório à espera de medição, é decisão de doutrina.
              const nuncaAutonomo = d.teto === "N1";
              return (
                <tr key={d.estagio} className="align-top">
                  <td className="px-4 py-3">
                    <p className="font-medium" title={d.estagio}>{NOME_ESTAGIO[d.estagio] ?? d.estagio}</p>
                  </td>
                  <td className="px-4 py-3">
                    <span className="rounded bg-tinta-900 px-1.5 py-0.5 text-xs font-semibold text-papel">
                      {d.nivel_atual}
                    </span>
                    <p className="mt-1 text-xs text-tinta-600">
                      {NIVEL[d.nivel_atual]?.titulo}
                    </p>
                    <p className="text-xs text-tinta-500">{NIVEL[d.nivel_atual]?.o_que_faz}</p>
                  </td>
                  <td className="px-4 py-3 text-xs text-tinta-600">
                    {d.teto}
                    {noTeto && <span className="ml-1 text-tinta-400">(no teto)</span>}
                    {nuncaAutonomo && (
                      <p className="mt-1 text-tinta-500">
                        Por decisão de doutrina, nunca autônomo — o teto é por natureza da etapa e nada
                        o sobrepõe.
                      </p>
                    )}
                  </td>
                  <td className="px-4 py-3 text-xs text-tinta-600">
                    {d.limiar_auto_clear === null ? (
                      <span className="text-tinta-500">
                        sem limiar — não auto-aceita, qualquer que seja o nível
                      </span>
                    ) : (
                      <>
                        {d.limiar_auto_clear}
                        {d.nivel_atual === "N0" || d.nivel_atual === "N1" ? (
                          <p className="mt-1 text-tinta-500">
                            sem efeito em {d.nivel_atual}: só N2/N3 auto-aceitam.
                          </p>
                        ) : null}
                      </>
                    )}
                  </td>
                  {/* 0126: o que a tela adivinhava por prefixo do nome agora é
                      coluna. 0136: três estados de medição em vez de dois, e a
                      cor separa o rótulo cego do enviesado. Verde é golden set;
                      azul é veredito de produção, que mede um piso. */}
                  <td className="px-4 py-3 text-xs">
                    {d.base_do_nivel === "medida" ? (
                      <>
                        <span className="rounded bg-ok-100 px-1.5 py-0.5 font-medium text-ok-800">
                          concordância medida
                        </span>
                        <p className="mt-1 text-tinta-500">
                          contra golden set em {dataHora(d.medicao_em)}
                        </p>
                      </>
                    ) : d.base_do_nivel === "medida_por_veredito" ? (
                      <>
                        <span className="rounded bg-info-100 px-1.5 py-0.5 font-medium text-info-900">
                          medida por veredito
                        </span>
                        <p className="mt-1 text-tinta-500">
                          piso, não ground truth: quem julgou viu o palpite da máquina
                          {d.medicao_em ? ` (${dataHora(d.medicao_em)})` : ""}
                        </p>
                      </>
                    ) : d.base_do_nivel === "declarada" ? (
                      <>
                        <span className="rounded bg-alerta-100 px-1.5 py-0.5 font-medium text-alerta-900">
                          decisão declarada
                        </span>
                        <p className="mt-1 text-tinta-500">
                          auto-clear ligado sem concordância medida
                        </p>
                      </>
                    ) : (
                      <span className="text-tinta-500">
                        {d.natureza === "deterministico"
                          ? "determinístico: a garantia é teste, não concordância"
                          : "não se aplica — abaixo do auto-clear"}
                      </span>
                    )}
                    {/* 0137: o freio precisa ser VISÍVEL. Um estágio com a
                        promoção automática desligada e ninguém sabendo é o
                        mesmo que um estágio que parou de subir sem motivo. */}
                    {d.natureza === "interpretativo" && !d.auto_promocao && (
                      <p className="mt-1 text-alerta-800">
                        promoção automática desligada por uma descida manual
                      </p>
                    )}
                  </td>
                  <td className="px-4 py-3 text-xs text-tinta-600">
                    <p>{dataHora(d.atualizado_em)}</p>
                    <p className="text-tinta-500">{d.atualizado_por ?? "—"}</p>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* A RESSALVA QUE VIAJA COM O NÚMERO. Sem isto, alguém lê "N2" na extração e
          conclui que houve medição de concordância contra golden set.

          0126: a condição saiu de `estagio.startsWith("extracao")` — heurística de
          NOME — para `base_do_nivel === "declarada"`, que é o fato. E o bloco passa
          a NOMEAR os estágios: antes ele dizia "os estágios de extração" mesmo
          quando só um estava assim, e ficaria calado sobre um estágio de outro
          nome que subisse sem medir. */}
      {declarados.length > 0 && (
        <div className="rounded border border-alerta-300 bg-alerta-50 p-3 text-sm text-alerta-900">
          <p className="font-medium">
            Autonomia declarada, não medida — {declarados.length}{" "}
            {declarados.length === 1 ? "estágio" : "estágios"}
          </p>
          <ul className="mt-1 list-disc pl-5">
            {declarados.map((d) => (
              <li key={d.estagio}>
                <strong>{NOME_ESTAGIO[d.estagio] ?? d.estagio}</strong> em {d.nivel_atual}
              </li>
            ))}
          </ul>
          <p className="mt-1">
            Estão nesse nível por decisão de produto, não por concordância medida. Quando houver
            base de comparação, a medição confirma ou derruba estes níveis. Subir sem medir exige
            um motivo assumido por escrito, que aparece na trilha abaixo como{" "}
            <em>sem medição</em>.
          </p>
          <DetalhesTecnicos prosa>
          <p>
            Estão nesse nível por decisão de produto, não por concordância medida:{" "}
            <code>Arquitetura do Sistema/1 Visão e Doutrina/01</code> exige comparação contra um golden set para subir dial de estágio
            interpretativo. Desde a <code>0126</code> subir sem isso continua possível, mas exige
            um motivo assumido por escrito — e é ele que aparece na trilha abaixo como{" "}
            <em>sem medição</em>. Quando houver golden set, a medição confirma ou derruba estes
            níveis.
          </p>
          <p>
            Desde a <code>0137</code> essa subida acontece <strong>sozinha</strong>: alcançado o
            critério, o estágio vai a N2 no instante em que a nota que o completou é registrada,
            com ator <code>sistema:auto_dial</code> na trilha e a medição que autorizou anexada. Ela
            para em N2 e nunca chega a N3, porque piso enviesado não sustenta autonomia plena. E se
            alguém <strong>baixar</strong> o nível de um estágio à mão, a automação dele é desligada
            na hora e só volta por decisão explícita: o freio não pode ser desfeito pela máquina no
            veredito seguinte.
          </p>
          <p>
            Desde a <code>0136</code> existe um terceiro caminho, e ele não depende de rotulagem:
            o veredito que o trabalho normal já produz. Cada vez que alguém confirma ou corrige o
            tipo de um documento na revisão, isso é um rótulo. O dial aceita esse número como base
            (<code>fn_mudar_dial</code> com <code>p_por_veredito</code>), e o nível resultante fica
            marcado como <strong>medida por veredito</strong>, nunca como medida. A diferença não é
            formalidade: quem julga na revisão vê o palpite da máquina antes de decidir, então o
            viés de confirmação empurra o número para cima e o que se mede é um piso.
          </p>
          <p>
            A medição que já é possível hoje roda contra o book sintético (
            <code>portal/scripts/medir-auto-aceite.mts</code>) e vale como piso, não como
            equivalente: o book é o melhor caso — PDF gerado, texto limpo, layout conhecido. Por
            isso rodada de golden set com <code>origem = sintetico</code> não autoriza subida.
          </p>
          </DetalhesTecnicos>
        </div>
      )}

      {/* O GOLDEN SET, e o que falta para ele destravar uma subida. Sem este bloco,
          "o golden set ainda não existe" é uma frase que ninguém consegue conferir
          — e continuaria sendo verdade no texto muito depois de deixar de ser. */}
      <div>
        <h2 className="text-sm font-semibold">Conjunto de referência (golden set)</h2>
        <p className="mt-1 text-xs text-tinta-500">
          Cerca de {cobertura[0]?.n_minimo ?? 20} documentos rotulados por tipo principal,
          estratificados por qualidade de captura. Só rodada <strong>congelada</strong> e de{" "}
          <strong>origem real</strong> autoriza subir dial — rotular um book cujo gabarito já se
          conhece mede o instrumento, não o modelo.
        </p>

        {/* NÃO HÁ PORTA DE ENTRADA DE ROTULAGEM AQUI, e a ausência é decisão, não
            lacuna. A casa optou por NÃO manter um fluxo de rotulagem manual: o
            objetivo é o sistema rodar sem triagem humana, e uma tela que convida a
            uma tarde de mesa por rodada orienta o oposto disso. O caminho de escrita
            existe no banco (`0130`) e continua chamável — o que saiu foi o convite.

            O que isto significa para o dial, dito sem rodeio: enquanto não houver
            concordância medida por ALGUMA fonte, os estágios interpretativos ficam
            onde estão. É o que a regra de ouro determina, e é o comportamento
            correto — não um item pendente de configuração. */}
        <p className="mt-2 rounded border border-tinta-200 bg-tinta-50 px-3 py-2 text-xs text-tinta-600">
          <strong>Não existe fluxo de rotulagem manual neste portal, por decisão.</strong> O
          objetivo é o sistema operar sem triagem humana, e uma tela que pede uma tarde de
          mesa por rodada orienta o contrário. Consequência assumida: sem concordância
          medida, os estágios interpretativos <strong>não sobem</strong> — a regra de ouro
          recusa, e recusar é o comportamento certo.
        </p>

        {listaRodadas.length === 0 ? (
          <div className="mt-2 text-sm text-tinta-500">
            <p>
              Nenhuma rodada de calibração registrada. O que falta é a rotulagem em si, que é
              trabalho de mesa sobre documento real de cliente.
            </p>
            <DetalhesTecnicos prosa>
              <p>
                O protocolo está fechado como v1 desde 14/07/2026, o esquema existe desde a
                migration 0126 e a 0130 abriu o caminho de escrita.
              </p>
            </DetalhesTecnicos>
          </div>
        ) : (
          <ul className="mt-2 divide-y divide-tinta-200 rounded border border-tinta-200 bg-folha text-sm">
            {listaRodadas.map((r) => (
              <li key={r.id} className="flex flex-wrap items-baseline gap-2 px-4 py-2">
                <span className="font-medium">{r.nome}</span>
                <span
                  className={
                    r.congelada_em
                      ? "rounded bg-tinta-900 px-1.5 py-0.5 text-xs font-medium text-papel"
                      : "rounded bg-alerta-100 px-1.5 py-0.5 text-xs font-medium text-alerta-900"
                  }
                >
                  {r.congelada_em ? "congelada" : "em montagem"}
                </span>
                <span className="text-xs text-tinta-500">
                  taxonomia v{r.taxonomia_versao} · criada {dataHora(r.criada_em)}
                  {r.congelada_em ? ` · congelada ${dataHora(r.congelada_em)}` : ""}
                </span>
              </li>
            ))}
          </ul>
        )}

        {rodadaVigente && cobertura.length > 0 && (
          <div className="mt-3 overflow-x-auto rounded border border-tinta-200 bg-folha">
            <table className="w-full text-sm">
              <caption className="px-4 pt-2 text-left text-xs text-tinta-500">
                Cobertura de <strong>{rodadaVigente.nome}</strong>, por tipo do Kit Básico. O tipo
                mais fraco governa: o nível é por etapa e a doutrina raciocina por tipo, então um
                tipo fraco segura a autonomia dos demais.
              </caption>
              <thead className="bg-tinta-50 text-left text-xs uppercase text-tinta-500">
                <tr>
                  <th className="px-4 py-2 font-medium">Tipo</th>
                  <th className="px-4 py-2 font-medium">Rotulados</th>
                  <th className="px-4 py-2 font-medium">Com 2 rotuladores</th>
                  <th className="px-4 py-2 font-medium">Estratos</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-tinta-200">
                {cobertura.map((c) => (
                  <tr key={c.tipo}>
                    <td className="px-4 py-2">
                      <p className="text-xs font-medium" title={c.tipo}>{formatarTipoTaxonomia(c.tipo)}</p>
                      {/* A granularidade explica a demora em vez de deixá-la
                          parecer negligência: tipo por CASO rende ~1 por mandato,
                          e a doutrina diz que ficar mais tempo em N0/N1 é esperado. */}
                      {(c.granularidade === "caso" || c.granularidade === "periodo") && (
                        <p className="text-xs text-tinta-500">
                          ~1 por mandato: juntar {c.n_minimo} demora, e é esperado
                        </p>
                      )}
                    </td>
                    <td className="px-4 py-2 text-xs">
                      <span className={c.atinge_minimo ? "text-ok-700" : "text-alerta-800"}>
                        {c.n_documentos} de {c.n_minimo}
                      </span>
                    </td>
                    <td className="px-4 py-2 text-xs text-tinta-600">{c.n_dois_rotuladores}</td>
                    <td className="px-4 py-2 text-xs text-tinta-600">
                      {c.estratos.length === 0 ? (
                        <span className="text-tinta-400">—</span>
                      ) : (
                        c.estratos.join(", ")
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* A CONCORDÂNCIA QUE JÁ EXISTE HOJE, sem golden set. Este bloco é a resposta
          à pergunta que o dial faz e que, para os outros estágios, ainda não tem
          resposta nenhuma. */}
      {cc && (
        <div>
          <h2 className="text-sm font-semibold">Concordância na classificação contábil</h2>
          <p className="mt-1 text-xs text-tinta-500">
            O único estágio cuja concordância humano-máquina já dá para medir sem golden set: o
            rótulo é o <strong>override</strong> que o analista registra na linha, e cada
            discordância é um ponto de calibração. Onde humanos discordam
            sistematicamente, ajusta-se a <strong>regra</strong> — não se sobe o nível.
          </p>

          {cc.com_veredito_humano === 0 ? (
            <p className="mt-2 text-sm text-tinta-500">
              Nenhuma linha classificada por humano ainda. A regra já sugere; a concordância
              começa a existir quando alguém confirmar ou derrubar a primeira sugestão, na página
              de um documento.
              {cc.sem_veredito_humano > 0 && (
                <>
                  {" "}
                  Há <strong>{cc.sem_veredito_humano}</strong> sugestões esperando veredito.
                </>
              )}
            </p>
          ) : (
            <>
              <div className="mt-2 grid gap-3 sm:grid-cols-3">
                <div className="rounded border border-tinta-200 bg-folha p-3">
                  <p className="text-lg font-semibold">
                    {cc.concordancia == null
                      ? "—"
                      : `${(cc.concordancia * 100).toFixed(1)}%`}
                  </p>
                  <p className="text-xs text-tinta-500">
                    concordância — {cc.concordaram} de {cc.com_veredito_humano} com veredito
                  </p>
                </div>
                <div className="rounded border border-tinta-200 bg-folha p-3">
                  <p className="text-lg font-semibold">
                    {cc.com_veredito_humano - cc.concordaram}
                  </p>
                  <p className="text-xs text-tinta-500">
                    discordâncias — é este o dado de calibração
                  </p>
                </div>
                <div className="rounded border border-tinta-200 bg-folha p-3">
                  <p className="text-lg font-semibold">{cc.sem_veredito_humano}</p>
                  <p className="text-xs text-tinta-500">
                    sem veredito — ficam FORA da conta: &quot;acertou&quot; e &quot;ninguém
                    conferiu&quot; são estados diferentes
                  </p>
                </div>
              </div>

              {cc.rubricas_que_mais_erram.length > 0 && (
                <div className="mt-3 overflow-x-auto rounded border border-tinta-200 bg-folha">
                  <table className="w-full text-sm">
                    <caption className="px-4 pt-2 text-left text-xs text-tinta-500">
                      As rubricas em que a regra mais erra. É por aqui que se ajusta o catálogo —
                      corrigir a <strong>regra</strong> é mais barato e mais auditável que
                      reclassificar linha a linha para sempre.
                    </caption>
                    <thead className="bg-tinta-50 text-left text-xs uppercase text-tinta-500">
                      <tr>
                        <th className="px-4 py-2 font-medium">Padrão do catálogo</th>
                        <th className="px-4 py-2 font-medium">A regra sugeria</th>
                        <th className="px-4 py-2 font-medium">Vezes que o humano discordou</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-tinta-200">
                      {cc.rubricas_que_mais_erram.map((r) => (
                        <tr key={r.padrao}>
                          <td className="px-4 py-2 font-mono text-xs">{r.padrao}</td>
                          <td className="px-4 py-2 text-xs text-tinta-600">{r.sugeria}</td>
                          <td className="px-4 py-2 text-xs">{r.erros}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </>
          )}
        </div>
      )}

      <div>
        <h2 className="text-sm font-semibold">Mudanças de dial</h2>
        <p className="mt-1 text-xs text-tinta-500">
          Toda mudança de nível é decisão registrada e reversível. Tentativa recusada
          também fica — passar do teto é justamente o que a trilha precisa guardar.
        </p>
        {trilha.length === 0 ? (
          <p className="mt-2 text-sm text-tinta-500">Nenhuma mudança de dial registrada.</p>
        ) : (
          <ul className="mt-2 divide-y divide-tinta-200 rounded border border-tinta-200 bg-folha text-sm">
            {trilha.map((e, i) => (
              <li key={i} className="px-4 py-2">
                <div className="flex flex-wrap items-baseline gap-2">
                  <span
                    className={
                      e.acao === "mudanca_dial_recusada"
                        ? "rounded bg-risco-100 px-1.5 py-0.5 text-xs font-medium text-risco-800"
                        : e.acao === "mudanca_dial_sem_medicao"
                          ? "rounded bg-alerta-100 px-1.5 py-0.5 text-xs font-medium text-alerta-900"
                          : "rounded bg-tinta-100 px-1.5 py-0.5 text-xs font-medium text-tinta-600"
                    }
                  >
                    {e.acao === "mudanca_dial_recusada"
                      ? "recusada"
                      : e.acao === "mudanca_dial_sem_medicao"
                        ? "sem medição"
                        : "aplicada"}
                  </span>
                  <span className="text-xs font-medium" title={e.entidade_ref}>{NOME_ESTAGIO[e.entidade_ref] ?? e.entidade_ref}</span>
                  <span className="text-xs text-tinta-500">
                    {e.ator} · {dataHora(e.criado_em)}
                  </span>
                </div>
                {e.acao === "mudanca_dial_recusada" ? (
                  <p className="mt-1 text-xs text-tinta-600">
                    pediu {e.depois?.pedido} com teto {e.depois?.teto}
                    {e.depois?.motivo_informado ? ` — "${e.depois.motivo_informado}"` : ""}
                  </p>
                ) : (
                  <>
                    {e.depois?.motivo && (
                      <p className="mt-1 text-xs text-tinta-600">{e.depois.motivo}</p>
                    )}
                    {/* O motivo assumido é o que separa "subiu porque mediu" de
                        "subiu porque decidiu", e é o texto que alguém escreveu
                        sabendo que não mediu. Esconder isto devolveria a
                        indistinguibilidade que a 0126 acabou de tirar. */}
                    {e.depois?.sem_medicao_porque && (
                      <p className="mt-1 text-xs text-alerta-900">
                        sem medição: {e.depois.sem_medicao_porque}
                      </p>
                    )}
                  </>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
