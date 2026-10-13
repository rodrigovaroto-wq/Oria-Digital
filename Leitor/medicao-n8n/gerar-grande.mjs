// ECD sintética com N linhas de I250 (lançamento), escrita em fluxo, com 9900/9999 coerentes.
// Uso: node gerar-grande.mjs <milhoes> <saida>
import { createWriteStream } from 'node:fs';
import { gerarSped } from '../../Dados de Teste/fontes-oficiais/gerar.mjs';
const n = Math.round(Number(process.argv[2]) * 1e6), saida = process.argv[3];
const base = gerarSped('ECD', { linhasDeMovimento: 0 }).toString('latin1').split('\r\n').filter(Boolean);
const cab = base.filter(l => !l.startsWith('|9')); // 0000, 0001, I010
const out = createWriteStream(saida, { encoding: 'latin1' });
const w = s => out.write(s) || new Promise(r => out.once('drain', r));
for (const l of cab) await w(l + '\r\n');
let lote = [];
for (let i = 0; i < n; i++) {
  lote.push(`|I250|1.01.01.${String(i % 997).padStart(3, '0')}.001|CC${i % 40}|${(i * 37 % 9999999) / 100},${String(i % 100).padStart(2, '0')}|${i % 2 ? 'D' : 'C'}|${i}|LT${i % 5000}|HISTÓRICO DE LANÇAMENTO CONTÁBIL FICTÍCIO NÚMERO ${i}|P${i % 300}|`);
  if (lote.length === 10000) { const p = w(lote.join('\r\n') + '\r\n'); lote = []; if (p !== true) await p; }
}
if (lote.length) await w(lote.join('\r\n') + '\r\n');
const regs = { '0000': 1, '0001': 1, I010: 1, I250: n };
const b9 = Object.entries(regs).map(([r, q]) => `|9900|${r}|${q}|`);
const n9900 = b9.length + 2;
b9.push(`|9900|9900|${n9900}|`, '|9900|9999|1|');
const total = cab.length + n + b9.length + 1;
for (const l of b9) await w(l + '\r\n');
await w(`|9999|${total}|\r\n`);
out.end(); await new Promise(r => out.on('finish', r));
console.log(JSON.stringify({ saida, linhas: total }));
