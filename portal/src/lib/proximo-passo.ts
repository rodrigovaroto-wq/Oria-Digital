// O "PRÓXIMO PASSO" DA VISÃO GERAL: uma frase e um destino, decididos pelos dados
// que a tela já leu — sem consulta própria.
//
// POR QUE EXISTE. A visão geral empilhava sete seções e quem abria o mandato tinha
// de somar de cabeça o que fazer primeiro. Agora a resposta é uma.
//
// CADA ENTRADA É `number | boolean | null`, E `null` É "A LEITURA FALHOU" (regra 1).
// Sem isso, uma consulta que não respondeu viraria "0 pendências" e o banner diria
// "aprove o mandato" sobre um caso que talvez esteja travado. As entradas são
// avaliadas NA ORDEM DE PRIORIDADE e a primeira que dispara decide: uma leitura
// falha SÓ impede a resposta se ela é anterior ao passo que decidiria — se já se
// sabe que há bloqueante, o que a leitura do kit diria é irrelevante.
//
//   1. pendência aberta que TRAVA a aprovação   → /pendencias
//   2. documento esperando confirmação          → /pendencias?filtro=confirmar
//   3. Kit Básico incompleto, enquanto o portão
//      ainda não aceita o mandato               → /perguntas (pedir ao cliente)
//   4. ainda não aprovado, e pode ser           → âncora do cartão de aprovação
//      ainda não aprovado, e não pode           → idem, o cartão lista o que falta
//   5. aprovado, modelo ainda não montado       → /modelagem
//   6. aprovado, modelo montado                 → /entregaveis
export interface EntradaProximoPasso {
  /** pendências abertas com severidade bloqueante */
  bloqueantesAbertas: number | null;
  /** pendências abertas de classificação/entidade/período à espera de confirmação */
  revisoesAbertas: number | null;
  /** itens do Kit Básico que não chegaram ou chegaram sem dado */
  kitFaltantes: number | null;
  /** `fn_avaliar_portao2.elegivel` (null = a avaliação não respondeu) */
  aprovavel: boolean | null;
  /** o mandato já foi aprovado (status aprovado ou pronto para a base) */
  aprovado: boolean;
  /** `caso_modelagem` tem entidade, último exercício real e anos projetados (null = leitura falhou) */
  modeloMontado: boolean | null;
}

export type PassoId =
  | "decidir" | "confirmar" | "pedir" | "aprovar" | "ver_aprovacao"
  | "modelar" | "entregaveis" | "indeterminado";

export interface ProximoPasso {
  passo: PassoId;
  titulo: string;
  /** o que o passo faz, em uma frase */
  detalhe: string;
  /** o que o botão diz; null quando não há para onde ir (indeterminado) */
  acao: string | null;
  /** depois de `/casos/{id}`; "#aprovacao" é a âncora do cartão da própria visão geral */
  href: string | null;
}

const plural = (n: number, um: string, varios: string) => `${n} ${n === 1 ? um : varios}`;

export function proximoPasso(e: EntradaProximoPasso): ProximoPasso {
  const naoDa = (o_que: string): ProximoPasso => ({
    passo: "indeterminado",
    titulo: "Não dá para determinar o próximo passo",
    detalhe: `A leitura de ${o_que} não respondeu, e dizer "aprove" ou "está tudo certo" sem saber seria chute. Recarregue a página; se persistir, avise o administrador.`,
    acao: null,
    href: null,
  });

  if (e.bloqueantesAbertas === null) return naoDa("pendências do mandato");
  if (e.bloqueantesAbertas > 0) {
    return {
      passo: "decidir",
      titulo: `Decidir ${plural(e.bloqueantesAbertas, "pendência que trava", "pendências que travam")} a aprovação`,
      detalhe: "Enquanto houver pendência bloqueante sem decisão, o mandato não pode ser aprovado.",
      acao: "Ver pendências",
      href: "/pendencias",
    };
  }

  if (e.revisoesAbertas === null) return naoDa("documentos à espera de confirmação");
  if (e.revisoesAbertas > 0) {
    return {
      passo: "confirmar",
      titulo: `Confirmar ${plural(e.revisoesAbertas, "documento", "documentos")}`,
      detalhe: "O sistema não teve certeza do tipo, da empresa ou do período; nada entra na base sem a sua confirmação.",
      acao: "Confirmar agora",
      href: "/pendencias?filtro=confirmar",
    };
  }

  // KIT SÓ MANDA PEDIR ANTES DA APROVAÇÃO SER POSSÍVEL. Um item faltante pode ter sido
  // decidido ("prosseguir sem resolução", "não procede" — o cliente não tem a DVA): o
  // portão aceita, `kitFaltantes` nunca zera, e com o kit antes de tudo o banner ficava
  // preso em "pedir" para sempre, inclusive depois de aprovado (revisão do PR #265).
  // Aprovado, ou aprovável, o portão já disse que o kit como está basta.
  const kitAindaDecide = !e.aprovado && e.aprovavel !== true;
  if (kitAindaDecide && e.kitFaltantes === null) return naoDa("itens do Kit Básico");
  if (kitAindaDecide && e.kitFaltantes !== null && e.kitFaltantes > 0) {
    return {
      passo: "pedir",
      titulo: `Pedir ${plural(e.kitFaltantes, "documento", "documentos")} ao cliente`,
      detalhe: "Itens obrigatórios do Kit Básico que ainda não chegaram, ou chegaram sem nenhum dado aproveitável.",
      acao: "Ver perguntas ao cliente",
      href: "/perguntas",
    };
  }

  if (!e.aprovado) {
    if (e.aprovavel === null) return naoDa("a aprovação do mandato");
    if (e.aprovavel) {
      return {
        passo: "aprovar",
        titulo: "Aprovar o mandato",
        detalhe: "Nenhuma pendência trava e o Kit Básico está completo. A aprovação libera o modelo e a apresentação.",
        acao: "Ir para a aprovação",
        href: "#aprovacao",
      };
    }
    // Não há bloqueante, revisão nem item faltante, e mesmo assim o portão está fechado:
    // o motivo é outro, e é o cartão de aprovação quem o lista. Não se inventa um passo.
    return {
      passo: "ver_aprovacao",
      titulo: "Ver o que falta para a aprovação",
      detalhe: "O mandato ainda não pode ser aprovado; o cartão de aprovação lista os motivos.",
      acao: "Ver motivos",
      href: "#aprovacao",
    };
  }

  if (e.modeloMontado === null) return naoDa("a configuração do modelo");
  if (!e.modeloMontado) {
    return {
      passo: "modelar",
      titulo: "Montar o modelo",
      detalhe: "Mandato aprovado. Falta definir a entidade modelada, o último exercício real e os anos projetados.",
      acao: "Ir para a Modelagem",
      href: "/modelagem",
    };
  }
  return {
    passo: "entregaveis",
    titulo: "Baixar os arquivos do mandato",
    detalhe: "Mandato aprovado e modelo montado: a base, o modelo e a apresentação estão na aba Entregáveis.",
    acao: "Ir para Entregáveis",
    href: "/entregaveis",
  };
}
