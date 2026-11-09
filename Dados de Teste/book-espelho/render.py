# -*- coding: utf-8 -*-
"""Renderização do book ESPELHO: PDF (reportlab) e planilha (openpyxl).

Mesmo desenho dos outros três books (cabeçalho, rodapé sintético, tabela), com
`rl_config.invariant = 1` como o `book-distress`: metadado de data fixo e `/ID`
determinístico, para dois `gerar.py` seguidos darem os mesmos bytes de PDF.

As bagunças de FORMATO — que são o objeto deste book — moram aqui:

  • DRE analítica: 9 colunas de valor em paisagem, fonte 5,4pt; folha negativa
    COM SINAL ("-1.234,56"), subtotal negativo ENTRE PARÊNTESES; célula VAZIA
    no mês sem movimento e "0,00" no mês em que o saldo zerou. É a combinação
    que faz a leitura por linha perder o alinhamento coluna × valor.
  • Balancete: 4 colunas de valor; folha com D/C COLADO depois do valor
    ("1.234,56D"), linha sintética com SINAL; a tabela atravessa páginas no
    meio dos grupos (sem quebra por grupo — o ERP real não quebra).
  • Balanço mensal: 12 colunas, paisagem, fonte 4,7pt, redutora entre parênteses.
  • Planilhas: título MESCLADO, cabeçalho na linha 6 (não na 1), aba extra
    irrelevante, total por FÓRMULA e total por VALOR, formato numérico
    brasileiro — e, numa delas, valor gravado como TEXTO "R$ 1.234,56".

A contagem de VERDADE das linhas de conta dos PDFs vem de
`Dados de Teste/comum/contagem.py`, a mesma dos outros books. A das planilhas
usa a MESMA regra de linha (`_conta_uma_linha`) sobre as células gravadas —
ver `verdade_xlsx` abaixo.
"""

import datetime
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from reportlab import rl_config  # noqa: E402

rl_config.invariant = 1  # data de metadado fixa e /ID determinístico

from openpyxl import Workbook  # noqa: E402
from openpyxl.styles import Alignment, Font, PatternFill  # noqa: E402
from reportlab.lib import colors  # noqa: E402
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY  # noqa: E402
from reportlab.lib.pagesizes import A4, landscape  # noqa: E402
from reportlab.lib.styles import ParagraphStyle  # noqa: E402
from reportlab.lib.units import mm  # noqa: E402
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle  # noqa: E402

from comum.contagem import CONTAGEM, SEM_VALOR_MONETARIO, _conta_uma_linha, build  # noqa: E402,F401

import dados as D  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pdf")
os.makedirs(OUT, exist_ok=True)

RODAPE_SINTETICO = ("Documento sintético, gerado para teste de sistema. Não corresponde a "
                    "empresa, pessoa ou fato real.")
CONTADOR = "Jussara P. Weber — Contadora — CRC RS-071.338/O-2"
DIRETOR = "Ademar Luiz Fontana — Sócio Administrador — CPF 421.118.730-05"

ST_TIT = ParagraphStyle("t", fontName="Helvetica-Bold", fontSize=10.5, alignment=TA_CENTER, leading=13)
ST_SUB = ParagraphStyle("s", fontName="Helvetica", fontSize=8, alignment=TA_CENTER, leading=10)
ST_NOTA = ParagraphStyle("n", fontName="Helvetica-Oblique", fontSize=6.8, leading=8.5)
ST_TXT = ParagraphStyle("p", fontName="Helvetica", fontSize=8.8, leading=12.5, alignment=TA_JUSTIFY)
ST_H2 = ParagraphStyle("h2", fontName="Helvetica-Bold", fontSize=9, leading=13, spaceBefore=5)


# --------------------------------------------------------------- FORMATAÇÃO --
def brl(c):
    """Centavos → '1.234,56' (módulo, sem sinal)."""
    s = f"{abs(c) / 100:,.2f}"
    return s.replace(",", "\x00").replace(".", ",").replace("\x00", ".")


def fmt(c, modo="paren"):
    """Imprime centavos como o documento imprime.

    modo: "paren" → (1.234,56) | "sinal" → -1.234,56 | "dc" → 1.234,56D / 1.234,56C.
    `None` é célula VAZIA — ausência, não zero. Zero é "0,00", sem D/C."""
    if c is None:
        return ""
    if c == 0:
        return "0,00"
    if modo == "dc":
        return f"{brl(c)}{'D' if c > 0 else 'C'}"
    if c < 0:
        return f"({brl(c)})" if modo == "paren" else f"-{brl(c)}"
    return brl(c)


def cabecalho(empresa, titulo, periodo, escala=None, extra=None):
    e = D.EMPRESAS[empresa]
    el = [Paragraph(e["razao_social"], ST_TIT), Paragraph(f"CNPJ {e['cnpj']} — {e['cidade']}", ST_SUB),
          Spacer(1, 2 * mm), Paragraph(titulo, ST_TIT), Paragraph(periodo, ST_SUB)]
    if escala:
        el.append(Paragraph(escala, ST_SUB))
    if extra:
        el.append(Paragraph(extra, ST_SUB))
    el.append(Spacer(1, 3 * mm))
    return el


def _rodape(canvas, doc_):
    canvas.saveState()
    canvas.setFont("Helvetica", 6.2)
    canvas.setFillColorRGB(.35, .35, .35)
    canvas.drawRightString(doc_.pagesize[0] - 10 * mm, 6 * mm, f"Folha: {canvas.getPageNumber():04d}")
    canvas.drawString(10 * mm, 6 * mm, RODAPE_SINTETICO)
    canvas.restoreState()


def doc(nome_arquivo, paisagem=False):
    d = SimpleDocTemplate(
        os.path.join(OUT, nome_arquivo),
        pagesize=landscape(A4) if paisagem else A4,
        leftMargin=10 * mm, rightMargin=10 * mm, topMargin=10 * mm, bottomMargin=12 * mm,
        title=nome_arquivo.rsplit(".", 1)[0], author="Sistema sintético de teste",
    )
    d._decorador = _rodape
    return d


def _tab(linhas, larguras, estilos_extra=(), fonte=6.0, repeat=1):
    t = Table(linhas, colWidths=larguras, repeatRows=repeat)
    # LEADING explícito: o padrão do reportlab é 12pt qualquer que seja a fonte,
    # e com fonte de 5pt isso dobrava as páginas (DRE analítica: 12 em vez de ~6)
    # — densidade que o relatório de ERP real não tem.
    est = [("FONTSIZE", (0, 0), (-1, -1), fonte),
           ("LEADING", (0, 0), (-1, -1), fonte * 1.18),
           ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
           ("FONTNAME", (0, 0), (-1, repeat - 1), "Helvetica-Bold"),
           ("LINEBELOW", (0, repeat - 1), (-1, repeat - 1), 0.6, colors.black),
           ("TOPPADDING", (0, 0), (-1, -1), 0.6),
           ("BOTTOMPADDING", (0, 0), (-1, -1), 0.6),
           ("LEFTPADDING", (0, 0), (-1, -1), 1.5),
           ("RIGHTPADDING", (0, 0), (-1, -1), 1.5),
           ("VALIGN", (0, 0), (-1, -1), "MIDDLE")]
    est.extend(estilos_extra)
    t.setStyle(TableStyle(est))
    return t


def _assina(el, extra=None):
    el.append(Spacer(1, 4 * mm))
    if extra:
        el.append(Paragraph(extra, ST_NOTA))
        el.append(Spacer(1, 2 * mm))
    el.append(Paragraph("_______________________________________", ST_NOTA))
    el.append(Paragraph(CONTADOR, ST_NOTA))
    el.append(Spacer(1, 1.2 * mm))
    el.append(Paragraph(DIRETOR, ST_NOTA))


def _negrito_onde(linhas_dados, cond, desloc=1):
    return [("FONTNAME", (0, i + desloc), (-1, i + desloc), "Helvetica-Bold")
            for i, l in enumerate(linhas_dados) if cond(l)]


# ------------------------------------------------------------ DRE ANALÍTICA --
def pdf_dre_analitica(linhas_dre, arquivo):
    d = doc(arquivo, paisagem=True)
    el = cabecalho("maquinas", "DEMONSTRAÇÃO DO RESULTADO — ANALÍTICA MENSAL — EXERCÍCIO 2026",
                   "Período: 01/01/2026 a 31/08/2026", "Valores em R$")
    # Cabeçalho SEM o ano ("JAN", não "Jan/2026"): pela regra comum de contagem,
    # rótulo + célula com dígito é linha de conta, e o cabeçalho viraria uma conta
    # a mais na verdade (medido: 433 em vez de 432). O ano está no título.
    cab = ["Descrição"] + [m.upper() for m in D.MESES[:8]] + ["ACUMULADO"]
    corpo = []
    for l in linhas_dre:
        # Folha: negativo COM SINAL. Grupo, sintética e cascata: ENTRE PARÊNTESES.
        modo = "sinal" if l["tipo"] == "folha" else "paren"
        rot = ("  " * l["nivel"] + (f"{l['cod']} " if l["tipo"] in ("grupo", "sintetica") else "") + l["rot"])
        corpo.append([rot] + [fmt(v, modo) for v in l["vals"]])
    est = _negrito_onde(linhas_dre, lambda l: l["tipo"] != "folha")
    est += [("BACKGROUND", (0, i + 1), (-1, i + 1), colors.Color(.88, .88, .88))
            for i, l in enumerate(linhas_dre) if l["tipo"] == "calculada"]
    el.append(_tab([cab] + corpo, [75 * mm] + [22 * mm] * 9, est, fonte=5.4))
    el.append(Spacer(1, 2 * mm))
    el.append(Paragraph("Contas sem movimento no mês aparecem em branco. Valores negativos das contas analíticas "
                        "são impressos com sinal; os dos totalizadores, entre parênteses.", ST_NOTA))
    _assina(el)
    build(d, el)
    return arquivo


# ------------------------------------------------------------ DRE SINTÉTICA --
def pdf_dre_sintetica(linhas_dre, arquivo):
    d = doc(arquivo)
    el = cabecalho("maquinas", "DEMONSTRAÇÃO DO RESULTADO DO EXERCÍCIO",
                   "Exercícios findos em 31 de dezembro de 2025 e de 2024", "Valores em R$")
    corpo = [["", "2025", "2024"]]
    for l in linhas_dre:
        corpo.append(["   " * l["nivel"] + l["rot"]] + [fmt(v, "paren") for v in l["vals"]])
    est = _negrito_onde(linhas_dre, lambda l: l["tipo"] == "calculada" and l["nivel"] == 0)
    el.append(_tab(corpo, [120 * mm, 31 * mm, 31 * mm], est, fonte=6.8))
    _assina(el)
    build(d, el)
    return arquivo


# --------------------------------------------------------------- BALANCETE ---
def pdf_balancete(linhas_b, total_movimento, arquivo):
    d = doc(arquivo)
    el = cabecalho("maquinas", "BALANCETE DE VERIFICAÇÃO — ANALÍTICO",
                   "Período: 01/01/2026 a 31/08/2026", "Valores em R$",
                   "Saldos analíticos com natureza (D/C) após o valor; totalizadores com sinal (credor negativo)")
    corpo = [["Código", "Descrição da conta", "Saldo anterior", "Débito", "Crédito", "Saldo atual"]]
    for l in linhas_b:
        ant, deb, cre, atual = l["vals"]
        if l["tipo"] == "folha":
            ant_s, atual_s = fmt(ant, "dc"), fmt(atual, "dc")
        else:
            ant_s, atual_s = fmt(ant, "sinal"), fmt(atual, "sinal")
        corpo.append([l["cod"], "  " * l["nivel"] + l["rot"], ant_s, fmt(deb, "sinal"), fmt(cre, "sinal"), atual_s])
    corpo.append(["", "TOTAL DOS MOVIMENTOS", "", brl(total_movimento), brl(total_movimento), ""])
    est = _negrito_onde(linhas_b, lambda l: l["tipo"] != "folha")
    est += [("FONTNAME", (0, len(corpo) - 1), (-1, len(corpo) - 1), "Helvetica-Bold"),
            ("LINEABOVE", (0, len(corpo) - 1), (-1, len(corpo) - 1), 0.5, colors.black),
            ("ALIGN", (0, 0), (1, -1), "LEFT")]
    el.append(_tab(corpo, [19 * mm, 67 * mm, 24 * mm, 24 * mm, 24 * mm, 24 * mm], est, fonte=5.8))
    _assina(el)
    build(d, el)
    return arquivo


# ----------------------------------------------------------- BALANÇO MENSAL --
def pdf_balanco_mensal(linhas_b, arquivo):
    d = doc(arquivo, paisagem=True)
    el = cabecalho("maquinas", "BALANÇO PATRIMONIAL MENSAL — EXERCÍCIO 2025", "Janeiro a dezembro de 2025",
                   "Valores em R$ — saldos ao final de cada mês")
    corpo = [["Conta"] + [m.upper() for m in D.MESES]]  # sem o ano: ver pdf_dre_analitica
    for l in linhas_b:
        corpo.append(["  " * l["nivel"] + l["rot"]] + [fmt(v, "paren") for v in l["vals"]])
    est = _negrito_onde(linhas_b, lambda l: l["tipo"] != "folha")
    el.append(_tab(corpo, [61 * mm] + [17.6 * mm] * 12, est, fonte=4.7))
    _assina(el)
    build(d, el)
    return arquivo


# -------------------------------------------------------- BALANÇO 2 COLUNAS --
def pdf_balanco_implementos(linhas_b, arquivo):
    d = doc(arquivo)
    el = cabecalho("implementos", "BALANÇO PATRIMONIAL", "Levantado em 31 de dezembro de 2025 e de 2024",
                   "Valores em R$")
    corpo = [["", "31/12/2025", "31/12/2024"]]
    for l in linhas_b:
        rot = "   " * l["nivel"] + l["rot"]
        corpo.append([rot] + [fmt(v, "paren") for v in l["vals"]])
    est = _negrito_onde(linhas_b, lambda l: l["tipo"] in ("sintetica", "calculada"))
    est += [("FONTNAME", (0, i + 1), (0, i + 1), "Helvetica-Oblique")
            for i, l in enumerate(linhas_b) if l["tipo"] == "credor"]
    el.append(_tab(corpo, [122 * mm, 30 * mm, 30 * mm], est, fonte=7.0))
    el.append(Spacer(1, 2 * mm))
    el.append(Paragraph(
        "Nota 7 — As cédulas de crédito bancário de longo prazo foram contratadas em conjunto com quatro "
        "instituições, em tranches de igual valor e com o mesmo cronograma de amortização; por isso os "
        "quatro saldos de longo prazo são idênticos.", ST_NOTA))
    _assina(el, extra="Documento assinado digitalmente com certificado ICP-Brasil (MP 2.200-2/2001). "
                      "Código de verificação: 7F3A-91C2-55E0-B8D4.")
    build(d, el)
    return arquivo


# ---------------------------------------------------------- CONTRATO SOCIAL --
def pdf_contrato_social(arquivo):
    cap = brl(D.CAPITAL_SOCIAL * 100)
    quota = brl(D.CAPITAL_SOCIAL * 100 // len(D.SOCIOS))
    nq = f"{D.CAPITAL_SOCIAL:,}".replace(",", ".")
    nq_s = f"{D.CAPITAL_SOCIAL // len(D.SOCIOS):,}".replace(",", ".")
    d = doc(arquivo)
    el = cabecalho("maquinas", "12ª ALTERAÇÃO E CONSOLIDAÇÃO DO CONTRATO SOCIAL",
                   "NIRE 43.2.0619377-1 — arquivada na JUCISRS sob o nº 9.882.417 em 14/04/2026")
    nomes = ", ".join(f"{n}, CPF {c}" for n, c in D.SOCIOS)
    clausulas = [
        ("PREÂMBULO",
         f"Os sócios {nomes}, únicos sócios da sociedade, resolvem alterar e consolidar o contrato social, "
         "mediante as cláusulas seguintes."),
        ("CLÁUSULA PRIMEIRA — DA CESSÃO DE QUOTAS",
         "O sócio retirante Osmar Fontana (espólio) cede e transfere a totalidade de suas quotas aos sócios "
         "remanescentes, em partes iguais, sem alteração do valor do capital social."),
        ("CLÁUSULA SEGUNDA — DO CAPITAL SOCIAL",
         f"O capital social, que era de R$ {cap} ({nq} quotas), permanece em R$ {cap}, totalmente subscrito "
         f"e integralizado em moeda corrente nacional, dividido em {nq} quotas de R$ 1,00 cada."),
        ("CLÁUSULA TERCEIRA — DA SUBSCRIÇÃO E INTEGRALIZAÇÃO",
         f"O capital subscrito, de R$ {cap}, encontra-se integralmente realizado, de modo que o capital "
         f"integralizado é de R$ {cap} na data desta alteração."),
        ("CLÁUSULA QUARTA — DA DISTRIBUIÇÃO DAS QUOTAS",
         f"Após a cessão, cada um dos quatro sócios passa a deter {nq_s} quotas, no valor de R$ {quota}, "
         "correspondentes a 25% (vinte e cinco por cento) do capital social, conforme o quadro abaixo."),
        ("CLÁUSULA QUINTA — DA ADMINISTRAÇÃO",
         "A administração da sociedade cabe ao sócio Ademar Luiz Fontana, com os poderes e atribuições de "
         "sócio administrador, vedado o uso da denominação em negócios estranhos ao objeto social."),
        ("CLÁUSULA SEXTA — DO OBJETO",
         "Comércio de máquinas, implementos e peças agrícolas, prestação de serviços de manutenção e "
         "assistência técnica, e intermediação de consórcios e financiamentos."),
    ]
    for t, x in clausulas:
        el.append(Paragraph(t, ST_H2))
        el.append(Paragraph(x, ST_TXT))
    el.append(Spacer(1, 3 * mm))
    corpo = [["Sócio", "CPF", "Quotas", "Valor (R$)", "%"]]
    for n, c in D.SOCIOS:
        corpo.append([n, c, nq_s, quota, "25,00"])
    corpo.append(["TOTAL", "", nq, cap, "100,00"])
    el.append(_tab(corpo, [70 * mm, 30 * mm, 26 * mm, 32 * mm, 16 * mm],
                   [("FONTNAME", (0, len(corpo) - 1), (-1, len(corpo) - 1), "Helvetica-Bold")], fonte=7.6))
    el.append(Spacer(1, 4 * mm))
    el.append(Paragraph("Cruz Alta (RS), 2 de abril de 2026.", ST_TXT))
    _assina(el)
    build(d, el)
    return arquivo


# --------------------------------------------------------------- PROCURAÇÃO --
def pdf_procuracao(arquivo):
    """Sem dado financeiro, mas cheio de número (CPF, RG, CEP, datas, OAB). É o
    controle de "documento sem dado financeiro não é falha"."""
    d = doc(arquivo)
    el = cabecalho("maquinas", "PROCURAÇÃO AD NEGOTIA ET AD JUDICIA",
                   "Lavrada no Tabelionato de Notas de Cruz Alta (RS), Livro 214-P, fls. 087, em 09/03/2026")
    el.append(Paragraph(
        "OUTORGANTE: SERRA DO ESPELHO MÁQUINAS AGRÍCOLAS LTDA., inscrita no CNPJ sob o nº 52.418.077/0001-30, "
        "com sede na Avenida Venâncio Aires, nº 2.140, Bairro Centro, CEP 98005-020, Cruz Alta (RS), neste ato "
        "representada por seu sócio administrador Ademar Luiz Fontana, CPF 421.118.730-05, RG 1012345678 SSP/RS.",
        ST_TXT))
    el.append(Spacer(1, 2 * mm))
    el.append(Paragraph("OUTORGADOS:", ST_H2))
    corpo = [["Nome", "CPF", "RG / OAB", "Endereço profissional"]]
    for n, cpf, rg, end in [
        ("Mariana Bortolini Rech", "803.551.220-90", "OAB/RS 98.114", "Rua Pinheiro Machado, 455, sala 3"),
        ("Gustavo Henrique Lenz", "915.207.380-33", "OAB/RS 104.920", "Rua Pinheiro Machado, 455, sala 3"),
        ("Patrícia Schmitt Fontana", "026.744.910-57", "RG 3098765432", "Av. Venâncio Aires, 2.140"),
    ]:
        corpo.append([n, cpf, rg, end])
    el.append(_tab(corpo, [55 * mm, 30 * mm, 32 * mm, 63 * mm], [("ALIGN", (0, 0), (-1, -1), "LEFT")], fonte=7.4))
    el.append(Spacer(1, 2 * mm))
    el.append(Paragraph(
        "PODERES: representar a outorgante perante instituições financeiras, cooperativas de crédito, a "
        "Receita Federal do Brasil, a Secretaria da Fazenda do Estado do Rio Grande do Sul e o Poder "
        "Judiciário, podendo assinar requerimentos, receber intimações, transigir, firmar acordos, dar e "
        "receber quitação, substabelecer com reserva de iguais poderes, e praticar todos os atos necessários "
        "ao fiel cumprimento deste mandato. Prazo de validade: 12 (doze) meses, a contar de 09/03/2026.", ST_TXT))
    el.append(Spacer(1, 2 * mm))
    el.append(Paragraph("Selo digital: 0461.03.2600002.04417 — Emolumentos conforme tabela vigente.", ST_NOTA))
    el.append(Spacer(1, 4 * mm))
    el.append(Paragraph("Cruz Alta (RS), 9 de março de 2026.", ST_TXT))
    el.append(Paragraph("_______________________________________", ST_NOTA))
    el.append(Paragraph("Tabelião substituto — Matrícula 2.117", ST_NOTA))
    build(d, el)
    return arquivo


# ================================================================ PLANILHAS ==
FMT_BR = '#,##0.00;[Red]-#,##0.00'           # exibido como 1.234,56 no Excel em pt-BR
FMT_RS = '"R$ "#,##0.00;[Red]-"R$ "#,##0.00'
DATA_FIXA = datetime.datetime(2026, 9, 2, 8, 0, 0)
LINHA_CAB = 6  # o cabeçalho NÃO está na linha 1 — linhas 1–5 são título e identificação


def _novo_livro(titulo_aba, titulo, subtitulo, periodo, ncols):
    wb = Workbook()
    wb.properties.creator = "Sistema sintético de teste"
    wb.properties.created = DATA_FIXA
    wb.properties.modified = DATA_FIXA
    ws = wb.active
    ws.title = titulo_aba
    ultima = chr(ord("A") + ncols - 1)
    ws.merge_cells(f"A1:{ultima}2")  # título MESCLADO em duas linhas
    ws["A1"] = titulo
    ws["A1"].font = Font(bold=True, size=13)
    ws["A1"].alignment = Alignment(horizontal="center", vertical="center")
    ws.merge_cells(f"A3:{ultima}3")
    ws["A3"] = subtitulo
    ws["A4"] = periodo
    ws["A5"] = RODAPE_SINTETICO
    ws["A5"].font = Font(italic=True, size=8)
    return wb, ws


def _cabecalho_tabela(ws, nomes, larguras):
    for i, (n, w) in enumerate(zip(nomes, larguras)):
        c = ws.cell(row=LINHA_CAB, column=i + 1, value=n)
        c.font = Font(bold=True)
        c.fill = PatternFill("solid", fgColor="D9D9D9")
        ws.column_dimensions[chr(ord("A") + i)].width = w


def _aba_irrelevante(wb, nome, linhas):
    ws = wb.create_sheet(nome)
    for r in linhas:
        ws.append(list(r))


def _total_formula_e_valor(ws, linha, col_rotulo, colunas_valor, primeira, ultima, valores, fmt_num):
    """Duas linhas de total: uma por FÓRMULA (=SUM, sem valor em cache — o
    openpyxl não calcula) e uma por VALOR, digitado como o usuário faz quando
    "confere" o total. A segunda é a única que um leitor sem motor de cálculo vê."""
    ws.cell(row=linha, column=col_rotulo, value="TOTAL").font = Font(bold=True)
    for col in colunas_valor:
        letra = chr(ord("A") + col - 1)
        c = ws.cell(row=linha, column=col, value=f"=SUM({letra}{primeira}:{letra}{ultima})")
        c.number_format = fmt_num
        c.font = Font(bold=True)
    ws.cell(row=linha + 1, column=col_rotulo, value="Total conferido (valor)").font = Font(italic=True)
    for col, v in zip(colunas_valor, valores):
        c = ws.cell(row=linha + 1, column=col, value=v)
        c.number_format = fmt_num


def xlsx_extrato(saldo_inicial, linhas, saldo_final, arquivo):
    wb, ws = _novo_livro("Extrato", "EXTRATO DE CONTA CORRENTE",
                         "Banco do Planalto S.A. — Ag. 0731 — C/C 41.207-3 — "
                         + D.EMPRESAS["maquinas"]["razao_social"],
                         "Período: 01/08/2026 a 31/08/2026 — valores em R$", 6)
    _cabecalho_tabela(ws, ["Data", "Histórico", "Documento", "Valor (R$)", "D/C", "Saldo (R$)"],
                      [12, 34, 12, 16, 5, 18])
    r = LINHA_CAB + 1
    ws.cell(row=r, column=1, value="31/07/2026")
    ws.cell(row=r, column=2, value="SALDO ANTERIOR")
    c = ws.cell(row=r, column=6, value=saldo_inicial / 100)
    c.number_format = FMT_BR
    r += 1
    primeira = r
    for data, hist, docu, v, saldo in linhas:
        ws.cell(row=r, column=1, value=data)  # data como TEXTO, como o internet banking exporta
        ws.cell(row=r, column=2, value=hist)
        ws.cell(row=r, column=3, value=docu)
        c = ws.cell(row=r, column=4, value=abs(v) / 100)
        c.number_format = FMT_BR
        ws.cell(row=r, column=5, value="C" if v > 0 else "D")
        c = ws.cell(row=r, column=6, value=saldo / 100)
        c.number_format = FMT_BR
        r += 1
    ultima = r - 1
    cred = sum(v for *_x, v, _s in linhas if v > 0)
    deb = -sum(v for *_x, v, _s in linhas if v < 0)
    ws.cell(row=r + 1, column=2, value="Total de créditos").font = Font(bold=True)
    c = ws.cell(row=r + 1, column=4, value=f'=SUMIF(E{primeira}:E{ultima},"C",D{primeira}:D{ultima})')
    c.number_format = FMT_BR
    ws.cell(row=r + 2, column=2, value="Total de débitos").font = Font(bold=True)
    c = ws.cell(row=r + 2, column=4, value=f'=SUMIF(E{primeira}:E{ultima},"D",D{primeira}:D{ultima})')
    c.number_format = FMT_BR
    ws.cell(row=r + 3, column=2, value="Total de créditos (conferido)")
    ws.cell(row=r + 3, column=4, value=cred / 100).number_format = FMT_BR
    ws.cell(row=r + 4, column=2, value="Total de débitos (conferido)")
    ws.cell(row=r + 4, column=4, value=deb / 100).number_format = FMT_BR
    ws.cell(row=r + 5, column=2, value="SALDO FINAL").font = Font(bold=True)
    ws.cell(row=r + 5, column=6, value=saldo_final / 100).number_format = FMT_BR
    _aba_irrelevante(wb, "Legenda", [("Código", "Significado"), ("C", "Crédito"), ("D", "Débito"),
                                     ("*", "Lançamento futuro"), ("Atendimento", "Central de relacionamento")])
    wb.save(os.path.join(OUT, arquivo))
    return arquivo, {"creditos": cred, "debitos": deb}


def xlsx_mapa_divida(linhas, total, arquivo):
    wb, ws = _novo_livro("Dívida", "MAPA DE ENDIVIDAMENTO BANCÁRIO",
                         D.EMPRESAS["maquinas"]["razao_social"] + " — CNPJ " + D.EMPRESAS["maquinas"]["cnpj"],
                         "Posição em 31/08/2026 — valores em R$", 8)
    _cabecalho_tabela(ws, ["Credor", "Modalidade", "Contrato", "Taxa", "Vencimento final",
                           "Saldo curto prazo", "Saldo longo prazo", "Saldo total"],
                      [32, 24, 18, 18, 14, 18, 18, 18])
    r = LINHA_CAB + 1
    primeira = r
    for credor, mod, ctr, taxa, venc, cp, lp in linhas:
        ws.cell(row=r, column=1, value=credor)
        ws.cell(row=r, column=2, value=mod)
        ws.cell(row=r, column=3, value=ctr)
        ws.cell(row=r, column=4, value=taxa)
        if venc[0].isdigit():
            dd, mm_, aa = venc.split("/")
            c = ws.cell(row=r, column=5, value=datetime.date(int(aa), int(mm_), int(dd)))
            c.number_format = "dd/mm/yyyy"
        else:
            ws.cell(row=r, column=5, value=venc)
        ws.cell(row=r, column=6, value=cp / 100).number_format = FMT_RS
        ws.cell(row=r, column=7, value=lp / 100).number_format = FMT_RS
        ws.cell(row=r, column=8, value=f"=F{r}+G{r}").number_format = FMT_RS  # total da LINHA por fórmula
        r += 1
    ultima = r - 1
    tcp = sum(x[5] for x in linhas)
    tlp = sum(x[6] for x in linhas)
    _total_formula_e_valor(ws, r + 1, 1, [6, 7, 8], primeira, ultima, [tcp / 100, tlp / 100, total / 100], FMT_RS)
    _aba_irrelevante(wb, "Premissas CDI", [("Mês", "CDI projetado a.m. (%)")]
                     + [(f"{m}/2026", round(0.82 + 0.01 * i, 2)) for i, m in enumerate(D.MESES)])
    wb.save(os.path.join(OUT, arquivo))
    return arquivo, {"curto_prazo": tcp, "longo_prazo": tlp, "total": total}


def xlsx_estoque(linhas, total, arquivo):
    wb, ws = _novo_livro("Posição", "POSIÇÃO DE ESTOQUE — PEÇAS",
                         D.EMPRESAS["maquinas"]["razao_social"] + " — Depósito 01 (Cruz Alta)",
                         "Inventário em 31/08/2026 — custo médio em R$", 5)
    _cabecalho_tabela(ws, ["Produto", "Un.", "Quantidade", "Custo médio (R$)", "Valor total (R$)"],
                      [46, 6, 12, 16, 18])
    r = LINHA_CAB + 1
    primeira = r
    for _conta, rotulo, unid, qtd, valor in linhas:
        ws.cell(row=r, column=1, value=rotulo)  # CÓDIGO COLADO no nome — o produto não tem coluna de código
        ws.cell(row=r, column=2, value=unid)
        ws.cell(row=r, column=3, value=qtd)
        ws.cell(row=r, column=4, value=round(valor / 100 / qtd, 4)).number_format = '#,##0.0000'
        ws.cell(row=r, column=5, value=valor / 100).number_format = FMT_BR
        r += 1
    _total_formula_e_valor(ws, r + 1, 1, [5], primeira, r - 1, [total / 100], FMT_BR)
    _aba_irrelevante(wb, "Plan2", [("contagem", "responsável", "data"), ("1ª", "Almoxarifado", "30/08/2026"),
                                   ("2ª", "Controladoria", "31/08/2026")])
    wb.save(os.path.join(OUT, arquivo))
    return arquivo, {"total": total, "itens": len(linhas)}


def xlsx_contingencias(linhas, arquivo):
    wb, ws = _novo_livro("Processos", "RELATÓRIO DE CONTINGÊNCIAS JUDICIAIS",
                         D.EMPRESAS["maquinas"]["razao_social"] + " — Fonseca & Lenz Advogados",
                         "Posição em 31/08/2026", 5)
    _cabecalho_tabela(ws, ["Nº do processo (CNJ)", "Natureza", "Prognóstico", "Valor da causa",
                           "Valor provisionado (R$)"], [28, 13, 12, 18, 20])
    r = LINHA_CAB + 1
    primeira = r
    for numero, nat, prog, causa, prov in linhas:
        ws.cell(row=r, column=1, value=numero)
        ws.cell(row=r, column=2, value=nat)
        ws.cell(row=r, column=3, value=prog)
        # Valor da causa como TEXTO "R$ 1.234,56", como o sistema jurídico exporta —
        # nenhuma fórmula soma esta coluna, e é de propósito.
        ws.cell(row=r, column=4, value=f"R$ {brl(causa)}")
        ws.cell(row=r, column=5, value=prov / 100).number_format = FMT_BR
        r += 1
    total_prov = sum(x[4] for x in linhas)
    _total_formula_e_valor(ws, r + 1, 3, [5], primeira, r - 1, [total_prov / 100], FMT_BR)
    _aba_irrelevante(wb, "Instruções", [("Preencher somente as colunas em branco.",),
                                        ("Prognóstico: Provável / Possível / Remoto (CPC 25).",),
                                        ("Enviar à controladoria até o 5º dia útil.",)])
    wb.save(os.path.join(OUT, arquivo))
    por_nat = {}
    for _n, nat, prog, causa, prov in linhas:
        k = por_nat.setdefault(nat, {"processos": 0, "provisionado": 0, "causa_provavel": 0,
                                     "causa_possivel": 0, "causa_remoto": 0})
        k["processos"] += 1
        k["provisionado"] += prov
        k[f"causa_{prog.lower().replace('á', 'a').replace('í', 'i')}"] += causa
    return arquivo, {"provisionado": total_prov, "por_natureza": por_nat, "processos": len(linhas)}


# ---------------------------------------------------- VERDADE DAS PLANILHAS --
def verdade_xlsx(arquivo):
    """A verdade de uma planilha, pela MESMA regra de linha dos PDFs.

    Lê de volta o que o openpyxl gravou (não o dicionário de origem), aba por
    aba, e aplica `comum.contagem._conta_uma_linha` a cada linha com as células
    como TEXTO. Duas decisões, declaradas:
      • célula de FÓRMULA conta como VAZIA. O openpyxl não grava valor em cache,
        então um leitor sem motor de cálculo (o `Extract From File` do n8n é um
        deles) vê a célula em branco. Elas vão contadas à parte, em
        `celulas_de_formula`, para ninguém confundir "sem valor" com "zero".
      • só a PRIMEIRA aba é dado; a aba extra é ruído e a verdade dela é zero —
        o que a régua enxergar ali é contagem a mais.
    """
    from openpyxl import load_workbook
    wb = load_workbook(os.path.join(OUT, arquivo))
    resultado = {"abas": wb.sheetnames, "linha_do_cabecalho": LINHA_CAB}
    texto = {}
    for i, ws in enumerate(wb.worksheets):
        acc = {"linhas_de_conta": 0, "celulas_de_valor": 0, "rotulos": set()}
        formulas, linhas_txt = 0, []
        for row in ws.iter_rows(values_only=True):
            celulas = []
            for v in row:
                if isinstance(v, str) and v.startswith("="):
                    formulas += 1
                    celulas.append("")
                elif v is None:
                    celulas.append("")
                elif isinstance(v, float):
                    celulas.append(repr(v))
                else:
                    celulas.append(str(v))
            if any(c.strip() for c in celulas):
                linhas_txt.append(" | ".join(str(v) if v is not None else "" for v in row))
            if i == 0:
                _conta_uma_linha(celulas, acc)
        texto[ws.title] = linhas_txt
        if i == 0:
            resultado.update({"linhas_de_conta": acc["linhas_de_conta"], "celulas_de_valor": acc["celulas_de_valor"],
                              "contas_distintas": len(acc["rotulos"]), "celulas_de_formula": formulas})
    return resultado, texto
