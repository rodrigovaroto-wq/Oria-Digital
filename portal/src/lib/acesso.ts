// O QUE CADA PAPEL PODE FAZER NA TELA — e a frase para quando o banco disser que não.
//
// O BANCO É A AUTORIDADE (migration 0216: `membro`, `alocacao`, as policies por mandato e os
// gatilhos que reservam aprovar/fechar/reabrir/excluir/dial ao Sócio). Este arquivo NÃO decide
// acesso: ele só evita o clique inútil — esconde, ou desabilita com o motivo à vista, o que o
// banco recusaria — e traduz a recusa que ainda chegar. Uma regra aqui que divergisse do banco
// seria só uma interface sugerindo uma separação que o banco não garante (PRODUCT.md, "RLS por
// caso"), que foi o motivo de a tela de equipe esperar a 0216.
//
// A PERGUNTA É FEITA UMA VEZ POR REQUISIÇÃO, no servidor (`lib/supabase/acesso.ts`), e as telas
// recebem a resposta: nenhum componente consulta o papel por conta própria.
//
// "NÃO SEI" ≠ "NÃO PODE" ≠ "NÃO TEM PAPEL" (regra 1). São três estados e a tela os trata diferente:
//   - o banco respondeu um papel      -> a tela aplica `permissoes`;
//   - o banco respondeu "sem papel"   -> NADA vale (a 0216 nega tudo, inclusive o catálogo), e a
//     tela diz isso em vez de mostrar listas vazias que se leriam como "nenhum mandato";
//   - a pergunta FALHOU (rede, função ausente) -> `conferido: false`: a tela não esconde nada (o
//     banco recusa o que for recusar) e DIZ que não conseguiu conferir. Esconder tudo por causa de
//     uma falha de leitura trancaria o Sócio fora do próprio portal por um soluço de rede.

export type Papel = "socio" | "analista" | "leitura";

export const PAPEIS: readonly Papel[] = ["socio", "analista", "leitura"];

export const ROTULO_DO_PAPEL: Record<Papel, string> = {
  socio: "Sócio",
  analista: "Analista",
  leitura: "Leitura",
};

/** O que cada papel faz, em uma frase — a tela de equipe a mostra ao lado do seletor. */
export const O_QUE_O_PAPEL_FAZ: Record<Papel, string> = {
  socio: "vê e altera todos os mandatos; aprova, fecha, reabre e exclui mandato; muda o nível de automação; gere a equipe",
  analista: "vê e altera os mandatos em que está alocado; abre mandato novo (e fica alocado nele)",
  leitura: "só consulta os mandatos em que está alocado",
};

export function ehPapel(v: unknown): v is Papel {
  return v === "socio" || v === "analista" || v === "leitura";
}

export type AcessoLido =
  | { estado: "ok"; papel: Papel | null }
  | { estado: "falha"; detalhe: string };

/**
 * A resposta de `fn_meu_papel()` em um dos três estados. `null` é RESPOSTA ("sem papel"); erro ou
 * texto fora do vocabulário é FALHA — um papel novo que o banco passasse a devolver e a tela não
 * conhecesse não pode virar "sem papel" e trancar a pessoa fora.
 */
export function interpretarPapel(res: { data: unknown; error: { message: string } | null }): AcessoLido {
  if (res.error) return { estado: "falha", detalhe: res.error.message };
  if (res.data === null || res.data === undefined) return { estado: "ok", papel: null };
  if (ehPapel(res.data)) return { estado: "ok", papel: res.data };
  return { estado: "falha", detalhe: `o banco devolveu um papel que a tela não conhece: ${JSON.stringify(res.data)}` };
}

export type Liberacao = {
  pode: boolean;
  /** Por que não — escrito para a tela exibir AO LADO do que está desabilitado, nunca em `title=`. */
  motivo: string | null;
};

export type Permissoes = {
  papel: Papel | null;
  /** false = o papel (ou a alocação) não pôde ser lido; nada é escondido e a tela avisa. */
  conferido: boolean;
  semPapel: boolean;
  /** Trabalhar no mandato: arquivos, decisões, modelagem, perguntas, perímetro, campos da apresentação. */
  escrever: Liberacao;
  /** Abrir mandato novo. */
  criarMandato: Liberacao;
  /** Aprovar, fechar, reabrir, excluir mandato, mudar o dial e gerir a equipe. */
  reservadoAoSocio: Liberacao;
};

export const MOTIVO_SEM_PAPEL = "Seu acesso ainda não foi liberado — peça a um Sócio.";

const LIBERADO: Liberacao = { pode: true, motivo: null };
const bloqueado = (motivo: string): Liberacao => ({ pode: false, motivo });

/**
 * `podeEscreverNoMandato`: o que `fn_pode_escrever_caso(caso)` respondeu para ESTE mandato.
 * `undefined` = a tela não está dentro de um mandato (a pergunta não se aplica); `null` = a pergunta
 * falhou. Só o Analista depende dela: o Sócio escreve em todos e a Leitura em nenhum, de modo que a
 * resposta do banco para esses dois é conhecida pelo papel, e conferi-la de novo só repetiria o que
 * `fn_meu_papel` já disse.
 */
export function permissoes(acesso: AcessoLido, podeEscreverNoMandato?: boolean | null): Permissoes {
  if (acesso.estado === "falha") {
    return {
      papel: null, conferido: false, semPapel: false,
      escrever: LIBERADO, criarMandato: LIBERADO, reservadoAoSocio: LIBERADO,
    };
  }
  const { papel } = acesso;
  if (papel === null) {
    return {
      papel, conferido: true, semPapel: true,
      escrever: bloqueado(MOTIVO_SEM_PAPEL), criarMandato: bloqueado(MOTIVO_SEM_PAPEL),
      reservadoAoSocio: bloqueado(MOTIVO_SEM_PAPEL),
    };
  }
  if (papel === "socio") {
    return { papel, conferido: true, semPapel: false, escrever: LIBERADO, criarMandato: LIBERADO, reservadoAoSocio: LIBERADO };
  }
  const reservado = bloqueado(
    `Aprovar, fechar, reabrir e excluir mandato, mudar o nível de automação e gerir a equipe são reservados a Sócio (seu papel: ${ROTULO_DO_PAPEL[papel]}).`,
  );
  if (papel === "leitura") {
    return {
      papel, conferido: true, semPapel: false,
      escrever: bloqueado("Seu papel é Leitura: você consulta este mandato e baixa os arquivos, mas não altera nada nele."),
      criarMandato: bloqueado("Seu papel é Leitura: abrir mandato é de Sócio e Analista."),
      reservadoAoSocio: reservado,
    };
  }
  // Analista
  if (podeEscreverNoMandato === null) {
    // A pergunta do mandato falhou: não se esconde (o banco recusa), mas se diz que não foi conferido.
    return { papel, conferido: false, semPapel: false, escrever: LIBERADO, criarMandato: LIBERADO, reservadoAoSocio: reservado };
  }
  return {
    papel, conferido: true, semPapel: false,
    escrever: podeEscreverNoMandato === false
      ? bloqueado("Você não está alocado neste mandato como Analista: peça a um Sócio para alocar você.")
      : LIBERADO,
    criarMandato: LIBERADO,
    reservadoAoSocio: reservado,
  };
}

/**
 * Quando a lista do papel vem vazia, o que a tela pode dizer SEM mentir. Sócio vê todos os mandatos,
 * então "nenhum" é fato; Analista e Leitura só enxergam os alocados (a RLS devolve VAZIO, não erro,
 * para o resto), então "nenhum" seria uma afirmação sobre a mesa que ninguém mediu.
 */
export function escopoDaLista(papel: Papel | null): "todos" | "alocados" | "indefinido" {
  if (papel === "socio") return "todos";
  if (papel === "analista" || papel === "leitura") return "alocados";
  return "indefinido";
}

// ---------------------------------------------------------------------------
// A RECUSA DO BANCO, em português
// ---------------------------------------------------------------------------

export const MENSAGEM_SEM_PERMISSAO =
  "Seu papel não permite esta ação. Se você deveria poder, peça a um Sócio para conferir seu papel e sua alocação neste mandato.";

type ErroDoBanco = { code?: string | null; message?: string | null } | null | undefined;

/**
 * 42501 é o que o Postgres devolve para as DUAS recusas da 0216: a policy de linha ("new row violates
 * row-level security policy") e `fn_exige_socio` / os gatilhos de reserva ao Sócio, que levantam o
 * mesmo código de propósito. Só o código decide: casar por texto dependeria de a mensagem do banco
 * não mudar, e a Leitura não pode passar a ver o texto cru porque alguém reescreveu uma frase.
 */
export function ehNegacaoDePermissao(erro: ErroDoBanco): boolean {
  return erro?.code === "42501";
}

/**
 * O texto de falha de uma ação. Recusa de permissão vira a frase do papel (sem o prefixo "Falha ao
 * …", que sugeriria defeito); qualquer outro erro continua com o prefixo e a mensagem técnica, como
 * antes — esta função NÃO engole erro, só traduz o que é uma resposta esperada do acesso por papel.
 */
export function textoDeFalhaDaAcao(prefixo: string, erro: NonNullable<ErroDoBanco>): string {
  if (ehNegacaoDePermissao(erro)) return MENSAGEM_SEM_PERMISSAO;
  return `${prefixo}: ${erro.message ?? "erro sem mensagem"}`;
}

/** O índice único `caso_nome_unico` (0216) barrou o nome: ele ignora caixa e espaços nas pontas. */
export const MENSAGEM_NOME_DE_MANDATO_EXISTE =
  "Já existe um mandato com este nome. Abra o mandato existente ou escolha outro nome.";

/**
 * A falha de CRIAR mandato (`fn_upsert_caso`), em português — ou `null` quando ela não é uma das duas
 * respostas esperadas e quem chama segue com o texto que já tinha.
 *
 * Duas recusas distintas chegam aqui, e uma delas usa o MESMO código que a negação por papel:
 *  - 42501 com "Já existe um mandato com este nome ao qual você não tem acesso…": o nome é de um
 *    mandato que a RLS esconde de quem digitou. A frase do banco já diz o remédio (pedir alocação a
 *    um Sócio ou usar outro nome) e é devolvida INTEIRA; trocá-la por "Seu papel não permite esta
 *    ação" mandaria o Analista conferir o papel quando o problema é o nome.
 *  - 42501 de qualquer outro texto (Leitura criando mandato, `fn_caso_nome_ocupado`): a frase do papel.
 *  - 23505 de `caso_nome_unico`: duas abas criaram o mesmo nome no mesmo instante, e o índice barrou a
 *    segunda no INSERT, sem a frase clara da função.
 * Qualquer outro 23505 NÃO é traduzido: seria atribuir ao nome um erro que não é dele.
 */
export function textoDeFalhaDoMandato(
  erro: { code?: string | null; message?: string | null; details?: string | null } | null | undefined,
): string | null {
  if (!erro) return null;
  if (erro.code === "42501") {
    return /^Já existe um mandato com este nome/.test(erro.message ?? "") ? (erro.message as string) : MENSAGEM_SEM_PERMISSAO;
  }
  if (erro.code === "23505" && /caso_nome_unico/.test(`${erro.message ?? ""} ${erro.details ?? ""}`)) {
    return MENSAGEM_NOME_DE_MANDATO_EXISTE;
  }
  return null;
}

/**
 * O texto de "Recentes" quando a barra não tem mandato a mostrar. Três respostas diferentes para três
 * situações que a RLS por mandato torna distintas: a leitura FALHOU (não se sabe), o usuário só vê os
 * alocados (vazio = não está alocado em nenhum aberto) e o Sócio, que vê todos (vazio = não há).
 */
export function textoDeRecentesVazio(papel: Papel | null, leituraFalhou: boolean): string {
  if (leituraFalhou) return "Não foi possível ler os mandatos";
  if (escopoDaLista(papel) === "alocados") return "Nenhum mandato aberto alocado a você";
  return "Nenhum mandato aberto";
}

// ---------------------------------------------------------------------------
// O ENVIO DE ARQUIVOS PELO PORTAL — a única escrita que o banco NÃO guarda
// ---------------------------------------------------------------------------

export const MENSAGEM_SEM_ENVIO = "Seu papel não permite enviar arquivos a este mandato.";

export type DecisaoDeEnvio = { ok: true } | { ok: false; status: 403 | 409 | 503; mensagem: string };

/**
 * Pode esta pessoa mandar arquivos a este mandato (pelo NOME)? É a única escrita que a RLS da 0216 não
 * cobre: `/api/intake` encaminha ao Form do n8n, que grava com a conexão de serviço (BYPASSRLS) e acha
 * o mandato pelo nome — então sem esta checagem a Leitura, ou um Analista não alocado, injetaria
 * documentos em qualquer mandato. FALHA FECHA (503): aqui um "não consegui conferir" que deixasse
 * passar seria exatamente o furo; o custo é pedir para tentar de novo.
 *
 * `achados`: o que a consulta do nome devolveu SOB RLS — `n` mandatos de mesmo nome visíveis e o que
 * `fn_pode_escrever_caso` disse do primeiro (`null` = a pergunta falhou); `null` = a consulta falhou.
 * Sócio não precisa dela (escreve em todos). Mandato que o Analista não enxerga é recusado: a RLS não
 * distingue "não existe" de "existe e é de outra equipe", e o portal sempre cria o mandato ANTES de
 * enviar (passo 1 de Novo mandato), então um nome invisível não é um envio legítimo.
 */
export function decidirEnvioAoMandato(
  acesso: AcessoLido,
  achados: { n: number; podeEscrever: boolean | null } | null,
): DecisaoDeEnvio {
  const recusa = (status: 403 | 409 | 503, mensagem: string): DecisaoDeEnvio => ({ ok: false, status, mensagem });
  if (acesso.estado === "falha") {
    return recusa(503, "Não foi possível conferir o seu papel agora, então nada foi enviado. Tente de novo.");
  }
  if (acesso.papel === null) return recusa(403, MOTIVO_SEM_PAPEL);
  if (acesso.papel === "leitura") return recusa(403, MENSAGEM_SEM_ENVIO);
  if (acesso.papel === "socio") return { ok: true };
  if (achados === null || (achados.n === 1 && achados.podeEscrever === null)) {
    return recusa(503, "Não foi possível conferir a sua alocação neste mandato agora, então nada foi enviado. Tente de novo.");
  }
  if (achados.n > 1) return recusa(409, MENSAGEM_NOME_DUPLICADO);
  if (achados.n === 0 || achados.podeEscrever !== true) return recusa(403, MENSAGEM_SEM_ENVIO);
  return { ok: true };
}

export const MENSAGEM_NOME_DUPLICADO =
  "Há mais de um mandato com este nome, então o portal não sabe a qual deles se refere. Peça a um Sócio para renomear um dos dois.";

/**
 * O que a Administração mostra a cada papel. Custos, concordância da classificação, golden set e a
 * trilha do dial são somas e listas de TODOS os mandatos: quem só vê os alocados receberia números
 * parciais com cara de total (0216, "o que pode quebrar" nº 5). A área inteira é do Sócio.
 */
export function administracaoLiberada(acesso: AcessoLido): boolean {
  // Falha de leitura abre (o banco ainda recorta); só a resposta "não é Sócio" fecha.
  return acesso.estado === "falha" || acesso.papel === "socio";
}
