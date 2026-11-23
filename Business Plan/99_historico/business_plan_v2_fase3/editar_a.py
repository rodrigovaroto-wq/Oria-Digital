"""Fase 3, edições A: slides 8 (IA), 9 (pedido) e 14 (novo: modelo de negócio). Roda sobre un/ (deck desempacotado)."""
import re
import sys
from pathlib import Path
from xml.sax.saxutils import escape

UN = Path(sys.argv[1])
S = UN / "ppt" / "slides"


def ler(p): return p.read_text(encoding="utf-8")
def gravar(p, t): p.write_text(t, encoding="utf-8")


def troca(t, old, new, n=1):
    a = f"<a:t>{escape(old)}</a:t>"
    assert t.count(a) == n, (old, t.count(a))
    return t.replace(a, f"<a:t>{escape(new)}</a:t>")


def shape(t, nome, idx=0):
    ms = [m for m in re.finditer(r"<p:sp>.*?</p:sp>", t, re.S) if f'name="{nome}"' in m.group(0)]
    return ms[idx]


def troca_runs(t, nome, pares):
    """Dentro da forma `nome`, troca o texto de cada run, na ordem (old -> new)."""
    m = shape(t, nome)
    s = m.group(0)
    for old, new in pares:
        a = f"<a:t>{escape(old)}</a:t>"
        assert a in s, (nome, old)
        s = s.replace(a, f"<a:t>{escape(new)}</a:t>", 1)
    return t[:m.start()] + s + t[m.end():]


# ------------------------------------------------------------------ slide 8 (estratégia de IA)
p = S / "slide8.xml"
t = ler(p)
t = troca(t, "7 · A ESTRATÉGIA DE IA", "8 · A ESTRATÉGIA DE IA")
t = troca(t, "Oito agentes de IA dividem o diagnóstico, e o Especialista Oria decide",
          "Onze agentes de IA dividem o diagnóstico, e o Especialista Oria decide")
# sem status explícito (J4): sai a legenda e os marcadores ●/○ viram a seta usada no resto do deck
m = shape(t, "legenda-status")
t = t[:m.start()] + t[m.end():]
t = t.replace("<a:t>●  </a:t>", "<a:t>→  </a:t>").replace("<a:t>○  </a:t>", "<a:t>→  </a:t>")
assert "●" not in t and "○" not in t
# selos numerados todos iguais (antes: cheio = em operação, vazado = em construção)
vazado = ('<a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:ln w="19050"><a:solidFill><a:srgbClr val="F04600"/></a:solidFill></a:ln>')
cheio = ('<a:solidFill><a:srgbClr val="F04600"/></a:solidFill><a:ln w="25400"><a:solidFill><a:srgbClr val="EEF3EE"/></a:solidFill></a:ln>')
for i in range(1, 9):
    m = shape(t, f"badge-{i}")
    s = m.group(0).replace(vazado, cheio)
    s = re.sub(r'(<a:rPr sz="1260" b="1"><a:solidFill><a:srgbClr val=")F04600', r"\1FFFFFF", s)
    t = t[:m.start()] + s + t[m.end():]

# dois agentes novos do catálogo de 11 (B1): Auditor acima e Autoaprimoramento abaixo do Orquestrador
modelo_ag = shape(t, "agente-7").group(0)
modelo_bd = shape(t, "badge-1").group(0)  # já cheio
CX = 5257800 + 1682496 // 2  # centro do Orquestrador
AW, AH = 1824228, 748893
X = CX - AW // 2
novos = [("Auditor", "1365", 1783080, 2531973, 2962656, "9"),
         ("Autoaprimoramento", "1150", 5000000, 4645152, 5000000, "10")]
blocos = []
nid = 4001
for nome, sz, y, l1, l2, num in novos:
    ag = re.sub(r'id="\d+" name="agente-7"', f'id="{nid}" name="agente-{num}"', modelo_ag)
    ag = re.sub(r'<a:off x="\d+" y="\d+"/>', f'<a:off x="{X}" y="{y}"/>', ag)
    ag = ag.replace("<a:t>Estrategista</a:t>", f"<a:t>{nome}</a:t>").replace('sz="1365" b="1"', f'sz="{sz}" b="1"')
    bd = re.sub(r'id="\d+" name="badge-1"', f'id="{nid+1}" name="badge-{num}"', modelo_bd)
    bd = re.sub(r'<a:off x="\d+" y="\d+"/>', f'<a:off x="{X}" y="{y-96012}"/>', bd)
    bd = bd.replace("<a:t>1</a:t>", f"<a:t>{num}</a:t>")
    lig = (f'<p:cxnSp><p:nvCxnSpPr><p:cNvPr id="{nid+2}" name="liga-agente-{num}"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>'
           f'<p:spPr><a:xfrm><a:off x="{CX}" y="{l1}"/><a:ext cx="0" cy="{l2-l1}"/></a:xfrm>'
           '<a:prstGeom prst="straightConnector1"><a:avLst/></a:prstGeom><a:ln w="22225"><a:solidFill><a:srgbClr val="B7C4BA"/></a:solidFill></a:ln></p:spPr></p:cxnSp>')
    blocos.append(lig + ag + bd)
    nid += 3
i = t.index("</p:spTree>")
t = t[:i] + "".join(blocos) + t[i:]
gravar(p, t)

# ------------------------------------------------------------------ slide 9 (para levar adiante)
p = S / "slide9.xml"
t = ler(p)
t = troca(t, "8 · PARA LEVAR ADIANTE", "9 · PARA LEVAR ADIANTE")
t = troca(t, "Sistema rodando em mandatos reais da Oria Partners, testado e validado.",
          "Piloto com a Oria Partners, primeira cliente, medindo dias, horas e achados.")
t = troca_runs(t, "TextBox 203", [("EM ", "DEPOIS"), ("3", ""), (" A ", ""), ("6", ""), (" MESES", ""),
                                  ("Primeiro ", "Primeiros clientes além da Oria Partners e início da expansão."),
                                  ("cliente", ""), (" fora da Oria Partners e ", ""), ("início", ""), (" da ", ""),
                                  ("expansão", ""), (".", "")])
t = troca(t, "Engenharia e IA lado a lado com especialistas em finanças, jurídico e fiscal.",
          "Engenharia, IA e um analista financeiro que revisa cada diagnóstico.")
t = troca(t, "Experiência para decidir o que construir primeiro, para quem vender e com quem se associar.",
          "Experiência e rede para decidir o que construir e chegar a consultorias, fundos e bancos.")
t = troca(t, "Testes e IA para os 14 ramos em construção, com dados isolados e trilha de auditoria.",
          "Ambientes de teste isolados, dados protegidos e trilha de auditoria à prova de adulteração.")
t = troca(t, "O método já funciona na Oria Partners. Com esses quatro pilares, o Oria Digital ganha escala.",
          "O método já funciona na Oria Partners. Em parceria estratégica, com participação, o Oria Digital ganha escala.")
gravar(p, t)

# ------------------------------------------------------------------ slide 14 (novo: modelo de negócio, sem valores — J1/J2)
p = S / "slide14.xml"
t = ler(p)
t = troca(t, "3 · O NEGÓCIO E PARA QUEM", "7 · O MODELO DE NEGÓCIO")
t = troca(t, "Do caos de documentos à decisão em poucos dias",
          "Duas receitas: o diagnóstico de cada mandato e o acompanhamento contínuo")
t = troca(t, "O QUE RESOLVEMOS", "O QUE VENDEMOS")
t = troca(t, "Em vez de queimar 3 meses de caixa até saber o que cortar e renegociar, a empresa sabe em poucos dias: ganha tempo, preserva caixa e chega aos credores com credibilidade.",
          "Um serviço completo: a equipe Oria Digital opera a plataforma e entrega o diagnóstico, com o especialista incluído. O cliente acompanha tudo pelo portal.")
t = troca(t, "O DIFERENCIAL", "PARA QUEM")
t = troca_runs(t, "t47", [("Encontra", "Os dois lados da mesa: a empresa que precisa se reestruturar e seus assessores, e os credores, compradores e fundos que precisam confiar nos números."),
                          (" o ", ""), ("detalhe", ""), (" que a análise manual não vê: cada linha da empresa contra o mercado e com a prova de cada número.", "")])
cards = [
    ("Consultorias de reestruturação", "Diagnóstico por mandato", "Renegociam dívidas de empresas em crise.", "Visão 360°, modelo, dossiê e apresentação aos credores.", ("2.466", " empresas"), ("Por mandato", ""), "em recuperação em 2025", "receita de entrada"),
    ("Assessores de M&A", "Acompanhamento contínuo", "Intermediam compra e venda de empresas.", "Pós-reestruturação e carteiras de credores, com relatório e alertas.", ("1.581", " transações"), ("Mensal", ""), "de M&A em 2025", "recorrente, conforme o contrato"),
    ("Bancos e credores", "Plataforma por usuário", "Emprestam dinheiro para empresas.", "Para bancos e fundos que quiserem operar o sistema.", ("R$ 2,8 tri",), ("Por usuário",), "de crédito PJ em set/2026", "mais adiante"),
    ("Fundos de crédito", "Bônus por resultado", "Compram dívidas de empresas.", "Pequeno e opcional, atrelado ao plano aprovado.", ("R$ 56 bi",), ("Opcional",), "captados por FIDCs em 2026", "nunca a base da receita"),
]
for t1, n1, d1, n2, num_old, num_new, s1, s2 in cards:
    t = troca(t, t1, n1)
    t = troca(t, d1, n2)
    for o, n in zip(num_old, num_new):
        t = troca(t, o, n)
    t = troca(t, s1, s2)
for nome in ("t52", "t58", "t64", "t70"):  # só os destaques dos cartões (o título também é 28 pt)
    m = shape(t, nome)
    t = t[:m.start()] + m.group(0).replace('sz="2800"', 'sz="2400"') + t[m.end():]
t = troca(t, "Serasa Experian (abr/2026); KPMG 4T25; Banco Central (out/2026); Anbima (out/2026).",
          "Valores definidos depois do piloto com a Oria Partners, com custo de IA, horas de analista e prazo medidos em cada mandato.")
gravar(p, t)
print("ok")
