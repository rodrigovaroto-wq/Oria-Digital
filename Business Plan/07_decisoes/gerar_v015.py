"""Gera o registro cumulativo v0.1.5 a partir da v0.1.4 (preservada integralmente) + adendo G5-1.

Uso: python3 -I gerar_v015.py <v0.1.4.html> <saida.html>
"""
import html
import sys
from pathlib import Path

base_path, out_path = Path(sys.argv[1]), Path(sys.argv[2])
base = base_path.read_text(encoding="utf-8")
E = html.escape

# (código, decisão, status, relação, fala exata, origem)
DECISOES = [
 ("G5-1",
  "Na gravidade “alto” (G5), o limite “> 1%” é 1% do EBITDA ou da dívida total — a mesma base do nível crítico (> 5%). "
  "Fica: alto = > 1% do EBITDA ou da dívida, ou muda um indicador-chave.",
  "DEFINIDO",
  "Esclarece a G5 (o texto dizia só “> 1%”); entra na régua de gravidade do item 1.D6 do plano. Levantada na segunda "
  "revisão independente da Fase 4",
  "Sim, 1% do EBITDA ou da dívida",
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
 '<h2 id="sec-21">21. Adendo cumulativo v0.1.5 — base da gravidade “alto” (23/11/2026)</h2>',
 '<p><strong>Data do registro:</strong> 23/11/2026<br/>'
 '<strong>Natureza:</strong> esclarecimento do dono sobre a G5, pedido pela segunda revisão independente da Fase 4.<br/>'
 '<strong>Preservação:</strong> todo o texto das versões 0.1.0 a 0.1.4 acima foi mantido sem alteração. '
 '<strong>Este adendo registra decisões de projeto; não comprova implementação.</strong></p>',
 '<h3 id="sec-21-1">21.1 Decisões</h3>',
 '<div class="table-wrap"><table><thead><tr><th>Código</th><th>Decisão</th><th>Status</th>'
 '<th>Relação com versões anteriores / repositório</th><th>Fala do dono (trecho) · origem</th></tr></thead><tbody>'
 + linhas + '</tbody></table></div>',
 '<h3 id="sec-21-2">21.2 Pendência fechada</h3>',
 tabela(["Pendência", "Situação"], [
  ("Gravidade “alto” (G5): “> 1%” de quê? (levantada na segunda revisão independente da Fase 4)", "Fechada pela G5-1"),
 ]),
 '<h3 id="sec-21-3">21.3 Registro de versão aditivo</h3>',
 tabela(["Versão", "Data", "Alteração", "Situação"], [
  ("0.1.5", "23/11/2026", "Adendo com a G5-1 (gravidade alto = > 1% do EBITDA ou da dívida). "
   "Conteúdo das versões 0.1.0–0.1.4 preservado.", "Decisão do dono; implementação não comprovada"),
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


rep("<title>Oria Digital | Registro de decisões e pendências | v0.1.4</title>",
    "<title>Oria Digital | Registro de decisões e pendências | v0.1.5</title>")
rep("Versão cumulativa 0.1.4 · 23 de novembro de 2026", "Versão cumulativa 0.1.5 · 23 de novembro de 2026")
rep('<a href="#sec-20">20. Adendo cumulativo v0.1.4 — decisões da Fase 4</a></aside>',
    '<a href="#sec-20">20. Adendo cumulativo v0.1.4 — decisões da Fase 4</a>\n'
    '<a href="#sec-21">21. Adendo cumulativo v0.1.5 — base da gravidade “alto”</a></aside>')
rep('<main><div class="notice"><strong>Atualização desta versão (0.1.4):</strong>',
    '<main><div class="notice"><strong>Atualização desta versão (0.1.5):</strong> incluída ao final a seção 21, com a '
    'G5-1 (gravidade alto = &gt; 1% do EBITDA ou da dívida). Todo o texto das versões anteriores foi mantido, inclusive os '
    'avisos a seguir.</div><div class="notice"><strong>Atualização desta versão (0.1.4):</strong>')
rep("</article></main></div>", adendo + "\n</article></main></div>")
out_path.write_text(out, encoding="utf-8")
print("ok", len(DECISOES), len(out))
