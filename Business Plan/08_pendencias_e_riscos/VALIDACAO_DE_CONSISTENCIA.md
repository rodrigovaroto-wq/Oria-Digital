# Validação de consistência (Fase 4, 23/11/2026)

Retrato da conferência pedida no item 3.3 da Fase 4: o business plan, o workflow, o registro de
decisões e o plano de execução dizem a mesma coisa? É um **retrato datado**, não fonte viva: o que
continua aberto foi para as [pendências](PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md) ou para o
[plano](../06_execucao/PLANO_DE_EXECUCAO.md).

## 1. O que foi medido, e como

| Conferência | Método | Resultado |
|---|---|---|
| Toda decisão da seção 19 tem lugar num documento oficial | Os 88 códigos do registro v0.1.3 procurados nos `.md` de `01_` a `08_`. Provado não-cego: com dois códigos retirados do texto, o teste acusou os dois | **88 de 88** |
| Links relativos entre documentos | Verificador de links em todos os `.md` e `.html` versionados. Provado não-cego: com um plano movido numa cópia, acusou 5 links quebrados em 3 arquivos | **0 quebrados** |
| Nada se perdeu na reorganização | 40 de 40 arquivos movidos com `git mv`, 0 linha alterada; os dois geradores regeram a v0.1.3 e o workflow v0.3.0 idênticos byte a byte | **40 de 40** |
| Situação "feito / corrigir / desenvolver" | Conferida no código (arquivo, migration, suíte), não nos planos antigos | Ver o plano, seção 3 |

## 2. Requisitos técnicos derivados (19.15) × plano

| Requisito (19.15) | Itens do plano |
|---|---|
| Organização com RLS, papéis Técnico e revisor da consultoria, teste de vazamento | 1.F1, 1.F2, 1.F5, 2.14 |
| Chaves de mínimo privilégio para n8n e agentes | 0.4, 1.D1 |
| Cópia diária criptografada e teste de restauração antes do piloto | 0.2, 0.3 |
| Extração: código primeiro, IA onde falhar, IA revisora | 1.B1, 1.B2 |
| Captação externa e cruzamento com os dois valores | 1.B3, 1.B4, 1.B5, 2.5 |
| Proveniência por dado e registro de autorizações | 1.B6, 1.B7 |
| Réguas de baixo impacto e de gravidade | 1.D6 |
| Fila de decisão com resumo + dossiê, campos, prazos, escalonamento | 1.D5, 1.D7 |
| Botão Conferência e estados do Kit | 1.F4 |
| Limites de ressalva e "limitações relevantes" | 1.F3, 1.I2 |
| Provedores múltiplos e roteamento por região | 1.D8 |
| Custo por etapa e agente; medição por mandato | 1.D9, 1.J1 |
| Gabarito com parte oculta; régua de autonomia; extração em N1 | 1.J2, 0.5, 3.3 |
| Agentes do piloto e dados de mercado | 1.C1–1.C5, 1.D4, 1.D5, 1.E1–1.E4 |
| Portal do cliente com link seguro; duas etapas depois | 1.G1, 2.16 |
| Excel com link para documento e página + PDF | 1.I1, 1.I2 |
| Monitoramento e relatório periódico | 2.8, 2.9 |
| Autoaprimoramento: rascunho, relatório semanal, contagem validada, bloqueio de escrita | 2.10, 4.1 |
| Chave liga/desliga, caminho gradual, migrations em duas etapas | 2.11 |
| Três ambientes; dado real só anonimizado | 0.9, 0.10 |
| Trilha com cadeia de hashes | 2.15 |
| Expurgo em três camadas | 2.12 |
| Benchmarks anonimizados | 2.13 |

**Resultado:** todo requisito tem item, dependência e critério de pronto no plano.

## 3. Os quatro documentos dizem a mesma coisa?

| Assunto | Registro v0.1.3 | Workflow v0.3.0 | Deck v2 | Plano | Coerente? |
|---|---|---|---|---|---|
| Piloto = Conferidor, Dívida, Caixa, Mercado + Supervisor e Auditor (K6) | Sim | Selo PILOTO nesses 6 | Slide 9 sem status (J4) | Trilhas D e E | Sim |
| Restante da v1: Risco, Estrategista, Entregas, Captador formal, monitoramento, autoaprimoramento fase A | A2, B1, F1 | Selo V1 | — | Fase 2 | Sim |
| Open Finance "desde a v1" (C4) | Sim | Selo V1 | Slide 6 cita "Open Finance" | 2.5 (restante da v1, não piloto) | Sim (o K6 não o inclui no piloto) |
| Infraestrutura só candidata (R2) | Sim | Seção "EM ESTUDO" | Pilar "infraestrutura segura" | 0.1 primeiro | Sim |
| Sem prazo (K2) | Sim | Sem datas | Sem prazo em meses | Sem datas | Sim |
| Valores só depois do piloto (J1, J2) | Sim | — | Slide 8 sem valores | 3.6 | Sim |
| Provedores de IA hoje | — | "Hoje: OpenAI (um provedor)" | — | 1.D8: dois dialetos (OpenAI e Gemini) por variável, sem troca automática | **Pequena divergência**: o workflow simplifica. Corrigir numa próxima versão do workflow |
| Backup hoje | H1-1 (cópia diária até a produção) | Bloco "Continuidade": "Hoje: cópia diária criptografada (provisória)" | — | 0.2 DESENVOLVER: não existe backup fora do Supabase | **Divergência**: o workflow escreve no presente o que é meta do 0.2 (o mesmo workflow diz "Supabase … sem backup"). Corrigir para "Até o piloto:" na próxima versão do workflow |
| Portal do cliente hoje | 19.1: "portal do cliente não existe" | Selo PILOTO | — | 1.G1 CORRIGIR: o envio por token já existe | **Pequena divergência**: existe a base (envio por link), não a área do cliente. Sem efeito no plano |
| "mais de 30 fontes" (slide 5) | — | Lista ~13 fontes no bloco de captação | Afirma no presente | 1.C1–1.C5 | **Em aberto**: o dono não fechou; está nas pendências |
| Retenção (I2) | 3 camadas | 3 camadas | — | 2.12; 0.11 corrige a especificação técnica | **Divergência técnica**: `10_DADOS_RETENCAO_E_LGPD.md` ainda diz [A CONFIRMAR] |
| Aprovação | Segundo revisor (E1) | Segundo revisor | "Especialista Oria decide" | 1.F2 | **Divergência técnica**: `06_HUMAN_IN_THE_LOOP.md` ainda fala em "revisor sênior" (removido na `0110`, segundo a pesquisa da Fase 1). Entra no 0.11 |

## 4. O que depende de testes, fornecedores ou decisões futuras

Listado, com o item que destrava cada um, em
[`PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md`](PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md): seções 1 (decisões),
2 (terceiros: integrador de dados, Open Finance, registradoras, provedores de IA, plataformas do
estudo), 3 (parecer jurídico) e 4 (testes).
