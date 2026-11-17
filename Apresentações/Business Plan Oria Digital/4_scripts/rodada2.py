"""Rodada 2: achados confirmados dos revisores independentes (visual + narrativa/precisão).

Cada item aqui foi conferido no arquivo antes de entrar (medida entre parênteses).
Uso: python3 -I rodada2.py entrada.pptx saida.pptx
"""
import sys

from pptx import Presentation
from pptx.util import Inches, Pt

A = "http://schemas.openxmlformats.org/drawingml/2006/main"
prs = Presentation(sys.argv[1])
log = []


def find(slide, needle, exact=False):
    hits = [
        sh for sh in slide.shapes
        if sh.has_text_frame and ((sh.text_frame.text == needle) if exact else (needle in sh.text_frame.text))
    ]
    assert hits, needle
    return hits


def replace_in_runs(sh, old, new):
    for p in sh.text_frame.paragraphs:
        for r in p.runs:
            if old in r.text:
                r.text = r.text.replace(old, new)
                return
    raise KeyError(old)


def set_first(sh, text):
    p = sh.text_frame.paragraphs[0]
    p.runs[0].text = text
    for r in p.runs[1:]:
        r._r.getparent().remove(r._r)


S = lambda n: prs.slides[n - 1]  # noqa: E731

# --- conteúdo (auditoria de narrativa; nenhum dado novo) ---------------------------
replace_in_runs(find(S(3), "Semanas perdidas")[0], "Semanas perdidas", "Meses perdidos")
log.append("S3: 'Semanas perdidas' -> 'Meses perdidos' (alinha com os 3 meses dos slides 2 e 4)")

set_first(find(S(5), "Do documento ao diagnóstico completo")[0], "Do documento ao diagnóstico, com a prova de cada número")
log.append("S5: título diferenciado do S4 e ancorado no diferencial")

replace_in_runs(find(S(7), "Nove análises rodando juntas")[0], "Nove análises rodando juntas", "Nove análises integradas")
log.append("S7: 'rodando juntas' -> 'integradas' (5 dos 8 agentes estão em construção, S9)")

set_first(find(S(9), "Agentes de IA percorrem")[0], "Oito agentes de IA cobrem o diagnóstico, e o Especialista Oria decide")
log.append("S9: título com a contagem e sem ponto final")

replace_in_runs(find(S(11), "está no roteiro")[0], "está no roteiro", "está no plano de construção")
log.append("S11: 'roteiro' -> 'plano de construção' (termo do S9)")

replace_in_runs(find(S(12), "5 com efeito direto no EBITDA")[0], "direto ", "")
log.append("S12: título sem 'direto' (a legenda não define efeito direto; padrão dos S13/S14)")

src8 = find(S(8), "Exemplo ilustrativo: empresa")[0]
replace_in_runs(src8, "de custos por ano", "de custos operacionais por ano")
notes8 = S(8).notes_slide.notes_text_frame.paragraphs[0].runs[0]
notes8.text = notes8.text.replace("R$ 200 milhões de custos por ano", "R$ 200 milhões de custos operacionais por ano")
log.append("S8: base de custos explicitada como operacional (o card lista energia, frete, aluguel, folha; evita dupla contagem com o juro)")

# --- grade e acabamento (crítica visual, conferida na geometria) ---------------------
# S7: bloco da direita ia até 13,17" (margem 12,73"); espelha o da esquerda (0,60–4,30")
for sh in find(S(7), "A melhor saída", exact=True) + find(S(7), "Com as nove análises"):
    sh.left, sh.width = Inches(9.03), Inches(3.70)
log.append("S7: bloco 'A melhor saída' recolhido para dentro da margem, espelhando o bloco da esquerda")

# S8: rótulo do gráfico na mesma linha de 'REDUZ CUSTO' / 'AMORTIZA DÍVIDA' (2,20")
hdr = find(S(8), "EXEMPLO ILUSTRATIVO", exact=True)[0]
hdr.top = Inches(2.20)
chart = [sh for sh in S(8).shapes if sh.has_chart][0]
chart.top, chart.height = Inches(2.55), Inches(2.10)
log.append("S8: rótulo do gráfico alinhado aos rótulos dos cards (2,15\" -> 2,20\")")

# S9: símbolos da legenda legíveis ao lado dos badges
leg = [sh for sh in S(9).shapes if sh.name == "legenda-status"][0]
for r in leg.text_frame.paragraphs[0].runs:
    if r.text.strip() in ("●", "○"):
        r.font.size = Pt(15)
log.append("S9: símbolos da legenda 11 -> 15 pt")

# S10: rótulos com o mesmo espaçamento entre letras do resto do deck (spc=300)
for needle in ("HOJE", "PRÓXIMO MARCO", "EM 3 A 6 MESES", "O QUE BUSCAMOS NO SÓCIO"):
    sh = find(S(10), needle)[0]
    p = sh.text_frame.paragraphs[0]
    for r in p.runs:
        r._r.get_or_add_rPr().set("spc", "300")
log.append("S10: rótulos com espaçamento spc=300, como os demais rótulos do deck")

# S12-14: selos de 7 -> 8 pt; cinza do RISCO 8A9590 -> 66716C (branco sobre ele: ~3,1:1 -> ~5,0:1)
OLD, NEW = "8A9590", "66716C"
for n in (12, 13, 14):
    n_sz = n_cor = 0
    for sh in S(n).shapes:
        el = sh._element
        if sh.has_text_frame and sh.text_frame.text in ("EBITDA", "DÍVIDA", "CAIXA", "RISCO"):
            for r in sh.text_frame.paragraphs[0].runs:
                r.font.size = Pt(8)
                n_sz += 1
        for c in el.iter("{%s}srgbClr" % A):
            if c.get("val") == OLD:
                c.set("val", NEW)
                n_cor += 1
    log.append(f"S{n}: {n_sz} selos 7 -> 8 pt; {n_cor} ocorrências do cinza RISCO escurecidas")

prs.save(sys.argv[2])
print("\n".join(log))
