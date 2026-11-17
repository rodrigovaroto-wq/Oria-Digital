# Relatório de melhorias: Business Plan Oria Digital, v2 → v3

**Resumo:** 13 dos 14 slides mudaram. Nenhum foi reconstruído. A ordem, a estrutura e a identidade visual ficaram iguais. Corrigi um defeito visível na apresentação (slide 8), três inconsistências de dados, o pedido ao sócio, que não estava explícito, e seis problemas de grade e legibilidade.

Referência das decisões: [`00_BRIEFING.md`](00_BRIEFING.md).

## 1. Classificação por slide

| Slide | Classe | O que mudou |
|---|---|---|
| 1 Capa | **A**, preservar | Nada |
| 2 O problema | **B**, refinar | "recuperação (extra) judicial" → "recuperação judicial e extrajudicial" |
| 3 Consequências | **B** | "Semanas perdidas" → "Meses perdidos" |
| 4 O negócio | **A** | Nada |
| 5 Como funciona | **B** | Título |
| 6 Dados | **A** | Nada |
| 7 O que calcula | **B** | Rótulo e margem |
| 8 O que o cliente ganha | **C**, reorganizar | Defeito visível, dados, título, gráfico, fonte |
| 9 Estratégia de IA | **B** | Status dos agentes (aprovado pelo dono com prévia) e título |
| 10 Para levar adiante | **C** | O pedido ao sócio, os pilares, uma contradição e o prazo nas notas |
| 11 Anexo 1 | **B** | Uma palavra no rodapé |
| 12–14 Anexo 2 | **B** | Selos legíveis e contraste; uma palavra no título do 12 |

Nenhum slide ficou na classe D (reconstruir).

## 2. Problemas encontrados e o que foi feito

### Erros de fato e de consistência (prioridade 1)

1. **Slide 8: texto solto sobre os cartões.** A caixa "com um nível de excelência e exigência extremamente alto" ficava por cima do meio do slide e cobria números (detectado também pelo script de colisão: 4 palavras sobrepostas). **Removida.**
2. **Slide 8: soma de ganho anual com ganho único.** O gráfico se chamava "R$ mi por ano" e somava R$ 60 mi. Mas R$ 20 mi de crédito tributário é ganho de uma vez só. **Agora:** "Exemplo ilustrativo · R$ 40 mi por ano + R$ 20 mi uma vez". A parte única fica em verde, a cor do cartão "Amortiza dívida". A separação é sutil, como você pediu.
3. **Slide 8: "Fonte: McKinsey."** era uma citação sem estudo identificável, embaixo de um exemplo inventado. **Retirada** por sua decisão. No lugar entrou a premissa: "empresa com R$ 500 mi de dívida e R$ 200 mi de custos operacionais por ano". "Operacionais" deixa claro que o juro (R$ 10 mi) não está dentro dos R$ 200 mi, então não há dupla contagem.
4. **Slide 10, notas: "Em 6 a 12 meses"** contradizia o "3 a 6 meses" do slide. **Corrigido para 3 a 6**, por sua decisão.
5. **Slide 10: "O método e o primeiro cliente já existem"** contradizia a linha do tempo do mesmo slide, que põe o primeiro cliente daqui a 3 a 6 meses. **Agora:** "O método já funciona na Oria Partners. Com esses quatro pilares, o Oria Digital ganha escala."

### Narrativa e mensagem para o sócio (prioridade 3)

6. **Slide 10: o pedido não estava explícito.** "PARA CHEGAR LÁ" virou **"O QUE BUSCAMOS NO SÓCIO"**. Os quatro pilares estão na sua ordem:
   - **Direção estratégica** (cartão novo, com ícone de bússola, que conversa com o sextante da marca);
   - Time de especialistas;
   - **Infraestrutura segura para desenvolvimento** (junta os dois cartões de infraestrutura);
   - Banco de dados.

   O título virou conclusão: "Quatro pilares levam o Oria Digital do método validado ao mercado". As notas foram reescritas com o pedido.
7. **Slide 9: o que já funciona.** Pelas suas notas, só Captador, Conferidor e Entregas operam hoje. Agora eles aparecem "já em operação" (badge cheio). Os demais aparecem "em construção" (badge vazado), com legenda. Você aprovou com a prévia. Título: "Oito agentes de IA cobrem o diagnóstico, e o Especialista Oria decide", que perdeu o ponto final e o exagero "todo o diagnóstico".
8. **Slide 7: "Nove análises rodando juntas"** afirmava no presente o que o slide 9 mostra em construção. Virou "Nove análises integradas".
9. **Slide 5: o título repetia o do slide 4** ("Do documento ao diagnóstico…" / "Do caos de documentos à decisão…"). Virou "Do documento ao diagnóstico, com a prova de cada número", que ancora o diferencial.
10. **Slide 3: "Semanas perdidas"** competia com os "3 meses" dos slides 2 e 4. Virou "Meses perdidos".
11. **Slide 12: "5 com efeito direto no EBITDA".** A legenda não define o que é efeito "direto". Ficou "5 com efeito no EBITDA", no padrão dos slides 13 e 14.
12. **Slide 11: "está no roteiro"** virou "está no plano de construção", o termo das notas do slide 9.

### Acabamento e legibilidade (prioridades 4 e 5)

13. **Slide 7:** o bloco "A melhor saída" ia até 13,17", e a margem direita do deck é 12,73". Agora ele espelha o bloco da esquerda (3,70" de largura).
14. **Slide 8:**
    - Os valores não se separam mais da unidade na quebra de linha ("R$ 10 / mi/ano" virou "R$ 10 mi/ano", com espaço que não quebra).
    - O rótulo do gráfico está alinhado aos rótulos dos cartões (2,15" → 2,20").
    - O título perdeu o "; Mais", maiúsculo depois de ponto e vírgula, e ficou paralelo: "Menos custo desnecessário, mais dívida amortizada".
15. **Slide 10:** os rótulos "HOJE", "PRÓXIMO MARCO", "EM 3 A 6 MESES" e "O QUE BUSCAMOS NO SÓCIO" ganharam o mesmo espaçamento entre letras dos outros rótulos do deck (`spc=300`).
16. **Slides 12–14:**
    - Os 59 selos (EBITDA, DÍVIDA, CAIXA, RISCO) subiram de 7 para 8 pt. É o máximo que o selo comporta sem mudar de tamanho.
    - O cinza do "RISCO" escureceu de `8A9590` para `66716C`. O contraste do branco sobre ele passou de 3,1:1 para 5,1:1 (a recomendação WCAG é de 4,5:1). O tom continua cinza e a legenda acompanha.

## 3. O que foi preservado de propósito

- **Paleta e logotipo:** paleta, sextante, rodapé, logotipo, sistema de cartões, tipografia (Calibri) e a ordem e quantidade de slides.
- **Os quatro números de mercado e as fontes deles** (slides 2 e 4).
- **Os anexos:** conteúdo integral. Só a legibilidade mudou.
- **Slides 1, 4 e 6 sem alteração:** cumprem a função, e mexer neles seria só para demonstrar atividade.

## 4. Questões que precisam de validação humana

| # | Questão | Por que não mexi |
|---|---|---|
| 1 | **"Mais de 30 fontes" (slide 5).** O slide 6 lista 14 grupos e cerca de 28 itens. | Não há prova no projeto para confirmar nem para negar. Se você não tiver a lista, sugiro "cerca de 30" ou "14 grupos de fontes". |
| 2 | **"3 meses" (slide 2)** não tem fonte. | É a experiência da Oria Partners. Vale ter o caso pronto se o sócio perguntar. |
| 3 | **R$ 18,9 bi (OBRE), 2.466, 1.581, R$ 2,7 tri, R$ 56 bi** | Dados externos que não conferi neste ambiente, sem acesso às fontes. "R$ 2,7 tri" parece saldo de crédito (estoque), e os outros são do ano. Se for saldo, considere "R$ 2,7 tri de saldo de crédito a empresas". |
| 4 | **15% de redução de despesa (slide 8)** | É o número mais agressivo do exemplo. Um sócio pode perguntar a base. |
| 5 | **Perguntas que o deck não responde:** modelo de receita/preço, concorrência, quem é o time hoje | Não é falha de slide: com público ao vivo, basta ter as respostas prontas. Não criei slides com dados que não existem. |

## 5. Melhorias propostas e não aplicadas

Ficaram de fora por serem de baixo impacto ou por tocarem em escolhas originais:

- O número da página aparece na capa e fica uns 0,05" acima da linha de "ORIA DIGITAL" em todos os slides (vem do layout).
- Slide 6: a frase "Resultado:" fica solta. Os slides 2 e 3 usam faixa tingida para o mesmo papel. Falta espaço vertical antes do rodapé para a faixa.
- Slide 8: os "Entregáveis" usam bolinha, e o resto do deck usa seta.
- Slides 3, 5, 11, 12 e 14: há bastante espaço vazio no pé dos cartões. Está assim no original, e preenchê-lo seria decoração sem função.
- Slide 9: o texto das elipses está em 10,5 pt, pequeno para projeção. Aumentar exige redesenhar as elipses.
