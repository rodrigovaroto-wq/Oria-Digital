"""Fase 3, edições D (revisão do dono, 19/11): slides 2, 4, 8 (modelo de negócio, layout novo) e 9 (estratégia
operacional com IA, mapa simétrico). Uso: python3 editar_d.py entrada.pptx saida.pptx"""
import math
import sys

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Emu, Inches, Pt

NAVY, ORANGE, BORDA, TEXTO, CINZA = (RGBColor.from_string(c) for c in ("16263B", "F04600", "D6DED6", "404040", "707070"))
BRANCO, CURVA = RGBColor.from_string("FFFFFF"), RGBColor.from_string("B7C4BA")

prs = Presentation(sys.argv[1])
sl = prs.slides


def por_nome(slide, nome):
    return [s for s in slide.shapes if s.name == nome]


def texto_unico(shape, novo):
    """Troca o texto mantendo a formatação do primeiro run e esvaziando os demais."""
    runs = [r for p in shape.text_frame.paragraphs for r in p.runs]
    runs[0].text = novo
    for r in runs[1:]:
        r.text = ""


# ------------------------------------------------------------------ slide 2: o valor em jogo é a dívida
s2 = sl[1]
texto_unico(por_nome(s2, "t15")[0], "R$ 244,4 bi")
r = [r for p in por_nome(s2, "t16")[0].text_frame.paragraphs for r in p.runs]
r[0].text = "em dívidas de 9,3 milhões de empresas inadimplentes: recorde (ago/2026)."

# ------------------------------------------------------------------ slide 4: fonte sem a frase de RJ 2026
texto_unico(por_nome(sl[3], "t72")[0], "Serasa Experian (abr/2026); KPMG (2025); Banco Central (out/2026); Anbima (nov/2026).")

# ------------------------------------------------------------------ slide 8: modelo de negócio, layout próprio
s8 = sl[7]
manter = {"Slide Number Placeholder 0"}
textos = [s for s in s8.shapes if s.name == "Text 2"]  # rótulo e título
nota = por_nome(s8, "t72")[0]
for s in list(s8.shapes):
    if s._element not in [x._element for x in textos] and s._element is not nota._element and s.name not in manter:
        s._element.getparent().remove(s._element)


def caixa(slide, x, y, w, h, fill, line=None, shape=MSO_SHAPE.ROUNDED_RECTANGLE, nome=None, adj=0.08):
    b = slide.shapes.add_shape(shape, Inches(x), Inches(y), Inches(w), Inches(h))
    if shape == MSO_SHAPE.ROUNDED_RECTANGLE:
        b.adjustments[0] = adj
    b.fill.solid()
    b.fill.fore_color.rgb = fill
    if line is None:
        b.line.fill.background()
    else:
        b.line.color.rgb = line
        b.line.width = Pt(1)
    b.shadow.inherit = False
    if nome:
        b.name = nome
    return b


def texto(slide, x, y, w, h, partes, anchor=MSO_ANCHOR.TOP, align=PP_ALIGN.LEFT, nome=None, espaco=0):
    """partes: lista de parágrafos; cada parágrafo = lista de (texto, tamanho, negrito, cor, spacing)."""
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    if nome:
        tb.name = nome
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = tf.margin_right = tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = anchor
    for i, par in enumerate(partes):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        if i and espaco:
            p.space_before = Pt(espaco)
        for txt, sz, b, cor, *sp in par:
            run = p.add_run()
            run.text = txt
            run.font.size = Pt(sz)
            run.font.bold = b
            run.font.color.rgb = cor
            if sp and sp[0]:
                run.font._element.set("spc", str(sp[0]))
    return tb


# painel escuro à esquerda: o que vendemos / para quem
caixa(s8, 0.60, 1.95, 4.05, 4.45, NAVY, nome="painel-proposta", adj=0.05)
texto(s8, 0.95, 2.25, 3.40, 1.75, [
    [("O QUE VENDEMOS", 11, True, ORANGE, 300)],
    [("Diagnóstico 360° e acompanhamento contínuo, com a prova de cada número.", 17, True, BRANCO)],
], nome="proposta-o-que", espaco=8)
linha = s8.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(0.95), Inches(4.12), Inches(4.30), Inches(4.12))
linha.line.color.rgb = RGBColor.from_string("3A4A5E")
linha.line.width = Pt(1)
texto(s8, 0.95, 4.35, 3.40, 1.85, [
    [("PARA QUEM", 11, True, ORANGE, 300)],
    [("Os dois lados da mesa: quem precisa se reestruturar e quem precisa confiar nos números para emprestar, comprar ou renegociar.", 15, False, BRANCO)],
], nome="proposta-para-quem", espaco=8)

# quatro receitas em linhas: destaque laranja | título + descrição
linhas = [
    ("Receita de entrada", "por mandato", "Diagnóstico por mandato", "Visão 360°, modelo, dossiê e apresentação aos credores."),
    ("Mensal recorrente", "por contrato", "Acompanhamento contínuo", "Empresas em pós-reestruturação e carteiras de credores."),
    ("Licença de uso", "por perfil de acesso", "Plataforma por usuário", "Empresas, credores e fundos acompanham seus mandatos e carteiras."),
    ("Variável", "complemento da receita", "Bônus por resultado", "Mediante contrato, atrelado ao plano aprovado."),
]
y0, h, gap = 1.95, 1.0, 0.15
for i, (dest, sub, tit, desc) in enumerate(linhas):
    y = y0 + i * (h + gap)
    caixa(s8, 4.90, y, 7.83, h, BRANCO, BORDA, nome=f"receita-{i+1}", adj=0.12)
    texto(s8, 5.20, y, 2.55, h, [[(dest, 20, True, ORANGE)], [(sub, 12, False, CINZA)]],
          anchor=MSO_ANCHOR.MIDDLE, nome=f"receita-{i+1}-destaque", espaco=2)
    sep = s8.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(7.95), Inches(y + 0.2), Inches(7.95), Inches(y + h - 0.2))
    sep.line.color.rgb = BORDA
    sep.line.width = Pt(1)
    texto(s8, 8.20, y, 4.30, h, [[(tit, 15, True, NAVY)], [(desc, 13, False, TEXTO)]],
          anchor=MSO_ANCHOR.MIDDLE, nome=f"receita-{i+1}-texto", espaco=2)
# a nota de rodapé fica por cima, por último
nota._element.getparent().remove(nota._element)
s8.shapes._spTree.append(nota._element)

# ------------------------------------------------------------------ slide 9: estratégia operacional com IA, simétrico
s9 = sl[8]
for s in s9.shapes:
    if s.has_text_frame and s.text_frame.text == "8 · A ESTRATÉGIA DE IA":
        texto_unico(s, "8 · ESTRATÉGIA OPERACIONAL COM IA")
for c in [s for s in s9.shapes if s.element.tag.endswith("cxnSp")]:
    c._element.getparent().remove(c._element)

anel = por_nome(s9, "Oval 10")[0]
cx, cy = anel.left + anel.width // 2, anel.top + anel.height // 2
raio = anel.width // 2
TOPOS = [1.80, 3.04, 4.28, 5.52]  # topo de cada linha de ramos (4 vagas de 0,28"; 0,14" entre grupos)
PASSO, PILL_H = 0.28, 0.26


def curva(x1, y1, x2, y2, largura):
    c = s9.shapes.add_connector(MSO_CONNECTOR.CURVE, Emu(int(x1)), Emu(int(y1)), Emu(int(x2)), Emu(int(y2)))
    c.line.color.rgb = CURVA
    c.line.width = Pt(largura)
    return c


for lado, agentes in (("esq", [1, 2, 3, 4]), ("dir", [5, 6, 7, 8])):
    for linha_i, n in enumerate(agentes):
        topo = TOPOS[linha_i]
        ramos = por_nome(s9, f"analise-{n}")
        k = len(ramos)
        off = (4 - k) * PASSO / 2
        centro_y = Inches(topo + (3 * PASSO + PILL_H) / 2)
        ag, bd = por_nome(s9, f"agente-{n}")[0], por_nome(s9, f"badge-{n}")[0]
        ag.left = Inches(3.57) if lado == "esq" else Inches(7.76)
        ag.top = int(centro_y - ag.height / 2)
        bd.left, bd.top = ag.left, ag.top - Emu(96012)
        for j, r in enumerate(ramos):
            r.left = Inches(0.79) if lado == "esq" else Inches(9.94)
            r.top = Inches(topo + off + j * PASSO)
            ry = r.top + r.height // 2
            if lado == "esq":
                curva(ag.left, centro_y, r.left + r.width, ry, 1)
            else:
                curva(ag.left + ag.width, centro_y, r.left, ry, 1)
        # do anel até a borda interna do agente
        ax = ag.left + ag.width if lado == "esq" else ag.left
        ang = math.atan2(centro_y - cy, ax - cx)
        curva(cx + raio * math.cos(ang), cy + raio * math.sin(ang), ax, centro_y, 1.75)

# Auditor (acima) e Autoaprimoramento (abaixo), com uma frase cada, no eixo do Orquestrador
for n, y_ag, y_pill, frase in ((9, 2.05, 1.66, "Revisa o trabalho dos agentes"),
                               (10, 5.42, 6.33, "Propõe melhorias a partir dos erros")):
    ag, bd = por_nome(s9, f"agente-{n}")[0], por_nome(s9, f"badge-{n}")[0]
    ag.left = int(cx - ag.width / 2)
    ag.top = Inches(y_ag)
    bd.left, bd.top = ag.left, ag.top - Emu(96012)
    if n == 9:
        s9.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Emu(int(cx)), ag.top + ag.height, Emu(int(cx)), cy - raio)
    else:
        s9.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Emu(int(cx)), cy + raio, Emu(int(cx)), ag.top)
    pill = caixa(s9, 0, y_pill, 2.6, PILL_H, BRANCO, BORDA, nome=f"analise-{n}", adj=0.5)
    pill.left = int(cx - pill.width / 2)
    tf = pill.text_frame
    tf.margin_top = tf.margin_bottom = 0
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER
    a = p.add_run()
    a.text = "→ "
    a.font.size, a.font.bold, a.font.color.rgb = Pt(10), True, ORANGE
    b = p.add_run()
    b.text = frase
    b.font.size, b.font.color.rgb = Pt(10), NAVY
for c in s9.shapes:
    if c.element.tag.endswith("cxnSp") and c.line.color and c.line.color.type is None:
        c.line.color.rgb = CURVA
        c.line.width = Pt(1.75)

# conectores atrás dos nós: logo depois do anel
arvore = s9.shapes._spTree
anel_el = anel._element
for c in [e for e in list(arvore) if e.tag.endswith("cxnSp")]:
    arvore.remove(c)
    anel_el.addnext(c)
prs.save(sys.argv[2])
print("ok")
