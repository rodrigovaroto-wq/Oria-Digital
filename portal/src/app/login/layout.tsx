import { Geist } from "next/font/google";

// GEIST SÓ NO LOGIN (direção A · Cobalto noturno). Registrada aqui, no layout do
// segmento, e não no layout raiz: o `next/font` só pré-carrega a fonte nas rotas
// que passam por este layout, então as telas internas não pagam o arquivo nem
// trocam de aparência. `display: swap` mostra o texto de reserva de imediato.
// Geist Mono não entra: a maquete a usava só na linha de números, que não existe
// na tela deslogada (não há como ler esses números do banco sem sessão).
const geist = Geist({ subsets: ["latin"], display: "swap", variable: "--fonte-login" });

export default function LoginLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <div className={geist.variable}>{children}</div>;
}
