# -*- coding: utf-8 -*-
"""Confere as bases volumosas de `saida/` contra o book-distress, relendo os ARQUIVOS.

    cd "Dados de Teste"/volume && python3 conferir_volume.py              # todo GABARITO_*.json em saida/
    cd "Dados de Teste"/volume && python3 conferir_volume.py --linhas 3000

Não importa o `gerar_volume.py`, de propósito: se o conferidor usasse a memória do
gerador, um arquivo escrito errado passaria (o mesmo código errando dos dois
lados). As fontes de verdade são duas e independentes do arquivo:
  1. o book-distress (`demonstracoes.aging_ar`, `aging_ap`, `extrato`): o que o
     arquivo TEM de dizer;
  2. o próprio arquivo, contado linha a linha: o que ele DIZ.
O GABARITO_<n>.json só é conferido contra o arquivo (para a MB1/MB3 poderem
confiar nele), nunca usado como verdade sobre o book.

Sai com código 1 e a lista das falhas se qualquer conferência reprovar.
"""

import argparse
import datetime as dt
import glob
import json
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.append(os.path.join(AQUI, "..", "book-distress"))  # append: os módulos daqui vencem

import demonstracoes as X  # noqa: E402
import motor as M  # noqa: E402

DATA_BASE = dt.date(2025, 12, 31)
ANO = 2025


def centavos(s):
    """'1.234,56' → 123456. Recusa o que não tiver exatamente esse formato."""
    if not re.fullmatch(r"\d{1,3}(\.\d{3})*,\d{2}", s):
        raise ValueError(f"valor fora do formato: {s!r}")
    return int(s.replace(".", "").replace(",", ""))


def data(s):
    return dt.datetime.strptime(s, "%d/%m/%Y").date() if s else None


def faixa_do_book(venc):
    """A faixa do book pela DATA, não pelo rótulo que o gerador tinha na memória."""
    atraso = (DATA_BASE - venc).days
    if atraso <= 0:
        return 0
    return 1 if atraso <= 30 else 2 if atraso <= 60 else 3 if atraso <= 90 else 4


class Conferencia:
    def __init__(self):
        self.ok, self.falhas = 0, []

    def igual(self, nome, obtido, esperado):
        if obtido == esperado:
            self.ok += 1
        else:
            self.falhas.append(f"{nome}: obtido {obtido!r}, esperado {esperado!r}")


def ler_csv(caminho):
    """Lê o CSV como um analista o abriria e devolve as linhas por destino."""
    destinos = {"cabecalho_relatorio": 0, "em_branco": 0, "cabecalho_colunas": 0,
                "titulo": 0, "total": 0, "nao_reconhecida": 0}
    titulos, total = [], None
    with open(caminho, encoding="cp1252", newline="") as fh:
        for n, linha in enumerate(fh):
            linha = linha.rstrip("\r\n")
            if not linha:
                destinos["em_branco"] += 1
            elif n < 2 and ";" not in linha:
                destinos["cabecalho_relatorio"] += 1
            elif linha.startswith("Código;"):
                destinos["cabecalho_colunas"] += 1
            elif linha.startswith("TOTAL GERAL;"):
                destinos["total"] += 1
                c = linha.split(";")
                total = (centavos(c[7]), centavos(c[8]), centavos(c[9]))
            else:
                c = linha.split(";")
                if len(c) != 12:
                    destinos["nao_reconhecida"] += 1
                    continue
                destinos["titulo"] += 1
                titulos.append({"cod": c[0], "num": c[3], "emissao": data(c[5]), "venc": data(c[6]),
                                "orig": centavos(c[7]), "pago": centavos(c[8]), "saldo": centavos(c[9]),
                                "quando": data(c[10]), "sit": c[11]})
    return destinos, titulos, total


def conferir_aging(conf, papel, chave, gab, saida):
    bp, _tot, _dre = M.construir()
    linhas, por_faixa, total_mil = (X.aging_ar if papel == "Cliente" else X.aging_ap)(bp, ANO)
    esperado_contraparte = {r.split(" - ", 1)[0]: st * 100_000 for r, _, st in linhas}

    g = gab[chave]
    arq = os.path.join(saida, g["csv"]["arquivo"])
    destinos, titulos, total = ler_csv(arq)
    p = f"{chave}"

    # O arquivo inteiro: toda linha tem destino, e nenhuma ficou sem reconhecer.
    with open(arq, "rb") as fh:
        linhas_fisicas = sum(b.count(b"\n") for b in iter(lambda: fh.read(1 << 20), b""))
    conf.igual(f"{p}: linhas com destino = linhas do arquivo", sum(destinos.values()), linhas_fisicas)
    conf.igual(f"{p}: linhas não reconhecidas", destinos["nao_reconhecida"], 0)
    conf.igual(f"{p}: arquivo tem as linhas pedidas", linhas_fisicas, gab["linhas_pedidas"])

    # Contra o BOOK: saldo total, por faixa (pela data) e por contraparte nomeada.
    saldo = sum(t["saldo"] for t in titulos)
    conf.igual(f"{p}: Σ saldo = BP × 100.000", saldo, total_mil * 100_000)
    faixas = [0] * 5
    por_cp = {}
    for t in titulos:
        if t["saldo"] > 0:
            faixas[faixa_do_book(t["venc"])] += t["saldo"]
            por_cp[t["cod"]] = por_cp.get(t["cod"], 0) + t["saldo"]
    conf.igual(f"{p}: saldo por faixa = aging do book", faixas, [v * 100_000 for v in por_faixa])
    conf.igual(f"{p}: saldo por contraparte = aging do book", por_cp,
               {k: v for k, v in esperado_contraparte.items() if v > 0})

    # Coerência de cada título (o liquidado é a armadilha: linha lida, saldo zero).
    conf.igual(f"{p}: títulos com original = pago + saldo",
               sum(t["orig"] == t["pago"] + t["saldo"] for t in titulos), len(titulos))
    conf.igual(f"{p}: liquidado tem saldo zero",
               sum(t["sit"] == "LIQUIDADO" and t["saldo"] != 0 for t in titulos), 0)
    conf.igual(f"{p}: emissão até a data-base", sum(t["emissao"] > DATA_BASE for t in titulos), 0)
    conf.igual(f"{p}: número de título único", len({t["num"] for t in titulos}), len(titulos))
    conf.igual(f"{p}: linha TOTAL GERAL = Σ das colunas", total,
               (sum(t["orig"] for t in titulos), sum(t["pago"] for t in titulos), saldo))

    # O GABARITO diz a verdade sobre o arquivo?
    conf.igual(f"{p}: gabarito, linhas por destino", g["linhas_por_destino"],
               {k: v for k, v in destinos.items() if k != "nao_reconhecida"})
    conf.igual(f"{p}: gabarito, saldo", g["saldo_em_aberto_centavos"], saldo)
    conf.igual(f"{p}: gabarito, saldo por contraparte", g["saldo_por_contraparte_centavos"],
               dict(sorted(por_cp.items())))
    conf.igual(f"{p}: gabarito, linhas do arquivo", g["csv"]["linhas_arquivo"], linhas_fisicas)
    conf.igual(f"{p}: gabarito, bytes", g["csv"]["bytes"], os.path.getsize(arq))


def ler_ofx(caminho):
    """Lê o OFX SGML (tag folha sem fechamento) e devolve as transações e o saldo."""
    txs, atual, saldo = [], None, None
    with open(caminho, encoding="cp1252", newline="") as fh:
        for linha in fh:
            linha = linha.strip()
            if linha == "<STMTTRN>":
                atual = {}
            elif linha == "</STMTTRN>":
                txs.append(atual)
                atual = None
            elif atual is not None and linha.startswith("<"):
                tag, _, valor = linha[1:].partition(">")
                atual[tag] = valor
            elif linha.startswith("<BALAMT>"):
                saldo = linha[len("<BALAMT>"):]
    return txs, saldo


def _cent_ofx(s):
    if not re.fullmatch(r"-?\d+\.\d{2}", s):
        raise ValueError(f"valor OFX fora do formato: {s!r}")
    neg = s.startswith("-")
    v = int(s.lstrip("-").replace(".", ""))
    return -v if neg else v


def conferir_ofx(conf, gab, saida):
    bp, _tot, _dre = M.construir()
    meses, ini, fim = X.extrato(bp, ANO)
    g = gab["extrato_ofx"]
    arq = os.path.join(saida, g["arquivo"])
    txs, balamt = ler_ofx(arq)
    p = "extrato_ofx"

    cred, deb = [0] * 12, [0] * 12
    for t in txs:
        v = _cent_ofx(t["TRNAMT"])
        m = int(t["DTPOSTED"][4:6]) - 1
        if v > 0:
            cred[m] += v
        else:
            deb[m] += -v
    conf.igual(f"{p}: créditos por mês = extrato do book", cred, [r[2] for r in meses])
    conf.igual(f"{p}: débitos por mês = extrato do book", deb, [r[3] for r in meses])
    conf.igual(f"{p}: LEDGERBAL = saldo final do book", _cent_ofx(balamt), fim)
    conf.igual(f"{p}: saldo inicial deduzido = caixa do BP de 2024",
               _cent_ofx(balamt) - sum(cred) + sum(deb), ini)
    conf.igual(f"{p}: saldo final em R$ mil = caixa do BP de 2025", round(fim / 100_000),
               X.soma(bp[ANO]["metalurgica"]["AC"]["Disponível"]))
    conf.igual(f"{p}: FITID único", len({t["FITID"] for t in txs}), len(txs))
    conf.igual(f"{p}: TRNTYPE coerente com o sinal",
               sum((t["TRNTYPE"] == "CREDIT") != (_cent_ofx(t["TRNAMT"]) > 0) for t in txs), 0)
    conf.igual(f"{p}: gabarito, transações", g["transacoes"], len(txs))
    conf.igual(f"{p}: gabarito, bytes", g["bytes"], os.path.getsize(arq))


def conferir(n_linhas, saida):
    with open(os.path.join(saida, f"GABARITO_{n_linhas}.json"), encoding="utf-8") as fh:
        gab = json.load(fh)
    conf = Conferencia()
    conferir_aging(conf, "Cliente", "contas_a_receber", gab, saida)
    conferir_aging(conf, "Fornecedor", "contas_a_pagar", gab, saida)
    conferir_ofx(conf, gab, saida)
    return conf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--linhas", type=int, action="append")
    ap.add_argument("--saida", default=os.path.join(AQUI, "saida"))
    a = ap.parse_args()
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
