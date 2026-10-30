# Pedido de proposta (RFP): fornecimento de dados para análise de crédito e reestruturação

**Oria Partners** · Emitido em [data de envio] · Prazo para resposta: [data de envio + 15 dias corridos]
Contato: [nome do responsável] · [e-mail] · [telefone]

> Nota interna, a remover antes do envio: o §1 a §5 e o §7 vão para todos os fornecedores. O §6 é
> enviado só na parte que cabe a cada categoria. A lista de destinatários está no §8.

---

## 1. Objeto

A Oria Partners é uma assessoria boutique em M&A e reestruturação de empresas. Em cada mandato, a
Oria consolida demonstrações financeiras, endividamento, contingências e informações cadastrais do
grupo assessorado e de seus sócios, e cruza o que o cliente declara com fontes independentes.

Este pedido busca fornecedores para as fontes independentes. A Oria pretende contratar, por
categoria:

| Categoria | Dado procurado |
|---|---|
| A. Consultas a fontes oficiais | certidões judiciais, fiscais e trabalhistas; consultas ao e-CAC, à PGFN e a cadastros públicos |
| B. Consulta processual | processos por CPF e CNPJ, com dados estruturados e monitoramento |
| C. Bureau de crédito | protestos, ações, falências, recuperações judiciais, sócios, histórico de pagamento e score de empresas |
| D. Open Finance | extratos, limites e operações de crédito de contas de pessoa jurídica, com consentimento do titular |
| E. Infraestrutura de recebíveis | indicadores de boleto, cartão e TED; agenda de recebíveis de cartão |
| F. Registro de imóveis | certidões de matrícula por API |

O fornecedor pode responder a uma ou mais categorias.

## 2. Uso pretendido

- **Integração por API** com o sistema interno da Oria. Não há uso por tela como canal principal.
- **Dois momentos de uso.** No **pré-mandato**, consultas sobre a empresa e os sócios, com
  autorização escrita do consultado, antes da assinatura do mandato. No **mandato**, as mesmas
  consultas e o monitoramento periódico enquanto o mandato durar.
- **Volume estimado:** 4 mandatos ativos por mês, cada um com cerca de 8 empresas e 6 pessoas
  físicas, ou cerca de 56 alvos por mês. O volume pode dobrar em 12 meses. A proposta deve informar
  o preço nas faixas de 50, 200 e 1.000 alvos por mês.
- **Uso final:** análise interna da Oria e relatórios aos seus clientes e credores no âmbito do
  mandato. Não há revenda nem disponibilização dos dados a terceiros fora do mandato.

## 3. Requisitos obrigatórios (eliminatórios)

1. **Distinção entre resultado vazio, falha e fonte não coberta.** Cada resposta da API deve
   permitir saber, sem ambiguidade, se a consulta (a) encontrou registros, (b) consultou a fonte e
   não encontrou nada, (c) falhou (fonte fora do ar, CAPTCHA, tempo esgotado, mudança de leiaute) ou
   (d) não cobre aquele tribunal, órgão ou município. Uma falha nunca pode ser devolvida como
   resultado negativo. A proposta deve mostrar como cada caso aparece na resposta.
2. **Evidência da consulta.** Data e hora da consulta na fonte original, identificação da fonte e,
   quando houver, o documento original (PDF da certidão, por exemplo) ou o retorno bruto.
3. **LGPD.** Papel do fornecedor no tratamento (operador ou controlador), base legal da fonte dos
   dados, localização do armazenamento, prazo de retenção do dado consultado, lista de
   suboperadores e minuta de acordo de tratamento de dados.
4. **Segurança.** Certificações vigentes (ISO 27001, SOC 2 ou equivalente), criptografia em
   trânsito e em repouso, autenticação da API e registro de acesso.
5. **Preço transparente.** Tabela por consulta e por faixa de volume, custos adicionais por tipo de
   consulta, franquia mínima, fidelidade, reajuste e o que acontece com créditos não usados.
6. **Ambiente de teste ou créditos para o piloto** do §5.
7. **Aviso de mudança.** Compromisso de avisar com antecedência quando uma fonte deixar de ser
   coberta ou mudar de formato.

## 4. Informações gerais pedidas

1. Razão social, CNPJ, tempo de operação e três clientes de referência com uso semelhante
   (assessorias, gestoras de crédito, departamentos de crédito).
2. Documentação da API (endereço público ou anexo) e limites de requisição.
3. Disponibilidade medida nos últimos 12 meses e o acordo de nível de serviço oferecido.
4. Canal e prazo de suporte técnico.
5. Para fornecedores regulados: autorização vigente do Banco Central ou de outro órgão, com número.

## 5. Piloto

Antes de contratar, a Oria vai conduzir um piloto comparativo com os fornecedores pré-selecionados
em cada categoria. Condições:

- **Amostra:** um grupo econômico real assessorado pela Oria, com cerca de 8 empresas e seus sócios
  e administradores, além de controles: CNPJs com histórico conhecido e um identificador inválido,
  para testar a resposta de falha.
- **Autorização:** a Oria obtém a autorização escrita dos titulares antes do piloto.
- **Mesma entrada, mesmo dia** para todos os fornecedores da categoria.
- **Medição** contra documentos que a Oria já tem (certidões, relatório de contingências, mapa de
  dívida). Os critérios estão no §7.
- **Custo:** a Oria pede créditos de teste ou paga as consultas do piloto a preço de tabela, sem
  compromisso de contratação.
- **Confidencialidade:** os dados da amostra não podem ser usados pelo fornecedor para nenhum outro
  fim, e o fornecedor não recebe o resultado comparativo dos concorrentes.

A proposta deve dizer se o fornecedor aceita participar nessas condições.

## 6. Questionário por categoria

### A. Consultas a fontes oficiais

1. Lista de consultas cobertas, por órgão, com indicação das que emitem certidão com validade legal.
2. Certidões de distribuição cível, de falência e criminal: quais Tribunais de Justiça e Tribunais
   Regionais Federais são cobertos, para pessoa física e jurídica. Quais exigem login gov.br do
   titular.
3. Certidões trabalhistas: CNDT e certidões dos 24 Tribunais Regionais do Trabalho.
4. Certidões fiscais: federal (Receita e PGFN), estaduais (as 27 UFs) e municipais (quais
   municípios).
5. Protestos: cobertura nacional, forma de acesso à central de protestos e o que é devolvido
   (quantidade, valor, cartório, data).
6. Consultas ao e-CAC com certificado de procurador: quais serviços (DCTFWeb, PER/DCOMP, Caixa
   Postal, situação fiscal, parcelamentos).
7. Antecedentes criminais da Polícia Federal.
8. Preço por consulta, consultas com adicional e tempo médio de resposta por tipo.

### B. Consulta processual

1. Busca por CPF, CNPJ e nome: cobertura por tribunal, instância e esfera (cível, trabalhista,
   federal, criminal), inclusive processos eletrônicos e físicos digitalizados.
2. Campos devolvidos por processo: número, classe, assunto, valor da causa, polo (ativo ou passivo),
   partes, fase, último andamento, data de distribuição.
3. Tratamento de homônimos na busca por nome e taxa de falso positivo conhecida.
4. Processos em segredo de justiça: o que aparece e como é sinalizado.
5. Defasagem entre a distribuição no tribunal e a disponibilidade na base.
6. Monitoramento: de processos já identificados e de novas ações contra um CPF ou CNPJ; forma de
   aviso (webhook ou consulta).
7. Preço por consulta, por processo devolvido e por monitoramento; franquia mínima.

### C. Bureau de crédito

1. Relatórios de pessoa jurídica disponíveis por API e o conteúdo de cada um: protestos (estaduais
   ou nacionais), ações judiciais, falência e recuperação judicial, cheques sem fundo, dívidas
   vencidas, sócios e administradores com suas próprias ocorrências, score e histórico de
   pagamento.
2. Fontes e defasagem de cada informação, em especial protestos e ações.
3. Consulta de pessoa física (sócios): conteúdo e requisitos de autorização.
4. Monitoramento de CNPJ e CPF com aviso de nova ocorrência.
5. Indicadores setoriais de inadimplência e recuperação judicial por CNAE.
6. Combinação com outras fontes (por exemplo, dados de boleto da Núclea), quando houver.
7. Preço por relatório e por monitoramento, franquia e fidelidade.

### D. Open Finance

1. Instituição que recebe os dados no Open Finance Brasil (participante autorizado) e o papel
   contratual da Oria, que não é instituição autorizada.
2. Recursos entregues para pessoa jurídica: contas (saldos, transações, limites de cheque especial),
   cartões, e operações de crédito (empréstimos, financiamentos, adiantamentos e direitos
   creditórios descontados).
3. Histórico disponível na primeira coleta e frequência de atualização.
4. Fluxo de consentimento para empresas com mais de um representante legal; aviso quando o
   consentimento expira, é revogado ou fica pendente.
5. Entrega da transação bruta junto da categorização própria.
6. Cobertura de instituições financeiras e instituições fora do ambiente regulado.
7. Preço por conexão, por consulta ou por mês.

### E. Infraestrutura de recebíveis (Núclea e registradoras)

1. Produtos de dados sobre um CNPJ que uma assessoria pode contratar.
2. Acesso, com autorização do cliente, à agenda de recebíveis de cartão (cessões, gravames,
   antecipações), sem que a Oria seja instituição financiadora.
3. Acesso, com autorização do cliente, ao status dos boletos emitidos por ele e às duplicatas
   escriturais registradas.
4. Granularidade máxima entregue com autorização do cliente (transação, dia, mês, faixa).
5. Preço por consulta.

### F. Registro de imóveis (ONR)

1. Condições para um integrador usar a API de pedido de certidão de matrícula.
2. Pedido por número de matrícula e por CPF/CNPJ do proprietário (pesquisa de bens).
3. Custo de integração além dos emolumentos e prazo médio de emissão.

## 7. Critérios de avaliação

| Critério | Peso | Como é medido |
|---|---|---|
| Cobertura e acerto no piloto | 30% | resultados do piloto contra os documentos de referência da Oria |
| Distinção entre vazio, falha e fonte não coberta (requisito 1) | 15% | comportamento no piloto, inclusive com o identificador inválido |
| Qualidade e estrutura do dado e da evidência | 15% | campos preenchidos, documento original, data da consulta |
| Custo total no volume estimado | 20% | proposta nas três faixas do §2 |
| LGPD e segurança | 15% | documentação do §3; o não atendimento dos itens 3 e 4 elimina |
| Integração e suporte | 5% | documentação da API e prazo de suporte |

Os requisitos do §3 são eliminatórios. Entre propostas que os atendem, vale a pontuação acima.

**Formato da resposta.** Um documento com as respostas na ordem deste pedido, a tabela de preços e
a minuta de contrato e de acordo de tratamento de dados, enviados a [e-mail] até [prazo]. Dúvidas
sobre este pedido podem ser enviadas ao mesmo endereço até [prazo de dúvidas]. A Oria responde a
todas as dúvidas a todos os participantes da mesma categoria.

A Oria Partners agradece a participação e permanece à disposição pelo contato acima.

---

## 8. Destinatários (nota interna, não enviar)

| Categoria | Destinatários | Observação da verificação de 27/10/2026 |
|---|---|---|
| A | Infosimples; Exato Digital; Dabradata | Infosimples: 930 consultas no catálogo; a de protestos foi descontinuada |
| B | Escavador; JUDIT; Jusbrasil; Exato Digital | JUDIT publica preço; Escavador mostra a tabela só no painel |
| C | Serasa Experian; Boa Vista (Equifax); Quod | Serasa Concentre PJ reúne protestos nacionais, ações, falências e sócios |
| D | Pluggy; Belvo; Klavi | Klavi é desenhada para PF; perguntar primeiro quem é a receptora |
| E | Núclea; CERC | a pergunta 2 decide se a trava bancária entra no sistema |
| F | ONR (contato técnico do ONR) | sem observação |

O SERPRO Integra Contador não entra no RFP: é contratado na Loja SERPRO por tabela pública (13A,
item 3.3).
