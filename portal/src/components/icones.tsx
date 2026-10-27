// ÍCONES DA NAVEGAÇÃO, desenhados à mão e embutidos.
//
// POR QUE NÃO UMA BIBLIOTECA: o portal usa ~10 ícones, e uma biblioteca de
// ícones entra no lock (e no bundle) pelo preço de um punhado de `<path>`. A
// regra do projeto é dependência nova só quando poucas linhas não fazem — aqui
// poucas linhas fazem. Todos seguem a mesma gramática (viewBox 24, traço de
// 1,7px, pontas arredondadas, `currentColor`) para pesarem igual ao lado do
// texto de 14px; traço de 2px ao lado de `text-sm` lê como negrito.
//
// `aria-hidden`: o ícone NUNCA é o nome do controle. Quem o usa sozinho (o
// trilho recolhido da barra) põe `aria-label` no botão/link, e quem o usa ao
// lado de texto deixa o texto falar — leitor de tela não anuncia desenho.

import type { ReactNode, SVGProps } from "react";

type Props = Omit<SVGProps<SVGSVGElement>, "children"> & { tamanho?: number };

function Base({ tamanho = 18, children, ...resto }: Props & { children: ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={tamanho}
      height={tamanho}
      fill="none"
      stroke="currentColor"
      strokeWidth={1.7}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
      {...resto}
    >
      {children}
    </svg>
  );
}

export const IconeInicio = (p: Props) => (
  <Base {...p}>
    <path d="M4 11.2 12 4l8 7.2" />
    <path d="M6 10v9.2a.8.8 0 0 0 .8.8H10v-5.5h4V20h3.2a.8.8 0 0 0 .8-.8V10" />
  </Base>
);

export const IconeMandatos = (p: Props) => (
  <Base {...p}>
    <path d="M3.5 7.2A1.7 1.7 0 0 1 5.2 5.5h4l2 2.3h7.6a1.7 1.7 0 0 1 1.7 1.7v8.3a1.7 1.7 0 0 1-1.7 1.7H5.2a1.7 1.7 0 0 1-1.7-1.7z" />
  </Base>
);

export const IconeMais = (p: Props) => (
  <Base {...p}>
    <path d="M12 5.5v13M5.5 12h13" />
  </Base>
);

export const IconeQualidade = (p: Props) => (
  <Base {...p}>
    <path d="M4.5 20h15" />
    <path d="M7 20v-6.5M12 20V5M17 20v-9.5" />
  </Base>
);

export const IconeSair = (p: Props) => (
  <Base {...p}>
    <path d="M10 4.5H6.2A1.7 1.7 0 0 0 4.5 6.2v11.6a1.7 1.7 0 0 0 1.7 1.7H10" />
    <path d="M15 8l4 4-4 4M19 12H9.5" />
  </Base>
);

/** Recolher a barra: seta para a esquerda contra um fio vertical. */
export const IconeRecolher = (p: Props) => (
  <Base {...p}>
    <path d="M4.5 5v14" />
    <path d="M18.5 7.5 13.5 12l5 4.5" />
  </Base>
);

/** Expandir a barra: o espelho do anterior. */
export const IconeExpandir = (p: Props) => (
  <Base {...p}>
    <path d="M4.5 5v14" />
    <path d="M10 7.5l5 4.5-5 4.5" />
  </Base>
);

export const IconeChevronBaixo = (p: Props) => (
  <Base {...p}>
    <path d="m6.5 9.5 5.5 5.5 5.5-5.5" />
  </Base>
);

export const IconeConta = (p: Props) => (
  <Base {...p}>
    <circle cx="12" cy="8.5" r="3.5" />
    <path d="M5 19.5c.8-3.3 3.7-5 7-5s6.2 1.7 7 5" />
  </Base>
);

export const IconeCheck = (p: Props) => (
  <Base {...p}>
    <path d="m5 12.5 4.5 4.5L19 7.5" />
  </Base>
);

export const IconeMais3Pontos = (p: Props) => (
  <Base {...p}>
    <circle cx="5.5" cy="12" r="1.1" fill="currentColor" />
    <circle cx="12" cy="12" r="1.1" fill="currentColor" />
    <circle cx="18.5" cy="12" r="1.1" fill="currentColor" />
  </Base>
);
