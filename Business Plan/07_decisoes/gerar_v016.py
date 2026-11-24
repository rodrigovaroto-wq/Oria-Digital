"""Gera o registro cumulativo v0.1.6 a partir da v0.1.5 (preservada integralmente) + adendo do score do dado externo
(D15, D15.1–D15.15), D4-1 e J7.

Uso: python3 -I gerar_v016.py <v0.1.5.html> <saida.html>
"""
import html
import sys
from pathlib import Path

base_path, out_path = Path(sys.argv[1]), Path(sys.argv[2])
base = base_path.read_text(encoding="utf-8")
E = html.escape

# (código, decisão, status, relação, fala exata, origem)
DECISOES = [
 ("D15",
  "Criar um score de confiabilidade para os dados captados fora do cliente (não os documentos importados), "
  "por vários fatores além de quantidade e qualidade, incluindo a auditoria do dado e o quanto ele bate com o que já "
  "temos, com um score por tipo de dado e um portão em cada etapa do processo: abaixo do mínimo, a etapa é barrada.",
  "DEFINIDO",
  "Novo. Desenho e pesquisa na Espec. 15 (Arquitetura do Sistema/2 Especificação/15_SCORE_DE_CONFIABILIDADE_DOS_DADOS_EXTERNOS.md); no plano: 0.13, Trilha K da Fase 1, 2.18, 2.19, 3.8, 3.9",
  "a gente cria um score para cada tipo de dado, para a gente conseguir ter meio que uma barreira, um portão, a cada fragmento do processo do Oria Digital",
  "Pedido do dono na sessão de 23/11/2026 com o Claude"),
 ("D15.1",
  "Documentos oficiais emitidos por terceiro e trazidos pelo cliente (SPED, Registrato/SCR, certidões) entram no score "
  "como dado externo só com recibo, hash ou autenticidade conferidos; sem isso, contam como documento do cliente.",
  "DEFINIDO", "Espec. 15 §1 e §4 (veto de custódia); item 1.K2", "Sim, com recibo", "Respostas do dono às perguntas da sessão de 24/11/2026"),
 ("D15.2",
  "No portal interno, cada dado externo mostra o resultado do portão, a classe e o score (com a cobertura e o motivo).",
  "DEFINIDO", "Espec. 15 §4; item 1.K5", "Resultado + classe + score", "Respostas do dono às perguntas da sessão de 24/11/2026"),
 ("D15.3",
  "Qualquer analista pode liberar um dado que o portão mandou para REVISÃO, em qualquer gravidade, sempre com "
  "justificativa registrada.",
  "DEFINIDO",
  "Diverge da recomendação da Espec. 15 (Sócio nas gravidades alta e crítica). Vale para liberar o DADO; a aprovação do "
  "DIAGNÓSTICO com ressalvas continua pela E3 e pela E3-1. Toda liberação entra na revisão semanal (D15.13)",
  "Qualquer analista", "Respostas do dono às perguntas da sessão de 24/11/2026"),
 ("D15.4",
  "Durante o piloto, antes da calibração, o portão bloqueia pelos VETOS e pelos PISOS (nota mínima por dimensão): piso "
  "falho manda para REVISÃO. Os pesos e o score ponderado rodam em modo sombra até a calibração (item 3.8).",
  "DEFINIDO",
  "Diverge da recomendação da Espec. 15 (só os vetos). Afeta a Espec. 15 §5A e os itens 1.K2 e 1.K3 do plano",
  "Vetos e pisos", "Respostas do dono às perguntas da sessão de 24/11/2026"),
 ("D15.5",
  "O cliente e o credor veem só a ressalva, com o motivo e o efeito; o score e a classe ficam internos.",
  "DEFINIDO", "Espec. 15 §5; regra 1 do projeto", "Só a ressalva", "Respostas do dono às perguntas da sessão de 24/11/2026"),
 ("D15.6",
  "No piloto, quem rotula a amostra de calibração do score (dado externo certo ou errado) é o dono, com o Claude "
  "preparando as amostras.",
  "DEFINIDO", "Item 3.8; o mesmo papel da D4-1", "Eu (o dono), no piloto", "Respostas do dono às perguntas da sessão de 24/11/2026"),
 ("D15.7",
  "A divergência entre o dado externo e o documento do cliente não baixa a confiança no dado externo: é o achado do "
  "Conferidor. Só baixa a divergência com outra fonte externa independente ou com uma identidade aritmética.",
  "DEFINIDO", "Espec. 15 §3 (B1); D3, D3-3", "Não, é o achado", "Respostas do dono às perguntas da sessão de 24/11/2026"),
 ("D15.8",
  "Os pesos, mínimos, coberturas, pisos e tetos da Espec. 15 §5A (v2: mediana de três avaliações independentes) são o "
  "ponto de partida, como hipótese a calibrar (item 3.8); só passam a bloquear pelo score depois da calibração.",
  "DEFINIDO", "Espec. 15 §5A; casos em 15_anexos/casos_do_score.py",
  "Seguimos com sua recomendação: Refazer o §5A da Espec. 15 [...] gostei dessa proposta e dessa versão",
  "Pedido do dono na sessão de 23/11/2026 com o Claude e de 24/11/2026"),
]
REGRAS = [
 ("D15.9", "Base legal por destino: o mesmo dado pode servir ao uso interno e travar na saída para terceiros (sigilo bancário, licença de bureau)."),
 ("D15.10", "“Nada consta” só vale com execução provada e cobertura declarada; sem isso, é reprovado em todo agente."),
 ("D15.11", "Propagação: um número calculado herda o menor score e o pior resultado dos seus insumos."),
 ("D15.12", "Frescor medido contra a data de referência do uso, não contra hoje."),
 ("D15.13", "Alerta de carimbo: portão em que o humano libera sem alterar mais de 95% das revisões gera alerta de calibração."),
 ("D15.14", "O Auditor confere 5% dos aprovados e todos os que passaram com até 5 pontos de folga; isso alimenta o histórico de acerto."),
 ("D15.15", "Fonte em estreia: teto de score de 90 (oficial) ou 80 (demais) até 30 conferências; o histórico entra na conta a partir de 10."),
]
for c, d in REGRAS:
    DECISOES.append((c, d, "DEFINIDO", "Espec. 15 §5A.5", "aprovo as 7 ideias sugeridas", "Pedido do dono na sessão de 23/11/2026 com o Claude"))
DECISOES += [
 ("D4-1",
  "No piloto, quem monta o gabarito de 30 a 50 páginas (D4) é o dono, com o Claude preparando as amostras.",
  "DEFINIDO", "Fecha a pendência “quem monta o gabarito (papel)” da D4; itens 1.J2 e 3.4", "Eu (o dono), no piloto", "Respostas do dono às perguntas da sessão de 24/11/2026"),
 ("J7",
  "O slide 5 do deck mantém “mais de 30 fontes”: é a meta do que o sistema terá de fazer, e serve para orientar a "
  "construção. O deck não muda.",
  "DEFINIDO",
  "Fecha a pendência do slide 5. Exceção explícita à regra 6 da documentação do deck (nada no presente que ainda não "
  "existe) para este número",
  "Não mudar o BP, manter essas metas e previsões do que o sistema terá que fazer internamente para construirmos",
  "Respostas do dono às perguntas da sessão de 24/11/2026"),
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
 '<h2 id="sec-22">22. Adendo cumulativo v0.1.6 — score de confiabilidade do dado externo (23–24/11/2026)</h2>',
 '<p><strong>Data do registro:</strong> 24/11/2026<br/>'
 '<strong>Natureza:</strong> o score de confiabilidade do dado externo e os portões por agente (D15), as respostas do dono '
 'às perguntas da Espec. 15 (D15.1–D15.8), as 7 regras aprovadas (D15.9–D15.15), o papel de quem monta o gabarito (D4-1) '
 'e o slide 5 do deck (J7).<br/>'
 '<strong>Preservação:</strong> todo o texto das versões 0.1.0 a 0.1.5 acima foi mantido sem alteração. '
 '<strong>Este adendo registra decisões de projeto; não comprova implementação.</strong></p>',
 '<h3 id="sec-22-1">22.1 Decisões</h3>',
 '<div class="table-wrap"><table><thead><tr><th>Código</th><th>Decisão</th><th>Status</th>'
 '<th>Relação com versões anteriores / repositório</th><th>Fala do dono (trecho) · origem</th></tr></thead><tbody>'
 + linhas + '</tbody></table></div>',
 '<h3 id="sec-22-2">22.2 Pendências fechadas</h3>',
 tabela(["Pendência", "Situação"], [
  ("Quem monta o gabarito (papel) — D4", "Fechada pela D4-1: o dono, no piloto"),
  ("Deck, slide 5: “mais de 30 fontes”", "Fechada pela J7: o slide fica como está, como meta de construção"),
  ("Perguntas D15.1–D15.8 da Espec. 15", "Fechadas por D15.1–D15.8"),
 ]),
 '<h3 id="sec-22-3">22.3 Pendências que continuam abertas, por escolha do dono</h3>',
 tabela(["Pendência", "Situação"], [
  ("Segundo revisor na Partners (R1): quem é a pessoa", "Aberta: o dono indica depois"),
  ("Gestão das integrações (N-C5a)", "Aberta, como o dono pediu na entrevista"),
  ("Primeiro cliente além da Partners (A6)", "Aberta, como o dono pediu na entrevista"),
 ]),
 '<h3 id="sec-22-4">22.4 Registro de versão aditivo</h3>',
 tabela(["Versão", "Data", "Alteração", "Situação"], [
  ("0.1.6", "24/11/2026", "Adendo com D15, D15.1–D15.15, D4-1 e J7. Conteúdo das versões 0.1.0–0.1.5 preservado.",
   "Decisão do dono; implementação não comprovada"),
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


rep("<title>Oria Digital | Registro de decisões e pendências | v0.1.5</title>",
    "<title>Oria Digital | Registro de decisões e pendências | v0.1.6</title>")
rep("Versão cumulativa 0.1.5 · 23 de novembro de 2026", "Versão cumulativa 0.1.6 · 24 de novembro de 2026")
rep('<a href="#sec-21">21. Adendo cumulativo v0.1.5 — base da gravidade “alto”</a></aside>',
    '<a href="#sec-21">21. Adendo cumulativo v0.1.5 — base da gravidade “alto”</a>\n'
    '<a href="#sec-22">22. Adendo cumulativo v0.1.6 — score do dado externo</a></aside>')
rep('<main><div class="notice"><strong>Atualização desta versão (0.1.5):</strong>',
    '<main><div class="notice"><strong>Atualização desta versão (0.1.6):</strong> incluída ao final a seção 22, com o '
    'score de confiabilidade do dado externo (D15 a D15.15), o papel de quem monta o gabarito (D4-1) e o slide 5 do deck '
    '(J7). Todo o texto das versões anteriores foi mantido, inclusive os avisos a seguir.</div>'
    '<div class="notice"><strong>Atualização desta versão (0.1.5):</strong>')
rep("</article></main></div>", adendo + "\n</article></main></div>")
out_path.write_text(out, encoding="utf-8")
print("ok", len(DECISOES), len(out))
