import type { CasoStatus } from "./types";

// Rótulo + cor por status do caso (Arquitetura do Sistema/2 Especificação/f0/04 — máquina de estado do caso).
export const CASO_STATUS_LABEL: Record<CasoStatus, string> = {
  intake: "Recebendo documentos",
  em_triagem: "Em triagem",
  completude_ok: "Documentação completa",
  em_revisao: "Em revisão",
  aprovado: "Aprovado",
  pronto_para_base: "Pronto para análise",
  bloqueado: "Bloqueado",
  aguardando_cliente: "Aguardando cliente",
};

export const CASO_STATUS_COLOR: Record<CasoStatus, string> = {
  intake: "bg-tinta-100 text-tinta-600",
  em_triagem: "bg-alerta-100 text-alerta-800",
  completude_ok: "bg-ok-100 text-ok-800",
  em_revisao: "bg-info-100 text-info-800",
  aprovado: "bg-ok-100 text-ok-800",
  pronto_para_base: "bg-ok-100 text-ok-800",
  bloqueado: "bg-risco-100 text-risco-800",
  aguardando_cliente: "bg-alerta-100 text-alerta-800",
};
