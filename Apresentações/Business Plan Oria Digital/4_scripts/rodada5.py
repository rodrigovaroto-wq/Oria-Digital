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

# geometria (pedido do dono: 1-4 à esquerda, 5-8 à direita; ramos mais largos e específicos)
CX, CY = 6.665, 4.16                          # centro do Orquestrador
RING_D, CORE_D = 1.75, 1.43                   # anel e núcleo reduzidos (eram 2,15 e 1,76) para abrir espaço aos ramos
RING = RING_D / 2
EW, EH = 1.90, 0.78                           # elipse do agente: "Agente" + nome
LEFT_E, RIGHT_E = 3.72, 7.71
LW_BASE = 2.95                                # largura de referência das pílulas (2,95")
LW = round(LW_BASE * 0.84, 3)  # 18/11: 0,88 -> 0,84 ("um pouquinho mais"); depois o mapa todo cresce 5%                 # dono (18/11): pílula 12% mais estreita, só cortando o branco após o texto;
                                              # o texto mais longo ocupa ~2,25", então 2,60" ainda folga
LEFT_L = 0.60 + (LW_BASE - LW)                # lado esquerdo: a borda que encosta na curva fica parada
RIGHT_L, LH = 9.78, 0.25
PITCH, GROUP_GAP = 0.285, 0.21                # vão interno 0,035" x vão entre grupos 0,21"
_id = [3000]

# Cada ramo é uma ENTREGA (nome de etapa, nunca frase corrida — regra do dono) e tem evidência no repositório.
# Cinco ramos ficam com o texto original por decisão do dono: fingerprint, capacidade de pagamento,
# liquidez de 13 semanas, waterfall de credores, capital de giro.
# Status: ● = no código hoje; ○ = etapa do STATUS_POR_ETAPA_2026-11-11.md ainda não concluída.
# Rodada de auditoria (pedido do dono): saíram métricas que não dizem nada a quem decide
# ("4 formatos", "fingerprint", "14 abas", "7 fórmulas e 89 premissas"); a evidência ficou aqui.
AGENTES = [  # (n, agente opera?, nome, [(existe?, análise)])
    (1, True, "Captador", [
        (1, "Leitura de documentos sem digitação"),            # ROADMAP:122 ingestão de 4 formatos + extração
        (1, "Duplicata barrada por fingerprint"),           # ROADMAP:122 fingerprint contra reenvio
        (1, "Controle de documentos pendentes"),         # kit do mandato, ESTADO S130, 0300/0301
        (0, "Coleta de SPED, ECD e NF-e na fonte")]),         # STATUS fase 16 (ondas 1 e 3), 0%
    (2, True, "Conferidor", [
        (1, "Conferência de balanço, caixa e DRE"),           # 0009, 0015 (caixa BP x DFC), 0105, 0133
        (1, "Conciliação de mútuos do grupo"),       # 0117, 0124
        (1, "Perguntas ao cliente sobre lacunas"),           # portal/src/lib/perguntas.ts
        (0, "Consolidação sem dupla contagem")]),          # STATUS 5.3/5.4 eliminação intragrupo, 0%
    (3, False, "Mercado", [
        (1, "Projeção com IPCA e Selic do Focus"),        # export/route.ts:200 (premissas de inflação/juro)
        (0, "Juro por contrato vs. Banco Central"),       # STATUS 18.6 dívida contra o Banco Central
        (0, "Despesas vs. setor e região")]),      # STATUS 18.3/18.5
    (4, False, "Risco", [
        (0, "Sinais de deterioração financeira"),        # STATUS 10.1-10.3
        (0, "Mapeamento de processos e bureau"),      # STATUS 17.3/17.4
        (0, "Nota de risco para o comitê")]),             # scorecard em deck-credito.ts (estrutura)
    (5, False, "Caixa", [
        (1, "Capital de giro: NCG e ciclo"),            # modelo-institucional.ts aba Capital de Giro (NCG)
        (1, "Aging conciliado com o balanço"),        # 0274 aging conciliado com o balanço
        (0, "Liquidez de 13 semanas")]),            # STATUS 9.1-9.3 liquidez de 13 semanas
    (6, False, "Dívida", [
        (1, "Mapa da dívida por vencimento"),          # portal/src/lib/mapa-da-divida.ts
        (1, "Capacidade de pagamento em fórmula"),        # modelo-institucional.ts:6062 (ND/EBITDA)
        (0, "Garantias e covenants por credor"),          # STATUS 8.1-8.3
        (0, "Waterfall de credores")]),             # STATUS 12.1-12.3 waterfall, Lei 11.101
    (7, False, "Estrategista", [
        (1, "Plano em 3 cenários, com stress"),               # modelo-institucional.ts:96 Base/Cliente/Stress
        (0, "Recálculo automático das premissas"),           # STATUS 6.1/6.2 motor de cálculo
        (0, "Valuation por DCF e múltiplos"),         # STATUS 11.1/11.2
        (0, "Simulação de propostas aos credores")]),        # STATUS 13.1-13.4 carência, haircut, new money
    (8, True, "Entregas", [
        (1, "Modelo do comitê auditável em Excel"),       # modelo-institucional.ts:73-78 (14 abas em fórmula)
        (1, "Base de dados conferível no 1º dia"),        # export/route.ts ?modo=dados "desde a ingestão"
        (0, "Apresentação de crédito pronta")]),       # STATUS 14.3 (80%) / 14.4
]
SIDE = {n: ("L" if n <= 4 else "R") for n in range(1, 9)}


def layout(ns):
    """Centros das pílulas e do grupo, empilhando os grupos de um lado em torno de CY."""
    grupos = [len(AGENTES[n - 1][3]) for n in ns]
    total = sum(g * PITCH - (PITCH - LH) for g in grupos) + GROUP_GAP * (len(grupos) - 1)
    y = CY - total / 2
    out = {}
    for n, g in zip(ns, grupos):
        ys = [y + LH / 2 + i * PITCH for i in range(g)]
        out[n] = ((ys[0] + ys[-1]) / 2, ys)
        y += g * PITCH - (PITCH - LH) + GROUP_GAP
    return out


POS = {**layout([1, 2, 3, 4]), **layout([5, 6, 7, 8])}

# Orquestrador menor, recentrado
for sid, d in ((11, RING_D), (9, CORE_D), (10, CORE_D)):
    sh = shapes[sid]
    sh.left, sh.top, sh.width, sh.height = Inches(CX - d / 2), Inches(CY - d / 2), Inches(d), Inches(d)
for r in shapes[10].text_frame.paragraphs:
    for run in r.runs:
        run.font.size = Pt(15)


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


for n, on, nome, itens in AGENTES:
    side = SIDE[n]
    ya, ys = POS[n]
    ex = RIGHT_E if side == "R" else LEFT_E
    e = place(ELIPSE, ex, ya - EH / 2, EW, EH, f"agente-{n}")
    texto(e, [[("Agente", 9.5, False, TXT)], [(nome, 13, True, NAVY)]], ins=0.02)
    b = place(BADGE_ON if on else BADGE_OFF, ex + 0.0, ya - EH / 2 - 0.1, 0.36, 0.36, f"badge-{n}")
    b.text_frame.paragraphs[0].runs[0].text = str(n)

    inner_x = ex if side == "R" else ex + EW
    ang = math.atan2(ya - CY, inner_x - CX)
    curve(CX + RING * math.cos(ang), CY + RING * math.sin(ang), inner_x, ya, 22225, f"liga-orq-{n}")

    lx = RIGHT_L if side == "R" else LEFT_L
    outer_x = ex + EW if side == "R" else ex
    for (existe, txt), yl in zip(itens, ys):
        leaf_in = lx if side == "R" else lx + LW
        curve(outer_x, ya, leaf_in, yl, 12700, f"liga-analise-{n}")
        pill = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(lx), Inches(yl - LH / 2), Inches(LW), Inches(LH))
        pill.name = f"analise-{n}"
        pill.adjustments[0] = 0.5
        st = pill._element.find(f"{{{P}}}style")
        if st is not None:
            pill._element.remove(st)
        # o dono: todo ramo preenchido; só a bolinha diz se já existe (●) ou está em construção (○)
        pill.fill.solid()
        pill.fill.fore_color.rgb = RGBColor.from_string("FFFFFF")
        pill.line.color.rgb = RGBColor.from_string(BORDA)
        pill.line.width = Pt(1)
        texto(pill, [[("●  " if existe else "○  ", 9.5, True, ORANGE), (txt, 9.5, False, NAVY)]], algn="l", ins=0.1)

# dono (18/11): o organograma inteiro 5% maior (posições a partir do centro, tamanhos e fontes)
K = 1.05
mapa = [sh for sh in s.shapes if sh.shape_id in (9, 10, 11)
        or sh.name.split("-")[0] in ("agente", "badge", "analise", "liga")]
for sh in mapa:
    x, y = sh.left / 914400, sh.top / 914400
    w, h = sh.width / 914400, sh.height / 914400
    sh.left = Inches(CX + (x - CX) * K)
    sh.top = Inches(CY + (y - CY) * K)
    sh.width, sh.height = Inches(w * K), Inches(h * K)
    for rpr in sh._element.iter(f"{{{A}}}rPr"):
        if rpr.get("sz"):
            rpr.set("sz", str(int(round(int(rpr.get("sz")) * K / 5.0) * 5)))
log.append(f"Mapa: pílulas a {LW:.2f}\" e organograma +5% ({len(mapa)} shapes)")

# legenda única (vale para badge do agente e para a pílula da análise)
leg = s.shapes.add_textbox(Inches(7.73), Inches(1.5), Inches(5.0), Inches(0.25))
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
    "O Orquestrador Oria coordena oito agentes de IA; cada ramo é uma análise concreta, e todas estão "
    "no plano de execução. Bolinha cheia: já existe no sistema hoje. Bolinha vazada: em construção. "
    "Do lado esquerdo, a base: o Captador lê 4 formatos e barra duplicata; o Conferidor bate balanço, caixa "
    "e receita e cruza os mútuos do grupo; Mercado e Risco são a próxima fronteira, com juro contra o Banco "
    "Central, despesas contra o setor e processos e bureau. Do lado direito, a decisão: capital de giro e "
    "aging já conciliados, mapa da dívida e capacidade de pagamento em fórmula, três cenários e o Excel do "
    "comitê com 14 abas; liquidez de 13 semanas, waterfall de credores, valuation e propostas com carência, "
    "haircut e new money são o plano. O especialista aprova cada etapa e escolhe a saída que preserva mais valor."
)
for r in nt.runs[1:]:
    r._r.getparent().remove(r._r)
tot = sum(len(a[3]) for a in AGENTES)
ok = sum(e for a in AGENTES for e, _ in a[3])
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
