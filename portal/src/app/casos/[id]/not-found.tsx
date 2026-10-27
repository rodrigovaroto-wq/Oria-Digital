import { AvisoDeTela } from "@/components/aviso-de-tela";

// Pega o `notFound()` lançado por uma PÁGINA do mandato (ex.: documento que não
// existe), dentro do layout do mandato. O `notFound()` do próprio
// `[id]/layout.tsx` NÃO chega aqui — ver `casos/not-found.tsx`.
export default function MandatoNaoEncontrado() {
  return (
    <AvisoDeTela titulo="Mandato não encontrado" href="/casos/todos" rotulo="Ir para Mandatos">
      Ele pode ter sido excluído, ou o endereço está incompleto.
    </AvisoDeTela>
  );
}
