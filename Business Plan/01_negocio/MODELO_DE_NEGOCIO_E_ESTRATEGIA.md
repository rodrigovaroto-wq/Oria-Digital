# Modelo de negócio, proposta de valor e estratégia comercial

**Fonte oficial** do negócio do Oria Digital (K5). O deck para o sócio investidor
([`Apresentações/Business Plan Oria Digital/`](../../Apresentações/Business%20Plan%20Oria%20Digital/)) é
**derivado** deste arquivo: quando um dado ou uma definição de negócio muda, muda aqui primeiro e o
deck é refeito depois. As decisões citadas estão no
[registro v0.1.6](../07_decisoes/oria_digital_decisoes_e_pendencias_v0.1.6.html).

## 1. Objetivo (OBJ)

Acelerar a reestruturação financeira num **ecossistema único**: diagnóstico mais rápido, confiável e
coerente com o cliente; dados atualizados e confiáveis; comparação da empresa com os seus benchmarks;
gatilhos para reduzir custo e dívida e aumentar receita e lucro em pouco tempo.

## 2. Problema e proposta de valor

- **Problema:** decisões de milhões são tomadas com números que ninguém conferiu. Montar a base à mão
  leva cerca de **3 meses** (experiência da Oria Partners; sem fonte externa) e consome caixa,
  credibilidade e tempo.
- **O que resolvemos:** a empresa sabe em poucos dias o que cortar e o que renegociar, e chega aos
  credores com credibilidade.
- **Diferencial:** cada linha da empresa contra o mercado, com a **prova de cada número** (documento,
  página, fonte externa). A IA faz o trabalho pesado; o especialista decide; nenhum número é inventado
  (B2, B4).
- **Como funciona, em 5 etapas:** capta → diagnostica → calcula → recomenda → entrega. O fluxo técnico
  completo é o [workflow v0.3.0](../02_workflow_e_arquitetura/oria_digital_workflow_v0.3.0.html).

## 3. Para quem

| Decisão | Definição |
|---|---|
| **Os dois lados da mesa** (A3) | Quem precisa se reestruturar (devedores) e quem precisa confiar nos números para emprestar, comprar ou renegociar (credores, compradores) |
| **Segmentos** (deck, slide 4) | Consultorias de reestruturação · assessores de M&A · bancos e credores · fundos de crédito |
| **Empresa separada** (A3) | Oria Digital e Oria Partners são empresas distintas. **A Partners é a primeira cliente piloto** |
| **Modelo de operação** (A4, A5) | Serviço completo, operado pela equipe do Oria Digital. O cliente envia documentos e acompanha; não opera. Autosserviço sem prazo |
| **Consultoria-cliente** (L4) | Vê os mandatos dos clientes dela, sem acesso cruzado entre consultorias |
| **Primeiro cliente além da Partners** (A6) | **Em aberto.** Hipótese: empresas que precisam de reestruturação rápida; depois consultorias, assessorias, FIDCs e bancos |

## 4. Modelo de cobrança (J1, J2)

"O que vendemos" (texto do dono): *"Uma plataforma integrada e auditada, operada pela nossa equipe. O
cliente envia os documentos e acompanha tudo em um lugar só: base conferida, modelo financeiro, dossiê
e alertas com suporte direto."*

| Receita | Destaque (texto literal do slide 8) | Descrição |
|---|---|---|
| **Diagnóstico por mandato** | Receita de entrada · por mandato | Base conferida, modelo financeiro, dossiê e apresentação aos credores |
| **Acompanhamento contínuo** | Mensal recorrente · por contrato | Empresas em pós-reestruturação e carteiras de credores (G1, G2) |
| **Plataforma por usuário** | Licença de uso · por perfil de acesso | Empresas, credores e fundos acompanham seus mandatos e carteiras |
| **Bônus por resultado** | Variável · complemento da receita | Mediante contrato, atrelado ao plano aprovado |

- **Regras de cobrança (J1):** a licença por usuário vem mais adiante; o bônus por resultado é só opcional, nunca a base.
- **Valores:** definidos **depois do piloto**, com custo de IA, horas de analista e prazo medidos em
  cada mandato (J2, J6). O deck mostra só o modelo, sem valores.
- **Projeção:** [`MODELO_DE_PROJECAO.md`](MODELO_DE_PROJECAO.md), com as premissas em branco.
- **Referências de mercado** (pesquisa da Fase 1, [§5](../09_pesquisa/SINTESE_DA_PESQUISA_FASE1.md)):
  cobrança híbrida predomina em produtos de IA; concorrentes cobram por assento (Hebbia ~US$ 10 mil/ano,
  AlphaSense ~US$ 18 mil, Rogo ~US$ 3,3 mil, fontes secundárias); QoE nos EUA US$ 15–150 mil por
  trabalho de 30–45 dias.

## 5. O que o cliente ganha (exemplo ilustrativo do deck, slide 7)

Empresa com R$ 500 mi de dívida e R$ 200 mi de custos operacionais por ano. **É ilustrativo**, e o deck
diz isso duas vezes.

| Alavanca | Conta | Natureza |
|---|---|---|
| Juro acima do mercado | 2 p.p. × R$ 500 mi = **R$ 10 mi / ano** | Recorrente |
| Despesa acima do setor | 10% × R$ 200 mi = **R$ 20 mi / ano** | Recorrente |
| Crédito tributário | **R$ 20 mi**, recuperados uma vez e usados para amortizar dívida | Único (no gráfico: barra verde, sem "/ ano") |

## 6. Mercado: dados e fontes

Reconferidos na fonte primária em 19/11/2026 (J3). **Todo número externo novo passa pela mesma
reconferência, com o recorte certo, antes de entrar no deck.**

| Slide | Dado | Fonte e recorte | Situação |
|---|---|---|---|
| 2 | **R$ 244,4 bi** em dívidas, **9,3 milhões de empresas inadimplentes**: recorde | Serasa Experian, "Novo recorde: inadimplência das empresas chegou a 9,3 milhões em agosto", 20/10/2026 (dado de ago/2026) | Conferido. Substituiu os "R$ 18,9 bi do OBRE", sem fonte primária |
| 2, 4 | "3 meses" para montar os números à mão | Experiência da Oria Partners | Sem fonte externa |
| 4 | **2.466 empresas pediram recuperação judicial** em 2025 (977 processos) | Serasa Experian, 07/04/2026 | Conferido. São pedidos do ano, não o estoque. No 1º semestre de 2026 os pedidos caíram (435 × 509, pesquisa da Fase 1) |
| 4 | **1.581 transações de M&A** em 2025 | KPMG, Pesquisa de Fusões e Aquisições 2025 – 4º trimestre (ano inteiro) | Conferido. Rótulo corrigido de "KPMG 4T25" para "KPMG (2025)" |
| 4 | **R$ 2,8 tri** de crédito a pessoas jurídicas em set/2026 | Banco Central, Estatísticas Monetárias e de Crédito, 29/10/2026 | Conferido |
| 4 | **R$ 56 bi de captação líquida** em FIDCs em 2026 (R$ 56,1 bi de jan a out) | Anbima, "Fundos registram saída líquida de R$ 39,4 bilhões em outubro", 10/11/2026 | Conferido. É captação líquida, não ofertas (ofertas de FIDC: R$ 87,8 bi de jan a set/2026) |
| 5 | "mais de 30 fontes" | O slide 6 mostra só as principais | Mantido por decisão do dono. **Ponto não fechado:** ver pendências |

## 7. Concorrência e posicionamento

Da pesquisa da Fase 1 (§2 e §5): o concorrente mais próximo é a Keye (YC, diligência de private equity).
**Não foi encontrado** concorrente com diagnóstico de reestruturação brasileiro usando fontes oficiais e
Excel em fórmula. Vale copiar a rastreabilidade célula → página (DataSnipper) e a grade de perguntas
sobre contratos (Hebbia).

## 8. Estratégia comercial e o pedido ao sócio

- **Sequência** (deck, slide 10; K2, sem prazo em meses): hoje, método validado na Oria Partners e
  sistema em construção → **piloto com a Partners**, medindo dias, horas e achados → primeiros clientes
  além da Partners e início da expansão.
- **Prova do valor:** o piloto mede, por mandato, dias, horas de analista, custo de IA e de dados,
  erros por etapa e agente, e achados em R$ (J6). É essa medição que define preço e argumento comercial.
- **O pedido ao sócio** (J5), em quatro pilares: direção estratégica e rede (consultorias, fundos,
  bancos); time (engenharia, IA e um analista financeiro que revisa cada diagnóstico); infraestrutura
  segura (orçamento do estudo de infraestrutura); banco de dados contínuo. Parceria **com
  participação**; a contrapartida é negociada fora do deck.
- **Marca** (L3): própria, com identidade derivada da Oria Partners. Ainda não desenhada.

## 9. Riscos de negócio

Responsabilidade civil (teto contratual), seguro de erros e omissões, dependência de provedor de IA e
canibalização entre Oria Digital e Oria Partners (pesquisa da Fase 1, §5). A lista viva de riscos está
em `08_pendencias_e_riscos/PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md`.
