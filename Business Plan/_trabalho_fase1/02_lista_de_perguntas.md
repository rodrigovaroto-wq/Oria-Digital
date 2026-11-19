# Oria Digital — Fase 1: lista completa de perguntas (18/11/2026)

Referência de comparação: `oria_digital_decisoes_e_pendencias_v0.1.2.html`.
Coluna "v0.1.2": **NOVA** = assunto que o registro não cobre; **REVISA §x** = muda algo [DEFINIDO];
**FECHA §x** = resolve algo [PROPOSTO]/[PENDENTE]. Cada pergunta será feita sozinha, com alternativas,
fonte e recomendação. As respostas viram o adendo v0.1.3.

## A. O que o Oria Digital é (identidade e escopo) — 6

| # | Pergunta | Por que importa | v0.1.2 |
|---|---|---|---|
| A1 | Os agentes são uma camada sobre o pipeline atual, uma reescrita, ou ficam só como visão futura? | Define todo o resto: arquitetura, prazo e o que o BP pode afirmar | REVISA §1, §3 |
| A2 | A v1 é o `PLANO_MVP` de 18/12 (book Excel + dossiê)? E o que entra na v2? | É a pergunta pendente do escopo da primeira versão | FECHA §18 |
| A3 | De que lado da mesa o Oria Digital trabalha: devedor, credor/comprador ou os dois? | Decide o cliente, o preço e se concorre com a Oria Partners | NOVA |
| A4 | O cliente compra um software que ele mesmo opera, ou um serviço com o especialista Oria incluído? | Muda margem, responsabilidade, suporte e o que precisa ser construído | NOVA |
| A5 | Quem usa o sistema: só a equipe Oria, ou também o cliente, o credor e parceiros? Com quais papéis? | Define telas, permissões e o isolamento entre clientes | NOVA |
| A6 | Qual é o primeiro cliente externo (boutique, FIDC, banco) e quando? | O BP diz 3 a 6 meses; os planos dizem 2027 | NOVA |

## B. Agentes e funções — 8

| # | Pergunta | Por que importa | v0.1.2 |
|---|---|---|---|
| B1 | Qual é a lista única de agentes (nomes e funções), igual no BP, no workflow e na spec? | Hoje são três listas diferentes | FECHA §3 (proposto) |
| B2 | Os agentes nunca calculam número; só leem e citam o que o motor calculou? | Protege a regra "aritmética no motor" e evita número alucinado | NOVA (detalha §5) |
| B3 | Na divergência, a 2ª rodada é debate entre agentes ou votação com amostragem? | A pesquisa mostra que o debate não melhora a precisão | REVISA §3 |
| B4 | O auditor é o motor determinístico (recalcula), e a IA só revisa o texto? | É o feedback externo que a literatura exige | FECHA §5 (proposto) |
| B5 | Quantas tentativas automáticas antes de chamar o analista: 5 ou 2 a 3? | Cinco gasta custo sem ganho quando o erro não muda | REVISA §5 |
| B6 | Das 31 frentes de diligência do BP, quais o sistema cobre e em que ordem? | Hoje o anexo é só um mapa; não há plano por frente | NOVA |
| B7 | Até onde vai a recomendação: o sistema propõe corte de custo e renegociação com evidência, e o analista decide? | A visão original excluía estratégia de negociação; o BP a promete | NOVA |
| B8 | Ajustes de EBITDA e Quality of Earnings: o sistema sugere com evidência ou fica fora? | A doutrina limita esse tipo de etapa a N1 | NOVA |

## C. Dados e fontes — 7

| # | Pergunta | Por que importa | v0.1.2 |
|---|---|---|---|
| C1 | Quais fontes entram no MVP, na fase 2 e no futuro (grátis / pagas / com credencial do cliente)? | "Mais de 30 fontes" precisa virar lista com prazo | FECHA §2 (proposto) |
| C2 | Contratamos um integrador de dados pagos (processos, protestos, bureaus)? Qual orçamento por CNPJ? | Comprar é mais barato e rápido que fazer 15 integrações | NOVA |
| C3 | A Oria aceita guardar certificado digital ou procuração eletrônica do cliente (e-CAC, NF-e, FGTS)? | Abre SPED e NF-e automáticos, mas traz responsabilidade | NOVA |
| C4 | Open Finance agora (como parceira de uma integradora, Res. Conjunta 21) ou extrato por upload? | A regra nova exige auditor e consentimento | NOVA |
| C5 | O Registrato/SCR vira documento obrigatório do kit do cliente? | É a melhor prova contra dívida escondida, e é grátis | NOVA |
| C6 | "Recebíveis já cedidos" vira "indício" até termos acesso às registradoras? | Sem a CERC ou a B3 não dá para provar | NOVA |
| C7 | Podemos usar dados de vários clientes, anonimizados, para criar benchmarks próprios? | Faz a Oria virar controladora de dados pela LGPD | NOVA |

## D. IA: modelos, extração, custo e autonomia — 6

| # | Pergunta | Por que importa | v0.1.2 |
|---|---|---|---|
| D1 | Onde a IA pode processar dado de cliente: só no Brasil, também na UE, ou nos EUA com cláusulas da ANPD? | Troca qualidade de modelo por conformidade | NOVA |
| D2 | Um provedor de IA ou dois com reserva automática? | Revisa a decisão de 11/11 (sem reserva) | NOVA |
| D3 | Extração: só LLM, ou um fornecedor especializado mais leitura local, com formatos estruturados sem IA? | Custo, precisão e LGPD | NOVA |
| D4 | Montamos um gabarito com 30 a 50 páginas reais para escolher o modelo e medir? | Sem isso a escolha é palpite | FECHA §14.2 em parte |
| D5 | Qual orçamento de IA por diagnóstico, e qual modelo atende cada tarefa? | Hoje o teto é US$ 5 por book; os agentes custam mais | NOVA |
| D6 | Quantas amostras cegas e qual acerto mínimo para um estágio subir de nível? E a extração volta para N1 até medir? | Hoje 30 vereditos sobem a N2; a estatística pede cerca de 300 | REVISA doutrina do repositório |

## E. Pessoas, papéis e aprovação — 6

| # | Pergunta | Por que importa | v0.1.2 |
|---|---|---|---|
| E1 | O autor pode aprovar o próprio diagnóstico, ou exigimos um segundo revisor (quatro olhos)? | Padrão de auditoria e bancos proíbe autoaprovação | REVISA §6 |
| E2 | Quem tem a permissão técnica, separada da financeira? Quais pessoas reais? | O papel não existe no código | FECHA §10/§11 |
| E3 | Existe limite de ressalvas por caso? Quem pode aprovar com ressalva? | Evita a ressalva virar carimbo | NOVA (detalha §6) |
| E4 | As pendências aprovadas com ressalva entram sozinhas na revisão semanal? | Pergunta interrompida no registro | FECHA §14.1 |
| E5 | Qual o prazo para o aprovador responder, e o que acontece se ele não responder? | Sem prazo, a fila trava | NOVA |
| E6 | Criamos o botão "conferi" por documento? | Pendente desde 13/11; hoje "conferido" é quase inalcançável | NOVA |

## F. Autoaprimoramento e mudanças técnicas — 6

| # | Pergunta | Por que importa | v0.1.2 |
|---|---|---|---|
| F1 | Na primeira fase, o agente só propõe mudanças (PR em rascunho) de prompts e regras, ou também código e ferramentas? | Riscos de reward hacking e de mudança grande sem histórico | REVISA §9 |
| F2 | Publicação: liberação gradual por cliente (canary) ou todos de uma vez? | A v0.1.2 publica para todos sem fase gradual | REVISA §11 |
| F3 | Reversão automática por chave liga/desliga (flag), sabendo que restaurar backup não é reversão? | Restaurar backup apaga o trabalho de todos os clientes | REVISA §11 |
| F4 | Backtest com dados de clientes antigos: com que base contratual, e anonimizado ou não? | LGPD e contrato precisam permitir | REVISA §9 |
| F5 | O agente fica proibido de alterar o que o mede (gabarito, testes, portões), e existe um conjunto que ele nunca vê? | Evita que ele "passe na prova" trapaceando | NOVA |
| F6 | O ciclo semanal continua? Quem recebe e analisa o relatório? | Confirma §9 e define o responsável | confirma §9 |

## G. Monitoramento, relatórios e cliente — 5

| # | Pergunta | Por que importa | v0.1.2 |
|---|---|---|---|
| G1 | O que é monitorado, com que frequência e para quais clientes? | Define o produto recorrente | FECHA §8 (proposto) |
| G2 | O relatório mensal é um produto pago? O que ele contém? | Hoje não existe nem está planejado | detalha §7 |
| G3 | O cliente acessa por link sem login ou por uma área com login? | Muda segurança e esforço de construção | NOVA |
| G4 | O que o cliente recebe: Excel, PDF, apresentação? Cada número clicável até a página de origem? | Rastreabilidade é o diferencial da tese | detalha §7 |
| G5 | Quais níveis de gravidade de alerta, e qual prazo para tratar cada um? | Hoje é só proposta | FECHA §8 (proposto) |

## H. Infraestrutura e segurança — 8

| # | Pergunta | Por que importa | v0.1.2 |
|---|---|---|---|
| H1 | Saímos já do plano gratuito do Supabase (Pro com backup contínuo, São Paulo)? | Hoje não há backup nenhum | NOVA (urgente) |
| H2 | Para onde vai o n8n: servidor próprio no Brasil ou n8n Cloud na UE? | PikaPods não tem contrato de dados nem certificação | NOVA (urgente) |
| H3 | O processo longo (diagnóstico → revisão → monitoramento) fica numa máquina de estados no Postgres ou numa ferramenta de orquestração? | Substitui o LangGraph do workflow | REVISA §12 |
| H4 | Isolamento entre clientes: separação por linha no mesmo banco, ou banco separado para cliente regulado? | Bancos e fundos vão exigir | FECHA §1 (proposto) |
| H5 | Observabilidade da IA: Langfuse no nosso servidor ou serviço na nuvem? | Substitui LangSmith/Langfuse da §12 | FECHA §12 |
| H6 | A trilha de auditoria ganha selo à prova de adulteração (hash encadeado + cópia externa imutável)? | Prova de integridade para credor e juiz | FECHA §1 (proposto) |
| H7 | Quanto dado podemos perder no pior caso, e em quanto tempo voltamos (RPO/RTO)? E o teste de restauração? | Nunca foi testado; o Storage não entra no backup | FECHA §14.4 |
| H8 | Ambientes separados (desenvolvimento, teste, produção) e nenhum dado real fora da produção? | Pré-requisito do autoaprimoramento | FECHA §12 (proposto) |

## I. LGPD, retenção e contratos — 5

| # | Pergunta | Por que importa | v0.1.2 |
|---|---|---|---|
| I1 | Quem é o advogado ou encarregado de dados (DPO) que valida LGPD e contratos? | Várias decisões dependem de parecer | FECHA §14.7 |
| I2 | Retenção em três camadas: originais apagados em 6 meses; entregáveis por 5 ou 10 anos; trilha sem dado pessoal? | Os 6 meses conflitam com prazos legais de defesa | REVISA §13 |
| I3 | A Oria se enquadra na Lei de Lavagem (COAF, art. 9º XIV) por fazer consultoria em M&A? | Se sim, é obrigada a guardar por 5 anos | NOVA |
| I4 | Contrato com o cliente: teto de responsabilidade, seguro de responsabilidade profissional, aviso de incidente em 24–48 h? | Proteção antes do primeiro cliente externo | NOVA |
| I5 | Fazemos agora o relatório de impacto (RIPD)? | Recomendado: IA + dados financeiros + envio ao exterior | NOVA |

## J. Modelo de negócio e Business Plan — 6

| # | Pergunta | Por que importa | v0.1.2 |
|---|---|---|---|
| J1 | Como cobramos: por mandato, assinatura de monitoramento, por usuário, ou combinação? | Base das projeções | NOVA |
| J2 | Preço, receita e projeções entram agora no BP, ou seguem fora até a conversa com o sócio? | O PR #301 deixou fora de propósito | NOVA |
| J3 | Corrigimos os dados do deck (FIDC R$ 56 bi vs. R$ 90,8 bi; queda de RJ em 2026; inadimplência recorde)? | Número errado diante do investidor | NOVA |
| J4 | O slide 8 continua dizendo "em operação" com a rodada real ainda não validada? | Atrito com a regra 5 do próprio deck | NOVA |
| J5 | O que pedimos ao sócio, e o que oferecemos em troca? | Precede qualquer projeção | NOVA |
| J6 | Medimos desde o 1º mandato: horas do analista, custo de IA e dias até a entrega? | Sem isso o "dias, não meses" não tem prova | NOVA |

## K. Execução e governança do projeto — 5

| # | Pergunta | Por que importa | v0.1.2 |
|---|---|---|---|
| K1 | Qual plano vale, e quais viram histórico? | Há cinco planos e dois MVPs | NOVA |
| K2 | Quais datas são compromisso (marcos) e quais são estimativa? | 18/12, 19/01 e abril/2027 convivem | NOVA |
| K3 | Quem constrói: você + Claude, ou o sócio traz engenheiros? Quem responde por cada área? | O plano precisa de responsáveis | NOVA |
| K4 | Os riscos urgentes (backup, contrato com a IA, proteção do `main`, extração em N2) viram uma "Fase 0" antes de tudo? | Hoje há dado real sem backup | NOVA |
| K5 | A pasta `Business Plan` vira a fonte oficial do negócio, e `Arquitetura do Sistema` a fonte técnica? | Evita duplicação na Fase 4 | NOVA |

**Total: 68 perguntas em 11 blocos.**
