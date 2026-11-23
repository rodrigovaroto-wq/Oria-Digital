# Como o sistema funciona, do começo ao fim

Escrito em linguagem simples, de propósito. Quem quiser o detalhe técnico abre o
[plano de execução](../../Business%20Plan/06_execucao/PLANO_DE_EXECUCAO.md) ou o código; aqui é o mapa da estrada.

O sistema tem **três pernas**: o n8n (que processa), o Supabase (que guarda e
confere) e o portal (que mostra e deixa decidir). Nenhuma delas trabalha sozinha.

---

## Parte 1 — O documento chega (n8n)

**1.1. Listar arquivos.** Alguém sobe os documentos num formulário. O sistema
lista o que chegou.
> Atenção: o campo precisa estar marcado para aceitar **vários arquivos**. Sem
> isso ele aceita um por vez, e ninguém percebe até tentar subir 190.

**1.2. Classificar pelo nome.** Antes de gastar qualquer coisa com IA, o sistema
tenta adivinhar pelo nome do arquivo o que é aquilo (balanço? DRE? de que ano?).
Metade dos nomes resolve. A outra metade vai precisar da IA.

**1.3. Preparar o conteúdo.** Aqui ele decide **como ler** cada arquivo, olhando o
tipo dele.

**1.4. Roteador de formato.** Cada arquivo vai para **um** leitor, nunca para
vários:

| O arquivo é | Vai para | O que acontece |
|---|---|---|
| PDF | leitor de PDF | tenta pegar o texto nativo antes de gastar IA |
| Imagem | direto | a IA lê a imagem |
| CSV | leitor de CSV | vira tabela de texto |
| XLSX (Excel moderno) | leitor de XLSX | vira tabela de texto |
| XLS (Excel antigo) | leitor de XLS | vira tabela de texto |
| XML | leitor de XML | vira texto |
| Qualquer outro | direto | fica registrado que **não foi lido**, com o motivo |

> Essa última linha é o princípio da casa: quando o sistema não consegue ler uma
> coisa, ele **diz que não conseguiu**. Nunca finge que leu e devolve vazio.

**1.5. Juntar e recompor.** Um Excel vira muitas linhas; elas são reagrupadas de
volta no documento a que pertencem.

**1.6. Medir o documento.** Quantas páginas, quanto texto, quantos números.

---

## Parte 2 — A extração (n8n)

**2.1. Orçar o lote.** Antes de gastar **um centavo**, o sistema calcula quanto o
lote vai custar. Se passar do teto, ele **recusa o lote inteiro** e explica.
> Não existe "roda metade": meio lote deixa metade dos documentos registrados sem
> dados e a outra metade sem registro, e separar os dois depois é pior.

**2.2. Verificar a cota do dia.** O provedor de IA tem limite por dia. Se o lote
não couber, ele avisa antes — estourar no meio **mata** os documentos que faltavam.

**2.3. Classificar pela IA.** Só os documentos cujo nome não resolveu.

**2.4. Extrair pela IA.** Manda o documento e pede as linhas financeiras de volta,
num formato fixo. Documento grande é partido em pedaços e remontado.

**2.5. Diagnosticar.** Na mesma passada, a IA responde: *esse documento é mesmo o
que o nome diz? é dessa empresa? desse período?* Quando discorda, abre uma
**pendência** para um humano olhar.

**2.6. Reconciliar.** Quando dois documentos falam do mesmo número e discordam, o
sistema decide qual manda — e quando não dá para decidir com segurança, ele
**não decide**: marca como conflito e chama o analista.

**2.7. Resumo de custo e fechamento.** Grava quanto custou e marca o lote como
fechado. Lote que começou e não terminou fica visivelmente sem fechamento.

---

## Parte 3 — O banco confere (Supabase)

O banco não é um depósito passivo. Ele **recusa** coisa errada:

- **Nunca inventa número.** Valor que o documento não trouxe fica em branco, com
  nota dizendo por quê e qual o efeito.
- **O mesmo arquivo enviado duas vezes** é o mesmo documento, com uma versão nova.
- **Escala e moeda** (mil, milhão, R$) são convertidas ou a comparação é recusada
  — nunca chutadas.
- **Kit Básico**: confere se chegou o mínimo para o mandato fechar.
- **Sonda de instalação**: responde se o banco tem tudo que o código espera. É ela
  a autoridade, nunca um arquivo do repositório.

---

## Parte 4 — O analista decide (portal)

**4.1. Tela do caso.** O que chegou, o que extraiu, o que ficou pendente.

**4.2. Fila de revisão.** Cada pendência com o motivo e o efeito. Algumas bloqueiam
a aprovação; outras podem ser sobrepujadas com justificativa.

**4.3. Modelagem.** O analista escolhe as premissas e diz onde cada uma entra na
projeção.

**4.4. Exportar.** Sai um Excel com os dados e o modelo de projeção **vivo em
fórmula** — não é um retrato, é um modelo que o analista continua mexendo.

---

## Parte 5 — Apresentação para os bancos *(ainda não construída)*

Etapa final planejada: transformar os dados e a modelagem num **PowerPoint no
padrão da casa**, pronto para apresentar aos bancos.

Duas formas possíveis, a decidir:
1. O sistema **monta os slides** direto.
2. O sistema **monta um prompt** com os dados exatos do cliente e a especificação
   do modelo visual, para o slide ser produzido num chat.

A segunda é o plano B declarado: se a primeira não sair com qualidade excelente,
é melhor um prompt ótimo que um slide medíocre.

---

## O que atravessa tudo

**Nunca apresentar ausência como dado.** Um zero inventado é indistinguível de um
zero medido — e num mandato isso decide o futuro de uma empresa.

**Todo estágio que não rodou tem de parecer diferente de estágio que rodou e não
achou nada.** Foi o erro mais caro deste projeto.
