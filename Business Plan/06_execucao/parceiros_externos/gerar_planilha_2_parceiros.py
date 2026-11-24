"""Gera a Planilha 2 — empresas que resolvem cada etapa do Oria Digital.

Uso:  python3 -I gerar_planilha_2_parceiros.py <saida.xlsx>

Entrada: os arquivos pesquisa/res_*.json (pesquisa web de 24/11/2026, quatro frentes), um
objeto por fornecedor avaliado, com a conta do % de uso, o preço com fonte e o veredito.
O plano por etapa (PLANO, abaixo) é a síntese escrita a partir deles; cada escolha cita o
fornecedor que está na aba "Fornecedores avaliados".

Critério do dono (24/11/2026): só serve fornecedor de que a Oria use ≥ 80% do que paga.
"""
import json
import sys
from pathlib import Path

import openpyxl
from openpyxl.formatting.rule import CellIsRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

AQUI = Path(__file__).resolve().parent
FONTE = "Arial"
AZUL_ESCURO = "1F3A5F"
CINZA = "F2F2F2"
BORDA = Border(*(Side(style="thin", color="BFBFBF"),) * 4)
COR_VEREDITO = {"Recomendado": "C6EFCE", "Condicional": "FFEB9C", "Rejeitado": "FFC7CE"}

ORDEM_ARQUIVOS = ["res_risco.json", "res_fiscal_bancario.json", "res_mercado_infra.json", "res_ia_plataforma.json"]

sys.path.insert(0, str(AQUI))  # python -I não põe a pasta do script no path
from plano_por_etapa import PLANO  # noqa: E402  (síntese escrita à mão, separada dos dados)


def cabecalho(ws, colunas, larguras, linha=1):
    for i, (nome, larg) in enumerate(zip(colunas, larguras), start=1):
        c = ws.cell(row=linha, column=i, value=nome)
        c.font = Font(name=FONTE, bold=True, color="FFFFFF", size=10)
        c.fill = PatternFill("solid", fgColor=AZUL_ESCURO)
        c.alignment = Alignment(wrap_text=True, vertical="center")
        c.border = BORDA
        ws.column_dimensions[get_column_letter(i)].width = larg
    ws.freeze_panes = ws.cell(row=linha + 1, column=1)
    ws.row_dimensions[linha].height = 34


def linhas(ws, dados, inicio=2, col_veredito=None):
    for r, linha in enumerate(dados, start=inicio):
        for col, v in enumerate(linha, start=1):
            c = ws.cell(row=r, column=col, value=v)
            c.font = Font(name=FONTE, size=9)
            c.alignment = Alignment(wrap_text=True, vertical="top")
            c.border = BORDA
            if r % 2 == 1:
                c.fill = PatternFill("solid", fgColor=CINZA)
        if col_veredito:
            v = ws.cell(row=r, column=col_veredito)
            for chave, cor in COR_VEREDITO.items():
                if str(v.value or "").startswith(chave):
                    v.fill = PatternFill("solid", fgColor=cor)
                    v.font = Font(name=FONTE, size=9, bold=True)
    ws.auto_filter.ref = f"A{inicio - 1}:{get_column_letter(ws.max_column)}{ws.max_row}"


def carregar():
    todos = []
    for nome in ORDEM_ARQUIVOS:
        p = AQUI / "pesquisa" / nome
        if p.exists():
            todos.extend(json.loads(p.read_text(encoding="utf-8")))
        else:
            print(f"AVISO: {p.name} ausente — a frente não entra na planilha", file=sys.stderr)
    return todos


def main(saida: str):
    forn = carregar()
    wb = openpyxl.Workbook()

    # --- Leia-me -------------------------------------------------------------
    ws = wb.active
    ws.title = "Leia-me"
    texto = [
        ("Planilha 2 — Parceiros externos por etapa do Oria Digital", True),
        ("Versão 1 · 24/11/2026 · gerada por gerar_planilha_2_parceiros.py a partir de pesquisa/res_*.json (não editar à mão: regere).", False),
        ("", False),
        ("O critério do dono", True),
        ("Não serve empresa que resolve várias coisas da qual usaríamos só um pedaço. Só entra fornecedor em que a Oria usa pelo menos 80% do que paga.", False),
        ("", False),
        ("Como o % de uso foi calculado (coluna 'Conta do %')", True),
        ("% de uso = parte do escopo PAGO que a Oria usaria ÷ escopo pago total. Escopo pago = o que entra no contrato/plano que teríamos de assinar, não o catálogo inteiro do site.", False),
        ("Cobrança por consulta, página ou token, sem franquia ociosa → ~100% (pagamos só o que consumimos). Franquia mínima que sobraria no volume de referência é descontada.", False),
        ("Plano ou assento que empacota módulos → módulos listados, marcados usa/não usa; % por preço quando conhecido, senão por contagem (a conta diz qual).", False),
        ("Volume de referência: 4 mandatos ativos/mês × ~8 empresas × ~6 pessoas (Espec. 13, Plano_de_Captacao_v3). É premissa, não medição: o piloto mede (J6).", False),
        ("", False),
        ("Vereditos", True),
        ("Recomendado = ≥ 80% de uso. Condicional = ≥ 80% só sob a condição escrita na linha. Rejeitado = < 80%: a linha diz o que sobraria sem uso.", False),
        ("'Construir' aparece como opção quando nenhum fornecedor passa, ou quando a fonte oficial é gratuita e o fornecedor só a revende.", False),
        ("", False),
        ("Abas", True),
        ("Plano por etapa — para cada etapa E01–E17 (Planilha 1): a escolha, as alternativas, a condição e o que confirmar antes de assinar.", False),
        ("Fornecedores avaliados — cada empresa pesquisada, com o que oferece, o que a Oria usaria, o que sobraria, a conta do %, o preço com fonte e o veredito.", False),
        ("A confirmar — o que cada fornecedor Recomendado ou Condicional precisa responder por escrito (vira o RFP, Espec. 13 §5).", False),
        ("Resumo — contagens por categoria e veredito, em fórmula.", False),
        ("", False),
        ("Regras de honestidade", True),
        ("Preço sem fonte aparece como 'não publicado' ou 'a confirmar'. Afirmação feita de memória, sem URL, está marcada 'memória — conferir'. Pesquisa pública não é contrato: preço, cobertura e regime só valem confirmados por escrito.", False),
    ]
    for r, (t, negrito) in enumerate(texto, start=1):
        c = ws.cell(row=r, column=1, value=t)
        c.font = Font(name=FONTE, bold=negrito, size=12 if r == 1 else 10, color=AZUL_ESCURO if negrito else "000000")
        c.alignment = Alignment(wrap_text=True, vertical="top")
    ws.column_dimensions["A"].width = 135

    # --- Plano por etapa -----------------------------------------------------
    ws = wb.create_sheet("Plano por etapa")
    cols = ["Etapa", "Nome da etapa", "Necessidade (funcionalidades da Planilha 1)", "Escolha", "Tipo da escolha", "% de uso da escolha", "Modelo de cobrança / preço", "Alternativas (veredito)", "Condição / risco", "Quando", "O que confirmar antes de assinar"]
    cabecalho(ws, cols, [7, 22, 34, 30, 16, 10, 30, 34, 40, 10, 40])
    linhas(ws, PLANO)
    for r in range(2, len(PLANO) + 2):
        ws.cell(row=r, column=6).number_format = "0%"

    # --- Fornecedores avaliados ---------------------------------------------
    ws = wb.create_sheet("Fornecedores avaliados")
    cols = ["ID", "Etapas", "Categoria", "Empresa", "Site", "O que oferece (escopo pago)", "O que a Oria usaria", "O que sobraria", "% de uso estimado", "Conta do %", "Modelo de cobrança", "Preço publicado (data, fonte)", "Brasil / LGPD", "Veredito", "Motivo", "Riscos / a confirmar", "Fontes"]
    cabecalho(ws, cols, [6, 10, 22, 26, 22, 40, 34, 30, 9, 36, 20, 32, 26, 12, 36, 36, 40])
    dados = []
    for n, f in enumerate(forn, start=1):
        pct = f.get("pct_uso_estimado")
        dados.append((
            f"P{n:03d}", ", ".join(f["etapas"]), f["categoria"], f["empresa"], f["site"],
            f["o_que_oferece"], f["o_que_oria_usaria"], f["o_que_sobraria"],
            (pct / 100) if isinstance(pct, (int, float)) else "não calculável",
            f["conta_do_pct"], f["modelo_cobranca"], f["preco_publicado"], f["brasil_lgpd"],
            f["veredito"], f["motivo"], f["riscos_a_confirmar"], "\n".join(f["fontes"]),
        ))
    linhas(ws, dados, col_veredito=14)
    n_f = len(dados) + 1
    for r in range(2, n_f + 1):
        ws.cell(row=r, column=9).number_format = "0%"
    ws.conditional_formatting.add(f"I2:I{n_f}", CellIsRule(operator="greaterThanOrEqual", formula=["0.8"], font=Font(name=FONTE, size=9, color="006100", bold=True)))
    ws.conditional_formatting.add(f"I2:I{n_f}", CellIsRule(operator="lessThan", formula=["0.8"], font=Font(name=FONTE, size=9, color="9C0006", bold=True)))

    # --- A confirmar ---------------------------------------------------------
    ws = wb.create_sheet("A confirmar")
    cols = ["ID", "Etapas", "Empresa", "Veredito", "O que perguntar / confirmar por escrito", "Resposta (preencher)", "Data da resposta"]
    cabecalho(ws, cols, [6, 10, 30, 12, 80, 40, 12])
    conf = [(d[0], d[1], d[3], d[13], d[15], None, None) for d in dados if d[13] in ("Recomendado", "Condicional")]
    linhas(ws, conf, col_veredito=4)
    for r in range(2, len(conf) + 2):
        for col in (6, 7):
            ws.cell(row=r, column=col).fill = PatternFill("solid", fgColor="FFFF00")

    # --- Resumo (fórmulas) ---------------------------------------------------
    ws = wb.create_sheet("Resumo", 1)
    cols = ["Categoria", "Avaliados", "Recomendado", "Condicional", "Rejeitado", "Maior % de uso entre os não rejeitados"]
    cabecalho(ws, cols, [52, 11, 13, 13, 11, 18])
    cats = list(dict.fromkeys(d[2] for d in dados))
    rng = lambda col: f"'Fornecedores avaliados'!${col}$2:${col}${n_f}"  # noqa: E731
    for i, cat in enumerate(cats, start=2):
        ws.cell(row=i, column=1, value=cat)
        ws.cell(row=i, column=2, value=f"=COUNTIF({rng('C')},A{i})")
        for col, v in zip((3, 4, 5), ("Recomendado", "Condicional", "Rejeitado")):
            ws.cell(row=i, column=col, value=f'=COUNTIFS({rng("C")},A{i},{rng("N")},"{v}")')
        ws.cell(row=i, column=6, value=f'=IFERROR(_xlfn.MAXIFS({rng("I")},{rng("C")},A{i},{rng("N")},"<>Rejeitado"),"")')
        ws.cell(row=i, column=6).number_format = "0%"
    tot = len(cats) + 2
    ws.cell(row=tot, column=1, value="TOTAL")
    for col in range(2, 6):
        L = get_column_letter(col)
        ws.cell(row=tot, column=col, value=f"=SUM({L}2:{L}{tot - 1})")
    for row in ws.iter_rows(min_row=2, max_row=tot):
        for c in row:
            c.font = Font(name=FONTE, size=9, bold=(c.row == tot))
            c.border = BORDA

    wb.save(saida)
    print(f"{saida}: {len(PLANO)} etapas no plano, {len(dados)} fornecedores, {len(conf)} itens a confirmar")


if __name__ == "__main__":
    main(sys.argv[1])
