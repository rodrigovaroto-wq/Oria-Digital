# Business Plan — fonte central do negócio do Oria Digital

Esta pasta é a **fonte oficial de negócio e produto** do Oria Digital (decisão K5). A fonte oficial
**técnica** é [`Arquitetura do Sistema/`](../Arquitetura%20do%20Sistema/README.md); o deck para o sócio
investidor, em [`Apresentações/`](../Apresentações/Business%20Plan%20Oria%20Digital/README.md), é
**derivado** daqui.

**Regra da pasta: uma fonte por assunto.** Cada assunto tem um único arquivo oficial; os outros lugares
apontam para ele com um link, sem copiar. Decisões são citadas pelo código (`K6`, `B3b-1`) e o texto
delas fica só no registro.

## Onde está cada assunto

| Assunto | Fonte oficial |
|---|---|
| **Decisões** (o que foi decidido, com a fala do dono) | [`07_decisoes/`](07_decisoes/README.md) — registro **v0.1.4** |
| **Modelo de negócio, proposta de valor, clientes, cobrança, mercado, estratégia comercial, pedido ao sócio** | [`01_negocio/MODELO_DE_NEGOCIO_E_ESTRATEGIA.md`](01_negocio/MODELO_DE_NEGOCIO_E_ESTRATEGIA.md) |
| Modelo de projeção (premissas em branco até o piloto) | [`01_negocio/MODELO_DE_PROJECAO.md`](01_negocio/MODELO_DE_PROJECAO.md) |
| **Workflow do produto** e ponte para a arquitetura técnica | [`02_workflow_e_arquitetura/`](02_workflow_e_arquitetura/README.md) — workflow **v0.3.0** |
| **Agentes**: catálogo, responsabilidades, contrato, status real | [`03_agentes/AGENTES.md`](03_agentes/AGENTES.md) |
| **Regras de negócio e definições** (réguas, gravidade, aprovação, fontes, glossário) | [`04_regras_de_negocio/REGRAS_E_DEFINICOES.md`](04_regras_de_negocio/REGRAS_E_DEFINICOES.md) |
| **Memória, autoaprimoramento, papéis e publicação** | [`05_governanca/MEMORIA_AUTOAPRIMORAMENTO_E_GOVERNANCA.md`](05_governanca/MEMORIA_AUTOAPRIMORAMENTO_E_GOVERNANCA.md) |
| **Segurança, continuidade e dados pessoais** | [`05_governanca/SEGURANCA_E_DADOS_PESSOAIS.md`](05_governanca/SEGURANCA_E_DADOS_PESSOAIS.md) |
| **Plano de execução e roadmap** (único, sem datas) | [`06_execucao/PLANO_DE_EXECUCAO.md`](06_execucao/PLANO_DE_EXECUCAO.md) |
| **Pendências, riscos e questões futuras** (lista viva) | [`08_pendencias_e_riscos/PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md`](08_pendencias_e_riscos/PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md) |
| Validação de consistência da Fase 4 (retrato datado) | [`08_pendencias_e_riscos/VALIDACAO_DE_CONSISTENCIA.md`](08_pendencias_e_riscos/VALIDACAO_DE_CONSISTENCIA.md) |
| Pesquisa da Fase 1, com fontes | [`09_pesquisa/SINTESE_DA_PESQUISA_FASE1.md`](09_pesquisa/SINTESE_DA_PESQUISA_FASE1.md) |
| **Histórico** (versões anteriores, entrevista, rascunhos do deck, planos superados) | [`99_historico/`](99_historico/README.md) |

## Fora desta pasta (outras fontes oficiais)

| Assunto | Onde |
|---|---|
| Estado do dia (última migration, suítes, rodada mais recente) | [`ESTADO.md`](../ESTADO.md) |
| Como o sistema funciona e as especificações técnicas | [`Arquitetura do Sistema/`](../Arquitetura%20do%20Sistema/README.md) |
| O deck, o visual e como refazê-lo | [`Apresentações/Business Plan Oria Digital/DOCUMENTACAO.md`](../Apresentações/Business%20Plan%20Oria%20Digital/DOCUMENTACAO.md) |
| O que está no banco de produção | A sonda `fn_instalacao_conferir()`; nenhum arquivo é autoridade sobre o banco |

## Como manter

1. **Decisão nova ou mudada:** nova versão do registro (v0.1.4…), nunca edição da vigente; depois
   atualize os arquivos que citam o código (ver [`07_decisoes/README.md`](07_decisoes/README.md)).
2. **Item do plano avançou:** atualize a situação e a evidência no plano e no `AGENTES.md`, se for um
   agente. É o último passo de cada rodada (agente `estado-e-handoff`, comando `/fechar`).
3. **Pendência fechou:** marque no arquivo de pendências, com data e evidência.
4. **Dado do deck mudou:** mude em `01_negocio/` primeiro, reconferido na fonte primária (J3); depois
   refaça o deck.
5. **Nada é apagado sem autorização do dono.** O superado vai para `99_historico/`.
