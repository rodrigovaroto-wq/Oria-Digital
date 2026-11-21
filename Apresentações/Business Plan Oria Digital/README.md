# Business Plan Oria Digital

Versão em vigor (**v4**, 21/11/2026: a v2 com o prazo "Em 3 a 6 meses" recolocado pelo dono no slide 10, a numeração dos slides 7 e 8 corrigida e os ids das formas renumerados para abrir certo no iPhone) do business plan para o potencial sócio investidor. A v1 (13 slides, PR #301) fica no histórico do git; os comparativos e os scripts da v2 estão em `Business Plan/_trabalho_fase3/`.

| Arquivo | O que é |
|---|---|
| `Business_Plan_Oria_Digital.pptx` | O deck: 14 slides, editável, com notas do apresentador |
| `Business_Plan_Oria_Digital_celular.pptx` | Versão para abrir no celular: cada slide é uma imagem do deck, com as notas. Não editável; é derivada, regere com `ferramentas/versao_celular.py` |
| `Business_Plan_Oria_Digital.pdf` | O mesmo deck em PDF, para leitura e compartilhamento |
| `DOCUMENTACAO.md` | Tudo o que é preciso para manter ou refazer o deck: público e pedido, estrutura, dados e fontes, modelo de negócio, status real de cada agente, identidade visual, regras de escrita e como conferir |
| `ferramentas/qa_geometria.py` | Checagem automática: texto colidindo no render, caixas sobrepostas, shapes fora do slide, fonte pequena |
| `ferramentas/comparativo.py` | Comparativo lado a lado entre duas versões quaisquer, com IGUAL ou ALTERADO por slide |
| `ferramentas/versao_celular.py` | Gera a versão para celular a partir do deck e do PDF |
| `ferramentas/renumerar_ids.py` | Dá id único a cada forma do deck; rode antes de publicar, senão o iPhone mistura formas entre slides |

Para conferir e comparar, veja a seção 8 de `DOCUMENTACAO.md`.
