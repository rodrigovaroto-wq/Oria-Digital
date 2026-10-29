// A RECUPERAÇÃO DE SENHA — a lógica que não depende de tela, para poder ser medida.
//
// Três defeitos silenciosos moram aqui, e cada um tem asserts em
// scripts/verificar-mensagem-de-falha.mts (medidos: ver o commit):
//   1. a resposta do pedido NÃO PODE depender de o e-mail existir — senão a tela vira
//      uma consulta de "quem tem conta" aberta ao mundo, e esta é a única tela
//      pública do sistema que escreve algo;
//   2. `next` volta do e-mail como texto de terceiros: só caminho interno passa, ou o
//      link vira um redirecionamento aberto (/auth/confirmar?next=//evil.com);
//   3. a lista de rotas públicas é EXATA — o proxy usava `startsWith("/login")`, e
//      qualquer rota nova sob /login nascia aberta sem ninguém decidir isso.

export const SENHA_MINIMA = 10;
export const REGRA_DA_SENHA = `Use ao menos ${SENHA_MINIMA} caracteres.`;

/** A ÚNICA resposta do pedido de recuperação — a mesma exista ou não a conta. */
export const RESPOSTA_DO_PEDIDO =
  "Se houver uma conta com este e-mail, enviamos um link para criar uma nova senha. O link vale por tempo limitado; confira também a caixa de spam.";

/** Rotas que respondem SEM sessão. Exata: prefixo não vale (ver o item 3 acima). */
export const ROTAS_PUBLICAS: readonly string[] = ["/login", "/login/recuperar", "/auth/confirmar"];

export function rotaPublica(pathname: string): boolean {
  // Barra final é o mesmo caminho para o Next (trailingSlash desligado redireciona).
  const p = pathname.length > 1 && pathname.endsWith("/") ? pathname.slice(0, -1) : pathname;
  return ROTAS_PUBLICAS.includes(p);
}

/** `next` só aceita caminho interno: começa com "/" e não com "//" nem "/\". */
export function caminhoInternoSeguro(next: string | null | undefined, padrao: string): string {
  if (typeof next !== "string" || next.length === 0) return padrao;
  if (!next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) return padrao;
  // Controle/branco no começo do destino é como `/\t/evil.com` escapa de filtro ingênuo.
  if (/[\u0000-\u001f\u007f\\]/.test(next)) return padrao;
  return next;
}

/** A origem do site a partir dos cabeçalhos; nunca monta URL com host vazio. */
export function origemDaRequisicao(origin: string | null, host: string | null, proto: string | null): string | null {
  if (origin && /^https?:\/\/[^/\s]+$/.test(origin)) return origin;
  if (host && /^[A-Za-z0-9.-]+(:\d+)?$/.test(host)) {
    const esquema = proto === "http" || proto === "https" ? proto : host.startsWith("localhost") ? "http" : "https";
    return `${esquema}://${host}`;
  }
  return null;
}

/** O `redirectTo` do e-mail: callback do portal, com `next` já saneado. */
export function montarRedirectTo(origem: string, next: string): string {
  return `${origem}/auth/confirmar?next=${encodeURIComponent(caminhoInternoSeguro(next, "/login/nova-senha"))}`;
}

/** Nova senha: devolve o CÓDIGO do problema (a frase sai de `mensagemDeRecuperacao`), ou null. */
export function validarNovaSenha(senha: string, confirmacao: string): "senha_curta" | "senhas_diferentes" | null {
  if (senha.length < SENHA_MINIMA) return "senha_curta";
  if (senha !== confirmacao) return "senhas_diferentes";
  return null;
}

export const ERRO_LINK = "link_invalido";

/**
 * O texto do Auth (inglês) vira frase de negócio. `aguardar` marca o limite de envio
 * (429), que pede espera e não nova tentativa. Texto desconhecido cai numa frase
 * genérica — nunca em silêncio, e nunca em "enviamos", que seria prometer o e-mail.
 */
export function mensagemDeRecuperacao(bruto: string): { mensagem: string; aguardar: boolean } {
  const m = bruto.toLowerCase();
  if (m === ERRO_LINK || m.includes("otp_expired") || m.includes("expired") || m.includes("invalid or has expired")
    || m.includes("session missing") || m.includes("session_not_found") || m.includes("access_denied")) {
    return { mensagem: "Este link venceu ou já foi usado. Peça um novo link para criar a senha.", aguardar: false };
  }
  if (m.includes("rate limit") || m.includes("too many") || m.includes("over_email_send_rate_limit")
    || m.includes("over_request_rate_limit") || m.includes("429") || m.includes("security purposes")) {
    return { mensagem: "Muitos pedidos seguidos. Aguarde alguns minutos antes de pedir outro link.", aguardar: true };
  }
  if (m.includes("same_password") || m.includes("different from the old")) {
    return { mensagem: "A nova senha precisa ser diferente da atual.", aguardar: false };
  }
  if (m.includes("weak_password") || m.includes("password should")) {
    return { mensagem: `O sistema recusou esta senha por ser fraca. ${REGRA_DA_SENHA} Misture letras e números.`, aguardar: false };
  }
  if (m === "senha_curta") return { mensagem: `A senha é curta demais. ${REGRA_DA_SENHA}`, aguardar: false };
  if (m === "senhas_diferentes") {
    return { mensagem: "As duas senhas não são iguais. Digite a mesma nos dois campos.", aguardar: false };
  }
  if (m === "email_vazio") {
    return { mensagem: "Informe o e-mail da sua conta.", aguardar: false };
  }
  return {
    mensagem: "Não foi possível concluir agora. Tente de novo; se continuar, avise o administrador da equipe.",
    aguardar: false,
  };
}
