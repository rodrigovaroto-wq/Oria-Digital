"""Comparativo visual v2 (14 slides) x v3 (13 slides): uma página por slide original.

O slide 7 original foi fundido no slide dos agentes; a página dele mostra o original e aponta
para onde o conteúdo foi.
Uso: python3 -I comparativo.py dir_v2 dir_v3 saida.pdf   (dir_* com s-01.jpg …)
"""
import sys

from PIL import Image, ImageDraw, ImageFont

D2, D3, OUT = sys.argv[1:4]
FB = ImageFont.truetype("/usr/share/fonts/truetype/crosextra/Carlito-Bold.ttf", 30)
FR = ImageFont.truetype("/usr/share/fonts/truetype/crosextra/Carlito-Regular.ttf", 24)
NAVY, ORANGE, GREY = (22, 38, 59), (240, 70, 0), (112, 112, 112)

# (slide original, slide final ou None, mudanças)
PARES = [
    (1, 1, []),
    (2, 2, ["Rodapé: 'recuperação (extra) judicial' -> 'recuperação judicial e extrajudicial'."]),
    (3, 3, ["'Semanas perdidas' -> 'Meses perdidos' (alinha com os 3 meses dos slides 2 e 4).",
            "Cada card ganhou 'COMO RESOLVEMOS' com a dor resolvida (textos do dono): ex. 'Erro achado antes do credor'."]),
    (4, 4, ["R$ 2,7 tri (agosto) -> R$ 2,8 tri 'de saldo em set/2026' (relatório do BC de 29/10/2026); fonte 'Banco Central (out/2026)'."]),
    (5, 5, ["Título: 'Do documento ao diagnóstico, com a prova de cada número' (não repete o slide 4).",
            "Cada etapa ganhou 'RESULTADO' com o que muda para o cliente (textos do dono): ex. 'Até onde o caixa aguenta'."]),
    (6, 6, ["'principais fontes' nos cards Micro e Macro (a lista é um resumo).",
            "Fecho no card 'O que revela': cada achado chega com a fonte que o prova."]),
    (7, None, ["REMOVIDO: as 'nove análises' foram fundidas no slide 8 (mapa mental dos agentes).",
               "Motivo: três descrições do mesmo motor (5 etapas, 9 análises, 8 agentes) sem ponte, e 4 análises listadas como prontas estão em 0%.",
               "A mensagem 'o especialista escolhe a saída que preserva mais valor' foi para a linha de supervisão do slide 8."]),
    (8, 7, ["Removida caixa de texto solta sobreposta aos cards; título paralelo, sem ponto e vírgula.",
            "Exemplo de despesa 15% -> 10% (R$ 20 mi/ano); rótulos 'R$ 10 mi / ano', 'R$ 20 mi / ano', 'R$ 20 mi'; barra única em verde.",
            "'Fonte: McKinsey.' substituída pela premissa do exemplo (custos operacionais)."]),
    (9, 8, ["Mapa mental: Orquestrador -> 8 agentes (1-4 à esquerda, 5-8 à direita) -> 28 análises com fonte no repositório.",
            "Bolinha cheia = já existe (14); vazada = em construção (14), conforme STATUS_POR_ETAPA e o código."]),
    (10, 9, ["Título-conclusão; 'O QUE BUSCAMOS' com os 4 pilares na ordem do dono (Direção estratégica nova; infraestruturas fundidas).",
             "Fecho sem contradição; notas 6 a 12 -> 3 a 6 meses; rótulos com espaçamento do deck."]),
    (11, 10, ["Rodapé: 'roteiro' -> 'plano de construção'."]),
    (12, 11, ["Título sem 'direto'; selos 7 -> 8 pt; cinza do RISCO mais escuro (3,1:1 -> 5,1:1)."]),
    (13, 12, ["Selos 7 -> 8 pt; cinza do RISCO mais escuro."]),
    (14, 13, ["Selos 7 -> 8 pt; cinza do RISCO mais escuro."]),
]


def page(o, f, notes):
    a = Image.open(f"{D2}/s-{o:02d}.jpg").convert("RGB")
    w, h = a.size
    if f:
        b = Image.open(f"{D3}/s-{f:02d}.jpg").convert("RGB")
    else:
        b = Image.new("RGB", (w, h), (238, 243, 238))
        ImageDraw.Draw(b).text((w // 2 - 230, h // 2 - 20), "fundido no slide 8 da versão final", fill=ORANGE, font=FB)
    pad, gap, top = 40, 30, 110
    H = top + h + 40 + max(1, len(notes)) * 36 + 40
    P = Image.new("RGB", (pad * 2 + w * 2 + gap, H), "white")
    d = ImageDraw.Draw(P)
    d.text((pad, 30), f"Original {o}" + (f"  ->  Final {f}" if f else "  ->  removido"), fill=NAVY, font=FB)
    d.text((pad + 420, 30), "ALTERADO" if notes else "PRESERVADO", fill=ORANGE if notes else GREY, font=FB)
    d.text((pad, top - 34), "ORIGINAL v2", fill=GREY, font=FR)
    d.text((pad + w + gap, top - 34), "FINAL v3", fill=ORANGE if notes else GREY, font=FR)
    P.paste(a, (pad, top))
    P.paste(b, (pad + w + gap, top))
    for side in (0, 1):
        x = pad + side * (w + gap)
        d.rectangle([x - 1, top - 1, x + w, top + h], outline=(210, 210, 210))
    y = top + h + 30
    for t in notes or ["Preservado: nenhuma mudança justificada."]:
        d.text((pad, y), "• " + t, fill=NAVY if notes else GREY, font=FR)
        y += 36
    return P


pages = [page(*p) for p in PARES]
pages[0].save(OUT, save_all=True, append_images=pages[1:], resolution=150)
print(OUT, len(pages), "páginas")
