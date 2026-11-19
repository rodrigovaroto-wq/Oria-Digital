"""Fase 3, edições B (J3): números dos slides 2 e 4 reconferidos na fonte primária em 19/11/2026."""
import re, sys
from pathlib import Path
from xml.sax.saxutils import escape
UN = Path(sys.argv[1]); S = UN/"ppt"/"slides"; N = UN/"ppt"/"notesSlides"
def troca(t, old, new):
    a=f"<a:t>{escape(old)}</a:t>"; assert t.count(a)==1,(old,t.count(a)); return t.replace(a,f"<a:t>{escape(new)}</a:t>")
# slide 2: OBRE R$ 18,9 bi não confirmado na fonte primária -> inadimplência recorde (Serasa, confirmada)
p=S/"slide2.xml"; t=p.read_text(encoding="utf-8")
t=troca(t,"R$ 18,9 bi","9,3 mi")
t=troca(t,"em dívidas renegociadas só nas recuperações extrajudiciais de 2025.","de empresas inadimplentes, com R$ 244,4 bi em dívidas: recorde (ago/2026).")
t=troca(t,"Fonte: OBRE (out/2026)","Fonte: Serasa Experian (out/2026)")
p.write_text(t,encoding="utf-8")
# slide 4: recortes corretos
p=S/"slide4.xml"; t=p.read_text(encoding="utf-8")
t=troca(t,"em recuperação em 2025","pediram recuperação em 2025, recorde")
t=troca(t,"captados por FIDCs em 2026","de captação líquida em FIDCs até out/2026")
t=troca(t,"Serasa Experian (abr/2026); KPMG 4T25; Banco Central (out/2026); Anbima (out/2026).",
 "Serasa Experian (abr/2026); KPMG (2025); Banco Central (out/2026); Anbima (nov/2026). Recuperação judicial no 1º sem/2026: 435 pedidos, contra 509 no 1º sem/2025 (Serasa Experian).")
p.write_text(t,encoding="utf-8")
def nota(arq, texto):
    p=N/arq; t=p.read_text(encoding="utf-8"); m=re.search(r"<a:t>([^<]{40,})</a:t>",t); assert m
    p.write_text(t[:m.start()]+f"<a:t>{escape(texto)}</a:t>"+t[m.end():],encoding="utf-8")
nota("notesSlide2.xml","Vender uma empresa, renegociar a dívida de um grupo em crise, conceder um crédito: tudo depende dos números da empresa. Eles chegam bagunçados, muitas vezes imprecisos, e são montados à mão. E o momento pesa: 9,3 milhões de empresas estão inadimplentes, recorde, com R$ 244,4 bi em dívidas (Serasa, ago/2026), com juro de 24,4% ao ano no crédito livre a empresas e Selic em 13,75%.")
nota("notesSlide4.xml","O que vendemos e o que nos diferencia. Os quatro clientes fazem o mesmo trabalho todos os dias; os números mostram o tamanho de cada demanda e não se somam. 2025 foi recorde de pedidos de recuperação judicial; no 1º semestre de 2026 os pedidos caíram cerca de 15%, mas seguem em patamar alto, e a inadimplência de empresas é recorde, o que puxa a demanda de credores por acompanhamento.")
print("ok")
