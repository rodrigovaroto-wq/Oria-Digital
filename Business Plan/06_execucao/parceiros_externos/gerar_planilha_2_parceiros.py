"""Gera a Planilha 2 — plataformas e parceiros por etapa do Oria Digital (versão 2).

Uso:  python3 -I gerar_planilha_2_parceiros.py <saida.xlsx>

Versão 2 (24/11/2026), pedida pelo dono: linguagem simples para quem não está no projeto, visual
limpo, as plataformas-ponte (que compõem o Oria Digital enquanto ele é construído) e a aba com a
combinação proposta e o que falta construir.

Entradas (não editar a planilha à mão; regere):
- pesquisa/ponte.json ............ as plataformas-ponte, com compatibilidade e utilidade
- pesquisa/res_*.json ............ 1ª rodada: fornecedores de dados por API (integração definitiva)
- combinacao.py .................. a combinação proposta, a cobertura por etapa e as perguntas

As duas métricas (definição do dono, 24/11/2026), sobre as ferramentas DA PLATAFORMA:
- Compatibilidade = ferramentas da plataforma ligadas ao tema da Oria ÷ total de ferramentas dela
- Utilidade       = ferramentas que a Oria usaria de fato ÷ total de ferramentas dela
"""
import json
import sys
from pathlib import Path

import openpyxl
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

AQUI = Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))  # python -I não põe a pasta do script no path
from combinacao import COBERTURA, COMBINACAO, ETAPAS, PERGUNTAS_FIXAS  # noqa: E402

FONTE = "Arial"
TINTA = "1F2937"        # texto principal
SUAVE = "6B7280"        # texto secundário
AZUL = "1F3A5F"         # títulos
CAB = "E8EEF5"          # fundo do cabeçalho
LINHA = Side(style="thin", color="E5E7EB")
SEP = Border(bottom=LINHA)
# Cor só onde carrega significado: a recomendação e a cobertura
COR = {
    "Usar agora": "D1FAE5", "Já temos": "D1FAE5", "Coberta": "D1FAE5", "Recomendado": "D1FAE5",
    "Testar (demo)": "FEF3C7", "Testar antes": "FEF3C7", "Em parte": "FEF3C7", "Condicional": "FEF3C7",
    "Não serve": "F3F4F6", "Não coberta": "FEE2E2", "Rejeitado": "F3F4F6",
}
NOME_ETAPA = dict(ETAPAS)
ORDEM_REC = {"Usar agora": 0, "Testar (demo)": 1, "Não serve": 2}


def f(size=10, bold=False, color=TINTA, italic=False):
    return Font(name=FONTE, size=size, bold=bold, color=color, italic=italic)


def titulo(ws, texto, subtitulo):
    ws.sheet_view.showGridLines = False
    ws["A1"] = texto
    ws["A1"].font = f(14, True, AZUL)
    ws["A2"] = subtitulo
    ws["A2"].font = f(10, color=SUAVE)
    ws.row_dimensions[1].height = 24


def tabela(ws, cab, larguras, dados, linha=4, col_cor=None, altura=None):
    for i, (nome, larg) in enumerate(zip(cab, larguras), start=1):
        c = ws.cell(row=linha, column=i, value=nome)
        c.font = f(10, True, AZUL)
        c.fill = PatternFill("solid", fgColor=CAB)
        c.alignment = Alignment(wrap_text=True, vertical="center")
        ws.column_dimensions[get_column_letter(i)].width = larg
    ws.row_dimensions[linha].height = 30
    for r, d in enumerate(dados, start=linha + 1):
        for col, v in enumerate(d, start=1):
            c = ws.cell(row=r, column=col, value=v)
            c.font = f(10)
            c.alignment = Alignment(wrap_text=True, vertical="top")
            c.border = SEP
        if col_cor:
            c = ws.cell(row=r, column=col_cor)
            if c.value in COR:
                c.fill = PatternFill("solid", fgColor=COR[c.value])
                c.font = f(10, True)
        if altura:
            ws.row_dimensions[r].height = altura
    ws.freeze_panes = ws.cell(row=linha + 1, column=1)
    return linha + len(dados)


def main(saida: str):
    ponte = json.loads((AQUI / "pesquisa" / "ponte.json").read_text(encoding="utf-8"))
    ponte.sort(key=lambda p: (p["etapa"], ORDEM_REC.get(p["recomendacao"], 9), -p["util_num"] / max(p["util_den"], 1)))
    wb = openpyxl.Workbook()

    # --- 1. Como ler ---------------------------------------------------------
    ws = wb.active
    ws.title = "Como ler"
    titulo(ws, "Plataformas e parceiros do Oria Digital", "Versão 2 · 24/11/2026 · pesquisa pública na internet; preços e prazos só valem confirmados por escrito")
    blocos = [
        ("O que é o Oria Digital", "Um sistema que monta o diagnóstico financeiro de empresas em crise ou em venda: lê os documentos, busca dados em fontes oficiais, confere tudo, e entrega um Excel em que cada número mostra de onde veio."),
        ("Para que serve esta planilha", "Enquanto o sistema não fica pronto, a Oria pode usar plataformas que já existem para fazer parte do trabalho. Aqui estão as plataformas pesquisadas, a combinação que propomos e o que ainda falta construir."),
        ("As abas", f"1. Combinação proposta — as plataformas que sugerimos usar juntas, e o que fica faltando.\n2. Plataformas por etapa — todas as {len(ponte)} plataformas avaliadas, organizadas pelas etapas do trabalho.\n3. Perguntas para as demos — o que perguntar antes de assinar.\n4. Integração definitiva — fornecedores de dados para ligar direto no sistema, mais adiante.\n5. Etapas — as 17 etapas do trabalho da Oria."),
        ("Compatibilidade", "Das ferramentas que a plataforma vende, quantas têm a ver com o trabalho da Oria (os documentos que ela busca e o que ela faz). Ex.: 7 de 8 ferramentas = 88%."),
        ("Utilidade", "Das ferramentas que a plataforma vende, quantas a Oria usaria de fato se assinasse. É sempre menor ou igual à compatibilidade. Quanto mais perto de 100%, menos pagamos por coisa que não usamos."),
        ("Recomendação", "Usar agora: dá para contratar já, preço e uso conhecidos.\nTestar (demo): parece servir, mas precisa de demonstração antes (quase nenhuma publica preço).\nNão serve: explicado na linha."),
        ("Cuidados", "Preço que não está no site aparece como 'Não publicado' — nunca estimado. O que não deu para confirmar aparece como 'A confirmar'."),
    ]
    r = 4
    for rotulo, texto in blocos:
        ws.cell(row=r, column=1, value=rotulo).font = f(10, True, AZUL)
        c = ws.cell(row=r, column=2, value=texto)
        c.font = f(10)
        c.alignment = Alignment(wrap_text=True, vertical="top")
        ws.cell(row=r, column=1).alignment = Alignment(vertical="top")
        ws.row_dimensions[r].height = 15 * (texto.count("\n") + 1 + len(texto) // 110)
        r += 2
    ws.column_dimensions["A"].width = 22
    ws.column_dimensions["B"].width = 110

    # --- 2. Combinação proposta ----------------------------------------------
    ws = wb.create_sheet("Combinação proposta")
    titulo(ws, "Combinação proposta", "As plataformas que sugerimos usar juntas enquanto o Oria Digital é construído — e o que fica faltando")
    fim = tabela(ws, ["Plataforma", "Para que usamos", "Etapas", "Situação", "Como entra no dia a dia", "Custo"],
                 [24, 52, 14, 14, 40, 40], COMBINACAO, linha=4, col_cor=4)

    r0 = fim + 3
    ws.cell(row=r0 - 1, column=1, value="O que a combinação cobre, etapa por etapa").font = f(12, True, AZUL)
    # Mesmas colunas da tabela de cima (larguras 24, 52, 14, 14, 40, 40): a cobertura ocupa
    # A (etapa), B (por quem e como), C (cobertura) e D:F mesclada (o que falta).
    dados = [(f"{c} · {NOME_ETAPA[c]}", por if por == "—" else f"{por}: {como[0].lower()}{como[1:]}", cob, falta)
             for c, por, como, cob, falta in COBERTURA]
    for i, nome in ((1, "Etapa do trabalho"), (2, "Coberta por"), (3, "Cobertura"), (4, "O que ainda falta construir")):
        c = ws.cell(row=r0, column=i, value=nome)
        c.font = f(10, True, AZUL)
        c.fill = PatternFill("solid", fgColor=CAB)
        c.alignment = Alignment(wrap_text=True, vertical="center")
    ws.merge_cells(start_row=r0, start_column=4, end_row=r0, end_column=6)
    for k, (etapa, por, cob, falta) in enumerate(dados, start=r0 + 1):
        for col, v in ((1, etapa), (2, por), (3, cob), (4, falta)):
            c = ws.cell(row=k, column=col, value=v)
            c.font = f(10)
            c.alignment = Alignment(wrap_text=True, vertical="top")
        for col in range(1, 7):
            ws.cell(row=k, column=col).border = SEP
        ws.merge_cells(start_row=k, start_column=4, end_row=k, end_column=6)
        ws.row_dimensions[k].height = 15 * max(2, len(falta) // 85 + 1, len(por) // 48 + 1)
        c = ws.cell(row=k, column=3)
        c.fill = PatternFill("solid", fgColor=COR[c.value])
        c.font = f(10, True)
    fim_cob = r0 + len(dados)

    rs = fim_cob + 3
    ws.cell(row=rs - 1, column=1, value="Em números").font = f(12, True, AZUL)
    rng = f"$C${r0 + 1}:$C${fim_cob}"
    resumo = [
        ("Etapas cobertas pela combinação", f'=COUNTIF({rng},"Coberta")'),
        ("Etapas cobertas em parte", f'=COUNTIF({rng},"Em parte")'),
        ("Etapas que só a Oria pode fazer (construir)", f'=COUNTIF({rng},"Não coberta")'),
        ("Plataformas para usar agora", f'=COUNTIF($D$5:$D${fim},"Usar agora")'),
        ("Plataformas para testar antes", f'=COUNTIF($D$5:$D${fim},"Testar antes")'),
    ]
    for k, (rot, form) in enumerate(resumo, start=rs):
        ws.merge_cells(start_row=k, start_column=1, end_row=k, end_column=2)
        ws.cell(row=k, column=1, value=rot).font = f(10)
        c = ws.cell(row=k, column=3, value=form)
        c.font = f(10, True)
        c.alignment = Alignment(horizontal="left")
    ws.cell(row=rs + len(resumo) + 1, column=1,
            value="Leitura: as plataformas resolvem a parte de buscar e ler dados. O que é o coração da Oria — conferir os números entre fontes, aprovar e entregar com a prova de cada número — continua sendo construção nossa.").font = f(10, italic=True, color=SUAVE)

    # --- 3. Plataformas por etapa ---------------------------------------------
    ws = wb.create_sheet("Plataformas por etapa")
    titulo(ws, "Plataformas por etapa", f"As {len(ponte)} plataformas avaliadas como ponte, organizadas pela etapa principal do trabalho. Use o filtro da coluna Recomendação.")
    cab = ["Etapa", "Plataforma", "O que é", "Documentos e dados que busca", "Principais funções", "Compatibilidade", "Utilidade", "Recomendação", "Por quê", "Como se usa", "Preço", "Também ajuda nas etapas", "Site"]
    dados = []
    for p in ponte:
        dados.append((
            f"{p['etapa']} · {NOME_ETAPA.get(p['etapa'], '')}", p["plataforma"], p["o_que_e"], p["documentos"], p["funcoes"],
            f"={p['compat_num']}/{p['compat_den']}" if p["compat_den"] else "A confirmar",
            f"={p['util_num']}/{p['util_den']}" if p["util_den"] else "A confirmar",
            p["recomendacao"], p["por_que"], p["como_usar"], p["preco"],
            ", ".join(p.get("outras_etapas") or []) or "—", p["fonte"],
        ))
    fim = tabela(ws, cab, [26, 18, 34, 34, 38, 14, 11, 14, 38, 24, 24, 14, 28], dados, col_cor=8)
    for k in range(5, fim + 1):
        for col in (6, 7):
            ws.cell(row=k, column=col).number_format = "0%"
            ws.cell(row=k, column=col).alignment = Alignment(horizontal="center", vertical="top")
    ws.auto_filter.ref = f"A4:{get_column_letter(len(cab))}{fim}"

    # --- 4. Perguntas para as demos -------------------------------------------
    ws = wb.create_sheet("Perguntas para as demos")
    titulo(ws, "Perguntas para as demos", "As 4 perguntas valem para todas; a última coluna é a dúvida específica de cada plataforma. As células amarelas são para preencher.")
    for k, q in enumerate(PERGUNTAS_FIXAS, start=4):
        ws.cell(row=k, column=1, value=f"{k - 3}.").font = f(10, True, AZUL)
        ws.cell(row=k, column=2, value=q).font = f(10)
    linha = 4 + len(PERGUNTAS_FIXAS) + 2
    testar = [p for p in ponte if p["recomendacao"] in ("Usar agora", "Testar (demo)")]
    dados = [(p["plataforma"], p["recomendacao"], p.get("a_confirmar") or "—", None, None) for p in testar]
    fim = tabela(ws, ["Plataforma", "Recomendação", "Dúvida específica", "Resposta", "Data"], [24, 16, 70, 50, 12], dados, linha=linha, col_cor=2)
    for k in range(linha + 1, fim + 1):
        for col in (4, 5):
            ws.cell(row=k, column=col).fill = PatternFill("solid", fgColor="FFFBEB")
    ws.column_dimensions["A"].width = 24
    ws.column_dimensions["B"].width = 16

    # --- 5. Integração definitiva (1ª rodada) ----------------------------------
    ws = wb.create_sheet("Integração definitiva")
    titulo(ws, "Integração definitiva", "Fornecedores de dados para ligar direto no sistema mais adiante (1ª rodada, 24/11/2026). Critério: a Oria precisa usar pelo menos 80% do que paga.")
    forn = []
    for nome in ("res_risco.json", "res_fiscal_bancario.json", "res_mercado_infra.json", "res_ia_plataforma.json"):
        forn.extend(json.loads((AQUI / "pesquisa" / nome).read_text(encoding="utf-8")))
    # Escolhas da 1ª rodada, por prefixo exato do nome da empresa no JSON.
    # Comparar por pedaço de texto marcava B3, n8n Magalu e Infosimples fiscal por engano.
    escolhidos = ("Direct Data", "Autentique", "n8n Community self-host em VM AWS", "Anthropic Claude API",
                  "Google Gemini no Vertex", "Microsoft Azure AI Document", "Construir — Web Service NFe",
                  "SERPRO", "Pluggy", "Núclea", "JUDIT", "Infosimples", "Fontes oficiais diretas", "GDELT",
                  "ONR", "Fontes públicas gratuitas", "Receita Federal — Painel", "DBOS", "Langfuse",
                  "Biblioteca open source", "Supabase Pro", "AWS S3", "Supabase Auth", "Não há fornecedor")
    # A mesma empresa avaliada em duas categorias (medido: só a Neoway, em risco e em benchmarks,
    # ambas Rejeitado) vira UMA linha, com as categorias juntas — o dono pediu planilha sem repetição.
    juntos = {}
    for x in forn:
        chave = x["empresa"].strip().lower()  # nome completo: "Infosimples" e "Infosimples (APIs fiscais)" são produtos diferentes
        if chave in juntos:
            a = juntos[chave]
            assert a["veredito"] == x["veredito"], f"{x['empresa']}: vereditos diferentes, não juntar às cegas"
            a["categoria"] += " · " + x["categoria"]
            a["motivo"] += " | " + x["motivo"]
        else:
            juntos[chave] = dict(x)
    forn = list(juntos.values())
    ordem_v = {"Recomendado": 0, "Condicional": 1, "Rejeitado": 2}
    forn.sort(key=lambda x: (x["etapas"][0], ordem_v.get(x["veredito"], 9)))
    dados = []
    for x in forn:
        pct = x.get("pct_uso_estimado")
        escolhido = "Sim" if x["empresa"].startswith(escolhidos) and not x["empresa"].startswith("Infosimples (") else ""
        dados.append((
            f"{x['etapas'][0]} · {NOME_ETAPA.get(x['etapas'][0], '')}", x["categoria"], x["empresa"],
            (pct / 100) if isinstance(pct, (int, float)) else "A confirmar",
            x["veredito"], escolhido, x["motivo"], x["preco_publicado"],
        ))
    fim = tabela(ws, ["Etapa", "Tipo de serviço", "Empresa", "Parte do pagamento que usaríamos", "Veredito", "Escolhido", "Por quê", "Preço publicado"],
                 [26, 26, 28, 14, 13, 10, 50, 40], dados, col_cor=5)
    for k in range(5, fim + 1):
        ws.cell(row=k, column=4).number_format = "0%"
        ws.cell(row=k, column=4).alignment = Alignment(horizontal="center", vertical="top")
        ws.cell(row=k, column=6).alignment = Alignment(horizontal="center", vertical="top")
    ws.auto_filter.ref = f"A4:H{fim}"

    # --- 6. Etapas ---------------------------------------------------------------
    ws = wb.create_sheet("Etapas")
    titulo(ws, "As 17 etapas do trabalho da Oria", "Os mesmos códigos da Planilha 1 (funcionalidades, integrações e dados)")
    tabela(ws, ["Código", "Etapa"], [10, 60], ETAPAS)

    wb.save(saida)
    print(f"{saida}: {len(COMBINACAO)} na combinação, {len(ponte)} plataformas-ponte, {len(forn)} fornecedores de dados")


if __name__ == "__main__":
    main(sys.argv[1])
