// Tira comentários `/* */` e `// …` de um fonte, para os portões de "o texto do código" não casarem
// com o que um COMENTÁRIO cita. Sem regex de fim de linha: a `(^|[^:"\'`])\/\/.*$` que vivia copiada em
// três scripts tem desempenho super-linear (Sonar S8786). `//` precedido de `:` ou de aspas fica
// (URL, string) — a mesma regra de antes.
export function semComentarios(c: string): string {
  return c
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((linha) => {
      let i = linha.indexOf("//");
      while (i !== -1) {
        if (i === 0 || !":\"'`".includes(linha[i - 1])) return linha.slice(0, i);
        i = linha.indexOf("//", i + 1);
      }
      return linha;
    })
    .join("\n");
}
