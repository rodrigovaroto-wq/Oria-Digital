# -*- coding: utf-8 -*-
"""Bases volumosas sintéticas (MB0 do PLANO_MVP_2026-11.md): contas a receber,
contas a pagar e extrato OFX de 10 mil, 100 mil e 1 milhão de linhas.

    cd "Dados de Teste"/volume && python3 gerar_volume.py                # os três tamanhos
    cd "Dados de Teste"/volume && python3 gerar_volume.py --linhas 3000  # um tamanho só
    cd "Dados de Teste"/volume && python3 gerar_volume.py --xlsx         # + contas a receber em .xlsx

Saída em `saida/` (não versionada; o CONTEÚDO é determinístico, basta rodar de
novo; o .xlsx muda só o carimbo do zip). Um GABARITO_<n>.json por tamanho.

POR QUE OS TOTAIS VÊM DO BOOK-DISTRESS, E NÃO DE UM NÚMERO DIGITADO AQUI.
Um sintético de volume que fecha consigo mesmo prova só que a soma funciona. O
que o MVP precisa provar é a CONCILIAÇÃO: o aging lido de um arquivo de 1M de
linhas bate com o Clientes do balanço que a extração por IA leu de um PDF. Por
isso a carteira EM ABERTO de cada contraparte, em cada faixa, é a do aging do
book-distress (`demonstracoes.aging_ar`/`aging_ap`, 2025), em centavos:
  - Σ saldo do AR = 24.917 mil = Clientes brutos do BP da Metalúrgica em 2025;
  - Σ saldo do AP = 14.900 mil = Fornecedores do mesmo BP;
  - o OFX repete, mês a mês, créditos e débitos do extrato do book, e o saldo
    final (R$ 676.317,46) arredonda para o caixa do BP (676 mil).
O volume vem de (1) partir cada célula contraparte × faixa em muitos títulos e
(2) títulos LIQUIDADOS (saldo zero) de uma carteira pulverizada. O liquidado é a
armadilha de propósito: conta como linha lida e não pode entrar no aging.

`conferir_volume.py` relê os ARQUIVOS (não a memória deste gerador) e confronta com o
book. É ele o teste; `test_volume.py` prova que ele reprova quando o arquivo mente.
"""

import argparse
import datetime as dt
import json
import math
import os
import random
import sys
import zlib

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.append(os.path.join(AQUI, "..", "book-distress"))  # append: os módulos daqui vencem

import demonstracoes as X  # noqa: E402  (book-distress)
import motor as M  # noqa: E402

DATA_BASE = dt.date(2025, 12, 31)
ANO = 2025
TAMANHOS = [10_000, 100_000, 1_000_000]
SEMENTE = 20251231
STORAGE_TETO_BYTES = 52_428_800  # fileSizeLimit do Storage de produção, medido em 11/11/2026
EMPRESA = "PIRAQUARA METALÚRGICA E ESTRUTURAS LTDA."
CNPJ_EMPRESA = "61.702.331/0001-96"

# Dias de atraso (data-base − vencimento) de cada faixa do book. "A vencer" é
# negativo. A última faixa vai até 900 dias para o corte fino (91–180, 181–360,
# >360) que a MB3 calcula ter o que mostrar.
JANELAS = {
    "A vencer": (-120, -1),
    "1 a 30 dias": (1, 30),
    "31 a 60 dias": (31, 60),
    "61 a 90 dias": (61, 90),
    "Acima de 90 dias": (91, 900),
}
assert list(JANELAS) == X.FAIXAS, "as faixas do book mudaram; ajuste JANELAS"

COLUNAS = ["Código", "{papel}", "CNPJ/CPF", "Título", "Parcela", "Emissão", "Vencimento",
           "Valor Original", "Valor Pago", "Saldo", "Data Pagamento", "Situação"]

PREFIXOS = ["COMERCIAL", "DISTRIBUIDORA", "INDÚSTRIA", "CONSTRUTORA", "TRANSPORTES",
            "AGROPECUÁRIA", "SERVIÇOS", "METALÚRGICA", "ATACADO", "LOGÍSTICA"]
NUCLEOS = ["ARAÇÁ", "BURITI", "CAMBARÁ", "GUARIROBA", "IPÊ ROXO", "JATOBÁ", "MANACÁ",
           "PEROBA", "SUCUPIRA", "TAIÚVA", "URUCUM", "VEREDA", "ANGICO", "CAJUÍ", "GOIABEIRA"]
SUFIXOS = ["LTDA.", "S.A.", "EIRELI", "LTDA. ME"]


# ----------------------------------------------------------------- formatos --
def br(cent):
    """Centavos → '1.234,56' (como o ERP exporta). Sempre ≥ 0 aqui."""
    assert cent >= 0
    return f"{cent // 100:,}".replace(",", ".") + f",{cent % 100:02d}"


def data_br(d):
    return d.strftime("%d/%m/%Y") if d else ""


def cnpj(base8, filial=1):
    """CNPJ com dígitos verificadores válidos — o leitor pode validar o DV."""
    n = [int(c) for c in f"{base8:08d}{filial:04d}"]
    for pesos in ([5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2], [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]):
        r = sum(a * b for a, b in zip(n, pesos)) % 11
        n.append(0 if r < 2 else 11 - r)
    s = "".join(map(str, n))
    return f"{s[:2]}.{s[2:5]}.{s[5:8]}/{s[8:12]}-{s[12:]}"


def reparte(total, k, rng):
    """`total` centavos em `k` partes POSITIVAS que somam exatamente `total`."""
    assert total >= k >= 1, (total, k)
    w = [rng.random() + 0.05 for _ in range(k)]
    s = sum(w)
    partes = [1 + int((total - k) * x / s) for x in w]
    partes[rng.randrange(k)] += total - sum(partes)
    assert sum(partes) == total and min(partes) >= 1
    return partes


# ------------------------------------------------------------------ carteira --
def carteira_do_book(papel):
    """[(codigo, nome, [centavos por faixa])] — a carteira em aberto do book."""
    bp, _tot, _dre = M.construir()
    linhas, _por_faixa, total = (X.aging_ar if papel == "Cliente" else X.aging_ap)(bp, ANO)
    out = []
    for rotulo, por_faixa, _st in linhas:
        codigo, nome = rotulo.split(" - ", 1)
        out.append((codigo, nome, [v * 100_000 for v in por_faixa]))
    assert sum(sum(c) for _, _, c in out) == total * 100_000
    return out, total


def gerar_titulos(papel, n_linhas, rng):
    """Os títulos de um arquivo de AR (papel='Cliente') ou AP ('Fornecedor')."""
    carteira, total_mil = carteira_do_book(papel)
    base_cnpj = 33_000_000 if papel == "Cliente" else 44_000_000
    nomeados = [(cod, nome, cnpj(base_cnpj + i)) for i, (cod, nome, _) in enumerate(carteira)]

    celulas = [(i, f, v) for i, (_, _, c) in enumerate(carteira) for f, v in enumerate(c) if v > 0]
    total = sum(v for _, _, v in celulas)
    n_abertos = max(len(celulas), n_linhas // 5)
    n_liquidados = n_linhas - n_abertos
    assert n_liquidados >= 0, f"{n_linhas} linhas não comportam {len(celulas)} células em aberto"

    titulos, seq = [], 0

    def novo_numero():
        nonlocal seq
        seq += 1
        return f"{seq:09d}"

    # (1) Em aberto: cada célula contraparte × faixa partida em títulos.
    alocados = 0
    for j, (i, f, v) in enumerate(celulas):
        k = n_abertos - alocados if j == len(celulas) - 1 else max(1, round(n_abertos * v / total))
        k = max(1, min(k, n_abertos - alocados - (len(celulas) - j - 1)))
        alocados += k
        lo, hi = JANELAS[X.FAIXAS[f]]
        for saldo in reparte(v, k, rng):
            atraso = rng.randint(lo, hi)
            venc = DATA_BASE - dt.timedelta(days=atraso)
            prazo = rng.choice([28, 30, 45, 60, 90])
            if venc - dt.timedelta(days=prazo) > DATA_BASE:  # emissão nunca depois da data-base
                prazo = (venc - DATA_BASE).days + rng.randint(0, 30)
            emissao = venc - dt.timedelta(days=prazo)
            if rng.random() < 0.2:
                pago = max(1, int(saldo * rng.uniform(0.1, 1.5)))
                quando = emissao + dt.timedelta(days=rng.randint(0, max(0, (DATA_BASE - emissao).days)))
                situacao = "PARCIAL"
            else:
                pago, quando, situacao = 0, None, "ABERTO"
            cod, nome, doc = nomeados[i]
            titulos.append((cod, nome, doc, novo_numero(), f"{rng.randint(1, 3)}/3", emissao, venc,
                            saldo + pago, pago, saldo, quando, situacao))
    assert alocados == n_abertos

    # (2) Liquidados: carteira pulverizada + os nomeados. Saldo zero.
    n_pulv = max(50, n_linhas // 40)
    pulverizados = []
    for p in range(n_pulv):
        nome = f"{rng.choice(PREFIXOS)} {rng.choice(NUCLEOS)} {rng.choice(SUFIXOS)}"
        pulverizados.append((f"{(2 if papel == 'Cliente' else 5)}{p:05d}", nome, cnpj(base_cnpj + 100 + p)))
    todos = pulverizados + nomeados
    inicio = dt.date(ANO - 1, 1, 1)
    janela = (DATA_BASE - dt.timedelta(days=30) - inicio).days
    for _ in range(n_liquidados):
        cod, nome, doc = rng.choice(todos)
        emissao = inicio + dt.timedelta(days=rng.randint(0, janela))
        venc = emissao + dt.timedelta(days=rng.choice([28, 30, 45, 60, 90]))
        quando = min(DATA_BASE, max(emissao, venc + dt.timedelta(days=rng.randint(-10, 45))))
        original = max(1_000, int(math.exp(rng.gauss(math.log(800_000), 1.0))))
        titulos.append((cod, nome, doc, novo_numero(), f"{rng.randint(1, 3)}/3", emissao, venc,
                        original, original, 0, quando, "LIQUIDADO"))

    # Como o ERP entrega: por contraparte, depois vencimento, depois título.
    titulos.sort(key=lambda t: (t[0], t[6], t[3]))
    return titulos, total_mil


# --------------------------------------------------------------------- saída --
def _medir(caminho):
    """Bytes e bytes em gzip (nível 6, o padrão do zlib e do CompressionStream)."""
    z = zlib.compressobj(6, zlib.DEFLATED, 31)
    comprimido = 0
    with open(caminho, "rb") as fh:
        for bloco in iter(lambda: fh.read(1 << 20), b""):
            comprimido += len(z.compress(bloco))
    comprimido += len(z.flush())
    bruto = os.path.getsize(caminho)
    return {"bytes": bruto, "bytes_gzip": comprimido,
            "cabe_no_storage": bruto <= STORAGE_TETO_BYTES,
            "cabe_no_storage_em_gzip": comprimido <= STORAGE_TETO_BYTES}


def escrever_csv(caminho, papel, titulos):
    """CSV como um ERP brasileiro exporta: windows-1252, ';', '1.234,56', CRLF,
    duas linhas de título do relatório, uma em branco, o cabeçalho e uma linha
    TOTAL GERAL no fim. As cinco linhas que não são título são de propósito: o
    leitor tem de contá-las por destino, não descartá-las em silêncio."""
    rel = "CONTAS A RECEBER" if papel == "Cliente" else "CONTAS A PAGAR"
    so = sp = ss = 0
    with open(caminho, "w", encoding="cp1252", newline="") as fh:
        fh.write(f"RELATÓRIO DE {rel} - {EMPRESA} - CNPJ {CNPJ_EMPRESA}\r\n")
        fh.write(f"Posição em {data_br(DATA_BASE)}\r\n")
        fh.write("\r\n")
        fh.write(";".join(c.format(papel=papel) for c in COLUNAS) + "\r\n")
        for (cod, nome, doc, num, parc, emi, ven, orig, pago, saldo, quando, sit) in titulos:
            so, sp, ss = so + orig, sp + pago, ss + saldo
            fh.write(f"{cod};{nome};{doc};{num};{parc};{data_br(emi)};{data_br(ven)};"
                     f"{br(orig)};{br(pago)};{br(saldo)};{data_br(quando)};{sit}\r\n")
        fh.write(f"TOTAL GERAL;;;;;;;{br(so)};{br(sp)};{br(ss)};;\r\n")
    return {"cabecalho_relatorio": 2, "em_branco": 1, "cabecalho_colunas": 1,
            "titulo": len(titulos), "total": 1}


def escrever_xlsx(caminho, papel, titulos):
    """O mesmo conteúdo do CSV numa planilha (MB1 lê .xlsx em fluxo)."""
    from openpyxl import Workbook  # só quem pede --xlsx precisa do openpyxl

    wb = Workbook(write_only=True)
    fixa = dt.datetime(2026, 1, 1)
    wb.properties.created = fixa
    wb.properties.modified = fixa
    ws = wb.create_sheet("Contas a Receber" if papel == "Cliente" else "Contas a Pagar")
    rel = "CONTAS A RECEBER" if papel == "Cliente" else "CONTAS A PAGAR"
    ws.append([f"RELATÓRIO DE {rel} - {EMPRESA} - CNPJ {CNPJ_EMPRESA}"])
    ws.append([f"Posição em {data_br(DATA_BASE)}"])
    ws.append([])
    ws.append([c.format(papel=papel) for c in COLUNAS])
    so = sp = ss = 0
    for (cod, nome, doc, num, parc, emi, ven, orig, pago, saldo, quando, sit) in titulos:
        so, sp, ss = so + orig, sp + pago, ss + saldo
        ws.append([cod, nome, doc, num, parc, emi, ven, orig / 100, pago / 100, saldo / 100, quando, sit])
    ws.append(["TOTAL GERAL", None, None, None, None, None, None, so / 100, sp / 100, ss / 100])
    wb.save(caminho)


MEMOS_C = ["PIX RECEBIDO", "TED RECEBIDA", "LIQUIDACAO DE BOLETO", "DEPOSITO EM CHEQUE"]
MEMOS_D = ["PIX ENVIADO", "TED ENVIADA", "PAGAMENTO DE BOLETO", "TARIFA BANCARIA", "DEBITO AUTOMATICO"]
LINHAS_POR_TRANSACAO = 7


def gerar_extrato(n_linhas, rng):
    """Transações do ano, que repetem mês a mês créditos e débitos do extrato do book."""
    bp, _tot, _dre = M.construir()
    meses, ini, fim = X.extrato(bp, ANO)
    n_tx = max(24, (n_linhas - 40) // LINHAS_POR_TRANSACAO)
    txs, resumo, fitid = [], [], 0
    for m, (rotulo, s_ini, cred, deb, s_fim) in enumerate(meses, start=1):
        k = n_tx // 12 + (1 if m <= n_tx % 12 else 0)
        kc = max(1, int(k * 0.4))
        kd = max(1, k - kc)
        dias = (dt.date(ANO + (m == 12), m % 12 + 1, 1) - dt.date(ANO, m, 1)).days
        for valor, sinal, memos in ((cred, 1, MEMOS_C), (deb, -1, MEMOS_D)):
            for parte in reparte(valor, kc if sinal > 0 else kd, rng):
                quando = dt.date(ANO, m, rng.randint(1, dias))
                txs.append((quando, sinal * parte, rng.choice(memos)))
        resumo.append({"mes": f"{ANO}-{m:02d}", "rotulo": rotulo, "saldo_inicial": s_ini,
                       "creditos": cred, "debitos": deb, "saldo_final": s_fim,
                       "n_creditos": kc, "n_debitos": kd})
    txs.sort(key=lambda t: (t[0], -t[1]))
    out = []
    for quando, valor, memo in txs:
        fitid += 1
        out.append((quando, valor, memo, f"{quando:%Y%m%d}{fitid:08d}"))
    return out, resumo, ini, fim


def escrever_ofx(caminho, txs, fim):
    """OFX 1.02 SGML, como os bancos brasileiros entregam: CHARSET 1252 e tag
    folha SEM fechamento (`<TRNAMT>-50.00`). Saldo inicial não existe no OFX:
    o leitor o deduz (final − Σ transações) e o confere contra o BP de 2024."""
    def valor(c):
        return f"{'-' if c < 0 else ''}{abs(c) // 100}.{abs(c) % 100:02d}"

    with open(caminho, "w", encoding="cp1252", newline="") as fh:
        fh.write("OFXHEADER:100\r\nDATA:OFXSGML\r\nVERSION:102\r\nSECURITY:NONE\r\n"
                 "ENCODING:USASCII\r\nCHARSET:1252\r\nCOMPRESSION:NONE\r\n"
                 "OLDFILEUID:NONE\r\nNEWFILEUID:NONE\r\n\r\n")
        fh.write("<OFX>\r\n<SIGNONMSGSRSV1>\r\n<SONRS>\r\n<STATUS>\r\n<CODE>0\r\n<SEVERITY>INFO\r\n"
                 "</STATUS>\r\n<DTSERVER>20260105120000[-3:BRT]\r\n<LANGUAGE>POR\r\n</SONRS>\r\n"
                 "</SIGNONMSGSRSV1>\r\n<BANKMSGSRSV1>\r\n<STMTTRNRS>\r\n<TRNUID>1\r\n<STATUS>\r\n"
                 "<CODE>0\r\n<SEVERITY>INFO\r\n</STATUS>\r\n<STMTRS>\r\n<CURDEF>BRL\r\n<BANKACCTFROM>\r\n"
                 "<BANKID>999\r\n<BRANCHID>0001\r\n<ACCTID>12345-6\r\n<ACCTTYPE>CHECKING\r\n"
                 "</BANKACCTFROM>\r\n<BANKTRANLIST>\r\n"
                 f"<DTSTART>{ANO}0101000000[-3:BRT]\r\n<DTEND>{ANO}1231235959[-3:BRT]\r\n")
        for quando, v, memo, fid in txs:
            fh.write(f"<STMTTRN>\r\n<TRNTYPE>{'CREDIT' if v > 0 else 'DEBIT'}\r\n"
                     f"<DTPOSTED>{quando:%Y%m%d}120000[-3:BRT]\r\n<TRNAMT>{valor(v)}\r\n"
                     f"<FITID>{fid}\r\n<MEMO>{memo}\r\n</STMTTRN>\r\n")
        fh.write(f"</BANKTRANLIST>\r\n<LEDGERBAL>\r\n<BALAMT>{valor(fim)}\r\n"
                 f"<DTASOF>{ANO}1231235959[-3:BRT]\r\n</LEDGERBAL>\r\n</STMTRS>\r\n"
                 "</STMTTRNRS>\r\n</BANKMSGSRSV1>\r\n</OFX>\r\n")


def _contar_linhas(caminho):
    with open(caminho, "rb") as fh:
        return sum(bloco.count(b"\n") for bloco in iter(lambda: fh.read(1 << 20), b""))


def _gabarito_aging(papel, titulos, total_mil, por_linha):
    abertos = [t for t in titulos if t[9] > 0]
    por_contraparte = {}
    for t in abertos:
        por_contraparte[t[0]] = por_contraparte.get(t[0], 0) + t[9]
    saldo = sum(t[9] for t in abertos)
    top10 = sorted(por_contraparte.values(), reverse=True)[:10]
    return {
        "papel": papel,
        "linhas_por_destino": por_linha,
        "titulos": {"abertos": sum(t[11] == "ABERTO" for t in titulos),
                    "parciais": sum(t[11] == "PARCIAL" for t in titulos),
                    "liquidados": sum(t[11] == "LIQUIDADO" for t in titulos)},
        "contrapartes_no_arquivo": len({t[0] for t in titulos}),
        "contrapartes_em_aberto": len(por_contraparte),
        "saldo_em_aberto_centavos": saldo,
        "bp_rs_mil": total_mil,
        "saldo_por_contraparte_centavos": dict(sorted(por_contraparte.items())),
        "concentracao_top10": round(sum(top10) / saldo, 6),
    }


def gerar(n_linhas, saida, xlsx=False):
    os.makedirs(saida, exist_ok=True)
    rng = random.Random(SEMENTE + n_linhas)
    gab = {"data_base": DATA_BASE.isoformat(), "linhas_pedidas": n_linhas,
           "origem": "book-distress, Piraquara Metalúrgica, BP de 31/12/2025",
           "storage_teto_bytes": STORAGE_TETO_BYTES}

    for chave, papel, nome in (("contas_a_receber", "Cliente", "contas_a_receber"),
                               ("contas_a_pagar", "Fornecedor", "contas_a_pagar")):
        # -5: as cinco linhas de cabeçalho, branco e total — o arquivo sai com n_linhas.
        titulos, total_mil = gerar_titulos(papel, n_linhas - 5, rng)
        arq = os.path.join(saida, f"{nome}_{n_linhas}.csv")
        por_linha = escrever_csv(arq, papel, titulos)
        g = _gabarito_aging(papel, titulos, total_mil, por_linha)
        g["csv"] = {"arquivo": os.path.basename(arq), "linhas_arquivo": _contar_linhas(arq), **_medir(arq)}
        if xlsx and papel == "Cliente":
            arqx = os.path.join(saida, f"{nome}_{n_linhas}.xlsx")
            escrever_xlsx(arqx, papel, titulos)
            g["xlsx"] = {"arquivo": os.path.basename(arqx), **_medir(arqx)}
        gab[chave] = g

    txs, resumo, ini, fim = gerar_extrato(n_linhas, rng)
    arq = os.path.join(saida, f"extrato_{n_linhas}.ofx")
    escrever_ofx(arq, txs, fim)
    gab["extrato_ofx"] = {"arquivo": os.path.basename(arq), "linhas_arquivo": _contar_linhas(arq),
                          **_medir(arq), "transacoes": len(txs), "saldo_inicial_centavos": ini,
                          "saldo_final_centavos": fim, "bp_caixa_rs_mil": round(fim / 100_000),
                          "por_mes": resumo}

    with open(os.path.join(saida, f"GABARITO_{n_linhas}.json"), "w", encoding="utf-8") as fh:
        json.dump(gab, fh, ensure_ascii=False, indent=1)
    return gab


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--linhas", type=int, action="append", help="tamanho (repetível)")
    ap.add_argument("--saida", default=os.path.join(AQUI, "saida"))
    ap.add_argument("--xlsx", action="store_true", help="também contas a receber em .xlsx")
    a = ap.parse_args()
    for n in a.linhas or TAMANHOS:
        g = gerar(n, a.saida, a.xlsx)
        ar, ap_, ofx = g["contas_a_receber"], g["contas_a_pagar"], g["extrato_ofx"]
        print(f"{n:>9} linhas | AR {ar['csv']['bytes'] / 1e6:7.1f} MB (gzip {ar['csv']['bytes_gzip'] / 1e6:5.1f})"
              f" | AP {ap_['csv']['bytes'] / 1e6:7.1f} MB | OFX {ofx['bytes'] / 1e6:6.1f} MB,"
              f" {ofx['transacoes']} transações")


if __name__ == "__main__":
    main()
