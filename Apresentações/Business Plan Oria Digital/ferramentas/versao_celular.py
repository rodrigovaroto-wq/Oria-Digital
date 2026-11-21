"""Gera a versão para celular do deck: cada slide vira uma imagem de página inteira, com as notas do apresentador.
Motivo: o visualizador do iPhone (Arquivos/Mail) desenha mal o deck editável. Ele troca a Calibri por uma fonte com
serifa e mostra formas de um slide em outro (slides 6 a 14 da v4), e continuou assim depois dos ids únicos.
Uma imagem por slide sai igual ao computador. Custo: o texto não é editável; a fonte oficial continua sendo o
.pptx editável. Uso: python3 versao_celular.py deck.pptx deck.pdf saida.pptx  (o PDF vem do próprio deck)"""
import glob, os, shutil, subprocess, sys, tempfile
from pptx import Presentation
from pptx.util import Emu



def arquivo_de_entrada(caminho, extensoes):
    """Mesmo critério de qa_geometria.py: arquivo existente, dentro da pasta de trabalho, extensão esperada."""
    base = os.path.realpath(os.getcwd())
    real = os.path.realpath(caminho)
    if not real.startswith(base + os.sep):
        sys.exit(f"recusado: {caminho} está fora da pasta de trabalho ({base})")
    if os.path.splitext(real)[1].lower() not in extensoes or not os.path.isfile(real):
        sys.exit(f"recusado: {caminho} não é um arquivo {'/'.join(sorted(extensoes))} existente")
    return real


if len(sys.argv) != 4:
    sys.exit("uso: versao_celular.py deck.pptx deck.pdf saida.pptx")
deck = arquivo_de_entrada(sys.argv[1], {".pptx"})
pdf = arquivo_de_entrada(sys.argv[2], {".pdf"})
saida = sys.argv[3]
orig = Presentation(deck)
with tempfile.TemporaryDirectory() as tmp:
    # o PDF validado vai com NOME FIXO para a pasta temporária: só esse nome chega à linha de comando
    # (SonarCloud S8705 no PR #305, o mesmo achado e a mesma correção do PR #301 em qa_geometria.py)
    copia = os.path.join(tmp, "deck.pdf")
    shutil.copyfile(pdf, copia)
    # 200 dpi: 2667 px de largura, nítido na tela retina do iPhone com zoom de 2x
    subprocess.run(["pdftoppm", "-r", "200", "-png", copia, os.path.join(tmp, "s")], check=True)
    imgs = sorted(glob.glob(os.path.join(tmp, "s-*.png")))
    if len(imgs) != len(orig.slides):
        sys.exit(f"PDF com {len(imgs)} páginas, deck com {len(orig.slides)} slides: o PDF não é deste deck")
    novo = Presentation()
    novo.slide_width, novo.slide_height = orig.slide_width, orig.slide_height
    vazio = novo.slide_layouts[6]
    for img, s in zip(imgs, orig.slides):
        n = novo.slides.add_slide(vazio)
        n.shapes.add_picture(img, Emu(0), Emu(0), novo.slide_width, novo.slide_height)
        if s.has_notes_slide and s.notes_slide.notes_text_frame is not None:
            n.notes_slide.notes_text_frame.text = s.notes_slide.notes_text_frame.text
    novo.save(saida)
print("ok", len(imgs), "slides")
