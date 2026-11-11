---
id: p11-coordenada-so-onde-o-texto-e-confiavel
tipo: doutrina
toca:
  - N8N/build-workflow.mjs
  - N8N/lib/extract.mjs
  - N8N/lib/cobertura.mjs
  - Supabase/migrations/0270_a_linha_que_nao_sabia_de_que_linha_veio.sql
prova: N8N/test/*.test.mjs
---

**O que surpreende:** a P11 ("toda linha extraída cita a linha do texto de onde veio") NÃO
cobre o corpus inteiro, e é de propósito. Decisão do dono em 11/11/2026 (opção A).

**Por quê:** a P6/P6b manda como ARQUIVO (imagem) todo PDF cuja camada de texto foi reprovada
(números colados, camada corrompida, colunas sem posição, texto ralo). Foi isso que derrubou o
Krauspenhar de 303 contas descartadas para 0. Numerar essa camada e anexá-la ao lado da imagem
(o que o `4b242f2` fazia) devolvia ao modelo o texto que a P6b tirou dali (achado A1, revisão
independente). Desde o `3c2531c`, PDF com `leitura_pdf = 'ocr'` não recebe texto numerado: `ln`
fica null e `medicao_documento.texto_numerado_motivo = 'camada-reprovada:<motivo>'`.

**Medido nos books sintéticos (medir-custo-book, 11/11):** ficam sem coordenada 21 de 38 do
canastra, 11 de 14 do distress, 4 de 14 do vertentes, 6 de 7 do espelho. A coordenada existe
onde o texto é confiável: PDF na rota de texto e planilha.

**Opções recusadas, para não reabrir sem fato novo:**
- B, a IA numerar o que lê na imagem: a coordenada viria do próprio modelo e não seria
  conferível — é a "coordenada inventada" voltando por outro caminho.
- C, OCR próprio no n8n para os reprovados: daria coordenada a todos, mas é dependência nova e
  memória (o pod caiu com 2 GB no lote de 80 MB da AMO em 11/11; foi a 4 GB). Fatia própria se
  um dia for preciso.

**Consequência para a P12 (bijeção):** ela começa pelos documentos com `texto_numerado = true`.
Documento sem coordenada não é "sem buraco": é "não medível", e tem de aparecer assim (regra 7).
