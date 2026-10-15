// A LÓGICA PURA DA TELA DE PERÍMETRO — o que a tela traduz e o que ela lê das respostas do banco.
//
// A REGRA "o que falta para esta entidade estar pronta" mora em `fn_perimetro_situacao` (0208) e NÃO é
// repetida aqui: a tela só traduz o vocabulário de `falta` para frase de analista. Duas implementações
// da mesma conta divergem sem erro nenhum.
//
// REGRA 7 / REGRA 1: chave de `falta` que este arquivo não conhece aparece CRUA, nunca some. Uma
// migration futura que acrescente um motivo novo continua visível na tela, ainda que sem tradução —
// esconder a chave faria a entidade parecer "sem falta" quando o banco diz que falta algo.

export type PapelNoGrupo = "holding" | "operacional" | "veiculo" | "coligada" | "fora_do_perimetro";
export type FormaDeControle = "indefinido" | "controlada_por_entidade" | "controle_comum";

export const PAPEIS: ReadonlyArray<{ valor: PapelNoGrupo; rotulo: string }> = [
  { valor: "holding", rotulo: "Holding" },
  { valor: "operacional", rotulo: "Operacional" },
  { valor: "veiculo", rotulo: "Veículo" },
  { valor: "coligada", rotulo: "Coligada" },
  { valor: "fora_do_perimetro", rotulo: "Fora do perímetro" },
];

export const FORMAS: ReadonlyArray<{ valor: FormaDeControle; rotulo: string }> = [
  { valor: "indefinido", rotulo: "Ainda não definida" },
  { valor: "controlada_por_entidade", rotulo: "Controlada por outra empresa do caso" },
  { valor: "controle_comum", rotulo: "Controle comum (mesmos sócios)" },
];

/** Escopo oferecido por padrão. É texto livre no banco; 'combinado' é o único usado até hoje. */
export const ESCOPO_PADRAO = "combinado";

const FALTAS: Record<string, string> = {
  papel_no_grupo_indefinido: "Falta dizer o papel da empresa no grupo (holding, operacional, veículo, coligada ou fora do perímetro).",
  forma_de_controle_indefinida: "Falta dizer como a empresa é controlada (por outra empresa do caso ou por controle comum).",
  controlada_por_entidade_sem_controladora: "Está marcada como controlada por outra empresa, mas a controladora não foi escolhida.",
  controle_comum_sem_vinculo: "Está marcada como controle comum, mas nenhum sócio/controlador foi registrado.",
  sem_escopo_vigente: "Está no perímetro mas sem escopo vigente: o combinado não sabe se ela entra.",
  fora_do_perimetro_com_escopo_vigente: "Está marcada como fora do perímetro, mas ainda tem escopo vigente: encerre o escopo ou mude o papel.",
  entidade_fantasma_pendente_de_revisao: "Nome que parece coluna, aba ou arquivo, não empresa: funda com a empresa real ou descarte.",
};

const PENDENCIAS: Record<string, string> = {
  entidade_ambigua: "Há pendência aberta: não está claro a qual empresa os documentos pertencem.",
  entidade_nome_suspeito: "Há pendência aberta: o nome da empresa parece suspeito.",
  entidade_incorreta: "Há pendência aberta: documento atribuído a uma empresa que pode estar errada.",
  contrato_social_ausente: "Há pendência aberta: falta o contrato social desta empresa.",
};

const PREFIXO_PENDENCIA = "pendencia_aberta:";

/** Uma chave de `falta` em frase de analista. Chave desconhecida volta CRUA, com o aviso. */
export function traduzirFalta(chave: string): string {
  if (Object.hasOwn(FALTAS, chave)) return FALTAS[chave];
  if (chave.startsWith(PREFIXO_PENDENCIA)) {
    const tipo = chave.slice(PREFIXO_PENDENCIA.length);
    if (Object.hasOwn(PENDENCIAS, tipo)) return PENDENCIAS[tipo];
    return `Há pendência aberta de perímetro sem tradução (${chave}).`;
  }
  return `Motivo sem tradução: ${chave}`;
}

/** Os dois vocabulários conhecidos, para o verificador provar que cada chave tem frase. */
export const CHAVES_DE_FALTA = Object.keys(FALTAS);
export const TIPOS_DE_PENDENCIA = Object.keys(PENDENCIAS);

/** 14 dígitos viram 00.000.000/0000-00; qualquer outra coisa volta como veio (não inventa máscara). */
export function formatarCnpj(cnpj: string | null | undefined): string {
  if (!cnpj) return "CNPJ não informado";
  const d = cnpj.replace(/\D/g, "");
  if (d.length !== 14) return cnpj;
  return `${d.slice(0, 2)}.${d.slice(2, 5)}.${d.slice(5, 8)}/${d.slice(8, 12)}-${d.slice(12)}`;
}

/** "12,5" e "12.5" são o mesmo número; vazio é null (ausência), texto inválido é NaN para a action recusar. */
export function lerPercentual(texto: string | null | undefined): number | null {
  const t = (texto ?? "").trim().replace(",", ".");
  if (t === "") return null;
  if (!/^\d+(\.\d+)?$/.test(t)) return Number.NaN;
  return Number(t);
}

export function tituloDoVeredito(v: { entidades: number; prontas: number; fechado: boolean }): string {
  if (v.fechado) return "Perímetro fechado";
  if (v.entidades === 0) return "Perímetro não montado";
  return `Faltam ${v.entidades - v.prontas} de ${v.entidades} empresas`;
}

export const ACEITE_ROTULO: Record<string, string> = {
  nao_verificado: "Não verificado contra o combinado do cliente",
  pendente_conferencia: "Pendente de conferência humana contra o combinado",
};

/** Aceite desconhecido aparece cru (regra 7); nunca vira "ok" por omissão. */
export function rotuloDoAceite(chave: string): string {
  return Object.hasOwn(ACEITE_ROTULO, chave) ? ACEITE_ROTULO[chave] : `Aceite sem tradução: ${chave}`;
}

// --- Família declarada (0212) ------------------------------------------------------------------
// Parentesco só vale DECLARADO, com fonte: nunca inferido por sobrenome.
export type Parentesco = "conjuge_companheiro" | "linha_reta_ate_2o_grau" | "irmao";

export const PARENTESCOS: ReadonlyArray<{ valor: Parentesco; rotulo: string }> = [
  { valor: "conjuge_companheiro", rotulo: "Cônjuge ou companheiro(a)" },
  { valor: "linha_reta_ate_2o_grau", rotulo: "Linha reta até 2º grau (pais, filhos, avós, netos)" },
  { valor: "irmao", rotulo: "Irmão(ã)" },
];

/** Parentesco desconhecido aparece cru (regra 7): nunca vira um rótulo vizinho nem some. */
export function rotuloDoParentesco(chave: string): string {
  const p = PARENTESCOS.find((x) => x.valor === chave);
  return p ? p.rotulo : `Parentesco sem tradução: ${chave}`;
}

const MOTIVOS_DO_GRUPO: Record<string, string> = {
  controlador_comum: "Por sócio em comum: as empresas têm ao menos um sócio/controlador em comum.",
  vinculo_familiar: "Por vínculo familiar declarado: sem o parentesco abaixo estas empresas seriam grupos separados. O fecho é transitivo (A–B e B–C juntam A e C).",
};
export const MOTIVOS_DE_GRUPO = Object.keys(MOTIVOS_DO_GRUPO);

/** Motivo de grupo desconhecido, ou ausente (banco sem a 0212), aparece dito e cru, nunca como "sócio em comum". */
export function rotuloDoMotivoDoGrupo(chave: string | null | undefined): string {
  if (chave === null || chave === undefined || chave === "") return "Motivo do grupo não informado pelo banco.";
  return Object.hasOwn(MOTIVOS_DO_GRUPO, chave) ? MOTIVOS_DO_GRUPO[chave] : `Motivo do grupo sem tradução: ${chave}`;
}
