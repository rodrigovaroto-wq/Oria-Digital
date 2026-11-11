# -*- coding: utf-8 -*-
"""O conferidor das bases volumosas NÃO nasce vazio (regra 2).

    cd "Dados de Teste"/volume && python3 -m unittest -v test_volume

Gera 3.000 linhas num diretório temporário, confere (0 falhas) e depois estraga
o ARQUIVO de sete jeitos diferentes. Cada estrago tem de derrubar a conferência
que existe para pegá-lo, pelo nome. Um conferidor que passasse em tudo daria 0
falhas nos sete, e este teste reprovaria.
"""

import os
import shutil
import tempfile
import unittest

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
        self.ofx = os.path.join(self.dir, f"extrato_{N}.ofx")

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
        self.assertGreater(conf.ok, 30)

    # ----------------------------------------------------------- estragos AR --
    def test_titulo_em_aberto_some(self):
        linhas = _ler(self.ar)
        del linhas[self._primeira(linhas, "ABERTO")]
        _gravar(self.ar, linhas)
        self.assertReprova("contas_a_receber: Σ saldo = BP")

    def test_um_centavo_a_mais(self):
        linhas = _ler(self.ar)
        i = self._primeira(linhas, "ABERTO")
        c = linhas[i].split(";")
        v = C.centavos(c[9]) + 1
        c[9] = G.br(v)
        c[7] = G.br(v)  # original acompanha: só o saldo do book é que não bate
        linhas[i] = ";".join(c)
        _gravar(self.ar, linhas)
        self.assertReprova("contas_a_receber: saldo por contraparte = aging do book")

    def test_vencimento_muda_de_faixa_com_o_total_intacto(self):
        """O total continua certo; só a faixa pela DATA denuncia."""
        linhas = _ler(self.ar)
        i = self._primeira(linhas, "ABERTO")
        c = linhas[i].split(";")
        c[6] = "15/01/2026"  # a vencer, qualquer que fosse a faixa original (o 1º é >90)
        linhas[i] = ";".join(c)
        _gravar(self.ar, linhas)
        f = self.assertReprova("contas_a_receber: saldo por faixa = aging do book")
        self.assertFalse(any("Σ saldo = BP" in x for x in f), "o total não devia ter mudado")

    def test_liquidado_com_saldo(self):
        linhas = _ler(self.ar)
        i = self._primeira(linhas, "ABERTO")
        linhas[i] = linhas[i][: -len("ABERTO")] + "LIQUIDADO"
        _gravar(self.ar, linhas)
        self.assertReprova("contas_a_receber: liquidado tem saldo zero")

    def test_linha_estranha_no_meio(self):
        linhas = _ler(self.ar)
        linhas.insert(10, "*** página 2 ***;continua")
        _gravar(self.ar, linhas)
        self.assertReprova("contas_a_receber: linhas não reconhecidas")

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


if __name__ == "__main__":
    unittest.main()
