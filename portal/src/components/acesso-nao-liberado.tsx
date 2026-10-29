// A TELA ÚNICA DE QUEM NÃO TEM PAPEL (0216: "usuário criado depois nasce SEM PAPEL e não vê nada").
// Com a RLS por mandato toda lista volta VAZIA para essa pessoa — e "Nenhum mandato", "Nada encontrado"
// e "Nenhum aviso" seriam afirmações falsas sobre a mesa. Esta tela ocupa o lugar de todas elas.
export function AcessoNaoLiberado({ email }: Readonly<{ email: string }>) {
  return (
    <div className="mx-auto max-w-xl py-12 text-center">
      <h1 className="font-titulo text-2xl font-medium text-tinta-900">Seu acesso ainda não foi liberado</h1>
      <p className="mt-2 text-sm text-tinta-600">
        {email ? <>Você entrou como <strong className="font-medium text-tinta-800">{email}</strong>, mas </> : "Você entrou, mas "}
        ainda não recebeu um papel no portal. Peça a um Sócio para liberar o seu acesso; depois é só
        recarregar esta página.
      </p>
      <p className="mt-4 text-xs text-tinta-500">
        Isto não significa que não há mandatos: a lista fica oculta até o acesso ser liberado.
      </p>
    </div>
  );
}
