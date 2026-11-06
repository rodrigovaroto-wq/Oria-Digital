# -*- coding: utf-8 -*-
"""As LINHAS de cada documento do book ESPELHO, em centavos, prontas para o render.

Cada função devolve a tabela como o documento a imprime (ordem, nível, total),
com os números ainda inteiros — quem decide parêntese, sinal, D/C e célula vazia
é `render.py`. Cada total impresso é conferido aqui contra a fonte do `motor.py`.

Linha = dict(cod, rot, vals, nivel, tipo) onde `tipo` é "folha", "grupo",
"sintetica" ou "calculada" (as linhas "=" da cascata da DRE).
"""

import dados as D
import motor as M


def _soma_vals(linhas, n):
    tot = [0] * n
    for l in linhas:
        for i, v in enumerate(l["vals"]):
            tot[i] += v or 0
    return tot


# ------------------------------------------------------------ DRE ANALÍTICA --
def dre_analitica(res26):
    """DRE mensal jan–ago/2026 + Acumulado, em cascata, ~440 linhas.

    Colunas: 8 meses + acumulado. Folha com mês sem movimento leva `None`
    (célula vazia); linha sintética soma o que há (vazio conta zero)."""
    n = M.N_MESES_2026
    folhas = {}
    for cod, c in res26.items():
        folhas.setdefault(c["grupo"], []).append(
            {"cod": cod, "rot": c["rotulo"], "vals": c["meses"] + [c["acum"]], "nivel": 3, "tipo": "folha"})

    def bloco_grupo(grupo):
        rot = next(r for g, r, _f in D.PLANO_RESULTADO if g == grupo)
        fs = folhas[grupo]
        tot = _soma_vals(fs, n + 1)
        return [{"cod": grupo, "rot": rot, "vals": tot, "nivel": 2, "tipo": "grupo"}] + fs, tot

    def bloco_n2(prefixo):
        grupos = [g for g, _r, _f in D.PLANO_RESULTADO if g.startswith(prefixo + ".")]
        if len(grupos) == 1:
            return bloco_grupo(grupos[0])
        corpo, tot = [], [0] * (n + 1)
        for g in grupos:
            b, t = bloco_grupo(g)
            corpo += b
            tot = [a + x for a, x in zip(tot, t)]
        cab = {"cod": prefixo, "rot": D.SINTETICAS_RESULTADO[prefixo], "vals": tot, "nivel": 1, "tipo": "sintetica"}
        return [cab] + corpo, tot

    def calc(rot, vals):
        return {"cod": "", "rot": rot, "vals": vals, "nivel": 0, "tipo": "calculada"}

    def mais(*ts):
        return [sum(x) for x in zip(*ts)]

    linhas = []
    b, rb = bloco_n2("3.01"); linhas += b
    b, ded = bloco_n2("4.01"); linhas += b
    rl = mais(rb, ded); linhas.append(calc("= RECEITA OPERACIONAL LÍQUIDA", rl))
    b, cmv = bloco_n2("4.02"); linhas += b
    lb = mais(rl, cmv); linhas.append(calc("= LUCRO BRUTO", lb))
    ops = []
    for p in ("4.03", "4.04", "4.05", "4.06", "3.03", "4.08"):
        b, t = bloco_n2(p); linhas += b; ops.append(t)
    ro = mais(lb, *ops); linhas.append(calc("= RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO", ro))
    b, rf_r = bloco_n2("3.02"); linhas += b
    b, rf_d = bloco_n2("4.07"); linhas += b
    rf = mais(rf_r, rf_d); linhas.append(calc("= RESULTADO FINANCEIRO LÍQUIDO", rf))
    lair = mais(ro, rf); linhas.append(calc("= RESULTADO ANTES DO IRPJ E DA CSLL", lair))
    b, ir = bloco_n2("4.09"); linhas += b
    ll = mais(lair, ir); linhas.append(calc("= RESULTADO LÍQUIDO DO PERÍODO", ll))

    meses_lucro, lucro = M.lucro_2026(res26)
    assert ll == meses_lucro + [lucro], "DRE analítica não fecha com o motor"
    for l in linhas:  # acumulado = soma dos meses, em TODA linha impressa
        assert l["vals"][-1] == sum(v or 0 for v in l["vals"][:-1]), l["rot"]
    folhas_impressas = [l for l in linhas if l["tipo"] == "folha"]
    assert len(folhas_impressas) == len(res26)
    ancoras = {"receita_bruta": rb, "deducoes": ded, "receita_liquida": rl, "custo": cmv,
               "lucro_bruto": lb, "resultado_operacional": ro, "resultado_financeiro": rf,
               "lair": lair, "irpj_csll": ir, "resultado_liquido": ll}
    return linhas, ancoras


# ------------------------------------------------------------ DRE SINTÉTICA --
def dre_sintetica(sint):
    """DRE anual 2025 × 2024, ~95 linhas, a partir de `motor.dre_sintetica`."""
    por_cod = {c: (r, v25, v24) for c, r, v25, v24 in sint}

    def l(cod, nivel=2, tipo="folha", rot=None):
        r, v25, v24 = por_cod[cod]
        return {"cod": cod, "rot": rot or r, "vals": [v25, v24], "nivel": nivel, "tipo": tipo}

    def soma(prefixo):
        ks = [c for c in por_cod if c.startswith(prefixo)]
        return [sum(por_cod[k][1] for k in ks), sum(por_cod[k][2] for k in ks)]

    def calc(rot, vals, nivel=0):
        return {"cod": "", "rot": rot, "vals": vals, "nivel": nivel, "tipo": "calculada"}

    def mais(*ts):
        return [sum(x) for x in zip(*ts)]

    L = []
    rb = soma("3.01"); L.append(calc("RECEITA OPERACIONAL BRUTA", rb))
    for g, rot, _f in D.PLANO_RESULTADO:
        if g.startswith("3.01"):
            L.append(calc(rot.capitalize(), soma(g + "."), 1))
            L += [l(c, 2) for c in por_cod if c.startswith(g + ".")]
    ded = soma("4.01"); L.append(calc("(-) DEDUÇÕES DA RECEITA BRUTA", ded))
    L += [l(c, 1, rot=f"(-) {por_cod[c][0]}") for c in por_cod if c.startswith("4.01")]
    rl = mais(rb, ded); L.append(calc("= RECEITA OPERACIONAL LÍQUIDA", rl))
    cmv = soma("4.02"); L.append(calc("(-) CUSTO DAS VENDAS E DOS SERVIÇOS", cmv))
    L += [l(c, 1, rot=f"(-) {por_cod[c][0]}") for c in por_cod if c.startswith("4.02")]
    lb = mais(rl, cmv); L.append(calc("= LUCRO BRUTO", lb))
    pes, adm = soma("4.03"), soma("4.04")
    outras = [soma(p) for p in ("4.05", "4.06", "3.03", "4.08")]
    desp = mais(pes, adm, *outras); L.append(calc("(-) DESPESAS OPERACIONAIS", desp))
    L.append(calc("Despesas com pessoal", pes, 1))
    L += [l(c, 2) for c in por_cod if c.startswith("4.03")]
    L.append(calc("Despesas administrativas", adm, 1))
    L += [l(c, 2) for c in por_cod if c.startswith("4.04")]
    for p in ("4.05", "4.06", "3.03", "4.08"):
        L += [l(c, 1) for c in por_cod if c.startswith(p)]
    ro = mais(lb, desp); L.append(calc("= RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO", ro))
    rfr, rfd = soma("3.02"), soma("4.07")
    L.append(l("3.02.01", 1, rot="Receitas financeiras"))
    L.append(l("4.07.01", 1, rot="(-) Despesas financeiras"))
    rf = mais(rfr, rfd); L.append(calc("= RESULTADO FINANCEIRO LÍQUIDO", rf))
    lair = mais(ro, rf); L.append(calc("= RESULTADO ANTES DO IRPJ E DA CSLL", lair))
    ir = soma("4.09")
    L += [l(c, 1, rot=f"(-) {por_cod[c][0]}") for c in por_cod if c.startswith("4.09")]
    ll = mais(lair, ir); L.append(calc("= RESULTADO LÍQUIDO DO EXERCÍCIO", ll))

    r25, r24 = M.resultado_sintetica(sint)
    assert ll == [r25, r24], "DRE sintética não fecha"
    folhas = [x for x in L if x["tipo"] == "folha"]
    assert len(folhas) == len(sint), "linha da DRE sintética ficou de fora"
    return L, {"receita_bruta": rb, "receita_liquida": rl, "lucro_bruto": lb,
               "resultado_operacional": ro, "resultado_financeiro": rf, "resultado_liquido": ll}


# ----------------------------------------------- HIERARQUIA DO PLANO DE CONTAS --
def _rotulo_sintetico(cod):
    for dic in (D.SINTETICAS_PATRIMONIAL, D.SINTETICAS_RESULTADO):
        if cod in dic:
            return dic[cod]
    for g, r, _f in D.PLANO_PATRIMONIAL:
        if g == cod:
            return r
    for g, r, _f in D.PLANO_RESULTADO:
        if g == cod:
            return r
    raise KeyError(cod)


def _ancestrais(cod):
    p = cod.split(".")
    return [".".join(p[:i]) for i in range(1, len(p))]


def hierarquia(folhas_vals, ncols):
    """Monta a lista hierárquica (sintéticas + folhas) a partir de
    {codigo_folha: (rotulo, [valores])}, na ordem dos códigos. Sintética = soma
    das folhas abaixo dela."""
    linhas, vistos, somas = [], set(), {}
    for cod, (_rot, vals) in folhas_vals.items():
        for a in _ancestrais(cod):
            s = somas.setdefault(a, [0] * ncols)
            for i, v in enumerate(vals):
                s[i] += v or 0
    for cod, (rot, vals) in folhas_vals.items():
        for a in _ancestrais(cod):
            if a not in vistos:
                vistos.add(a)
                linhas.append({"cod": a, "rot": _rotulo_sintetico(a), "vals": somas[a],
                               "nivel": a.count("."), "tipo": "sintetica"})
        linhas.append({"cod": cod, "rot": rot, "vals": list(vals), "nivel": cod.count("."), "tipo": "folha"})
    return linhas


# --------------------------------------------------------------- BALANCETE ---
def balancete(bcte, res26):
    rot = {c: r for c, r, _g, _b in M.folhas_patrimoniais()}
    rot.update({c: v["rotulo"] for c, v in res26.items()})
    ordem = sorted(bcte, key=lambda c: [int(x) for x in c.split(".")])
    folhas_vals = {c: (rot[c], list(bcte[c])) for c in ordem}
    linhas = hierarquia(folhas_vals, 4)
    raiz = [l for l in linhas if l["nivel"] == 0]
    tot_d = sum(l["vals"][1] for l in raiz)
    tot_c = sum(l["vals"][2] for l in raiz)
    assert tot_d == tot_c, "balancete: débito ≠ crédito"
    assert sum(l["vals"][0] for l in raiz) == 0 and sum(l["vals"][3] for l in raiz) == 0
    return linhas, tot_d


# -------------------------------------------------------- BALANÇO MENSAL -----
def balanco_mensal(bal25):
    """178 linhas × 12 meses, sinal NATURAL (ativo e passivo positivos; redutora negativa)."""
    rot = {c: r for c, r, _g, _b in M.folhas_patrimoniais()}
    folhas_vals = {c: (rot[c], bal25[c]) for c in sorted(bal25, key=lambda c: [int(x) for x in c.split(".")])}
    linhas = hierarquia(folhas_vals, 12)
    ativo = next(l for l in linhas if l["cod"] == "1")["vals"]
    passivo = next(l for l in linhas if l["cod"] == "2")["vals"]
    assert ativo == passivo, "balanço mensal: ativo ≠ passivo + PL"
    return linhas


# ----------------------------------------------------- BALANÇO 2 COLUNAS ------
def balanco_implementos(impl):
    """~80 linhas: seção (com total), subgrupo (com total), folhas; nas tranches
    LP, uma linha de credor SEM valor antes de cada uma das quatro linhas iguais."""
    L = []
    for secao, subgrupos in M.PLANO_IMPLEMENTOS:
        def tot(filtro):
            return [sum(v for s, sb, _r, v, _c in impl[a] if filtro(s, sb)) for a in (2025, 2024)]
        L.append({"cod": "", "rot": secao, "vals": tot(lambda s, sb: s == secao), "nivel": 0, "tipo": "sintetica"})
        for sub, _f in subgrupos:
            L.append({"cod": "", "rot": sub, "vals": tot(lambda s, sb: s == secao and sb == sub),
                      "nivel": 1, "tipo": "grupo"})
            f25 = [x for x in impl[2025] if x[0] == secao and x[1] == sub]
            f24 = [x for x in impl[2024] if x[0] == secao and x[1] == sub]
            for a, b in zip(f25, f24):
                assert a[2] == b[2]
                if a[4]:
                    L.append({"cod": "", "rot": a[4], "vals": [None, None], "nivel": 2, "tipo": "credor"})
                L.append({"cod": "", "rot": a[2], "vals": [a[3], b[3]], "nivel": 2, "tipo": "folha"})
        if secao == "ATIVO NÃO CIRCULANTE":
            L.append({"cod": "", "rot": "TOTAL DO ATIVO",
                      "vals": [sum(z[3] for z in impl[a] if z[0].startswith("ATIVO")) for a in (2025, 2024)],
                      "nivel": 0, "tipo": "calculada"})
    passivo = [sum(z[3] for z in impl[a] if not z[0].startswith("ATIVO")) for a in (2025, 2024)]
    L.append({"cod": "", "rot": "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO", "vals": passivo, "nivel": 0,
              "tipo": "calculada"})
    ta = next(l for l in L if l["rot"] == "TOTAL DO ATIVO")["vals"]
    assert ta == passivo, "balanço implementos não fecha"
    return L
