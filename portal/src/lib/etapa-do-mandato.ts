import type { CasoStatus } from "./types";

// A RÉGUA DE ETAPAS do cabeçalho do mandato: Recebimento → Conferência →
// Modelagem → Entrega.
//
// É UMA APROXIMAÇÃO da máquina de estado do caso (Arquitetura do Sistema/2
// Especificação/f0/04), não uma segunda máquina. O `status` do banco descreve o
// estado do GATE (triagem, completude, revisão, aprovação); a régua descreve em
// que fase do TRABALHO a pessoa está, que é o que ela pergunta ao abrir o
// mandato. Os dois não são 1:1 — `bloqueado` e `aguardando_cliente` podem
// acontecer em qualquer ponto e aqui caem em Conferência, que é onde se
// destrava. Por isso a função é pura e mora em lib: quando a máquina ganhar um
// estado, o compilador reprova o `Record` abaixo em vez de a régua mentir.
export const ETAPAS_DO_MANDATO = ["Recebimento", "Conferência", "Modelagem", "Entrega"] as const;

const ETAPA_POR_STATUS: Record<CasoStatus, number> = {
  intake: 0,
  em_triagem: 0,
  completude_ok: 1,
  em_revisao: 1,
  bloqueado: 1,
  aguardando_cliente: 1,
  aprovado: 2,
  pronto_para_base: 3,
};

/** Índice (0–3) da etapa atual em `ETAPAS_DO_MANDATO`. */
export function etapaDoMandato(status: CasoStatus): number {
  return ETAPA_POR_STATUS[status];
}
