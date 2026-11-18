import { Suspense } from "react";

// BLOCO QUE CHEGA POR STREAMING, com esqueleto do tamanho final que se revela.
//
// COMO FUNCIONA. O `<Suspense>` manda o `esqueleto` já no primeiro HTML; quando a consulta do bloco
// responde, o servidor envia o conteúdo e o React o põe no lugar do esqueleto. O efeito é o
// "skeleton reveal" do transitions.dev (cross-fade com cross-blur, `--duration-slow`/`--blur-small`/
// `--ease-in-out`), em CSS puro: o conteúdo entra de opacity 0 + blur 2px para nítido, e uma CÓPIA do
// esqueleto (`t-skel-ghost`, aria-hidden, sobre o conteúdo) sai no mesmo tempo. A skill original
// empilha as duas camadas e alterna uma classe por JS; aqui o React TROCA o nó, então o esqueleto
// que sai precisa ser uma cópia dentro do conteúdo — sem JS no cliente e sem hidratar nada.
//
// A REDE DE SEGURANÇA (a lição do `Surgir`): o estado BASE do CSS é o estado final — conteúdo visível,
// cópia do esqueleto invisível. A animação só parte de "escondido" para o base. Se ela não rodar
// (prefers-reduced-motion, CSS falhou, aba em segundo plano), o número está na tela, nunca um bloco
// invisível.
//
// REGRA 1 / 7: o esqueleto é "carregando", e diz isso (`role="status"` + texto para leitor de tela).
// Ele nunca carrega valor, e um bloco que não chegou fica com cara de carregando, não de "nada a
// mostrar". Consulta que falha é problema do FILHO: ele mostra o erro com motivo e efeito, como já
// mostrava, e esse erro também se revela por aqui.
export function Revelar({
  esqueleto,
  rotulo = "Carregando…",
  className = "",
  children,
}: Readonly<{
  /** Forma do bloco pronto, no tamanho final (altura medida, não chutada). Sem valor nenhum. */
  esqueleto: React.ReactNode;
  /** O que o leitor de tela ouve enquanto o bloco não chega. */
  rotulo?: string;
  /** Posição do bloco no pai (coluna do grid, etc.), a mesma no esqueleto e no conteúdo. */
  className?: string;
  /** O conteúdo: normalmente um componente assíncrono que faz a consulta. */
  children: React.ReactNode;
}>) {
  return (
    <Suspense
      fallback={
        <div role="status" aria-live="polite" className={className}>
          <span className="sr-only">{rotulo}</span>
          {esqueleto}
        </div>
      }
    >
      <ConteudoRevelado esqueleto={esqueleto} className={className}>{children}</ConteudoRevelado>
    </Suspense>
  );
}

// Fica DENTRO do Suspense: quem suspende é `children`, e esta moldura só é montada quando ele chega.
function ConteudoRevelado({
  esqueleto, className, children,
}: Readonly<{ esqueleto: React.ReactNode; className: string; children: React.ReactNode }>) {
  return (
    <div className={`t-skel ${className}`}>
      <div aria-hidden className="t-skel-ghost">{esqueleto}</div>
      <div className="t-skel-content">{children}</div>
    </div>
  );
}
