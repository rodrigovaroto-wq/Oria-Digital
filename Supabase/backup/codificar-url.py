"""Reescreve a BACKUP_DB_URL com a senha codificada para URL (Fase A, fatia A1).

    BACKUP_DB_URL_CRU=postgresql://usuario:s3nh@@host:5432/postgres python3 -I Supabase/backup/codificar-url.py

Imprime duas espécies de linha, que o workflow consome (nunca vão para o log):
    MASCARA=<valor>        cada forma da senha, para `::add-mask::`
    BACKUP_DB_URL=<url>    a URL com a senha em percent-encoding

POR QUE: a senha do banco de produção tem `@`. Na URL crua, o libpq corta no PRIMEIRO `@` e trata o
resto da senha como nome do servidor — a 1ª execução (24/11/2026) morreu em "could not translate
host name" e imprimiu o fim da senha no log público (o GitHub só mascara o segredo inteiro).

COMO SEPARA: o servidor é o que vem depois do ÚLTIMO `@`, e o usuário é o que vem antes do PRIMEIRO
`:` depois do `://` — então a senha pode ter `@`, `:` e `/` sem ambiguidade (usuário do Supabase é
`postgres.<ref>`, sem `:` nem `@`). Senha já codificada continua certa: decodifica e recodifica.
Limite conhecido: senha com `%` seguido de dois dígitos hexadecimais literais seria lida como já
codificada.
"""
import os
import sys
from urllib.parse import quote, unquote


def main() -> int:
    url = os.environ.get("BACKUP_DB_URL_CRU", "")
    esquema, sep, resto = url.partition("://")
    if not sep or "@" not in resto:
        print("ERRO: BACKUP_DB_URL não tem a forma esquema://usuario:senha@servidor", file=sys.stderr)
        return 1
    credenciais, _, servidor = resto.rpartition("@")
    usuario, sep, senha = credenciais.partition(":")
    if not sep or not senha:
        print("ERRO: BACKUP_DB_URL sem senha depois do usuário", file=sys.stderr)
        return 1
    crua = unquote(senha)
    codificada = quote(crua, safe="")
    # O runner DECODIFICA os dados de `::add-mask::` (%25 -> %, %0A -> \n): sem escapar, a máscara da
    # forma codificada `ab%40c%25z` seria registrada como `ab%40c%z`, não casaria com a URL do
    # $GITHUB_ENV e a senha inteira apareceria no `env:` dos passos seguintes (achado da revisão).
    for forma in {crua, senha, codificada}:
        escapada = forma.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"MASCARA={escapada}")
    print(f"BACKUP_DB_URL={esquema}://{usuario}:{codificada}@{servidor}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
