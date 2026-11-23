# Pendências, riscos e questões futuras

**Lista viva.** A decisão que gerou cada item está no
[registro v0.1.5](../07_decisoes/oria_digital_decisoes_e_pendencias_v0.1.5.html) (seção 19.13); aqui fica
a **situação** e o item do [plano](../06_execucao/PLANO_DE_EXECUCAO.md) que a resolve. Quando um item
fecha, marque a data e a evidência; a decisão nova, se houver, vai para uma nova versão do registro.

## 1. Decisões em aberto (o dono decide)

| Pendência | Decisões | Destrava | Situação |
|---|---|---|---|
| Plataformas: coordenação e hospedagem dos agentes, banco, automação, observabilidade | H3/H5, R2 | 0.1 → 1.D3, 1.D10, 3.1 | Aberta. Primeira entrega do plano |
| Gestão das integrações (interna ou centralizada) | N-C5a | 2.4, 2.5 | Aberta |
| Priorização das 31 frentes de diligência | B6 | 1.E1–1.E4, 2.2, 2.3 | Definida na construção de cada agente |
| Primeiro cliente além da Partners | A6 | G2 | Aberta (hipótese registrada) |
| Valores: teto de dados pagos, teto de IA, preços | N-C6b, D5, J1, J2 | 3.6 | Depende da medição do piloto |
| Quem monta o gabarito (papel) | D4 | 1.J2 | Aberta |
| Quem é o segundo revisor na Partners | R1 | 1.F2 | Aberta: pessoa a indicar |
| Deck, slide 5: "mais de 30 fontes" | — | — | **Não fechado pelo dono.** Hoje o código capta poucas fontes externas (séries do BCB e os arquivos do cliente). A regra 6 da documentação do deck diz que nada é afirmado no presente se ainda não existe |
| Deck, slide 10: retirada do prazo "3 a 6 meses" | K2 | — | Feita na Fase 3, coerente com a K2. O dono não confirmou explicitamente a frase final |
| **Classificação de documentos em N2 sem gabarito** (`0127_o_dial_obedecido.sql:493`, "declarada, não medida"): voltar a N1 junto com a extração no item 0.5, ou manter em N2 | D6 (fala só da extração) | 0.5, G0 | **Fechada em 23/11/2026: volta a N1** (D6-1, registro v0.1.4) |
| Gravidade "alto" (G5): "> 1%" de quê? O registro diz só "> 1%"; as regras leem "do EBITDA ou da dívida", como no crítico | G5 | 1.D6 | **Fechada em 23/11/2026: do EBITDA ou da dívida** (G5-1, registro v0.1.5) |
| Reconferir os defeitos do lote 2 que travam o uso (antiga ME1 do PLANO_MVP) e abrir um item por defeito que continuar aberto | — | Fase 1 | Aberta: a lista não foi reconferida na Fase 4 |
| Tirar do piloto alguma fonte de mercado do slide 5 (ANEEL/CCEE, ANTT/ANP, SUSEP, FipeZAP; item 1.C5) | K6 (pede **todos** os dados de mercado no piloto) | 1.C5, G1 | Só com decisão registrada do dono; sem ela, ficam no piloto |
| Ligar a conciliação do aging na rodada (`fn_reconciliar_caso`) | — | 1.A2 | **Fechada em 13/11/2026**: ligada pela `0278`, aplicada em produção (`ESTADO.md`, sessão 129b) |
| Arquivo real de AR e AP para medir a leitura | DM7 do PLANO_MVP | 1.A1 | Depende do dono |

## 2. Dependências de terceiros

| Dependência | Decisões | Destrava | Situação |
|---|---|---|---|
| Contrato de dados e cláusulas ANPD com cada provedor de IA | D1, K4 | 0.7, G0 | **Antes do piloto** |
| Integrador de dados pagos (processos, protestos, bureaus): fornecedor e valor | C2 | 2.4, 1.H3 | Cotação. Candidatos da pesquisa: Direct Data, Infosimples, Judit, BigDataCorp, Kronoos, Escavador |
| Open Finance (Res. Conjunta 21/2026): só como entidade parceira de integradora regulada | C4 | 2.5 | Parceria |
| Registradoras de recebíveis (CERC, B3, Núclea) | C6 | 4.3 | Parceria ou participante autorizado |
| Provedor de processos e fonte de notícias | — | 1.H3, 1.H4 | Escolha (1.H1) |
| Plataformas do estudo de infraestrutura | H1, H2, H3, H5 | 0.1 | Cotação e teste |

## 3. Parecer jurídico pendente

| Assunto | Decisões | Destrava |
|---|---|---|
| Custódia de certificado digital e procuração | C3 | 4.2 |
| Benchmarks com dados de vários clientes | C7 | 2.13 |
| Transferência internacional de dados para a IA | D1 | 0.7 |
| Backtest com cópias de casos reais | F4 | 2.10 |
| Retenção em três camadas | I2 | 2.12 |
| RIPD (parte jurídica) | I5 | 0.8, G0 |
| Base legal para consultar pessoa física (sócios, familiares) | — | 1.H1 |

## 4. O que depende de teste (não está provado até ser medido)

| O que | Como se prova | Item |
|---|---|---|
| Backup e restauração | Restaurar e conferir pela sonda | 0.2, 0.3 |
| Isolamento entre organizações | Teste de vazamento que reprova sem a política | 1.F5, 2.14 |
| Agente nunca calcula | Agente que inventa número tem a saída recusada | 1.D1 |
| Autonomia N2 | ~300 amostras, parte cega, ≥ 98% no limite inferior | 3.3 |
| Reversão por chave | Desligar a chave numa cópia; diagnósticos antigos iguais | 2.11 |
| Cadeia de hashes | Alterar um evento quebra a cadeia | 2.15 |
| Troca de provedor de IA | Derrubar um provedor; a tarefa segue | 1.D8 |
| Extração que não perde linha | Regressão no corpus real; falha silenciosa = 0 | 1.A5, 1.A6 |

## 5. Riscos

| Risco | Efeito se acontecer | Mitigação (item) | Situação |
|---|---|---|---|
| **Sem backup** (banco no plano gratuito; nada fora do provedor) | Perda dos mandatos reais | 0.2, 0.3 | **Aberto, urgente (K4)** |
| **n8n com acesso total** (`service_role`) num serviço sem SOC 2/DPA publicados | Vazamento de todos os mandatos | 0.4 | **Aberto, urgente (K4)** |
| **Extração e classificação em N2 sem medição** (`0041`, `0127`), com promoção automática ligada (`0137`) | Linha extraída ou documento classificado errado aceito sem humano | 0.5 | **Aberto, urgente (K4)** |
| **`main` sem proteção conferida** | Mudança sem revisão em produção | 0.6 | **Aberto, urgente (K4)** |
| **Sem contrato de dados com a IA** | Transferência internacional irregular | 0.7 | **Aberto, urgente (K4)** |
| Plataforma escolhida sem estudo | Reconstrução cara depois | 0.1 primeiro (R2) | Controlado pelo plano |
| Dependência de uma pessoa (o dono faz todos os papéis) | Segundo revisor e Técnico não fecham com uma pessoa só | 1.F2 (Partners), 3.5, 3.7 | Aberto até a contratação |
| Multiagente custa mais e piora em raciocínio sequencial (pesquisa da Fase 1, §1) | Custo e erro sobem sem ganho | Medir por agente (1.D9, 1.E5); só dividir com ganho medido | A medir no piloto |
| Responsabilidade civil por erro no diagnóstico | Ação do cliente ou do credor | Segundo revisor (E1), ressalvas (E3), teto contratual | Fora do escopo técnico (L1) |
| Canibalização entre Oria Digital e Oria Partners | Conflito comercial | — | Fora do escopo técnico (L1) |

## 6. Questões futuras (sem decisão, sem prazo)

- Autosserviço (A4).
- Valuation e recuperação de credores (etapas do plano antigo de 111 etapas). A apresentação a credores é o item 2.6 do plano.

## 7. Fora do escopo técnico (19.14)

Relação contratual entre Oria Digital e Oria Partners (L1); advogado/DPO, enquadramento no COAF,
cláusulas do contrato com o cliente e política de conflito de interesse (I1, I3, I4, L2).
