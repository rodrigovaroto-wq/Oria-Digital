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
import {
  escolhasVisiveis,
  excecoesQueOLoteSubstitui,
  formDataDoLote,
  lotesPendentes,
  podarEdicoes,
  registrarEdicao,
  resumirSalvamento,
  totalPendente,
  type EscolhasPorSecao,
  type SecaoEditavel,
} from "../src/lib/modelagem-lote.ts";

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
  ok(!/^pronto/i.test(chip) && /NÃO CONFERIDA/.test(chip),
    "chip com portão não conferido não começa por 'pronto' e diz que não foi conferido", chip);
  ok(!/%/.test(chip), "…e não mostra a fração 'X% das contas projetam' como se o export estivesse liberado", chip);
  ok(!/Pronto para o export/.test(titulo) && /NÃO foi possível conferir a aprovação/.test(titulo),
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
  ok(textoChipModelagem({ pronto: true, fracao_linhas_com_premissa: 0.9 }, veredictoDoPortao({ data: {} }).portao).includes("NÃO CONFERIDA"),
    "a tela, alimentada pela MESMA função, não diz 'pronto' diante de `{}`");
}

console.log("--- 9. SALVAR TUDO (`modelagem-lote.ts`): só as linhas que mudaram, e falha parcial honesta ---");
{
  // O defeito que isto previne: a seção 3 tinha um "salvar esta seção" por seção (8 a 12 no caso
  // real). Com UMA barra, o risco passa a ser o lote levar linha intocada (reenviar "não
  // projetar" grava uma decisão que ninguém tomou) ou o resumo dizer "salvo" com seção falha.
  // Não há fixture de produção aqui: as seções abaixo são mínimas e escritas para a regra.
  const linha = (rotulo: string, papel = "conta") =>
    ({ rotulo_norm: rotulo, chave: rotulo.toUpperCase(), entidade: null, papel });
  const secoes: SecaoEditavel[] = [
    { secao: "receita", rotulo: "Receita", linhas: [linha("a"), linha("b"), linha("sub", "subtotal")] },
    { secao: "custos", rotulo: "Custos", linhas: [linha("c"), linha("d")] },
    { secao: "(sem seção canônica)", rotulo: "Sem seção", linhas: [linha("e")] },
  ];
  const v = (premissa: string, sazonalidade = "") => ({ premissa, sazonalidade });
  const gravado: EscolhasPorSecao = {
    receita: { a: v("P1"), b: v(""), sub: v("") },
    custos: { c: v(""), d: v("P2", "S1") },
    "(sem seção canônica)": { e: v("") },
  };
  const copia = (): EscolhasPorSecao => structuredClone(gravado);

  const parado = lotesPendentes(secoes, copia(), gravado);
  ok(parado.length === 0 && totalPendente(parado) === 0, "nada mudou: nenhum lote e nenhuma chamada");

  const esc = copia();
  esc.receita.a = v("P9");               // mudou
  esc.custos.d = v("P2", "S2");          // só a sazonalidade mudou
  esc.receita.sub = v("P1");             // subtotal não tem seletor: nunca entra
  const lotes = lotesPendentes(secoes, esc, gravado);
  ok(lotes.map((l) => l.secao).join() === "receita,custos", "seção sem mudança não gera lote", lotes.map((l) => l.secao).join());
  ok(lotes.flatMap((l) => l.linhas.map((x) => x.rotulo_norm)).join() === "a,d",
    "o lote leva EXATAMENTE as linhas que mudaram (b e c, intocadas, ficam fora)");
  ok(totalPendente(lotes) === 2, "o contador da barra conta as linhas mudadas", String(totalPendente(lotes)));

  const volta = copia();
  volta.receita.a = v("P9");
  volta.receita.a = v("P1");             // voltou ao original
  ok(lotesPendentes(secoes, volta, gravado).length === 0,
    "linha trocada e devolvida ao valor original NÃO é enviada");

  const fd = formDataDoLote(lotes[0]);
  ok(fd.get("rotulo__0") === "A" && fd.get("premissa__0") === "P9" && fd.get("orig__0") === "P1"
    && !fd.has("rotulo__1"), "o FormData reindexa de 0 e leva só a linha mudada, com o original ao lado");
  ok(formDataDoLote(lotesPendentes(secoes, { ...copia(), "(sem seção canônica)": { e: v("P3") } }, gravado)[0])
    .get("secao_canonica") === "", "'(sem seção canônica)' vai ao banco como vazio (NULL)");

  const r1 = { tom: "ok" as const, texto: "ok" };
  const r2 = { tom: "erro" as const, texto: "recusado: premissa inativa" };
  const parcial = resumirSalvamento([{ lote: lotes[0], r: r1 }, { lote: lotes[1], r: r2 }]);
  ok(parcial.tom === "erro", "uma seção falhou: o resumo é de ERRO, nunca 'salvo'", parcial.texto);
  ok(parcial.secoesOk.join() === "receita", "só a seção confirmada entra em secoesOk", parcial.secoesOk.join());
  ok(parcial.texto.includes("Receita") && parcial.texto.includes("Custos")
    && parcial.texto.includes("premissa inativa") && /NÃO salvas \(1 de 2/.test(parcial.texto),
    "o texto diz quais salvaram, quais NÃO, e o motivo", parcial.texto);
  const tudo = resumirSalvamento([{ lote: lotes[0], r: r1 }, { lote: lotes[1], r: r1 }]);
  ok(tudo.tom === "ok" && tudo.secoesOk.length === 2, "todas confirmaram: aí sim é 'ok'", tudo.texto);
  const nenhuma = resumirSalvamento([{ lote: lotes[0], r: r2 }]);
  ok(nenhuma.tom === "erro" && /Nenhuma seção foi salva/.test(nenhuma.texto) && nenhuma.secoesOk.length === 0,
    "nenhuma salvou: diz isso", nenhuma.texto);

  // O "GRAVADO" VEM DO SERVIDOR. O defeito: `salvarSecao` grava umas linhas e recusa outras; o
  // `gravado` local só era promovido para seção inteira `ok`, então a linha que o banco GRAVOU
  // seguia "suja" (e "Descartar" a devolvia ao valor velho). Não há fixture de produção: o
  // arranjo abaixo é o contrato, escrito para a regra — a seção `receita` tinha a (gravada) e
  // b (recusada); o servidor, após o `revalidatePath`, devolve a=P9 e b=""; a edição é a=P9, b=P7.
  const servidorDepois: EscolhasPorSecao = structuredClone(gravado);
  servidorDepois.receita.a = v("P9");     // o banco gravou
  const edicoes: EscolhasPorSecao = { receita: { a: v("P9"), b: v("P7") } };  // b foi recusada
  const aposRefresh = podarEdicoes(edicoes, servidorDepois);
  const visivel = escolhasVisiveis(servidorDepois, aposRefresh);
  const restante = lotesPendentes(secoes, visivel, servidorDepois);
  ok(restante.length === 1 && restante[0].linhas.map((x) => x.rotulo_norm).join() === "b" && totalPendente(restante) === 1,
    "salvamento parcial: só a linha RECUSADA continua pendente; a gravada na mesma seção fica limpa",
    restante.flatMap((l) => l.linhas.map((x) => x.rotulo_norm)).join());
  ok(restante[0].linhas[0].orig.premissa === "" && restante[0].linhas[0].novo.premissa === "P7",
    "o reenvio leva a linha recusada contra o valor do SERVIDOR (nenhum reenvio da gravada)");
  // Descartar: a tela volta ao que o servidor TEM (P9 gravado), não ao que havia antes (P1).
  const descartado = escolhasVisiveis(servidorDepois, {});
  ok(descartado.receita.a.premissa === "P9" && descartado.receita.b.premissa === "" &&
    lotesPendentes(secoes, descartado, servidorDepois).length === 0,
    "Descartar devolve ao valor do SERVIDOR (P9), não ao valor de antes do salvamento (P1)",
    descartado.receita.a.premissa);
  // Servidor mudou por fora (premissa removida no passo 2): a linha que o analista NÃO editou
  // mostra o que o servidor tem agora. Antes, o estado local (fotografia do mount) vencia o
  // servidor e o vínculo removido seguia na tela como "salvo".
  const servidorSemP2: EscolhasPorSecao = structuredClone(gravado);
  servidorSemP2.custos.d = v("", "S1");
  const visSemP2 = escolhasVisiveis(servidorSemP2, podarEdicoes({}, servidorSemP2));
  ok(visSemP2.custos.d.premissa === "" && lotesPendentes(secoes, visSemP2, servidorSemP2).length === 0,
    "premissa removida no servidor: a tela mostra o que o servidor tem (sem vínculo fantasma 'salvo')",
    visSemP2.custos.d.premissa);
  // registrarEdicao: editar e devolver ao valor do servidor deixa de ser edição.
  const e1 = registrarEdicao({}, gravado, escolhasVisiveis(gravado, {}), "receita", "a", "premissa", "P9");
  ok(e1.receita.a.premissa === "P9" && Object.keys(registrarEdicao(e1, gravado, escolhasVisiveis(gravado, e1), "receita", "a", "premissa", "P1").receita).length === 0,
    "editar e devolver ao valor do servidor remove a edição");
  // "aplicar em lote" avisa quantas escolhas por linha NÃO salvas ele substituiria.
  const contasRec = [{ rotulo_norm: "a" }, { rotulo_norm: "b" }];
  ok(excecoesQueOLoteSubstitui(contasRec, { a: v("P9"), b: v("") }, gravado.receita, "P5") === 1
    && excecoesQueOLoteSubstitui(contasRec, { a: v("P5"), b: v("") }, gravado.receita, "P5") === 0
    && excecoesQueOLoteSubstitui(contasRec, gravado.receita, gravado.receita, "P5") === 0,
    "lote: conta o que seria substituído (escolha pendente ≠ lote); pendente igual ao lote e linha limpa não contam");
  ok(gravado.receita.a.premissa === "P1", "as funções não mutam o servidor anterior");
}

console.log(`\n${passou} asserts passaram, ${falhas} falharam`);
if (falhas > 0) process.exit(1);
console.log("MODELAGEM COBERTURA OK — o veredito 'pronto' não pinta 5% e 100% do mesmo verde");
