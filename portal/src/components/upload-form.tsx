"use client";

import { useEffect, useRef, useState } from "react";
import { explicarFalha, explicarParada, explicarLoteVazio, type FalhaExplicada } from "@/lib/falha-em-portugues";
import { ExcluirMandato } from "@/components/excluir-mandato";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import PainelOficiais from "@/components/painel-oficiais";
import PainelZip from "@/components/painel-zip";
import {
  detectarPeloArquivo, separarOficiais, destinoDe, gravarResumo, obterCasoId, desfechoEncerra,
  rotuloDaFamilia, type Deteccao, type ResultadoOficial, type ChamarRpc, type EntradaDoZip, type ProgressoDoZip,
} from "@/lib/envio-oficial";
import { lerNoNavegador } from "@/lib/ler-no-navegador";
import { lerZipNoNavegador } from "@/lib/ler-zip-no-navegador";
import {
  estimativaEmMinutos, janelaPara, semPrimeiroSinalMs, semProgressoMs, proximoIntervalo,
  INTERVALO_ACOMPANHAMENTO_MS,
} from "@/lib/espera-do-lote";
import {
  planejarEnvio, recusaPorArquivoGrande, avisoDeArquivoVazio, formatarBytes, type ViaDeEnvio,
} from "@/lib/limite-de-envio";

// O TAMANHO É FORMATADO POR `formatarBytes`, DA BIBLIOTECA, e por ela só.
// Havia dois formatadores nesta tela: o local escrevia "1.2 MB" com ponto e
// arredondava 0 byte para "1 KB"; o da biblioteca escreve "1,2 MB" e chama
// vazio de vazio. Os dois apareciam um embaixo do outro — e o arredondamento
// do zero era o que disfarçava de arquivo pequeno o arquivo que o envio
// descarta.

export default function UploadForm({
  mandatoInicial = "",
  travarMandato = false,
  casoId,
}: {
  mandatoInicial?: string;
  travarMandato?: boolean;
  casoId?: string;
}) {
  const router = useRouter();
  const inputRef = useRef<HTMLInputElement>(null);
  const [mandato, setMandato] = useState(mandatoInicial);
  const [arquivos, setArquivos] = useState<File[]>([]);
  const [arrastando, setArrastando] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<
    { mandato: string; arquivos: number; desde: string; via: ViaDeEnvio; origemIncerta: boolean } | null
  >(null);
  // POR QUAL CAMINHO ESTE ENVIO FOI (ver `enviarPeloPortal`/`enviarDireto`). A
  // tela precisa disto por uma razão só: sob envio direto a resposta é opaca, e
  // prometer "enviado com sucesso" com a mesma cara dos dois lados seria afirmar
  // uma confirmação que só um dos caminhos tem.
  const [via, setVia] = useState<ViaDeEnvio>("proxy");
  // OS ARQUIVOS QUE FICARAM DE FORA (0 byte). Estado próprio porque o aviso tem
  // de aparecer JUNTO do cartão de sucesso — `erro` não é renderizado ali, e um
  // descarte anunciado numa tela que ninguém mais vê é um descarte silencioso.
  const [descartados, setDescartados] = useState<string | null>(null);
  const [pronto, setPronto] = useState(false);
  // A FALHA DO PROCESSAMENTO. Sem este estado, o "aguarde" era eterno: a tela
  // deduzia progresso da ausência de documentos, e falha produz exatamente a
  // mesma ausência.
  const [falha, setFalha] = useState<{ etapa: string; mensagem: string } | null>(null);
  // O PROGRESSO, que a rota já devolvia e esta tela ignorava. Numa espera de 20
  // minutos, "12 de 38 organizados" e "nada aconteceu" são a diferença entre
  // esperar tranquilo e achar que travou.
  const [progresso, setProgresso] = useState<{ processados: number; esperados: number } | null>(null);
  const [demorou, setDemorou] = useState(false);
  // A PARADA SEM REGISTRO — o caso que a 0108 não alcança (ver SEM_PROGRESSO_MS).
  const [parada, setParada] = useState<{ processados: number; esperados: number } | null>(null);
  // O LOTE QUE TERMINOU VAZIO. Vem do status, e só existe depois de `pronto`.
  const [loteVazio, setLoteVazio] = useState<{ comLinhas: number; comFatos: number; documentos: number } | null>(null);
  // O ID DO MANDATO, que a rota já conhecia e não devolvia. Ele existe aqui por
  // UM motivo: um mandato que terminou sem nada dentro tem de poder ser
  // descartado da própria tela que o acusa — ver o bloco de explicação.
  const [casoIdDoLote, setCasoIdDoLote] = useState<string | null>(null);
  // O QUE O NAVEGADOR RECONHECEU PELOS BYTES (ver `lib/envio-oficial.ts`).
  // `undefined` = ainda examinando; `null` = o arquivo não pôde ser examinado
  // (segue o caminho de sempre, que dirá o que tiver a dizer).
  const [deteccoes, setDeteccoes] = useState<Record<string, Deteccao | null>>({});
  const promessasDeDeteccao = useRef(new Map<string, Promise<Deteccao | null>>());
  // O RESULTADO DE CADA ARQUIVO LIDO NO PRÓPRIO COMPUTADOR, da fila ao veredito do banco.
  const [oficiais, setOficiais] = useState<ResultadoOficial[]>([]);
  // O PACOTE (zip) ABERTO NO COMPUTADOR: onde ele está, e cada entrada que NÃO foi lida
  // como arquivo oficial (as oficiais entram em `oficiais`, acima).
  const [progressoZip, setProgressoZip] = useState<ProgressoDoZip | null>(null);
  const [entradasZip, setEntradasZip] = useState<EntradaDoZip[]>([]);

  const chaveDe = (f: File) => `${f.name}:${f.size}`;
  // Uma detecção por arquivo, memorizada: a lista a pede ao escolher e o envio a
  // pede de novo, e a segunda não pode reler os 64 KB nem correr contra a primeira.
  function deteccaoDe(f: File): Promise<Deteccao | null> {
    const chave = chaveDe(f);
    let p = promessasDeDeteccao.current.get(chave);
    if (!p) {
      p = detectarPeloArquivo(f).catch(() => null);
      promessasDeDeteccao.current.set(chave, p);
    }
    return p;
  }
  useEffect(() => {
    let cancelado = false;
    for (const f of arquivos) {
      const chave = chaveDe(f);
      // `void`: `deteccaoDe` nunca rejeita (o `.catch(() => null)` acima vira "não examinado").
      void deteccaoDe(f).then((d) => {
        if (!cancelado) setDeteccoes((atuais) => (chave in atuais ? atuais : { ...atuais, [chave]: d }));
      });
    }
    return () => { cancelado = true; };
    // `deteccaoDe` só usa a ref: não precisa estar nas dependências.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [arquivos]);

  // Acompanha silenciosamente, em segundo plano, até os arquivos enviados
  // estarem organizados — sem nomear nenhuma ferramenta ou etapa técnica.
  useEffect(() => {
    if (!sucesso || pronto || falha || parada) return;
    let cancelado = false;
    let intervalo = INTERVALO_ACOMPANHAMENTO_MS;
    let proximaEspera: ReturnType<typeof setTimeout> | undefined;
    const comecou = Date.now();
    const janela = janelaPara(sucesso.arquivos);
    // O RELÓGIO DA PARADA anda em paralelo ao da janela e mede outra coisa: a
    // janela pergunta "já esperei demais?", este pergunta "está andando?". Um
    // lote lento e vivo não pode acionar o segundo; um lote morto tem de acionar
    // antes de o primeiro estourar, senão a tela cala como sempre calou.
    let ultimoAvanco = Date.now();
    let ultimoVisto = -1;

    const verificar = async () => {
      if (cancelado) return;
      try {
        const params = new URLSearchParams({
          caso: sucesso.mandato,
          desde: sucesso.desde,
          esperados: String(sucesso.arquivos),
        });
        const resp = await fetch(`/api/intake/status?${params}`);
        const json = await resp.json().catch(() => ({}));
        // A falha ENCERRA o acompanhamento. Continuar perguntando depois dela
        // seria manter a espera de pé sobre um processo que não vai voltar.
        if (!cancelado && resp.ok && json.falha) {
          if (typeof json.casoId === "string") setCasoIdDoLote(json.casoId);
          setFalha({ etapa: json.falha.etapa, mensagem: json.falha.mensagem });
          return;
        }
        if (!cancelado && resp.ok && typeof json.processados === "number") {
          setProgresso({ processados: json.processados, esperados: json.esperados });
          // AVANÇO é qualquer um dos dois contadores subindo. Só o de extração
          // deixaria a fase inicial inteira — upload, orçamento, registro dos
          // documentos — parecer parada, e ela pode durar minutos num lote grande.
          const marca = (json.classificados ?? 0) + json.processados;
          if (marca > ultimoVisto) {
            ultimoVisto = marca;
            ultimoAvanco = Date.now();
          }
        }
        if (!cancelado && resp.ok && json.pronto) {
          setPronto(true);
          // `comLinhas` só vem no fim, e `null` significa "não consegui conferir"
          // — que NÃO é zero. Tratar os dois igual acusaria lote vazio por causa
          // de uma consulta que falhou, e um alarme falso desses ensina a
          // ignorar o alarme.
          if (typeof json.casoId === "string") setCasoIdDoLote(json.casoId);
          if (typeof json.comLinhas === "number") {
            setLoteVazio({
              comLinhas: json.comLinhas,
              // FATO CONTA COMO CONTEÚDO: um Parecer do Auditor rende zero
              // linhas e o alerta que vai ao comitê. Ver `explicarLoteVazio`.
              comFatos: typeof json.comFatos === "number" ? json.comFatos : 0,
              documentos: json.esperados,
            });
          }
          if (casoId) router.refresh();
          return;
        }
        // PAROU DE ANDAR: declara, em vez de continuar perguntando com cara de
        // calma. O limite é maior enquanto nada apareceu ainda — nessa fase o
        // silêncio é legítimo.
        if (!cancelado && resp.ok) {
          const parado = Date.now() - ultimoAvanco;
          // OS DOIS LIMITES SAEM DO TAMANHO DO LOTE (ver espera-do-lote.ts).
          // O do meio era FIXO em 5 minutos e declarou morto um lote de 190 que
          // estava vivo: entre a barreira que registra os documentos e a que
          // grava as linhas correm 25 minutos de chamadas de IA em que, por
          // construção, nada é escrito no banco.
          const limite = ultimoVisto > 0
            ? semProgressoMs(sucesso.arquivos)
            : semPrimeiroSinalMs(sucesso.arquivos);
          if (parado > limite) {
            setParada({ processados: json.processados ?? 0, esperados: json.esperados ?? sucesso.arquivos });
            return;
          }
        }
      } catch {
        // Falha pontual de rede não interrompe o acompanhamento — só a
        // próxima tentativa (ou o teto de tentativas) decide quando parar.
      }
      const decorrido = Date.now() - comecou;
      if (!cancelado && decorrido < janela) {
        intervalo = proximoIntervalo(intervalo, decorrido);
        proximaEspera = setTimeout(verificar, intervalo);
      } else if (!cancelado) {
        // DESISTIR EM SILÊNCIO É O DEFEITO. Parar de perguntar é legítimo (a aba
        // pode ficar aberta o dia todo); fingir que ainda se está esperando, não.
        setDemorou(true);
      }
    };

    proximaEspera = setTimeout(verificar, intervalo);
    return () => {
      cancelado = true;
      // Limpa o timer AGENDADO, seja ele o primeiro ou um reagendamento: agora
      // que o intervalo varia, `proximaEspera` é sempre o único pendente.
      clearTimeout(proximaEspera);
    };
  }, [sucesso, pronto, falha, parada, casoId, router]);

  function adicionarArquivos(lista: FileList | null) {
    if (!lista) return;
    const novos = Array.from(lista);
    setArquivos((atuais) => {
      // dedup por nome+tamanho para evitar duplicar ao soltar duas vezes
      const chave = (f: File) => `${f.name}:${f.size}`;
      const vistos = new Set(atuais.map(chave));
      return [...atuais, ...novos.filter((f) => !vistos.has(chave(f)))];
    });
  }

  function removerArquivo(idx: number) {
    setArquivos((atuais) => atuais.filter((_, i) => i !== idx));
  }

  // OS DOIS CAMINHOS DO ENVIO, e por que eles existem — o defeito inteiro está
  // em `src/lib/limite-de-envio.ts`, e aqui fica só o que a tela faz com ele.
  //
  //   `proxy`  — o de sempre: `POST /api/intake`, a Serverless Function
  //              encaminha e devolve o status REAL do n8n. É o caminho do lote
  //              pequeno, que é quase todo envio.
  //   `direto` — o navegador fala com o Form do n8n sem intermediário, porque
  //              acima de ~4 MB a Vercel recusa o corpo na BORDA (413) e a
  //              rota nunca chega a rodar.
  //
  // O QUE O CAMINHO DIRETO CUSTA, dito aqui porque é a parte que engana: a
  // resposta do n8n vem OPACA (é outra origem, e o Form não manda cabeçalho de
  // CORS). Sabemos que a requisição partiu e se ela falhou no TRANSPORTE — não
  // sabemos o status HTTP que voltou.
  //
  // Isso é menos do que parece. O status do Form nunca foi prova de nada neste
  // sistema, e está escrito no topo de `api/intake/route.ts` desde a sessão 7:
  // o webhook responde 200 ANTES de saber se o workflow terá o que processar, e
  // foi exatamente assim que um upload "com sucesso" rendeu zero documento e
  // zero token. A prova de que o lote entrou sempre foi o BANCO — e é o
  // acompanhamento logo acima que a colhe, documento a documento, e que declara
  // parada quando nada aparece.
  async function enviarPeloPortal(
    aEnviar: File[],
  ): Promise<{ mandato: string; arquivos: number; desde: string } | null> {
    const fd = new FormData();
    fd.append("mandato", mandato.trim());
    for (const a of aEnviar) fd.append("arquivos", a, a.name);
    const resp = await fetch("/api/intake", { method: "POST", body: fd });
    const json = await resp.json().catch(() => ({}));
    if (!resp.ok) {
      setErro(json.error ?? `Falha no envio (HTTP ${resp.status}).`);
      return null;
    }
    return {
      mandato: json.mandato ?? mandato.trim(),
      arquivos: json.arquivos ?? aEnviar.length,
      desde: json.desde ?? new Date().toISOString(),
    };
  }

  async function enviarDireto(
    destino: { url: string; campos: { mandato: string; arquivos: string }; agora: string },
    aEnviar: File[],
  ): Promise<{ mandato: string; arquivos: number; desde: string } | null> {
    const fd = new FormData();
    fd.append(destino.campos.mandato, mandato.trim());
    for (const a of aEnviar) fd.append(destino.campos.arquivos, a, a.name);
    try {
      // `no-cors` não é gambiarra nem afrouxamento: um POST `multipart/form-data`
      // é requisição SIMPLES (sem preflight), então ela é entregue igual — o que
      // o modo muda é só a leitura da resposta, que passa a ser opaca. Falha de
      // transporte (DNS, conexão recusada, TLS) continua REJEITANDO a promessa,
      // e é por isso que o `catch` abaixo ainda tem o que dizer.
      await fetch(destino.url, { method: "POST", body: fd, mode: "no-cors" });
    } catch (err) {
      setErro(
        `Não foi possível enviar os arquivos: ${(err as Error).message}. `
        + "Confira a conexão e tente de novo — nada foi processado.",
      );
      return null;
    }
    // O RELÓGIO É LIDO DE NOVO DEPOIS DO UPLOAD, e a janela do acompanhamento
    // encolhe do tamanho do upload.
    //
    // `destino.agora` é de ANTES — e num lote de 50 MB "antes" pode ser três
    // minutos atrás. Três minutos em que um OUTRO lote, ainda rodando no mesmo
    // mandato, grava documentos que este acompanhamento contaria como seus e
    // fecharia com "Tudo pronto" sem nenhum documento deste envio ter chegado.
    //
    // Ler depois é SEGURO porque o gatilho do Form só dispara quando a
    // requisição termina: nenhum documento deste lote pode ter sido gravado
    // antes deste instante — entre o disparo e o primeiro `documento` correm
    // ainda o upload ao Storage, a leitura do texto e a barreira da
    // classificação, minutos em que nada é escrito (ver `espera-do-lote.ts`).
    //
    // Se a leitura falhar, cai no `destino.agora`: janela mais larga é pior que
    // janela nenhuma, e "não sei que horas são" não pode cancelar um envio que
    // já aconteceu.
    let desde = destino.agora;
    try {
      const resp = await fetch("/api/intake/destino?apenas=agora");
      const json = await resp.json();
      if (resp.ok && typeof json.agora === "string") desde = json.agora;
    } catch {
      // segue com `destino.agora`
    }
    return { mandato: mandato.trim(), arquivos: aEnviar.length, desde };
  }

  // A LEITURA E A GRAVAÇÃO DOS ARQUIVOS OFICIAIS, um de cada vez.
  //
  // UM DE CADA VEZ porque cada leitura é CPU de uma thread (37,5 s para 10M de
  // linhas) e cada worker segura o seu heap: dois em paralelo disputam o mesmo
  // núcleo e dobram a memória sem terminar antes. O `caso_id` vem de
  // `obterCasoId` (o `fn_upsert_caso` do n8n, com o ator da tela).
  //
  // Devolve as chaves dos que ficaram SEM veredito do banco (falha de leitura,
  // de rede, exceção): eles continuam na lista para reenvio. Os que o banco
  // respondeu (completo, recusado, ausente, reenvio) saem dela — a resposta está
  // no painel, e mantê-los na lista faria o próximo "Enviar" reenviá-los.
  async function processarOficiais(lista: File[], casoIdConhecido: string): Promise<Set<string>> {
    const supabase = createClient();
    const rpc: ChamarRpc = (funcao, args) => supabase.rpc(funcao, args);
    const pendentes = new Set<string>();
    const atualizar = (chave: string, mudanca: Partial<ResultadoOficial>) =>
      setOficiais((rs) => rs.map((r) => (r.chave === chave ? { ...r, ...mudanca } : r)));

    for (const f of lista) {
      const chave = chaveDe(f);
      const det = (await deteccaoDe(f)) as Deteccao;
      atualizar(chave, { fase: "lendo", lidosBytes: 0, familia: det.familia ?? "", subtipo: det.subtipo });
      let lido;
      try {
        lido = await lerNoNavegador(f, (lidos) => atualizar(chave, { lidosBytes: lidos }));
      } catch (err) {
        atualizar(chave, { fase: "fim", erroDeLeitura: (err as Error).message });
        pendentes.add(chave);
        continue;
      }
      if (!lido.envelope.familia || lido.envelope.familia === "zip") {
        atualizar(chave, { fase: "fim", erroDeLeitura: "o leitor não reconheceu o arquivo como leiaute oficial" });
        pendentes.add(chave);
        continue;
      }
      atualizar(chave, { fase: "gravando", lidosBytes: f.size, envelope: lido.envelope, resumo: lido.resumo });
      const desfecho = await gravarResumo(rpc, casoIdConhecido, lido.envelope, lido.resumo,
        (gravacao) => atualizar(chave, { gravacao }));
      atualizar(chave, { fase: "fim", desfecho });
      if (!desfechoEncerra(desfecho)) pendentes.add(chave);
    }
    return pendentes;
  }

  // O PACOTE (zip), ABERTO NO COMPUTADOR — sem ir ao n8n (sessão 109).
  //
  // O zip não é lido inteiro: o worker o abre por posição e entrega UMA entrada de cada
  // vez. Cada entrada oficial é gravada como um arquivo avulso (`gravarResumo`, o MESMO
  // caminho); as demais voltam como `File` quando cabem no processamento, e são
  // listadas com o motivo quando não cabem.
  //
  // O QUE FAZ UM ZIP FICAR "PENDENTE" (continua na lista, para reenvio): o banco não
  // respondeu a uma entrada oficial (falha de rede/exceção), ou o pacote nem abriu.
  // Entrada recusada ou corrompida NÃO deixa o zip pendente — reenviar a recusaria de
  // novo — e aparece na lista com o motivo.
  //
  // E UM ZIP PENDENTE NÃO ENCAMINHA NADA AO N8N: o reenvio recomeçaria o pacote e
  // mandaria os mesmos arquivos comuns uma segunda vez. As entradas ficam "retidas",
  // com a frase dizendo isso.
  async function processarZip(
    zip: File,
    casoIdConhecido: string,
  ): Promise<{ pendente: boolean; paraN8n: File[] }> {
    const supabase = createClient();
    const rpc: ChamarRpc = (funcao, args) => supabase.rpc(funcao, args);
    const nomeZip = zip.name;
    const chaveZip = chaveDe(zip);
    const paraN8n: File[] = [];
    let pendente = false;
    let atual: string | null = null;
    let seq = 0;
    const atualizar = (chave: string, mudanca: Partial<ResultadoOficial>) =>
      setOficiais((rs) => rs.map((r) => (r.chave === chave ? { ...r, ...mudanca } : r)));
    const novaEntrada = (e: Omit<EntradaDoZip, "chave" | "zip">) =>
      setEntradasZip((l) => [...l, { chave: `${chaveZip}::${seq++}`, zip: nomeZip, ...e }]);
    const ir = (indice: number, total: number, nome: string) =>
      setProgressoZip({ zip: nomeZip, fase: "lendo", indice, total, nome });

    // Um reenvio do mesmo pacote começa do zero: o que ficou da tentativa anterior sai.
    setEntradasZip((l) => l.filter((x) => x.zip !== nomeZip));
    setOficiais((rs) => rs.filter((r) => !r.chave.startsWith(`${chaveZip}::`)));
    setProgressoZip({ zip: nomeZip, fase: "abrindo", indice: 0, total: 0, nome: "" });
    try {
      await lerZipNoNavegador(zip, async (ev) => {
        switch (ev.tipo) {
          case "oficial_inicio": {
            ir(ev.indice, ev.total, ev.nome);
            atual = `${chaveZip}::${ev.nome}`;
            const chave = atual;
            setOficiais((rs) => [
              ...rs.filter((r) => r.chave !== chave),
              {
                chave, nome: `${nomeZip} › ${ev.nome}`, bytes: ev.bytes, familia: ev.familia, subtipo: ev.subtipo,
                fase: "lendo", lidosBytes: 0,
              },
            ]);
            return;
          }
          case "progresso":
            if (atual) atualizar(atual, { lidosBytes: ev.lidos });
            return;
          case "oficial": {
            const chave = atual;
            atual = null;
            if (!chave) return;
            if (!ev.envelope.familia || ev.envelope.familia === "zip") {
              atualizar(chave, { fase: "fim", erroDeLeitura: "o leitor não reconheceu a entrada como leiaute oficial" });
              return;
            }
            atualizar(chave, { fase: "gravando", envelope: ev.envelope, resumo: ev.resumo });
            const desfecho = await gravarResumo(rpc, casoIdConhecido, ev.envelope, ev.resumo,
              (gravacao) => atualizar(chave, { gravacao }));
            atualizar(chave, { fase: "fim", desfecho });
            if (!desfechoEncerra(desfecho)) pendente = true;
            return;
          }
          case "nao_oficial":
            ir(ev.indice, ev.total, ev.nome);
            if (ev.arquivo) {
              paraN8n.push(ev.arquivo);
              novaEntrada({ nome: ev.nome, bytes: ev.bytes, situacao: "ao_n8n" });
            } else {
              novaEntrada({ nome: ev.nome, bytes: ev.bytes, situacao: ev.situacao ?? "nao_enviada", motivo: ev.motivo });
            }
            return;
          case "recusada": {
            if (ev.indice !== null && ev.total !== null) ir(ev.indice, ev.total, ev.nome);
            // Falha ao ler uma entrada oficial já aberta: a linha dela no painel dos arquivos lidos diz o motivo.
            if (atual && atual === `${chaveZip}::${ev.nome}`) {
              atualizar(atual, { fase: "fim", erroDeLeitura: ev.motivo });
              atual = null;
            }
            novaEntrada({ nome: ev.nome, bytes: null, situacao: "recusada", motivo: ev.motivo });
            return;
          }
          case "fim":
          case "erro":
            return;
        }
      });
      const fechado: Partial<ProgressoDoZip> = pendente
        ? { fase: "falhou", erro: "um arquivo oficial do pacote não teve a resposta do banco (veja a lista de arquivos lidos)" }
        : { fase: "fim" };
      setProgressoZip((p) => (p ? { ...p, ...fechado } : p));
    } catch (err) {
      pendente = true;
      setProgressoZip((p) => ({ zip: nomeZip, indice: p?.indice ?? 0, total: p?.total ?? 0, nome: p?.nome ?? "", fase: "falhou", erro: (err as Error).message }));
    }
    if (pendente) {
      const motivo = "o pacote não foi concluído (um arquivo oficial não foi gravado, ou a leitura parou); reenvie o pacote — ele recomeça e os arquivos oficiais já gravados são reconhecidos como reenvio";
      setEntradasZip((l) => l.map((x) => (x.zip === nomeZip && x.situacao === "ao_n8n" ? { ...x, situacao: "retida", motivo } : x)));
      return { pendente: true, paraN8n: [] };
    }
    return { pendente: false, paraN8n };
  }

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    if (!mandato.trim()) {
      setErro("Informe o nome do mandato.");
      return;
    }
    if (arquivos.length === 0) {
      setErro("Selecione ao menos um arquivo.");
      return;
    }
    // O ARQUIVO VAZIO SAI ANTES DA CONTA, e o analista fica sabendo.
    //
    // O encaminhamento sempre descartou `size === 0` no servidor e devolvia a
    // contagem JÁ FILTRADA — que vira o `esperados` do acompanhamento. O envio
    // direto não tem servidor no meio: sem isto, a tela esperaria 48 documentos
    // de um lote capaz de produzir 47, os contadores nunca fechariam, e 37,6
    // minutos depois a tela acusaria "o sistema parou" sobre um lote que
    // terminou tudo o que dava (ver `arquivosVazios`).
    const vazios = arquivos.filter((a) => a.size <= 0);
    const aEnviar = arquivos.filter((a) => a.size > 0);
    if (aEnviar.length === 0) {
      setErro(avisoDeArquivoVazio(vazios.map((a) => ({ nome: a.name, bytes: a.size }))));
      return;
    }

    // O ESTADO DO ENVIO ANTERIOR NÃO ATRAVESSA PARA ESTE. Sem isto, o cartão do
    // lote novo abria exibindo "48 de 48 organizados" do lote passado até o
    // primeiro polling, oito segundos depois — progresso afirmado sobre um lote
    // que ainda não começou.
    setProgresso(null);
    setDemorou(false);
    setDescartados(null);
    // `via` volta ao padrão até o plano decidir: sem isto, o envio pequeno que
    // segue um grande anunciava "direto para o processamento" durante o
    // round-trip ao destino, sobre um envio que vai pelo encaminhamento.
    setVia("proxy");
    setEnviando(true);
    try {
      // OS OFICIAIS SAEM DO LOTE ANTES DE QUALQUER COISA, e rodam ANTES do envio
      // ao n8n. Pelos bytes (`detectarFamilia`), nunca pela extensão. O que sobra
      // — PDF, imagem, planilha, zip, o que o navegador não conseguiu examinar —
      // segue EXATAMENTE como sempre: `aoN8n` é o antigo `aEnviar`.
      //
      // ANTES e não depois: o caso é criado aqui (se o mandato for novo) e o n8n o
      // encontra por nome. Na ordem inversa, os dois caminhos criariam o mesmo
      // mandato em paralelo e o `caso.nome` não é único (ver `obterCasoId`).
      const deteccaoDosArquivos = new Map<File, Deteccao | null>();
      await Promise.all(aEnviar.map(async (f) => { deteccaoDosArquivos.set(f, await deteccaoDe(f)); }));
      const { oficiais: aLerAqui, zips, aoN8n: aoN8nDireto } = separarOficiais(aEnviar, (f) => deteccaoDosArquivos.get(f));
      // O que vai ao n8n é o de sempre MAIS os arquivos comuns que couberem de dentro dos pacotes (zip).
      let aoN8n = aoN8nDireto;
      // Os vazios já foram avisados acima e nunca ficam na lista (o envio de sempre também os limpava).
      let restantes = arquivos.filter((a) => a.size > 0);
      if (aLerAqui.length > 0 || zips.length > 0) {
        let caso;
        try {
          caso = await obterCasoId(createClient(), mandato.trim(), casoId);
        } catch (err) {
          // Antes de ler e de enviar QUALQUER coisa: nada saiu, e a mensagem é a do banco.
          setErro((err as Error).message);
          return;
        }
        const chavesLidas = new Set([...aLerAqui, ...zips].map(chaveDe));
        setOficiais((rs) => [
          ...rs.filter((r) => !chavesLidas.has(r.chave)),
          ...aLerAqui.map((f): ResultadoOficial => {
            const d = deteccaoDosArquivos.get(f) as Deteccao;
            return {
              chave: chaveDe(f), nome: f.name, bytes: f.size, familia: d.familia ?? "", subtipo: d.subtipo,
              fase: "na_fila", lidosBytes: 0,
            };
          }),
        ]);
        const pendentes = await processarOficiais(aLerAqui, caso.id);
        // Os pacotes DEPOIS dos avulsos, um de cada vez (cada um é CPU de uma thread e o heap do seu worker).
        const doPacote: File[] = [];
        for (const z of zips) {
          const r = await processarZip(z, caso.id);
          if (r.pendente) pendentes.add(chaveDe(z)); else doPacote.push(...r.paraN8n);
        }
        aoN8n = [...aoN8nDireto, ...doPacote];
        // Sai da lista quem o banco respondeu; fica quem precisa de reenvio.
        restantes = restantes.filter((a) => !chavesLidas.has(chaveDe(a)) || pendentes.has(chaveDe(a)));
        // Já aqui, e não só no fim: se o envio ao n8n falhar logo abaixo, o próximo
        // "Enviar" não pode reenviar ao banco o que o banco já respondeu.
        setArquivos(restantes);
        if (casoId) router.refresh();
        if (aoN8n.length === 0) {
          // O aviso do arquivo vazio não pode morrer junto com a tela de sucesso, que aqui não existe.
          setDescartados(vazios.length > 0
            ? avisoDeArquivoVazio(vazios.map((a) => ({ nome: a.name, bytes: a.size })))
            : null);
          return;
        }
      }

      // O DESTINO VEM PRIMEIRO, e vem do servidor, nos DOIS caminhos. Ele
      // responde quatro coisas que a tela não pode adivinhar: se o upload está
      // configurado (503 com a frase de sempre), quais são os nomes REAIS dos
      // campos do Form, DE ONDE eles vieram, e que horas são no servidor.
      const respDestino = await fetch("/api/intake/destino");
      const destino = await respDestino.json().catch(() => ({}));
      if (!respDestino.ok) {
        setErro(destino.error ?? `Não foi possível preparar o envio (HTTP ${respDestino.status}).`);
        return;
      }
      // RESPOSTA 200 QUE NÃO É O DESTINO. Sessão expirada: o `proxy.ts` manda
      // para /login, o `fetch` segue o redirecionamento e entrega **HTML com
      // status 200** — `respDestino.ok` é verdadeiro e não há destino nenhum
      // dentro. Sem este guarda, o erro aparecia como um `TypeError` em inglês
      // vindo lá de dentro da conta do tamanho.
      if (typeof destino.url !== "string" || !destino.campos?.arquivos || !destino.campos?.mandato) {
        setErro("Sua sessão expirou ou o portal não respondeu. Atualize a página, entre de novo e reenvie — nada foi processado.");
        return;
      }
      // O DIAGNÓSTICO VAI PARA O CONSOLE, não para a tela do analista.
      //
      // ACHADO EM 13/09/2026: a descoberta de campo falhou em produção e não
      // havia NENHUM jeito de saber por quê — nem aqui, nem no servidor. Sem
      // isto, a próxima falha seria de novo muda. Fica no console (F12 →
      // Console), pela mesma razão de sempre: o texto que o analista lê não
      // pode citar termo técnico, mas quem for investigar precisa do motivo,
      // e "developer tools" é exatamente onde quem investiga já olha.
      if (destino.motivo) {
        console.warn(`[intake] descoberta de campo caiu no fallback: ${destino.motivo}`);
      }

      const plano = planejarEnvio(
        aoN8n.map((a) => ({ nome: a.name, bytes: a.size })),
        destino.campos,
        mandato.trim(),
      );
      // O ARQUIVO QUE NENHUM CAMINHO ACEITA é recusado ANTES de subir. Sob envio
      // direto ele seria recusado do outro lado, em silêncio, depois de o
      // analista esperar o upload inteiro.
      if (plano.acimaDoTetoPorArquivo.length > 0) {
        setErro(recusaPorArquivoGrande(plano.acimaDoTetoPorArquivo));
        return;
      }
      // NOME DE CAMPO CHUTADO NÃO BLOQUEIA MAIS O LOTE GRANDE.
      //
      // `origem: "fallback"` diz que a descoberta falhou e os nomes são os
      // padrões — bloquear aqui (versão anterior, 13/09/2026) travou o próprio
      // lote da AMO: a descoberta tropeçou em produção e o ÚNICO caminho para
      // um lote deste tamanho ficou impossível de usar, sem alternativa
      // nenhuma. O mesmo risco (nome errado, 200 opaco, zero token — sessão 7
      // cont.¹²) já era aceito sem bloqueio no encaminhamento, que nunca
      // checou `origem`. A rede de segurança que já bastava lá — a detecção de
      // parada do acompanhamento, que declara "não chegou nada" sem inventar
      // sucesso — cobre este caminho também, sem depender de a descoberta ter
      // confirmado o nome antes. Ver `.claude/memory/teto-da-borda-recusa-antes-do-codigo.md`.
      const origemIncerta = plano.via === "direto" && destino.origem === "fallback";
      setVia(plano.via);

      const enviado = plano.via === "proxy"
        ? await enviarPeloPortal(aoN8n)
        : await enviarDireto(destino, aoN8n);
      if (!enviado) return;

      setPronto(false);
      setSucesso({ ...enviado, via: plano.via, origemIncerta });
      setArquivos(restantes.filter((a) => !aoN8n.includes(a)));
      // O DESCARTE É NOTICIADO, e fica visível junto do cartão de sucesso: quem
      // selecionou o arquivo vazio precisa saber que ele não está no mandato —
      // senão vai procurá-lo lá depois.
      setDescartados(
        vazios.length > 0
          ? avisoDeArquivoVazio(vazios.map((a) => ({ nome: a.name, bytes: a.size })))
          : null,
      );
    } catch (err) {
      setErro((err as Error).message);
    } finally {
      setEnviando(false);
    }
  }

  // UM CARTÃO PARA AS TRÊS FORMAS DE NÃO TER DADO CERTO.
  //
  // Elas chegam por caminhos diferentes — falha registrada no banco, parada sem
  // registro nenhum, lote que terminou vazio — e para quem lê são a mesma
  // notícia: não terminou como devia, e isto é o que aconteceu. Três cartões
  // diferentes fariam o analista aprender três telas para uma informação só.
  //
  // A ORDEM DA LEITURA É A ORDEM DA PERGUNTA: o que aconteceu, o que fazer, e —
  // só se pedirem — o texto técnico. Ele continua ali porque sem ele quem for
  // ajudar começa perguntando "qual erro apareceu?"; mas fechado, porque quem
  // precisa dele não é quem está olhando a tela.
  const painelOficiais = (
    <>
      <PainelOficiais resultados={oficiais} />
      <PainelZip progresso={progressoZip} entradas={entradasZip} oficiais={oficiais} />
    </>
  );
  // O QUE VAI AO N8N, e o que o navegador lê. A tela decide pelos mesmos bytes que o envio.
  const naTela = (f: File) => {
    const d = deteccoes[chaveDe(f)];
    return d === undefined ? "examinando" as const : destinoDe(d);
  };

  const arquivosOficiaisNaTela = arquivos.filter((a) => naTela(a) === "oficial");
  const arquivosZipNaTela = arquivos.filter((a) => a.size > 0 && naTela(a) === "zip");
  // O pacote não conta aqui: o que sai dele ao processamento só se sabe depois de aberto.
  const arquivosAoN8nNaTela = arquivos.filter((a) => a.size > 0 && naTela(a) !== "oficial" && naTela(a) !== "zip");

  const explicacao: FalhaExplicada | null = falha
    ? explicarFalha(falha)
    : parada
      ? explicarParada(parada)
      : loteVazio
        ? explicarLoteVazio(loteVazio)
        : null;

  if (sucesso && explicacao) {
    const tecnico = falha
      ? `${falha.etapa ? `Etapa: ${falha.etapa}\n` : ""}${falha.mensagem}`
      : parada
        ? `Sem progresso por mais de ${Math.round(semProgressoMs(sucesso?.arquivos ?? 0) / 60000)} minutos. `
          + `Organizados: ${parada.processados} de ${parada.esperados}. Mandato: "${sucesso.mandato}". `
          + `Envio: ${new Date(sucesso.desde).toLocaleString("pt-BR")}.`
        : `Lote concluído com ${loteVazio?.comLinhas ?? 0} de ${loteVazio?.documentos ?? 0} documentos `
          + `com linhas extraídas. Mandato: "${sucesso.mandato}". `
          + `Envio: ${new Date(sucesso.desde).toLocaleString("pt-BR")}.`;

    return (
      <>
      {painelOficiais}
      <div className="rounded border border-risco-300 bg-risco-50 p-4 text-sm text-risco-900">
        <p className="text-xs font-semibold uppercase tracking-wide text-risco-700">
          O sistema parou por um problema técnico
        </p>
        <p className="mt-2 text-base font-medium">{explicacao.titulo}</p>
        <p className="mt-2 text-risco-800">{explicacao.explicacao}</p>

        <div className="mt-3 rounded border border-risco-200 bg-folha p-3">
          <p className="text-xs font-semibold uppercase tracking-wide text-risco-700">
            {explicacao.quemResolve === "voce" ? "O que você pode fazer" : "Quem resolve isto"}
          </p>
          <p className="mt-1 text-risco-900">{explicacao.oQueFazer}</p>
        </div>

        {/* FECHADO POR PADRÃO, e presente por escolha. A causa técnica é o que
            um desenvolvedor precisa e o que some quando a interface "simplifica"
            demais — mas ela não é a primeira coisa que o analista deve ler. */}
        <details className="mt-3">
          <summary className="cursor-pointer text-xs text-risco-700 hover:text-risco-900">
            Ver detalhes técnicos (para enviar a quem cuida do sistema)
          </summary>
          <p className="mt-2 whitespace-pre-wrap rounded border border-risco-200 bg-folha p-3 text-xs text-tinta-600">
            {tecnico}
          </p>
        </details>

        <div className="mt-3 flex gap-3">
          <button
            type="button"
            onClick={() => {
              setFalha(null); setParada(null); setLoteVazio(null); setSucesso(null);
              setProgresso(null); setDemorou(false); setDescartados(null); setOficiais([]);
            }}
            className="rounded bg-risco-700 px-3 py-1.5 text-xs font-medium text-papel hover:bg-risco-800"
          >
            Enviar de novo
          </button>
          <button
            type="button"
            onClick={() => router.push(casoId ? `/casos/${casoId}` : "/casos")}
            className="rounded border border-risco-300 px-3 py-1.5 text-xs font-medium text-risco-800 hover:bg-risco-100"
          >
            {casoId ? "Voltar ao mandato →" : "Ver mandatos →"}
          </button>

          {/* DESCARTAR O MANDATO QUE NÃO TROUXE NADA — na tela que o acusa.
              O mandato é criado no PRIMEIRO nó do fluxo, antes de qualquer
              leitura: ele é o recipiente em que todo o resto é gravado, e não
              existe "criar depois" sem inverter o pipeline inteiro. O que dá
              para garantir é o efeito prático — que ninguém fique com um
              mandato vazio na lista sem saber o que fazer com ele.
              Só aparece quando o lote terminou SEM CONTEÚDO NENHUM (nem linha
              nem fato); um lote incompleto tem dado dentro, e apagá-lo perderia
              o que deu certo. A confirmação é a mesma do resto do portal. */}
          {loteVazio && !falha && !parada && loteVazio.comLinhas === 0 && loteVazio.comFatos === 0
            && casoIdDoLote && (
            <ExcluirMandato casoId={casoIdDoLote} nome={sucesso.mandato} />
          )}
        </div>
      </div>
      </>
    );
  }

  if (sucesso) {
    return (
      <>
        {painelOficiais}
        <div className="rounded border border-ok-300 bg-ok-50 p-4 text-sm text-ok-900">
          <p className="font-medium">
            {sucesso.arquivos} arquivo(s) enviado(s) para o mandato “{sucesso.mandato}”.
          </p>
          {/* O RECIBO QUE O LOTE GRANDE NÃO TEM. Acima do teto da hospedagem os
              arquivos vão do navegador direto para o processamento, e essa
              resposta não é legível por esta tela (outra origem). Então "enviado"
              aqui é "a requisição partiu", e quem confirma que os documentos
              chegaram é o acompanhamento logo abaixo — que já sabe declarar
              parada se nada aparecer. Dizer isso custa uma linha; não dizer é
              exatamente o "sucesso na tela, nada no mandato" que este arquivo
              inteiro combate. */}
          {descartados && (
            <p className="mt-2 rounded border border-alerta-300 bg-alerta-50 p-2 text-xs text-alerta-900">
              {descartados}
            </p>
          )}
          {sucesso.via === "direto" && (
            <p className="mt-1 text-xs text-ok-800">
              Lote grande: os arquivos foram enviados sem passar por esta página, e por isso o
              recibo de entrega vem do acompanhamento abaixo — ele conta os documentos conforme
              chegam e avisa se nada chegar.
            </p>
          )}
          {/* O AVISO DA DESCOBERTA INCERTA. Só aparece quando o servidor não
              conseguiu confirmar os nomes dos campos com o processamento antes
              do envio (a descoberta tropeçou), e é exatamente o caso em que o
              acompanhamento abaixo é a ÚNICA prova de que o lote chegou —
              reforça, sem alarmar, o que o parágrafo acima já diz. */}
          {sucesso.origemIncerta && (
            <p className="mt-1 text-xs text-alerta-800">
              Não consegui confirmar com o processamento os nomes dos campos antes deste envio.
              Se nada aparecer no acompanhamento em alguns minutos, é esse o motivo — avise quem
              cuida do sistema.
            </p>
          )}
          {/* O TEMPO É PROPORCIONAL AO LOTE, e a tela diz isso antes de a pessoa
              se perguntar. Cada documento passa pela IA com espaçamento entre as
              chamadas (o limite de uso da conta obriga), então 38 arquivos são
              ~20 minutos — e quem não sabe disso lê a demora como travamento. */}
          <p className="mt-1 text-ok-800">
            Estamos organizando tudo com cuidado. São cerca de{" "}
            <strong>{estimativaEmMinutos(sucesso.arquivos)} minutos</strong>
            {" "}para {sucesso.arquivos} arquivo(s) — cada um é lido separadamente. Você pode aguardar
            aqui ou voltar mais tarde.
          </p>
          {progresso && progresso.processados > 0 && (
            <div className="mt-2">
              <div className="h-1.5 w-full overflow-hidden rounded bg-ok-200">
                <div
                  className="h-full bg-ok-600 transition-all"
                  style={{ width: `${Math.min(100, (progresso.processados / Math.max(1, progresso.esperados)) * 100)}%` }}
                />
              </div>
              <p className="mt-1 text-xs text-ok-800">
                {progresso.processados} de {progresso.esperados} organizados
              </p>
            </div>
          )}
          {demorou && (
            <p className="mt-2 rounded border border-alerta-300 bg-alerta-50 p-2 text-xs text-alerta-900">
              Está levando mais tempo que o previsto e paramos de acompanhar por aqui — o
              processamento pode continuar em segundo plano. Abra o mandato para ver o estado atual;
              se nada tiver chegado, acione o desenvolvedor do sistema.
            </p>
          )}
          <div className="mt-3 flex gap-3">
            {casoId ? (
              <button
                type="button"
                onClick={() => router.push(`/casos/${casoId}`)}
                className="rounded bg-ok-700 px-3 py-1.5 text-xs font-medium text-papel hover:bg-ok-800"
              >
                Voltar ao mandato →
              </button>
            ) : (
              <button
                type="button"
                onClick={() => router.push("/casos")}
                className="rounded bg-ok-700 px-3 py-1.5 text-xs font-medium text-papel hover:bg-ok-800"
              >
                Ver mandatos →
              </button>
            )}
            <button
              type="button"
              onClick={() => {
                setSucesso(null);
                setPronto(false);
                setProgresso(null);
                setDemorou(false);
                setDescartados(null);
                setOficiais([]);
              }}
              className="rounded border border-ok-300 px-3 py-1.5 text-xs font-medium text-ok-800 hover:bg-ok-100"
            >
              Enviar mais arquivos
            </button>
          </div>
        </div>

        {/* O MODAL DE SUCESSO SÓ APARECE QUANDO HOUVE SUCESSO.
            Ele era condicionado só a `pronto`, e `pronto` mede que o pipeline
            TENTOU ler cada arquivo — não que ele conseguiu, e não que a
            execução chegou ao fim. Foi assim que uma execução morta virou "Tudo
            pronto" na tela do dono em 27/08/2026. Agora, se há o que explicar
            (falha, parada ou lote sem conteúdo), a explicação é a tela — e ela
            já é renderizada acima, antes de chegar aqui. */}
        {pronto && !explicacao && (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-tinta-900/40 px-4">
            <div className="w-full max-w-sm rounded-lg bg-folha p-6 text-center shadow-xl">
              <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-ok-100 text-2xl">
                ✓
              </div>
              <h2 className="text-base font-semibold text-tinta-900">Tudo pronto</h2>
              <p className="mt-2 text-sm text-tinta-600">
                Seus documentos foram organizados e já estão disponíveis no mandato “{sucesso.mandato}”.
              </p>
              <div className="mt-5 flex justify-center gap-3">
                <button
                  type="button"
                  onClick={() => (casoId ? router.push(`/casos/${casoId}`) : router.push("/casos"))}
                  className="rounded bg-tinta-900 px-4 py-2 text-sm font-medium text-papel hover:bg-tinta-600"
                >
                  Ver mandato →
                </button>
                <button
                  type="button"
                  onClick={() => setPronto(false)}
                  className="rounded border border-tinta-200 px-4 py-2 text-sm font-medium text-tinta-600 hover:bg-tinta-50"
                >
                  Continuar aqui
                </button>
              </div>
            </div>
          </div>
        )}
      </>
    );
  }

  return (
    <form onSubmit={enviar} className="space-y-4">
      <div>
        <label className="mb-1 block text-sm font-medium text-tinta-600">Mandato</label>
        <input
          type="text"
          value={mandato}
          onChange={(e) => setMandato(e.target.value)}
          readOnly={travarMandato}
          placeholder="ex.: Reestruturação Grupo X"
          className={`w-full rounded border px-3 py-2 text-sm ${
            travarMandato ? "border-tinta-200 bg-tinta-100 text-tinta-600" : "border-tinta-200"
          }`}
        />
        <p className="mt-1 text-xs text-tinta-500">
          {travarMandato
            ? "Os arquivos entram neste mesmo mandato — somam ao checklist, à exportação e à checagem de dados já existentes."
            : "Use o MESMO nome para enviar arquivos em momentos diferentes e acumulá-los no mesmo mandato (mesmo checklist, mesma exportação, mesma reconciliação)."}
        </p>
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium text-tinta-600">Arquivos</label>
        <button
          type="button"
          // BOTÃO DE VERDADE, não `div` com `role="button"`. A versão anterior
          // reimplementava na mão o que o elemento nativo já faz — foco, Enter,
          // Espaço, anúncio do papel — e o Sonar cobra isso em `typescript:S6819`
          // com razão: a reimplementação cobre os teclados que alguém lembrou, e
          // o elemento nativo cobre os que ninguém lembrou (leitor de tela em
          // modo de navegação, controle por voz, teclado de celular). Some junto
          // o `onKeyDown` manual: Enter e Espaço passam a vir do navegador.
          onClick={() => inputRef.current?.click()}
          onDragOver={(e) => {
            e.preventDefault();
            setArrastando(true);
          }}
          onDragLeave={() => setArrastando(false)}
          onDrop={(e) => {
            e.preventDefault();
            setArrastando(false);
            adicionarArquivos(e.dataTransfer.files);
          }}
          className={`flex w-full cursor-pointer flex-col items-center justify-center rounded border-2 border-dashed px-4 py-8 text-center text-sm transition ${
            arrastando ? "border-tinta-500 bg-tinta-50" : "border-tinta-200"
          }`}
        >
          <span className="font-medium text-tinta-600">Arraste os arquivos aqui</span>
          <span className="text-tinta-500">ou clique para selecionar (PDF, imagens; vários de uma vez)</span>
        </button>
        {/* O input fica FORA do botão: `<input>` dentro de `<button>` é HTML
            inválido (conteúdo interativo aninhado), e o navegador pode reparar a
            árvore movendo o input para fora do botão sozinho — o que quebraria o
            `inputRef` de um jeito que só aparece em runtime. */}
        <input
          ref={inputRef}
          type="file"
          multiple
          className="hidden"
          onChange={(e) => adicionarArquivos(e.target.files)}
        />
      </div>

      {arquivos.length > 0 && (
        <ul className="divide-y divide-tinta-100 rounded border border-tinta-200 bg-folha text-sm">
          {arquivos.map((a, i) => (
            <li key={`${a.name}:${a.size}`} className="flex items-center justify-between px-3 py-2">
              <span className="truncate">
                {a.name} <span className="text-tinta-400">({formatarBytes(a.size)})</span>
                {naTela(a) === "oficial" && (
                  <span className="ml-2 rounded bg-ok-50 px-1.5 py-0.5 text-xs text-ok-800">
                    {rotuloDaFamilia(deteccoes[chaveDe(a)]!.familia ?? "", deteccoes[chaveDe(a)]!.subtipo)}
                    {" · "}lido no seu computador; só o resumo é enviado
                  </span>
                )}
                {naTela(a) === "zip" && (
                  <span className="ml-2 rounded bg-tinta-100 px-1.5 py-0.5 text-xs text-tinta-600">
                    pacote compactado · aberto no seu computador: os arquivos de leiaute oficial são lidos aqui
                    (só o resumo é enviado) e os demais, de até 15 MiB, seguem para o processamento
                  </span>
                )}
              </span>
              <button
                type="button"
                onClick={() => removerArquivo(i)}
                className="ml-3 text-xs text-tinta-500 underline hover:text-risco-700"
              >
                remover
              </button>
            </li>
          ))}
        </ul>
      )}

      {/* O TEMPO ESPERADO APARECE ANTES DE ENVIAR, e não só depois.
          Até aqui a estimativa só existia na tela de sucesso — ou seja, o
          analista descobria que o lote levaria vinte minutos DEPOIS de já ter
          mandado, quando a decisão de esperar ou voltar mais tarde já não era
          dele. Com 38 arquivos selecionados isso é a diferença entre planejar e
          ser surpreendido. */}
      {/* O TAMANHO DO LOTE, NA TELA, ANTES DE ENVIAR.
          A lista mostrava o tamanho de cada arquivo e nunca o do conjunto — e o
          conjunto é o que decide se o envio cabe no encaminhamento ou tem de ir
          direto. Num lote de 48, somar 48 números à mão não é opção.
          SÓ CONTA O QUE SOBE: o arquivo oficial é lido aqui e só o resumo sai,
          então o tamanho dele não entra no corpo do envio nem na estimativa de
          leitura pela IA (que é por arquivo enviado ao processamento). */}
      {arquivos.length > 0 && (
        <p className="rounded border border-tinta-200 bg-tinta-50 px-3 py-2 text-sm text-tinta-600">
          <strong className="text-tinta-800">{arquivos.length}</strong>{" "}
          {arquivos.length === 1 ? "arquivo" : "arquivos"} selecionado
          {arquivos.length === 1 ? "" : "s"}, somando{" "}
          <strong className="text-tinta-800">
            {formatarBytes(arquivos.reduce((s, a) => s + a.size, 0))}
          </strong>{"."}
          {arquivos.some((a) => naTela(a) === "oficial") && (
            <>
              {" "}Destes, <strong className="text-tinta-800">{arquivosOficiaisNaTela.length}</strong>{" "}
              {arquivosOficiaisNaTela.length === 1 ? "é arquivo" : "são arquivos"} de leiaute oficial,
              lido{arquivosOficiaisNaTela.length === 1 ? "" : "s"} no seu computador: só o resumo é
              enviado, e eles não contam no tamanho nem no tempo do envio.
            </>
          )}
        </p>
      )}

      {arquivosAoN8nNaTela.length > 0 && (
        <p className="rounded border border-tinta-200 bg-tinta-50 px-3 py-2 text-sm text-tinta-600">
          Tempo esperado de processamento:{" "}
          <strong className="text-tinta-800">
            ~{estimativaEmMinutos(arquivosAoN8nNaTela.length)}{" "}
            {estimativaEmMinutos(arquivosAoN8nNaTela.length) === 1 ? "minuto" : "minutos"}
          </strong>{" "}
          para {arquivosAoN8nNaTela.length} {arquivosAoN8nNaTela.length === 1 ? "arquivo" : "arquivos"}. Cada arquivo é
          lido separadamente pela IA, e as chamadas são espaçadas por exigência do limite de uso
          da conta. Depois que o envio terminar você pode fechar esta aba — o processamento continua
          sozinho.
        </p>
      )}

      {(arquivosOficiaisNaTela.length > 0 || arquivosZipNaTela.length > 0) && (
        <p className="rounded border border-tinta-200 bg-tinta-50 px-3 py-2 text-sm text-tinta-600">
          Os arquivos de leiaute oficial são lidos <strong className="text-tinta-800">no seu computador</strong>,
          antes de qualquer envio, e só o resumo é gravado. Um arquivo grande pode levar alguns minutos
          para ser lido (um SPED de 10 milhões de linhas levou cerca de 40 segundos num computador de
          teste): <strong className="text-tinta-800">mantenha esta aba aberta</strong> até o fim — se ela
          fechar, o arquivo fica sem gravar e é preciso reenviar.
          {arquivosZipNaTela.length > 0 && (
            <>
              {" "}Um pacote compactado (zip) é aberto aqui, sem ir inteiro para lugar nenhum: cada arquivo
              de leiaute oficial dentro dele é lido como se fosse avulso, e os demais seguem para o
              processamento se tiverem até 15 MiB. <strong className="text-tinta-800">Um pacote de vários
              gigabytes leva muitos minutos</strong>; a tela mostra a entrada em curso, e todo arquivo que
              ficar de fora aparece na lista com o motivo.
            </>
          )}
        </p>
      )}

      {painelOficiais}

      {descartados && (
        <p className="rounded border border-alerta-300 bg-alerta-50 p-2 text-xs text-alerta-900">{descartados}</p>
      )}

      {erro && (
        <p className="rounded border border-risco-300 bg-risco-50 px-3 py-2 text-sm text-risco-700">{erro}</p>
      )}

      {/* O QUE ACONTECE DURANTE O UPLOAD — e ele pode durar minutos.
          Subir 50 MB numa conexão doméstica não é instantâneo, e o botão
          "Enviando…" sozinho não distingue "está subindo" de "travou". O
          navegador não expõe progresso de upload num `fetch`, então a tela não
          inventa uma barra: diz o tamanho, diz que demora, e diz a única coisa
          que o analista pode fazer errado (fechar a aba ANTES de o envio
          terminar — depois dele, pode fechar à vontade). */}
      {enviando && arquivosAoN8nNaTela.length > 0 && (
        <p className="rounded border border-tinta-200 bg-tinta-50 px-3 py-2 text-sm text-tinta-600">
          Enviando {arquivosAoN8nNaTela.length} {arquivosAoN8nNaTela.length === 1 ? "arquivo" : "arquivos"} (
          {formatarBytes(arquivosAoN8nNaTela.reduce((s, a) => s + a.size, 0))})
          {via === "direto" ? " direto para o processamento" : ""}. Numa conexão doméstica isso
          pode levar alguns minutos — mantenha esta aba aberta até o envio terminar. Depois disso
          ela pode ser fechada: o processamento continua sozinho.
        </p>
      )}

      <button
        type="submit"
        disabled={enviando}
        className="btn-primario px-4 py-2"
      >
        {/* A ação primária da tela usa a cor primária do produto — este botão
            era grafite enquanto o resto do portal já era acento. E o rótulo
            conta os arquivos em vez do "(s)": com 38 selecionados, "Enviar 38
            arquivos" confirma o que vai acontecer. */}
        {enviando
          ? "Enviando…"
          : arquivos.length === 0
            ? "Enviar arquivos"
            : `Enviar ${arquivos.length} ${arquivos.length === 1 ? "arquivo" : "arquivos"}`}
      </button>
    </form>
  );
}
