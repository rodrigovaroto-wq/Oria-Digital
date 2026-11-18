"""QA automático de geometria: limites, sobreposições, fonte mínima e colisão de palavras renderizadas.

Uso (a partir da pasta do deck): python3 -I ferramentas/qa_geometria.py deck.pptx deck.pdf
Os dois arquivos precisam estar dentro da pasta de trabalho.
- limites: shape fora do slide (tolerância 0,01")
- sobreposição: dois shapes COM TEXTO cujas caixas se cruzam (contêiner sem texto é ignorado)
- fonte: runs abaixo de 9 pt
- colisão: duas palavras do PDF renderizado com caixas sobrepostas (texto sobre texto)
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from itertools import combinations

from pptx import Presentation

EMU = 914400

def arquivo_de_entrada(caminho, extensoes):
    """Aceita só um arquivo que existe, dentro da pasta de trabalho, com extensão esperada.

    Devolve o caminho absoluto (nunca começa com "-", então não vira opção do programa externo).
    SonarCloud S8705/S8707 (PR #301): o argumento ia direto ao subprocess sem validação.
    """
    base = os.path.realpath(os.getcwd())
    real = os.path.realpath(caminho)
    if not real.startswith(base + os.sep):
        sys.exit(f"recusado: {caminho} está fora da pasta de trabalho ({base})")
    if os.path.splitext(real)[1].lower() not in extensoes or not os.path.isfile(real):
        sys.exit(f"recusado: {caminho} não é um arquivo {'/'.join(sorted(extensoes))} existente")
    return real


if len(sys.argv) != 3:
    sys.exit("uso: qa_geometria.py deck.pptx deck.pdf")
deck = arquivo_de_entrada(sys.argv[1], {".pptx"})
pdf = arquivo_de_entrada(sys.argv[2], {".pdf"})
prs = Presentation(deck)
W, H = prs.slide_width / EMU, prs.slide_height / EMU
out = []


def box(sh):
    return (sh.left / EMU, sh.top / EMU, (sh.left + sh.width) / EMU, (sh.top + sh.height) / EMU)


def inter(a, b):
    w = min(a[2], b[2]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[1], b[1])
    return w * h if w > 0.02 and h > 0.02 else 0


for n, s in enumerate(prs.slides, 1):
    texty = []
    for sh in s.shapes:
        if sh.left is None:
            continue
        b = box(sh)
        if b[0] < -0.01 or b[1] < -0.01 or b[2] > W + 0.01 or b[3] > H + 0.01:
            out.append(f"S{n:02d} LIMITE  {sh.name} {tuple(round(v, 2) for v in b)}")
        if sh.has_text_frame and sh.text_frame.text.strip():
            texty.append((sh, b))
            for p in sh.text_frame.paragraphs:
                for r in p.runs:
                    if r.font.size and r.font.size.pt < 9 and r.text.strip():
                        out.append(f"S{n:02d} FONTE   {r.font.size.pt}pt '{r.text[:30]}'")
    for (s1, b1), (s2, b2) in combinations(texty, 2):
        a = inter(b1, b2)
        if a:
            out.append(f"S{n:02d} SOBREP  '{s1.text_frame.text[:22]}' x '{s2.text_frame.text[:22]}' ({a:.2f} pol²)")

# colisão de palavras no PDF renderizado
# o PDF validado é copiado com NOME FIXO para uma pasta temporária: só esse nome chega à linha de
# comando do pdftotext (SonarCloud S8705 no PR #301: a validação de caminho sozinha não bastou)
with tempfile.TemporaryDirectory() as _tmp:
    copia = os.path.join(_tmp, "deck.pdf")
    shutil.copyfile(pdf, copia)
    html = subprocess.run(["pdftotext", "-bbox", copia, "-"], capture_output=True, text=True).stdout
for n, page in enumerate(html.split("<page ")[1:], 1):
    words = [
        (float(a), float(b), float(c), float(d), t)
        for a, b, c, d, t in re.findall(
            r'xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)<', page
        )
    ]
    for w1, w2 in combinations(words, 2):
        dx = min(w1[2], w2[2]) - max(w1[0], w2[0])
        dy = min(w1[3], w2[3]) - max(w1[1], w2[1])
        if dx > 1.5 and dy > 2.5:  # pontos; tolera kerning e entrelinha justa
            out.append(f"S{n:02d} COLISÃO '{w1[4]}' x '{w2[4]}'")

print("\n".join(out) if out else "nenhum achado")
print(f"-- {len(out)} achados", file=sys.stderr)
