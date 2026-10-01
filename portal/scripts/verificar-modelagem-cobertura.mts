/**
 * Verificação de que o veredito "pronto" da Modelagem mostra a FRAÇÃO de
 * cobertura, não só o booleano (Supabase/migrations/0158, metade do portal)
 * (roda com `./node_modules/.bin/tsx scripts/verificar-modelagem-cobertura.mts`).
 *
 * O DEFEITO, medido no fixture Vertentes ANTES da 0158: `fn_conferir_modelagem`
 * respondia `pronto: true` com `linhas_com_premissa: 23` de
 * `linhas_do_caso: 480` — 23 de 480 linhas projetáveis de fato vinculadas a
 * alguma premissa. O portal pintava um chip VERDE "pronto para exportar"
 * (`casos/[id]/modelagem/page.tsx`, então linha 401-402) sobre esse booleano.
 * A 0158 endureceu o booleano (`pronto` passa a exigir `linhas_com_premissa >
 * 0`) e publicou `fracao_linhas_com_premissa` — mas um booleano mais duro
 * ainda pinta o MESMO verde para 62% e para 100% de cobertura: só o NÚMERO
 * ao lado do veredito resolve isso, e essa metade é do portal, não do banco.
 *
 * O invariante que este arquivo prova, em COMPORTAMENTO — contra
 * `lib/modelagem-cobertura.ts`, a mesma função que `modelagem/page.tsx`
 * chama para desenhar o chip e o título do bloco de conferência, nunca uma
 * reimplementação do texto aqui:
 *
 *  1. Veredito `pronto` com fração BAIXA mostra a fração no chip e no título
 *     — não some atrás do "pronto".
 *  2. Veredito `pronto` com fração ALTA (100%) produz um texto DIFERENTE do
 *     de fração baixa — os dois casos que o defeito original pintava
 *     idênticos deixam de parecer o mesmo caso.
 *  3. Fração AUSENTE (chave nem existe — banco sem a 0158 aplicada) faz a
 *     tela voltar ao texto de ANTES da 0158: só o veredito, nunca um "0%"
 *     fabricado pela ausência.
 *  4. Fração `null` (0158 aplicada, mas `linhas_do_caso` é zero — zero
 *     coberto de zero possível) cai no MESMO texto do item 3, pela mesma
 *     razão: não é medição de zero, é ausência de medição.
 *  5. Veredito `falta algo` (não pronto) nunca mostra fração — o caso que o
 *     defeito original não afetava (o chip já era vermelho) continua sem
 *     ganhar um número que ninguém pediu.
 */

import {
  fracaoPctDe,
  portaoFechado,
  portaoNaoConferido,
  veredictoDoPortao,
  textoChipModelagem,
  textoTituloConferenciaModelagem,
  type ConferenciaModelagemCobertura,
} from "../src/lib/modelagem-cobertura.ts";

let falhas = 0;
let passou = 0;

// O Sonar cobra `typescript:S2301` aqui ("não decida ação por parâmetro
// booleano"). Fica como está DE PROPÓSITO, pela mesma razão já escrita em
// `verificar-kit-basico.mts`: é a assinatura de `verificar-premissas-do-realizado.mts:37`,
// caractere por caractere, e é a convenção dos seis `verificar-*.mts`. Partir um
// helper de assert em dois métodos deixaria cada teste menos legível para
// satisfazer uma regra escrita para código de produção.
function ok(cond: boolean, nome: string, detalhe?: string) {
  if (cond) {
    passou += 1;
    console.log(`  ok    ${nome}`);
  } else {
    falhas += 1;
    const sufixo = detalhe ? " — " + detalhe : "";
    console.error(`  FALHOU: ${nome}${sufixo}`);
  }
}

console.log("--- 1. pronto com fração baixa: a fração aparece, não some atrás do 'pronto' ---");
{
  // 0,048 = 23 / 480, o número medido no Grupo Vertentes (cabeçalho da 0158).
  const conf: ConferenciaModelagemCobertura = { pronto: true, fracao_linhas_com_premissa: 0.048 };
  const chip = textoChipModelagem(conf);
  const titulo = textoTituloConferenciaModelagem(conf);
  ok(chip.includes("5%"), "o chip carrega o percentual (23 de 480 arredonda a 5%)", chip);
  ok(chip !== "pronto para exportar", "o chip NÃO é mais o texto plano — o defeito original", chip);
  ok(titulo.includes("5%"), "o título do bloco de conferência também carrega o percentual", titulo);
}

console.log("--- 2. pronto com fração alta (100%) produz texto DIFERENTE do de fração baixa ---");
{
  const baixa: ConferenciaModelagemCobertura = { pronto: true, fracao_linhas_com_premissa: 0.048 };
  const alta: ConferenciaModelagemCobertura = { pronto: true, fracao_linhas_com_premissa: 1 };
  ok(textoChipModelagem(baixa) !== textoChipModelagem(alta),
    "23 de 480 e 480 de 480 pintavam o MESMO chip antes desta correção — agora o texto diverge",
    `baixa=${textoChipModelagem(baixa)} alta=${textoChipModelagem(alta)}`);
  ok(textoTituloConferenciaModelagem(baixa) !== textoTituloConferenciaModelagem(alta),
    "o título do bloco também diverge entre 5% e 100%");
  ok(textoChipModelagem(alta).includes("100%"), "a fração alta aparece por extenso, não só 'pronto'");
}

console.log("--- 3. fração AUSENTE (banco sem a 0158): volta ao texto de antes, sem 0% fabricado ---");
{
  // A chave nem existe no objeto — é exatamente o que um banco sem a 0158
  // devolve (RPC mais antiga), e é diferente de `fracao_linhas_com_premissa:
  // 0` (que SERIA uma medição real de zero).
  const conf = { pronto: true } as ConferenciaModelagemCobertura;
  ok(fracaoPctDe(conf) === null, "fração ausente vira `null`, nunca `0`");
  ok(textoChipModelagem(conf) === "pronto para exportar",
    "sem a 0158, o chip é o texto de sempre — nenhum percentual inventado");
  ok(textoTituloConferenciaModelagem(conf) === "Pronto para o export de modelagem",
    "sem a 0158, o título do bloco também é o texto de sempre");
}

console.log("--- 4. fração `null` (0158 aplicada, linhas_do_caso = 0): mesmo texto do item 3 ---");
{
  const conf: ConferenciaModelagemCobertura = { pronto: true, fracao_linhas_com_premissa: null };
  ok(fracaoPctDe(conf) === null,
    "zero coberto de zero possível não é medição — cai em `null`, igual à chave ausente");
  ok(textoChipModelagem(conf) === "pronto para exportar",
    "`null` explícito do banco produz o MESMO texto que a chave ausente — a tela não distingue "
    + "'não sei medir' de 'meço uma ausência', porque as duas são a mesma ausência de dado");
}

console.log("--- 5. não pronto: nunca mostra fração, mesmo que o banco a tenha medido ---");
{
  const conf: ConferenciaModelagemCobertura = { pronto: false, fracao_linhas_com_premissa: 0.62 };
  ok(textoChipModelagem(conf) === "falta algo",
    "o chip de 'falta algo' não ganha percentual — o defeito original nunca o pintou de verde");
  ok(textoTituloConferenciaModelagem(conf) === "Ainda falta algo para o export de modelagem",
    "o título do bloco de 'falta algo' também fica como sempre foi");
}

console.log("--- 6. Portão 2 fechado: a tela NÃO diz 'pronto para o export' (o export recusa com 409) ---");
{
  // Medido em 30/09/2026 (caso bb37f726): premissas prontas, 3 pendências
  // bloqueantes sem decisão, a tela dizia "Pronto para o export de modelagem" e
  // o clique devolvia um JSON 409. O comportamento afirmado: com o portão
  // fechado nenhum dos dois textos promete o export, e o título nomeia o motivo.
  const conf: ConferenciaModelagemCobertura = { pronto: true, fracao_linhas_com_premissa: 0.1 };
  const fechado = { elegivel: false, motivos: ["3 pendência(s) BLOQUEANTE(s) sem decisão"] };
  const chip = textoChipModelagem(conf, fechado);
  const titulo = textoTituloConferenciaModelagem(conf, fechado);
  ok(!/^pronto/i.test(chip), "chip com portão fechado não começa por 'pronto'", chip);
  ok(!/Pronto para o export/.test(titulo), "título com portão fechado não diz 'Pronto para o export'", titulo);
  ok(titulo.includes("3 pendência(s) BLOQUEANTE(s) sem decisão"), "título nomeia o motivo do portão", titulo);
  const aberto = { elegivel: true, motivos: [] };
  ok(textoTituloConferenciaModelagem(conf, aberto) === textoTituloConferenciaModelagem(conf),
    "portão aberto: o texto é o mesmo de antes (nada muda para quem pode exportar)");
}

console.log("--- 7. Portão 2 NÃO CONFERIDO (RPC falhou → null): nem 'pronto', nem botão; três estados ---");
{
  // O defeito: `portaoFechado(null)` é false, então com o RPC falhando o chip voltava a
  // "pronto — X% das contas projetam" e o botão ficava ativo — ausência como estado.
  const conf: ConferenciaModelagemCobertura = { pronto: true, fracao_linhas_com_premissa: 0.62 };
  const chip = textoChipModelagem(conf, null);
  const titulo = textoTituloConferenciaModelagem(conf, null);
  ok(!/^pronto/i.test(chip) && /NÃO CONFERIDO/.test(chip),
    "chip com portão não conferido não começa por 'pronto' e diz que não foi conferido", chip);
  ok(!/%/.test(chip), "…e não mostra a fração 'X% das contas projetam' como se o export estivesse liberado", chip);
  ok(!/Pronto para o export/.test(titulo) && /NÃO foi possível conferir o Portão 2/.test(titulo),
    "título com portão não conferido diz que não foi possível conferir", titulo);
  ok(portaoNaoConferido(null) && !portaoNaoConferido(undefined)
    && !portaoNaoConferido({ elegivel: true }) && !portaoNaoConferido({ elegivel: false }),
    "só `null` é NÃO CONFERIDO: `undefined` (não perguntado), aberto e fechado são outros estados");
  ok(!portaoFechado(null),
    "não conferido NÃO é 'fechado' (seria outra afirmação sem prova): são estados distintos");
  ok(textoChipModelagem(conf, null) !== textoChipModelagem(conf, { elegivel: false, motivos: [] })
    && textoChipModelagem(conf, null) !== textoChipModelagem(conf, { elegivel: true }),
    "os três estados produzem três textos diferentes no chip");
}

console.log("--- 8. UMA regra para tela e rota (`veredictoDoPortao`): resposta do RPC → aberto/fechado/não conferido ---");
{
  // A rota recusava (503) quando `elegivel` não era booleano; a tela só tratava `null`. Com o
  // RPC respondendo `{}` a tela dizia "pronto" e o clique devolvia JSON cru. Os dois
  // consumidores chamam ESTA função, então cobrir ela cobre os dois.
  const est = (r: { data?: unknown; error?: unknown } | null | undefined) => veredictoDoPortao(r).estado;
  ok(est({ data: {} }) === "nao_conferido", "resposta `{}` (sem `elegivel`) é NÃO CONFERIDO");
  ok(est({ data: { motivos: [] } }) === "nao_conferido", "resposta só com motivos é NÃO CONFERIDO");
  ok(est({ data: { elegivel: "x" } }) === "nao_conferido", "`elegivel` que não é booleano é NÃO CONFERIDO");
  ok(est({ data: { elegivel: 1 } }) === "nao_conferido", "`elegivel` numérico não é aberto");
  ok(est({ data: null }) === "nao_conferido" && est({}) === "nao_conferido" && est(null) === "nao_conferido",
    "resposta ausente é NÃO CONFERIDO");
  ok(est({ data: { elegivel: true }, error: { message: "boom" } }) === "nao_conferido",
    "erro na consulta é NÃO CONFERIDO mesmo que haja dado junto");
  ok(est({ data: { elegivel: false, motivos: ["pendência"] } }) === "fechado", "`elegivel` false é FECHADO");
  ok(est({ data: { elegivel: true } }) === "aberto", "`elegivel` true é ABERTO");
  const f = veredictoDoPortao({ data: { elegivel: false, motivos: ["a", 3, "b"] } });
  ok(f.portao !== null && f.portao.motivos?.join("|") === "a|b",
    "fechado entrega só motivos textuais", JSON.stringify(f.portao));
  ok(veredictoDoPortao({ data: {} }).portao === null,
    "não conferido entrega `portao: null`, que a tela lê com `portaoNaoConferido`");
  ok(textoChipModelagem({ pronto: true, fracao_linhas_com_premissa: 0.9 }, veredictoDoPortao({ data: {} }).portao).includes("NÃO CONFERIDO"),
    "a tela, alimentada pela MESMA função, não diz 'pronto' diante de `{}`");
}

console.log(`\n${passou} asserts passaram, ${falhas} falharam`);
if (falhas > 0) process.exit(1);
console.log("MODELAGEM COBERTURA OK — o veredito 'pronto' não pinta 5% e 100% do mesmo verde");
