import type { ReactNode } from "react";
import { ROTULO_DO_PAPEL, type Liberacao, type Permissoes } from "@/lib/acesso";

// COMO O PAPEL APARECE NA TELA. Duas peças, e nenhuma decide acesso — o banco decide (0216):
//   - `FaixaDeAcesso`: o MOTIVO, em texto visível. Dica de mouse (`title=`) não existe no toque, e o
//     celular é a cena de uso 3 do PRODUCT.md; o que está desabilitado diz por quê ao lado.
//   - `ZonaDeEscrita`: desabilita de uma vez todo botão e campo de dentro. É um `<fieldset
//     disabled>` — o próprio navegador impede o clique e o Enter, sem repassar `disabled` a cada
//     controle de cada formulário (e sem esquecer um). Link não é controle de formulário e o
//     `fieldset` não o alcança: o que é link o chamador esconde.
export function FaixaDeAcesso({ liberacao, titulo }: Readonly<{ liberacao: Liberacao; titulo?: string }>) {
  if (liberacao.pode || !liberacao.motivo) return null;
  return (
    <p role="note" className="rounded-lg border border-tinta-200 bg-tinta-50 px-3 py-2 text-sm text-tinta-700">
      {titulo && <strong className="font-semibold text-tinta-900">{titulo} </strong>}
      {liberacao.motivo}
    </p>
  );
}

export function ZonaDeEscrita({
  pode, children, className = "",
}: Readonly<{ pode: boolean; children: ReactNode; className?: string }>) {
  // `className` serve ao layout de dentro (flex, grid); com `pode`, o filho é entregue como estava.
  if (pode) return className ? <div className={className}>{children}</div> : <>{children}</>;
  return (
    <fieldset
      disabled
      className={`m-0 min-w-0 border-0 p-0 [&_:is(button,input,select,textarea):disabled]:opacity-50 ${className}`}
    >
      {children}
    </fieldset>
  );
}

/** Aviso de que o papel não pôde ser lido: a tela não esconde nada e diz que não conferiu. */
export function AvisoDeAcessoNaoConferido({ permissoes }: Readonly<{ permissoes: Permissoes }>) {
  if (permissoes.conferido) return null;
  return (
    <p role="status" className="rounded-lg border border-alerta-200 bg-alerta-50 px-3 py-2 text-sm text-alerta-900">
      Não foi possível conferir o seu papel agora, então a tela não esconde nenhuma ação. O sistema
      continua recusando o que o seu papel não permite.
    </p>
  );
}

/** O papel, em uma etiqueta: no menu da conta e na tela de equipe. */
export function EtiquetaDoPapel({ papel }: Readonly<{ papel: Permissoes["papel"] }>) {
  return (
    <span className="chip bg-tinta-100 text-tinta-700">{papel ? ROTULO_DO_PAPEL[papel] : "Sem papel"}</span>
  );
}
