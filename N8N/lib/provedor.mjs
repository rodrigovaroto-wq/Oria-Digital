// O PROVEDOR DE IA VIRA ESCOLHA, E A ESCOLHA MORA AQUI.
//
// Até 24/08/2026 este repositório não tinha "um provedor": tinha a OpenAI
// espalhada. A URL estava em `lib/openai.mjs` e outra vez em `lib/extract.mjs`;
// o formato do corpo (`messages`/`response_format`) estava nos dois módulos e
// mais uma vez, minificado, dentro de `build-workflow.mjs`; a leitura da
// resposta (`choices[0].message.content`) aparecia em quatro lugares; e o
// `usage` da OpenAI era lido direto pelo medidor de custo. Trocar de provedor
// era, literalmente, achar todos eles.
//
// Aqui a diferença entre um provedor e outro fica reduzida a UM objeto de dados
// (`PROVEDORES`) e a um punhado de funções que ramificam pelo `dialeto` dele.
// O resto do sistema não sabe com quem está falando: monta o corpo, lê o
// conteúdo, lê o uso.
//
// POR QUE DADO PURO, E NÃO UM OBJETO COM MÉTODOS. Os nós Code do n8n não
// importam módulo — o gerador embute o `toString()` das funções da lib, e
// `toString()` não leva o escopo do módulo junto (é o mesmo motivo pelo qual
// `diagnosticarErroApi` é auto-contida). Um provedor com métodos não
// atravessaria essa fronteira; um provedor que é JSON atravessa, porque o
// gerador o escreve no nó como literal e as funções o recebem por argumento.
//
// LGPD: vale para qualquer provedor daqui, e a trilha não mudou de lugar — API
// direta está fora do perímetro Azure, e antes de dado real em produção é
// preciso ter zero-retention/DPA acertado com QUEM ESTIVER ATIVO (ver Arquitetura do Sistema/2 Especificação/f0/02 e
// Arquitetura do Sistema/2 Especificação/10). Trocar de provedor não herda o acordo do anterior.

// ---------------------------------------------------------------------------
// O CATÁLOGO
// ---------------------------------------------------------------------------
//
// `dialeto` é o que as funções deste arquivo olham — 'openai' cobre todo
// provedor que fala `/chat/completions` (a própria OpenAI, e por tabela quem
// imita o formato dela), 'gemini' cobre a API nativa do Google.
//
// A API NATIVA DO GOOGLE, E NÃO A CAMADA DE COMPATIBILIDADE. O Google publica um
// endpoint que imita o `/chat/completions`, e usá-lo faria este arquivo quase
// desaparecer. Não foi o escolhido, e o motivo é o único que importa aqui: o que
// esta troca busca é a leitura de DOCUMENTO, e é a API nativa que recebe o PDF
// como parte (`inlineData` com `application/pdf`) e aceita `responseSchema`. Uma
// camada de imitação é, por construção, o subconjunto que o formato do outro
// comporta — trocar de provedor para ficar com o subconjunto do provedor antigo
// seria pagar a migração e não levar a mercadoria.
export const PROVEDORES = {
  openai: {
    id: 'openai',
    rotulo: 'OpenAI',
    dialeto: 'openai',
    // `{modelo}` não é interpolado nesta URL (o modelo vai no corpo) — o
    // marcador existe para as duas entradas terem a mesma forma.
    url: 'https://api.openai.com/v1/chat/completions',
    // Nome da credencial Header Auth no n8n. O dono cria uma credencial com
    // este nome e o JSON gerado já aponta para ela.
    credencial: 'OpenAI API',
    auth: { nome: 'Authorization', prefixo: 'Bearer ' },
    console: 'platform.openai.com',
    // O CATÁLOGO DE MODELOS DA CONTA. É um GET, não consome token nenhum, e
    // responde a única pergunta que uma chamada de 1 token responde MAL: um 404
    // diz "este id não existe para esta conta" sem dizer QUAIS existem — e a
    // diferença entre um id errado por um dígito e um modelo sem acesso é
    // exatamente a que decide o que fazer.
    catalogo: 'https://api.openai.com/v1/models',
    // Cadência: os dois limites da conta, e o intervalo sai do MAIS restritivo.
    // TPM importa porque `max_tokens` é RESERVA de balde (ver extract.mjs);
    // RPM importa porque um provedor pode limitar por CHAMADA e não por token.
    //
    // 30.000 ERA O PISO DO TIER 1, e o dono confirmou em 14/09/2026 que a conta
    // real tem 500.000 TPM para o `gpt-5.6-luna` — 16,7x mais. Era exatamente o
    // item que a sessão 84 tinha deixado registrado como "o item de maior
    // retorno da lista" (ESTADO.md): `CHAMADAS_POR_MINUTO = TPM_CONTA /
    // (entrada+saída)` em `build-workflow.mjs` escala LINEAR com este número, e
    // o lote de 44 documentos da AMO mediu 1h28 rodando com o piso — a mesma
    // cadência com o TPM real cai para a ordem de 5-6 minutos. Errar para baixo
    // custa tempo; errar para cima faz a API responder 429 no meio do lote — por
    // isso o número aqui é o que o DONO mediu na própria conta, não um chute.
    tpm: 500000,
    rpm: null,
    // RPD é do TIER e a OpenAI não publica um número único para o Tier 1 —
    // `null` diz "não sei", que é diferente de "não tem". Ver o comentário do
    // Google abaixo para o que este número decide.
    rpd: null,
  },
  google: {
    id: 'google',
    rotulo: 'Google (Gemini)',
    dialeto: 'gemini',
    url: 'https://generativelanguage.googleapis.com/v1beta/models/{modelo}:generateContent',
    credencial: 'Google AI (Gemini)',
    // A chave vai em header próprio, não em Bearer, e NUNCA na query string:
    // `?key=` apareceria na URL do nó, que o n8n mostra na tela de execução e
    // grava no log — é segredo em lugar de leitura.
    auth: { nome: 'x-goog-api-key', prefixo: '' },
    console: 'aistudio.google.com/apikey',
    catalogo: 'https://generativelanguage.googleapis.com/v1beta/models',
    // 250.000 TPM e 15 RPM é o patamar de entrada anunciado para a linha
    // Flash-Lite. Declarado no PISO de propósito, pela mesma regra que já valia
    // para o Tier 1 da OpenAI: errar para o lento faz a extração demorar; errar
    // para o rápido faz ela FALHAR, e falha custa a rodada inteira. Quem estiver
    // num tier acima ajusta AQUI — e os três lugares que dependem da cadência
    // (o gerador, o teste que a trava e o diagnóstico) leem este mesmo número.
    tpm: 250000,
    rpm: 15,
    // O LIMITE QUE NINGUÉM TINHA MODELADO, E É O QUE DE FATO APERTA.
    //
    // TPM e RPM decidem a CADÊNCIA — de quanto em quanto tempo a próxima
    // chamada sai. O RPD decide outra coisa: quantos documentos cabem no DIA,
    // somando todos os lotes. E com a linha Flash-Lite no nível gratuito ele é
    // 500, que é pouco perto de um book de 190 documentos: são ~190 extrações
    // mais ~95 classificações por conteúdo (metade dos nomes não resolve
    // tipo+período, medido nos dois books), ou seja ~285 chamadas — 57% da
    // cota do dia num lote só.
    //
    // Por que isso importa mais do que parece: estourar o RPD no meio do lote
    // não deixa o trabalho mais lento, ele MATA os documentos que faltavam, e
    // `diagnosticarErroApi` só consegue nomear a causa DEPOIS. Espaçar as
    // chamadas não ajuda — a cota só reabre na virada da janela diária.
    //
    // Fica declarado aqui, junto dos outros dois, para que a conta "este lote
    // cabe no que sobrou do dia?" tenha uma fonte só. Quem estiver num plano
    // pago ajusta AQUI.
    rpd: 500,
  },
};

// O PADRÃO VOLTOU A SER A OPENAI em 11/09/2026 (decisão do dono: "troque todos
// os modelos do sistema para o GPT-5.6 Luna"). O Google continua inteiro e
// testado aqui — voltar é `IA_PROVEDOR=google` e regerar o workflow.
//
// A TROCA RESOLVE, DE QUEBRA, A CAUSA MEDIDA DA ÚLTIMA RODADA. No "Teste 00"
// (190 documentos, 10–11/09) 75 documentos saíram sem nenhuma linha, e 72 deles
// pelo MESMO motivo: conta do Google sem billing ativo, HTTP 429. Não era
// defeito de código — era a conta — e sair dessa conta remove a causa. Isto não
// é razão para trocar de provedor; é consequência, e fica registrado para a
// próxima sessão não procurar no código um defeito que nunca esteve lá.
export const PROVEDOR_PADRAO = 'openai';

/**
 * O provedor ativo, lido do ambiente. Nome desconhecido cai no padrão em vez de
 * lançar: o gerador roda em CI e num terminal, e um `IA_PROVEDOR` com erro de
 * digitação não deve produzir um workflow pela metade — deve produzir o padrão.
 */
export function provedorAtivo(env = (typeof process !== 'undefined' ? process.env : {})) {
  const id = String((env && env.IA_PROVEDOR) || '').trim().toLowerCase();
  return Object.prototype.hasOwnProperty.call(PROVEDORES, id) ? id : PROVEDOR_PADRAO;
}

/** O objeto do provedor, por id. Desconhecido → o padrão (mesma razão acima). */
export function provedor(id = provedorAtivo()) {
  return PROVEDORES[id] || PROVEDORES[PROVEDOR_PADRAO];
}

/** A URL da chamada, já com o modelo no lugar quando o dialeto pede. */
export function urlDaChamada(prov, modelo) {
  return String(prov.url).replace('{modelo}', encodeURIComponent(String(modelo || '')));
}

// ---------------------------------------------------------------------------
// AS CAPACIDADES DO MODELO — o que é do MODELO e não do provedor
// ---------------------------------------------------------------------------
//
// Até 11/09/2026 este arquivo supunha que "dialeto openai" bastava para montar o
// corpo: `temperature: 0` e `max_tokens`, sempre. A família GPT-5 quebrou a
// suposição, e não em silêncio — ela RECUSA os dois:
//
//   • `temperature` não é aceito (só o default) → HTTP 400 na chamada inteira.
//   • `max_tokens` foi substituído por `max_completion_tokens` → HTTP 400.
//
// Ou seja: trocar só o nome do modelo faria TODA chamada do lote falhar. Não é
// defeito silencioso — é barulhento — mas mata a rodada inteira, e o custo de
// descobrir isso em produção é um book perdido.
//
// POR QUE UM MAPA DECLARADO E NÃO UM `if (/^gpt-5/)`. Um regex sobre o id acerta
// hoje e erra no próximo modelo que a OpenAI lançar com outro prefixo — e erra
// em SILÊNCIO, mandando `temperature` para quem não aceita. Um mapa erra ALTO:
// modelo que ninguém declarou cai no default conservador abaixo e o teste
// `custo.test.mjs` cobra a declaração. É a mesma razão pela qual `PROVEDORES` é
// dado puro e não código.
//
// O DEFAULT DE MODELO DESCONHECIDO é o moderno (sem `temperature`,
// `max_completion_tokens`, sem raciocínio): é o que não quebra numa API nova.
// Ele NÃO é uma opinião sobre qualidade — é a escolha que falha para o lado de
// uma chamada que funciona com o default do provedor, em vez de uma que é
// recusada. Modelo que precise de `temperature: 0` (determinismo) tem de estar
// DECLARADO aqui, senão perde o determinismo sem ninguém notar.
export const CAPACIDADES_POR_MODELO = {
  // OpenAI, família GPT-5 — raciocina, recusa temperature, teto novo.
  'gpt-5.6-luna': { temperatura: false, tetoDeSaida: 'max_completion_tokens', raciocina: true },
  // OpenAI, geração 4o — aceita temperature, teto antigo, não raciocina.
  'gpt-4o': { temperatura: true, tetoDeSaida: 'max_tokens', raciocina: false },
  'gpt-4o-mini': { temperatura: true, tetoDeSaida: 'max_tokens', raciocina: false },
  // Google — o teto e a temperatura moram no `generationConfig`, e o campo do
  // raciocínio (`thinkingConfig`) não é o `reasoning` da OpenAI. `raciocina`
  // aqui diz só "gasta token de pensamento", que é o que o ORÇAMENTO precisa
  // saber; quem monta o corpo ramifica pelo dialeto, como sempre.
  'gemini-3.5-flash-lite': { temperatura: true, tetoDeSaida: 'maxOutputTokens', raciocina: true },
  'gemini-2.5-flash-lite': { temperatura: true, tetoDeSaida: 'maxOutputTokens', raciocina: false },
};

export const CAPACIDADES_PADRAO = {
  temperatura: false, tetoDeSaida: 'max_completion_tokens', raciocina: false,
};

export function capacidadesDoModelo(modelo) {
  return CAPACIDADES_POR_MODELO[String(modelo || '')] || CAPACIDADES_PADRAO;
}

/** O modelo gasta token de raciocínio? É o que o orçamento precisa saber. */
export function modeloRaciocina(modelo) {
  return capacidadesDoModelo(modelo).raciocina === true;
}

// ---------------------------------------------------------------------------
// O SCHEMA — a tradução que não pode inventar campo
// ---------------------------------------------------------------------------
//
// Os dois schemas do sistema (classificação e extração) são escritos no dialeto
// da OpenAI: `strict`, `additionalProperties:false`, e o "nulo" expresso como
// `type:['string','null']`. O Gemini fala um subconjunto de OpenAPI: tipos em
// MAIÚSCULA, nulo como `nullable:true`, e nada de `additionalProperties`,
// `strict`, `minimum` ou `maximum` — mandar um campo que ele não conhece é 400
// na chamada inteira, não um aviso.
//
// A tradução é MECÂNICA de propósito: ela não acrescenta nem remove propriedade
// nenhuma, só reescreve a forma. Quem manda no conteúdo continua sendo o schema
// da lib — se um dia a extração ganhar um campo, ele aparece nos dois provedores
// sem ninguém tocar aqui, que é a diferença entre uma tradução e um segundo
// schema mantido à mão (o espelho manual que este repositório já viu divergir).
//
// `propertyOrdering` não é enfeite: o Gemini documenta que a ordem das chaves na
// saída segue a do schema, e a nossa ordem é a de LEITURA do documento
// (seção → colunas → contas). Sem ela, a ordem fica a critério do modelo — e a
// ordem das linhas é dado neste sistema (0027: é ela que denuncia o subtotal
// impresso acima dos componentes).
export function schemaDoProvedor(prov, jsonSchema) {
  const traduzir = (no) => {
    if (!no || typeof no !== 'object') return no;
    const tipos = Array.isArray(no.type) ? no.type : [no.type];
    const nulo = tipos.includes('null');
    const base = tipos.find((t) => t && t !== 'null') || 'string';
    const MAPA = {
      string: 'STRING', number: 'NUMBER', integer: 'INTEGER',
      boolean: 'BOOLEAN', array: 'ARRAY', object: 'OBJECT',
    };
    const fora = { type: MAPA[base] || 'STRING' };
    if (nulo) fora.nullable = true;
    if (no.description) fora.description = no.description;
    if (Array.isArray(no.enum)) fora.enum = no.enum.slice();
    if (no.items) fora.items = traduzir(no.items);
    if (no.properties && typeof no.properties === 'object') {
      const chaves = Object.keys(no.properties);
      fora.properties = {};
      for (const k of chaves) fora.properties[k] = traduzir(no.properties[k]);
      fora.propertyOrdering = chaves;
      // `required` do Gemini é lista de chaves, igual ao JSON Schema — mas só
      // faz sentido num objeto, e mandá-lo solto num escalar é 400.
      if (Array.isArray(no.required)) fora.required = no.required.slice();
    }
    return fora;
  };
  if (prov.dialeto === 'gemini') return traduzir(jsonSchema.schema || jsonSchema);
  return jsonSchema.schema || jsonSchema;
}

// ---------------------------------------------------------------------------
// O CORPO DA CHAMADA
// ---------------------------------------------------------------------------
//
// A mesma entrada nos dois dialetos: um prompt de SISTEMA (idêntico em toda
// chamada — é o que faz o cache de prefixo valer, Arquitetura do Sistema/4 Análises e Auditorias/CUSTO_IA.md), uma lista
// de PARTES de usuário (texto + o documento), um schema e um teto de saída.
//
// O prompt de sistema fica em campo PRÓPRIO nos dois (`role:'system'` na OpenAI,
// `systemInstruction` no Gemini) e nunca é concatenado na mensagem do usuário:
// é a condição do cache, e é o invariante que `workflow-sim.test.mjs` trava.
//
// `schema` NULO é caso legítimo, e existe por um usuário só: o workflow de
// diagnóstico, que manda uma chamada de UM token para descobrir se a conta
// responde. Ali não há saída para prender — prendê-la a um schema faria a
// chamada mínima deixar de ser mínima. Todo o resto do sistema sempre manda
// schema, e é o schema que torna o parsing não-frágil.
export function montarCorpoIA(
  prov,
  { modelo, sistema, partes, schema = null, maxTokens = null, esforco = null },
) {
  const lista = Array.isArray(partes) ? partes : [partes];
  if (prov.dialeto === 'gemini') {
    const corpo = {
      contents: [{ role: 'user', parts: lista }],
      generationConfig: { temperature: 0 },
    };
    if (sistema) corpo.systemInstruction = { parts: [{ text: sistema }] };
    if (schema) {
      corpo.generationConfig.responseMimeType = 'application/json';
      corpo.generationConfig.responseSchema = schemaDoProvedor(prov, schema);
    }
    if (maxTokens) corpo.generationConfig.maxOutputTokens = maxTokens;
    return corpo;
  }
  const cap = capacidadesDoModelo(modelo);
  const corpo = { model: modelo, messages: [] };
  // `temperature: 0` só entra em modelo que o ACEITA. Na família GPT-5 ele é
  // recusado (400) e o modelo roda no default — então o determinismo que este
  // sistema tinha na extração numérica deixa de existir por construção, não por
  // descuido. `N8N/lib/repetibilidade.mjs` (`compararExtracoes`) é a função
  // determinística, fora do LLM, que compara duas extrações do MESMO documento
  // e acusa divergência — pedida pelo dono para fechar exatamente esta lacuna.
  // ELA AINDA NÃO ESTÁ LIGADA AO WORKFLOW (11/09/2026): existe testada e
  // auto-contida, mas nenhum nó do grafo a chama ainda — a segunda extração
  // amostral e a comparação dentro do fluxo ficaram para uma sessão seguinte.
  // Até lá, a perda de determinismo NÃO está coberta, só nomeada.
  if (cap.temperatura) corpo.temperature = 0;
  if (schema) corpo.response_format = { type: 'json_schema', json_schema: schema };
  if (sistema) corpo.messages.push({ role: 'system', content: sistema });
  corpo.messages.push({ role: 'user', content: lista });
  // O NOME DO TETO MUDA COM O MODELO, e mandar o errado é 400.
  if (maxTokens) corpo[cap.tetoDeSaida] = maxTokens;
  // O esforço só vai para quem raciocina — campo desconhecido é 400 na chamada
  // inteira, não um aviso. `esforco` nulo deixa o modelo no default dele.
  if (cap.raciocina && esforco) corpo.reasoning_effort = esforco;
  return corpo;
}

// ---------------------------------------------------------------------------
// AS PARTES DE CONTEÚDO
// ---------------------------------------------------------------------------
//
// NUNCA LANÇA: tipo não suportado vira uma parte de TEXTO que declara o caso, em
// vez de derrubar o item. É comportamento antigo e deliberado — um dead-end no
// meio do grafo do n8n é uma execução que morre sem dizer o que faltou.
export function parteDeTexto(prov, texto) {
  const t = String(texto == null ? '' : texto);
  return prov.dialeto === 'gemini' ? { text: t } : { type: 'text', text: t };
}

export function parteDeArquivo(prov, { mimeType, base64, filename, text } = {}) {
  const mt = (mimeType || '').toLowerCase();
  if (text != null && text !== '') {
    return parteDeTexto(prov, String(text).slice(0, 20000));
  }
  const ehPdf = /pdf/.test(mt);
  const ehImagem = mt.startsWith('image/');
  if (!ehPdf && !ehImagem) {
    return parteDeTexto(
      prov,
      `(conteúdo não enviado: tipo "${mt || 'desconhecido'}" requer extração prévia; `
      + `classificar só pelo nome "${filename || ''}")`,
    );
  }
  if (prov.dialeto === 'gemini') {
    // O Gemini recebe PDF e imagem pela MESMA porta (`inlineData`), e é isso que
    // faz o documento escaneado e o documento com camada de texto seguirem o
    // mesmo caminho — na OpenAI eles são duas formas diferentes de parte.
    return { inlineData: { mimeType: ehPdf ? 'application/pdf' : mt, data: base64 } };
  }
  if (ehPdf) {
    return {
      type: 'file',
      file: { filename: filename || 'documento.pdf', file_data: `data:application/pdf;base64,${base64}` },
    };
  }
  return { type: 'image_url', image_url: { url: `data:${mt};base64,${base64}` } };
}

// ---------------------------------------------------------------------------
// A LEITURA DA RESPOSTA
// ---------------------------------------------------------------------------

/**
 * O texto da resposta — o JSON pedido no schema, ainda como string.
 *
 * O Gemini pode devolver a saída repartida em VÁRIAS partes do mesmo candidato;
 * ler só `parts[0]` daria um JSON cortado ao meio, que é indistinguível de
 * truncamento e mandaria a próxima sessão investigar o teto de tokens. Concatena.
 */
export function conteudoDaResposta(prov, resp) {
  if (prov.dialeto === 'gemini') {
    const partes = resp && resp.candidates && resp.candidates[0]
      && resp.candidates[0].content && resp.candidates[0].content.parts;
    if (!Array.isArray(partes)) return null;
    const texto = partes.map((p) => (p && typeof p.text === 'string' ? p.text : '')).join('');
    return texto === '' ? null : texto;
  }
  const c = resp && resp.choices && resp.choices[0]
    && resp.choices[0].message && resp.choices[0].message.content;
  return c == null || c === '' ? null : c;
}

/**
 * A resposta foi cortada pelo teto de saída?
 *
 * Normalizado para booleano de propósito: `finish_reason:'length'` e
 * `finishReason:'MAX_TOKENS'` são o mesmo fato, e quem lê rio abaixo só precisa
 * do fato. É ele que separa "documento denso demais para uma chamada" de
 * "resposta inválida" — e essa distinção decide se o caminho é fatiar ou
 * investigar.
 */
export function cortadoPorLimite(prov, resp) {
  if (prov.dialeto === 'gemini') {
    return (resp && resp.candidates && resp.candidates[0]
      && resp.candidates[0].finishReason) === 'MAX_TOKENS';
  }
  return (resp && resp.choices && resp.choices[0] && resp.choices[0].finish_reason) === 'length';
}

/**
 * O uso da chamada, NA FORMA DA OPENAI.
 *
 * Normalizar aqui é o que deixa `custoDaChamada` intocado: ele já sabia ler
 * `prompt_tokens`/`completion_tokens`/`cached_tokens`, e continua sendo o único
 * lugar que faz conta de dinheiro. O provedor novo não espalha um segundo
 * formato de `usage` pelo sistema — ele traduz para o que já existe.
 *
 * Ausente devolve `null`, e não zero: `custoDaChamada` trata null como "não sei"
 * e devolve null, que é o certo. Zero seria um custo INVENTADO num relatório de
 * custo, que é pior que um campo vazio.
 */
/**
 * O uso na forma do Gemini, traduzido para a da OpenAI.
 *
 * SEPARADA DE `usoDaChamada` em 11/09/2026, e não é cosmético: a função única
 * ramificava por dialeto E fazia a normalização numérica dos dois lados, e o
 * ramo novo do raciocínio da OpenAI a empurrou para complexidade cognitiva 16
 * (o Sonar reprova acima de 15). Empilhar mais um `if` numa função que já
 * ramificava é exatamente o sedimento que a auditoria desta sessão mediu — a
 * saída é separar os ramos, não achatá-los.
 *
 * ATENÇÃO À FRONTEIRA DO `toString()`: esta função roda DENTRO de nó Code do
 * n8n, e o gerador tem de embuti-la junto com `usoDaChamada` (ver
 * `FONTE_PROVEDOR` em `build-workflow.mjs`). Sem isso é `ReferenceError` no nó
 * e a medição de custo do lote some — já aconteceu nesta sessão com
 * `capacidadesDoModelo`.
 */
export function usoGemini(resp) {
    const u = resp?.usageMetadata;
    if (!u) return null;
    const cache = Number(u.cachedContentTokenCount || 0);
    // O TOKEN DE RACIOCÍNIO É TOKEN DE SAÍDA, E É COBRADO COMO TAL.
    //
    // Achado na PRIMEIRA chamada real, em 24/08: o catálogo declara
    // `thinking: true` para toda a linha 3.x, e um modelo que pensa gasta
    // orçamento de saída ANTES de escrever a primeira chave do JSON. Esses
    // tokens vêm em `thoughtsTokenCount`, separados de `candidatesTokenCount`.
    //
    // Contar só o `candidates` era subdeclarar a conta pela parte que não se vê
    // — e subdeclarar POR CIMA de um teto de gasto é o pior lado para errar: o
    // guarda dos US$ 3 deixaria passar um lote que o provedor cobra mais caro.
    // A medição do book (US$ 0,28) foi feita sem esta parcela e é, portanto, um
    // PISO; o número real sai da primeira rodada de verdade.
    const raciocinio = Number(u.thoughtsTokenCount || 0);
    const saida = Number(u.candidatesTokenCount || 0);
    return {
      prompt_tokens: Number(u.promptTokenCount || 0),
      completion_tokens: (Number.isFinite(saida) ? saida : 0)
        + (Number.isFinite(raciocinio) ? raciocinio : 0),
      prompt_tokens_details: { cached_tokens: Number.isFinite(cache) ? cache : 0 },
      // Declarado à parte para quem lê a execução: sem isto, "a saída custou X"
      // não distingue JSON de raciocínio, e é essa distinção que decide se vale
      // desligar o pensamento no prompt de extração.
      thoughts_tokens: Number.isFinite(raciocinio) ? raciocinio : 0,
    };
}

export function usoDaChamada(prov, resp) {
  if (prov.dialeto === 'gemini') return usoGemini(resp);
  const u = resp?.usage;
  if (!u) return null;
  // O TOKEN DE RACIOCÍNIO TAMBÉM EXISTE AQUI, desde a família GPT-5.
  //
  // Diferença que importa para a conta: na OpenAI o `completion_tokens` JÁ
  // INCLUI os tokens de raciocínio (ao contrário do Gemini, onde
  // `candidatesTokenCount` e `thoughtsTokenCount` são disjuntos e precisam ser
  // somados). Então `custoDaChamada` não muda e NÃO se soma nada aqui — somar
  // cobraria o raciocínio duas vezes.
  //
  // O que se acrescenta é a PARCELA declarada, no mesmo campo que o lado Gemini
  // já publica, porque é ela que responde à pergunta que a regra do dono faz:
  // quantos tokens o modelo gastou pensando, para decidir o `reasoning_effort`
  // pela medição em vez de pelo limiar teórico (ver `escolherEsforco`).
  const det = u.completion_tokens_details;
  const raciocinio = Number(det?.reasoning_tokens || 0);
  return { ...u, thoughts_tokens: Number.isFinite(raciocinio) ? raciocinio : 0 };
}

/**
 * Acrescenta uma instrução ao FIM do texto da mensagem de usuário.
 *
 * Usado pelo fatiamento, que precisa dizer "extraia da linha X à Y" sem tocar no
 * prompt de sistema — o prefixo tem de continuar byte a byte idêntico em toda
 * chamada para o cache valer (Arquitetura do Sistema/4 Análises e Auditorias/CUSTO_IA.md, alavanca 3). Muda o corpo NO
 * LUGAR e devolve ele, porque quem chama já trabalha sobre uma cópia funda.
 */
export function acrescentarInstrucao(prov, corpo, instrucao) {
  if (!instrucao || !corpo) return corpo;
  if (prov.dialeto === 'gemini') {
    const c = Array.isArray(corpo.contents) ? corpo.contents[corpo.contents.length - 1] : null;
    const p = c && Array.isArray(c.parts) ? c.parts[0] : null;
    if (p && typeof p.text === 'string') p.text += instrucao;
    return corpo;
  }
  const m = Array.isArray(corpo.messages) ? corpo.messages[corpo.messages.length - 1] : null;
  const parte = m && Array.isArray(m.content) ? m.content[0] : null;
  if (parte && typeof parte.text === 'string') parte.text += instrucao;
  return corpo;
}


/**
 * Os ids de modelo que o catálogo do provedor devolveu.
 *
 * As duas respostas têm formas diferentes — `{data:[{id}]}` na OpenAI,
 * `{models:[{name:'models/x'}]}` no Google — e o `models/` do Google é prefixo
 * do RECURSO, não parte do id: mandá-lo de volta no lugar do id monta uma URL
 * com `models/models/x`. Tirar aqui é o que faz a lista ser comparável com o que
 * `MODELOS_POR_PROVEDOR` declara.
 *
 * Devolve sempre um array — resposta inesperada vira lista vazia, e quem chama
 * trata "não consegui listar" separado de "listei e seu modelo não está lá".
 */
export function modelosDoCatalogo(prov, json) {
  if (!json || typeof json !== 'object') return [];
  if (prov.dialeto === 'gemini') {
    const m = Array.isArray(json.models) ? json.models : [];
    return m
      .map((x) => (x && typeof x.name === 'string' ? x.name.replace(/^models\//, '') : null))
      .filter(Boolean);
  }
  const d = Array.isArray(json.data) ? json.data : [];
  return d.map((x) => (x && typeof x.id === 'string' ? x.id : null)).filter(Boolean);
}

/**
 * Os candidatos mais parecidos com um id que não existe.
 *
 * Serve para a mensagem de erro: "gemini-3.5-flash-lite não existe" é meia
 * informação; "não existe, e o que existe é gemini-3.5-flash-lite-002" é a
 * correção inteira. A semelhança é por PREFIXO comum, que é o que erra de
 * verdade num id de modelo (sufixo de versão, geração trocada) — comparar por
 * distância de edição acharia vizinhos que não têm nada a ver.
 */
export function modelosParecidos(alvo, disponiveis, quantos = 8) {
  const a = String(alvo || '').toLowerCase();
  const prefixo = (x) => {
    const b = String(x).toLowerCase();
    let i = 0;
    while (i < a.length && i < b.length && a[i] === b[i]) i += 1;
    return i;
  };
  return (Array.isArray(disponiveis) ? disponiveis : [])
    .map((x) => ({ id: x, p: prefixo(x) }))
    .sort((x, y) => y.p - x.p || x.id.localeCompare(y.id))
    .slice(0, quantos)
    .map((x) => x.id);
}
