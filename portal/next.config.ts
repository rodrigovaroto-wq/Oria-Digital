import type { NextConfig } from "next";
import path from "node:path";

// O PORTAL IMPORTA CÓDIGO DE FORA DE `portal/` — pela primeira vez (13/10/2026).
//
// O leitor de arquivos oficiais (`Leitor/lib`, que importa `N8N/lib/formato.mjs`)
// roda no navegador, e é o MESMO módulo do CLI: copiá-lo para cá criaria duas
// implementações da mesma leitura, que divergem sem erro nenhum. O teto por
// arquivo também vem de `N8N/lib/custo.mjs`. Por isso o build tem de enxergar a
// raiz do repositório, e não só `portal/`:
//   - `outputFileTracingRoot`: sem ele a raiz do build é `portal/` (pelo lockfile) e o
//     Turbopack, o padrão do Next 16, falha com "Module not found: ../../../Leitor/lib/...".
//     MEDIDO em 13/10/2026: sem esta linha o `next build` reprova (3 erros); com ela
//     passa, e o `turbopack.root` herda o valor — por isso não é repetido aqui;
//   - `experimental.externalDir` NÃO foi necessário: `next build --webpack` também passa
//     só com `outputFileTracingRoot` (medido). Não está ligado por não ter o que provar.
//
// RISCO NA VERCEL: o Root Directory do projeto é `portal`. Para o build enxergar
// `../Leitor` e `../N8N`, o projeto precisa de "Include source files outside of
// the Root Directory in the Build Step" LIGADO (Settings > General > Root
// Directory). É o padrão em projeto novo, mas projeto criado antes pode estar
// desligado — e nesse caso o `next build` da Vercel falha com "Module not
// found: ../../../Leitor/lib/...", enquanto o local passa. Confira ao publicar.
const raizDoRepositorio = path.join(__dirname, "..");

const nextConfig: NextConfig = {
  outputFileTracingRoot: raizDoRepositorio,
};

export default nextConfig;
