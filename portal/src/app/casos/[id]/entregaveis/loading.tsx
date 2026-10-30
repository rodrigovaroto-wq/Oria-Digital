import { Bloco, Esqueleto } from "@/components/esqueleto";

// Forma da tela: título, três cartões lado a lado (os entregáveis) e a seção dos campos. A página
// faz uma RPC (Portão 2) e duas leituras antes de pintar — sem este arquivo o clique na aba
// parecia não ter feito nada.
export default function CarregandoEntregaveis() {
  return (
    <Esqueleto>
      <Bloco className="h-5 w-48" />
      <div className="grid gap-4 md:grid-cols-3"><Bloco className="h-52" /><Bloco className="h-52" /><Bloco className="h-52" /></div>
      <Bloco className="h-5 w-56" />
      <Bloco className="h-40" />
    </Esqueleto>
  );
}
