// Classificador determinístico por NOME DE ARQUIVO + regras (E1).
//
// Autonomia: classificação doc→checklist nasce em N1 (sugere, humano confirma).
// Este classificador é o passo barato/determinístico; quando não tem confiança,
// o workflow N8N faz fallback para a IA ler o conteúdo (ver ia.mjs e provedor.mjs).
//
// Não decide nada sozinho: devolve uma SUGESTÃO com confiança e os sinais que
// a sustentam, para a fila de revisão.

import { normalize } from './normalize.mjs';
import { ALIASES } from './taxonomia.mjs';

// QUEDA, não regra. O limiar que MANDA é o do dial (`estagio_autonomia.
// limiar_auto_clear` do estágio `classificacao_doc_checklist`), lido do banco e
// passado em `classifyByFilename(nome, limiar)`. Este valor só vale quando o
// limiar não chegou — banco sem a linha do dial, ou chamada de teste.
//
// POR QUE ISSO IMPORTA, e não é organização. A `0127` já tinha tirado o número
// fixo do lado do Postgres: lá `fn_registrar_documento` chama
// `fn_dial_permite_auto(...)` e o `p_threshold default 0.7` sobrou só como
// queda. O lado do n8n ficou para trás, e com ele a metade da divergência que o
// cabeçalho da própria 0127 denunciou: *"o 0,70 mora em DOIS lugares"*.
//
// O ESTRAGO CONCRETO de deixar assim: subir o dial para 0,85 faz o banco abrir
// `classificacao_pendente` para todo documento entre 0,70 e 0,85 — e o n8n, com
// 0,70 fixo, nunca mandou a IA LER esses documentos, porque para ele 0,72 já
// era bom. O sistema pergunta ao humano exatamente o que ele poderia ter
// resolvido sozinho por conteúdo, e o dial vira um botão que piora o serviço ao
// ser apertado. Com o limiar vindo do dial, subir o dial faz as duas pontas se
// moverem juntas.
const THRESHOLD_AUTO = 0.7;

// Helper de `parsePeriodo` (extraído pelo Sonar S3776; AUTO-CONTIDO, embutido por
// toString() junto com ela em FONTE_CLASSIFICADOR).
export function periodoAcumuladoNoAno(t) {
  // ACUMULADO NO ANO (YTD) — "janaago26", "jan a ago 26", "janeiro a agosto de 2026".
  // Krauspenhar real: `DRE_janaago26.pdf` foi registrada como período anual 2026 e
  // são 8 meses (jan-ago); a receita de 8 meses era comparada com ano cheio. Faixa
  // que COMEÇA em janeiro e termina antes de dezembro vira "NM" + ano (8M26), na
  // forma que o banco já canoniza (fn_periodo_canonico: NM → "nm"+ano) e que o
  // prompt já usa para "9 meses de 2024". Só YTD (começa em jan): outra faixa
  // ("mar a ago") compartilharia a referência com outra do mesmo tamanho, então
  // fica sem período do nome em vez de ganhar um ambíguo.
  const mesesFim = ['fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov'];
  const ytd = t.match(/\bjan[a-z]*?\s*(?:a\s*|ate\s*)?(fev|mar|abr|mai|jun|jul|ago|set|out|nov)[a-z]*\s*(?:de\s*)?((?:20)?\d{2})\b/);
  if (ytd) {
    const meses = mesesFim.indexOf(ytd[1]) + 2;
    // `fraco`: é uma DICA do nome (soma 0,05 e não 0,3), de propósito — com 0,3 o
    // documento passaria do limiar e PULARIA a classificação por conteúdo, que hoje
    // roda para esses nomes. O que este sinal faz é impedir que a IA o sobrescreva
    // com "anual" (ver mergeClassification).
    return { tipo: 'multi', referencia: `${meses}M${ytd[2].slice(-2)}`, fraco: true };
  }
  return null;
}

// Helper de `parsePeriodo` (idem): intervalo de anos "2021-2025" → lista.
export function periodoDeIntervaloDeAnos(t) {
  // intervalo de anos: "2021-2025" | "2021 a 2025" | "21-25" → expande a lista
  // inteira (não só os extremos), no formato multi-ano existente ("21,22,...").
  const m = t.match(/\b(20\d{2}|\d{2})\s*(?:-|–|a)\s*(20\d{2}|\d{2})\b/);
  if (m) {
    const full = (y) => (y.length === 2 ? `20${y}` : y);
    const start = Number(full(m[1]));
    const end = Number(full(m[2]));
    if (start <= end && end - start <= 50) {
      const anos = [];
      for (let y = start; y <= end; y++) anos.push(String(y).slice(-2));
      return { tipo: 'multi', referencia: anos.join(',') };
    }
  }
  return null;
}

// --- Período -----------------------------------------------------------------
// Reconhece as convenções de Arquitetura do Sistema/2 Especificação/f0/03 (12M25, 1T25/1T26, L24M, listas multi-ano)
// e formatos adicionais pedidos pelo dono: ano isolado ("2025") e intervalo de
// anos ("2021-2025", "2021 a 2025") — expandido para a lista completa, não só
// os extremos.
export function parsePeriodo(textoNormalizado) {
  // Prefixo de ORDENAÇÃO do arquivo não é ano. Achado com dado real
  // ("13_Balancete_Analitico_Componentes_2025.pdf" saía como período
  // "multi 13,25" — o "13" do prefixo virou o ano 2013 e o 2025 virou 25):
  // um número no COMEÇO do nome, seguido de separador, é numeração de arquivo,
  // não competência. Remover antes de procurar ano evita períodos-lixo, que
  // além de exibirem errado fragmentam a tabela `periodo` e impedem a
  // reconciliação de casar os documentos do mesmo exercício.
  const t = String(textoNormalizado || '')
    .replace(/^\s*\d{1,3}\s*[-_. ]+/, '')
    // "2025x2024"/"2025 x 2024" é comparativo: o 'x' separa exercícios.
    .replace(/(\d)\s*[x\u00d7]\s*(\d)/g, '$1 $2');

  const acumulado = periodoAcumuladoNoAno(t);
  if (acumulado) return acumulado;

  // 12M25 / 12M2025  → anual (12 meses do ano)
  let m = t.match(/\b(\d{1,2})m(\d{2,4})\b/);
  if (m && Number(m[1]) === 12) {
    return { tipo: 'anual', referencia: `12M${m[2].slice(-2)}` };
  }
  // LxxM → últimos xx meses (ex.: L24M, L12M, L36M ou "faturamento 36 meses")
  m = t.match(/\bl(\d{1,2})m\b/) || t.match(/\b(\d{2})\s*meses\b/);
  if (m) {
    const n = m[1];
    return { tipo: 'multi', referencia: `L${n}M` };
  }
  // 1T25 / 2T2025 → trimestre
  m = t.match(/\b([1-4])t(\d{2,4})\b/);
  if (m) {
    return { tipo: 'trimestre', referencia: `${m[1]}T${m[2].slice(-2)}` };
  }
  const intervalo = periodoDeIntervaloDeAnos(t);
  if (intervalo) return intervalo;
  // listas multi-ano: "23, 24 e 25" | "2023 2024 2025" | "23 24 26"
  // Só é multi-ano de verdade quando os candidatos têm a MESMA largura: um nome
  // como "Balancete 13 2025" mistura numeração com ano, e tratar os dois como
  // exercício produzia "13,25" (bug real). Havendo exatamente UM ano de 4
  // dígitos, ele manda — é o sinal forte.
  const anos4 = t.match(/\b(19|20)\d{2}\b/g);
  if (anos4 && anos4.length === 1) {
    return { tipo: 'anual', referencia: anos4[0], fraco: true };
  }
  if (anos4 && anos4.length >= 2) {
    // ORDENAR ANTES DE TRUNCAR. O `.sort()` sem comparador ordena por texto, e
    // truncar para dois dígitos ANTES disso perde o século: 1999 e 2001 viram
    // "99" e "01", e a ordem de texto devolve "01,99" — o exercício mais novo
    // primeiro, invertido. Ordenando o ano de QUATRO dígitos como número, 1999
    // vem antes de 2001 e a truncagem só acontece depois, sobre a lista já
    // cronológica. Nenhum documento dos dois books exercita o cruzamento de
    // século (o `\b(19|20)\d{2}\b` aceita 19xx, mas todo período medido é 20xx),
    // então isto é defeito LATENTE: some antes de aparecer, e o comparador
    // explícito também é o que a regra S2871 do Sonar cobra.
    const ordenados = [...anos4].sort((a, b) => Number(a) - Number(b));
    return { tipo: 'multi', referencia: ordenados.map((a) => a.slice(-2)).join(',') };
  }
  const anos = t.match(/\b(20)?\d{2}\b/g);
  if (anos && anos.length >= 2) {
    const norm = anos.map((a) => a.slice(-2));
    return { tipo: 'multi', referencia: norm.join(',') };
  }
  // ano isolado: "2025" (só um número de 4 dígitos plausível como ano).
  // Sinal FRACO de propósito — um ano sozinho é muito mais ambíguo que os
  // formatos estruturados acima (poderia ser parte de qualquer texto), então
  // pesa menos na confiança (ver classifyByFilename) e não deve, sozinho,
  // empurrar a classificação por nome a pular a verificação da IA.
  if (anos && anos.length === 1 && /^(19|20)\d{2}$/.test(anos[0])) {
    return { tipo: 'anual', referencia: anos[0], fraco: true };
  }
  return null;
}

// --- Tipo (código da taxonomia) ----------------------------------------------
export function parseTipo(textoNormalizado) {
  for (const { codigo, termos } of ALIASES) {
    for (const termo of termos) {
      if (textoNormalizado.includes(termo)) {
        return { codigo, termo };
      }
    }
  }
  return null;
}

// --- Assinado (atributo de validação formal, Arquitetura do Sistema/2 Especificação/f0/03) --------------------------
export function parseAssinado(textoNormalizado) {
  if (/\bassinad[oa]s?\b/.test(textoNormalizado)) return true;
  return null; // desconhecido (não é "não assinado")
}

// --- Entidade ----------------------------------------------------------------
// O "teste v31" mostrou o preço de devolver `entidade: null` aqui. A cadeia era:
// num documento que o nome classifica ACIMA do limiar (0,90 nos comparativos
// `..._2025x2024.pdf`) o fallback da IA nunca roda, então a ÚNICA fonte de
// entidade passava a ser o `diagnostico` da EXTRAÇÃO. Quando a extração falha —
// no v31, teto de gasto da OpenAI derrubou 8 de 14 — a entidade morre junto, e o
// dashboard mostrou "—" nos 14. Os nomes diziam a empresa em voz alta:
// `Vertentes_Metalurgica`, `VT_Logistica`, `Grupo_Vertentes`.
//
// O que isto NÃO faz, porque seria furar a anti-ancoragem (Arquitetura do Sistema/1 Visão e Doutrina/01, Arquitetura do Sistema/2 Especificação/f0/06):
//   • não soma confiança nenhuma — um documento não pode PULAR a verificação da
//     IA porque o nome sugeriu uma empresa. `confianca` continua saindo só de
//     tipo/período/assinado, e `THRESHOLD_AUTO` continua valendo igual;
//   • não vira fato: sai com `fonte: 'nome_arquivo'` e seque o caminho de sempre
//     — `fn_registrar_diagnostico` (0010) só preenche entidade quando está vazia
//     e abre pendência quando o conteúdo diverge do que foi registrado.
// É uma HIPÓTESE barata que sobrevive à falha da extração, e nada além disso.
//
// AUTO-CONTIDA de propósito (recebe `aliases` por parâmetro, declara os próprios
// helpers): o gerador embute o `toString()` desta função no Code node, que não
// importa arquivo. É o mesmo padrão de `diagnosticarErroApi` — e é o que impede
// este virar o quarto mirror manual do repositório, já que dois dos anteriores
// divergiram na prática.
export function parseEntidade(textoNormalizado, aliases) {
  // Palavras que descrevem o DOCUMENTO, não a empresa. Sem isto,
  // `12_Mutuos_Intragrupo_Grupo_Vertentes` viraria "Intragrupo Grupo Vertentes".
  const RUIDO = new Set([
    'combinado', 'combinada', 'combinadas', 'consolidado', 'consolidada', 'consolidadas',
    'analitico', 'analitica', 'sintetico', 'sintetica', 'intragrupo', 'intra',
    'assinado', 'assinada', 'assinados', 'assinadas', 'final', 'rev', 'revisado',
    'versao', 'copia', 'scan', 'digitalizado', 'grupo_', 'exercicio', 'exercicios',
    // Preposições e artigos: ninguém se chama "De". Sem isto sobrava
    // "Aging De Canastra Industria" e "Folha De Pagamento Canastra Industria".
    'de', 'do', 'da', 'dos', 'das', 'em', 'no', 'na', 'nos', 'nas', 'ao', 'aos', 'por',
    // Vocabulário de NOME DE ARQUIVO — o que o cliente escreve quando não escreve
    // o tipo: "ANEXO IV - planilha final REV3.pdf", "Doc1.pdf". São os três
    // arquivos com nome de vida real do book, e nenhum deles nomeia empresa.
    'anexo', 'anexos', 'doc', 'doc1', 'documento', 'documentos', 'arquivo', 'planilha',
    'planilhas', 'pasta', 'meses', 'mes', 'periodo', 'atualizado', 'atualizada', 'novo', 'nova',
    // O ESTADO EM QUE O DOCUMENTO CHEGOU — medido nos 190 nomes do book-araucaria,
    // onde estas palavras produziram 30 empresas que não existem: "Comparativo
    // Araucaria Serraria", "Encerramento Araucaria Part", "Grupo Araucaria
    // Preliminar", "Reemitido Araucaria Serraria Reemissao", "Segunda Via
    // Araucaria Serraria".
    //
    // POR QUE AQUI E NÃO NA TAXONOMIA: nenhuma delas é TIPO de documento. Um
    // balanço comparativo é um balanço; um encerramento é um balanço; uma
    // reemissão é o mesmo documento outra vez. Elas dizem em que ESTADO a peça
    // chegou — que é exatamente o que esta lista existe para descrever. As que
    // ERAM tipo (fluxos de caixa, mapa de dívida bancária, relatório do auditor)
    // foram para `taxonomia.mjs`, junto com o resto do vocabulário.
    //
    // 'preliminar' NÃO some do sistema por sair daqui: `fn_documento_preliminar`
    // (0151) continua lendo o nome ORIGINAL do arquivo e rebaixando a autoridade
    // do documento em 25. O que muda é só que ela para de virar nome de empresa.
    'comparativo', 'comparativa', 'encerramento', 'preliminar', 'preliminares',
    'reemitido', 'reemitida', 'reemissao', 'revisada', 'revisao', 'segunda', 'via',
    'lote', 'escritorio', 'alteracao', 'alteracoes', 'parte', 'partes',
    // AQUI NÃO MORA MAIS PALAVRA DE TIPO. 'negativas', 'societario' e
    // 'parcelamentos' ficaram nesta lista por um tempo com um comentário
    // dizendo que o lugar certo era a taxonomia — e era mesmo: agora eles são
    // termos de CERTIDOES, ORGANOGRAMA e SITUACAO_FISCAL em `lib/taxonomia.mjs`,
    // e a regra do vocabulário logo abaixo os remove sozinha, junto com toda
    // palavra de tipo que entrar na taxonomia daqui para a frente.
    //
    // O que sobrou nesta lista é de outra natureza, e por isso continua: ruído
    // de nome de ARQUIVO ("rev3", "scan", "anexo") e preposição. Nada disso é
    // tipo de documento, então nada disso tem lugar na taxonomia.
  ]);
  // Siglas que ficam feias em Title Case ("Vt Logistica"). Lista curta e
  // explícita: adivinhar por "não tem vogal" erraria em `SPE`.
  const SIGLAS = new Set(['vt', 'spe', 'sa', 'me', 'epp', 'ltda', 'eireli', 'scp']);

  const ehPeriodo = (tok) =>
    /^(19|20)?\d{2}$/.test(tok) ||        // 2025, 25
    /^\d{1,3}$/.test(tok) ||              // número de sequência do arquivo (01)
    // 2025x2024 E 2025x2024x2023: o comparativo de TRÊS exercícios não casava no
    // `x` único, e era ele que produzia a entidade "Canastra Industria
    // 2025x2024x2023" na rodada real — 15 das 22 pendências de revisão saíram
    // daí, porque o diagnóstico do conteúdo diz "Canastra Industria" e a
    // divergência com o nome registrado abre pendência.
    /^\d{2,4}(x\d{2,4})+$/.test(tok) ||
    /^\d{1,2}m\d{2,4}$/.test(tok) ||      // 12m25
    /^l\d{1,2}m$/.test(tok) ||            // l24m
    /^\d{1,2}m$/.test(tok) ||             // 24m
    /^[1-4]t\d{2,4}$/.test(tok) ||        // 1t25
    // Data ou sequência de scanner ("digitalizado_20260115_0003"): token que é
    // SÓ dígito nunca é nome de empresa, qualquer que seja o comprimento.
    /^\d+$/.test(tok);

  // Remove TODOS os termos de tipo presentes, do mais longo para o mais curto.
  // Parar no primeiro match (como `parseTipo` faz, e deve fazer) deixaria lixo:
  // em `06_BP_COMBINADO_Grupo_Vertentes` o alias que casa é 'combinado', e o
  // 'bp' sobraria dentro do nome da entidade.
  let s = ` ${textoNormalizado} `;
  const termos = [];
  for (const a of aliases || []) for (const termo of a.termos) termos.push(termo);
  termos.sort((x, y) => y.length - x.length);
  for (const termo of termos) s = s.split(` ${termo} `).join(' ');

  // PALAVRA QUE VIVE NO VOCABULÁRIO DE TIPO NÃO É NOME DE EMPRESA.
  //
  // A remoção acima é por FRASE INTEIRA, e o nome de arquivo raramente traz a
  // frase inteira: `23_Aging_de_Contas_a_Pagar_...` casa o alias "contas a
  // pagar" e deixa "aging" para trás; `27_Composicao_do_Imobilizado_...` deixa
  // "composicao" e "imobilizado"; `30_Certidoes_Negativas_...` deixa
  // "negativas". Medido nos 38 nomes do book: onze entidades saíam com sobra
  // documental grudada no nome da empresa.
  //
  // A fonte é a MESMA taxonomia, palavra a palavra — não uma segunda lista à mão
  // (o repositório já pagou caro por espelho manual que divergiu). Ela cresce
  // sozinha quando um tipo novo entra na taxonomia.
  //
  // O erro que esta regra pode cometer é remover demais numa empresa que se
  // chame com uma palavra de tipo, e o resultado disso é `entidade: null` — que
  // é a saída CONSERVADORA. Esta função é uma hipótese barata: não ter hipótese
  // é melhor que ter a errada, porque a errada vira pendência de divergência
  // para um humano resolver.
  const palavrasDeTipo = new Set();
  // TRÊS LETRAS, NÃO DUAS — e a diferença é uma empresa inteira.
  //
  // Com `> 1`, o token 'ar' do alias `aging ar` entra no vocabulário de tipo, e
  // `parseEntidade` passa a apagar o "AR" de QUALQUER nome. Medido no
  // book-araucaria: `007_Balanco_Patrimonial_AR_Log_...` saía como a empresa
  // "Log", e `011_..._AR_Servicos_...` como "Servicos" — duas empresas do grupo
  // decapitadas pela sigla, e a "Log" chegou a virar linha em `entidade`.
  //
  // Nada se perde com o corte em 3: as siglas de tipo de DUAS letras ('ar',
  // 'ap', 'bp', 'df') existem no vocabulário apenas dentro de FRASES
  // ('aging ar', 'df auditada'), e a remoção por frase inteira — que roda antes
  // desta — já dá conta delas. O que sobra em 2 letras é prefixo de razão
  // social, que é o caso desta correção.
  for (const termo of termos) for (const p of termo.split(' ')) if (p.length > 2) palavrasDeTipo.add(p);
  // "grupo" NÃO sai, e é a exceção que prova a regra: ele existe no vocabulário
  // de tipo (`faturamento intra grupo`) e ao mesmo tempo é parte do nome de
  // empresa que os documentos combinados usam — "GRUPO CANASTRA" está impresso no
  // cabeçalho deles. Removê-lo faria o nome dizer "Canastra" enquanto o conteúdo
  // diz "Grupo Canastra", e divergência entre os dois é exatamente o que abre a
  // pendência que esta correção existe para evitar.
  palavrasDeTipo.delete('grupo');

  // PONTUAÇÃO QUE SOBRA NÃO É NOME DE EMPRESA. `normalize` troca `_ - .` por
  // espaço e não mexe em parêntese, então `balanço 2024 (1).pdf` chegava aqui
  // com o token `(1)` — que não é período (não é só dígito), não é ruído, e
  // virava a empresa "(1)". Medido nos 190 nomes.
  const tokens = s
    .split(' ')
    .map((tok) => tok.replace(/[^0-9a-z]+/g, ''))
    .filter((tok) => tok && tok.length > 1 && !ehPeriodo(tok)
      && !RUIDO.has(tok) && !palavrasDeTipo.has(tok));
  if (tokens.length === 0) return null;

  const nome = tokens
    .map((tok) => (SIGLAS.has(tok) ? tok.toUpperCase() : tok.charAt(0).toUpperCase() + tok.slice(1)))
    .join(' ');
  // Duas letras não identificam empresa nenhuma; devolver isso como hipótese só
  // geraria uma entidade-lixo na base para um humano ter que apagar depois.
  return nome.length >= 3 ? nome : null;
}

// --- Classificação completa por nome -----------------------------------------
// Retorna sempre um objeto; confianca baixa sinaliza necessidade de fallback.
export function classifyByFilename(nomeOriginal, limiarDoDial) {
  // O limiar chega do dial (ver THRESHOLD_AUTO). Só número finito em (0,1] é
  // aceito: `null`, string vazia, NaN e 0 caem na queda, porque um limiar zero
  // faria CADA documento passar sem a IA ler nenhum — o oposto silencioso do
  // que quem mexeu no dial quis.
  const n = Number(limiarDoDial);
  const limiar = Number.isFinite(n) && n > 0 && n <= 1 ? n : THRESHOLD_AUTO;
  const t = normalize(nomeOriginal);
  const tipo = parseTipo(t);
  const periodo = parsePeriodo(t);
  const assinado = parseAssinado(t);
  // NOME QUE NÃO DIZ NEM O TIPO NÃO DIZ A EMPRESA. Sem esta linha, o resto do
  // nome vira "entidade" por eliminação, e o que sobra é o próprio nome do
  // documento: `34_Relatorio_do_Auditor_Independente_2025.pdf` saía como a
  // empresa "Relatorio Auditor Independente", e `ANEXO IV - planilha final
  // REV3.pdf` como "Iv Rev3". Medido nos 38 nomes do book: seis nomes não têm
  // tipo, e em quatro deles a entidade era pura sobra documental.
  //
  // E não se perde hipótese nenhuma: sem tipo a confiança fica em 0,65 ou menos,
  // abaixo do limiar — então esses documentos VÃO para a classificação por
  // conteúdo, que devolve a entidade lida do próprio documento. Trocar um chute
  // pelo silêncio aqui é trocar pendência de divergência por nada.
  const entidade = tipo ? parseEntidade(t, ALIASES) : null;

  const sinais = { tipo: !!tipo, periodo: !!periodo, assinado: assinado === true, entidade: !!entidade };

  // Confiança: tipo é o sinal forte; período reforça (menos se for um sinal
  // fraco, tipo ano isolado — não deve, sozinho, somado ao tipo, ultrapassar
  // o limiar e pular a verificação da IA); assinado é bônus pequeno.
  let confianca = 0;
  if (tipo) confianca += 0.6;
  if (periodo) confianca += periodo.fraco ? 0.05 : 0.3;
  if (assinado === true) confianca += 0.1;
  confianca = Math.min(1, Number(confianca.toFixed(2)));

  const precisaFallback = confianca < limiar || !tipo;

  return {
    tipo_taxonomia: tipo ? tipo.codigo : null,
    periodo: periodo, // {tipo, referencia} | null
    assinado, // true | null
    confianca,
    fonte: 'nome_arquivo',
    precisa_fallback_ia: precisaFallback,
    // DECLARA contra o que a decisão foi tomada. Sem isto, "não precisou de
    // fallback" é indistinguível de "o limiar estava frouxo", e a pendência que
    // o banco abre do outro lado cita o limiar DELE — os dois números precisam
    // poder ser comparados depois do fato.
    limiar_aplicado: limiar,
    sinais,
    // Hipótese barata, NUNCA fato — e deliberadamente fora do cálculo de
    // `confianca` acima (ver o comentário de `parseEntidade`).
    entidade,
  };
}

export { THRESHOLD_AUTO };
