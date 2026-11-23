# Decisões do Oria Digital

**Fonte oficial das decisões de negócio e de produto:**
[`oria_digital_decisoes_e_pendencias_v0.1.4.html`](oria_digital_decisoes_e_pendencias_v0.1.4.html)
(abrir no navegador; autocontido).

- Seções 1–18: o registro v0.1.2, preservado sem alteração.
- **Seção 19**: as 88 decisões da entrevista de definição (18–19/11/2026), cada uma com a fala do dono;
  as revisões da v0.1.2 (19.12), as pendências (19.13), o que saiu do escopo (19.14) e os requisitos
  técnicos derivados (19.15).
- **Seção 20**: as decisões da Fase 4 (23/11/2026). Hoje, a **D6-1**: a classificação de documentos
  volta a N1 junto com a extração.
- Onde uma decisão revisa outra, as duas ficam registradas e o adendo diz qual vale.

O registro guarda **decisões**, não implementação. O que já está construído, e a evidência, está no
plano de execução ([`../06_execucao/PLANO_DE_EXECUCAO.md`](../06_execucao/PLANO_DE_EXECUCAO.md)).

## Como citar

Pelo código da decisão: `K6`, `B3b-1`, `N-C7a`, `D6-1`. Os demais documentos da pasta citam o código e
**não copiam** o texto da decisão. Em dúvida de interpretação, a fala completa da entrevista, pergunta
a pergunta, está em [`../99_historico/entrevista/03_rascunho_adendo_v0.1.3.md`](../99_historico/entrevista/03_rascunho_adendo_v0.1.3.md).

## Como registrar uma decisão nova ou uma mudança

1. Nunca editar a versão vigente. Uma mudança vira **nova versão** (v0.1.5, v0.1.6…), com um adendo no
   fim: código, data, fala do dono, decisão afetada e qual passa a valer.
2. A versão nova é gerada a partir da anterior pelo gerador da versão, como a v0.1.4 foi gerada da
   v0.1.3 por [`gerar_v014.py`](gerar_v014.py): copie-o para `gerar_v015.py`, troque o adendo e rode-o
   sobre a v0.1.4. Confira que todo o texto da versão anterior continua na nova (só o título e o
   número da versão mudam).
3. A versão anterior e o gerador dela vão para
   [`../99_historico/registro_de_decisoes/`](../99_historico/registro_de_decisoes/). Depois de mover,
   atualize o comando abaixo para o caminho novo do gerador e para a versão nova.
4. Atualize os documentos que citam a decisão afetada e os links para o registro. Para achá-los:

```bash
grep -rn "B3b-1" "Business Plan" --include=*.md
```

```bash
python3 -I "Business Plan/07_decisoes/gerar_v014.py" "Business Plan/99_historico/registro_de_decisoes/oria_digital_decisoes_e_pendencias_v0.1.3.html" /tmp/v014.html
```

## Versões

| Versão | Data | O que trouxe | Onde está |
|---|---|---|---|
| 0.1.0–0.1.1 | 18/11/2026 | Registro inicial e edição para distribuição | Dentro de todas as versões seguintes (seções 1–17) |
| 0.1.2 | 18/11/2026 | Pergunta sobre o escopo da v1, sem resposta | [`99_historico/registro_de_decisoes/`](../99_historico/registro_de_decisoes/) |
| 0.1.3 | 19/11/2026 | Entrevista de definição completa: 88 decisões | [`99_historico/registro_de_decisoes/`](../99_historico/registro_de_decisoes/) |
| **0.1.4** | 23/11/2026 | D6-1: classificação de documentos volta a N1 junto com a extração | **Esta pasta (vigente)** |
