import { Revelar } from "@/components/revelar";
import { Bloco } from "@/components/esqueleto";
import {
  AndamentoDoMandato, EquipeDoMandatoComPapel, FatosDoMandato, IndicadoresDoMandato, KitBasicoDoMandato, PortaoDoMandato,
  ProximoPassoDoMandato,
} from "./visao-blocos";

// A VISÃO GERAL DO MANDATO, por streaming (item 2 do plano do dono). Cabeçalho e abas moram no
// `layout.tsx` do mandato e saem primeiro; esta página NÃO lê nada. Ela devolve cinco blocos, cada um
// com a sua consulta num `<Suspense>` e um esqueleto do tamanho final (`visao-blocos.tsx`; as leituras
// compartilhadas e o porquê da ordem delas, em `visao-dados.ts`).
//
// ESQUELETOS: alturas MEDIDAS na tela do mandato de 115 documentos (1440 px, next start): Próximo
// passo 90 px, indicadores 96 px, Portão 2 102 px, cada fato 146 px (este mandato tem 11, o esqueleto
// mostra 2: eles ficam abaixo da dobra e só empurram a Equipe), Equipe 125 px.
export default async function CasoDashboardPage({
  params,
}: Readonly<{
  params: Promise<{ id: string }>;
}>) {
  const { id } = await params;
  return (
    <div className="space-y-6">
      <Revelar rotulo="Carregando o próximo passo…" esqueleto={<EsqueletoDoProximoPasso />}>
        <ProximoPassoDoMandato id={id} />
      </Revelar>
      <Revelar rotulo="Carregando os indicadores…" esqueleto={<EsqueletoDosIndicadoresDoMandato />}>
        <IndicadoresDoMandato id={id} />
      </Revelar>
      <div className="grid items-start gap-5 lg:grid-cols-2">
        <Revelar rotulo="Carregando o Kit Básico…" className="min-w-0" esqueleto={<Bloco className="h-[212px] w-full rounded-[10px]" />}>
          <KitBasicoDoMandato id={id} />
        </Revelar>
        <Revelar rotulo="Carregando o andamento da leitura…" className="min-w-0" esqueleto={<Bloco className="h-[150px] w-full rounded-[10px]" />}>
          <AndamentoDoMandato id={id} />
        </Revelar>
      </div>
      <Revelar rotulo="Carregando a avaliação de aprovação…" esqueleto={<Bloco className="h-[102px] w-full" />}>
        <PortaoDoMandato id={id} />
      </Revelar>
      <Revelar rotulo="Carregando o que os documentos dizem…" esqueleto={<EsqueletoDosFatos />}>
        <FatosDoMandato id={id} />
      </Revelar>
      <Revelar rotulo="Carregando a equipe…" esqueleto={<EsqueletoDaEquipe />}>
        <EquipeDoMandatoComPapel id={id} />
      </Revelar>
    </div>
  );
}

function EsqueletoDoProximoPasso() {
  return (
    <div className="carta flex flex-wrap items-center justify-between gap-3 px-4 py-3" style={{ minHeight: 90 }}>
      <div className="min-w-0 space-y-2">
        <Bloco className="h-3 w-24" />
        <Bloco className="h-5 w-72 max-w-full" />
        <Bloco className="h-4 w-96 max-w-full" />
      </div>
      <Bloco className="h-8 w-32" />
    </div>
  );
}

function EsqueletoDosIndicadoresDoMandato() {
  return (
    <div className="space-y-2">
    <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
      {[0, 1, 2, 3].map((i) => (
        <div key={i} className="carta px-[18px] py-4" style={{ minHeight: 104 }}>
          <Bloco className="h-8 w-14" />
          <Bloco className="mt-2 h-4 w-32" />
        </div>
      ))}
    </div>
    <Bloco className="h-4 w-80 max-w-full" />
    </div>
  );
}

function EsqueletoDosFatos() {
  return (
    <div>
      <div className="mb-2 flex items-baseline justify-between gap-3">
        <h2 className="titulo-secao">O que os documentos dizem</h2>
        <Bloco className="h-4 w-36" />
      </div>
      <div className="space-y-2">
        {[0, 1].map((i) => <Bloco key={i} className="h-[146px] w-full rounded-lg" />)}
      </div>
    </div>
  );
}

function EsqueletoDaEquipe() {
  return (
    <div className="space-y-3" style={{ minHeight: 125 }}>
      <h2 className="titulo-secao">Equipe do mandato</h2>
      <Bloco className="h-4 w-80 max-w-full" />
      <Bloco className="h-8 w-full max-w-md" />
    </div>
  );
}
