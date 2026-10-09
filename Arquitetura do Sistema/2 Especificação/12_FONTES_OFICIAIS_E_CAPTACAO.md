# 12 — Fontes oficiais (SPED, eSocial, logística, CNAB, CNAE) e a captação automática

**Data:** 09/10/2026 · **Base:** `8ae5c35` · **Natureza:** especificação. Nada aqui está
implementado; o que já existe está apontado com o arquivo que o prova. Trechos marcados
**[A CONFIRMAR]** dependem de verificação com o órgão ou o fornecedor antes de virar código.

**Origem, em ordem de autoridade:**

1. **O pedido do dono** (09/10/2026): o sistema deve **ler e usar todos os arquivos e grupos de
   todas as categorias** (SPED, eSocial, conhecimento de transporte e de embarque, CNAB, CNAE),
   interligados e voltados para a reestruturação, e a captação deve ser **automatizada ao máximo**.
2. A **Especificação 11** (`11_ANALISE_DE_CREDITO_ASSESSORIA.md`), Etapa 4 (a trilha transacional) e
   §5 (consulta externa como dado). Esta especificação **estende** a 11: amplia o escopo do §4 de
   "SPED, CAP, CAR e extratos" para todas as famílias abaixo e acrescenta a captação (§9 a §11).
3. O que o sistema já tem: os tipos `SPED`, `EXTRATO_BANCARIO`, `AGING_AP` e `AGING_AR` existem,
   todos `sem_consumidor` (`Supabase/migrations/0187_o_tipo_que_chegava_sem_leitor_declarado.sql`);
   o `book-distress` (`Dados de Teste/book-distress`) gera aging e extrato fechando no BP; o teto
   de envio da borda (`.claude/memory/teto-da-borda-recusa-antes-do-codigo.md`).

**Leitura adotada de um termo ambíguo.** A anotação manuscrita "notas de conte…", sobre
logística, foi lida como **conhecimento de transporte** (CT-e) e **conhecimento de embarque**
(B/L). Se for outro documento, o §3 muda; o resto não.

---

## Resumo

**Decisão: o sistema lê e usa todos os arquivos das quatro famílias abaixo, sem exceção de
módulo ou grupo.** Eles mudam a análise de "o que a empresa declara" para "o que ela entregou ao
fisco, ao governo e ao banco". São arquivos de leiaute oficial: a leitura é **determinística, sem
IA**, e cada número aponta para o arquivo e a linha de onde saiu.

| Família | O que é | Quem gera | O que acrescenta à análise |
|---|---|---|---|
| **SPED** | Contabilidade e tributos entregues à Receita | Contador, via programas da RFB | Balancete mensal oficial, notas fiscais, impostos apurados, inventário, retiradas de sócios |
| **eSocial** | Eventos trabalhistas e previdenciários | Departamento pessoal | Folha, funcionários, rescisões, FGTS, INSS, processos trabalhistas |
| **Logística** (CT-e, MDF-e, conhecimento de embarque) | Documentos do transporte da mercadoria | Transportadora, armador, despachante | Frete real, rotas, comércio exterior, prova de que a venda saiu de fato |
| **CNAB** (FEBRABAN) | Arquivos que a empresa troca com o banco | Banco e ERP | Extrato, boletos emitidos e pagos, pagamentos a fornecedores, débito automático |

O **CNAE** (§5) não é arquivo: é o campo que liga a empresa ao setor e aparece em várias fontes.

**Estado hoje.** `SPED` e `EXTRATO_BANCARIO` existem como tipo, mas nada os lê, e não há SPED em
produção (`0187`). eSocial, CT-e, conhecimento de embarque, CNAB de cobrança e de pagamento e o
CNAE da entidade **não existem** no sistema.

**Regra que vale para todos (D3 da Espec. 11):** o documento é opcional, mas quando chega é
usado. Quando falta, o sistema diz o efeito — "sem SPED, a receita foi conferida só contra o que o
cliente declarou" (regra 1).

---

## §1 SPED: a versão da empresa que foi entregue ao fisco

A escrituração é texto separado por `|`, que começa em `|0000|` (empresa e período) e termina em
`|9999|` (total de linhas: o controle de leitura completa). Os documentos eletrônicos (NF-e, CT-e)
são XML.

### Todos os módulos

| Módulo | Periodicidade | Registros-chave | O que o sistema usa |
|---|---|---|---|
| **ECD** (contábil) | anual | `I050` plano de contas · `I051` plano referencial da RFB · `I155` saldos mensais · `I200`/`I250` lançamentos · `J100` balanço · `J150` DRE | Balancete mensal oficial conta a conta; confronto com as demonstrações enviadas; o `I051` pode resolver a conta canônica (F4) |
| **ECF** (IRPJ/CSLL) | anual | `L100` balanço · `L300` DRE · `M300` LALUR · `Y540` receita por atividade · `Y600` sócios e remuneração | DRE fiscal, lucro real × contábil, segmento faturado, retiradas de sócios |
| **EFD ICMS/IPI** | mensal | `0150` participantes · `0200` itens · `C100`/`C170`/`C190` notas · `D100` fretes · `E110` apuração ICMS · `H010` inventário · bloco `K` produção e estoque | Receita por nota e CFOP, clientes e fornecedores reais, ICMS devido, estoque fiscal |
| **EFD-Contribuições** | mensal | `A100` serviços · `C100`/`C180` vendas · `M200`/`M600` PIS e COFINS | Receita de serviço, PIS/COFINS devidos |
| **EFD-Reinf** | mensal | série `R-2000` retenções e CPRB · série `R-4000` IR retido · `R-9001`/`R-9005` totalizadores | Tributos retidos na fonte; com o eSocial, forma a DCTFWeb |
| **NF-e / NFC-e** (XML) | por nota | emitente, destinatário, itens, NCM, CFOP, valor, chave | Vendas e compras nota a nota, inclusive meses ainda não escriturados |
| **NFS-e** (padrão nacional) | por nota | prestador, tomador, serviço, ISS | Receita de serviços |
| **CT-e e MDF-e** | por documento | ver §3 | Frete e transporte |

A e-Financeira também é SPED, mas quem a entrega são os bancos; a empresa não tem acesso. Fica fora.

### Reconciliações que o SPED habilita

S1 a S6 são as da Espec. 11 §4.2; S7 é nova.

| # | Confronto | O que revela |
|---|---|---|
| S1 | DRE enviada × ECD `J150` × ECF `L300` | Demonstração gerencial diferente da transmitida. O achado mais importante possível |
| S2 | Balancete enviado × ECD `I155`, conta a conta | Ajustes feitos depois da transmissão |
| S3 | Receita da DRE × notas de saída (`C190`, NF-e) | Venda sem nota, ou nota sem receita |
| S4 | Estoque do BP × inventário `H010` × bloco `K` | Estoque inflado: onde a perda se esconde em empresa em crise |
| S5 | ICMS, PIS e COFINS a recolher × `E110`, `M200`, `M600` × `SITUACAO_FISCAL` | Imposto apurado e não pago, ou fora do passivo |
| S6 | Lucro contábil × LALUR `M300` | Adições e exclusões relevantes |
| S7 | Retenções da Reinf × passivo tributário | Imposto retido de terceiros e não repassado |

**Limites.** O SPED mostra o declarado, não necessariamente a verdade. A ECD do ano corrente ainda
não existe (a EFD mensal e o XML cobrem). Empresa do Simples tem pouco SPED: a ausência vira nota
com efeito, nunca silêncio.

---

## §2 eSocial: a folha de pagamento oficial

Cada fato trabalhista vira um evento XML. O sistema lê **todos os grupos**, mas grava **números
agregados por padrão**: o XML individual traz CPF e salário, e o detalhe por pessoa só é guardado
quando a análise precisa dele (custo de rescisão). Ver `10_DADOS_RETENCAO_E_LGPD.md`.

| Grupo | Eventos | O que o sistema usa |
|---|---|---|
| **Tabelas** | `S-1000` empregador · `S-1005` estabelecimentos · `S-1010` rubricas · `S-1020` lotações · `S-1070` processos adm./judiciais | Perímetro (quais CNPJs empregam), dicionário das verbas, processos que suspendem tributo |
| **Periódicos** | `S-1200` remuneração · `S-1210` pagamentos · `S-1260` produção rural · `S-1270` avulsos · `S-1280` desoneração · `S-1298` reabertura · `S-1299` fechamento | Folha bruta por mês, o que foi pago e quando, desoneração; `S-1298` mostra folha reaberta depois de fechada |
| **Vínculos** | `S-2190` · `S-2200` admissão · `S-2205`/`S-2206` alterações · `S-2230` afastamento · `S-2231` cessão · `S-2298` reintegração · `S-2299` desligamento · `S-2300`/`S-2306`/`S-2399` sem vínculo | Headcount mês a mês, rotatividade, demissões em massa, tempo de casa e salário para o **custo de rescisão** |
| **Saúde e segurança** | `S-2210` CAT · `S-2220` exames · `S-2221` toxicológico · `S-2240` agentes nocivos | Passivo potencial: acidentes, insalubridade, aposentadoria especial |
| **Processos trabalhistas** | `S-2500` processo · `S-2501` tributos do processo | Acordos e condenações **declarados**, com valor |
| **Totalizadores** | `S-5001`/`S-5011` contribuição previdenciária · `S-5002`/`S-5012` IRRF · `S-5003`/`S-5013` FGTS · `S-5501`/`S-5503` de processo | O número oficial do mês em uma linha: o ponto de partida |
| **Exclusão** | `S-3000` · `S-3500` | Eventos apagados depois de transmitidos; muitos em folha antiga são alerta |

Os eventos de regime próprio (`S-1202`, `S-1207`, `S-2400` a `S-2420`) só valem para órgão
público; o leitor os reconhece, mas não aparecem em mandato privado. Vêm junto dois derivados: a
**DCTFWeb** (débito previdenciário declarado × pago, montada de eSocial + Reinf) e o **FGTS Digital**.

| # | Confronto | O que revela |
|---|---|---|
| E1 | Despesa de pessoal da DRE × `S-5011` + `S-1200` | Folha fora do resultado, ou despesa inflada |
| E2 | INSS e IRRF descontados (`S-5011`, `S-5012`) × DCTFWeb paga × extrato | **Desconto do empregado não repassado**: passivo e crime de apropriação indébita para os sócios |
| E3 | FGTS devido (`S-5013`) × FGTS Digital pago | FGTS atrasado: passivo e risco de rescisão indireta |
| E4 | `S-2500` × provisões do BP × certidões | Passivo trabalhista sem provisão |
| E5 | Headcount × receita | Produtividade e custo de um plano de reestruturação |

---

## §3 Logística: conhecimento de transporte e conhecimento de embarque

"Conhecimento" é o documento que prova que a mercadoria foi entregue a um transportador. No
Brasil é eletrônico (CT-e) e se liga à NF-e pela chave. No comércio exterior é o **conhecimento de
embarque** (*bill of lading*). Para a análise, é a prova física de que venda e compra aconteceram.

| Documento | Campos que o sistema lê | O que o sistema usa |
|---|---|---|
| **CT-e** (modelo 57) | remetente, destinatário, tomador, origem/destino, frete, peso, **chaves das NF-e transportadas** | Frete real por rota e cliente; prova de que a nota de venda saiu |
| **CT-e OS** (modelo 67) | tomador, valor, percurso | Transporte de pessoas e valores |
| **MDF-e** (modelo 58) | veículo, percurso, chaves dos documentos | Frota própria, viagens por mês, consistência do volume vendido |
| **EFD `D100`/`D190`** | valor, CFOP, crédito de ICMS | Frete de compra e venda mês a mês, mesmo sem os XML |
| **B/L marítimo** e **CE-Mercante** | embarcador, consignatário, porto, data de embarque, mercadoria, frete | Data real de exportação/importação, frete internacional, mercadoria em trânsito |
| **AWB** (aéreo) · **CRT** (rodoviário internacional) · **TIF/DTA** (ferroviário) | os mesmos do B/L | Idem, por modal |
| **DU-E** (exportação) | NF-e exportadas, valor, moeda, país, averbação | Receita de exportação comprovada; exposição cambial por moeda e país |
| **DI / DUIMP** (importação) | fornecedor estrangeiro, NCM, valor aduaneiro, tributos, moeda | Compras importadas, dependência externa, passivo em moeda estrangeira |

| # | Confronto | O que revela |
|---|---|---|
| L1 | NF-e de venda × CT-e/MDF-e que a transportou | **Venda sem transporte**: receita que pode não ter existido (vendas CIF ou frota própria) |
| L2 | Frete da DRE × Σ CT-e × `D100` | Frete fora do custo, margem bruta superestimada |
| L3 | Receita de exportação (CFOP `7xxx`) × DU-E averbada × câmbio no extrato | Exportação que não embarcou, ou ACC/ACE sem embarque |
| L4 | Data do conhecimento de embarque × reconhecimento da receita | Receita antecipada no fechamento (corte) |
| L5 | DI/DUIMP × estoque e fornecedores do BP | Mercadoria em trânsito sem registro, fornecedor externo fora do passivo |
| L6 | Concentração de transportadores e rotas | Dependência operacional |

O B/L e o AWB chegam em PDF: é o único item desta especificação lido por **IA**, conferido contra o
CE-Mercante.

---

## §4 CNAB (FEBRABAN): os arquivos que a empresa troca com o banco

Arquivo posicional (cada campo em colunas fixas). **Remessa**: empresa → banco. **Retorno**: banco
→ empresa. Estrutura: cabeçalho → lotes → detalhes → rodapés com quantidade de registros e totais
(o controle de leitura completa). **CNAB 240** é padronizado em segmentos; **CNAB 400** varia por
banco; **CNAB 150** é o débito automático. O leitor tem um leiaute por versão e, no 400, por banco.

| Serviço | Segmentos (240) | O que o sistema usa |
|---|---|---|
| Cobrança: remessa | `P` título · `Q` sacado · `R` desconto/multa/juros · `S` mensagens · `Y` complementos e Pix | Carteira de clientes título a título |
| Cobrança: retorno | `T` situação · `U` valores pagos, juros, tarifas | **CAR real**: liquidações, atrasos, protestos, baixas, títulos **descontados ou cedidos** |
| Pagamentos | `A`/`B` crédito em conta, TED, Pix · `C` · `J`/`J-52` boletos · `W` | **CAP real**: quem foi pago, quando, quanto; folha por crédito em conta |
| Tributos | `O` com código de barras · `N` sem código (DARF, GPS, GARE, FGTS) | Imposto efetivamente pago |
| Extrato para conciliação | `E` | Saldo e lançamentos por conta (como o OFX) |
| Débito automático (CNAB 150) | autorização e débito | Recebimento recorrente e inadimplência |
| Cobrança CNAB 400 | detalhe com código de ocorrência por banco | Idem cobrança 240, leiaute antigo |
| Custódia de cheques | leiaute do banco | Recebível em cheque, inclusive em garantia |

| # | Confronto | O que revela |
|---|---|---|
| C1 | Carteira de cobrança × CAR do BP | Recebível inflado ou baixado sem pagamento |
| C2 | Carteira descontada/cedida × dívida declarada | **Antecipação de recebíveis**: dívida de curtíssimo prazo fora do `MAPA_DIVIDA` |
| C3 | Vencimento × liquidação | DSO efetivo e inadimplência por cliente |
| C4 | Pagamentos × CAP × vencimentos | DPO efetivo, fornecedor que deixou de ser pago |
| C5 | Tributos pagos (`N`, `O`) × apurados (SPED, eSocial) | Imposto apurado e não pago |
| C6 | Extrato (`E`) × caixa e bancos do BP | Conciliação de saldo por conta |

Para extrato, o OFX (Espec. 11 §4.6.1) continua a primeira opção; o CNAB `E` é a segunda.

---

## §5 CNAE: o código que diz em que setor a empresa está

Classificação oficial da atividade (IBGE). Hierarquia, com `1091-1/01` de exemplo:

| Nível | Formato | Exemplo | Uso no sistema |
|---|---|---|---|
| Seção | letra (21) | `C` Indústrias de transformação | Visão do portfólio |
| Divisão | 2 dígitos | `10` Produtos alimentícios | **Chave do setor**: benchmarks, fontes setoriais, pares |
| Grupo | 3 dígitos | `109` | Pares mais próximos |
| Classe | 4 + DV | `1091-1` | Estatísticas do IBGE (PIA, PAC, PAS) |
| Subclasse | 7 dígitos | `1091-1/01` | Cadastro, tributação, enquadramento |

Cada CNPJ tem um principal e vários secundários, por estabelecimento; o principal costuma estar
desatualizado.

| Fonte | Campo | O que diz |
|---|---|---|
| Cadastro CNPJ (dados abertos RFB) | principal e secundários | Setor **declarado** |
| ECF `Y540` | receita por CNAE | Setor **faturado**, com peso. É o que vale |
| eSocial `S-1005` | CNAE preponderante | Alíquota RAT/FAP, custo da folha |
| NF-e / NFS-e | CNAE do emitente (quando informado) | Atividade de cada venda |
| Novo CAGED | emprego por CNAE | Tendência do setor |

Usos na reestruturação: segmento real × declarado; pares e benchmarks para o laudo e o plano;
risco setorial (o problema é da empresa ou do setor?); enquadramento tributário (Simples,
desoneração, ST, RAT) e o passivo de CNAE errado; o catálogo de fontes por divisão (Espec. 11
§2.2). **No sistema:** atributo da entidade do perímetro (F1), vindo do cadastro e confrontado com
o `Y540`. Hoje não existe no banco.

---

## §6 Como tudo se conecta

```
 ARQUIVOS DE LEIAUTE OFICIAL (sem IA)           TRILHA DETERMINÍSTICA
 ┌──────────────────────────────┐               ┌────────────────────────────────────────┐
 │ SPED  ECD·ECF·EFDs·Reinf·NF-e│               │ 1. Roteador de formato (pelo conteúdo) │
 │ eSocial  todos os grupos     │──────────────►│ 2. Leitores determinísticos (+controle)│
 │ Logística  CT-e·MDF-e·B/L·DU-E│              │ 3. Tabelas novas                       │
 │ Banco  CNAB 240/400/150·OFX  │               │ 4. CHAVES COMUNS: CNPJ/CPF · chave NF-e│
 │ Cadastro CNPJ e CNAE         │               │    · competência · conta · CNAE        │
 └──────────────────────────────┘               │ 5. Reconciliação contra BP e DRE       │
 ┌──────────────────────────────┐               └───────────────────▲───────┬────────────┘
 │ Extração por IA (atual)      │───────────────────────────────────┘       │
 │ PDF/xlsx → campo_extraido    │                                           ▼
 └──────────────────────────────┘      Book Excel · Lista de credores · Caixa 13 semanas · Laudo
```

É nas chaves comuns que o fornecedor da EFD (`0150`) vira o mesmo do CNAB de pagamentos e da lista
de credores, e o empregado do eSocial vira o credor trabalhista.

---

## §7 Cada fonte nas frentes da reestruturação

| Frente | Pergunta | Fontes | Entrega |
|---|---|---|---|
| **Diagnóstico** | Os números são verdadeiros? | S1–S7 · E1 · L1 · C6 | Demonstrações conferidas contra fisco e banco |
| **Caixa realizado e 13 semanas** | Quando o caixa acaba? | OFX/CNAB `E` · cobrança `T`/`U` · pagamentos `A`/`J` · folha `S-1210` · tributos `N`/`O` | Caixa efetivo mensal; entradas pelo vencimento dos títulos, saídas pelo CAP e pela folha |
| **Lista de credores** (Lei 11.101, art. 51) | Quem, quanto, que classe? | I trabalhista: `S-2299`, `S-2500`, `S-5013` · II garantia real: contratos e garantias · III quirografários: CAP + EFD `0150` + CNAB pagamentos + DI/DUIMP · IV ME/EPP: porte no cadastro CNPJ | Relação nominal com CNPJ/CPF, valor, vencimento, classe e fonte por linha |
| **Fora da recuperação** | O que não entra no plano? | Recebíveis cedidos (CNAB) · tributos (SPED, DCTFWeb, Reinf) | Cessão fiduciária e débito tributário separados |
| **Passivo fiscal e transação** | Quanto se deve ao fisco, e quanto é crime? | `E110`, `M200`/`M600`, Reinf, DCTFWeb × pagos (CNAB `N`/`O`, extrato) | Débito apurado e não pago por tributo e competência; retenção não repassada em destaque |
| **Plano e laudo** (art. 53) | Se sustenta depois do plano? | `Y540`, NF-e · frete (CT-e) · folha e rescisão (eSocial) · pares por CNAE | Base realizada do modelo e premissas contra o setor |
| **Garantias e dinheiro novo** | O que está livre de ônus? | Carteira livre × cedida (CNAB) · `H010` · imobilizado (ECD) | Ativo livre para DIP ou nova linha |
| **Sócios** | Saiu dinheiro na crise? | ECF `Y600` · extrato (CPFs dos sócios) · mútuos | Retiradas por período × início da crise |
| **Risco setorial** | Empresa ou setor? | CNAE · Novo CAGED · estatísticas setoriais | Comparação com pares para a apresentação aos credores |

A frente que mais ganha é a lista de credores: deixa de depender do que o cliente diz.

---

## §8 Arquitetura de leitura

A trilha é a da Espec. 11 §4.1, com o escopo ampliado. Cinco passos iguais para todas as fontes:

1. **Reconhecer pelo conteúdo**, não pelo nome: `|0000|` (SPED), namespace XML (eSocial, NF-e,
   CT-e), linha de 240/400/150 posições com código do banco (CNAB), `OFXHEADER`.
2. **Ler registro por registro com proveniência**: arquivo, linha, registro.
3. **Conferir que leu tudo** (regra 7): `|9999|`, rodapés do CNAB, `S-1299`. Leitura incompleta é
   falha visível, nunca dado parcial apresentado como completo.
4. **Ligar pelas chaves comuns**: CNPJ/CPF, chave da NF-e, competência, conta contábil, CNAE.
5. **Reconciliar contra BP e DRE**, com a divergência explicada ou a ausência com o efeito.

`campo_extraido` não muda (roadmap §9, item 9). Tabelas propostas, ao lado:

| Tabela | Recebe |
|---|---|
| `documento_fiscal_registro` | SPED (todos os módulos) e XML de NF-e, NFS-e, CT-e, MDF-e |
| `evento_trabalhista` | eSocial, DCTFWeb, FGTS Digital (agregado por padrão) |
| `lancamento_bancario` | OFX, CNAB `E`, CSV, PDF |
| `titulo` | Cobrança e pagamentos (CNAB 240/400/150) e aging do ERP |
| `documento_comex` | DU-E, DI/DUIMP, CE-Mercante, B/L, AWB, CRT |
| atributo da entidade | CNAE principal e secundários, porte, regime |

### Ondas de leitura

| Onda | Escopo | Destrava |
|---|---|---|
| 1 | ECD + ECF; CNAE da entidade; medir o `I051` em 3 ECDs reais | S1, S2, S6; segmento real; hipótese da F4 |
| 2 | OFX, CNAB `E`, CNAB cobrança e pagamentos (240, 400, 150) | Caixa realizado, 13 semanas, recebível cedido, DSO/DPO efetivos |
| 3 | EFD ICMS/IPI, Contribuições, Reinf, XML NF-e/NFS-e | Receita nota a nota, passivo fiscal, retenções |
| 4 | eSocial (todos os grupos), DCTFWeb, FGTS Digital | Classe I, encargos não recolhidos, custo de rescisão |
| 5 | CT-e, MDF-e, DU-E, DI/DUIMP, CE-Mercante, B/L, AWB, CRT | Prova física de venda, frete, câmbio |

Cada onda entra com book sintético fechando no BP e portão no CI, no padrão do `book-distress`, e
cada reconciliação nova é medida não-vazia antes do commit (regra 2).

---

## §9 Captação: como pegar cada informação

**Três canais, do mais automático ao mais manual.** Para cada fonte o sistema tenta o primeiro
canal disponível e só cai para o seguinte quando ele falha. O cliente age duas vezes: assina a
autorização no kickoff e encaminha um pedido ao contador.

| Canal | Como funciona | O que o cliente faz | Automação |
|---|---|---|---|
| **A. Dado público** | Consulta por CNPJ/CPF assim que o caso é criado | Nada | Total |
| **B. Acesso delegado** | O cliente autoriza a Oria uma vez (procuração eletrônica no e-CAC, consentimento Open Finance, ou certificado A1 custodiado); coletores agendados buscam e repetem | Assina a autorização | Alta, depois da autorização |
| **C. Pacote do contador e do ERP** | O sistema gera a lista exata por regime e período e um link de envio; o contador sobe um zip e o sistema classifica pelo conteúdo | Encaminha o pedido | Média: pedido e leitura automáticos, envio humano |

| Fonte | Canal | Como, na prática | Alternativa | Atualização |
|---|---|---|---|---|
| Cadastro CNPJ, CNAE, QSA, porte, regime | A | Dados abertos do CNPJ (RFB), carga mensal | APIs comerciais de CNPJ | mensal |
| IBAMA, CEIS/CNEP, PGFN, trabalho escravo | A | Dados abertos e API do Portal da Transparência (Espec. 11 §3.4) | — | mensal |
| Processos (metadados) | A | API pública DataJud, por número de processo já conhecido | Provedor comercial para descoberta | semanal |
| ECD, ECF | B | Procuração eletrônica no e-CAC + ReceitaNet BX | C: `.txt` e recibos do contador | anual |
| EFD ICMS/IPI, Contribuições, Reinf | B | Idem. ReceitaNet BX é desktop, sem API: automatizar exige RPA, frágil. **[A CONFIRMAR]** quais módulos entrega a procurador | C: contador | mensal |
| Situação fiscal, DCTFWeb, parcelamentos, Caixa Postal | B | API Integra Contador (SERPRO, paga, usa a procuração). **[A CONFIRMAR]** serviços e preço | e-CAC manual | mensal |
| NF-e e CT-e **recebidas** | B | Web service de Distribuição DF-e com o A1 do cliente | C: ERP; plataformas de captura de XML | diária |
| NF-e, NFS-e, CT-e **emitidas**, MDF-e | C | Export de XML do ERP | Distribuição DF-e no que couber | mensal |
| eSocial | C | Export do sistema de folha | B: web service de download de eventos. **[A CONFIRMAR]** se procurador pode | mensal |
| FGTS Digital | C | Extrato e guias pelo cliente | — | mensal |
| Extrato bancário | B | **Open Finance** via agregador contratado; consentimento do representante da PJ | C: OFX | diária |
| CNAB cobrança e pagamentos | C | Pasta de retornos do ERP ou internet banking | B: VAN ou API de cobrança do banco | semanal |
| Registrato (SCR) | C | O sócio baixa pelo gov.br; sem API para terceiros | — | mensal |
| DU-E, DI/DUIMP, CE-Mercante | C | Despachante exporta do Portal Único Siscomex. **[A CONFIRMAR]** API com certificado | B, se a API servir | mensal |
| B/L, AWB, CRT | C | PDF do armador, lido por IA, conferido contra o CE-Mercante | — | por embarque |
| CAP e CAR (aging) | C | Relatório do ERP em xlsx/csv | — | semanal |

**Por que o canal B primeiro:** com uma autorização, a Oria deixa de depender de o cliente lembrar
de mandar arquivo, e durante a RJ o caixa de 13 semanas e o passivo fiscal se atualizam sozinhos.

---

## §10 Fluxo operacional do caso

```
                 Kickoff do caso (CNPJ, regime, período; cliente assina a autorização)
                    │                       │                          │
           A. Dado público        B. Acesso delegado         C. Pacote do contador  ◄──┐
           (dia 0, ninguém age)   (coletores agendados)      (pedido gerado + link)    │
                    └───────────────────────┼──────────────────────────┘               │
                                 Entrada única no Storage                              │
                                 (roteador pelo conteúdo)                              │
                                            │                                          │
                                 Trilha determinística (§8)                            │
                                            │                                          │
                                 Painel de cobertura ──── todo mês: pede de novo ──────┘
                                 (chegou · falta · venceu · efeito)   o que falta ou venceu
```

---

## §11 O que construir para receber tudo sozinho

| # | Peça | O que faz | Por que |
|---|---|---|---|
| 1 | **Gerador de pedido por caso** | Do CNPJ, regime e período, gera a lista exata (quais SPEDs e anos, bancos, comex) como e-mail pronto com o link de envio | Pedido manual esquece itens; Simples não tem ECD — pedir gera ruído, não pedir sem dizer por quê gera ausência silenciosa |
| 2 | **Envio direto ao Storage** | URL assinada do Supabase Storage, sem passar pela função da Vercel; aceita zip, `.txt`, `.xml`, `.ret`, `.ofx` | A borda da Vercel recusa ~4,5 MB por requisição antes de o código rodar (13/09/2026: 48 arquivos, ~50 MB; `teto-da-borda-recusa-antes-do-codigo`) |
| 3 | **Consultas públicas automáticas** | Fluxo n8n ao criar o caso; grava em `consulta_externa` (Espec. 11 §5), **inclusive o vazio** | "Consultei e não achei" ≠ "não consultei" (regra 7) |
| 4 | **Cofre de credenciais e autorizações** | Procuração, consentimento Open Finance, A1; validade, escopo, termo assinado, registro de cada uso | Sem ele o canal B não existe; o A1 é a chave fiscal da empresa |
| 5 | **Coletores agendados** (canal B) | Fluxos n8n diários/mensais: Distribuição DF-e, Open Finance, Integra Contador e, se aprovado, ReceitaNet BX; cada coleta registra o que buscou e quantos itens vieram | Análise pontual vira monitoramento durante a RJ |
| 6 | **Painel de cobertura do caso** | Por fonte e mês: chegou, falta, venceu, efeito; reenvia o pedido | O analista deixa de caçar documento por e-mail |

As peças 1 a 3 não dependem de contrato novo. As 4 e 5 dependem das decisões abaixo.

---

## §12 Pré-requisitos para o sistema buscar tudo sozinho

Quatro grupos: o que a Oria monta uma vez, os contratos, o que cada cliente entrega no kickoff (a
reunião de abertura do mandato) e o que continua humano por limite dos órgãos e dos bancos.

### O que a Oria precisa ter (uma vez, e manter)

| # | Pré-requisito | Para quê | Observação |
|---|---|---|---|
| P1 | **e-CNPJ A1 da Oria** (ICP-Brasil) | Identidade dos coletores como procuradores no e-CAC, Integra Contador e eSocial | Vence todo ano; vencido, o canal B inteiro para no mesmo dia. O painel (peça 6) deve avisar antes |
| P2 | **Cofre de credenciais** (peça 4) | Guardar o A1 da Oria e, se D12.2, o dos clientes, com registro de cada uso | O A1 do cliente é a chave fiscal da empresa dele |
| P3 | **Pacote jurídico e LGPD** | Termo de autorização, cláusula no contrato do mandato, RIPD, política de retenção (`10_DADOS_RETENCAO_E_LGPD.md`) | Base legal da coleta; eSocial traz salário e CPF, extrato traz terceiros |
| P4 | **Responsável pelas credenciais** | Renovar, revogar ao fim do mandato, auditar | Sem dono, a autorização sobrevive ao caso |
| P5 | **Infraestrutura dos coletores** (peça 5) | Agendamento e chamadas com certificado na conexão (Distribuição DF-e, eSocial) | Com D12.5, também uma máquina dedicada ao ReceitaNet BX (desktop) |
| P6 | **Armazenamento** (peça 2) | XML e SPED de vários anos somam GB por cliente | Envio direto ao Storage; a borda da Vercel recusa ~4,5 MB |

### Contratos com fornecedores

| Fornecedor | Destrava | Sem ele | Decisão |
|---|---|---|---|
| SERPRO, Integra Contador (por consulta) | Situação fiscal, DCTFWeb, parcelamentos, Caixa Postal automáticos | e-CAC manual | D12.3 |
| Agregador de Open Finance (por conexão) | Extrato diário de todos os bancos | OFX manual | D12.4 |
| Chave da API do Portal da Transparência (gratuita) | CEIS, CNEP, CEPIM | — | — |
| *(opcional)* Provedor de consulta processual | Descoberta de processos por CPF/CNPJ | DataJud só por número conhecido | Espec. 11 §3.5 |

### O que cada cliente entrega no kickoff

| # | Item | Detalhe |
|---|---|---|
| K1 | Procuração eletrônica no e-CAC para o CNPJ da Oria | Uma por CNPJ do grupo (e-CNPJ do cliente ou gov.br do representante) |
| K2 | Consentimento de Open Finance | Um por banco, pelo representante legal |
| K3 | A1 do cliente e senha | Só com D12.2; destrava as NF-e recebidas automáticas |
| K4 | Termo de autorização e tratamento de dados | Modelo de P3 |
| K5 | Contatos do contador e do departamento pessoal | Destino do pedido do canal C (peça 1) |
| K6 | Lista de bancos, ERP e sistema de folha | De onde sai o CNAB e o eSocial |

### O que continua dependendo de alguém

| Fonte | Por que não é automática | Quem age |
|---|---|---|
| NF-e emitidas, CNAB de cobrança e pagamentos, CAP e CAR | Ficam no ERP do cliente | Contador ou financeiro, pelo link |
| eSocial e FGTS Digital | **[A CONFIRMAR]** acesso do procurador | Departamento pessoal |
| Registrato (SCR) | Só o titular baixa, pelo gov.br | Sócio |
| B/L, AWB, CRT | PDF do armador ou agente de carga | Despachante |
| ECD e EFDs | Sem API; só RPA no ReceitaNet BX | Robô (D12.5) ou contador |

O sistema não elimina esse trabalho, mas o barateia: o pedido sai pronto, o envio é um link e o
painel cobra o que falta todo mês. E cada um desses itens, enquanto não chega, aparece no painel
com o efeito nomeado (regra 1), nunca como fonte "sem achados".

---

## Decisões do dono em aberto

| # | Decisão | Bloqueia |
|---|---|---|
| D12.1 | A Oria aceita ser procuradora eletrônica dos clientes no e-CAC, com e-CNPJ próprio? | Canal B fiscal |
| D12.2 | A Oria aceita custodiar o A1 do cliente? Se não, NF-e recebidas vêm pelo ERP | Distribuição DF-e |
| D12.3 | Contratar o Integra Contador (SERPRO)? | Situação fiscal e DCTFWeb automáticas |
| D12.4 | Qual agregador de Open Finance (custo, cobertura PJ, LGPD)? | Extrato automático |
| D12.5 | RPA no ReceitaNet BX é aceitável, sabendo que quebra com a tela? | SPED automático |
| D12.6 | Termo de autorização e tratamento de dados do kickoff (jurídico) | Peças 4 e 5 |
| D12.7 | Política de dado pessoal do eSocial: até onde guardar o detalhe por empregado? | Onda 4 |

---

## Estado e encaixe

| Item | Estado hoje | Encaixe |
|---|---|---|
| Tipos `SPED`, `EXTRATO_BANCARIO`, `AGING_AP`, `AGING_AR` | 🟢 existem, `sem_consumidor` (`0187`) | — |
| Tipos para eSocial, CT-e/MDF-e, comex, CNAB cobrança/pagamento | 🔴 | migration de taxonomia, por onda |
| CNAE na entidade | 🔴 | F1 |
| Leitores (todas as famílias) | 🔴 | F2, em ondas (§8) |
| Reconciliações S1–S7, E1–E5, L1–L6, C1–C6 | 🔴 | F2/F6; as que dependem de conta canônica esperam F4 |
| Captação (peças 1–6) | 🔴 | 1–3 já; 4–5 após D12.1–D12.6 |
