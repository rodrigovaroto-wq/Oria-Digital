// A ABA DOCUMENTOS TEM DOIS SLOTS: `children` (a lista, ou a página inteira de um documento) e
// `@painel` (o detalhe interceptado sobre a lista). Clicar numa linha é navegação suave: a rota
// `@painel/(.)[docId]` é interceptada e a lista continua montada por baixo — filtro (que vive na
// URL da lista), posição de rolagem e ordem intactos. Link direto e F5 não interceptam: o
// `@painel/default.tsx` devolve nada e `children` mostra a página inteira de sempre.
export default function DocumentosLayout({
  children,
  painel,
}: Readonly<{ children: React.ReactNode; painel: React.ReactNode }>) {
  return (
    <>
      {children}
      {painel}
    </>
  );
}
