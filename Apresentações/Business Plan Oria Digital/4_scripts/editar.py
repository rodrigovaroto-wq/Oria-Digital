"""Aplica o plano de intervenção v2 -> v3 do Business Plan Oria Digital.

Edição pontual sobre o arquivo original (python-pptx + XML do gráfico):
nenhum slide é reconstruído, só os shapes listados mudam.
Uso: python3 -I editar.py original.pptx saida.pptx compass.png
"""
import copy
import io
import sys

from lxml import etree
from openpyxl import load_workbook
from pptx import Presentation
from pptx.util import Emu, Inches, Pt

SRC, OUT, COMPASS = sys.argv[1:4]
NBSP = " "
NS = {
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "c": "http://schemas.openxmlformats.org/drawingml/2006/chart",
}
GREEN = "2E5B45"  # verde do cartão "Amortiza dívida" do próprio slide 8

prs = Presentation(SRC)
log = []


def shape(slide, sid):
    for sh in slide.shapes:
        if sh.shape_id == sid:
            return sh
    raise KeyError(sid)


def by_text(slide, needle):
    hits = [sh for sh in slide.shapes if sh.has_text_frame and needle in sh.text_frame.text]
    assert len(hits) == 1, (needle, len(hits))
    return hits[0]


def set_para(sh, text, para=0):
    """Troca o texto mantendo a formatação do primeiro run do parágrafo."""
    p = sh.text_frame.paragraphs[para]
    runs = p.runs
    runs[0].text = text
    for r in runs[1:]:
        r._r.getparent().remove(r._r)


def set_notes(slide, text):
    tf = slide.notes_slide.notes_text_frame
    set_para_tf(tf, text)


def set_para_tf(tf, text):
    p = tf.paragraphs[0]
    p.runs[0].text = text
    for r in p.runs[1:]:
        r._r.getparent().remove(r._r)


# ---------------------------------------------------------------- slide 2
s2 = prs.slides[1]
sh = by_text(s2, "Acontece em:")
runs = sh.text_frame.paragraphs[0].runs
runs[2].text = "recuperação judicial e extrajudicial"
runs[3].text = "  ·  concessão de crédito"
log.append("S2: '(extra) judicial' -> 'judicial e extrajudicial'")

# ---------------------------------------------------------------- slide 8
s8 = prs.slides[7]
set_para(shape(s8, 3), "Menos custo desnecessário, mais dívida amortizada")

# texto solto sobreposto ao slide ("com um nível de excelência...")
stray = shape(s8, 33)
stray._element.getparent().remove(stray._element)
log.append("S8: removida caixa de texto solta sobre os cartões")

# números não se partem da unidade
set_para(shape(s8, 10), f"2{NBSP}p.p. sobre R${NBSP}500{NBSP}mi = R${NBSP}10{NBSP}mi/ano")
set_para(shape(s8, 14), f"15% de R${NBSP}200{NBSP}mi = R${NBSP}30{NBSP}mi/ano")
set_para(shape(s8, 20), f"R${NBSP}20{NBSP}mi recuperados = R${NBSP}20{NBSP}mi a menos de dívida")

# cabeçalho do gráfico: só o rótulo; a separação recorrente x única fica nos próprios valores (pedido do dono)
hdr = shape(s8, 26)
set_para(hdr, "EXEMPLO ILUSTRATIVO")
chart_gf = shape(s8, 27)
chart_gf.top = Inches(2.50)
chart_gf.height = Inches(2.15)

chart = chart_gf.chart
cs = chart._chartSpace
ser = cs.find(".//c:ser", NS)
# série: nome + cor do ponto único (verde) + rótulo por ponto
ser.find("c:tx//c:v", NS).text = "R$ mi"
inv = ser.find("c:invertIfNegative", NS)
dpt = etree.fromstring(
    f'<c:dPt xmlns:c="{NS["c"]}" xmlns:a="{NS["a"]}"><c:idx val="2"/><c:invertIfNegative val="0"/>'
    f'<c:bubble3D val="0"/><c:spPr><a:solidFill><a:srgbClr val="{GREEN}"/></a:solidFill>'
    f"<a:effectLst/></c:spPr></c:dPt>"
)
inv.addnext(dpt)
# rótulos por ponto: "/ ano" nos recorrentes; sem quebra de linha (wrap="none") e com
# largura explícita (c15:layout), senão o rótulo se parte em "R$ 30 mi" + "/ ano" (medido no render)
dlbls = ser.find("c:dLbls", NS)
txpr = copy.deepcopy(dlbls.find("c:txPr", NS))
txpr.find("a:bodyPr", NS).set("wrap", "none")
C15 = "http://schemas.microsoft.com/office/drawing/2012/chart"
for idx, fmt in ((0, '"R$ "0" mi / ano"'), (1, '"R$ "0" mi / ano"'), (2, '"R$ "0" mi"')):
    fmt_xml = fmt.replace('"', "&quot;").replace(" ", NBSP)
    lbl = etree.fromstring(
        f'<c:dLbl xmlns:c="{NS["c"]}" xmlns:a="{NS["a"]}" xmlns:c15="{C15}"><c:idx val="{idx}"/>'
        f'<c:numFmt formatCode="{fmt_xml}" sourceLinked="0"/>'
        f"<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>"
        f"{etree.tostring(txpr).decode()}"
        f'<c:dLblPos val="outEnd"/><c:showLegendKey val="0"/><c:showVal val="1"/><c:showCatName val="0"/>'
        f'<c:showSerName val="0"/><c:showPercent val="0"/><c:showBubbleSize val="0"/>'
        f'<c:extLst><c:ext uri="{{CE6537A1-D6FC-4f65-9D91-7224C49458BB}}"><c15:layout><c:manualLayout>'
        f'<c:w val="0.34"/><c:h val="0.13"/></c:manualLayout></c15:layout></c:ext></c:extLst></c:dLbl>'
    )
    dlbls.insert(idx, lbl)
dlbls.find("c:txPr", NS).find("a:bodyPr", NS).set("wrap", "none")
# a planilha embutida acompanha o cache
wb_part = chart.part.chart_workbook.xlsx_part
wb = load_workbook(io.BytesIO(wb_part.blob))
wb.active["B1"] = "R$ mi"
buf = io.BytesIO()
wb.save(buf)
wb_part._blob = buf.getvalue()
log.append("S8: ponto único em verde; rótulos R$ 10 mi / ano, R$ 30 mi / ano, R$ 20 mi")

src = shape(s8, 31)
set_para(src, f"Exemplo ilustrativo: empresa com R${NBSP}500{NBSP}mi de dívida e R${NBSP}200{NBSP}mi de custos por ano.")
src.left, src.top, src.width = Inches(0.6), Inches(6.55), Inches(12.13)
log.append("S8: 'Fonte: McKinsey.' substituída pela premissa do exemplo")

set_notes(
    s8,
    "Exemplo ilustrativo de uma empresa com R$ 500 milhões de dívida e R$ 200 milhões de custos por ano. "
    "Juro e despesa são ganhos recorrentes: R$ 40 milhões por ano. O crédito tributário é um ganho único: "
    "R$ 20 milhões recuperados que viram R$ 20 milhões a menos de dívida. A lógica é sempre a mesma: comparar "
    "a empresa com o mercado e transformar a diferença em caixa.",
)

# ---------------------------------------------------------------- slide 10
s10 = prs.slides[9]
set_para(shape(s10, 3), "Quatro pilares levam o Oria Digital do método validado ao mercado")
set_para(shape(s10, 207), "O QUE BUSCAMOS NO SÓCIO")

slots = [Inches(x) for x in (0.6, 3.69, 6.79, 9.88)]
groups = {  # cartão: (fundo, círculo, ícone, título, texto)
    "dev": (21, 22, 23, 24, 25),
    "time": (11, 12, 13, 14, 15),
    "dados": (16, 17, 18, 19, 20),
    "seg": (26, 27, 28, 29, 30),
}


def move(key, slot):
    ids = groups[key]
    dx = slots[slot] - shape(s10, ids[0]).left
    for i in ids:
        sh = shape(s10, i)
        sh.left = sh.left + dx


# nova ordem pedida pelo dono: direção, time, infraestrutura segura p/ desenvolvimento, banco de dados
move("dev", 0)
move("time", 1)
move("seg", 2)
move("dados", 3)

# cartão 1 vira "Direção estratégica" (reaproveita o cartão "Infraestrutura de desenvolvimento")
old_icon = shape(s10, 23)
x, y, w, h = old_icon.left, old_icon.top, old_icon.width, old_icon.height
old_icon._element.getparent().remove(old_icon._element)
pad = Inches(0.02)  # o glifo da bússola é mais vazado que os vizinhos; 0,04" a mais iguala o peso visual
pic = s10.shapes.add_picture(COMPASS, x - pad, y - pad, w + 2 * pad, h + 2 * pad)
pic.name = "icimg-direcao"
set_para(shape(s10, 24), "Direção estratégica")
set_para(shape(s10, 25), "Experiência para decidir o que construir primeiro, para quem vender e com quem se associar.")

# cartão 3 funde as duas infraestruturas
set_para(shape(s10, 29), "Infraestrutura segura para desenvolvimento")
set_para(shape(s10, 30), "Testes e IA para os oito agentes, com dados isolados por cliente e trilha de auditoria.")

set_para(shape(s10, 31), "O método já funciona na Oria Partners. Com esses quatro pilares, o Oria Digital ganha escala.")
set_notes(
    s10,
    "Fechamento. Hoje temos o método validado na Oria Partners e o sistema em construção. O próximo marco é o "
    "sistema rodando em mandatos reais da Oria Partners, testado e validado. Em 3 a 6 meses, o primeiro cliente "
    "fora da Oria Partners. Para chegar lá, buscamos no sócio quatro pilares: direção estratégica para definir "
    "prioridades; o time que une engenharia, IA e especialistas em finanças, jurídico e fiscal; a infraestrutura "
    "segura para desenvolver e colocar os oito agentes em operação; e a base de dados que fica mais precisa a cada "
    "mandato. Perguntamos onde a experiência dele ajuda mais.",
)
log.append("S10: pedido explícito ao sócio, 4 pilares na ordem do dono, infraestruturas fundidas, notas 3 a 6 meses")

prs.save(OUT)
print("\n".join(log))
