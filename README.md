# aictx (token-optimized)

Per-project persistent AI context runner that supports **Codex CLI**, **Claude Code CLI**, and **Gemini CLI**.

## Why token-optimized?
By default, `aictx run` uses `prompt_mode=paths`:
- The initial prompt is tiny (now 2 lines) and points the model to read local files.
- The model reads `.aictx/DIGEST.md` first (compact working memory).
- Detailed docs remain on disk (CONTEXT/DECISIONS/TODO/sessions) but are not inlined into the prompt.
- Transcripts are sanitized (strip ANSI/control noise, collapse blank lines) before finalize to avoid wasting tokens on terminal noise.

### Advanced Token Optimizations (Phase 1+2)
aictx implements aggressive token optimization achieving **40-60% reduction**:

- **Template minification**: Compressed prompts using semantic abbreviations
- **Lazy file loading**: Skips empty TODO.md, old DECISIONS.md, stale sessions
- **Context caching**: Hash-based caching for stable CONTEXT.md (24h validity)
- **Session cleanup**: Auto-archive old sessions, keep last 5 recent

**Typical savings: 400-850 tokens per run**

See [OPTIMIZATION.md](OPTIMIZATION.md) for detailed guide and best practices.

Use `aictx cleanup` to manually trigger cleanup and optimization.

Auto-cleanup runs on `aictx run` by default. Configurable in `.aictx/config.json`:
- `auto_cleanup`: enable/disable (default `true`)
- `decision_keep_days`: archive decisions older than N days (default `90`)
- `transcript_keep_days`: archive transcripts older than N days (default `30`)

If you want the previous (token-heavy) behavior, set:
```json
{ "prompt_mode": "inline" }
```
in `.aictx/config.json`.

## Install (macOS)

```bash
git clone https://github.com/<you>/aictx ~/.aictx-tool
mkdir -p ~/.local/bin
ln -sf ~/.aictx-tool/bin/aictx ~/.local/bin/aictx

grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.zshrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## Use (inside a project repo)

```bash
aictx init
aictx run                 # engine auto (prefers codex > claude > gemini if installed)
aictx run --engine claude  # choose Claude
aictx run --engine gemini  # choose Gemini
```

`aictx init` also creates a project skill at `.aictx/skills/<project>-aictx/SKILL.md` for repo-specific guidance.
`aictx init` also appends an `aictx` section to `AGENTS.md` (or creates it) so Codex app follows the same context rules.

### Gemini CLI notes
- `aictx init` creates a repo-root `GEMINI.md` if missing. Gemini CLI loads it automatically for persistent project instructions.


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
