import { Bloco, Esqueleto, EsqueletoTabela } from "@/components/esqueleto";

// A Modelagem é a tela mais lenta do portal: a página dispara várias RPCs em
// sequência (portão 2, realizado, sugestões) e leva segundos. Sem este arquivo o
// clique na aba parecia não ter feito nada. Forma: faixa de ações + duas seções.
export default function CarregandoModelagem() {
  return (
    <Esqueleto>
      <div className="flex gap-2"><Bloco className="h-8 w-40" /><Bloco className="h-8 w-40" /></div>
      <Bloco className="h-5 w-56" />
      <EsqueletoTabela linhas={4} />
      <Bloco className="h-5 w-44" />
      <EsqueletoTabela linhas={6} />
    </Esqueleto>
  );
}
