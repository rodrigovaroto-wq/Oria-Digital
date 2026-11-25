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
import http.client
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def baixar(url: str, chave: str, destino: str, tamanho: str):
    """Baixa um objeto. Devolve (bytes, None, _) ou (None, motivo, passageira)."""
    pedido = urllib.request.Request(url, headers={"Authorization": f"Bearer {chave}", "apikey": chave})
    try:
        with urllib.request.urlopen(pedido, timeout=120) as r, open(destino, "wb") as f:
            while bloco := r.read(1 << 20):
                f.write(bloco)
            comprimento = r.headers.get("Content-Length")
    except urllib.error.HTTPError as e:
        try:
            corpo = e.read(300).decode("utf-8", "replace")
        except Exception:  # a conexão pode cair também ao ler o corpo do erro
            corpo = ""
        if e.code == 400 and "not_found" in corpo:
            # A Storage responde 400 (não 404) para "não encontrado", e a RLS do bucket também esconde
            # o arquivo de uma chave sem acesso total. Medido em 25/11/2026: os 186 objetos davam 400
            # com a chave errada no segredo, e o mesmo arquivo baixava (200) com a service_role.
            return None, ("não encontrado (HTTP 400). Se TODOS falham assim, a SUPABASE_SERVICE_ROLE_KEY "
                          "não é a service_role (Settings > API Keys > Legacy API Keys)"), False
        return None, f"HTTP {e.code}: {corpo[:120]}", e.code >= 500 or e.code == 429
    except (http.client.HTTPException, OSError) as e:
        # OSError cobre URLError, timeout, conexão e TLS (SSLError); HTTPException cobre IncompleteRead
        # de resposta chunked que cai no meio. A 1ª versão desta função pegava só URLError/Timeout/
        # Connection e deixava os dois últimos derrubarem o script sem nova tentativa (revisão).
        return None, f"rede: {type(e).__name__}: {e}", True
    # A conexão que cai no meio não levanta exceção: `read()` devolve b"" e o laço acaba com o
    # arquivo pela metade (revisão: 100.000 de 5.000.000 bytes, sem erro, Python 3.13). O tamanho
    # que o Storage registrou é a régua; sem ele, o Content-Length.
    esperado = int(tamanho) if tamanho else (int(comprimento) if comprimento else None)
    obtido = os.path.getsize(destino)
    if esperado is None:
        return None, "sem tamanho conhecido para conferir o download", False
    if obtido != esperado:
        return None, f"baixados {obtido} de {esperado} bytes", True
    return obtido, None, False


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

    # Sem check=True: o traceback dele imprime a lista de argumentos, com a URL e a senha; se a senha
    # tiver `\\` ou `'`, o repr a escapa e a máscara de segredo do GitHub deixa de casar.
    r = subprocess.run(
        ["psql", url_banco, "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-F", "\t", "-c",
         "set row_security = off; select bucket_id, coalesce(metadata->>'size', ''), name"
         " from storage.objects where name is not null order by 1, 3"],
        capture_output=True, text=True)
    if r.returncode != 0:
        print(f"ERRO ao listar storage.objects:\n{r.stderr}", file=sys.stderr)
        return 1
    objetos = [linha.split("\t", 2) for linha in r.stdout.splitlines() if linha]
    # `row_security = off` acima: se o papel passasse pela RLS, o Postgres RECUSA a consulta em vez
    # de devolver só parte da lista.

    falhas, baixados, total_bytes, repetidos, seguidas = [], 0, 0, 0, 0
    # Storage fora do ar inteiro: 186 objetos × 3 tentativas × até ~70 s passariam dos 45 min do job,
    # que seria cancelado SEM imprimir o resumo — o dono não saberia se foi chave, rede ou tamanho.
    # 10 objetos seguidos perdidos depois das tentativas = desistir e dizer por quê.
    LIMITE_SEGUIDAS = 10
    for indice, (bucket, tamanho, nome) in enumerate(objetos):
        if seguidas >= LIMITE_SEGUIDAS:
            falhas.append(f"(desisti dos {len(objetos) - indice} restantes: {LIMITE_SEGUIDAS} objetos "
                          "seguidos falharam — Storage fora do ar ou chave sem acesso total)")
            break
        destino = os.path.join(pasta, bucket, nome)
        if not os.path.abspath(destino).startswith(os.path.abspath(pasta) + os.sep):
            falhas.append(f"{bucket}/{nome}: nome sai da pasta de destino")
            continue
        url = f"{api}/storage/v1/object/authenticated/{urllib.parse.quote(f'{bucket}/{nome}')}"
        # Até 3 tentativas, SÓ para falha passageira. Medido na 1ª cópia completa (25/11/2026, run
        # 45678617119): 182 de 186 baixados e 4 com "HTTP Error 522" — tempo esgotado na Cloudflare
        # do Supabase, que some ao repetir. Uma tentativa só reprovava a cópia inteira por 2% de
        # ruído de rede. Falha definitiva (4xx) não se repete. E nada disso afrouxa a regra: depois
        # das tentativas, um arquivo que ainda falta reprova a cópia.
        try:
            os.makedirs(os.path.dirname(destino), exist_ok=True)
            for tentativa in range(1, 4):
                obtido, motivo, passageira = baixar(url, chave, destino, tamanho)
                if obtido is not None or not passageira or tentativa == 3:
                    break
                repetidos += 1
                time.sleep(2 ** (2 * tentativa - 1))  # 2 s, depois 8 s
        except Exception as e:  # o inesperado (disco cheio, tamanho ilegível) conta como falha e segue
            obtido, motivo, tentativa = None, f"{type(e).__name__}: {e}", 1
        if obtido is None:
            falhas.append(f"{bucket}/{nome}: {motivo} (tentativas: {tentativa})")
            seguidas += 1
        else:
            baixados += 1
            total_bytes += obtido
            seguidas = 0

    print(f"[storage] {len(objetos)} objetos listados, {baixados} baixados, "
          f"{total_bytes / 1e6:.1f} MB, {repetidos} nova(s) tentativa(s)", file=sys.stderr)
    if falhas:
        print(f"ERRO: {len(falhas)} arquivo(s) não copiado(s):", *falhas[:30], sep="\n  ", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
