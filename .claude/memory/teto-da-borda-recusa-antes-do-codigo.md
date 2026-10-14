---
name: teto-da-borda-recusa-antes-do-codigo
description: o 413 de 48 arquivos (~50 MB) veio da BORDA da Vercel: /api/intake nunca rodou, e nenhuma mensagem nossa podia aparecer — teto de 4,5 MB por requisição na Serverless Function
tipo: defeito
toca:
  - portal/src/lib/limite-de-envio.ts
  - portal/src/components/upload-form.tsx
prova: portal/scripts/verificar-limite-de-envio.mts
ancora: portal/src/lib/limite-de-envio.ts#TETO_DA_FUNCTION_BYTES
ancora_sha: f285efe531b1
---

# O teto da hospedagem recusa ANTES de o código rodar

**Medido em 13/09/2026.** O dono selecionou 48 arquivos (~50 MB) para o mandato da AMO. A tela
ofereceu "Enviar 48 arquivos", estimou 58 minutos de processamento, e o envio morreu em:

```
Failed to load resource: the server responded with a status of 413    /api/intake:1
```

A tela mostrou "Falha no envio (HTTP 413)" — a frase genérica, porque `json.error` veio vazio.

## Por que nenhuma correção dentro da rota resolveria

**`/api/intake` nunca rodou.** O 413 é da borda da Vercel, que recusa o corpo acima de ~4,5 MB
antes de invocar a Serverless Function. Nenhum `try/catch`, nenhuma validação e nenhuma mensagem
em português daquele arquivo tinham como aparecer. `bodySizeLimit` do Next cobre Server Action,
não Route Handler, e não muda a borda.

**A regra geral:** quando o erro chega com um número HTTP e SEM nenhuma mensagem nossa, a primeira
pergunta não é "que bug tem na rota" — é **"a rota chegou a rodar?"**. Borda de CDN, limite de
plataforma e proxy respondem por nós, e o repositório inteiro é invisível nesse ponto.

Sinal que confirmou: com 2 arquivos o n8n cobrou US$ 0,04 (lote rodou inteiro); com 48 não houve
execução nenhuma — ou seja, a requisição nunca saiu da Vercel.

## E "mandar em levas" era a correção errada

Foi o conselho que o `portal/README.md` deu por 6 semanas, e automatizá-lo teria sido pior:
**cada submissão ao Form abre UMA execução no n8n, e a cadência da IA é por execução**
(`IA Extrair` a cada 73 s, `IA Classificar` a cada 42 s — Tier 1 da OpenAI, 30.000 TPM). Treze
levas de 4 MB = treze execuções espaçando cada uma o seu próprio minuto contra um rate limit que
é da CONTA. O resultado já está medido no repositório (sessão 7 cont.⁸: 16 documentos, 16 erros
"Try spacing your requests out") e chega como lote pela metade, não como falha limpa. Some-se que
as quatro contas de `espera-do-lote.ts` são todas dimensionadas para UMA submissão.

A correção foi tirar os bytes do caminho da Vercel — navegador → Form do n8n, uma execução só
(`portal/src/lib/limite-de-envio.ts`, `api/intake/destino`).

## O preço, e por que ele é menor do que parece

O envio direto é cross-origin e o Form não manda cabeçalho de CORS: a resposta vem **opaca**
(`mode: "no-cors"`). Sabemos que a requisição partiu e se falhou no transporte — não sabemos o
status HTTP.

Isso custa pouco porque **o status do Form nunca foi prova de nada aqui**: ele responde 200 antes
de saber se o workflow terá o que processar, e foi assim que um upload "com sucesso" rendeu zero
documento e zero token (sessão 7 cont.¹²). A prova sempre foi o banco, e é o acompanhamento
(`/api/intake/status`) que a colhe. Por isso o caminho pela Function **continua existindo para o
lote pequeno**: ele é o único que devolve status real e mensagem em português, e jogar todo envio
no caminho direto trocaria um defeito raro por perda de diagnóstico todo dia.

## O que ficou em aberto (achado na revisão da mesma rodada)

`/api/intake/status` distingue lotes por `caso_nome` + `criado_em >= desde`, e por mais nada.
**Dois lotes no mesmo mandato ao mesmo tempo se confundem:** o segundo conta os documentos do
primeiro como seus e fecha com "Tudo pronto" sem que nenhum documento dele tenha chegado. A
correção de 13/09 encolheu a janela (o `desde` do envio direto passou a ser lido DEPOIS do upload,
não antes — num lote de 50 MB são minutos), mas o caso continua de pé. A solução é o pipeline
gravar o identificador do lote no `documento` e o status filtrar por ele.

## O bloqueio que criei virou o próximo incidente (mesmo dia, 13/09/2026)

A revisão adversarial da correção acima pediu para recusar o envio direto quando a descoberta do
nome do campo falhasse (`origem: "fallback"`), para não repetir o defeito da sessão 7 cont.¹²
(200 opaco, zero token, nome de campo errado). Isso foi implementado como um **bloqueio total**:
se `origem !== "html"` e a via era `direto`, a tela recusava enviar.

**Bloqueou o lote da AMO no mesmo dia.** Em produção, a descoberta (`fetch` do HTML do Form)
falhou — causa externa (instância do n8n, rede, ou HTML mudado; não investigada até o fim) — e o
único caminho que existe para um lote de 44 arquivos / 40,4 MB ficou **impossível de usar**, sem
alternativa nenhuma: pequeno demais para reduzir a levas sem reintroduzir o problema das múltiplas
execuções, grande demais para o encaminhamento.

**A causa do erro de julgamento:** tratar "não confirmado" como "inseguro o bastante para
bloquear", sem notar que o MESMO risco (nome de campo chutado) já era aceito sem bloqueio nenhum
no encaminhamento (`enviarPeloPortal`), que nunca checou `origem` — e nunca travou por causa
disso. A rede de segurança que já bastava ali — a detecção de parada do acompanhamento
(`vereditoDoLote`, `semPrimeiroSinalMs`), que declara "não chegou nada" sem inventar sucesso —
cobre o caminho direto do mesmo jeito, e não depende de a descoberta ter confirmado nada antes.

**A correção:** o bloqueio virou aviso (`origemIncerta`, mostrado junto do cartão de sucesso).
O envio prossegue; se o nome estiver errado, a parada denuncia em minutos — a mesma garantia que
o encaminhamento sempre teve.

**A lição, para a próxima vez que uma revisão sugerir "recusar por segurança":** perguntar sempre
se o caminho que já existe (e que ninguém questiona) aceita o mesmo risco sem bloquear — se
aceita, um bloqueio novo não está fechando um buraco, está criando um a mais.
