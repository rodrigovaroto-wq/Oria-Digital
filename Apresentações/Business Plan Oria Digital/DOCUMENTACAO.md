# Business Plan Oria Digital: documentação da versão em vigor (v2)

Este documento reúne o que é preciso para entender, apresentar, manter ou refazer o deck `Business_Plan_Oria_Digital.pptx` (**v2**, 14 slides, 16:9, 13,33" × 7,5"). **Esta é a versão em vigor.** Ela substituiu a v1 (13 slides, PR #301) em 19/11/2026, depois de três rodadas de revisão do dono. A v1 fica no histórico do git; os comparativos e os scripts que produziram a v2 estão em `Business Plan/_trabalho_fase3/`.

Base das mudanças: o registro de decisões **v0.1.3** (`Business Plan/_trabalho_fase1/registro_de_decisoes/`), em especial A3, B1, J1–J5 e K2.

## 1. Para quem e para quê

| Item | Definição |
|---|---|
| Público | Um potencial **sócio investidor** |
| Formato | **Ao vivo**, conduzido pelo dono. As notas do apresentador sustentam a fala |
| O que pedimos | Parceria estratégica, **com participação**, em quatro pilares: direção estratégica e rede (consultorias, fundos, bancos); time com engenharia e um analista financeiro que revisa cada diagnóstico; infraestrutura segura; banco de dados contínuo. A contrapartida é negociada fora do deck (J5) |
| Prazo | **Sem prazo em meses no deck** (K2: plano sem calendário). A linha do tempo diz: hoje → piloto com a Oria Partners → depois, primeiros clientes além da Partners |
| Mensagem central | O método já funciona na Oria Partners, que é empresa separada e a primeira cliente (A3). O piloto mede dias, horas e achados |

## 2. Estrutura (14 slides)

| # | Seção | Título | Função na narrativa |
|---|---|---|---|
| 1 | Capa | Oria Digital: visão 360° da empresa em poucos dias, não em meses | Promessa |
| 2 | 1 · O problema | Decisões de milhões são tomadas com números que ninguém conferiu | Dor e tamanho do que está em jogo |
| 3 | 2 · As consequências | O trabalho manual custa tempo, credibilidade e dinheiro | 4 dores, com a dor resolvida em cada uma |
| 4 | 3 · O negócio e para quem | Do caos de documentos à decisão em poucos dias | O que resolvemos, diferencial, 4 clientes e o tamanho de cada mercado |
| 5 | 4 · Como funciona | Do documento ao diagnóstico, com a prova de cada número | 5 etapas e o que cada uma muda para o cliente |
| 6 | 5 · Os dados que ele captura | Dados da empresa e do mercado, cruzados em uma base única | Fontes micro e macro, e o que o cruzamento revela |
| 7 | 6 · O que o cliente ganha | Menos custo desnecessário, mais dívida amortizada | Exemplo ilustrativo em R$ |
| 8 | 7 · O modelo de negócio | Duas receitas: o diagnóstico por mandato e o acompanhamento | **Novo na v2.** O que vendemos, para quem e as quatro receitas, sem valores (J1, J2) |
| 9 | 8 · Estratégia operacional com IA | Onze agentes de IA dividem o diagnóstico, e o Especialista Oria decide | **Refeito na v2.** Árvore: Orquestrador → 8 especialistas, cada um com uma descrição; Auditor e Autoaprimoramento leem o resultado de todos (B1) |
| 10 | 9 · Para levar adiante | Quatro pilares levam o Oria Digital do método validado ao mercado | Linha do tempo (Hoje → Próximo marco → Em 3 a 6 meses) e "O QUE BUSCAMOS". O prazo "Em 3 a 6 meses" foi recolocado pelo dono na v4 (21/11) |
| 11 | Anexo 1 | 6 blocos e 31 frentes de diligência | Mapa da diligência |
| 12–14 | Anexo 2 (1/3 a 3/3) | Blocos 1–2, 3–4 e 5–6 | Cada frente com a área de impacto e a alavanca de valor |

## 3. Dados e fontes (reconferidos na fonte primária em 19/11/2026)

| Slide | Dado | Fonte e recorte | Situação |
|---|---|---|---|
| 2 | **R$ 244,4 bi** em dívidas, com **9,3 milhões de empresas inadimplentes**: recorde | Serasa Experian, "Novo recorde: inadimplência das empresas chegou a 9,3 milhões em agosto", 20/10/2026 (dado de ago/2026) | **Conferido na fonte**. Substituiu os "R$ 18,9 bi do OBRE", que não foram encontrados em fonte primária |
| 2, 4 | "3 meses" para montar os números à mão | Experiência da Oria Partners | Sem fonte externa |
| 4 | 2.466 empresas **pediram recuperação judicial** em 2025 (977 processos) | Serasa Experian, 07/04/2026 | **Conferido na fonte**. Recorte corrigido: são pedidos do ano, não o estoque "em recuperação" |
| 4 | 1.581 transações de M&A em 2025 | KPMG, Pesquisa de Fusões e Aquisições 2025 – 4º trimestre (dado do **ano inteiro**) | **Conferido na fonte**. Rótulo corrigido de "KPMG 4T25" para "KPMG (2025)" |
| 4 | R$ 2,8 tri de crédito a pessoas jurídicas em set/2026 | Banco Central, Estatísticas Monetárias e de Crédito, 29/10/2026 | **Conferido na fonte** |
| 4 | R$ 56 bi de **captação líquida** em FIDCs em 2026 (R$ 56,1 bi de jan a out/2026) | Anbima, "Fundos registram saída líquida de R$ 39,4 bilhões em outubro", 10/11/2026 | **Conferido na fonte**. Recorte explicitado: é captação líquida, não ofertas (ofertas de FIDC: R$ 87,8 bi de jan a set/2026) |
| 5 | "mais de 30 fontes" | O slide 6 mostra só as principais | Mantido por decisão do dono |

**Exemplo do slide 7.** É ilustrativo, e o slide diz isso duas vezes. A empresa tem R$ 500 mi de dívida e R$ 200 mi de custos operacionais por ano.

| Alavanca | Conta | Natureza |
|---|---|---|
| Juro acima do mercado | 2 p.p. × R$ 500 mi = **R$ 10 mi / ano** | Recorrente |
| Despesa acima do setor | 10% × R$ 200 mi = **R$ 20 mi / ano** | Recorrente |
| Crédito tributário | **R$ 20 mi**, recuperados uma vez e usados para amortizar dívida | Único (barra verde, sem "/ ano") |

**Anexos.** As contagens dos títulos batem com os selos de cada frente: slide 11, 3 + 6 + 8 + 7 + 4 + 3 = 31 frentes; slide 12, 5 com efeito no EBITDA; slide 13, 10 em risco e 10 em caixa; slide 14, 6 em risco.

## 4. Slide 8: modelo de negócio (sem valores)

| Receita | Destaque | Descrição |
|---|---|---|
| Diagnóstico por mandato | Receita de entrada · por mandato | Base conferida, modelo financeiro, dossiê e apresentação aos credores |
| Acompanhamento contínuo | Mensal recorrente · por contrato | Empresas em pós-reestruturação e carteiras de credores |
| Plataforma por usuário | Licença de uso · por perfil de acesso | Empresas, credores e fundos acompanham seus mandatos e carteiras |
| Bônus por resultado | Variável · complemento da receita | Mediante contrato, atrelado ao plano aprovado |

"O que vendemos" (texto do dono): *"Uma plataforma integrada e auditada, operada pela nossa equipe. O cliente envia os documentos e acompanha tudo em um lugar só: base conferida, modelo financeiro, dossiê e alertas com suporte direto."*

Os **valores** saem do piloto, quando custo de IA, horas de analista e prazo forem medidos (J2, J6). O modelo de projeção com premissas em branco é documentação interna, não slide.

## 5. Slide 9: os agentes e o status real (só nesta documentação)

O slide **não mostra status** (J4): mostra o catálogo de 11 agentes (B1) e o que cada um faz. **Nenhum agente existe hoje como agente**; o que existe são módulos do sistema que a v1 transforma em agentes, começando pelo piloto (K6). Use esta tabela na conversa e atualize-a quando o plano mudar.

| Agente | O que faz (texto do slide) | Base que existe hoje no sistema | No piloto (K6)? |
|---|---|---|---|
| Captador | Lê os documentos e busca dados na Receita e nos bancos | Leitura de 4 formatos, duplicata por fingerprint, Kit do mandato (0300/0301). Captação externa (SPED, Registrato, OFX) **não existe** | Sim (extração + captação externa) |
| Conferidor | Cruza a contabilidade com fontes externas e aponta divergências | Conferências de balanço, caixa e DRE (0009, 0015, 0105, 0133); mútuos (0117, 0124). Cruzamento com fontes externas **não existe** | Sim |
| Mercado | Compara a empresa e os juros com o setor e o mercado | Premissas de IPCA e Selic do Focus no export. Juro por contrato e despesas vs. setor **não existem** | Sim |
| Risco | Mapeia processos, protestos e dívida ativa antes da crise | Dossiê de processos e notícias planejado no MVP; scorecard só como estrutura | Não (dossiê de processos entra no piloto como entrega) |
| Caixa | Mostra até onde o caixa aguenta, semana a semana | Capital de giro (NCG e ciclo) e aging conciliado (0274). 13 semanas **não existe** | Sim |
| Dívida | Mapeia a dívida e mede a capacidade de pagamento | Mapa da dívida e ND/EBITDA em fórmula. Covenants e waterfall **não existem** | Sim |
| Estrategista | Propõe cortes, renegociação e propostas aos credores | Plano em 3 cenários (Base, Cliente, Stress). Simulação de propostas **não existe** | Não |
| Entregas | Monta modelo, dossiê e apresentação, com a prova | Excel do comitê com 14 abas em fórmula; base de dados exportável. Rastreabilidade número → página **não existe** | Excel + PDF no piloto |
| Supervisor / Orquestrador | Coordena os agentes e media divergências | **Não existe** | Sim |
| Auditor | Revisa o trabalho de todos os agentes | **Não existe** (o equivalente hoje são as conferências em SQL e o Portão 2) | Sim |
| Autoaprimoramento | Propõe melhorias a partir dos erros | **Não existe** | Não (entra depois do piloto, F1) |

## 6. Identidade visual

| Elemento | Valor |
|---|---|
| Navy (títulos, cartões escuros, contorno dos agentes) | `16263B` |
| Laranja (rótulos, números, destaques) | `F04600` |
| Verde (faixas de conclusão, "amortiza dívida", valor único no gráfico) | `2E5B45` |
| Fundo | `EEF3EE` · faixa tingida e fundo dos agentes `E3EBE4` |
| Bordas de cartão e balão | `D6DED6` · linhas da árvore `B7C4BA` (1,75 pt barramento, 1,25 pt ramos, tracejado para leitura) |
| Texto corrido | `404040` · secundário `707070` · selo RISCO `66716C` |
| Tipografia | Calibri (fonte do tema). Rótulo de seção 11 pt, caixa alta, espaçamento 300, laranja. Título 28 pt navy. Agentes: nome 13 pt (especialistas) e 12 pt (Auditor, Autoaprimoramento) |
| Margens | 0,60" nas laterais (conteúdo de 0,60" a 12,73") |
| Elementos de marca | Sextante na capa; rodapé "CONFIDENCIAL · uso exclusivo do destinatário" + "ORIA DIGITAL" espaçado. A marca própria do Oria Digital, derivada da Oria Partners (L3), ainda não foi desenhada |

## 7. Regras de escrita

1. **Os títulos são conclusões curtas**, sem ponto final.
2. **As descrições dos agentes (slide 9)** dizem o que o agente faz, em linguagem simples e com termos técnicos só quando ajudam. Um balão por agente.
3. **Os blocos "COMO RESOLVEMOS" (slide 3) e "RESULTADO" (slide 5)** dizem a dor resolvida do cliente e não repetem o texto de cima. Textos definidos pelo dono:
   - Slide 3: Time focado na tomada de decisão · Erro achado antes do credor · Rastreabilidade de cada valor · Empresa vs. seus benchmarks
   - Slide 5: Maior confiabilidade nos dados · Nenhuma surpresa em cima da hora · Até onde o caixa aguenta · Sugestões estruturadas e bem embasadas · A prova que o banco precisava para renegociar
4. **"O que vendemos" (slide 8) descreve a entrega**, não o resultado: o resultado já está em "O que resolvemos" (slide 4). Não repetir "visão 360°" fora da capa.
5. **Número e unidade não se separam** (usar espaço que não quebra). Valor anual se escreve "R$ 10 mi / ano".
6. **Nada é afirmado no presente se ainda não existe** (seção 5). O slide 9 não mostra status; o slide 6 diz "cruzados em uma base única", e não "automaticamente".
7. **O que ainda não tem dado não entra.** Preço e projeções ficam fora do deck até o piloto medir custo, horas e prazo (J2).
8. **Todo número externo é reconferido na fonte primária**, com o recorte certo, antes de entrar (J3).

## 8. Como conferir e comparar

Os comandos abaixo rodam a partir desta pasta. Pré-requisitos: LibreOffice (`soffice` ou `libreoffice` no `PATH`), Poppler (`pdftoppm`, `pdftotext`) e Python com `python-pptx` e `Pillow`. **Por segurança, as ferramentas só aceitam arquivos `.pptx`/`.pdf` que existem dentro da pasta de trabalho.** Para comparar com uma versão nova, copie-a para esta pasta antes.

```bash
soffice --headless --convert-to pdf Business_Plan_Oria_Digital.pptx
python3 ferramentas/qa_geometria.py Business_Plan_Oria_Digital.pptx Business_Plan_Oria_Digital.pdf
python3 ferramentas/comparativo.py Business_Plan_Oria_Digital.pptx nova_versao.pptx comparativo.pdf --rotulos "ATUAL" "NOVA"
```

- **`qa_geometria.py`** aponta shape fora do slide, caixas de texto sobrepostas, fonte abaixo de 9 pt e **palavras que colidem no render**, que é o defeito que importa. Na v2 são **0**. Os outros achados são do próprio desenho: o sextante que sangra para fora da capa, os balões sobre as elipses e os títulos empilhados nos anexos.
- **`comparativo.py`** compara duas versões quaisquer, lado a lado, e marca IGUAL ou ALTERADO pela contagem de pixels. Os slides são pareados pela posição: quando um slide entra ou sai, todos os seguintes aparecem como alterados.

- **`renumerar_ids.py`** dá a cada forma um id único no deck inteiro (slide k → k×1000+n). **Rode-o sempre antes de publicar uma versão nova.** Motivo: no iPhone (visualizador do Arquivos/Mail), quando o mesmo id de forma aparecia em slides diferentes, formas de um slide eram desenhadas em outro. As setas do slide 5 apareciam no 6 a 10, o painel do 8 no 9 a 14 e as elipses do 9 no 10 a 14. Os slides 1 a 5 abriam bem. Na v4 havia ids repetidos em todos os slides; depois do script ficaram 0 de 563, e o render no LibreOffice ficou idêntico pixel a pixel nos 14 slides. O script recusa o slide que referencia ids (conectores colados, animação), porque renumerar quebraria a referência.

**Limitação.** A conferência visual foi feita no LibreOffice, em que a Calibri é substituída pela Carlito, de métricas iguais. Abra no Microsoft PowerPoint antes de apresentar. Os pontos mais sensíveis são a árvore do slide 9 e os rótulos do gráfico do slide 7.
