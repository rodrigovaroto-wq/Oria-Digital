import type { Metadata } from "next";
import { Fraunces, Inter_Tight, JetBrains_Mono } from "next/font/google";
import "./globals.css";
import { SCRIPT_DISCRICAO_ANTES_DA_PINTURA } from "@/lib/casco";

/* As três famílias do site da Oria, auto-hospedadas pelo `next/font`: os
   arquivos são baixados no build e servidos do nosso próprio domínio. Nada de
   `<link>` para o Google em runtime — uma requisição a menos para um terceiro,
   e `display: swap` com métricas de fallback ajustadas evita o salto de layout
   que trocar de fonte costuma causar.

   `titulo` (Fraunces) só nomeia DOCUMENTO — mandato e a lockup do login.
   `dado` (JetBrains Mono) só onde há medição. O resto da interface é `texto`
   (Inter Tight). A regra completa está no comentário de `globals.css`. */
const texto = Inter_Tight({
  subsets: ["latin"],
  display: "swap",
  variable: "--fonte-texto",
});

const titulo = Fraunces({
  subsets: ["latin"],
  display: "swap",
  variable: "--fonte-titulo",
  axes: ["opsz"],
});

const dado = JetBrains_Mono({
  subsets: ["latin"],
  display: "swap",
  variable: "--fonte-dado",
});

export const metadata: Metadata = {
  title: "Oria Partners · Tratamento de Dados Financeiros",
  description: "Portal interno — mandatos, conferência da ingestão e fila de revisão.",
  // O sextante como ícone da aba: é a parte da marca que sobrevive a 16px.
  icons: { icon: "/logo-oria-sextante.svg" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html
      lang="pt-BR"
      className={`h-full ${texto.variable} ${titulo.variable} ${dado.variable}`}
      // O script abaixo pode ligar `data-discricao` no <html> ANTES de o React hidratar; sem
      // isto o React acusaria a divergência entre o HTML do servidor e o do cliente.
      suppressHydrationWarning
    >
      <head>
        {/* MODO DISCRIÇÃO sem flash: lê a preferência e liga o atributo antes da primeira
            pintura. Bloqueante de propósito (uma linha, sem rede): os números nunca aparecem
            nítidos para quem deixou o modo ligado. A string vem de `lib/casco.ts`, onde o
            teste a executa. */}
        <script dangerouslySetInnerHTML={{ __html: SCRIPT_DISCRICAO_ANTES_DA_PINTURA }} />
      </head>
      {/* `bg-fundo-reserva` e não `bg-papel`: o fundo da marca é uma foto escura
          e fixa (`FundoDaMarca`); enquanto ela carrega, creme piscando e virando
          escuro seria pior do que escuro virando foto. */}
      <body className="min-h-full bg-fundo-reserva font-texto text-tinta-900 antialiased">{children}</body>
    </html>
  );
}
