import { FundoDaMarca } from "@/components/fundo-da-marca";
import { AvisoDeTela } from "@/components/aviso-de-tela";

// 404 genérico, fora de `/casos` (sem a barra do portal: este nível só tem o
// layout raiz). Endereço que não existe; o caminho de volta é o início.
// O body agora é escuro (fundo da marca), e `AvisoDeTela` usa texto escuro: por
// isso ele vem numa folha de vidro creme, como o conteúdo de toda tela do portal.
export default function NaoEncontrado() {
  return (
    <div className="min-h-screen p-3">
      <FundoDaMarca variante="app" />
      <main className="vidro-folha mx-auto max-w-3xl rounded-2xl px-6 py-8">
        <AvisoDeTela titulo="Página não encontrada" href="/casos" rotulo="Ir para o início">
          O endereço não existe ou foi movido.
        </AvisoDeTela>
      </main>
    </div>
  );
}
