"""Gera a Planilha 1 — funcionalidades, integrações e dados do Oria Digital.

Uso:  python3 -I gerar_planilha_1_funcionalidades.py <saida.xlsx>

Fontes (nenhum item foi inventado; cada linha cita a decisão ou o documento de origem):
- Registro de decisões v0.1.6 (Business Plan/07_decisoes)
- Workflow v0.3.0, AGENTES.md, REGRAS_E_DEFINICOES.md, governança, plano de execução
- Espec. 12, 13 e 15 (Arquitetura do Sistema/2 Especificação)
- A aba "Dados a captar" é lida de 13_anexos/Plano_de_Captacao_v3.xlsx (179 linhas, verificada em
  27/10/2026) — não é redigitada, para as duas planilhas não divergirem.
"""
import sys
from pathlib import Path

import openpyxl
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

RAIZ = Path(__file__).resolve().parents[3]
CAPTACAO = RAIZ / "Arquitetura do Sistema/2 Especificação/13_anexos/Plano_de_Captacao_v3.xlsx"

FONTE = "Arial"
AZUL_ESCURO = "1F3A5F"
CINZA = "F2F2F2"
BORDA = Border(*(Side(style="thin", color="BFBFBF"),) * 4)

# ---------------------------------------------------------------------------
# Etapas do processo — a chave que liga a Planilha 1 à Planilha 2
# ---------------------------------------------------------------------------
ETAPAS = [
    ("E01", "Pré-mandato e prospecção", "Capta", "Antes do NDA: cadastro, sanções, bureau e processos da empresa e dos sócios para a apresentação pré-mandato", "Espec. 13 §1–§3; D13.4"),
    ("E02", "Abertura do mandato e autorizações", "Capta", "Mandato, perímetro do grupo, autorização geral do cliente (LGPD), consentimentos e procurações", "N-C7b; C3; Espec. 13 §3"),
    ("E03", "Recebimento de documentos", "Capta", "Portal/link seguro do cliente, Kit do mandato, upload em lote, bases volumosas", "A5; G3; E6; C5"),
    ("E04", "Extração e classificação de documentos", "Capta", "Código primeiro, IA só onde o código falha, IA revisora em PDF/imagem", "D3; D6; D6-1"),
    ("E05", "Captação fiscal e contábil oficial", "Capta", "SPED, NF-e/CT-e/NFS-e, situação fiscal, parcelamentos, dívida ativa", "D3; C4; Espec. 12"),
    ("E06", "Captação bancária e de crédito", "Capta", "OFX/CNAB, Open Finance, Registrato/SCR, indicadores de recebíveis, registradoras", "C4; C5; C6; D13.1"),
    ("E07", "Captação de risco", "Capta", "Bureau, protestos, processos, certidões, sanções, PEP, notícias, matrículas de imóveis", "C2; N-C6b; K6 (dossiê)"),
    ("E08", "Dados de mercado e benchmarks", "Diagnostica", "Macro, juros por modalidade, setor, CVM, pares, benchmarks próprios anonimizados", "K6; C7; 1.C1–1.C5"),
    ("E09", "Cruzamento e score do dado externo", "Diagnostica", "Extração × captação, veredito do Conferidor, portão de confiabilidade por agente", "D3; D3-3; D15–D15.15"),
    ("E10", "Motor de cálculo e análises", "Calcula", "Toda conta no banco ou em fórmula: dívida, caixa 13 semanas, giro, mercado, cenários, QoE", "B2; B4; B7; B8"),
    ("E11", "Orquestração dos agentes e IA", "Calcula", "Supervisor, Auditor, especialistas, provedores de IA, custo, observabilidade", "B1; B3; B3b-1; B4; B5; D1; D2; D5"),
    ("E12", "Decisão humana e aprovação", "Recomenda", "Fila com gravidade e prazo, segundo revisor, ressalvas, versões aprovadas", "G5; E1–E6; N-B5a–c"),
    ("E13", "Entregáveis", "Entrega", "Excel em fórmula com link número → página, PDF, relatório interno, apresentação a credores", "G4; L6; E3-1"),
    ("E14", "Monitoramento contínuo e alertas", "Entrega", "Reconsulta periódica, alertas só no portal interno, relatório mensal", "G1; G2; v0.1.2 §7–§8"),
    ("E15", "Autoaprimoramento e mudanças técnicas", "Transversal", "Propostas semanais, backtest, gabarito oculto, chave liga/desliga, publicação gradual", "F1–F6; E2; E4"),
    ("E16", "Plataforma, segurança e continuidade", "Transversal", "Banco, arquivos, RLS por organização, 2FA, trilha com hash, backup, ambientes, retenção", "H1–H8; I2; I5"),
    ("E17", "Medição e gestão do mandato", "Transversal", "Dias, horas, custo de IA e de dados, erros por etapa/agente, achados em R$", "J6; D5; N-C6b"),
]

# ---------------------------------------------------------------------------
# Funcionalidades
# (ID, Etapa, Módulo, Funcionalidade, O que faz / critério, Decisões, Agente/papel,
#  Entrega, Situação hoje, Item do plano, Natureza, Categoria de parceiro)
# Natureza: "Construir (núcleo)" = é o valor da Oria; "Parceiro" = commodity que um fornecedor
# entrega; "Construir sobre parceiro" = a Oria constrói a regra em cima do dado/serviço comprado;
# "Plataforma (comprar)" = infraestrutura.
# ---------------------------------------------------------------------------
F = [
    # E01
    ("E01", "Pré-mandato", "Caso em momento pré-mandato", "Caso criado como pré-mandato só recebe consultas, nunca documento; passagem a mandato com autor e data", "Espec. 13 §3 (caso.momento)", "Analista", "V1", "Desenvolver", "Espec. 13 Etapa 3", "Construir (núcleo)", "—"),
    ("E01", "Pré-mandato", "Consulta de cadastro CNPJ, QSA, CNAE e situação", "Dado aberto da Receita para empresa e grupo; vira a lista de nomes a pesquisar", "Espec. 13 §1; 1.H2", "Captador", "Piloto", "Desenvolver", "1.H2", "Construir sobre parceiro", "Dados cadastrais / KYC"),
    ("E01", "Pré-mandato", "Bureau de crédito da empresa e dos sócios", "Pendências, protestos, RJ/falência, ações, quadro societário e score — só com autorização registrada", "D13.4; R5 Espec. 13", "Captador / Risco", "V1", "Desenvolver", "Espec. 13 Etapa 5; 2.4", "Parceiro", "Bureau de crédito"),
    ("E01", "Pré-mandato", "Apresentação pré-mandato (.pptx) a partir de consultas externas", "Deck sem documento do cliente; dimensão não pesquisada aparece como 'não pesquisado' com efeito", "D13.4; Espec. 13 Etapa 6", "Entregas", "V1", "Existe · evoluir", "Espec. 13 Etapa 6", "Construir (núcleo)", "—"),
    # E02
    ("E02", "Abertura", "Cadastro do mandato e perímetro do grupo", "Empresas do grupo com CNPJ, papel, controle e escopo do combinado", "1.A8", "Analista", "Piloto", "Existe · evoluir", "1.A8", "Construir (núcleo)", "—"),
    ("E02", "Abertura", "Autorização geral por cliente (LGPD)", "Registro com data, fontes e finalidade; consulta externa sem autorização é recusada no banco", "N-C7b; R5", "Sistema", "Piloto", "Desenvolver", "1.B7", "Construir (núcleo)", "—"),
    ("E02", "Abertura", "Assinatura eletrônica da autorização, do termo de kickoff e do consentimento", "Autorização pré-mandato (1 página), termo de kickoff, termo de Open Finance assinados digitalmente e guardados", "Espec. 13 §5; N-C7b", "Analista", "Piloto", "Desenvolver", "1.H1", "Parceiro", "Assinatura eletrônica"),
    ("E02", "Abertura", "Cofre de certificado digital e procuração do cliente", "Custódia segura do e-CNPJ/procuração; ativado só após política de segurança e parecer jurídico", "C3", "Técnico", "Futuro", "Desenvolver", "4.2", "Construir sobre parceiro", "Captação fiscal (e-CAC)"),
    ("E02", "Abertura", "Configuração de fontes, metas e limites do mandato", "Fontes autorizadas, indicadores, teto de custo de dados por mandato", "v0.1.1 §2; N-C6b", "Analista", "Piloto", "Desenvolver", "2.4", "Construir (núcleo)", "—"),
    # E03
    ("E03", "Recebimento", "Link seguro de envio por mandato", "Cliente envia e acompanha sem operar; login 2FA antes do 1º cliente além da Partners", "A5; G3", "Cliente", "Piloto", "Existe · evoluir", "1.G1", "Construir (núcleo)", "Autenticação 2FA"),
    ("E03", "Recebimento", "Kit do mandato com estados", "Lista de documentos esperados: recebido → extraído → cruzado → conferido; Registrato obrigatório", "E6; C5", "Sistema", "Piloto", "Existe · evoluir", "1.F4", "Construir (núcleo)", "—"),
    ("E03", "Recebimento", "Upload em lote e classificação automática", "Organiza cada arquivo em Mandato × Empresa × Tipo × Período", "f0/02 (ingestão)", "Captador", "Piloto", "Existe", "—", "Construir (núcleo)", "—"),
    ("E03", "Recebimento", "Envio de bases volumosas (AR/AP até 1M linhas)", "Leitura em fluxo, mapeamento de colunas confirmado pelo analista", "1.A1; 1.A3", "Captador", "Piloto", "Existe · evoluir", "1.A1, 1.A3", "Construir (núcleo)", "—"),
    ("E03", "Recebimento", "Detecção de duplicata por fingerprint", "Mesmo arquivo enviado duas vezes não entra duas vezes", "AGENTES.md (Captador)", "Sistema", "Piloto", "Existe", "—", "Construir (núcleo)", "—"),
    ("E03", "Recebimento", "Busca de arquivos no dataroom (SharePoint)", "Integração futura via Microsoft Graph; hoje upload manual", "f0/02; D13.2", "Sistema", "Futuro", "Desenvolver", "—", "Construir sobre parceiro", "Dataroom (já contratado)"),
    # E04
    ("E04", "Extração", "Leitores determinísticos de leiaute oficial", "SPED/EFD, CNAB, OFX, XML fiscal lidos por código, sem IA", "D3", "Captador", "Piloto", "Existe · evoluir", "1.B1", "Construir (núcleo)", "—"),
    ("E04", "Extração", "Extração por IA de PDF e imagem (só onde o código falha)", "Demonstrações, contratos, notas explicativas, Registrato em PDF → linhas com página e trecho literal", "D3; 1.A5", "Captador", "Piloto", "Existe · evoluir", "1.B1, 1.A5", "Construir sobre parceiro", "Extração de PDF / OCR"),
    ("E04", "Extração", "IA revisora de PDF e imagem", "Segunda leitura confere a primeira; divergência vira pendência", "D3", "Captador", "Piloto", "Desenvolver", "1.B2", "Construir sobre parceiro", "Modelos de IA (LLM)"),
    ("E04", "Extração", "Classificação de documentos", "Tipo, empresa e período de cada arquivo; volta a N1 até ser medida", "D6-1", "Captador", "Piloto", "Existe · evoluir", "0.5", "Construir sobre parceiro", "Modelos de IA (LLM)"),
    ("E04", "Extração", "A linha tem endereço", "Toda linha extraída com página e trecho; valor sem trecho literal abre pendência", "1.A5; G4", "Captador", "Piloto", "Existe · evoluir", "1.A5", "Construir (núcleo)", "—"),
    ("E04", "Extração", "Leitor de fatos em texto (covenant, litígio, garantia)", "Fatos materiais lidos do texto do documento com gravidade", "AGENTES.md (0148)", "Captador", "Piloto", "Existe", "—", "Construir (núcleo)", "—"),
    ("E04", "Extração", "Número novo × reapresentado por período", "Mostra o igual, o novo e o reapresentado quando um ano traz o anterior diferente", "1.A10", "Conferidor", "Piloto", "Desenvolver", "1.A10", "Construir (núcleo)", "—"),
    # E05
    ("E05", "Fiscal", "Captação de SPED (ECD, ECF, EFD) como fonte de referência", "Versão entregue ao fisco serve de régua do cruzamento; recibo confere custódia", "D3; D15.1", "Captador", "Piloto", "Existe · evoluir", "1.B4", "Construir (núcleo)", "—"),
    ("E05", "Fiscal", "Captura automática de NF-e, CT-e e NFS-e por CNPJ", "XMLs emitidos e recebidos de 12–24 meses sem depender do ERP do cliente", "D3; Espec. 12 §9", "Captador", "V1", "Desenvolver", "—", "Parceiro", "Documentos fiscais eletrônicos"),
    ("E05", "Fiscal", "Situação fiscal (e-CAC/SITFIS), parcelamentos e DCTFWeb", "Relatório de situação fiscal com a Oria como procuradora", "Espec. 13 §8a", "Captador", "V1", "Desenvolver", "—", "Parceiro", "Captação fiscal (e-CAC)"),
    ("E05", "Fiscal", "Dívida ativa (PGFN) por CNPJ", "Inscrições, valor e situação; passivo fiscal fora da RJ", "1.H2", "Captador", "Piloto", "Desenvolver", "1.H2", "Construir sobre parceiro", "Dados públicos (grátis)"),
    # E06
    ("E06", "Bancário", "OFX lido e conciliado", "Saldo inicial + Σ transações = saldo final, por conta e mês", "1.A4", "Caixa", "Piloto", "Existe · evoluir", "1.A4", "Construir (núcleo)", "—"),
    ("E06", "Bancário", "CNAB de cobrança e pagamento", "Liquidações por dia e sacado cruzadas com o AR; DSO e DPO reais", "1.A9", "Caixa", "Piloto", "Existe · evoluir", "1.A9", "Construir (núcleo)", "—"),
    ("E06", "Bancário", "Open Finance PJ via integradora regulada", "Extrato, e se disponível empréstimos e cartões PJ; upload manual sempre disponível; consentimento expirado ≠ sem movimento", "C4; D13.1", "Caixa / Dívida", "V1", "Desenvolver", "2.5", "Parceiro", "Open Finance PJ"),
    ("E06", "Bancário", "Leitura do Registrato/SCR", "Item obrigatório do Kit; PDF do gov.br lido; ausente = pendência com efeito", "C5", "Dívida", "Piloto", "Desenvolver", "1.B3", "Construir (núcleo)", "—"),
    ("E06", "Bancário", "Indicadores agregados de boleto, cartão e TED", "Teste de plausibilidade (nunca conciliação) receita × extrato × faixa da registradora", "D13.5; R3 Espec. 13", "Conferidor", "V1", "Desenvolver", "Espec. 13 Etapa 8", "Parceiro", "Registradoras / recebíveis"),
    ("E06", "Bancário", "Agenda de recebíveis cedidos (cessão, gravame, trava)", "Só vira prova com acesso às registradoras; até lá não aparece como prova", "C6", "Dívida", "Futuro", "Desenvolver", "4.3", "Parceiro", "Registradoras / recebíveis"),
    # E07
    ("E07", "Risco", "Busca de processos por CPF/CNPJ com cruzamento × contingências", "Empresa e cada sócio/administrador; homônimo só pelo nome = 'possível'", "K6; 1.H3; D13.3", "Risco", "Piloto", "Desenvolver", "1.H3", "Parceiro", "Processos judiciais"),
    ("E07", "Risco", "Certidões (TJ, TRF, TRT, CNDT, criminais, CNDs)", "A certidão prova; o provedor de processos só descobre. Validade de 90 dias", "Espec. 13 §2.2, R7", "Risco", "V1", "Desenvolver", "—", "Parceiro", "Certidões"),
    ("E07", "Risco", "Protestos nacionais", "Via relatório de bureau (CENPROT exige gov.br)", "Espec. 13 §8a", "Risco", "V1", "Desenvolver", "2.4", "Parceiro", "Bureau de crédito"),
    ("E07", "Risco", "Sanções e listas (CEIS/CNEP, IBAMA, trabalho escravo, PEP)", "Dados abertos; uma linha por entidade × fonte, inclusive vazia", "1.H2", "Risco", "Piloto", "Desenvolver", "1.H2", "Construir sobre parceiro", "Dados públicos (grátis)"),
    ("E07", "Risco", "Notícias por razão social e por sócio + empresa", "Título, veículo, data, link e trecho por notícia", "K6; 1.H4", "Risco", "Piloto", "Desenvolver", "1.H4", "Parceiro", "Notícias / mídia negativa"),
    ("E07", "Risco", "Matrículas de imóveis e ônus", "Certidão de matrícula: hipotecas, alienação fiduciária; ativo livre para dinheiro novo", "Plano de captação #128", "Dívida / Estrategista", "V1", "Desenvolver", "—", "Parceiro", "Matrículas de imóveis"),
    ("E07", "Risco", "Dossiê de processos e notícias com estado por fonte", "encontrado · nada encontrado · falhou · não consultado (nunca 'sem achados' sem execução)", "K6; D15.10; regra 7", "Risco", "Piloto", "Desenvolver", "1.H5", "Construir (núcleo)", "—"),
    ("E07", "Risco", "Registro de consultas externas (consulta_externa)", "Fornecedor, base legal, autorização, custo, validade e resultado de cada consulta", "Espec. 13 §3; R6", "Sistema", "Piloto", "Desenvolver", "Espec. 13 Etapa 2", "Construir (núcleo)", "—"),
    # E08
    ("E08", "Mercado", "Séries macro do BCB (IPCA, IGP-M, INPC, Selic, CDI, PTAX)", "Captação diária agendada", "K6; 1.C1", "Mercado", "Piloto", "Existe · evoluir", "1.C1", "Construir sobre parceiro", "Dados públicos (grátis)"),
    ("E08", "Mercado", "Focus e juros por modalidade (BCB)", "Expectativas e taxa de mercado para comparar cada contrato de dívida", "K6; 1.C2", "Mercado", "Piloto", "Existe · evoluir", "1.C2", "Construir sobre parceiro", "Dados públicos (grátis)"),
    ("E08", "Mercado", "CVM, IBGE, CAGED/RAIS", "Empresas do setor (DFP/ITR), atividade e emprego setorial", "K6; 1.C3", "Mercado", "Piloto", "Desenvolver", "1.C3", "Construir sobre parceiro", "Dados de mercado e pares"),
    ("E08", "Mercado", "Fontes setoriais (ANEEL/CCEE, ANTT/ANP, SUSEP, FipeZAP)", "Demais fontes do slide 6, com alerta de frescor", "K6; 1.C5; J7", "Mercado", "Piloto", "Desenvolver", "1.C5", "Construir sobre parceiro", "Dados públicos (grátis)"),
    ("E08", "Mercado", "Comparáveis (pares) e benchmarks setoriais", "Margem EBITDA, alavancagem, giro e ROIC de comparáveis", "OBJ; Plano de captação #27", "Mercado", "Piloto", "Desenvolver", "1.E4", "Parceiro", "Dados de mercado e pares"),
    ("E08", "Mercado", "Benchmarks próprios anonimizados", "Base de vários clientes, só anonimizada e com cláusula", "C7", "Mercado", "V1", "Desenvolver", "2.13", "Construir (núcleo)", "—"),
    ("E08", "Mercado", "Painel de frescor das fontes", "Cada fonte com última atualização, estado e efeito; vencida aparece vencida", "1.C4; D15.12", "Analista", "Piloto", "Desenvolver", "1.C4", "Construir (núcleo)", "—"),
    # E09
    ("E09", "Cruzamento", "Cruzamento extração × captação", "Externo com maior peso; os dois valores guardados; veredito; divergência relevante vira achado", "D3; D3-3", "Conferidor", "Piloto", "Desenvolver", "1.B5, 1.E1", "Construir (núcleo)", "—"),
    ("E09", "Cruzamento", "Conferências determinísticas em SQL (balanço, caixa, DRE, mútuos)", "Portão de qualidade; nunca valor presumido", "B4", "Motor", "Piloto", "Existe", "—", "Construir (núcleo)", "—"),
    ("E09", "Cruzamento", "Catálogo das fontes externas", "Origem, periodicidade, prazo crítico, base legal típica, se é opinativo", "D15; 1.K1", "Sistema", "Piloto", "Desenvolver", "1.K1", "Construir (núcleo)", "—"),
    ("E09", "Cruzamento", "Portão do dado externo por agente (vetos e pisos)", "Veto reprova; piso falho manda a REVISÃO; score ponderado em sombra até calibrar", "D15.4; D15.8", "Todos os agentes", "Piloto", "Desenvolver", "1.K2, 1.K3", "Construir (núcleo)", "—"),
    ("E09", "Cruzamento", "Propagação pelo menor score e frescor pela data do uso", "Número calculado herda o pior insumo", "D15.11; D15.12", "Motor", "Piloto", "Desenvolver", "1.K4", "Construir (núcleo)", "—"),
    ("E09", "Cruzamento", "Proveniência por dado", "Fonte, data de coleta, autorização e versão do diagnóstico em cada número", "N-C7a", "Sistema", "Piloto", "Existe · evoluir", "1.B6", "Construir (núcleo)", "—"),
    ("E09", "Cruzamento", "Painel do score do dado externo", "Resultado, classe, score, cobertura e motivo (interno; cliente vê só a ressalva)", "D15.2; D15.5", "Analista", "Piloto", "Desenvolver", "1.K5", "Construir (núcleo)", "—"),
    # E10
    ("E10", "Motor", "Motor determinístico (SQL + fórmulas)", "Único lugar que calcula; agentes só interpretam", "B2; B4; ADR-02", "Motor", "Piloto", "Existe · evoluir", "1.D1", "Construir (núcleo)", "—"),
    ("E10", "Motor", "Mapa da dívida, covenants calculados e capacidade de pagamento", "Operação a operação, cronograma, covenant a partir de contratos e índices, × Registrato", "K6; 1.E2", "Dívida", "Piloto", "Existe · evoluir", "1.E2", "Construir (núcleo)", "—"),
    ("E10", "Motor", "Caixa: NCG, aging conciliado e fluxo de 13 semanas", "Variação calendário × permanente", "K6; 1.E3", "Caixa", "Piloto", "Existe · evoluir", "1.A2, 1.E3", "Construir (núcleo)", "—"),
    ("E10", "Motor", "Juro por contrato × mercado; despesa × setor e região", "Cada contrato com a taxa de mercado ao lado e a fonte", "K6; 1.E4", "Mercado", "Piloto", "Desenvolver", "1.E4", "Construir (núcleo)", "—"),
    ("E10", "Motor", "Motor de cenários e simulação de propostas aos credores", "Carência, desconto, dinheiro novo; humano decide", "B7", "Estrategista", "V1", "Existe · evoluir", "2.3", "Construir (núcleo)", "—"),
    ("E10", "Motor", "Ajustes de EBITDA e Quality of Earnings", "Sugeridos com evidência; nada aplicado sem aceite", "B8", "Estrategista", "V1", "Desenvolver", "2.7", "Construir (núcleo)", "—"),
    ("E10", "Motor", "Classificação de risco (processos, protestos, dívida ativa)", "Risco classificado com a fonte", "2.2", "Risco", "V1", "Desenvolver", "2.2", "Construir (núcleo)", "—"),
    # E11
    ("E11", "Agentes", "Contrato agente × motor", "Entrada por permissão; saída estruturada que cita número do motor e evidência; número próprio recusado", "B2; B4", "Todos", "Piloto", "Desenvolver", "1.D1", "Construir (núcleo)", "—"),
    ("E11", "Agentes", "Orquestração durável dos agentes", "Rodada de ponta a ponta com estado persistido e retomável", "R2; H3/H5", "Supervisor", "Piloto", "Desenvolver", "0.1, 1.D3", "Plataforma (comprar)", "Orquestração durável"),
    ("E11", "Agentes", "Supervisor/Orquestrador", "1ª rodada independente, consolidação, debate sem limite fixo, decide só baixo impacto", "B3; B3b-1; L5", "Supervisor", "Piloto", "Desenvolver", "1.D4", "Construir (núcleo)", "—"),
    ("E11", "Agentes", "Auditor Independente", "Revisa a execução, usa o motor, até 3 tentativas, depois resumo + dossiê", "B4; B5; N-B5a", "Auditor", "Piloto", "Desenvolver", "1.D5", "Construir (núcleo)", "—"),
    ("E11", "Agentes", "Agentes especialistas (Conferidor, Dívida, Caixa, Mercado; depois Risco, Estrategista, Entregas, Captador)", "Interpretação estruturada com evidência", "B1; K6", "Especialistas", "Piloto / V1", "Desenvolver", "1.E1–1.E4; 2.1–2.6", "Construir (núcleo)", "Modelos de IA (LLM)"),
    ("E11", "Agentes", "Dois ou mais provedores de IA com troca automática e roteamento por região", "Cliente pode exigir 'só Brasil'; contrato de dados com cada provedor antes do piloto", "D1; D2; K4", "Sistema", "Piloto", "Existe · evoluir", "1.D8, 0.7", "Parceiro", "Modelos de IA (LLM)"),
    ("E11", "Agentes", "Roteamento barato/médio/topo e custo por etapa e agente", "Alerta acima de US$ 5 por diagnóstico", "D5", "Sistema", "Piloto", "Existe · evoluir", "1.D9", "Construir sobre parceiro", "Observabilidade de IA"),
    ("E11", "Agentes", "Observabilidade da IA (traces, custo, tempo, evals)", "Toda chamada rastreável", "H5", "Técnico", "Piloto", "Desenvolver", "1.D10", "Plataforma (comprar)", "Observabilidade de IA"),
    ("E11", "Agentes", "Memória central por organização e mandato", "Agentes não guardam memória própria", "v0.1.2 §4", "Sistema", "Piloto", "Existe · evoluir", "1.D2", "Construir (núcleo)", "—"),
    # E12
    ("E12", "Aprovação", "Réguas parametrizadas e versionadas (baixo impacto e gravidade)", "Agente só sobe o nível", "B3b-1; G5; G5-1", "Sistema", "Piloto", "Desenvolver", "1.D6", "Construir (núcleo)", "—"),
    ("E12", "Aprovação", "Fila de decisão humana", "Campos estruturados, justificativa obrigatória, evidência, prazos por gravidade, escalonamento ao Sócio", "N-B5a; N-B5b; E5", "Analista", "Piloto", "Existe · evoluir", "1.D7", "Construir (núcleo)", "—"),
    ("E12", "Aprovação", "Papéis (Sócio, Analista, Leitura, Técnico, revisor da consultoria)", "Quem propõe não aprova; autoaprovação reprova no banco", "E2; R1; L4", "Sistema", "Piloto", "Existe · evoluir", "1.F1", "Construir (núcleo)", "—"),
    ("E12", "Aprovação", "Segundo revisor no que vai para fora", "No piloto, analista da Partners só nos mandatos da Partners", "E1; R1", "Segundo revisor", "Piloto", "Desenvolver", "1.F2", "Construir (núcleo)", "—"),
    ("E12", "Aprovação", "Limite de ressalvas e 'limitações relevantes'", "Até 3 altas/críticas; acima, só o Sócio", "E3; E3-1", "Sócio", "Piloto", "Desenvolver", "1.F3", "Construir (núcleo)", "—"),
    ("E12", "Aprovação", "Botão 'Conferência' por documento", "Quem conferiu, quando, qual versão", "E6", "Analista", "Piloto", "Existe · evoluir", "1.F4", "Construir (núcleo)", "—"),
    ("E12", "Aprovação", "Versões de diagnóstico preservadas", "Nova evidência reabre; versão aprovada preservada", "v0.1.2 §8; N-B5c", "Sistema", "Piloto", "Existe · evoluir", "1.F6", "Construir (núcleo)", "—"),
    # E13
    ("E13", "Entregáveis", "Excel do comitê em fórmula (14 abas)", "Modelo FP&A vivo em fórmula, base exportável", "G4", "Entregas", "Piloto", "Existe", "—", "Construir (núcleo)", "—"),
    ("E13", "Entregáveis", "Link de cada número do Excel ao documento e página", "Rastreabilidade número a número", "G4; 1.I1", "Entregas", "Piloto", "Existe · evoluir", "1.I1", "Construir (núcleo)", "—"),
    ("E13", "Entregáveis", "Relatório em PDF com autoria Oria Digital", "Conclusões aprovadas e limitações relevantes", "G4; E3-1; L6", "Entregas", "Piloto", "Desenvolver", "1.I2", "Construir sobre parceiro", "Geração de PDF"),
    ("E13", "Entregáveis", "Relatório interno × relatório do cliente", "Mesmo diagnóstico, conteúdo diferente por regra; cliente não vê agentes", "v0.1.2 §7; L6", "Entregas", "Piloto", "Existe · evoluir", "1.I3, 1.G2", "Construir (núcleo)", "—"),
    ("E13", "Entregáveis", "Apresentação a credores (.pptx) com a prova de cada número", "Propostas simuladas; depois do piloto", "G4; B7", "Entregas", "V1", "Existe · evoluir", "2.6", "Construir (núcleo)", "—"),
    # E14
    ("E14", "Monitoramento", "Agenda de monitoramento por cliente", "Caixa, dívida, covenants, Registrato, processos, protestos, notícias, mercado; frequência por contrato", "G1", "Monitoramento", "V1", "Desenvolver", "2.8", "Construir (núcleo)", "—"),
    ("E14", "Monitoramento", "Reconsulta periódica de processos, protestos e bureau", "Alerta em mudança", "G1", "Risco", "V1", "Desenvolver", "2.8", "Parceiro", "Processos judiciais / Bureau de crédito"),
    ("E14", "Monitoramento", "Alertas só no portal interno", "Analista decide se avisa o cliente", "v0.1.2 §7–§8", "Analista", "V1", "Desenvolver", "2.9", "Construir (núcleo)", "—"),
    ("E14", "Monitoramento", "Relatório periódico (mensal)", "Indicadores × plano, calendário × permanente, alertas; visão de carteira", "G2", "Entregas", "V1", "Desenvolver", "2.9", "Construir (núcleo)", "—"),
    # E15
    ("E15", "Autoaprimoramento", "Propostas semanais de prompts e regras (fase A)", "Relatório ao Técnico; erros validados pelo Auditor", "F1; F1-3; F6; E4", "Autoaprimoramento", "V1", "Desenvolver", "2.10", "Construir (núcleo)", "—"),
    ("E15", "Autoaprimoramento", "Gabarito de 30–50 páginas com parte oculta", "Conferido célula a célula; refeito por semestre", "D4; D4-1; F5", "Dono", "Piloto", "Existe · evoluir", "1.J2, 3.4", "Construir (núcleo)", "—"),
    ("E15", "Autoaprimoramento", "Régua de autonomia N0–N3 (~300 amostras, parte cega)", "Piora medida rebaixa", "D6", "Sistema", "V1", "Existe · evoluir", "3.3", "Construir (núcleo)", "—"),
    ("E15", "Autoaprimoramento", "Chave liga/desliga por mudança e publicação gradual", "Sombra → 1–2 clientes → todos; reversão comprovada", "F2; F3", "Técnico", "V1", "Desenvolver", "2.11", "Construir (núcleo)", "—"),
    ("E15", "Autoaprimoramento", "Backtest com casos anonimizados", "Mudança que afeta número", "F4", "Técnico", "V1", "Desenvolver", "0.10, 2.10", "Construir (núcleo)", "—"),
    # E16
    ("E16", "Plataforma", "Banco Postgres gerenciado em São Paulo com backup contínuo", "Perda máxima de minutos, volta em até 4 h", "H1; H7", "Técnico", "Piloto", "Existe · evoluir", "0.12, 3.1", "Plataforma (comprar)", "Banco de dados gerenciado"),
    ("E16", "Plataforma", "Backup diário criptografado fora do provedor + teste de restauração", "Banco e arquivos (o backup do provedor não cobre Storage)", "H1-1; H7", "Técnico", "Piloto", "Desenvolver", "0.2, 0.3", "Plataforma (comprar)", "Backup e armazenamento imutável"),
    ("E16", "Plataforma", "Automação/coleta fora da instância atual do n8n", "Chave de mínimo privilégio; nenhum mandato real novo no n8n atual", "H2", "Técnico", "Piloto", "Existe · evoluir", "0.4, 0.12", "Plataforma (comprar)", "Automação / coleta"),
    ("E16", "Plataforma", "Organização + RLS por organização e teste de vazamento", "Consultoria-cliente vê só seus mandatos", "H4; L4", "Sistema", "Piloto", "Existe · evoluir", "1.F5, 2.14", "Construir (núcleo)", "—"),
    ("E16", "Plataforma", "Login com verificação em duas etapas", "Antes do 1º cliente além da Partners", "G3", "Sistema", "V1", "Desenvolver", "2.16", "Plataforma (comprar)", "Autenticação 2FA"),
    ("E16", "Plataforma", "Trilha de auditoria com cadeia de hashes e cópia externa imutável", "Alterar um evento quebra a cadeia", "H6", "Sistema", "V1", "Existe · evoluir", "2.15", "Construir sobre parceiro", "Backup e armazenamento imutável"),
    ("E16", "Plataforma", "Três ambientes e anonimização", "Dado real só sai da produção anonimizado", "H8", "Técnico", "Piloto", "Existe · evoluir", "0.9, 0.10", "Construir (núcleo)", "—"),
    ("E16", "Plataforma", "Retenção em três camadas e expurgo com bloqueio por processo", "Originais 6 meses após contrato; entregáveis 5 anos", "I2", "Sistema", "V1", "Desenvolver", "2.12", "Construir (núcleo)", "—"),
    ("E16", "Plataforma", "Arquivos e evidências (Storage)", "Original nunca muda; cópia separada", "ADR-01; H1", "Sistema", "Piloto", "Existe · evoluir", "0.1", "Plataforma (comprar)", "Backup e armazenamento imutável"),
    # E17
    ("E17", "Medição", "Medição automática por mandato", "Dias, horas de analista, custo de IA e de dados, erros por etapa e agente, achados em R$", "J6", "Sistema", "Piloto", "Existe · evoluir", "1.J1", "Construir (núcleo)", "Observabilidade de IA"),
    ("E17", "Medição", "Teto de custo de dados pagos por mandato", "Consulta acima do teto bloqueada; custo gravado por consulta", "N-C6b; R6", "Sistema", "V1", "Desenvolver", "2.4", "Construir (núcleo)", "—"),
    ("E17", "Medição", "Request list e perguntas ao cliente", "Itens pedidos, status, motivo e resposta", "Plano de captação #173, #176", "Analista", "Piloto", "Existe", "—", "Construir (núcleo)", "—"),
]

# ---------------------------------------------------------------------------
# Integrações (sistemas externos que o Oria Digital precisa falar)
# (Sistema, Tipo, O que traz, Etapas, Momento, Custo, Entrega, Situação, Decisões, Condição/observação)
# ---------------------------------------------------------------------------
I = [
    ("BCB — SGS, Olinda (Focus, PTAX, juros por modalidade)", "API pública gratuita", "IPCA, IGP-M, INPC, Selic, CDI, câmbio, expectativas, taxa média por modalidade", "E08", "Pré e pós", "Grátis", "Piloto", "Existe · evoluir", "K6; 1.C1; 1.C2", "Execução em produção não conferida"),
    ("IBGE — SIDRA", "API pública gratuita", "PIB, PIM/PMC/PMS, PNAD, IPCA (conferência)", "E08", "Pré e pós", "Grátis", "Piloto", "Existe · evoluir", "1.C3", ""),
    ("CVM — dados abertos (DFP/ITR, cadastro)", "Dado aberto em lote", "Demonstrações de companhias abertas para pares do setor", "E08", "Pré e pós", "Grátis", "Piloto", "Desenvolver", "1.C3", ""),
    ("MTE — Novo CAGED / RAIS", "Dado aberto em lote", "Emprego setorial; lista de trabalho escravo", "E07, E08", "Pré e pós", "Grátis", "Piloto", "Desenvolver", "1.C3", "Arquivos grandes, carga mensal"),
    ("ANBIMA / B3 — ETTJ, DI futuro, debêntures", "Dado aberto em lote", "Curva de juros e histórico de emissões", "E08", "Pré e pós", "Grátis (download)", "V1", "Desenvolver", "Plano de captação #63, #77", ""),
    ("Reguladores setoriais (ANEEL/CCEE, ANTT/ANP, SUSEP, ANS, ANATEL) e FipeZAP", "API/dado aberto", "Indicadores do setor", "E08", "Pré e pós", "Grátis", "Piloto", "Desenvolver", "1.C5; J7", ""),
    ("Comex Stat (MDIC)", "API pública gratuita", "Exportação e importação por NCM", "E08", "Pré e pós", "Grátis", "V1", "Desenvolver", "Plano de captação #19", ""),
    ("Receita Federal — dados abertos do CNPJ", "Dado aberto em lote", "Cadastro, CNAE, QSA (CPF mascarado), porte, situação", "E01, E07", "Pré e pós", "Grátis", "Piloto", "Desenvolver", "1.H2", "URL mudou em 2026; CPF do sócio vem mascarado"),
    ("CGU — Portal da Transparência (CEIS, CNEP, PEP)", "API pública gratuita", "Sanções e pessoas expostas politicamente", "E01, E07", "Pré e pós", "Grátis (chave)", "Piloto", "Desenvolver", "1.H2", ""),
    ("PGFN — dívida ativa", "Dado aberto em lote", "Inscrições por CNPJ", "E05, E07", "Pré e pós", "Grátis", "Piloto", "Desenvolver", "1.H2", "Carga trimestral"),
    ("IBAMA — autos e embargos", "Dado aberto em lote", "Autos de infração por CNPJ/CPF", "E07", "Pré e pós", "Grátis", "V1", "Desenvolver", "Plano de captação #161", ""),
    ("CNJ — DataJud", "API pública gratuita", "Andamento por número de processo (não busca por CPF/CNPJ)", "E07, E14", "Pós", "Grátis (chave)", "V1", "Desenvolver", "Plano de captação #109", ""),
    ("Registrato/SCR (Banco Central, via gov.br do cliente)", "Upload do cliente (PDF)", "Dívida bancária da empresa e dos sócios", "E06", "Pós", "Grátis", "Piloto", "Desenvolver", "C5", "Sem API: o cliente baixa"),
    ("SPED (ECD, ECF, EFD ICMS/IPI, Contribuições, Reinf)", "Upload / contador", "Versão entregue ao fisco", "E05", "Pós", "Grátis", "Piloto", "Existe · evoluir", "D3; 1.B4", "Robô no ReceitaNet BX avaliado (D12.5)"),
    ("Bancos — OFX e CNAB", "Upload do cliente", "Extrato, cobrança e pagamentos", "E06", "Pós", "Grátis", "Piloto", "Existe · evoluir", "1.A4; 1.A9", ""),
    ("Agregador de Open Finance PJ", "Parceiro pago (API)", "Extrato, saldos e, se disponível, empréstimos/cartões PJ", "E06, E14", "Pós", "A cotar", "V1", "Desenvolver", "C4; D13.1", "Oria entra como parceira de um receptor regulado"),
    ("Captura de NF-e/CT-e/NFS-e por certificado", "Parceiro pago (API)", "XMLs emitidos e recebidos", "E05", "Pós", "A cotar", "V1", "Desenvolver", "D3", "Depende de certificado do cliente (C3)"),
    ("SERPRO Integra Contador / e-CAC", "Parceiro pago (API)", "Situação fiscal, parcelamentos, DCTFWeb", "E05", "Pós", "Por transação", "V1", "Desenvolver", "Espec. 13 §8a", "e-CNPJ da Oria como procuradora"),
    ("Bureau de crédito (PJ e sócios)", "Parceiro pago (API)", "Pendências, protestos, RJ/falência, ações, score", "E01, E07, E14", "Pré e pós", "A cotar", "V1", "Desenvolver", "D13.4; C2", "Só com autorização"),
    ("Provedor de processos por CPF/CNPJ", "Parceiro pago (API)", "Processos, polo, valor, fase, andamento, monitoramento", "E01, E07, E14", "Pré e pós", "Por consulta", "Piloto", "Desenvolver", "K6; D13.3", "Decidir pelo teste contra certidões no mandato AMO"),
    ("Agregador de certidões", "Parceiro pago (API)", "TJ, TRF, TRT, CNDT, criminais, CNDs", "E07", "Pós", "Por consulta", "V1", "Desenvolver", "Espec. 13 §8a", ""),
    ("Fonte de notícias", "Pública ou parceiro", "Notícias da empresa e dos sócios", "E07, E14", "Pré e pós", "Grátis ou a cotar", "Piloto", "Desenvolver", "K6; 1.H4", ""),
    ("Registradoras (Núclea, CERC, B3, TAG)", "Parceiro (contrato)", "Indicadores agregados; agenda de recebíveis", "E06", "Pós", "A cotar", "Futuro", "Desenvolver", "C6; D13.5", "Acesso de não financiador a confirmar"),
    ("ONR / SAEC — registro de imóveis", "Parceiro pago (pedido eletrônico)", "Matrículas e ônus", "E07", "Pós", "Emolumento por certidão", "V1", "Desenvolver", "Plano de captação #128", ""),
    ("Assinatura eletrônica", "Parceiro pago (API)", "Autorização pré-mandato, kickoff, consentimento", "E01, E02", "Pré e pós", "Por envelope/plano", "Piloto", "Desenvolver", "N-C7b; Espec. 13 §5", ""),
    ("Microsoft SharePoint (dataroom)", "Sistema já contratado", "Documentos do cliente", "E03", "Pós", "Já pago", "Futuro", "Desenvolver", "f0/02; D13.2", "Integração via Graph API"),
    ("Provedores de IA (≥ 2)", "Parceiro pago (API)", "Extração, classificação, revisão, agentes", "E04, E11", "Pós", "Por token", "Piloto", "Existe · evoluir", "D1; D2; D5", "Contrato com cláusulas ANPD antes do piloto"),
    ("Extração de PDF/OCR especializada", "Parceiro pago (API) ou open source", "Tabelas de demonstrações em PDF/imagem", "E04", "Pós", "Por página", "Piloto", "Desenvolver", "D3; D4", "Escolher pelo gabarito de 30–50 páginas"),
    ("Orquestração durável", "Plataforma", "Estado dos agentes, retomada", "E11", "—", "A cotar", "Piloto", "Desenvolver", "R2; H3/H5", "Estudo ≥ 5 opções (0.1)"),
    ("Observabilidade de IA", "Plataforma", "Traces, custo, evals", "E11, E17", "—", "A cotar", "Piloto", "Desenvolver", "H5", "Langfuse self-host é o candidato preferido"),
    ("Banco de dados e arquivos", "Plataforma", "Base oficial, evidências, aprovações", "E16", "—", "Assinatura", "Piloto", "Existe · evoluir", "H1; H7", "Hoje Supabase gratuito, sem backup"),
    ("Automação / coleta", "Plataforma", "Coletores agendados", "E05–E08, E14", "—", "Assinatura", "Piloto", "Existe · evoluir", "H2", "Hoje n8n no PikaPods (só até a produção)"),
    ("Backup externo e armazenamento imutável", "Plataforma", "Cópia diária; âncora da trilha", "E16", "—", "Por GB", "Piloto", "Desenvolver", "H1-1; H6", ""),
    ("Autenticação 2FA", "Plataforma", "Login do cliente e da equipe", "E03, E16", "—", "A cotar", "V1", "Desenvolver", "G3", ""),
    ("Hospedagem do portal (Vercel)", "Plataforma", "Portal Next.js", "E03, E12, E13", "—", "Assinatura", "Piloto", "Existe", "Workflow v0.3.0", "Mantido"),
]


def agente_por_frente(frente: str) -> str:
    c = frente.split(" ")[0]
    if c.startswith("1."):
        return "Mercado"
    return {
        "2.1": "Conferidor", "2.2": "Conferidor", "2.3": "Conferidor / Risco", "2.4": "Dívida",
        "2.5": "Caixa", "2.6": "Conferidor", "4.1": "Estrategista", "4.2": "Caixa",
        "4.3": "Caixa", "4.4": "Caixa", "6.1": "Conferidor", "6.2": "Estrategista",
        "6.3": "Supervisor / sistema",
    }.get(c, "Risco" if c.startswith(("3.", "4.", "5.")) else "—")


def etapa_por_meio(frente: str, meio: str) -> str:
    c = frente.split(" ")[0]
    m = meio.lower()
    bancario = c in ("2.4", "2.5")
    if "leitor determinístico" in m:
        return "E05" if c == "2.3" else ("E06" if bancario else "E04")
    if "upload" in m or "questionário" in m:
        return "E04 / E06" if bancario else "E03 / E04"
    if "parceiro" in m:
        return {"2.3": "E05", "2.4": "E06", "2.5": "E06"}.get(c, "E07")
    if "api pública" in m or "dado aberto" in m:
        if c.startswith("1.") or c == "2.4":
            return "E08"
        return "E05" if c == "2.3" else "E07"
    if "cálculo" in m or "formulário" in m:
        return "E10"
    if "curadoria" in m or "cartório" in m:
        return "E07"
    if "gerado pelo sistema" in m:
        return "E17"
    return "—"


def origem_por_meio(meio: str) -> str:
    m = meio.lower()
    if "upload" in m or "questionário" in m:
        return "Cliente"
    if "parceiro" in m or "cartório" in m:
        return "Parceiro pago"
    if "api pública" in m or "dado aberto" in m:
        return "Fonte pública"
    if "formulário" in m or "curadoria" in m:
        return "Analista"
    return "Sistema"


def cabecalho(ws, colunas, larguras):
    for i, (nome, larg) in enumerate(zip(colunas, larguras), start=1):
        c = ws.cell(row=1, column=i, value=nome)
        c.font = Font(name=FONTE, bold=True, color="FFFFFF", size=10)
        c.fill = PatternFill("solid", fgColor=AZUL_ESCURO)
        c.alignment = Alignment(wrap_text=True, vertical="center")
        c.border = BORDA
        ws.column_dimensions[get_column_letter(i)].width = larg
    ws.freeze_panes = "A2"
    ws.row_dimensions[1].height = 32


def linhas(ws, dados, inicio=2):
    for r, linha in enumerate(dados, start=inicio):
        for col, v in enumerate(linha, start=1):
            c = ws.cell(row=r, column=col, value=v)
            c.font = Font(name=FONTE, size=9)
            c.alignment = Alignment(wrap_text=True, vertical="top")
            c.border = BORDA
            if r % 2 == 1:
                c.fill = PatternFill("solid", fgColor=CINZA)
    ws.auto_filter.ref = f"A1:{get_column_letter(ws.max_column)}{ws.max_row}"


def main(saida: str):
    wb = openpyxl.Workbook()

    # --- Leia-me -----------------------------------------------------------
    ws = wb.active
    ws.title = "Leia-me"
    texto = [
        ("Planilha 1 — Funcionalidades, integrações e dados do Oria Digital", True),
        ("Versão 1 · 24/11/2026 · gerada por gerar_planilha_1_funcionalidades.py (não editar à mão: regere).", False),
        ("", False),
        ("Para que serve", True),
        ("Inventário de tudo o que o sistema precisa fazer, falar e captar, para casar cada etapa com um parceiro externo (Planilha 2).", False),
        ("", False),
        ("Abas", True),
        ("Etapas — as 17 etapas do processo (E01–E17). É a chave que liga esta planilha à Planilha 2.", False),
        ("Funcionalidades — o que o sistema faz, com a decisão de origem, o agente, a entrega (Piloto/V1/Futuro), a situação hoje e a natureza.", False),
        ("Integrações — cada sistema externo com que o Oria Digital precisa falar.", False),
        ("Dados a captar — a etapa, o agente e a origem de cada um dos 179 dados. O detalhe de cada dado (o que buscar, onde, criticidade, parceiro) está no Plano_de_Captacao_v3.xlsx (Arquitetura do Sistema/2 Especificação/13_anexos), pelo mesmo número de linha — não é copiado aqui para não haver dado repetido.", False),
        ("Resumo — contagens por etapa, em fórmula.", False),
        ("", False),
        ("Como ler a coluna 'Natureza'", True),
        ("Construir (núcleo): é o valor da Oria (motor, cruzamento, agentes, aprovação). Não se terceiriza.", False),
        ("Parceiro: commodity que um fornecedor já entrega pronto (bureau, processos, Open Finance…). Candidato direto à Planilha 2.", False),
        ("Construir sobre parceiro: a Oria compra o dado ou o serviço e constrói a regra em cima (ex.: extração por IA sobre um provedor de modelo).", False),
        ("Plataforma (comprar): infraestrutura (banco, automação, observabilidade). Sujeita ao estudo comparativo 0.1 (≥ 5 opções, R2).", False),
        ("", False),
        ("Situação hoje", True),
        ("Existe = no código hoje · Existe · evoluir = existe e muda · Desenvolver = não existe. Fonte: AGENTES.md e plano de execução (19–24/11/2026). Nenhum arquivo é autoridade sobre o banco: a sonda fn_instalacao_conferir() é.", False),
        ("", False),
        ("Fontes", True),
        ("Registro de decisões v0.1.6 · Workflow v0.3.0 · AGENTES.md · REGRAS_E_DEFINICOES.md · governança · PLANO_DE_EXECUCAO.md · Espec. 12, 13 e 15 · 13_anexos/Plano_de_Captacao_v3.xlsx.", False),
    ]
    for r, (t, negrito) in enumerate(texto, start=1):
        c = ws.cell(row=r, column=1, value=t)
        c.font = Font(name=FONTE, bold=negrito, size=12 if r == 1 else 10, color=AZUL_ESCURO if negrito else "000000")
        c.alignment = Alignment(wrap_text=True, vertical="top")
    ws.column_dimensions["A"].width = 130

    # --- Etapas ------------------------------------------------------------
    ws = wb.create_sheet("Etapas")
    cabecalho(ws, ["Código", "Etapa", "Fase do produto (capta → diagnostica → calcula → recomenda → entrega)", "O que acontece", "Decisões"], [8, 34, 22, 70, 30])
    linhas(ws, ETAPAS)

    # --- Funcionalidades ---------------------------------------------------
    ws = wb.create_sheet("Funcionalidades")
    cols = ["ID", "Etapa", "Nome da etapa", "Módulo", "Funcionalidade", "O que faz / critério", "Decisões (registro v0.1.6)", "Agente / papel", "Entrega", "Situação hoje", "Item do plano", "Natureza", "Categoria de parceiro (Planilha 2)"]
    cabecalho(ws, cols, [7, 7, 24, 13, 38, 55, 20, 16, 10, 14, 14, 20, 24])
    dados = []
    for n, f in enumerate(F, start=1):
        dados.append((f"F{n:03d}", f[0], None, *f[1:]))
    linhas(ws, dados)
    for r in range(2, len(dados) + 2):
        ws.cell(row=r, column=3, value=f"=IFERROR(INDEX(Etapas!$B:$B,MATCH(B{r},Etapas!$A:$A,0)),\"\")")
    dv = DataValidation(type="list", formula1='"Construir (núcleo),Parceiro,Construir sobre parceiro,Plataforma (comprar)"', allow_blank=False)
    ws.add_data_validation(dv)
    dv.add(f"L2:L{len(dados) + 1}")

    # --- Integrações -------------------------------------------------------
    ws = wb.create_sheet("Integrações")
    cols = ["ID", "Sistema externo", "Tipo", "O que traz", "Etapas", "Momento", "Custo", "Entrega", "Situação hoje", "Decisões", "Condição / observação"]
    cabecalho(ws, cols, [7, 40, 22, 45, 12, 11, 16, 9, 14, 20, 40])
    linhas(ws, [(f"I{n:02d}", *i) for n, i in enumerate(I, start=1)])

    # --- Dados a captar ----------------------------------------------------
    src = openpyxl.load_workbook(CAPTACAO, data_only=True)["Plano por item"]
    rows = [r for r in src.iter_rows(min_row=2, values_only=True) if r[0] is not None]
    ws = wb.create_sheet("Dados a captar")
    # Só o que é NOVO em relação ao Plano_de_Captacao_v3.xlsx: a etapa, o agente e a origem.
    # A versão anterior copiava as 179 linhas inteiras (medido: 179 de 179 iguais à origem) e o dono
    # pediu o repositório sem dado repetido. O "#" é o número da linha lá; "Tema" fica só para ler.
    cols = ["# no Plano de Captação", "Tema", "Etapa principal", "Agente que usa", "Origem"]
    cabecalho(ws, cols, [12, 34, 14, 20, 14])
    dados = []
    for r in rows:
        num, frente, tema, meio = r[0], r[2] or "", r[3], r[9] or ""
        dados.append((num, tema, etapa_por_meio(frente, meio), agente_por_frente(frente), origem_por_meio(meio)))
    linhas(ws, dados)
    n_dados = len(dados)

    # --- Resumo (fórmulas) -------------------------------------------------
    ws = wb.create_sheet("Resumo", 1)
    cols = ["Etapa", "Nome", "Funcionalidades", "…núcleo (construir)", "…parceiro", "…construir sobre parceiro", "…plataforma (comprar)", "Já existem (Existe ou evoluir)", "No piloto", "Integrações", "Dados a captar (etapa principal)"]
    cabecalho(ws, cols, [8, 34, 14, 14, 11, 16, 14, 16, 10, 12, 16])
    nf = len(F) + 1
    for i, (cod, nome, *_r) in enumerate(ETAPAS, start=2):
        ws.cell(row=i, column=1, value=cod)
        ws.cell(row=i, column=2, value=nome)
        ws.cell(row=i, column=3, value=f"=COUNTIF(Funcionalidades!$B$2:$B${nf},A{i})")
        for col, nat in zip(range(4, 8), ["Construir (núcleo)", "Parceiro", "Construir sobre parceiro", "Plataforma (comprar)"]):
            ws.cell(row=i, column=col, value=f'=COUNTIFS(Funcionalidades!$B$2:$B${nf},A{i},Funcionalidades!$L$2:$L${nf},"{nat}")')
        ws.cell(row=i, column=8, value=f'=COUNTIFS(Funcionalidades!$B$2:$B${nf},A{i},Funcionalidades!$J$2:$J${nf},"Existe*")')
        ws.cell(row=i, column=9, value=f'=COUNTIFS(Funcionalidades!$B$2:$B${nf},A{i},Funcionalidades!$I$2:$I${nf},"Piloto*")')
        ws.cell(row=i, column=10, value=f'=COUNTIF(Integrações!$E$2:$E${len(I) + 1},"*"&A{i}&"*")')
        ws.cell(row=i, column=11, value=f"=COUNTIF('Dados a captar'!$C$2:$C${n_dados + 1},\"*\"&A{i}&\"*\")")
    tot = len(ETAPAS) + 2
    ws.cell(row=tot, column=2, value="TOTAL")
    for col in range(3, 10):
        L = get_column_letter(col)
        ws.cell(row=tot, column=col, value=f"=SUM({L}2:{L}{tot - 1})")
    ws.cell(row=tot, column=10, value=f"=COUNTA(Integrações!$A$2:$A${len(I) + 1})")
    ws.cell(row=tot, column=11, value=f"=COUNTA('Dados a captar'!$A$2:$A${n_dados + 1})")
    ws.cell(row=tot + 1, column=2, value="Integrações e dados podem cair em mais de uma etapa; o TOTAL dessas duas colunas conta cada item uma vez.")
    for row in ws.iter_rows(min_row=2, max_row=tot + 1):
        for c in row:
            c.font = Font(name=FONTE, size=9, bold=(c.row == tot))
            c.border = BORDA if c.row <= tot else Border()

    wb.save(saida)
    print(f"{saida}: {len(F)} funcionalidades, {len(I)} integrações, {n_dados} dados")


if __name__ == "__main__":
    main(sys.argv[1])
