import { AvisoDeTela } from "@/components/aviso-de-tela";

// 404 genérico, fora de `/casos` (sem a barra do portal: este nível só tem o
// layout raiz). Endereço que não existe; o caminho de volta é o início.
export default function NaoEncontrado() {
  return (
    <main className="px-6">
      <AvisoDeTela titulo="Página não encontrada" href="/casos" rotulo="Ir para o início">
        O endereço não existe ou foi movido.
      </AvisoDeTela>
    </main>
  );
}
