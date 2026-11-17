"""Variante do slide 9: distingue os agentes que já operam dos que estão em construção.

Fonte do estado: notas do próprio slide 9 ("Hoje a IA já trabalha na captação, na
conferência e nos entregáveis; os demais agentes são o plano de construção").
Em operação: 1 Captador, 2 Conferidor, 8 Entregas. Em construção: 3 a 7.
Uso: python3 -I slide9_status.py entrada.pptx saida.pptx
"""
import copy
import sys

from pptx import Presentation
from pptx.util import Inches

A = "http://schemas.openxmlformats.org/drawingml/2006/main"
ORANGE, NAVY, GREY = "F04600", "16263B", "707070"
EM_CONSTRUCAO = {17, 19, 22, 25, 28}  # badges 3, 4, 5, 6, 7

prs = Presentation(sys.argv[1])
s9 = prs.slides[8]
shapes = {sh.shape_id: sh for sh in s9.shapes}

for sid in EM_CONSTRUCAO:
    sp = shapes[sid]._element
    spPr = sp.find("{http://schemas.openxmlformats.org/presentationml/2006/main}spPr")
    spPr.find(f"{{{A}}}solidFill/{{{A}}}srgbClr").set("val", "FFFFFF")
    ln = spPr.find(f"{{{A}}}ln")
    ln.set("w", "19050")
    ln.find(f"{{{A}}}solidFill/{{{A}}}srgbClr").set("val", ORANGE)
    sp.find(f".//{{{A}}}rPr/{{{A}}}solidFill/{{{A}}}srgbClr").set("val", ORANGE)

# legenda abaixo da caixa do título (que termina em 1,78") e acima do Agente Conferidor (2,17"), alinhada à margem direita (12,73")
tb = s9.shapes.add_textbox(Inches(8.73), Inches(1.80), Inches(4.0), Inches(0.25))
tb.name = "legenda-status"
tf = tb.text_frame
tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
p = tf.paragraphs[0]
from pptx.enum.text import PP_ALIGN
from pptx.dml.color import RGBColor
from pptx.util import Pt

p.alignment = PP_ALIGN.RIGHT
for txt, color, bold in (("●", ORANGE, True), ("  já em operação", NAVY, False),
                         ("      ○", ORANGE, True), ("  em construção", NAVY, False)):
    r = p.add_run()
    r.text = txt
    r.font.size = Pt(11)
    r.font.bold = bold
    r.font.color.rgb = RGBColor.from_string(color)

prs.save(sys.argv[2])
print("S9: badges 3-7 vazados + legenda de status")
