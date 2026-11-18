import { funcaoAusente } from "./historico-do-mandato";

/**
 * Lê o resultado de `fn_fatos_do_caso` sem esconder a falha (regra 7). Lógica pura, para a suíte medir.
 *
 * Função ausente (banco sem a 0148: PGRST202/42883) é estado NORMAL: não é falha, o bloco não aparece.
 * Qualquer outro erro é falha: o bloco diz que não leu, com o efeito. Antes o erro era jogado fora e o
 * bloco sumia, com a mesma cara de "o documento não diz nada".
 */
export function lerResultadoDeFatos<T>(
  r: { data: T[] | null; error: { code?: string | null } | null },
): { fatos: T[]; falhou: boolean } {
  return { fatos: r.data ?? [], falhou: Boolean(r.error) && !funcaoAusente(r.error) };
}
