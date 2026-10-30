import { AvisoDeTela } from "@/components/aviso-de-tela";

// Pega o `notFound()` lançado por uma PÁGINA do mandato (ex.: documento que não
// existe), dentro do layout do mandato. O `notFound()` do próprio
// `[id]/layout.tsx` NÃO chega aqui — ver `casos/not-found.tsx`.
export default function PaginaDoMandatoNaoEncontrada() {
  return (
    <AvisoDeTela titulo="Página não encontrada neste mandato" href="/casos/todos" rotulo="Ir para Mandatos">
      O item pedido (um documento, por exemplo) pode ter sido removido, ou o endereço está
      incompleto. O mandato em si existe: use as abas acima.
    </AvisoDeTela>
  );
}
