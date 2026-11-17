"""Rodada 4: decisões do dono depois da rodada 3.

- Slide 8: a redução de despesa do exemplo cai de 15% para 10% (o número mais agressivo do
  deck; o dono aceitou a recomendação). 10% de R$ 200 mi = R$ 20 mi/ano; recorrente total
  passa de R$ 40 mi/ano para R$ 30 mi/ano.
Uso: python3 -I rodada4.py entrada.pptx saida.pptx
"""
import io
import sys

from openpyxl import load_workbook
from pptx import Presentation

NBSP = " "
C = "http://schemas.openxmlformats.org/drawingml/2006/chart"
prs = Presentation(sys.argv[1])
s8 = prs.slides[7]

hits = [s for s in s8.shapes if s.has_text_frame and s.text_frame.text.startswith("15%")]
assert len(hits) == 1
r = hits[0].text_frame.paragraphs[0].runs[0]
r.text = f"10% de R${NBSP}200{NBSP}mi = R${NBSP}20{NBSP}mi/ano"

chart = [s for s in s8.shapes if s.has_chart][0].chart
pts = chart._chartSpace.findall(f".//{{{C}}}val//{{{C}}}pt")
assert pts[1].find(f"{{{C}}}v").text == "30"
pts[1].find(f"{{{C}}}v").text = "20"
part = chart.part.chart_workbook.xlsx_part
wb = load_workbook(io.BytesIO(part.blob))
ws = wb.active
assert ws["B3"].value == 30, ws["B3"].value
ws["B3"] = 20
buf = io.BytesIO()
wb.save(buf)
part._blob = buf.getvalue()

n = s8.notes_slide.notes_text_frame.paragraphs[0].runs[0]
assert "R$ 40 milhões por ano" in n.text
n.text = n.text.replace("R$ 40 milhões por ano", "R$ 30 milhões por ano")

prs.save(sys.argv[2])
print("S8: despesa 15% -> 10% (R$ 20 mi/ano); barra Despesas 30 -> 20; notas 40 -> 30 mi/ano")
