"""Fase 3: notas do apresentador dos slides 8, 9 e do slide novo (14). Roda sobre un/."""
import re
import shutil
import sys
from pathlib import Path
from xml.sax.saxutils import escape

UN = Path(sys.argv[1])
N = UN / "ppt" / "notesSlides"


def nota(arq, texto):
    p = N / arq
    t = p.read_text(encoding="utf-8")
    # a nota é o primeiro <a:t> longo (o segundo é o número do slide)
    m = re.search(r"<a:t>([^<]{40,})</a:t>", t)
    assert m, arq
    t = t[:m.start()] + f"<a:t>{escape(texto)}</a:t>" + t[m.end():]
    p.write_text(t, encoding="utf-8")


NOTA_IA = ("O Orquestrador Oria coordena onze agentes: oito especialistas, o Auditor Independente, que revisa o trabalho "
           "dos outros sem refazer contas, e o Autoaprimoramento, que propõe melhorias a partir dos erros e só publica com "
           "aprovação humana. Cada ramo é uma análise concreta do plano de execução. O slide não mostra status de propósito. "
           "Para a conversa: a base já funciona como sistema hoje (leitura de documentos, conferência de balanço, caixa e DRE, "
           "mútuos do grupo, mapa da dívida, capital de giro, três cenários e o Excel do comitê com 14 abas). Os agentes "
           "começam no piloto com a Oria Partners: Conferidor, Dívida, Caixa e Mercado, com o Supervisor e o Auditor. Nenhum "
           "número é calculado pela IA: o motor calcula, os agentes interpretam e o especialista aprova cada etapa.")
NOTA_PEDIDO = ("Fechamento. Hoje o método está validado na Oria Partners e o sistema em construção. O próximo marco é o piloto "
               "com a Oria Partners, a primeira cliente, medindo em cada mandato os dias até o diagnóstico, as horas de analista, "
               "o custo de IA e os achados em reais. Depois vêm os primeiros clientes além da Oria Partners. Para chegar lá, "
               "buscamos uma parceria estratégica, com participação, em quatro pilares: direção estratégica e rede para chegar a "
               "consultorias, fundos e bancos; um time com engenharia e um analista financeiro que revisa cada diagnóstico; "
               "infraestrutura segura, começando por um estudo comparativo das plataformas; e o banco de dados que fica mais "
               "preciso a cada mandato.")
NOTA_MODELO = ("Como o Oria Digital ganha dinheiro, sem números ainda: os valores saem do piloto, quando tivermos custo, horas e "
               "prazo medidos. Vendemos um serviço completo, operado pela nossa equipe, com o especialista incluído. A receita de "
               "entrada é por mandato: o diagnóstico 360°. A recorrente é o acompanhamento: empresas depois da reestruturação e "
               "carteiras de credores, com relatório periódico e alertas, na frequência que cada contrato definir. Mais adiante, "
               "bancos e fundos que quiserem operar o sistema pagam por usuário. Bônus por resultado só como complemento pequeno: "
               "o resultado depende também de credor, juiz e especialista.")

nota("notesSlide9.xml", NOTA_IA)
nota("notesSlide10.xml", NOTA_PEDIDO)

# notas novas para o slide 14, copiando a estrutura das notas do slide 4
shutil.copy(N / "notesSlide4.xml", N / "notesSlide15.xml")
rels = (N / "_rels" / "notesSlide4.xml.rels").read_text(encoding="utf-8")
(N / "_rels" / "notesSlide15.xml.rels").write_text(rels.replace("slide4.xml", "slide14.xml"), encoding="utf-8")
nota("notesSlide15.xml", NOTA_MODELO)
srel = UN / "ppt" / "slides" / "_rels" / "slide14.xml.rels"
s = srel.read_text(encoding="utf-8")
s = s.replace("</Relationships>", '<Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" Target="../notesSlides/notesSlide15.xml"/></Relationships>')
srel.write_text(s, encoding="utf-8")
ct = UN / "[Content_Types].xml"
c = ct.read_text(encoding="utf-8")
c = c.replace("</Types>", '<Override PartName="/ppt/notesSlides/notesSlide15.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"/></Types>')
ct.write_text(c, encoding="utf-8")
print("ok")
