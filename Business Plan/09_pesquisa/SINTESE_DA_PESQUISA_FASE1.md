# Oria Digital — Fase 1: síntese da pesquisa (18/11/2026)

Cinco frentes pesquisadas na web, mais duas varreduras do repositório. Cada linha leva a fonte.
"[sec]" = fonte secundária. Nada aqui é parecer jurídico.

## 0. Estado real do repositório (o que existe vs. o que os documentos descrevem)

- O produto é um **pipeline de dados**, não um sistema multiagente: n8n (4 workflows; IA só em
  "IA Classificar" e "IA Extrair") → Postgres/Supabase (301 migrations, reconciliações em SQL,
  trilha append-only, RLS por mandato desde a 0216) → portal Next.js (export Excel em fórmula).
- Não existe: LangGraph, Python/FastAPI, filas, Cloud Run, Langfuse, pgvector, agente supervisor,
  auditor-agente, autoaprimoramento, backtest, sandbox, rollback automático, relatório mensal,
  área do cliente, multiempresa (`organizacao`), separação permissão técnica × financeira.
- Provedor de IA no código: OpenAI `gpt-5.6-luna`, sem reserva (decisão de 11/11)
  (`N8N/lib/provedor.mjs:135`). A spec de LGPD diz Google; DPA [A CONFIRMAR].
- Aprovação: só o papel **Sócio** fecha o Portão 2, muda o dial, gere equipe (`0216:97-99`).
  `06_HUMAN_IN_THE_LOOP.md` ainda fala em "revisor sênior" (removido na 0110).
- Retenção: todos os prazos [A CONFIRMAR] em `10_DADOS_RETENCAO_E_LGPD.md`; "6 meses" não aparece.
- Plano: `STATUS_POR_ETAPA_2026-11-11` = 111 etapas, 20 completas, 86 não iniciadas, fim 19/01/2027;
  `PLANO_DE_EXECUCAO_2026-11` fala em abril/2027; `PLANO_MVP_2026-11` (aprovado, DM0) vai até 18/12.
- Riscos abertos: rodada real nunca validada; extração em N2 sem medição; backup nunca testado;
  `main` sem proteção conferida; Supabase em plano gratuito (sem backup); n8n no PikaPods.

## 1. Agentes e orquestração

- Anthropic: workflow (caminho fixo) antes de agente; complexidade só com ganho medido.
  https://www.anthropic.com/engineering/building-effective-agents
- Multiagente: +90% só em pesquisa ampla e paralela; ~15× tokens; ruim quando há dependência.
  https://www.anthropic.com/engineering/multi-agent-research-system
- OpenAI: maximizar um agente antes de dividir; humano em ação de alto risco.
  https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf
- Cognition: escrita em uma linha só; gerador + revisor de contexto limpo funciona.
  https://cognition.com/blog/dont-build-multi-agents · https://cognition.com/blog/multi-agents-working
- Google/MIT: em raciocínio sequencial, multiagente piorou 39–70%. https://arxiv.org/abs/2512.08296
- Debate ≈ votação; ganho vem da maioria. https://arxiv.org/abs/2508.17536
- Autocorreção sem feedback externo piora. https://arxiv.org/abs/2310.01798
- Frameworks TS compatíveis com o stack: Vercel AI SDK 6, Mastra, LangGraph.js; execução durável
  em Postgres: DBOS (https://supabase.com/blog/durable-workflows-in-postgres-dbos).
- MCP do Supabase é para desenvolvimento, usa service_role. https://supabase.com/docs/guides/ai-tools/mcp
- Casos: Hebbia (grade documento × pergunta), Rogo (modelos em camadas), Big Four "human-led";
  Deloitte Austrália devolveu valor por citações inventadas (out/2025).
- Recomendação: núcleo determinístico; especialistas = chamadas só de leitura sobre dado
  reconciliado, saída em schema, citam número do motor; consolidador compara em SQL; auditor = motor;
  2–3 tentativas; autoaprimoramento só propõe.

## 2. Extração, concorrentes e fontes de dados

- Benchmark (1 documento financeiro, 42 ferramentas): Claude Opus 4.8 1º (célula 1,00, US$1,19/doc);
  Gemini 3 Flash 2º (US$0,089/doc); GPT-5.5 com 25 alucinações em tabela; Docling 36% de célula.
  https://needl.ai/technical-notes/benchmarking-pdf-extraction-tools
- Caminho: estruturado (XLSX, OFX, CNAB, SPED) sem IA; PDF nativo com Docling local + LLM só nas
  páginas de demonstração; escaneado direto em LLM multimodal; SQL como portão; gabarito próprio
  de 30–50 páginas antes de escolher fornecedor.
- Concorrente mais próximo: Keye (YC, diligência de PE). Espaço livre: diagnóstico de reestruturação
  brasileiro com fontes oficiais e Excel em fórmula — não encontrado concorrente.
- Copiar: rastreabilidade célula → página (DataSnipper); grade de perguntas sobre contratos (Hebbia);
  variação timing × permanente nas 13 semanas.
- Fontes em 3 camadas: ~12 grátis sem autorização (BCB SGS/juros por modalidade/Focus, CVM, IBGE,
  PGFN, DataJud, PDET); ~6 compráveis por consulta (bureaus, protestos R$2,95–3,50, processos por
  CNPJ via Escavador/Judit, CNPJ); ~6 dependem de credencial do cliente (e-CAC/procuração, NF-e com
  A1, eSocial, Open Finance, registradoras).
- SCR/Registrato: sem API; o cliente baixa grátis pelo gov.br → melhor prova contra dívida escondida.
- Open Finance: Res. Conjunta nº 21 (22/10/2026) — empresa não regulada só como "entidade parceira".
- Recebível já cedido: sem acesso a registradora, vira "indício".
- Integradores: Direct Data, Infosimples, Judit, BigDataCorp, Kronoos.

## 3. Avaliação, observabilidade e autoaprimoramento

- Evals: 20–50 tarefas de falhas reais; regressão ~100%; pass^k para consistência.
  https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents
- Métrica-mãe em finanças: exatidão por célula + identidades contábeis; juiz LLM só para texto.
- Observabilidade: Langfuse self-host (MIT; comprado pela ClickHouse em jan/2026). Evitar Helicone.
- Reward hacking real em agentes de código (EvilGenie). O agente não pode escrever no golden set,
  avaliadores, portões nem na sonda; holdout que ele nunca vê.
- Quem propõe não aprova (GitHub Copilot coding agent). Agente nunca é o "segundo olho".
- Supabase branching começa sem dado de produção; PITR restaura o projeto inteiro → não é rollback
  de mudança. Rollback por flag; migrations em expand/contract.
- Canary/shadow antes de "todos"; "todos de uma vez" só para mudança aditiva com diferença zero.
- ISQM 2: revisor de qualidade não pode ser da equipe. Autoaprovação não é prática aceita para
  entregável que embasa decisão de terceiros.
- Amostra: 30/30 → limite inferior 88,6%; 300/300 → 98,7%. Zero erro em 30 → até 9,5% de erro.
  Revisão cega numa amostra para fugir do viés de automação.
- Governança: NIST AI 600-1, ISO/IEC 42001; PL 2338/2023 ainda na Câmara; EU AI Act provavelmente
  não alcança B2B fora da UE.

## 4. Segurança, LGPD e infraestrutura

- Supabase Free não tem backup; Pro US$25 + PITR US$100/mês; Team US$599 (SOC 2, ISO, log de
  auditoria). **Backup não inclui o Storage.** sa-east-1 disponível. https://supabase.com/pricing
- PikaPods: só UE/EUA, sem SOC 2/DPA publicados → elo mais fraco. https://www.pikapods.com/gdpr
- Vercel: gru1 (São Paulo), SOC 2 e ISO 27001.
- LLM no Brasil: só Gemini 2.5 Flash no Vertex southamerica-east1 com endpoint regional.
  OpenAI e Anthropic sem região Brasil. Nunca Gemini API gratuita com dado de cliente.
- Transferência internacional: cláusulas-padrão ANPD (Res. 19/2024), prazo encerrado em 23/08/2025.
- Papel LGPD: Oria tende a ser operadora; vira controladora se reusar dados (benchmark, melhoria).
- Incidente: controlador comunica em 3 dias úteis (Res. 15/2024); contrato com aviso de 24–48 h.
- Retenção: CTN 5 anos (cliente); CC art. 205, 10 anos (defesa da Oria); Lei 9.613 art. 9º XIV,
  5 anos se a Oria for enquadrada [VERIFICAR com advogado/COAF].
- Proposta de 3 camadas: originais expurgados; entregáveis retidos e minimizados; trilha só com
  hash e IDs pseudônimos; crypto-shredding por mandato; legal hold.
- Trilha imutável: append-only + hash encadeado + âncora diária em S3 Object Lock.
- OWASP LLM Top 10 2025 e Agentic Top 10: extração sem ferramentas, saída em schema, sem credencial
  na chamada, sem rede de saída.
- Bancos: Res. CMN 4.893 (alterada pela 5.274/2025) — diligência de fornecedor, local dos dados.

## 5. Mercado e modelo de negócio

- Cobrança: 54% dos produtos de IA já cobram além de assento; híbrido predomina (ICONIQ 2026).
- Margem bruta de IA: 45% (2025) → 53% (2026) (ICONIQ); serviço com especialista < SaaS.
- Recomendado: preço por mandato (entrada) + assinatura de monitoramento + assento só no ano 2.
  Por resultado: não, como base.
- Concorrentes vendem assento: Hebbia ~US$10 mil/ano, AlphaSense ~US$18 mil, Rogo ~US$3,3 mil [sec].
- Âncoras: QoE nos EUA US$15–150 mil (30–45 dias); AJ até 5% (art. 24 Lei 11.101).
- Deck: RJ 2025 = 2.466 ✔; KPMG 1.581 ✔; crédito PJ R$2,8 tri ✔; **FIDC R$56 bi diverge** (Anbima
  2025: R$90,8 bi em ofertas); **RJ caiu no 1º sem/2026** (435 processos vs 509); inadimplência PJ
  recorde (9,3 mi empresas, ago/2026); Selic 13,75%.
- Canibalização: Oria Digital no lado credor/comprador; Oria Partners no devedor (proposta).
- Riscos: responsabilidade civil (teto contratual, art. 421-A CC), E&O, dependência de provedor.
