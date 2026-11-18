import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { SCRIPT_DISCRICAO_ANTES_DA_PINTURA, SCRIPT_TEMA_ANTES_DA_PINTURA } from "@/lib/casco";

/* GEIST NO PORTAL INTEIRO (direção A, 13/11/2026), auto-hospedada pelo `next/font`: o arquivo é baixado
   no build e servido do nosso domínio, sem `<link>` para terceiro em runtime. Substitui Fraunces, Inter
   Tight e JetBrains Mono. Duas famílias, uma só voz: `texto` (Geist) para tudo, `dado` (Geist Mono) só
   onde há medição (valor, contagem, hora, referência). A Geist do login saiu de `login/layout.tsx` e
   foi unificada aqui: o login lê --fonte-texto, e o arquivo da fonte é pedido uma vez só. */
const texto = Geist({ subsets: ["latin"], display: "swap", variable: "--fonte-texto" });
const dado = Geist_Mono({ subsets: ["latin"], display: "swap", variable: "--fonte-dado" });

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
      className={`h-full ${texto.variable} ${dado.variable}`}
      // Os scripts abaixo podem ligar `data-discricao` e `data-tema` no <html> ANTES de o React hidratar; sem
      // isto o React acusaria a divergência entre o HTML do servidor e o do cliente.
      suppressHydrationWarning
    >
      <head>
        {/* MODO DISCRIÇÃO sem flash: lê a preferência e liga o atributo antes da primeira
            pintura. Bloqueante de propósito (uma linha, sem rede): os números nunca aparecem
            nítidos para quem deixou o modo ligado. A string vem de `lib/casco.ts`, onde o
            teste a executa. */}
        <script dangerouslySetInnerHTML={{ __html: SCRIPT_DISCRICAO_ANTES_DA_PINTURA }} />
        {/* TEMA sem flash: o mesmo padrão. Liga `data-tema` (claro/escuro) antes da pintura, a partir
            da escolha guardada ou, em "Sistema", do aparelho. */}
        <script dangerouslySetInnerHTML={{ __html: SCRIPT_TEMA_ANTES_DA_PINTURA }} />
      </head>
      <body className="min-h-full bg-papel font-texto text-tinta-900 antialiased">{children}</body>
    </html>
  );
}
