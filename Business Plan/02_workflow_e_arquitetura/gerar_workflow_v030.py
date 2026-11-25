"""Gera o workflow v0.3.0 do Oria Digital (HTML autocontido, SVG fixo).

Mantém a linguagem visual do v0.2.0 (nós com faixa, cores por tipo, setas ortogonais, seções numeradas,
barra de navegação e zoom) e aplica as decisões do registro v0.1.3. Cada bloco leva um selo de status:
EXISTE (no código hoje), EXISTE · EVOLUIR, PILOTO (primeira entrega da v1), V1 (entregas seguintes da v1),
FUTURO, EM ESTUDO (plataforma sujeita ao estudo comparativo). Uso: python3 -I gerar_workflow_v030.py saida.html
"""
import html
import sys

E = html.escape
FONT = "Inter,Segoe UI,Arial,sans-serif"
W = 2600

KINDS = {  # fill, stroke, faixa, texto  (paleta do v0.2.0)
    "root": ("#155d68", "#0e4552", "#9fe2de", "#ffffff"),
    "stage": ("#e9f4f6", "#92c5cb", "#4e9ba7", "#244e5c"),
    "gate": ("#fff5dd", "#edcb87", "#d7a14c", "#735427"),
    "note": ("#f3f7f9", "#d1e0e6", "#a1bcc8", "#456171"),
    "agent": ("#e7f0fa", "#a4c1dd", "#5b8bb6", "#264c6b"),
    "function": ("#f5f9fc", "#c7d6e2", "#91adca", "#365e75"),
    "review": ("#e5f5ed", "#89bda5", "#50977b", "#255c47"),
    "alert": ("#fff0ee", "#e7a69b", "#d87464", "#8a433e"),
    "platform": ("#e9f6ee", "#91bda5", "#5da383", "#275a45"),
    "alt": ("#f5faf7", "#c7ded0", "#88b69c", "#326553"),
    "improve": ("#efeefb", "#b9b3e3", "#7d72c9", "#3f3775"),
}
STATUS = {
    "EXISTE": "#1f6b45", "EXISTE · EVOLUIR": "#4f9a76", "PILOTO": "#2f6fb0",
    "V1": "#6a5bb0", "FUTURO": "#7f8e9c", "EM ESTUDO": "#c08a2e",
}

out = []
late = []  # legendas desenhadas por cima das setas, com fundo
sections = []  # (id, y)


def t(x, y, s, size=14, weight=460, fill="#244e5c", anchor="middle"):
    out.append(f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-size="{size}" font-weight="{weight}" '
               f'fill="{fill}" font-family="{FONT}">{E(s)}</text>')


def label_bg(x, y, s, size=15, weight=600, fill="#5f7c88", bg="#fbfdfe"):
    w = 0.56 * size * len(s) + 24
    late.append(f'<rect x="{x - w/2:.0f}" y="{y - size - 5}" width="{w:.0f}" height="{size + 14}" rx="8" fill="{bg}"/>')
    late.append(f'<text x="{x}" y="{y}" text-anchor="middle" font-size="{size}" font-weight="{weight}" fill="{fill}" font-family="{FONT}">{E(s)}</text>')


class Box:
    def __init__(s, x, y, w, h):
        s.x, s.y, s.w, s.h = x, y, w, h

    @property
    def cx(s): return s.x + s.w / 2

    @property
    def b(s): return s.y + s.h


def node(x, y, w, kind, label, title, lines=(), status=None, h=None):
    fill, stroke, band, ink = KINDS[kind]
    lines = [l for l in lines if l]
    h = h or (78 + 25 * len(lines) + (0 if label else -10))
    out.append(f'<g class="node {kind}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="16" fill="{fill}" '
               f'stroke="{stroke}" stroke-width="2" filter="url(#sh)"/>'
               f'<path d="M {x+16} {y+4} L {x+w-16} {y+4}" fill="none" stroke="{band}" stroke-width="6" stroke-linecap="round"/>')
    if label:
        t(x + 18, y + 25, label, 12, 750, ink, "start")
    if status:
        pw = 14 + 7.6 * len(status)
        px = x + w - pw - 12
        out.append(f'<rect x="{px:.0f}" y="{y+12}" width="{pw:.0f}" height="20" rx="10" fill="{STATUS[status]}"/>')
        t(px + pw / 2, y + 26, status, 11, 760, "#ffffff")
    cy = y + (50 if label else 40)
    t(x + w / 2, cy, title, 19 if kind != "function" else 17, 770, ink)
    for i, l in enumerate(lines):
        t(x + w / 2, cy + 27 + 25 * i, l, 16 if i == 0 else 14, 640 if i == 0 else 460, ink)
    out.append("</g>")
    return Box(x, y, w, h)


def edge(a, b, color="#8aa7b6", dash="", marker="arr", side=None):
    if side == "h":  # da lateral de a para a lateral de b
        y = a.y + a.h / 2
        x1, x2 = (a.x + a.w, b.x) if b.x > a.x else (a.x, b.x + b.w)
        d = f"M {x1:.0f} {y:.0f} L {x2:.0f} {y:.0f}"
    else:
        x1, y1, x2, y2 = a.cx, a.b, b.cx, b.y
        if abs(x1 - x2) < 1:
            d = f"M {x1:.0f} {y1:.0f} L {x2:.0f} {y2-2:.0f}"
        else:
            my = y1 + (y2 - y1) / 2
            d = f"M {x1:.0f} {y1:.0f} L {x1:.0f} {my:.0f} L {x2:.0f} {my:.0f} L {x2:.0f} {y2-2:.0f}"
    out.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="2.5" stroke-linecap="round" '
               f'stroke-linejoin="round" stroke-dasharray="{dash}" marker-end="url(#{marker})"/>')


def row(y, specs, gap=40, left=60, right=W - 60):
    """specs: lista de (largura, kwargs). Centraliza a linha."""
    total = sum(w for w, _ in specs) + gap * (len(specs) - 1)
    x = left + ((right - left) - total) / 2
    boxes = []
    for w, kw in specs:
        boxes.append(node(round(x), y, w, **kw))
        x += w + gap
    return boxes


def section_title(y, num, title, sub, color):
    t(70, y, f"{num} / {title}", 20, 800, color, "start")
    t(W - 70, y, sub, 15, 620, color, "end")


bg_rects = []

# ---------------------------------------------------------------- 01 CICLO DO MANDATO
y0 = 28
sections.append(("goTop", 0))
section_title(y0 + 42, "01", "CICLO DO MANDATO E ANÁLISES", "Decisões do registro v0.1.3 · serviço operado pela equipe Oria Digital", "#688998")
root = node(1010, 96, 580, "root", "PLATAFORMA", "ORIA DIGITAL",
            ["Diagnóstico → reestruturação → acompanhamento", "Empresa própria · Oria Partners = 1ª cliente piloto"])
trig = row(270, [
    (560, dict(kind="stage", label="GATILHO", title="Novo mandato", lines=["Pedido do analista · equipe Oria Digital opera", "Sócio · Analista · Leitura · Técnico"], status="EXISTE · EVOLUIR")),
    (560, dict(kind="stage", label="GATILHO", title="Rotina de monitoramento", lines=["Frequência e duração por contrato", "Pós-reestruturação e carteiras de credores"], status="V1")),
    (560, dict(kind="stage", label="GATILHO", title="Eventos e alertas", lines=["Regras objetivas + avaliação dos agentes", "Processos, protestos, notícias, covenants"], status="V1")),
])
for b in trig:
    edge(root, b)
portal = node(70, 470, 520, "note", "PORTAL DO CLIENTE", "Envio e acompanhamento",
              ["Link seguro por mandato (login 2FA antes", "do 1º cliente além da Partners)"], status="PILOTO", h=150)
entrada = row(470, [
    (620, dict(kind="stage", label="01 · ENTRADA", title="Documentos do cliente", lines=["Upload em lote · Kit do mandato", "Registrato/SCR obrigatório"], status="EXISTE · EVOLUIR")),
    (560, dict(kind="stage", label="01 · ENTRADA", title="Open Finance", lines=["Via integradora regulada (Res. Conj. 21)", "Upload de extratos sempre disponível"], status="V1")),
], left=640)
edge(trig[0], entrada[0])
edge(trig[1], entrada[1])
edge(portal, entrada[0], side="h")
t(330, 645, "Consultoria-cliente vê os mandatos dos clientes dela;", 14, 600, "#5f7c88")
t(330, 666, "a empresa vê só o próprio mandato. Ninguém vê outra organização.", 14, 600, "#5f7c88")

ext = row(700, [
    (760, dict(kind="stage", label="02 · EXTRAÇÃO · CAPTADOR", title="Código e ferramentas primeiro", lines=["IA extrai só onde o código falhar", "IA revisora confere PDF e imagem · estruturados: SQL"], status="EXISTE · EVOLUIR")),
    (760, dict(kind="stage", label="03 · CAPTAÇÃO EXTERNA · CAPTADOR", title="Dados externos e de mercado", lines=["SPED · Registrato · OFX · NF-e · fontes públicas", "Mercado: BCB, Focus, CVM, IBGE, CAGED (atualizados)"], status="PILOTO")),
])
for e_ in entrada:
    for x_ in ext:
        if (e_ is entrada[0]) or (x_ is ext[1]):
            edge(e_, x_)
pagos = node(1990, 900, 560, "note", "03 · CAPTAÇÃO · FONTES PAGAS", "Integrador de dados",
             ["Processos, protestos, bureaus", "Teto de custo por mandato"], status="V1")
cert = node(1990, 1045, 560, "note", "03 · CAPTAÇÃO · CREDENCIADAS", "Certificado / procuração",
            ["e-CAC, NF-e, FGTS com custódia segura", "Só após política e parecer jurídico"], status="FUTURO")
reg = node(1990, 1190, 560, "note", "03 · CAPTAÇÃO · REGISTRADORAS", "Recebíveis já cedidos",
           ["CERC · B3 · Núclea", "Até existir, não é exibido como prova"], status="FUTURO")
edge(ext[1], pagos, color="#cb9951", dash="7 5", marker="arr2")

cruz = node(840, 920, 920, "gate", "04 · CRUZAMENTO · CONFERIDOR", "Extração × captação externa",
            ["Externo = referência de maior peso · os dois valores ficam guardados",
             "Veredito: divergências · resolvido (régua de baixo impacto) · humano · sugestões",
             "Divergência relevante vira achado do diagnóstico"], status="PILOTO")
edge(ext[0], cruz)
edge(ext[1], cruz)
pend = node(70, 930, 640, "note", "SEM DADO / FALHA", "Pendências de dados",
            ["Lacuna declarada com motivo e efeito", "Só etapas dependentes aguardam"], status="EXISTE")
edge(cruz, pend, color="#cb9951", dash="7 5", marker="arr2", side="h")
portao = node(990, 1145, 620, "gate", "CONTROLE", "PORTÃO DE QUALIDADE",
              ["Conferências determinísticas em SQL", "Nunca valor presumido · proveniência por dado"], status="EXISTE")
edge(cruz, portao)
sup = node(990, 1330, 620, "root", "NÚCLEO · SUPERVISOR / ORQUESTRADOR", "05 · DISTRIBUI E COORDENA",
           ["1ª rodada independente entre especialistas", "Memória central por organização e mandato"], status="PILOTO")
edge(portao, sup)
memo = node(70, 1330, 640, "note", "ACESSO SOB PERMISSÃO", "Base central (memória)",
            ["Agentes NÃO guardam memória própria", "Separação por organização (RLS) + mínimo privilégio"], status="EXISTE · EVOLUIR")
edge(memo, sup, color="#8aa7b6", dash="4 5", side="h")
motor = node(1890, 1330, 640, "review", "AUTORIDADE NUMÉRICA", "Motor determinístico",
             ["SQL + fórmulas · único lugar que calcula", "Agentes só interpretam (nunca calculam)"], status="EXISTE · EVOLUIR")
edge(motor, sup, color="#77ad96", dash="4 5", marker="arr3", side="h")

label_bg(W / 2, 1566, "1ª RODADA · CADA ESPECIALISTA VÊ DADOS E EVIDÊNCIAS, NÃO AS CONCLUSÕES DOS OUTROS", 19, 750, "#4e7493")
ag = [
    ("Conferidor", "Contábil e fiscal", "BP · DRE · ECD · conciliações", "PILOTO"),
    ("Dívida", "Endividamento", "Mapa · covenants · capacidade", "PILOTO"),
    ("Caixa", "Liquidez e giro", "NCG · aging · 13 semanas", "PILOTO"),
    ("Mercado", "Benchmarks", "Juro vs. BCB · setor · região", "PILOTO"),
    ("Risco", "Riscos e sinais", "Processos · bureaus · crise", "V1"),
    ("Estrategista", "Custos e propostas", "Cortes · renegociação · simulação", "V1"),
    ("Entregas", "Relatórios", "Excel · PDF · apresentação", "V1"),
]
agb = row(1590, [(330, dict(kind="agent", label="ESPECIALISTA", title=n, lines=[a, b], status=s)) for n, a, b, s in ag], gap=26)
for b in agb:
    edge(sup, b)
label_bg(W / 2, 1766, "Captador atua nas etapas 02–03 · o catálogo de 11 agentes é referência flexível (pode crescer ou encolher com evidência)", 15, 600, "#5f7c88")
fun = row(1790, [(330, dict(kind="function", label="", title="Entrega ao Supervisor", lines=["Interpretação + evidência", "Incongruência → revisão"], h=104)) for _ in ag], gap=26)
for a_, f_ in zip(agb, fun):
    edge(a_, f_, color="#91adca")

cons = node(990, 1955, 620, "root", "NÚCLEO", "06 · SUPERVISOR CONSOLIDA",
            ["Cruza conclusões · não inventa consenso", "Toda divergência é notificada ao analista"], status="PILOTO")
for f_ in fun:
    edge(f_, cons, color="#90aebc")
deb = node(70, 1955, 760, "note", "SE HOUVER DIVERGÊNCIA", "Verificação independente + debate",
           ["Sem limite fixo de rodadas: o Supervisor decide parar", "Decide sozinho só baixo impacto (<1% linha e <0,5% EBITDA/dívida)"], status="PILOTO")
edge(cons, deb, color="#cb9951", dash="7 5", marker="arr2", side="h")
aud = node(990, 2145, 620, "review", "AUDITORIA HÍBRIDA", "07 · AUDITOR INDEPENDENTE",
           ["Motor recalcula · Auditor revisa a execução das IAs", "Evidências, fontes e coerência — sem recalcular"], status="PILOTO")
edge(cons, aud)
cic = node(1790, 2145, 760, "alert", "EM CASO DE FALHA", "Até 3 tentativas automáticas",
           ["Reextrair · reler · pedir dado · reinterpretar", "Nunca recalcular · depois: resumo + dossiê ao analista"], status="PILOTO")
edge(aud, cic, color="#d87464", dash="7 5", side="h")
dep = node(990, 2335, 620, "gate", "GATE DE EXECUÇÃO", "08 · DEPENDÊNCIAS",
           ["Executa o que não depende do dado falho", "Dependentes aguardam ou levam ressalva"], status="EXISTE · EVOLUIR")
edge(aud, dep)
fila = node(70, 2335, 760, "gate", "DECISÃO HUMANA", "Fila do analista",
            ["Campos estruturados · justificativa · evidência", "Prazo: crítico 1 · alto 2 · médio 5 dias úteis → Sócio"], status="PILOTO")
edge(dep, fila, color="#cb9951", dash="7 5", marker="arr2", side="h")
grav = node(1790, 2335, 760, "note", "GRAVIDADE (RÉGUAS AJUSTÁVEIS)", "Crítico · alto · médio · baixo",
            ["Crítico: muda conclusão, >5% EBITDA/dívida, passivo oculto", "Agentes só podem subir o nível, nunca descer"], status="PILOTO")
apr = node(990, 2525, 620, "review", "PORTÃO OBRIGATÓRIO", "09 · APROVAÇÃO HUMANA",
           ["Para fora: segundo revisor (piloto: analista Partners)", "≤3 ressalvas altas/críticas · acima: só o Sócio"], status="EXISTE · EVOLUIR")
edge(dep, apr)
conf = node(70, 2525, 760, "note", "POR DOCUMENTO", "Conferência",
            ["Quem conferiu, quando e qual versão", "Recebido → extraído → cruzado → conferido"], status="PILOTO")
med = node(1790, 2525, 760, "note", "MEDIÇÃO AUTOMÁTICA POR MANDATO", "Prova do “dias, não meses”",
           ["Dias · horas de analista · custo IA e dados", "Erros por etapa/agente · achados em R$"], status="PILOTO")
outs = row(2720, [
    (600, dict(kind="review", label="USO INTERNO", title="10A · RELATÓRIO INTERNO", lines=["Diagnóstico completo + erros e pendências", "Riscos, justificativas, histórico"], status="EXISTE · EVOLUIR")),
    (600, dict(kind="review", label="USO DO CLIENTE", title="10B · ENTREGA AO CLIENTE", lines=["Excel em fórmula, cada número → documento e página", "PDF com limitações relevantes · autoria Oria Digital"], status="PILOTO")),
    (560, dict(kind="review", label="QUANDO O MANDATO PEDIR", title="Apresentação a credores", lines=["Propostas simuladas (carência, desconto,", "dinheiro novo) · humano decide"], status="V1")),
])
for b in outs:
    edge(apr, b)
mon = row(2915, [
    (600, dict(kind="stage", label="CICLO DO CONTRATO", title="11 · MONITORAMENTO", lines=["Caixa, dívida, covenants, Registrato,", "processos, protestos, notícias, mercado"], status="V1")),
    (600, dict(kind="review", label="PADRÃO MENSAL", title="Relatório periódico", lines=["Indicadores × plano · calendário × permanente", "Revisão humana antes de ir ao cliente"], status="V1")),
    (600, dict(kind="alert", label="IMEDIATO", title="12 · ALERTAS", lines=["Só no portal interno da Oria Digital", "Analista decide se avisa o cliente"], status="V1")),
])
edge(outs[1], mon[0])
edge(mon[0], mon[1], side="h")
edge(mon[1], mon[2], color="#d87464", dash="7 5", side="h")
t(W / 2, 3130, "↻ Novas evidências reabrem a análise; diagnósticos aprovados são preservados e versionados.", 18, 640, "#678998")
s1_end = 3165
bg_rects.append((y0, s1_end - y0, "#fbfdfe", "#dce8ed"))

# ---------------------------------------------------------------- 02 AUTOAPRIMORAMENTO
y2 = s1_end + 30
sections.append(("goImprove", y2))
section_title(y2 + 42, "02", "AUTOAPRIMORAMENTO E MUDANÇAS TÉCNICAS", "Entra na v1 depois do piloto · quem propõe nunca aprova", "#63719c")
inp = row(y2 + 80, [
    (560, dict(kind="improve", label="SEM AUTORIZAÇÃO PRÉVIA", title="Rotina semanal", lines=["Erros, correções, ressalvas (por gravidade)", "Relatório ao Técnico em dia fixo"], status="V1")),
    (560, dict(kind="alert", label="AUTORIZAÇÃO Nº 1", title="Erro grave fora da rotina", lines=["Aviso no portal + pedido para investigar", "Autorizar · não autorizar · aguardar"], status="V1")),
    (560, dict(kind="alert", label="EXCEÇÃO", title="Após reversão automática", lines=["Investiga e testa sem autorização nº 1", "Versão estável segue funcionando"], status="V1")),
])
hist = node(990, y2 + 280, 620, "improve", "MEMÓRIA CENTRAL", "Histórico e evidências",
            ["Primeiro: análises, erros, correções, justificativas", "Depois: documentos originais, se autorizado"], status="V1")
for b in inp:
    edge(b, hist, color="#9a92d6")
faseA = node(330, y2 + 470, 860, "improve", "FASE A · INICIAL", "Só propõe prompts e regras",
             ["Proposta em rascunho · nada vai à produção sem o Técnico", "Erros validados pelo Auditor Independente"], status="V1")
faseB = node(1410, y2 + 470, 860, "improve", "FASE B · APÓS O GATILHO", "Código, ferramentas e migrations",
             ["Gatilho: ≥50 erros em ≥3 etapas/agentes", "e ≥60% das propostas aprovadas sem piora (mín. 10)"], status="FUTURO")
edge(hist, faseA)
edge(faseA, faseB, color="#9a92d6", dash="7 5", side="h")
sand = row(y2 + 660, [
    (560, dict(kind="note", label="EXPERIMENTAÇÃO CONTROLADA", title="Ambiente de teste descartável", lines=["Cópia por mudança · sem credenciais de produção", "Dados inventados ou anonimizados"], status="V1")),
    (560, dict(kind="note", label="MUDANÇAS QUE AFETAM NÚMERO", title="Backtest", lines=["Casos reais anonimizados (se o contrato permitir)", "+ dados inventados · antigos são referência"], status="V1")),
    (560, dict(kind="gate", label="PROTEÇÃO DA MEDIÇÃO", title="Gabarito com parte oculta", lines=["Agente não altera gabarito, testes, portões", "Melhora no conhecido e piora no oculto = rejeita"], status="V1")),
])
edge(faseA, sand[0])
edge(faseA, sand[1])
edge(faseA, sand[2])
rel = node(990, y2 + 860, 620, "improve", "PROPOSTA PARA DECISÃO", "Relatório técnico-econômico",
           ["Antes/depois · regressões · custo (tokens, APIs, infra)", "Riscos · estratégia de publicação e reversão"], status="V1")
for b in sand:
    edge(b, rel, color="#9a92d6")
apt = node(990, y2 + 1050, 620, "review", "AUTORIZAÇÃO", "APROVAÇÃO TÉCNICA",
           ["Papel Técnico · quem propôs não aprova", "Afeta número/conclusão: + aprovação do Sócio"], status="V1")
edge(rel, apt)
rej = node(70, y2 + 1050, 760, "note", "NÃO AUTORIZADO", "Rejeitado ou ajustes pedidos",
           ["Revisar hipótese e voltar aos testes", "Nenhuma mudança em produção"], status="V1")
edge(apt, rej, color="#cb9951", dash="7 5", marker="arr2", side="h")
rev = node(1790, y2 + 1050, 760, "gate", "VERIFICAÇÃO OBRIGATÓRIA", "Reversão comprovada",
           ["Chave liga/desliga por mudança", "Banco: acrescenta primeiro, remove depois"], status="V1")
edge(apt, rev, side="h")
pub = row(y2 + 1240, [
    (760, dict(kind="review", label="MUDANÇA ADITIVA, NENHUM NÚMERO MUDA", title="Publica para todos", lines=["Monitoramento imediato", "Reversão = desligar a chave"], status="V1")),
    (760, dict(kind="review", label="MEXE EM EXTRAÇÃO, CÁLCULO, PREMISSA, BANCO", title="Publicação gradual", lines=["Sombra → 1–2 clientes → todos", "Comparação de resultados em cada passo"], status="V1")),
])
edge(apt, pub[0])
edge(apt, pub[1])
mrev = node(990, y2 + 1430, 620, "alert", "PROTEÇÃO DA OPERAÇÃO", "Monitorar e reverter",
            ["Erro grave → desliga a chave e avisa no portal", "Backup é só recuperação de desastre"], status="V1")
edge(pub[0], mrev, color="#d87464")
edge(pub[1], mrev, color="#d87464")
s2_end = y2 + 1600
bg_rects.append((y2, s2_end - y2, "#fcfcff", "#e1e4f2"))

# ---------------------------------------------------------------- 03 CONTROLES TRANSVERSAIS
y3 = s2_end + 30
sections.append(("goCtrl", y3))
section_title(y3 + 42, "03", "CONTROLES TRANSVERSAIS: QUALIDADE, SEGURANÇA E DADOS", "Valem para todo o ciclo", "#6f7f8c")
c1 = row(y3 + 80, [
    (600, dict(kind="gate", label="AUTONOMIA POR ETAPA", title="N0 → N1 → N2 → N3", lines=["N2 exige ~300 amostras (parte cega), ≥95%", "Extração volta a N1 até medir · piora rebaixa"], status="EXISTE · EVOLUIR")),
    (600, dict(kind="gate", label="QUALIDADE DA EXTRAÇÃO", title="Gabarito de páginas reais", lines=["30–50 páginas, célula a célula", "Refeito a cada semestre · decide modelo/fornecedor"], status="PILOTO")),
    (600, dict(kind="note", label="MODELOS DE IA", title="Dois ou mais provedores", lines=["Troca automática · roteamento por região", "Cliente pode exigir “só Brasil”"], status="PILOTO")),
    (600, dict(kind="note", label="CUSTO", title="Medido por etapa e agente", lines=["Alerta acima de US$ 5 por diagnóstico", "Barato classifica · médio extrai · topo sintetiza"], status="PILOTO")),
], gap=30)
c2 = row(y3 + 290, [
    (600, dict(kind="review", label="ISOLAMENTO", title="Por organização (RLS)", lines=["Chaves de mínimo privilégio", "Teste automático de vazamento"], status="PILOTO")),
    (600, dict(kind="review", label="TRILHA DE AUDITORIA", title="À prova de adulteração", lines=["Cadeia de hashes + cópia externa imutável", "Antes do 1º cliente além da Partners"], status="V1")),
    (600, dict(kind="review", label="AMBIENTES", title="Dev · teste · produção", lines=["Dado real só sai anonimizado", "Sem credenciais de produção fora dela"], status="PILOTO")),
    (600, dict(kind="alert", label="CONTINUIDADE", title="Backup e recuperação", lines=["Hoje: cópia diária criptografada (provisória)", "Produção: perda de minutos, volta em 4 h, teste trimestral"], status="PILOTO")),
], gap=30)
c3 = row(y3 + 500, [
    (800, dict(kind="note", label="DADOS PESSOAIS", title="Retenção em 3 camadas", lines=["Originais: 6 meses após o contrato · entregáveis: 5 anos", "Trilha sem dado pessoal · bloqueio com processo"], status="V1")),
    (800, dict(kind="note", label="ANTES DO PILOTO", title="RIPD + contrato de dados com a IA", lines=["Mapa de dados, fluxos e controles", "Cláusulas-padrão ANPD com cada provedor"], status="PILOTO")),
    (800, dict(kind="note", label="BENCHMARKS PRÓPRIOS", title="Dados de vários clientes", lines=["Só anonimizados e com cláusula contratual", "Mandatos sem cobertura ficam de fora"], status="V1")),
], gap=30)
s3_end = y3 + 690
bg_rects.append((y3, s3_end - y3, "#fbfcfc", "#e0e6ea"))

# ---------------------------------------------------------------- 04 INFRAESTRUTURA
y4 = s3_end + 30
sections.append(("goInfra", y4))
section_title(y4 + 42, "04", "INFRAESTRUTURA: HOJE × CANDIDATOS DO ESTUDO", "Nada abaixo está decidido: estudo com ≥5 opções por item, antes do piloto", "#508e6e")
est = node(800, y4 + 80, 1000, "gate", "PRIMEIRA ENTREGA DO PLANO", "Estudo comparativo de infraestrutura",
           ["≥5 opções por item · custo, complexidade, capacidade (memória, processamento, disco)",
            "Agentes podem começar em paralelo, sem prender a uma plataforma"], status="EM ESTUDO")
infra = [
    ("Coordenação dos agentes", "Hoje: estados no banco + n8n dispara", "Candidatos: máquina de estados no banco · LangGraph · DBOS/Temporal · outros", "EM ESTUDO"),
    ("Hospedagem dos agentes", "Hoje: não há serviço próprio", "Candidatos: Cloud Run · ECS Fargate · funções do portal · outros", "EM ESTUDO"),
    ("Banco de dados", "Hoje: Supabase (plano gratuito, sem backup)", "Candidatos: Supabase Pro/Team · Neon · Cloud SQL · RDS · outros", "EM ESTUDO"),
    ("Automação / coleta", "Hoje: n8n no PikaPods (só até a produção)", "Candidatos: n8n próprio no Brasil · n8n Cloud · workers próprios", "EM ESTUDO"),
    ("Observabilidade da IA", "Preferido: Langfuse no próprio servidor", "Candidatos: Langfuse Cloud · Phoenix · LangSmith · outros", "EM ESTUDO"),
    ("Arquivos e evidências", "Hoje: Supabase Storage", "Candidatos: Storage + cópia externa · S3 · GCS", "EM ESTUDO"),
    ("Portal e aprovação", "Hoje: Next.js + Vercel", "Mantido · login 2FA antes do 1º cliente além da Partners", "EXISTE · EVOLUIR"),
    ("Modelos de IA", "Hoje: OpenAI (um provedor)", "Dois ou mais com troca automática · candidatos: Anthropic, Google, OpenAI", "PILOTO"),
]
ib = []
for i, (title, l1, l2, st) in enumerate(infra):
    col, rw = i % 4, i // 4
    ib.append(node(60 + col * 630, y4 + 290 + rw * 190, 600, "platform", "PLATAFORMA", title, [l1, l2], status=st))
for b in ib[:4]:
    edge(est, b, color="#77ad96", marker="arr3")
t(W / 2, y4 + 700, "Tecnologias do workflow v0.2.0 (LangGraph, Cloud Run, Polars/DuckDB, pgvector, Supabase Queues, Airbyte/Fivetran, Okta/Auth0) entram no estudo como candidatas, não como decisão.", 16, 600, "#4f8a6c")
s4_end = y4 + 740
bg_rects.append((y4, s4_end - y4, "#f3faf6", "#d7e9de"))

# ---------------------------------------------------------------- LEGENDA
yl = s4_end + 40
t(W / 2, yl, "LEGENDA · Azul: fluxo analítico | Verde: auditoria, aprovação e plataforma | Âmbar: controles e decisão humana | Vermelho: incidentes | Lilás: autoaprimoramento", 17, 620, "#59778a")
xs = 330
for nome, desc in [("EXISTE", "no código hoje"), ("EXISTE · EVOLUIR", "existe e muda"), ("PILOTO", "1ª entrega da v1"),
                   ("V1", "entregas seguintes"), ("FUTURO", "depois da v1 / condicionado"), ("EM ESTUDO", "plataforma a decidir")]:
    pw = 14 + 7.6 * len(nome)
    out.append(f'<rect x="{xs}" y="{yl+22}" width="{pw:.0f}" height="20" rx="10" fill="{STATUS[nome]}"/>')
    t(xs + pw / 2, yl + 36, nome, 11, 760, "#ffffff")
    t(xs + pw + 8, yl + 37, desc, 14, 560, "#59778a", "start")
    xs += pw + 8 + 8 * len(desc) + 40
H = yl + 80

bg = [f'<rect width="{W}" height="{H}" fill="#f8fbfc"/>', f'<rect width="{W}" height="{H}" fill="url(#dots)" opacity=".6"/>']
for y, h, fill, stroke in bg_rects:
    bg.append(f'<rect x="25" y="{y}" width="2550" height="{h}" rx="27" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')

defs = ('<defs><pattern id="dots" width="24" height="24" patternUnits="userSpaceOnUse"><circle cx="2" cy="2" r="1" fill="#e4edf1"/></pattern>'
        + "".join(f'<marker id="{i}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
                  f'<path d="M 0 0 L 10 5 L 0 10 z" fill="{c}"/></marker>' for i, c in [("arr", "#8aa7b6"), ("arr2", "#cb9951"), ("arr3", "#77ad96")])
        + '<filter id="sh"><feDropShadow dx="0" dy="4" stdDeviation="5" flood-color="#244e5b" flood-opacity=".09"/></filter></defs>')
svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" '
       f'aria-label="Workflow v0.3.0 do Oria Digital: ciclo do mandato, agentes, autoaprimoramento, controles e infraestrutura">'
       + defs + "".join(bg) + "".join(out) + "".join(late) + "</svg>")

CSS = """:root{--bg:#edf3f6;--ink:#193c49;--muted:#6d8794;--line:#d9e5ea}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--bg);font-family:Inter,Segoe UI,Arial,sans-serif;color:var(--ink)}
header{padding:25px max(22px,calc((100vw - 1460px)/2));background:#f9fbfc;border-bottom:1px solid #d5e3e8;display:flex;flex-wrap:wrap;justify-content:space-between;gap:16px;align-items:center}
h1{font-size:30px;margin:0;letter-spacing:-.8px;color:#145a68}header p{font-size:14px;color:var(--muted);margin:8px 0 0}.meta{display:flex;gap:9px;flex-wrap:wrap;align-items:center}.chip{background:#e5f1f1;border:1px solid #c4d9df;border-radius:30px;color:#366875;font-size:12px;padding:7px 11px;font-weight:650}
.toolbar{max-width:1510px;margin:20px auto 10px;padding:0 16px;display:flex;align-items:center;flex-wrap:wrap;gap:8px}.toolbar button{border:1px solid #c7dade;border-radius:9px;padding:9px 14px;color:#285866;background:#fff;font-weight:650;cursor:pointer}.toolbar button:hover{background:#e9f3f5}.toolbar .sp{flex:1}
main{max-width:2640px;margin:0 auto;padding:0 13px 25px}.viewport{height:min(80vh,880px);min-height:510px;background:#f8fbfc;border:1px solid var(--line);border-radius:16px;overflow:auto;box-shadow:0 9px 32px #294e5d0e;position:relative}.viewport svg{display:block;max-width:none;height:auto;width:1700px;user-select:none}.notice{max-width:1510px;margin:12px auto 25px;padding:15px 20px;border:1px solid #d6e3e8;background:white;border-radius:11px;color:#476778;font-size:13px;line-height:1.6}.notice h2{font-size:15px;margin:4px 0 8px;color:#145a68}.notice ul{margin:6px 0;padding-left:20px}
footer{max-width:1510px;margin:0 auto;padding:0 18px 24px;font-size:12px;color:#69838f}a{color:#236379}
@media(max-width:700px){header{padding:20px}h1{font-size:23px}.viewport{height:73vh;min-height:490px}.toolbar button{padding:8px 10px;font-size:12px}}
@media print{@page{size:A1 portrait;margin:10mm}body{background:white}header{padding:0 0 10mm}.toolbar,.notice,footer{display:none!important}main{padding:0}.viewport{overflow:visible!important;height:auto;min-height:0;box-shadow:none;border:0}.viewport svg{width:100%!important;max-width:none}}"""

secs = "{" + ",".join(f"{k}:{v}" for k, v in sections) + "}"
JS = (f"(function(){{const box=document.getElementById('viewport'),svg=box.querySelector('svg');let width=1700;const H={H};const sections={secs};"
      "function setWidth(n){width=Math.max(900,Math.min(3400,n));svg.style.width=width+'px'}"
      "function jump(key){let y=sections[key]||0;box.scrollTo({top:y/H*svg.getBoundingClientRect().height,behavior:'smooth'});}"
      "for(let k of Object.keys(sections))document.getElementById(k).onclick=()=>jump(k);"
      "document.getElementById('zoomIn').onclick=()=>setWidth(width*1.25);document.getElementById('zoomOut').onclick=()=>setWidth(width/1.25);"
      "document.getElementById('fit').onclick=()=>setWidth(Math.max(900,box.clientWidth-12));})();")

MUDANCAS = [
    "Agentes: catálogo único de 11 (8 especialistas + Supervisor, Auditor, Autoaprimoramento), com os nomes do Business Plan (B1, D3-3).",
    "Extração redesenhada: código primeiro, IA onde falhar, IA revisora em PDF; captação externa e cruzamento pelo Conferidor, com o dado externo como referência e os dois valores guardados (D3).",
    "Supervisor decide só baixo impacto (régua objetiva); debate sem limite fixo; Auditor revisa a execução e o motor recalcula; 3 tentativas, não 5 (B3b-1, L5, B4, B5).",
    "Aprovação: segundo revisor para o que vai para fora (no piloto, analista da Partners); limite de ressalvas; fila com prazos por gravidade; botão Conferência (E1, R1, E3, E5, E6, G5).",
    "Cliente: portal com link seguro desde o piloto; consultoria-cliente vê os mandatos dos clientes dela; Excel com cada número ligado à página de origem (A5, G3, L4, G4).",
    "Autoaprimoramento: só propõe até o gatilho (≥50 erros validados, ≥3 etapas, ≥60% de propostas aprovadas); publicação por tipo; reversão por chave; backtest anonimizado; gabarito com parte oculta (F1–F6).",
    "Nova seção de controles transversais: autonomia com ~300 amostras, provedores múltiplos, custo medido, isolamento por organização, trilha com hash, 3 ambientes, backup, retenção em 3 camadas, RIPD (D1–D6, H4–H8, I2, I5).",
    "Infraestrutura: tudo vira candidato de um estudo com ≥5 opções por item, primeira entrega do plano, antes do piloto (H1–H3, H5, R2).",
    "Selos de status em cada bloco: EXISTE, EXISTE · EVOLUIR, PILOTO, V1, FUTURO, EM ESTUDO.",
]

page = f"""<!DOCTYPE html>
<html lang="pt-BR"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Oria Digital · Workflow v0.3.0</title><meta name="description" content="Workflow operacional do Oria Digital alinhado ao registro de decisões v0.1.3: ciclo do mandato, 11 agentes, autoaprimoramento, controles e infraestrutura em estudo."/>
<style>
{CSS}
</style></head>
<body>
<header><div><h1>ORIA DIGITAL <span style="font-weight:480;color:#4d8392">/ Workflow v0.3.0</span></h1><p>Ciclo do mandato · 11 agentes · autoaprimoramento · controles · infraestrutura em estudo</p></div><div class="meta"><span class="chip">Versão 0.3.0</span><span class="chip">19 novembro 2026</span><span class="chip">Base: registro de decisões v0.1.3</span><span class="chip">Selos indicam o que existe hoje</span></div></header>
<div class="toolbar"><button id="goTop">Ciclo do mandato</button><button id="goImprove">Autoaprimoramento</button><button id="goCtrl">Controles</button><button id="goInfra">Infraestrutura</button><span class="sp"></span><button id="zoomIn">Ampliar +</button><button id="zoomOut">Reduzir −</button><button id="fit">Ajustar largura</button><button onclick="window.print()">Imprimir / PDF</button></div>
<main><div class="viewport" id="viewport">{svg}</div></main>
<div class="notice"><h2>O que mudou em relação ao v0.2.0</h2><ul>{"".join(f"<li>{E(m)}</li>" for m in MUDANCAS)}</ul>
<p><strong>Como ler os selos:</strong> <b>EXISTE</b> = está no código hoje; <b>EXISTE · EVOLUIR</b> = existe e será alterado; <b>PILOTO</b> = primeira entrega da v1, com a Oria Partners; <b>V1</b> = entregas seguintes da v1; <b>FUTURO</b> = depois da v1 ou condicionado a parecer/parceria; <b>EM ESTUDO</b> = plataforma sujeita ao estudo comparativo. O diagrama registra decisões de projeto; ele não comprova implementação.</p></div>
<footer>Fontes: registro de decisões e pendências v0.1.3 (19/11/2026); workflow v0.2.0 (preservado); inspeção do repositório Oria-Digital. HTML autocontido: abre sem internet.</footer>
<script>
{JS}
</script></body></html>"""

open(sys.argv[1], "w", encoding="utf-8").write(page)
print("ok", H, len(page))
