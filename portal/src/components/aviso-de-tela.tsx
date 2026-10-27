import Link from "next/link";

// CORPO DAS TELAS "NÃO ENCONTRADO". Server component puro: o `not-found.tsx` do
// App Router não recebe props, então o texto específico vem de quem o chama.
export function AvisoDeTela({
  titulo, children, href, rotulo,
}: Readonly<{
  titulo: string;
  children: React.ReactNode;
  href: string;
  rotulo: string;
}>) {
  return (
    <div className="mx-auto max-w-xl py-12 text-center">
      <p className="font-dado text-sm tabular-nums text-tinta-500">404</p>
      <h1 className="mt-1 font-titulo text-2xl font-medium text-tinta-900">{titulo}</h1>
      <p className="mt-2 text-sm text-tinta-600">{children}</p>
      <Link href={href} className="btn-primario mt-5">{rotulo}</Link>
    </div>
  );
}
