import { PainelDocumento } from "@/components/painel-documento";
import { Bloco, Esqueleto } from "@/components/esqueleto";

// Enquanto o detalhe carrega (versão vigente + até milhares de linhas), o painel já abre —
// o clique responde na hora. Sem ids aqui: anterior/próximo e "página inteira" chegam com o conteúdo.
export default function CarregandoPainel() {
  return (
    <PainelDocumento casoId="">
      <Esqueleto>
        <h1 id="titulo-documento" className="sr-only">Carregando documento</h1>
        <Bloco className="h-5 w-2/3" />
        <Bloco className="h-4 w-1/3" />
        <Bloco className="h-40 w-full" />
      </Esqueleto>
    </PainelDocumento>
  );
}
