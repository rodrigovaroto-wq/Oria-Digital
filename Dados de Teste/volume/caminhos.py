# -*- coding: utf-8 -*-
"""Onde as bases volumosas podem ser lidas e escritas (gerar_volume.py e conferir_volume.py).

POR QUE EXISTE. A pasta de saída vem da linha de comando e, na primeira versão, o
conferidor abria o arquivo pelo nome que lia do GABARITO_<n>.json. O SonarCloud do PR
#297 marcou isso como "path traversal" (5 bloqueadores, S2083, e 17 S8707): um gabarito
ou um argumento adulterado faria a ferramenta ler ou escrever fora de onde deve. É
ferramenta de teste, nunca roda em produção, mas o conserto é pequeno e vale:
  - a pasta tem de ficar DENTRO desta ferramenta (`saida/`) ou do diretório temporário
    do sistema (os testes do Leitor e o test_volume.py geram lá);
  - o nome do arquivo é MONTADO pelo código (`contas_a_receber_3000.csv`), só com
    letras, dígitos, `_`, `-` e `.`, e nunca lido de conteúdo.
"""

import os
import re
import tempfile

AQUI = os.path.dirname(os.path.realpath(__file__))
_RAIZES = (AQUI, os.path.realpath(tempfile.gettempdir()))
_NOME = re.compile(r"[A-Za-z0-9_.-]+")


def pasta_segura(pasta):
    """A pasta, resolvida, se ela estiver dentro desta ferramenta ou do temporário; senão erro."""
    real = os.path.realpath(pasta)
    for raiz in _RAIZES:
        if real == raiz or real.startswith(raiz + os.sep):
            return real
    raise SystemExit(f"pasta fora do permitido ({AQUI} ou {_RAIZES[1]}): {pasta}")


def arquivo_seguro(pasta, nome):
    """O caminho de `nome` dentro de `pasta`, com nome simples e sem sair da pasta."""
    base = pasta_segura(pasta)
    if not _NOME.fullmatch(nome) or nome in (".", ".."):
        raise SystemExit(f"nome de arquivo recusado: {nome!r}")
    caminho = os.path.realpath(os.path.join(base, nome))
    if os.path.dirname(caminho) != base:
        raise SystemExit(f"o arquivo sai da pasta: {nome!r}")
    return caminho
