"""Copia os arquivos de TODOS os buckets do Storage para <pasta>/<bucket>/<nome> (Fase A, fatia A1).

    BACKUP_DB_URL=... SUPABASE_SERVICE_ROLE_KEY=... python3 -I Supabase/backup/copia-do-storage.py <pasta>

POR QUE A LISTA VEM DO BANCO e não da API de listagem: `storage.objects` é a lista que o próprio
Storage mantém, e é a mesma que o `copia-do-banco.sh` guarda no dump. Assim o dump e os arquivos
contam a mesma coisa, e a conferência é uma igualdade: arquivos baixados == linhas listadas.
A API de listagem pagina por pasta e esconde subpasta; uma listagem incompleta daria uma cópia
menor SEM ERRO — o defeito que esta fatia existe para impedir.

POR QUE A service_role: os objetos do bucket `documentos` têm RLS por mandato (0216). Um papel
sem ela baixaria só o que a policy deixa — de novo, cópia menor sem erro. A falha de UM arquivo
reprova a cópia inteira, com o nome dele: "baixei 99 de 100" não é cópia.
"""
import os
import subprocess
import sys
import urllib.parse
import urllib.request


def main() -> int:
    pasta = sys.argv[1]
    url_banco = os.environ["BACKUP_DB_URL"]
    chave = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    # O usuário do Session pooler é `postgres.<ref>`; a API do projeto é https://<ref>.supabase.co.
    usuario = urllib.parse.urlparse(url_banco).username or ""
    if "." not in usuario:
        print(f"ERRO: não achei o <ref> do projeto no usuário da BACKUP_DB_URL ({usuario!r}); "
              "use a string do Session pooler (usuário postgres.<ref>).", file=sys.stderr)
        return 1
    api = os.environ.get("SUPABASE_URL") or f"https://{usuario.split('.', 1)[1]}.supabase.co"

    lista = subprocess.run(
        ["psql", url_banco, "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-F", "\t", "-c",
         "set row_security = off; select bucket_id, name from storage.objects where name is not null order by 1, 2"],
        check=True, capture_output=True, text=True).stdout.splitlines()
    objetos = [linha.split("\t", 1) for linha in lista if linha]
    # `row_security = off` acima: se o papel passasse pela RLS, o Postgres RECUSA a consulta em vez
    # de devolver só parte da lista.

    falhas, total_bytes = [], 0
    for bucket, nome in objetos:
        destino = os.path.join(pasta, bucket, nome)
        if not os.path.abspath(destino).startswith(os.path.abspath(pasta) + os.sep):
            falhas.append(f"{bucket}/{nome}: nome sai da pasta de destino")
            continue
        os.makedirs(os.path.dirname(destino), exist_ok=True)
        caminho = urllib.parse.quote(f"{bucket}/{nome}")
        pedido = urllib.request.Request(f"{api}/storage/v1/object/authenticated/{caminho}",
                                        headers={"Authorization": f"Bearer {chave}", "apikey": chave})
        try:
            with urllib.request.urlopen(pedido, timeout=120) as r, open(destino, "wb") as f:
                while bloco := r.read(1 << 20):
                    f.write(bloco)
            total_bytes += os.path.getsize(destino)
        except Exception as e:  # qualquer falha conta: a cópia é tudo ou é falha
            falhas.append(f"{bucket}/{nome}: {e}")

    print(f"[storage] {len(objetos)} objetos listados, {len(objetos) - len(falhas)} baixados, "
          f"{total_bytes / 1e6:.1f} MB", file=sys.stderr)
    if falhas:
        print(f"ERRO: {len(falhas)} arquivo(s) não copiado(s):", *falhas[:30], sep="\n  ", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
