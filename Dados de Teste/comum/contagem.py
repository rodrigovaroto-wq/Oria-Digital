# -*- coding: utf-8 -*-
"""A contagem de VERDADE das linhas de conta, compartilhada pelos dois books.

Ela morava duplicada em `book-canastra/render.py` e `book-vertentes/render.py` —
a segunda cópia nasceu de um port meu em 01/09. Este número é o denominador
contra o qual a régua de `N8N/lib/cobertura.mjs` é calibrada, e ele só vale como
SEGUNDA OPINIÃO se os dois books contarem a mesma coisa: duas cópias divergem no
dia em que alguém corrigir uma só, e a divergência não produz erro — produz um
denominador diferente, calado.

Conta sobre os FLOWABLES, antes de o PDF existir. Não é outra leitura do arquivo.
"""

import os
import re

from reportlab.platypus import Table, KeepTogether

SEM_VALOR_MONETARIO = set()
CONTAGEM = {}


def _texto_da_celula(c):
    """Célula pode ser str, número, Paragraph ou uma lista de flowables."""
    if c is None:
        return ""
    if isinstance(c, str):
        return c
    if isinstance(c, (int, float)):
        return str(c)
    texto = getattr(c, "text", None)
    if isinstance(texto, str):
        return texto
    if isinstance(c, (list, tuple)):
        return " ".join(_texto_da_celula(x) for x in c)
    return ""


def _tem_digito(s):
    return any(ch.isdigit() for ch in s)


_TRES_LETRAS = re.compile(r"[^\W\d_]{3}", re.UNICODE)
_PERIODO = re.compile(r"^\s*((19|20)\d{2}|\d{2}/\d{2}/\d{4})\s*$")


def _conta_uma_linha(linha, acc):
    """Uma linha de tabela: conta se ela tem rótulo E valor. A regra não mudou.

    Saiu de dentro de `_conta_linhas` porque as duas responsabilidades são
    distintas — andar pela árvore de flowables, e decidir se UMA linha é conta —
    e juntas passavam de 15 de complexidade cognitiva (`python:S3776`, medido em
    16). Separadas, cada uma cabe na cabeça de quem lê.
    """
    celulas = [_texto_da_celula(c).strip() for c in linha]
    # O rótulo é a primeira célula com texto de verdade, em QUALQUER coluna;
    # os valores são as demais células com dígito.
    i_rotulo = next((i for i, c in enumerate(celulas) if _TRES_LETRAS.search(c)), None)
    if i_rotulo is None:
        return
    valores = [c for i, c in enumerate(celulas) if i != i_rotulo and _tem_digito(c)]
    # Cabeçalho de colunas ("Mês | 2024 | 2025 | Variação %") tem rótulo e dígito, mas
    # o dígito é o ANO, não valor: contava como conta e dava 16 onde o documento tem
    # 15 (Faturamento 24M do Vertentes; o texto do PDF e a leitura da IA dão 15).
    if not any(not _PERIODO.match(c) for c in valores):
        return
    acc["linhas_de_conta"] += 1
    acc["celulas_de_valor"] += len(valores)
    # O rótulo DISTINTO importa porque é essa a unidade do outro lado da guarda:
    # a extração grava conta, e duas linhas com o mesmo histórico viram uma só.
    # Num livro razão isso é a regra, não a exceção — e a guarda acusaria
    # extração perfeita de incompleta.
    acc["rotulos"].add(" ".join(celulas[i_rotulo].split()).lower())


def _conta_linhas(elementos, acc):
    """Percorre os flowables procurando Table, inclusive dentro de KeepTogether."""
    for el in elementos:
        if isinstance(el, Table):
            for linha in el._cellvalues:
                _conta_uma_linha(linha, acc)
        elif isinstance(el, KeepTogether):
            _conta_linhas(el._content, acc)


def build(d, elementos):
    arquivo = os.path.basename(d.filename)
    acc = {"linhas_de_conta": 0, "celulas_de_valor": 0, "rotulos": set()}
    if arquivo not in SEM_VALOR_MONETARIO:
        _conta_linhas(elementos, acc)
    CONTAGEM[arquivo] = {"linhas_de_conta": acc["linhas_de_conta"],
                         "celulas_de_valor": acc["celulas_de_valor"],
                         "contas_distintas": len(acc["rotulos"])}
    # O DECORADOR É OPCIONAL, e é o que difere os dois books: o canastra põe
    # carimbo de página em `_decorador`, o vertentes não tem nenhum. Passar o
    # atributo sem conferir quebrava o vertentes com `AttributeError` — e uma
    # função compartilhada que só serve a um dos dois não é compartilhada.
    deco = getattr(d, "_decorador", None)
    if deco is None:
        d.build(elementos)
    else:
        d.build(elementos, onFirstPage=deco, onLaterPages=deco)


