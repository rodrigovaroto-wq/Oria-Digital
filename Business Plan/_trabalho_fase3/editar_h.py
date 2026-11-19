"""Fase 3, edições H (escolha do dono, 19/11): fica a versão B (árvore) do slide de estratégia operacional, com
um ramo só por agente, sem numeração e com borda laranja em todos os agentes; a versão A sai do deck.
Uso: python3 editar_h.py entrada.pptx saida.pptx   (entrada = saída do editar_g.py, com A no slide 9 e B no 10)"""
import copy
import sys

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.dml import MSO_LINE_DASH_STYLE
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Emu, Inches, Pt

NAVY, ORANGE, BORDA, LINHA, CINZA, BRANCO = (RGBColor.from_string(c) for c in
                                             ("16263B", "F04600", "D6DED6", "B7C4BA", "707070", "FFFFFF"))
UM_RAMO = {
    1: ("Captador", "Lê os documentos e busca dados na Receita e nos bancos"),
    2: ("Conferidor", "Cruza a contabilidade com fontes externas e aponta o que não bate"),
    3: ("Mercado", "Compara a empresa e os juros com o setor e o mercado"),
    4: ("Risco", "Mapeia processos, protestos e dívida ativa antes da crise"),
    5: ("Caixa", "Mostra até onde o caixa aguenta, semana a semana"),
    6: ("Dívida", "Mapeia a dívida e mede a capacidade de pagamento"),
    7: ("Estrategista", "Propõe cortes, renegociação e propostas aos credores"),
    8: ("Entregas", "Monta modelo, dossiê e apresentação, com a prova"),
}
AUDITOR = ("Auditor", "Revisa o trabalho de todos os agentes")
AUTO = ("Autoaprimoramento", "Propõe melhorias a partir dos erros")

prs = Presentation(sys.argv[1])

# a versão A (slide 9) sai; as notas dela já foram copiadas para a B
ids = prs.slides._sldIdLst
a = list(ids)[8]
prs.part.drop_rel(a.rId)
ids.remove(a)
s = prs.slides[8]
assert s.shapes.title is None or True


def forma(tipo, x, y, w, h, fill, line=None, larg=1, nome=None):
    f = s.shapes.add_shape(tipo, Emu(int(x)), Emu(int(y)), Emu(int(w)), Emu(int(h)))
    f.fill.solid()
    f.fill.fore_color.rgb = fill
    if line is None:
        f.line.fill.background()
    else:
        f.line.color.rgb, f.line.width = line, Pt(larg)
    f.shadow.inherit = False
    if nome:
        f.name = nome
    tf = f.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = Inches(0.08)
    tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    return f


def escreve(f, linhas):
    tf = f.text_frame
    for i, (txt, sz, b, cor) in enumerate(linhas):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.CENTER
        r = p.add_run()
        r.text, r.font.size, r.font.bold, r.font.color.rgb = txt, Pt(sz), b, cor


def agente(cx, cy, w, h, num, nome, sz_nome):
    f = forma(MSO_SHAPE.OVAL, cx - w / 2, cy - h / 2, w, h, BRANCO, ORANGE, 1.5, nome=f"agente-{num}")
    escreve(f, [("Agente", 10, False, CINZA), (nome, sz_nome, True, NAVY)])
    return f


def bolha(cx, cy, w, h, texto, num, sz):
    f = forma(MSO_SHAPE.OVAL, cx - w / 2, cy - h / 2, w, h, BRANCO, BORDA, 1, nome=f"ramo-{num}")
    f.text_frame.margin_left = f.text_frame.margin_right = Inches(0.12)
    escreve(f, [(texto, sz, False, NAVY)])
    return f


def liga(x1, y1, x2, y2, larg=1.25, tracejado=False):
    c = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Emu(int(x1)), Emu(int(y1)), Emu(int(x2)), Emu(int(y2)))
    c.line.color.rgb, c.line.width = LINHA, Pt(larg)
    if tracejado:
        c.line.dash_style = MSO_LINE_DASH_STYLE.DASH
    return c


# limpa o desenho da árvore anterior e redesenha (ficam rótulo, título, supervisão e número do slide)
for f in list(s.shapes):
    fica = f.name == "Slide Number Placeholder 0" or (f.has_text_frame and (
        f.text_frame.text.startswith("8 · ") or f.text_frame.text.startswith("Onze agentes")
        or f.text_frame.text.startswith("Supervisão")))
    if not fica:
        f._element.getparent().remove(f._element)

OCX = Inches(13.333 / 2)
orq = forma(MSO_SHAPE.ROUNDED_RECTANGLE, OCX - Inches(1.15), Inches(1.95), Inches(2.3), Inches(0.62), NAVY, nome="orquestrador")
orq.adjustments[0] = 0.5
escreve(orq, [("Orquestrador Oria", 15, True, BRANCO)])
ymid = orq.top + orq.height / 2
for num, (nome, frase), lado in ((9, AUDITOR, -1), (10, AUTO, 1)):
    w = Inches(1.62) if num == 9 else Inches(2.10)
    acx = OCX + lado * Inches(2.85)
    ag = agente(acx, ymid, w, Inches(0.62), num, nome, 12 if num == 9 else 10.5)
    liga(acx + w / 2 if lado < 0 else acx - w / 2, ymid, orq.left if lado < 0 else orq.left + orq.width, ymid, tracejado=True)
    bw = Inches(2.0)
    bcx = acx + lado * (w / 2 + Inches(0.15) + bw / 2)
    bolha(bcx, ymid, bw, Inches(0.52), frase, num, 10)
    liga(acx + lado * w / 2, ymid, bcx - lado * bw / 2, ymid)
lab = s.shapes.add_textbox(OCX + Inches(0.12), Inches(2.66), Inches(3.4), Inches(0.25))
lab.name = "legenda-leitura"
lab.text_frame.margin_left = lab.text_frame.margin_right = 0
escreve(lab, [("Auditor e Autoaprimoramento leem o resultado de todos", 9, False, CINZA)])
lab.text_frame.paragraphs[0].alignment = PP_ALIGN.LEFT
lab.text_frame.paragraphs[0].runs[0].font.italic = True

COLS = [Inches(0.6 + 12.13 / 8 * (i + 0.5)) for i in range(8)]
Y_BUS, Y_AG, AGW, AGH = Inches(3.10), Inches(3.75), Inches(1.40), Inches(0.66)
liga(OCX, orq.top + orq.height, OCX, Y_BUS, larg=1.75)
liga(COLS[0], Y_BUS, COLS[-1], Y_BUS, larg=1.75)
for cx, n in zip(COLS, range(1, 9)):
    nome, frase = UM_RAMO[n]
    liga(cx, Y_BUS, cx, Y_AG - AGH / 2, larg=1.75)
    ag = agente(cx, Y_AG, AGW, AGH, n, nome, 12 if n != 7 else 11)
    b = bolha(cx, Inches(5.12), Inches(1.46), Inches(1.40), frase, n, 10)
    liga(cx, ag.top + ag.height, cx, b.top)

arv = s.shapes._spTree
cx_el = [e for e in list(arv) if e.tag.endswith("cxnSp")]
for e in cx_el:
    arv.remove(e)
for e in reversed(cx_el):
    arv[1].addnext(e)

prs.save(sys.argv[2])
print("ok")
