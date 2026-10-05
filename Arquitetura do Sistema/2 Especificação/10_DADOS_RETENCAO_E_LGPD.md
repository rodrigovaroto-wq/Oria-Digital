# 10 — Dados do cliente: onde ficam, quanto tempo, como se recupera, quem vê

**Estado:** v1, escrito em 20/08/2026. As lacunas estão marcadas **[A CONFIRMAR]** e são de
configuração do plano/console, não de código — quem as fecha é o dono, com a conta do Supabase
aberta.

---

## Por que este documento existe

O diagnóstico de 11/08 registrou, na tabela de operação e segurança:

> **Sem backup/retenção declarados** — nada em `docs/` sobre restore. Dado de cliente em Supabase,
> sem procedimento de recuperação escrito.

E a sessão 36 mostrou por que isso não é burocracia: houve um susto de perda de dado no Supabase, e a
resposta teve de ser montada na hora. **A pergunta "como se recupera?" aparece sob pressão, que é o
pior momento possível para descobrir a resposta.**

Uma coisa este documento NÃO faz: prometer uma garantia que ninguém verificou. Onde a resposta
depende de configuração que não está no repositório, ele diz **[A CONFIRMAR]** em vez de escrever
uma frase tranquilizadora. Uma política de backup que não foi testada é uma crença, não um controle
— e este projeto inteiro existe para não confundir as duas.

---

## 1. Onde o dado do cliente mora

| Onde | O quê | Sai do Brasil? |
|---|---|---|
| **Supabase / Postgres** | Todo o estado: mandatos, entidades, períodos, documentos e versões, campos extraídos, pendências, decisões, trilha de auditoria | **[A CONFIRMAR]** — depende da região do projeto |
| **Supabase / Storage** | Os **arquivos originais** enviados pelo cliente (PDF, XLSX, CSV) | idem |
| **Provedor de IA** — hoje **Google (Gemini)**, antes OpenAI | O conteúdo do documento vai na chamada de classificação e de extração | **Sim** — servidores do provedor |
| **Vercel** | Nada persistente. O portal renderiza no servidor e não guarda dado de cliente | logs de requisição |
| **n8n** | Estado de execução do workflow, incluindo o binário do documento durante o lote | **[A CONFIRMAR]** — onde a instância roda |

> **O item que mais importa desta tabela é o terceiro.** Documento financeiro de cliente é enviado a
> um terceiro para ser lido. Isso é o desenho do produto, não um efeito colateral — e é o primeiro
> fato que qualquer conversa de LGPD com o cliente precisa ter à frente.
>
> **E O TERCEIRO MUDOU EM 24/08/2026:** era a OpenAI, passou a ser o Google (Gemini). Quem é ele hoje
> está declarado em `N8N/lib/provedor.mjs` (`PROVEDOR_PADRAO`), e a troca é uma variável de ambiente
> mais um rebuild — o que significa que **este parágrafo pode envelhecer sem ninguém perceber**.
> Antes de qualquer conversa de LGPD, confira lá qual provedor está ativo.
>
> **NÍVEL GRATUITO É OUTRO TRATAMENTO, e a diferença é exatamente esta.** No nível gratuito da API
> do Gemini o provedor usa o conteúdo enviado para melhorar os produtos dele; no pago, não. Ou seja:
> **documento real de cliente não pode rodar numa chave de nível gratuito** — só material sintético
> (`Dados de Teste/book-canastra`, `Dados de Teste/book-vertentes`). Confirme os termos vigentes no console do
> provedor antes de qualquer rodada com dado real.
>
> **[A CONFIRMAR] — e este é o item que a troca deixou EM ABERTO:** o acordo de tratamento
> (zero-retention / DPA) **não se herda de um provedor para o outro**. Qualquer acerto que existisse
> com a OpenAI não vale para o Google. Enquanto isso não estiver fechado com o provedor ATIVO, dado
> real de cliente não deve rodar no pipeline — ver `Arquitetura do Sistema/2 Especificação/f0/02`.

---

## 2. Retenção

**Hoje não há política de expurgo, e isso é uma escolha por omissão.** Nada apaga documento, versão,
campo extraído ou trilha; `fn_excluir_caso` existe e é manual. A `0114` acrescentou `fechado_em` para
distinguir mandato encerrado de mandato ativo, mas **fechar não apaga** — de propósito, porque a
trilha de auditoria é parte do produto.

O que precisa ser decidido, e é decisão do dono com o jurídico:

| Pergunta | Estado |
|---|---|
| Por quanto tempo o **arquivo original** fica no Storage depois de o mandato fechar? | **[A CONFIRMAR]** |
| Por quanto tempo o **dado extraído** fica? | **[A CONFIRMAR]** |
| A **trilha de auditoria** é imutável para sempre? (a `0126`/`0130` já a tratam como append-only) | proposta: sim |
| Há obrigação contratual de devolução ou destruição ao fim do mandato? | **[A CONFIRMAR]** |

**A recomendação de engenharia**, para quando a decisão vier: expurgar o **arquivo original** e
manter o **dado extraído com a trilha**. O arquivo é o que carrega mais dado pessoal incidental
(assinaturas, CPF de sócios, endereços) e é o que menos serve depois do fechamento; o extraído é o
que sustenta o trabalho entregue e a auditoria dele.

---

## 3. Recuperação — o que existe e o que precisa ser testado

### O que o Supabase oferece

- **Backup diário automático** nos planos pagos, com retenção que varia por plano. **[A CONFIRMAR]**
  qual plano e qual retenção.
- **Point-in-time recovery (PITR)** é um add-on. **[A CONFIRMAR]** se está ligado.
- **Storage** tem política própria; backup de bucket **[A CONFIRMAR]**.

### O que o repositório garante sozinho, e é bastante

Isto **não** depende de plano nenhum e vale registrar, porque muda o tamanho do problema:

- **O SCHEMA é reproduzível do zero.** `Supabase/migrations/` aplicadas em ordem reconstroem o banco
  inteiro, e o `Supabase/test/run.sh` faz exatamente isso a cada execução, contra Postgres 16. O
  `Supabase/schema.sql` é o espelho materializado, conferido no CI.
- **A configuração do pipeline é versionada.** Os quatro workflows do n8n saem de geradores, com
  `git diff --exit-code` no CI garantindo que o JSON commitado é o que o gerador produz.

**Ou seja: o que não se recupera de backup é o DADO — o schema e o pipeline se remontam do
repositório.** Isso é uma propriedade forte e ela foi construída de propósito.

### O teste que falta, e é o que transforma isto em controle

> **O procedimento operacional está escrito:** `Arquitetura do Sistema/6 Referência/RESTAURACAO.md`
> — com as consultas prontas (conferidas contra o `schema.sql`), o registro para preencher, e as
> três perguntas `[A CONFIRMAR]` desta seção respondidas no mesmo movimento. O que segue abaixo é o
> **critério**; aquele arquivo é a **execução**.

Um procedimento de restauração que nunca foi executado **não é um procedimento**. O que fecha esta
seção:

1. Restaurar um backup num projeto Supabase **descartável**;
2. Rodar `select * from fn_instalacao_conferir() where not presente` contra ele — nenhuma linha, os
   13 requisitos verdes, prova que o banco restaurado é o banco esperado; a sonda da `0131` existe
   exatamente para responder isso (até 21/08 ela tinha tela no portal, `/instalacao`, removida por
   decisão do dono; a função ficou);
3. Abrir um mandato e conferir que documento, extração e trilha vieram juntos;
4. **Anotar o tempo que levou** — porque "temos backup" e "voltamos em 40 minutos" são afirmações
   diferentes, e só a segunda serve para responder a um cliente.

---

## 4. Acesso: quem vê o quê

**Hoje o controle é binário, e isso está medido.** A `0003` estabeleceu que toda tabela exposta tem
policy "usuário autenticado pode tudo". A `0107` acrescentou **papel** (`analista` / `senior`) e o
usa para a ressalva do Portão 2 — que é o controle que mais precisava dele —, mas **as policies de
leitura continuam abertas a qualquer autenticado**.

Consequência exata, sem suavizar: **qualquer pessoa com acesso ao portal vê todos os mandatos.** Com
duas pessoas isso é aceitável e consciente; com a terceira, ou com um estagiário, deixa de ser.

O que falta, em ordem de quem destrava o quê:

1. **Segregação por mandato** — quem trabalha no mandato A não precisa ver o B. É a mudança de maior
   efeito e a que o cliente mais espera de uma boutique.
2. **Papel na leitura**, não só na escrita.
3. **Registro de acesso** — hoje a trilha registra o que foi *decidido*, não o que foi *lido*.

> **DECISÃO DO DONO em 05/10/2026 (D7 da `11_ANALISE_DE_CREDITO_ASSESSORIA.md`):** todo mandato
> tem NDA assinado, e o dado fica num banco **extremamente seguro e privado, sem possibilidade de
> vazamento**. Isso torna os três itens acima **pré-requisito** da trilha transacional (extrato,
> certidões de sócio PF, folha). Eles passam a ser a fatia **T0** daquela especificação, antecipada
> da F17, e deixam de ser apenas "o que falta". Nenhum lançamento bancário nem certidão de PF é
> gravado antes da T0. O NDA cobre a relação Oria–cliente; os terceiros que aparecem no extrato
> (empregados, sócios PF, fornecedores PF) seguem sob a LGPD, e a base legal precisa de uma linha
> aqui, a confirmar pelo jurídico.

> **`fn_papel` não é auto-atribuível**, e isso já está travado por teste desde a `0107`: um controle
> que o próprio usuário se concede não é controle. A promoção a `senior` é por migration.

---

## 5. Dado pessoal que atravessa o sistema, nomeado

Não é "dado financeiro" genérico. O que de fato passa por aqui:

- **CPF e assinatura** de sócios e contadores (contrato social, DF auditada, certidões);
- **CRC** de contador;
- **Nome e cargo** em organograma e headcount;
- **Folha de pagamento agregada** — e, em alguns headcounts, individualizada;
- **Razão social e CNPJ** das empresas, que não são dado pessoal mas identificam o mandato.

**Onde isso aparece fora do banco:** no prompt enviado ao provedor de IA (o documento inteiro vai como
imagem/PDF) e nos logs do n8n durante a execução. **[A CONFIRMAR]** por quanto tempo o n8n retém
dados de execução na instância em uso — é a configuração `EXECUTIONS_DATA_MAX_AGE`, e o padrão
guarda mais do que a maioria das pessoas imagina.

---

## 6. O que fazer com este documento

Ele fica **incompleto de propósito** até o dono responder os **[A CONFIRMAR]** com a conta aberta.
Um documento que preenchesse essas linhas por dedução seria pior que a ausência dele: pareceria
política e não seria — exatamente o defeito que a `0131` corrigiu do outro lado (recado em prosa que
nada executa).

**A ordem sugerida:** (1) região e plano do Supabase, que respondem metade das linhas de uma vez;
(2) o teste de restauração do §3, que é o único que transforma crença em controle; (3) a retenção do
§2, que é conversa com o jurídico; (4) a segregação por mandato do §4, que é engenharia e já tem
desenho.
