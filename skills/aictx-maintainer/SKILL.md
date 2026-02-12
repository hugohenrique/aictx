---
name: aictx-maintainer
description: Maintain and extend the aictx CLI (context runner) and its token-optimized flow. Use when updating aictx behavior, prompt/cleanup strategy, engine routing (codex/claude/gemini), templates in templates/, or shell modules in lib/ and bin/.
---

# Aictx Maintainer

## Overview

Maintain the aictx CLI and its token-optimized context flow with minimal regressions and predictable file growth.

## Project Map (read first)

- /Users/hugohenrique/workspace/aictx/bin/aictx: entrypoint that wires commands.
- /Users/hugohenrique/workspace/aictx/lib/: shell modules.
- /Users/hugohenrique/workspace/aictx/templates/: prompt/context/session templates used at init.
- /Users/hugohenrique/workspace/aictx/OPTIMIZATION.md: token strategy details and rationale.

Key modules:
- /Users/hugohenrique/workspace/aictx/lib/session_run.sh: `aictx run` flow, engine selection, session/transcript handling.
- /Users/hugohenrique/workspace/aictx/lib/prompt.sh: prompt construction + lazy loading logic.
- /Users/hugohenrique/workspace/aictx/lib/cleanup.sh: session/pending/transcript cleanup.
- /Users/hugohenrique/workspace/aictx/lib/engines/*.sh: per-engine run/finalize behavior.

## Core Flow (high level)

1. `aictx_run` bootstraps `.aictx/`, loads config, selects engine/model.
2. Session is reused or created in `.aictx/sessions/`.
3. Prompt file is built (paths vs inline) in `lib/prompt.sh`.
4. Engine runs with transcript captured and sanitized/compressed.
5. Finalize updates DIGEST/CONTEXT/DECISIONS/TODO and session summary.

## Token Strategy Constraints

- Paths mode is the default. It should only list files that must be read.
- Do not force reading optional files when the flow intends to skip them.
- Keep DIGEST <= 60 lines (bullets), CONTEXT <= 20 lines, DECISIONS append-only.
- If you change lazy-loading rules in `lib/prompt.sh`, update templates/PROMPT.md to match.

## When Changing Behavior

- Prefer small, reversible changes.
- Keep shell portability (macOS and Linux).
- Update templates if you introduce new files or rules.
- Avoid adding new persistent files unless needed for long-term memory or safety.

## Suggested Checks

- Run `bash -n` on touched shell files.
- Run `./bin/aictx status` after changes that affect initialization or paths.
- If prompt logic changes, compare generated prompt output for paths mode.
