"""Combinação proposta de plataformas-ponte (24/11/2026) e o que falta construir.

Fonte: pesquisa/ponte.json (48 plataformas, 4 pesquisas de 24/11/2026) e pesquisa/res_*.json
(1ª rodada, fornecedores de dados por API). Linguagem simples, para quem não está no projeto.
"""

# Nomes simples das etapas (o código E01–E17 é o mesmo da Planilha 1)
ETAPAS = [
    ("E01", "Conhecer a empresa antes do contrato"),
    ("E02", "Abrir o trabalho e colher autorizações"),
    ("E03", "Receber os documentos do cliente"),
    ("E04", "Ler os documentos e tirar os números"),
    ("E05", "Buscar dados fiscais e contábeis oficiais"),
    ("E06", "Buscar dados de bancos e dívidas"),
    ("E07", "Pesquisar riscos (processos, protestos, certidões)"),
    ("E08", "Comparar com o mercado e com empresas parecidas"),
    ("E09", "Conferir os números entre fontes"),
    ("E10", "Analisar dívida, caixa e cenários"),
    ("E11", "Inteligência artificial e agentes"),
    ("E12", "Aprovar o diagnóstico"),
    ("E13", "Entregar ao cliente (Excel, PDF, apresentação)"),
    ("E14", "Acompanhar a empresa depois"),
    ("E15", "Melhorar o sistema com o tempo"),
    ("E16", "Infraestrutura e segurança"),
    ("E17", "Medir tempo e custo de cada trabalho"),
]

# A combinação: (Plataforma, Para que usamos, Etapas, Situação, Como entra no dia a dia, Custo)
COMBINACAO = [
    ("Direct Data", "Pesquisa de risco da empresa e dos sócios: processos, protestos, certidões, sanções e cadastro",
     "E01, E07, E14", "Usar agora", "O analista consulta por CNPJ/CPF e baixa o resultado", "Paga por consulta, sem mínimo (protesto completo R$ 8,10; certidão R$ 0,36)"),
    ("JUDIT", "Processos judiciais com valor, fase e partes; avisa quando surge processo novo",
     "E07, E14", "Usar agora", "Consulta por CNPJ/CPF e liga o monitoramento das empresas do trabalho", "R$ 6,00 por mil processos; R$ 15 por empresa monitorada por mês"),
    ("Serasa Experian", "Relatório de crédito da empresa, do grupo e dos sócios: o que os credores já conhecem",
     "E01", "Usar agora", "Relatório por CNPJ no início do trabalho", "Relato (o completo): não publicado; consultas avulsas em pacote pré-pago a partir de R$ 119,99"),
    ("Klooks", "Ler balanço, DRE e demonstrativo de dívidas em PDF e devolver os números em Excel",
     "E04, E06", "Testar antes", "O analista envia o PDF e recebe a planilha padronizada em até 3 h úteis", "Não publicado; teste grátis com 5 créditos"),
    ("VERI", "Situação fiscal: certidões, pendências na Receita, parcelamentos e dívida ativa",
     "E05, E14", "Testar antes", "Painel por CNPJ, com procuração eletrônica da empresa", "Não publicado; a alternativa grátis é o analista baixar no e-CAC"),
    ("Itera", "Comparar a empresa com empresas parecidas de capital fechado; também lê balanços",
     "E08, E04", "Testar antes", "Relatório de comparação por setor e porte", "Não publicado"),
    ("Accountfy", "Montar as demonstrações a partir do balancete, juntar as empresas do grupo, cenários e caixa semanal",
     "E10, E13", "Testar antes", "O analista sobe o balancete de cada empresa e gera planilha e slides", "Não publicado"),
    ("DataSnipper", "Ligar cada número do Excel à página do documento de onde ele saiu",
     "E09, E13", "Testar antes", "Funciona dentro do Excel do analista", "Não publicado"),
    ("Keye", "Inteligência artificial que lê todos os documentos do trabalho e responde perguntas de diligência",
     "E11", "Testar antes", "O analista sobe a pasta do cliente e faz perguntas", "Não publicado"),
    ("SharePoint (já contratado)", "Pasta segura onde o cliente deixa os documentos",
     "E03", "Já temos", "Uma pasta por trabalho, com acesso do cliente", "Já pago"),
    ("Fontes públicas grátis", "Banco Central, IBGE e CVM (mercado); e-CAC e Receitanet (fiscal); Registrato que o cliente baixa (bancos)",
     "E05, E06, E08", "Usar agora", "O sistema já capta parte; o resto o analista baixa", "Grátis"),
]

# Cobertura por etapa: (Código, Coberto por, Como fica coberto, Cobertura, O que ainda falta construir)
# Cobertura: "Coberta" (a combinação resolve a etapa no dia a dia), "Em parte", "Não coberta".
COBERTURA = [
    ("E01", "Serasa Experian + Direct Data", "Relatório de crédito e pesquisa de risco antes do contrato", "Coberta",
     "Registro da autorização do cliente para consultar os sócios; apresentação pré-contrato montada sozinha"),
    ("E02", "—", "Nenhuma plataforma da ponte faz", "Não coberta",
     "Cadastro do trabalho e do grupo de empresas; autorização do cliente com data, fontes e finalidade; assinatura eletrônica (uma ferramenta simples, como Autentique, resolve)"),
    ("E03", "SharePoint (já contratado)", "Pasta segura por trabalho", "Em parte",
     "Lista de documentos esperados com o andamento de cada um; organizar os arquivos por empresa e por período; link de envio por trabalho"),
    ("E04", "Klooks (+ Itera)", "Números de balanço, DRE e dívidas tirados dos PDFs", "Em parte",
     "Leitura de arquivos oficiais (SPED, extrato OFX, CNAB) — já existe em parte no sistema; a página de origem de cada número; segunda leitura que confere a primeira"),
    ("E05", "VERI ou e-CAC manual (grátis)", "Situação fiscal e SPED baixados pelo analista", "Em parte",
     "Notas fiscais com mais de 90 dias (vêm do contador ou do sistema do cliente); usar o SPED como régua para conferir a contabilidade"),
    ("E06", "Klooks + extratos enviados pelo cliente", "Demonstrativo de dívidas e SCR lidos", "Em parte",
     "Leitor do Registrato; conferência do extrato (saldo inicial + movimento = saldo final); Open Finance, só depois de parecer jurídico; recebíveis cedidos"),
    ("E07", "Direct Data + JUDIT", "Processos, protestos, certidões e sanções da empresa e dos sócios", "Coberta",
     "Guardar cada consulta com fonte, data e custo; dossiê que mostra o que foi pesquisado e o que não foi"),
    ("E08", "Itera + fontes públicas grátis", "Comparação com o setor e dados de mercado", "Em parte",
     "Comparar o juro de cada contrato com a taxa média do Banco Central; base própria de comparação, anonimizada"),
    ("E09", "DataSnipper", "Cada número do Excel ligado à página do documento", "Em parte",
     "Cruzamento automático da contabilidade com as fontes externas e o parecer de cada divergência — é o diferencial da Oria; nota de confiança de cada dado externo"),
    ("E10", "Accountfy", "Demonstrações, grupo consolidado, cenários e caixa semanal", "Em parte",
     "Mapa da dívida com cláusulas de contrato (covenants); caixa de 13 semanas separando atraso de perda; simulação de propostas aos credores; ajustes de EBITDA"),
    ("E11", "Keye", "Perguntas e respostas sobre os documentos do trabalho", "Em parte",
     "Os agentes próprios da Oria (coordenador, auditor e especialistas), que interpretam sem nunca fazer conta"),
    ("E12", "—", "Nenhuma plataforma da ponte faz", "Não coberta",
     "Fila de decisões com gravidade e prazo; segundo revisor; limite de ressalvas; versões aprovadas guardadas"),
    ("E13", "Accountfy + DataSnipper", "Planilha e slides com a prova de cada número", "Em parte",
     "O Excel em fórmula da Oria com link à página (já existe em parte); relatório em PDF com a marca Oria; apresentação aos credores"),
    ("E14", "JUDIT + Direct Data + VERI", "Aviso de processo novo, protesto e pendência fiscal", "Em parte",
     "Relatório mensal ao cliente; alertas só no portal interno; acompanhamento de caixa e de cláusulas de dívida"),
    ("E15", "—", "Não é tarefa de plataforma externa", "Não coberta",
     "Revisão semanal dos erros, testes antes de mudar e chave para desligar uma mudança"),
    ("E16", "Infraestrutura (ver aba 'Integração definitiva')", "Banco de dados, cópia de segurança e login", "Não coberta",
     "Contratar o plano pago do banco em São Paulo, a cópia de segurança fora dele e o login com dois fatores"),
    ("E17", "—", "Nenhuma plataforma da ponte faz", "Não coberta",
     "Medir em cada trabalho: dias, horas do analista, custo de IA e de dados, erros e ganhos em R$"),
]

# Perguntas fixas para toda demo
PERGUNTAS_FIXAS = [
    "Exporta para Excel? Em que formato fica cada número?",
    "Onde os dados ficam guardados (Brasil?) e há contrato de proteção de dados (LGPD)?",
    "Mostra a fonte ou a página de origem de cada número?",
    "Qual o preço para ~4 trabalhos por mês, cada um com ~8 empresas e ~6 sócios? Há mínimo mensal ou contrato anual?",
]
