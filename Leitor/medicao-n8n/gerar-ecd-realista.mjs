// ECD sintética com a COMPOSIÇÃO de uma real: plano de contas (I050), saldos mensais
// (I150/I155), balanço e DRE (J100/J150) e o volume em lançamentos (I200/I250).
// Uso: node gerar-ecd-realista.mjs <milhões de linhas> <saída> [contas=2000]
// O 9900 e o 9999 são coerentes: `Leitor/ler.mjs` tem de dar `lido`.
import { createWriteStream } from 'node:fs';
const alvo = Math.round(Number(process.argv[2]) * 1e6), saida = process.argv[3], CONTAS = Number(process.argv[4] || 2000);
const out = createWriteStream(saida, { encoding: 'latin1' });
const regs = {};
let buf = [], total = 0;
const w = async (l) => {
  regs[l.slice(1, 5)] = (regs[l.slice(1, 5)] || 0) + 1; total++;
  buf.push(l);
  if (buf.length === 10000) { const ok = out.write(buf.join('\r\n') + '\r\n'); buf = []; if (!ok) await new Promise(r => out.once('drain', r)); }
};
const conta = (i) => `1.${1 + (i % 4)}.${String(1 + (i % 9)).padStart(2, '0')}.${String(i).padStart(5, '0')}`;
const v = (x) => (x / 100).toFixed(2).replace('.', ',');
const dd = (d, m) => `${String(d).padStart(2, '0')}${String(m).padStart(2, '0')}2025`;
await w('|0000|LECD|01012025|31122025|AÇÚCAR SINTÉTICO LTDA (fictícia)|11222333000181|SP||3550308||0|0|0|0||0|0||N|N|0|0||');
await w('|0001|0|');
await w('|I010|G|9.00|');
for (let i = 0; i < CONTAS; i++) await w(`|I050|01012025|01|A|5|${conta(i)}|${conta(i).slice(0, -6)}|CONTA ANALÍTICA FICTÍCIA ${i} - APLICAÇÕES E DÉBITOS|`);
for (let m = 1; m <= 12; m++) {
  await w(`|I150|${dd(1, m)}|${dd(28, m)}|`);
  for (let i = 0; i < CONTAS; i++) await w(`|I155|${conta(i)}|CC${i % 40}|${v(i * 1000 + m)}|D|${v(i * 37 + m * 11)}|${v(i * 13 + m * 7)}|${v(i * 1000 + m + i * 24 + m * 4)}|D|`);
}
// J100 (120 linhas) + J150 (60) + J005/J900, e o 9900/9999 depois
const fixas = 4 + 120 + 60 + 1 + 1 + 1; // J005, J100s, J150s, J900, 9990... (estimativa só para o alvo)
const blocoNove = 30;
let n = 0;
while (total + fixas + blocoNove < alvo) {
  const m = 1 + (n % 12), d = 1 + (n % 28);
  await w(`|I200|${n}|${dd(d, m)}|${v(n * 31 % 9999999)}|N|`);
  for (let k = 0; k < 3 && total + fixas + blocoNove < alvo; k++)
    await w(`|I250|${conta((n * 7 + k) % CONTAS)}|CC${n % 40}|${v((n * 31 + k) % 9999999)}|${k % 2 ? 'C' : 'D'}|${n}|LT${n % 5000}|HISTÓRICO DE LANÇAMENTO CONTÁBIL FICTÍCIO NÚMERO ${n}|P${n % 300}|`);
  n++;
}
await w('|J005|01012025|31122025|1||');
for (let i = 0; i < 120; i++) await w(`|J100|${i + 1}|${1 + (i % 4)}|${i % 7 ? 'D' : 'T'}|${1 + (i % 4)}|1|LINHA DO BALANÇO ${i}|${v(i * 99991)}|D|${v(i * 99989)}|D||`);
for (let i = 0; i < 60; i++) await w(`|J150|${i + 1}|${1 + (i % 3)}|${i % 5 ? 'D' : 'T'}|1|LINHA DA DRE ${i}|${v(i * 7777)}|C|${v(i * 7771)}|C||`);
await w('|J900|TERMO DE ENCERRAMENTO|');
if (buf.length) { out.write(buf.join('\r\n') + '\r\n'); buf = []; }
const b9 = Object.entries(regs).map(([r, q]) => `|9900|${r}|${q}|`);
b9.push(`|9900|9900|${b9.length + 2}|`, '|9900|9999|1|');
total += b9.length + 1;
out.write(b9.join('\r\n') + '\r\n' + `|9999|${total}|\r\n`);
out.end(); await new Promise(r => out.on('finish', r));
console.log(JSON.stringify({ saida, linhas: total, lancamentos: n }));
