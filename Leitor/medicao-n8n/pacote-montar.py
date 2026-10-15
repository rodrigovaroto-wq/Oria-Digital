"""Monta o zip sintético grande da medição (S109). Uso (na pasta de trabalho; só NOMES, sem barra, como os outros scripts desta pasta):
  python3 -I <repo>/Leitor/medicao-n8n/pacote-montar.py <saida.zip> <ecd.txt>

A pasta de trabalho tem nfe.xml, extrato.ofx, retorno.ret e ecf.txt (os geradores de `Dados de Teste/fontes-oficiais/gerar.mjs`);
a ECD vem de `Leitor/medicao-n8n/gerar-ecd-realista.mjs 10 <arquivo>`. Gasta ~9,6 GB de disco.

Ordem de propósito: o preenchimento (PDF "não oficial" grande) vem PRIMEIRO, para que os SPEDs
fiquem em posições acima de 4 GiB (campo de posição de 32 bits estourado = ZIP64 de verdade),
e um dos preenchimentos tem 4,2 GiB declarados (acima do limite por entrada: tem de ser recusado,
com o tamanho lido do extra ZIP64).
"""
import os, sys, zipfile, io, time



def nome_local(arg):
    # Da linha de comando vem só um NOME (sem pasta): o arquivo é o do diretório atual.
    if not arg or os.path.basename(arg) != arg or arg in ('.', '..'):
        print('passe só o nome do arquivo (sem pasta); ele é lido/gravado no diretório atual', file=sys.stderr)
        sys.exit(2)
    return os.path.join(os.getcwd(), arg)


saida, ecd = nome_local(sys.argv[1]), nome_local(sys.argv[2])

GiB = 1 << 30
bloco = b'%PDF-1.4\n' + os.urandom((1 << 20) - 9)

def preencher(zf, nome, n_bytes):
    zi = zipfile.ZipInfo(nome, date_time=(2026, 10, 15, 12, 0, 0))
    zi.compress_type = zipfile.ZIP_STORED
    t = time.time()
    with zf.open(zi, 'w', force_zip64=True) as f:
        falta = n_bytes
        while falta > 0:
            n = min(len(bloco), falta)
            f.write(bloco[:n])
            falta -= n
    print(f'{nome}: {n_bytes} bytes em {time.time() - t:.1f}s', flush=True)

def arquivo(zf, nome, caminho, deflate=True):
    zi = zipfile.ZipInfo(nome, date_time=(2026, 10, 15, 12, 0, 0))
    zi.compress_type = zipfile.ZIP_DEFLATED if deflate else zipfile.ZIP_STORED
    t = time.time()
    with open(caminho, 'rb') as o, zf.open(zi, 'w', force_zip64=True) as f:
        while True:
            b = o.read(1 << 20)
            if not b:
                break
            f.write(b)
    print(f'{nome}: {os.path.getsize(caminho)} bytes em {time.time() - t:.1f}s', flush=True)

def bytes_(zf, nome, dados):
    zi = zipfile.ZipInfo(nome, date_time=(2026, 10, 15, 12, 0, 0))
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, dados)

xlsx = io.BytesIO()
with zipfile.ZipFile(xlsx, 'w', zipfile.ZIP_DEFLATED) as x:
    x.writestr('[Content_Types].xml', '<Types spreadsheetml/>')
    x.writestr('xl/workbook.xml', '<workbook/>')
    x.writestr('xl/worksheets/sheet1.xml', '<worksheet>' + '<row/>' * 1000 + '</worksheet>')

with zipfile.ZipFile(saida, 'w', allowZip64=True) as zf:
    preencher(zf, 'anexos/cartoes-2025.pdf', int(3.5 * GiB))
    preencher(zf, 'anexos/conciliacao-historica.pdf', 1 * GiB)
    preencher(zf, 'anexos/arquivo-morto-enorme.pdf', int(4.2 * GiB))
    arquivo(zf, 'sped/ecd-2025.txt', ecd)
    arquivo(zf, 'sped/ecd-2024.txt', ecd)
    for i in range(300):
        bytes_(zf, f'xml/nfe-{i:04d}.xml', open(nome_local('nfe.xml'), 'rb').read())
    bytes_(zf, 'bancos/extrato.ofx', open(nome_local('extrato.ofx'), 'rb').read())
    bytes_(zf, 'bancos/retorno.ret', open(nome_local('retorno.ret'), 'rb').read())
    bytes_(zf, 'sped/ecf-2025.txt', open(nome_local('ecf.txt'), 'rb').read())
    bytes_(zf, 'receber/contas-a-receber.xlsx', xlsx.getvalue())
    bytes_(zf, 'pagar/contas-a-pagar.csv', b'vencimento;fornecedor;valor\n01/11/2025;ACME;1.234,56\n')
    bytes_(zf, 'fornecedores/fornecedores.csv', b'cnpj;nome\n11222333000181;ACME\n')
    bytes_(zf, '__MACOSX/sped/._ecd-2025.txt', b'metadados do macOS')
print('tamanho final', os.path.getsize(saida), flush=True)
