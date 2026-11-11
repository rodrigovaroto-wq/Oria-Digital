# -*- coding: utf-8 -*-
"""Bases volumosas sintéticas (MB0 do PLANO_MVP_2026-11.md): contas a receber,
contas a pagar e extrato OFX de 10 mil, 100 mil e 1 milhão de linhas.

    cd "Dados de Teste"/volume && python3 gerar_volume.py                # os três tamanhos
    cd "Dados de Teste"/volume && python3 gerar_volume.py --linhas 3000  # um tamanho só

Saída em `saida/` (não versionada; determinística AO BYTE, basta rodar de novo).
Um GABARITO_<n>.json por tamanho. Só biblioteca padrão: o .xlsx é escrito à mão.

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

DE ONDE VEM O VOLUME. A carteira em aberto tem no máximo ABERTOS_TETO títulos em
QUALQUER tamanho; o resto são títulos LIQUIDADOS (saldo zero) de uma carteira
pulverizada. Medido na primeira versão (revisão de 11/11/2026): escalar os em
aberto com o arquivo fazia o título médio cair de R$ 12.464 (10 mil linhas) para
R$ 124 (1M), um perfil que não existe e que calibraria errado qualquer corte de
materialidade. O liquidado é a armadilha de propósito: é linha lida e não entra
no aging.

`conferir_volume.py` relê os ARQUIVOS (não a memória deste gerador) e confronta
com o book. É ele o teste; `test_volume.py` prova que ele reprova quando o
arquivo mente.
"""

import argparse
import datetime as dt
import json
import math
import os
import random
import sys
import zipfile
import zlib
from xml.sax.saxutils import escape

AQUI = os.path.dirname(os.path.abspath(__file__))
# Posição 1: depois do diretório deste script e ANTES do site-packages. Com
# append, um pacote instalado chamado `motor` (há um, o driver do MongoDB)
# venceria o motor.py do book em silêncio.
sys.path.insert(1, os.path.join(AQUI, "..", "book-distress"))

import demonstracoes as X  # noqa: E402  (book-distress)
import motor as M  # noqa: E402

DATA_BASE = dt.date(2025, 12, 31)
ANO = 2025
TAMANHOS = [10_000, 100_000, 1_000_000]
SEMENTE = 20251231
ABERTOS_TETO = 2_000             # títulos em aberto por arquivo: ~R$ 12 mil no AR, em todo tamanho
STORAGE_TETO_BYTES = 52_428_800  # fileSizeLimit do Storage de produção, medido em 11/11/2026
EMPRESA = "PIRAQUARA METALÚRGICA E ESTRUTURAS LTDA."
CNPJ_EMPRESA = "61.702.331/0001-96"
CARIMBO_ZIP = (2026, 1, 1, 0, 0, 0)

# Dias de atraso (data-base − vencimento) de cada faixa do book. "A vencer" vai
# até 0: o título que vence NA data-base ainda não está vencido. A última faixa
# vai até 900 dias para o corte fino (91–180, 181–360, >360) ter o que mostrar.
JANELAS = {
    "A vencer": (-120, 0),
    "1 a 30 dias": (1, 30),
    "31 a 60 dias": (31, 60),
    "61 a 90 dias": (61, 90),
    "Acima de 90 dias": (91, 900),
}
assert list(JANELAS) == X.FAIXAS, "as faixas do book mudaram; ajuste JANELAS"
# As fronteiras aparecem SEMPRE (os primeiros títulos de cada célula caem nelas):
# um leitor que põe "vence hoje" em "1 a 30" erra no sintético, não só no real.
FRONTEIRAS = {"A vencer": [0, -1], "1 a 30 dias": [1, 30], "31 a 60 dias": [31, 60],
              "61 a 90 dias": [61, 90], "Acima de 90 dias": [91, 180, 181, 360, 361]}

# O corte fino que a MB3 calcula. O book não o tem; o gabarito traz o do arquivo.
FAIXAS_FINAS = [("a vencer", None, 0), ("1-30", 1, 30), ("31-60", 31, 60), ("61-90", 61, 90),
                ("91-180", 91, 180), ("181-360", 181, 360), (">360", 361, None)]

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


def faixa_fina(venc):
    atraso = (DATA_BASE - venc).days
    for nome, lo, hi in FAIXAS_FINAS:
        if (lo is None or atraso >= lo) and (hi is None or atraso <= hi):
            return nome
    raise AssertionError(atraso)


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
    """Os títulos de um arquivo de AR (papel='Cliente') ou AP ('Fornecedor').

    Um título tem de 1 a 3 parcelas, com o MESMO número e parcela i/p, como no
    ERP: um leitor que indexa só pelo número descartaria 2/3 das linhas."""
    carteira, total_mil = carteira_do_book(papel)
    base_cnpj = 33_000_000 if papel == "Cliente" else 44_000_000
    nomeados = [(cod, nome, cnpj(base_cnpj + i)) for i, (cod, nome, _) in enumerate(carteira)]

    celulas = [(i, f, v) for i, (_, _, c) in enumerate(carteira) for f, v in enumerate(c) if v > 0]
    total = sum(v for _, _, v in celulas)
    n_abertos = max(len(celulas), min(ABERTOS_TETO, n_linhas // 5))
    n_liquidados = n_linhas - n_abertos
    assert n_liquidados >= 0, f"{n_linhas} linhas não comportam {len(celulas)} células em aberto"

    titulos, seq = [], 0

    def parcelas(quantas):
        """Agrupa `quantas` linhas em títulos de 1 a 3 parcelas, sem sobrar parcela órfã."""
        nonlocal seq
        out = []
        while len(out) < quantas:
            seq += 1
            p = min(rng.choice([1, 1, 2, 3]), quantas - len(out))
            out += [(f"{seq:09d}", f"{i}/{p}") for i in range(1, p + 1)]
        return out

    # (1) Em aberto: cada célula contraparte × faixa partida em títulos.
    alocados = 0
    for j, (i, f, v) in enumerate(celulas):
        k = n_abertos - alocados if j == len(celulas) - 1 else max(1, round(n_abertos * v / total))
        k = max(1, min(k, n_abertos - alocados - (len(celulas) - j - 1)))
        alocados += k
        faixa = X.FAIXAS[f]
        lo, hi = JANELAS[faixa]
        cod, nome, doc = nomeados[i]
        for idx, (saldo, (num, parc)) in enumerate(zip(reparte(v, k, rng), parcelas(k))):
            fr = FRONTEIRAS[faixa]
            atraso = fr[idx] if idx < len(fr) else rng.randint(lo, hi)
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
            titulos.append((cod, nome, doc, num, parc, emissao, venc,
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
    grupos = parcelas(n_liquidados)
    g = 0
    while g < len(grupos):
        cod, nome, doc = rng.choice(todos)  # todas as parcelas de um título: mesma contraparte
        p = int(grupos[g][1].split("/")[1])
        for num, parc in grupos[g:g + p]:
            emissao = inicio + dt.timedelta(days=rng.randint(0, janela))
            venc = emissao + dt.timedelta(days=rng.choice([28, 30, 45, 60, 90]))
            quando = min(DATA_BASE, max(emissao, venc + dt.timedelta(days=rng.randint(-10, 45))))
            original = max(1_000, int(math.exp(rng.gauss(math.log(800_000), 1.0))))
            titulos.append((cod, nome, doc, num, parc, emissao, venc,
                            original, original, 0, quando, "LIQUIDADO"))
        g += p

    # Como o ERP entrega: por contraparte, depois vencimento, depois título e parcela.
    titulos.sort(key=lambda t: (t[0], t[6], t[3], t[4]))
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


def _cabecalho(papel):
    rel = "CONTAS A RECEBER" if papel == "Cliente" else "CONTAS A PAGAR"
    return (f"RELATÓRIO DE {rel} - {EMPRESA} - CNPJ {CNPJ_EMPRESA}",
            f"Posição em {data_br(DATA_BASE)}",
            [c.format(papel=papel) for c in COLUNAS])


def _totais(titulos):
    return (sum(t[7] for t in titulos), sum(t[8] for t in titulos), sum(t[9] for t in titulos))


def escrever_csv(caminho, papel, titulos):
    """CSV como um ERP brasileiro exporta: windows-1252, ';', '1.234,56', CRLF,
    duas linhas de título do relatório, uma em branco, o cabeçalho e uma linha
    TOTAL GERAL no fim. As cinco linhas que não são título são de propósito: o
    leitor tem de contá-las por destino, não descartá-las em silêncio."""
    t1, t2, colunas = _cabecalho(papel)
    so, sp, ss = _totais(titulos)
    with open(caminho, "w", encoding="cp1252", newline="") as fh:
        fh.write(f"{t1}\r\n{t2}\r\n\r\n" + ";".join(colunas) + "\r\n")
        for (cod, nome, doc, num, parc, emi, ven, orig, pago, saldo, quando, sit) in titulos:
            fh.write(f"{cod};{nome};{doc};{num};{parc};{data_br(emi)};{data_br(ven)};"
                     f"{br(orig)};{br(pago)};{br(saldo)};{data_br(quando)};{sit}\r\n")
        fh.write(f"TOTAL GERAL;;;;;;;{br(so)};{br(sp)};{br(ss)};;\r\n")
    return {"cabecalho_relatorio": 2, "em_branco": 1, "cabecalho_colunas": 1,
            "titulo": len(titulos), "total": 1}


# O .xlsx é escrito À MÃO, como o Excel e os ERPs gravam: texto em `t="s"` com a
# tabela `sharedStrings.xml`, data como serial com formato 14, valor com formato
# 4, e a linha em branco AUSENTE (não `<row>` vazia). Medido na primeira versão
# (revisão de 11/11/2026): o openpyxl em write_only grava `inlineStr`, sem tabela
# de strings — o formato que nenhum arquivo real tem, e justamente a tabela que
# pesa no heap de um leitor em fluxo. Um leitor calibrado nele leria nome e CNPJ
# como índice no primeiro AR de verdade.
_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"  # NOSONAR(S5332): namespace, não URL
_NS_R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"  # NOSONAR(S5332)
_NS_PR = "http://schemas.openxmlformats.org/package/2006/relationships"  # NOSONAR(S5332)
_CT = "application/vnd.openxmlformats-officedocument.spreadsheetml."
_PARTES_FIXAS = {
    "[Content_Types].xml":
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'  # NOSONAR(S5332)
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        f'<Override PartName="/xl/workbook.xml" ContentType="{_CT}sheet.main+xml"/>'
        f'<Override PartName="/xl/worksheets/sheet1.xml" ContentType="{_CT}worksheet+xml"/>'
        f'<Override PartName="/xl/sharedStrings.xml" ContentType="{_CT}sharedStrings+xml"/>'
        f'<Override PartName="/xl/styles.xml" ContentType="{_CT}styles+xml"/></Types>',
    "_rels/.rels":
        f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="{_NS_PR}">'
        f'<Relationship Id="rId1" Type="{_NS_R}/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    "xl/_rels/workbook.xml.rels":
        f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="{_NS_PR}">'
        f'<Relationship Id="rId1" Type="{_NS_R}/worksheet" Target="worksheets/sheet1.xml"/>'
        f'<Relationship Id="rId2" Type="{_NS_R}/styles" Target="styles.xml"/>'
        f'<Relationship Id="rId3" Type="{_NS_R}/sharedStrings" Target="sharedStrings.xml"/></Relationships>',
    "xl/styles.xml":
        f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<styleSheet xmlns="{_NS}">'
        '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
        '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
        '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>',
}
_LETRAS = "ABCDEFGHIJKL"
_EPOCA_EXCEL = dt.date(1899, 12, 30)


def _zinfo(nome):
    zi = zipfile.ZipInfo(nome, date_time=CARIMBO_ZIP)
    zi.compress_type = zipfile.ZIP_DEFLATED
    return zi


def escrever_xlsx(caminho, papel, titulos):
    """O mesmo conteúdo do CSV numa planilha (MB1 lê .xlsx em fluxo)."""
    t1, t2, colunas = _cabecalho(papel)
    so, sp, ss = _totais(titulos)

    def linha(r, valores):
        """valores: str → t="s"; ('d', date) → serial; ('v', centavos) → número; None → célula ausente."""
        cel = []
        for c, v in enumerate(valores):
            ref = f"{_LETRAS[c]}{r}"
            if v is None or v == "":
                continue
            if isinstance(v, str):
                cel.append(f'<c r="{ref}" t="s"><v>{indice(v)}</v></c>')
            elif v[0] == "d":
                cel.append(f'<c r="{ref}" s="1"><v>{(v[1] - _EPOCA_EXCEL).days}</v></c>')
            else:
                cel.append(f'<c r="{ref}" s="2"><v>{v[1] // 100}.{v[1] % 100:02d}</v></c>')
        return f'<row r="{r}">' + "".join(cel) + "</row>"

    sst, refs = {}, 0

    def indice(s):
        nonlocal refs
        refs += 1
        return sst.setdefault(s, len(sst))

    def d(x):
        return ("d", x) if x else None

    ultima = len(titulos) + 5  # 1-2 título do relatório, 3 em branco (ausente), 4 cabeçalho, total

    def linhas_da_planilha():
        """Em fluxo: 1M de linhas em memória como texto passaria de 700 MB."""
        yield linha(1, [t1]) + linha(2, [t2]) + linha(4, colunas)  # a linha 3 não existe
        lote = []
        for r, (cod, nome, doc, num, parc, emi, ven, orig, pago, saldo, quando, sit) in enumerate(titulos, 5):
            lote.append(linha(r, [cod, nome, doc, num, parc, d(emi), d(ven),
                                  ("v", orig), ("v", pago), ("v", saldo), d(quando), sit]))
            if len(lote) == 10_000:
                yield "".join(lote)
                lote = []
        lote.append(linha(ultima, ["TOTAL GERAL", None, None, None, None, None, None,
                                   ("v", so), ("v", sp), ("v", ss)]))
        yield "".join(lote)

    # A planilha vai ANTES da tabela de strings no zip: a tabela nasce enquanto
    # a planilha é escrita. A ordem das partes no zip não importa ao Excel.
    with zipfile.ZipFile(caminho, "w", compresslevel=6) as z:
        for nome in ("[Content_Types].xml", "_rels/.rels", "xl/_rels/workbook.xml.rels", "xl/styles.xml"):
            z.writestr(_zinfo(nome), _PARTES_FIXAS[nome])
        aba = "Contas a Receber" if papel == "Cliente" else "Contas a Pagar"
        z.writestr(_zinfo("xl/workbook.xml"),
                   f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
                   f'<workbook xmlns="{_NS}" xmlns:r="{_NS_R}"><sheets>'
                   f'<sheet name="{aba}" sheetId="1" r:id="rId1"/></sheets></workbook>')
        with z.open(_zinfo("xl/worksheets/sheet1.xml"), "w", force_zip64=True) as fh:
            fh.write(f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<worksheet xmlns="{_NS}">'
                     f'<dimension ref="A1:L{ultima}"/><sheetData>'.encode())
            for bloco in linhas_da_planilha():
                fh.write(bloco.encode())
            fh.write(b"</sheetData></worksheet>")
        with z.open(_zinfo("xl/sharedStrings.xml"), "w", force_zip64=True) as fh:
            fh.write(f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
                     f'<sst xmlns="{_NS}" count="{refs}" uniqueCount="{len(sst)}">'.encode())
            itens = list(sst)
            for i in range(0, len(itens), 10_000):
                fh.write("".join(f"<si><t>{escape(s)}</t></si>" for s in itens[i:i + 10_000]).encode())
            fh.write(b"</sst>")
    return {"linhas_planilha": ultima, "strings_unicas": len(sst)}


# OFX: tipo e memo variados, com acento (o CHARSET 1252 tem de ser exercitado no
# OFX, não só no CSV). XFER aparece nos dois sentidos: o tipo NÃO dá o sinal.
MOVIMENTOS_C = [("CREDIT", "PIX RECEBIDO"), ("DEP", "DEPÓSITO EM CHEQUE"),
                ("XFER", "TRANSFERÊNCIA RECEBIDA TED"), ("CREDIT", "LIQUIDAÇÃO DE BOLETO")]
MOVIMENTOS_D = [("DEBIT", "PIX ENVIADO"), ("PAYMENT", "PAGAMENTO DE BOLETO"),
                ("FEE", "TARIFA BANCÁRIA"), ("XFER", "TRANSFERÊNCIA ENVIADA TED"),
                ("DEBIT", "DÉBITO AUTOMÁTICO CONVÊNIO")]
LINHAS_POR_TRANSACAO = 7


def gerar_extrato(n_linhas, rng):
    """Transações do ano, que repetem mês a mês créditos e débitos do extrato do book."""
    bp, _tot, _dre = M.construir()
    meses, ini, fim = X.extrato(bp, ANO)
    n_tx = max(24, (n_linhas - 40) // LINHAS_POR_TRANSACAO)
    txs, resumo = [], []
    for m, (rotulo, s_ini, cred, deb, s_fim) in enumerate(meses, start=1):
        k = n_tx // 12 + (1 if m <= n_tx % 12 else 0)
        kc = max(1, int(k * 0.4))
        kd = max(1, k - kc)
        dias = (dt.date(ANO + (m == 12), m % 12 + 1, 1) - dt.date(ANO, m, 1)).days
        for valor, sinal, movimentos, quantas in ((cred, 1, MOVIMENTOS_C, kc), (deb, -1, MOVIMENTOS_D, kd)):
            for parte in reparte(valor, quantas, rng):
                quando = dt.date(ANO, m, rng.randint(1, dias))
                tipo, memo = rng.choice(movimentos)
                txs.append((quando, sinal * parte, tipo, memo))
        resumo.append({"mes": f"{ANO}-{m:02d}", "saldo_inicial": s_ini, "creditos": cred,
                       "debitos": deb, "saldo_final": s_fim, "n_creditos": kc, "n_debitos": kd})
    txs.sort(key=lambda t: (t[0], -t[1]))
    out = [(q, v, tipo, memo, f"{q:%Y%m%d}{i:08d}") for i, (q, v, tipo, memo) in enumerate(txs, start=1)]
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
        for quando, v, tipo, memo, fid in txs:
            fh.write(f"<STMTTRN>\r\n<TRNTYPE>{tipo}\r\n"
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
    por_contraparte, finas = {}, {nome: 0 for nome, _, _ in FAIXAS_FINAS}
    for t in abertos:
        por_contraparte[t[0]] = por_contraparte.get(t[0], 0) + t[9]
        finas[faixa_fina(t[6])] += t[9]
    saldo = sum(t[9] for t in abertos)
    top10 = sorted(por_contraparte.values(), reverse=True)[:10]
    return {
        "papel": papel,
        "linhas_por_destino": por_linha,
        "titulos": {"abertos": sum(t[11] == "ABERTO" for t in titulos),
                    "parciais": sum(t[11] == "PARCIAL" for t in titulos),
                    "liquidados": sum(t[11] == "LIQUIDADO" for t in titulos)},
        "titulos_distintos": len({t[3] for t in titulos}),
        "contrapartes_no_arquivo": len({t[0] for t in titulos}),
        "contrapartes_em_aberto": len(por_contraparte),
        "saldo_em_aberto_centavos": saldo,
        "bp_rs_mil": total_mil,
        "saldo_por_contraparte_centavos": dict(sorted(por_contraparte.items())),
        "saldo_por_faixa_fina_centavos": finas,
        "concentracao_top10": round(sum(top10) / saldo, 6),
    }


def gerar(n_linhas, saida, xlsx=True):
    os.makedirs(saida, exist_ok=True)
    rng = random.Random(SEMENTE + n_linhas)
    gab = {"data_base": DATA_BASE.isoformat(), "linhas_pedidas": n_linhas,
           "origem": "book-distress, Piraquara Metalúrgica, BP de 31/12/2025",
           "storage_teto_bytes": STORAGE_TETO_BYTES}

    for chave, papel in (("contas_a_receber", "Cliente"), ("contas_a_pagar", "Fornecedor")):
        # -5: as cinco linhas de cabeçalho, branco e total — o arquivo sai com n_linhas.
        titulos, total_mil = gerar_titulos(papel, n_linhas - 5, rng)
        arq = os.path.join(saida, f"{chave}_{n_linhas}.csv")
        por_linha = escrever_csv(arq, papel, titulos)
        g = _gabarito_aging(papel, titulos, total_mil, por_linha)
        g["csv"] = {"arquivo": os.path.basename(arq), "linhas_arquivo": _contar_linhas(arq), **_medir(arq)}
        if xlsx and papel == "Cliente":
            arqx = os.path.join(saida, f"{chave}_{n_linhas}.xlsx")
            info = escrever_xlsx(arqx, papel, titulos)
            g["xlsx"] = {"arquivo": os.path.basename(arqx), **info, **_medir(arqx)}
        gab[chave] = g

    txs, resumo, ini, fim = gerar_extrato(n_linhas, rng)
    arq = os.path.join(saida, f"extrato_{n_linhas}.ofx")
    escrever_ofx(arq, txs, fim)
    gab["extrato_ofx"] = {"arquivo": os.path.basename(arq), "linhas_arquivo": _contar_linhas(arq),
                          **_medir(arq), "transacoes": len(txs), "saldo_inicial_centavos": ini,
                          "saldo_final_centavos": fim, "por_mes": resumo}

    with open(os.path.join(saida, f"GABARITO_{n_linhas}.json"), "w", encoding="utf-8") as fh:
        json.dump(gab, fh, ensure_ascii=False, indent=1)
    return gab


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--linhas", type=int, action="append", help="tamanho (repetível)")
    ap.add_argument("--saida", default=os.path.join(AQUI, "saida"))
    ap.add_argument("--sem-xlsx", action="store_true", help="pula o .xlsx do contas a receber")
    a = ap.parse_args()
    for n in a.linhas or TAMANHOS:
        g = gerar(n, a.saida, not a.sem_xlsx)
        ar, ap_, ofx = g["contas_a_receber"], g["contas_a_pagar"], g["extrato_ofx"]
        x = ar.get("xlsx")
        print(f"{n:>9} linhas | AR {ar['csv']['bytes'] / 1e6:7.1f} MB (gzip {ar['csv']['bytes_gzip'] / 1e6:5.1f})"
              f" | AP {ap_['csv']['bytes'] / 1e6:7.1f} MB"
              + (f" | AR.xlsx {x['bytes'] / 1e6:6.1f} MB (gzip {x['bytes_gzip'] / 1e6:5.1f})" if x else "")
              + f" | OFX {ofx['bytes'] / 1e6:6.1f} MB, {ofx['transacoes']} transações")


if __name__ == "__main__":
    main()
