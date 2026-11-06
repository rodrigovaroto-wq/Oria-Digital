# -*- coding: utf-8 -*-
"""Os números do book ESPELHO, em CENTAVOS inteiros, com assert em cada amarração.

    PYTHONPATH=. python3 motor.py     # imprime as amarrações

Centavos e não reais em ponto flutuante porque os documentos que este book
imita (balancete, DRE analítica, balanço mensal) são impressos com centavos, e
"acumulado = soma dos meses" e "débito = crédito" têm de fechar no CENTAVO —
em float, oito meses somados já erram na terceira casa e o assert mentiria.

A ordem de construção, e o que cada passo amarra:

  1. Resultado jan–ago/2026 por folha e por mês (DRE analítica). Acumulado =
     soma dos meses, por construção e por assert.
  2. DRE sintética anual 2025 × 2024. O resultado de 2025 é o que o balanço
     de dezembro de 2025 carrega no PL.
  3. Balanço mensal 2025 (12 colunas): folhas por mês; a conta movimento do
     Banco Meridional FECHA Ativo = Passivo + PL em cada mês (assert > 0).
  4. Balancete jan–ago/2026: saldo anterior = balanço de dez/2025 depois do
     encerramento (resultado → lucros acumulados); saldo atual das contas de
     resultado = acumulado da DRE analítica; débito = crédito por assert.
  5. Anexos (.xlsx) lidos do balancete: extrato, mapa de dívida, estoque de
     peças e contingências somam a conta que detalham, no centavo.

Ruído determinístico pelo RÓTULO (sha256), como no canastra: rodar duas vezes
dá os mesmos números, sem `random` e sem semente para esquecer.
"""

import hashlib

import dados as D

N_MESES_2026 = 8  # jan–ago


def ruido(chave, lo=0.0, hi=1.0):
    h = int(hashlib.sha256(chave.encode("utf-8")).hexdigest()[:12], 16)
    return lo + (hi - lo) * (h / float(0xFFFFFFFFFFFF))


def cent(reais):
    return int(round(reais * 100))


# --------------------------------------------------------------- RESULTADO --
def folhas_resultado():
    """Lista de (codigo, rotulo, grupo, natureza R/D) na ordem do plano."""
    saida = []
    for grupo, _rot, folhas in D.PLANO_RESULTADO:
        for i, (rot, nat) in enumerate(folhas, 1):
            saida.append((f"{grupo}.{i:03d}", rot, grupo, nat))
    return saida


# Sazonalidade de jan a ago: a safra de verão colhe em fev–abr e a feira de
# março puxa venda de máquina. Só afeta o tamanho, não a forma.
SAZONAL = [0.72, 0.86, 1.31, 1.12, 0.94, 0.81, 0.88, 1.24]


def _base_da_folha(grupo, n_folhas):
    chave_curta = grupo[:4]
    if chave_curta in ("4.03", "4.04"):
        return D.BASE_MENSAL[chave_curta]  # já é por folha
    return D.BASE_MENSAL[grupo] / n_folhas


def _mensal_bruto(cod, rot, base, sazonal=True):
    vals = []
    for m in range(N_MESES_2026):
        f = SAZONAL[m] if sazonal else 1.0
        vals.append(base * f * ruido(f"{cod}|{rot}|{m}", 0.55, 1.45))
    return vals


def resultado_2026():
    """{codigo: {"rotulo", "grupo", "nat", "meses": [centavos|None]*8, "acum"}}.

    Convenção da DRE: receita POSITIVA, custo/despesa NEGATIVA.

    Três formas que o documento real tinha e que este gerador reproduz de
    propósito, porque são elas que embaralham coluna na leitura:
      • célula VAZIA em alguns meses (conta sem movimento no mês) — `None`;
      • ZERO impresso ("0,00") em alguns meses — movimento que se anulou;
      • sinal TROCADO num mês (estorno maior que o lançamento).
    """
    folhas = folhas_resultado()
    por_grupo = {}
    for cod, rot, grupo, nat in folhas:
        por_grupo.setdefault(grupo, []).append((cod, rot, nat))

    out = {}
    venda_por_linha = {}  # rótulo da linha de produto → meses (centavos), para o CMV
    for grupo, itens in por_grupo.items():
        base = _base_da_folha(grupo, len(itens))
        for cod, rot, nat in itens:
            sinal = 1 if nat == "R" else -1
            if grupo.startswith("4.02"):
                # CMV/CSP amarrado à venda da MESMA linha: margem por linha.
                linha = rot.split(" - ", 1)[1]
                chave_venda = {"4.02.01": "3.01.01", "4.02.02": "3.01.02",
                               "4.02.03": "3.01.03", "4.02.04": "3.01.04"}[grupo]
                venda = venda_por_linha[(chave_venda, linha)]
                margem = {"4.02.01": (0.78, 0.86), "4.02.02": (0.80, 0.90),
                          "4.02.03": (0.58, 0.70), "4.02.04": (0.42, 0.58)}[grupo]
                r = ruido(f"margem|{cod}", *margem)
                meses = [None if v is None else -int(round(v * r)) for v in venda]
            else:
                sazonal = grupo.startswith("3.01") or grupo.startswith("4.01")
                brutos = _mensal_bruto(cod, rot, base, sazonal)
                meses = [sinal * cent(v) for v in brutos]
                h = ruido(f"forma|{cod}")
                if h < 0.30 or grupo in ("4.01.02", "3.03.01", "4.08.01"):
                    # esporádica: metade dos meses sem movimento (célula vazia)
                    meses = [v if ruido(f"vazio|{cod}|{m}") < 0.5 else None
                             for m, v in enumerate(meses)]
                elif h < 0.40:
                    # zero IMPRESSO num mês — não é ausência, é saldo que zerou
                    m0 = int(ruido(f"zero|{cod}") * N_MESES_2026)
                    meses[m0] = 0
                if 0.40 <= h < 0.46:
                    # estorno maior que o lançamento: sinal trocado num mês
                    m1 = int(ruido(f"estorno|{cod}") * N_MESES_2026)
                    if meses[m1] is not None:
                        meses[m1] = -meses[m1] // 4
                if all(v is None for v in meses):
                    meses[3] = sinal * cent(base)
            if grupo in ("3.01.01", "3.01.02", "3.01.03", "3.01.04"):
                venda_por_linha[(grupo, rot.split(" - ", 1)[1])] = meses
            out[cod] = {"rotulo": rot, "grupo": grupo, "nat": nat, "meses": meses,
                        "acum": sum(v for v in meses if v is not None)}
    for cod, c in out.items():
        assert c["acum"] == sum(v or 0 for v in c["meses"]), cod
    return out


def soma_meses(res, prefixo):
    """Soma por mês (lista de 8) e acumulado das folhas cujo código começa com prefixo."""
    meses = [0] * N_MESES_2026
    for cod, c in res.items():
        if cod.startswith(prefixo + ".") or cod == prefixo:
            for m, v in enumerate(c["meses"]):
                meses[m] += v or 0
    return meses, sum(meses)


def lucro_2026(res):
    meses = [0] * N_MESES_2026
    for c in res.values():
        for m, v in enumerate(c["meses"]):
            meses[m] += v or 0
    return meses, sum(meses)


# ----------------------------------------------------------- DRE SINTÉTICA --
def dre_sintetica():
    """DRE anual 2025 × 2024, ~100 linhas: as folhas de receita bruta por linha
    de produto, e os demais grupos condensados. {chave: (rotulo, v2025, v2024)}.

    Valores anuais ≈ 12 × a base mensal, com ruído próprio — é OUTRA empresa no
    tempo (exercícios fechados), não a soma da analítica de 2026."""
    linhas = []
    for grupo, rot_g, folhas in D.PLANO_RESULTADO:
        n = len(folhas)
        base = _base_da_folha(grupo, n) * 12
        if grupo.startswith("3.01"):
            itens = [(f"{grupo}.{i:03d}", r) for i, (r, _n) in enumerate(folhas, 1)]
        elif grupo.startswith("4.09"):
            itens = [(f"{grupo}.{i:03d}", r) for i, (r, _n) in enumerate(folhas, 1)]
        else:
            itens = [(grupo, rot_g.capitalize())]
            base = base * n
        sinal = 1 if folhas[0][1] == "R" else -1
        for cod, r in itens:
            v25 = cent(base * ruido(f"a25|{cod}", 0.75, 1.25)) * sinal
            v24 = int(round(v25 * ruido(f"a24|{cod}", 0.86, 1.08)))
            linhas.append((cod, r, v25, v24))
    # CMV amarrado à receita da linha, como na analítica (margem anual).
    rec = {cod: (v25, v24) for cod, _r, v25, v24 in linhas}
    novas = []
    for cod, r, v25, v24 in linhas:
        if cod.startswith("4.02"):
            g = {"4.02.01": "3.01.01", "4.02.02": "3.01.02", "4.02.03": "3.01.03", "4.02.04": "3.01.04"}[cod]
            r25 = sum(v[0] for k, v in rec.items() if k.startswith(g + "."))
            r24 = sum(v[1] for k, v in rec.items() if k.startswith(g + "."))
            mg = {"4.02.01": 0.82, "4.02.02": 0.85, "4.02.03": 0.64, "4.02.04": 0.50}[cod]
            v25, v24 = -int(round(r25 * mg)), -int(round(r24 * (mg + 0.01)))
        novas.append((cod, r, v25, v24))
    return novas


def resultado_sintetica(linhas):
    return (sum(v25 for _c, _r, v25, _v24 in linhas), sum(v24 for _c, _r, _v25, v24 in linhas))


# ------------------------------------------------------------- PATRIMONIAL --
def folhas_patrimoniais():
    """(codigo, rotulo, grupo, base_reais) na ordem do plano."""
    saida = []
    for grupo, _rot, folhas in D.PLANO_PATRIMONIAL:
        for i, (rot, base) in enumerate(folhas, 1):
            saida.append((f"{grupo}.{i:03d}", rot, grupo, base))
    return saida


def _eh_ativo(cod):
    return cod.startswith("1")


def _valor_mensal(cod, rot, base, t):
    """Saldo da folha no instante t (0 = jan/2025 … 11 = dez/2025, 12..19 =
    jan..ago/2026), em centavos, com sinal NATURAL do documento: ativo positivo,
    redutora do ativo negativa, passivo positivo."""
    if rot.startswith("(-) Depreciação") or rot.startswith("(-) Amortização"):
        # redutora cresce em módulo todo mês: ~1% do saldo ao mês
        return -cent(abs(base) * (1 + 0.012 * t))
    if rot in ("Terrenos", "Marcas e patentes", "Quotas de cooperativa de crédito", "Imóveis para renda",
               "Reserva legal", "Ajuste de avaliação patrimonial", "Direito de concessão de revenda"):
        return cent(base)  # não se mexe: o mesmo número nos 12 meses
    if base == 0:
        # conta movimento dos bancos secundários: saldo pequeno e volátil
        return cent(ruido(f"cm|{rot}|{t}", 25_000, 160_000))
    tendencia = 1 + 0.004 * t
    return int(round(cent(base) * tendencia * ruido(f"p|{cod}|{t}", 0.90, 1.10)))


PERFIL_RESULTADO_2025 = [0.04, 0.10, 0.24, 0.36, 0.45, 0.52, 0.60, 0.70, 0.78, 0.85, 0.93, 1.0]


def balanco_2025(resultado_2025):
    """{codigo: [12 saldos]} das folhas, dez/2025 carregando o resultado do ano.

    A conta movimento do Banco Meridional é a ÚNICA que fecha: em cada mês ela
    é Passivo + PL − (demais ativos). Assert de que ela fica positiva — caixa
    negativo no balanço seria um book incoerente, não uma armadilha."""
    folhas = folhas_patrimoniais()
    bal = {}
    for cod, rot, _g, base in folhas:
        meses = []
        for t in range(12):
            if rot == "Capital social subscrito e integralizado":
                v = cent(D.CAPITAL_SOCIAL)
            elif rot == "Lucros ou prejuízos acumulados":
                v = cent(D.LUCROS_ACUMULADOS_INICIO_2025)
            elif rot == "Resultado do exercício":
                v = int(round(resultado_2025 * PERFIL_RESULTADO_2025[t])) if t < 11 else resultado_2025
            elif rot == "Dividendos a pagar":
                v = 0
            elif rot == D.CONTA_QUE_FECHA:
                v = None
            else:
                v = _valor_mensal(cod, rot, base, t)
            meses.append(v)
        bal[cod] = meses
    cod_fecha = next(c for c, r, _g, _b in folhas if r == D.CONTA_QUE_FECHA)
    for t in range(12):
        ativo = sum(bal[c][t] for c, *_ in folhas if _eh_ativo(c) and c != cod_fecha)
        passivo_pl = sum(bal[c][t] for c, *_ in folhas if not _eh_ativo(c))
        bal[cod_fecha][t] = passivo_pl - ativo
        assert bal[cod_fecha][t] > 0, f"caixa negativo no mês {t + 1}: {bal[cod_fecha][t]}"
    for t in range(12):
        a = sum(bal[c][t] for c, *_ in folhas if _eh_ativo(c))
        p = sum(bal[c][t] for c, *_ in folhas if not _eh_ativo(c))
        assert a == p, f"balanço não fecha no mês {t + 1}: {a} x {p}"
    return bal


def total_grupo(saldos, prefixo, t):
    return sum(v[t] for c, v in saldos.items() if c == prefixo or c.startswith(prefixo + "."))


# --------------------------------------------------------------- BALANCETE --
def balancete_2026(bal25, res26):
    """{codigo: (saldo_anterior, debito, credito, saldo_atual)} das folhas,
    SALDOS COM SINAL DEVEDOR POSITIVO (credor negativo) — o documento imprime em
    módulo com D/C ou com sinal; o sinal aqui é só a convenção da conta.

    Saldo anterior = dezembro/2025 DEPOIS do encerramento: o resultado do
    exercício vai para lucros acumulados e a conta de resultado do exercício
    abre o ano zerada. Contas de resultado (3 e 4) abrem em zero."""
    folhas_p = folhas_patrimoniais()
    cod_fecha = next(c for c, r, _g, _b in folhas_p if r == D.CONTA_QUE_FECHA)
    cod_la = next(c for c, r, _g, _b in folhas_p if r == "Lucros ou prejuízos acumulados")
    cod_re = next(c for c, r, _g, _b in folhas_p if r == "Resultado do exercício")

    def devedor(cod, v):  # sinal natural do balanço → devedor positivo
        return v if _eh_ativo(cod) else -v

    ant = {c: devedor(c, bal25[c][11]) for c, *_ in folhas_p}
    ant[cod_la] += ant[cod_re]  # encerramento: resultado → lucros acumulados
    ant[cod_re] = 0
    for c in res26:
        ant[c] = 0
    assert sum(ant.values()) == 0, "saldo anterior do balancete não fecha"

    atual = {}
    for cod, rot, _g, base in folhas_p:
        if cod in (cod_fecha,):
            continue
        if rot in ("Capital social subscrito e integralizado", "Reserva legal", "Reserva de lucros",
                   "Ajuste de avaliação patrimonial", "Lucros ou prejuízos acumulados",
                   "Resultado do exercício", "Terrenos", "Marcas e patentes",
                   "Quotas de cooperativa de crédito", "Imóveis para renda",
                   "Direito de concessão de revenda", "Dividendos a pagar"):
            atual[cod] = ant[cod]
        else:
            atual[cod] = devedor(cod, _valor_mensal(cod, rot, base, 19))
    for cod, c in res26.items():
        atual[cod] = -c["acum"]  # receita (+ na DRE) é saldo CREDOR
    atual[cod_fecha] = -sum(atual.values())
    assert atual[cod_fecha] > 0, f"conta movimento negativa em ago/2026: {atual[cod_fecha]}"
    assert sum(atual.values()) == 0, "saldo atual do balancete não fecha"

    linhas = {}
    for cod in list(ant):
        delta = atual[cod] - ant[cod]
        if cod in res26:
            # resultado: o giro é o estorno do período (pequeno, às vezes zero)
            giro = cent(abs(res26[cod]["acum"]) / 100 * ruido(f"giro|{cod}", 0, 0.04)) \
                if ruido(f"temgiro|{cod}") < 0.6 else 0
        elif delta == 0 and atual[cod] == ant[cod] and cod not in (cod_fecha,):
            giro = 0  # conta parada no período: débito e crédito zerados
        else:
            giro = int(round(abs(ant[cod] or atual[cod]) * ruido(f"giro|{cod}", 0.6, 3.2)))
        deb = max(delta, 0) + giro
        cre = max(-delta, 0) + giro
        assert ant[cod] + deb - cre == atual[cod], cod
        linhas[cod] = (ant[cod], deb, cre, atual[cod])
    tot_d = sum(v[1] for v in linhas.values())
    tot_c = sum(v[2] for v in linhas.values())
    assert tot_d == tot_c, f"balancete: débitos {tot_d} ≠ créditos {tot_c}"
    return linhas


# -------------------------------------------------------- BALANÇO 2 COLUNAS --
# Segunda empresa do grupo. Quatro tranches IGUAIS de um mesmo contrato
# sindicalizado aparecem como quatro linhas com o MESMO rótulo e o MESMO valor
# — o arranjo real que a guarda de "padrão típico de fabricação" acusou.
TRANCHE_LP = {2025: 329_166_667, 2024: 383_680_556}  # centavos: R$ 3.291.666,67 e 3.836.805,56
CREDORES_LP = ["Banco Meridional S.A. — CCB 2023/0418", "Banco do Planalto S.A. — CCB 77.120",
               "Coop. de Crédito Vale do Espelho — CCB 5.031", "Banco Austral S.A. — CCB 2023-118"]

PLANO_IMPLEMENTOS = [
    ("ATIVO CIRCULANTE", [
        ("Disponível", [("Caixa", 12_000), ("Bancos conta movimento", None),
                        ("Aplicações financeiras", 640_000)]),
        ("Clientes", [("Duplicatas a receber", 5_600_000), ("Cartões a receber", 85_000),
                      ("(-) Perdas estimadas com créditos", -160_000)]),
        ("Estoques", [("Implementos acabados", 2_700_000), ("Matéria-prima - aço", 1_350_000),
                      ("Componentes comprados", 880_000), ("Produtos em elaboração", 520_000),
                      ("Peças para revenda", 610_000), ("(-) Provisão para obsolescência", -95_000)]),
        ("Tributos a recuperar", [("ICMS a recuperar", 410_000), ("IPI a recuperar", 96_000),
                                  ("PIS e COFINS a recuperar", 233_000), ("IRPJ e CSLL a compensar", 71_000)]),
        ("Outros créditos", [("Adiantamentos a fornecedores", 190_000), ("Despesas antecipadas", 44_000),
                             ("Adiantamentos a empregados", 18_000)]),
    ]),
    ("ATIVO NÃO CIRCULANTE", [
        ("Realizável a longo prazo", [("Depósitos judiciais", 210_000),
                                      ("Créditos tributários", 380_000)]),
        ("Investimentos", [("Participação em cooperativa", 52_000)]),
        ("Imobilizado", [("Terrenos", 1_100_000), ("Edificações industriais", 9_500_000),
                         ("Máquinas e equipamentos industriais", 13_500_000),
                         ("Veículos", 540_000), ("Móveis e utensílios", 160_000),
                         ("(-) Depreciação acumulada", -5_200_000)]),
        ("Intangível", [("Softwares e projetos", 260_000), ("(-) Amortização acumulada", -140_000)]),
    ]),
    ("PASSIVO CIRCULANTE", [
        ("Fornecedores", [("Fornecedores de aço", 1_750_000), ("Fornecedores de componentes", 820_000),
                          ("Fornecedores de serviços", 140_000)]),
        ("Empréstimos e financiamentos", [("Capital de giro", 1_900_000), ("FINAME - curto prazo", 760_000),
                                          ("Parcela de curto prazo das CCBs", 1_250_000)]),
        ("Obrigações trabalhistas", [("Salários a pagar", 310_000), ("Provisão de férias e 13º", 420_000),
                                     ("Encargos sociais a recolher", 160_000)]),
        ("Obrigações tributárias", [("ICMS a recolher", 120_000), ("IPI a recolher", 38_000),
                                    ("PIS e COFINS a recolher", 74_000), ("Parcelamentos - curto prazo", 96_000)]),
        ("Outras obrigações", [("Adiantamentos de clientes", 480_000), ("Contas a pagar", 65_000)]),
    ]),
    ("PASSIVO NÃO CIRCULANTE", [
        ("Empréstimos e financiamentos", "TRANCHES"),
        ("Outras obrigações de longo prazo", [("FINAME - longo prazo", 1_600_000),
                                              ("Parcelamentos - longo prazo", 410_000),
                                              ("Provisão para contingências", 230_000)]),
    ]),
    ("PATRIMÔNIO LÍQUIDO", [
        ("Capital e reservas", [("Capital social", 3_000_000), ("Reserva legal", 410_000),
                                ("Reservas de lucros", None)]),
    ]),
]


def balanco_implementos():
    """{ano: [(secao, subgrupo, rotulo, centavos)]}, fechado por 'Reservas de lucros'
    (o PL absorve) e com caixa como segunda conta que fecha se o PL sair absurdo.

    Fecha pelo PL de propósito: os passivos (inclusive as quatro tranches) são
    o dado, e o que sobra é patrimônio — é o único arranjo em que a tranche LP
    não precisa ser ajustada para o balanço fechar, e ela tem de ficar IGUAL."""
    out = {}
    for ano in (2025, 2024):
        linhas = []
        for secao, subgrupos in PLANO_IMPLEMENTOS:
            for sub, folhas in subgrupos:
                if folhas == "TRANCHES":
                    for credor in CREDORES_LP:
                        linhas.append((secao, sub, "EMPRÉSTIMOS E FINANCIAMENTOS - LP", TRANCHE_LP[ano], credor))
                    continue
                for rot, base in folhas:
                    if base is None:
                        v = None
                    elif rot in ("Terrenos", "Capital social", "Reserva legal"):
                        v = cent(base)
                    else:
                        f = 1.0 if ano == 2025 else ruido(f"imp24|{rot}", 0.92, 1.05)
                        v = int(round(cent(base) * f * ruido(f"imp|{rot}", 0.93, 1.07)))
                        if ano == 2024 and base < 0:
                            v = int(round(v * 0.88))
                    linhas.append((secao, sub, rot, v, None))
        # caixa = 3% das demais contas do ativo circulante (decisão de forma, não de fechamento)
        ac = sum(v for s, _sb, _r, v, _c in linhas if s == "ATIVO CIRCULANTE" and v is not None)
        linhas = [(s, sb, r, (int(round(ac * 0.03)) if r == "Bancos conta movimento" else v), c)
                  for s, sb, r, v, c in linhas]
        ativo = sum(v for s, _sb, _r, v, _c in linhas if s.startswith("ATIVO") and v is not None)
        passivo = sum(v for s, _sb, _r, v, _c in linhas if not s.startswith("ATIVO") and v is not None)
        linhas = [(s, sb, r, (ativo - passivo if r == "Reservas de lucros" else v), c)
                  for s, sb, r, v, c in linhas]
        a = sum(v for s, _sb, _r, v, _c in linhas if s.startswith("ATIVO"))
        p = sum(v for s, _sb, _r, v, _c in linhas if not s.startswith("ATIVO"))
        assert a == p, f"implementos {ano} não fecha"
        assert next(v for _s, _sb, r, v, _c in linhas if r == "Reservas de lucros") > 0, \
            "reserva de lucros negativa"
        tranches = [v for _s, _sb, r, v, _c in linhas if r == "EMPRÉSTIMOS E FINANCIAMENTOS - LP"]
        assert len(tranches) == 4 and len(set(tranches)) == 1, "as quatro tranches têm de ser IGUAIS"
        out[ano] = linhas
    return out


# --------------------------------------------------------- ANEXOS (.xlsx) ----
def _reparte(total, chaves, lo=0.3, hi=1.7):
    """Reparte `total` (centavos) entre as chaves com pesos determinísticos; a
    última absorve o arredondamento — a soma fecha no centavo por construção."""
    pesos = [ruido(f"rep|{k}", lo, hi) for k in chaves]
    s = sum(pesos)
    partes = [int(total * p / s) for p in pesos[:-1]]
    partes.append(total - sum(partes))
    assert sum(partes) == total
    return partes


def extrato_agosto(balancete, conta_rotulo="Banco do Planalto S.A. - conta movimento"):
    """Extrato de agosto/2026 da conta, saldo final = saldo atual do balancete."""
    folhas = {r: c for c, r, _g, _b in folhas_patrimoniais()}
    saldo_final = balancete[folhas[conta_rotulo]][3]
    historicos = [
        ("PIX RECEBIDO", 1), ("TED RECEBIDA", 1), ("LIQUIDAÇÃO DE COBRANÇA", 1),
        ("DEP CHEQUE", 1), ("PAGTO FORNECEDOR", -1), ("PAGTO TITULO", -1), ("TARIFA PACOTE SERVIÇOS", -1),
        ("TRANSF ENTRE CONTAS", -1), ("DARF", -1), ("GPS/INSS", -1), ("FGTS GRRF", -1),
        ("PAGTO SALÁRIOS", -1), ("IOF", -1), ("RESGATE APLICAÇÃO", 1), ("APLICAÇÃO AUTOMÁTICA", -1),
        ("CRÉDITO CARTÕES", 1), ("ESTORNO TARIFA", 1),
    ]
    movs = []
    for i in range(132):
        dia = 1 + (i * 31) // 132
        hist, sinal = historicos[int(ruido(f"ext|h|{i}") * len(historicos))]
        if hist.startswith("TARIFA") or hist in ("IOF", "ESTORNO TARIFA"):
            v = cent(ruido(f"ext|v|{i}", 8, 480))
        else:
            v = cent(ruido(f"ext|v|{i}", 900, 185_000))
        doc = f"{int(ruido(f'ext|d|{i}', 100000, 999999))}"
        movs.append((f"{min(dia, 31):02d}/08/2026", hist, doc, sinal * v))
    saldo_inicial = saldo_final - sum(m[3] for m in movs)
    saldo = saldo_inicial
    linhas = []
    for data, hist, doc, v in movs:
        saldo += v
        linhas.append((data, hist, doc, v, saldo))
    assert saldo == saldo_final
    return saldo_inicial, linhas, saldo_final


def mapa_divida(balancete):
    """Contratos cujo saldo CP + LP soma, no centavo, as folhas de empréstimos
    (2.01.02 e 2.02.01) do balancete de agosto/2026."""
    f = {r: c for c, r, _g, _b in folhas_patrimoniais()}

    def s(r):  # saldo credor → positivo
        return -balancete[f[r]][3]

    contratos = [
        # (credor, modalidade, contrato, taxa, vencimento, rotulo_cp, rotulo_lp, n_sub)
        ("Banco Meridional S.A.", "Capital de giro", "CG 40.118-2", "CDI + 4,10% a.a.", "15/03/2029",
         "Capital de giro - Banco Meridional", "Capital de giro LP - Banco Meridional", 1),
        ("Banco do Planalto S.A.", "Capital de giro", "CG-77.120/2024", "CDI + 3,85% a.a.", "10/11/2028",
         "Capital de giro - Banco do Planalto", "Capital de giro LP - Banco do Planalto", 1),
        ("Coop. de Crédito Vale do Espelho", "Capital de giro", "5.031/2025", "CDI + 3,20% a.a.", "05/06/2029",
         "Capital de giro - Coop. Vale do Espelho", "Capital de giro LP - Coop. Vale do Espelho", 1),
        ("Montadora (floor plan)", "Floor plan", "FP-2026", "1,35% a.m.", "rotativo",
         "Floor plan - montadora", None, 1),
        ("Banco Meridional S.A.", "FINAME", "FINAME", "TLP + 3,50% a.a.", "diversos",
         "FINAME - parcelas de curto prazo", "FINAME - longo prazo", 6),
        ("Banco Austral S.A.", "Conta garantida", "CGAR 2026-04", "CDI + 6,00% a.a.", "30/11/2026",
         "Conta garantida - Banco Austral", None, 1),
        ("Banco do Planalto S.A.", "Antecipação de recebíveis", "ANT-2026", "1,48% a.m.", "rotativo",
         "Antecipação de recebíveis", None, 1),
        ("Banco Austral S.A.", "Cédula de crédito bancário", "CCB 2025-311", "CDI + 4,50% a.a.", "20/08/2030",
         "Cédula de crédito bancário - curto prazo", "Cédula de crédito bancário - longo prazo", 1),
    ]
    linhas = []
    for credor, mod, ctr, taxa, venc, r_cp, r_lp, n in contratos:
        cp = s(r_cp)
        lp = s(r_lp) if r_lp else 0
        if n == 1:
            linhas.append((credor, mod, ctr, taxa, venc, cp, lp))
        else:
            chaves = [f"{ctr}-{i}" for i in range(n)]
            cps = _reparte(cp, chaves)
            lps = _reparte(lp, [k + "lp" for k in chaves]) if lp else [0] * n
            for i in range(n):
                venc_i = f"15/{(i * 2) % 12 + 1:02d}/{2028 + i % 4}"
                linhas.append((credor, mod, f"{ctr} {41_200 + 37 * i}", taxa, venc_i, cps[i], lps[i]))
    total_bal = sum(-balancete[c][3] for c in balancete if c.startswith("2.01.02.") or c.startswith("2.02.01."))
    assert sum(l[5] + l[6] for l in linhas) == total_bal, "mapa de dívida não fecha com o balancete"
    return linhas, total_bal


ITENS_ESTOQUE = {
    "Peças - filtros e lubrificantes": ["FILTRO DE ÓLEO MOTOR 4 CIL", "FILTRO DE AR PRIMÁRIO", "FILTRO DE AR SECUNDÁRIO",
                                        "FILTRO DE COMBUSTÍVEL", "FILTRO HIDRÁULICO", "ÓLEO MOTOR 15W40 20L",
                                        "ÓLEO TRANSMISSÃO 20L", "GRAXA EP2 20KG", "ARLA 32 20L", "FLUIDO DE FREIO 1L",
                                        "ÓLEO HIDRÁULICO 68 20L", "FILTRO SEPARADOR DE ÁGUA"],
    "Peças - pneus": ["PNEU 18.4-34 R1", "PNEU 14.9-24 R1", "PNEU 7.50-16 F2", "CÂMARA 18.4-34", "PNEU 23.1-30 R1",
                      "PNEU 600/65R38", "PNEU 480/70R28", "PNEU 30.5L-32 R1"],
    "Peças - motor e transmissão": ["JOGO DE JUNTAS MOTOR", "PISTÃO STD", "BRONZINA DE BIELA", "BOMBA D'ÁGUA",
                                    "TURBINA COMPLETA", "EMBREAGEM COMPLETA", "DISCO DE EMBREAGEM", "CRUZETA CARDAN",
                                    "ENGRENAGEM PLANETÁRIA", "RETENTOR VIRABREQUIM", "BICO INJETOR",
                                    "BOMBA INJETORA RECOND", "RADIADOR", "CORREIA DO ALTERNADOR"],
    "Peças - hidráulica": ["BOMBA HIDRÁULICA", "CILINDRO HIDRÁULICO 3\"", "MANGUEIRA 1/2 PRENSADA",
                           "VÁLVULA DE CONTROLE REMOTO", "ENGATE RÁPIDO", "KIT REPARO CILINDRO", "COMANDO HIDRÁULICO",
                           "VÁLVULA DE ALÍVIO", "FILTRO DE SUCÇÃO"],
    "Peças - elétrica e eletrônica": ["ALTERNADOR 12V", "MOTOR DE PARTIDA", "BATERIA 150AH", "MONITOR DE PLANTIO",
                                      "SENSOR DE ROTAÇÃO", "CHICOTE PRINCIPAL", "FAROL DE TRABALHO LED", "RELÉ AUXILIAR",
                                      "ANTENA GNSS", "CONTROLADORA DE TAXA"],
    "Peças - desgaste e acessórios": ["DISCO DE CORTE PLANTADEIRA", "PONTEIRA SUBSOLADOR", "FACA ROÇADEIRA",
                                      "DISCO DE GRADE 28\"", "ROLAMENTO 6205 2RS", "ROLAMENTO 6308 ZZ", "BICO PULVERIZADOR",
                                      "MOLA DE TENSÃO", "BANCO DO OPERADOR", "TAPETE DE CABINE", "ESPELHO RETROVISOR",
                                      "CORRENTE DE ROLOS", "RODA COMPACTADORA"],
}


def estoque_pecas(balancete):
    """Itens de estoque de peças com o CÓDIGO COLADO na descrição. A soma do
    valor por item fecha, no centavo, as seis folhas 'Peças - …' do balancete."""
    f = {r: c for c, r, _g, _b in folhas_patrimoniais()}
    linhas = []
    for conta, itens in ITENS_ESTOQUE.items():
        total = balancete[f[conta]][3]
        partes = _reparte(total, [f"{conta}|{x}" for x in itens], 0.2, 2.5)
        for i, (desc, valor) in enumerate(zip(itens, partes)):
            codigo = int(ruido(f"cod|{desc}", 100, 99_999))
            # O RÓTULO COLADO, nas três formas que exportação de ERP produz:
            # "10234-DESC", "10234 - DESC" e "849DESC" (sem separador nenhum).
            forma = int(ruido(f"forma|{desc}") * 3)
            rotulo = [f"{codigo}-{desc}", f"{codigo} - {desc}", f"{codigo}{desc}"][forma]
            unid = "BD" if desc.startswith(("ÓLEO", "GRAXA", "ARLA", "FLUIDO")) else "UN"
            qtd = max(1, int(ruido(f"qtd|{desc}", 2, 140)))
            linhas.append((conta, rotulo, unid, qtd, valor))
    tot = sum(l[4] for l in linhas)
    tot_bal = sum(balancete[f[c]][3] for c in ITENS_ESTOQUE)
    assert tot == tot_bal, "estoque não fecha com o balancete"
    return linhas, tot


def contingencias(balancete):
    """Processos com prognóstico; só o PROVÁVEL está provisionado, e a soma do
    provável por natureza fecha as três folhas de provisão do balancete."""
    f = {r: c for c, r, _g, _b in folhas_patrimoniais()}
    naturezas = [("Trabalhista", "Provisão para contingências trabalhistas", 34, "5.04"),
                 ("Cível", "Provisão para contingências cíveis", 14, "8.21"),
                 ("Tributária", "Provisão para contingências tributárias", 12, "4.04")]
    linhas = []
    for nat, conta, n, seg in naturezas:
        provisao = -balancete[f[conta]][3]
        progn = []
        for i in range(n):
            h = ruido(f"prog|{nat}|{i}")
            progn.append("Provável" if h < 0.40 else ("Possível" if h < 0.80 else "Remoto"))
        provaveis = [i for i, p in enumerate(progn) if p == "Provável"]
        partes = _reparte(provisao, [f"{nat}|{i}" for i in provaveis])
        prov_de = dict(zip(provaveis, partes))
        for i in range(n):
            seq = int(ruido(f"cnj|{nat}|{i}", 1_000, 9_999_999))
            ano = 2019 + int(ruido(f"cnja|{nat}|{i}") * 7)
            dv = int(ruido(f"cnjd|{nat}|{i}", 10, 99))
            numero = f"{seq:07d}-{dv}.{ano}.{seg}.{int(ruido(f'or|{nat}|{i}', 1, 999)):04d}"
            if i in prov_de:
                causa = int(round(prov_de[i] * ruido(f"causa|{nat}|{i}", 1.2, 2.6)))
                prov = prov_de[i]
            else:
                causa = cent(ruido(f"causa|{nat}|{i}", 8_000, 640_000))
                prov = 0
            linhas.append((numero, nat, progn[i], causa, prov))
    for nat, conta, _n, _s in naturezas:
        assert sum(l[4] for l in linhas if l[1] == nat) == -balancete[f[conta]][3], nat
    return linhas


# ---------------------------------------------------------------- CONSTRUIR --
def construir():
    res26 = resultado_2026()
    sint = dre_sintetica()
    r25, r24 = resultado_sintetica(sint)
    bal25 = balanco_2025(r25)
    bcte = balancete_2026(bal25, res26)
    # amarração cruzada: o saldo atual das contas de resultado é o acumulado da DRE
    for cod, c in res26.items():
        assert bcte[cod][3] == -c["acum"], cod
    # e o resultado do balanço de dezembro é o da DRE sintética de 2025
    cod_re = next(c for c, r, *_ in folhas_patrimoniais() if r == "Resultado do exercício")
    assert bal25[cod_re][11] == r25
    return {"res26": res26, "sint": sint, "r25": r25, "r24": r24, "bal25": bal25, "bcte": bcte,
            "impl": balanco_implementos()}


if __name__ == "__main__":
    M = construir()
    _m, lucro = lucro_2026(M["res26"])
    print("folhas de resultado:", len(M["res26"]), "| folhas patrimoniais:", len(folhas_patrimoniais()))
    print("lucro jan–ago/2026 (R$):", lucro / 100)
    print("resultado 2025 / 2024 (R$):", M["r25"] / 100, M["r24"] / 100)
    cf = next(c for c, r, *_ in folhas_patrimoniais() if r == D.CONTA_QUE_FECHA)
    print("conta que fecha, jan..dez/2025 (R$):", [v / 100 for v in M["bal25"][cf]])
    print("conta que fecha, ago/2026 (R$):", M["bcte"][cf][3] / 100)
