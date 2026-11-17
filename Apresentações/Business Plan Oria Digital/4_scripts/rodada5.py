"""Rodada 5: o slide 7 (nove análises) é fundido no slide dos agentes, como mapa mental.

Por quê: o deck descrevia o mesmo motor de três jeitos (5 etapas no S5, 9 análises no S7,
8 agentes no S9) sem ponte entre eles, e o S7 listava como prontas 4 análises que estão em 0%
(STATUS_POR_ETAPA_2026-11-11). O dono escolheu: Orquestrador no centro -> 8 agentes -> as
análises de cada agente como ramos.

Preserva do original: círculo do Orquestrador, elipses brancas (borda D6DED6), badges
cheio/vazado, curvas cinza B7C4BA de 1,75 pt, linha de supervisão. A mensagem "o especialista
escolhe a saída que preserva mais valor" do S7 passa para a linha de supervisão.
Uso: python3 -I rodada5.py entrada.pptx saida.pptx
"""
import copy
import math
import sys

from lxml import etree
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.dml import MSO_LINE_DASH_STYLE
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.util import Emu, Inches, Pt

A = "http://schemas.openxmlformats.org/drawingml/2006/main"
P = "http://schemas.openxmlformats.org/presentationml/2006/main"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
NAVY, ORANGE, GREEN, TXT, LINE, BORDA = "16263B", "F04600", "2E5B45", "404040", "B7C4BA", "D6DED6"

prs = Presentation(sys.argv[1])
log = []

# ---------------------------------------------------------------- 1. tira o slide 7
lst = prs.slides._sldIdLst
s7 = prs.slides[6]
_t = [p for p in s7.placeholders if p.placeholder_format.idx == 103][0].text_frame.text
assert "Nove análises" in _t, _t
sld = lst[6]
prs.part.drop_rel(sld.get(f"{{{R}}}id"))
lst.remove(sld)
log.append("S7 (nove análises) removido; o conteúdo vai para o slide dos agentes")

# renumera as seções seguintes (rótulo do placeholder 102)
for s, old, new in ((prs.slides[6], "7 · ", "6 · "), (prs.slides[7], "8 · ", "7 · "), (prs.slides[8], "9 · ", "8 · ")):
    ph = [p for p in s.placeholders if p.placeholder_format.idx == 102][0]
    r = ph.text_frame.paragraphs[0].runs[0]
    assert r.text.startswith(old), r.text
    r.text = new + r.text[len(old):]
log.append("Rótulos de seção renumerados: 7->6, 8->7, 9->8")

# ---------------------------------------------------------------- 2. mapa mental
s = prs.slides[7]  # agentes
shapes = {sh.shape_id: sh for sh in s.shapes}
ELIPSE = copy.deepcopy(shapes[12]._element)
BADGE_ON = copy.deepcopy(shapes[13]._element)
BADGE_OFF = copy.deepcopy(shapes[17]._element)
for sid in (5, 6, 7, 8, 20, 23, 26, 29, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 24, 25, 27, 28, 30, 31):
    el = shapes[sid]._element
    el.getparent().remove(el)
for sh in list(s.shapes):
    if sh.name == "legenda-status":
        sh._element.getparent().remove(sh._element)

CX, CY, RING = 6.665, 4.095, 1.075          # centro do círculo do Orquestrador (já existente)
ROWS = (2.415, 3.535, 4.655, 5.775)          # simétricas em torno de CY; passo 1,12"
EW, EH = 2.30, 0.92                          # elipse do agente (2,10" partia "Agente Estrategista" em 2 linhas)
RIGHT_E, LEFT_E = 8.24, 2.79                 # x da elipse (direita / esquerda)
RIGHT_L, LEFT_L, LW, LH = 10.72, 0.60, 2.01, 0.27   # pílulas das análises
_id = [3000]

AGENTES = [  # (n, opera?, nome, papel, [(existe?, análise)])  — lado, linha
    (1, True, "Captador", "Reúne documentos e dados.", [(1, "Leitura de documentos"), (1, "Pendências do mandato"), (0, "SPED e Open Finance")]),
    (2, True, "Conferidor", "Aponta o que não bate.", [(1, "Reconciliações"), (1, "Mútuos e intragrupo"), (1, "Perguntas ao cliente")]),
    (3, False, "Mercado", "Compara com setor e região.", [(1, "Índices macro"), (0, "Comparativo setorial")]),
    (4, False, "Risco", "Acha o passivo escondido.", [(0, "Processos e protestos"), (0, "Bureaus e dívida ativa"), (0, "Score de risco")]),
    (5, False, "Caixa", "Projeta o caixa e o estresse.", [(1, "Capital de giro e aging"), (0, "Fluxo de 13 semanas")]),
    (6, False, "Dívida", "Organiza a dívida por credor.", [(1, "Mapa da dívida"), (1, "Capacidade de pagamento"), (0, "Recuperação por credor")]),
    (7, False, "Estrategista", "Simula as saídas.", [(1, "Três cenários e EBITDA"), (0, "Valuation"), (0, "Propostas aos credores")]),
    (8, True, "Entregas", "Monta book e apresentação.", [(1, "Excel em fórmula viva"), (0, "Apresentação de crédito")]),
]
# horário a partir do alto à direita: 1-4 descem pela direita, 5-8 sobem pela esquerda
POS = {1: ("R", 0), 2: ("R", 1), 3: ("R", 2), 4: ("R", 3), 5: ("L", 3), 6: ("L", 2), 7: ("L", 1), 8: ("L", 0)}


def place(el, x, y, w, h, name):
    el = copy.deepcopy(el)
    s.shapes._spTree.append(el)
    _id[0] += 1
    c = el.find(f".//{{{P}}}cNvPr")
    c.set("id", str(_id[0]))
    c.set("name", name)
    sh = [x_ for x_ in s.shapes if x_._element is el][0]
    sh.left, sh.top, sh.width, sh.height = Inches(x), Inches(y), Inches(w), Inches(h)
    return sh


def curve(x1, y1, x2, y2, width_emu, name):
    """Curva em S (curvedConnector3), cinza do original, sem ponta de seta."""
    c = s.shapes.add_connector(MSO_CONNECTOR.CURVE, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    c.name = name
    c.line.color.rgb = RGBColor.from_string(LINE)
    c.line.width = Emu(width_emu)
    # conectores entram atrás dos nós: move para logo depois do fundo
    sp = c._element
    sp.getparent().remove(sp)
    s.shapes._spTree.insert(3, sp)
    return c


def texto(sh, paras_spec, algn="ctr", ins=0.04):
    tx = sh._element.find(f"{{{P}}}txBody")
    bp = tx.find(f"{{{A}}}bodyPr")
    for k in ("lIns", "rIns"):
        bp.set(k, str(int(Inches(ins))))
    bp.set("tIns", "0")
    bp.set("bIns", "0")
    bp.set("anchor", "ctr")
    for p in tx.findall(f"{{{A}}}p"):
        tx.remove(p)
    for runs in paras_spec:
        p = etree.SubElement(tx, f"{{{A}}}p")
        etree.SubElement(p, f"{{{A}}}pPr", algn=algn)
        for t, size, bold, color in runs:
            r = etree.SubElement(p, f"{{{A}}}r")
            rpr = etree.SubElement(r, f"{{{A}}}rPr", lang="pt-BR", sz=str(int(size * 100)), b="1" if bold else "0")
            f = etree.SubElement(rpr, f"{{{A}}}solidFill")
            etree.SubElement(f, f"{{{A}}}srgbClr", val=color)
            etree.SubElement(r, f"{{{A}}}t").text = t


for n, on, nome, papel, itens in AGENTES:
    side, row = POS[n]
    ya = ROWS[row]
    ex = RIGHT_E if side == "R" else LEFT_E
    e = place(ELIPSE, ex, ya - EH / 2, EW, EH, f"agente-{n}")
    texto(e, [[("Agente " + nome, 11.5, True, NAVY)], [(papel, 9.5, False, TXT)]], ins=0.02)
    b = place(BADGE_ON if on else BADGE_OFF, ex + 0.02, ya - EH / 2 - 0.1, 0.38, 0.38, f"badge-{n}")
    b.text_frame.paragraphs[0].runs[0].text = str(n)

    # Orquestrador -> agente: sai do anel na direção do agente
    inner_x = ex if side == "R" else ex + EW
    ang = math.atan2(ya - CY, inner_x - CX)
    curve(CX + RING * math.cos(ang), CY + RING * math.sin(ang), inner_x, ya, 22225, f"liga-orq-{n}")

    # agente -> análises
    k = len(itens)
    gap = 0.31  # vão interno 0,04" x vão entre grupos ~0,22": os grupos se leem separados (revisor: 0,16" fundia)
    ys = [ya + (i - (k - 1) / 2) * gap for i in range(k)]
    lx = RIGHT_L if side == "R" else LEFT_L
    outer_x = ex + EW if side == "R" else ex
    for (existe, txt), yl in zip(itens, ys):
        leaf_in = lx if side == "R" else lx + LW
        curve(outer_x, ya, leaf_in, yl, 12700, f"liga-analise-{n}")
        pill = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(lx), Inches(yl - LH / 2), Inches(LW), Inches(LH))
        pill.name = f"analise-{n}"
        pill.adjustments[0] = 0.5
        pill.shadow.inherit = False
        if existe:
            pill.fill.solid()
            pill.fill.fore_color.rgb = RGBColor.from_string("FFFFFF")
            pill.line.color.rgb = RGBColor.from_string(BORDA)
        else:
            pill.fill.background()
            pill.line.color.rgb = RGBColor.from_string(LINE)
            pill.line.dash_style = MSO_LINE_DASH_STYLE.DASH
        pill.line.width = Pt(1)
        texto(pill, [[("●  " if existe else "○  ", 10, True, ORANGE), (txt, 10, False, NAVY if existe else TXT)]],
              algn="l", ins=0.1)
        # sem estilo de tema no texto (o add_shape traz fontRef lt1)
        st = pill._element.find(f"{{{P}}}style")
        if st is not None:
            pill._element.remove(st)
            pill.line.color.rgb = RGBColor.from_string(BORDA if existe else LINE)

# legenda única (vale para badge do agente e para a pílula da análise)
leg = s.shapes.add_textbox(Inches(7.73), Inches(1.55), Inches(5.0), Inches(0.25))
leg.name = "legenda-status"
texto(leg, [[("Agentes e análises:   ", 10.5, True, NAVY), ("●", 14, True, ORANGE), ("  já existe     ", 10.5, False, NAVY), ("○", 14, True, ORANGE), ("  em construção", 10.5, False, NAVY)]],
      algn="r", ins=0)

# supervisão herda a mensagem do slide 7 que saiu
sup = shapes[32].text_frame.paragraphs[0].runs
assert sup[0].text.strip().startswith("Supervisão")
sup[-1].text = " o Especialista Oria aprova cada etapa e escolhe a saída que preserva mais valor para a empresa e para os credores."
for r in sup[1:-1]:
    r._r.getparent().remove(r._r)

nt = s.notes_slide.notes_text_frame.paragraphs[0]
nt.runs[0].text = (
    "O Orquestrador Oria coordena oito agentes de IA, e cada ramo mostra o que o agente analisa. "
    "Cheio é o que já existe no sistema; vazado é o que está em construção. Hoje operam o Captador, "
    "o Conferidor e o Entregas, e já existem reconciliações, mútuos e intragrupo, mapa da dívida, "
    "capacidade de pagamento, capital de giro, três cenários e o Excel em fórmula viva. Valuation, "
    "comparativo setorial, recuperação por credor e propostas aos credores são o plano de construção, "
    "e o catálogo cresce a cada mandato. O especialista aprova cada etapa e escolhe a saída que "
    "preserva mais valor; cada agente só ganha autonomia onde mede o próprio acerto."
)
for r in nt.runs[1:]:
    r._r.getparent().remove(r._r)
tot = sum(len(a[4]) for a in AGENTES)
ok = sum(e for a in AGENTES for e, _ in a[4])
log.append(f"Slide dos agentes vira mapa mental: Orquestrador -> 8 agentes -> {tot} análises ({ok} já existem, {tot - ok} em construção)")

# ---------------------------------------------------------------- 3. acabamento (revisor independente, rodada 5)
s9 = prs.slides[8]  # pilares
sh9 = {x.shape_id: x for x in s9.shapes}
for sid in (14, 19, 24, 29):  # títulos dos pilares ancorados embaixo: 1 e 2 linhas terminam na mesma base
    bp = sh9[sid].text_frame._txBody.find(f"{{{A}}}bodyPr")
    bp.set("anchor", "b")
    for k in list(bp):
        if k.tag.endswith("spAutoFit"):
            bp.remove(k)
for sid in (205, 206):        # setas ~0,08" acima do centro dos cards da linha do tempo
    sh9[sid].top = sh9[sid].top + Inches(0.08)
s6 = prs.slides[5]
res = [x for x in s6.shapes if x.has_text_frame and x.text_frame.text.startswith("Resultado:")][0]
res.top = Inches(6.52)        # 0,15" -> 0,22" dos cards, como nos outros slides
log.append("Acabamento: títulos dos pilares com base comum, setas centradas, 'Resultado:' com respiro")

prs.save(sys.argv[2])
print("\n".join(log))
