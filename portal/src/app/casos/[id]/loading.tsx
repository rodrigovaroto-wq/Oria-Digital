import { Bloco, Esqueleto, EsqueletoTabela } from "@/components/esqueleto";

// Renderiza DENTRO de `[id]/layout.tsx`: cabeçalho, régua e abas do mandato
// ficam na tela e só o conteúdo da aba é esqueleto. Vale para toda subtela sem
// `loading.tsx` próprio (visão geral, revisão, perguntas, grupo).
export default function CarregandoAba() {
  return (
    <Esqueleto>
      <Bloco className="h-5 w-48" />
      <EsqueletoTabela linhas={5} />
    </Esqueleto>
  );
}
