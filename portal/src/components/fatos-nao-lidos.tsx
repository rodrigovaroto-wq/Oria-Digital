// O bloco "O que os documentos dizem" quando a leitura dos fatos FALHOU (não quando não há fato).
// Sem ele, a seção sumia e um mandato com covenant rompido "crítico" ficava com a mesma cara de
// "o documento não diz nada" (regra 7). Diz o motivo e o EFEITO. Componente sem dados nem rede, para
// a suíte renderizá-lo.
export function FatosNaoLidos() {
  return (
    <section aria-live="polite" className="carta p-4 text-sm text-alerta-900">
      <p className="font-semibold">Fatos dos documentos não lidos</p>
      <p className="mt-1 text-xs">
        Não foi possível ler os fatos declarados nos documentos agora: contingências, partes
        relacionadas e eventos subsequentes podem existir e não estão listados aqui. Recarregue a
        página; se persistir, avise o administrador do sistema.
      </p>
    </section>
  );
}
