"""Rodada 3: direção de arte (cards preenchidos com conteúdo funcional) + dado do BC atualizado.

Regra da rodada: todo elemento novo é CLONE de um elemento que já existe no deck
(rótulo, texto, divisor, fundo de linha), para herdar fonte, cor e espaçamento. Nada de
estilo novo. Todo texto novo é afirmação que o próprio deck ou o repositório sustenta.
Uso: python3 -I rodada3.py entrada.pptx saida.pptx
"""
import copy
import sys

from lxml import etree
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.util import Inches, Pt

A = "http://schemas.openxmlformats.org/drawingml/2006/main"
P = "http://schemas.openxmlformats.org/presentationml/2006/main"
NAVY, ORANGE, GREEN, GREY_TAG, WHITE = "16263B", "F04600", "2E5B45", "66716C", "FFFFFF"
NBSP = " "

prs = Presentation(sys.argv[1])
S = lambda n: prs.slides[n - 1]  # noqa: E731
log = []
_next_id = [900]


def by_id(slide, sid):
    return [s for s in slide.shapes if s.shape_id == sid][0]


def find(slide, needle):
    hits = [s for s in slide.shapes if s.has_text_frame and needle in s.text_frame.text]
    assert hits, needle
    return hits[0]


def clone(slide, src_el, x, y, w, h, name):
    """Copia um shape (de qualquer slide; só shapes sem relação externa) para `slide`."""
    el = copy.deepcopy(src_el)
    slide.shapes._spTree.append(el)
    _next_id[0] += 1
    el.find(f".//{{{P}}}cNvPr").set("id", str(_next_id[0]))
    el.find(f".//{{{P}}}cNvPr").set("name", name)
    sh = [s for s in slide.shapes if s._element is el][0]
    sh.left, sh.top, sh.width, sh.height = Inches(x), Inches(y), Inches(w), Inches(h)
    return sh


def set_text(sh, text, size=None, bold=None, color=None, spc=None, italic=None, align=None):
    p = sh.text_frame.paragraphs[0]
    runs = p.runs
    runs[0].text = text
    for r in runs[1:]:
        r._r.getparent().remove(r._r)
    for extra in sh.text_frame.paragraphs[1:]:
        extra._p.getparent().remove(extra._p)
    r = p.runs[0]
    if size:
        r.font.size = Pt(size)
    if bold is not None:
        r.font.bold = bold
    if italic is not None:
        r.font.italic = italic
    if color:
        r.font.color.rgb = RGBColor.from_string(color)
    rpr = r._r.get_or_add_rPr()
    if spc is not None:
        rpr.set("spc", str(spc))
    if align is not None:
        p.alignment = align
    return sh


DIVIDER = copy.deepcopy(by_id(S(4), 14)._element)  # divisor fino dos cards do slide 4 (D6DED6, 1 pt)
LABEL = copy.deepcopy(by_id(S(3), 8)._element)     # rótulo laranja espaçado ("TEMPO")
BODY = copy.deepcopy(by_id(S(3), 10)._element)     # texto corrido 15 pt, 404040


def divider(slide, x, y, w, color=None):
    sh = clone(slide, DIVIDER, x, y, w, 0, "divisor")
    if color:
        sh._element.find(f".//{{{A}}}ln//{{{A}}}srgbClr").set("val", color)
    return sh


# ------------------------------------------------------------------ slide 3
# cada consequência aponta a resposta do Oria Digital: o problema já anuncia a solução
s3 = S(3)
for sid in (5, 11, 17, 23):
    by_id(s3, sid).height = Inches(3.62)          # card 2,00 -> 5,62
for sid in (10, 16, 22, 28):
    by_id(s3, sid).height = Inches(0.60)          # corpo: 2 linhas de 15 pt
for sid in (29, 30):
    by_id(s3, sid).top = Inches(5.85)             # faixa "Quem sente" desce junto (vão 0,23")
SOLUCOES = [
    (0.90, "Extração automática", False),
    (3.98, "Conferência entre fontes", False),
    (7.06, "Prova de cada número", False),
    (10.14, "Cada linha vs. mercado", True),
]
for x, txt, dark in SOLUCOES:
    divider(s3, x, 4.78, 2.28, color="34465E" if dark else None)
    set_text(clone(s3, LABEL, x, 4.92, 2.28, 0.22, "rotulo-resposta"), "COMO RESOLVEMOS", size=10)
    set_text(
        clone(s3, BODY, x, 5.17, 2.28, 0.26, "resposta"),
        f"→{NBSP} {txt}", size=13, bold=True, color=WHITE if dark else NAVY,
    )
log.append("S3: cada card ganhou 'COMO RESOLVEMOS' (problema -> resposta), com o divisor dos cards do S4")

# ------------------------------------------------------------------ slide 4
s4 = S(4)
set_text(by_id(s4, 27), "R$ 2,8 tri")
set_text(by_id(s4, 28), "de saldo em set/2026")  # o card já diz "emprestam para empresas"; 1 linha como os vizinhos
src = by_id(s4, 35).text_frame.paragraphs[0].runs[0]
src.text = src.text.replace("Banco Central (set/2026)", "Banco Central (out/2026)")
log.append("S4: R$ 2,7 tri (agosto, relatório de 29/09) -> R$ 2,8 tri (setembro, relatório BC de 29/10/2026); período explícito")

# ------------------------------------------------------------------ slide 5
# cada etapa diz o que sai dela: o leitor vê a cadeia de entregas, não só verbos
s5 = S(5)
for sid in (8, 13, 18, 23, 28):
    by_id(s5, sid).height = Inches(2.40)          # card 3,10 -> 5,50
for sid in (9, 14, 19, 24, 29):
    by_id(s5, sid).height = Inches(1.15)
for sid in (30, 31):
    by_id(s5, sid).top = Inches(5.70)
RESULTADOS = [
    (0.80, "Tudo em uma base única"),
    (3.20, "Lista de divergências e desvios"),
    (5.60, "Caixa e dívida em três cenários"),
    (8.00, "Plano de corte e de renegociação"),
    (10.40, "Excel em fórmula, dossiê e apresentação"),
]
for x, txt in RESULTADOS:
    divider(s5, x, 4.55, 1.90)
    set_text(clone(s5, LABEL, x, 4.66, 1.90, 0.22, "rotulo-resultado"), "RESULTADO", size=10)
    set_text(clone(s5, BODY, x, 4.90, 1.90, 0.50, "resultado"), txt, size=13, bold=True, color=NAVY)
log.append("S5: cada etapa ganhou 'RESULTADO' (o que sai dela)")

# ------------------------------------------------------------------ slide 6
s6 = S(6)
for sid in (6, 29):
    by_id(s6, sid).width = Inches(1.5)  # rótulos MICRO/MACRO ocupavam 3,6" e cobririam a nota
for x in (0.90, 5.25):  # o dono: as fontes listadas são um resumo; há muito mais
    set_text(
        clone(s6, BODY, x + 1.6, 2.13, 2.0, 0.25, "nota-fontes"),
        "principais fontes", size=12, italic=True, color="707070", align=PP_ALIGN.RIGHT,
    )
by_id(s6, 53).height = Inches(2.80)               # lista "O que revela" termina em ~5,30"
divider(s6, 9.60, 5.50, 2.83, color="34465E")
set_text(
    clone(s6, BODY, 9.60, 5.62, 2.83, 0.55, "fecho-revela"),
    "Cada achado chega ao especialista com a fonte que o prova.", size=13, bold=True, color=WHITE,
)
log.append("S6: 'principais fontes' nos cards Micro/Macro; fecho no card 'O que revela'")


# ------------------------------------------------------------------ slides 12 e 14
def painel(slide, x, y, w, h, titulo, contagem, row_bg_id):
    """Painel 'onde pesa': frentes por área de impacto em números grandes (padrão dos números do S4)."""
    bg = clone(slide, copy.deepcopy(by_id(slide, row_bg_id)._element), x, y, w, h, "painel-impacto")
    gd = bg._element.find(f".//{{{A}}}prstGeom/{{{A}}}avLst/{{{A}}}gd")
    if gd is not None:  # raio de ~0,08" como os demais cards (o adj da linha de 0,45" vira um raio enorme num painel de 2")
        gd.set("fmla", f"val {int(0.08 / min(w, h) * 100000)}")
    set_text(clone(slide, LABEL, x + 0.25, y + 0.2, w - 0.5, 0.22, "rotulo-painel"), titulo, size=11)
    set_text(
        clone(slide, BODY, x + 0.25, y + 0.48, w - 0.5, 0.25, "sub-painel"),
        "Frentes por área de impacto. Uma frente pode afetar mais de uma área.", size=11, color="707070",
    )
    col_w = (w - 0.5) / 4
    for i, (cat, color) in enumerate((("EBITDA", ORANGE), ("Dívida", NAVY), ("Caixa", GREEN), ("Risco", GREY_TAG))):
        cx = x + 0.25 + i * col_w
        if i:
            div = divider(slide, cx - 0.12, y + 0.95, 0, None)
            div.width, div.height = 0, Inches(h - 1.2)   # divisor vertical entre os números
        set_text(clone(slide, BODY, cx, y + 0.9, col_w - 0.2, 0.6, "numero-impacto"),
                 str(contagem[cat]), size=32, bold=True, color=color)
        set_text(clone(slide, BODY, cx, y + 1.5, col_w - 0.2, 0.3, "rotulo-impacto"),
                 cat, size=12, bold=True, color="404040")  # o subtítulo já diz "frentes por área"


def contar(slide):
    c = {"EBITDA": 0, "Dívida": 0, "Caixa": 0, "Risco": 0}
    nome = {"EBITDA": "EBITDA", "DÍVIDA": "Dívida", "CAIXA": "Caixa", "RISCO": "Risco"}
    for sh in slide.shapes:
        if sh.has_text_frame and sh.text_frame.text in nome:
            c[nome[sh.text_frame.text]] += 1
    return c


c12 = contar(S(12))  # contado dos selos do próprio slide: a fonte do painel é o slide
painel(S(12), 0.60, 4.00, 5.98, 2.05, "ONDE OS BLOCOS 1 E 2 PESAM", c12, 6)
c14 = contar(S(14))
painel(S(14), 0.60, 4.50, 12.13, 1.85, "ONDE OS BLOCOS 5 E 6 PESAM", c14,
       [s for s in S(14).shapes if s.has_text_frame and s.text_frame.text == ""][0].shape_id)
log.append(f"S12: painel de impacto {c12}")
log.append(f"S14: painel de impacto {c14}")

prs.save(sys.argv[2])
print("\n".join(log))
