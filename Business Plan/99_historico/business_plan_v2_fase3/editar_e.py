"""Fase 3, edições E: notas do slide 8 (modelo de negócio) alinhadas ao texto novo."""
import sys
from pptx import Presentation
prs = Presentation(sys.argv[1])
tf = prs.slides[7].notes_slide.notes_text_frame
tf.text = ("Como o Oria Digital ganha dinheiro, sem números ainda: os valores saem do piloto, quando tivermos custo, horas e "
           "prazo medidos. Vendemos o diagnóstico 360° e o acompanhamento contínuo, operados pela nossa equipe, com a prova "
           "de cada número. A receita de entrada é o diagnóstico de cada mandato. A recorrente é o acompanhamento mensal de "
           "empresas depois da reestruturação e de carteiras de credores, na frequência que cada contrato definir. A licença "
           "de uso dá a empresas, credores e fundos acesso para acompanhar seus mandatos e carteiras. O bônus por resultado é "
           "variável, mediante contrato e atrelado ao plano aprovado: complementa a receita, porque o resultado também "
           "depende de credor, juiz e especialista.")
prs.save(sys.argv[2]); print("ok")
