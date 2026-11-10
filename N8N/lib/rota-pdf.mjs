// A ROTA DE LEITURA DO PDF (texto ou imagem) como FONTE embutível no nó Code.
// Fica aqui, e não dentro de `build-workflow.mjs`, para o teste poder importá-la
// sem executar o gerador. UMA lista, dois consumidores: o nó (`FONTE_COBERTURA`)
// e o hash do `FINGERPRINT_EXTRACAO`. Duas cópias da lista divergem calado.
import {
  linhasComNumero, camadaDeTextoDoPdf, linhasCurtasDaTabela, CARACTERES_MINIMOS_POR_PAGINA,
  MINIMO_LINHAS_COM_NUMERO_PDF, fracaoDePalavrasDobradas, MAX_FRACAO_PALAVRAS_DOBRADAS,
  fracaoDeNumerosColados, MAX_FRACAO_NUMEROS_COLADOS,
} from './cobertura.mjs';

// A ORDEM é a de execução no Code do n8n (sem hoisting de `const`): `linhasComNumero`
// primeiro, as constantes, os três helpers, e `camadaDeTextoDoPdf`, que chama todos.
// FECHADA de propósito: avaliada sozinha ela tem de rodar (teste em
// `workflow-sim.test.mjs`) — helper novo da rota que ficar fora desta lista
// reprova lá, em vez de virar `ReferenceError` em produção ou rota fora do hash.
export const FONTE_ROTA_PDF = [
  `const linhasComNumero = ${linhasComNumero.toString()};`,
  `const CARACTERES_MINIMOS_POR_PAGINA = ${CARACTERES_MINIMOS_POR_PAGINA};`,
  `const MINIMO_LINHAS_COM_NUMERO_PDF = ${MINIMO_LINHAS_COM_NUMERO_PDF};`,
  `const MAX_FRACAO_PALAVRAS_DOBRADAS = ${MAX_FRACAO_PALAVRAS_DOBRADAS};`,
  `const MAX_FRACAO_NUMEROS_COLADOS = ${MAX_FRACAO_NUMEROS_COLADOS};`,
  `const fracaoDePalavrasDobradas = ${fracaoDePalavrasDobradas.toString()};`,
  `const linhasCurtasDaTabela = ${linhasCurtasDaTabela.toString()};`,
  `const fracaoDeNumerosColados = ${fracaoDeNumerosColados.toString()};`,
  `const camadaDeTextoDoPdf = ${camadaDeTextoDoPdf.toString()};`,
];
