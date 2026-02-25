# aictx UX Guide (fluxo natural)

Este guia e para usar o `aictx` com o menor atrito possivel.
Objetivo: **rodar com 1 comando no dia a dia**.

## Regra principal

Use:

```bash
aictx run
```

So isso.

O que acontece automaticamente:
- carrega contexto essencial
- compacta memoria de forma deterministica (sem IA)
- evita crescimento descontrolado de `DECISIONS.md`
- preserva historico em `.aictx/archive/`

## Fluxo diario recomendado

1. Rode `aictx run`
2. Trabalhe normalmente no CLI (Codex/Claude/Gemini)
3. Pare aqui

Nao precisa rodar `aictx cleanup` toda hora.
`cleanup` fica como comando manual de manutencao.

## Como ler os avisos

- `warning: token estimate ...`
  - Significa: contexto esta ficando caro.
  - Acao normal: continue usando `aictx run`; a compactacao automatica ja ajuda.

- `memory warning: DECISIONS.md has ...`
  - Significa: arquivo passou do alvo.
  - Acao normal: no proximo `aictx run`, compactacao deterministica roda sozinha.

## Quando usar comandos extras

Use somente quando precisar diagnostico:

```bash
aictx stats
```

Use manutencao manual (raro):

```bash
aictx cleanup
```

## Config minima para UX

Em `.aictx/config.json`:

```json
{
  "prompt_mode": "paths",
  "auto_compact": true,
  "auto_compact_ai": false
}
```

## Filosofia adotada

- Padrao: previsivel e barato (deterministico)
- IA: opcional, nunca obrigatoria para manter o fluxo
- Menos comandos, mais continuidade
