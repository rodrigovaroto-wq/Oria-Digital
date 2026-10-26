---
id: f2e-parceiros-de-dados-e-pre-mandato-espec13
tipo: doutrina
toca:
  - Arquitetura do Sistema/2 Especificação/13_PARCEIROS_DE_DADOS_E_PRE_MANDATO.md
  - Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md
  - Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md
substitui: []
---

# F2E — parceiros de dados (bureau, processos, Núclea, Open Finance) e o momento pré-mandato: Espec. 13

Termos de busca: Núclea, CIP, Klavi, Clavi, Pluggy, Belvo, Open Finance, Exato Digital, Jusbrasil,
JUDIT, bureau, biro, Serasa, Boa Vista, Quod, pré-mandato, prospecção, parceiros, recebíveis, boleto,
Pix, F2E, Espec. 13, Obsidian.

**Estado (26/10/2026): planejada, nada implementado.** O plano com artefatos por etapa é a §4 da
Espec. 13. A fase no roadmap é a F2E.

## O que surpreende quem chega sem ler a Espec. 13

- **Open Finance foi recusado em 13/10 (D6 = D12.4) e REABERTO em 26/10 (D13.1).** Quem ler só a
  Espec. 11 ou a 12 vê a decisão antiga: as duas tabelas foram marcadas como revistas.
- **A Oria não pode receber Open Finance diretamente.** Só instituição autorizada pelo Banco Central
  participa. O agregador (ou quem ele usa) é o receptor, e a Oria entra como parceira.
- **A Núclea não tem Pix.** O Pix liquida no SPI do Banco Central. E o que a Núclea vende sobre um
  CNPJ é **agregado** (faixas anônimas, percentil, score): serve para plausibilidade, nunca para
  conciliar transação a transação com o OFX.
- **"Sem dados de transação" na Núclea não é erro nem zero.** Pode ser empresa nova ou movimento
  fora de boleto. Mostrar como não observado (regra 1).
- **Consentimento PJ de Open Finance expira em silêncio** quando a empresa tem mais de um sócio.
  "Expirado" e "sem movimento" são estados diferentes (regra 7).
- **Provedor de processos descobre, certidão prova.** Nenhum provedor substitui a certidão; a D5
  se decide medindo o provedor contra as certidões do mandato AMO, não por catálogo.
- **O Obsidian como dataroom foi descartado (D13.2).** O dataroom é o SharePoint e o link de envio.
- **Nenhum dado de PF antes da T0 e da autorização registrada.** Hoje todo usuário autenticado lê
  todo mandato.
