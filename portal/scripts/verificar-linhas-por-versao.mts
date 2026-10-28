// A SUÍTE DA CONTAGEM POR DOCUMENTO — o teto de 1000 linhas que o PostgREST
// aplica em silêncio.
//
// POR QUE ELA EXISTE. Em 24/09/2026 a auditoria achou a conta "quantas linhas
// cada documento rendeu" em duas cópias: o detalhe do caso passava por
// `paginar`, o painel (`casos/page.tsx`, as dez linhas de "O que chegou") fazia
// uma consulta só. O PostgREST devolve no máximo `db-max-rows` linhas — 1000 por
// padrão — e corta o resto SEM erro: a contagem saía truncada com cara de
// contagem. É o defeito que `paginar.ts` registra ter aparecido em produção
// ("1.000 linhas extraídas" com muito mais no banco), corrigido para o total e
// esquecido nesta conta.
//
// O QUE ESTA SUÍTE TRAVA:
//   1. contra um servidor que corta em 1000 como o PostgREST, a contagem de um
//      documento com 2.500 linhas dá 2.500 — e a soma das versões bate;
//   2. um teto de servidor MENOR que a janela (500) não encerra a leitura cedo —
//      a regra de parada de `paginar` é a página vazia, não a página curta;
//   3. nenhuma leitura de LINHAS de `campo_extraido` em `portal/src` fica fora
//      do `paginar` (ou de um `count` com `head: true`, que não traz linha) — é
//      a forma de a segunda cópia voltar.
//
// Não há banco aqui: o servidor é simulado, e o que se simula é SÓ o teto (a
// regra 4 — o arranjo real é "mais linhas do que o teto", e é esse o arranjo).
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import {
  destinoDoOriginal, ehPdf, escolherVersaoDoOriginal, hrefDoOriginal, orientacaoDoMotivo,
  paginaDeOriginalIndisponivel, paginaValida, rotuloDoLink,
} from "../src/lib/original-do-documento";
import { contarLinhasPorVersao } from "../src/lib/supabase/linhas-por-versao";

let ok = 0;
const falhas: string[] = [];
function checar(cond: boolean, msg: string) {
  if (cond) ok++;
  else falhas.push(msg);
}

type Linha = { id: number; documento_versao_id: string };

/** Um PostgREST de mentira que só sabe uma coisa: cortar em `teto` linhas. */
function servidor(linhas: Linha[], teto: number, falhaNaConsulta = 0) {
  let consultas = 0;
  const cliente = {
    from: () => ({
      select: () => ({
        in: (_c: string, versoes: string[]) => {
          const filtradas = linhas.filter((l) => versoes.includes(l.documento_versao_id));
          // Só `.order().range()`: é a única forma de pedir linhas que este servidor
          // aceita, como o contrato de `paginar` exige.
          const range = (de: number, ate: number) => {
            consultas++;
            if (consultas === falhaNaConsulta) return Promise.resolve({ data: null, error: { message: "canceling statement due to statement timeout" } });
            const fim = Math.min(ate + 1, de + teto);
            return Promise.resolve({ data: filtradas.slice(de, fim), error: null });
          };
          return { order: () => ({ range }) };
        },
      }),
    }),
  };
  return { cliente, consultas: () => consultas };
}

function lote(porVersao: Record<string, number>): Linha[] {
  const out: Linha[] = [];
  let id = 1;
  for (const [v, n] of Object.entries(porVersao)) for (let i = 0; i < n; i++) out.push({ id: id++, documento_versao_id: v });
  return out;
}

// --- 1. acima do teto padrão -------------------------------------------------
{
  const esperado = { "v-razao": 2500, "v-bp": 180, "v-dre": 1 };
  const { cliente, consultas } = servidor(lote(esperado), 1000);
  const { porVersao, incompleto } = await contarLinhasPorVersao(cliente as never, Object.keys(esperado));
  for (const [v, n] of Object.entries(esperado)) {
    checar(porVersao.get(v) === n, `${v}: contou ${porVersao.get(v)} linhas, o documento tem ${n} — o teto de 1000 cortou em silêncio`);
  }
  const soma = [...porVersao.values()].reduce((a, b) => a + b, 0);
  checar(soma === 2681, `a soma das versões deu ${soma}, esperado 2681`);
  checar(incompleto === false, "a leitura se declarou incompleta sem ter falhado nem batido no teto de segurança");
  checar(consultas() > 1, `uma consulta só (${consultas()}) não passa de 1000 linhas — a leitura não está paginando`);
}

// --- 2. servidor com teto MENOR que a janela ----------------------------------
{
  const esperado = { "v-razao": 1700 };
  const { cliente } = servidor(lote(esperado), 500);
  const { porVersao } = await contarLinhasPorVersao(cliente as never, ["v-razao"]);
  checar(porVersao.get("v-razao") === 1700,
    `com o servidor cortando em 500, contou ${porVersao.get("v-razao")} de 1700 — a leitura parou na primeira página curta`);
}

// --- 2b. uma página que FALHA no meio não vira contagem ------------------------
// Achado da revisão do PR #244: `paginar` devolve o que leu até o erro, e a versão
// anterior desta função jogava o erro fora — o detalhe do caso mostrava a soma
// parcial e contava como "sem nenhuma linha" documentos que tinham linhas. A
// contagem parcial tem de se declarar (regra 1), e é o que `incompleto` faz.
{
  const esperado = { "v-razao": 2500 };
  const { cliente } = servidor(lote(esperado), 1000, 2);
  const { porVersao, incompleto } = await contarLinhasPorVersao(cliente as never, ["v-razao"]);
  checar(incompleto === true,
    `a segunda página falhou e a contagem (${porVersao.get("v-razao")} de 2500) NÃO se declarou incompleta`);
}

// --- e o caso vazio não consulta nada nem inventa zero -------------------------
{
  const { cliente, consultas } = servidor([], 1000);
  const { porVersao } = await contarLinhasPorVersao(cliente as never, []);
  checar(porVersao.size === 0 && consultas() === 0, "sem versões, a função consultou o banco ou devolveu contagem");
}

// --- 3. nenhuma outra leitura de LINHAS de campo_extraido fora do paginar ------
// Cada `.from("campo_extraido")` em portal/src precisa estar dentro de um
// `paginar(` ou ser um `count` com `head: true` NO PRÓPRIO `.select(` dessa
// consulta. A primeira versão (24/09/2026) aceitava `head: true` em qualquer lugar
// das 12 linhas seguintes — e no painel a consulta de `documento`, oito linhas
// abaixo, tem um: tirar o `head: true` da contagem total de linhas (a volta exata
// do "1.000 linhas extraídas") passava verde, medido pela revisão do PR #244.
// Agora o que se lê são os argumentos balanceados do `.select(` que segue o
// `.from(` — o `head` de outra consulta não conta.
{
  const SRC = new URL("../src/", import.meta.url).pathname;
  const arquivos: string[] = [];
  const andar = (d: string) => {
    for (const f of readdirSync(d)) {
      const p = join(d, f);
      if (statSync(p).isDirectory()) andar(p);
      else if (/\.(ts|tsx)$/.test(f)) arquivos.push(p);
    }
  };
  andar(SRC);
  /**
   * O CÓDIGO sem comentários nem conteúdo de texto — as mesmas posições, com esses
   * trechos trocados por espaço (quebra de linha preservada).
   *
   * POR QUE (quarta revisão do PR #244): o casamento de parênteses contava `(` e `)`
   * dentro de comentário e de string. Um comentário citando `paginar(` sem fechar
   * "abria" um paginar falso que o `)` do `Promise.all` fechava — medido: trocar um
   * comentário de `perguntas/page.tsx` para "PAGINADA via `paginar(`" fazia uma
   * leitura solta passar 15/0. E há `)` desbalanceado em comentários reais
   * ("1) nota"). Sobre este texto, parêntese é só parêntese de código.
   */
  /** Onde termina o comentário ou o texto que começa em `k`; -1 se ali começa código. */
  const fimDoTrecho = (src: string, k: number): number => {
    const c = src[k], d = src[k + 1];
    if (c === "/" && d === "/") { const f = src.indexOf("\n", k); return f < 0 ? src.length : f; }
    if (c === "/" && d === "*") { const f = src.indexOf("*/", k + 2); return f < 0 ? src.length : f + 2; }
    if (c !== '"' && c !== "'" && c !== "`") return -1;
    let f = k + 1;
    while (f < src.length && src[f] !== c) f += src[f] === "\\" ? 2 : 1;
    return Math.min(f + 1, src.length);
  };
  const soCodigo = (src: string): string => {
    let out = "";
    let k = 0;
    while (k < src.length) {
      const fim = fimDoTrecho(src, k);
      if (fim < 0) { out += src[k]; k++; continue; }
      // O delimitador de texto fica (a posição de `from("…")` continua reconhecível); o
      // conteúdo — e o comentário inteiro — vira espaço, com a quebra de linha preservada.
      const apagado = (de: number, ate: number) => src.slice(de, ate).replace(/[^\n]/g, " ");
      if (src[k] === "/") {
        out += apagado(k, fim);
      } else {
        const fechou = fim - 1 > k; // texto sem aspa de fechamento vai até o fim do arquivo
        out += src[k] + apagado(k + 1, fechou ? fim - 1 : fim) + (fechou ? src[fim - 1] : "");
      }
      k = fim;
    }
    return out;
  };
  /** Posição do `)` que fecha o `(` em `abre`, no código já limpo; -1 se não fecha. */
  const fecha = (c: string, abre: number): number => {
    let nivel = 0;
    for (let k = abre; k < c.length; k++) {
      if (c[k] === "(") nivel++;
      else if (c[k] === ")" && --nivel === 0) return k;
    }
    return -1;
  };
  /**
   * Os métodos encadeados na leitura que começa em `from(` na posição `i`:
   * `from(…).select(…).in(…).range(…)` → ["select", "in", "range"]. Segue os
   * parênteses casados de cada chamada até a cadeia acabar, então o `.range` de
   * OUTRA consulta não conta como desta.
   */
  const cadeia = (c: string, i: number): Array<{ nome: string; args: string }> => {
    const metodos: Array<{ nome: string; args: string }> = [];
    let k = fecha(c, c.indexOf("(", i)) + 1;
    while (k > 0) {
      let j = k;
      while (/\s/.test(c[j] ?? "")) j++;
      if (c[j] !== ".") break;
      j++;
      const ini = j;
      while (/[\w$]/.test(c[j] ?? "")) j++;
      const nome = c.slice(ini, j);
      while (/\s/.test(c[j] ?? "")) j++;
      if (!nome || c[j] !== "(") break;
      const fim = fecha(c, j);
      if (fim < 0) break;
      metodos.push({ nome, args: c.slice(j + 1, fim) });
      k = fim + 1;
    }
    return metodos;
  };
  /**
   * A leitura em `i` está dentro dos parênteses de um `paginar(...)`?
   *
   * Sozinho não basta (quarta revisão): uma leitura secundária no callback,
   * `paginar(async (de, ate) => { await supabase.from(…).in(…); … })`, sai limitada
   * a 1000 linhas — por isso quem decide é esta condição E a cadeia da leitura
   * chegar a `.range`. Sem regex com retrocesso: o Sonar acusou a anterior (S8786).
   */
  /** Pula espaços a partir de `k`. */
  const pularEspaco = (c: string, k: number): number => {
    while (/\s/.test(c[k] ?? "")) k++;
    return k;
  };
  /** Pula o genérico `<…>` que começa em `k`, sem contar o `>` de `=>`. */
  const pularGenerico = (c: string, k: number): number => {
    if (c[k] !== "<") return k;
    let nivel = 0;
    for (; k < c.length; k++) {
      if (c[k] === "<") nivel++;
      else if (c[k] === ">" && c[k - 1] !== "=" && --nivel === 0) return k + 1;
    }
    return k;
  };
  /** Posição do `(` da chamada `paginar` que começa em `p`; -1 se ali não é uma chamada dele. */
  const aberturaDoPaginar = (c: string, p: number): number => {
    if (/[\w$]/.test(c[p - 1] ?? "") || /[\w$]/.test(c[p + 7] ?? "")) return -1; // outro identificador
    const k = pularEspaco(c, pularGenerico(c, pularEspaco(c, p + 7)));
    return c[k] === "(" ? k : -1;
  };
  const dentroDeUmPaginar = (c: string, i: number): boolean => {
    for (let p = c.indexOf("paginar"); p >= 0 && p < i; p = c.indexOf("paginar", p + 1)) {
      const abre = aberturaDoPaginar(c, p);
      if (abre >= 0 && fecha(c, abre) > i) return true;
    }
    return false;
  };
  let leituras = 0;
  for (const arq of arquivos) {
    const texto = readFileSync(arq, "utf8");
    const codigo = soCodigo(texto);
    const alvo = 'from("campo_extraido")';
    for (let i = texto.indexOf(alvo); i >= 0; i = texto.indexOf(alvo, i + 1)) {
      if (codigo[i] !== "f") continue; // citada num comentário ou texto, não é leitura
      leituras++;
      const linha = texto.slice(0, i).split("\n").length;
      const metodos = cadeia(codigo, i);
      const paginada = dentroDeUmPaginar(codigo, i) && metodos.some((m) => m.nome === "range");
      const soContagem = metodos.some((m) => m.nome === "select" && /head:\s*true/.test(m.args));
      checar(paginada || soContagem,
        `${arq.replace(SRC, "portal/src/")}:${linha} lê linhas de campo_extraido sem paginar — o teto de 1000 corta em silêncio`);
    }
  }
  // controle positivo: o varredor ACHOU as leituras que se sabe existirem
  // Eram 4; o Início deixou de ler o COUNT total de linhas (indicador "linhas financeiras
  // lidas" removido, REDESENHO item 8), então o piso conhecido passou a 3 (medido: 3).
  checar(leituras >= 3, `o varredor achou só ${leituras} leitura(s) de campo_extraido — ele não está olhando onde devia`);
}

// ---- "Ver no original": âncora de página só para PDF; ?pagina só inteiro positivo ----------
// (Carona nesta suíte por ser leitura de portal sem banco; a rota em si, que fala com o Storage,
// não é exercitada aqui — só a decisão pura que ela toma.)
{
  const URL_ASSINADA = "https://x.supabase.co/storage/v1/object/sign/documentos/a.pdf?token=t";
  checar(destinoDoOriginal(URL_ASSINADA, true, 7) === `${URL_ASSINADA}#page=7`, "(orig 1) PDF + página → #page=N");
  checar(destinoDoOriginal(URL_ASSINADA, false, 7) === URL_ASSINADA, "(orig 2) não-PDF nunca leva âncora de página");
  checar(destinoDoOriginal(URL_ASSINADA, true, null) === URL_ASSINADA, "(orig 3) PDF sem página → URL pura");
  checar(paginaValida("12") === 12, "(orig 4) '12' é página 12");
  for (const ruim of ["0", "-3", "1.5", "3abc", "", "1e3", " 4", "9999999", null, undefined]) {
    checar(paginaValida(ruim as string | null) === null, `(orig 5) ${JSON.stringify(ruim)} NÃO é página`);
  }
  checar(ehPdf("Balanço 2024.PDF", null) && !ehPdf("dre.xlsx", "x/dre.pdf") && ehPdf(null, "k/a.pdf"),
    "(orig 6) PDF decidido pelo nome original, com a chave como reserva");
  checar(rotuloDoLink(true, 3) === "abre na página 3" && rotuloDoLink(false, 3) === "abre o arquivo",
    "(orig 7) o rótulo só promete página quando ela será aplicada");
  checar(hrefDoOriginal("c1", "d 1", 4) === "/casos/c1/documentos/d%201/original?pagina=4"
    && hrefDoOriginal("c1", "d1") === "/casos/c1/documentos/d1/original",
    "(orig 8) href aponta para a rota, com a página só quando existe");
  // ALTO 1: a versão citada pela tela viaja no link e manda sobre a função.
  checar(hrefDoOriginal("c1", "d1", 4, "v 2") === "/casos/c1/documentos/d1/original?pagina=4&versao=v%202"
    && hrefDoOriginal("c1", "d1", null, "v2") === "/casos/c1/documentos/d1/original?versao=v2",
    "(orig 9) href leva a versão citada (com ou sem página)");
  const V = (id: string, n: number) => ({ id, n_versao: n, nome_original: `${id}.pdf`, arquivo_ref: `k/${id}`, origem_arquivo: null });
  const vs = [V("v1", 1), V("v2", 2), V("v3", 3)];
  const idDe = (r: ReturnType<typeof escolherVersaoDoOriginal>) => ("versao" in r ? r.versao.id : `ERRO:${r.tipo}`);
  checar(idDe(escolherVersaoDoOriginal(vs, "v1", "v3")) === "v1",
    "(orig 10) versão pedida vence a vigente (o fato citou a v1, a função diz v3)");
  checar(idDe(escolherVersaoDoOriginal(vs, "outro-doc", "v3")) === "ERRO:fora_do_caso",
    "(orig 11) versão pedida que não é deste documento NÃO cai em outra");
  checar(idDe(escolherVersaoDoOriginal(vs, null, "v2")) === "v2"
    && idDe(escolherVersaoDoOriginal(vs, null, null)) === "v3"
    && idDe(escolherVersaoDoOriginal([], null, null)) === "ERRO:sem_arquivo",
    "(orig 12) sem pedido: vigente; função null → mais recente (a que o detalhe exibe); sem versão → erro");
  // MÉDIO 4: reenviar só quando o arquivo não está guardado.
  checar(/reenvie/.test(orientacaoDoMotivo("sem_arquivo").nota) && /reenvie/.test(orientacaoDoMotivo("nao_assinavel").nota),
    "(orig 13) sem arquivo / não assinável → sugere reenvio");
  for (const t of ["falha_tecnica", "fora_do_caso", "origem_externa"] as const) {
    const o = orientacaoDoMotivo(t);
    checar(!/reenvie|não encontrou o arquivo/i.test(o.corpo + o.nota), `(orig 14) ${t} NÃO sugere reenvio`);
  }
  checar(/Tente de novo/.test(orientacaoDoMotivo("falha_tecnica").nota)
    && /Tente de novo/.test(paginaDeOriginalIndisponivel("/x", "boom", "falha_tecnica"))
    && !/reenvie/.test(paginaDeOriginalIndisponivel("/x", "boom", "falha_tecnica")),
    "(orig 15) falha técnica pede nova tentativa na página renderizada");
}

if (falhas.length > 0) {
  console.error(`\n${falhas.length} falha(s):`);
  for (const f of falhas) console.error(`  ✗ ${f}`);
  console.error(`\n${ok} verificações OK / ${falhas.length} falhas`);
  process.exit(1);
}
console.log(`${ok} verificações OK / 0 falhas`);
console.log("CONTAGEM POR DOCUMENTO OK — passa do teto de 1000 do PostgREST, e nenhuma leitura de linhas fica fora do paginar");
