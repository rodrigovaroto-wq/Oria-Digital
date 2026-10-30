"use client";

import Image, { type ImageLoaderProps } from "next/image";

// A IMAGEM DA MARCA, FIXA ATRÁS DE TUDO (decisão do dono, 28/10/2026).
//
// POR QUE `next/image` E NÃO `image-set()` EM CSS. O fundo é a maior coisa que a
// tela baixa (230 KB), e um `background-image` só é descoberto DEPOIS que o CSS
// chega e é interpretado; o `<img priority>` entra como `<link rel=preload>` no
// `<head>`, com `imagesrcset`, e começa a baixar junto com o HTML — o navegador
// escolhe o arquivo certo ANTES de pintar. Em celular isso é a diferença entre
// 94 KB e 230 KB (-59%) no mesmo pedido.
//
// POR QUE UM `loader` PRÓPRIO, E NÃO O OTIMIZADOR DO NEXT: os dois `.webp` já
// saíram prontos da mão do dono, em duas larguras. O otimizador os recodificaria
// em runtime (CPU no servidor, uma terceira cópia em cache) para entregar quase o
// mesmo. O loader só ESCOLHE entre os dois arquivos estáticos: até 1200px de
// largura pedida (um celular de 400px a 3x pede 1200) vai o de 960px; acima, o de
// 1678px. A foto fica sob um véu escuro e sob vidro desfocado, então a
// ampliação leve do arquivo menor em tela densa não aparece.
// O `?w=` existe só porque o Next, em desenvolvimento, reclama de loader que não
// usa a largura; o servidor de arquivos estáticos o ignora.
function escolherArquivo({ width }: ImageLoaderProps) {
  const arquivo =
    width <= 1200 ? "/marca/fundo-oria-digital-960.webp" : "/marca/fundo-oria-digital.webp";
  return `${arquivo}?w=${width}`;
}

/**
 * `app`: véu escuro quase uniforme (o vidro por cima precisa de um fundo
 * previsível). `login`: véu claro à esquerda, onde a placa "ORIA DIGITAL" tem de
 * ser lida, e escuro à direita, onde fica o cartão.
 */
export function FundoDaMarca({ variante = "app" }: Readonly<{ variante?: "app" | "login" }>) {
  return (
    // `fixed` + `-z-10`, e NÃO `background-attachment: fixed`: esse é ignorado no
    // iOS. Um elemento fixo é composto na GPU e não repinta a cada rolagem.
    <div aria-hidden className="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
      <Image
        src="/marca/fundo-oria-digital.webp"
        loader={escolherArquivo}
        alt=""
        fill
        priority
        sizes="100vw"
        className="object-cover"
      />
      <div className={`absolute inset-0 ${variante === "login" ? "fundo-veu-login" : "fundo-veu-app"}`} />
    </div>
  );
}
