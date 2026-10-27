import { AvisoDeTela } from "@/components/aviso-de-tela";

// ESTE ARQUIVO É O QUE REALMENTE PEGA "mandato inexistente". `[id]/layout.tsx`
// chama `notFound()` quando o caso não existe (linha ~56), e um `notFound()`
// lançado num LAYOUT é capturado pela fronteira do segmento PAI — a que o
// layout de `casos` monta —, não por `[id]/not-found.tsx` (que embrulha só as
// páginas abaixo do layout). Sem este arquivo o 404 cairia no `app/not-found.tsx`
// genérico, perdendo a barra e o cabeçalho do portal e a frase certa.
export default function CasoNaoEncontrado() {
  return (
    <AvisoDeTela titulo="Mandato não encontrado" href="/casos/todos" rotulo="Ir para Mandatos">
      Ele pode ter sido excluído, ou o endereço está incompleto.
    </AvisoDeTela>
  );
}
