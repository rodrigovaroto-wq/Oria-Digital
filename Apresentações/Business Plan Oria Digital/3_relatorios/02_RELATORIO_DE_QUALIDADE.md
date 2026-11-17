# Relatório de qualidade: Business Plan Oria Digital v3

**Veredito:** o arquivo está íntegro e editável, sem texto sobreposto nem fora da margem. Não sobrou nenhum erro de dado conhecido. As pendências são dados externos que dependem de você (relatório de melhorias, seção 4).

## 1. Ciclo executado

Foram duas rodadas completas de gerar → renderizar → inspecionar → criticar → corrigir → validar.

| Rodada | Gerou | Inspecionou | Achou e corrigiu |
|---|---|---|---|
| 1 | Edição pontual dos slides 2, 8, 9 e 10 | Render de cada slide alterado, a cada mudança | Rótulos do gráfico quebrando "R$ 30 / mi/ano" (trocados por legenda colorida); descrição vazando do cartão 3 do slide 10 (texto encurtado); legenda do slide 9 colada na caixa do título (descida) |
| 2 | Achados confirmados de 2 revisores independentes | Render dos 14 slides + script de colisão | A regressão que eu mesmo causei ("Nove análises no mesmo modelo" quebrava em 2 linhas e colidia com o texto de baixo, detectado pelo script) virou "Nove análises integradas"; zero colisões depois |

## 2. Testes e resultados

| Teste | Ferramenta | Resultado |
|---|---|---|
| Integridade OOXML (esquema, relações, content types, gráfico) | `validate.py` da skill PPTX, comparado com o original | **PASSOU** |
| Abertura e renderização dos 14 slides | LibreOffice headless → PDF → `pdftoppm` | **PASSOU**: 14 páginas |
| Texto sobre texto no render | `qa_geometria.py` (caixas das palavras via `pdftotext -bbox`) | v2: **4 colisões** (slide 8). v3: **0** |
| Shape fora do slide | `qa_geometria.py` | Só o sextante da capa, que sangra de propósito e é igual ao original |
| Caixas de texto sobrepostas | `qa_geometria.py` | Nenhuma nova. As que restam são do desenho original: título e subtítulo empilhados nos anexos, caixa do título encostando no agente 1 sem tocar o texto |
| Fonte abaixo de 9 pt | `qa_geometria.py` | Selos dos anexos agora em 8 pt (eram 7). É o limite do selo sem redesenhá-lo |
| Contraste do selo RISCO | Cálculo WCAG | 3,1:1 → **5,1:1** |
| Conteúdo e diferenças de texto | `slide_text.py` + `diff` v2 × v3 | Toda mudança de texto está listada no relatório de melhorias; nenhum texto foi perdido sem querer |
| Auditoria numérica | Revisor independente + conferência própria | Todas as contas e contagens internas batem: 10 + 30 = 40; 31 frentes; 5 EBITDA; 10 risco/10 caixa; 6 risco; 9 análises; 8 agentes. "Mais de 30 fontes" está sinalizado |
| Crítica visual independente | Subagente "diretor de arte" (sem ver meu raciocínio), comparando as 28 imagens | Nenhuma regressão. Os 9 achados de alto e médio impacto foram conferidos na geometria antes de serem aceitos; 6 aplicados, 3 justificados como não aplicados |
| Editabilidade | Inspeção dos shapes | Todo texto é texto vivo e o gráfico é nativo, com a planilha embutida atualizada. A única imagem nova é o ícone da bússola (PNG 256 px, no mesmo padrão dos outros ícones) |

## 3. Avaliação pela rubrica

As notas são minhas. Elas são cruzadas com as notas dos dois revisores independentes, mostradas entre parênteses.

| Dimensão (peso) | v2 | v3 | Evidência |
|---|---|---|---|
| Narrativa e inteligência (25%) | 7 | **9** (revisor: 7 → 8, antes da rodada 2) | O pedido ao sócio está explícito e na ordem certa. Os títulos dos slides 5, 9 e 10 viraram conclusões. Não sobrou contradição de tempo (o "3 meses" bate com o card de consequências e com as notas). O ponto que ainda falta, o modelo de receita, não depende do deck |
| Direção de arte (25%) | 7 | **8,5** (revisor: 7 → 7,5, antes da rodada 2) | O código de cor do gráfico casa com os cartões. O status dos agentes ficou legível. A grade está respeitada. Fica abaixo de 9 pelo espaço vazio dos cartões, que é do desenho original e foi preservado de propósito |
| Fidelidade à identidade (20%) | n/a | **9,5** (revisor: 9) | Paleta, tipografia, sextante, cartões e rodapé intactos. A única cor nova é um tom mais escuro do cinza que já existia, para dar contraste |
| Precisão informacional (15%) | 4 | **9** (revisor: 4 → 7,5, antes da rodada 2) | Saíram: a soma de anual com único, a fonte sem prova, a contradição do cliente, o prazo divergente e as afirmações no presente sobre o que está em construção. Ficam abaixo de 10 por "mais de 30 fontes" e pelos dados externos não conferidos |
| Legibilidade e acabamento (10%) | 4,5 | **8,5** (revisor: 4,5 → 7, antes da rodada 2) | Zero colisões, nenhuma caixa fora da margem, selos maiores e com contraste. Sobram o texto de 10,5 pt nas elipses e o número de página no layout |
| Integridade técnica (5%) | 9 | **10** | Validador passou, gráfico nativo, nenhum slide virou imagem |

**Média ponderada: v3 ≈ 8,9.** Na v2, sem a fidelidade, que não se aplica, a média é cerca de 6,2.

As dimensões abaixo de 9 (arte e acabamento) dependem de mudanças que tocam a composição original. Não as fiz, por respeito à regra de preservar a identidade, e elas estão listadas no relatório de melhorias, seção 5.

## 4. Limitações

1. **Não conferi no Microsoft PowerPoint.** O render é do LibreOffice. A Calibri foi substituída pela Carlito, que tem as mesmas métricas, então a checagem de quebra e de vazamento é confiável. Mesmo assim, abra o arquivo no PowerPoint antes da reunião. Os pontos de maior risco são os rótulos do gráfico do slide 8 e a legenda do slide 9.
2. **O pequeno "degrau" claro no canto de baixo dos cartões escuros** é artefato do LibreOffice e aparece igual no original. O XML é um retângulo arredondado comum.
3. **Os dados externos (OBRE, Serasa, KPMG, Banco Central, Anbima) não foram conferidos.** Este ambiente não tem acesso às fontes, e conferir exigiria buscar os relatórios originais.
4. **Os scripts em `4_scripts/` reproduzem a v3 a partir do original.** A ordem é: `editar.py` → `slide9_status.py` → `rodada2.py`. Eles dependem de `python-pptx` e `openpyxl`.
