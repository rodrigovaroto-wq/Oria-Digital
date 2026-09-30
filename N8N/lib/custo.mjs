// Orçamento de execução — o teto de gasto que o DONO pediu, em código.
//
// Pedido literal (2026-07-31, depois do teste v31): "o sistema não deve gastar
// mais de $3 dólares por execução completa e o teto deve ficar em $5".
//
// São DUAS defesas em camadas diferentes, e a distinção importa:
//
//   • O teto de US$ 5 é configurado NO PROVEDOR (na OpenAI: Settings → Projects
//     → Limits; no Google: o orçamento do projeto no Cloud Billing). É a defesa
//     dura: se este código falhar em qualquer hipótese, o provedor recusa a
//     chamada e o pipeline registra `limite_de_gasto` com causa nomeada — foi
//     exatamente o que aconteceu no v31. Nenhuma linha daqui pode substituir
//     isso, e é bom que não possa: um teto que o próprio sistema controla é um
//     teto que um bug do próprio sistema fura.
//
//     TROCAR DE PROVEDOR NÃO HERDA O TETO. Ele é configuração de conta, não de
//     código: a conta nova começa SEM teto nenhum, e a defesa dura fica ausente
//     até alguém ir lá pôr. É o primeiro item do checklist de troca em
//     Arquitetura do Sistema/4 Análises e Auditorias/CUSTO_IA.md, e é o único que este repositório não consegue conferir.
//
//   • O teto de US$ 3 por execução é ESTE arquivo. Ele existe para o lote nunca
//     CHEGAR no limite do provedor, porque chegar lá é caro de outra forma: no v31
//     o teto cortou no meio do lote e 8 documentos morreram sem extração. A
//     diferença entre US$ 3 e US$ 5 é a folga que garante que quem barra o lote
//     seja este código (que explica o que fazer) e não a API (que só devolve 429).
//
// A decisão é tomada ANTES da primeira chamada, e é um NÃO INTEIRO: ou o lote
// cabe e roda todo, ou não começa. Deliberadamente não existe "roda os que
// cabem": um lote parcial deixa metade dos documentos registrados sem extração
// e a outra metade sem registro nenhum, e distinguir os dois casos depois é o
// tipo de trabalho que a doutrina (Arquitetura do Sistema/1 Visão e Doutrina/01) manda não criar. Recusar antes de
// gastar não custa nada e diz o que fazer.

import { provedorAtivo, provedor, modeloRaciocina } from './provedor.mjs';

// Preço, US$ por MILHÃO de tokens, POR PROVEDOR.
// ⚠️ Preço de terceiro muda sem avisar e este arquivo não tem como saber. Se a
// conta divergir do que `custoDaChamada` reporta, é AQUI que se corrige — e o
// sintoma é o orçamento parecer folgado enquanto a fatura não é.
//
// `entrada_cache` é o preço do token de entrada que o provedor serviu do cache
// de prefixo. Na OpenAI é metade do cheio e está na página de preço; no Google é
// um quarto. Os dois estão DECLARADOS aqui, não medidos por nós — e é por isso
// que `custoDaChamada` só o aplica quando a resposta DIZ quantos tokens vieram
// do cache, em vez de supor que vieram.
export const PRECOS_POR_PROVEDOR = {
  openai: {
    // O MODELO ATIVO desde 11/09/2026 (decisão do dono: "troque todos os
    // modelos do sistema para o GPT-5.6 Luna").
    //
    // Preço do CONTEXTO CURTO, conferido na página oficial da OpenAI em
    // 11/09/2026. A mesma página devolveu `gpt-4o-mini` a 0,15/0,075/0,6 —
    // idêntico ao que este arquivo já declarava — e é esse cruzamento que prova
    // que a unidade lida é a mesma (US$ por MILHÃO), não uma tabela de outro
    // formato.
    //
    // O QUE ESTA LINHA NÃO COBRE, e é deliberado: acima de 272 mil tokens de
    // ENTRADA a OpenAI cobra 2× a entrada e 1,5× a saída, na requisição
    // inteira. Uma linha só de preço não sabe expressar isso, e inventar uma
    // média entre as duas faixas seria declarar um preço que não existe em
    // faixa nenhuma. Fica o número da faixa em que este sistema roda: a maior
    // entrada medida aqui é um PDF de 20 páginas (~20 mil tokens de imagem,
    // `Arquitetura do Sistema/4 Análises e Auditorias/CUSTO_IA.md`), 13× abaixo
    // do degrau. Documento que passe de 272 mil tokens sai mais caro do que
    // esta tabela diz — e o lugar de tratar isso é aqui, quando existir um.
    'gpt-5.6-luna': { entrada: 0.20, entrada_cache: 0.02, saida: 1.20 },
    'gpt-4o': { entrada: 2.5, entrada_cache: 1.25, saida: 10.0 },
    'gpt-4o-mini': { entrada: 0.15, entrada_cache: 0.075, saida: 0.6 },
  },
  google: {
    'gemini-3.5-flash-lite': { entrada: 0.30, entrada_cache: 0.075, saida: 2.50 },
    'gemini-2.5-flash-lite': { entrada: 0.10, entrada_cache: 0.025, saida: 0.40 },
  },
};

// A tabela do provedor ATIVO. O nome não mudou de propósito: `custoDaChamada` e
// a cópia dele que roda dentro do nó Code do n8n leem esta constante, e um
// provedor a mais no catálogo não deve reescrever nenhum dos dois.
export const PRECO_USD_POR_MILHAO = PRECOS_POR_PROVEDOR[provedorAtivo()];

// Teto por execução completa (pedido do dono). Menor que o teto da OpenAI de
// propósito — ver o comentário do topo.
export const TETO_EXECUCAO_USD = 3;

// ---------------------------------------------------------------------------
// OS DOIS MODELOS DO PIPELINE — e por que eles moram AQUI e não no build
// ---------------------------------------------------------------------------
//
// Eles estavam em `build-workflow.mjs`, que é quem os escreve nos nós. Mudaram
// de casa porque o ORÇAMENTO passou a depender deles: o preço da chamada de
// classificação entra na conta do lote (ver `pesoDaChamadaDeClassificacao`), e
// um preço derivado de um modelo declarado em outro arquivo é a mesma cópia à
// mão que este repositório já viu divergir três vezes. O build importa daqui.
//
// NA OPENAI eles eram DOIS: `gpt-4o-mini` classificava e `gpt-4o` extraía. A
// separação nasceu de uma diferença de preço de 17× entre os dois, e ela tinha
// rede — o `diagnostico` da extração, que rodava no modelo forte, confere
// tipo/entidade/período contra o conteúdo e abre pendência quando o barato erra.
//
// NO GOOGLE eles são UM SÓ, e não é economia de linha de código: a linha
// Flash-Lite já entra no preço em que o modelo "barato" da OpenAI entrava, então
// a razão que justificava dois desapareceu. Rebaixar a classificação para uma
// geração anterior economizaria ~US$ 0,005 no book inteiro (a classificação é
// 0,4% da conta medida) e reintroduziria o único erro que a separação sempre
// custou: um tipo errado que só o diagnóstico pega, uma etapa adiante.
//
// A ESTRUTURA CONTINUA DE DOIS, e é de propósito. `pesoDaChamadaDeClassificacao`,
// o orçamento e os nós do workflow seguem lendo duas constantes distintas — se
// um dia valer separar de novo, é uma linha aqui, e não um refatoramento.
// NA OPENAI, DESDE 11/09/2026, ELES VOLTARAM A SER UM SÓ — e pelo mesmo motivo
// que os unificou no Google: o Luna entra no preço em que o modelo "barato"
// entrava (US$ 0,20 de entrada contra os US$ 0,15 do `gpt-4o-mini`), então a
// diferença de 17× que justificava dois modelos deixou de existir. O que separa
// as duas chamadas agora é o ESFORÇO DE RACIOCÍNIO, não o modelo — ver
// `ESFORCO_POR_PAPEL` abaixo.
export const MODELOS_POR_PROVEDOR = {
  openai: { classificacao: 'gpt-5.6-luna', extracao: 'gpt-5.6-luna' },
  google: { classificacao: 'gemini-3.5-flash-lite', extracao: 'gemini-3.5-flash-lite' },
};

export const MODELO_CLASSIFICACAO = MODELOS_POR_PROVEDOR[provedorAtivo()].classificacao;
export const MODELO_EXTRACAO = MODELOS_POR_PROVEDOR[provedorAtivo()].extracao;

// ---------------------------------------------------------------------------
// O ESFORÇO DE RACIOCÍNIO — a regra do dono, em código, e o que ela NÃO decide
// ---------------------------------------------------------------------------
//
// O Luna é modelo de RACIOCÍNIO. Isso acrescenta uma grandeza que nenhum modelo
// anterior deste sistema tinha: tokens que o modelo gasta PENSANDO, cobrados
// como SAÍDA e gastos ANTES da primeira chave do JSON. É o mesmo fato que o
// lado Google já tinha aprendido com `thoughtsTokenCount` (ver `usoDaChamada`
// em `provedor.mjs`) — aqui ele vem em `completion_tokens_details.reasoning_tokens`.
//
// REGRA DO DONO (11/09/2026), literal:
//   • extração:     se `medium` gastar MAIS DE 50% a mais que `low`  → `low`; senão `medium`.
//   • classificação: usar `low` se gastar MENOS DE 25% a mais que `none`; senão `none`.
//
// `escolherEsforco` é a regra, e só a regra. Ela NÃO adivinha quantos tokens de
// raciocínio cada nível gasta — esse número é do modelo, não nosso, e só a
// primeira rodada real o mede. O que ela faz é responder à pergunta que DÁ para
// responder sem medir: **a partir de quantos tokens de raciocínio o nível mais
// caro viola a regra?** Esse limiar é aritmética pura sobre o perfil de token
// MEDIDO deste repositório, e é ele que torna a decisão auditável em vez de
// opinião.
// Os valores que a OpenAI aceita em `reasoning_effort` (Chat Completions),
// conferidos na referência da API em 11/09/2026. Declarados para o teste poder
// reprovar um esforço que não existe — um valor inventado aqui é 400 na chamada.
export const ESFORCOS = ['none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'];

// O perfil de token MEDIDO neste repositório, por documento.
// Fonte: `Arquitetura do Sistema/4 Análises e Auditorias/CUSTO_IA.md` — o book de
// 14 documentos/20 páginas somou ~49.000 tokens de entrada e ~106.000 de saída
// na extração, e a classificação devolve ~120 tokens com a MESMA entrada.
// São medições, não estimativas: quem mudar o formato de saída mexe aqui.
// (`saidaClassificacao` repete de propósito o valor de
// `TOKENS_SAIDA_CLASSIFICACAO`, declarado mais abaixo neste arquivo; um teste
// trava os dois iguais, para o espelho não poder divergir em silêncio.)
export const PERFIL_MEDIDO = {
  entradaPorDocumento: 3500, // 49.000 ÷ 14
  saidaExtracao: 7571, // 106.000 ÷ 14
  saidaClassificacao: 120,
};

// A folga que cada papel tolera, pela regra do dono.
export const FOLGA_EXTRACAO = 0.5; // medium só vale se não passar de +50% do low
export const FOLGA_CLASSIFICACAO = 0.25; // low só vale se não passar de +25% do none

/**
 * Quantos tokens de raciocínio o nível CARO pode gastar antes de violar a regra.
 *
 * Sai de `custo(caro) <= (1 + folga) * custo(barato)`, com
 * `custo = entrada*pe + (saida + raciocinio)*ps`. Tomando o pior caso do barato
 * (raciocínio zero — supor que ele também pensa só AFROUXARIA o limiar, e
 * limiar afrouxado por suposição é o que este projeto não faz):
 *
 *     (S + r)*ps  <=  (1+folga)*(E*pe + S*ps) - E*pe
 *              r  <=  folga * (E*pe/ps + S)
 *
 * O termo `E*pe/ps` é a entrada convertida para "tokens de saída equivalentes":
 * é por isso que uma chamada com entrada grande e saída minúscula (a
 * classificação) quase não tem folga — não há saída sobre a qual a folga incida.
 *
 * Devolve `null` quando o preço do modelo é desconhecido: sem preço não há
 * limiar, e um limiar inventado num arquivo de orçamento é pior que nenhum.
 */
export function limiarDeRaciocinio({ entrada, saida, folga, preco }) {
  // `!Number.isFinite(...)` e NAO `<= 0`: o Sonar sugere a "operação oposta"
  // (`preco.saida <= 0`), e ela seria ERRADA aqui. Preço ausente vira `NaN`, e
  // `NaN <= 0` é FALSO — o modelo sem preço passaria pela guarda e a divisão
  // devolveria `NaN` como se fosse um limiar. `!(x > 0)` já rejeitava NaN por
  // acidente da semântica; isto rejeita por INTENÇÃO declarada.
  if (!preco || !Number.isFinite(preco.saida) || preco.saida <= 0) return null;
  return folga * ((entrada * preco.entrada) / preco.saida + saida);
}

/**
 * O esforço de raciocínio de um papel, pela regra do dono.
 *
 * `raciocinioMedido` é quantos tokens de raciocínio o nível CARO gasta de fato,
 * e só a rodada real o sabe. Ausente (`null`), a função NÃO chuta: devolve o
 * nível barato e diz, no `porque`, que a condição do nível caro não foi provada.
 * É a regra 1 deste projeto aplicada a uma decisão de configuração — "não medi"
 * não pode sair vestido de "medi e deu isto".
 */
export function escolherEsforco({
  barato, caro, entrada, saida, folga, preco, raciocinioMedido = null,
}) {
  const limiar = limiarDeRaciocinio({ entrada, saida, folga, preco });
  if (limiar == null) {
    return { esforco: barato, limiar: null, porque: 'preço do modelo desconhecido — sem limiar' };
  }
  const arredondado = Math.round(limiar);
  if (raciocinioMedido == null) {
    return {
      esforco: barato,
      limiar: arredondado,
      porque: `"${caro}" só cabe na regra se gastar até ${arredondado} token(s) de `
        + `raciocínio por chamada, e isso ainda NÃO foi medido nesta conta`,
    };
  }
  const cabe = raciocinioMedido <= limiar;
  return {
    esforco: cabe ? caro : barato,
    limiar: arredondado,
    porque: cabe
      ? `"${caro}" medido em ${raciocinioMedido} token(s) de raciocínio, dentro do limiar ${arredondado}`
      : `"${caro}" medido em ${raciocinioMedido} token(s) de raciocínio, acima do limiar ${arredondado}`,
  };
}

/**
 * O esforço de cada papel, resolvido para o provedor ativo.
 *
 * Provedor sem raciocínio (o Google, aqui) devolve `null` nos dois — mandar
 * `reasoning` para quem não tem é campo desconhecido, e campo desconhecido é
 * 400 na chamada inteira, não um aviso.
 */
export function esforcosDoProvedor(
  modeloExtracao = MODELO_EXTRACAO,
  modeloClassificacao = MODELO_CLASSIFICACAO,
  tabela = PRECO_USD_POR_MILHAO,
  medido = {},
) {
  if (!modeloRaciocina(modeloExtracao) && !modeloRaciocina(modeloClassificacao)) {
    return { extracao: null, classificacao: null };
  }
  return {
    extracao: escolherEsforco({
      barato: 'low',
      caro: 'medium',
      entrada: PERFIL_MEDIDO.entradaPorDocumento,
      saida: PERFIL_MEDIDO.saidaExtracao,
      folga: FOLGA_EXTRACAO,
      preco: tabela[modeloExtracao],
      raciocinioMedido: medido.extracao ?? null,
    }),
    classificacao: escolherEsforco({
      barato: 'none',
      caro: 'low',
      entrada: PERFIL_MEDIDO.entradaPorDocumento,
      saida: PERFIL_MEDIDO.saidaClassificacao,
      folga: FOLGA_CLASSIFICACAO,
      preco: tabela[modeloClassificacao],
      raciocinioMedido: medido.classificacao ?? null,
    }),
  };
}

// ---------------------------------------------------------------------------
// O PESO DA SEGUNDA CHAMADA — o defeito de estimativa que restava
// ---------------------------------------------------------------------------
//
// O orçamento contava a chamada de CLASSIFICAÇÃO como se ela custasse o mesmo
// que uma extração. Não custa, e a diferença é grande: medido no book-canastra,
// as 19 classificações somaram **US$ 0,0893** contra **US$ 1,32** das 38
// extrações — US$ 0,0047 contra US$ 0,035 em média, ou seja **13%**. A razão é
// física: as duas mandam o MESMO PDF, mas a classificação devolve um objeto de
// ~120 tokens e a extração devolve centenas de linhas — e a saída responde por
// ~75% da conta (medição do book, `docs/CUSTO_OPENAI.md`).
//
// Cobrar cheio inflava a estimativa do book em 46% (fator 1,5 em vez de 1,03) e
// era o que faltava para o lote de 35 caber com folga em vez de raspar o teto.
//
// A conta do peso, com as duas parcelas declaradas:
//
//   peso = PARCELA_ENTRADA_NA_CHAMADA × (preço de entrada do modelo de
//          classificação ÷ preço de entrada do modelo de extração)
//
// `PARCELA_ENTRADA_NA_CHAMADA = 0,30` é a fatia da conta que é ENTRADA (medido:
// 25%; 0,30 é a margem). O segundo termo é 1 quando os dois modelos são iguais e
// 0,06 com a classificação em `gpt-4o-mini`. O piso de 0,05 existe para que a
// segunda chamada NUNCA saia de graça: modelo barato não é modelo grátis, e um
// lote de mil documentos mal nomeados tem de pesar alguma coisa.
export const PARCELA_ENTRADA_NA_CHAMADA = 0.3;
export const PESO_MINIMO_CLASSIFICACAO = 0.05;

export function pesoDaChamadaDeClassificacao(
  modeloClassificacao = MODELO_CLASSIFICACAO,
  modeloExtracao = MODELO_EXTRACAO,
) {
  const c = PRECO_USD_POR_MILHAO[modeloClassificacao];
  const e = PRECO_USD_POR_MILHAO[modeloExtracao];
  // Modelo que não está na tabela de preço é modelo cujo custo não se conhece —
  // e desconhecido cobra CHEIO. Errar para o lado seguro é o projeto daqui.
  if (!c || !e || !(e.entrada > 0)) return 1;
  return Math.max(PESO_MINIMO_CLASSIFICACAO, PARCELA_ENTRADA_NA_CHAMADA * (c.entrada / e.entrada));
}

// Versão do orçamento, e ela vai na MENSAGEM de recusa de propósito.
//
// Por que existe: em 12/08/2026 o dono reexecutou o lote depois de a estimativa
// por tamanho ter entrado no repositório e recebeu a MESMA recusa antiga
// ("51 chamadas ≈ US$ 7,65") — porque o n8n roda o JSON que foi IMPORTADO, e o
// merge no `main` não reimporta nada. Da tela, código novo e código velho têm a
// mesma aparência: os dois recusam. Com a versão na mensagem, "o n8n está com o
// workflow velho" deixa de ser hipótese e vira leitura.
//
// SOBE PARA v4 NA TROCA DE PROVEDOR, e é o uso mais importante que ela já teve:
// os três números da calibração mudaram de ordem de grandeza (US$ 0,20 → 0,055
// por chamada), então um n8n rodando o JSON velho recusa lotes que o código novo
// aceita — e recusa com uma mensagem que parece a mesma. Com a versão na
// mensagem, "o n8n está com o workflow velho" volta a ser leitura, não hipótese.
// v5: o proxy por byte e o piso por chamada foram reescalados para o provedor
// ativo (13/09/2026) — a troca de 11/09 os tinha deixado no preço do Google. A
// versão carimba a MENSAGEM DE RECUSA, e é o que responde, da tela do n8n, se o
// workflow que está no ar é o que tem a conta corrigida.
export const VERSAO_ORCAMENTO = 'v5 (2026-09-13)';

// Custo estimado de UM documento, usado só para decidir se o lote cabe antes de
// existir qualquer medição.
//
// De onde saiu o número original (docs/CUSTO_OPENAI.md): ~1k tokens de entrada
// por página, documento típico de ~10 páginas + ~2,5k do prompt de sistema ≈
// 12,5k de entrada = US$ 0,031; saída de extração densa até MAX_OUTPUT_TOKENS/2
// ≈ 8k = US$ 0,08. Soma ≈ US$ 0,11 — e ficou em 0,15 para o estimador errar para
// o lado SEGURO (barrar um lote que caberia é um aviso; deixar passar um que não
// cabe é o v31 de novo).
//
// RECALIBRADO DE 0,15 PARA 0,20 EM 07/08/2026, POR MEDIÇÃO. Este comentário
// pedia justamente isso ("é com ele que este número deve ser recalibrado"), e a
// medição chegou com o book-canastra: `N8N/medir-custo-book.mjs` mede o custo de
// cada documento a partir de páginas e linhas contadas no PDF gerado, e um dos
// 38 — o livro razão, 3 páginas e 461 linhas — deu **US$ 0,1725 por chamada**,
// ACIMA dos 0,15. Ou seja: existia documento realista que custava mais do que o
// número que sustenta o teto, e num lote só dele a promessa de "no máximo US$ 3
// por execução" seria quebrada em ~15%.
//
// O que 0,20 muda na prática: o lote máximo cai de 20 para 15 chamadas. É o
// preço de a recusa continuar acontecendo AQUI (com mensagem que diz o que
// fazer) e não na API (que só devolve 429 no meio do lote).
//
// O limite que ele NÃO resolve, e que fica declarado: o estimador é PLANO — não
// sabe quantas páginas nem quantas linhas o documento tem. Acima de ~550 linhas
// extraíveis o custo real volta a passar dele. Enquanto for plano, a defesa dura
// continua sendo o teto do projeto configurado no provedor.
//
// RECALIBRADO DE 0,20 PARA 0,055 EM 24/08/2026, NA TROCA DE PROVEDOR, E PELA
// MESMA MEDIÇÃO. O mesmo `medir-custo-book.mjs` sobre o mesmo book-canastra, só
// que com a tabela de preço do provedor novo: o documento mais caro dos 38 — o
// livro razão, 3 páginas e 461 linhas, o mesmo de sempre — passou de US$ 0,1725
// para **US$ 0,0459**, e o lote inteiro de US$ 1,2932 para **US$ 0,2821**.
//
// 0,055 é 1,2× o documento mais caro medido, que é a MESMA folga que 0,20 tinha
// sobre 0,1725. Deixar 0,20 de pé teria sido pior que um número velho: seria um
// guarda cego recusando lotes de quatro vezes o tamanho que o teto comporta, e
// "o sistema não deixa rodar" é indistinguível de "o sistema está quebrado".
export const CUSTO_ESTIMADO_DOC_USD = 0.055;

// ---------------------------------------------------------------------------
// ESTIMATIVA POR TAMANHO — o que substitui o número plano quando os bytes são
// conhecidos, que é sempre que o arquivo veio pelo formulário.
// ---------------------------------------------------------------------------
//
// POR QUE ISTO EXISTE, com o número que o justifica. O estimador plano recusou
// um lote REAL de 35 documentos do book-canastra dizendo "≈ US$ 7,65, acima do
// teto de US$ 3". O mesmo book inteiro — 38 documentos, 57 chamadas — foi MEDIDO
// por `N8N/medir-custo-book.mjs` em **US$ 1,41**. O estimador errou por 5,4× e
// barrou um lote que cabia com folga de mais da metade do teto.
//
// Errar para o lado seguro é o projeto do estimador, e continua sendo. Errar por
// 5× é outra coisa: é impedir o uso do sistema para proteger um orçamento que
// nunca esteve em risco. E o custo disso não é teórico — foi o que travou o
// primeiro teste de ponta a ponta com o book difícil.
//
// A CALIBRAÇÃO, medida sobre os 38 documentos do book-canastra:
//
//   • custo agregado real: US$ 1,4117 para 257.150 bytes ponderados por chamada
//     (o documento mal nomeado paga o PDF duas vezes e conta duas vezes aqui)
//     = US$ 5,76 por MB;
//   • `CUSTO_POR_MB_USD` fica em **10,5**, ou seja 1,8× o agregado medido. A
//     margem cobre um lote quase duas vezes mais denso que o book — e o book já
//     é o material mais difícil que existe no repositório;
//   • `CUSTO_MINIMO_CHAMADA_USD` existe porque toda chamada paga o prompt de
//     sistema e pelo menos uma página de imagem, independente do tamanho do
//     arquivo. Sem ele, um lote de PDFs minúsculos estimaria quase zero.
//
// O QUE ESTA CALIBRAÇÃO ACERTA, e é o teste que importa: o book de 38 documentos
// estima ≈ US$ 2,5 (real 1,41) e PASSA; um lote de 35 cópias do documento mais
// denso do book — o livro razão, 461 linhas — estima ≈ US$ 3,7 e é RECUSADO,
// enquanto custaria US$ 6,04 de verdade. Ou seja: passa o caso realista e barra
// o caso caro, que é exatamente o que o teto existe para fazer e o que o número
// plano não conseguia fazer nos dois sentidos ao mesmo tempo.
//
// O LIMITE QUE FICA DECLARADO: bytes de PDF não são tokens. Um PDF de texto
// dá mais linhas por byte que um escaneado, e a razão entre os extremos medidos
// no book é de 4× por byte. A margem de 1,8× cobre a média de um lote, não o
// pior documento isolado — para isso continua valendo a defesa dura, o teto de
// US$ 5 do projeto na OpenAI. Um lote que estimasse exatamente no teto de US$ 3
// e fosse inteiro do tipo mais denso custaria ~US$ 4,8: cabe no teto duro.
//
// OS DOIS NÚMEROS ABAIXO FORAM ESCALADOS EM 24/08/2026, na troca de provedor.
// A calibração ACIMA continua valendo inteira — ela é sobre a relação entre
// bytes e tokens, que é física do PDF e não muda com quem cobra. O que mudou foi
// o PREÇO do token, e escalar (em vez de recalibrar do zero) preserva a margem
// que foi calibrada contra dinheiro de verdade.
//
// E A ESCOLHA DA RAZÃO IMPORTA, porque existem DUAS e elas não são iguais:
//
//   • o lote inteiro do book caiu 0,218× (US$ 1,2932 → US$ 0,2821);
//   • o documento mais DENSO dele caiu 0,266× (US$ 0,1725 → US$ 0,0459).
//
// Elas divergem porque o preço da SAÍDA caiu menos que o da entrada, e documento
// denso é o que gasta saída. Um escalar só não preserva as duas propriedades, e
// entre elas a escolha não é ambígua: escalar pelo AGREGADO (0,218) fazia o lote
// homogêneo denso — o caso que o teto existe para barrar — passar a ser ACEITO.
// Trocar "recusa lote que caberia" por "aceita lote que não cabe" é exatamente o
// v31 de novo, e é o erro caro. Vale a razão do documento denso.
//
//   10,5 × 0,266 = 2,79 → 2,80      0,012 × 0,266 = 0,0032
//
// O CUSTO DA ESCOLHA, declarado: o guarda por byte fica ~2× acima do custo real
// de um lote típico (era ~1,45×). Continua muito longe de barrar trabalho — o
// book inteiro estima US$ 0,30 contra um teto de US$ 3 (era US$ 0,58 enquanto o
// número de agosto ficou de pé — ver a reescala de 13/09 abaixo) —, e quem decide o lote
// típico hoje é a estimativa por CONTEÚDO.
//
// A FRASE "QUE ERRA 3%" SAIU DAQUI EM 10/09/2026, E ELA ERA FALSA PARA O
// PROVEDOR ATUAL. Os 3% vinham de UMA rodada do book-vertentes na era OpenAI
// (fatura US$ 0,90 contra US$ 0,87 estimados). Contra o Google, medido em
// `lote_execucao`, a estimativa por conteúdo ficava ABAIXO do real em todas as
// quatro rodadas que gastaram: 1,49× · 1,46× · 1,42× · 1,37×. A causa era o
// cache assumido e não entregue, corrigida em `custoEstimadoPorConteudo`.
//
// E OS DOIS NÚMEROS FORAM ESCALADOS DE NOVO EM 13/09/2026, PELA MESMA RAZÃO E
// COM ATRASO DE DOIS DIAS — a troca de provedor de 11/09/2026 (Google
// `gemini-3.5-flash-lite` → OpenAI `gpt-5.6-luna`) atualizou a tabela de preço,
// os modelos e a cadência, e DEIXOU ESTES DOIS PARA TRÁS. É o "espelho que fica
// para trás" do `CLAUDE.md`, desta vez sobre uma constante de dinheiro: o proxy
// continuou cobrando preço de Google num lote que a OpenAI cobra.
//
// O EFEITO MEDIDO, e ele chegou ao dono: o lote de 44 documentos da AMO (14,4 MB)
// foi recusado em US$ 52,39 contra o teto de US$ 3. Parte disso é o defeito de
// REGIME (o proxy foi calibrado sobre PDF de 4,8 KB do `reportlab` e aplicado a
// PDF de cliente de 335 KB — 69× mais bytes para o mesmo conteúdo), que esta
// fatia NÃO corrige; o que ela corrige é a parcela que é preço velho.
//
// A razão, pelo MESMO método que 24/08 documenta (a do documento DENSO, nunca a
// agregada, e entre as candidatas a MAIOR — escalar de menos recusa lote que
// cabe, escalar de mais aceita lote que não cabe, e o segundo é o v31):
//
//   perfil denso (20 páginas de imagem, 7.571 tokens de saída):
//     google (0,30/2,50) US$ 0,024927 → luna (0,20/1,20) US$ 0,013085   razão 0,5249
//   perfil medido do book (3.500 entrada / 7.571 saída):                razão 0,4898
//   só entrada 0,6667 · só saída 0,4800
//
//   2,80 × 0,5249 = 1,4697 → 1,48      0,0032 × 0,5249 = 0,00168 → 0,0017
//
// (o produto é arredondado para CIMA, como 24/08 arredondou 2,79 → 2,80: o lado
// seguro de um guarda de teto é o de cobrar de mais.)
//
// A MARGEM CALIBRADA SOBREVIVE À TROCA, e é o que o invariante novo trava, com
// os dois números MEDIDOS por `N8N/medir-custo-book.mjs` nesta sessão contra o
// provedor ATIVO: o book-canastra inteiro custa US$ 0,1380 (era US$ 0,2821 no
// Google) e o proxy por byte estimava US$ 0,56 — **4,06× o real**, contra os
// ~2× que a calibração declara. Com 1,48 ele estima US$ 0,2957, ou 2,14×. O
// número velho não era só velho: ele tinha DOBRADO a margem sem que ninguém
// escolhesse isso.
export const CUSTO_POR_MB_USD = 1.48;
export const CUSTO_MINIMO_CHAMADA_USD = 0.0017;

const BYTES_POR_MB = 1024 * 1024;

// ---------------------------------------------------------------------------
// O DEFEITO DO PROXY ÚNICO — `CUSTO_POR_MB_USD` aplicado a QUALQUER arquivo
// ---------------------------------------------------------------------------
//
// `CUSTO_POR_MB_USD` é um proxy por BYTE calibrado sobre PDF (a calibração
// está no comentário acima, 10,5 × 0,266): ele existe porque um PDF vai ao
// modelo como IMAGEM (`TOKENS_POR_PAGINA_IMAGEM`), e bytes de PDF não dizem
// quase nada sobre tokens. Até 12/09/2026 esse mesmo proxy era aplicado a
// QUALQUER arquivo, inclusive TEXTO PURO — onde a razão byte→token não é um
// proxy nenhum, é ARITMÉTICA (`CARACTERES_POR_TOKEN`).
//
// MEDIDO, com o modelo ativo (`gpt-5.6-luna`, entrada US$0,20/M) e
// `CARACTERES_POR_TOKEN = 4`:
//
//   2 MB de texto  -> proxy de PDF = US$  5,60 | entrada real = US$ 0,105 | 53×
//   40 MB de texto -> proxy de PDF = US$112,00 | entrada real = US$ 2,097 | 53×
//
// O EFEITO EM PRODUÇÃO: um dono tentou subir 2 arquivos de texto e o
// `Orcamento do Lote` recusou dizendo "US$ 5,60 contra o teto de US$ 3" — um
// número 53× o real. Um guarda de teto que recusa lote que cabe é o defeito
// v31 pelo outro lado, e é exatamente o que o cabeçalho de `orcamentoDoLote`
// já descreve.
//
// A CORREÇÃO: a razão byte→token é propriedade do FORMATO, não do arquivo.
// `custoEstimadoPorTamanho` passa a receber `formato` (opcional, string —
// aceita as mesmas categorias que `PADRAO_MIME` em `build-workflow.mjs` usa:
// 'csv', 'xml', um mimetype `text/...`, ou 'texto' direto) e escolhe a conta:
//
//   • PDF/imagem (ou formato ausente): continua `CUSTO_POR_MB_USD` — a
//     calibração É SOBRE ISTO, e não muda.
//   • texto (`ehFormatoDeTexto`): sem proxy — `bytes / CARACTERES_POR_TOKEN`
//     tokens de entrada × preço de entrada do modelo de extração ativo
//     (`custoPorMbDeTextoUSD`), com a MESMA margem que a estimativa por
//     CONTEÚDO usa (`MARGEM_ORCAMENTO_CONTEUDO = 1,25`), não o 1,8× do PDF —
//     aqui não há calibração por incerteza de formato para justificar 1,8×,
//     só a folga que o resto do arquivo já aplica a uma conta por token.
//   • xlsx/xls: NÃO é texto (o byte comprimido de um ZIP não é caractere —
//     `CARACTERES_POR_TOKEN` não vale) nem é imagem, e este repositório não
//     tem medição própria dele. Suposição declarada: fica no MESMO proxy do
//     PDF, por ser mais perto de "densidade de informação por byte de um
//     binário comprimido" do que de "texto solto". Quem quiser um número
//     melhor tem de MEDIR um book de planilhas primeiro.
//
// O QUE NÃO MUDA: sem `formato` (ou com um valor desconhecido), o
// comportamento é o de sempre — o caminho conservador. Compatibilidade com
// quem já chama `custoEstimadoPorTamanho(bytes)` continua total.
export const FORMATOS_DE_TEXTO = ['csv', 'xml', 'texto', 'txt', 'text'];

/** `formato` é texto puro (não PDF, não imagem, não planilha)? */
export function ehFormatoDeTexto(formato) {
  const f = typeof formato === 'string' ? formato.trim().toLowerCase() : '';
  if (!f) return false;
  if (FORMATOS_DE_TEXTO.includes(f)) return true;
  // Aceita também as strings que `PADRAO_MIME` (build-workflow.mjs) usa para
  // reconhecer texto: um mimetype `text/...` inteiro, ou `.../xml` no fim.
  return f.startsWith('text/') || f.endsWith('/xml') || f.endsWith('+xml');
}

/**
 * Custo por MB de ENTRADA de texto puro, no preço do modelo de extração do
 * provedor ativo (ou informado). Diferente de `CUSTO_POR_MB_USD`, não há
 * calibração aqui: a razão byte→token de texto puro É `CARACTERES_POR_TOKEN`,
 * então o custo por MB sai direto do preço do modelo.
 *
 * NÃO cobra a SAÍDA por byte — de propósito. A saída de um documento de texto
 * depende de quantos NÚMEROS ele tem, não de quantos BYTES, e não existe uma
 * razão byte→saída para texto do jeito que existe para entrada (o mesmo
 * motivo pelo qual `CUSTO_POR_MB_USD`, para PDF, também é dominado pela
 * entrada de imagem). Quem cobre a saída mínima de uma chamada é o piso
 * `CUSTO_MINIMO_CHAMADA_USD`, aplicado por `custoEstimadoPorTamanho`.
 *
 * Devolve `null` quando o preço do modelo é desconhecido — mesma regra do
 * resto do arquivo: sem preço não há conta, e uma conta inventada é pior que
 * nenhuma (quem chama decide o que fazer com `null`).
 */
export function custoPorMbDeTextoUSD(tabela = PRECO_USD_POR_MILHAO, modelo = MODELO_EXTRACAO) {
  const preco = tabela[modelo];
  if (!preco || !Number.isFinite(preco.entrada) || preco.entrada <= 0) return null;
  const tokensPorMb = BYTES_POR_MB / CARACTERES_POR_TOKEN;
  return (tokensPorMb * preco.entrada) / 1_000_000;
}

/**
 * Custo estimado de UMA chamada sobre um arquivo de `bytes`.
 * Devolve `null` quando o tamanho não é conhecido — quem chama decide o que
 * fazer com isso, e o que NÃO se pode fazer é tratar desconhecido como zero.
 *
 * `formato` é OPCIONAL, e a ausência preserva o comportamento de sempre (o
 * proxy conservador de PDF) — ver o comentário acima desta função para a
 * conta por formato.
 */
export function custoEstimadoPorTamanho(bytes, formato = null) {
  const b = Number(bytes);
  if (!Number.isFinite(b) || b <= 0) return null;
  const mb = b / BYTES_POR_MB;

  if (ehFormatoDeTexto(formato)) {
    const porMb = custoPorMbDeTextoUSD();
    // Preço do modelo de extração desconhecido: sem base própria para a conta
    // de texto, cai no proxy conservador — nunca em zero.
    if (porMb == null) return Math.max(CUSTO_MINIMO_CHAMADA_USD, mb * CUSTO_POR_MB_USD);
    return Math.max(CUSTO_MINIMO_CHAMADA_USD, mb * porMb * MARGEM_ORCAMENTO_CONTEUDO);
  }

  return Math.max(CUSTO_MINIMO_CHAMADA_USD, mb * CUSTO_POR_MB_USD);
}

/**
 * Bytes de um binário do n8n, na ordem do mais confiável para o menos.
 *
 * O n8n guarda o binário de dois jeitos e o formato do metadado muda com o modo:
 * em memória, `data` é base64 (e o tamanho real sai dele); em modo filesystem,
 * `data` é um ponteiro e só resta `fileSize`, que vem FORMATADO ("10.79 kB").
 * Ler só um dos dois funciona no ambiente de quem escreveu e falha no outro.
 */
export function bytesDoBinario(bin) {
  if (!bin) return null;
  if (Number.isFinite(Number(bin.fileSize))) return Number(bin.fileSize);
  if (typeof bin.data === 'string' && !bin.id) {
    // base64 → bytes, sem alocar o buffer inteiro só para medir.
    const s = bin.data.length;
    const pad = bin.data.endsWith('==') ? 2 : bin.data.endsWith('=') ? 1 : 0;
    const n = Math.floor((s * 3) / 4) - pad;
    if (n > 0) return n;
  }
  if (typeof bin.fileSize === 'string') {
    const m = /^\s*([\d.,]+)\s*([kmg]?b)\s*$/i.exec(bin.fileSize);
    if (m) {
      const n = Number(m[1].replace(',', '.'));
      const mult = { b: 1, kb: 1024, mb: 1024 * 1024, gb: 1024 * 1024 * 1024 }[m[2].toLowerCase()];
      if (Number.isFinite(n) && mult) return Math.round(n * mult);
    }
  }
  return null;
}

// Custo REAL de uma chamada, a partir do bloco `usage` da resposta.
// Não estima nada: se o `usage` não vier, devolve null em vez de chutar — um
// custo inventado num relatório de custo é pior que um campo vazio.
//
// O `usage` chega aqui SEMPRE na forma da OpenAI, inclusive vindo do Google: a
// tradução acontece na fronteira (`usoDaChamada`, em lib/provedor.mjs), e é o
// que mantém esta função como o único lugar do sistema que faz conta de
// dinheiro — em vez de dois formatos de uso espalhados.
//
// `tabela` existe para o teste poder cobrar um modelo que não é o do provedor
// ativo. Em produção nunca é passada: o padrão é a tabela do ativo, que é a
// mesma constante que o nó Code do n8n recebe embutida.
export function custoDaChamada(usage, modelo, tabela = PRECO_USD_POR_MILHAO) {
  const p = tabela[modelo];
  if (!p || !usage) return null;
  const entradaTotal = Number(usage.prompt_tokens ?? usage.input_tokens ?? 0);
  const saida = Number(usage.completion_tokens ?? usage.output_tokens ?? 0);
  if (!Number.isFinite(entradaTotal) || !Number.isFinite(saida)) return null;
  // Tokens em cache custam menos, e esta função está CERTA: ela só aplica o
  // desconto quando a resposta DIZ quantos vieram do cache. É por isso que o
  // custo gravado bate com a tabela de preços até a sexta casa nas quatro
  // rodadas reais que gastaram.
  //
  // O comentário aqui dizia "o cache pega". MEDIDO: não pega. `tokens_cache = 0`
  // nas cinco rodadas de `lote_execucao` com o provedor Google. A frase ficava
  // ao lado de um código correto e induzia a acreditar num desconto que nunca
  // aconteceu — foi o que deixou o ESTIMADOR assumi-lo (ver
  // `custoEstimadoPorConteudo`).
  const cache = Number(usage.prompt_tokens_details?.cached_tokens ?? 0);
  const entradaCheia = Math.max(0, entradaTotal - cache);
  const usd =
    (entradaCheia * p.entrada + cache * p.entrada_cache + saida * p.saida) / 1_000_000;
  return Number(usd.toFixed(6));
}

// A decisão de orçamento do lote. Pura de propósito: é o que permite testá-la
// sem n8n e sem gastar um centavo.
//
// `chamadasPorDocumento` existe porque um documento mal nomeado paga o PDF DUAS
// vezes (classificação por conteúdo + extração — docs/CUSTO_OPENAI.md, medido no
// v31: 8 dos 14). O orçamento tem de contar o custo que o lote REALMENTE tem, não
// o do caso bem nomeado.
export function orcamentoDoLote({
  documentos,
  chamadasPorDocumento = 1,
  teto = TETO_EXECUCAO_USD,
  custoPorChamada = CUSTO_ESTIMADO_DOC_USD,
  bytes = null,
  pesoClassificacao = pesoDaChamadaDeClassificacao(),
}) {
  const n = Number(documentos) || 0;
  // Arredonda para CIMA: meia chamada não existe, e a metade que sobra é gasto.
  const chamadas = Math.ceil(n * Math.max(1, chamadasPorDocumento));

  // POR TAMANHO quando os bytes vieram; PLANO quando não vieram.
  //
  // `bytes` é o total do lote. A distinção não é cosmética: o número plano é o
  // que recusou um lote de US$ 1,41 dizendo US$ 7,65, e a estimativa por tamanho
  // é o que o corrige. Mas tamanho DESCONHECIDO não pode virar zero — isso
  // deixaria qualquer lote passar —, então a ausência cai no plano de propósito,
  // e a mensagem diz qual dos dois decidiu.
  const bytesTotais = Number(bytes);
  const porTamanho = Number.isFinite(bytesTotais) && bytesTotais > 0;

  // O FATOR DE CUSTO não é o número de chamadas: a segunda chamada de um
  // documento é a de CLASSIFICAÇÃO, e ela custa uma fração da extração (o
  // comentário de `pesoDaChamadaDeClassificacao` traz a medição). Contar
  // "2 chamadas = 2× o custo" é o que inflava a estimativa em 46% no lote real.
  //
  // E ELE SÓ VALE NO CAMINHO POR TAMANHO. A tentação é aplicar nos dois — o
  // desconto é o mesmo fato físico —, e é justamente onde ele não deve ir: o
  // caminho PLANO é o de "não sei nada sobre estes arquivos", e a única
  // calibração que ele tem é um incidente de dinheiro de verdade (o v31, 14
  // documentos reais que estouraram o teto de US$ 5 da OpenAI no meio do lote).
  // Descontar num caminho cego, com base numa proporção medida em PDFs
  // sintéticos de uma página, seria trocar a evidência cara pela barata. Quando
  // o tamanho é conhecido, a conta tem base própria e o desconto tem onde se
  // apoiar; quando não é, o guarda continua contando chamada cheia.
  const extrasPorDocumento = Math.max(0, Math.max(1, chamadasPorDocumento) - 1);
  const peso = Number.isFinite(Number(pesoClassificacao))
    ? Math.min(1, Math.max(0, Number(pesoClassificacao)))
    : 1;
  const fatorCusto = porTamanho ? 1 + extrasPorDocumento * peso : Math.max(1, chamadasPorDocumento);

  const estimadoUSD = porTamanho
    ? Number(Math.max(
        chamadas * CUSTO_MINIMO_CHAMADA_USD,
        (bytesTotais / BYTES_POR_MB) * CUSTO_POR_MB_USD * fatorCusto,
      ).toFixed(2))
    : Number((chamadas * custoPorChamada).toFixed(2));

  // Quantos documentos caberiam. Por tamanho, usa o tamanho MÉDIO deste lote —
  // é a única base honesta: dizer "no máximo 15" com base num documento típico
  // que não é o deste lote foi o que produziu a recusa errada.
  const custoMedioPorDoc = n > 0 ? estimadoUSD / n : custoPorChamada;
  const maxDocumentos = custoMedioPorDoc > 0
    ? Math.max(0, Math.floor(teto / custoMedioPorDoc))
    : n;
  const cabe = estimadoUSD <= teto;

  // A mensagem é metade do valor desta função: ela é o que o dono lê quando o
  // lote é recusado, e tem de dizer o que FAZER — não só que deu errado.
  const base = porTamanho
    ? `${(bytesTotais / 1024).toFixed(0)} KB de arquivo`
    : `estimativa plana de US$ ${custoPorChamada.toFixed(2)} por chamada (o tamanho dos arquivos não chegou até aqui)`;

  const mensagem = cabe
    ? null
    : `[orçamento ${VERSAO_ORCAMENTO}] ` +
      `Lote recusado ANTES de gastar: ${n} documento(s) = ${chamadas} chamada(s) de IA ` +
      `≈ US$ ${estimadoUSD.toFixed(2)}, acima do teto de US$ ${teto.toFixed(2)} por execução. ` +
      `A conta saiu de ${base}. ` +
      `Envie no máximo ${maxDocumentos} documento(s) por vez (${Math.ceil(n / Math.max(1, maxDocumentos))} levas). ` +
      `Nada foi enviado ao provedor de IA e nada foi gravado, então reenviar não duplica nem custa. ` +
      `Se o lote precisa rodar inteiro, o teto vive em TETO_EXECUCAO_USD (N8N/lib/custo.mjs) ` +
      `— e subir ele exige subir também o teto do projeto no provedor, senão a API barra no meio.`;

  return {
    cabe, estimadoUSD, maxDocumentos, teto, chamadas, mensagem, porTamanho,
    versao: VERSAO_ORCAMENTO,
    fatorCusto: Number(fatorCusto.toFixed(4)),
  };
}

// ===========================================================================
// A ESTIMATIVA POR CONTEÚDO — o que o teto passa a usar quando o texto do
// documento já foi lido.
// ===========================================================================
//
// O DEFEITO QUE ISTO CORRIGE, e ele é de LUGAR antes de ser de fórmula. O teto
// decidia entre `Classificar Nome` e `Preparar Conteudo`, ou seja, com o nome
// do arquivo e o tamanho em bytes na mão e mais nada. Dali não dá para saber
// duas coisas que mandam no custo:
//
//   • QUANTAS LINHAS o documento tem. Bytes de PDF não são tokens — um PDF de
//     texto rende quatro vezes mais linha por byte que um escaneado (medido no
//     book), e por isso a estimativa por byte carrega uma margem de 1,8× que
//     superestima o lote típico em ~50%. Um lote que cabe é recusado.
//   • QUANTOS BLOCOS a extração vai gastar. Documento acima de
//     `MAX_CELULAS_POR_BLOCO` é FATIADO, e cada fatia é uma chamada nova que
//     reenvia o PDF inteiro. A conta por byte não tem como saber disso, então
//     ela subestima justamente o documento grande — que é o caro.
//
// Depois do `Extrair Texto` os dois números existem e são EXATOS: as linhas com
// número saem do texto do próprio PDF, e o número de blocos sai de
// `planejarFatias`, a MESMA função que o `Fatiar Extracao` vai executar. Deixa
// de ser estimativa por proxy e passa a ser a conta do que vai acontecer.
//
// O QUE NÃO MUDA: continua sendo ANTES de qualquer chamada de IA. Entre o
// `Medir Documento` e a primeira chamada não há gasto nenhum — o `Extrair
// Texto` é local e o `Upload Storage` é ramo lateral (e desligado). O teto
// continua barrando de graça.
//
// A CALIBRAÇÃO É A MESMA de `medir-custo-book.mjs`, e agora é literalmente o
// mesmo código: aquele script tinha estas constantes copiadas, e o único jeito
// de o medidor e o guarda discordarem é serem dois arquivos.

/** ~4 caracteres por token — razão média do tokenizador do gpt-4o em português. */
export const CARACTERES_POR_TOKEN = 4;

/** O PDF vira imagem: ~1.000 tokens por página (docs/CUSTO_OPENAI.md). */
export const TOKENS_POR_PAGINA_IMAGEM = 1000;

// O PIOR CASO REAL DE ENTRADA, não um teto do sistema. É o mesmo número que o
// comentário de `PRECOS_POR_PROVEDOR.openai` já cita (20 páginas, ~20 mil
// tokens de imagem, `Arquitetura do Sistema/4 Análises e Auditorias/CUSTO_IA.md`)
// — documento maior pode aparecer amanhã, mas este é o maior JÁ MEDIDO, e é o
// número certo para dimensionar CADÊNCIA (abaixo, em `build-workflow.mjs`):
// dimensionar pela MÉDIA (`PERFIL_MEDIDO.entradaPorDocumento`, 3.500 tokens)
// deixaria o intervalo folgado no documento típico e apertado exatamente no
// maior — que é o único em que o TPM de fato aperta.
//
// ACHADO NUMA REVISÃO ADVERSARIAL (11/09/2026): até esta correção, o intervalo
// entre chamadas (`INTERVALO_EXTRACAO_MS`) considerava só os tokens de SAÍDA
// (`MAX_OUTPUT_TOKENS`), com um comentário afirmando que a reserva "cobre a
// chamada inteira" — falso. Um PDF de 20 páginas manda ~20.000 tokens de
// ENTRADA MAIS os 16.384 reservados de saída: 36.384 numa única chamada,
// acima do TPM de 30.000 do Tier 1. Nenhum espaçamento entre chamadas evita um
// 429 de UMA chamada sozinha estourando o balde — é o mesmo desfecho das 72
// falhas do "Teste 00" (`HANDOFF.md`), por um caminho que ninguém tinha somado.
export const PAGINAS_MAX_MEDIDO = 20;

// A saída, no formato AGRUPADO que roda hoje (uma seção por grupo, as colunas
// declaradas uma vez, a conta escrita uma vez com um valor por coluna). Os três
// números saem da medição de caracteres do formato real (JSON.stringify / 4).
export const TOKENS_CABECALHO_GRUPO = 30;
export const TOKENS_CONTA_BASE = 26;
export const TOKENS_POR_VALOR = 9;

// Quantas contas cabem num grupo, em média. Não é medido no PDF: é a razão
// observada nos books — um balanço tem ~8 seções e ~50 contas por coluna, e cada
// subtotal abre grupo próprio. Declarado como SUPOSIÇÃO porque só afeta o custo
// do cabeçalho, que é ~5% da saída.
export const CONTAS_POR_GRUPO = 8;

/** A classificação por conteúdo manda o mesmo PDF e devolve um objeto minúsculo. */
export const TOKENS_SAIDA_CLASSIFICACAO = 120;

// A MARGEM DO GUARDA, e por que ela é 1,25 e não 1,8.
//
// A estimativa por byte carrega 1,8× porque bytes de PDF não dizem quase nada
// sobre tokens (4× de diferença entre os extremos medidos no book). Aqui a
// conta é de linhas lidas do próprio documento, e o modelo foi conferido contra
// a única fatura REAL que existe: o dono rodou o book-vertentes e pagou
// US$ 0,90; o mesmo modelo, no formato daquela época, estima US$ 0,87 — 3%
// abaixo. Margem grande em cima de uma conta dessas seria recusar lote que cabe,
// que é o defeito que este trabalho existe para tirar.
//
// O QUE A MARGEM COBRE, e é honesto listar: duas suposições não medidas —
// `CONTAS_POR_GRUPO` (afeta ~5% da saída) e os ~4 caracteres por token — mais o
// documento escaneado que entra no lote sem camada de texto (esse cai no
// caminho por byte inteiro, mas um lote misto ainda passa por aqui).
//
// A MARGEM CONTINUA 1,25, E A TENTATIVA DE SUBI-LA FOI DERRUBADA POR TESTE.
//
// O 1,25 foi calibrado contra UMA fatura da era OpenAI. Contra o Google, as
// quatro rodadas de `lote_execucao` que gastaram mostraram a estimativa ABAIXO
// do real — a direção errada para um guarda de teto:
//
//     7276 1,49×  ·  7377 1,46×  ·  7316 1,42×  ·  7417 1,37×
//
// Tirar o cache assumido e não entregue (ver `custoEstimadoPorConteudo`) fecha
// METADE do buraco: a estimativa do book sobe 1,24× (US$ 0,29 → US$ 0,36), e o
// erro da 7377 cai de 1,46× para ~1,11×.
//
// SUBIR A MARGEM PARA 1,50 FOI TENTADO E MEDIDO COMO ERRADO: o
// `custo.test.mjs` reprovou com "190 documentos com a forma do book-araucaria
// foram RECUSADOS: US$ 3,09 contra o teto de US$ 3". Recusar um lote que custa
// US$ 2,36 de verdade é o v31 pelo outro lado, e o lote é um NÃO INTEIRO —
// recusado, ele não roda em parte nenhuma. Folga em cima de um modelo errado não
// é segurança, é o guarda cego que o cabeçalho deste arquivo já descreve.
//
// O QUE SOBRA, MEDIDO E ATRIBUÍDO: ~1,11× de subestimação, e a causa NÃO é a
// margem — é `tokensDeSaida`, medida em 1,50× (96.762 tokens previstos contra
// 145.579 gravados na 7377). Recalibrá-la é fatia própria, porque mexe numa
// suposição sobre a FORMA da resposta do modelo, não num fator de folga. Até lá
// a defesa dura continua sendo o teto de US$ 5 no provedor — e ela é a que
// nunca dependeu deste arquivo.
export const MARGEM_ORCAMENTO_CONTEUDO = 1.25;

/**
 * Tokens de SAÍDA de uma extração com `celulas` células em `colunas` colunas.
 *
 * Célula é toda linha com número; a mesma conta em três exercícios são três
 * células e UMA conta — é essa divisão que o formato agrupado explora, e é por
 * isso que a conta não é linear no número de células.
 */
export function tokensDeSaida(celulas, colunas = 1) {
  const cel = Math.max(0, Number(celulas) || 0);
  const cols = Math.max(1, Number(colunas) || 1);
  const contas = Math.max(1, Math.ceil(cel / cols));
  const grupos = Math.max(1, Math.ceil(contas / CONTAS_POR_GRUPO));
  return grupos * TOKENS_CABECALHO_GRUPO + contas * (TOKENS_CONTA_BASE + cols * TOKENS_POR_VALOR);
}

/**
 * Custo estimado de UM documento, a partir do que já foi MEDIDO nele.
 *
 * `blocos` é o número de chamadas de extração: cada fatia reenvia o documento
 * inteiro (a entrada se repete) e devolve a sua parte da saída (a saída se
 * divide). Ignorar isso é o erro que a estimativa por byte comete no
 * documento grande.
 *
 * A ENTRADA NÃO É SEMPRE "PÁGINAS × TOKENS_POR_PAGINA_IMAGEM" — só era até
 * 12/09/2026, quando este arquivo só sabia extrair PDF (que vai ao modelo como
 * IMAGEM). Documento de TEXTO (`formato` reconhecido por `ehFormatoDeTexto`,
 * o mesmo detector de `custoEstimadoPorTamanho`) não tem página nenhuma — o
 * que ele tem é `bytes`, e a entrada dele é `bytes / CARACTERES_POR_TOKEN`,
 * a MESMA conta direta que já vale na estimativa por TAMANHO. Contar página
 * (`pag = 1` por padrão, `Math.max(1, ...)`) num `.txt` de 670 KB subestimava
 * a entrada em 167× — 1.000 tokens fixos contra ~167.000 reais — e teria
 * TROCADO uma recusa de lote que cabe (o defeito do proxy de PDF) por um
 * aceite de lote que não cabe, que é o v31 de novo.
 *
 * Documento de texto SEM `bytes` conhecido não inventa entrada nenhuma: quem
 * decide isso é `orcamentoDoLotePorConteudo.medido`, que joga esse documento
 * (e o lote inteiro, pela mesma doutrina que já vale para PDF sem página) de
 * volta para o caminho por TAMANHO — nunca para um chute de página.
 */
export function custoEstimadoPorConteudo({
  celulas, paginas, colunas = 1, blocos = 1, precisaFallback = false, tokensPromptSistema = 0,
  formato = null, bytes = null,
}) {
  const cel = Math.max(0, Number(celulas) || 0);
  const nBlocos = Math.max(1, Number(blocos) || 1);
  const sistema = Math.max(0, Number(tokensPromptSistema) || 0);
  const entradaDocumento = ehFormatoDeTexto(formato)
    ? Math.max(0, Number(bytes) || 0) / CARACTERES_POR_TOKEN
    : Math.max(1, Number(paginas) || 1) * TOKENS_POR_PAGINA_IMAGEM;
  const saidaTotal = tokensDeSaida(cel, colunas);

  let usd = 0;
  for (let b = 0; b < nBlocos; b += 1) {
    // A saída se reparte entre os blocos; a entrada, não — cada bloco reenvia o
    // documento inteiro. Repartir por igual é a aproximação certa aqui:
    // `planejarFatias` corta por número de células, então os blocos saem do
    // mesmo tamanho.
    usd += custoDaChamada({
      prompt_tokens: sistema + entradaDocumento,
      completion_tokens: Math.ceil(saidaTotal / nBlocos),
      // O PROMPT DE SISTEMA NÃO É COBRADO COMO CACHE AQUI, e esta linha foi
      // removida em 10/09/2026 — ela dizia `cached_tokens: sistema`, com o
      // comentário "é a condição do cache de prefixo da OpenAI, e ignorá-lo
      // superestimaria ~40%".
      //
      // O PROVEDOR É GOOGLE DESDE 24/08 e a troca não revisitou isto. MEDIDO em
      // produção, `lote_execucao` de CINCO rodadas consecutivas (7276, 7316,
      // 7327, 7377, 7417): `tokens_cache = 0` em TODAS. O mapeamento não é o
      // culpado — `provedor.mjs` traduz `usageMetadata.cachedContentTokenCount`
      // corretamente para este campo; o Gemini simplesmente reporta zero, porque
      // `cachedContentTokenCount` conta cache EXPLÍCITO (CachedContent API) e
      // este pipeline não usa nenhum.
      //
      // O EFEITO ERA SUBESTIMAR, que é a direção errada para um guarda de teto.
      // Medido, estimativa contra real: 7276 1,49× · 7377 1,46× · 7316 1,42× ·
      // 7417 1,37×. Um lote estimado em US$ 2,9 (abaixo do teto de 3) custaria
      // ~US$ 4,2 — e "aceita lote que não cabe" é exatamente o v31 que o
      // cabeçalho deste arquivo existe para não repetir.
      //
      // Não assumir cache nenhum é a escolha certa mesmo se um provedor futuro
      // cachear: aí a estimativa erra para CIMA, que é o lado seguro por
      // projeto. Quem quiser o desconto de volta tem de MEDIR `tokens_cache`
      // não-zero em produção primeiro.
    }, MODELO_EXTRACAO) ?? 0;
  }

  if (precisaFallback) {
    usd += custoDaChamada({
      prompt_tokens: entradaDocumento + 400,
      completion_tokens: TOKENS_SAIDA_CLASSIFICACAO,
    }, MODELO_CLASSIFICACAO) ?? 0;
  }

  return Number(usd.toFixed(6));
}

// ---------------------------------------------------------------------------
// O DOCUMENTO QUE NÃO DÁ PARA MEDIR — e por que ele deixou de derrubar o lote
// ---------------------------------------------------------------------------
//
// A REGRA ATÉ 13/09/2026 ERA TUDO-OU-NADA: bastava UM documento sem medida de
// conteúdo para o lote INTEIRO cair no proxy por byte. O argumento dela está no
// comentário que ela deixou e é honesto — "medir só os que dá subestimaria o
// lote na exata proporção do que não se sabe".
//
// O ARGUMENTO NÃO FECHA PARA O HÍBRIDO, e é essa a correção. Medir por conteúdo
// os documentos que dá e cobrar o caminho conservador dos que não dá **nunca
// subestima**: o proxy por byte é ≥ o custo real por construção (é a margem de
// ~2× que a calibração dele declara, travada por invariante desde esta mesma
// rodada). Tudo-ou-nada não trocava "sei menos" por "erro maior": trocava "não
// sei sobre 1" por "erro de regime sobre 44", e essa troca não é conservadora, é
// só cara.
//
// O NÚMERO QUE MOSTRA O TAMANHO DA TROCA, medido com a função de verdade no
// lote de 44 documentos da AMO (14,4 MB): US$ 52,39 pela regra antiga com o
// proxy no preço de agosto, US$ 27,69 com o proxy já reescalado — e o mesmo lote
// medido documento a documento fica na casa de US$ 1. O teto é US$ 3.
//
// O TERCEIRO CAMINHO, E É ELE QUE FECHA A CONTA: um PDF escaneado NÃO é
// imensurável. Falta só a camada de texto — `paginas` existe (`Medir Documento`
// tira do `numpages` do `pdf-parse`, que não depende de texto nenhum), e a
// ENTRADA dele já é `paginas × TOKENS_POR_PAGINA_IMAGEM`, que é a conta boa. O
// que faltava era estimar a SAÍDA, e é para isso que serve a constante abaixo.
//
// A CALIBRAÇÃO DELA, MEDIDA nesta sessão sobre os 52 documentos dos dois books
// (`Dados de Teste/book-canastra/pdf/METRICAS.json` e `book-vertentes`, campos
// `celulas_de_valor_verdade` e `paginas`):
//
//   agregado 53,4 células/página · mediana 43,0 · p75 65,2 · p90 91,7 · máximo 131,0
//
// `CELULAS_POR_PAGINA_ESTIMADAS = 100` fica ACIMA do p90 (47 dos 52 documentos
// medidos estão abaixo dela) e é 1,87× o agregado — a mesma ordem de margem que
// o proxy por byte declara para o lote típico, pela mesma razão: quem não foi
// medido paga a incerteza, e a incerteza aqui é para cima.
//
// O QUE ELA CUSTA POR DOCUMENTO, e é a comparação que importa: um PDF escaneado
// de 20 páginas e 335 KB (a média medida do lote da AMO) sai por ~US$ 0,12 nesta
// conta contra ~US$ 0,48 no proxy por byte — 4× menos, e ainda ~2× acima do que
// um documento desse tamanho custa de verdade nos books medidos.
//
// O LIMITE QUE FICA DECLARADO, porque ele existe: um documento escaneado MAIS
// DENSO que 100 células por página é SUBESTIMADO por esta conta. É o mesmo
// limite que o proxy por byte já declara para o documento isolado ("a margem
// cobre a média de um lote, não o pior documento"), e a defesa dele continua
// sendo a mesma — o teto duro de US$ 5 do projeto no provedor. O que NÃO é
// defesa é voltar ao tudo-ou-nada: ele não protegia contra o documento denso,
// ele só recusava o lote inteiro.
/** Células por página de um PDF sem camada de texto — p90 dos 52 documentos medidos. */
export const CELULAS_POR_PAGINA_ESTIMADAS = 100;

// A MESMA IDEIA PARA TEXTO, e ela nasceu de um achado da revisão desta rodada
// (o buraco está descrito em `estimativaDoDocumento`, ramo `tamanho`). MEDIDA
// sobre os mesmos 52 documentos dos dois books (`celulas_de_valor_verdade` /
// `caracteres`, que é o texto extraído do PDF — o analógo direto do conteúdo de
// um `.txt`/`.csv`):
//
//   agregado 1 célula a cada 33,5 caracteres · mediana 38,2 · p90 22,3 · o mais
//   denso medido 14,2
//
// Vale o p90 (22), pelo mesmo motivo do p90 da página: quem não foi medido paga
// a incerteza, e a incerteza é para cima. O LIMITE DECLARADO: um texto mais denso
// que 1 célula a cada 22 caracteres — uma planilha exportada em CSV cru, sem
// rótulo comprido — é subestimado por esta conta, e a defesa dele continua sendo
// o teto duro do provedor. O que ela impede é o buraco de 46× que existia aqui.
/** Caracteres por célula num documento de texto sem contagem — p90 dos 52 medidos. */
export const CARACTERES_POR_CELULA_ESTIMADA = 22;

/**
 * A estimativa de UM documento, e o CAMINHO por onde ela saiu.
 *
 * Quatro caminhos, do mais medido para o mais cego. O `motivo` não é enfeite: é
 * o que a mensagem de recusa passou a dizer, porque "a conta saiu de 14737 KB de
 * arquivo" não diz QUAL documento derrubou a medição nem POR QUÊ — e isso é a
 * regra 1 (nunca apresentar ausência como dado) aplicada ao próprio diagnóstico.
 *
 *   `conteudo` — células e (páginas, ou bytes se for texto) medidos no documento;
 *   `pagina`   — PDF/imagem com páginas mas SEM camada de texto: saída estimada
 *                por `CELULAS_POR_PAGINA_ESTIMADAS`;
 *   `tamanho`  — nem células nem páginas, mas o tamanho chegou: proxy por byte;
 *   `cego`     — nada chegou: a estimativa plana, sem desconto de 2ª chamada
 *                (mesma doutrina de `orcamentoDoLote`).
 *
 * A MARGEM DE CONTEÚDO (1,25×) vale só nos dois primeiros. Os outros dois já
 * carregam a margem própria da calibração deles — aplicar as duas seria cobrar
 * a mesma incerteza duas vezes e recusar lote que cabe.
 */
export function estimativaDoDocumento(d, tokensPromptSistema = 0, peso = pesoDaChamadaDeClassificacao(), custoPorChamada = CUSTO_ESTIMADO_DOC_USD) {
  const doc = d || {};
  const celulas = Number(doc.celulas);
  const paginas = Number(doc.paginas);
  const bytes = Number(doc.bytes);
  const texto = ehFormatoDeTexto(doc.formato);
  const temCelulas = Number.isFinite(celulas) && celulas > 0;
  const temPaginas = Number.isFinite(paginas) && paginas > 0;
  const temBytes = Number.isFinite(bytes) && bytes > 0;
  const blocos = Math.max(1, Number(doc.blocos) || 1);

  if (temCelulas && (texto ? temBytes : temPaginas)) {
    return {
      caminho: 'conteudo',
      motivo: null,
      usd: custoEstimadoPorConteudo({ ...doc, tokensPromptSistema }) * MARGEM_ORCAMENTO_CONTEUDO,
    };
  }

  if (!texto && temPaginas) {
    // `colunas: 1` de propósito, e não o que veio no documento: com uma coluna
    // cada célula é uma conta, e `tokensDeSaida` devolve o MAIOR número de
    // tokens para o mesmo total de células. Quem não foi medido paga o pior caso.
    const estimadas = Math.ceil(paginas * CELULAS_POR_PAGINA_ESTIMADAS);
    return {
      caminho: 'pagina',
      motivo: `sem camada de texto em ${paginas} página(s) — saída estimada por `
        + `${CELULAS_POR_PAGINA_ESTIMADAS} célula(s) por página, não medida no documento`,
      usd: custoEstimadoPorConteudo({
        ...doc, celulas: estimadas, colunas: 1, blocos, tokensPromptSistema,
      }) * MARGEM_ORCAMENTO_CONTEUDO,
    };
  }

  if (temBytes) {
    // O PISO DO CAMINHO CEGO VALE AQUI TAMBÉM, e ele é a correção de uma
    // AFIRMAÇÃO FALSA que esta mesma rodada tinha escrito: "o proxy por byte é
    // ≥ o custo real por construção". Ele não é. MEDIDO por
    // `N8N/medir-custo-book.mjs`: o documento mais denso do book
    // (`17_Livro_Razao`, 10.849 bytes, 461 linhas) custa US$ 0,0222 e o proxy
    // sobre ele dá US$ 0,0153 — **0,69× o real**. A margem de ~2× do proxy é
    // AGREGADA DE LOTE, e o próprio arquivo já declarava isso ("a margem cobre
    // a média de um lote, não o pior documento"); o que mudou nesta rodada foi
    // aplicá-lo documento a documento, que é exatamente onde a média não vale.
    // O piso `custoPorChamada` é o número calibrado de "não sei nada sobre este
    // arquivo" (2,5× o documento mais caro medido), e é ele que devolve à frase
    // "quem não foi medido paga a incerteza" a verdade que ela afirma.
    const proxy = custoEstimadoPorTamanho(bytes, doc.formato) * (1 + (doc.precisaFallback ? peso : 0));

    if (texto) {
      // TEXTO SEM LINHA CONTADA É O BURACO QUE A REVISÃO ACHOU, e ele era o v31
      // pelo outro lado: `custoEstimadoPorTamanho`, para texto, cobra SÓ A
      // ENTRADA de propósito (o comentário dela diz isso) — a saída quem cobria
      // era o piso por chamada, que bastava enquanto este caminho decidia o
      // lote INTEIRO junto com documentos medidos. Como caminho POR DOCUMENTO
      // ele passou a cobrar 46× menos que a conta por conteúdo do mesmo
      // arquivo: 20 CSVs de 1 MB não medidos estimavam US$ 1,31 e PASSAVAM,
      // contra US$ 15,26 da conta por conteúdo — e a regra tudo-ou-nada, que
      // esta fatia substituiu, recusava esse mesmo lote. Corrigir sem isto
      // seria trocar "recusa lote que cabe" por "aceita lote que não cabe".
      //
      // A SAÍDA PASSA A SER ESTIMADA PELO TAMANHO DO TEXTO, com a mesma
      // doutrina do caminho por página: bytes de texto SÃO caracteres (é o
      // argumento que `custoEstimadoPorTamanho` já faz para a entrada), e a
      // razão caractere→célula foi MEDIDA sobre os 52 documentos dos dois
      // books — ver `CARACTERES_POR_CELULA_ESTIMADA`.
      const estimadas = Math.ceil(bytes / CARACTERES_POR_CELULA_ESTIMADA);
      const porDensidade = custoEstimadoPorConteudo({
        ...doc, celulas: estimadas, colunas: 1, blocos, tokensPromptSistema,
      }) * MARGEM_ORCAMENTO_CONTEUDO;
      return {
        caminho: 'tamanho',
        motivo: `texto sem nenhuma linha com número contada (${(bytes / 1024).toFixed(0)} KB) — `
          + `saída estimada por 1 célula a cada ${CARACTERES_POR_CELULA_ESTIMADA} caracteres, `
          + `não medida no documento`,
        usd: Math.max(proxy, porDensidade, custoPorChamada),
      };
    }

    // E A FRASE DIZ O QUE É VERDADE DESTE RAMO, que é o único não-texto sem
    // página nenhuma — quem tem página já saiu pelo caminho por página, acima.
    // A revisão desta rodada levantou o caso do PDF com 30 páginas lidas que
    // caísse aqui e ouvisse "sem página lida": ele existe, mas é o PDF com
    // camada de TEXTO (`leitura_pdf === 'texto'`, que o nó carimba como formato
    // 'texto'), e a frase dele é a do ramo acima, que não fala de página nenhuma.
    return {
      caminho: 'tamanho',
      motivo: `sem linha com número e sem página lida — cobrado pelo proxy por tamanho `
        + `(${(bytes / 1024).toFixed(0)} KB), com piso da estimativa plana`,
      usd: Math.max(proxy, custoPorChamada),
    };
  }

  return {
    caminho: 'cego',
    motivo: 'nem conteúdo, nem página, nem tamanho chegaram até o orçamento',
    usd: custoPorChamada * (doc.precisaFallback ? 2 : 1),
  };
}

// A INSTRUÇÃO DE LEVAS da recusa, fora de `orcamentoDoLotePorConteudo` para a
// função ficar dentro do teto de complexidade cognitiva do Sonar
// (`javascript:S3776`: ela passou de 15 para 21 quando o ramo do documento que
// não cabe sozinho entrou, e o Sonar acusou isso no PR #246). O comportamento é
// o mesmo, e as suítes de `N8N/test` o cobrem.
export function instrucaoDeLevasDoLote({ partes, docs, teto, maxDocumentos, maxNomes }) {
  const n = docs.length;
  const acimaDoTeto = partes
    .map((p, i) => ({ nome: docs[i]?.nome ?? null, usd: p.usd }))
    .filter((p) => p.usd > teto);
  const restantes = n - acimaDoTeto.length;
  const somaRestantes = partes.reduce((s, p) => s + (p.usd > teto ? 0 : p.usd), 0);
  const maxRestantes = restantes > 0 && somaRestantes > 0
    ? Math.max(1, Math.floor(teto / (somaRestantes / restantes)))
    : restantes;
  if (acimaDoTeto.length === 0) {
    return `Envie no máximo ${maxDocumentos} documento(s) por vez (${Math.ceil(n / Math.max(1, maxDocumentos))} levas). `;
  }
  const nomesAcima = acimaDoTeto.slice(0, maxNomes)
    .map((p) => `${p.nome || '(sem nome)'} (~US$ ${p.usd.toFixed(2)})`).join('; ');
  const restoAcima = acimaDoTeto.length > maxNomes ? ` e mais ${acimaDoTeto.length - maxNomes}` : '';
  return `${acimaDoTeto.length} documento(s) custam sozinhos MAIS que o teto de US$ ${teto.toFixed(2)} e `
    + `nenhuma leva os faz passar: ${nomesAcima}${restoAcima}. Divida cada um em arquivos menores (por período ou por entidade) `
    + 'ou suba o teto. '
    + (restantes > 0
      ? `Os outros ${restantes} documento(s) cabem em levas de no máximo ${maxRestantes} por vez. `
      : '');
}

/**
 * A decisão de orçamento do lote QUANDO O CONTEÚDO JÁ FOI LIDO.
 *
 * DOCUMENTO A DOCUMENTO desde 13/09/2026 (ver o comentário grande acima): cada
 * um é estimado pelo melhor caminho que a medição dele permite, e nenhum
 * documento derruba a medição dos outros. O que a função devolve continua sendo
 * uma decisão só para o lote inteiro — "roda os que cabem" continua não
 * existindo, pelo mesmo motivo de sempre (metade registrada sem extração é
 * estado que dá mais trabalho para desfazer que o reenvio).
 *
 * `porConteudo` passou a significar "NENHUM documento caiu no caminho cego" —
 * inclui o PDF escaneado estimado por página, que é medição do documento
 * (páginas), não proxy de arquivo. `porTamanho` é o complemento: algum documento
 * foi cobrado por byte ou pela estimativa plana.
 *
 * O QUE CONTA COMO "MEDIDO" DEPENDE DO FORMATO, e é a correção de 12/09/2026:
 * documento de texto é medido por `celulas` e `bytes` — nunca por `paginas`, que
 * ele não tem e não precisa (a entrada dele sai do tamanho do texto). Um único
 * `.txt` sem página derrubava o lote inteiro no proxy de PDF.
 */
export function orcamentoDoLotePorConteudo({
  documentos = [],
  teto = TETO_EXECUCAO_USD,
  custoPorChamada = CUSTO_ESTIMADO_DOC_USD,
  tokensPromptSistema = 0,
}) {
  const docs = Array.isArray(documentos) ? documentos : [];
  const n = docs.length;

  // Lote vazio não é lote medido: segue pelo caminho de sempre, que devolve
  // zero e `cabe`, sem afirmar que mediu coisa nenhuma.
  if (n === 0) {
    return { ...orcamentoDoLote({ documentos: 0, teto, custoPorChamada }), porConteudo: false, naoMedidos: [], aviso: null };
  }

  const peso = pesoDaChamadaDeClassificacao();
  const partes = docs.map((d) => estimativaDoDocumento(d, tokensPromptSistema, peso, custoPorChamada));

  const estimadoUSD = Number(partes.reduce((s, p) => s + p.usd, 0).toFixed(2));
  const chamadas = docs.reduce(
    (s, d) => s + Math.max(1, Number(d?.blocos) || 1) + (d?.precisaFallback ? 1 : 0), 0);
  // AS CÉLULAS SÃO AS DOS DOCUMENTOS QUE FORAM MEDIDOS POR CONTEÚDO, e só delas.
  // Somar sobre o lote inteiro atribuía à frase "N documentos medidos por
  // conteúdo (X linhas lidas dos próprios documentos)" as linhas de um documento
  // que NÃO foi por esse caminho — um PDF com 5.000 células medidas mas sem
  // `numpages` engordava o número dos outros. É a mesma atribuição errada que
  // esta fatia existe para tirar da mensagem.
  const celulas = docs.reduce(
    (s, d, i) => s + (partes[i].caminho === 'conteudo' && Number.isFinite(Number(d?.celulas))
      ? Math.max(0, Number(d.celulas)) : 0), 0);

  const porCaminho = partes.reduce((acc, p) => ({ ...acc, [p.caminho]: (acc[p.caminho] || 0) + 1 }), {});
  const porConteudo = partes.every((p) => p.caminho === 'conteudo' || p.caminho === 'pagina');
  const porTamanho = !porConteudo;

  // OS NÃO MEDIDOS SÃO NOMEADOS, e é a regra 1 aplicada ao diagnóstico: a
  // mensagem antiga dizia "a conta saiu de 14737 KB de arquivo" e o dono não
  // tinha como saber QUAL documento tinha derrubado a medição, nem por quê —
  // sobrava reenviar às cegas em 22 levas.
  const naoMedidos = partes
    .map((p, i) => ({ nome: docs[i]?.nome ?? null, caminho: p.caminho, motivo: p.motivo, usd: Number(p.usd.toFixed(4)) }))
    .filter((p) => p.caminho !== 'conteudo');
  const MAX_NOMES = 5;
  let aviso = null;
  if (naoMedidos.length > 0) {
    const nomeados = naoMedidos.slice(0, MAX_NOMES)
      .map((p) => `${p.nome || '(sem nome)'} (${p.motivo}, US$ ${p.usd.toFixed(4)})`)
      .join('; ');
    const resto = naoMedidos.length > MAX_NOMES
      ? ` e mais ${naoMedidos.length - MAX_NOMES} documento(s)`
      : '';
    aviso = `${naoMedidos.length} de ${n} documento(s) não tiveram o conteúdo medido e foram `
      + `estimados pelo caminho conservador: ${nomeados}${resto}.`;
  }

  const cabe = estimadoUSD <= teto;
  const custoMedioPorDoc = n > 0 ? estimadoUSD / n : custoPorChamada;
  const maxDocumentos = custoMedioPorDoc > 0
    ? Math.max(0, Math.floor(teto / custoMedioPorDoc))
    : n;

  // DE ONDE SAIU A CONTA, CAMINHO A CAMINHO. A frase única ("a conta saiu de N
  // linhas lidas dos próprios documentos") era verdade enquanto o lote inteiro
  // ia por um caminho só; com a conta híbrida ela viraria o defeito da regra 1
  // no próprio diagnóstico — um lote sem nenhuma medição anunciava "a conta saiu
  // de 0 linha(s) com número", que é apresentar ausência como dado.
  const base = [
    porCaminho.conteudo
      ? `${porCaminho.conteudo} documento(s) medidos por conteúdo (${celulas} linha(s) com número `
        + `lidas dos próprios documentos, mais ${MARGEM_ORCAMENTO_CONTEUDO}× de margem)`
      : null,
    porCaminho.pagina
      ? `${porCaminho.pagina} estimado(s) por PÁGINA (${CELULAS_POR_PAGINA_ESTIMADAS} célula(s) por `
        + `página, porque não têm camada de texto)`
      : null,
    porCaminho.tamanho ? `${porCaminho.tamanho} pelo TAMANHO do arquivo` : null,
    porCaminho.cego
      ? `${porCaminho.cego} pela estimativa plana de US$ ${custoPorChamada.toFixed(2)} por chamada `
        + `(o tamanho dos arquivos não chegou até aqui)`
      : null,
  ].filter(Boolean).join(', ');

  // `avisoNaMensagem` é variável em vez de ternário dentro da concatenação: o
  // Sonar (`javascript:S3358`) reprova ternário aninhado, e aqui ele tinha
  // razão — a frase da recusa já é longa, e um `? :` no meio dela é onde um
  // erro de pontuação passa despercebido numa revisão.
  const avisoNaMensagem = aviso === null ? '' : `${aviso} `;
  // O DOCUMENTO QUE NÃO CABE NEM SOZINHO TEM DE SER NOMEADO (17/09/2026). A
  // execução 7888 recusou 7 documentos (US$ 40,31) com "Envie no máximo 0
  // documento(s) por vez (7 levas)": `maxDocumentos` sai da média do lote, e a
  // média passou do teto porque UM documento custava US$ 10,81 — mais que os
  // US$ 3,00 do teto. Nenhuma leva de tamanho nenhum o faria passar, e a
  // instrução "envie 0" não diz isso nem qual arquivo é. Agora cada documento
  // cujo custo SOZINHO passa do teto é nomeado com o seu custo, e a instrução
  // de levas fala só dos demais.
  const instrucaoDeLevas = instrucaoDeLevasDoLote({ partes, docs, teto, maxDocumentos, maxNomes: MAX_NOMES });
  const mensagem = cabe
    ? null
    : `[orçamento ${VERSAO_ORCAMENTO}] ` +
      `Lote recusado ANTES de gastar: ${n} documento(s) = ${chamadas} chamada(s) de IA ` +
      `≈ US$ ${estimadoUSD.toFixed(2)}, acima do teto de US$ ${teto.toFixed(2)} por execução. ` +
      `A conta saiu de ${base}. ${avisoNaMensagem}` +
      instrucaoDeLevas +
      `Nada foi enviado ao provedor de IA e nada foi gravado, então reenviar não duplica nem custa. ` +
      `Se o lote precisa rodar inteiro, o teto vive em TETO_EXECUCAO_USD (N8N/lib/custo.mjs) ` +
      `— e subir ele exige subir também o teto do projeto no provedor, senão a API barra no meio.`;

  return {
    cabe, estimadoUSD, maxDocumentos, teto, chamadas, mensagem,
    porTamanho, porConteudo, celulas, porCaminho, naoMedidos, aviso,
    versao: VERSAO_ORCAMENTO,
  };
}

// ---------------------------------------------------------------------------
// A COTA DO DIA — o limite que de fato aperta, e que ninguém lia
// ---------------------------------------------------------------------------
//
// POR QUE ESTA FUNÇÃO EXISTE. `lib/provedor.mjs` declara `rpd: 500` para a linha
// Flash-Lite no nível gratuito, com um comentário que o chama de "O LIMITE QUE
// NINGUÉM TINHA MODELADO, E É O QUE DE FATO APERTA". Medido em 31/08: `rpd` era
// lido por DOIS lugares — o `medir-custo-book.mjs`, que é relatório de CI, e a
// suíte. Nada em execução o lia. `tpm` e `rpm` alimentam a cadência do workflow
// (lib/extract.mjs); o RPD não alimentava nada.
//
// E O PORTÃO QUE EXISTIA MEDE A GRANDEZA ERRADA. `Orcamento do Lote` confere o
// teto de US$ 3, e o dólar não é a restrição que morde — medido:
//
//   Canastra   38 documentos  US$ 0,285 (passa folgado)   63 chamadas =  13% do RPD
//   Araucária 190 documentos  ~US$ 2,1  (passa folgado)  440 chamadas =  88% do RPD
//
// O lote que o guarda aprova por preço é o mesmo que a cota mata na metade. E o
// modo de falha não é lentidão: estourar o RPD no meio do lote MATA os
// documentos que faltavam, e a cota só reabre na virada da janela diária.
//
// O QUE ELA RECUSA, E O QUE ELA APENAS DECLARA. Recusa só o impossível — lote
// que não cabe num dia inteiro nem sozinho. Acima do limiar de aviso ela DEIXA
// PASSAR e declara, porque um portão que barrasse a 80% barraria o book de 190
// que é o caso de uso do dono, e portão que impede o trabalho legítimo é portão
// que alguém desliga.
//
// O QUE ELA NÃO SABE, E DIZ QUE NÃO SABE. O RPD é do DIA, somando todos os
// lotes; este nó vê um lote só. Quanto o dia já consumiu não está em lugar
// nenhum que ele alcance — e o painel do Google mostra o PICO DOS ÚLTIMOS 28
// DIAS, não o consumo de hoje. Declarar essa ignorância é o ponto: um "cabe"
// que escondesse a premissa "supondo que hoje ainda não rodou nada" seria
// exatamente apresentar ausência como dado.

/** Fração da cota diária acima da qual o lote passa, mas declarando. */
export const FRACAO_AVISO_RPD = 0.8;

/**
 * O veredito da cota diária para um lote de `chamadas` chamadas de IA.
 *
 * AUTO-CONTIDA: é embutida num nó Code por `toString()` e não pode referenciar
 * constante do módulo — `fracaoAviso` entra por argumento com o padrão no lugar.
 *
 * `rpd` ausente (a OpenAI não publica um número único para o Tier 1) devolve
 * `conhecido: false`. Não é "cabe": é "não sei", e quem lê trata diferente.
 */
export function vereditoDaCotaDiaria(entrada) {
  // PARÂMETRO SIMPLES, DESESTRUTURAÇÃO NO CORPO — e não é estilo. O espelho
  // inline (`espelho-inline.test.mjs`) extrai a função do JSON do workflow
  // procurando a primeira `{` DEPOIS do nome para achar o início do corpo. Com
  // `function f({ a, b } = {})`, a primeira `{` é a da desestruturação, e o
  // texto extraído sai cortado no meio da assinatura — `SyntaxError` no espelho,
  // que é a guarda reprovando por uma limitação do extrator e não por
  // divergência. Portão que reprova por ruído é pior que portão nenhum, e o
  // custo de evitá-lo aqui é uma linha.
  const e = entrada || {};
  const c = Number(e.chamadas);
  const limite = Number(e.rpd);
  const fracaoAviso = Number.isFinite(Number(e.fracaoAviso)) ? Number(e.fracaoAviso) : 0.8;
  if (!Number.isFinite(limite) || limite <= 0 || !Number.isFinite(c) || c < 0) {
    return { conhecido: false, cabe: true, fracao: null, chamadas: Number.isFinite(c) ? c : null, rpd: null, mensagem: null };
  }
  const fracao = Number((c / limite).toFixed(3));
  const cabe = c <= limite;
  const naoSeiDeHoje = 'O RPD é do DIA e soma TODOS os lotes: o que hoje já consumiu não é'
    + ' visível daqui, e o painel do provedor mostra o pico dos últimos 28 dias, não o de hoje.'
    + ' Cada RETENTATIVA também conta (o nó de extração tem até 6).';
  let mensagem = null;
  if (!cabe) {
    mensagem = `[cota diária] Lote recusado ANTES de gastar: ${c} chamada(s) de IA contra um limite`
      + ` de ${limite} por DIA — ele não cabe num dia inteiro nem sozinho.`
      + ` Estourar a cota no meio do lote não deixa o trabalho lento: MATA os documentos que`
      + ` faltavam, e ela só reabre na virada da janela diária.`
      + ` Divida o envio em ${Math.ceil(c / limite)} leva(s), em dias diferentes.`
      + ` Nada foi enviado ao provedor e nenhum documento foi registrado, então reenviar não`
      + ` duplica nem custa. ${naoSeiDeHoje}`;
  } else if (fracao >= Number(fracaoAviso)) {
    mensagem = `[cota diária] Este lote pede ${c} de ${limite} chamada(s) do dia`
      + ` (${Math.round(fracao * 100)}%) — ele PASSA, e praticamente ocupa a cota inteira:`
      + ` conte com um book por dia. ${naoSeiDeHoje}`;
  }
  return { conhecido: true, cabe, fracao, chamadas: c, rpd: limite, mensagem };
}
