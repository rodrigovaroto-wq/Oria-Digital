// A SUÍTE DA TELA DO PERÍMETRO — a tradução do vocabulário de `falta` e o que a tela nunca esconde.
//
// POR QUE ELA EXISTE. `fn_perimetro_situacao` (0208) nomeia o que falta em cada entidade; a tela só traduz.
// Se uma chave do vocabulário ficasse sem frase, ou uma chave NOVA fosse engolida em silêncio, a entidade
// pareceria sem falta quando o banco diz que falta algo (regra 7). Cada item é uma forma de errar:
//   1. toda chave do vocabulário da 0208 tem frase própria (não a crua, não a de "sem tradução");
//   2. chave desconhecida aparece CRUA, tanto de `falta` quanto de `pendencia_aberta:<tipo>`;
//   3. a frase de uma chave não é a de outra (tradução colada em tudo passaria o item 1);
//   4. aceite desconhecido nunca vira "ok" nem some; os dois conhecidos têm rótulo distinto;
//   5. percentual vazio é AUSÊNCIA (null), não zero; lixo é NaN e a action o recusa;
//   6. título do veredito: "fechado" só quando o banco diz fechado;
//   7. as actions não usam service role e conferem que a entidade é do caso.
import {
  CHAVES_DE_FALTA, TIPOS_DE_PENDENCIA, traduzirFalta, rotuloDoAceite, lerPercentual, formatarCnpj, tituloDoVeredito,
  PARENTESCOS, rotuloDoParentesco, MOTIVOS_DE_GRUPO, rotuloDoMotivoDoGrupo,
} from "../src/lib/perimetro.ts";
import { readFileSync } from "node:fs";

let ok = 0;
const falhas: string[] = [];
function checar(condicao: boolean, o_que: string) {
  if (condicao) { ok += 1; return; }
  falhas.push(o_que);
}

// O vocabulário REAL da 0208, lido da migration (não copiado aqui): se a migration ganhar um motivo
// que a tela não traduz, este item reprova em vez de a tela mostrar a chave crua para sempre.
const MIGRATION = readFileSync(new URL("../../Supabase/migrations/0208_a_situacao_do_perimetro_que_so_o_teste_lia.sql", import.meta.url), "utf8");
// Só o trecho que monta `falta` (o aceite e o motivo do veredito têm outros literais parecidos).
const TRECHO_FALTA = MIGRATION.slice(MIGRATION.indexOf("faltas as ("), MIGRATION.indexOf("from marcada m"));
const DA_MIGRATION = new Set([...TRECHO_FALTA.matchAll(/then '([a-z_]+)'(?: end)?[,\s]/g)].map((m) => m[1])
  .filter((k) => k.includes("_") && !k.startsWith("contrato_social") && k !== "entidade_incorreta"));
checar(DA_MIGRATION.size >= 6, `a leitura do vocabulário da 0208 achou só ${DA_MIGRATION.size} chaves — o regex não casa mais com a migration`);
for (const k of DA_MIGRATION) {
  checar(CHAVES_DE_FALTA.includes(k), `a 0208 emite "${k}" e a tela não tem tradução`);
}

const frases = new Set<string>();
for (const k of CHAVES_DE_FALTA) {
  const f = traduzirFalta(k);
  checar(!f.includes(k), `"${k}" ficou crua na tradução: ${f}`);
  checar(!f.startsWith("Motivo sem tradução"), `"${k}" caiu no caminho de chave desconhecida`);
  frases.add(f);
}
checar(frases.size === CHAVES_DE_FALTA.length, "duas chaves de falta diferentes têm a MESMA frase");

for (const t of TIPOS_DE_PENDENCIA) {
  const f = traduzirFalta(`pendencia_aberta:${t}`);
  checar(!f.includes("sem tradução"), `pendencia_aberta:${t} caiu no caminho sem tradução`);
  frases.add(f);
}
checar(frases.size === CHAVES_DE_FALTA.length + TIPOS_DE_PENDENCIA.length, "uma pendência aberta tem a mesma frase de outra chave");
checar(DA_MIGRATION.has("entidade_fantasma_pendente_de_revisao") || CHAVES_DE_FALTA.includes("entidade_fantasma_pendente_de_revisao"),
  "a chave da fantasma sumiu do vocabulário");

// 2. controle negativo: o desconhecido aparece cru.
checar(traduzirFalta("motivo_novo_da_0300").includes("motivo_novo_da_0300"), "chave de falta desconhecida sumiu em vez de aparecer crua");
checar(traduzirFalta("pendencia_aberta:tipo_novo").includes("pendencia_aberta:tipo_novo"), "pendência aberta de tipo desconhecido sumiu em vez de aparecer crua");
checar(traduzirFalta("toString").includes("toString") && traduzirFalta("constructor").includes("constructor"),
  "chave com nome de propriedade de Object foi tratada como traduzida");

// 4. aceite
checar(rotuloDoAceite("nao_verificado") !== rotuloDoAceite("pendente_conferencia"), "os dois aceites conhecidos têm o mesmo rótulo");
checar(!/\bok\b/i.test(rotuloDoAceite("nao_verificado")) && !/\bok\b/i.test(rotuloDoAceite("pendente_conferencia")), "o aceite conhecido apareceu como ok");
checar(rotuloDoAceite("aceite_novo").includes("aceite_novo"), "aceite desconhecido sumiu em vez de aparecer cru");

// 5. percentual
checar(lerPercentual("") === null && lerPercentual("   ") === null && lerPercentual(null) === null, "percentual vazio virou número (zero fabricado)");
checar(lerPercentual("12,5") === 12.5 && lerPercentual("51") === 51 && lerPercentual("0") === 0, "percentual válido mal lido");
checar(Number.isNaN(lerPercentual("abc")) && Number.isNaN(lerPercentual("12%")) && Number.isNaN(lerPercentual("-5")), "percentual inválido foi aceito");

// formato do CNPJ
checar(formatarCnpj("12345678000195") === "12.345.678/0001-95", "CNPJ de 14 dígitos mal formatado");
checar(formatarCnpj("12.345.678/0001-95") === "12.345.678/0001-95", "CNPJ já formatado foi alterado");
checar(formatarCnpj("123") === "123", "valor que não é CNPJ ganhou máscara inventada");
checar(formatarCnpj(null) === "CNPJ não informado" && formatarCnpj("") === "CNPJ não informado", "ausência de CNPJ não foi dita");

// 6. veredito
checar(tituloDoVeredito({ entidades: 8, prontas: 8, fechado: true }) === "Grupo econômico fechado", "fechado não foi dito fechado");
checar(tituloDoVeredito({ entidades: 8, prontas: 3, fechado: false }) === "Faltam 5 de 8 empresas", "contagem do que falta errada");
checar(tituloDoVeredito({ entidades: 8, prontas: 8, fechado: false }) !== "Grupo econômico fechado", "o banco disse não fechado (fantasma) e a tela disse fechado");
checar(tituloDoVeredito({ entidades: 0, prontas: 0, fechado: false }) === "Grupo econômico não montado", "caso sem entidade foi apresentado como 'Faltam 0 de 0'");

// 7. as actions
const ACTIONS = readFileSync(new URL("../src/app/casos/[id]/perimetro/actions.ts", import.meta.url), "utf8");
checar(!/service_role|SERVICE_ROLE/.test(ACTIONS), "as actions do perímetro usam service role — a RLS é contornada");
checar((ACTIONS.match(/caso_id !== casoId/g) ?? []).length >= 2, "as actions não conferem que a entidade pertence ao caso");
const PAGINA = readFileSync(new URL("../src/app/casos/[id]/perimetro/page.tsx", import.meta.url), "utf8");
checar(PAGINA.includes("aceite_motivo") && PAGINA.includes("aceite_financeiro") && !/aceite_financeiro\s*[=!]==?\s*["']nao_verificado/.test(PAGINA),
  "a tela esconde o aceite financeiro quando não verificado");

// 8. família declarada (0212): os três parentescos do enum e os dois motivos de grupo, lidos da migration.
const M212 = readFileSync(new URL("../../Supabase/migrations/0212_o_bloco_familiar_que_o_controle_comum_nao_via.sql", import.meta.url), "utf8");
const ENUM212 = [...(M212.match(/create type controlador_parentesco as enum \(([^)]*)\)/)?.[1] ?? "").matchAll(/'([a-z_0-9]+)'/g)].map((m) => m[1]);
checar(ENUM212.length === 3, `a leitura do enum controlador_parentesco achou ${ENUM212.length} valores, esperava 3`);
const rotP = new Set<string>();
for (const k of ENUM212) {
  const r = rotuloDoParentesco(k);
  checar(!r.includes("sem tradução") && !r.includes(k), `parentesco "${k}" sem rótulo próprio: ${r}`);
  checar(PARENTESCOS.some((p) => p.valor === k), `o formulário não oferece o parentesco "${k}"`);
  rotP.add(r);
}
checar(rotP.size === ENUM212.length, "dois parentescos diferentes têm o mesmo rótulo");
checar(rotuloDoParentesco("tio").includes("tio"), "parentesco desconhecido sumiu em vez de aparecer cru");
for (const k of ["controlador_comum", "vinculo_familiar"]) {
  checar(MOTIVOS_DE_GRUPO.includes(k) && M212.includes(`'${k}'`), `motivo de grupo "${k}" fora do vocabulário da tela ou da migration`);
}
checar(rotuloDoMotivoDoGrupo("controlador_comum") !== rotuloDoMotivoDoGrupo("vinculo_familiar"), "os dois motivos de grupo têm a mesma frase");
checar(/familiar/.test(rotuloDoMotivoDoGrupo("vinculo_familiar")) && !/familiar/.test(rotuloDoMotivoDoGrupo("controlador_comum")), "motivo familiar e motivo de sócio comum trocados");
checar(rotuloDoMotivoDoGrupo("motivo_novo").includes("motivo_novo"), "motivo de grupo desconhecido sumiu em vez de aparecer cru");
checar(rotuloDoMotivoDoGrupo(undefined) !== rotuloDoMotivoDoGrupo("controlador_comum") && /não informado/.test(rotuloDoMotivoDoGrupo(undefined)),
  "grupo sem motivo (banco sem a 0212) foi apresentado como sócio em comum");
const PAG = readFileSync(new URL("../src/app/casos/[id]/perimetro/page.tsx", import.meta.url), "utf8");
checar(PAG.includes("vinculos") && PAG.includes("rotuloDoMotivoDoGrupo"), "a tela não mostra os vínculos e o motivo dos grupos");
checar(/nunca por sobrenome/.test(readFileSync(new URL("../src/app/casos/[id]/perimetro/SecaoParentesco.tsx", import.meta.url), "utf8")), "a tela não diz que parentesco só vale declarado");

if (falhas.length > 0) {
  console.error(`\n${falhas.length} falha(s):`);
  for (const f of falhas) console.error(`  ✗ ${f}`);
  console.error(`\n${ok} verificações OK / ${falhas.length} falhas`);
  process.exit(1);
}
console.log(`${ok} verificações OK / 0 falhas`);
console.log("PERÍMETRO OK — toda chave de falta traduzida, a desconhecida aparece crua, o aceite nunca some nem vira ok");
