# Memória, autoaprimoramento e governança

**Fonte oficial** de como o sistema guarda memória, como ele melhora e quem decide o quê. Cita os
códigos do [registro v0.1.5](../07_decisoes/oria_digital_decisoes_e_pendencias_v0.1.5.html). Segurança
e dados pessoais estão em [`SEGURANCA_E_DADOS_PESSOAIS.md`](SEGURANCA_E_DADOS_PESSOAIS.md).

## 1. Papéis e quem decide

| Papel | Pode | Não pode | Quem é hoje (K3) |
|---|---|---|---|
| **Sócio** | Aprovar diagnóstico; aprovar acima de 3 ressalvas altas (E3-1); receber escalonamento de prazo vencido (E5); aprovar, junto com o Técnico, mudança que afeta número ou conclusão (E2); liberar o autoaprimoramento para código (F1-1) | — | O dono |
| **Analista** | Operar o mandato, decidir pendências, aprovar diagnóstico interno com checklist (E1) | Ser o próprio segundo revisor do que vai para fora (E1) | O dono |
| **Leitura** | Ver | Decidir | — |
| **Técnico** (E2) | Aprovar mudança técnica (código, prompts, regras, ferramentas) | Aprovar a mudança que ele mesmo propôs | O dono **[pessoa a contratar para separar do Sócio]** |
| **Segundo revisor** (E1, R1) | Revisar o que vai para fora | Ser o autor; ser um agente | No piloto: **um analista da Oria Partners** **[pessoa a indicar]** |
| **Revisor da consultoria** (L4, R1) | Revisar os mandatos da própria organização | Ver outra organização | No piloto: o mesmo analista da Partners |
| **Claude** (K3) | Implementar, revisar e documentar | **Aprovar** qualquer coisa | — |

Permissão para aprovar diagnóstico **não** dá permissão para aprovar mudança técnica (v0.1.2 §10).
Os papéis existentes hoje no banco são `socio`, `analista` e `leitura` (`Supabase/migrations/0216_o_acesso_que_so_o_portal_decidia.sql`);
**Técnico e revisor da consultoria ainda não existem**.

## 2. Memória

- **Base central**, separada por organização e mandato. Os agentes **não** guardam memória própria
  permanente por empresa; consultam a base por permissão (v0.1.2 §4).
- Aprendizados de **processo** podem melhorar os agentes; **dado confidencial** de um cliente nunca
  chega a outro (v0.1.2 §4, H4).
- O autoaprimoramento começa pelo histórico de análises, erros, correções e justificativas; consulta
  documentos originais só quando precisa e dentro da permissão do mandato (v0.1.2 §4).
- Decisões humanas ficam versionadas e justificadas, com vínculo às evidências (N-B5c), e servem de
  aprendizado dentro das permissões.

## 3. Autoaprimoramento

### 3.1 O que ele pode fazer, por fase

| Fase | Pode | Gatilho para passar |
|---|---|---|
| **A — inicial** (F1) | Só **propor** mudanças de prompts e regras, em rascunho. Nada vai à produção sem o Técnico | — |
| **B — após o gatilho** (F1-1, F1-2) | Propor também código, ferramentas e migrations | **≥ 50 erros** cometidos ou achados pelos agentes, em **≥ 3 etapas ou agentes**, validados pelo Auditor (F1-3) **e ≥ 60% das propostas aprovadas** (mínimo de 10) sem causar piora. Liberação por decisão registrada do Técnico e do Sócio |

O gatilho é por **erros e qualidade das propostas**, não por tempo (F1; substitui "3–6 meses" do roteiro).

### 3.2 Rotinas

- **Semanal** (F6): investiga, propõe e testa em ambiente isolado; relatório ao Técnico no portal em dia
  fixo (erros, propostas com backtest e custo, contagem rumo aos 50, taxa de aprovação). Inclui
  automaticamente as pendências aprovadas com ressalva, por gravidade (E4).
- **Erro grave fora da rotina** (v0.1.2 §10.2): registra e avisa no portal; pede a **autorização nº 1**
  para investigar e testar (autorizar · não autorizar · aguardar); depois, a **autorização nº 2** para
  publicar.
- **Exceção:** se uma publicação provocou reversão automática, investiga e testa sem a autorização nº 1;
  publicar de novo ainda exige o Técnico.

### 3.3 Proteção da medição (F5)

- O agente **não escreve** no gabarito, nos testes, nos portões, na sonda nem nas regras do projeto;
  mudança nesses itens é só por pessoa, em proposta separada.
- Parte do gabarito fica **oculta**. Proposta que melhora no conhecido e piora no oculto é **rejeitada**.
- O Auditor valida cada erro antes de contar; o autoaprimoramento nunca valida a própria contagem (F1-3).

### 3.4 Proposta para decisão

Toda proposta traz o **relatório técnico-econômico** da v0.1.2 §9: problema e causa, o que muda,
arquivos e agentes afetados, resultados antes × depois, testes, regressões, riscos, **custo atual e
futuro** (tokens, APIs, infraestrutura, manutenção, custo por análise), premissas, estratégia de
publicação e reversão, recomendação. Regressão crítica não é compensada por melhora média.

## 4. Testar, publicar e reverter

| Etapa | Regra | Decisões |
|---|---|---|
| **Ambiente** | Teste descartável por mudança, sem credencial de produção; dados inventados ou cópias anonimizadas | H8 |
| **Backtest** | Para mudança que afeta número: casos reais anonimizados (quando o contrato permitir) + dados inventados; gabarito sempre incluído; diagnósticos antigos são referência, não verdade | F4, v0.1.2 §9 |
| **Aprovação** | Técnico; se afeta número ou conclusão, Técnico **e** Sócio; quem propôs não aprova | E2 |
| **Publicação** | Aditiva e sem diferença de número no backtest → todos. Mexe em extração, cálculo, premissa ou banco → **sombra → 1–2 clientes → todos**, comparando resultados em cada passo | F2 |
| **Reversão** | **Chave liga/desliga por mudança**; banco em "acrescenta primeiro, remove depois"; teste de reversão = desligar a chave numa cópia e conferir que diagnósticos antigos não mudam. **Nenhuma publicação sem reversão comprovada** | F3, v0.1.2 §11 |
| **Operação** | Erro grave → desliga a chave e avisa no portal; a versão estável segue. Problema menor → alerta, sem reverter. Backup é só para desastre | F3, v0.1.2 §11 |

## 5. Governança do desenvolvimento (hoje)

Enquanto o sistema é construído pelo dono com o Claude (K3), valem as regras do `CLAUDE.md` da raiz:
uma fatia por commit, invariante medido não-vazio, portões no CI, revisão independente antes de fechar
e o PR como ponto de aprovação do dono. Essas regras são o embrião técnico do fluxo da seção 4.
