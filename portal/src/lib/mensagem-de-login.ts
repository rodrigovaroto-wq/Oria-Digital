// A FRASE DE LOGIN QUE O ANALISTA LÊ. O Supabase Auth devolve texto em inglês
// ("Invalid login credentials"); ele ia cru para a tela. Os três casos conhecidos
// viram frase de negócio com o que fazer; qualquer outro texto cai numa frase
// genérica — NUNCA num silêncio: o login recusado continua dito. O texto original
// vai ao <details> da tela, para quem abrir chamado.
export function mensagemDeLogin(bruto: string): string {
  const m = bruto.toLowerCase();
  if (m.includes("invalid login credentials") || m.includes("invalid credentials")) {
    return "E-mail ou senha incorretos. Confira os dados e tente de novo.";
  }
  if (m.includes("email not confirmed")) {
    return "Este e-mail ainda não foi confirmado. Avise o administrador da equipe.";
  }
  if (m.includes("rate limit") || m.includes("too many") || m.includes("over_request_rate_limit")) {
    return "Muitas tentativas seguidas. Aguarde alguns minutos e tente de novo.";
  }
  return "Não foi possível entrar. Tente de novo; se continuar, avise o administrador da equipe.";
}
