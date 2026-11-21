"""Gera a versão para celular do deck: cada slide vira uma imagem de página inteira, com as notas do apresentador.
Motivo: o visualizador do iPhone (Arquivos/Mail) desenha mal o deck editável. Ele troca a Calibri por uma fonte com
serifa e mostra formas de um slide em outro (slides 6 a 14 da v4), e continuou assim depois dos ids únicos.
Uma imagem por slide sai igual ao computador. Custo: o texto não é editável; a fonte oficial continua sendo o
.pptx editável. Uso: python3 versao_celular.py deck.pptx deck.pdf saida.pptx  (o PDF vem do próprio deck)"""
import glob, os, subprocess, sys, tempfile
from pptx import Presentation
from pptx.util import Emu

deck, pdf, saida = sys.argv[1:4]
orig = Presentation(deck)
with tempfile.TemporaryDirectory() as tmp:
    # 200 dpi: 2667 px de largura, nítido na tela retina do iPhone com zoom de 2x
    subprocess.run(["pdftoppm", "-r", "200", "-png", pdf, os.path.join(tmp, "s")], check=True)
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
