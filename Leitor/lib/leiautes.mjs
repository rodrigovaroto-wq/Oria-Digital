// O REGISTRO DE LEIAUTES (Espec. 12, G7): o que o leitor sabe ler, versão por versão.
//
// Por que um registro e não um `if` por formato: os leiautes mudam. A ECF e a ECD
// mudam a cada ano, o eSocial passou do S-1.2 para o S-1.3, a NF-e ganhou os
// campos da reforma tributária. Um leitor que aceita qualquer versão lê um arquivo
// de leiaute novo com as posições do velho e devolve números deslocados SEM ERRO.
// A regra aqui é a oposta: versão fora desta lista é `versao_desconhecida`, falha
// visível, e quem a resolve é a pessoa que confere o Guia Prático e acrescenta a
// versão abaixo, com o teste dela.
//
// [A CONFIRMAR] As versões e as posições abaixo foram escritas de memória dos Guias
// Práticos e dos schemas oficiais, e os testes as exercitam com arquivos SINTÉTICOS
// gerados a partir deste mesmo registro. Isso prova que o leitor é coerente consigo
// mesmo, e NÃO que ele lê um arquivo real (regra 4 do CLAUDE.md). A prova contra
// arquivo real é o aceite da onda 1 (3 ECDs reais, roadmap F2T). Até lá, uma versão
// real ausente daqui reprova alto, que é o modo de falha certo.

// SPED: posições (índice depois do split por '|', em que [0] é vazio e [1] é o
// código do registro) dos campos de identificação no registro 0000 de cada
// escrituração. As quatro escriturações têm 0000 DIFERENTES, e é por essas
// posições que o leitor distingue uma da outra.
export const SPED = {
  ECD: {
    // |0000|LECD|DT_INI|DT_FIN|NOME|CNPJ|UF|IE|COD_MUN|IM|IND_SIT_ESP|IND_SIT_INI_PER|IND_NIRE|IND_FIN_ESC|...
    marca: { indice: 2, valor: 'LECD' },
    dtIni: 3, dtFim: 4, nome: 5, cnpj: 6,
    // A ECD não tem versão no 0000: ela vem no I010 (COD_VER_LC). IND_FIN_ESC
    // (0 original, 1 substituta) diz se é retificadora.
    versao: { registro: 'I010', indice: 3 },
    retificadora: { indice: 14, valores: ['1'] },
    versoes: ['9.00', '10.00'],
  },
  ECF: {
    // |0000|LECF|COD_VER|CNPJ|NOME|IND_SIT_INI_PER|SIT_ESPECIAL|PAT_REMAN_CIS|DT_SIT_ESP|DT_INI|DT_FIN|RETIFICADORA|...
    marca: { indice: 2, valor: 'LECF' },
    versao: { registro: '0000', indice: 3 },
    cnpj: 4, nome: 5, dtIni: 10, dtFim: 11,
    retificadora: { indice: 12, valores: ['S', 'F'] },
    versoes: ['0010', '0011'],
  },
  EFD_ICMS_IPI: {
    // |0000|COD_VER|COD_FIN|DT_INI|DT_FIN|NOME|CNPJ|CPF|UF|IE|COD_MUN|IM|SUFRAMA|IND_PERFIL|IND_ATIV|
    versao: { registro: '0000', indice: 2 },
    retificadora: { indice: 3, valores: ['1'] },
    dtIni: 4, dtFim: 5, nome: 6, cnpj: 7,
    versoes: ['018', '019', '020'],
  },
  EFD_CONTRIBUICOES: {
    // |0000|COD_VER|TIPO_ESCRIT|IND_SIT_ESP|NUM_REC_ANTERIOR|DT_INI|DT_FIN|NOME|CNPJ|UF|COD_MUN|SUFRAMA|IND_NAT_PJ|IND_ATIV|
    versao: { registro: '0000', indice: 2 },
    retificadora: { indice: 3, valores: ['1'] },
    dtIni: 6, dtFim: 7, nome: 8, cnpj: 9,
    versoes: ['006'],
  },
};

// XML: a versão vem do atributo `versao` do elemento de informação (NF-e, CT-e,
// MDF-e, NFS-e) ou do NAMESPACE do evento (eSocial e Reinf versionam o schema no
// próprio namespace, ex.: .../evtRemun/v_S_01_02_00).
// Os eventos (cancelamento, carta de correção, manifestação) têm schema e versão
// PRÓPRIOS, diferentes da versão do documento: `versoesEvento`.
export const XML = {
  nfe:  { namespace: 'http://www.portalfiscal.inf.br/nfe',  elemento: 'infNFe', prefixoId: 'NFe',  versoes: ['4.00'], versoesEvento: ['1.00'] },
  cte:  { namespace: 'http://www.portalfiscal.inf.br/cte',  elemento: 'infCte', prefixoId: 'CTe',  versoes: ['4.00'], versoesEvento: ['4.00'] },
  mdfe: { namespace: 'http://www.portalfiscal.inf.br/mdfe', elemento: 'infMDFe', prefixoId: 'MDFe', versoes: ['3.00'], versoesEvento: ['3.00'] },
  nfse: { namespace: 'http://www.sped.fazenda.gov.br/nfse', elemento: 'infNFSe', prefixoId: 'NFS',  versoes: ['1.00', '1.01'] },
  esocial: { raizNamespace: 'http://www.esocial.gov.br/schema/evt/', versoes: ['v_S_01_02_00', 'v_S_01_03_00'] },
  reinf:   { raizNamespace: 'http://www.reinf.esocial.gov.br/schemas/', versoes: ['v2_01_02'] },
};

// CNAB: o tamanho da linha É a versão do leiaute (240, 400 ou 150 posições), e o
// controle de leitura completa mora no trailer de arquivo. Posições FEBRABAN,
// contadas a partir de 1.
export const CNAB = {
  cnab240: {
    tamanho: 240,
    tipoRegistro: [8, 8],            // 0 header arquivo, 1 header lote, 3 detalhe, 5 trailer lote, 9 trailer arquivo
    segmento: [14, 14],              // no detalhe (tipo 3): P/Q/R/S/T/U/Y cobrança, A/B/C/J/N/O/W pagamentos, E extrato
    banco: [1, 3],
    cnpjHeader: [19, 32],            // header de arquivo: tipo de inscrição em 18, número em 19-32
    trailerQtdRegistros: [24, 29],   // trailer de arquivo: quantidade de registros do arquivo
  },
  cnab400: {
    tamanho: 400,
    // 0 header, 1 detalhe (outros dígitos em extensões por banco), 9 trailer.
    tipoRegistro: [1, 1],
    operacao: [2, 2],                // no header: 1 remessa, 2 retorno
    banco: [77, 79],
    sequencial: [395, 400],          // toda linha numerada: o último sequencial É a contagem
  },
  cnab150: {
    tamanho: 150,
    // Débito automático: A header, Z trailer; as letras do meio são os tipos de registro.
    tipoRegistro: [1, 1],
    banco: [43, 45],
    trailerQtdRegistros: [2, 7],
  },
};

// OFX: 1.x é SGML (cabeçalho OFXHEADER:100), 2.x é XML (<?OFX OFXHEADER="200" ...?>).
export const OFX = { versoes: ['102', '103', '151', '160', '200', '211', '220'] };

/** Versão do leitor gravada em cada envelope: quando um leiaute muda, dá para achar tudo que foi lido antes. */
export const LEITOR_VERSAO = 'leitor-envelope/1';
