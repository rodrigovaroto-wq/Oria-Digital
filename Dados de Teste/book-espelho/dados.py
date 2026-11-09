# -*- coding: utf-8 -*-
"""Plano de contas e parâmetros do book ESPELHO. Só RÓTULOS e escalas — nenhum total.

O book imita a FORMA dos documentos reais que falharam em produção (ver
README.md): concessionária de máquinas agrícolas com plano de contas analítico
grande, balancete de 4 colunas, DRE mensal de 8 meses e balanço de 12 meses. Os
números saem de `motor.py`; aqui só mora o que um contador escreveria no plano.

Por que um plano GERADO por combinação (linha de produto × natureza, centro de
custo × despesa) e não uma lista digitada: os documentos reais têm 400–500
linhas de conta, e a dificuldade deles é o VOLUME e a repetição de rótulos
quase iguais ("Salários - Oficina", "Salários - Peças"), não a variedade. É
essa repetição que embaralha a leitura por IA quando as colunas desalinham.
"""

GRUPO = "GRUPO SERRA DO ESPELHO"

EMPRESAS = {
    "maquinas": {
        "razao_social": "SERRA DO ESPELHO MÁQUINAS AGRÍCOLAS LTDA.",
        "cnpj": "52.418.077/0001-30",
        "cidade": "Cruz Alta (RS)",
    },
    "implementos": {
        "razao_social": "ESPELHO IMPLEMENTOS E PEÇAS LTDA.",
        "cnpj": "52.418.077/0002-11",
        "cidade": "Ijuí (RS)",
    },
}

MESES = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"]

# ------------------------------------------------------------------ RESULTADO
LINHAS_NOVAS = [
    "Tratores até 100 cv", "Tratores de 100 a 200 cv", "Tratores acima de 200 cv",
    "Colheitadeiras de grãos", "Colhedoras de forragem", "Plantadeiras", "Semeadoras",
    "Pulverizadores autopropelidos", "Pulverizadores de arrasto", "Distribuidores de calcário",
    "Grades aradoras", "Roçadeiras", "Carretas agrícolas", "Enfardadoras",
]
LINHAS_USADAS = [
    "Tratores usados", "Colheitadeiras usadas", "Plantadeiras usadas", "Pulverizadores usados",
    "Implementos usados", "Máquinas retomadas", "Máquinas de demonstração", "Usados de terceiros em consignação",
]
LINHAS_PECAS = [
    "Filtros", "Pneus e câmaras", "Lubrificantes", "Baterias", "Correias", "Rolamentos",
    "Peças de motor", "Peças hidráulicas", "Peças elétricas", "Peças de desgaste",
    "Acessórios de cabine", "Kits de revisão",
]
LINHAS_SERVICOS = [
    "Revisões programadas", "Mão de obra de oficina", "Atendimento em campo",
    "Garantia ressarcida pelo fabricante", "Deslocamento técnico", "Treinamento de operadores",
    "Agricultura de precisão", "Locação de máquinas",
]

CENTROS_PESSOAL = ["Administrativo", "Comercial", "Oficina", "Peças", "Logística", "Diretoria"]
ITENS_PESSOAL = [
    "Salários", "Horas extras", "Férias", "13º salário", "INSS patronal", "FGTS",
    "Vale-transporte", "Vale-refeição", "Plano de saúde", "Seguro de vida em grupo",
    "Participação nos lucros", "Comissões", "Indenizações trabalhistas", "Treinamentos",
    "Uniformes e EPI", "Exames admissionais e periódicos",
]
CENTROS_ADM = ["Administrativo", "Comercial", "Oficina", "Peças", "Logística"]
ITENS_ADM = [
    "Energia elétrica", "Água e esgoto", "Telefonia", "Internet", "Aluguel de imóveis",
    "Condomínio", "IPTU", "Seguros", "Manutenção predial", "Manutenção de veículos",
    "Combustíveis", "Pedágios", "Viagens", "Hospedagem", "Refeições", "Material de escritório",
    "Material de limpeza", "Correios e malotes", "Honorários contábeis", "Honorários advocatícios",
    "Consultoria", "Software e licenças", "Depreciação", "Amortização",
]

# (código, rótulo, filhos) — filhos é lista de (rótulo, natureza_dre) para as
# folhas. Natureza: "R" receita (saldo credor), "D" despesa (saldo devedor).
# A ordem das folhas é a ordem do plano; a ordem da DRE é outra (cascata),
# montada em `demonstracoes.py`.
def _plano_resultado():
    g = []
    g.append(("3.01.01", "VENDA DE MÁQUINAS NOVAS", [(f"Venda - {x}", "R") for x in LINHAS_NOVAS]))
    g.append(("3.01.02", "VENDA DE MÁQUINAS USADAS", [(f"Venda - {x}", "R") for x in LINHAS_USADAS]))
    g.append(("3.01.03", "VENDA DE PEÇAS E ACESSÓRIOS", [(f"Venda de peças - {x}", "R") for x in LINHAS_PECAS]))
    g.append(("3.01.04", "RECEITA DE SERVIÇOS", [(f"Serviços - {x}", "R") for x in LINHAS_SERVICOS]))
    g.append(("3.01.05", "RECEITA DE COMISSÕES E BONIFICAÇÕES", [
        ("Comissão sobre consórcio", "R"), ("Comissão sobre financiamento", "R"),
        ("Comissão sobre seguros", "R"), ("Bonificação de montadora", "R")]))
    g.append(("3.02.01", "RECEITAS FINANCEIRAS", [
        ("Rendimentos de aplicações financeiras", "R"), ("Juros recebidos de clientes", "R"),
        ("Descontos obtidos", "R"), ("Variação cambial ativa", "R"), ("Variação monetária ativa", "R"),
        ("Equalização de juros - FINAME", "R"), ("Atualização de depósitos judiciais", "R"),
        ("Juros sobre capital próprio recebidos", "R")]))
    g.append(("3.03.01", "OUTRAS RECEITAS OPERACIONAIS", [
        ("Ganho na venda de imobilizado", "R"), ("Recuperação de despesas", "R"),
        ("Aluguéis recebidos", "R"), ("Indenizações de seguros", "R"),
        ("Reversão de provisões", "R"), ("Créditos extemporâneos de PIS/COFINS", "R")]))
    g.append(("4.01.01", "IMPOSTOS SOBRE VENDAS", [(f"{x} sobre vendas", "D") for x in
                                                   ("ICMS", "ICMS-ST", "PIS", "COFINS", "IPI", "ISS")]))
    g.append(("4.01.02", "DEVOLUÇÕES DE VENDAS", [(f"Devoluções - {x}", "D") for x in LINHAS_NOVAS[:10]]))
    g.append(("4.01.03", "DESCONTOS INCONDICIONAIS", [(f"Descontos concedidos - {x}", "D") for x in
                                                      ("máquinas novas", "máquinas usadas", "peças",
                                                       "serviços", "campanhas de safra")]))
    g.append(("4.02.01", "CUSTO DAS MÁQUINAS NOVAS VENDIDAS", [(f"CMV - {x}", "D") for x in LINHAS_NOVAS]))
    g.append(("4.02.02", "CUSTO DAS MÁQUINAS USADAS VENDIDAS", [(f"CMV - {x}", "D") for x in LINHAS_USADAS]))
    g.append(("4.02.03", "CUSTO DAS PEÇAS VENDIDAS", [(f"CMV peças - {x}", "D") for x in LINHAS_PECAS]))
    g.append(("4.02.04", "CUSTO DOS SERVIÇOS PRESTADOS", [(f"CSP - {x}", "D") for x in LINHAS_SERVICOS]))
    for i, c in enumerate(CENTROS_PESSOAL, 1):
        g.append((f"4.03.{i:02d}", f"PESSOAL - {c.upper()}", [(f"{x} - {c}", "D") for x in ITENS_PESSOAL]))
    for i, c in enumerate(CENTROS_ADM, 1):
        g.append((f"4.04.{i:02d}", f"ADMINISTRATIVAS - {c.upper()}", [(f"{x} - {c}", "D") for x in ITENS_ADM]))
    g.append(("4.05.01", "DESPESAS COMERCIAIS", [(x, "D") for x in (
        "Fretes sobre vendas", "Comissões de representantes", "Propaganda e publicidade",
        "Feiras e exposições", "Dias de campo", "Brindes", "Marketing digital",
        "Garantia não ressarcida", "Revisões gratuitas de entrega", "Preparação de entrega",
        "Perdas estimadas com créditos (PECLD)", "Perdas com clientes", "Seguro de crédito",
        "Despesas com consórcio", "Test-drive e demonstrações", "Catálogos e material técnico",
        "Patrocínios", "Bonificação a vendedores", "Taxas de cartão", "Despesas com leilões")]))
    g.append(("4.06.01", "DESPESAS TRIBUTÁRIAS", [(x, "D") for x in (
        "Taxas municipais", "IOF", "Contribuição sindical patronal", "Multas fiscais", "ITR",
        "IPVA", "Taxa de fiscalização", "Emolumentos cartoriais")]))
    g.append(("4.07.01", "DESPESAS FINANCEIRAS", [(x, "D") for x in (
        "Juros de capital de giro", "Juros de FINAME", "Juros de floor plan", "Juros de mora",
        "Descontos concedidos financeiros", "Tarifas bancárias", "IOF sobre empréstimos",
        "Variação cambial passiva", "Variação monetária passiva", "Juros de parcelamento tributário",
        "Deságio na antecipação de recebíveis", "Comissão de fiança bancária", "Encargos de leasing",
        "Juros sobre mútuo de sócios")]))
    g.append(("4.08.01", "OUTRAS DESPESAS OPERACIONAIS", [(x, "D") for x in (
        "Perda na baixa de imobilizado", "Perdas de estoque", "Provisão para contingências",
        "Doações", "Multas contratuais", "Sinistros não indenizados")]))
    g.append(("4.09.01", "IMPOSTO DE RENDA E CONTRIBUIÇÃO SOCIAL", [(x, "D") for x in (
        "IRPJ corrente", "CSLL corrente", "IRPJ diferido", "CSLL diferido")]))
    return g


PLANO_RESULTADO = _plano_resultado()

# Rótulos dos níveis sintéticos acima dos grupos de folhas.
SINTETICAS_RESULTADO = {
    "3": "RECEITAS", "3.01": "RECEITA OPERACIONAL BRUTA", "3.02": "RECEITAS FINANCEIRAS",
    "3.03": "OUTRAS RECEITAS OPERACIONAIS",
    "4": "CUSTOS E DESPESAS", "4.01": "DEDUÇÕES DA RECEITA BRUTA", "4.02": "CUSTO DAS VENDAS E SERVIÇOS",
    "4.03": "DESPESAS COM PESSOAL", "4.04": "DESPESAS ADMINISTRATIVAS", "4.05": "DESPESAS COMERCIAIS",
    "4.06": "DESPESAS TRIBUTÁRIAS", "4.07": "DESPESAS FINANCEIRAS", "4.08": "OUTRAS DESPESAS OPERACIONAIS",
    "4.09": "TRIBUTOS SOBRE O LUCRO",
}

# Escala base mensal de cada grupo de resultado, em REAIS (o motor converte em
# centavos e espalha pelas folhas com ruído determinístico).
BASE_MENSAL = {
    "3.01.01": 2_600_000, "3.01.02": 520_000, "3.01.03": 160_000, "3.01.04": 95_000,
    "3.01.05": 60_000, "3.02.01": 18_000, "3.03.01": 9_000,
    "4.01.01": 210_000, "4.01.02": 22_000, "4.01.03": 30_000,
    "4.02.01": 2_150_000, "4.02.02": 455_000, "4.02.03": 105_000, "4.02.04": 52_000,
    "4.03": 1_500, "4.04": 450, "4.05.01": 60_000, "4.06.01": 6_000, "4.07.01": 300_000,
    "4.08.01": 4_000, "4.09.01": 12_000,
}

# --------------------------------------------------------------- PATRIMONIAL
# (código do grupo, rótulo, [(rótulo da folha, saldo base em REAIS)]). Saldo
# NEGATIVO no ativo é conta redutora (natureza credora) e sai entre parênteses.
BANCOS = ["Banco Meridional S.A.", "Banco do Planalto S.A.", "Coop. de Crédito Vale do Espelho",
          "Banco Austral S.A."]

PLANO_PATRIMONIAL = [
    ("1.01.01", "DISPONÍVEL", [
        ("Caixa geral", 18_000), ("Caixa da oficina", 3_500), ("Fundo fixo", 2_000),
        *[(f"{b} - conta movimento", 0) for b in BANCOS],  # Meridional = conta que FECHA
        ("Aplicação CDB - Banco Meridional", 420_000), ("Aplicação CDB - Banco do Planalto", 260_000),
        ("Aplicação compromissada - Coop. Vale do Espelho", 180_000),
        ("Fundo DI - Banco Austral", 95_000)]),
    ("1.01.02", "CLIENTES", [
        ("Duplicatas a receber - máquinas", 6_900_000), ("Duplicatas a receber - peças", 780_000),
        ("Duplicatas a receber - serviços", 310_000), ("Cartões a receber", 95_000),
        ("Cheques em cobrança", 42_000), ("FINAME a receber - repasse", 3_100_000),
        ("Consórcio a receber", 640_000), ("Montadora - garantias a receber", 285_000),
        ("Montadora - bonificações a receber", 410_000),
        ("(-) Perdas estimadas com créditos de liquidação duvidosa", -390_000)]),
    ("1.01.03", "ESTOQUES", [
        ("Tratores novos", 7_800_000), ("Colheitadeiras novas", 9_400_000),
        ("Plantadeiras e semeadoras novas", 2_100_000), ("Pulverizadores novos", 3_300_000),
        ("Implementos novos", 1_250_000), ("Máquinas usadas", 2_900_000),
        ("Peças - filtros e lubrificantes", 410_000), ("Peças - pneus", 380_000),
        ("Peças - motor e transmissão", 920_000), ("Peças - hidráulica", 640_000),
        ("Peças - elétrica e eletrônica", 455_000), ("Peças - desgaste e acessórios", 515_000),
        ("Serviços em andamento", 120_000), ("Mercadorias em trânsito", 1_150_000),
        ("Adiantamentos a fornecedores", 340_000), ("(-) Provisão para obsolescência", -260_000)]),
    ("1.01.04", "TRIBUTOS A RECUPERAR", [
        ("ICMS a recuperar", 610_000), ("ICMS-ST a ressarcir", 215_000), ("PIS a recuperar", 48_000),
        ("COFINS a recuperar", 221_000), ("IPI a recuperar", 33_000), ("IRRF a compensar", 27_000),
        ("IRPJ estimativa mensal", 140_000), ("CSLL estimativa mensal", 52_000),
        ("INSS a compensar", 19_000), ("Créditos extemporâneos", 380_000)]),
    ("1.01.05", "OUTROS CRÉDITOS", [
        ("Adiantamentos a empregados", 22_000), ("Adiantamento de férias", 64_000),
        ("Despesas antecipadas - seguros", 88_000), ("Despesas antecipadas - outras", 31_000),
        ("Depósitos caução", 45_000), ("Créditos com montadora - campanhas", 260_000)]),
    ("1.02.01", "REALIZÁVEL A LONGO PRAZO", [
        ("Depósitos judiciais trabalhistas", 185_000), ("Depósitos judiciais cíveis", 72_000),
        ("Depósitos judiciais tributários", 410_000), ("Créditos tributários de longo prazo", 530_000),
        ("Consórcios a contemplar", 260_000), ("IRPJ e CSLL diferidos ativos", 340_000)]),
    ("1.02.02", "INVESTIMENTOS", [
        ("Quotas de cooperativa de crédito", 96_000), ("Cotas de consórcio próprio", 140_000),
        ("Imóveis para renda", 1_350_000)]),
    ("1.02.03", "IMOBILIZADO", [
        ("Terrenos", 2_400_000), ("Edificações", 5_800_000), ("(-) Depreciação de edificações", -1_420_000),
        ("Benfeitorias em imóveis de terceiros", 640_000), ("(-) Amortização de benfeitorias", -205_000),
        ("Máquinas e equipamentos de oficina", 1_380_000), ("(-) Depreciação de máquinas e equipamentos", -610_000),
        ("Ferramentas", 260_000), ("(-) Depreciação de ferramentas", -140_000),
        ("Veículos leves", 920_000), ("(-) Depreciação de veículos leves", -480_000),
        ("Caminhões e pranchas", 1_650_000), ("(-) Depreciação de caminhões e pranchas", -790_000),
        ("Móveis e utensílios", 310_000), ("(-) Depreciação de móveis e utensílios", -170_000),
        ("Equipamentos de informática", 285_000), ("(-) Depreciação de informática", -198_000),
        ("Instalações", 540_000), ("(-) Depreciação de instalações", -233_000),
        ("Máquinas de demonstração", 1_120_000), ("(-) Depreciação de máquinas de demonstração", -260_000),
        ("Imobilizado em andamento", 480_000)]),
    ("1.02.04", "INTANGÍVEL", [
        ("Softwares", 410_000), ("(-) Amortização de softwares", -265_000), ("Marcas e patentes", 35_000),
        ("Direito de concessão de revenda", 900_000), ("(-) Amortização do direito de concessão", -300_000)]),
    ("2.01.01", "FORNECEDORES", [
        ("Montadora - máquinas", 9_800_000), ("Montadora - peças", 1_150_000),
        ("Fornecedores nacionais", 640_000), ("Fornecedores de serviços", 180_000),
        ("Fornecedores estrangeiros", 230_000)]),
    ("2.01.02", "EMPRÉSTIMOS E FINANCIAMENTOS", [
        ("Capital de giro - Banco Meridional", 2_100_000), ("Capital de giro - Banco do Planalto", 1_400_000),
        ("Capital de giro - Coop. Vale do Espelho", 900_000), ("Floor plan - montadora", 6_200_000),
        ("FINAME - parcelas de curto prazo", 1_800_000), ("Conta garantida - Banco Austral", 650_000),
        ("Antecipação de recebíveis", 1_100_000), ("Cédula de crédito bancário - curto prazo", 760_000)]),
    ("2.01.03", "OBRIGAÇÕES TRABALHISTAS", [
        ("Salários a pagar", 520_000), ("Pró-labore a pagar", 60_000), ("Provisão de férias", 610_000),
        ("Provisão de 13º salário", 380_000), ("INSS a recolher", 210_000), ("FGTS a recolher", 72_000),
        ("IRRF sobre folha", 64_000), ("Contribuição assistencial", 6_500),
        ("Participação nos lucros a pagar", 240_000), ("Pensão alimentícia a repassar", 4_200)]),
    ("2.01.04", "OBRIGAÇÕES TRIBUTÁRIAS", [
        ("ICMS a recolher", 260_000), ("ICMS-ST a recolher", 95_000), ("PIS a recolher", 22_000),
        ("COFINS a recolher", 101_000), ("IPI a recolher", 14_000), ("ISS a recolher", 9_000),
        ("IRPJ a recolher", 88_000), ("CSLL a recolher", 34_000), ("IRRF de terceiros", 11_000),
        ("CSRF retidos a recolher", 7_500), ("Parcelamento federal - curto prazo", 310_000),
        ("Parcelamento estadual - curto prazo", 145_000)]),
    ("2.01.05", "ADIANTAMENTOS DE CLIENTES", [
        ("Adiantamentos - máquinas", 2_300_000), ("Adiantamentos - consórcio", 410_000),
        ("Adiantamentos - serviços", 55_000)]),
    ("2.01.06", "OUTRAS OBRIGAÇÕES", [
        ("Comissões a pagar", 190_000), ("Aluguéis a pagar", 45_000), ("Seguros a pagar", 38_000),
        ("Dividendos a pagar", 0), ("Contas a pagar diversas", 92_000), ("Garantias a pagar", 75_000)]),
    ("2.02.01", "EMPRÉSTIMOS E FINANCIAMENTOS - LONGO PRAZO", [
        ("Capital de giro LP - Banco Meridional", 3_200_000), ("Capital de giro LP - Banco do Planalto", 2_100_000),
        ("Capital de giro LP - Coop. Vale do Espelho", 1_500_000), ("FINAME - longo prazo", 5_400_000),
        ("Cédula de crédito bancário - longo prazo", 1_900_000)]),
    ("2.02.02", "PARCELAMENTOS TRIBUTÁRIOS - LONGO PRAZO", [
        ("Parcelamento federal - longo prazo", 1_650_000), ("Parcelamento estadual - longo prazo", 720_000)]),
    ("2.02.03", "PROVISÕES", [
        ("Provisão para contingências trabalhistas", 640_000), ("Provisão para contingências cíveis", 210_000),
        ("Provisão para contingências tributárias", 530_000)]),
    ("2.02.04", "OUTRAS OBRIGAÇÕES DE LONGO PRAZO", [
        ("Mútuos com sócios", 1_800_000), ("IRPJ e CSLL diferidos passivos", 290_000)]),
    ("2.03.01", "CAPITAL E RESERVAS", [
        ("Capital social subscrito e integralizado", 0), ("Reserva legal", 1_240_000),
        ("Reserva de lucros", 600_000), ("Ajuste de avaliação patrimonial", 220_000),
        ("Lucros ou prejuízos acumulados", 0), ("Resultado do exercício", 0)]),
]

SINTETICAS_PATRIMONIAL = {
    "1": "ATIVO", "1.01": "ATIVO CIRCULANTE", "1.02": "ATIVO NÃO CIRCULANTE",
    "2": "PASSIVO E PATRIMÔNIO LÍQUIDO", "2.01": "PASSIVO CIRCULANTE", "2.02": "PASSIVO NÃO CIRCULANTE",
    "2.03": "PATRIMÔNIO LÍQUIDO",
}

# A conta que fecha o balanço mês a mês (o caixa de verdade de uma
# concessionária é a conta movimento do banco principal).
CONTA_QUE_FECHA = "Banco Meridional S.A. - conta movimento"

# Capital social: o MESMO número que o contrato social repete quatro vezes.
CAPITAL_SOCIAL = 12_400_000
SOCIOS = [  # quatro sócios com 25% cada — quatro valores iguais, LEGÍTIMOS
    ("Ademar Luiz Fontana", "421.118.730-05"),
    ("Cleusa Maria Fontana Rech", "538.204.910-62"),
    ("Valdir José Fontana", "617.390.440-18"),
    ("Neiva Terezinha Fontana Bortolini", "702.885.160-41"),
]

# Resultado de 2025 da Máquinas (a DRE sintética anual o reproduz e o balanço
# de dezembro de 2025 o carrega no PL). Em REAIS.
LUCROS_ACUMULADOS_INICIO_2025 = 2_150_000
