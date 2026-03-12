<p align="center">
  <img src="assets/aictx-logo.png" alt="aictx logo" width="220" />
</p>

# aictx

`aictx` is a per-project AI context runner for **Codex CLI**, **Claude Code CLI**, and **Gemini CLI**.
It keeps project memory on disk, reuses it across sessions, and tries to keep prompts small enough to stay practical in day-to-day development.

The core idea is simple:
- keep durable project context in `.aictx/`
- make `aictx run` the default entry point
- reduce prompt bloat with paths-based context and deterministic cleanup
- keep the workflow readable instead of hiding state inside a single chat session

Prefer a practical day-to-day flow first? See [UX.md](UX.md).

## What problem it solves

When working with CLI coding agents, context usually degrades in one of two ways:
- important project knowledge gets lost between sessions
- prompts grow until they become noisy, expensive, or inconsistent

`aictx` addresses that by storing a small, explicit project memory on disk:
- `DIGEST.md` for compact operational memory
- `CONTEXT.md` for stable facts
- `DECISIONS.md` for append-only decisions
- `TODO.md` for actionable follow-up
- `sessions/` and transcripts for run history and finalize flow

The result is a workflow that stays local-first, inspectable, and cheap enough to use often.

## How it works

In normal use, you initialize once and keep coming back to `aictx run`.

```bash
aictx init
aictx run
```

From there, `aictx`:
- builds a minimal prompt from `.aictx/`
- prefers paths-based context by default
- auto-compacts context before runs
- captures transcripts and can finalize memory updates after the session
- lets you route to Codex, Claude, or Gemini without changing the project memory model

## Quick start

Install (script):

```bash
bash install.sh
```

Or from a release tag:

```bash
curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/install.sh | bash -s -- --version vX.Y.Z --repo <you>/<repo>
```

Install (manual):

```bash
git clone https://github.com/<you>/aictx ~/.aictx-tool
mkdir -p ~/.local/bin
ln -sf ~/.aictx-tool/bin/aictx ~/.local/bin/aictx
grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.zshrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Use in a repo:

```bash
aictx init
aictx run
```

Daily flow: keep using `aictx run` and let auto-compaction maintain context size.

## Why the workflow stays lightweight
- `aictx run` is the default flow.
- Context stays small automatically (deterministic compaction, no AI by default).
- Project memory stays on disk and readable (`.aictx/*`), instead of hidden state.
- Prompt stays minimal by default (`prompt_mode=paths`).

## Default behavior (recommended)
- `prompt_mode=paths`
- `auto_compact=true`
- `auto_compact_ai=false`

This gives predictable, low-cost behavior with no extra commands.

## Common commands

```bash
aictx run                      # main flow
aictx run --dry-run            # estimate prompt/tokens only
aictx run --engine claude      # force Claude
aictx run --engine gemini      # force Gemini
aictx run --intent review      # intent-based skill selection
aictx run --skills impl,tests  # explicit skills
aictx run --no-skill           # disable overlays for one run
aictx stats                    # inspect prompt/token metrics
aictx cleanup                  # manual maintenance (usually unnecessary)
```

## Configuration highlights
Auto-compaction runs on `aictx run` by default (deterministic, no AI). Main options in `.aictx/config.json`:
- `auto_compact`: enable/disable deterministic compaction on `run` (default `true`)
- `auto_compact_ai`: AI summarization during compaction (default `false`)
- `auto_cleanup`: legacy alias kept for backward compatibility
- `decision_keep_days`: archive decisions older than N days (default `30`)
- `transcript_keep_days`: archive transcripts older than N days (default `30`)
- `token_budget_est`: estimated token budget threshold (default `2500`)
- `warn_budget_pct`: warn threshold percentage of budget (default `80`)
- `digest_max_lines`: DIGEST warning threshold (default `60`)
- `context_max_lines`: CONTEXT warning threshold (default `20`)
- `decisions_max_chars`: DECISIONS size cap for cleanup + warning (default `5000`)
- `todo_max_chars`: TODO warning threshold (default `1200`)
- `skills.enabled`: enable/disable Skills v1 overlays (default `true`)
- `skills.auto_select`: infer skills by command/intent when none passed (default `true`)
- `skills.max_active`: maximum active skills per run (default `2`)
- `skills.intent_map`: intent -> skill ids map used by `--intent`
- Recommended map v2: `impl/review/tests/release/refactor/debug/finalize/compact` with `triage` as first pass for complex intents.

If you want the previous (token-heavy) behavior, set:
```json
{ "prompt_mode": "inline" }
```
in `.aictx/config.json`.

See [OPTIMIZATION.md](OPTIMIZATION.md) for deeper internals and tuning.

`aictx init` also creates a project skill at `.aictx/skills/<project>-aictx/SKILL.md` for repo-specific guidance.
`aictx init` also appends an `aictx` section to `AGENTS.md` (or creates it) so Codex app follows the same context rules.

`aictx review --engine claude --since main --paths src/` generates a read-only architecture/code-quality report saved under `.aictx/reviews/`.
`aictx swarm --impl codex --review claude --fix` runs an agent swarm pipeline (implementation + review + optional fix) and emits a report under `.aictx/swarm/`.

Add `--ns <name>` to any command (e.g., `aictx --ns payments run`) to isolate sessions/transcripts/pending under `.aictx/namespaces/<name>/`.

## Namespaces, fallbacks & agent modes

- **Namespaces**: pass `--ns <name>` before the command to keep sessions, transcripts, and pending jobs scoped to `.aictx/namespaces/<name>/`, while shared memory files (`DIGEST.md`, `CONTEXT.md`, etc.) remain global.
- **Fallback engines**: configure `fallback_engine`, `fallback_model`, and `fallback_on_quota` in `.aictx/config.json`. When a transcript contains 429/quota/rate-limit markers, `aictx run` reruns the request with the fallback engine/model and updates the pending metadata to keep finalize/watch in sync.
- **Review mode**: `aictx review` (read-only) asks the configured engine to evaluate architecture, code quality, tests, and risks, storing structured reports under `.aictx/reviews/` without touching repository files.
- **Swarm mode**: `aictx swarm` chains implementation + review passes (plus an optional fix pass) using the review prompts and saves the narrative report under `.aictx/swarm/`. Use `--fix` to generate remediation guidance based on the implementation and review outputs.

### Gemini CLI note
- `GEMINI.md` is treated as an engine-specific adapter file, not core project memory. `aictx` creates it on demand only when the Gemini engine is used.


### Model-based routing (level 1)
If you pass `--model`, `aictx` will infer which CLI to use when you didn't explicitly set `--engine`:
- Models containing `codex` -> Codex CLI
- `opus|sonnet|haiku` or `claude*` -> Claude CLI
- `gemini*` -> Gemini CLI

Examples:
```bash
aictx run --model gpt-5.1-codex-max   # uses Codex
aictx run --model sonnet              # uses Claude
aictx run --model gemini-2.0-flash    # uses Gemini
```

### Skills v1 (policy overlays)
- `aictx run --skill review`: activate one skill.
- `aictx run --skills impl,review`: activate a validated skill pair.
- `aictx run --intent tests`: resolve skills from `config.json` intent map.
- `aictx run --no-skill`: bypass all skills for the current run.
- Precedence: `--no-skill` > `--skills/--skill` > `--intent` > inferred default.
- Default inference: `run -> impl`, `review -> review`, `swarm -> impl,review`.
- Skill contracts live in `SKILL.json` + `OVERLAY.md`, overlays are capped to 40 lines.
- Suggested skills for higher signal:
  - `triage`, `debug-root-cause`, `test-strategy`, `review-critical`
  - `release-safety`, `memory-hygiene`, `token-budget-guard`


### Background finalize safety
- `aictx run` writes a pending job under `.aictx/pending/` **before** starting the session.
- A best-effort `trap` finalizes on normal exits.
- For crashes/terminal closes, run a watcher:

```bash
aictx watch
```

On macOS, you can run it as a LaunchAgent:

```bash
aictx install-launchd
```

## Context directory
`aictx` uses only `.aictx/` as the project context directory.
