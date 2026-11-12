# -*- coding: utf-8 -*-
"""O conferidor das bases volumosas NÃO nasce vazio (regra 2).

    cd "Dados de Teste"/volume && python3 test_volume.py -v

Gera 3.000 linhas num diretório temporário, confere (0 falhas) e depois estraga
o ARQUIVO (ou o gabarito) de doze jeitos. Cada estrago tem de derrubar, pelo
nome, a conferência que existe para pegá-lo. Um conferidor que passasse em tudo
daria 0 falhas nos doze, e este teste reprovaria. Só biblioteca padrão.
"""

import json
import os
import re
import shutil
import tempfile
import unittest
import zipfile

import conferir_volume as C
import gerar_volume as G

N = 3000


def _ler(caminho):
    with open(caminho, encoding="cp1252", newline="") as fh:
        return fh.read().split("\r\n")


def _gravar(caminho, linhas):
    with open(caminho, "w", encoding="cp1252", newline="") as fh:
        fh.write("\r\n".join(linhas))


class ConferidorNaoNasceVazio(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.limpo = tempfile.mkdtemp(prefix="volume-")
        G.gerar(N, cls.limpo)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.limpo, ignore_errors=True)

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="volume-mut-")
        for nome in os.listdir(self.limpo):
            shutil.copy(os.path.join(self.limpo, nome), self.dir)
        self.ar = os.path.join(self.dir, f"contas_a_receber_{N}.csv")
        self.xlsx = os.path.join(self.dir, f"contas_a_receber_{N}.xlsx")
        self.ofx = os.path.join(self.dir, f"extrato_{N}.ofx")
        self.gab = os.path.join(self.dir, f"GABARITO_{N}.json")

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def falhas(self):
        return C.conferir(N, self.dir).falhas

    def assertReprova(self, trecho):
        f = self.falhas()
        self.assertTrue(any(trecho in x for x in f), f"esperava falha com {trecho!r}; vieram {f}")
        return f

    def _primeira(self, linhas, situacao):
        return next(i for i, l in enumerate(linhas) if l.endswith(";" + situacao))

    # ---------------------------------------------------------------- limpo --
    def test_limpo_passa(self):
        conf = C.conferir(N, self.dir)
        self.assertEqual(conf.falhas, [])
        self.assertGreater(conf.ok, 80)

    def test_determinismo_ao_byte(self):
        outro = tempfile.mkdtemp(prefix="volume-det-")
        try:
            G.gerar(N, outro)
            for nome in os.listdir(self.limpo):
                with open(os.path.join(self.limpo, nome), "rb") as a, open(os.path.join(outro, nome), "rb") as b:
                    self.assertEqual(a.read(), b.read(), nome)
        finally:
            shutil.rmtree(outro, ignore_errors=True)

    # ----------------------------------------------------------- estragos AR --
    def test_titulo_em_aberto_some(self):
        linhas = _ler(self.ar)
        del linhas[self._primeira(linhas, "ABERTO")]
        _gravar(self.ar, linhas)
        self.assertReprova("contas_a_receber.csv: Σ saldo = BP")

    def test_um_centavo_a_mais(self):
        linhas = _ler(self.ar)
        i = self._primeira(linhas, "ABERTO")
        c = linhas[i].split(";")
        v = C.centavos(c[9]) + 1
        c[9] = G.br(v)
        c[7] = G.br(v)  # original acompanha: só o saldo do book é que não bate
        linhas[i] = ";".join(c)
        _gravar(self.ar, linhas)
        self.assertReprova("contas_a_receber.csv: saldo por contraparte = aging do book")

    def test_vencimento_muda_de_faixa_com_o_total_intacto(self):
        """O total continua certo; só a faixa pela DATA denuncia."""
        linhas = _ler(self.ar)
        i = self._primeira(linhas, "ABERTO")
        c = linhas[i].split(";")
        c[6] = "15/01/2026"  # a vencer; o primeiro ABERTO do arquivo é da faixa >90
        linhas[i] = ";".join(c)
        _gravar(self.ar, linhas)
        f = self.assertReprova("contas_a_receber.csv: saldo por faixa = aging do book")
        self.assertFalse(any("Σ saldo = BP" in x for x in f), "o total não devia ter mudado")

    def test_situacao_trocada_mesmo_tamanho_de_texto(self):
        """ABERTO → PARCIAL não muda o saldo; antes só pegava por acaso (bytes)."""
        linhas = _ler(self.ar)
        i = self._primeira(linhas, "ABERTO")
        linhas[i] = linhas[i][: -len("ABERTO")] + "PARCIAL"
        _gravar(self.ar, linhas)
        self.assertReprova("contas_a_receber.csv: situação coerente com pago e saldo")

    def test_parcela_orfa(self):
        """Some a parcela 2/3 de um título liquidado: saldo e faixas continuam certos."""
        linhas = _ler(self.ar)
        i = next(i for i, l in enumerate(linhas) if l.endswith(";LIQUIDADO") and ";2/3;" in l)
        del linhas[i]
        _gravar(self.ar, linhas)
        f = self.assertReprova("contas_a_receber.csv: parcelas de cada título completas")
        self.assertFalse(any("Σ saldo = BP" in x for x in f), "liquidado não mexe no saldo")

    def test_linha_estranha_no_meio(self):
        linhas = _ler(self.ar)
        linhas.insert(10, "*** página 2 ***;continua")
        _gravar(self.ar, linhas)
        self.assertReprova("contas_a_receber.csv: linhas não reconhecidas")

    # --------------------------------------------------------- estragos xlsx --
    def test_xlsx_ilegivel(self):
        with open(self.xlsx, "wb") as fh:
            fh.write(b"lixo")
        self.assertReprova("contas_a_receber.xlsx: arquivo legível")

    def test_xlsx_perde_uma_linha_em_aberto(self):
        with zipfile.ZipFile(self.xlsx) as z:
            partes = {n: z.read(n) for n in z.namelist()}
        folha = partes["xl/worksheets/sheet1.xml"].decode()
        # a linha 5 é o primeiro título: o arquivo vem ordenado pela contraparte 10233, em aberto
        folha = re.sub(r'<row r="5">.*?</row>', "", folha, count=1)
        partes["xl/worksheets/sheet1.xml"] = folha.encode()
        with zipfile.ZipFile(self.xlsx, "w", zipfile.ZIP_DEFLATED) as z:
            for n, b in partes.items():
                z.writestr(n, b)
        self.assertReprova("contas_a_receber.xlsx: Σ saldo = BP")

    # ---------------------------------------------------------- estragos OFX --
    def test_transacao_some_do_ofx(self):
        linhas = _ler(self.ofx)
        i = linhas.index("<STMTTRN>")
        del linhas[i:i + G.LINHAS_POR_TRANSACAO]
        _gravar(self.ofx, linhas)
        f = self.assertReprova("extrato_ofx: saldo inicial deduzido = caixa do BP de 2024")
        self.assertTrue(any("por mês = extrato do book" in x for x in f))

    def test_fitid_repetido(self):
        linhas = _ler(self.ofx)
        fitids = [i for i, l in enumerate(linhas) if l.startswith("<FITID>")]
        linhas[fitids[1]] = linhas[fitids[0]]
        _gravar(self.ofx, linhas)
        self.assertReprova("extrato_ofx: FITID único")

    def test_ano_trocado_no_ofx(self):
        """Mês e valor intactos, ano errado: antes passava com 0 falhas."""
        linhas = [l.replace("<DTPOSTED>2025", "<DTPOSTED>2031") for l in _ler(self.ofx)]
        _gravar(self.ofx, linhas)
        self.assertReprova(f"extrato_ofx: transações todas de {G.ANO}")

    # ------------------------------------------------------ estrago gabarito --
    def test_gabarito_mente(self):
        with open(self.gab, encoding="utf-8") as fh:
            g = json.load(fh)
        g["contas_a_receber"]["titulos"]["liquidados"] += 500
        with open(self.gab, "w", encoding="utf-8") as fh:
            json.dump(g, fh)
        self.assertReprova("contas_a_receber.csv: gabarito, titulos")


    # ------------------------------------------- caminho (SonarCloud do #297) --
    def test_gabarito_com_caminho_adulterado_nao_le_fora_da_pasta(self):
        """O nome do arquivo vem do código; o do gabarito só é conferido contra ele."""
        with open(self.gab, encoding="utf-8") as fh:
            g = json.load(fh)
        g["extrato_ofx"]["arquivo"] = "../../../../etc/passwd"
        with open(self.gab, "w", encoding="utf-8") as fh:
            json.dump(g, fh)
        self.assertReprova("extrato_ofx: gabarito, arquivo")

    def test_pasta_fora_do_permitido_e_recusada(self):
        import caminhos
        with self.assertRaises(SystemExit):
            caminhos.pasta_segura("/etc")
        with self.assertRaises(SystemExit):
            caminhos.arquivo_seguro(self.dir, "../fora.csv")
        self.assertTrue(caminhos.arquivo_seguro(self.dir, f"extrato_{N}.ofx").startswith(os.path.realpath(self.dir)))


if __name__ == "__main__":
    unittest.main()
