// A SUÍTE DA MENSAGEM DE FALHA — o texto que o analista lê quando nada deu certo.
//
// POR QUE ELA EXISTE. Este é o único texto do sistema cujo defeito NÃO aparece
// enquanto tudo funciona: ele só é lido no dia ruim. Um erro aqui — uma
// assinatura que deixou de casar, uma frase que voltou a citar ferramenta — não
// quebra nada, não aparece em nenhuma tela de teste, e só se descobre quando
// alguém está esperando ajuda e recebe "deu erro".
//
// O que ela trava, e cada item saiu de uma forma de errar:
//   1. toda causa REAL do pipeline chega numa explicação específica, e não na
//      genérica — a genérica é rede, não destino;
//   2. nenhuma frase visível nomeia ferramenta, empresa ou termo de código;
//   3. as causas que pedem AÇÕES OPOSTAS não podem cair na mesma explicação;
//   4. a genérica ainda responde as três perguntas que tiram o analista da
//      dúvida: parou, não foi culpa sua, nada se perdeu.
import {
  explicarFalha, explicarParada, explicarLoteVazio, FRACAO_MINIMA_COM_LINHAS,
  type FalhaExplicada,
} from "../src/lib/falha-em-portugues.ts";
import {
  semPrimeiroSinalMs, janelaPara, semProgressoMs, SEGUNDOS_POR_DOCUMENTO,
  vereditoDoLote, carenciaDoFechamentoMs, estimativaEmMinutos,
} from "../src/lib/espera-do-lote.ts";
import { agregarCustos, somarCustos, formatarUsd, motivoDaAusencia, type LoteDeCusto } from "../src/lib/custos.ts";
import {
  agruparPorDia, categoriaDoTipo, chaveDeCursorValida, chaveDoDia, cursorValido, funcaoAusente, hrefDosMaisAntigos,
  lerCursor, rotuloDoTipo, textoDoAutor,
} from "../src/lib/historico-do-mandato.ts";
import {
  ATRIBUTO_DISCRICAO, CHAVE_DISCRICAO, SCRIPT_DISCRICAO_ANTES_DA_PINTURA, destinoAtivo, discricaoLigada,
  gravarDiscricao, idDoCaso, lerDiscricao,
} from "../src/lib/casco.ts";
import { readFileSync } from "node:fs";

let ok = 0;
const falhas: string[] = [];
function checar(condicao: boolean, o_que: string) {
  if (condicao) { ok += 1; return; }
  falhas.push(o_que);
}

// ---------------------------------------------------------------------------
// 1. As causas REAIS, com as mensagens como o pipeline as produz
// ---------------------------------------------------------------------------
//
// Não são exemplos inventados: cada uma é a forma que `diagnosticarErroApi`
// (N8N/lib/extract.mjs), a recusa do orçamento (N8N/lib/custo.mjs) ou o Error
// Workflow escrevem no banco hoje.
// Tuplas e não objetos: são 9 linhas de DADO, e a forma repetida
// `{ etapa: …, mensagem: …, esperado: … }` nove vezes é ruído que esconde o que
// varia — além de o próprio Sonar ler o bloco como duplicado, com razão.
type CausaReal = readonly [etapa: string, mensagem: string, esperadoNoTitulo: string];

const CAUSAS_REAIS: readonly CausaReal[] = [
  ["orcamento", "[orçamento v4 (2026-08-24)] Lote recusado ANTES de gastar: 38 documento(s) = 44 chamada(s) de IA ≈ US$ 3,10, acima do teto de US$ 3,00 por execução.", "grande demais"],
  ["IA Extrair", "CHAVE DO PROVEDOR INVÁLIDA, AUSENTE OU SEM PERMISSÃO (401/403). Nada a ver com cadência ou crédito.", "entrar na conta"],
  ["IA Extrair", "CONTA DO PROVEDOR SEM CRÉDITO OU SEM COBRANÇA ATIVA. A conta não tem como pagar a chamada.", "sem saldo"],
  ["IA Classificar", "TETO DE GASTO ATINGIDO no provedor de IA — e isto NÃO é falta de crédito: há saldo.", "limite de gasto"],
  ["IA Extrair", "MODELO INDISPONÍVEL PARA ESTA CONTA (404). O modelo configurado no workflow não existe.", "não existe mais"],
  ["IA Extrair", "LIMITE DE CADÊNCIA DO PROVEDOR (rate limit por minuto). Aqui espaçar as chamadas ajuda.", "rápido demais"],
  ["IA Extrair", "COTA DIÁRIA DO PROVEDOR ESGOTADA (limite por DIA de tokens/requisições do tier da conta).", "limite de uso de hoje"],
  ["Registrar Documento", "connect ETIMEDOUT 10.0.0.1:5432", "guardar"],
  ["desconhecida", "O processamento parou sem mensagem de erro.", "não disse o motivo"],
];

for (const [etapa, mensagem, esperado] of CAUSAS_REAIS) {
  const e = explicarFalha({ etapa, mensagem });
  checar(
    e.titulo.toLowerCase().includes(esperado.toLowerCase()),
    `"${esperado}" — causa real de "${etapa}" caiu em: "${e.titulo}"`,
  );
}

// ---------------------------------------------------------------------------
// 2. NENHUMA palavra técnica no que o analista lê
// ---------------------------------------------------------------------------
//
// A lista é de coisas que o dono não deve precisar conhecer para entender que o
// trabalho parou. Ela inclui nomes de fornecedor de propósito: o analista não
// tem contrato com nenhum deles, e citá-los transfere para ele um problema que
// não é dele resolver.
const PROIBIDAS = [
  "openai", "gemini", "google", "n8n", "supabase", "postgres", "api", "token",
  "http", "json", "workflow", "endpoint", "timeout", "rate limit", "payload",
  "null", "undefined", "exception", "stack", "query", "sql", "webhook",
  "credencial", "provedor",
];

function textoVisivel(e: FalhaExplicada): string {
  return `${e.titulo} ${e.explicacao} ${e.oQueFazer}`.toLowerCase();
}

const TODAS: FalhaExplicada[] = [
  ...CAUSAS_REAIS.map(([etapa, mensagem]) => explicarFalha({ etapa, mensagem })),
  explicarFalha({ etapa: "Fatiar Extracao", mensagem: "Cannot read properties of undefined" }),
  explicarParada({ processados: 12, esperados: 38 }),
  explicarParada({ processados: 0, esperados: 38 }),
  explicarLoteVazio({ comLinhas: 0, documentos: 38 })!,
  explicarLoteVazio({ comLinhas: 5, documentos: 38 })!,
];

for (const e of TODAS) {
  const texto = textoVisivel(e);
  const encontradas = PROIBIDAS.filter((p) => texto.includes(p));
  checar(encontradas.length === 0, `palavra técnica na tela: ${encontradas.join(", ")} — em "${e.titulo}"`);
}

// ---------------------------------------------------------------------------
// 3. Causas com AÇÕES OPOSTAS não podem cair na mesma explicação
// ---------------------------------------------------------------------------
//
// É a mesma disciplina de `diagnosticarErroApi`, e o motivo é o mesmo: "sem
// saldo" manda recolocar dinheiro, "teto de gasto" manda mexer numa
// configuração com o dinheiro lá. Dizer um pelo outro faz a pessoa procurar o
// problema no lugar errado — e voltar dizendo que está tudo certo.
const semSaldo = explicarFalha({ etapa: "IA Extrair", mensagem: "CONTA DO PROVEDOR SEM CRÉDITO" });
const tetoGasto = explicarFalha({ etapa: "IA Extrair", mensagem: "TETO DE GASTO ATINGIDO no provedor" });
checar(semSaldo.titulo !== tetoGasto.titulo, "sem saldo e teto de gasto dizem a mesma coisa");
checar(semSaldo.oQueFazer !== tetoGasto.oQueFazer, "sem saldo e teto de gasto mandam fazer a mesma coisa");

// E a recusa do orçamento é a única em que a ação é DO ANALISTA — ele divide o
// lote e resolve sozinho. Marcá-la como "chame o suporte" transformaria um
// autoatendimento de um minuto numa espera.
const orcamento = explicarFalha({ etapa: "orcamento", mensagem: "Lote recusado ANTES de gastar" });
checar(orcamento.quemResolve === "voce", "a recusa por tamanho de lote é resolvível pelo próprio analista");
checar(
  explicarFalha({ etapa: "IA Extrair", mensagem: "CHAVE DO PROVEDOR INVÁLIDA" }).quemResolve === "suporte",
  "acesso recusado não é coisa que o analista resolva",
);

// ---------------------------------------------------------------------------
// 4. A genérica é REDE, e ainda responde as três perguntas
// ---------------------------------------------------------------------------
const generica = explicarFalha({ etapa: "Nó Que Ninguém Previu", mensagem: "algo completamente novo" });
checar(generica.titulo.toLowerCase().includes("problema técnico"), "a genérica diz que parou");
checar(
  generica.explicacao.toLowerCase().includes("não foi nada que você fez"),
  "a genérica tira a culpa de quem está lendo",
);
checar(
  generica.explicacao.toLowerCase().includes("não se perderam"),
  "a genérica diz que os arquivos estão salvos — é a pergunta seguinte de quem lê",
);

// ---------------------------------------------------------------------------
// 5. O lote vazio, e o limiar declarado
// ---------------------------------------------------------------------------
checar(explicarLoteVazio({ comLinhas: 38, documentos: 38 }) === null, "lote inteiro lido não vira aviso");
checar(explicarLoteVazio({ comLinhas: 0, documentos: 0 }) === null, "lote sem documento nenhum não vira aviso");
checar(
  explicarLoteVazio({ comLinhas: 19, documentos: 38 }) === null,
  `metade lida está no limiar (${FRACAO_MINIMA_COM_LINHAS}) e não vira aviso`,
);
checar(explicarLoteVazio({ comLinhas: 18, documentos: 38 }) !== null, "abaixo da metade vira aviso");
checar(
  explicarLoteVazio({ comLinhas: 0, documentos: 38 })!.titulo
    !== explicarLoteVazio({ comLinhas: 5, documentos: 38 })!.titulo,
  "nada lido e pouco lido são notícias diferentes",
);

// A parada precisa dizer QUANTO andou: "parou" sozinho não diz se dá para
// aproveitar o que já entrou.
checar(
  explicarParada({ processados: 12, esperados: 38 }).explicacao.includes("12"),
  "a parada diz quantos arquivos chegaram a ser organizados",
);
checar(
  explicarParada({ processados: 12, esperados: 38 }).oQueFazer.toLowerCase().includes("não reenvie"),
  "a parada avisa para não reenviar antes de saber a causa — reenviar pode duplicar",
);

// ---------------------------------------------------------------------------
// 5. A ESPERA DO LOTE — a outra forma de a tela mentir no dia ruim
// ---------------------------------------------------------------------------
//
// A mensagem de falha responde "o que aconteceu". Estas contas respondem, antes
// dela, "aconteceu alguma coisa?" — e erram para os dois lados: curtas demais,
// declaram parada sobre um lote vivo (e o analista reenvia, pagando a IA duas
// vezes); longas demais, devolvem a espera eterna que a 0108 existe para acabar.
//
// A CADÊNCIA VEM DO WORKFLOW, não de um número repetido aqui: é o mesmo
// `batchInterval` que o nó de classificação tem em produção. O JSON do workflow
// é dado, não código — lê-lo daqui não cruza a fronteira de build que impede o
// portal de importar `N8N/lib/*.mjs`.
const workflow = JSON.parse(
  readFileSync(new URL("../../N8N/workflow.e1-ingestao.json", import.meta.url), "utf8"),
) as { nodes: Array<{ name: string; parameters: Record<string, unknown> }> };
const noClassificar = workflow.nodes.find((n) => n.name === "IA Classificar")!;
const cadenciaS =
  (noClassificar.parameters as { options: { batching: { batch: { batchInterval: number } } } })
    .options.batching.batch.batchInterval / 1000;

// O SILÊNCIO INICIAL É UMA BARREIRA, não uma fila: `Juntar Ramos` (mode append)
// só emite quando a ÚLTIMA classificação volta, então o pior caso de um lote de
// N arquivos é N chamadas espaçadas pela cadência — nenhum documento é
// registrado antes disso, e é isso que a tela mede.
for (const n of [2, 38, 190]) {
  const piorSilencioMs = n * cadenciaS * 1000;
  checar(
    semPrimeiroSinalMs(n) > piorSilencioMs,
    `lote de ${n}: a tela desiste em ${(semPrimeiroSinalMs(n) / 60000).toFixed(1)} min e o silêncio `
      + `legítimo da barreira vai a ${(piorSilencioMs / 60000).toFixed(1)} min`,
  );
}

// E O LOTE DE 38 NÃO PODE GANHAR FOLGA — mas a RÉGUA dessa folga mudou, e a
// mudança é honesta.
//
// Até 11/09/2026 este assert comparava com **8 minutos fixos**, calibrados
// contra duas rodadas reais (v47/v48). Aquelas rodadas foram no `gpt-4o`, e
// depois no Gemini, com cadência de 8s por chamada. Hoje o provedor é a OpenAI
// com `gpt-5.6-luna`, e a cadência passou a SOMAR o token de entrada à reserva
// de saída (um PDF de 20 páginas são ~20.000 tokens de imagem além dos 16.384
// reservados, contra 30.000 TPM). A cadência real subiu para dezenas de
// segundos, e um lote de 38 leva mesmo ~30 min até o primeiro sinal.
//
// Ou seja: os 8 minutos não descrevem mais fenômeno nenhum — eles descrevem um
// provedor que saiu. Manter o número seria reprovar a tela por ela ter passado
// a dizer a VERDADE sobre a espera, que é o oposto do que este arquivo protege.
//
// O QUE SOBREVIVE, e é o que se afirma agora: a conta da tela não pode inventar
// folga ALÉM da que a cadência implica. Ela continua sendo `n × (cadência +
// preparo)`, e o teto é essa mesma conta com 10% de margem — o mesmo 1,1 de
// antes. Isso pega alguém acrescentando um fator de segurança arbitrário (o
// defeito real), e deixa passar a tela acompanhar a cadência (o certo).
const fonteEspera = readFileSync(
  new URL("../src/lib/espera-do-lote.ts", import.meta.url), "utf8");
const mCad = /const CADENCIA_IA_S = (\d+);/.exec(fonteEspera);
const mPre = /const PREPARO_POR_ARQUIVO_S = (\d+);/.exec(fonteEspera);
checar(!!mCad && !!mPre,
  "CADENCIA_IA_S/PREPARO_POR_ARQUIVO_S sumiram do fonte — o espelho perdeu o outro lado");
// O ESPELHO ESQUECEU O PISO DA PRÓPRIA FUNÇÃO, e a troca de TPM de 14/09/2026
// (30.000 → 500.000) expôs isso: `semPrimeiroSinalMs` é
// `max(SEM_PRIMEIRO_SINAL_MINIMO_MS, n × cadência)` — um PISO de UX que existe
// por conta própria (não panicar com jitter de rede num lote pequeno),
// independente de quão rápida a IA está. Comparar só contra `n × cadência`,
// sem o mesmo piso, faz este teste acusar "folga inventada" exatamente quando
// a IA fica RÁPIDA o bastante para o piso passar a dominar — que é o piso
// fazendo o trabalho dele, não um defeito. `SEM_PRIMEIRO_SINAL_MINIMO_MS` entra
// aqui pelo MESMO regex-no-fonte que os outros dois, para o espelho não travar
// um terceiro número por conta própria.
const mPiso = /const SEM_PRIMEIRO_SINAL_MINIMO_MS = (\d+) \* 60 \* 1000;/.exec(fonteEspera);
checar(!!mPiso, "SEM_PRIMEIRO_SINAL_MINIMO_MS sumiu do fonte, ou mudou de forma — o espelho perdeu o piso");
const pisoMs = Number(mPiso![1]) * 60 * 1000;
const cadenciaImplicadaMs = Math.max(pisoMs, 38 * (Number(mCad![1]) + Number(mPre![1])) * 1000);
checar(
  semPrimeiroSinalMs(38) <= cadenciaImplicadaMs * 1.1,
  `o lote de 38 ganhou folga ALÉM do maior entre o piso e a cadência: `
  + `${(semPrimeiroSinalMs(38) / 60000).toFixed(1)} min contra os `
  + `${(cadenciaImplicadaMs / 60000).toFixed(1)} min que o piso de ${mPiso![1]} min ou a cadência de `
  + `${mCad![1]}s + ${mPre![1]}s de preparo implicam`,
);

// A JANELA TOTAL tem de entregar a margem que ela promete no lote de 190 — o
// teto de 90 minutos truncava 152 em 90, e a margem de 3x virava 1,77x sem que
// nada dissesse. Um lote que andasse a 28s por documento (contra os 16 medidos)
// veria a tela desistir viva.
for (const n of [38, 190]) {
  const previstoMs = n * SEGUNDOS_POR_DOCUMENTO * 1000;
  checar(
    janelaPara(n) >= previstoMs * 3,
    `lote de ${n}: a janela entrega ${(janelaPara(n) / previstoMs).toFixed(2)}x do previsto, e a tela promete 3x`,
  );
}

// ---------------------------------------------------------------------------
// A ESTIMATIVA CONTRA UMA RODADA CRONOMETRADA — o portão que faltava
// ---------------------------------------------------------------------------
//
// O DEFEITO, achado pelo dono NA TELA em 16/09/2026, durante a rodada real do
// "Teste 00": o portal prometia ~5 minutos para um lote que levava muito mais.
// `SEGUNDOS_POR_DOCUMENTO` valia 6 — a cadência de UMA chamada de IA — quando o
// custo real de um documento de ponta a ponta (upload, texto, medição,
// classificação, extração, escritas) é ~20s.
//
// POR QUE NENHUM PORTÃO PEGOU, e é isto que este bloco conserta. O único assert
// que existia (`N8N/test/workflow-sim.test.mjs`) confere a estimativa contra o
// `batchInterval` do nó e aceita qualquer valor entre 1x e 4x a cadência — e o 6
// estava DENTRO da faixa. Medido nesta correção, com o valor antigo no lugar:
// `workflow-sim.test.mjs` passou 115 asserts e esta suíte passou 66, zero
// falhas nas duas. A faixa protege contra a estimativa descolar da CADÊNCIA; o
// defeito que o dono viu era descolar do RELÓGIO, e ninguém olhava para o
// relógio.
//
// O QUE ESTE ASSERT AFIRMA é COMPORTAMENTO (regra 3), não mecanismo: a tela
// nunca promete um tempo menor do que uma rodada real já levou. Ele não refaz a
// aritmética das chamadas — refazer essa conta é o que errou nas quatro
// recalibrações anteriores documentadas em `espera-do-lote.ts`.
//
// AS RODADAS SÃO MEDIDAS, NÃO INVENTADAS (regra 4): duração cronometrada da
// execução no n8n, cruzada com o `lote_execucao` gravado dentro da mesma janela.
// As duas são posteriores à correção do TPM, no regime de cadência que vale hoje.
//
// SÃO DUAS, E NÃO UMA, POR UM MOTIVO MEDIDO: a primeira versão deste portão
// (mesma sessão, algumas horas antes) tinha só a #7747, e a estimativa que ela
// sozinha justificava — 20s por documento — já nasceu curta. A #7851, o lote 1
// real do "Teste 00", veio a 25,2s e desmentiu. Uma rodada só descreve uma
// rodada; o que a tela promete tem de cobrir o PIOR caso já visto.
const RODADAS_CRONOMETRADAS = [
  { documentos: 44, segundos: 869, qual: "#7747, 14/09/2026" },
  { documentos: 49, segundos: 1237, qual: "#7851, 16/09/2026 (lote 1 do Teste 00)" },
];
for (const r of RODADAS_CRONOMETRADAS) {
  const estimadoS = estimativaEmMinutos(r.documentos) * 60;
  checar(
    estimadoS >= r.segundos,
    `a tela promete ${(estimadoS / 60).toFixed(0)} min para ${r.documentos} documentos, e a `
    + `rodada real (${r.qual}) levou ${(r.segundos / 60).toFixed(1)} min `
    + `— prometer mais rápido do que o já medido faz o analista ler o atraso como travamento`,
  );
  // O TETO existe para o assert não virar decoração no sentido oposto: prometer
  // o dobro do medido devolve o defeito de 24/08 (a tela dizia 29 minutos para
  // um lote de 8) por outro caminho.
  checar(
    estimadoS <= r.segundos * 2,
    `a tela promete ${(estimadoS / 60).toFixed(0)} min contra os `
    + `${(r.segundos / 60).toFixed(1)} min medidos (${r.qual}) `
    + `— mais que o dobro é o defeito de 24/08 ao contrário`,
  );
}

// A PARADA POR FALTA DE AVANÇO TAMBÉM CRESCE COM O LOTE — e este bloco existia
// dizendo exatamente o contrário.
//
// A versão anterior travava `SEM_PROGRESSO_MS === 5 minutos` com a justificativa
// "depois do primeiro documento o progresso anda a cada extração". **A premissa
// é falsa, e a rodada de 190 de 27/08/2026 a desmentiu com relógio:**
//
//   20:55:12  os 190 documentos registrados, TODOS no mesmo instante
//   21:24     as 13.942 linhas gravadas, TODAS no mesmo minuto
//
// O progresso NÃO anda a cada extração. Ele anda em DOIS SALTOS, porque nó do
// n8n não é streaming e os dois merges (`Juntar Ramos`, `Juntar Extraidos`) são
// barreiras. Entre um salto e outro corre o `IA Extrair` inteiro — N chamadas à
// cadência do nó — e nada é escrito no banco por construção.
//
// Ou seja: o silêncio do MEIO tem a mesma forma do silêncio INICIAL, e a
// distinção que este assert protegia não existe. Aos 21:00 a tela declarou "o
// sistema parou por um problema técnico" sobre um lote vivo.
//
// O que se trava agora é a propriedade, não o número: o limite tem de ser MAIOR
// que o silêncio legítimo da segunda barreira, em cada tamanho de lote.
for (const n of [2, 38, 190]) {
  const silencioDaExtracaoMs = n * cadenciaS * 1000;
  checar(
    semProgressoMs(n) > silencioDaExtracaoMs,
    `lote de ${n}: a tela declara parada em ${(semProgressoMs(n) / 60000).toFixed(1)} min e a `
      + `barreira da extração cala por ${(silencioDaExtracaoMs / 60000).toFixed(1)} min`,
  );
}

// E O PISO CONTINUA SENDO O 5 ANTIGO: o lote pequeno não pode PERDER vigilância
// por causa de uma correção feita para o lote grande.
checar(
  semProgressoMs(1) === 5 * 60 * 1000 && semProgressoMs(0) === 5 * 60 * 1000,
  "o piso de 5 minutos sumiu: lote pequeno passou a esperar mais do que esperava antes",
);

// ---------------------------------------------------------------------------
// 6. O LOTE QUE NÃO FECHOU, E O LOTE QUE TROUXE FATO EM VEZ DE LINHA
// ---------------------------------------------------------------------------
//
// Os dois nasceram da mesma tela, em 27/08/2026, e apontam para lados opostos:
// um é a tela dizendo SUCESSO sobre uma execução morta, o outro seria a tela
// dizendo FRACASSO sobre o lote que funcionou pela primeira vez.

// (a) A execução morreu no `Upload Storage` e o portal disse "Tudo pronto".
// O registro de falha depende do Error Workflow do n8n, que é passo manual e
// não está ligado — então a rota passou a exigir o FECHAMENTO do lote, e a
// falta dele chega aqui como uma falha de etapa `lote_nao_fechou`.
checar(
  explicarFalha({ etapa: "lote_nao_fechou", mensagem: "O lote não fechou: os 2 documento(s) foram lidos, mas o processamento não chegou ao fim (nenhum registro de encerramento do lote foi gravado)." })
    .titulo.toLowerCase().includes("parou antes de terminar"),
  "o lote que não fechou tem explicação própria, e não cai na genérica",
);
checar(
  explicarFalha({ etapa: "lote_nao_fechou", mensagem: "" }).oQueFazer.includes("Varoto"),
  "o lote que não fechou diz com quem falar",
);

// (b) A CAUSA DESCONHECIDA agora nomeia quem resolve. "Contate o suporte" é um
// beco quando a equipe é uma pessoa; o dono pediu o nome, literalmente.
const desconhecida = explicarFalha({ etapa: "algo novo", mensagem: "erro que ninguém previu" });
checar(
  desconhecida.oQueFazer.includes("Varoto"),
  `a falha sem causa conhecida diz com quem falar — hoje diz: "${desconhecida.oQueFazer}"`,
);
checar(
  !desconhecida.titulo.toLowerCase().includes("tudo pronto"),
  "a falha sem causa conhecida jamais se parece com sucesso",
);

// (c) ZERO LINHA COM FATO NÃO É LOTE VAZIO. Medido no smoke test: Notas
// Explicativas e Parecer do Auditor renderam 0 linhas e 9 fatos materiais, que
// é o resultado CERTO — esses documentos dizem as coisas em texto. Uma checagem
// que só conta linha acusaria justamente o lote que funcionou.
checar(
  explicarLoteVazio({ comLinhas: 0, comFatos: 2, documentos: 2 }) === null,
  "o lote que rendeu só FATOS (Notas Explicativas + Parecer) foi acusado de vazio",
);
// e sem fato nenhum ele continua sendo acusado, que é o ponto.
const vazioDeVerdade = explicarLoteVazio({ comLinhas: 0, comFatos: 0, documentos: 2 });
checar(
  vazioDeVerdade !== null && vazioDeVerdade.titulo.toLowerCase().includes("nada pôde ser lido"),
  "o lote sem linha E sem fato deixou de ser acusado",
);
checar(
  vazioDeVerdade !== null && vazioDeVerdade.oQueFazer.includes("Varoto"),
  "o lote sem nada dentro diz com quem falar",
);
checar(
  vazioDeVerdade !== null && vazioDeVerdade.oQueFazer.toLowerCase().includes("descartado"),
  "o lote sem nada dentro diz que pode ser descartado — é o mandato vazio que o dono não quer na lista",
);
// A omissão de `comFatos` não pode mudar o veredito de quem já chamava a função
// só com linhas: ausente é zero, não "não sei".
checar(
  explicarLoteVazio({ comLinhas: 0, documentos: 2 }) !== null,
  "sem `comFatos`, o lote sem linha nenhuma deixou de ser acusado",
);

// ---------------------------------------------------------------------------
// 7. O VEREDITO DO LOTE — a decisão que dizia "Tudo pronto" sobre uma execução morta
// ---------------------------------------------------------------------------
const AGORA = Date.parse("2026-08-27T12:00:00Z");
const HA_DEZ_MINUTOS = AGORA - 10 * 60 * 1000;
const AGORINHA = AGORA - 5 * 1000;
const lote = (over: Partial<Parameters<typeof vereditoDoLote>[0]>) => vereditoDoLote({
  classificados: 2, processados: 2, esperados: 2,
  loteFechou: true, desdeMs: HA_DEZ_MINUTOS, agoraMs: AGORA, ...over,
});

checar(lote({}).estado === "pronto", "o lote que fechou com tudo lido tem de ficar pronto");
checar(lote({ processados: 1 }).estado === "andando", "lote com documento faltando não é pronto nem falha");

// O CASO DO DONO: contadores completos, lote NUNCA fechado. Antes isto era
// "pronto"; agora é falha nomeada.
checar(lote({ loteFechou: false }).estado === "nao_fechou",
  "a execução que morreu sem fechar o lote voltou a ser reportada como sucesso");

// A CARÊNCIA: um lote saudável passa alguns segundos com os contadores
// completos e o fechamento ainda não gravado. Acusar aí seria alarme falso em
// QUALQUER lote — o alarme que ensina a ignorar o alarme.
checar(lote({ loteFechou: false, desdeMs: AGORINHA }).estado === "andando",
  "a carência sumiu: todo lote saudável passaria a acusar falha no instante entre o último documento e o fechamento");
// A CARÊNCIA TAMBÉM CRESCE, pela mesma razão. O comentário dela dizia que a
// cauda do workflow "leva segundos" — verdade em 38 documentos, e na rodada de
// 190 o `Reconciliar` sozinho passou de uma hora. A 0152 corrigiu a causa; o
// número aqui continuava descrevendo o lote em que foi calibrado.
checar(carenciaDoFechamentoMs(2) >= 60 * 1000,
  "a carência do fechamento ficou curta demais para a cauda do workflow");
checar(carenciaDoFechamentoMs(190) > carenciaDoFechamentoMs(38),
  "a carência do fechamento não cresce com o lote — a cauda é O(documentos) e ela não pode ser fixa");
checar(carenciaDoFechamentoMs(2) === 2 * 60 * 1000,
  "o piso de 2 minutos da carência sumiu: lote pequeno passou a acusar antes do que acusava");

// "NÃO SEI" NUNCA ACUSA. Se a consulta do fechamento falhar, o lote não pode
// virar falha por causa da conferência — é a mesma regra que o `comLinhas` já
// aplicava.
checar(lote({ loteFechou: null }).estado === "pronto",
  "uma consulta que falhou passou a derrubar um lote que terminou de verdade");

// ---------------------------------------------------------------------------
// CUSTOS (aba da Administração) — o custo que falta não vira "US$ 0,00".
// Os lotes abaixo são ARRANJO DE TESTE da regra (null não soma como zero), não
// reprodução de um lote real: não afirmam nenhum valor de produção (regra 4).
const AGORA_DOS_CUSTOS = new Date("2026-10-28T12:00:00Z");
const lc = (caso: string, dias: number, docs: number | null, custo: number | string | null): LoteDeCusto => ({
  caso_id: caso, documentos: docs, custo_total_usd: custo,
  criado_em: new Date(AGORA_DOS_CUSTOS.getTime() - dias * 86_400_000).toISOString(),
});
{
  // A tem um lote medido e um SEM custo; B só tem lote sem custo; C só tem lote fora do período.
  const ag = agregarCustos([
    lc("A", 1, 10, 0.5), lc("A", 2, 100, null), lc("B", 3, 5, null), lc("C", 60, 4, 2),
  ], AGORA_DOS_CUSTOS, 30);
  const A = ag.porMandato.find((m) => m.casoId === "A")!;
  const B = ag.porMandato.find((m) => m.casoId === "B")!;
  const C = ag.porMandato.find((m) => m.casoId === "C")!;
  checar(A.periodo.custoUsd === 0.5 && A.periodo.semCusto === 1,
    "o lote sem custo foi somado como zero (ou sumiu sem ser contado): o total deixou de ser piso declarado");
  checar(Math.abs((A.periodo.custoPorDocumentoUsd ?? Number.NaN) - 0.05) < 1e-9,
    "o custo por documento dividiu pelos documentos do lote SEM custo (100) — numerador e denominador de conjuntos diferentes");
  checar(B.periodo.custoUsd === null && B.periodo.custoPorDocumentoUsd === null,
    "mandato só com lote sem custo mostrou número em vez de ausência");
  checar(C.periodo.lotes === 0 && C.periodo.custoUsd === null && C.total.custoUsd === 2,
    "lote fora da janela entrou no período, ou o total desde o início o perdeu");
  checar(ag.porMandato[0].casoId === "A" && ag.porMandato[ag.porMandato.length - 1].casoId === "B",
    "mandato sem custo medido subiu na ordenação, acima de um com custo");
  checar(ag.periodo.custoUsd === 0.5 && ag.total.custoUsd === 2.5,
    "a soma geral não bate com a soma dos mandatos (período 0,5 / total 2,5)");
  checar(somarCustos([]).custoUsd === null && somarCustos([]).lotes === 0,
    "conjunto vazio devolveu zero em vez de ausência");
  checar(somarCustos([lc("A", 0, 3, "1.25")]).custoUsd === 1.25,
    "numeric em texto (como o Postgres pode entregar) não foi lido como número");
  checar(somarCustos([lc("A", 0, 3, "abc"), lc("A", 0, 3, -1)]).custoUsd === null,
    "custo ilegível ou negativo foi aceito como valor");
  // Motivo próprio por causa da ausência (arranjo de teste da lógica, não lote real).
  const sem = (ls: LoteDeCusto[]) => somarCustos(ls);
  const mDoc = motivoDaAusencia(sem([lc("A", 0, null, 1), lc("A", 0, 0, 2)]), "custoPorDocumentoUsd") ?? "";
  checar(/documentos processados não registrados/.test(mDoc) && !/custo não registrado/.test(mDoc),
    "custo com documentos nulos/0 foi explicado como 'custo não registrado'");
  checar(motivoDaAusencia(sem([lc("A", 0, 3, null)]), "custoPorDocumentoUsd") === "custo não registrado",
    "lote sem custo perdeu o motivo 'custo não registrado'");
  checar(/ilegível ou negativo/.test(motivoDaAusencia(sem([lc("A", 0, 3, -1)]), "custoUsd") ?? "")
    && /ilegível ou negativo/.test(motivoDaAusencia(sem([lc("A", 0, 3, "abc")]), "custoPorDocumentoUsd") ?? ""),
    "custo negativo/ilegível foi chamado de 'não registrado'");
  checar(motivoDaAusencia(sem([]), "custoUsd") === "sem execução no período" && motivoDaAusencia(sem([lc("A", 0, 3, 1)]), "custoUsd") === null,
    "motivo de conjunto vazio errado, ou motivo devolvido onde há valor");
  checar(formatarUsd(null) === null && formatarUsd(0.0523) === "US$ 0,0523" && formatarUsd(12.3) === "US$ 12,30",
    "formatação de dólar: null tem de seguir null, e centavos pequenos precisam de 4 casas");
}

// ---------------------------------------------------------------------------
// 6. O histórico do mandato (0215): palavra da tela sobre o que o banco devolve
// ---------------------------------------------------------------------------
//
// Cada assert nasceu de uma forma de mentir: sumir com o tipo que o mapa não conhece, escrever
// "Sistema" onde o banco só não sabe quem foi, e contar o dia em UTC (22h de SP já é o dia seguinte).
checar(rotuloDoTipo("tipo_que_ainda_nao_existe") === "tipo_que_ainda_nao_existe",
  "tipo desconhecido sumiu ou foi renomeado em vez de aparecer cru");
checar(categoriaDoTipo("tipo_que_ainda_nao_existe") === "outros",
  "tipo desconhecido não caiu em 'outros' (e sairia de todo filtro)");
checar(rotuloDoTipo("documento_recebido") === "Documento recebido" && rotuloDoTipo("caso_fechado") === "Mandato fechado",
  "rótulo humano de tipo conhecido errado");
checar(categoriaDoTipo("pergunta_enviada") === "perguntas" && categoriaDoTipo("pergunta_descartada") === "perguntas"
  && categoriaDoTipo("premissa_aplicada_em_lote") === "modelagem" && categoriaDoTipo("perimetro_alterado") === "grupo"
  && categoriaDoTipo("pendencia_decidida") === "pendencias" && categoriaDoTipo("extracao_aceita") === "documentos"
  && categoriaDoTipo("caso_aprovado") === "mandato",
  "categoria de tipo conhecido errada");
checar(textoDoAutor("pendencia_decidida", null) === "Sistema",
  "autor nulo fora do recebimento deveria ser 'Sistema' (a 0215 anula sistema:* e n8n*)");
checar(textoDoAutor("documento_recebido", null) !== "Sistema" && /não registrado/i.test(textoDoAutor("documento_recebido", null)),
  "autor nulo no recebimento virou 'Sistema': a tabela não guarda quem enviou, o texto tem de dizer 'não registrado'");
checar(textoDoAutor("pergunta_enviada", "ana@oria.com") === "ana@oria.com",
  "autor gravado não foi mostrado como veio");
checar(!/^portal:/.test(textoDoAutor("pergunta_enviada", "portal:desconhecido")),
  "'portal:desconhecido' vazou cru para a tela");
// 28/10/2026 01:30 UTC = 27/10 22:30 em São Paulo: o dia é 27, não 28.
checar(chaveDoDia("2026-10-28T01:30:00.123456+00:00") === "2026-10-27",
  "dia calculado em UTC: evento das 22h30 de SP foi para o dia seguinte");
{
  const dias = agruparPorDia([
    { em: "2026-10-28T13:00:00+00:00", n: 1 }, { em: "2026-10-28T01:30:00+00:00", n: 2 },
    { em: "2026-10-27T20:00:00+00:00", n: 3 }, { em: "2026-10-26T12:00:00+00:00", n: 4 },
  ]);
  checar(dias.length === 3 && dias[0].eventos.length === 1 && dias[1].eventos.length === 2 && dias[2].eventos.length === 1,
    "agrupamento por dia (fuso de SP) errado: esperado 1 + 2 + 1 em três dias");
  checar(dias.flatMap((d) => d.eventos.map((e) => e.n)).join() === "1,2,3,4",
    "o agrupamento perdeu ou reordenou eventos");
  checar(agruparPorDia([]).length === 0, "lista vazia deveria dar zero dias");
}
checar(funcaoAusente({ code: "42883" }) && funcaoAusente({ code: "PGRST202" }) && !funcaoAusente({ code: "57014" }) && !funcaoAusente(null),
  "detecção de função ausente: 42883 e PGRST202 sim, qualquer outro erro não");
checar(cursorValido("2026-10-28T13:00:00.123456+00:00") && !cursorValido("ontem") && !cursorValido("2026-10-28' or 1=1") && !cursorValido(undefined),
  "cursor da URL: o formato do banco passa, lixo não");

// --- 0215 corrigida (1b25441): cursor composto, autor pela bandeira do banco, "salva" e não "preenchida" ---
// O cursor é o `em` E a `chave` da última linha mostrada. Sem a chave, paginar só por instante perde o
// segundo evento de um empate (a apresentação salva todos os campos com o mesmo `preenchido_em`).
{
  const EM = "2026-10-28T13:00:00.123456+00:00";
  const lido = lerCursor(EM, "decisao:7f3a");
  checar(lido.situacao === "pagina" && lido.antes === EM && lido.chave === "decisao:7f3a",
    "cursor composto válido não foi lido com em e chave como vieram");
  checar(lerCursor(undefined, undefined).situacao === "inicio", "sem cursor deveria ser a primeira página");
  checar(lerCursor(EM, undefined).situacao === "recusado",
    "cursor só com `em` (sem chave) foi aceito: paginaria por instante e perderia empate");
  checar(lerCursor(undefined, "decisao:7f3a").situacao === "recusado", "chave sem `em` foi aceita");
  checar(lerCursor(EM, "").situacao === "recusado" && lerCursor(EM, "   ").situacao === "recusado",
    "chave vazia ou em branco foi aceita");
  checar(lerCursor(EM, "x".repeat(301)).situacao === "recusado" && lerCursor(EM, "x".repeat(300)).situacao === "pagina",
    "o teto de 300 caracteres da chave não vale");
  checar(lerCursor(EM, "evento:1\n2").situacao === "recusado" && !chaveDeCursorValida("a\u0000b"),
    "chave com caractere de controle foi aceita");
  checar(lerCursor("ontem", "evento:1").situacao === "recusado", "`em` inválido com chave válida foi aceito");
  // A chave real tem `:` e pode ter e-mail e espaço (`vinculo:<epoch>:<e-mail>`, `apresentacao:<campo>`).
  checar(chaveDeCursorValida("vinculo:1761656400.123456:ana@oria.com") && chaveDeCursorValida("apresentacao:visão geral"),
    "chave real com ':', '@' ou espaço foi recusada");
  // O link volta com os microssegundos inteiros e a chave codificada, e é lido de volta igual.
  const href = hrefDosMaisAntigos("c1", { em: EM, chave: "vinculo:1:ana@oria.com" });
  const q = new URL(href, "http://x").searchParams;
  const volta = lerCursor(q.get("antes") ?? undefined, q.get("chave") ?? undefined);
  checar(volta.situacao === "pagina" && volta.antes === EM && volta.chave === "vinculo:1:ana@oria.com" && href.includes("&chave="),
    "o link de 'Carregar mais antigos' não leva em e chave íntegros (microssegundos ou chave perdidos)");
}
// Autor: a bandeira do banco manda; o tipo é só rede.
checar(/^Automático/.test(textoDoAutor("extracao_aceita", null, { automatico: true })),
  "auto-aceite (autor nulo + automatico) não ganhou texto próprio");
checar(textoDoAutor("extracao_aceita", null, { automatico: true }) !== "Sistema"
  && textoDoAutor("extracao_aceita", null, {}) === "Sistema",
  "auto-aceite virou 'Sistema' genérico, ou o nulo sem bandeira deixou de ser 'Sistema'");
checar(/não registrado/i.test(textoDoAutor("qualquer_tipo", null, { autor_desconhecido: true })),
  "autor_desconhecido não foi lido da referência (só o tipo valia)");
checar(/não registrado/i.test(textoDoAutor("documento_recebido", null, null)) && /não registrado/i.test(textoDoAutor("documento_recebido", null, "lixo")),
  "sem a bandeira, o fallback por tipo do recebimento sumiu");
checar(textoDoAutor("extracao_aceita", "ana@oria.com", { automatico: true }) === "ana@oria.com",
  "autor gravado perdeu para a bandeira: pessoa nomeada tem de aparecer");
checar(textoDoAutor("extracao_aceita", null, { automatico: "true" }) === "Sistema",
  "bandeira que não é o booleano true foi tratada como verdadeira");
// Rótulo: "salva" (último salvamento), e o nome antigo não afirma autoria do conteúdo.
checar(/salva/i.test(rotuloDoTipo("apresentacao_salva")) && !/preenchid/i.test(rotuloDoTipo("apresentacao_salva"))
  && categoriaDoTipo("apresentacao_salva") === "modelagem",
  "apresentacao_salva sem rótulo de salvamento ou fora de 'modelagem'");
checar(rotuloDoTipo("apresentacao_preenchida") === "apresentacao_preenchida" && categoriaDoTipo("apresentacao_preenchida") === "outros",
  "o nome antigo apresentacao_preenchida deveria cair cru em 'Outros', não ser rotulado como autoria");

// ---------------------------------------------------------------------------
// 7. CASCO — modo discrição e barra inferior do celular (Fase 4)
// ---------------------------------------------------------------------------
//
// O defeito que esta seção impede é SILENCIOSO: o modo ligado e um número financeiro nítido na
// tela, diante de terceiros. Ele nasce de três lados — a preferência que não liga (ou liga só
// depois da pintura), o CSS que o hover/foco desfaz, e a tela nova que mostra valor sem marcar.
// Não há DOM neste harness: a preferência e o script do <head> são EXECUTADOS; o CSS e as
// marcações são conferidos no texto dos arquivos, e dizem isso.
const armazemFalso = (inicial: Record<string, string> = {}) => {
  const m = new Map(Object.entries(inicial));
  return { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => void m.set(k, v) };
};
const armazemQueRecusa = {
  getItem: (): string | null => { throw new Error("SecurityError"); },
  setItem: (): void => { throw new Error("QuotaExceededError"); },
};
checar(discricaoLigada("1") && !discricaoLigada(null) && !discricaoLigada(undefined) && !discricaoLigada("")
  && !discricaoLigada("0") && !discricaoLigada("true"),
  "só o texto '1' pode ligar o modo discrição; qualquer outra coisa (ausente, '0', 'true') = desligado");
checar(!lerDiscricao(armazemFalso()) && lerDiscricao(armazemFalso({ [CHAVE_DISCRICAO]: "1" })),
  "padrão tem de ser DESLIGADO e '1' guardado tem de ligar");
checar(!lerDiscricao(armazemQueRecusa) && !lerDiscricao(null),
  "armazenamento bloqueado ou ausente tem de dar 'desligado', sem exceção");
{
  const a = armazemFalso();
  checar(gravarDiscricao(a, true) && lerDiscricao(a) && gravarDiscricao(a, false) && !lerDiscricao(a),
    "gravar e reler a preferência não fecha o ciclo ligar → desligar");
  checar(gravarDiscricao(armazemQueRecusa, true) === false && gravarDiscricao(null, true) === false,
    "gravar em armazenamento que recusa tem de devolver false, não lançar");
}
// O script inline do <head>, EXECUTADO como está no HTML, contra um <html> e um localStorage falsos.
const rodarScript = (ls: unknown) => {
  const atributos = new Map<string, string>();
  const doc = { documentElement: { setAttribute: (k: string, v: string) => void atributos.set(k, v) } };
  let lancou = false;
  try { new Function("localStorage", "document", SCRIPT_DISCRICAO_ANTES_DA_PINTURA)(ls, doc); } catch { lancou = true; }
  return { ligou: atributos.has(ATRIBUTO_DISCRICAO), lancou };
};
checar(rodarScript(armazemFalso({ [CHAVE_DISCRICAO]: "1" })).ligou,
  "o script do <head> não liga data-discricao com a preferência gravada: haveria flash de número nítido");
checar(!rodarScript(armazemFalso({ [CHAVE_DISCRICAO]: "0" })).ligou && !rodarScript(armazemFalso()).ligou,
  "o script do <head> ligou o modo sem preferência gravada");
checar(!rodarScript(armazemQueRecusa).lancou && !rodarScript(armazemQueRecusa).ligou,
  "armazenamento bloqueado derrubou o script do <head> ou ligou o modo");
checar(ATRIBUTO_DISCRICAO === "data-discricao", "o atributo do <html> mudou de nome: o CSS e o script se desencontram");

// CSS: o desfoque só existe com o modo ligado, e NADA o desfaz por hover ou foco (o objetivo é sigilo).
const css = readFileSync(new URL("../src/app/globals.css", import.meta.url), "utf8")
  .replace(/\/\*[\s\S]*?\*\//g, ""); // sem comentários: o texto deles cita o seletor
const regrasSensiveis = [...css.matchAll(/([^{}]*\.valor-sensivel[^{}]*)\{([^}]*)\}/g)];
checar(regrasSensiveis.length >= 1 && regrasSensiveis.some((r) => /filter:\s*blur\(/.test(r[2])
  && /html\[data-discricao\]\s+\.valor-sensivel/.test(r[1])),
  "globals.css não tem a regra html[data-discricao] .valor-sensivel com filter: blur()");
checar(regrasSensiveis.every((r) => /^\s*html\[data-discricao\]/.test(r[1].trim()) && !/:(hover|focus|active)/.test(r[1])
  && !/filter:\s*none/.test(r[2])),
  "uma regra de .valor-sensivel desfaz o desfoque (hover/foco/filter:none) ou borra com o modo desligado");

// Marcações: toda tela que formata VALOR financeiro o embrulha em .valor-sensivel.
const fonte = (c: string) => readFileSync(new URL(`../src/${c}`, import.meta.url), "utf8");
const marcacoes: Array<[string, RegExp, string]> = [
  ["components/documento-detalhe.tsx", /valor-sensivel[^>]*>\s*\{formatValor\(/, "coluna de valor do documento"],
  ["app/casos/[id]/modelagem/SecaoLinhas.tsx", /valor-sensivel[^>]*>\{fmt\.format\(l\.valor_ultimo\)/, "valor das linhas da Modelagem"],
  ["app/casos/[id]/modelagem/SugestoesDoRealizado.tsx", /valor-sensivel[^>]*>\{mostrado\}/, "premissa sugerida do realizado"],
  ["app/casos/[id]/modelagem/SugestoesDoRealizado.tsx", /valor-sensivel[^>]*>\s*\(\{num\(/, "numerador e denominador da sugestão"],
  ["app/casos/[id]/modelagem/page.tsx", /valor-sensivel[^"]*"[\s\S]{0,80}\/>|name=\{`valor_\$\{ano\}`\}[\s\S]{0,600}valor-sensivel/, "caixas de premissa por ano"],
  ["app/administracao/custos/page.tsx", /valor-sensivel[^>]*>\{txt\}/, "custo em US$"],
];
for (const [arq, re, o_que] of marcacoes) {
  checar(re.test(fonte(arq)), `${o_que} (${arq}) deixou de ser marcada com .valor-sensivel: o modo discrição não a borra`);
}
// A cola: o layout raiz injeta o script (não uma cópia) e tolera o atributo ligado antes da hidratação.
const raiz = fonte("app/layout.tsx");
checar(raiz.includes("SCRIPT_DISCRICAO_ANTES_DA_PINTURA") && raiz.includes("suppressHydrationWarning"),
  "o layout raiz não injeta o script do modo discrição (flash) ou perdeu o suppressHydrationWarning");

// Barra inferior: o destino ativo. Caminhos reais, com o UUID de um mandato.
const UUID = "0b9f2c1e-5a4d-4c8e-9f3b-7d6a1e2c3b4a";
const casosDestino: Array<[string, ReturnType<typeof destinoAtivo>]> = [
  ["/casos", "inicio"], ["/casos/", "inicio"], ["/casos?x=1", "inicio"],
  ["/casos/todos", "mandatos"], [`/casos/${UUID}`, "mandatos"], [`/casos/${UUID}/modelagem`, "mandatos"],
  [`/casos/${UUID.toUpperCase()}/documentos/x`, "mandatos"],
  ["/casos/novo", "novo"], ["/administracao", "mais"], ["/administracao/custos", "mais"],
  ["/login", null], ["/", null], ["/casos/nao-e-uuid", null], ["/administracaox", null], ["/casos/todos/lixo", null],
];
for (const [c, esperado] of casosDestino) {
  checar(destinoAtivo(c) === esperado, `destinoAtivo(${c}) = ${destinoAtivo(c)}, esperado ${esperado}`);
}
checar(idDoCaso(`/casos/${UUID.toUpperCase()}/x`) === UUID && idDoCaso("/casos/todos") === null,
  "idDoCaso: o id vem em minúsculas e 'todos'/'novo' não são mandato");
// Dentro do mandato as abas rolam na horizontal (celular): faixa com overflow e lista que não encolhe.
const abas = fonte("app/casos/[id]/abas-do-mandato.tsx");
checar(/<nav[^>]*overflow-x-auto/.test(abas) && /<ul[^>]*min-w-max/.test(abas) && abas.includes("whitespace-nowrap"),
  "as abas do mandato perderam a rolagem horizontal (overflow-x-auto / min-w-max / whitespace-nowrap)");

if (falhas.length > 0) {
  console.error(`\n${falhas.length} falha(s):`);
  for (const f of falhas) console.error(`  ✗ ${f}`);
  console.error(`\n${ok} verificações OK / ${falhas.length} falhas`);
  process.exit(1);
}
console.log(`${ok} verificações OK / 0 falhas`);
console.log("MENSAGEM DE FALHA OK — toda causa real tem explicação própria, e nenhuma cita ferramenta");
console.log("ESPERA DO LOTE OK — o silêncio da barreira e a janela cobrem o lote de 190");
console.log("FIM DO LOTE OK — execução morta não vira sucesso, e fato conta como conteúdo");
console.log("VEREDITO DO LOTE OK — pronto exige o lote FECHADO, com carência e sem acusar por \"não sei\"");
console.log("HISTÓRICO OK — tipo desconhecido aparece cru, nulo no recebimento é \"não registrado\" e o dia é o de São Paulo");
console.log("CASCO OK — o modo discrição liga antes da pintura, nada o desfaz por hover, e o destino ativo da barra inferior casa com a rota");
console.log("CUSTOS OK — custo ausente fica ausente, o total é piso declarado e o por-documento usa um só conjunto");
