# Contexto comum (leia antes de pesquisar)

O **Oria Digital** é uma plataforma brasileira de diagnóstico de reestruturação financeira e M&A,
operada por uma equipe pequena. O cliente (empresa em crise, consultoria, credor, fundo) envia
documentos; o sistema extrai as demonstrações, capta dados externos (fiscais, bancários, de risco e
de mercado), cruza tudo, roda agentes de IA que interpretam (nunca calculam), um humano aprova, e o
cliente recebe um Excel em fórmula com cada número ligado ao documento/página/fonte + PDF.
Stack atual: Postgres/Supabase, n8n, portal Next.js na Vercel, IA via API. Volume de referência:
**4 mandatos ativos por mês, cada um com ~8 empresas e ~6 pessoas (sócios/administradores)**.
Regras: dado de pessoa física só com autorização registrada (LGPD); preferência por processamento no
Brasil; o dado externo é guardado com fonte, data e custo por consulta.

## Etapas do processo (use estes códigos)
E01 Pré-mandato e prospecção · E02 Abertura do mandato e autorizações · E03 Recebimento de documentos
· E04 Extração e classificação de documentos · E05 Captação fiscal e contábil oficial · E06 Captação
bancária e de crédito · E07 Captação de risco (bureau, protestos, processos, certidões, sanções,
notícias, imóveis) · E08 Dados de mercado e benchmarks · E09 Cruzamento e score do dado externo · E10
Motor de cálculo e análises · E11 Orquestração dos agentes e IA · E12 Decisão humana e aprovação · E13
Entregáveis (Excel, PDF, apresentação) · E14 Monitoramento contínuo e alertas · E15 Autoaprimoramento
· E16 Plataforma, segurança e continuidade · E17 Medição e gestão do mandato

## O critério do dono (o mais importante)
Ele NÃO quer uma empresa que resolve várias coisas e da qual a Oria usaria só um pedaço. Só serve
fornecedor em que a Oria consiga usar **pelo menos 80% do que estaria pagando**.
Calcule assim, e mostre a conta:
- **% de uso = parte do escopo PAGO que a Oria usaria ÷ escopo pago total.** "Escopo pago" é o que
  entra no contrato/plano que teríamos de assinar, não o catálogo inteiro do site.
- Cobrança por consulta/página/token, sem franquia que obrigue a pagar módulos que não usaríamos →
  tende a ~100% (pagamos só o que consumimos). Diga isso explicitamente, e desconte franquia mínima
  que ficaria ociosa no volume de referência.
- Plano/assinatura/assento que empacota módulos → liste os módulos do plano, marque usa/não usa, e
  estime o % (ponderado por preço se souber; senão por contagem, e diga que é por contagem).
- Veredito: **Recomendado** (≥ 80%), **Condicional** (≥ 80% só sob uma condição — diga qual: plano
  específico, só API, volume…), **Rejeitado** (< 80%: explique o que sobraria sem uso).

## Regras de honestidade (inegociáveis)
- Nunca invente preço, cobertura ou cliente. Sem fonte, escreva "não publicado" / "a confirmar".
- Cada afirmação factual relevante leva a URL da fonte. Prefira o site do fornecedor e páginas de preço.
- Se uma pesquisa falhar, registre que falhou; não preencha por memória sem avisar
  (marque `"fonte":"memória — conferir"` quando usar conhecimento prévio sem URL).

## Saída (obrigatória)
Escreva um arquivo JSON (lista de objetos, UTF-8) no caminho indicado no seu pedido, com estes campos:
```
{"etapas":["E07"], "categoria":"...", "empresa":"...", "site":"https://...",
 "o_que_oferece":"lista completa dos produtos/módulos do escopo pago",
 "o_que_oria_usaria":"...", "o_que_sobraria":"...",
 "pct_uso_estimado":95, "conta_do_pct":"como chegou ao número",
 "modelo_cobranca":"por consulta / assinatura / ...", "preco_publicado":"R$ ... (data, fonte) ou 'não publicado'",
 "brasil_lgpd":"dado/processamento no Brasil? DPA?", "veredito":"Recomendado|Condicional|Rejeitado",
 "motivo":"1-2 frases", "riscos_a_confirmar":"...", "fontes":["https://..."]}
```
Avalie de 2 a 6 fornecedores por categoria, incluindo os rejeitados (o dono quer ver por que caíram).
Ao terminar, responda só com: caminho do arquivo, nº de fornecedores, e 1 linha por categoria com o
recomendado. Não cole o JSON na resposta.
