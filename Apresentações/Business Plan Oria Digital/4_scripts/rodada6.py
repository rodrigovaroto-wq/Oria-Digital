"""Rodada 6: achados da revisão independente final, aprovados pelo dono (4 grupos).

1. Correções objetivas: 360º (ordinal) -> 360° (grau); "mi/ano" -> "mi / ano" como no gráfico;
   "Resultado diferente do da Receita" (truncado); espaço sobrando em "redução de custos ".
2. Coerência com o slide 8: slides 6 e 8 deixam de afirmar no presente o que o slide 8 marca
   como em construção; a metade vazada do slide 8 vira o motivo do pedido (notas e pilar 3).
3. Clareza: o KPI do BC diz saldo de quê; a legenda explica o badge do agente.
4. Acabamento: pilares do slide 9 em pilha a partir do ícone; gráfico do slide 7 sem vazio em cima.
Uso: python3 -I rodada6.py entrada.pptx saida.pptx
"""
import sys

from pptx import Presentation
from pptx.util import Inches

A = "http://schemas.openxmlformats.org/drawingml/2006/main"
C = "http://schemas.openxmlformats.org/drawingml/2006/chart"
NBSP = " "
prs = Presentation(sys.argv[1])
S = lambda n: prs.slides[n - 1]  # noqa: E731
log = []


def by_id(n, sid):
    return [s for s in S(n).shapes if s.shape_id == sid][0]


def rep_run(sh, old, new):
    for p in sh.text_frame.paragraphs:
        for r in p.runs:
            if old in r.text:
                r.text = r.text.replace(old, new)
                return
    raise KeyError((sh.name, old))


def title(n):
    return [p for p in S(n).placeholders if p.placeholder_format.idx == 103][0].text_frame.paragraphs[0].runs


def set_title(n, text):
    runs = title(n)
    runs[0].text = text
    for r in runs[1:]:
        r._r.getparent().remove(r._r)


# ---- 1. correções objetivas
rep_run(by_id(1, 5), "360º", "360°")
for sid in (10, 14):
    rep_run(by_id(7, sid), f"mi/ano", f"mi{NBSP}/{NBSP}ano")
rep_run(by_id(7, 30), "de custos ", "de custos")
rep_run(by_id(6, 53), "Resultado diferente do da Receita", "Resultado diferente do declarado à Receita")
log.append("Objetivas: 360°, 'mi / ano' nos cards do S7, item do S6 completo, espaço sobrando no S7")

# ---- 2. coerência com o slide 8
set_title(6, "Dados da empresa e do mercado, cruzados em uma base única")
set_title(8, "Oito agentes de IA dividem o diagnóstico, e o Especialista Oria decide")
n8 = S(8).notes_slide.notes_text_frame.paragraphs[0].runs[0]
n8.text = n8.text.replace(
    "Bolinha vazada: em construção. ",
    "Bolinha vazada: em construção. Metade das 28 análises já existe hoje; a outra metade é o que construímos com o sócio. ",
)
assert "Metade das 28" in n8.text
rep_run(by_id(9, 30), "Testes e IA para os oito agentes, com dados isolados por cliente e trilha de auditoria.",
        "Testes e IA para os 14 ramos em construção, com dados isolados e trilha de auditoria.")
log.append("Coerência: títulos do S6 e S8 sem prometer o que está em construção; pedido ligado aos 14 ramos")

# ---- 3. clareza
rep_run(by_id(4, 28), "de saldo em set/2026", "de crédito PJ em set/2026")
leg = [s for s in S(8).shapes if s.name == "legenda-status"][0]
runs = leg.text_frame.paragraphs[0].runs
runs[0].text = ""
runs[2].text = "  agente em operação · análise pronta     "
log.append("Clareza: KPI do BC 'de crédito PJ'; legenda explica o badge do agente")

# ---- 4. acabamento
# S9: título e texto empilhados a partir do ícone (o título de 2 linhas empurra só o próprio texto)
for t_id, d_id, linhas in ((24, 25, 1), (14, 15, 1), (29, 30, 2), (19, 20, 1)):
    t, d = by_id(9, t_id), by_id(9, d_id)
    bp = t.text_frame._txBody.find(f"{{{A}}}bodyPr")
    bp.set("anchor", "t")
    t.top = Inches(4.62)
    t.height = Inches(0.3 * linhas)
    d.top = Inches(4.62 + 0.3 * linhas + 0.1)
# S7: o eixo ia até ~25 com barras de no máximo 20; teto de 23 dá altura às barras e ainda cabe o rótulo
ch = [s for s in S(7).shapes if s.has_chart][0].chart
va = ch.value_axis
va.maximum_scale = 23
va.minimum_scale = 0
log.append("Acabamento: pilares do S9 empilhados a partir do ícone; gráfico do S7 com escala 0-23")

# ---- 5. pedidos do dono em 18/11
lbl = [x for x in S(9).shapes if x.has_text_frame and x.text_frame.text == "O QUE BUSCAMOS NO SÓCIO"][0]
rep_run(lbl, "O QUE BUSCAMOS NO SÓCIO", "O QUE BUSCAMOS")
log.append("S9: 'O QUE BUSCAMOS NO SÓCIO' -> 'O QUE BUSCAMOS'")

prs.save(sys.argv[2])
print("\n".join(log))
