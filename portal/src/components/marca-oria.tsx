/* eslint-disable @next/next/no-img-element */

// A MARCA, EM UM LUGAR SÓ.
//
// Os dois arquivos em `public/` saíram do original enviado pelo dono, com UMA
// operação: o creme do fundo virou transparência. A arte não foi redesenhada,
// traçada nem recortada — mesma silhueta, mesmo tamanho, mesmo azul. O que
// mudou é que a suavização das bordas passou a viver no canal alfa, que é o que
// permite pôr o logotipo sobre qualquer fundo sem auréola.
//
// POR QUE `<img>` E NÃO SVG INLINE: o SVG entregue EMBUTE a arte original (o
// desenho em pixels, em base64). Vetorizar de verdade exigiria TRAÇAR a imagem —
// o computador redesenharia as curvas por aproximação —, e a instrução foi
// explícita: não mexer na arte. Embutir preserva o original byte a byte e ainda
// assim entrega um `.svg` com fundo transparente, que é o que "adaptável a
// qualquer ambiente" pede.
//
// DUAS VARIANTES, e a escolha é de espaço, não de gosto:
//   • `completa` — sextante + ORIA + PARTNERS, empilhados. Precisa de altura;
//     usar onde ela existe (login, capa).
//   • `sextante` — só o instrumento. É o que cabe numa barra de 57px sem virar
//     um borrão de 9px de altura por linha de texto.
export function MarcaOria({
  variante = "completa",
  className = "",
  alt = "Oria Partners",
}: {
  variante?: "completa" | "sextante";
  className?: string;
  // `alt=""` quando a marca vem ao lado do próprio nome escrito: o leitor de
  // tela diria "Oria Partners ORIA DIGITAL" para um link só.
  alt?: string;
}) {
  const arquivo = variante === "sextante" ? "/logo-oria-sextante.svg" : "/logo-oria.svg";
  return (
    <img
      src={arquivo}
      alt={alt}
      className={className}
      // A arte é quadrada nas duas variantes; declarar as proporções evita o
      // pulo de layout enquanto o arquivo carrega.
      width={variante === "sextante" ? 178 : 400}
      height={variante === "sextante" ? 178 : 400}
    />
  );
}
