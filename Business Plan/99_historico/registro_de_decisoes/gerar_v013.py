"""Gera o registro cumulativo v0.1.3 a partir da v0.1.2 (preservada integralmente) + adendo da entrevista."""
import html
import sys
from pathlib import Path

base_path, out_path = Path(sys.argv[1]), Path(sys.argv[2])
base = base_path.read_text(encoding="utf-8")
E = html.escape

# (código, decisão, status, relação com v0.1.2/repo, fala exata, origem)
TEMAS = [
 ("19.2", "Identidade, escopo e primeira versão", [
  ("OBJ", "Objetivo do Oria Digital: acelerar a reestruturação financeira num ecossistema único — diagnóstico mais rápido, confiável e coerente com o cliente; dados atualizados e confiáveis; cruzamento com benchmarks; gatilhos de redução de custo e dívida e de aumento de receita e lucro.", "DEFINIDO", "Novo", "acelerar o processo de reestruturação financeira e trazer mais qualidade e clareza na depuração dos dados e na comparação da empresa com os seus benchmarks a fins de diminuir custos e dívida e aumentar receita e lucro em pouco tempo, com dados mais atualidados, atualizados e confiáveis, e dentro de um ecossistema só", "Lote 01"),
  ("A1", "Evoluir o sistema existente, sem reconstruir do zero, incorporando agentes de IA desde agora e de forma gradual, inclusive na leitura e estruturação dos dados. A tecnologia (LangGraph, Python etc.) não foi escolhida aqui.", "DEFINIDO c/ condição", "Revisa §1/§3 (agentes como alvo sem data) e o PLANO_MVP do repositório", "Você escolhe a opção B, mas com ênfase de aproveitar a evolução e estrutura atual, incorporando agentes de IA desde agora, mas gradualmente, conforme o projeto vai avançando, e também para melhorar a leitura e estruturação e o processo dos dados sem reconstruir nada do zero", "Lote 01"),
  ("A2", "A primeira versão (v1) inclui agentes de IA e monitoramento. A data de 18/12/2026 do MVP anterior não foi reconfirmada.", "DEFINIDO", "Fecha §18 (escopo da v1); revisa o PLANO_MVP_2026-11", "A opção B, já incluir agentes de IA e monitoramento na primeira versão", "Lote 01"),
  ("A3", "Atende os dois lados (devedores e credores/compradores). Oria Digital e Oria Partners são empresas separadas; a Oria Partners é a primeira cliente piloto.", "DEFINIDO", "Novo; corrige documentos que descrevem o produto como nascido dentro da Oria Partners", "a Oria Partners é uma empresa separada da Oria Digital. Oria Partners seria primeiro cliente piloto da Oria Digital", "Lote 01"),
  ("A4", "Modelo inicial: serviço completo, operado pela equipe do Oria Digital, que entrega diagnósticos e resultados. Autosserviço sem prazo.", "DEFINIDO", "Novo", "inicialmente vamos definir exatamente como um serviço completo com especialistas operando a plataforma e entregando os resultados", "Lote 01"),
  ("A5", "Desde a v1, só a equipe do Oria Digital opera (Sócio, Analista, Leitura); o cliente tem portal limitado para enviar documentos e acompanhar mandato, consultas e relatórios da própria empresa.", "DEFINIDO", "Novo; antecipa a área do cliente", "os clientes vão poder acompanhar o mandato, enviar a documentação e acompanhar o andamento das consultas e relatórios dentro da plataforma", "Lote 01"),
  ("A6", "Primeiro cliente além da Partners sem definição. Hipótese: empresas que precisam de reestruturação rápida; depois consultorias, assessorias, FIDCs e bancos.", "ABERTO", "—", "essa pergunta fica meio em aberto, mas você já tem uma contextualização e uma resposta abrangente", "Lote 01"),
  ("K6", "Piloto com a Partners (primeira entrega da v1): book Excel confiável; extração com captação externa (SPED, Registrato, OFX) e cruzamento; agentes Conferidor, Dívida, Caixa e Mercado, com Supervisor e Auditor; todos os dados de mercado captados e atualizados; portal do cliente para envio e acompanhamento; dossiê de processos e notícias. O restante da v1 vem em entregas seguintes.", "DEFINIDO", "Novo; define o primeiro marco da v1", "K6 -> A + Agente de Mercado e todos os dados de mercado sendo captados e atualizados", "Entrevista direta"),
 ]),
 ("19.3", "Agentes e governança das análises", [
  ("B1", "Catálogo de referência, flexível, com 11 agentes: Captador, Conferidor, Mercado, Risco, Caixa, Dívida, Estrategista, Entregas + Supervisor/Orquestrador, Auditor Independente e Autoaprimoramento. Mudanças futuras com justificativa, teste e versão.", "DEFINIDO c/ condição", "Fecha §3 (proposto); substitui as listas do workflow v0.2.0 e do Business Plan", "Quero que essa seja a ideia inicial, mas não... não se limite apenas a isso, podendo ter mais agentes ou menos", "Lote 01"),
  ("B2", "Agentes nunca calculam, refazem ou corrigem número; interpretam o resultado do motor determinístico. Ao ver incongruência, o agente da área manda para revisão com a sua interpretação, sem resolver sozinho.", "DEFINIDO", "Detalha §5", "Ele não deve aceitar ou ou refazer cálculos e e tentar solucionar tudo sozinho", "Lote 01"),
  ("B3", "Divergência entre agentes: verificação independente + debate mediado pelo Supervisor; toda divergência é notificada ao analista; em caso relevante o Supervisor só propõe e o humano aceita, recusa ou pede revisão.", "DEFINIDO", "Confirma e detalha §3", "o supervisor não deve ter o poder de decidir e falar o que está certo ou errado. Ele deve fazer uma análise, sugerir uma solução para que para esse problema e passar para um humano eh, decidir sobre qual caminho tomar", "Lote 01"),
  ("B3b-1", "O Supervisor decide sozinho, sempre notificando o analista: forma; arredondamento; reclassificação entre contas de mesma natureza; diferenças de valor abaixo de 1% da linha e de 0,5% do EBITDA ou da dívida total, sem mudar conclusão, recomendação ou risco. Acima disso, toda diferença de valor vai ao humano.", "DEFINIDO", "Revisa a B3b do lote 02 (só forma)", "Sobre a B3b, na verdade quero que o Supervisor decida sobre coisas de baixo impacto. / B + A -> … / B3b-1 está correto.", "Entrevista direta"),
  ("B4", "O motor recalcula e é a autoridade numérica; o Auditor Independente revisa a execução dos outros agentes, evidências e coerência, usando o motor, sem recalcular.", "DEFINIDO", "Detalha §5 (auditoria híbrida)", "ele revisa não os valores determinísticos e imutáveis, né, os números, mas sim ele revisa a execução da outra IA", "Lote 02"),
  ("B5", "Até 3 tentativas automáticas de correção (reextrair, reler, pedir dado, reinterpretar — nunca recalcular); depois vai ao analista com o histórico.", "DEFINIDO", "Revisa §5 (5 → 3 tentativas)", "eu quero até, exatamente, três tentativas, e não duas", "Lote 02"),
  ("N-B5a", "Após 3 tentativas falhas, o analista recebe um resumo (o que deu errado, tentativas, proposta do Supervisor) com o dossiê completo a um clique, na mesma tela.", "DEFINIDO", "Novo", "N-B5a -> A", "Entrevista direta (confirma lote 02)"),
  ("N-B5b", "Decisão do analista em campos estruturados: ação (aceitar, recusar, pedir revisão), justificativa obrigatória e vínculo às evidências; texto livre opcional.", "DEFINIDO", "Detalha §6", "N-B5b -> A", "Entrevista direta (confirma lote 02)"),
  ("N-B5c", "Decisões humanas sempre versionadas e justificadas com referência às evidências.", "DEFINIDO", "Reforça §6", "Eu quero que você registre minha escolha da opção A", "Lote 03"),
  ("B6", "A cobertura e a ordem das 31 frentes de diligência são definidas na construção de cada agente.", "DEFINIDO c/ condição", "—", "Dessas frentes serão definidas depois, junto com a construção de cada agente de IA", "Lote 03"),
  ("B7", "O sistema propõe cortes de custo e caminhos de renegociação e simula propostas aos credores (carência, desconto, dinheiro novo); o humano decide.", "DEFINIDO", "Amplia a visão original; exige motor de cenários", "Eu gosto de uma combinação da opção A com a opção C, ok? Então, mais voltado para a opção C", "Lote 03"),
  ("B8", "Agentes sugerem ajustes de EBITDA e Quality of Earnings com evidência; nenhum ajuste é aplicado sem aceite humano.", "DEFINIDO", "Coerente com o teto N1 da doutrina", "Opção A", "Lote 03"),
  ("D3-3", "Captador: extração e captação externa. Conferidor: cruzamento e veredito. Supervisor: coordena, media e decide só baixo impacto.", "DEFINIDO", "Detalha B1", "D3-3 - A", "Entrevista direta"),
  ("L5", "Sem limite fixo de rodadas de debate; o Supervisor decide quando a discussão não é mais necessária. Rodadas e custo por divergência são registrados.", "DEFINIDO", "Detalha B3", "deixar o Supervisor decidir quando não for mais necessário a discussão", "Entrevista direta"),
  ("L6", "Nomes e papéis dos agentes só no lado interno; o cliente vê o diagnóstico, as fontes de cada número e a aprovação humana, com autoria Oria Digital.", "DEFINIDO", "Coerente com §7", "L6 -> A", "Entrevista direta"),
 ]),
 ("19.4", "Dados, fontes, extração e cruzamento", [
  ("C1", "Fontes: públicas gratuitas e uploads do cliente primeiro; pagas depois; credenciadas no futuro — referência revisável, definida na construção dos agentes.", "DEFINIDO c/ condição", "Fecha §2 (proposto); revisada pela C4", "pode colocar a opção A como uma resposta inicial. Ela não vai ser imutável", "Lote 03"),
  ("C2", "Usar um integrador de dados pagos (processos, protestos, bureaus); fornecedor e valor a definir.", "DEFINIDO c/ condição", "Novo", "Opção A", "Lote 03"),
  ("N-C6b", "Teto de custo por mandato para consultas pagas; valor a definir.", "DEFINIDO c/ condição", "Novo", "Opção A, sim, deve ter um corte, um teto de custos", "Lote 03"),
  ("C3", "Aceita guardar certificado digital e procuração eletrônica do cliente, com política de custódia; ativação só depois da política de segurança e do parecer jurídico.", "DEFINIDO c/ condição", "Novo", "Opção B", "Lote 03"),
  ("C4", "Open Finance desde a v1, via integradora, e upload manual de extratos sempre disponível.", "DEFINIDO", "Revisa a C1; exige parceria regulada (Res. Conjunta 21/2026)", "quero integrar sim, mas também quero que o sistema tenha capacidade de eh, registrar e com Chrome, de ter a capacidade de quando eu não tiver o Open Finance, ou eu algo do tipo, eu conseguir mandar os extratos", "Lote 03"),
  ("C5", "Registrato/SCR obrigatório no kit do cliente.", "DEFINIDO", "Novo", "Sim, obrigatório", "Lote 03"),
  ("C6", "Mantida a promessa de identificar recebíveis já cedidos; a função será construída com acesso às registradoras (CERC, B3, Núclea). Até existir, o achado não é exibido como prova.", "DEFINIDO c/ condição", "Novo; cria requisito de acesso às registradoras", "não temos essa função ainda no sistema, mas teremos e deixará de ser um indício", "Entrevista direta"),
  ("C7", "Benchmarks próprios com dados de vários clientes, anonimizados, desde já — com anonimização efetiva e cláusula contratual; mandatos sem cobertura ficam de fora.", "DEFINIDO c/ condição", "Novo", "C7 -> C", "Entrevista direta"),
  ("N-C6a", "Divergência entre fontes: agentes analisam, registram hipóteses e encaminham ao humano.", "DEFINIDO", "Coerente com B2/B3", "Opção B", "Lote 03"),
  ("N-C7a", "Cada dado guarda fonte, data de coleta, autorização aplicável e versão do diagnóstico.", "DEFINIDO", "Detalha §2 (proposto)", "Opção A", "Lote 03"),
  ("N-C7b", "Autorização geral por cliente (não por diagnóstico), registrada com data, fontes e finalidade.", "DEFINIDO", "Novo", "cada autorização seja registrada com data, fonte e finalidade, mas não por diagnóstico", "Lote 03"),
  ("D3", "Extração: código e ferramentas primeiro; IA extrai só onde o código falhar; IA revisora confere extrações de PDF e imagem (estruturados: conferência SQL). Captação externa por IA + código (SPED, Registrato, OFX, Open Finance, notas, fontes públicas). Cruzamento: compara extração × captação, com o dado externo como referência de maior peso; os dois valores ficam guardados; veredito com divergências, o que foi resolvido (escolha de fonte dentro da régua B3b-1, sem alterar o original), o que precisa de humano e sugestões; divergência relevante vira achado.", "DEFINIDO", "Revisa o pipeline atual; substitui as versões anteriores D3, D3-1 e D3-2 (ver 19.10)", "aceito todas as propostas da D3 revisada", "Entrevista direta"),
  ("N-C5a", "Gestão das integrações (interna ou centralizada).", "ABERTO", "—", "Não sei ainda, deixa essa pergunta em aberto", "Lote 03"),
 ]),
 ("19.5", "IA: provedores, qualidade, custo e autonomia", [
  ("D1", "A IA pode processar no Brasil, na UE e nos EUA, com contrato de dados e cláusulas-padrão da ANPD assinados com cada provedor antes do piloto; o cliente pode exigir “só Brasil” (roteamento por cliente).", "DEFINIDO c/ condição", "Novo", "D1 -> C + D", "Entrevista direta"),
  ("D2", "Dois ou mais provedores de IA, com troca automática por tarefa, respeitando a região permitida do cliente.", "DEFINIDO", "Revisa a decisão de 11/11 (provedor único, sem reserva)", "D2 -> B", "Entrevista direta"),
  ("D4", "Gabarito de 30 a 50 páginas reais, formatos mais comuns, conferido célula a célula, refeito a cada semestre, antes de trocar ou manter modelo e fornecedor.", "DEFINIDO c/ condição", "Fecha em parte §14.2", "D4 -> A", "Entrevista direta"),
  ("D5", "Teto de custo de IA por diagnóstico medido no piloto (por etapa e por agente, alerta acima de US$ 5) e fixado depois; roteamento barato/médio/topo por tarefa.", "DEFINIDO", "Novo", "D5 -> A", "Entrevista direta"),
  ("D6", "Subir uma etapa a N2 exige cerca de 300 amostras por etapa e tipo de documento, parte cega, acerto mínimo de 98% no limite inferior; a extração volta a N1 até lá; piora medida rebaixa automaticamente.", "DEFINIDO", "Revisa a doutrina de autonomia do repositório (30 vereditos)", "D6 -> A", "Entrevista direta"),
 ]),
 ("19.6", "Pessoas, papéis e aprovação humana", [
  ("E1", "Agora: segundo revisor humano obrigatório quando o diagnóstico vai para fora (inclui clientes da Partners) ou tem ressalva; autoaprovação de itens internos com checklist e revisão posterior por amostra. Com equipe: sempre segundo revisor. O agente Auditor nunca conta como segundo revisor.", "DEFINIDO c/ condição", "Revisa §6 (autoaprovação livre)", "E1 -> C agora, A quando houver equipe", "Entrevista direta"),
  ("R1", "No piloto, o segundo revisor é um analista da Oria Partners, com acesso de revisão só aos mandatos da Partners.", "DEFINIDO", "Fecha a lacuna E1 × K3", "R1 -> A", "Entrevista direta"),
  ("E2", "Papel “Técnico”, separado de Sócio, Analista e Leitura, aprova mudanças técnicas; quem propõe não aprova (inclui o agente de autoaprimoramento); mudança que afeta número ou conclusão exige aprovação técnica e de negócio (Sócio). Hoje o Técnico é o dono (K3).", "DEFINIDO", "Fecha §10/§11", "E2 -> A", "Entrevista direta"),
  ("E3", "Até 3 ressalvas em itens de gravidade alta ou crítica por diagnóstico; sem teto para itens médios e baixos; mantida a proibição de ressalva sobre dado sabidamente errado.", "DEFINIDO", "Detalha §6", "até 3 ressalvas em item alto e crítico; sem teto para itens médios ou baixos", "Entrevista direta"),
  ("E3-1", "Acima de 3 ressalvas altas ou críticas: só o Sócio aprova, e o relatório do cliente traz “limitações relevantes”.", "DEFINIDO", "Detalha §6/§7", "E3-1 -> A", "Entrevista direta"),
  ("E4", "Pendências aprovadas com ressalva entram automaticamente na revisão semanal do autoaprimoramento, priorizadas por gravidade.", "DEFINIDO", "Fecha §14.1 (pergunta interrompida)", "E4 -> A", "Entrevista direta"),
  ("E5", "Prazo máximo de decisão humana: crítico 1 dia útil, alto 2, médio 5, baixo sem prazo; aviso na metade; vencido, sobe ao Sócio; etapas independentes seguem; ajustável por contrato.", "DEFINIDO", "Novo", "E5 -> A", "Entrevista direta"),
  ("E6", "Botão “Conferência” por documento: registra quem conferiu, quando e qual versão; o Kit mostra recebido → extraído → cruzado → conferido.", "DEFINIDO", "Fecha pendência de 13/11 no repositório", "E6 -> A - mudar o nome para Conferência", "Entrevista direta"),
  ("K3", "Agora o dono e o Claude constroem; o dono responde por todas as áreas; o Claude implementa, revisa e documenta, nunca aprova. Com o sócio, engenheiros e especialistas assumem áreas.", "DEFINIDO", "Novo", "K3 -> A", "Entrevista direta"),
 ]),
 ("19.7", "Autoaprimoramento e mudanças técnicas", [
  ("F1", "Fase inicial: o agente só propõe mudanças de prompts e regras; nada vai à produção sem aprovação do Técnico.", "DEFINIDO", "Revisa §9 (alcance inicial)", "F1 -> A mas nao limite em tempo, e sim em mandatos e erros encontrados", "Entrevista direta"),
  ("F1-1", "Gatilho para liberar código, ferramentas e migrations: ≥ 50 erros cometidos ou encontrados pelos agentes, distribuídos em ≥ 3 etapas ou agentes, sem mínimo de mandatos; liberação por decisão registrada do Técnico e do Sócio.", "DEFINIDO", "Detalha F1", "os 50 nao precisa ser confirmado por uma pessoa. nao precisa ser vindo de pelo menos 10 mandatos", "Entrevista direta"),
  ("F1-2", "Além dos 50 erros: ≥ 60% das propostas (mínimo 10) aprovadas pelo Técnico e sem causar piora.", "DEFINIDO", "Detalha F1", "F1-2 -> A", "Entrevista direta"),
  ("F1-3", "O Auditor Independente valida se cada erro é real antes de contar; o autoaprimoramento nunca valida a própria contagem.", "DEFINIDO", "Amplia o papel do Auditor (B4)", "F1-3 -> A", "Entrevista direta"),
  ("F2", "Publicação por tipo: mudança só aditiva e sem diferença de número no backtest vai para todos; mudança em extração, cálculo, premissa ou banco segue o caminho gradual (sombra → 1–2 clientes → todos).", "DEFINIDO", "Revisa §11 (publicação geral sem fase gradual)", "F2 -> C", "Entrevista direta"),
  ("F3", "Reversão por chave liga/desliga por mudança; mudanças no banco em “acrescenta primeiro, remove depois”; teste de reversão = desligar a chave numa cópia de teste e conferir que diagnósticos antigos não mudam. Backup é só recuperação de desastre.", "DEFINIDO", "Detalha §11 (rollback e bloqueio pré-publicação)", "F3 -> A", "Entrevista direta"),
  ("F4", "Backtest em ambiente de teste com cópias anonimizadas de casos reais (quando o contrato permitir) e dados inventados; gabarito sempre incluído, anonimizado.", "DEFINIDO", "Detalha §9 (backtest)", "F4 -> A", "Entrevista direta"),
  ("F5", "O agente não escreve sobre gabarito, testes, portões, sonda nem regras do projeto; parte do gabarito fica oculta, e proposta que melhora no conhecido e piora no oculto é rejeitada.", "DEFINIDO", "Novo; complementa §9", "F5 -> A", "Entrevista direta"),
  ("F6", "Ciclo semanal mantido; relatório ao Técnico no portal em dia fixo (erros, propostas com backtest e custo, contagem rumo aos 50, taxa de aprovação).", "DEFINIDO", "Confirma §9", "F6 -> A", "Entrevista direta"),
 ]),
 ("19.8", "Monitoramento, relatórios e cliente", [
  ("G1", "Monitoramento para empresas em pós-reestruturação e carteiras de credores: caixa e liquidez, dívida e vencimentos, covenants, processos, protestos, notícias, Registrato e dados de mercado. Frequência e duração configuráveis por cliente, conforme contrato.", "DEFINIDO", "Fecha §8 (proposto)", "não defina um tempo fixo de acompanhamento, isso será definido em contrato com a empresa", "Entrevista direta"),
  ("G2", "Relatório periódico (mensal como padrão): indicadores × plano, variações explicadas (calendário × permanente), alertas e tratamento, processos, protestos, notícias e recomendação; revisão humana antes de ir ao cliente; visão consolidada para carteiras.", "DEFINIDO", "Detalha §7", "G2 -> A", "Entrevista direta"),
  ("G3", "Piloto: link seguro por mandato. Antes do primeiro cliente além da Partners, ou com vários usuários por cliente: login com verificação em duas etapas.", "DEFINIDO", "Novo", "G3 -> C", "Entrevista direta"),
  ("G4", "Pacote ao cliente: Excel em fórmula com rastreabilidade número a número (documento, página, fonte externa) + relatório em PDF; apresentação para credores depois do piloto.", "DEFINIDO", "Detalha §7", "G4 -> A", "Entrevista direta"),
  ("G5", "Gravidade em 4 níveis — crítico (muda conclusão, > 5% do EBITDA ou dívida, passivo não declarado, covenant rompido), alto (> 1% ou muda indicador-chave), médio (acima da régua B3b-1 e < 1%), baixo (dentro da B3b-1). Agentes só podem subir o nível. Réguas ajustáveis e versionadas.", "DEFINIDO c/ condição", "Fecha §8 e §14.2 (severidade)", "G5 -> A, mas deixe passível de mudanças", "Entrevista direta"),
  ("L4", "Consultoria-cliente vê todos os mandatos dos clientes dela, envia documentos e acompanha, sem operar; empresa atendida vê só o próprio mandato; nunca há acesso cruzado entre consultorias.", "DEFINIDO", "Detalha A5", "L4 -> A", "Entrevista direta"),
  ("I5-1", "“Primeiro cliente externo” em G3 e H6 = primeiro cliente além da Partners. Na E1, “ir para fora” inclui os clientes da Partners.", "DEFINIDO", "Esclarece G3, H6, E1", "I5-1 -> A", "Entrevista direta"),
 ]),
 ("19.9", "Infraestrutura, segurança e dados pessoais", [
  ("H1", "Plano pago com backup contínuo, região São Paulo, cópia separada dos arquivos — quando entrar em produção real. A permanência no Supabase não está decidida.", "DEFINIDO c/ condição", "Supabase passa de “recomendado” a candidato", "só quando formos realmente colocar em produção real com clientes… nem sabemos ainda se vamos continuar no Supabase", "Entrevista direta"),
  ("H1-1", "O piloto com a Partners conta como produção real. Até lá: cópia diária automática, criptografada, do banco e dos arquivos, fora do Supabase.", "DEFINIDO", "Protege os mandatos reais hoje sem backup", "H1-1 -> A", "Entrevista direta"),
  ("H2", "n8n permanece onde está até a produção real; imediatamente: chave de mínimo privilégio e nenhum mandato real novo nele. Destino final no estudo.", "DEFINIDO c/ condição", "n8n passa a candidato", "H2 -> C", "Entrevista direta"),
  ("H3/H5", "Coordenação/hospedagem dos agentes, banco de dados, automação e observabilidade: estudo comparativo com ≥ 5 opções cada, as melhores para o caso, com variação de custo, complexidade e capacidade. Langfuse self-hosted é candidato preferido para observabilidade.", "ABERTO", "LangGraph, Cloud Run, Supabase, n8n e Langfuse do workflow v0.2.0 viram candidatos", "não quero um estudo comparativo apenas das 3 opções… mais de 5 ja seria suficiente, mas precisam ser as 5 melhores para o meu caso e sem desperdiçar muito dinheiro", "Entrevista direta"),
  ("R2", "O estudo é a primeira entrega do plano e termina antes do primeiro mandato do piloto; a construção dos agentes pode começar em paralelo sem prender a uma plataforma.", "DEFINIDO", "Fecha a lacuna H1 × H2 × H3", "R2 -> A", "Entrevista direta"),
  ("H4", "Separação por organização no mesmo banco (RLS), chaves de mínimo privilégio para n8n e agentes, teste automático de vazamento que precisa reprovar, banco dedicado para cliente regulado que exigir.", "DEFINIDO", "Fecha §1 (proposto: isolamento estrito)", "H4 -> A", "Entrevista direta"),
  ("H6", "Trilha de auditoria com cadeia de hashes e cópia diária externa imutável, antes do primeiro cliente além da Partners.", "DEFINIDO", "Fecha §1 (proposto: trilha imutável)", "H6 -> A", "Entrevista direta"),
  ("H7", "Produção: perda máxima de minutos, volta em até 4 h, teste de recuperação trimestral (banco + arquivos). Até lá: perda máxima de 1 dia e um teste antes do piloto.", "DEFINIDO", "Fecha em parte §14.4", "H7 -> A", "Entrevista direta"),
  ("H8", "Três ambientes (desenvolvimento, teste descartável por mudança, produção); dado real só sai da produção anonimizado; nenhuma credencial de produção fora dela.", "DEFINIDO", "Fecha §12 (proposto)", "H8 -> A", "Entrevista direta"),
  ("K4", "Riscos urgentes (backup, n8n, contrato com a IA, extração em N2 sem medição, proteção do repositório) resolvidos em paralelo à construção do piloto; contrato com a IA e backup prontos antes do primeiro mandato do piloto.", "DEFINIDO", "Novo", "K4 -> B", "Entrevista direta"),
  ("I2", "Retenção em 3 camadas: originais e extrações brutas apagados 6 meses após o fim do contrato; entregáveis e papéis de trabalho por 5 anos (ajustável), sem dado pessoal desnecessário; trilha de auditoria sem dado pessoal; bloqueio de expurgo com processo; benchmarks só anonimizados.", "DEFINIDO", "Revisa §13 (6 meses só para originais)", "I2 -> A", "Entrevista direta"),
  ("I5", "Relatório de impacto à proteção de dados (RIPD) antes do piloto: parte técnica pelo Claude, parte jurídica validada por advogado.", "DEFINIDO", "Novo", "a Oria é o primeiro cliente que vai usar em seus clientes que seriam os clientes externos", "Entrevista direta"),
 ]),
 ("19.10", "Negócio, Business Plan e execução", [
  ("J1", "Cobrança combinada: por mandato + assinatura de monitoramento + por usuário mais adiante; por resultado só como bônus opcional. Valores depois do piloto.", "DEFINIDO", "Novo", "J1 -> A", "Entrevista direta"),
  ("J2", "Deck mostra só o modelo de cobrança, sem valores; documentação interna ganha modelo de projeção com premissas em branco, preenchidas pelo piloto.", "DEFINIDO", "Mantém a decisão do PR #301", "J2 -> B", "Entrevista direta"),
  ("J3", "Corrigir os dados do deck (FIDC, queda de RJ em 2026, recorde de inadimplência), reconferidos na fonte oficial.", "DEFINIDO", "Fase 3", "J3 -> A", "Entrevista direta"),
  ("J4", "Slide de agentes com o catálogo de 11, sem status explícito; status real só na documentação interna do deck.", "DEFINIDO", "Fase 3", "J4 -> A mas não deixar status explícito", "Entrevista direta"),
  ("J5", "Pedido ao sócio nos 4 pilares, detalhados (time: engenheiro e analista; infraestrutura: orçamento do estudo; rede de clientes); contrapartida negociada fora do BP.", "DEFINIDO", "Fase 3", "J5 -> A", "Entrevista direta"),
  ("J6", "Medidas automáticas por mandato desde o piloto: dias, horas de analista, custo de IA e dados, erros por etapa e agente, achados em R$.", "DEFINIDO", "Novo", "J6 -> A", "Entrevista direta"),
  ("L3", "Marca própria do Oria Digital com identidade derivada da Oria Partners.", "DEFINIDO", "Fase 3", "L3 -> A", "Entrevista direta"),
  ("K1", "Plano de execução único novo; os 5 planos antigos ficam como histórico com nota de superação.", "DEFINIDO", "Fase 4", "K1 -> A", "Entrevista direta"),
  ("K2", "Plano sem calendário: sequência, dependências e critérios de pronto.", "DEFINIDO", "Revisa as datas dos planos antigos", "K2 -> C", "Entrevista direta"),
  ("K5", "Pasta Business Plan = fonte oficial de negócio e produto; Arquitetura do Sistema = fonte técnica; referências cruzadas; Apresentações = deck derivado.", "DEFINIDO", "Fase 4", "K5 -> A", "Entrevista direta"),
 ]),
]

SUBSTITUIDAS = [
 ("B3b (lote 02)", "Supervisor decide só divergências de forma.", "Substituída pela B3b-1 (inclui baixo impacto)."),
 ("D3 (1ª versão)", "Dupla leitura obrigatória (código + IA) e IA revisora comparando as duas.", "Substituída pela D3 revisada."),
 ("D3-1", "Régua da B3b-1 aplicada à divergência entre as duas leituras.", "Incorporada à D3 revisada (escolha de fonte dentro da régua)."),
 ("D3-2", "Cruzamento de todo dado extraído com fontes externas.", "Incorporada à D3 revisada (captação externa + cruzamento)."),
 ("F1 (texto do roteiro)", "Liberação de código após 3–6 meses.", "Substituída pelo gatilho F1-1/F1-2 (erros e qualidade das propostas)."),
]

REVISOES = [
 ("§1, §3 — agentes como arquitetura-alvo", "Agentes desde já, gradualmente, sobre o sistema existente; v1 com agentes e monitoramento; piloto com 4 agentes de análise.", "A1, A2, K6"),
 ("§3 — 2ª rodada com debate", "Verificação independente + debate sem limite fixo; Supervisor decide só baixo impacto, com régua objetiva.", "B3, B3b-1, L5"),
 ("§5 — até 5 tentativas automáticas", "Até 3 tentativas, nunca recalculando; motor recalcula, Auditor revisa a execução.", "B4, B5"),
 ("§6 — analista aprova o próprio diagnóstico", "Segundo revisor humano para o que vai para fora (no piloto, analista da Partners); limites de ressalva.", "E1, R1, E3, E3-1"),
 ("§9 — autoaprimoramento cria código desde o início", "Só propõe prompts e regras até ≥ 50 erros em ≥ 3 etapas e ≥ 60% de propostas aprovadas; Auditor valida os erros.", "F1, F1-1, F1-2, F1-3"),
 ("§9 — backtest com dados de clientes", "Cópias anonimizadas + dados inventados, em ambiente de teste.", "F4, H8"),
 ("§11 — publicação para todos sem fase gradual", "Por tipo de mudança: aditiva vai a todos; a que mexe em número segue caminho gradual.", "F2"),
 ("§11 — rollback automático", "Por chave liga/desliga; banco em duas etapas; backup só para desastre.", "F3"),
 ("§12 — stack proposta", "Todas as plataformas viram candidatas; estudo com ≥ 5 opções antes do piloto.", "H1, H2, H3/H5, R2"),
 ("§13 — 6 meses para tudo", "Três camadas de retenção; 6 meses só para originais.", "I2"),
 ("§14.1 — ressalvas na revisão semanal", "Sim, automaticamente, por gravidade.", "E4"),
 ("§18 — escopo da v1", "v1 com agentes e monitoramento; primeira entrega = piloto definido na K6.", "A2, K6"),
]

PENDENCIAS = [
 ("Estudo comparativo de infraestrutura (≥ 5 opções por item)", "Primeira entrega do plano; antes do piloto", "H3/H5, R2"),
 ("Valores: teto de dados pagos por mandato, teto de IA por diagnóstico, preços", "Medição no piloto", "N-C6b, D5, J1, J2"),
 ("Fornecedor do integrador de dados pagos", "Cotação", "C2"),
 ("Parceria de Open Finance (Res. Conjunta 21/2026)", "Integradora regulada", "C4"),
 ("Acesso às registradoras de recebíveis", "Parceria / participante autorizado", "C6"),
 ("Parecer jurídico: custódia de certificados, benchmarks, transferência internacional, backtest, retenção, RIPD", "Advogado", "C3, C7, D1, F4, I2, I5"),
 ("Contrato de dados com cada provedor de IA (cláusulas ANPD)", "Provedores", "D1, K4"),
 ("Quem monta o gabarito (papel)", "Equipe", "D4"),
 ("Priorização das 31 frentes de diligência", "Construção de cada agente", "B6"),
 ("Gestão das integrações", "Em aberto", "N-C5a"),
 ("Primeiro cliente além da Partners", "Em aberto", "A6"),
]

FORA = [
 ("L1", "Relação contratual e de dados entre Oria Digital e Oria Partners", "Não precisa disso agora, aqui estamos construindo o Oria digital, nao tratando de questões contratuais e legais entre empresas"),
 ("I1, I3, I4, L2", "Advogado/DPO, enquadramento COAF, cláusulas do contrato com o cliente, política de conflito de interesse", "Pode tirar as 4 se não for algo técnico que esteja diretamente relacionada com a construção do Oria Digital"),
]

REQUISITOS = [
 "Camada <code>organizacao</code> com RLS por organização, papéis Técnico e revisor da consultoria, e teste automático de vazamento (H4, E2, R1, L4).",
 "Chaves de mínimo privilégio para n8n e agentes; fim do acesso total (H2, H4).",
 "Cópia diária criptografada do banco e dos arquivos fora do provedor atual, e teste de restauração antes do piloto (H1-1, H7).",
 "Extração: leitores determinísticos por formato, IA só no que falhar, IA revisora em PDF/imagem (D3).",
 "Captação externa (SPED, Registrato, OFX, Open Finance, NF-e, fontes públicas) e cruzamento com os dois valores guardados (D3, C4, C5).",
 "Proveniência por dado (fonte, data, autorização, versão) e registro de autorizações gerais (N-C7a, N-C7b).",
 "Régua de baixo impacto e de gravidade parametrizadas e versionadas (B3b-1, G5).",
 "Fila de decisão humana com resumo + dossiê, campos estruturados, prazos por gravidade e escalonamento (N-B5a, N-B5b, E5).",
 "Botão “Conferência” por documento e estados recebido → extraído → cruzado → conferido (E6).",
 "Limites de ressalva por gravidade e seção “limitações relevantes” (E3, E3-1).",
 "Provedores de IA múltiplos com troca automática e roteamento por região permitida do cliente (D1, D2).",
 "Medição de custo por etapa e agente, com alerta; medição de dias, horas, erros e achados em R$ por mandato (D5, J6).",
 "Gabarito de 30–50 páginas reais com parte oculta; régua estatística de autonomia (~300 amostras, parte cega) e extração de volta a N1 (D4, D6, F5).",
 "Agentes do piloto: Conferidor, Dívida, Caixa, Mercado, Supervisor e Auditor; dados de mercado captados e atualizados (K6).",
 "Portal do cliente com link seguro por mandato; login com verificação em duas etapas antes do primeiro cliente além da Partners (G3).",
 "Entregáveis: Excel em fórmula com link para documento e página + relatório PDF (G4).",
 "Monitoramento com agenda configurável por cliente e relatório periódico (G1, G2).",
 "Autoaprimoramento: propostas em rascunho, relatório semanal, contagem de erros validada pelo Auditor, bloqueio de escrita sobre o que mede (F1–F6).",
 "Publicação por chave liga/desliga, caminho gradual para mudanças que afetam número, migrations em duas etapas (F2, F3).",
 "Três ambientes; dados reais fora da produção só anonimizados (H8, F4).",
 "Trilha de auditoria com cadeia de hashes e âncora externa imutável (H6).",
 "Rotina de expurgo em três camadas, com bloqueio por processo judicial (I2).",
 "Base própria de benchmarks anonimizados, só com dados cobertos por contrato (C7).",
]


def badge(st):
    cor = {"DEFINIDO": "#1f6b45", "DEFINIDO c/ condição": "#8a5a00", "ABERTO": "#9e440e", "FORA DO ESCOPO": "#5f6f82"}[st]
    return f'<strong style="color:{cor}">[{E(st)}]</strong>'


def tabela_decisoes(itens):
    linhas = []
    for cod, dec, st, rel, fala, orig in itens:
        linhas.append(
            f"<tr id=\"d-{E(cod)}\"><td><strong>{E(cod)}</strong></td><td>{E(dec)}</td><td>{badge(st)}</td>"
            f"<td>{E(rel)}</td><td><em>“{E(fala)}”</em><br/><span class=\"muted\">{E(orig)}</span></td></tr>")
    return ('<div class="table-wrap"><table><thead><tr><th>Código</th><th>Decisão</th><th>Status</th>'
            '<th>Relação com v0.1.2 / repositório</th><th>Fala do dono (trecho) · origem</th></tr></thead><tbody>'
            + "".join(linhas) + "</tbody></table></div>")


def tabela(cab, linhas):
    th = "".join(f"<th>{E(c)}</th>" for c in cab)
    trs = "".join("<tr>" + "".join(f"<td>{E(c)}</td>" for c in l) + "</tr>" for l in linhas)
    return f'<div class="table-wrap"><table><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table></div>'


total = sum(len(t[2]) for t in TEMAS)
partes = [
 '<hr/>',
 '<h2 id="sec-19">19. Adendo cumulativo v0.1.3 — Entrevista de definição completa (18–19/11/2026)</h2>',
 '<p><strong>Data do registro:</strong> 19/11/2026<br/>'
 '<strong>Natureza:</strong> decisões tomadas pelo dono do projeto numa entrevista estruturada (lotes 01–03 por voz com outro assistente; '
 'restante diretamente com o Claude), confrontadas com o registro v0.1.2, o workflow v0.2.0, o Business Plan e o repositório.<br/>'
 '<strong>Preservação:</strong> todo o texto das versões 0.1.0 a 0.1.2 acima foi mantido sem alteração. Onde uma decisão abaixo '
 'revisa uma anterior, a regra nova passa a valer e a antiga continua registrada (seção 19.11). '
 '<strong>Este adendo registra decisões de projeto; não comprova implementação.</strong></p>',
 '<h3 id="sec-19-1">19.1 Como ler este adendo</h3>',
 '<ul>'
 f'<li>{total} decisões e esclarecimentos, agrupados por tema (19.2 a 19.10). Os códigos seguem o roteiro da entrevista '
 '(A a L), as perguntas surgidas durante ela (N-…) e as de reavaliação final (R1, R2).</li>'
 '<li>A coluna “Fala do dono” traz o trecho literal que fixa a decisão. As transcrições integrais dos lotes 01–03 ficam preservadas '
 'nos arquivos <code>oria_entrevista_lote_01..03.html</code>.</li>'
 '<li><strong>[DEFINIDO]</strong> decisão aceita; <strong>[DEFINIDO c/ condição]</strong> aceita com condição ou valor a definir; '
 '<strong>[ABERTO]</strong> sem decisão; <strong>[FORA DO ESCOPO]</strong> retirada por não ser técnica.</li>'
 '<li>Contexto apurado no repositório durante a entrevista: o produto real hoje é um pipeline de dados (n8n + Postgres/Supabase + portal '
 'Next.js com export Excel); nenhum agente, supervisor, auditor-agente, autoaprimoramento, portal do cliente ou monitoramento existe ainda.</li>'
 '</ul>',
]
for sec, titulo, itens in TEMAS:
    partes.append(f'<h3 id="sec-{sec.replace(".", "-")}">{sec} {E(titulo)}</h3>')
    partes.append(tabela_decisoes(itens))
partes += [
 '<h3 id="sec-19-11">19.11 Respostas substituídas durante a entrevista (histórico)</h3>',
 tabela(["Item", "O que dizia", "Situação"], SUBSTITUIDAS),
 '<h3 id="sec-19-12">19.12 Revisões das decisões da v0.1.2</h3>',
 '<p>As regras originais continuam nas seções 1–18. A tabela indica qual passa a valer.</p>',
 tabela(["Regra da v0.1.2", "Passa a valer", "Decisões"], REVISOES),
 '<h3 id="sec-19-13">19.13 Pendências abertas e dependências de terceiros</h3>',
 tabela(["Pendência", "Depende de", "Decisões"], PENDENCIAS),
 '<h3 id="sec-19-14">19.14 Retiradas por estarem fora do escopo técnico</h3>',
 tabela(["Código", "Assunto", "Fala do dono"], FORA),
 '<h3 id="sec-19-15">19.15 Requisitos técnicos derivados (insumo das Fases 2 e 4)</h3>',
 '<ol>' + "".join(f"<li>{r}</li>" for r in REQUISITOS) + '</ol>',
 '<h3 id="sec-19-16">19.16 Registro de versão aditivo</h3>',
 tabela(["Versão", "Data", "Alteração", "Situação"], [
  ("0.1.3", "19/11/2026", f"Adendo com {total} decisões da entrevista de definição, revisões da v0.1.2, pendências, requisitos derivados e histórico de respostas substituídas. Conteúdo das versões 0.1.0–0.1.2 preservado.", "Decisões do dono; implementação não comprovada"),
 ]),
 '<p><strong>Regra de continuidade:</strong> novas decisões entram como adendo de versão seguinte, com fala, data e decisão afetada; nada é sobrescrito.</p>',
]
adendo = "\n".join(partes)

out = base
def rep(a, b):
    global out
    assert out.count(a) == 1, a[:60]
    out = out.replace(a, b)

rep("<title>Oria Digital | Registro de decisões e pendências | v0.1.2</title>",
    "<title>Oria Digital | Registro de decisões e pendências | v0.1.3</title>")
rep("Versão cumulativa 0.1.2 · 18 de novembro de 2026", "Versão cumulativa 0.1.3 · 19 de novembro de 2026")
rep('<a href="#sec-18">18. Adendo cumulativo v0.1.2 — questão anterior sobre o escopo da primeira versão</a></aside>',
    '<a href="#sec-18">18. Adendo cumulativo v0.1.2 — questão anterior sobre o escopo da primeira versão</a>\n'
    '<a href="#sec-19">19. Adendo cumulativo v0.1.3 — entrevista de definição completa</a>'
    + "".join(f'\n<a href="#sec-{s.replace(".", "-")}">&nbsp;&nbsp;{s} {E(t)}</a>' for s, t, _ in TEMAS)
    + '\n<a href="#sec-19-12">&nbsp;&nbsp;19.12 Revisões da v0.1.2</a>\n<a href="#sec-19-13">&nbsp;&nbsp;19.13 Pendências</a>'
    '\n<a href="#sec-19-15">&nbsp;&nbsp;19.15 Requisitos derivados</a></aside>')
i = out.index('<main><div class="notice">')
j = out.index('</div>', i)
out = out[:i] + ('<main><div class="notice"><strong>Atualização desta versão (0.1.3):</strong> incluída ao final a seção 19, com as '
                 f'{total} decisões da entrevista de definição, as revisões da v0.1.2, as pendências e os requisitos derivados. '
                 'Todo o texto das versões anteriores foi mantido, inclusive o aviso da v0.1.2 a seguir.</div>'
                 '<div class="notice">' + out[i + len('<main><div class="notice">'):j] + '</div>') + out[j + len('</div>'):]
rep("</article></main></div>", adendo + "\n</article></main></div>")
rep("</style>", "code{overflow-wrap:anywhere}</style>")
out_path.write_text(out, encoding="utf-8")
print("ok", total, len(out))
