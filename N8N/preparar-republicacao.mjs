// O JSON PRONTO PARA PUBLICAR — comportamento do repositório, identidade da instalação.
//
// POR QUE ISTO EXISTE. Duas republicações seguidas (26/08 e 27/08) perderam a
// mesma coisa: os campos de nó que vivem FORA de `parameters`. Medido na
// segunda, contra o workflow vivo: `onError: continueRegularOutput` em 23 nós,
// `retryOnFail`/`maxTries`/`waitBetweenTries` em 11 — e, na do dia 27, o
// `multipleFiles: true` do campo de arquivo do formulário, que é o que permite
// subir mais de um documento por vez.
//
// Corrigir isso à mão é abrir 23 nós no editor e mexer na aba Settings de cada
// um. Este script faz a fusão em um comando: parte do JSON do REPOSITÓRIO (que
// é a autoridade sobre o que o workflow FAZ e COMO ele falha) e traz do
// PUBLICADO só o que pertence à instalação e não pode ser sobrescrito:
//
//   • o `id` de cada credencial — o repositório grava `REPLACE` de propósito,
//     para não guardar nada da instalação;
//   • o `path` do gatilho de formulário — ele é atribuído pelo n8n, e
//     sobrescrevê-lo TROCA A URL PÚBLICA do intake (já se perdeu uma vez assim);
//   • o `id` de cada nó e as `settings` do workflow — onde mora, entre outras
//     coisas, o `errorWorkflow` que o dono ligou à mão.
//
//   curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$ID" \
//     | node N8N/preparar-republicacao.mjs > publicar.json
//
//   curl -X PUT -H "X-N8N-API-KEY: $N8N_API_KEY" -H 'Content-Type: application/json' \
//     "$N8N_URL/api/v1/workflows/$ID" --data-binary @publicar.json
//
//   # e conferir o que ficou de pé, que é o passo que ninguém pode pular:
//   curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$ID" \
//     | node N8N/conferir-publicado.mjs
//
// O JSON sai por `JSON.stringify`, que escapa `\uXXXX` corretamente — a
// armadilha de 26/08 era o transporte do MCP DECODIFICAR esses escapes e
// transformar a chave de dedup do `Juntar Blocos` num byte NUL cru. Por `curl`
// com `--data-binary`, o byte que sai é o que este script escreveu.
import { readFileSync } from 'node:fs';
import { lerWorkflowDaEntradaPadrao, ehExecucaoDireta } from './entrada-workflow.mjs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/** O que o PUT aceita — mandar campo a mais faz o n8n recusar a requisição. */
const CAMPOS_DO_PUT = ['name', 'nodes', 'connections', 'settings'];

/**
 * OS PLACEHOLDERS DE CREDENCIAL — ids que o REPOSITÓRIO grava e que nenhuma
 * instalação tem. Qualquer um deles, no mapa do ambiente ou no publicado, é
 * AUSÊNCIA, não resposta.
 *
 * `SUPABASE_PG` entrou em 24/09/2026: o gerador do macro o gravava nas três
 * credenciais Postgres até então (os outros três geradores gravam `REPLACE`). Se
 * ele chegou à instalação, o publicado o carrega como se fosse id real — e, com só
 * `REPLACE` aqui, a republicação o preservava (o VIVO ganha) e a trava do
 * `republicar.sh` não o via. `conferir-publicado.mjs` usa a mesma lista.
 */
export const PLACEHOLDERS_DE_CREDENCIAL = new Set(['REPLACE', 'SUPABASE_PG']);
export const ehPlaceholderDeCredencial = (id) => PLACEHOLDERS_DE_CREDENCIAL.has(String(id ?? '').trim());

/**
 * IDs DE CREDENCIAL VINDOS DE FORA, por NOME — a saída para o que o vivo não conta.
 *
 * POR QUE ISTO EXISTE, e o número é medido. `prepararRepublicacao` resolve o id
 * lendo o workflow PUBLICADO, e isso funciona para a maioria: na republicação de
 * 11/09/2026 as ONZE credenciais `postgres` resolveram todas. As TRÊS
 * `httpHeaderAuth` não resolveram NENHUMA — e a divisão é por TIPO, não por nó.
 * A API pública do n8n (`GET /api/v1/workflows/:id`) não devolve a credencial
 * `httpHeaderAuth` desses nós, então não há o que ler. O resultado foi a action
 * do GitHub abortar em TRÊS execuções seguidas, no passo 4, com "sobraram 2
 * ocorrência(s) de REPLACE" — `IA Classificar` e `IA Extrair`.
 *
 * A trava que abortou estava CERTA: publicar `REPLACE` num nó ligado quebra a
 * credencial dele em produção. O que faltava era um jeito de o id chegar aqui
 * sem passar pelo vivo — e sem ser versionado, que é a razão de o repositório
 * gravar `REPLACE` desde sempre.
 *
 * A CHAVE É O NOME DA CREDENCIAL, não o nó: uma mesma credencial ("OpenAI API")
 * serve vários nós, e mapear por nó obrigaria a repetir o mesmo id N vezes —
 * cada repetição uma chance de divergir.
 *
 * Formato (JSON no ambiente, tipicamente um secret do GitHub):
 *     N8N_CRED_IDS='{"OpenAI API":"aBc123","Supabase Service (Header Auth)":"dEf456"}'
 *
 * PRECEDÊNCIA, e ela é deliberada: o VIVO ganha. Quem está publicado é a verdade
 * sobre a instalação; o mapa é a queda para quando ele se cala. Ao contrário, um
 * mapa desatualizado sobrescreveria silenciosamente a credencial certa por uma
 * que não existe mais — e o sintoma apareceria só na próxima rodada.
 *
 * ID INVÁLIDO NÃO ENTRA: `REPLACE` ou vazio no mapa é tratado como ausência, não
 * como resposta. Aceitar `REPLACE` aqui desarmaria a trava do `republicar.sh`
 * fazendo exatamente o que ela existe para impedir.
 */
export function idsDeCredencialDoAmbiente(env = process.env) {
  const cru = env.N8N_CRED_IDS;
  if (!cru || !String(cru).trim()) return {};
  let mapa;
  try {
    mapa = JSON.parse(cru);
  } catch {
    throw new Error('N8N_CRED_IDS não é JSON válido. Esperado um objeto '
      + '{"<nome da credencial>": "<id>"} — por exemplo {"OpenAI API":"aBc123"}.');
  }
  if (!mapa || typeof mapa !== 'object' || Array.isArray(mapa)) {
    throw new Error('N8N_CRED_IDS precisa ser um OBJETO {"<nome>": "<id>"}, não '
      + `${Array.isArray(mapa) ? 'uma lista' : typeof mapa}.`);
  }
  const limpo = {};
  for (const [nome, id] of Object.entries(mapa)) {
    if (typeof id === 'string' && id.trim() && !ehPlaceholderDeCredencial(id)) limpo[nome] = id.trim();
  }
  return limpo;
}

/** Marca de par (tipo, nome) com mais de um id no publicado — ver acima. */
const AMBIGUO = Symbol('id ambiguo no publicado');

/** O id do índice, ou `undefined` quando ausente OU ambíguo. */
function idDoIndice(indice, tipo, nome) {
  const achado = indice.get(tipo)?.get(nome);
  return typeof achado === 'string' ? achado : undefined;
}

/**
 * IDS DE CREDENCIAL LIDOS DO PUBLICADO, por TIPO e NOME — o que o nó irmão sabe.
 *
 * POR QUE ISTO EXISTE, com o número medido na action de 12/09/2026. A resolução
 * do id era por NÓ: o preparador procurava o nó de mesmo nome no publicado e
 * lia a credencial dele. Isso resolve todo nó que já foi publicado uma vez — e
 * NENHUM nó novo, porque um nó que ainda não existe na instalação não tem o que
 * ser lido. Dos ONZE nós `postgres` do workflow, todos os onze usam a MESMA
 * credencial ("Supabase Postgres (Session Pooler)"); nove resolveram pelo
 * publicado e DOIS não — `Gravar Uso do Lote` e `Conferir Lote`, os dois
 * habilitados, os dois abortando o arquivo inteiro no portão do `republicar.sh`.
 *
 * O id que faltava estava na resposta, a dois nós de distância. O preparador
 * tinha a informação e não olhava para ela.
 *
 * A CHAVE É (TIPO, NOME), e o tipo entra de propósito: o nome de credencial é
 * único por tipo no n8n, não globalmente, e casar só por nome deixaria uma
 * credencial `postgres` responder por uma `httpHeaderAuth` de mesmo nome.
 *
 * AMBIGUIDADE NÃO RESPONDE. Se o publicado traz o mesmo (tipo, nome) com ids
 * DIFERENTES em nós diferentes, não há como saber qual é o certo, e escolher um
 * seria apontar metade dos nós para a credencial errada — falha silenciosa, que
 * é o defeito desta família. O par ambíguo simplesmente não entra no índice e o
 * nó cai para o mapa do ambiente, ou para o `REPLACE` que trava o portão.
 *
 * `REPLACE` e vazio no publicado são ausência, não resposta — mesma regra do
 * mapa do ambiente, pelo mesmo motivo: aceitá-los desarmaria a trava.
 */
export function idsDeCredencialDoPublicado(vivo) {
  const vistos = new Map();
  for (const n of vivo?.nodes ?? []) {
    for (const [tipo, cred] of Object.entries(n.credentials ?? {})) {
      if (!ehIdUtilizavel(cred?.id) || !ehNomePreenchido(cred?.name)) continue;
      anotarNoIndice(vistos, tipo, cred.name, cred.id);
    }
  }
  return vistos;
}

/** Placeholder (`REPLACE`, `SUPABASE_PG`) e vazio são ausência, não resposta — ver `idsDeCredencialDoPublicado`. */
function ehIdUtilizavel(id) {
  return typeof id === 'string' && !!id.trim() && !ehPlaceholderDeCredencial(id);
}

function ehNomePreenchido(nome) {
  return typeof nome === 'string' && !!nome.trim();
}

/** Primeiro id vence; um SEGUNDO id diferente marca o par como ambíguo para sempre. */
function anotarNoIndice(vistos, tipo, nome, id) {
  let porNome = vistos.get(tipo);
  if (!porNome) {
    porNome = new Map();
    vistos.set(tipo, porNome);
  }
  const jaVisto = porNome.get(nome);
  if (jaVisto === undefined) porNome.set(nome, id);
  else if (jaVisto !== id) porNome.set(nome, AMBIGUO);
}

export function prepararRepublicacao(vivo, repo, { idsPorNome = {} } = {}) {
  const doVivo = new Map((vivo.nodes ?? []).map((n) => [n.name, n]));
  const doPublicado = idsDeCredencialDoPublicado(vivo);

  const nodes = (repo.nodes ?? []).map((doRepo) => {
    const oVivo = doVivo.get(doRepo.name);
    const saida = { ...doRepo };

    // O id do NÓ: preservado quando existe, para o n8n não tratar o nó como
    // novo (o que descarta o histórico de execução preso a ele).
    if (oVivo?.id) saida.id = oVivo.id;
    if (oVivo?.webhookId) saida.webhookId = oVivo.webhookId;

    // O `path` do formulário — ver o cabeçalho. É o único parâmetro que o
    // publicado manda no repositório, e não o contrário.
    if (oVivo?.parameters?.path) {
      saida.parameters = { ...doRepo.parameters, path: oVivo.parameters.path };
    }

    // As CREDENCIAIS: o tipo e o nome são do repositório, o id é da instalação.
    // Sem isto, o `REPLACE` do repositório iria para produção e o nó falharia
    // com "Credential with ID REPLACE does not exist" — que foi exatamente o
    // erro do smoke test de 27/08.
    //
    // (Desde 07/10/2026 o `Upload Storage` é LIGADO, então esta exceção não o
    // alcança mais: ele cai no `REPLACE` e a trava do republicar.sh o segura até
    // haver id — vivo, irmão ou N8N_CRED_IDS. Ela continua valendo para qualquer
    // nó desabilitado que apareça no futuro.)
    // A EXCEÇÃO medida em 11/09/2026, no `Upload Storage`: nó DESABILITADO
    // sem id na instalação. Ele não executa — então a credencial some em vez
    // de ir REPLACE: nó desligado sem credencial não falha; nó desligado COM
    // REPLACE é o que o portão do republicar.sh barra o arquivo inteiro. Um
    // nó LIGADO sem id continua recebendo o REPLACE, e o portão continua
    // abortando — a trava fica intacta onde ela é defesa.
    if (doRepo.credentials) {
      saida.credentials = {};
      for (const [tipo, cred] of Object.entries(doRepo.credentials)) {
        const idVivo = oVivo?.credentials?.[tipo]?.id;
        const nomeVivo = oVivo?.credentials?.[tipo]?.name;
        // O mapa do ambiente é a QUEDA, nunca a primeira escolha — ver o
        // cabeçalho de `idsDeCredencialDoAmbiente`.
        const idDeFora = idsPorNome[cred.name];
        // O IRMÃO: a mesma credencial (tipo, nome) já publicada em OUTRO nó.
        // Vem ANTES do mapa do ambiente pela mesma razão que o vivo vem antes
        // dele — quem está publicado é a verdade sobre a instalação, e o mapa é
        // a queda para quando ela se cala. Ver `idsDeCredencialDoPublicado`.
        const idDoIrmao = idDoIndice(doPublicado, tipo, cred.name);
        if (ehIdUtilizavel(idVivo)) {
          saida.credentials[tipo] = { id: idVivo, name: nomeVivo ?? cred.name };
        } else if (idDoIrmao) {
          saida.credentials[tipo] = { id: idDoIrmao, name: cred.name };
        } else if (idDeFora) {
          saida.credentials[tipo] = { id: idDeFora, name: cred.name };
        } else if (!doRepo.disabled) {
          saida.credentials[tipo] = { ...cred };
        }
      }
      if (Object.keys(saida.credentials).length === 0) delete saida.credentials;
    }
    return saida;
  });

  return {
    name: repo.name ?? vivo.name,
    nodes,
    connections: repo.connections ?? {},
    // As `settings` são da INSTALAÇÃO: é onde o dono ligou o `errorWorkflow`, e
    // sobrescrever com as do repositório o desligaria em silêncio — o defeito
    // desta família, cometido de novo em outro campo.
    settings: { ...repo.settings, ...vivo.settings },
  };
}

/** Os nós que ainda saem com `REPLACE` — o passo manual que sobra. */
export { arquivoDoRepo };

export function credenciaisPendentes(pronto) {
  const pendentes = [];
  for (const n of pronto.nodes ?? []) {
    for (const [tipo, cred] of Object.entries(n.credentials ?? {})) {
      if (cred.id === 'REPLACE') pendentes.push({ no: n.name, tipo, nome: cred.name, desabilitado: !!n.disabled });
    }
  }
  return pendentes;
}

// ---------------------------------------------------------------------------

/**
 * QUAL arquivo do repositório preparar — por variável de ambiente, nunca por
 * argumento posicional (é a mesma convenção de `N8N_CRED_IDS`/`N8N_URL` deste
 * script, e do `republicar.sh`, que é quem chama isto).
 *
 * POR QUE ISTO EXISTE. Até 16/09/2026 este script só sabia preparar
 * `workflow.e1-ingestao.json` — hardcoded. Os OUTROS TRÊS workflows deste
 * repositório (`macro`, `erros`, `diagnostico-ia`) não tinham como usar a
 * mesma fusão que já protege a ingestão (o `id` do nó preservado, o `path` do
 * formulário, as credenciais por (tipo, nome), o `errorWorkflow` da
 * instalação) — cada republicação deles teria de repetir esses cinco anos de
 * incidente à mão, ou arriscar o `PUT` direto que este arquivo existe para
 * proibir.
 *
 * O padrão vazio continua apontando para a ingestão, de propósito: é o único
 * workflow que tinha uso documentado sem a variável antes desta mudança, e
 * mudar o padrão silenciosamente trocaria o alvo de quem já automatizou isso.
 */
function arquivoDoRepo(env = process.env) {
  return env.N8N_ARQUIVO_REPO?.trim() || 'N8N/workflow.e1-ingestao.json';
}

if (ehExecucaoDireta(import.meta.url)) {
  const vivo = await lerWorkflowDaEntradaPadrao([
    'uso: N8N_ARQUIVO_REPO=N8N/workflow.macro.json \\',
    '     curl -s -H "X-N8N-API-KEY: $K" "$URL/api/v1/workflows/$ID" \\',
    '       | node N8N/preparar-republicacao.mjs > publicar.json',
    '     o JSON do workflow PUBLICADO entra pela entrada padrão; o pronto sai pela saída padrão.',
    '     N8N_ARQUIVO_REPO escolhe QUAL workflow do repositório preparar — o padrão é a ingestão.',
  ]);
  const repo = JSON.parse(readFileSync(resolve(RAIZ, arquivoDoRepo()), 'utf8'));

  const pronto = prepararRepublicacao(vivo, repo, { idsPorNome: idsDeCredencialDoAmbiente() });

  // O relatório vai para o ERRO, não para a saída: a saída é o JSON, e ela
  // costuma estar redirecionada para um arquivo.
  const pendentes = credenciaisPendentes(pronto);
  const sobreOErro = pronto.settings.errorWorkflow
    ? ` (errorWorkflow ${pronto.settings.errorWorkflow})`
    : ' — SEM errorWorkflow';
  console.error(`pronto: ${pronto.nodes.length} nós, ${Object.keys(pronto.connections).length} com conexão, `
    + `settings da instalação preservadas${sobreOErro}.`);
  if (pendentes.length) {
    console.error(`\n${pendentes.length} credencial(is) ainda em REPLACE — o passo que só o editor resolve:`);
    for (const p of pendentes) {
      console.error(`  • ${p.no} (${p.tipo}: "${p.nome}")${p.desabilitado ? ' — nó DESABILITADO, então não impede a rodada' : ' — nó HABILITADO, VAI FALHAR'}`);
    }
    // A MENSAGEM DIZ O QUE FAZER, e isso é o que faltava: nas três execuções
    // da action de 11/09 ela listava os nós pendentes e parava aí. Saber QUAIS
    // nós não diz a ninguém como destravar — e o efeito prático foi a
    // republicação ficar parada, que é o passo sem o qual a correção fica no
    // repositório e não na produção.
    const nomesUnicos = [...new Set(pendentes.filter((p) => !p.desabilitado).map((p) => p.nome))];
    if (nomesUnicos.length) {
      const exemplo = JSON.stringify(Object.fromEntries(nomesUnicos.map((n) => [n, '<id>'])));
      console.error('\nCOMO DESTRAVAR — dois caminhos, e o segundo é o que serve para automação:');
      console.error('  1. No editor do n8n, abra cada nó acima e escolha a credencial na lista.');
      console.error('     O id passa a vir do publicado e nunca mais precisa ser informado.');
      console.error('     Se a credencial JÁ está publicada em outro nó, o preparador a reaproveita');
      console.error('     sozinho — chegar aqui significa que ela não está em nó nenhum, ou que o');
      console.error('     mesmo nome aparece com ids DIFERENTES e não dá para escolher.');
      console.error('  2. Informe o id por ambiente, em N8N_CRED_IDS (um secret do GitHub):');
      console.error(`         N8N_CRED_IDS='${exemplo}'`);
      console.error('     O id aparece na URL ao abrir a credencial no n8n:');
      console.error('         .../home/credentials/<id>');
      console.error('     Vale para a API pública do n8n NÃO devolver a credencial `httpHeaderAuth`');
      console.error('     destes nós — foi o que travou a action em 11/09/2026 (as 11 credenciais');
      console.error('     `postgres` resolveram pelo publicado; as `httpHeaderAuth`, nenhuma).');
    }
  }
  console.error(`\nDepois de publicar, confira: … | node N8N/conferir-publicado.mjs`);

  process.stdout.write(`${JSON.stringify(pronto, null, 2)}\n`);
  if (CAMPOS_DO_PUT.some((c) => !(c in pronto))) process.exit(1);
}
