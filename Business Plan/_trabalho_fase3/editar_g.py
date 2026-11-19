"""Fase 3, edições G (3ª revisão do dono, 19/11): slide 8 com o texto exato de "o que vendemos"; slide 9 em
duas versões — A (mapa radial refeito: ramos redondos, linhas quase retas, Auditor e Autoaprimoramento ligados
aos seus ramos) e B (árvore: Orquestrador em cima, agentes embaixo, descrições descendo de cada agente).
Uso: python3 editar_g.py entrada.pptx saida.pptx   (a entrada já tem o slide 10 duplicado do 9)"""
import math
import sys

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.dml import MSO_LINE_DASH_STYLE
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Emu, Inches, Pt

NAVY, ORANGE, BORDA, LINHA, CINZA, BRANCO, ANEL = (RGBColor.from_string(c) for c in
                                                   ("16263B", "F04600", "D6DED6", "B7C4BA", "707070", "FFFFFF", "E3EBE4"))
DESCR = {
    1: ("Captador", "Lê e organiza os documentos do cliente", "Busca dados na Receita, bancos e mercado"),
    2: ("Conferidor", "Cruza a contabilidade com fontes externas", "Aponta o que não bate, com a prova"),
    3: ("Mercado", "Compara a empresa com o setor e a região", "Compara juros com a média do mercado"),
    4: ("Risco", "Mapeia processos, protestos e dívida ativa", "Sinaliza deterioração antes da crise"),
    5: ("Caixa", "Mostra até onde o caixa aguenta", "Projeta a liquidez semana a semana"),
    6: ("Dívida", "Mapeia a dívida por credor e vencimento", "Mede a capacidade de pagamento"),
    7: ("Estrategista", "Propõe cortes e caminhos de renegociação", "Simula propostas aos credores"),
    8: ("Entregas", "Monta o modelo, o dossiê e a apresentação", "Liga cada número à sua fonte"),
}
AUDITOR = ("Auditor", "Revisa o trabalho de todos os agentes")
AUTO = ("Autoaprimoramento", "Propõe melhorias a partir dos erros")

prs = Presentation(sys.argv[1])
sl = prs.slides


def runs(shape):
    return [r for p in shape.text_frame.paragraphs for r in p.runs]


# ------------------------------------------------------------------ slide 8: texto exato do dono
oque = [s for s in sl[7].shapes if s.name == "proposta-o-que"][0]
runs(oque)[1].text = ("Uma plataforma integrada e auditada, operada pela nossa equipe. O cliente envia os documentos e "
                      "acompanha tudo em um lugar só: base conferida, modelo financeiro, dossiê e alertas com suporte direto.")


# ------------------------------------------------------------------ ferramentas de desenho
def limpar(slide, manter_nomes):
    for s in list(slide.shapes):
        guardar = s.name in manter_nomes or (s.has_text_frame and (
            s.text_frame.text.startswith("8 · ") or s.text_frame.text.startswith("Onze agentes")
            or s.text_frame.text.startswith("Supervisão")))
        if not guardar:
            s._element.getparent().remove(s._element)


def forma(slide, tipo, x, y, w, h, fill, line=None, larg=1, nome=None):
    s = slide.shapes.add_shape(tipo, Emu(int(x)), Emu(int(y)), Emu(int(w)), Emu(int(h)))
    s.fill.solid()
    s.fill.fore_color.rgb = fill
    if line is None:
        s.line.fill.background()
    else:
        s.line.color.rgb, s.line.width = line, Pt(larg)
    s.shadow.inherit = False
    if nome:
        s.name = nome
    tf = s.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = Inches(0.06)
    tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    return s


def escreve(s, linhas):
    """linhas: [(texto, tamanho, negrito, cor), ...] — um parágrafo por linha, centralizado."""
    tf = s.text_frame
    for i, (txt, sz, b, cor) in enumerate(linhas):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.CENTER
        r = p.add_run()
        r.text, r.font.size, r.font.bold, r.font.color.rgb = txt, Pt(sz), b, cor


def agente(slide, cx, cy, w, h, num, nome, sz_nome=13):
    s = forma(slide, MSO_SHAPE.OVAL, cx - w / 2, cy - h / 2, w, h, BRANCO, BORDA, 1, nome=f"agente-{num}")
    escreve(s, [("Agente", 10, False, CINZA), (nome, sz_nome, True, NAVY)])
    d = Inches(0.34)
    b = forma(slide, MSO_SHAPE.OVAL, cx - w / 2 - Inches(0.04), cy - h / 2 - Inches(0.10), d, d, ORANGE, nome=f"badge-{num}")
    b.text_frame.margin_left = b.text_frame.margin_right = 0
    escreve(b, [(str(num), 11 if num < 10 else 9.5, True, BRANCO)])
    return s


def bolha(slide, cx, cy, w, h, texto, num, sz=10):
    s = forma(slide, MSO_SHAPE.OVAL, cx - w / 2, cy - h / 2, w, h, BRANCO, BORDA, 1, nome=f"ramo-{num}")
    s.text_frame.margin_left = s.text_frame.margin_right = Inches(0.12)
    escreve(s, [(texto, sz, False, NAVY)])
    return s


def liga(slide, x1, y1, x2, y2, tipo=MSO_CONNECTOR.STRAIGHT, larg=1.25, tracejado=False):
    c = slide.shapes.add_connector(tipo, Emu(int(x1)), Emu(int(y1)), Emu(int(x2)), Emu(int(y2)))
    c.line.color.rgb, c.line.width = LINHA, Pt(larg)
    if tracejado:
        c.line.dash_style = MSO_LINE_DASH_STYLE.DASH
    return c


def conectores_atras(slide, depois_de=None):
    arv = slide.shapes._spTree
    cx = [e for e in list(arv) if e.tag.endswith("cxnSp")]
    for c in cx:
        arv.remove(c)
    ancora = depois_de if depois_de is not None else arv[1]
    for c in reversed(cx):
        ancora.addnext(c)


# ------------------------------------------------------------------ versão A: mapa radial refeito
sA = sl[8]
limpar(sA, {"Oval 10", "centro", "t271", "Slide Number Placeholder 0"})
anel = [s for s in sA.shapes if s.name == "Oval 10"][0]
ocx, ocy, raio = anel.left + anel.width / 2, anel.top + anel.height / 2, anel.width / 2
AW, AH = Inches(1.62), Inches(0.68)
BW, BH, BPASSO = Inches(2.62), Inches(0.50), Inches(0.56)
CENTROS = [Inches(v) for v in (2.42, 3.62, 4.82, 6.02)]
for lado, nums in (("esq", (1, 2, 3, 4)), ("dir", (5, 6, 7, 8))):
    acx = Inches(4.55) if lado == "esq" else Inches(8.78)
    bcx = Inches(1.95) if lado == "esq" else Inches(11.38)
    for i, n in enumerate(nums):
        cy = CENTROS[i]
        nome, d1, d2 = DESCR[n]
        a = agente(sA, acx, cy, AW, AH, n, nome)
        # do anel até o agente: linha reta na direção do agente (sem ondas)
        ax = acx + AW / 2 if lado == "esq" else acx - AW / 2
        ang = math.atan2(cy - ocy, ax - ocx)
        liga(sA, ocx + raio * math.cos(ang), ocy + raio * math.sin(ang), ax, cy, larg=1.75)
        for j, d in enumerate((d1, d2)):
            by = cy - BPASSO / 2 + j * BPASSO
            bolha(sA, bcx, by, BW, BH, d, n)
            x_ag = acx - AW / 2 if lado == "esq" else acx + AW / 2
            x_b = bcx + BW / 2 if lado == "esq" else bcx - BW / 2
            liga(sA, x_ag, cy, x_b, by, tipo=MSO_CONNECTOR.CURVE)
# Auditor acima e Autoaprimoramento abaixo do Orquestrador, cada um ligado ao seu ramo
aud = agente(sA, ocx, Inches(2.74), AW, AH, 9, AUDITOR[0])
liga(sA, ocx, aud.top + aud.height, ocx, ocy - raio, larg=1.75)
b9 = bolha(sA, ocx, Inches(1.98), Inches(2.25), Inches(0.46), AUDITOR[1], 9, sz=9.5)
liga(sA, ocx, aud.top, ocx, b9.top + b9.height)
auto = agente(sA, ocx, Inches(5.56), Inches(2.25), AH, 10, AUTO[0], sz_nome=11.5)
liga(sA, ocx, ocy + raio, ocx, auto.top, larg=1.75)
b10 = bolha(sA, ocx, Inches(6.38), Inches(2.6), Inches(0.42), AUTO[1], 10)
liga(sA, ocx, auto.top + auto.height, ocx, b10.top)
conectores_atras(sA, depois_de=anel._element)

# ------------------------------------------------------------------ versão B: árvore
sB = sl[9]
limpar(sB, {"Slide Number Placeholder 0"})
sup = [s for s in sB.shapes if s.has_text_frame and s.text_frame.text.startswith("Supervisão")][0]
OCX = Inches(13.333 / 2)
orq = forma(sB, MSO_SHAPE.ROUNDED_RECTANGLE, OCX - Inches(1.15), Inches(1.95), Inches(2.3), Inches(0.62), NAVY, nome="orquestrador")
orq.adjustments[0] = 0.5
escreve(orq, [("Orquestrador Oria", 15, True, BRANCO)])
# Auditor e Autoaprimoramento leem os resultados de TODOS os agentes: ligados ao Orquestrador, tracejado
for num, (nome, frase), lado in ((9, AUDITOR, -1), (10, AUTO, 1)):
    w = Inches(1.62) if num == 9 else Inches(2.10)
    acx = OCX + lado * Inches(2.85)
    a = agente(sB, acx, orq.top + orq.height / 2, w, Inches(0.62), num, nome, sz_nome=12 if num == 9 else 10.5)
    x_orq = orq.left if lado < 0 else orq.left + orq.width
    x_ag = acx + w / 2 if lado < 0 else acx - w / 2
    liga(sB, x_ag, a.top + a.height / 2, x_orq, a.top + a.height / 2, larg=1.25, tracejado=True)
    bw = Inches(2.0)
    bcx = acx + lado * (w / 2 + Inches(0.15) + bw / 2)
    b = bolha(sB, bcx, a.top + a.height / 2, bw, Inches(0.52), frase, num, sz=10)
    liga(sB, acx + lado * w / 2, a.top + a.height / 2, bcx - lado * bw / 2, a.top + a.height / 2)
lab = sB.shapes.add_textbox(OCX + Inches(0.12), Inches(2.66), Inches(3.4), Inches(0.25))
lab.text_frame.margin_left = lab.text_frame.margin_right = 0
escreve(lab, [("Auditor e Autoaprimoramento leem o resultado de todos", 9, False, CINZA)])
lab.text_frame.paragraphs[0].alignment = PP_ALIGN.LEFT
lab.text_frame.paragraphs[0].runs[0].font.italic = True
lab.name = "legenda-leitura"
# barramento e oito agentes
COLS = [Inches(0.6 + 12.13 / 8 * (i + 0.5)) for i in range(8)]
Y_BUS, Y_AG, AGW, AGH = Inches(3.05), Inches(3.62), Inches(1.40), Inches(0.62)
liga(sB, OCX, orq.top + orq.height, OCX, Y_BUS, larg=1.75)
liga(sB, COLS[0], Y_BUS, COLS[-1], Y_BUS, larg=1.75)
ordem = (1, 2, 3, 4, 5, 6, 7, 8)
for cx, n in zip(COLS, ordem):
    nome, d1, d2 = DESCR[n]
    liga(sB, cx, Y_BUS, cx, Y_AG - AGH / 2, larg=1.75)
    a = agente(sB, cx, Y_AG, AGW, AGH, n, nome, sz_nome=12 if n != 7 else 11)
    y_prev = a.top + a.height
    for j, d in enumerate((d1, d2)):
        by = Inches(4.66 + j * 1.06)
        b = bolha(sB, cx, by, Inches(1.46), Inches(0.92), d, n, sz=9)
        b.text_frame.margin_left = b.text_frame.margin_right = Inches(0.1)
        liga(sB, cx, y_prev, cx, b.top)
        y_prev = b.top + b.height
conectores_atras(sB)
sup.top = Inches(6.66)

# notas da versão B (a A mantém as notas que já tinha)
import copy
arv_b = sB.notes_slide.shapes._spTree
for e in list(arv_b)[2:]:
    arv_b.remove(e)
for e in list(sA.notes_slide.shapes._spTree)[2:]:
    arv_b.append(copy.deepcopy(e))

prs.save(sys.argv[2])
print("ok")
