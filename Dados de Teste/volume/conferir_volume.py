# -*- coding: utf-8 -*-
"""Confere as bases volumosas de `saida/` contra o book-distress, relendo os ARQUIVOS.

    cd "Dados de Teste"/volume && python3 conferir_volume.py              # todo GABARITO_*.json em saida/
    cd "Dados de Teste"/volume && python3 conferir_volume.py --linhas 3000

Não importa o `gerar_volume.py`, de propósito: se o conferidor usasse a memória
do gerador, um arquivo escrito errado passaria (o mesmo código errando dos dois
lados). As fontes de verdade são duas e independentes do arquivo:
  1. o book-distress (`demonstracoes.aging_ar`, `aging_ap`, `extrato`): o que o
     arquivo TEM de dizer;
  2. o próprio arquivo, contado linha a linha: o que ele DIZ.
O GABARITO_<n>.json é recalculado INTEIRO a partir do arquivo e comparado campo
a campo (a MB1, a MB3 e a MB5 vão usá-lo como verdade). Ele nunca é usado como
verdade sobre o book.

O .xlsx é lido pelo mesmo classificador do CSV: cada célula vira o texto que o
CSV teria (data dd/mm/aaaa, valor 1.234,56). Assim a planilha prova que diz o
mesmo que o CSV, e as conferências contra o book valem para as duas.

Sai com código 1 e a lista das falhas se qualquer conferência reprovar.
"""

import argparse
import datetime as dt
import glob
import json
import os
import re
import sys
import zipfile
import zlib
from decimal import Decimal, InvalidOperation
from xml.etree.ElementTree import iterparse

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(1, os.path.join(AQUI, "..", "book-distress"))  # antes do site-packages (há um `motor` no PyPI)

import demonstracoes as X  # noqa: E402
import motor as M  # noqa: E402
from caminhos import arquivo_seguro, pasta_segura  # noqa: E402

DATA_BASE = dt.date(2025, 12, 31)
ANO = 2025
STORAGE_TETO_BYTES = 52_428_800
FAIXAS_FINAS = [("a vencer", None, 0), ("1-30", 1, 30), ("31-60", 31, 60), ("61-90", 61, 90),
                ("91-180", 91, 180), ("181-360", 181, 360), (">360", 361, None)]
# O sinal pelo tipo da transação. XFER não diz o sentido: fica fora da regra.
SINAL_DO_TIPO = {"CREDIT": 1, "DEP": 1, "DEBIT": -1, "PAYMENT": -1, "FEE": -1}


def centavos(s):
    """'1.234,56' → 123456. Recusa o que não tiver exatamente esse formato."""
    if not re.fullmatch(r"\d{1,3}(\.\d{3})*,\d{2}", s):
        raise ValueError(f"valor fora do formato: {s!r}")
    return int(s.replace(".", "").replace(",", ""))


def br(cent):
    return f"{cent // 100:,}".replace(",", ".") + f",{cent % 100:02d}"


def data(s):
    return dt.datetime.strptime(s, "%d/%m/%Y").date() if s else None


def atraso(venc):
    return (DATA_BASE - venc).days


def faixa_do_book(venc):
    """A faixa do book pela DATA, não pelo rótulo que o gerador tinha na memória.
    Vence na data-base (atraso 0) = a vencer."""
    a = atraso(venc)
    if a <= 0:
        return 0
    return 1 if a <= 30 else 2 if a <= 60 else 3 if a <= 90 else 4


def faixa_fina(venc):
    a = atraso(venc)
    return next(n for n, lo, hi in FAIXAS_FINAS if (lo is None or a >= lo) and (hi is None or a <= hi))


def medir(caminho):
    """Mesma régua do gerador (gzip nível 6), refeita aqui para não importá-lo."""
    z = zlib.compressobj(6, zlib.DEFLATED, 31)
    comprimido = 0
    with open(caminho, "rb") as fh:
        for bloco in iter(lambda: fh.read(1 << 20), b""):
            comprimido += len(z.compress(bloco))
    comprimido += len(z.flush())
    bruto = os.path.getsize(caminho)
    return {"bytes": bruto, "bytes_gzip": comprimido, "cabe_no_storage": bruto <= STORAGE_TETO_BYTES,
            "cabe_no_storage_em_gzip": comprimido <= STORAGE_TETO_BYTES}


class Conferencia:
    def __init__(self):
        self.ok, self.falhas = 0, []

    def igual(self, nome, obtido, esperado):
        if obtido == esperado:
            self.ok += 1
        else:
            self.falhas.append(f"{nome}: obtido {obtido!r}, esperado {esperado!r}")

    def falha(self, nome, motivo):
        self.falhas.append(f"{nome}: {motivo}")

    def gabarito(self, p, gab, recalculado):
        """Campo a campo, para a falha dizer QUAL campo mente."""
        for k in sorted(set(gab) | set(recalculado)):
            self.igual(f"{p}: gabarito, {k}", gab.get(k), recalculado.get(k))


# ------------------------------------------------------------------ leitura --
def linhas_do_csv(caminho):
    """(índice, [células]) por linha física; linha vazia = []."""
    with open(caminho, encoding="cp1252", newline="") as fh:
        for n, linha in enumerate(fh):
            linha = linha.rstrip("\r\n")
            yield n, (linha.split(";") if linha else [])


def linhas_do_xlsx(caminho):
    """(índice, [células como o CSV as escreveria]) por linha da planilha, com as
    linhas AUSENTES do XML devolvidas como [] — elas existem para quem abre."""
    ns = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"  # NOSONAR(S5332)
    with zipfile.ZipFile(caminho) as z:
        sst = []
        if "xl/sharedStrings.xml" in z.namelist():
            with z.open("xl/sharedStrings.xml") as fh:
                for _ev, el in iterparse(fh):
                    if el.tag == ns + "si":
                        sst.append("".join(t.text or "" for t in el.iter(ns + "t")))
                        el.clear()
        anterior = 0
        with z.open("xl/worksheets/sheet1.xml") as fh:
            for _ev, el in iterparse(fh):
                if el.tag != ns + "row":
                    continue
                r = int(el.get("r"))
                for vazia in range(anterior + 1, r):
                    yield vazia - 1, []
                anterior = r
                cel = {}
                for c in el.iter(ns + "c"):
                    col = ord(re.match(r"[A-Z]", c.get("r")).group()) - ord("A")
                    v = c.find(ns + "v")
                    t, s = c.get("t"), c.get("s")
                    if t == "s":
                        cel[col] = sst[int(v.text)]
                    elif t == "inlineStr":
                        cel[col] = "".join(x.text or "" for x in c.iter(ns + "t"))
                    elif v is None:
                        continue
                    elif s == "1":
                        cel[col] = (dt.date(1899, 12, 30) + dt.timedelta(days=int(v.text))).strftime("%d/%m/%Y")
                    else:
                        try:
                            d = Decimal(v.text) * 100
                            cel[col] = br(int(d)) if d == d.to_integral_value() and d >= 0 else v.text
                        except InvalidOperation:
                            cel[col] = v.text
                el.clear()
                yield r - 1, [cel.get(i, "") for i in range(max(cel) + 1)] if cel else []


def classificar(linhas):
    """Toda linha tem destino. Devolve (destinos, títulos, linha TOTAL, nº de linhas)."""
    destinos = {"cabecalho_relatorio": 0, "em_branco": 0, "cabecalho_colunas": 0,
                "titulo": 0, "total": 0, "nao_reconhecida": 0}
    titulos, total, n_linhas = [], None, 0
    for n, c in linhas:
        n_linhas += 1
        if not any(c):
            destinos["em_branco"] += 1
        elif c[0] == "Código":
            destinos["cabecalho_colunas"] += 1
        elif c[0] == "TOTAL GERAL":
            destinos["total"] += 1
            total = (centavos(c[7]), centavos(c[8]), centavos(c[9]))
        elif n < 2 and sum(bool(x) for x in c) == 1:
            destinos["cabecalho_relatorio"] += 1
        elif len(c) == 12:
            try:
                titulos.append({"cod": c[0], "num": c[3], "parc": c[4], "emissao": data(c[5]),
                                "venc": data(c[6]), "orig": centavos(c[7]), "pago": centavos(c[8]),
                                "saldo": centavos(c[9]), "quando": data(c[10]), "sit": c[11]})
                destinos["titulo"] += 1
            except ValueError:
                destinos["nao_reconhecida"] += 1
        else:
            destinos["nao_reconhecida"] += 1
    return destinos, titulos, total, n_linhas


def situacao_esperada(t):
    if t["saldo"] == 0:
        return "LIQUIDADO"
    return "PARCIAL" if t["pago"] > 0 else "ABERTO"


# ---------------------------------------------------------------- conferência --
def conferir_aging(conf, papel, chave, formato, gab, saida):
    bp, _tot, _dre = M.construir()
    linhas, por_faixa, total_mil = (X.aging_ar if papel == "Cliente" else X.aging_ap)(bp, ANO)
    esperado_contraparte = {r.split(" - ", 1)[0]: st * 100_000 for r, _, st in linhas}

    g = gab[chave]
    meta = g[formato]
    # O nome é MONTADO aqui e o do gabarito é só conferido contra ele: abrir o arquivo pelo
    # nome lido do JSON deixava um gabarito adulterado ler fora da pasta (Sonar, S2083).
    nome = f"{chave}_{gab['linhas_pedidas']}.{formato}"
    if meta["arquivo"] != nome:
        conf.falha(f"{chave}.{formato}: gabarito, arquivo", f"o gabarito diz {meta['arquivo']!r}, o esperado é {nome!r}")
        return
    arq = arquivo_seguro(saida, nome)
    p = f"{chave}.{formato}"
    try:
        leitor = linhas_do_csv(arq) if formato == "csv" else linhas_do_xlsx(arq)
        destinos, titulos, total, n_linhas = classificar(leitor)
    # Arquivo ilegível é falha CONFERIDA (entra na lista), não exceção solta que derruba a conferência.
    except Exception as e:  # noqa: BLE001
        conf.falha(f"{p}: arquivo legível", f"{type(e).__name__}: {e}")
        return

    # O arquivo inteiro: toda linha tem destino, e nenhuma ficou sem reconhecer.
    if formato == "csv":
        with open(arq, "rb") as fh:
            fisicas = sum(b.count(b"\n") for b in iter(lambda: fh.read(1 << 20), b""))
        conf.igual(f"{p}: linhas lidas = linhas físicas do arquivo", n_linhas, fisicas)
    conf.igual(f"{p}: linhas com destino = linhas lidas", sum(destinos.values()), n_linhas)
    conf.igual(f"{p}: linhas não reconhecidas", destinos["nao_reconhecida"], 0)
    conf.igual(f"{p}: arquivo tem as linhas pedidas", n_linhas, gab["linhas_pedidas"])

    # Contra o BOOK: saldo total, por faixa (pela data) e por contraparte nomeada.
    abertos = [t for t in titulos if t["saldo"] > 0]
    saldo = sum(t["saldo"] for t in abertos)
    conf.igual(f"{p}: Σ saldo = BP × 100.000", saldo, total_mil * 100_000)
    faixas, finas, por_cp = [0] * 5, {n: 0 for n, _, _ in FAIXAS_FINAS}, {}
    for t in abertos:
        faixas[faixa_do_book(t["venc"])] += t["saldo"]
        finas[faixa_fina(t["venc"])] += t["saldo"]
        por_cp[t["cod"]] = por_cp.get(t["cod"], 0) + t["saldo"]
    conf.igual(f"{p}: saldo por faixa = aging do book", faixas, [v * 100_000 for v in por_faixa])
    conf.igual(f"{p}: saldo por contraparte = aging do book", por_cp,
               {k: v for k, v in esperado_contraparte.items() if v > 0})

    # Coerência de cada título.
    n = len(titulos)
    conf.igual(f"{p}: original = pago + saldo", sum(t["orig"] == t["pago"] + t["saldo"] for t in titulos), n)
    conf.igual(f"{p}: situação coerente com pago e saldo", sum(t["sit"] == situacao_esperada(t) for t in titulos), n)
    conf.igual(f"{p}: emissão até a data-base", sum(t["emissao"] > DATA_BASE for t in titulos), 0)
    conf.igual(f"{p}: emissão até o vencimento", sum(t["emissao"] > t["venc"] for t in titulos), 0)
    conf.igual(f"{p}: título + parcela único", len({(t["num"], t["parc"]) for t in titulos}), n)
    grupos = {}
    for t in titulos:
        i, de = (int(x) for x in t["parc"].split("/"))
        grupos.setdefault(t["num"], []).append((i, de, t["cod"]))
    incompletos = sum(sorted(i for i, _, _ in v) != list(range(1, v[0][1] + 1))
                      or len({de for _, de, _ in v}) != 1 or len({c for _, _, c in v}) != 1
                      for v in grupos.values())
    conf.igual(f"{p}: parcelas de cada título completas e da mesma contraparte", incompletos, 0)
    conf.igual(f"{p}: linha TOTAL GERAL = Σ das colunas", total,
               (sum(t["orig"] for t in titulos), sum(t["pago"] for t in titulos), saldo))

    # O GABARITO inteiro, recalculado do arquivo. O CSV responde pelo aging; o
    # .xlsx responde só pelos próprios metadados (o resto já foi conferido acima).
    if formato == "csv":
        top10 = sorted(por_cp.values(), reverse=True)[:10]
        recalculado = {
            "papel": papel,
            "linhas_por_destino": {k: v for k, v in destinos.items() if k != "nao_reconhecida"},
            "titulos": {"abertos": sum(t["sit"] == "ABERTO" for t in titulos),
                        "parciais": sum(t["sit"] == "PARCIAL" for t in titulos),
                        "liquidados": sum(t["sit"] == "LIQUIDADO" for t in titulos)},
            "titulos_distintos": len(grupos),
            "contrapartes_no_arquivo": len({t["cod"] for t in titulos}),
            "contrapartes_em_aberto": len(por_cp),
            "saldo_em_aberto_centavos": saldo,
            "bp_rs_mil": total_mil,
            "saldo_por_contraparte_centavos": dict(sorted(por_cp.items())),
            "saldo_por_faixa_fina_centavos": finas,
            "concentracao_top10": round(sum(top10) / saldo, 6) if saldo else None,
            "csv": {"arquivo": meta["arquivo"], "linhas_arquivo": fisicas, **medir(arq)},
        }
        if "xlsx" in g:
            recalculado["xlsx"] = g["xlsx"]  # conferido na passada do .xlsx
        conf.gabarito(p, g, recalculado)
    else:
        with zipfile.ZipFile(arq) as z, z.open("xl/sharedStrings.xml") as fh:
            unicas = sum(1 for _ev, el in iterparse(fh) if el.tag.endswith("}si"))
        conf.gabarito(p, meta, {"arquivo": meta["arquivo"], "linhas_planilha": n_linhas,
                                "strings_unicas": unicas, **medir(arq)})


def ler_ofx(caminho):
    """Lê o OFX SGML (tag folha sem fechamento) e devolve transações, saldo e período."""
    txs, atual, folhas = [], None, {}
    with open(caminho, encoding="cp1252", newline="") as fh:
        for linha in fh:
            linha = linha.strip()
            if linha == "<STMTTRN>":
                atual = {}
            elif linha == "</STMTTRN>":
                txs.append(atual)
                atual = None
            elif linha.startswith("<") and not linha.startswith("</"):
                tag, _, valor = linha[1:].partition(">")
                (atual if atual is not None else folhas)[tag] = valor
    return txs, folhas


def _cent_ofx(s):
    if not re.fullmatch(r"-?\d+\.\d{2}", s or ""):
        raise ValueError(f"valor OFX fora do formato: {s!r}")
    v = int(s.lstrip("-").replace(".", ""))
    return -v if s.startswith("-") else v


def conferir_ofx(conf, gab, saida):
    bp, _tot, _dre = M.construir()
    meses, ini, fim = X.extrato(bp, ANO)
    g = gab["extrato_ofx"]
    nome = f"extrato_{gab['linhas_pedidas']}.ofx"
    if g["arquivo"] != nome:
        conf.falha("extrato_ofx: gabarito, arquivo", f"o gabarito diz {g['arquivo']!r}, o esperado é {nome!r}")
        return
    arq = arquivo_seguro(saida, nome)
    p = "extrato_ofx"
    txs, folhas = ler_ofx(arq)

    cred, deb, nc, nd = [0] * 12, [0] * 12, [0] * 12, [0] * 12
    anos = set()
    for t in txs:
        v = _cent_ofx(t["TRNAMT"])
        anos.add(t["DTPOSTED"][:4])
        m = int(t["DTPOSTED"][4:6]) - 1
        if v > 0:
            cred[m] += v
            nc[m] += 1
        else:
            deb[m] += -v
            nd[m] += 1
    balamt = _cent_ofx(folhas.get("BALAMT"))
    conf.igual(f"{p}: transações todas de {ANO}", anos, {str(ANO)})
    conf.igual(f"{p}: período declarado (DTSTART, DTEND)",
               (folhas.get("DTSTART", "")[:8], folhas.get("DTEND", "")[:8]), (f"{ANO}0101", f"{ANO}1231"))
    conf.igual(f"{p}: créditos por mês = extrato do book", cred, [r[2] for r in meses])
    conf.igual(f"{p}: débitos por mês = extrato do book", deb, [r[3] for r in meses])
    conf.igual(f"{p}: LEDGERBAL = saldo final do book", balamt, fim)
    deduzido = balamt - sum(cred) + sum(deb)
    conf.igual(f"{p}: saldo inicial deduzido = caixa do BP de 2024", deduzido, ini)
    conf.igual(f"{p}: FITID único", len({t["FITID"] for t in txs}), len(txs))
    conf.igual(f"{p}: TRNTYPE coerente com o sinal (XFER fora da regra)",
               sum(SINAL_DO_TIPO.get(t["TRNTYPE"], 0) * _cent_ofx(t["TRNAMT"]) < 0 for t in txs), 0)
    conf.igual(f"{p}: TRNTYPE conhecido", {t["TRNTYPE"] for t in txs} - set(SINAL_DO_TIPO) - {"XFER"}, set())

    por_mes, saldo = [], deduzido
    for m in range(12):
        fim_m = saldo + cred[m] - deb[m]
        por_mes.append({"mes": f"{ANO}-{m + 1:02d}", "saldo_inicial": saldo, "creditos": cred[m],
                        "debitos": deb[m], "saldo_final": fim_m, "n_creditos": nc[m], "n_debitos": nd[m]})
        saldo = fim_m
    with open(arq, "rb") as fh:
        fisicas = sum(b.count(b"\n") for b in iter(lambda: fh.read(1 << 20), b""))
    conf.gabarito(p, g, {"arquivo": g["arquivo"], "linhas_arquivo": fisicas, **medir(arq),
                         "transacoes": len(txs), "saldo_inicial_centavos": deduzido,
                         "saldo_final_centavos": balamt, "por_mes": por_mes})


def conferir(n_linhas, saida):
    with open(arquivo_seguro(saida, f"GABARITO_{int(n_linhas)}.json"), encoding="utf-8") as fh:
        gab = json.load(fh)
    conf = Conferencia()
    conferir_aging(conf, "Cliente", "contas_a_receber", "csv", gab, saida)
    if "xlsx" in gab["contas_a_receber"]:
        conferir_aging(conf, "Cliente", "contas_a_receber", "xlsx", gab, saida)
    else:
        conf.falha("contas_a_receber.xlsx", "o gabarito não declara o .xlsx (gerado com --sem-xlsx?)")
    conferir_aging(conf, "Fornecedor", "contas_a_pagar", "csv", gab, saida)
    conferir_ofx(conf, gab, saida)
    return conf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--linhas", type=int, action="append")
    ap.add_argument("--saida", default=os.path.join(AQUI, "saida"))
    a = ap.parse_args()
    a.saida = pasta_segura(a.saida)
    tamanhos = a.linhas or sorted(int(re.search(r"_(\d+)\.json$", f).group(1))
                                  for f in glob.glob(os.path.join(a.saida, "GABARITO_*.json")))
    if not tamanhos:
        print("NADA A CONFERIR: nenhum GABARITO_*.json em", a.saida, "(rode o gerar_volume.py antes)")
        sys.exit(1)
    falhou = False
    for n in tamanhos:
        conf = conferir(n, a.saida)
        print(f"{n:>9} linhas: {conf.ok} conferências ok, {len(conf.falhas)} falhas")
        for f in conf.falhas:
            print("   FALHA", f[:300])
        falhou |= bool(conf.falhas)
    sys.exit(1 if falhou else 0)


if __name__ == "__main__":
    main()
