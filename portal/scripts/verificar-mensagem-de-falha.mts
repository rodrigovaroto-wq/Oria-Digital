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
  ATRIBUTO_DISCRICAO, ATRIBUTO_TEMA, CHAVE_DISCRICAO, CHAVE_TEMA, SCRIPT_DISCRICAO_ANTES_DA_PINTURA,
  SCRIPT_TEMA_ANTES_DA_PINTURA, alvoDoRetornoDeFoco, armazem, ariaCurrentDoLink, aplicarTema, destinoAtivo, discricaoLigada, gravarDiscricao,
  gravarPreferenciaDeTema, idDoCaso, lerDiscricao, lerPreferenciaDeTema, preferenciaDeTema, temaEfetivo,
} from "../src/lib/casco.ts";
import {
  CHAVE_AVISOS_VISTOS, TETO_DE_VISTOS, TOLERANCIA_DO_RELOGIO_MS, classificarLote, pedeAtencao, vistosEfetivos, contarNaoVistos, gravarVistos, lerVistos, montarAvisos,
  nomeDoSino, unirVistos, ROTULO_DO_TIPO, type LoteLido,
} from "../src/lib/avisos-de-processamento.ts";
import { campoCarregaValor, CHAVES_APRESENTACAO } from "../src/lib/apresentacao/campos.ts";
import {
  ERRO_LINK, RESPOSTA_DO_PEDIDO, ROTAS_PUBLICAS, SENHA_MINIMA, caminhoInternoSeguro, mensagemDeRecuperacao,
  montarRedirectTo, origemDaRequisicao, rotaPublica, validarNovaSenha,
} from "../src/lib/recuperar-senha.ts";
import {
  MENSAGEM_NOME_DUPLICADO, MENSAGEM_SEM_ENVIO, MENSAGEM_SEM_PERMISSAO, MOTIVO_SEM_PAPEL, administracaoLiberada, decidirEnvioAoMandato,
  ehNegacaoDePermissao, escopoDaLista, interpretarPapel, permissoes, textoDeFalhaDaAcao, textoDeRecentesVazio,
  type AcessoLido,
} from "../src/lib/acesso.ts";
import { ehUuid, equipeDoMandato, linhasDaEquipe, pessoaDoUsuario } from "../src/lib/equipe.ts";
import { readFileSync, readdirSync } from "node:fs";
import { runInNewContext } from "node:vm";

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
  const q = new URL(href, "https://x").searchParams;
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
  // Num contexto V8 isolado (node:vm), com só `localStorage` e `document` visíveis — e não por
  // `new Function`, que roda no escopo do processo (Sonar S1523 no PR #265).
  try { runInNewContext(SCRIPT_DISCRICAO_ANTES_DA_PINTURA, { localStorage: ls, document: doc }); } catch { lancou = true; }
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

// VARREDURA, e não só as seis marcações acima: "toda tela que formata valor" tem de ser verdade
// para a tela que ninguém lembrou de listar. Percorre `src/**/*.tsx`; todo uso de um formatador de
// número (`formatValor(`, `formatarUsd(`, `fmt.format(`, `Intl.NumberFormat`, `toLocaleString("pt-BR"`)
// precisa ter `valor-sensivel` a até 600 caracteres, antes ou depois (o elemento ou o ancestral
// próximo; o formatador pode ficar numa `const` acima do JSX). O que NÃO é valor monetário entra na
// lista de exceções ABAIXO, uma a uma, com o motivo — e exceção que deixou de casar com o código
// reprova, para a lista não virar depósito.
const FORMATADORES = /formatValor\(|formatarUsd\(|\bfmt\.format\(|Intl\.NumberFormat|toLocaleString\(["']pt-BR["']/g;
const EXCECOES_DE_FORMATADOR: ReadonlyArray<readonly [arquivo: string, trecho: string, motivo: string]> = [
  ["components/upload-form.tsx", 'new Date(sucesso.desde).toLocaleString("pt-BR")', "data/hora do envio, não valor"],
  ["components/painel-zip.tsx", "progresso.indice.toLocaleString", "contagem de entradas do ZIP, não valor"],
  ["app/casos/[id]/page.tsx", 'linhasTotais.toLocaleString("pt-BR")', "contagem de linhas extraídas, não valor"],
  ["app/casos/[id]/documentos/(lista)/page.tsx", 'linhas.toLocaleString("pt-BR")', "contagem de linhas do documento, não valor"],
  ["app/casos/page.tsx", "const numero = (n: number) => n.toLocaleString", "contagens do painel (mandatos, pendências), não valor"],
  ["app/administracao/page.tsx", 'new Date(iso).toLocaleString("pt-BR"', "data/hora, não valor"],
  // DEFINIÇÕES de formatador (não são uso em JSX): o uso é varrido (`formatValor(` em
  // documento-detalhe, `fmt.format(` em SecaoLinhas) ou, quando o resultado passa por uma variável
  // (`mostrado`, `num(`), é garantido pelas marcações NOMEADAS acima (SugestoesDoRealizado).
  ["components/documento-detalhe.tsx", "function formatValor(", "definição do formatador; o uso (linha da coluna de valor) é varrido"],
  ["components/documento-detalhe.tsx", "valorNum.toLocaleString", "corpo do formatador; idem"],
  ["app/casos/[id]/modelagem/SecaoLinhas.tsx", "const fmt = new Intl.NumberFormat", "definição; o uso `fmt.format(` é varrido"],
  ["app/casos/[id]/modelagem/SugestoesDoRealizado.tsx", "p.valor.toLocaleString", "helper de `mostrado`; a marcação nomeada acima cobre o render"],
  ["app/casos/[id]/modelagem/SugestoesDoRealizado.tsx", "(p.valor * 100).toLocaleString", "helper de `mostrado`; idem"],
  ["app/casos/[id]/modelagem/SugestoesDoRealizado.tsx", "const num = (v: number)", "helper de numerador/denominador; marcação nomeada acima"],
];
const arquivosTsx = (readdirSync(new URL("../src", import.meta.url), { recursive: true }) as string[])
  .map((a) => a.split("\\").join("/")).filter((a) => a.endsWith(".tsx"));
let usosVarridos = 0;
const excecoesUsadas = new Set<number>();
for (const arq of arquivosTsx) {
  const txt = fonte(arq);
  for (const m of txt.matchAll(FORMATADORES)) {
    const ini = m.index ?? 0;
    const linha = txt.slice(txt.lastIndexOf("\n", ini) + 1, txt.indexOf("\n", ini));
    const iExc = EXCECOES_DE_FORMATADOR.findIndex(([a, t]) => a === arq && linha.includes(t));
    if (iExc >= 0) { excecoesUsadas.add(iExc); continue; }
    usosVarridos += 1;
    const janela = txt.slice(Math.max(0, ini - 600), ini + 600);
    checar(janela.includes("valor-sensivel"),
      `${arq}: usa ${m[0]} sem .valor-sensivel a 600 caracteres — o modo discrição deixaria o número nítido (se não é valor monetário, entre na lista de exceções com o motivo)`);
  }
}
checar(usosVarridos >= 3, `a varredura de formatadores achou ${usosVarridos} usos fora das exceções (esperado ≥ 3: formatValor, fmt.format, formatarUsd): ela deixou de varrer`);
EXCECOES_DE_FORMATADOR.forEach(([a, t], i) =>
  checar(excecoesUsadas.has(i), `exceção de formatador sem correspondente no código (apodreceu): ${a} · ${t}`));

// Textos que chegam PRONTOS do banco e carregam número sem passar por formatador nenhum — a
// varredura acima não os vê. 0009: "Ativo Total (…) vs Passivo+PL (…): divergência de …".
const textosDoBanco: Array<[string, RegExp, string]> = [
  ["app/casos/[id]/Pendencia.tsx", /valor-sensivel[^>]*>\{partes\[0\]\}/, "frase principal da pendência"],
  ["app/casos/[id]/Pendencia.tsx", /valor-sensivel[^>]*>\{parte\}/, "qualificações da pendência"],
  ["app/casos/[id]/pendencias/page.tsx", /valor-sensivel[^>]*>\{p\.descricao\}/, "descrição no cartão de confirmar"],
  ["app/casos/[id]/pendencias/FormConfirmarDocumento.tsx", /valor-sensivel[^>]*>\{p\.descricao\}/, "descrição no formulário de confirmar"],
  ["app/casos/page.tsx", /valor-sensivel[^>]*>\{resumoTexto\}/, "resumo da pendência na fila do início"],
  ["app/casos/[id]/page.tsx", /<blockquote className="valor-sensivel[^>]*>\s*“\{f\.trecho\}”/, "trecho do fato material"],
  ["app/casos/[id]/page.tsx", /valor-sensivel[^>]*>\{f\.leitura\}/, "leitura do fato material"],
  ["app/casos/[id]/historico/linha-do-tempo.tsx", /valor-sensivel[^>]*>\{e\.resumo\}/, "resumo do evento do histórico"],
  ["app/casos/[id]/perguntas/CartaoPergunta.tsx", /valor-sensivel[^>]*whitespace-pre-wrap[^>]*>\s*\{p\.pergunta\}/, "texto da pergunta"],
  ["app/casos/[id]/perguntas/CartaoPergunta.tsx", /valor-sensivel">\{p\.motivo\}[\s\S]*valor-sensivel">\{p\.risco\}[\s\S]*valor-sensivel">\{p\.impacto\}/, "motivo, risco e impacto da pergunta"],
  ["app/casos/[id]/perguntas/page.tsx", /valor-sensivel[^>]*>\{a\.texto_enviado\}/, "texto já enviado ao cliente"],
  ["app/casos/[id]/perguntas/EmailAoClienteDialogo.tsx", /<textarea[\s\S]{0,300}?valor-sensivel/, "texto editável do e-mail ao cliente"],
  ["components/documento-detalhe.tsx", /valor-sensivel[^>]*>\{doc\.resumo\}/, "resumo do documento (detalhe)"],
  ["app/casos/[id]/documentos/(lista)/page.tsx", /valor-sensivel[^>]*truncate[^>]*>\s*\{doc\.resumo\}/, "resumo do documento (lista)"],
];
for (const [arq, re, o_que] of textosDoBanco) {
  checar(re.test(fonte(arq)), `${o_que} (${arq}) deixou de ser marcado com .valor-sensivel: texto do banco com número fica nítido no modo discrição`);
}

// Campos digitados da apresentação (FormCapitulo): a decisão é por CHAVE, função pura.
// Valor/percentual/nota/cronograma/magnitude: borra. Fonte, justificativa e texto de julgamento: nítidos.
for (const k of ["i1.kpi1", "i1.kpi4", "xv2.alavanca1", "xv2.titulo", "xvi.realizacao.clientes", "xvi.recuperacao",
  "xiii3.cronograma", "xiii3.ruptura", "xvii.nota1", "xvii.nota6"]) {
  checar(campoCarregaValor(k), `campo ${k} carrega número e tem de ser marcado .valor-sensivel`);
}
for (const k of ["i1.kpi1.fonte", "xvii.justificativa1", "i1.contexto1", "iii2.socio1", "xviii.hipotese", "xiii2.op1.vencimento"]) {
  checar(!campoCarregaValor(k), `campo ${k} é texto/data e não deve ser borrado (o modo perderia o sentido)`);
}
checar([...CHAVES_APRESENTACAO].filter(campoCarregaValor).length >= 20,
  "campoCarregaValor cobre menos de 20 chaves do catálogo: a regra deixou de casar com as chaves de `campos.ts`");
checar(/campoCarregaValor\(c\.chave\)/.test(fonte("app/casos/[id]/entregaveis/FormCapitulo.tsx"))
  && (fonte("app/casos/[id]/entregaveis/FormCapitulo.tsx").match(/ valor-sensivel/g) ?? []).length === 2,
  "FormCapitulo não aplica .valor-sensivel ao <input> E ao <textarea> pelos campos de valor");
// Campo editável marcado: user-select:none no iOS impede digitar.
checar(regrasSensiveis.some((r) => /html\[data-discricao\]\s+\.valor-sensivel:is\(input,\s*textarea,\s*select\)/.test(r[1])
  && /(?<!-webkit-)user-select:\s*auto/.test(r[2]) && /-webkit-user-select:\s*auto/.test(r[2])),
  "globals.css não devolve user-select:auto a input/textarea/select marcados (no iOS o campo deixa de aceitar digitação)");

// Barra inferior e busca: comportamento puro + estrutura da cola.
checar(ariaCurrentDoLink("/casos/todos", "/casos/todos", true) === "page"
  && ariaCurrentDoLink("/casos/todos/", "/casos/todos?q=a", true) === "page"
  && ariaCurrentDoLink("/administracao", "/administracao/custos", true) === "true"
  && ariaCurrentDoLink("/casos/ABC", "/casos/abc/pendencias", true) === "true"
  && ariaCurrentDoLink("/casos/abc", "/casos/abc", true) === "page"
  && ariaCurrentDoLink("/casos/todos", "/casos/todos", false) === undefined,
  "aria-current: 'page' só quando o caminho é o do link; subpágina é 'true'; inativo é ausente");
{
  const corpo = { isConnected: true }; const gat = { isConnected: true }; const bt = { isConnected: true };
  checar(alvoDoRetornoDeFoco(bt, corpo, gat) === bt && alvoDoRetornoDeFoco(corpo, corpo, gat) === gat
    && alvoDoRetornoDeFoco(null, corpo, gat) === gat && alvoDoRetornoDeFoco({ isConnected: false }, corpo, gat) === gat,
    "o foco da busca volta a quem abriu; <body>, ausente ou desmontado cai no gatilho do cabeçalho");
}
{
  const lateral = fonte("components/barra-lateral.tsx");
  checar(/if \(naCriacao\) return <BarraInferior recentes=\{recentes\} podeCriar=\{podeCriar\} vazioDa=\{vazioDa\} mostrarAdministracao=\{mostrarAdministracao\} \/>;/.test(lateral) && !/if \(naCriacao\) return null/.test(lateral),
    "em /casos/novo a barra inferior some: o celular fica sem navegação nem busca");
  const inf = fonte("components/barra-inferior.tsx");
  checar(!/aria-current=\{[^}]*"page"/.test(inf) && (inf.match(/ariaCurrentDoLink\(/g) ?? []).length >= 3,
    "a barra inferior marca aria-current='page' sem passar por ariaCurrentDoLink");
  checar((inf.match(/onClick=\{dispensar\}/g) ?? []).length === 2, "os links da folha 'Mais' não a fecham no clique");
  checar(inf.includes("stopImmediatePropagation") && inf.includes('document.body.style.overflow = "hidden"')
    && inf.includes("document.body.style.overflow = rolagem"),
    "a folha 'Mais' não prende o Esc nem trava/restaura a rolagem do body");
  checar(/detail: \{ origem: e\.currentTarget \}/.test(inf), "o botão Busca da barra inferior não informa quem abriu");
  const busca = fonte("components/busca-global.tsx");
  checar(/alvoDoRetornoDeFoco\(origem\.current/.test(busca) && /detail\?\.origem/.test(busca),
    "a busca não devolve o foco a quem a abriu (pela barra inferior o gatilho do cabeçalho está oculto)");
  const cssTodo = readFileSync(new URL("../src/app/globals.css", import.meta.url), "utf8");
  checar(/--altura-barra-inferior:\s*calc\(/.test(cssTodo)
    && fonte("app/casos/layout.tsx").includes("var(--altura-barra-inferior)")
    && fonte("app/casos/[id]/modelagem/EditorLinhas.tsx").includes("bottom-[calc(var(--altura-barra-inferior)+0.75rem)]")
    && fonte("app/casos/[id]/modelagem/EditorLinhas.tsx").includes("sm:bottom-3")
    && fonte("app/casos/[id]/perguntas/SelecaoDePerguntas.tsx").includes("bottom-[calc(var(--altura-barra-inferior)+0.75rem)]")
    && fonte("app/casos/[id]/perguntas/SelecaoDePerguntas.tsx").includes("sm:bottom-3"),
    "as barras sticky de ação voltaram a ficar atrás da barra inferior no celular (variável --altura-barra-inferior)");
}
// A cola: o layout raiz injeta o script (não uma cópia) e tolera o atributo ligado antes da hidratação.
const raiz = fonte("app/layout.tsx");
checar(raiz.includes("SCRIPT_DISCRICAO_ANTES_DA_PINTURA") && raiz.includes("suppressHydrationWarning"),
  "o layout raiz não injeta o script do modo discrição (flash) ou perdeu o suppressHydrationWarning");

// ---------------------------------------------------------------------------
// MODO ESCURO — preferência, script do <head>, paridade dos tokens e contraste medido
// ---------------------------------------------------------------------------
//
// O defeito silencioso daqui é DUPLO: (1) uma cor do claro que ficou sem par no escuro e continua
// creme numa folha escura (ou escuro sobre escuro, ilegível); (2) um par texto/fundo do escuro que
// reprova AA sem ninguém medir. Sem DOM neste harness: a preferência e o script do <head> são
// EXECUTADOS; o CSS é lido como texto e os contrastes são CALCULADOS a partir dos valores que
// estão nele (nunca de uma cópia no teste). Não prova a pintura real — isso é screenshot.
checar(preferenciaDeTema("claro") === "claro" && preferenciaDeTema("escuro") === "escuro"
  && preferenciaDeTema("sistema") === "sistema" && preferenciaDeTema(null) === "sistema"
  && preferenciaDeTema(undefined) === "sistema" && preferenciaDeTema("") === "sistema"
  && preferenciaDeTema("dark") === "sistema" && preferenciaDeTema("1") === "sistema",
  "só 'claro' e 'escuro' valem; ausente, vazio ou lixo tem de dar 'sistema' (o padrão)");
checar(lerPreferenciaDeTema(armazemFalso()) === "sistema" && lerPreferenciaDeTema(null) === "sistema"
  && lerPreferenciaDeTema(armazemFalso({ [CHAVE_TEMA]: "escuro" })) === "escuro"
  && lerPreferenciaDeTema(armazemQueRecusa) === "sistema",
  "padrão 'sistema'; armazenamento bloqueado ou ausente dá 'sistema', sem exceção");
{
  const a = armazemFalso();
  checar(gravarPreferenciaDeTema(a, "escuro") && lerPreferenciaDeTema(a) === "escuro"
    && gravarPreferenciaDeTema(a, "claro") && lerPreferenciaDeTema(a) === "claro"
    && gravarPreferenciaDeTema(a, "sistema") && lerPreferenciaDeTema(a) === "sistema",
    "gravar e reler a preferência de tema não fecha o ciclo claro → escuro → sistema");
  checar(gravarPreferenciaDeTema(armazemQueRecusa, "escuro") === false && gravarPreferenciaDeTema(null, "escuro") === false,
    "gravar tema em armazenamento que recusa tem de devolver false, não lançar");
}
checar(temaEfetivo("claro", true) === "claro" && temaEfetivo("escuro", false) === "escuro"
  && temaEfetivo("sistema", true) === "escuro" && temaEfetivo("sistema", false) === "claro",
  "a escolha explícita vence o aparelho; 'sistema' segue o aparelho");
{
  const marcados = new Map<string, string>();
  checar(aplicarTema({ setAttribute: (k, v) => void marcados.set(k, v) }, "sistema", true) === "escuro"
    && marcados.get(ATRIBUTO_TEMA) === "escuro",
    "aplicarTema não grava data-tema com o tema efetivo");
}
// O script do <head>, EXECUTADO como está no HTML, contra localStorage/matchMedia/<html> falsos.
const rodarScriptTema = (ls: unknown, sistemaEscuro: boolean | "lanca") => {
  const atributos = new Map<string, string>();
  const doc = { documentElement: { setAttribute: (k: string, v: string) => void atributos.set(k, v) } };
  const matchMedia = () => {
    if (sistemaEscuro === "lanca") throw new Error("sem matchMedia");
    return { matches: sistemaEscuro };
  };
  let lancou = false;
  try { runInNewContext(SCRIPT_TEMA_ANTES_DA_PINTURA, { localStorage: ls, matchMedia, document: doc }); } catch { lancou = true; }
  return { tema: atributos.get(ATRIBUTO_TEMA), lancou };
};
const casosScriptTema: Array<[string, unknown, boolean | "lanca", string]> = [
  ["claro guardado vence o aparelho escuro", armazemFalso({ [CHAVE_TEMA]: "claro" }), true, "claro"],
  ["escuro guardado vence o aparelho claro", armazemFalso({ [CHAVE_TEMA]: "escuro" }), false, "escuro"],
  ["sem preferência + aparelho escuro", armazemFalso(), true, "escuro"],
  ["sem preferência + aparelho claro", armazemFalso(), false, "claro"],
  ["'sistema' guardado + aparelho escuro", armazemFalso({ [CHAVE_TEMA]: "sistema" }), true, "escuro"],
  ["lixo guardado + aparelho escuro", armazemFalso({ [CHAVE_TEMA]: "dark" }), true, "escuro"],
  // O caso que o try ÚNICO errava: janela privada bloqueia o localStorage e o aparelho é escuro.
  ["localStorage bloqueado + aparelho escuro", armazemQueRecusa, true, "escuro"],
  ["matchMedia ausente + nada guardado", armazemFalso(), "lanca", "claro"],
];
for (const [o_que, ls, sistema, esperado] of casosScriptTema) {
  const r = rodarScriptTema(ls, sistema);
  checar(!r.lancou && r.tema === esperado, `script do tema (${o_que}): esperado ${esperado}, saiu ${r.tema}${r.lancou ? " (lançou)" : ""}`);
}
checar(ATRIBUTO_TEMA === "data-tema" && CHAVE_TEMA === "oria.tema",
  "o atributo ou a chave do tema mudou de nome: o CSS, o script e o menu se desencontram");
checar(raiz.includes("SCRIPT_TEMA_ANTES_DA_PINTURA"), "o layout raiz não injeta o script do tema: flash de folha creme no escuro");
checar(/SCRIPT_TEMA_ANTES_DA_PINTURA/.test(fonte("components/menu-conta.tsx")) === false
  && fonte("components/menu-conta.tsx").includes("gravarPreferenciaDeTema") && fonte("components/menu-conta.tsx").includes("aria-pressed"),
  "o menu da conta perdeu o seletor de tema (Claro · Escuro · Sistema)");

// --- globals.css: paridade claro × escuro -----------------------------------------------------
const blocosDe = (re: RegExp) => [...css.matchAll(re)].map((m) => m[1]);
const declaracoes = (corpo: string) => new Map([...corpo.matchAll(/(--[\w-]+)\s*:\s*([^;]+);/g)].map((m) => [m[1], m[2].trim()]));
const uniao = (blocos: string[]) => new Map(blocos.flatMap((b) => [...declaracoes(b)]));
const tema = declaracoes(blocosDe(/@theme\s*\{([\s\S]*?)\n\}/g)[0] ?? "");
const raizCss = uniao(blocosDe(/(?:^|\n):root\s*\{([^}]*)\}/g));
const blocosEscuro = blocosDe(/html\[data-tema="escuro"\]\s*\{([^}]*)\}/g);
// O 1º bloco é o principal; os seguintes são os fallbacks do vidro e NÃO podem mascarar o valor dele.
const escuro = new Map([...blocosEscuro.slice(1).flatMap((b) => [...declaracoes(b)]), ...declaracoes(blocosEscuro[0] ?? "")]);
const coresClaro = [...tema.keys()].filter((k) => k.startsWith("--color-"));
const coresEscuro = [...escuro.keys()].filter((k) => k.startsWith("--color-"));
// O casco NÃO acompanha o tema, de propósito: estas são as ÚNICAS cores sem par no escuro.
const FIXAS_DO_CASCO = ["--color-fundo-reserva", "--color-vidro-papel", "--color-vidro-suave",
  "--color-vidro-terracota", "--color-vidro-texto", "--color-vidro-tinta"];
checar(coresClaro.length >= 60 && coresEscuro.length >= 60, `leitura do globals.css vazia (${coresClaro.length} claro / ${coresEscuro.length} escuro): o teste mediria nada`);
checar(coresEscuro.every((k) => tema.has(k)),
  `token redefinido no escuro que não existe no claro: ${coresEscuro.filter((k) => !tema.has(k)).join(", ")}`);
{
  const semPar = coresClaro.filter((k) => !escuro.has(k)).sort((a, b) => a.localeCompare(b));
  checar(JSON.stringify(semPar) === JSON.stringify(FIXAS_DO_CASCO),
    `cor do claro sem par no escuro (esqueceram): ${semPar.filter((k) => !FIXAS_DO_CASCO.includes(k)).join(", ") || "—"}; `
    + `ou cor fixa do casco que ganhou par: ${FIXAS_DO_CASCO.filter((k) => !semPar.includes(k)).join(", ") || "—"}`);
}
checar([...escuro.keys()].filter((k) => !k.startsWith("--color-")).every((k) => raizCss.has(k)),
  "variável não-cor redefinida no escuro que não existe em :root (vidro/sombra)");
checar([...escuro.entries()].every(([k, v]) => !/^#(000|000000|fff|ffffff)$/i.test(v) || !k.startsWith("--color-")),
  "o escuro usa preto ou branco puros: a paleta Oria não tem nenhum dos dois");
checar([...escuro.entries()].filter(([k, v]) => k.startsWith("--color-") && !/^#[0-9a-f]{6}$/i.test(v)).length === 0,
  "token de cor do escuro que não é #rrggbb: o contraste não é calculável");
// IMPRESSÃO sempre no claro: todo `html[data-tema="escuro"]` está dentro de `@media not print { }`.
{
  const ini = css.indexOf("@media not print");
  let fim = -1;
  if (ini >= 0) {
    let n = 0;
    for (let i = css.indexOf("{", ini); i < css.length; i++) {
      if (css[i] === "{") n++;
      else if (css[i] === "}" && --n === 0) { fim = i; break; }
    }
  }
  const posicoes = [...css.matchAll(/html\[data-tema="escuro"\]/g)].map((m) => m.index ?? -1);
  checar(ini >= 0 && fim > ini && posicoes.length >= 3 && posicoes.every((p) => p > ini && p < fim),
    "há regra html[data-tema=\"escuro\"] fora de @media not print: a impressão sairia escura");
}
// Os dois fallbacks do vidro (menos transparência / sem backdrop-filter) têm de ter par no escuro:
// o seletor do escuro tem especificidade MAIOR que `:root` e, sem isto, ele os sobrescreve.
checar(/@media \(prefers-reduced-transparency: reduce\)\s*\{\s*html\[data-tema="escuro"\]\s*\{[^}]*--vidro-folha-fundo:\s*#[0-9a-f]{6}/.test(css)
  && /@supports not [^{]*\{\s*html\[data-tema="escuro"\]\s*\{[^}]*--vidro-folha-fundo:\s*rgb\([^)]*\/\s*0\.9[68]\)/.test(css),
  "a folha escura perdeu o fallback sólido (reduced-transparency) ou o opaco (sem backdrop-filter)");
// O casco fixa as rampas de aviso do cartão do login nos valores do claro.
{
  const pino = declaracoes(blocosDe(/(?:^|\n)\.vidro-casco\s*\{([^}]*)\}/g).find((b) => /(?:^|[\s;])--color-/.test(b)) ?? "");
  checar(pino.size === 6 && [...pino].every(([k, v]) => tema.get(k) === v),
    "o pino de cores do .vidro-casco divergiu do @theme: os avisos do login mudariam com o tema");
}
// Nada que fique sobre o casco, ou sirva de véu, segue a troca de tinta/papel.
{
  const todos: string[] = [];
  const andar = (d: URL) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      const u = new URL(e.name + (e.isDirectory() ? "/" : ""), d);
      if (e.isDirectory()) andar(u); else if (/\.tsx$/.test(e.name)) todos.push(u.pathname);
    }
  };
  andar(new URL("../src/", import.meta.url));
  const lido = todos.map((f) => [f, readFileSync(f, "utf8")] as const);
  checar(lido.length > 50 && lido.every(([, t]) => !/bg-tinta-900\/\d/.test(t)),
    "véu de diálogo com bg-tinta-900/NN: no escuro ele clareia a tela inteira (use bg-fundo-reserva)");
  checar(lido.every(([, t]) => !/bg-vidro-texto[^"`]*\b(text-tinta-\d|hover:bg-papel)/.test(t)),
    "botão creme do casco com texto tinta/hover papel: no escuro vira texto claro sobre creme");
  // ALTO 2: fundo de token que INVERTE (tinta-*, papel, folha) com texto fixo do casco (vidro-*) no
  // MESMO className — o selo "Novo" (bg-tinta-900 text-vidro-texto) deu 1:1 no escuro. A tabela de
  // contraste mede pares declarados; esta varredura pega o par que ninguém declarou.
  const temFundoQueInverte = (t: string) => /(?:^|[\s"'`])(?:[\w-]+:)*bg-(?:tinta-\d+|papel|folha)(?![\w-])/.test(t);
  const temTextoFixoDoCasco = (t: string) => /(?:^|[\s"'`])(?:[\w-]+:)*text-vidro-[\w-]+/.test(t);
  const literais = (t: string) => t.match(/"[^"\n]*"|`[^`]*`/g) ?? [];
  checar(temFundoQueInverte('"rounded bg-tinta-900 text-vidro-texto"') && temTextoFixoDoCasco('"rounded bg-tinta-900 text-vidro-texto"')
    && !(temFundoQueInverte('"bg-papel text-tinta-900"') && temTextoFixoDoCasco('"bg-papel text-tinta-900"')),
    "a varredura de fundo-que-inverte x texto-do-casco não reconhece o caso que ela existe para pegar");
  const mistura = lido.flatMap(([f, t]) => literais(t).filter((l) => temFundoQueInverte(l) && temTextoFixoDoCasco(l)).map(() => f));
  checar(mistura.length === 0, `fundo que inverte com texto fixo do casco no mesmo className (1:1 no escuro) em: ${mistura.join(", ")}`);
  // MÉDIO 4: o acesso à PROPRIEDADE lança SecurityError com dados de site bloqueados; só `armazem()` o protege.
  const diretos = lido.filter(([, t]) => /window\.localStorage/.test(t)).map(([f]) => f);
  checar(diretos.length === 0, `.tsx com window.localStorage direto (lança SecurityError fora de try): ${diretos.join(", ")}`);
  checar(lido.every(([, t]) => !/\bbg-white(?![/\w-])/.test(t)), "bg-white em tela: no escuro vira bloco branco na folha");
}

// --- contraste medido (WCAG 2.x) ---------------------------------------------------------------
const rgbDe = (h: string): [number, number, number] => [1, 3, 5].map((i) => Number.parseInt(h.slice(i, i + 2), 16)) as [number, number, number];
const lum = ([r, g, b]: [number, number, number]) => {
  const l = (c: number) => { const x = c / 255; return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * l(r) + 0.7152 * l(g) + 0.0722 * l(b);
};
const razao = (a: [number, number, number], b: [number, number, number]) => {
  const [x, y] = [lum(a), lum(b)];
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
};
const corDe = (t: string): [number, number, number] => {
  const v = escuro.get(`--color-${t}`);
  if (!v) throw new Error(`token --color-${t} ausente do escuro`);
  return rgbDe(v);
};
// A FOLHA NA PIOR HORA: 94% da folha escura sobre o pixel MAIS CLARO da foto (255,255,236) — é o
// que clareia o fundo e derruba o contraste do texto claro (o mesmo critério da tabela do claro).
const folhaVidro = /rgb\((\d+) (\d+) (\d+) \/ ([\d.]+)\)/.exec(escuro.get("--vidro-folha-fundo") ?? "");
checar(folhaVidro !== null, "--vidro-folha-fundo do escuro não está em rgb(r g b / a): o pior caso não é calculável");
const alfaFolha = Number(folhaVidro?.[4] ?? 1);
const folhaNaPior = (folhaVidro
  ? [1, 2, 3].map((i, k) => Math.round(alfaFolha * Number(folhaVidro[i]) + (1 - alfaFolha) * [255, 255, 236][k]))
  : [255, 255, 255]) as [number, number, number];
const fundoDe = (n: string) => (n === "folha-sobre-foto" ? folhaNaPior : corDe(n));
type ParDeContraste = [fg: string, bg: string, minimo: number];
const pares: ParDeContraste[] = [];
const texto = (fg: string, bgs: string[], min = 4.5) => bgs.forEach((bg) => pares.push([fg, bg, min]));
const SUPERFICIES = ["folha-sobre-foto", "folha", "papel"];
texto("tinta-900", [...SUPERFICIES, "tinta-50", "tinta-100"]);            // texto primário
texto("tinta-800", SUPERFICIES);
texto("tinta-700", [...SUPERFICIES, "tinta-50"]);
texto("tinta-600", [...SUPERFICIES, "tinta-50", "tinta-100", "tinta-200"]); // secundário, chips neutros
texto("tinta-500", [...SUPERFICIES, "tinta-50", "tinta-100"]);              // placeholder e rótulo
texto("tinta-400", ["folha-sobre-foto", "folha"], 3.6);                     // ícone/fio: o piso do claro (3,62)
for (const f of ["risco", "alerta", "ok", "info", "serie"]) {
  texto(`${f}-800`, [`${f}-50`, `${f}-100`]);                                // chip
  texto(`${f}-900`, [`${f}-50`, `${f}-100`]);
  texto(`${f}-700`, [`${f}-50`, "folha-sobre-foto", "folha"]);               // texto de estado sobre a folha
  texto(`${f}-800`, ["folha-sobre-foto", "folha"]);
  texto(`${f}-900`, ["folha-sobre-foto", "folha"]);
}
texto("tinta-700", ["tinta-100"]); texto("tinta-700", ["tinta-200"]);        // chip neutro e o hover dele
texto("acento-700", [...SUPERFICIES, "acento-50", "acento-100"]);           // link e item ativo
texto("acento-600", SUPERFICIES);                                            // link; e o anel de foco precisa de 3:1
texto("tinta-900", ["acento-100"]);                                          // ::selection
// botões: o texto é `papel` (escuro) sobre o preenchimento, que no escuro é o tom CLARO
for (const bg of ["tinta-900", "tinta-800", "tinta-600", "ok-600", "ok-700", "ok-800", "risco-600", "risco-700", "risco-800", "acento-600"]) {
  texto("papel", [bg]);
}
// o que o `:root` mantém igual no escuro: o casco, medido no claro com o pior caso (DESIGN.md) — aqui só se
// confere que o terracota de foco do casco e o texto do botão creme dele seguem sendo ≥ 4,5:1 entre si.
checar(pares.length >= 100, `só ${pares.length} pares de contraste medidos: o conjunto encolheu ou o parse falhou`);
const medivel = ([fg, bg]: ParDeContraste) => [fg, bg].every((t) => t === "folha-sobre-foto" || escuro.has(`--color-${t}`));
checar(pares.every(medivel), `par de contraste com token ausente do escuro: ${pares.filter((p) => !medivel(p)).map(([f, b]) => `${f}/${b}`).join(", ")}`);
const reprovados = pares.filter(medivel).filter(([fg, bg, min]) => razao(corDe(fg), fundoDe(bg)) < min);
checar(reprovados.length === 0,
  `contraste abaixo do mínimo no escuro: ${reprovados.map(([fg, bg, min]) => `${fg} sobre ${bg} = ${razao(corDe(fg), fundoDe(bg)).toFixed(2)} (< ${min})`).join("; ")}`);
checar(razao(rgbDe("#11161d"), rgbDe("#ece8df")) >= 4.5 && razao(rgbDe("#11161d"), rgbDe("#f6f4ef")) >= 4.5,
  "texto do botão creme do casco (vidro-tinta sobre vidro-texto/vidro-papel) abaixo de 4,5:1");
if (process.env.TABELA_DE_CONTRASTE) {
  for (const [fg, bg, min] of pares) console.log(`${fg.padEnd(12)} sobre ${bg.padEnd(17)} ${razao(corDe(fg), fundoDe(bg)).toFixed(2)}  (mín ${min})`);
  console.log("folha na pior hora:", folhaNaPior.join(","));
}

// Barra inferior: o destino ativo. Caminhos reais, com o UUID de um mandato.
// `armazem()`: a propriedade lança (dados de site bloqueados) ou o `window` nem existe (servidor).
{
  const g = globalThis as Record<string, unknown>;
  const antes = g.window;
  const guardado = { getItem: () => "x" };
  try {
    delete g.window;
    checar(armazem() === null, "armazem() sem window (servidor) = null, sem exceção");
    g.window = { get localStorage() { throw new Error("SecurityError"); } };
    checar(armazem() === null, "armazem() com a propriedade lançando = null");
    g.window = { localStorage: guardado };
    checar(armazem() === (guardado as unknown), "armazem() devolve o localStorage quando existe");
  } finally {
    if (antes === undefined) delete g.window; else g.window = antes;
  }
}
// Os scripts do <head> não podem criar globais (`p`/`d` do tema viravam `window.p`/`window.d`).
for (const [nome, script] of [["tema", SCRIPT_TEMA_ANTES_DA_PINTURA], ["discrição", SCRIPT_DISCRICAO_ANTES_DA_PINTURA]] as const) {
  const sandbox: Record<string, unknown> = {
    localStorage: { getItem: () => "escuro" }, matchMedia: () => ({ matches: true }),
    document: { documentElement: { setAttribute: () => {} } },
  };
  const chavesAntes = Object.keys(sandbox);
  runInNewContext(script, sandbox);
  const novas = Object.keys(sandbox).filter((k) => !chavesAntes.includes(k));
  checar(novas.length === 0, `o script do ${nome} criou globais no head: ${novas.join(",")}`);
}

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

// AVISOS DE PROCESSAMENTO (sino) — o que a tela pode afirmar do estado do lote, e o "visto" por navegador.
{
  const T0 = Date.parse("2026-10-29T12:00:00Z");
  const min = (m: number) => new Date(T0 - m * 60_000).toISOString();
  const lote = (o: Partial<LoteLido>): LoteLido => ({
    id: "L1", execucao_ref: "900", caso_id: "C1", caso: { nome: "Mandato X" }, criado_em: min(60), fechado_em: null,
    documentos: 10, documentos_planejados: 10, documentos_com_falha: 0, ...o,
  });
  checar(classificarLote(lote({ fechado_em: min(5) }), T0) === "concluido", "lote fechado sem falha = concluído");
  checar(classificarLote(lote({ fechado_em: min(5), documentos_com_falha: 2 }), T0) === "concluido_com_falhas",
    "lote fechado com documento falho NÃO pode ser 'concluído' liso");
  checar(classificarLote(lote({ fechado_em: min(5), documentos_com_falha: null }), T0) === "concluido",
    "falha nula (não medida) não inventa falha");
  checar(classificarLote(lote({ criado_em: min(3) }), T0) === null, "lote aberto dentro da janela está andando: não é aviso");
  checar(classificarLote(lote({ criado_em: min(13 * 60) }), T0) === "demorando", "lote de 10 docs aberto há 13h = demorando");
  checar(classificarLote(lote({ criado_em: min(60), documentos_planejados: 190 }), T0) === null,
    "lote de 190 aberto há 1h NÃO é aviso (a janela é a da tela de upload)");
  checar(classificarLote(lote({ documentos_planejados: null, criado_em: min(13 * 60) }), T0) === "sem_confirmacao",
    "plano desconhecido: a tela não afirma 'demorando'");
  checar(classificarLote(lote({ criado_em: "lixo" }), T0) === "sem_confirmacao", "data ilegível não vira 'andando'");
  const avisos = montarAvisos(
    [lote({ id: "A", fechado_em: min(5) }), lote({ id: "B", criado_em: min(3) }), lote({ id: "P", criado_em: min(13 * 60) })],
    [{ id: "F", caso_id: null, caso_nome: "Sem caso", etapa: "orcamento", mensagem: "Lote acima do teto", detalhe: null, criado_em: min(1) }], T0);
  checar(avisos.length === 3 && !avisos.some((a) => a.chave.includes(":B:")), "em andamento fica fora; concluído, demorando e falha entram");
  checar(avisos[0].tipo === "falha" && avisos[0].casoId === null, "ordem: mais recente primeiro; falha sem caso não ganha link");
  checar(new Set(avisos.map((a) => a.chave)).size === 3, "chaves únicas");
  checar(montarAvisos(Array.from({ length: 30 }, (_, i) => lote({ id: `n${i}`, fechado_em: min(i) })), [], T0).length === 20, "teto de 20");
  checar(montarAvisos([lote({ caso: [{ nome: "Via array" }], fechado_em: min(1) })], [], T0)[0].casoNome === "Via array",
    "o join pode chegar como lista");
  const antes = montarAvisos([lote({ id: "Z", criado_em: min(13 * 60) })], [], T0)[0];
  const depois = montarAvisos([lote({ id: "Z", criado_em: min(13 * 60), fechado_em: min(1) })], [], T0)[0];
  checar(antes.chave !== depois.chave, "o lote que estava demorando e fechou é aviso NOVO (a chave leva o tipo)");

  // --- ALTO 1: nunca "parado"; relógio adiantado não vira aviso ---
  {
    const janela10 = janelaPara(10) / 60_000; // a MESMA janela que a tela de upload usa, em minutos
    const comRelogioAdiantado = lote({ criado_em: min(janela10 + 2) });
    checar(classificarLote(comRelogioAdiantado, T0) === null,
      "lote 2 min além da janela, dentro da tolerância de relógio, NÃO vira aviso");
    checar(classificarLote(lote({ criado_em: min(janela10 + TOLERANCIA_DO_RELOGIO_MS / 60_000 + 1) }), T0) === "demorando",
      "além da janela + tolerância vira 'demorando'");
    checar(!/parado/i.test(Object.values(ROTULO_DO_TIPO).join("|")), "nenhum rótulo afirma 'parado': lote_execucao não mede progresso");
    checar(ROTULO_DO_TIPO.demorando.includes("sem confirmação de término"), "o rótulo diz o que NÃO se sabe");
    checar(!pedeAtencao("demorando") && !pedeAtencao("sem_confirmacao") && pedeAtencao("falha") && pedeAtencao("concluido_com_nao_lidos"),
      "demorando não leva 'Atenção' (empurraria reenvio); falha e não lidos levam");
    const d = montarAvisos([lote({ criado_em: min(13 * 60) })], [], T0)[0];
    checar(/n[ãa]o\s+afirma|Pode estar só lento/.test(d.detalhe ?? "") && !/parou|parado/i.test(d.detalhe ?? ""),
      "o detalhe do 'demorando' admite que pode estar vivo e não diz 'parou'");
  }
  // --- ALTO 3: documento que nunca chegou à extração não é "concluído" liso ---
  {
    const fechado = lote({ id: "N1", fechado_em: min(5) });
    checar(classificarLote(fechado, T0, 3) === "concluido_com_nao_lidos", "fechado + 3 pendências documento_nao_extraido não é 'concluído'");
    checar(classificarLote(fechado, T0, 0) === "concluido", "sem pendência aberta segue 'concluído'");
    const a = montarAvisos([fechado], [], T0, { C1: 3 })[0];
    checar(a.tipo === "concluido_com_nao_lidos" && (a.detalhe ?? "").includes("3 documentos"), "o aviso traz a contagem");
    const dois = montarAvisos([lote({ id: "velho", fechado_em: min(500) }), fechado], [], T0, { C1: 2 });
    checar(dois.filter((x) => x.tipo === "concluido_com_nao_lidos").length === 1 && dois.some((x) => x.chave === "lote:velho:concluido"),
      "a contagem do caso entra só no lote fechado mais recente");
    const f2 = montarAvisos([lote({ id: "N2", fechado_em: min(5), documentos_com_falha: 1 })], [], T0, { C1: 2 })[0];
    checar(f2.tipo === "concluido_com_falhas" && (f2.detalhe ?? "").includes("2 documentos registrados sem extração"), "falhas + não lidos: os dois aparecem");
  }
  // --- MÉDIO 5: recusa duplicada, mensagem real, falha mata o 'demorando', nome via join ---
  {
    const recusa = { id: "R", caso_id: "C1", caso_nome: "Digitado", etapa: "orcamento", mensagem: "Lote acima do teto de US$ 3", detalhe: null, criado_em: min(10) };
    const erro = { id: "E", caso_id: "C1", caso_nome: "Digitado", etapa: "Abortar Lote", mensagem: "Lote acima do teto de US$ 3", detalhe: { execucao_id: "77" }, criado_em: min(10) };
    const av = montarAvisos([], [recusa, erro], T0);
    checar(av.length === 1 && av[0].tipo === "falha", "recusa + Error Workflow do mesmo acontecimento = UM aviso");
    checar(av[0].detalhe === "Lote acima do teto de US$ 3" && !/abra o mandato para ver o que foi lido/.test(av[0].detalhe ?? ""),
      "o aviso mostra a mensagem gravada, não um texto genérico que afirma o que foi lido");
    checar(montarAvisos([], [recusa, { ...erro, mensagem: "Outra coisa" }], T0).length === 2, "mensagem diferente = acontecimento diferente");
    checar(montarAvisos([], [recusa, { ...erro, criado_em: min(10 + 60) }], T0).length === 2, "mesma mensagem horas depois = outro acontecimento");
    checar(montarAvisos([], [{ ...erro, id: "E1" }, { ...erro, id: "E2", mensagem: "x", criado_em: min(40) }], T0).length === 1,
      "mesmo execucao_id deduplica mesmo com mensagem/hora diferentes");
    checar(montarAvisos([], [{ ...erro, id: "E1", caso_id: null, caso_nome: null }, { ...erro, id: "E2", caso_id: null, caso_nome: null, detalhe: null }], T0).length === 2,
      "falhas sem caso e sem execucao_id comum NÃO se fundem (não se sabe se são a mesma)");
    const vivo = lote({ id: "V", execucao_ref: "77", criado_em: min(13 * 60) });
    checar(montarAvisos([vivo], [erro], T0).every((x) => x.tipo === "falha"), "lote cuja execução já tem falha registrada não vira 'demorando'");
    checar(montarAvisos([lote({ id: "V2", execucao_ref: "78", criado_em: min(13 * 60) })], [erro], T0).some((x) => x.tipo === "demorando"),
      "falha de OUTRA execução não cala o 'demorando'");
    checar(montarAvisos([], [{ ...erro, caso: { nome: "Nome do join" } }], T0)[0].casoNome === "Nome do join"
      && montarAvisos([], [{ ...erro, caso: null }], T0)[0].casoNome === "Digitado", "nome: o do join, senão o digitado");
    checar(montarAvisos([], [{ ...erro, mensagem: "  " }], T0)[0].detalhe?.includes("não deixou mensagem") === true, "mensagem vazia tem texto neutro");
  }

  const mem = () => { const m = new Map<string, string>(); return { m, getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => { m.set(k, v); } }; };
  const a = mem();
  checar(JSON.stringify(lerVistos(a)) === "[]", "armazém vazio = nenhum visto");
  checar(gravarVistos(a, unirVistos([], ["x", "y"])) && JSON.stringify(lerVistos(a)) === '["x","y"]', "grava e lê de volta");
  checar(contarNaoVistos(avisos, lerVistos(a)) === 3, "nenhuma chave vista: todos contam");
  checar(contarNaoVistos(avisos, [avisos[0].chave]) === 2, "visto desconta");
  checar(contarNaoVistos(avisos, avisos.map((x) => x.chave)) === 0, "tudo visto = zero");
  checar(lerVistos(null) === null && lerVistos({ getItem: () => { throw new Error("bloqueado"); } }) === null,
    "armazenamento indisponível é NULL (não sei), nunca lista vazia");
  checar(contarNaoVistos(avisos, null) === 3, "sem poder guardar o visto, todos contam como novos");
  checar(JSON.stringify(lerVistos({ getItem: () => "{lixo" })) === "[]" && JSON.stringify(lerVistos({ getItem: () => '{"a":1}' })) === "[]",
    "conteúdo corrompido reaparece como novo, sem exceção");
  checar(gravarVistos({ setItem: () => { throw new Error("cheio"); } }, ["a"]) === false && gravarVistos(null, ["a"]) === false,
    "gravação recusada devolve false");
  const muitos = unirVistos(Array.from({ length: TETO_DE_VISTOS }, (_, i) => `k${i}`), ["novo", "k5"]);
  checar(muitos.length === TETO_DE_VISTOS && muitos.includes("novo") && !muitos.includes("k0") && muitos.filter((c) => c === "k5").length === 1,
    "o visto tem teto, descarta o mais antigo e não duplica");
  checar(CHAVE_AVISOS_VISTOS === "oria.avisos-vistos", "chave do visto estável");
  checar(!nomeDoSino("erro", 3).includes("3") && nomeDoSino("erro", 3).includes("não foi possível"),
    "sino com falha de leitura NÃO leva número no nome");
  checar(nomeDoSino("ok", 3).includes("3") && !/\d/.test(nomeDoSino("ok", 0)) && !/\d/.test(nomeDoSino("carregando", 5)),
    "o número entra no nome só com leitura ok e > 0");
  const comp = fonte("components/avisos-de-processamento.tsx");
  checar(!/select\(\s*["'`]\*/.test(comp), "o sino lê colunas nomeadas, nunca select *");
  checar(/fase === "ok" && naoVistos > 0/.test(comp) && /fase: "erro"/.test(comp), "o contador só aparece com leitura ok");
  checar(fonte("app/casos/layout.tsx").includes("<AvisosDeProcessamento />"), "o sino saiu do cabeçalho");
  checar(/documento_nao_extraido/.test(comp) && /\.neq\("estado", "resolvida"\)/.test(comp) && /execucao_ref/.test(comp) && /mensagem, detalhe/.test(comp)
    && /caso\(nome\)/.test(comp.slice(comp.indexOf('from("execucao_falha")'))), "o sino lê pendência não lida, execucao_ref, mensagem/detalhe e o join do caso da falha");
  // --- MÉDIO 6: o visto recusado sobrevive ao recarregar de 60 s ---
  checar(JSON.stringify(vistosEfetivos(["a"], ["b"])) === '["a","b"]' && JSON.stringify(vistosEfetivos([], ["b"])) === '["b"]',
    "armazém + memória do que foi recusado");
  checar(vistosEfetivos(null, []) === null && JSON.stringify(vistosEfetivos(null, ["b"])) === '["b"]',
    "armazém indisponível sem memória = null; com memória vale a memória");
  checar(JSON.stringify(vistosEfetivos(["a"], [])) === '["a"]', "sem memória, o armazém vale");
  checar(/naoGravados/.test(comp) && /vistosEfetivos\(lerVistos\(armazem\(\)\), naoGravados\.current\)/.test(comp), "o carregar une armazém e memória");
}

// ---------------------------------------------------------------------------
// RECUPERAR SENHA — a única tela pública que escreve algo
// ---------------------------------------------------------------------------
{
  // 1. O e-mail não revela existência: a frase do pedido é uma só, e o texto que o Auth
  //    daria para conta inexistente cai na genérica, nunca numa frase que distingue.
  const REVELA = /n[ãa]o (h[áa]|existe|encontr|cadastr)|inexistente|desconhecid|n[ãa]o est[áa] cadastr/i;
  for (const bruto of ["User not found", "Email not found", "user_not_found", "404 user_not_found Unable to find user"]) {
    const r = mensagemDeRecuperacao(bruto);
    checar(!REVELA.test(r.mensagem) && r.mensagem === mensagemDeRecuperacao("erro qualquer").mensagem,
      `"${bruto}" não vira frase que distingue conta inexistente`);
  }
  checar(!REVELA.test(RESPOSTA_DO_PEDIDO) && /^Se houver uma conta com este e-mail, enviamos um link/.test(RESPOSTA_DO_PEDIDO),
    "a resposta do pedido é condicional e não afirma que a conta existe");
  const acao = fonte("app/login/recuperar/actions.ts");
  checar(/redirect\("\/login\/recuperar\?enviado=1"\)/.test(acao) && !/user_not_found|not found/i.test(acao),
    "a action só responde 'enviado' sem olhar se a conta existe");
  // 2. Limite (429) manda aguardar; link vencido manda pedir outro; nada vira silêncio.
  for (const bruto of ["429 over_email_send_rate_limit email rate limit exceeded", "For security purposes, you can only request this after 52 seconds"]) {
    const r = mensagemDeRecuperacao(bruto);
    checar(r.aguardar && /Aguarde/.test(r.mensagem), `"${bruto.slice(0, 30)}…" pede espera`);
  }
  for (const bruto of [ERRO_LINK, "otp_expired: Email link is invalid or has expired", "Auth session missing!"]) {
    checar(/Peça um novo link/.test(mensagemDeRecuperacao(bruto).mensagem), `"${bruto.slice(0, 30)}" manda pedir novo link`);
  }
  checar(/diferente da atual/.test(mensagemDeRecuperacao("422 same_password New password should be different from the old password.").mensagem),
    "mesma senha: frase própria (e não a de senha fraca)");
  checar(mensagemDeRecuperacao("coisa nova do Auth").mensagem.length > 20, "erro desconhecido ainda é dito");
  // 3. `next` só aceita caminho interno.
  const PADRAO = "/login/nova-senha";
  const aceitos = ["/login/nova-senha", "/casos", "/casos?aviso=x"];
  const recusados = ["//evil.com", "///evil.com", "https://evil.com", "http://evil.com/login/nova-senha", "evil.com", "/\\evil.com",
    "/\t/evil.com", "javascript:alert(1)", "", "  /casos", "/casos\n//evil.com"];
  for (const n of aceitos) checar(caminhoInternoSeguro(n, PADRAO) === n, `next ${JSON.stringify(n)} passa`);
  for (const n of recusados) checar(caminhoInternoSeguro(n, PADRAO) === PADRAO, `next ${JSON.stringify(n)} cai no padrão`);
  checar(caminhoInternoSeguro(null, PADRAO) === PADRAO && caminhoInternoSeguro(undefined, PADRAO) === PADRAO, "next ausente cai no padrão");
  checar(montarRedirectTo("https://x.app", "//evil.com") === "https://x.app/auth/confirmar?next=%2Flogin%2Fnova-senha",
    "o redirectTo nunca carrega next externo");
  checar(montarRedirectTo("https://x.app", "/login/nova-senha") === "https://x.app/auth/confirmar?next=%2Flogin%2Fnova-senha",
    "o redirectTo padrão aponta ao callback com next=/login/nova-senha");
  checar(origemDaRequisicao("https://x.app", "outro", null) === "https://x.app"
    && origemDaRequisicao(null, "x.app", "https") === "https://x.app"
    && origemDaRequisicao(null, "localhost:3000", null) === "http://localhost:3000"
    && origemDaRequisicao("javascript:alert(1)", "bad host", null) === null,
    "a origem vem do cabeçalho validado, ou é nula (nunca URL com host vazio)");
  const rota = fonte("app/auth/confirmar/route.ts");
  checar(/caminhoInternoSeguro\(q\.get\("next"\)/.test(rota) && /new URL\(destino, request\.nextUrl\.origin\)/.test(rota),
    "o callback sanea o next antes de redirecionar");
  checar(/type"\) === "recovery"/.test(rota), "o callback só confirma o tipo recovery");
  // 4. Rotas públicas: EXATAMENTE estas, sem prefixo.
  checar(JSON.stringify([...ROTAS_PUBLICAS].sort()) === JSON.stringify(["/auth/confirmar", "/login", "/login/recuperar"]),
    "a lista de rotas públicas é exatamente login, login/recuperar e auth/confirmar");
  for (const r of ROTAS_PUBLICAS) checar(rotaPublica(r), `${r} é pública`);
  for (const r of ["/login/nova-senha", "/login/qualquer", "/loginx", "/login/recuperar/x", "/auth", "/auth/confirmar/x", "/casos", "/", "/api/intake", "/administracao"]) {
    checar(!rotaPublica(r), `${r} exige sessão`);
  }
  checar(rotaPublica("/login/") && rotaPublica("/login/recuperar/"), "a barra final não muda a rota");
  const px = fonte("lib/supabase/proxy.ts");
  checar(/!rotaPublica\(request\.nextUrl\.pathname\)/.test(px) && !/startsWith\("\/login"\)/.test(px),
    "o proxy usa a lista exata, não prefixo de /login");
  // 5. A regra da senha.
  checar(SENHA_MINIMA === 10, "mínimo de 10 caracteres");
  checar(validarNovaSenha("123456789", "123456789") === "senha_curta" && validarNovaSenha("1234567890", "1234567890") === null
    && validarNovaSenha("1234567890", "1234567891") === "senhas_diferentes" && validarNovaSenha("", "") === "senha_curta",
    "9 caracteres reprova, 10 passa, confirmação diferente reprova");
  const tela = fonte("app/login/nova-senha/page.tsx");
  checar(/REGRA_DA_SENHA/.test(tela) && /minLength=\{SENHA_MINIMA\}/.test(tela), "a regra da senha está visível na tela e no campo");
}

// ---------------------------------------------------------------------------
// ACESSO POR PAPEL (Fase 5, parte de tela) — a tela só evita o clique inútil; o banco (0216) decide
// ---------------------------------------------------------------------------
{
  const ok_ = (papel: "socio" | "analista" | "leitura" | null): AcessoLido => ({ estado: "ok", papel });
  const falhou: AcessoLido = { estado: "falha", detalhe: "rede" };
  // 1. fn_meu_papel: três estados distintos, e "sem papel" NÃO é falha nem o contrário.
  checar(interpretarPapel({ data: "socio", error: null }).estado === "ok", "papel conhecido lê");
  const semPapel = interpretarPapel({ data: null, error: null });
  checar(semPapel.estado === "ok" && semPapel.papel === null, "null do banco é RESPOSTA (sem papel), não falha");
  checar(interpretarPapel({ data: null, error: { message: "x" } }).estado === "falha", "erro de leitura é falha, não 'sem papel'");
  checar(interpretarPapel({ data: "estagiario", error: null }).estado === "falha", "papel fora do vocabulário é falha (não tranca a pessoa fora)");
  // 2. O que cada papel pode.
  const socio = permissoes(ok_("socio"));
  checar(socio.escrever.pode && socio.criarMandato.pode && socio.reservadoAoSocio.pode, "Sócio pode tudo");
  const leitura = permissoes(ok_("leitura"));
  checar(!leitura.escrever.pode && !leitura.criarMandato.pode && !leitura.reservadoAoSocio.pode, "Leitura não escreve, não cria, não aprova");
  checar(/Leitura/.test(leitura.escrever.motivo ?? "") && /Leitura/.test(leitura.criarMandato.motivo ?? ""), "o motivo da Leitura nomeia o papel");
  const analista = permissoes(ok_("analista"), true);
  checar(analista.escrever.pode && analista.criarMandato.pode && !analista.reservadoAoSocio.pode, "Analista alocado escreve e cria, mas não aprova/fecha/exclui");
  checar(/Analista/.test(analista.reservadoAoSocio.motivo ?? ""), "o motivo do reservado ao Sócio nomeia o papel");
  const fora = permissoes(ok_("analista"), false);
  checar(!fora.escrever.pode && /alocado/.test(fora.escrever.motivo ?? "") && fora.criarMandato.pode, "Analista NÃO alocado não escreve naquele mandato, mas cria o seu");
  const incerto = permissoes(ok_("analista"), null);
  checar(incerto.escrever.pode && !incerto.conferido, "alocação que não pôde ser lida: nada some, e a tela sabe que não conferiu");
  const nada = permissoes(falhou);
  checar(nada.escrever.pode && nada.reservadoAoSocio.pode && !nada.conferido && !nada.semPapel, "papel que não pôde ser lido NÃO tranca o Sócio fora");
  const sem = permissoes(semPapel);
  checar(sem.semPapel && !sem.escrever.pode && sem.escrever.motivo === MOTIVO_SEM_PAPEL, "sem papel: nada vale, e o motivo é o de acesso não liberado");
  // 3. Listas vazias: o que a tela pode afirmar.
  checar(escopoDaLista("socio") === "todos" && escopoDaLista("analista") === "alocados" && escopoDaLista("leitura") === "alocados" && escopoDaLista(null) === "indefinido",
    "só o Sócio vê a mesa inteira");
  checar(textoDeRecentesVazio("socio", false) === "Nenhum mandato aberto", "Sócio sem mandato: 'nenhum' é fato");
  checar(/alocado a você/.test(textoDeRecentesVazio("analista", false)) && /alocado a você/.test(textoDeRecentesVazio("leitura", false)),
    "Analista/Leitura sem mandato: 'nenhum alocado', não 'nenhum'");
  checar(/Não foi possível/.test(textoDeRecentesVazio("socio", true)), "leitura falha da barra não vira 'nenhum mandato'");
  // 4. 42501 -> frase do papel; o resto continua com o erro técnico.
  checar(ehNegacaoDePermissao({ code: "42501" }) && !ehNegacaoDePermissao({ code: "23503" }) && !ehNegacaoDePermissao(null), "só o código 42501 é negação de permissão");
  checar(textoDeFalhaDaAcao("Falha ao aprovar", { code: "42501", message: "new row violates row-level security policy" }) === MENSAGEM_SEM_PERMISSAO
    && /^Seu papel não permite esta ação/.test(MENSAGEM_SEM_PERMISSAO), "42501 vira 'Seu papel não permite esta ação'");
  checar(textoDeFalhaDaAcao("Falha ao aprovar", { code: "57014", message: "timeout" }) === "Falha ao aprovar: timeout", "erro que não é de permissão segue com o prefixo e o texto técnico");
  // 5. (a) ENVIO DE ARQUIVOS: a escrita que o banco não vê (n8n usa conexão de serviço).
  const envio = (a: AcessoLido, ach: { n: number; podeEscrever: boolean | null } | null) => decidirEnvioAoMandato(a, ach);
  checar(envio(ok_("leitura"), { n: 1, podeEscrever: false }).ok === false && (envio(ok_("leitura"), null) as { mensagem: string }).mensagem === MENSAGEM_SEM_ENVIO, "Leitura não envia arquivos");
  checar(!envio(semPapel, null).ok && (envio(semPapel, null) as { status: number }).status === 403, "sem papel não envia");
  checar(envio(ok_("socio"), null).ok, "Sócio envia sem consulta de nome");
  checar(envio(ok_("analista"), { n: 1, podeEscrever: true }).ok, "Analista alocado envia");
  checar(!envio(ok_("analista"), { n: 1, podeEscrever: false }).ok, "Analista não alocado não envia");
  checar(!envio(ok_("analista"), { n: 0, podeEscrever: null }).ok && (envio(ok_("analista"), { n: 0, podeEscrever: null }) as { status: number }).status === 403,
    "nome que o Analista não enxerga é recusado (a RLS não distingue 'não existe' de 'é de outra equipe')");
  const dup = envio(ok_("analista"), { n: 2, podeEscrever: null }) as { status: number; mensagem: string };
  checar(dup.status === 409 && dup.mensagem === MENSAGEM_NOME_DUPLICADO, "nome duplicado é erro explícito (409), não 'aguarde'");
  checar((envio(falhou, null) as { status: number }).status === 503 && (envio(ok_("analista"), null) as { status: number }).status === 503
    && (envio(ok_("analista"), { n: 1, podeEscrever: null }) as { status: number }).status === 503, "o envio FALHA FECHADO quando não consegue conferir");
  // 6. (b) ADMINISTRAÇÃO: números somados de todos os mandatos só para Sócio.
  checar(administracaoLiberada(ok_("socio")) && !administracaoLiberada(ok_("analista")) && !administracaoLiberada(ok_("leitura")) && !administracaoLiberada(semPapel)
    && administracaoLiberada(falhou), "Administração: só Sócio (e abre se o papel não pôde ser lido)");
  // 7. Fiação: o que a lógica pura decide TEM de ser o que as rotas e telas usam (a regra 3 só vale se o gatilho existir).
  const intake = fonte("app/api/intake/route.ts"), destino = fonte("app/api/intake/destino/route.ts"), status = fonte("app/api/intake/status/route.ts");
  checar(/conferirEnvioAoMandato\(mandato\)/.test(intake) && /permissao\.status/.test(intake), "POST /api/intake confere o papel antes de encaminhar");
  checar(/conferirEnvioAoMandato/.test(destino) && /searchParams\.get\("mandato"\)/.test(destino), "a URL do Form do n8n só sai para quem pode enviar ao mandato");
  checar(/\.limit\(2\)/.test(status) && !/maybeSingle/.test(status) && /MENSAGEM_NOME_DUPLICADO/.test(status), "o status não usa maybeSingle por nome (duplicata)");
  checar(/administracaoLiberada\(acesso\)/.test(fonte("app/administracao/layout.tsx")), "o layout da Administração fecha para quem não é Sócio");
  checar(/mostrarAdministracao=\{/.test(fonte("app/casos/layout.tsx")), "a barra esconde o link da Administração");
  checar(/semPapel/.test(fonte("app/casos/layout.tsx")) && /AcessoNaoLiberado/.test(fonte("app/casos/layout.tsx")), "o casco troca TODA tela por 'acesso não liberado' (Início e Mandatos incluídos)");
  // 8. Equipe: só o e-mail de quem está logado é conhecido; o resto aparece como código curto.
  const eu = { id: "11111111-1111-1111-1111-111111111111", email: "eu@oria.com" };
  const outro = "22222222-2222-2222-2222-222222222222";
  checar(pessoaDoUsuario(eu.id, eu).rotulo === "eu@oria.com" && pessoaDoUsuario(outro, eu).rotulo === "usuário 22222222" && !pessoaDoUsuario(outro, eu).temEmail,
    "e-mail só do usuário logado; os demais pelo código curto, sem inventar nome");
  checar(ehUuid(outro) && !ehUuid("abc") && !ehUuid("22222222-2222-2222-2222-22222222222g") && !ehUuid(null), "uuid é validado na fronteira");
  const casos = [{ id: "c1", nome: "B", fechado_em: null }, { id: "c2", nome: "A", fechado_em: null }];
  const linhas = linhasDaEquipe(
    [{ usuario_id: outro, papel: "analista" }, { usuario_id: eu.id, papel: "socio" }],
    [{ caso_id: "c1", usuario_id: outro }, { caso_id: "c9", usuario_id: outro }], casos, eu);
  checar(linhas[0].papel === "socio" && linhas[0].unicoSocio && linhas[0].veTodos && linhas[0].alocaveis.length === 0, "Sócio primeiro, único Sócio marcado e sem alocação");
  checar(linhas[1].alocados.length === 1 && linhas[1].alocadosNaoLidos === 1 && linhas[1].alocaveis.map((c) => c.id).join() === "c2",
    "alocação de mandato não lido é CONTADA, e só se oferece o que falta");
  const eq = equipeDoMandato([{ usuario_id: outro, papel: "leitura" }, { usuario_id: eu.id, papel: "socio" }, { usuario_id: "33333333-3333-3333-3333-333333333333", papel: "analista" }],
    [{ caso_id: "c1", usuario_id: outro }, { caso_id: "c1", usuario_id: "44444444-4444-4444-4444-444444444444" }], eu);
  checar(eq.alocados.length === 1 && eq.alocaveis.length === 1 && eq.semPapel === 1 && eq.socios === 1, "equipe do mandato: Sócio não entra, alocação sem papel é contada à parte");
}

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
console.log("TEMA OK — a preferência resolve claro/escuro/sistema antes da pintura, toda cor do claro tem par no escuro e todo par medido passa AA");
console.log("CUSTOS OK — custo ausente fica ausente, o total é piso declarado e o por-documento usa um só conjunto");
console.log("RECUPERAR SENHA OK — o pedido não revela se a conta existe, next só aceita caminho interno e as rotas públicas são exatamente três");
console.log("ACESSO OK — a tela só evita o clique inútil: sem papel nada vale, o envio e a Administração fecham para quem o banco não vê, e falha de leitura não tranca ninguém fora");
console.log("AVISOS OK — lote demorando nunca vira \"parado\", falha duplicada vira um aviso, documento não lido não é \"concluído\", e visto indisponível não vira \"nada novo\"");
