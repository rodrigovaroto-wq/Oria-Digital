"""Fase 3, ajustes de encaixe medidos no render (LibreOffice/Carlito)."""
import re, sys
from pathlib import Path
from xml.sax.saxutils import escape
S = Path(sys.argv[1])/"ppt"/"slides"
def troca(t, old, new):
    a=f"<a:t>{escape(old)}</a:t>"; assert t.count(a)==1,(old,t.count(a)); return t.replace(a,f"<a:t>{escape(new)}</a:t>")
def ed(arq, pares):
    p=S/arq; t=p.read_text(encoding="utf-8")
    for o,n in pares: t=troca(t,o,n)
    p.write_text(t,encoding="utf-8"); return p
ed("slide4.xml",[("pediram recuperação em 2025, recorde","pediram recuperação em 2025"),
                 ("de captação líquida em FIDCs até out/2026","captação líquida até out/2026")])
ed("slide14.xml",[("Duas receitas: o diagnóstico de cada mandato e o acompanhamento contínuo","Duas receitas: o diagnóstico por mandato e o acompanhamento"),
                  ("Pós-reestruturação e carteiras de credores, com relatório e alertas.","Pós-reestruturação e carteiras de credores."),
                  ("recorrente, conforme o contrato","recorrente, por contrato")])
ed("slide9.xml",[("Ambientes de teste isolados, dados protegidos e trilha de auditoria à prova de adulteração.","Ambientes de teste isolados, dados protegidos e trilha de auditoria.")])
p=S/"slide8.xml"; t=p.read_text(encoding="utf-8")
t=t.replace("<a:t>→  </a:t>","<a:t>→ </a:t>")
m=[m for m in re.finditer(r"<p:sp>.*?</p:sp>",t,re.S) if 'name="badge-10"' in m.group(0)][0]
s=m.group(0).replace('sz="1260"','sz="1000"').replace('lIns="45720" rIns="45720"','lIns="0" rIns="0"')
t=t[:m.start()]+s+t[m.end():]
p.write_text(t,encoding="utf-8"); print("ok")
