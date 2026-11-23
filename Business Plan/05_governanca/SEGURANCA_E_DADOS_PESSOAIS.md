# Segurança, continuidade e dados pessoais

**Fonte oficial das decisões** de segurança, continuidade e LGPD. O detalhe técnico (onde cada dado
mora, quem lê o quê) é da especificação técnica
[`10_DADOS_RETENCAO_E_LGPD.md`](../../Arquitetura%20do%20Sistema/2%20Especificação/10_DADOS_RETENCAO_E_LGPD.md),
que **ainda marca os prazos como [A CONFIRMAR]** e precisa ser atualizada para a I2 (item do plano).
Nada aqui é parecer jurídico.

## 1. Isolamento e acesso

| Regra | Decisões | Hoje |
|---|---|---|
| Separação **por organização** no mesmo banco (RLS); banco dedicado para cliente regulado que exigir | H4 | RLS por **mandato** existe (`0216`); camada de organização **não existe** |
| Chaves de **mínimo privilégio** para o n8n e para os agentes; fim do acesso total | H2, H4 | O n8n usa a chave `service_role`, de acesso total (`N8N/README.md`, credencial do Storage) |
| **Teste automático de vazamento** entre organizações, que precisa reprovar | H4 | Existe teste entre membros e mandatos (`Supabase/test/acesso_por_caso.test.sql`); entre organizações, não |
| n8n: nenhum mandato real novo nele até a produção real; destino final no estudo | H2 | — |

## 2. Trilha de auditoria

- Trilha **à prova de adulteração**: cadeia de hashes (alterar quebra a cadeia e gera alerta) + cópia
  diária externa e imutável do último elo, **antes do primeiro cliente além da Partners** (H6).
- Hoje: trilha só de acréscimo em `evento_auditoria` (`0215`, `0224`); **sem** encadeamento de hash.
- A trilha não guarda dado pessoal (I2).

## 3. Continuidade (backup e recuperação)

| Momento | Regra | Decisões |
|---|---|---|
| **Até o piloto** | Cópia **diária automática, criptografada**, do banco e dos arquivos, **fora do Supabase**; perda máxima de 1 dia; **um teste de restauração antes do piloto** | H1-1, H7 |
| **Produção** | Plano pago com backup contínuo, região São Paulo, cópia separada dos arquivos; perda máxima de minutos; volta em até 4 h; teste de recuperação **trimestral** (banco + arquivos, tempo anotado) | H1, H7 |
| Sempre | O backup do provedor **não cobre os arquivos** (Storage) — a cópia dos arquivos é separada | Síntese §4 |

Hoje **não existe backup** fora do esquema (`Supabase/README.md` só documenta `pg_dump --schema-only`) e o
banco está no plano gratuito. O piloto com a Partners **conta como produção real** (H1-1).

## 4. Ambientes

Três ambientes: desenvolvimento, teste descartável por mudança, produção. Dado real só sai da produção
**anonimizado**; nenhuma credencial de produção fora dela (H8). Hoje existe o banco de teste do CI
(`Supabase/test/run.sh`) e a produção; não há ambiente de desenvolvimento separado nem anonimização.

## 5. IA e transferência internacional

- Contrato de dados e **cláusulas-padrão da ANPD** com cada provedor **antes do piloto** (D1, K4).
- Processamento no Brasil, UE e EUA; cliente pode exigir "só Brasil", com roteamento por cliente (D1).
  Na pesquisa da Fase 1, o único modelo com processamento no Brasil era o Gemini no Vertex
  (`southamerica-east1`) — conferir no estudo de infraestrutura.

## 6. Retenção em três camadas (I2)

| Camada | Prazo | Observação |
|---|---|---|
| Originais e extrações brutas | Apagados **6 meses após o fim do contrato** | — |
| Entregáveis e papéis de trabalho | **5 anos** (ajustável) | Sem dado pessoal desnecessário |
| Trilha de auditoria | Conforme a trilha | **Sem dado pessoal** |
| Sempre | **Bloqueio de expurgo** quando houver processo | — |
| Benchmarks | — | Só anonimizados (C7) |

Hoje **não existe rotina de expurgo**.

## 7. Antes do piloto (K4, I5)

1. **RIPD** (relatório de impacto à proteção de dados): parte técnica pelo Claude, parte jurídica
   validada por advogado (I5).
2. Contrato de dados com cada provedor de IA (D1).
3. Backup provisório e um teste de restauração (H1-1, H7).
4. n8n com mínimo privilégio (H2).
5. Extração de volta a N1 até medir (D6).
6. Proteção do repositório: o `.github/CODEOWNERS` diz que, sem a regra de proteção do `main`, a
   revisão não bloqueia o merge; a regra ligada **não foi conferida** (K4).

## 8. Pendentes de parecer jurídico

Custódia de certificado e procuração (C3), benchmarks com dados de vários clientes (C7), transferência
internacional (D1), backtest com casos reais (F4), retenção (I2) e o RIPD (I5). A lista viva está em
[`08_pendencias_e_riscos/`](../08_pendencias_e_riscos/PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md).
