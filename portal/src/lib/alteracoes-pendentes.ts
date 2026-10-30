// GUARDA DE SAÍDA DENTRO DO APP. O `beforeunload` só cobre fechar a aba e recarregar; navegação
// do cliente (clique num <Link>, resultado do ⌘K com `router.push`) não dispara nada e perdia a
// escolha pendente da Modelagem em silêncio. O editor registra aqui quantas alterações não
// salvas existem; quem navega por código chama `interceptarNavegacao` — se houver pendência, o
// editor abre o diálogo de confirmação (evento) e a navegação NÃO acontece sozinha.
// Limite conhecido: o botão "voltar" do navegador não passa por aqui.

export const EVENTO_CONFIRMAR_SAIDA = "oria:confirmar-saida";

let pendentes = 0;

export function definirPendentes(n: number): void { pendentes = n; }
export function temPendentes(): boolean { return pendentes > 0; }

/** `true` = a navegação foi retida e o diálogo foi pedido; `false` = pode navegar. */
export function interceptarNavegacao(href: string): boolean {
  if (pendentes === 0 || typeof window === "undefined") return false;
  window.dispatchEvent(new CustomEvent(EVENTO_CONFIRMAR_SAIDA, { detail: { href } }));
  return true;
}
