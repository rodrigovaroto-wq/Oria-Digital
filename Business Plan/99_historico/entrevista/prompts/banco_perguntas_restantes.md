### Q:N-B5a
**N-B5a (confirmação). Quando as 3 tentativas automáticas falham, o que o analista recebe?**
Por que importa: no lote 02 você disse "Opção A" (relatório resumido), mas a confirmação ficou incompleta. E um resumo sozinho pode esconder a prova de que o auditor e o credor vão precisar.
- A) Um resumo (o que deu errado, as 3 tentativas, a proposta do Supervisor) **com o dossiê completo a um clique, na mesma tela**.
- B) Só o resumo.
- C) Só o dossiê completo.
★ A — rápido de ler, sem perder nenhuma evidência.

### Q:N-B5b
**N-B5b (confirmação). Como o analista registra a decisão depois de revisar?**
Por que importa: no lote 02 o "Opção A" foi dito por cima da fala do entrevistador e não houve confirmação separada.
- A) Campos estruturados: ação escolhida (aceitar, recusar, pedir revisão), justificativa obrigatória e ligação com as evidências; texto livre opcional.
- B) Só texto livre.
★ A — permite auditar e medir depois.

### Q:C6
**C6. "Recebíveis já cedidos" vira "indício" até termos acesso às registradoras?**
Por que importa: sem acesso às registradoras (CERC, B3, Núclea) não dá para **provar** que um recebível já foi cedido; dá só para ver sinais (desconto bancário no SCR, cláusula de cessão em contrato). O BP hoje promete o achado.
- A) Sim: o sistema mostra como "indício", com a evidência, e o BP passa a dizer "indício".
- B) Manter a promessa como está.
★ A.

### Q:C7
**C7. Podemos usar dados de vários clientes, anonimizados, para criar benchmarks próprios?**
Por que importa: é um diferencial forte, mas pela LGPD o Oria Digital passa a ser **controlador** desses dados (decide uma finalidade própria) e precisa de cláusula no contrato de cada cliente.
- A) Sim, com cláusula contratual e anonimização, depois de parecer jurídico.
- B) Não; só benchmarks públicos (Banco Central, CVM, IBGE…).
- C) Sim desde já.
★ A, e B até o parecer sair.

### Q:D1
**D1. Onde a IA pode processar dados de clientes?**
Por que importa: OpenAI e Anthropic não têm região Brasil; enviar dados ao exterior exige contrato de dados com as cláusulas-padrão da ANPD (prazo de adequação venceu em 23/08/2025). Só o Gemini no Google Cloud São Paulo processa aqui, e é um modelo mais antigo.
- A) Só no Brasil.
- B) Também na União Europeia (se a adequação da UE pela ANPD se confirmar).
- C) Também nos EUA, com contrato de dados (DPA) e cláusulas-padrão da ANPD assinados.
★ C ou B, com contrato assinado antes do primeiro cliente externo; A só se um cliente exigir. Depende de advogado.

### Q:D2
**D2. Um provedor de IA ou dois, com troca automática se um falhar?**
Por que importa: em 11/11 foi decidido "um só, sem reserva". Com agentes e monitoramento na v1, uma queda do provedor para tudo.
- A) Um só (mais simples).
- B) Dois, com troca automática.
★ B — revisa a decisão de 11/11.

### Q:D3
**D3. Como extrair os dados dos documentos?**
Por que importa: num teste com 42 ferramentas, o modelo GPT testado alterou valores de tabela; Claude e Gemini acertaram muito mais. E arquivos estruturados não precisam de IA.
- A) Formatos estruturados (Excel, OFX, CNAB, SPED, XML de nota) lidos **sem IA**; PDF com leitura local + IA só nas páginas de demonstração; PDF escaneado direto na IA com visão.
- B) Tudo pela IA, como hoje.
- C) Contratar fornecedor especializado de extração (ex.: Reducto).
★ A, e escolher modelo/fornecedor depois do gabarito (D4).

### Q:D4
**D4. Montamos um gabarito com 30 a 50 páginas reais (com a resposta certa) para medir e escolher o modelo?**
Por que importa: sem gabarito, trocar ou manter o modelo é palpite.
- A) Sim, antes de trocar de modelo ou fornecedor. (Pergunte quem monta e com quais documentos.)
- B) Não agora.
★ A.

### Q:D5
**D5. Qual o teto de custo de IA por diagnóstico?**
Por que importa: hoje o teto é US$ 5 por book, só com extração. Com 11 agentes, debate e monitoramento na v1, o custo sobe. (O teto para **consultas de dados pagas** já foi decidido em separado: existe, valor a definir.)
- A) Medir no primeiro mandato piloto e fixar o teto depois, com alerta se passar de US$ 5.
- B) Definir agora um teto (ele diz o valor).
★ A, usando modelo barato para classificar, médio para extrair e analisar, e caro só na síntese final.

### Q:D6
**D6. Quantas amostras "cegas" para uma etapa subir de autonomia? E a extração volta a revisão humana total até medir?**
Por que importa: hoje 30 vereditos sobem a etapa para "aceita sozinha" (N2). Estatisticamente, 30 acertos em 30 só garantem ~89%; ~300 garantem ~99%. E quem revisa vendo a sugestão da IA tende a concordar demais. Hoje a extração aceita linhas sozinha sem ter sido medida.
- A) ~300 amostras cegas e acerto mínimo de 98% para N2; a extração volta a N1 (revisão total) até lá.
- B) Manter 30 vereditos.
- C) Meio-termo (ele define).
★ A.

### Q:E1
**E1. O autor pode aprovar o próprio diagnóstico?**
Por que importa: o registro v0.1.2 permite. Normas de auditoria (ISQM 2) e bancos exigem "quatro olhos": quem fez não revisa o que vai a terceiros.
- A) Não; sempre um segundo revisor.
- B) Sim, como está no registro.
- C) Segundo revisor para itens relevantes; quando a equipe for pequena, autoaprovação com checklist e revisão posterior por amostra.
★ C agora, A quando houver equipe. Revisa o registro.

### Q:E2
**E2. Quem tem a permissão técnica (aprovar mudança de código, agentes e ferramentas), separada da permissão financeira?**
Por que importa: o registro exige essa separação, mas o papel não existe no sistema.
- A) Criar o papel "Técnico" (ele diz quem — use papéis, não nomes) e quem pediu a mudança não aprova.
- B) O Sócio acumula as duas.
★ A.

### Q:E3
**E3. Existe limite de ressalvas por diagnóstico? Quem pode aprovar com ressalva?**
Por que importa: sem limite, "aprovar com ressalva" vira carimbo.
- A) Teto de ressalvas por caso (ele diz o número); acima disso, só o Sócio aprova.
- B) Sem teto.
★ A.

### Q:E4
**E4. Pendências aprovadas com ressalva entram sozinhas na revisão semanal do agente de autoaprimoramento?**
Por que importa: é a pergunta que ficou interrompida no registro v0.1.2.
- A) Sim, automaticamente, priorizadas por gravidade.
- B) Só quando alguém pedir.
★ A.

### Q:E5
**E5. Qual o prazo para o aprovador responder, e o que acontece se não responder?**
Por que importa: com toda divergência indo ao analista (B3) e 3 tentativas antes de escalar (B5), sem prazo a fila trava.
- A) Prazo por gravidade (ex.: crítico 1 dia útil, normal 3) e escala para o Sócio.
- B) Sem prazo.
★ A. Pergunte os prazos.

### Q:E6
**E6. Criamos o botão "conferi" por documento (registra quem conferiu e quando)?**
Por que importa: hoje quase nenhum documento consegue ser marcado como "conferido por pessoa", então o sistema não distingue "recebido" de "conferido".
- A) Sim.
- B) Não.
★ A.

### Q:F1
**F1. Na primeira fase, o que o agente de autoaprimoramento pode fazer?**
Por que importa: agentes de código já foram pegos "trapaceando" testes. O registro permite que ele crie código e ferramentas.
- A) Só **propor** (abrir proposta para revisão) mudanças de prompts e regras; código, ferramentas e banco depois de 3–6 meses de histórico.
- B) Tudo, como está no registro.
★ A — revisa o registro.

### Q:F2
**F2. Como publicar uma mudança aprovada?**
Por que importa: o registro manda publicar para todos de uma vez. A prática de mercado é liberar aos poucos.
- A) Gradual: primeiro "em sombra" (roda sem efeito), depois 1–2 clientes, depois todos.
- B) Todos de uma vez, como está no registro.
- C) Todos de uma vez só se a mudança só acrescenta e não muda nenhum número no teste; senão, gradual.
★ C — revisa o registro.

### Q:F3
**F3. A reversão automática é feita por "chave liga/desliga" de cada mudança?**
Por que importa: restaurar backup não é reversão — apaga o trabalho de todos os clientes desde aquele momento.
- A) Sim, por chave; mudanças no banco só no formato "acrescenta primeiro, remove depois".
- B) Outra forma (ele descreve).
★ A.

### Q:F4
**F4. Backtest com dados de clientes antigos: com que base?**
Por que importa: usar o caso de um cliente para testar mudança que serve a outros exige permissão contratual (LGPD); e mandar esses dados a uma IA fora do Brasil é transferência internacional.
- A) Só com cláusula no contrato do cliente e, de preferência, dados anonimizados.
- B) Só com dados sintéticos (inventados para teste).
- C) Como está no registro, sem condição extra.
★ A (ou B até o contrato existir). Depende de advogado.

### Q:F5
**F5. O agente fica proibido de alterar o que o mede (gabarito, testes, portões), e existe um conjunto de teste que ele nunca vê?**
Por que importa: é a proteção contra o agente "passar na prova" trapaceando.
- A) Sim.
- B) Não.
★ A.

### Q:F6
**F6. O ciclo semanal continua? Quem recebe e analisa o relatório do agente?**
Por que importa: confirma o registro e define o responsável.
- A) Sim, semanal (ele diz quem analisa — papel, não nome).
- B) Outra frequência.
★ A.

### Q:G1
**G1. O que o monitoramento acompanha, com que frequência e para quais clientes — e qual parte entra já na v1?**
Por que importa: pela A2, monitoramento está na v1, mas ainda não existe nada construído.
- A) Empresas em pós-reestruturação e carteiras de credores: caixa, dívida, covenants, novos processos, protestos e notícias; mensal, com checagem semanal de processos e protestos.
- B) Só pós-reestruturação.
- C) Outra combinação (ele descreve).
★ A como desenho; na v1, o mínimo que ele escolher (sugestão: processos, protestos e notícias, que já estão no plano).

### Q:G2
**G2. O relatório mensal é um produto pago? O que ele contém?**
Por que importa: pode ser a receita recorrente do Oria Digital.
- A) Sim, assinatura mensal: indicadores contra o plano, alertas, variações explicadas.
- B) Incluído no preço do mandato.
★ A.

### Q:G3
**G3. Como o cliente entra no portal (que já está na v1, pela A5)?**
Por que importa: muda segurança e esforço de construção. Já existe desenho de link seguro por mandato.
- A) Link seguro sem login, por mandato.
- B) Área com login (usuário e senha).
- C) Link na v1 e login quando houver vários usuários por cliente.
★ C.

### Q:G4
**G4. O que o cliente recebe, e cada número leva até a página de origem?**
Por que importa: a rastreabilidade é o diferencial da tese ("a prova de cada número").
- A) Excel em fórmula + PDF/apresentação; cada número com link para o documento e a página.
- B) Só Excel.
★ A.

### Q:G5
**G5. Quais níveis de gravidade de alerta e qual prazo para tratar cada um?**
Por que importa: o registro manda criar, mas não define.
- A) Crítico / alto / médio / informativo, com prazos de 1 dia útil / 3 / 7 / sem prazo.
- B) Ele define.
★ A como ponto de partida.

### Q:H1
**H1. Saímos já do plano gratuito do Supabase?**
Por que importa: hoje o banco não tem backup nenhum, e há mandatos reais nele.
- A) Sim: plano Pro (~US$ 25/mês) + backup contínuo (~US$ 100/mês), região São Paulo, e backup separado dos arquivos (o backup do Supabase não inclui os arquivos).
- B) Esperar o primeiro cliente externo.
★ A, imediatamente.

### Q:H2
**H2. Para onde vai o n8n?**
Por que importa: hoje ele roda num serviço sem contrato de proteção de dados nem certificação, guardando credenciais com acesso total ao banco.
- A) Servidor próprio no Brasil.
- B) n8n Cloud na Europa, com contrato de dados.
- C) Manter onde está.
★ A ou B; C não é recomendado.

### Q:H3
**H3. Onde fica o "processo longo" (diagnóstico → revisão → monitoramento)?**
Por que importa: o workflow propõe LangGraph; o sistema atual já faz isso com estados no banco.
- A) Máquina de estados no próprio banco (como já é feito).
- B) Ferramenta de orquestração de agentes (LangGraph, como no workflow).
- C) Ferramenta de execução durável (ex.: DBOS, Temporal).
★ A; C só se A não bastar.

### Q:H4
**H4. Como separar os dados de clientes diferentes?**
Por que importa: com portal do cliente na v1 e consultorias como clientes, vazamento entre clientes é o pior erro possível.
- A) Separação por linha no mesmo banco (por organização) para a maioria; banco separado para cliente regulado (banco, fundo) que exigir.
- B) Banco separado para todos.
★ A.

### Q:H5
**H5. Onde fica a observabilidade da IA (ver cada chamada, custo e erro)?**
Por que importa: é a base do autoaprimoramento e do controle de custo.
- A) Langfuse no nosso próprio servidor (os dados não saem).
- B) Serviço na nuvem (ex.: LangSmith).
★ A.

### Q:H6
**H6. A trilha de auditoria ganha selo à prova de adulteração (cadeia de hashes + cópia diária imutável externa)?**
Por que importa: prova de integridade para credor e juiz.
- A) Sim, antes do primeiro cliente externo.
- B) Não por enquanto.
★ A.

### Q:H7
**H7. Quanto dado podemos perder no pior caso, em quanto tempo voltamos, e quando testamos a restauração?**
Por que importa: a restauração nunca foi testada.
- A) Perda máxima de minutos, volta em até 4 horas; teste de restauração trimestral, incluindo os arquivos.
- B) Ele define.
★ A.

### Q:H8
**H8. Ambientes separados (desenvolvimento, teste, produção), sem dado real fora da produção?**
Por que importa: é pré-requisito do autoaprimoramento e do backtest.
- A) Sim.
- B) Não.
★ A.

### Q:I1
**I1. Quem valida LGPD e contratos (advogado / encarregado de dados)?**
Por que importa: várias decisões (D1, F4, C3, C7, I2, I3) dependem de parecer.
- Resposta aberta: o papel ou tipo de escritório (sem dado pessoal), ou "a contratar".

### Q:I2
**I2. Como fica a retenção de dados?**
Por que importa: "apagar tudo em 6 meses" conflita com prazos legais: a Oria pode ser processada por até 10 anos (responsabilidade contratual) e pode ter dever de guarda de 5 anos (lei de lavagem, I3).
- A) Três camadas: documentos originais apagados 6 meses após o fim do contrato; entregáveis e papéis de trabalho guardados 5 ou 10 anos, sem dado pessoal desnecessário; trilha de auditoria sem dado pessoal; bloqueio de exclusão quando houver processo.
- B) Manter "6 meses para tudo".
★ A, com o prazo da camada 2 decidido com o advogado. Revisa o registro.

### Q:I3
**I3. O Oria Digital se enquadra na lei de lavagem de dinheiro (COAF) por fazer consultoria em M&A?**
Por que importa: se sim, há cadastro no COAF e guarda obrigatória de 5 anos.
- A) Verificar com advogado (adiado).
- B) Ele já sabe a resposta.
★ A.

### Q:I4
**I4. No contrato com o cliente: teto de responsabilidade, seguro de responsabilidade profissional e aviso de incidente em 24–48 h?**
Por que importa: proteção antes do primeiro cliente externo; um diagnóstico errado pode gerar processo.
- A) Sim, os três.
- B) Parte deles (quais).
★ A.

### Q:I5
**I5. Fazemos agora o relatório de impacto à proteção de dados (RIPD)?**
Por que importa: recomendado para IA + dados financeiros + envio ao exterior + custódia de certificados (C3).
- A) Sim, antes do primeiro cliente externo.
- B) Depois.
★ A.

### Q:J1
**J1. Como o Oria Digital cobra?**
Por que importa: base das projeções do BP.
- A) Por mandato (diagnóstico) + assinatura mensal de monitoramento; por usuário só depois, para bancos e fundos.
- B) Só por mandato.
- C) Só assinatura.
- D) Por resultado (percentual do ganho).
★ A. D não como base (o resultado depende de credor, juiz e especialista).

### Q:J2
**J2. Preço, receita e projeções entram agora no BP, ou seguem fora até a conversa com o sócio?**
Por que importa: no último deck isso ficou fora de propósito.
- A) Entram agora, com premissas explícitas e três cenários.
- B) Ficam fora do deck; entram só na documentação interna.
★ B.

### Q:J3
**J3. Corrigimos os dados do deck?**
Por que importa: número errado diante do investidor. FIDC: o deck diz R$ 56 bi; a Anbima registra R$ 90,8 bi em ofertas em 2025. Pedidos de recuperação judicial **caíram** no 1º semestre de 2026. A inadimplência de empresas é recorde (9,3 milhões).
- A) Sim, os três.
- B) Só alguns (quais).
★ A.

### Q:J4
**J4. O slide de agentes continua marcando 3 agentes "em operação" com a rodada real ainda não validada?**
Por que importa: a regra 5 do próprio deck proíbe afirmar no presente o que não está pronto. E agora o catálogo tem 11 agentes (B1).
- A) Trocar para "em validação" até a rodada real e atualizar para o catálogo de 11.
- B) Manter.
★ A.

### Q:J5
**J5. O que pedimos ao sócio e o que oferecemos em troca?**
Por que importa: precede qualquer projeção.
- Resposta aberta. Ajude-o a separar: o que pedimos (direção, time, infraestrutura, dados, rede de contatos, capital?) e o que oferecemos (participação, papel, prazo).

### Q:J6
**J6. Medimos desde o primeiro mandato piloto: horas do analista, custo de IA e dias até a entrega?**
Por que importa: é a prova do "dias, não meses".
- A) Sim.
- B) Não.
★ A.

### Q:K1
**K1. Qual plano vale, e quais viram histórico?**
Por que importa: hoje há cinco planos e dois MVPs diferentes no repositório.
- A) Um plano único novo, feito pelo Claude a partir desta entrevista; os outros viram histórico.
- B) Manter o plano atual e só ajustar.
★ A.

### Q:K2
**K2. Quais datas são compromisso e quais são estimativa?**
Por que importa: com agentes, monitoramento, portal do cliente e Open Finance na v1, a data de 18/12 não se sustenta.
- Resposta aberta: ele diz as datas fixas (ex.: primeiro mandato piloto com a Partners, conversa com o sócio, primeiro cliente externo).

### Q:K3
**K3. Quem constrói e quem responde por cada área?**
Por que importa: o plano precisa de responsáveis.
- A) Ele + Claude agora; o sócio traz engenheiros e especialistas depois.
- B) Outra composição (papéis, não nomes).
★ Registrar o que ele disser.

### Q:K4
**K4. Os riscos urgentes viram uma "Fase 0" antes de qualquer funcionalidade nova?**
Por que importa: hoje há mandatos reais sem backup, sem contrato de dados com a IA, repositório sem proteção conferida e extração aceitando linhas sem medição.
- A) Sim, Fase 0 primeiro.
- B) Em paralelo à construção da v1.
★ A (é curta e protege o que já existe).

### Q:K5
**K5. A pasta "Business Plan" vira a fonte oficial do negócio, e "Arquitetura do Sistema" a fonte técnica?**
Por que importa: evita dois documentos dizendo coisas diferentes.
- A) Sim.
- B) Outra organização.
★ A.

### Q:K6
**K6. (nova) Com tudo o que entrou na v1, qual é o mínimo para o primeiro mandato piloto com a Oria Partners?**
Por que importa: na entrevista entraram na v1 agentes, monitoramento, portal do cliente, Open Finance, custódia de certificados e simulação de propostas a credores. O plano antigo tinha 86 de 111 etapas sem começar. Sem um "mínimo do piloto", nada chega a ser usado.
- A) Piloto = book Excel confiável + dossiê de processos e notícias + 2 ou 3 agentes (ex.: Conferidor, Dívida, Caixa) + portal do cliente para enviar documentos; o resto entra em entregas seguintes da v1.
- B) Piloto só com tudo da v1 pronto.
- C) Outra composição (ele descreve).
★ A.

### Q:L1
**L1. Como fica a relação contratual e de dados entre Oria Digital e Oria Partners?**
Por que importa: sendo empresas separadas, os documentos dos clientes da Partners passam a ser tratados por outra empresa (LGPD e sigilo), e o sistema já guarda mandatos reais da Partners.
- A) Contrato de prestação de serviço + contrato de tratamento de dados (Oria Digital = operadora); os mandatos já existentes ficam sob esse contrato.
- B) Outra forma (ele descreve).
★ A, validado com advogado.

### Q:L2
**L2. Há conflito de interesse em atender empresas diretamente enquanto consultorias, inclusive a Partners, são clientes do Oria Digital?**
Por que importa: pela A6, os primeiros clientes podem ser empresas que precisam de reestruturação, que é o mesmo público das consultorias.
- A) Política de conflito: não atender diretamente empresa que já é cliente de uma consultoria-cliente sem autorização; informação de uma consultoria nunca vai a outra.
- B) Sem restrição.
★ A.

### Q:L3
**L3. O Oria Digital terá marca e identidade visual próprias, ou segue a da Oria Partners?**
Por que importa: Business Plan, portal e contratos.
- A) Marca própria, com identidade derivada (mesma família visual, nome próprio).
- B) Mesma identidade da Oria Partners.
- C) Totalmente nova.
★ A.

### Q:L4
**L4. Qual o papel da consultoria-cliente (ex.: a Partners) no portal?**
Por que importa: na A5 o "cliente" é a empresa; quando quem contrata é uma consultoria, ela precisa ver os mandatos dos clientes dela.
- A) A consultoria vê e acompanha os mandatos dos clientes dela, sem operar o sistema; a empresa atendida vê só o próprio mandato.
- B) A consultoria também opera (contradiz a A4 no início).
- C) Só a empresa atendida acessa.
★ A.

### Q:L5
**L5. Qual o limite de rodadas e de custo para o debate entre agentes?**
Por que importa: debate gasta muitos tokens e a pesquisa mostra pouco ganho depois da primeira rodada.
- A) Uma rodada de verificação + uma de debate; depois vai ao humano.
- B) Até 3 rodadas.
- C) Sem limite fixo; o Supervisor decide.
★ A.

### Q:L6
**L6. O nome e o papel de cada agente aparecem para o cliente, ou só internamente?**
Por que importa: relatório do cliente e Business Plan ("oito agentes").
- A) Só internamente; o cliente vê o diagnóstico e as fontes.
- B) O relatório do cliente mostra qual agente produziu cada parte.
★ A.
