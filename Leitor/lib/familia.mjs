// A FAMÍLIA DE UM ARQUIVO OFICIAL, medida nos bytes (Espec. 12, G5).
//
// O defeito que este arquivo fecha, medido em 13/10/2026 no nó "Preparar Conteúdo"
// do n8n (`N8N/build-workflow.mjs`): `detectarFormato` sabe o FORMATO (pdf, xlsx,
// xml, texto), mas não a família. Um SPED vira `texto`, é decodificado como UTF-8
// (o SPED é latin1, então os acentos se corrompem) e vai INTEIRO para a IA como se
// fosse um balanço. Uma NF-e vira `xml` e vai pelo mesmo caminho. Não há SPED em
// produção hoje (`0187`), então isso nunca disparou; seria no primeiro envio.
//
// O contrato é o mesmo do `formato.mjs`, e o formato vem DELE (escada, degrau 2):
// decide pelos bytes quando os bytes decidem, e diz qual foi a evidência. Arquivo
// que não é de nenhuma família oficial devolve `familia: null`, e é isso que manda
// o documento para o caminho atual (extração por IA), sem mudar nada nele.

import { detectarFormato } from '../../N8N/lib/formato.mjs';
import { SPED, XML } from './leiautes.mjs';
import { dataDDMMAAAA, cnpj } from './campos.mjs';

const CABECA = 65536;

/** Primeira linha sem o fim de linha (aceita \r\n e \n). */
function primeiraLinha(texto) {
  const i = texto.indexOf('\n');
  return (i === -1 ? texto : texto.slice(0, i)).replace(/\r$/, '');
}

/** Distingue as quatro escriturações SPED pelo registro 0000 (cada uma tem um 0000 diferente). */
export function subtipoSped(linha0000) {
  const c = linha0000.split('|');
  if (c[2] === SPED.ECD.marca.valor) return 'ECD';
  if (c[2] === SPED.ECF.marca.valor) return 'ECF';
  // EFD ICMS/IPI e EFD-Contribuições começam os dois por COD_VER (3 dígitos) e um
  // indicador de 1 dígito. O que separa é ONDE estão as datas e o CNPJ: na ICMS/IPI
  // DT_INI está no índice 4 e o CNPJ no 7; na Contribuições, DT_INI no 6 e CNPJ no 9.
  const e = SPED.EFD_ICMS_IPI, k = SPED.EFD_CONTRIBUICOES;
  if (dataDDMMAAAA(c[e.dtIni]) && dataDDMMAAAA(c[e.dtFim]) && cnpj(c[e.cnpj])) return 'EFD_ICMS_IPI';
  if (dataDDMMAAAA(c[k.dtIni]) && dataDDMMAAAA(c[k.dtFim]) && cnpj(c[k.cnpj])) return 'EFD_CONTRIBUICOES';
  return null;
}

/** Família e subtipo de um XML oficial, pelo namespace (é o namespace que o schema oficial fixa). */
function familiaXml(texto) {
  for (const fam of ['nfe', 'cte', 'mdfe', 'nfse']) {
    if (texto.includes(`"${XML[fam].namespace}"`)) return { familia: fam, evidencia: `namespace ${XML[fam].namespace}` };
  }
  let m = texto.match(/xmlns="http:\/\/www\.esocial\.gov\.br\/schema\/evt\/(evt\w+)\/(v_S_\d\d_\d\d_\d\d)"/);
  if (m) return { familia: 'esocial', subtipo: m[1], evidencia: `namespace do evento ${m[1]}` };
  m = texto.match(/xmlns="http:\/\/www\.reinf\.esocial\.gov\.br\/schemas\/(evt\w+)\/(v\d+_\d+_\d+)"/);
  if (m) return { familia: 'reinf', subtipo: m[1], evidencia: `namespace do evento ${m[1]}` };
  return null;
}

/** CNAB pelo tamanho fixo da linha e pela marca do header; exige duas linhas do mesmo tamanho. */
function familiaCnab(texto) {
  // Relatório de largura fixa (comum em ERP) também tem linhas do mesmo tamanho.
  // Por isso cada leiaute exige MAIS de uma marca do header, e o 240 exige que a
  // segunda linha seja header de lote: um falso positivo aqui tiraria um documento
  // legítimo do caminho da IA.
  const linhas = texto.split(/\r\n|\n|\r/, 3);
  if (linhas.length < 2) return null;
  const [a, b] = linhas;
  if (a.length !== b.length) return null;
  const dig = (s) => /^\d+$/.test(s);
  if (a.length === 240 && a[7] === '0' && dig(a.slice(0, 3)) && a.slice(3, 7) === '0000' && b[7] === '1' && b.slice(0, 3) === a.slice(0, 3)) return { familia: 'cnab240', evidencia: 'linhas de 240 posições, header de arquivo (lote 0000, tipo 0) seguido de header de lote do mesmo banco' };
  if (a.length === 400 && a[0] === '0' && /^[12]$/.test(a[1]) && dig(a.slice(76, 79))) return { familia: 'cnab400', evidencia: 'linhas de 400 posições, header 0 com operação na posição 2 e banco em 77-79' };
  if (a.length === 150 && a[0] === 'A' && /^[12]$/.test(a[1]) && dig(a.slice(42, 45))) return { familia: 'cnab150', evidencia: 'linhas de 150 posições, header A com remessa/retorno na posição 2 e banco em 43-45' };
  return null;
}

/**
 * A família de um arquivo, pelos primeiros 64 KB.
 * @returns {{familia: string|null, subtipo?: string|null, formato: string, evidencia: string}}
 *   familia null = não é arquivo oficial (segue o caminho atual); 'zip' = contêiner a abrir.
 */
export function detectarFamilia(buf) {
  const det = detectarFormato(buf);
  if (det.formato === 'pdf' || det.formato === 'imagem' || det.formato === 'xlsx' || det.formato === 'xls') {
    return { familia: null, formato: det.formato, evidencia: `formato ${det.formato}: não é arquivo de leiaute oficial` };
  }
  // Zip que não é planilha: o `formato.mjs` devolve 'desconhecido' com evidência de
  // assinatura. A assinatura PK\x03\x04 é a definição de zip.
  if (buf.length >= 4 && buf[0] === 0x50 && buf[1] === 0x4b && buf[2] === 0x03 && buf[3] === 0x04) {
    return { familia: 'zip', formato: 'zip', evidencia: 'assinatura PK\\x03\\x04: contêiner zip a abrir' };
  }
  // latin1 aqui é DE PROPÓSITO: SPED e CNAB são latin1, e para os marcadores ASCII
  // procurados abaixo (|0000|, namespaces, OFXHEADER) latin1 e UTF-8 coincidem.
  const texto = buf.subarray(0, CABECA).toString('latin1').replace(/^﻿|^ï»¿/, '');
  const inicio = texto.trimStart();
  if (inicio.startsWith('|0000|')) {
    const subtipo = subtipoSped(primeiraLinha(inicio));
    return { familia: 'sped', subtipo, formato: det.formato, evidencia: subtipo ? `registro 0000 de ${subtipo}` : 'registro 0000 de leiaute SPED não reconhecido' };
  }
  if (/^OFXHEADER:/.test(inicio) || /^<\?xml[^>]*\?>\s*<\?OFX/.test(inicio) || /^<OFX>/i.test(inicio)) {
    return { familia: 'ofx', formato: det.formato, evidencia: 'cabeçalho OFX' };
  }
  if (inicio.startsWith('<')) {
    const x = familiaXml(texto);
    if (x) return { subtipo: null, ...x, formato: 'xml' };
  }
  const cnab = familiaCnab(texto);
  if (cnab) return { ...cnab, subtipo: null, formato: det.formato };
  return { familia: null, formato: det.formato, evidencia: `formato ${det.formato}, sem marca de leiaute oficial` };
}
