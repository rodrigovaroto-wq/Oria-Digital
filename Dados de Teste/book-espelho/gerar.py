# -*- coding: utf-8 -*-
"""Ponto de entrada do book ESPELHO: PDFs, planilhas, gabarito, métricas e texto.

    cd "Dados de Teste/book-espelho" && PYTHONPATH=. python3 gerar.py

Saída em `pdf/` (não versionada — determinística, basta rodar de novo). Os
PDFs saem iguais ao byte entre execuções (`rl_config.invariant`); as planilhas
NÃO: o zip do .xlsx carimba a hora de gravação em cada membro, e o openpyxl não
expõe esse carimbo. O CONTEÚDO delas é determinístico.
"""

import json
import os
import re

import dados as D
import demonstracoes as X
import extrai
import motor as M
import render as R

m = M.construir()

# ---------------------------------------------------------------------------
# OS DOCUMENTOS, com os NOMES como o cliente manda: sem notação de período, com
# acento, espaço, maiúscula solta e o "(2)" de arquivo baixado duas vezes. É de
# propósito que nenhum segue `2 Especificação/f0/03` — os reais não seguiam.
#
# `ESPELHA`: qual caso REAL de produção o documento imita na FORMA, e qual
# falha real ele mira. Vai para o METRICAS.json, documento a documento.
# ---------------------------------------------------------------------------
ESPELHA = {
    "DRE_janaago26.pdf":
        "DRE_janaago26.pdf e 'DRE Krauspenhar 2025 - Ass.pdf' (493 linhas): DRE analítica mensal com 8 meses + "
        "acumulado. Mira 'conta(s) descartada(s) por desalinhamento entre colunas e valores' e "
        "'Extração INCOMPLETA: 223 de 493 (45%)'.",
    "DRE Sintética 2025 x 2024.pdf":
        "Controle do caso acima: a mesma empresa em DRE de 2 colunas e ~90 linhas. Se esta passa e a analítica "
        "falha, o problema é a largura (colunas), não o vocabulário.",
    "balancete_janaago26.pdf":
        "balancete_janaago26.pdf e 'Balancete 1º semestre 2025.pdf' (~1.500 pares conta×coluna, 11+ blocos): "
        "balancete de 4 colunas, código hierárquico, D/C após o valor. Mira o fatiamento em muitos blocos e o "
        "limite de pedidos por minuto do provedor.",
    "BALANÇO SERRA DO ESPELHO 2025.pdf":
        "'BALANÇO MOTO AGRICOLA 2023.pdf' (~2.500 pares, 24+ blocos): balanço com 12 colunas mensais em "
        "paisagem e fonte pequena. Mira volume de blocos e coluna de mês trocada.",
    "Balanço Patrimonial Espelho Implementos 2025 - Ass.pdf":
        "Balanço real com 4 linhas 'EMPRÉSTIMOS E FINANCIAMENTOS - LP' de valor idêntico: mira a guarda que "
        "acusou 'padrão típico de fabricação' em repetição LEGÍTIMA, e a deduplicação por rótulo.",
    "Alteração Contratual Consolidada nº 12 - Serra do Espelho.pdf":
        "Contrato social real com o capital (15.500.000,00) repetido em 4 contas: mira a mesma guarda de "
        "fabricação. Aqui o capital aparece 4× no texto e as 4 quotas por sócio são iguais.",
    "Procuração ad negotia - Serra do Espelho.pdf":
        "Controle: documento sem dado financeiro, mas com CPF, RG, OAB, CEP e datas. Zero linha extraída é o "
        "resultado CERTO (verdade declarada zero), não falha.",
    "Extrato cc 41.207-3 agosto 2026.xlsx":
        "Extrato bancário .xlsx real com 0 campos extraídos: cabeçalho na linha 6, título mesclado, data como "
        "texto, D/C em coluna própria, aba extra, totais por fórmula (sem cache) e por valor.",
    "MAPA DE DÍVIDA 31.08.2026.xlsx":
        "Mapa de dívida .xlsx real com 0 campos extraídos: cabeçalho na linha 6, total da LINHA por fórmula, "
        "datas como data do Excel, aba de premissas com números irrelevantes.",
    "estoque peças ago26 (2).xlsx":
        "Estoque .xlsx real com '1 rótulo com número colado' (e o padrão '849 -3.630,00(-) INSTALAÇÕES' do "
        "PDF): o código do item vem COLADO na descrição, em três formas ('10234-X', '10234 - X', '849X').",
    "Contingências jurídicas - posição ago-26.xlsx":
        "Contingências .xlsx real (86 campos): nº CNJ com muitos dígitos ao lado do valor, valor da causa como "
        "TEXTO 'R$ 1.234,56', só o provável provisionado, aba de instruções.",
}

dre_a, anc_a = X.dre_analitica(m["res26"])
dre_s, anc_s = X.dre_sintetica(m["sint"])
bcte, mov_total = X.balancete(m["bcte"], m["res26"])
bal_m = X.balanco_mensal(m["bal25"])
bal_i = X.balanco_implementos(m["impl"])

# Sem valor monetário por DECLARAÇÃO, como a armadilha 12 do canastra: o que a
# régua enxergar aqui é contagem a mais.
R.SEM_VALOR_MONETARIO.add("Procuração ad negotia - Serra do Espelho.pdf")

pdfs = [
    R.pdf_dre_analitica(dre_a, "DRE_janaago26.pdf"),
    R.pdf_dre_sintetica(dre_s, "DRE Sintética 2025 x 2024.pdf"),
    R.pdf_balancete(bcte, mov_total, "balancete_janaago26.pdf"),
    R.pdf_balanco_mensal(bal_m, "BALANÇO SERRA DO ESPELHO 2025.pdf"),
    R.pdf_balanco_implementos(bal_i, "Balanço Patrimonial Espelho Implementos 2025 - Ass.pdf"),
    R.pdf_contrato_social("Alteração Contratual Consolidada nº 12 - Serra do Espelho.pdf"),
    R.pdf_procuracao("Procuração ad negotia - Serra do Espelho.pdf"),
]

ext_ini, ext_linhas, ext_fim = M.extrato_agosto(m["bcte"])
div_linhas, div_total = M.mapa_divida(m["bcte"])
est_linhas, est_total = M.estoque_pecas(m["bcte"])
cont_linhas = M.contingencias(m["bcte"])

planilhas = {}
for arq, resumo in [
    R.xlsx_extrato(ext_ini, ext_linhas, ext_fim, "Extrato cc 41.207-3 agosto 2026.xlsx"),
    R.xlsx_mapa_divida(div_linhas, div_total, "MAPA DE DÍVIDA 31.08.2026.xlsx"),
    R.xlsx_estoque(est_linhas, est_total, "estoque peças ago26 (2).xlsx"),
    R.xlsx_contingencias(cont_linhas, "Contingências jurídicas - posição ago-26.xlsx"),
]:
    planilhas[arq] = resumo

assert set(ESPELHA) == set(pdfs) | set(planilhas), "documento sem `espelha` (ou `espelha` sem documento)"
print(f"{len(pdfs)} PDFs e {len(planilhas)} planilhas gerados em {R.OUT}")


# ---------------------------------------------------------------- GABARITO ---
def reais(c):
    """Centavos → reais com 2 casas (float só na SAÍDA, nunca na conta)."""
    return round(c / 100, 2)


def serie(v):
    return [reais(x) for x in v]


folhas_p = {r: c for c, r, _g, _b in M.folhas_patrimoniais()}
meses8 = [f"{x}/2026" for x in D.MESES[:8]] + ["Acumulado"]
cod_fecha = folhas_p[D.CONTA_QUE_FECHA]

gab = {
    "grupo": D.GRUPO,
    "exercicios": [2024, 2025, 2026],
    "escala": "R$ com centavos em todos os documentos (nenhum em R$ mil)",
    "entidades": {k: D.EMPRESAS[k]["razao_social"] for k in D.EMPRESAS},
    "cnpj": {k: D.EMPRESAS[k]["cnpj"] for k in D.EMPRESAS},
    "dre_analitica_2026": {
        "colunas": meses8,
        "linhas_impressas": len(dre_a),
        "folhas": len(m["res26"]),
        "celulas_vazias": sum(1 for l in dre_a for v in l["vals"] if v is None),
        "celulas_zero_impresso": sum(1 for l in dre_a for v in l["vals"] if v == 0),
        **{k: serie(v) for k, v in anc_a.items()},
    },
    "dre_sintetica": {"colunas": ["2025", "2024"], "linhas_impressas": len(dre_s),
                      **{k: serie(v) for k, v in anc_s.items()}},
    "balancete_jan_ago_2026": {
        "linhas_impressas": len(bcte),
        "contas_analiticas": sum(1 for l in bcte if l["tipo"] == "folha"),
        "total_debitos": reais(mov_total), "total_creditos": reais(mov_total),
        "saldo_atual_por_grupo_devedor_positivo": {
            l["cod"]: reais(l["vals"][3]) for l in bcte if l["nivel"] <= 1},
        "resultado_jan_ago_igual_dre_analitica": reais(anc_a["resultado_liquido"][-1]),
        "conta_movimento_banco_meridional": reais(m["bcte"][cod_fecha][3]),
    },
    "balanco_mensal_2025": {
        "colunas": [f"{x}/25" for x in D.MESES],
        "linhas_impressas": len(bal_m),
        **{rot: serie(next(l for l in bal_m if l["cod"] == cod)["vals"])
           for cod, rot in (("1", "total_ativo"), ("1.01", "ativo_circulante"), ("1.02", "ativo_nao_circulante"),
                            ("2.01", "passivo_circulante"), ("2.02", "passivo_nao_circulante"),
                            ("2.03", "patrimonio_liquido"))},
        "resultado_dez_igual_dre_sintetica_2025": reais(m["r25"]),
    },
    "balanco_implementos": {
        "colunas": ["31/12/2025", "31/12/2024"],
        "linhas_impressas": len(bal_i),
        "total_ativo": serie(next(l for l in bal_i if l["rot"] == "TOTAL DO ATIVO")["vals"]),
        "emprestimos_lp_tranches_iguais": {
            "rotulo": "EMPRÉSTIMOS E FINANCIAMENTOS - LP", "linhas": 4,
            "valor_2025": reais(M.TRANCHE_LP[2025]), "valor_2024": reais(M.TRANCHE_LP[2024]),
            "credores": M.CREDORES_LP,
            "esperado": "4 linhas legítimas com o MESMO rótulo e o MESMO valor — não é fabricação",
        },
    },
    "contrato_social": {
        "capital_social": float(D.CAPITAL_SOCIAL),
        "ocorrencias_do_capital_no_texto": 4,
        "ocorrencias_do_capital_no_quadro_de_socios": 1,
        "socios": len(D.SOCIOS),
        "quota_por_socio": float(D.CAPITAL_SOCIAL // len(D.SOCIOS)),
        "esperado": "capital repetido 4× (anterior, mantido, subscrito, integralizado) e 4 quotas iguais — "
                    "repetição legítima",
    },
    "procuracao": {"linhas_financeiras_esperadas": 0},
    "extrato_xlsx": {"conta": "Banco do Planalto S.A. - conta movimento", "lancamentos": len(ext_linhas),
                     "saldo_inicial": reais(ext_ini), "saldo_final": reais(ext_fim),
                     "saldo_final_igual_balancete": reais(m["bcte"][folhas_p['Banco do Planalto S.A. - conta movimento']][3]),
                     "total_creditos": reais(planilhas["Extrato cc 41.207-3 agosto 2026.xlsx"]["creditos"]),
                     "total_debitos": reais(planilhas["Extrato cc 41.207-3 agosto 2026.xlsx"]["debitos"])},
    "mapa_divida_xlsx": {"contratos": len(div_linhas),
                         **{k: reais(v) for k, v in planilhas["MAPA DE DÍVIDA 31.08.2026.xlsx"].items()},
                         "igual_balancete": "2.01.02 + 2.02.01"},
    "estoque_xlsx": {"itens": len(est_linhas), "total": reais(est_total),
                     "igual_balancete": "folhas 'Peças - …' de 1.01.03",
                     "rotulos_com_codigo_colado": len(est_linhas)},
    "contingencias_xlsx": {
        "processos": len(cont_linhas),
        "provisionado": reais(planilhas["Contingências jurídicas - posição ago-26.xlsx"]["provisionado"]),
        "por_natureza": {n: {k: (reais(v) if k != "processos" else v) for k, v in d.items()}
                         for n, d in planilhas["Contingências jurídicas - posição ago-26.xlsx"]["por_natureza"].items()},
        "igual_balancete": "2.02.03 (só o prognóstico provável)"},
    "documentos": pdfs + list(planilhas),
}
with open(f"{R.OUT}/GABARITO.json", "w", encoding="utf-8") as fh:
    json.dump(gab, fh, indent=2, ensure_ascii=False)


# ------------------------------------------------------------------ MÉTRICAS -
# PDFs: o mesmo formato do canastra/distress, medido no artefato, com a VERDADE
# contada por `comum/contagem.py` — mais o campo `espelha`.
metricas, texto_por_arquivo = [], {}
for arquivo in pdfs:
    bruto = open(f"{R.OUT}/{arquivo}", "rb").read()
    texto = extrai.texto(bruto)
    linhas_texto = [ln for ln in texto.split("\n") if ln.strip()]
    texto_por_arquivo[arquivo] = [ln for ln in extrai.linhas(bruto) if ln.strip()]
    verdade = R.CONTAGEM.get(arquivo, {"linhas_de_conta": 0, "celulas_de_valor": 0, "contas_distintas": 0})
    metricas.append({
        "arquivo": arquivo,
        "paginas": len(re.findall(rb"/Type\s*/Page[^s]", bruto)),
        "bytes": len(bruto),
        "caracteres": len(texto),
        "linhas_texto": len(linhas_texto),
        "linhas_com_numero": sum(1 for ln in linhas_texto if any(ch.isdigit() for ch in ln)),
        "linhas_de_conta_verdade": verdade["linhas_de_conta"],
        "celulas_de_valor_verdade": verdade["celulas_de_valor"],
        "contas_distintas_verdade": verdade["contas_distintas"],
        "espelha": ESPELHA[arquivo],
    })

# PLANILHAS: fora de `documentos`, numa lista própria. O motivo é concreto:
# `N8N/medir-custo-book.mjs` reprova documento com `paginas` zerada ("métrica
# ausente") e precifica por página-imagem, que é o caminho do PDF; e
# `medir-regua-cobertura.mjs` lê o texto do PDF. Pôr a planilha ali com
# `paginas: 0` seria apresentar ausência como dado (regra 1) e derrubar os dois
# medidores por um motivo que não é defeito de nenhum deles. `paginas` vai
# `null`: planilha não tem página.
metricas_xlsx, texto_xlsx = [], {}
for arquivo in planilhas:
    caminho = f"{R.OUT}/{arquivo}"
    verdade, texto_abas = R.verdade_xlsx(arquivo)
    todas = [ln for aba in texto_abas.values() for ln in aba]
    texto_xlsx[arquivo] = texto_abas
    metricas_xlsx.append({
        "arquivo": arquivo,
        "formato": "xlsx",
        "paginas": None,
        "bytes": os.path.getsize(caminho),
        "caracteres": sum(len(ln) for ln in todas),
        "linhas_texto": len(todas),
        "linhas_com_numero": sum(1 for ln in todas if any(ch.isdigit() for ch in ln)),
        "linhas_de_conta_verdade": verdade["linhas_de_conta"],
        "celulas_de_valor_verdade": verdade["celulas_de_valor"],
        "contas_distintas_verdade": verdade["contas_distintas"],
        "celulas_de_formula": verdade["celulas_de_formula"],
        "abas": verdade["abas"],
        "linha_do_cabecalho": verdade["linha_do_cabecalho"],
        "espelha": ESPELHA[arquivo],
    })

with open(f"{R.OUT}/METRICAS.json", "w", encoding="utf-8") as fh:
    json.dump({"livro": "book-espelho", "documentos": metricas, "planilhas": metricas_xlsx}, fh,
              indent=2, ensure_ascii=False)
with open(f"{R.OUT}/TEXTO_EXTRAIDO.json", "w", encoding="utf-8") as fh:
    json.dump({"livro": "book-espelho", "documentos": texto_por_arquivo,
               # As planilhas como o openpyxl as lê de volta, aba por aba, célula
               # separada por " | " e fórmula como TEXTO. NÃO é o texto que o n8n
               # produz (o `Extract From File` + `Agrupar Linhas XLSX` não foram
               # reimplementados aqui); serve para conferir o que está gravado.
               "planilhas": texto_xlsx}, fh, indent=1, ensure_ascii=False)

for x in metricas + metricas_xlsx:
    print(f"  {x['arquivo']:<62} pág={str(x['paginas']):>4}  verdade={x['linhas_de_conta_verdade']:>4} linhas "
          f"/ {x['celulas_de_valor_verdade']:>5} células")
print(f"GABARITO.json, METRICAS.json e TEXTO_EXTRAIDO.json gravados: {len(metricas)} PDFs "
      f"({sum(x['paginas'] for x in metricas)} páginas) + {len(metricas_xlsx)} planilhas, "
      f"{sum(x['linhas_de_conta_verdade'] for x in metricas + metricas_xlsx)} linhas de conta (verdade)")
