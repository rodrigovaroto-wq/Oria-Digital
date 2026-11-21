"""Dá a cada forma do deck um id único no arquivo inteiro (slide k -> k*1000+n). O visualizador do iPhone
reaproveitava formas de slides anteriores quando o id se repetia (setas do slide 5 no 6, painel do 8 no 9-14,
elipses do 9 no 10-14). Só muda o atributo id de p:cNvPr; texto, posição e estilo ficam idênticos.
Uso: python3 renumerar_ids.py entrada.pptx saida.pptx"""
import re, sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
zin = zipfile.ZipFile(src)
rels = zin.read("ppt/_rels/presentation.xml.rels").decode()
pres = zin.read("ppt/presentation.xml").decode()
rid2t = dict(re.findall(r'Id="(rId\d+)"[^>]*Target="(slides/slide\d+\.xml)"', rels)) | \
        {a: b for b, a in re.findall(r'Target="(slides/slide\d+\.xml)"[^>]*Id="(rId\d+)"', rels)}
ordem = ["ppt/" + rid2t[r] for r in re.findall(r'<p:sldId [^>]*r:id="(rId\d+)"', pres)]
def renumerar(xml, k):
    """O grupo raiz do slide (primeiro p:cNvPr) fica id=1, como em todo pptx; os demais viram k*1000+n."""
    partes = re.split(r'(<p:cNvPr id=")\d+(")', xml)
    # re.split com 2 grupos devolve [texto, abre, fecha, texto, ...]: cada trio após o primeiro texto é um id
    saida = [partes[0]]
    for i in range(1, len(partes), 3):
        n = i // 3
        saida.append(f"{partes[i]}{1 if n == 0 else k * 1000 + n}{partes[i + 1]}{partes[i + 2]}")
    return "".join(saida)


zout = zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED)
for item in zin.infolist():
    data = zin.read(item.filename)
    if item.filename in ordem:
        x = data.decode()
        if re.search(r'stCxn|endCxn|spTgt|spid=', x):
            sys.exit(f"{item.filename} referencia ids; renumerar quebraria a referência")
        data = renumerar(x, ordem.index(item.filename) + 1).encode()
    zout.writestr(item, data)
zout.close()
print("ok", len(ordem), "slides")
