"""Fase 3, edições F (2ª revisão do dono, 19/11): slide 2 (texto exato), slide 8 (o que vendemos = a entrega,
fontes iguais no painel, sem "360°") e slide 9 (agentes menores, ramos viram 2 descrições simples por agente,
Auditor sem sobrepor o selo 5). Uso: python3 editar_f.py entrada.pptx saida.pptx"""
import math
import sys

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Emu, Inches, Pt

ORANGE, NAVY, BORDA, CURVA, BRANCO = (RGBColor.from_string(c) for c in ("F04600", "16263B", "D6DED6", "B7C4BA", "FFFFFF"))
prs = Presentation(sys.argv[1])
sl = prs.slides


def por_nome(slide, nome):
    return [s for s in slide.shapes if s.name == nome]


def runs(shape):
    return [r for p in shape.text_frame.paragraphs for r in p.runs]


# ------------------------------------------------------------------ slide 2: texto exato pedido pelo dono
runs(por_nome(sl[1], "t16")[0])[0].text = "em dívidas, com 9,3 milhões de empresas inadimplentes: recorde"

# ------------------------------------------------------------------ slide 8
s8 = sl[7]
oque = por_nome(s8, "proposta-o-que")[0]
pq = por_nome(s8, "proposta-para-quem")[0]
r = runs(oque)
r[1].text = ("Uma plataforma integrada e auditada, conectada a mais de 30 fontes e operada pela nossa equipe. "
             "O cliente envia os documentos e acompanha tudo em um só lugar: base conferida, modelo financeiro, "
             "dossiê e alertas, com suporte direto.")
for x in (runs(oque)[1], runs(pq)[1]):  # mesmo corpo e peso nos dois blocos do painel
    x.font.size = Pt(14)
    x.font.bold = True
oque.top, oque.height = Inches(2.25), Inches(2.45)
linha = [s for s in s8.shapes if s.element.tag.endswith("cxnSp") and s.begin_x == Inches(0.95)][0]
linha.begin_y = linha.end_y = Inches(4.38)
pq.top = Inches(4.58)
for s in s8.shapes:
    if s.has_text_frame:
        for x in runs(s):
            if x.text == "Visão 360°, modelo, dossiê e apresentação aos credores.":
                x.text = "Base conferida, modelo financeiro, dossiê e apresentação aos credores."

# ------------------------------------------------------------------ slide 9
s9 = sl[8]
DESCR = {
    1: ("Lê e organiza os documentos do cliente", "Busca dados na Receita, bancos e mercado"),
    2: ("Cruza a contabilidade com fontes externas", "Aponta o que não bate, com a prova"),
    3: ("Compara a empresa com o setor e a região", "Compara juros com a média do mercado"),
    4: ("Mapeia processos, protestos e dívida ativa", "Sinaliza deterioração antes da crise"),
    5: ("Mostra até onde o caixa aguenta", "Projeta a liquidez semana a semana"),
    6: ("Mapeia a dívida por credor e vencimento", "Mede a capacidade de pagamento"),
    7: ("Propõe cortes e caminhos de renegociação", "Simula propostas aos credores"),
    8: ("Monta o modelo, o dossiê e a apresentação", "Liga cada número à sua fonte"),
}
for c in [s for s in s9.shapes if s.element.tag.endswith("cxnSp")]:
    c._element.getparent().remove(c._element)

AW, AH, BD = Inches(1.55), Inches(0.62), Inches(0.32)  # agentes e selos menores
PW, PH, PASSO = Inches(2.70), Inches(0.24), 0.31
CENTROS = [2.30, 3.55, 4.80, 6.02]
anel = por_nome(s9, "Oval 10")[0]
cx, cy, raio = anel.left + anel.width // 2, anel.top + anel.height // 2, anel.width // 2


def agente(n, x, y_centro):
    ag, bd = por_nome(s9, f"agente-{n}")[0], por_nome(s9, f"badge-{n}")[0]
    ag.width, ag.height = (Inches(1.90) if n == 10 else AW), AH
    ag.left, ag.top = int(x), int(y_centro - AH / 2)
    p = ag.text_frame.paragraphs
    for run in p[0].runs:
        run.font.size = Pt(9)
    for run in p[1].runs:
        run.font.size = Pt(12 if n != 10 else 10.5)
    bd.width = bd.height = BD
    bd.left, bd.top = ag.left - Inches(0.05), ag.top - Inches(0.10)
    for run in runs(bd):
        run.font.size = Pt(11 if n != 10 else 9)
    return ag


def curva(x1, y1, x2, y2, larg):
    c = s9.shapes.add_connector(MSO_CONNECTOR.CURVE, Emu(int(x1)), Emu(int(y1)), Emu(int(x2)), Emu(int(y2)))
    c.line.color.rgb, c.line.width = CURVA, Pt(larg)


def pill_texto(pill, frase):
    rr = runs(pill)
    rr[0].text, rr[0].font.size = "→ ", Pt(9)
    rr[1].text, rr[1].font.size = frase, Pt(9)
    for x in rr[2:]:
        x.text = ""


for lado, nums in (("esq", (1, 2, 3, 4)), ("dir", (5, 6, 7, 8))):
    for i, n in enumerate(nums):
        yc = Inches(CENTROS[i])
        ag = agente(n, Inches(3.80) if lado == "esq" else Inches(7.98), yc)
        ramos = por_nome(s9, f"analise-{n}")
        for extra in ramos[2:]:
            extra._element.getparent().remove(extra._element)
        for j, (rm, frase) in enumerate(zip(ramos[:2], DESCR[n])):
            rm.width, rm.height = PW, PH
            rm.left = Inches(0.72) if lado == "esq" else Inches(9.91)
            rm.top = int(yc - Inches((PASSO + 0.24) / 2) + Inches(j * PASSO))
            pill_texto(rm, frase)
            ry = rm.top + rm.height // 2
            if lado == "esq":
                curva(ag.left, yc, rm.left + rm.width, ry, 1)
            else:
                curva(ag.left + ag.width, yc, rm.left, ry, 1)
        ax = ag.left + ag.width if lado == "esq" else ag.left
        ang = math.atan2(yc - cy, ax - cx)
        curva(cx + raio * math.cos(ang), cy + raio * math.sin(ang), ax, yc, 1.75)

# Auditor e Autoaprimoramento no eixo do Orquestrador, com ramo menor que não encosta nos selos 1 e 5
for n, yc, y_pill, w_pill in ((9, 2.42, 1.80, 2.05), (10, 5.92, 6.33, 2.35)):
    ag = agente(n, cx - (Inches(1.90) if n == 10 else AW) / 2, Inches(yc))
    pill = por_nome(s9, f"analise-{n}")[0]
    pill.width, pill.height = Inches(w_pill), PH
    pill.left, pill.top = int(cx - pill.width / 2), Inches(y_pill)
    for x in runs(pill):
        x.font.size = Pt(9)
    if n == 9:
        s9.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Emu(int(cx)), ag.top + ag.height, Emu(int(cx)), cy - raio)
    else:
        s9.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Emu(int(cx)), cy + raio, Emu(int(cx)), ag.top)
for c in s9.shapes:
    if c.element.tag.endswith("cxnSp") and c.line.color.type is None:
        c.line.color.rgb, c.line.width = CURVA, Pt(1.75)
arvore = s9.shapes._spTree
for c in [e for e in list(arvore) if e.tag.endswith("cxnSp")]:
    arvore.remove(c)
    anel._element.addnext(c)

prs.save(sys.argv[2])
print("ok")
