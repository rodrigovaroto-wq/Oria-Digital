// Invariante de COMPORTAMENTO: uma conta é no máximo UM de {cliente, estoque, fornecedor}, e o certo.
// Caso Fw Valtra: 4 rótulos casavam ehCliente/ehFornecedor E ehEstoque (ver modelo-institucional.ts).
import { ehCliente, ehEstoque, ehFornecedor } from "../src/lib/modelo-institucional.ts";

const casos: [string, "cliente" | "estoque" | "fornecedor" | null][] = [
  ["(-) MERCADORIA EM GARANTIA/CONSERTO A DEVOLVER(CLIENTE)", "estoque"],
  ["(-) (-) MERCADORIA EM GARANTIA/CONSERTO A DEVOLVER(CLIENTE)", "estoque"],
  ["(-) ESTOQUE EM DEMONSTRAÇÃO COM CLIENTES A RECEBER", "estoque"],
  ["(-) MERCADORIA EM GARANTIA/CONSERTO(FORNECEDOR)", "estoque"],
  ["CLIENTES", "cliente"], ["Duplicatas a receber", "cliente"], ["Contas a receber de clientes", "cliente"],
  ["Títulos a receber", "cliente"], ["(-) Provisão para devedores duvidosos - clientes", "cliente"],
  ["ESTOQUE DE PEÇAS", "estoque"], ["Estoques", "estoque"], ["Matéria-prima", "estoque"],
  ["Produtos acabados", "estoque"], ["Mercadorias para revenda", "estoque"],
  ["Fornecedores", "fornecedor"], ["Fornecedores de mercadorias", "fornecedor"],
  ["Contas a pagar", "fornecedor"], ["Duplicatas a pagar", "fornecedor"],
  ["Adiantamento a fornecedores", "fornecedor"], ["Caixa e equivalentes", null],
];
let falhas = 0;
for (const [r, esperado] of casos) {
  const m = [ehCliente(r) && "cliente", ehEstoque(r) && "estoque", ehFornecedor(r) && "fornecedor"].filter(Boolean);
  const ok = m.length === (esperado ? 1 : 0) && (esperado === null || m[0] === esperado);
  if (!ok) { falhas++; console.error(`REPROVA  ${r}  -> [${m}] esperado ${esperado}`); }
}
console.log(`${casos.length - falhas}/${casos.length} asserts de exclusividade`);
process.exit(falhas ? 1 : 0);
