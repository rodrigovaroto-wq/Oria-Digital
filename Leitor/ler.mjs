#!/usr/bin/env node
// O SERVIÇO LEITOR, na forma de linha de comando (Espec. 12, D12.9).
//
//   node Leitor/ler.mjs <arquivo>...                       → imprime o envelope de cada arquivo (JSON)
//   LEITOR_PSQL="psql '<url>'" node Leitor/ler.mjs --caso <uuid> [--documento <uuid>] <arquivo>...
//                                                          → registra cada envelope em `arquivo_oficial`
//
// Por que linha de comando e ainda não um serviço HTTP: onde o leitor vai morar
// (máquina, contêiner) é o P5 da Espec. 12, e não está decidido. O CLI é a mesma
// leitura que o serviço vai chamar; o que falta é só o transporte. Até lá, nada
// em produção muda: o n8n continua sem chamar o leitor.
//
// Zip é aberto aqui (G5), por posição no disco e em fluxo (`lib/zip.mjs`, o MESMO código do
// navegador): o pacote não vai inteiro para a memória, então passa de 3 GB. Cada arquivo de
// dentro vira um envelope, e cada entrada recusada (zip-bomb, zip aninhado, cifrado, CRC,
// tamanho declarado que mente) aparece na saída com o motivo.
//
// Sai com código 1 se algum arquivo não ficou `lido`: o chamador (o n8n, depois)
// não pode tratar "rodou" como "leu tudo" (regra 7).

import { openAsBlob } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { basename } from 'node:path';
import { lerEnvelopeDeFluxo } from './lib/envelope.mjs';
import { lerEnvelopeDeArquivo } from './lib/arquivo.mjs';
import { entradasDoZip, motivoDoErro } from './lib/zip.mjs';
import { LEITOR_VERSAO } from './lib/leiautes.mjs';

const args = process.argv.slice(2);
const opcao = (nome) => {
  const i = args.indexOf(nome);
  if (i === -1) return null;
  const v = args[i + 1];
  // `--caso` sem valor não pode virar "não registrar nada e sair com 0".
  if (!v || v.startsWith('--')) { console.error(`${nome} exige um valor`); process.exit(2); }
  args.splice(i, 2);
  return v;
};
const caso = opcao('--caso');
const documento = opcao('--documento');
if (args.length === 0) {
  console.error('uso: node Leitor/ler.mjs [--caso <uuid> [--documento <uuid>]] <arquivo>...');
  process.exit(2);
}

function registrar(env) {
  const psql = process.env.LEITOR_PSQL;
  if (!psql) throw new Error('--caso exige LEITOR_PSQL (o comando psql com a conexão), como CONFERIR_PSQL nos outros scripts');
  const json = JSON.stringify(env);
  // Dollar-quoting com uma marca que o JSON não contém: nada do conteúdo do
  // arquivo (um nome de empresa com aspas, por exemplo) vira SQL.
  let marca = 'env';
  while (json.includes(`$${marca}$`)) marca += 'x';
  const doc = documento ? `'${documento}'::uuid` : 'null';
  const sql = `select fn_registrar_arquivo_oficial('${caso}'::uuid, ${doc}, $${marca}$${json}$${marca}$::jsonb);`;
  if (!/^[0-9a-f-]{36}$/i.test(caso) || (documento && !/^[0-9a-f-]{36}$/i.test(documento))) throw new Error('--caso e --documento são uuids');
  // /bin/sh pelo caminho absoluto: o executável não depende do PATH de quem chama (S4036).
  // O LEITOR_PSQL é um comando de shell DE PROPÓSITO, como o CONFERIR_PSQL dos outros scripts.
  const r = spawnSync('/bin/sh', ['-c', `${psql} -X -q -A -t -v ON_ERROR_STOP=1 -f -`], { input: sql, encoding: 'utf8' });
  if (r.status !== 0) throw new Error((r.stderr || r.stdout).trim());
  // A função devolve o que FICOU gravado (id, status, vigente). O status gravado
  // tem de ser o que este leitor leu: um reenvio que o banco descartasse não pode
  // aparecer aqui como "lido".
  return JSON.parse(r.stdout.trim());
}

const saida = [];
let todosLidos = true;

function processar(item) {
  if (item.recusado || !item.familia) {
    if (item.recusado) todosLidos = false;
    saida.push(item);
    return;
  }
  if (item.status !== 'lido') todosLidos = false;
  const { origem, evidencia, ...linha } = item;
  linha.detalhe = { ...linha.detalhe, origem };
  if (caso) {
    try {
      const gravado = registrar(linha);
      item.arquivo_oficial = gravado;
      if (gravado.status !== linha.status) {
        todosLidos = false;
        item.erro_registro = `o banco ficou com status ${gravado.status}, e este leitor leu ${linha.status}`;
      }
    } catch (e) { item.erro_registro = e.message; todosLidos = false; }
  }
  saida.push(item);
}

for (const caminho of args) {
  const env = await lerEnvelopeDeArquivo(caminho);
  if (env.familia !== 'zip') { processar({ origem: basename(caminho), ...env }); continue; }
  // O ZIP também é registrado, como contêiner: quantas entradas ele tinha, quantas
  // foram processadas e quais foram recusadas, com o motivo. Sem isso, uma entrada
  // cifrada some do banco sem rastro (regra 7). Arquivo NÃO oficial dentro do zip
  // (um PDF de balanço) é contado como processado e listado: ele segue para o
  // caminho atual, a extração por IA.
  // O zip NÃO vai para a memória: `entradasDoZip` lê o diretório e cada entrada por
  // posição no disco (`openAsBlob`), e o hash do contêiner já veio do envelope acima
  // (o fluxo do zip inteiro passou pelo sha256). Pacote de 3 GB abre com a memória
  // de uma entrada em curso.
  let entradas = 0, processadas = 0;
  const recusadas = [], naoOficiais = [];
  for await (const e of entradasDoZip(await openAsBlob(caminho))) {
    entradas++;
    const origem = `${basename(caminho)}:${e.nome}`;
    if (e.recusado) { recusadas.push({ nome: e.nome, motivo: e.recusado }); processar({ origem, recusado: e.recusado }); continue; }
    let env2;
    try { env2 = await lerEnvelopeDeFluxo(e.fluxo()); }
    catch (err) {
      // O fluxo da entrada erra no tamanho declarado, no CRC e no deflate corrompido:
      // a entrada vira recusada COM o motivo, e o resto do pacote segue.
      const motivo = motivoDoErro(err);
      recusadas.push({ nome: e.nome, motivo }); processar({ origem, recusado: motivo }); continue;
    }
    processadas++;
    if (!env2.familia) naoOficiais.push(e.nome);
    processar({ origem, ...env2 });
  }
  processar({
    origem: basename(caminho), familia: 'zip', subtipo: null, versao_leiaute: null,
    hash_sha256: env.hash_sha256, chave_natural: env.hash_sha256,
    cnpj: null, periodo_ini: null, periodo_fim: null, retificadora: false, controle_tipo: 'contagem_declarada',
    controle_declarado: entradas, controle_lido: processadas,
    status: entradas === processadas ? 'lido' : 'controle_divergente',
    detalhe: { recusadas, nao_oficiais: naoOficiais }, leitor_versao: LEITOR_VERSAO,
  });
}
console.log(JSON.stringify(saida, null, 2));
process.exit(todosLidos ? 0 : 1);
