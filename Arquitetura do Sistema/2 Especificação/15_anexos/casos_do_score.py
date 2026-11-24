"""Recalcula os casos do §5A.7 da Espec. 15 (score de confiabilidade do dado externo).

Uso:  python3 -I "Arquitetura do Sistema/2 Especificação/15_anexos/casos_do_score.py"

Imprime a tabela em Markdown. Se um peso, mínimo, piso ou regra do §5A mudar, mude AQUI e cole a
tabela nova no §5A.7: o documento e o cálculo não podem divergir.

Pesos: mediana das três avaliações independentes de 23/11/2026 (o Mercado somava 95; os 5 pontos
foram para o Frescor, B2). Notas dos casos: rubrica do §5A.1, piloto sem histórico de fonte.
"""
import json
NM = "nm"  # não medido: podia ser medido e não foi (reduz a cobertura)
NA = "na"  # não se aplica, ou fonte em estreia (sai da conta e da cobertura)
W = {  # pesos em %, por agente; cada linha soma 100
    "Captador": {"A1": 20, "A2": 10, "A3": 15, "B1": 5, "B2": 10, "B3": 20, "B5": 10, "B7": 10},
    "Conferidor": {"A1": 25, "A2": 15, "A3": 5, "B1": 20, "B2": 10, "B3": 10, "B5": 5, "B7": 10},
    "Mercado": {"A1": 25, "A2": 10, "A3": 5, "B1": 15, "B2": 25, "B3": 10, "B5": 10, "B7": 0},
    "Caixa": {"A1": 15, "A2": 5, "A3": 5, "B1": 25, "B2": 20, "B3": 20, "B5": 5, "B7": 5},
    "Divida": {"A1": 20, "A2": 5, "A3": 0, "B1": 15, "B2": 10, "B3": 25, "B5": 5, "B7": 20},
    "Risco": {"A1": 20, "A2": 15, "A3": 5, "B1": 15, "B2": 15, "B3": 20, "B5": 5, "B7": 5},
    "Estrategista": {"A1": 20, "A2": 15, "A3": 0, "B1": 25, "B2": 15, "B3": 15, "B5": 10, "B7": 0},
    "Entregas": {"A1": 20, "A2": 10, "A3": 0, "B1": 15, "B2": 15, "B3": 10, "B5": 5, "B7": 25},
}
for _a, _w in W.items():
    assert sum(_w.values()) == 100, _a
ag = list(W)

MIN=dict(Captador=60,Conferidor=80,Mercado=75,Caixa=75,Divida=80,Risco=70,Estrategista=85,Entregas=85)
COB=dict(Captador=60,Conferidor=75,Mercado=75,Caixa=75,Divida=80,Risco=75,Estrategista=80,Entregas=85)
# pisos: (dim, minimo, condicao opcional)
PISO=dict(Captador=[],Conferidor=[("A1",65),("B2",50),("B7",60)],Mercado=[("A1",70),("B2",70)],
 Caixa=[("B1",90,"extrato"),("B3",80,"extrato")],Divida=[("A1",60),("B3",80),("B7",80,"doc_cliente")],
 Risco=[("A1",45),("B3",80,"nada_consta")],Estrategista=[("B2",60)],Entregas=[("A1",70),("B7",70)])
def avalia(a,c):
    n=c["n"]; w=W[a]
    aplic={d:w[d] for d in w if n.get(d)!=NA}
    med={d:w[d] for d in aplic if n.get(d) not in (NM,None)}
    if c.get("veto"): return ("REPROVADO",None,None,c["veto"])
    pa=sum(aplic.values()); pm=sum(med.values())
    cob=round(100*pm/pa) if pa else 0
    s=sum(w[d]*n[d] for d in med)/pm if pm else 0
    if c.get("teto"): s=min(s,c["teto"])
    s=round(s,1)
    motivos=[]
    if c.get("nada_consta") and not c.get("cobertura_tribunais"):
        return ("REPROVADO",s,cob,"'nada consta' sem cobertura declarada")
    if s<50: return ("REPROVADO",s,cob,"score < 50")
    if a=="Entregas" and n.get("B7") not in (NM,NA,None) and n["B7"]<50: return ("REPROVADO",s,cob,"custódia < 50")
    if c.get("conflito"): motivos.append("conflito entre fontes")
    if c.get("nome"): motivos.append("identidade por nome")
    if c.get("opiniao") and a not in ("Captador","Risco"): motivos.append("dado opinativo (teto)")
    if a=="Entregas" and c.get("destino_sem_aut"): motivos.append("sem autorização p/ terceiros")
    if a!="Captador" and isinstance(n.get("B2"),(int,float)) and n["B2"]<60: motivos.append("frescor < 60")
    if s<MIN[a]: motivos.append(f"score < {MIN[a]}")
    if cob<COB[a]: motivos.append(f"cobertura < {COB[a]}%")
    for p in PISO[a]:
        d,m=p[0],p[1]; cond=p[2] if len(p)>2 else None
        if cond and not c.get(cond): continue
        v=n.get(d)
        if v in (NM,None): 
            if d in med or w[d]==0: continue
            if v==NM and w[d]>0: motivos.append(f"{d} não medido (piso)")
            continue
        if v==NA: continue
        if v<m: motivos.append(f"{d} < {m}")
    if motivos: return ("QUARENTENA" if a=="Captador" else "REVISÃO",s,cob,"; ".join(motivos))
    return ("APROVADO",s,cob,"")
of=dict(A1=100,A2=NA,A3=90,B2=100,B3=100,B5=95,B7=80)
CASOS=[
("IPCA do IBGE, espelho do BCB confere",dict(n=dict(of,B1=70),teto=90)),
("Focus (BCB), sem segunda fonte possível",dict(n=dict(of,B1=NA),teto=90)),
("Focus com o dobro da idade",dict(n=dict(of,B1=NA,B2=50),teto=90)),
("Registrato com recibo; envio a credor não autorizado",dict(n=dict(A1=100,A2=NA,A3=NA,B1=NA,B2=100,B3=90,B5=90,B7=100),teto=90,doc_cliente=True,destino_sem_aut=True)),
("Open Finance, saldo fecha, todas as contas",dict(n=dict(A1=85,A2=NA,A3=NM,B1=90,B2=100,B3=100,B5=90,B7=75),teto=90,destino_sem_aut=True,extrato=True)),
("Open Finance, falta 1 de 10 contas",dict(n=dict(A1=85,A2=NA,A3=NM,B1=90,B2=100,B3=90,B5=90,B7=75),teto=90,destino_sem_aut=True,extrato=True)),
("Processo por CNPJ, API sem origem declarada",dict(n=dict(A1=45,A2=NA,A3=NM,B1=NM,B2=100,B3=NM,B5=NA,B7=30),teto=80)),
("Processo por nome (homônimo possível)",dict(n=dict(A1=45,A2=NA,A3=NM,B1=NM,B2=100,B3=NM,B5=NA,B7=30),teto=80,nome=True)),
("Processo na certidão do tribunal",dict(n=dict(A1=100,A2=NA,A3=NA,B1=NA,B2=100,B3=100,B5=NA,B7=100),teto=90)),
("Score de bureau",dict(n=dict(A1=70,A2=NA,A3=85,B1=NA,B2=100,B3=100,B5=80,B7=50),teto=80,opiniao=True,destino_sem_aut=True)),
("Notícia, por nome",dict(n=dict(A1=45,A2=NA,A3=70,B1=NM,B2=100,B3=NM,B5=NA,B7=30),teto=80,nome=True,opiniao=True)),
("IPCA: IBGE e BCB divergem",dict(n=dict(of,B1=0),teto=90,conflito=True)),
("'Nada consta' de processos via provedor",dict(n=dict(A1=45,A2=NA,A3=NM,B1=NM,B2=100,B3=NM,B5=NA,B7=30),teto=80,nada_consta=True)),
]
res = {}
for nome, c in CASOS:
    res[nome] = {a: avalia(a, c) for a in ag}
AB = {"APROVADO": "APRO", "REVISÃO": "REV", "REPROVADO": "REPR", "QUARENTENA": "QUAR"}
print("| Caso | " + " | ".join(a.replace("Divida", "Dívida") for a in ag) + " |")
print("|---|" + "---|" * len(ag))
for caso, r in res.items():
    cel = [AB[v[0]] if v[1] is None else f"{v[1]:g} {AB[v[0]]}".replace(".", ",") for v in (r[a] for a in ag)]
    print(f"| {caso} | " + " | ".join(cel) + " |")
