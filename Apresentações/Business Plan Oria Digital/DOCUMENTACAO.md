# Business Plan Oria Digital: documentação da versão em vigor (v2)

Este documento reúne o que é preciso para entender, apresentar, manter ou refazer o deck `Business_Plan_Oria_Digital.pptx` (**v2**, 14 slides, 16:9, 13,33" × 7,5"). **Esta é a versão em vigor.** Ela substituiu a v1 (13 slides, PR #301) em 19/11/2026, depois de três rodadas de revisão do dono. A v1 fica no histórico do git; os comparativos e os scripts que produziram a v2 estão em [`Business Plan/99_historico/business_plan_v2_fase3/`](../../Business%20Plan/99_historico/business_plan_v2_fase3/).

Base das mudanças: o registro de decisões **v0.1.3** ([`Business Plan/99_historico/registro_de_decisoes/`](../../Business%20Plan/99_historico/registro_de_decisoes/); o vigente fica em [`07_decisoes/`](../../Business%20Plan/07_decisoes/)), em especial A3, B1, J1–J5 e K2.

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
| 10 | 9 · Para levar adiante | Quatro pilares levam o Oria Digital do método validado ao mercado | Linha do tempo e "O QUE BUSCAMOS" |
| 11 | Anexo 1 | 6 blocos e 31 frentes de diligência | Mapa da diligência |
| 12–14 | Anexo 2 (1/3 a 3/3) | Blocos 1–2, 3–4 e 5–6 | Cada frente com a área de impacto e a alavanca de valor |

## 3. Dados e fontes

A tabela de cada dado do deck, com fonte, recorte e situação, e o exemplo do slide 7 moram em
[`Business Plan/01_negocio/MODELO_DE_NEGOCIO_E_ESTRATEGIA.md`](../../Business%20Plan/01_negocio/MODELO_DE_NEGOCIO_E_ESTRATEGIA.md)
(seções 5 e 6), que é a fonte oficial do negócio (K5). Todo número novo é reconferido lá antes de
entrar no deck (J3).

**Anexos.** As contagens dos títulos batem com os selos de cada frente: slide 11, 3 + 6 + 8 + 7 + 4 + 3 = 31 frentes; slide 12, 5 com efeito no EBITDA; slide 13, 10 em risco e 10 em caixa; slide 14, 6 em risco.

## 4. Slide 8: modelo de negócio (sem valores)

O modelo de cobrança, o texto "O que vendemos" e a regra de que os valores saem do piloto (J1, J2)
estão em [`MODELO_DE_NEGOCIO_E_ESTRATEGIA.md`](../../Business%20Plan/01_negocio/MODELO_DE_NEGOCIO_E_ESTRATEGIA.md)
(seção 4). O modelo de projeção com premissas em branco está em
[`MODELO_DE_PROJECAO.md`](../../Business%20Plan/01_negocio/MODELO_DE_PROJECAO.md).

## 5. Slide 9: os agentes e o status real

O slide **não mostra status** (J4). O catálogo dos 11 agentes e o **status real de cada um**, com a
evidência no código, ficam em [`Business Plan/03_agentes/AGENTES.md`](../../Business%20Plan/03_agentes/AGENTES.md).
Use aquela tabela na conversa. Em resumo: nenhum agente existe hoje como agente; o piloto (K6) traz
Conferidor, Dívida, Caixa e Mercado, com Supervisor e Auditor.

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

**Limitação.** A conferência visual foi feita no LibreOffice, em que a Calibri é substituída pela Carlito, de métricas iguais. Abra no Microsoft PowerPoint antes de apresentar. Os pontos mais sensíveis são a árvore do slide 9 e os rótulos do gráfico do slide 7.
