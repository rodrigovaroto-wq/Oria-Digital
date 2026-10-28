// O veredito de "pronto para exportar" da Modelagem, com a FRAÇÃO de cobertura
// ao lado — nunca escondida atrás do booleano.
//
// O DEFEITO (Supabase/migrations/0158_o_pronto_que_nao_provava_cobertura.sql):
// `fn_conferir_modelagem` respondia `pronto: true` com 23 de 480 linhas
// projetáveis de fato vinculadas a alguma premissa (medido no Grupo
// Vertentes). A 0158 endureceu o BOOLEANO (`pronto` passou a exigir
// `linhas_com_premissa > 0`) e publicou o NÚMERO que faltava,
// `fracao_linhas_com_premissa` — mas um booleano mais duro continua sem
// conseguir dizer "62% das contas projetam" versus "100%": as duas respostas
// pintam o MESMO chip verde. Este arquivo é a metade que faltava: a
// apresentação da fração junto do veredito, em `casos/[id]/modelagem/page.tsx`.
//
// `fracao_linhas_com_premissa` é OPCIONAL de duas formas diferentes, e as duas
// caem no mesmo `null` aqui — nunca em `0` fabricado (regra 1 do CLAUDE.md):
//   • a CHAVE pode não existir — banco sem a 0158 aplicada (o dono aplica
//     migrations à mão; um banco atrasado é estado normal, não defeito);
//   • a 0158 publica o valor `null` quando `linhas_do_caso` é zero — zero
//     coberto de zero possível não é a mesma coisa que zero coberto de 480, e
//     tratar os dois como "0%" seria o mesmo defeito da regra 1 uma casa
//     adiante.
// A mesma convenção de `perguntasSugeridas` em `casos/[id]/page.tsx:277`:
// campo ausente ou de origem incerta vira `null`, e quem lê o `null` mostra o
// que sabe sem inventar o que não sabe.

export interface ConferenciaModelagemCobertura {
  pronto: boolean;
  fracao_linhas_com_premissa?: number | null;
}

/**
 * O PORTÃO 2 TAMBÉM DECIDE O EXPORT DE MODELAGEM, e a tela não sabia disso.
 *
 * Medido em 30/09/2026 no mandato de teste em produção (caso bb37f726): a
 * modelagem dizia "Pronto para o export de modelagem" enquanto
 * `/casos/[id]/export` recusava com 409, porque havia 3 pendências bloqueantes
 * sem decisão. O analista clicava e recebia um JSON cru. `pronto` aqui é a
 * conferência das PREMISSAS (`fn_conferir_modelagem`); a do export é a
 * `fn_avaliar_portao2`, a mesma que a rota usa. Passar o veredito do portão faz
 * a tela dizer o que o clique vai de fato encontrar. Quem não passa o portão
 * (os testes antigos, qualquer outro chamador) mantém o texto de antes.
 */
export interface PortaoDoExport {
  elegivel: boolean;
  motivos?: string[];
}

export function portaoFechado(portao: PortaoDoExport | null | undefined): boolean {
  return !!portao && portao.elegivel === false;
}

/**
 * TRÊS ESTADOS, NUNCA DOIS: aberto, fechado e NÃO CONFERIDO.
 *
 * `null` é "perguntei e a consulta falhou" (o RPC `fn_avaliar_portao2` deu erro);
 * `undefined` é "quem chama não passou o portão" (os testes antigos) e segue no
 * texto de antes. Com só dois estados, `null` caía em "não está fechado" e o topo
 * da tela voltava a dizer "pronto — X% das contas projetam" e habilitava o botão
 * sem ninguém saber se o Portão 2 estava aberto: ausência apresentada como estado
 * (regra 1). `portaoFechado(null)` continua `false` de propósito — não conferido
 * NÃO é fechado, é desconhecido, e quem lê o veredito usa esta função.
 */
export function portaoNaoConferido(portao: PortaoDoExport | null | undefined): boolean {
  return portao === null;
}

export type EstadoDoPortao = "aberto" | "fechado" | "nao_conferido";

/**
 * UMA REGRA SÓ para ler a resposta do RPC `fn_avaliar_portao2`, usada pela PÁGINA e pela
 * ROTA do export. Antes cada uma tinha a sua: a rota recusava (503) quando `elegivel` não
 * era booleano, e a tela só tratava `null` como não conferido — com o RPC respondendo `{}`
 * a tela dizia "pronto", habilitava o botão, e o clique devolvia JSON cru.
 *
 * NÃO CONFERIDO = erro na consulta, resposta ausente, ou resposta sem `elegivel` booleano.
 * Só `elegivel === true` é aberto e só `elegivel === false` é fechado: o que não é nenhum
 * dos dois é desconhecido, e desconhecido nunca é aberto (regra 1).
 */
export function veredictoDoPortao(
  resposta: { data?: unknown; error?: unknown } | null | undefined,
): { estado: EstadoDoPortao; portao: PortaoDoExport | null } {
  const d = resposta?.data;
  if (resposta?.error || d === null || typeof d !== "object"
      || typeof (d as { elegivel?: unknown }).elegivel !== "boolean") {
    return { estado: "nao_conferido", portao: null };
  }
  const { elegivel, motivos } = d as { elegivel: boolean; motivos?: unknown };
  const lista = Array.isArray(motivos) ? motivos.filter((m): m is string => typeof m === "string") : [];
  return { estado: elegivel ? "aberto" : "fechado", portao: { elegivel, motivos: lista } };
}

/** A fração (0 a 1) medida pelo banco, como percentual inteiro — ou `null`
 * quando o banco não a mediu (chave ausente) ou não pôde medi-la
 * (`linhas_do_caso` zero). Nunca `0` por omissão. */
export function fracaoPctDe(conf: ConferenciaModelagemCobertura | null | undefined): number | null {
  return typeof conf?.fracao_linhas_com_premissa === "number"
    ? Math.round(conf.fracao_linhas_com_premissa * 100)
    : null;
}

/** O texto do chip da barra de título. Só o veredito `pronto` ganha a fração:
 * é o caso que o defeito original pintava de verde plano, 23 de 480 incluído. */
export function textoChipModelagem(
  conf: ConferenciaModelagemCobertura, portao?: PortaoDoExport | null,
): string {
  if (!conf.pronto) return "falta algo";
  if (portaoNaoConferido(portao)) return "premissas prontas — aprovação NÃO CONFERIDA, export travado";
  if (portaoFechado(portao)) return "premissas prontas — export bloqueado até a aprovação do mandato";
  const pct = fracaoPctDe(conf);
  return pct !== null ? `pronto — ${pct}% das contas projetam` : "pronto para exportar";
}

/** O título do bloco de conferência (seção 4). O par absoluto
 * (`linhas_com_premissa` de `linhas_do_caso`) continua no item de lista logo
 * abaixo — ele já existia antes da 0158 e não sai daqui, porque porcentagem
 * sozinha esconde a ordem de grandeza (2 de 3 e 400 de 600 são os mesmos
 * 67%). Este título é o mesmo texto de sempre, com a fração ao lado quando o
 * banco a mede. */
export function textoTituloConferenciaModelagem(
  conf: ConferenciaModelagemCobertura, portao?: PortaoDoExport | null,
): string {
  if (!conf.pronto) return "Ainda falta algo para o export de modelagem";
  if (portaoNaoConferido(portao)) {
    return "As premissas estão prontas, mas NÃO foi possível conferir a aprovação (a consulta falhou): "
      + "o export de modelagem fica travado até a conferência responder. Recarregue a página; se "
      + "persistir, o motivo está na faixa de consultas com erro.";
  }
  if (portaoFechado(portao)) {
    return "As premissas estão prontas, mas o export de modelagem está bloqueado até a aprovação do mandato: "
      + `${(portao!.motivos ?? []).join("; ") || "o caso ainda não pode ser aprovado"}. `
      + "Decida as pendências na aba Pendências.";
  }
  const pct = fracaoPctDe(conf);
  return pct !== null
    ? `Pronto para o export de modelagem — ${pct}% das contas projetam`
    : "Pronto para o export de modelagem";
}
