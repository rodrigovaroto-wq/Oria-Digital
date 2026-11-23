"""Gera o registro cumulativo v0.1.4 a partir da v0.1.3 (preservada integralmente) + adendo da Fase 4.

Uso: python3 -I gerar_v014.py <v0.1.3.html> <saida.html>
"""
import html
import sys
from pathlib import Path

base_path, out_path = Path(sys.argv[1]), Path(sys.argv[2])
base = base_path.read_text(encoding="utf-8")
E = html.escape

# (código, decisão, status, relação, fala exata, origem)
DECISOES = [
 ("D6-1",
  "A classificação de documentos (etapa classificacao_doc_checklist) volta a N1 junto com a extração, até ser medida "
  "pela mesma régua da D6 (~300 amostras por etapa e tipo de documento, parte cega, ≥ 98% no limite inferior). "
  "Hoje ela está em N2 “declarada, não medida” (migration 0127_o_dial_obedecido.sql:493, limiar 0,70, sem gabarito).",
  "DEFINIDO",
  "Amplia a D6 (que citava só a extração); entra no item 0.5 do plano de execução (portão G0). Achada pela revisão "
  "independente da Fase 4",
  "Sim, volta a classificação para N1 junto com a extração",
  "Sessão da Fase 4 com o Claude, 23/11/2026"),
]


def badge(st):
    cor = {"DEFINIDO": "#1f6b45", "DEFINIDO c/ condição": "#8a5a00", "ABERTO": "#9e440e"}[st]
    return f'<strong style="color:{cor}">[{E(st)}]</strong>'


def tabela(cab, linhas):
    th = "".join(f"<th>{E(c)}</th>" for c in cab)
    trs = "".join("<tr>" + "".join(f"<td>{E(c)}</td>" for c in l) + "</tr>" for l in linhas)
    return f'<div class="table-wrap"><table><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table></div>'


linhas = "".join(
    f"<tr id=\"d-{E(c)}\"><td><strong>{E(c)}</strong></td><td>{E(d)}</td><td>{badge(s)}</td>"
    f"<td>{E(r)}</td><td><em>“{E(f)}”</em><br/><span class=\"muted\">{E(o)}</span></td></tr>"
    for c, d, s, r, f, o in DECISOES)
partes = [
 '<hr/>',
 '<h2 id="sec-20">20. Adendo cumulativo v0.1.4 — decisões da Fase 4 (23/11/2026)</h2>',
 '<p><strong>Data do registro:</strong> 23/11/2026<br/>'
 '<strong>Natureza:</strong> decisão tomada pelo dono durante a Fase 4 (plano de execução único e organização da pasta '
 '<code>Business Plan/</code>).<br/>'
 '<strong>Preservação:</strong> todo o texto das versões 0.1.0 a 0.1.3 acima foi mantido sem alteração. '
 '<strong>Este adendo registra decisões de projeto; não comprova implementação.</strong></p>',
 '<h3 id="sec-20-1">20.1 Decisões</h3>',
 '<div class="table-wrap"><table><thead><tr><th>Código</th><th>Decisão</th><th>Status</th>'
 '<th>Relação com versões anteriores / repositório</th><th>Fala do dono (trecho) · origem</th></tr></thead><tbody>'
 + linhas + '</tbody></table></div>',
 '<h3 id="sec-20-2">20.2 Pendência fechada</h3>',
 tabela(["Pendência", "Situação"], [
  ("Classificação de documentos em N2 sem gabarito (levantada na revisão independente da Fase 4)", "Fechada pela D6-1"),
 ]),
 '<h3 id="sec-20-3">20.3 Registro de versão aditivo</h3>',
 tabela(["Versão", "Data", "Alteração", "Situação"], [
  ("0.1.4", "23/11/2026", "Adendo com a decisão D6-1 (classificação de documentos volta a N1 junto com a extração). "
   "Conteúdo das versões 0.1.0–0.1.3 preservado.", "Decisão do dono; implementação não comprovada"),
 ]),
 '<p><strong>Regra de continuidade:</strong> novas decisões entram como adendo de versão seguinte, com fala, data e '
 'decisão afetada; nada é sobrescrito.</p>',
]
adendo = "\n".join(partes)

out = base


def rep(a, b):
    global out
    assert out.count(a) == 1, a[:60]
    out = out.replace(a, b)


rep("<title>Oria Digital | Registro de decisões e pendências | v0.1.3</title>",
    "<title>Oria Digital | Registro de decisões e pendências | v0.1.4</title>")
rep("Versão cumulativa 0.1.3 · 19 de novembro de 2026", "Versão cumulativa 0.1.4 · 23 de novembro de 2026")
rep('<a href="#sec-19-15">&nbsp;&nbsp;19.15 Requisitos derivados</a></aside>',
    '<a href="#sec-19-15">&nbsp;&nbsp;19.15 Requisitos derivados</a>\n'
    '<a href="#sec-20">20. Adendo cumulativo v0.1.4 — decisões da Fase 4</a></aside>')
rep('<main><div class="notice"><strong>Atualização desta versão (0.1.3):</strong>',
    '<main><div class="notice"><strong>Atualização desta versão (0.1.4):</strong> incluída ao final a seção 20, com a '
    'decisão D6-1 (classificação de documentos volta a N1 junto com a extração). Todo o texto das versões anteriores '
    'foi mantido, inclusive os avisos a seguir.</div><div class="notice"><strong>Atualização desta versão (0.1.3):</strong>')
rep("</article></main></div>", adendo + "\n</article></main></div>")
out_path.write_text(out, encoding="utf-8")
print("ok", len(DECISOES), len(out))
