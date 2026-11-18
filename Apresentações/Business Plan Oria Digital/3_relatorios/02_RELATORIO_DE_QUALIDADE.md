# Relatório de qualidade: Business Plan Oria Digital v3 (13 slides)

**Veredito:** o arquivo está íntegro e editável. Não há texto sobreposto nem fora da margem. Os dados verificáveis batem e o número do BC foi conferido na fonte. A única pendência material é o seu aval sobre o status das análises e sobre o slide de modelo de negócio.

## 1. Ciclo executado

Foram cinco rodadas de gerar → renderizar → inspecionar → criticar → corrigir → validar. Cada rodada é um script em `4_scripts/`, aplicado em sequência sobre o original.

| Rodada | Script | O que fez | O que o ciclo pegou e corrigiu |
|---|---|---|---|
| 1 | `editar.py`, `slide9_status.py` | Correções de fato e pedido ao sócio | Rótulos do gráfico partidos e descrição vazando do cartão 3 |
| 2 | `rodada2.py` | Achados de 2 revisores independentes | Uma regressão minha no slide 7 ("no mesmo modelo" colidia com o texto de baixo) |
| 3 | `rodada3.py` | Cards preenchidos e dado do BC | Painel em gráfico ilegível no slide 13, trocado por números grandes; respostas do slide 3 encostando no pé do card |
| 4 | `rodada4.py` | Despesa de 15% para 10% | — |
| 6 | `rodada6.py` | Revisão independente final + pedidos de 18/11 | Texto de 3 linhas do slide 3 encostando no pé do card (cards +0,3") |
| 5 | `rodada5.py` | Mapa mental, remoção do slide 7 e acabamento | Elipses partindo nomes; grupos de análises fundidos (achado do 3º revisor); raio de canto e títulos dos pilares; depois, por pedido seu, 1 a 4 à esquerda, ramos preenchidos e 28 ramos específicos |

## 2. Testes e resultados

| Teste | Ferramenta | Resultado |
|---|---|---|
| Integridade OOXML | `validate.py` da skill PPTX, comparado com o original | **PASSOU** |
| Render dos 13 slides | LibreOffice → PDF → `pdftoppm` | **PASSOU** |
| Texto sobre texto no render | `qa_geometria.py` (`pdftotext -bbox`) | v2: **4 colisões**. v3: **0** |
| Shape fora do slide | `qa_geometria.py` | Só o sextante da capa, que sangra de propósito, como no original |
| Contagens dos painéis de impacto | Script (contagem dos selos) + revisor | 5/4/5/5 e 2/3/2/6. **OK** |
| Contas do exemplo do slide 7 | Conferência | 2 p.p. × 500 = 10; 10% × 200 = 20; recorrente = 30/ano; único = 20. **OK** |
| Saldo de crédito PJ | Relatório oficial do BC (PDF de 29/10/2026, texto extraído) | "R$ 2,8 trilhões" em setembro. O deck dizia 2,7 (agosto). **Corrigido** |
| Status das 28 análises | Cada ramo conferido no código (grep) ou no STATUS_POR_ETAPA | 14 já existem e 14 estão em construção. "18 capítulos" não tem evidência e ficou de fora. **A validar com você** |
| Contraste do selo RISCO | WCAG | 3,1:1 → **5,1:1** |
| Crítica visual independente | 3 rodadas de subagente "diretor de arte" e 1 de "narrativa/finanças", sem ver o meu raciocínio | Nenhuma regressão de identidade. Os achados foram conferidos na geometria antes de serem aplicados |
| Editabilidade | Inspeção | Texto vivo, gráfico nativo com a planilha atualizada e conectores nativos (curvas editáveis) no mapa mental. Nenhum slide virou imagem |

## 3. Avaliação

| Dimensão (peso) | v2 | v3 | Evidência |
|---|---|---|---|
| Narrativa e inteligência (25%) | 7 | **9** | Um motor descrito de um jeito só (fluxo → agentes e análises), pedido explícito, títulos-conclusão, nenhuma contradição de prazo ou de cliente |
| Direção de arte (25%) | 7 | **9** | Os cards vazios ganharam conteúdo que tem função. O mapa mental mostra 28 análises sem perder a leitura. Os componentes novos são cópias dos existentes. Os pontos que sobram (anexo 1, cards escuros do slide 4) vêm do desenho original |
| Fidelidade à identidade (20%) | n/a | **9** | Paleta, tipografia, sextante, cartões, elipses e curvas do original |
| Precisão informacional (15%) | 4 | **9,5** | BC conferido na fonte, o anual separado do único, citação sem prova removida, status das análises honesto |
| Legibilidade e acabamento (10%) | 4,5 | **8,5** | Zero colisões e selos legíveis. As pílulas do mapa mental, em 10 pt, são o ponto mais pequeno do deck |
| Integridade técnica (5%) | 9 | **10** | Validador passou e tudo é editável |

**Média ponderada: v3 ≈ 9,1 (v2 ≈ 6,2).**

O revisor visual independente deu notas mais baixas (direção de arte 7 → 7,5). Isso foi **antes** da última rodada, que corrigiu os três achados principais dele: grupos fundidos no mapa, legenda dos selos e raio dos painéis. Não rodei o revisor de novo depois dessas correções.

## 4. Limitações

1. **Não verifiquei no Microsoft PowerPoint, só no LibreOffice**, com Carlito no lugar da Calibri e as mesmas métricas. Os conectores curvos do mapa mental e os rótulos sem quebra do gráfico são os pontos para conferir no PowerPoint.
2. **Os outros dados externos não foram conferidos neste ambiente:** OBRE, Serasa, KPMG e Anbima. Você confirmou que estão corretos.
3. **Para reproduzir a versão final**, a partir de `0_original/`, rode em sequência: `editar.py` → `slide9_status.py` → `rodada2.py` → `rodada3.py` → `rodada4.py` → `rodada5.py` → `rodada6.py`.
