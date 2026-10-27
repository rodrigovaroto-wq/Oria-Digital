import { Bloco, Esqueleto, EsqueletoTabela } from "@/components/esqueleto";

// Painel: saudação, quatro indicadores e a lista. Aparece DENTRO do layout de
// `casos` (barra e cabeçalho ficam) enquanto as consultas do painel rodam.
export default function CarregandoPainel() {
  return (
    <Esqueleto>
      <Bloco className="h-7 w-64" />
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        {[0, 1, 2, 3].map((i) => <Bloco key={i} className="h-20" />)}
      </div>
      <EsqueletoTabela linhas={5} />
    </Esqueleto>
  );
}
