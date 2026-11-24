# Regras de negócio e definições operacionais

**Fonte oficial** dos parâmetros e das definições que o sistema aplica. Cada regra cita o código da
decisão no [registro v0.1.6](../07_decisoes/oria_digital_decisoes_e_pendencias_v0.1.6.html); o texto da
decisão e a fala do dono ficam lá. Os números aqui são **réguas ajustáveis e versionadas** (G5): mudar
um valor é decisão registrada numa nova versão do registro, nunca edição silenciosa deste arquivo.

> Este arquivo diz **o que** vale. Onde a regra já existe no código e onde ainda falta está no
> plano de execução (`06_execucao/PLANO_DE_EXECUCAO.md`).

## 1. Princípios que não mudam

| Regra | Decisões |
|---|---|
| **Agentes nunca calculam.** Não fazem, refazem nem corrigem número; interpretam o resultado do motor determinístico. Incongruência vai para revisão com a interpretação do agente | B2 |
| **O motor é a autoridade numérica.** Toda conta que chega ao cliente é feita no banco ou em fórmula do Excel | B4; ADR-02 em `Arquitetura do Sistema/1 Visão e Doutrina/05_ADR_02_ARITMETICA_NO_MOTOR.md` |
| **Ausência não é dado.** Falta de informação aparece como lacuna, com o motivo e o efeito; nunca como zero | Regra 1 do `CLAUDE.md`; v0.1.2 §2 |
| **O original nunca muda.** Escolher uma fonte não altera o valor extraído; os dois valores ficam guardados | D3; ADR-01 |
| **Não se inventa consenso.** Divergência que persiste vai registrada ao humano | v0.1.2 §3; B3 |
| **Diagnóstico não confiável não sai como definitivo.** Só as etapas dependentes do dado falho esperam; as independentes seguem | v0.1.2 §5 |
| **Quem propõe não aprova.** Vale para pessoas e para o agente de autoaprimoramento. O Auditor nunca conta como segundo revisor | E1, E2 |
| **Versões aprovadas são preservadas.** Uma conclusão nova passa de novo por auditoria e aprovação | v0.1.2 §8 |

## 2. Primeira rodada, debate e decisão do Supervisor

1. **1ª rodada independente:** cada especialista vê dados e evidências das outras áreas do mesmo
   mandato, **não as conclusões** dos outros agentes (v0.1.2 §2).
2. **Divergência:** verificação independente + debate mediado pelo Supervisor, **sem limite fixo de
   rodadas**; o Supervisor decide quando parar. Rodadas e custo por divergência são registrados (B3, L5).
3. **Toda divergência é notificada ao analista** (B3).
4. **O Supervisor decide sozinho só o de baixo impacto** (B3b-1), sempre notificando o analista:

| Decide sozinho | Vai ao humano |
|---|---|
| Forma; arredondamento; reclassificação entre contas de mesma natureza | Qualquer outra diferença de valor |
| Diferença de valor **< 1% da linha E < 0,5% do EBITDA ou da dívida total**, sem mudar conclusão, recomendação ou risco | Diferença que muda conclusão, recomendação ou risco, em qualquer tamanho |

5. **Divergência entre fontes de dados:** os agentes analisam, registram hipóteses e encaminham ao
   humano (N-C6a). No cruzamento, o dado externo tem o maior peso (D3).

## 3. Gravidade (G5)

| Nível | Critério | Prazo de decisão humana (E5) |
|---|---|---|
| **Crítico** | Muda a conclusão; > 5% do EBITDA ou da dívida; passivo não declarado; covenant rompido | 1 dia útil |
| **Alto** | > 1% do EBITDA ou da dívida (G5-1), ou muda um indicador-chave | 2 dias úteis |
| **Médio** | Acima da régua B3b-1 e < 1% | 5 dias úteis |
| **Baixo** | Dentro da régua B3b-1 | Sem prazo |

- Agentes só podem **subir** o nível, nunca descer (G5).
- Aviso na metade do prazo; vencido, sobe ao Sócio; etapas independentes seguem; prazos ajustáveis por
  contrato (E5).

## 4. Correção automática

- **Até 3 tentativas** por erro: reextrair, reler, pedir dado, reinterpretar. **Nunca recalcular** (B5).
  Revisa o limite de 5 da v0.1.2 §5.
- Caminho do erro: Auditor → Supervisor → especialistas → Supervisor → Auditor (v0.1.2 §5, B4).
- Depois da 3ª falha: o analista recebe **resumo** (o que deu errado, as tentativas, a proposta do
  Supervisor) e o **dossiê completo a um clique**, na mesma tela (N-B5a).

## 5. Decisão humana, aprovação e ressalvas

| Regra | Decisões |
|---|---|
| Decisão em campos estruturados: ação (aceitar, recusar, pedir revisão), **justificativa obrigatória**, vínculo às evidências; texto livre opcional. Sempre versionada | N-B5b, N-B5c |
| O Auditor revisa **antes** da decisão humana | v0.1.2 §6 |
| **Segundo revisor humano** quando o diagnóstico vai para fora (inclusive para clientes da Partners) ou tem ressalva. Itens internos: autoaprovação com checklist e revisão posterior por amostra. Com equipe: sempre segundo revisor | E1 |
| No piloto, o segundo revisor é **um analista da Oria Partners**, com acesso de revisão só aos mandatos da Partners | R1 |
| Até **3 ressalvas** em itens altos ou críticos por diagnóstico; sem teto para médio e baixo. Proibido ressalvar dado sabidamente errado | E3 |
| Acima de 3 ressalvas altas ou críticas: **só o Sócio aprova**, e o relatório do cliente traz "limitações relevantes" | E3-1 |
| Pendências aprovadas com ressalva entram **automaticamente** na revisão semanal do autoaprimoramento, por gravidade | E4 |
| Ajuste de EBITDA e Quality of Earnings: o agente sugere com evidência; nada é aplicado sem aceite humano | B8 |
| Cortes, renegociação e propostas aos credores: o sistema propõe e simula; o humano decide | B7 |

## 6. Dados, fontes e extração

| Regra | Decisões |
|---|---|
| **Extração:** código e ferramentas primeiro; IA só onde o código falhar; IA revisora confere PDF e imagem; estruturados são conferidos em SQL | D3 |
| **Captação externa:** SPED, Registrato, OFX, Open Finance, NF-e e fontes públicas, por código e IA | D3, C4 |
| **Cruzamento** (Conferidor): extração × captação; o externo é a referência de maior peso; **os dois valores ficam guardados**; o veredito separa divergências, o que foi resolvido (dentro da régua B3b-1), o que precisa de humano e sugestões; divergência relevante vira **achado** | D3, D3-3 |
| Ordem das fontes: públicas gratuitas e uploads do cliente → pagas → credenciadas (referência revisável) | C1 |
| **Registrato/SCR obrigatório** no Kit do cliente | C5 |
| Open Finance via integradora regulada; upload manual de extratos **sempre** disponível | C4 |
| Integrador de dados pagos (processos, protestos, bureaus), com **teto de custo por mandato** | C2, N-C6b |
| Recebível já cedido: só é exibido como prova com acesso às registradoras; até lá, não aparece como prova | C6 |
| Certificado digital e procuração do cliente: aceitos com política de custódia, ativados só depois da política de segurança e do parecer jurídico | C3 |
| Benchmarks próprios: só anonimizados, com cláusula contratual; mandato sem cobertura fica de fora | C7 |
| **Proveniência por dado:** fonte, data de coleta, autorização aplicável e versão do diagnóstico | N-C7a |
| **Autorização geral por cliente** (não por diagnóstico), com data, fontes e finalidade | N-C7b |
| **Score do dado externo:** todo dado captado fora do cliente passa pelo portão do agente que o usa. Veto reprova; piso falho manda para REVISÃO, que qualquer analista libera com justificativa; o score ponderado só bloqueia depois da calibração. Divergir do cliente é achado, não baixa o score. Os números estão na [Espec. 15, §5A](../../Arquitetura%20do%20Sistema/2%20Especificação/15_SCORE_DE_CONFIABILIDADE_DOS_DADOS_EXTERNOS.md) | D15, D15.1–D15.15 |

## 7. Autonomia da IA (D6)

Os níveis N0 (sombra) a N3 (autônomo) estão definidos na doutrina técnica
(`Arquitetura do Sistema/1 Visão e Doutrina/01_DOUTRINA_DE_AUTONOMIA.md`). A régua de negócio é:

- **Subir uma etapa a N2** exige ~**300 amostras** por etapa e tipo de documento, **parte cega**, com acerto
  mínimo de **98% no limite inferior** do intervalo. (Referência: 300 acertos em 300 dão limite
  inferior de 98,7%; 30 em 30 dão só 88,6%. Fonte: [síntese da pesquisa](../09_pesquisa/SINTESE_DA_PESQUISA_FASE1.md), §3.)
- **A extração e a classificação de documentos voltam a N1 até serem medidas** (D6, D6-1). Piora medida rebaixa automaticamente.
- **A promoção automática obedece à mesma régua.** O banco já promove etapas sozinho (`0137`), hoje com 30 vereditos: até o critério virar o da D6, ela fica desligada nessas etapas (plano, itens 0.5 e 3.3).
- **Gabarito:** 30 a 50 páginas reais, formatos mais comuns, conferido célula a célula, refeito a cada
  semestre, antes de trocar ou manter modelo e fornecedor (D4). Parte dele fica **oculta** (F5).

## 8. IA: provedores e custo

| Regra | Decisões |
|---|---|
| Processamento permitido no Brasil, na UE e nos EUA, com contrato de dados e cláusulas-padrão da ANPD assinados com cada provedor **antes do piloto**; o cliente pode exigir "só Brasil" | D1 |
| Dois ou mais provedores, troca automática por tarefa, respeitando a região do cliente | D2 |
| Custo medido por etapa e por agente; **alerta acima de US$ 5 por diagnóstico**; teto fixado depois do piloto; roteamento barato / médio / topo por tarefa | D5 |

## 9. Cliente, relatórios e monitoramento

| Regra | Decisões |
|---|---|
| Serviço completo, operado pela equipe do Oria Digital; autosserviço sem prazo | A4 |
| Só a equipe opera (Sócio, Analista, Leitura, Técnico). O cliente envia documentos e acompanha o próprio mandato | A5, E2 |
| **Consultoria-cliente** vê os mandatos dos clientes dela, envia e acompanha, sem operar; a empresa atendida vê só o próprio mandato; **nunca há acesso cruzado** entre consultorias | L4 |
| O cliente **não vê nomes nem papéis dos agentes**: vê o diagnóstico, a fonte de cada número e a aprovação humana, com autoria Oria Digital | L6 |
| Acesso do cliente: **link seguro por mandato** no piloto; login com verificação em duas etapas antes do primeiro cliente além da Partners ou com vários usuários por cliente | G3, I5-1 |
| Relatório **interno** completo (erros, pendências, auditoria) × relatório **do cliente** (conclusões aprovadas, com a limitação relevante quando houver) | v0.1.2 §7, E3-1 |
| Pacote ao cliente: Excel em fórmula, cada número ligado ao documento, à página ou à fonte externa, + relatório em PDF; apresentação a credores depois do piloto | G4 |
| Monitoramento: caixa e liquidez, dívida e vencimentos, covenants, processos, protestos, notícias, Registrato, mercado. Frequência e duração por contrato | G1 |
| Relatório periódico (mensal por padrão): indicadores × plano, variações (calendário × permanente), alertas, processos, protestos, notícias, recomendação; revisão humana antes de ir ao cliente; visão consolidada para carteiras | G2 |
| Alertas críticos **só no portal interno**; o analista decide se avisa o cliente | v0.1.2 §7–§8 |
| Novas evidências podem reabrir um diagnóstico aprovado; a versão aprovada é preservada | v0.1.2 §8 |

## 10. Glossário

| Termo | Definição |
|---|---|
| **Mandato** | Um trabalho contratado sobre uma empresa ou grupo (diagnóstico, reestruturação, acompanhamento) |
| **Organização** | A empresa cliente do Oria Digital (ex.: Oria Partners, uma consultoria, um fundo). Separa dados por RLS (H4) |
| **Kit do mandato** | A lista de documentos esperados do cliente, com o estado de cada um: recebido → extraído → cruzado → conferido (E6) |
| **Conferência** | O ato registrado de um humano conferir um documento: quem, quando, qual versão (E6) |
| **Achado** | Divergência relevante ou fato material que entra no diagnóstico (D3) |
| **Ressalva** | Aprovação com pendência conhecida e justificativa; nunca sobre dado sabidamente errado (E3) |
| **Motor** | O cálculo determinístico (SQL e fórmulas do Excel); o único lugar que calcula (B4) |
| **Piloto** | A primeira entrega da v1, com a Oria Partners como cliente (K6). Conta como produção real (H1-1) |
| **Primeiro cliente externo** | O primeiro cliente **além da Partners** (I5-1). Em "ir para fora" (E1), os clientes da Partners já contam como fora |
| **v1** | A primeira versão completa: agentes e monitoramento (A2). Entregue em partes; a primeira é o piloto |
| **N0 a N3** | Níveis de autonomia de uma etapa (doutrina): N0 sombra, não influencia decisão; N1 sugestão com humano confirmando todo item; N2 automático acima do limiar, o resto vai ao humano; N3 autônomo com auditoria por amostra |
| **Técnico** | Papel que aprova mudança técnica; separado de Sócio, Analista e Leitura (E2) |
| **Segundo revisor** | Humano diferente de quem preparou; obrigatório no que vai para fora (E1, R1) |
