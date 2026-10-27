import { Bloco, Esqueleto, EsqueletoTabela } from "@/components/esqueleto";

// Lista completa de mandatos: título e a tabela.
export default function CarregandoMandatos() {
  return (
    <Esqueleto>
      <Bloco className="h-7 w-40" />
      <EsqueletoTabela linhas={8} />
    </Esqueleto>
  );
}
