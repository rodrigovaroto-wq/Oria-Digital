// O RASCUNHO DE E-MAIL AO CLIENTE, montado das perguntas que o analista selecionou.
//
// FUNÇÃO PURA, e por isso medida em `scripts/verificar-kit-basico.mts`. O que sai daqui é texto
// que VAI PARA FORA DA CASA, então três coisas importam e as três são silenciosas quando erram:
//   1. só o TEXTO da pergunta entra. Código do catálogo, motivo, risco, impacto, fonte e gatilho
//      são internos — "risco de aval cruzado" num e-mail ao cliente é vazamento de raciocínio;
//   2. a numeração é contínua e a ordem é estável (sem empresa primeiro, depois empresas em
//      ordem alfabética pt-BR; dentro do grupo, prioridade e código). Selecionar na ordem que
//      for gera o mesmo e-mail;
//   3. o sistema não envia nada: isto é um rascunho editável.
//
// O PREFIXO "Sobre a {empresa}: " que `fn_sugerir_perguntas` põe no texto (0120) é retirado
// quando a pergunta já está sob o título da empresa — repeti-lo é ruído. Só o prefixo exato da
// 0120 é retirado; qualquer outra coisa fica como o banco escreveu.

export interface PerguntaParaEmail {
  codigo: string;
  prioridade: number;
  entidade: string | null;
  pergunta: string;
}

const SEM_EMPRESA = "Perguntas gerais";

function semPrefixoDaEmpresa(texto: string, entidade: string | null): string {
  if (!entidade) return texto;
  const prefixo = `Sobre a ${entidade}: `;
  return texto.startsWith(prefixo) ? texto.slice(prefixo.length) : texto;
}

/**
 * O ITEM da pergunta no e-mail: o que `listaNumerada` escreve depois de "N. ". É o que se congela
 * em `texto_enviado` (imutável, 0213) — o trecho que o cliente recebeu para AQUELA pergunta, e não
 * o e-mail inteiro repetido em cada uma. A barra e o diálogo congelam este mesmo formato.
 */
export function textoDoItem(p: PerguntaParaEmail): string {
  return semPrefixoDaEmpresa(p.pergunta, p.entidade).trim();
}

const colapsar = (t: string) => t.replace(/\s+/g, " ").trim();

/**
 * Das perguntas do lote, as que o analista TIROU do texto ao editar. Registrar "enviada" uma
 * pergunta que não está no e-mail seria afirmar um envio que não houve (regra 1); a comparação
 * ignora quebra de linha/espaço duplo, que editores de e-mail reformatam, e nada além disso.
 */
export function perguntasForaDoTexto<T extends PerguntaParaEmail>(
  perguntas: readonly T[], textoEditado: string,
): T[] {
  const corpo = colapsar(textoEditado);
  return perguntas.filter((p) => !corpo.includes(colapsar(textoDoItem(p))));
}

/** As perguntas numeradas e agrupadas por empresa, sem saudação nem assinatura (o "Copiar" da barra). */
export function listaNumerada(perguntas: readonly PerguntaParaEmail[]): string {
  const ordenadas = [...perguntas].sort(
    (a, b) =>
      a.prioridade - b.prioridade
      || a.codigo.localeCompare(b.codigo)
      || (a.entidade ?? "").localeCompare(b.entidade ?? "", "pt-BR"),
  );
  const grupos = new Map<string, PerguntaParaEmail[]>();
  for (const p of ordenadas) {
    const chave = p.entidade ?? "";
    const g = grupos.get(chave);
    if (g) g.push(p);
    else grupos.set(chave, [p]);
  }
  const chaves = [...grupos.keys()].sort((a, b) =>
    a === "" ? -1 : b === "" ? 1 : a.localeCompare(b, "pt-BR"),
  );
  // Com uma só empresa (ou nenhuma), título de grupo seria ruído.
  const comTitulos = chaves.length > 1 || (chaves.length === 1 && chaves[0] !== "");
  const linhas: string[] = [];
  let n = 0;
  for (const chave of chaves) {
    if (comTitulos) linhas.push(chave === "" ? `${SEM_EMPRESA}:` : `${chave}:`, "");
    for (const p of grupos.get(chave) ?? []) {
      n += 1;
      linhas.push(`${n}. ${textoDoItem(p)}`, "");
    }
  }
  return linhas.join("\n").trimEnd();
}

export function montarEmailAoCliente(
  perguntas: readonly PerguntaParaEmail[],
  mandato: string,
): string {
  return [
    "Prezados,",
    "",
    `No âmbito do mandato ${mandato}, precisamos de alguns esclarecimentos e documentos complementares:`,
    "",
    listaNumerada(perguntas),
    "",
    "Ficamos à disposição para qualquer dúvida.",
    "",
    "Atenciosamente,",
    "[nome]",
  ].join("\n");
}

/** O assunto do e-mail. */
export function assuntoDoEmail(mandato: string): string {
  return `Documentos e esclarecimentos — ${mandato}`;
}

/** Acima disto, clientes de e-mail e navegadores começam a truncar ou recusar `mailto:` em silêncio. */
export const LIMITE_MAILTO = 1800;

/** `mailto:` com assunto e corpo, ou `null` quando passa do limite — quem chama diz isso ao analista. */
export function linkMailto(assunto: string, corpo: string): string | null {
  const url = `mailto:?subject=${encodeURIComponent(assunto)}&body=${encodeURIComponent(corpo)}`;
  return url.length <= LIMITE_MAILTO ? url : null;
}

/**
 * "N registradas; M falharam: …; K não registradas: …" — nunca diz que tudo deu certo se algo
 * falhou ou ficou de fora. `foraDoTexto` são as que o analista tirou do e-mail editado.
 */
export function resumoDoLote(
  registradas: number, falhas: readonly string[], foraDoTexto: readonly string[] = [],
): string {
  const reg = `${registradas} ${registradas === 1 ? "registrada" : "registradas"}`;
  if (falhas.length === 0 && foraDoTexto.length === 0) {
    return `${reg} como ${registradas === 1 ? "enviada" : "enviadas"}.`;
  }
  const partes = [reg];
  if (falhas.length > 0) {
    partes.push(`${falhas.length} ${falhas.length === 1 ? "falhou" : "falharam"}: ${falhas.join(" | ")}`);
  }
  if (foraDoTexto.length > 0) {
    partes.push(
      `${foraDoTexto.length} não ${foraDoTexto.length === 1 ? "registrada" : "registradas"} por ${foraDoTexto.length === 1 ? "não estar" : "não estarem"} mais no texto editado: ${foraDoTexto.join(" | ")}`,
    );
  }
  return partes.join("; ");
}
