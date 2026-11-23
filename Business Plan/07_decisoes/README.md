# Decisões do Oria Digital

**Fonte oficial das decisões de negócio e de produto:**
[`oria_digital_decisoes_e_pendencias_v0.1.3.html`](oria_digital_decisoes_e_pendencias_v0.1.3.html)
(abrir no navegador; autocontido).

- Seções 1–18: o registro v0.1.2, preservado sem alteração.
- **Seção 19**: as 88 decisões da entrevista de definição (18–19/11/2026), cada uma com a fala do dono;
  as revisões da v0.1.2 (19.12), as pendências (19.13), o que saiu do escopo (19.14) e os requisitos
  técnicos derivados (19.15).
- Onde uma decisão revisa outra, as duas ficam registradas e a tabela 19.12 diz qual vale.

O registro guarda **decisões**, não implementação. O que já está construído, e a evidência, está no
plano de execução (`06_execucao/PLANO_DE_EXECUCAO.md`).

## Como citar

Pelo código da decisão: `K6`, `B3b-1`, `N-C7a`. Os demais documentos da pasta citam o código e
**não copiam** o texto da decisão. Em dúvida de interpretação, a fala completa, pergunta a pergunta,
está em [`../99_historico/entrevista/03_rascunho_adendo_v0.1.3.md`](../99_historico/entrevista/03_rascunho_adendo_v0.1.3.md).

## Como registrar uma decisão nova ou uma mudança

1. Nunca editar a v0.1.3. Uma mudança vira **nova versão** (v0.1.4, v0.1.5…), com um adendo no fim:
   código, data, fala do dono, decisão afetada e qual passa a valer.
2. A versão nova é gerada a partir da anterior, como a v0.1.3 foi gerada da v0.1.2 por
   [`gerar_v013.py`](gerar_v013.py): copie o gerador para `gerar_v014.py`, troque o adendo e rode-o
   sobre a v0.1.3.
3. A versão anterior vai para [`../99_historico/registro_de_decisoes/`](../99_historico/registro_de_decisoes/).
4. Atualize os documentos que citam o código afetado. Para achá-los:

```bash
grep -rn "B3b-1" "Business Plan" --include=*.md
```

## Versões

| Versão | Data | O que trouxe | Onde está |
|---|---|---|---|
| 0.1.0–0.1.1 | 18/11/2026 | Registro inicial e edição para distribuição | Dentro da v0.1.2 (seções 1–17) |
| 0.1.2 | 18/11/2026 | Pergunta sobre o escopo da v1, sem resposta | [`99_historico/registro_de_decisoes/`](../99_historico/registro_de_decisoes/) |
| **0.1.3** | 19/11/2026 | Entrevista de definição completa: 88 decisões | **Esta pasta (vigente)** |
