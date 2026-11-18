"""Comparativo visual entre duas versões de um deck: uma página por slide, lado a lado.

Serve para qualquer par de versões futuras (ex.: a final de hoje x uma revisão). Cada página
diz se o slide ficou IGUAL ou foi ALTERADO pela contagem de pixels diferentes no render, e não por
declaração de quem editou.

Uso:
    python3 comparativo.py antes.pptx depois.pptx saida.pdf [--rotulos "Antes" "Depois"]
Aceita .pptx ou .pdf nas duas entradas, que precisam estar dentro da pasta de trabalho. Para
.pptx, converte com o LibreOffice (`soffice` ou `libreoffice` no PATH). Precisa de `pdftoppm`
(Poppler) e de Pillow.
Os slides são pareados pela posição. Se uma versão tiver mais slides, a outra mostra uma
página vazia com o aviso "sem slide correspondente".
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

NAVY, ORANGE, GREY = (22, 38, 59), (240, 70, 0), (112, 112, 112)
# Pixels diferentes acima dos quais o slide conta como ALTERADO. Medido em 18/11/2026: trocar
# "R$ 56 bi" por "R$ 99 bi" muda 519 pixels (0,056% do slide, a 96 dpi); dois renders do mesmo
# deck diferem em 0. Um limiar em fração (0,2%) deixava essa troca passar como IGUAL.
LIMIAR_PIXELS = 20


def fonte(tamanho, negrito=False):
    for nome in (("Carlito-Bold.ttf" if negrito else "Carlito-Regular.ttf"),
                 ("DejaVuSans-Bold.ttf" if negrito else "DejaVuSans.ttf")):
        for raiz in ("/usr/share/fonts", "/usr/local/share/fonts"):
            for p in Path(raiz).rglob(nome):
                return ImageFont.truetype(str(p), tamanho)
    return ImageFont.load_default()


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


def para_pdf(caminho: str, tmp: Path, nome: str) -> Path:
    real = arquivo_de_entrada(caminho, {".pptx", ".pdf"})
    if real.lower().endswith(".pdf"):
        return Path(real)
    soffice = shutil.which("soffice") or shutil.which("libreoffice")
    if not soffice:
        sys.exit("LibreOffice não encontrado no PATH (soffice/libreoffice)")
    out = tmp / nome
    out.mkdir(exist_ok=True)
    subprocess.run([soffice, "--headless", "--convert-to", "pdf", "--outdir", str(out), real],
                   check=True, capture_output=True)
    pdf = out / (Path(real).stem + ".pdf")
    if not pdf.exists():
        sys.exit(f"conversão falhou: {caminho}")
    return pdf


def paginas(pdf: Path, tmp: Path, prefixo: str):
    subprocess.run(["pdftoppm", "-jpeg", "-r", "96", str(pdf), str(tmp / prefixo)], check=True)
    return [Image.open(p).convert("RGB") for p in sorted(tmp.glob(f"{prefixo}-*.jpg"))]


def diferenca(a, b):
    """Número de pixels diferentes; None quando falta um dos lados ou o tamanho muda."""
    if a is None or b is None or a.size != b.size:
        return None
    d = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 24 else 0)
    return d.histogram()[255]


def pagina(n, a, b, rotulos):
    ref = a or b
    w, h = ref.size
    vazio = Image.new("RGB", (w, h), (238, 243, 238))
    ImageDraw.Draw(vazio).text((w // 2 - 160, h // 2 - 15), "sem slide correspondente", fill=ORANGE, font=fonte(26, True))
    a, b = a or vazio, b or vazio
    px = diferenca(a if a is not vazio else None, b if b is not vazio else None)
    alterado = px is None or px > LIMIAR_PIXELS
    pad, gap, top = 40, 30, 110
    P = Image.new("RGB", (pad * 2 + w * 2 + gap, top + h + 60), "white")
    d = ImageDraw.Draw(P)
    d.text((pad, 30), f"Slide {n}", fill=NAVY, font=fonte(30, True))
    d.text((pad + 170, 30), "ALTERADO" if alterado else "IGUAL", fill=ORANGE if alterado else GREY, font=fonte(30, True))
    if alterado and px is not None:
        d.text((pad + 360, 36), f"{px} pixels diferentes", fill=GREY, font=fonte(22))
    d.text((pad, top - 34), rotulos[0], fill=GREY, font=fonte(24))
    d.text((pad + w + gap, top - 34), rotulos[1], fill=ORANGE if alterado else GREY, font=fonte(24))
    P.paste(a, (pad, top))
    P.paste(b, (pad + w + gap, top))
    for x in (pad, pad + w + gap):
        d.rectangle([x - 1, top - 1, x + w, top + h], outline=(210, 210, 210))
    return P, alterado


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("antes")
    ap.add_argument("depois")
    ap.add_argument("saida")
    ap.add_argument("--rotulos", nargs=2, default=["ANTES", "DEPOIS"])
    a = ap.parse_args()
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        pa = paginas(para_pdf(a.antes, tmp, "a"), tmp, "a")
        pb = paginas(para_pdf(a.depois, tmp, "b"), tmp, "b")
        total = max(len(pa), len(pb))
        res = [pagina(i + 1, pa[i] if i < len(pa) else None, pb[i] if i < len(pb) else None, a.rotulos)
               for i in range(total)]
        res[0][0].save(a.saida, save_all=True, append_images=[p for p, _ in res[1:]], resolution=150)
        alterados = [i + 1 for i, (_, alt) in enumerate(res) if alt]
        print(f"{a.saida}: {total} páginas; alterados: {alterados or 'nenhum'}")


if __name__ == "__main__":
    main()
