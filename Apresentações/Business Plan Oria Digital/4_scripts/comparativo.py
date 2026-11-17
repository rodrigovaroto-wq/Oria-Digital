"""Comparativo visual v2 x v3: uma página por slide, lado a lado, com a lista das mudanças.

Uso: python3 -I comparativo.py dir_v2 dir_v3 saida.pdf
(dir_* contêm s-01.jpg … s-14.jpg na mesma resolução)
"""
import sys

from PIL import Image, ImageDraw, ImageFont

D2, D3, OUT = sys.argv[1:4]
FB = ImageFont.truetype("/usr/share/fonts/truetype/crosextra/Carlito-Bold.ttf", 30)
FR = ImageFont.truetype("/usr/share/fonts/truetype/crosextra/Carlito-Regular.ttf", 24)
NAVY, ORANGE, GREY = (22, 38, 59), (240, 70, 0), (112, 112, 112)

MUDANCAS = {
    2: ["Rodapé: 'recuperação (extra) judicial' → 'recuperação judicial e extrajudicial'."],
    8: [
        "Removida caixa de texto solta sobreposta aos cartões ('com um nível de excelência…').",
        "Título paralelo, sem ponto e vírgula: 'Menos custo desnecessário, mais dívida amortizada'.",
        "Gráfico: 'EXEMPLO ILUSTRATIVO' + legenda 'R$ 40 mi por ano + R$ 20 mi uma vez'; barra única em verde.",
        "'Fonte: McKinsey.' substituída pela premissa do exemplo; números não se separam mais da unidade.",
    ],
    9: ["Status dos agentes: 1, 2 e 8 'já em operação' (cheios); 3 a 7 'em construção' (vazados) + legenda."],
    10: [
        "Título-conclusão; 'PARA CHEGAR LÁ' → 'O QUE BUSCAMOS NO SÓCIO'.",
        "Pilares na ordem do dono: Direção estratégica (novo), Time, Infraestrutura segura p/ desenvolvimento (fusão), Banco de dados.",
        "Fecho sem contradição ('o método já funciona na Oria Partners'); notas: 6 a 12 → 3 a 6 meses.",
    ],
}
EXTRA = {
    3: ["Card 1: 'Semanas perdidas' -> 'Meses perdidos' (alinha com os 3 meses dos slides 2 e 4)."],
    5: ["Título: 'Do documento ao diagnóstico, com a prova de cada número' (deixa de repetir o slide 4)."],
    7: ["'Nove análises rodando juntas' -> 'Nove análises integradas'.", "Bloco 'A melhor saída' recolhido para dentro da margem direita (ia até 13,17\")."],
    8: ["Rótulo do gráfico alinhado aos rótulos dos cards; base do exemplo: 'custos operacionais'."],
    9: ["Título: 'Oito agentes de IA cobrem o diagnóstico, e o Especialista Oria decide'."],
    10: ["Rótulos com o mesmo espaçamento entre letras do resto do deck."],
    11: ["Rodapé: 'roteiro' -> 'plano de construção' (termo do slide 9)."],
    12: ["Título sem 'direto'; selos 7 -> 8 pt; cinza do RISCO mais escuro (contraste ~3,1:1 -> ~5,0:1)."],
    13: ["Selos 7 -> 8 pt; cinza do RISCO mais escuro."],
    14: ["Selos 7 -> 8 pt; cinza do RISCO mais escuro."],
}


def page(n):
    a = Image.open(f"{D2}/s-{n:02d}.jpg").convert("RGB")
    b = Image.open(f"{D3}/s-{n:02d}.jpg").convert("RGB")
    w, h = a.size
    notes = MUDANCAS.get(n, []) + EXTRA.get(n, [])
    pad, gap, top = 40, 30, 110
    H = top + h + 40 + max(1, len(notes)) * 36 + 40
    P = Image.new("RGB", (pad * 2 + w * 2 + gap, H), "white")
    d = ImageDraw.Draw(P)
    d.text((pad, 30), f"Slide {n}", fill=NAVY, font=FB)
    status = "ALTERADO" if notes else "PRESERVADO (sem alteração)"
    d.text((pad + 160, 30), status, fill=ORANGE if notes else GREY, font=FB)
    d.text((pad, top - 34), "ORIGINAL v2", fill=GREY, font=FR)
    d.text((pad + w + gap, top - 34), "FINAL v3", fill=ORANGE if notes else GREY, font=FR)
    P.paste(a, (pad, top))
    P.paste(b, (pad + w + gap, top))
    for side in (0, 1):
        x = pad + side * (w + gap)
        d.rectangle([x - 1, top - 1, x + w, top + h], outline=(210, 210, 210))
    y = top + h + 30
    for t in notes or ["Slide classificado como A (preservar): nenhuma mudança justificada."]:
        d.text((pad, y), "• " + t, fill=NAVY if notes else GREY, font=FR)
        y += 36
    return P


if __name__ == "__main__":
    pages = [page(n) for n in range(1, 15)]
    pages[0].save(OUT, save_all=True, append_images=pages[1:], resolution=150)
    print(OUT)
